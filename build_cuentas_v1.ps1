$ErrorActionPreference = "Stop"

# ===========================================================================
#  WORKFLOW: "Bot Cuentas JK"
#  Telegram + GPT-4o + Google Sheets
#  /mayor o /detal + datos de cuenta -> extrae con IA -> confirma -> sube al Sheet
#  Se crea INACTIVO. Activar manualmente desde n8n.
# ===========================================================================

# ID del Google Sheet. OJO: este ID se habia transcrito mal, confundiendo la "I"
# mayuscula con la "l" minuscula en 4 posiciones, y Google devolvia 404
# ("Requested entity was not found") al intentar escribir. Es el MISMO ID que usa
# el workflow "Tasas de Proveedores", que si funciona -- no cambiar sin comparar
# contra ese. Para verificarlo: no leerlo a ojo, copiarlo de la barra de direcciones.
$SHEET_ID = '1bkLLIh0i1ml9KOEl_QiCNIWlQVFErfjtPTnLNYfAp5s'

# La pestana se identifica por su GID (numero), NO por su nombre: si alguien le
# cambia el nombre a la pestana en el Sheet, el workflow sigue funcionando.
# GID 908170655 = pestana de Cuentas (la misma que lee el bot de WhatsApp).
$SHEET_GID = '908170655'

$CHAT_IDS    = @('627887509')
$CHAT_IDS_JS = "[" + (($CHAT_IDS | ForEach-Object { "'" + $_ + "'" }) -join ",") + "]"

$redisCred    = @{ redis     = @{ id = 'SKkvpS5A65SOcmJs'; name = 'Redis memoria para Cambios JK' } }
$openAiCred   = @{ openAiApi = @{ id = '44lRGIyEnSk1lMc5'; name = 'cambios jk para n8n' } }
# Credenciales REALES, ya creadas en n8n. Antes aqui habia un placeholder
# ('BOT-CUENTAS-JK-CRED') que al desplegar habria borrado la credencial buena.
$telegramCred = @{ telegramApi = @{ id = 'SvDJc9Nnwylt8TOz'; name = 'Telegram account' } }
$googleCred   = @{ googleApi   = @{ id = 'U7Rjn3kLCG7tpE3G'; name = 'Google Sheets Tasas JK proveedores' } }

# ===================== CODIGO: DETECTAR MENSAJE =====================
$detectarCode = @'
let texto = '', chatId = '';
try {
  const msg = $('Telegram Trigger').first().json.message || {};
  texto = String(msg.text || '').trim();
  chatId = String((msg.chat && msg.chat.id) || '');
} catch(e){}

const norm = s => String(s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]/g,'');
const t = norm(texto);
const ES_SI = ['si','sii','ok','oka','okey','dale','confirmo','confirmar','listo','ya','correcto','sipi'];
const ES_NO = ['no','nop','cancelar','cancela','anular','nel','negativo'];

const esRespCorta = ES_SI.indexOf(t) !== -1 || ES_NO.indexOf(t) !== -1;
const esMayor = /^\/mayor/i.test(texto);
const esDetal = /^\/detal/i.test(texto);
const esComando = esMayor || esDetal;
const tipo = esMayor ? 'MAYOR' : (esDetal ? 'DETAL' : '');
const textoCuenta = esComando ? texto.replace(/^\/(mayor|detal)\s*/i, '').trim() : texto;
const keyPendiente = 'cuentas:pendiente:' + chatId;

return [{ json: { chatId, texto, textoCuenta, tipo, esRespCorta, esComando, keyPendiente } }];
'@

# ===================== CODIGO: INTERPRETAR =====================
$interpretarCode = @'
const d = $('Detectar Mensaje').first().json;
const norm = s => String(s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]/g,'');
const t = norm(d.texto);
const ES_SI = ['si','sii','ok','oka','okey','dale','confirmo','confirmar','listo','ya','correcto','sipi'];

let pendiente = null;
try {
  const raw = $('Redis Leer Pendiente').first().json.pendienteRaw;
  if (raw) pendiente = typeof raw === 'string' ? JSON.parse(raw) : raw;
} catch(e){}

if (d.esRespCorta) {
  if (pendiente && pendiente.fila) {
    const esOk = ES_SI.indexOf(t) !== -1;
    return [{ json: { accion: esOk ? 'confirmar' : 'cancelar', chatId: d.chatId, pendiente, keyPendiente: d.keyPendiente } }];
  }
  return [{ json: { accion: 'sinPendiente', chatId: d.chatId, keyPendiente: d.keyPendiente } }];
}
if (d.esComando) {
  if (!d.textoCuenta) {
    return [{ json: { accion: 'ayuda', chatId: d.chatId, tipo: d.tipo } }];
  }
  return [{ json: { accion: 'nueva', chatId: d.chatId, textoCuenta: d.textoCuenta, tipo: d.tipo, keyPendiente: d.keyPendiente } }];
}
return [{ json: { accion: 'ignorar', chatId: d.chatId } }];
'@

# ===================== CODIGO: PREPARAR LLAMADA IA =====================
$promptIA = 'Eres un extractor de datos de cuentas bancarias para una empresa de remesas venezolana.
Te llega un mensaje con los datos de UNA cuenta. Devuelve SOLO este JSON, sin markdown y sin texto extra:
{"pais":"","metodo":"","notas":"","numeroCuenta":"","banco":"","identificacion":"","titular":"","extra":""}

Que va en cada campo:
- pais: nombre del pais en espanol.
- metodo: banco + tipo de cuenta. Ej: Bancolombia Ahorro, Pichincha Ahorro, Nequi, Zelle, PayPal.
- notas: banco + SOLO el primer nombre del titular. Ej: Bancolombia Enrique, Pichincha Dario.
- numeroCuenta: SOLO el numero de la cuenta, tal cual aparece, sin puntos ni espacios de adorno.
- banco: el banco y el tipo de cuenta como se escribe en el mensaje. Ej: Bancolombia ahorro, Pichincha ahorro.
- identificacion: la cedula, C.I., CC, DNI, RUC o pasaporte CON su etiqueta si la trae. Ej: C.I: 8536509, Cedula: 25760445, Pasaporte 5181234067. Si en el mensaje el documento viene como un numero suelto sin etiqueta, ponlo igual, solo el numero. Si no hay, cadena vacia.
- titular: nombre completo de la persona.
- extra: CUALQUIER otra linea del mensaje que no encaje en los campos de arriba, copiada TAL CUAL con sus saltos de linea. Ej: MOTIVO DE PAGO ES: ... , Codigo de Cuenta Interbancario: ... , Tipo de cuenta: ... . Si no sobra nada, cadena vacia.

REGLA CRITICA: no inventes, no corrijas y no acortes ningun numero. Copialos digito por digito.
No pongas el titulo CUENTA AUTORIZADA en ningun campo: ese lo agrega el sistema.

Para deducir el pais fijate en el banco, la moneda o la ciudad. Pistas de banco:
Bancolombia, Nequi, Daviplata, Davivienda = Colombia. Pichincha, Guayaquil, Produbanco, Pacifico, Bolivariano = Ecuador.
Banesco, Mercantil, Provincial, Banco de Venezuela, Pago Movil = Venezuela. BCP, Interbank, Scotiabank, Yape, Plin = Peru.
Nubank, Itau, Bradesco, Pix = Brasil. Mercado Pago, Santander Rio = Argentina. BBVA Mexico, Banorte, Spin = Mexico.
Por codigo de moneda: COP=Colombia, VES=Venezuela, BRL=Brasil, ARS=Argentina, PEN=Peru, MXN=Mexico, CLP=Chile,
DOP=Republica Dominicana, GTQ=Guatemala, BOB=Bolivia, PYG=Paraguay, UYU=Uruguay. USD puede ser Ecuador, Panama o EEUU:
decidelo por el banco (Pichincha/Guayaquil/Produbanco = Ecuador; Zelle = EEUU).

Si de verdad no puedes deducir el pais o el metodo, devuelve ese campo como cadena vacia. Nunca inventes.'

$prepLlamadaCode = @'
const d = $('Interpretar').first().json;
const promptSistema = '__PROMPT__';
return [{ json: { ...d, promptSistema } }];
'@
# El prompt se escribe arriba en varias lineas para poder leerlo, pero se inyecta
# dentro de una cadena JS de comillas simples: hay que escapar la barra invertida,
# la comilla y los saltos de linea, o el nodo queda con JavaScript invalido.
$promptEscapado = $promptIA.Replace('\', '\\').Replace("'", "\'").Replace("`r`n", '\n').Replace("`n", '\n')
if($promptEscapado.Contains("`n") -or $promptEscapado.Contains("`r")){ throw 'El prompt escapado todavia trae saltos de linea reales: romperia el JavaScript del nodo.' }
$prepLlamadaCode = $prepLlamadaCode.Replace('__PROMPT__', $promptEscapado)

# ===================== CODIGO: PREPARAR FILA =====================
$prepFilaCode = @'
let iaRaw = '';
try { iaRaw = String($('Parsear con GPT-4o').first().json.choices[0].message.content || ''); } catch(e){}
iaRaw = iaRaw.replace(/^```(?:json)?[\s]*/i,'').replace(/[\s]*```$/,'').trim();

let ia = {};
try { ia = JSON.parse(iaRaw); } catch(e){}

const d = $('Preparar Llamada IA').first().json;
const chatId = d.chatId || '';
const tipo = d.tipo || '';
const keyPendiente = d.keyPendiente || ('cuentas:pendiente:' + chatId);
const original = String(d.textoCuenta || '').trim();

const txt = v => String(v === undefined || v === null ? '' : v).trim();
const pais       = txt(ia.pais);
const metodo     = txt(ia.metodo);
const notas      = txt(ia.notas);
const disponible = 'SI';

if (!original || !pais || !metodo) {
  const falta = [];
  if (!pais)     falta.push('el pais');
  if (!metodo)   falta.push('el metodo/banco');
  if (!original) falta.push('los datos de la cuenta');
  return [{ json: {
    chatId, tipo, keyPendiente, error: true,
    resumen: String.fromCodePoint(9888) + ' No pude deducir ' + falta.join(' ni ') + '.\n\n'
      + 'Reenviame el mensaje agregando el banco, o escribelo asi:\n\n'
      + '/mayor\n*CUENTA AUTORIZADA COP*\n\n1) 55458142571\n*Bancolombia ahorro*\nC.I: 8536509\n*Enrique Rodriguez*'
  }}];
}

// Moneda del titulo: se saca del PAIS en codigo, no de la IA, para que nunca se
// cuele una moneda que no corresponde (ej. mandar Ecuador y que diga COP).
const MONEDAS = {
  colombia:'COP', venezuela:'VES', ecuador:'USD', peru:'PEN', brasil:'BRL',
  argentina:'ARS', mexico:'MXN', chile:'CLP', bolivia:'BOB', panama:'USD',
  uruguay:'UYU', paraguay:'PYG', guatemala:'GTQ', 'republica dominicana':'DOP',
  'costa rica':'CRC', nicaragua:'NIO', honduras:'HNL', cuba:'CUP',
  eeuu:'USD', 'estados unidos':'USD', espana:'EUR', europa:'EUR'
};
const sinTildes = s => s.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim();
const moneda = MONEDAS[sinTildes(pais)] || '';

// Se arma el texto en CODIGO (no lo formatea la IA) para que todas las filas
// queden exactamente iguales. La IA solo entrego las piezas sueltas.
const BANCO = String.fromCodePoint(127974);   // emoji del banco
const piezas = [];
piezas.push('*CUENTA AUTORIZADA' + (moneda ? ' ' + moneda : '') + '*');
piezas.push('');
piezas.push(BANCO + '1) ' + txt(ia.numeroCuenta));
if (txt(ia.banco))          piezas.push('*' + txt(ia.banco) + '*');
if (txt(ia.identificacion)) piezas.push(txt(ia.identificacion));
if (txt(ia.titular))        piezas.push('*' + txt(ia.titular) + '*');
if (txt(ia.extra))          { piezas.push(''); piezas.push(txt(ia.extra)); }
let datos = piezas.join('\n');

// ===== RED DE SEGURIDAD =====
// La IA esta reescribiendo numeros de cuenta y cedulas. Si al reordenar se le
// pierde o se le cambia algun numero de 4 digitos o mas, NO se guarda su version:
// se guarda el mensaje ORIGINAL tal cual y se avisa. Mas vale una fila desordenada
// que una fila con el numero de cuenta equivocado.
const numerosDe = s => (String(s).match(/\d{4,}/g) || []);
const enOriginal = numerosDe(original);
const enNuevo = numerosDe(datos);
const perdidos = enOriginal.filter(n => enNuevo.indexOf(n) === -1);

let aviso = '';
if (perdidos.length > 0) {
  datos = original;
  aviso = String.fromCodePoint(9888) + ' No pude reordenarla sin perder datos, asi que la guardo TAL CUAL me la mandaste.\n\n';
}

const lineas = [];
if (aviso) lineas.push(aviso.trim(), '');
lineas.push(
  String.fromCodePoint(128203) + ' Cuenta detectada:',
  '',
  String.fromCodePoint(127758) + ' Pais: ' + pais + (moneda ? ' (' + moneda + ')' : ''),
  String.fromCodePoint(127970) + ' Metodo: ' + metodo,
  String.fromCodePoint(9989) + ' Disponible: ' + disponible,
  String.fromCodePoint(128221) + ' Notas: ' + notas,
  String.fromCodePoint(128202) + ' Tipo: ' + tipo,
  '',
  String.fromCodePoint(128196) + ' Asi queda en la hoja:',
  '- - - - - - - - - - - - - - -',
  datos,
  '- - - - - - - - - - - - - - -',
  '',
  'La agrego a la hoja? Responde si o no.'
);
const resumen = lineas.join('\n');
const fila = { Pais: pais, Metodo: metodo, Disponible: disponible, Datos: datos, Notas: notas, Tipo: tipo };
const pendienteJson = JSON.stringify({ fila, tipo });

return [{ json: { chatId, resumen, fila, keyPendiente, pendienteJson, error: false, reordenada: perdidos.length === 0 } }];
'@

# ===================== CODIGO: PREPARAR PARA HOJA =====================
$prepHojaCode = @'
// Manda EXACTAMENTE las 6 columnas de la hoja y nada mas: el nodo de Sheets usa
// autoMapInputData, que casa los campos por nombre de columna. Antes aqui tambien
// iban chatId y keyPendiente, que no son columnas de la hoja.
// No hace falta pasarlos: los nodos de abajo (Redis Borrar, Texto OK) los leen
// directo de $('Interpretar'), no de este nodo.
// Todo se manda como texto y sin espacios de sobra, para que la hoja no reciba
// nulls ni "undefined".
const d = $('Interpretar').first().json;
const fila = (d.pendiente && d.pendiente.fila) ? d.pendiente.fila : {};
const txt = v => (v === undefined || v === null) ? '' : String(v).trim();
return [{ json: {
  Pais:       txt(fila.Pais),
  Metodo:     txt(fila.Metodo),
  Disponible: txt(fila.Disponible),
  Datos:      txt(fila.Datos),
  Notas:      txt(fila.Notas),
  Tipo:       txt(fila.Tipo)
} }];
'@

# ===================== CODIGO: TEXTO OK =====================
$textoOkCode = @'
const d = $('Interpretar').first().json;
const fila = (d.pendiente && d.pendiente.fila) ? d.pendiente.fila : {};
const pais   = fila.Pais   || '?';
const metodo = fila.Metodo || '?';
return [{ json: { chatId: d.chatId, texto: String.fromCodePoint(9989) + ' Cuenta guardada en la hoja.\n\n' + String.fromCodePoint(128204) + ' ' + pais + ' — ' + metodo } }];
'@

# ===================== NODOS =====================
$nodes = @(

  # 1. Telegram Trigger
  [ordered]@{
    parameters = @{ updates = @('message'); additionalFields = @{} }
    id = 'c1000000-0000-4000-9000-tgtrigger0001'; name = 'Telegram Trigger'; type = 'n8n-nodes-base.telegramTrigger'; typeVersion = 1.2; position = @(-400,300)
    credentials = $telegramCred
  },

  # 2. Chat Autorizado
  [ordered]@{
    parameters = @{
      conditions = @{
        options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }
        conditions = @( [ordered]@{
          id = 'chat-auth-1'
          leftValue = "={{ $CHAT_IDS_JS.indexOf(String(`$json.message.chat.id)) !== -1 }}"
          rightValue = $true
          operator = @{ type = 'boolean'; operation = 'equals' }
        })
        combinator = 'and'
      }
    }
    id = 'c2000000-0000-4000-9000-chatautorizado'; name = 'Chat Autorizado'; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(-200,300)
  },

  # 3. Detectar Mensaje
  [ordered]@{
    parameters = @{ jsCode = $detectarCode }
    id = 'c3000000-0000-4000-9000-detectarmsj01'; name = 'Detectar Mensaje'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(0,300)
  },

  # 4. Redis Leer Pendiente
  [ordered]@{
    parameters = @{ operation = 'get'; key = '={{ $json.keyPendiente }}'; propertyName = 'pendienteRaw'; keyType = 'string'; options = @{} }
    id = 'c4000000-0000-4000-9000-rgetpendcuent'; name = 'Redis Leer Pendiente'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(200,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = $redisCred
  },

  # 5. Interpretar
  [ordered]@{
    parameters = @{ jsCode = $interpretarCode }
    id = 'c5000000-0000-4000-9000-interpretarcue'; name = 'Interpretar'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(400,300)
  },

  # 6. Router
  [ordered]@{
    parameters = @{
      rules = @{ values = @(
        [ordered]@{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'r-conf';  leftValue = '={{ $json.accion }}'; rightValue = 'confirmar';    operator = @{ type = 'string'; operation = 'equals' } }); combinator = 'and' }; renameOutput = $true; outputKey = 'confirmar'    },
        [ordered]@{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'r-canc';  leftValue = '={{ $json.accion }}'; rightValue = 'cancelar';     operator = @{ type = 'string'; operation = 'equals' } }); combinator = 'and' }; renameOutput = $true; outputKey = 'cancelar'     },
        [ordered]@{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'r-nueva'; leftValue = '={{ $json.accion }}'; rightValue = 'nueva';        operator = @{ type = 'string'; operation = 'equals' } }); combinator = 'and' }; renameOutput = $true; outputKey = 'nueva'        },
        [ordered]@{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'r-sinp';  leftValue = '={{ $json.accion }}'; rightValue = 'sinPendiente'; operator = @{ type = 'string'; operation = 'equals' } }); combinator = 'and' }; renameOutput = $true; outputKey = 'sinPendiente' },
        [ordered]@{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'r-ayuda'; leftValue = '={{ $json.accion }}'; rightValue = 'ayuda';        operator = @{ type = 'string'; operation = 'equals' } }); combinator = 'and' }; renameOutput = $true; outputKey = 'ayuda'        }
      ) }
      options = @{}
    }
    id = 'c6000000-0000-4000-9000-routercuentas'; name = 'Router'; type = 'n8n-nodes-base.switch'; typeVersion = 3.2; position = @(600,300)
  },

  # === RAMA CONFIRMAR ===

  # 7. Preparar Para Hoja
  [ordered]@{
    parameters = @{ jsCode = $prepHojaCode }
    id = 'd1000000-0000-4000-9000-prepparahoja1'; name = 'Preparar Para Hoja'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(800,60)
  },

  # 8. Agregar a Hoja
  #    - La pestana va por GID, no por nombre (ver $SHEET_GID arriba).
  #    - authentication='serviceAccount' porque la credencial googleApi es de
  #      cuenta de servicio (la misma que usa "Tasas de Proveedores").
  #    - autoMapInputData casa los campos de entrada con las columnas por NOMBRE:
  #      por eso "Preparar Para Hoja" manda EXACTAMENTE las 6 columnas de la hoja
  #      (Pais, Metodo, Disponible, Datos, Notas, Tipo) y nada mas.
  [ordered]@{
    parameters = @{
      authentication = 'serviceAccount'
      operation = 'append'
      documentId = @{ __rl = $true; mode = 'id'; value = $SHEET_ID }
      sheetName  = @{ __rl = $true; mode = 'id'; value = $SHEET_GID }
      columns    = @{ mappingMode = 'autoMapInputData'; value = @{}; matchingColumns = @(); schema = @() }
      options    = @{}
    }
    id = 'd2000000-0000-4000-9000-agregarahoja01'; name = 'Agregar a Hoja'; type = 'n8n-nodes-base.googleSheets'; typeVersion = 4.5; position = @(1000,60)
    credentials = $googleCred
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 2000
  },

  # 9. Redis Borrar Pendiente (confirmar)
  [ordered]@{
    parameters = @{ operation = 'delete'; key = "={{ `$('Interpretar').first().json.keyPendiente }}" }
    id = 'd3000000-0000-4000-9000-rborrarpend001'; name = 'Redis Borrar Pendiente'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1200,60)
    onError = 'continueRegularOutput'
    credentials = $redisCred
  },

  # 10. Texto OK
  [ordered]@{
    parameters = @{ jsCode = $textoOkCode }
    id = 'd4000000-0000-4000-9000-textook000001'; name = 'Texto OK'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1400,60)
  },

  # 11. Avisar OK
  [ordered]@{
    parameters = @{ chatId = '={{ $json.chatId }}'; text = '={{ $json.texto }}'; additionalFields = @{ append_attribution = $false } }
    id = 'd5000000-0000-4000-9000-avisarok00001'; name = 'Avisar OK'; type = 'n8n-nodes-base.telegram'; typeVersion = 1.2; position = @(1600,60)
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 2000
    credentials = $telegramCred
  },

  # === RAMA CANCELAR ===

  # 12. Redis Borrar (Cancelar)
  [ordered]@{
    parameters = @{ operation = 'delete'; key = '={{ $json.keyPendiente }}' }
    id = 'e1000000-0000-4000-9000-rborrarcncel1'; name = 'Redis Borrar (Cancelar)'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(800,180)
    onError = 'continueRegularOutput'
    credentials = $redisCred
  },

  # 13. Avisar Cancelado
  [ordered]@{
    parameters = @{ chatId = '={{ $json.chatId }}'; text = 'Cancelado. No se guardo nada.'; additionalFields = @{ append_attribution = $false } }
    id = 'e2000000-0000-4000-9000-avisarcncel01'; name = 'Avisar Cancelado'; type = 'n8n-nodes-base.telegram'; typeVersion = 1.2; position = @(1000,180)
    credentials = $telegramCred
  },

  # === RAMA SIN PENDIENTE ===

  # 14. Avisar Sin Pendiente
  [ordered]@{
    parameters = @{ chatId = '={{ $json.chatId }}'; text = "No tengo ninguna cuenta esperando confirmacion.`n`nUsame con /mayor o /detal seguido de los datos."; additionalFields = @{ append_attribution = $false } }
    id = 'f1000000-0000-4000-9000-avisarsinpend'; name = 'Avisar Sin Pendiente'; type = 'n8n-nodes-base.telegram'; typeVersion = 1.2; position = @(800,300)
    credentials = $telegramCred
  },

  # === RAMA NUEVA CUENTA ===

  # 15. Preparar Llamada IA
  [ordered]@{
    parameters = @{ jsCode = $prepLlamadaCode }
    id = 'g1000000-0000-4000-9000-prepllmadaia1'; name = 'Preparar Llamada IA'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(800,440)
  },

  # 16. Parsear con GPT-4o
  [ordered]@{
    parameters = [ordered]@{
      method               = 'POST'
      url                  = 'https://api.openai.com/v1/chat/completions'
      authentication       = 'predefinedCredentialType'
      nodeCredentialType   = 'openAiApi'
      sendBody             = $true
      specifyBody          = 'json'
      jsonBody             = "={{ JSON.stringify({ model: 'gpt-4o', temperature: 0, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: `$json.promptSistema }, { role: 'user', content: `$json.textoCuenta }] }) }}"
      options              = @{}
    }
    id = 'g2000000-0000-4000-9000-parsearconiai'; name = 'Parsear con GPT-4o'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1000,440)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 2000; alwaysOutputData = $true
    credentials = $openAiCred
  },

  # 17. Preparar Fila
  [ordered]@{
    parameters = @{ jsCode = $prepFilaCode }
    id = 'g3000000-0000-4000-9000-prepararfila1'; name = 'Preparar Fila'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1200,440)
  },

  # 18. Extraccion OK
  [ordered]@{
    parameters = @{
      conditions = @{
        options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }
        conditions = @( [ordered]@{ id = 'extr-ok-1'; leftValue = '={{ $json.error }}'; rightValue = $false; operator = @{ type = 'boolean'; operation = 'equals' } })
        combinator = 'and'
      }
    }
    id = 'g4000000-0000-4000-9000-extraccionok1'; name = 'Extraccion OK'; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(1400,440)
  },

  # 19. Redis Guardar Pendiente
  [ordered]@{
    parameters = @{ operation = 'set'; key = '={{ $json.keyPendiente }}'; value = '={{ $json.pendienteJson }}'; keyType = 'string'; options = @{ expire = $true; ttl = 3600 } }
    id = 'g5000000-0000-4000-9000-rguardarpend1'; name = 'Redis Guardar Pendiente'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1600,380)
    credentials = $redisCred
  },

  # 20. Pedir Confirmacion
  [ordered]@{
    # Sin parse_mode a proposito: la columna Datos va tal cual y trae asteriscos,
    # que en Markdown romperian el envio. Asi Kelvin ve exacto lo que se guardara.
    parameters = @{ chatId = '={{ $json.chatId }}'; text = '={{ $json.resumen }}'; additionalFields = @{ append_attribution = $false } }
    id = 'g6000000-0000-4000-9000-pedirconfirm1'; name = 'Pedir Confirmacion'; type = 'n8n-nodes-base.telegram'; typeVersion = 1.2; position = @(1800,380)
    credentials = $telegramCred
  },

  # 21. Avisar Error IA
  [ordered]@{
    parameters = @{ chatId = '={{ $json.chatId }}'; text = '={{ $json.resumen }}'; additionalFields = @{ append_attribution = $false } }
    id = 'g7000000-0000-4000-9000-avisarerror01'; name = 'Avisar Error IA'; type = 'n8n-nodes-base.telegram'; typeVersion = 1.2; position = @(1600,540)
    credentials = $telegramCred
  },

  # === RAMA AYUDA ===

  # 22. Avisar Ayuda
  [ordered]@{
    parameters = @{
      chatId = '={{ $json.chatId }}'
      text   = "Usa /mayor o /detal seguido de los datos de la cuenta. Ejemplo:`n`n/mayor`n*CUENTA AUTORIZADA COP*`n`n1) 55458142571`n*Bancolombia ahorro*`nC.I: 8536509`n*Enrique Rodriguez*"
      additionalFields = @{ append_attribution = $false; parse_mode = 'Markdown' }
    }
    id = 'h1000000-0000-4000-9000-avisarayuda01'; name = 'Avisar Ayuda'; type = 'n8n-nodes-base.telegram'; typeVersion = 1.2; position = @(800,580)
    credentials = $telegramCred
  }
)

# ===================== CONEXIONES =====================
$connections = [ordered]@{
  'Telegram Trigger'       = @{ main = @( ,@( @{ node='Chat Autorizado';       type='main'; index=0 } ) ) }
  'Chat Autorizado'        = @{ main = @( ,@( @{ node='Detectar Mensaje';      type='main'; index=0 } ) ) }
  'Detectar Mensaje'       = @{ main = @( ,@( @{ node='Redis Leer Pendiente';  type='main'; index=0 } ) ) }
  'Redis Leer Pendiente'   = @{ main = @( ,@( @{ node='Interpretar';           type='main'; index=0 } ) ) }
  'Interpretar'            = @{ main = @( ,@( @{ node='Router';                type='main'; index=0 } ) ) }

  'Router' = @{ main = (
    @( ,@( @{ node='Preparar Para Hoja';     type='main'; index=0 } ) ) +   # 0: confirmar
    @( ,@( @{ node='Redis Borrar (Cancelar)'; type='main'; index=0 } ) ) +  # 1: cancelar
    @( ,@( @{ node='Preparar Llamada IA';    type='main'; index=0 } ) ) +   # 2: nueva
    @( ,@( @{ node='Avisar Sin Pendiente';   type='main'; index=0 } ) ) +   # 3: sinPendiente
    @( ,@( @{ node='Avisar Ayuda';           type='main'; index=0 } ) )     # 4: ayuda
  ) }

  # Rama confirmar
  'Preparar Para Hoja'      = @{ main = @( ,@( @{ node='Agregar a Hoja';          type='main'; index=0 } ) ) }
  'Agregar a Hoja'          = @{ main = @( ,@( @{ node='Redis Borrar Pendiente';   type='main'; index=0 } ) ) }
  'Redis Borrar Pendiente'  = @{ main = @( ,@( @{ node='Texto OK';                type='main'; index=0 } ) ) }
  'Texto OK'                = @{ main = @( ,@( @{ node='Avisar OK';               type='main'; index=0 } ) ) }

  # Rama cancelar
  'Redis Borrar (Cancelar)' = @{ main = @( ,@( @{ node='Avisar Cancelado';        type='main'; index=0 } ) ) }

  # Rama nueva
  'Preparar Llamada IA'     = @{ main = @( ,@( @{ node='Parsear con GPT-4o';      type='main'; index=0 } ) ) }
  'Parsear con GPT-4o'      = @{ main = @( ,@( @{ node='Preparar Fila';           type='main'; index=0 } ) ) }
  'Preparar Fila'           = @{ main = @( ,@( @{ node='Extraccion OK';           type='main'; index=0 } ) ) }
  'Extraccion OK' = @{ main = (
    @( ,@( @{ node='Redis Guardar Pendiente'; type='main'; index=0 } ) ) +  # true
    @( ,@( @{ node='Avisar Error IA';         type='main'; index=0 } ) )    # false
  ) }
  'Redis Guardar Pendiente' = @{ main = @( ,@( @{ node='Pedir Confirmacion'; type='main'; index=0 } ) ) }
}

# ===================== GENERAR JSON =====================
$body = [ordered]@{
  name        = 'Bot Cuentas JK'
  nodes       = $nodes
  connections = $connections
  settings    = @{ executionOrder = 'v1' }
}

$jsonOut = $body | ConvertTo-Json -Depth 40
$outputPath = "C:\Users\USER\Documents\APP PARA CAMBIOS JK CONVERSOR\workflow_cuentas_v1.json"
$jsonOut | Out-File -FilePath $outputPath -Encoding utf8

Write-Output ("=== Bot Cuentas JK - JSON generado ===")
Write-Output ("Nodos: " + $nodes.Count)
Write-Output ("Archivo: " + $outputPath)
Write-Output ("")
Write-Output ("PASOS SIGUIENTES:")
Write-Output ("1. Desplegar:  .scriptsdesplegar_cuentas.ps1")
Write-Output ("2. Revisar el workflow en n8n y activarlo A MANO.")
Write-Output ("")
Write-Output ("Las credenciales (Telegram, Redis, OpenAI, Google) ya existen en n8n y")
Write-Output ("este script apunta a sus IDs. NUNCA escribir un token aqui: este archivo")
Write-Output ("va a un repositorio PUBLICO.")
