# ============================================================================
#  WORKFLOW "Bot JK - Debounce y Admin"  (Cambios JK - Fase 5)
# ============================================================================
#  Sub-workflow independiente para procesar Media, acumular mensajes (Wait),
#  detectar comandos admin (modo mayor/detal) y delegar a Atencion e IA.
#
#  Genera workflow_debounce_admin.json. Se sube con scripts\desplegar_debounce_admin.ps1.
#  IMPORTANTE: guardar SIEMPRE con BOM UTF-8 (PowerShell 5.1 lo necesita).
# ============================================================================
$ErrorActionPreference = 'Stop'
$nodes = @(
  ,[ordered]@{
    parameters = [ordered]@{
      content = @'
## Bot JK - Debounce y Admin

Sub-workflow que recibe el item de `Es mensaje de cliente?` ({ body, accionPausa, nombreCargado, tarifaCargada }),
ejecuta `Bot JK - Procesar Media` síncrono, acumula mensajes en Redis con espera 30s/100s,
procesa comandos admin (modo mayor / modo detal) y delega la respuesta a `Bot JK - Atencion al Cliente e IA` sin esperarlo.

Se invoca fire-and-forget (`waitForSubWorkflow: false`) para que el Wait de 100s sea 100% seguro en n8n.
Se mantiene inactivo hasta que Kelvin lo publique manualmente en n8n.
'@
      height = 240
      width = 560
      color = 4
    }
    id = 'deb55000-0000-4a00-9a00-debnota00001'
    name = 'Nota'
    type = 'n8n-nodes-base.stickyNote'
    typeVersion = 1
    position = @(
      ,-320
      ,-240
    )
  }
  ,[ordered]@{
    parameters = [ordered]@{
      inputSource = 'passthrough'
    }
    id = 'deb55000-0001-4a00-9a00-debtrig00001'
    name = 'Cuando lo Llama el Bot'
    type = 'n8n-nodes-base.executeWorkflowTrigger'
    typeVersion = 1.1
    position = @(
      ,-320
      ,120
    )
  }
  ,[ordered]@{
    parameters = [ordered]@{
      workflowId = [ordered]@{
        mode = 'id'
        __rl = $true
        value = 'UMQqyE6H4HVrIDoy'
      }
      workflowInputs = [ordered]@{
        value = @{}
        mappingMode = 'defineBelow'
        schema = @()
        attemptToConvertTypes = $false
        matchingColumns = @()
        convertFieldsToString = $true
      }
      source = 'database'
      mode = 'once'
      options = [ordered]@{
        waitForSubWorkflow = $true
      }
    }
    id = 'e1f2a3b4-0005-4c00-9c00-procmedia001'
    name = 'Ejecutar Media'
    type = 'n8n-nodes-base.executeWorkflow'
    typeVersion = 1.3
    position = @(
      ,-80
      ,120
    )
    onError = 'continueRegularOutput'
  }
  ,[ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Prepara los datos para el debounce con Redis. El texto ya viene unificado (de texto directo o de audio transcrito).
let jid='', texto='';
try { jid = $('Cuando lo Llama el Bot').first().json.body.data.key.remoteJid || ''; } catch(e){}
try { texto = $json.texto || ''; } catch(e){}
const miTs = String(Date.now()) + '-' + Math.random().toString(36).slice(2,8);

// Si lo que llego es un COMPROBANTE, se espera mas antes de contestar. La gente manda
// primero la foto del pago y tarda en escribir la cuenta destino; si se contesta a los 30
// segundos, el comprobante y la cuenta caen en ejecuciones distintas y el bot nunca ve las
// dos cosas juntas. Paso el 19/11: la clienta tardo 36 segundos.
const esComprobante = texto.indexOf('COMPROBANTE de pago') !== -1;

// De noche (fuera de horario) NO se manda el sticker de "verificando su deposito": nadie lo esta
// verificando. Cuando tenga la captura y la cuenta, el bot le contesta "Recibido, se procesa...".
// ===== HORARIO DE ATENCION (hora de Ecuador: UTC-5, sin horario de verano) =====
// Lunes a sabado y domingo, como el workflow de apertura y cierre. Se cambia en build_v12.ps1
// ($HORA_ABRE_SEMANA y compania), nunca aqui.
const HORARIO_JK = { semana: [9, 18], domingo: [10, 14] };
function horarioDe(ms){
  const ec = new Date(ms - 5 * 3600000);
  const dow = ec.getUTCDay();
  const horas = ec.getUTCHours() + ec.getUTCMinutes() / 60;
  const rango = (dow === 0) ? HORARIO_JK.domingo : HORARIO_JK.semana;
  const abierto = horas >= rango[0] && horas < rango[1];
  const medianoche = ms - (((ec.getUTCHours() * 60 + ec.getUTCMinutes()) * 60 + ec.getUTCSeconds()) * 1000 + ec.getUTCMilliseconds());
  const esHoy = horas < rango[0];                      // de madrugada abre hoy; si ya cerro, manana
  const dowAbre = esHoy ? dow : (dow + 1) % 7;
  const horaAbre = (dowAbre === 0) ? HORARIO_JK.domingo[0] : HORARIO_JK.semana[0];
  const proximaApertura = medianoche + (esHoy ? 0 : 86400000) + horaAbre * 3600000;
  const DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
  const conDia = (dowAbre === 0 || (!esHoy && dowAbre === 1)) ? ' ' + DIAS[dowAbre] : '';
  const hora = (horaAbre % 12 || 12) + ':00 ' + (horaAbre >= 12 ? 'pm' : 'am');
  return { abierto, proximaApertura, cuandoAbre: (esHoy ? 'hoy' : 'mañana') + conDia + ' a partir de las ' + hora };
}
const stickerVerificando = esComprobante && horarioDe(Date.now()).abierto;

// Los datos de una CUENTA destino tambien esperan lo mismo (cuenta + foto). Solo cuentan los datos
// FIRMES: un numero largo (cuenta o telefono de pago movil, aunque venga con espacios o guiones),
// un correo (Zelle, PayPal) o una direccion de billetera. Una pregunta como "me pasas la cuenta?"
// o "tienes cuenta en Banesco?" NO espera: se contesta en 30 s como siempre.
// Lo que el cliente cita se ignora (puede ser nuestra propia cuenta).
function datosFirmes(t){
  const sinCita = String(t || '').replace(/\[el cliente respondio citando[^\]]*\]/gi, '');
  const bajo = ' ' + sinCita.toLowerCase() + ' ';
  if (/[0-9]{10,}/.test(bajo.replace(/([0-9])[ .-](?=[0-9])/g, '$1'))) return true;
  if (/[^ @]+@[^ @]+\.[a-z]{2,}/.test(bajo)) return true;
  return /(^|\s)[A-Za-z0-9]{26,}(\s|$)/.test(sinCita);
}
const esperaLarga = esComprobante || datosFirmes(texto);
const espera = esperaLarga ? 100 : 30;

// El id de ESTE mensaje viaja con el texto. Hace falta despues para poder CITAR el mensaje
// en el que el cliente escribio sus datos bancarios cuando se le mande el comprobante.
let idMensaje = '';
try { idMensaje = $('Cuando lo Llama el Bot').first().json.body.data.key.id || ''; } catch(e){}

return [{ json: { jid, texto: texto || '', miTs, esComprobante, stickerVerificando, espera, idMensaje,
                  keyBuf: 'buf:'+jid, keyTok: 'tok:'+jid } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      ,160
      ,120
    )
    id = 'c1a2b3c4-1111-4a11-9111-prep00000001'
    name = 'Prep Debounce'
  }
  ,[ordered]@{
    parameters = [ordered]@{
      conditions = [ordered]@{
        boolean = @(
          ,[ordered]@{
            value2 = '={{true}}'
            value1 = '={{ $json.stickerVerificando }}'
          }
        )
      }
    }
    id = 'd0e1f2a3-0000-4b00-9000-escomprob0001'
    name = 'Llego un Comprobante?'
    type = 'n8n-nodes-base.if'
    typeVersion = 1
    position = @(
      ,400
      ,-60
    )
  }
  ,[ordered]@{
    parameters = [ordered]@{
      url = 'http://evolution-api:8080/message/sendSticker/BOT%20JK%20Kelvin'
      options = @{}
      specifyBody = 'json'
      method = 'POST'
      headerParameters = [ordered]@{
        parameters = @(
          ,[ordered]@{
            value = 'application/json'
            name = 'Content-Type'
          }
        )
      }
      sendBody = $true
      sendHeaders = $true
      jsonBody = '={ "number": "{{ $("Prep Debounce").first().json.jid }}", "sticker": "https://grupojk-cambios.github.io/grupojk-conversor/logos/sticker-verificando-su-deposito.webp" }'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'd0e1f2a3-0000-4b00-9000-stickerverif1'
    name = 'Sticker Verificando'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      ,640
      ,-60
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 2
    waitBetweenTries = 1000
    alwaysOutputData = $true
    credentials = [ordered]@{
      httpHeaderAuth = [ordered]@{
        id = '70cMtifwmTdIqY1l'
        name = 'Evolution apikey Kelvin 0380'
      }
    }
  }
  ,[ordered]@{
    parameters = [ordered]@{
      list = '={{ $(''Prep Debounce'').item.json.keyBuf }}'
      operation = 'push'
      tail = $true
      messageData = '={{ JSON.stringify({ id: $(''Prep Debounce'').item.json.idMensaje, texto: $(''Prep Debounce'').item.json.texto }) }}'
    }
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      ,400
      ,120
    )
    id = 'c2a2b3c4-2222-4a22-9222-rpush0000001'
    name = 'Redis Guardar Msg'
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  }
  ,[ordered]@{
    parameters = [ordered]@{
      value = '={{ $(''Prep Debounce'').item.json.miTs }}'
      expire = $true
      ttl = 120
      keyType = 'string'
      key = '={{ $(''Prep Debounce'').item.json.keyTok }}'
      operation = 'set'
    }
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      ,640
      ,120
    )
    id = 'c3a2b3c4-3333-4a33-9333-rset00000001'
    name = 'Redis Marcar Token'
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  }
  ,[ordered]@{
    parameters = [ordered]@{
      unit = 'seconds'
      amount = '={{ $(''Prep Debounce'').first().json.espera }}'
    }
    type = 'n8n-nodes-base.wait'
    typeVersion = 1.1
    position = @(
      ,880
      ,120
    )
    id = 'd2b3c4d5-4444-4a44-9444-wait00000001'
    name = 'Esperar 30s'
    webhookId = 'e7c1a2b3-5555-4a55-9555-waithook0001'
  }
  ,[ordered]@{
    parameters = [ordered]@{
      operation = 'get'
      key = '={{ $(''Prep Debounce'').item.json.keyTok }}'
      keyType = 'string'
      propertyName = 'tokenActual'
      options = @{}
    }
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      ,1120
      ,120
    )
    id = 'c4a2b3c4-6666-4a66-9666-rget00000001'
    name = 'Redis Leer Token'
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  }
  ,[ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Tras esperar 30s: solo continua si mi token sigue siendo el ultimo en Redis.
const miTs = $('Prep Debounce').item.json.miTs;
let actual = $json.tokenActual;
if (actual === undefined || actual === null) { try { actual = $('Redis Leer Token').item.json.tokenActual; } catch(e){} }
if (String(actual) !== String(miTs)) {
  return []; // llego un mensaje mas nuevo: esta ejecucion NO responde
}
return [{ json: { jid: $('Prep Debounce').item.json.jid } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      ,1360
      ,120
    )
    id = 'f3c4d5e6-7777-4a77-9777-filtrar00001'
    name = 'Filtrar Ultimo'
  }
  ,[ordered]@{
    parameters = [ordered]@{
      operation = 'get'
      key = '={{ $(''Prep Debounce'').item.json.keyBuf }}'
      keyType = 'list'
      propertyName = 'mensajes'
      options = @{}
    }
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      ,1600
      ,120
    )
    id = 'c5a2b3c4-8888-4a88-9888-rgetlist0001'
    name = 'Redis Leer Mensajes'
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  }
  ,[ordered]@{
    parameters = [ordered]@{
      key = '={{ $(''Prep Debounce'').item.json.keyBuf }}'
      operation = 'delete'
    }
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      ,1840
      ,120
    )
    id = 'c6a2b3c4-9999-4a99-9999-rdel00000001'
    name = 'Redis Borrar Buffer'
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  }
  ,[ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Junta todos los mensajes leidos de Redis en un solo texto, y conserva el id de cada uno.
// Los ids hacen falta para citar despues el mensaje donde el cliente puso su cuenta.
let arr = [];
try { arr = $('Redis Leer Mensajes').item.json.mensajes; } catch(e){}
if (!Array.isArray(arr)) arr = (arr === undefined || arr === null) ? [] : [arr];

// Cada entrada es {"id":"...","texto":"..."}. Se acepta tambien el formato VIEJO (texto
// pelado): al desplegar puede haber mensajes guardados antes del cambio y no se pueden
// perder.
const mensajes = [];
for (const x of arr){
  if (x === undefined || x === null) continue;
  if (typeof x === 'object'){ mensajes.push({ id: x.id || '', texto: String(x.texto || '') }); continue; }
  const cruda = String(x);
  let obj = null;
  try { obj = JSON.parse(cruda); } catch(e){}
  if (obj && typeof obj === 'object' && obj.texto !== undefined) mensajes.push({ id: obj.id || '', texto: String(obj.texto) });
  else mensajes.push({ id: '', texto: cruda });
}

const combinado = mensajes.map(m => m.texto).join('\n\n').trim() || '(sin texto)';
return [{ json: { mensajeCombinado: combinado, mensajes } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      ,2080
      ,120
    )
    id = 'a7b8c9d0-aaaa-4aaa-9aaa-combinar0001'
    name = 'Combinar'
  }
  ,[ordered]@{
    parameters = [ordered]@{
      tableId = 'perfiles_detal'
      limit = 20
      filterString = 'role=eq.admin'
      resource = 'row'
      filterType = 'string'
      operation = 'getAll'
      returnAll = $false
    }
    id = 'f3a4b5c6-1234-4d99-9e11-supaadmin0001'
    name = 'Consultar Admins'
    type = 'n8n-nodes-base.supabase'
    typeVersion = 1
    position = @(
      ,2320
      ,120
    )
    onError = 'continueRegularOutput'
    alwaysOutputData = $true
    credentials = [ordered]@{
      supabaseApi = [ordered]@{
        id = 'JCvvp9JkZ15OpA9E'
        name = 'Supabase Cambios JK'
      }
    }
  }
  ,[ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Detecta si el remitente es ADMIN (Supabase perfiles_detal role=admin, nodo "Consultar Admins")
// y si escribio un comando de modo ("modo mayor" / "modo detal"). Un cliente normal JAMAS activa esto.
let jid = '';
try { jid = $('Cuando lo Llama el Bot').first().json.body.data.key.remoteJid || ''; } catch(e){}
const senderDigits = String(jid).replace(/\D/g,'');
// SOLO los numeros con role='admin' en Supabase pueden cambiar la tarifa. Si Supabase falla o no
// devuelve nada, esto queda en false y el comando NO se activa (falla del lado seguro).
// El match por "termina en" es para aguantar que el numero este guardado con o sin codigo de pais,
// pero se exigen al menos 8 digitos: si un admin tuviera el whatsapp mal cargado (ej. "0380"),
// sin ese minimo CUALQUIER cliente cuyo numero termine en 0380 pasaria por admin.
let esAdmin = false;
try {
  const admins = $('Consultar Admins').all().map(i => i.json).filter(a => a && a.whatsapp);
  esAdmin = admins.some(a => {
    const d = String(a.whatsapp||'').replace(/\D/g,'');
    if (!d || !senderDigits) return false;
    if (senderDigits === d) return true;
    if (d.length < 8 || senderDigits.length < 8) return false;
    return senderDigits.endsWith(d) || d.endsWith(senderDigits);
  });
} catch(e){}
let texto = '';
try { texto = String($('Combinar').item.json.mensajeCombinado || '').trim(); } catch(e){}

// Acepta: "mayor", "detal", "al mayor", "al detal", "modo mayor", "tarifa al detalle", etc.
// Se revisa LINEA POR LINEA (no el mensaje entero): por el debounce de 30s, si el admin manda
// "Modo detal" justo despues de otros mensajes, todo llega junto en un solo texto. Antes se exigia
// que el mensaje COMPLETO fuera el comando y por eso no lo reconocia.
// La linea tiene que ser SOLO el comando, para no secuestrar frases como "cuanto es al mayor para 5000".
const RX_COMANDO = /^\s*(?:modo\s+|tarifa\s+|precio\s+|pasame\s+|ponme\s+|dame\s+)?(?:al\s+|a\s+|en\s+)?(mayor|mayorista|detal|detalle)\s*[.!?]*\s*$/i;

// OJO: solo se toca el texto si el remitente ES admin. Un cliente puede responder "mayor" a una
// pregunta del bot, y si se le quitara esa linea el agente se quedaria sin saber que contesto.
const lineas = texto.split('\n');
const quedan = [];
let modoElegido = '';
for (const ln of lineas){
  const m = esAdmin ? ln.match(RX_COMANDO) : null;
  if (m){ modoElegido = /^may/i.test(m[1]) ? 'mayor' : 'detal'; continue; }  // se saca del texto
  quedan.push(ln);
}
const esComandoModo = !!(esAdmin && modoElegido);

// Lo que queda del mensaje despues de quitar el comando. Si sobra algo (una pregunta, un monto),
// el flujo sigue normal y se responde YA con la tarifa nueva, en vez de perder ese mensaje.
const textoLimpio = quedan.join('\n').replace(/\n{3,}/g, '\n\n').trim();
const soloComando = textoLimpio.length < 2;

return [{ json: { esAdmin, esComandoModo, modoElegido, soloComando, textoLimpio, jid } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      ,2560
      ,120
    )
    id = 'f4a5b6c7-2345-4d10-9e22-detcomando01'
    name = 'Detectar Comando Admin'
  }
  ,[ordered]@{
    parameters = [ordered]@{
      conditions = [ordered]@{
        options = [ordered]@{
          typeValidation = 'loose'
          leftValue = ''
          caseSensitive = $true
        }
        conditions = @(
          ,[ordered]@{
            id = 'admin-cond-1'
            leftValue = '={{ $json.esComandoModo }}'
            rightValue = $true
            operator = [ordered]@{
              operation = 'equals'
              type = 'boolean'
            }
          }
        )
        combinator = 'and'
      }
    }
    id = 'f5a6b7c8-3456-4d21-9e33-escomando001'
    name = '¿Es Comando Admin?'
    type = 'n8n-nodes-base.if'
    typeVersion = 2.2
    position = @(
      ,2800
      ,120
    )
  }
  ,[ordered]@{
    parameters = [ordered]@{
      value = '={{ $json.modoElegido }}'
      expire = $true
      ttl = 2592000
      keyType = 'string'
      key = '={{ ''modoAdmin:'' + $json.jid }}'
      operation = 'set'
    }
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      ,3040
      ,-40
    )
    id = 'f6a7b8c9-4567-4d32-9e44-rsetmodo0001'
    name = 'Redis Guardar Modo Admin'
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  }
  ,[ordered]@{
    parameters = [ordered]@{
      conditions = [ordered]@{
        options = [ordered]@{
          typeValidation = 'loose'
          leftValue = ''
          caseSensitive = $true
        }
        conditions = @(
          ,[ordered]@{
            id = 'solo-cmd-1'
            leftValue = '={{ $(''Detectar Comando Admin'').first().json.soloComando }}'
            rightValue = $true
            operator = [ordered]@{
              operation = 'equals'
              type = 'boolean'
            }
          }
        )
        combinator = 'and'
      }
    }
    id = 'f9a0b1c2-7890-4d65-9e77-solocomando1'
    name = '¿Solo el Comando?'
    type = 'n8n-nodes-base.if'
    typeVersion = 2.2
    position = @(
      ,3280
      ,-40
    )
  }
  ,[ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Arma el mensaje corto de confirmacion tras guardar la preferencia de tarifa del admin.
const modo = String($('Detectar Comando Admin').item.json.modoElegido || '').toLowerCase();
const texto = modo === 'mayor' ? 'Listo, ahora te muestro tarifa MAYOR 👍' : 'Listo, ahora te muestro tarifa DETAL 👍';
return [{ json: { output: texto } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      ,3520
      ,-120
    )
    id = 'f7a8b9c0-5678-4d43-9e55-confmodo0001'
    name = 'Confirmar Modo Admin'
  }
  ,[ordered]@{
    parameters = [ordered]@{
      instanceName = 'BOT JK Kelvin'
      messageText = '={{ $json.output }}'
      options_message = @{}
      resource = 'messages-api'
      remoteJid = '={{ $(''Cuando lo Llama el Bot'').first().json.body.data.key.remoteJid }}'
    }
    type = 'n8n-nodes-evolution-api.evolutionApi'
    typeVersion = 1
    position = @(
      ,3760
      ,-120
    )
    id = '02d01e05-a9f8-4caa-a02e-37a660aa662c'
    name = 'Enviar texto a WhatsApp'
    retryOnFail = $true
    maxTries = 4
    waitBetweenTries = 5000
    credentials = [ordered]@{
      evolutionApi = [ordered]@{
        id = 'iUIvc9Sd8diFJaGU'
        name = 'Evolution PARA n8n cambios JK'
      }
    }
  }
  ,[ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Empaqueta todo el contexto necesario para "Bot JK - Atencion al Cliente e IA" (Fase 4).
const wh = $('Cuando lo Llama el Bot').first().json || {};
const solo = $('Cuando lo Llama el Bot').first().json || {};
const prep = $('Prep Debounce').first().json || {};
const comb = $('Combinar').first().json || {};
const adm = $('Detectar Comando Admin').first().json || {};
return [{
  json: {
    body: wh.body || {},
    jid: prep.jid || '',
    nombreCargado: solo.nombreCargado || '',
    tarifaCargada: solo.tarifaCargada || '',
    esAdmin: !!adm.esAdmin,
    textoLimpio: adm.textoLimpio || '',
    mensajeCombinado: comb.mensajeCombinado || '',
    mensajes: Array.isArray(comb.mensajes) ? comb.mensajes : []
  }
}];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      ,3520
      ,200
    )
    id = 'e1f2a3b4-0006-4c00-9c00-prepctxia001'
    name = 'Preparar Contexto IA'
  }
  ,[ordered]@{
    parameters = [ordered]@{
      workflowId = [ordered]@{
        mode = 'id'
        __rl = $true
        value = 'OjALXRrfveeGpdtd'
      }
      workflowInputs = [ordered]@{
        value = @{}
        mappingMode = 'defineBelow'
        schema = @()
        attemptToConvertTypes = $false
        matchingColumns = @()
        convertFieldsToString = $true
      }
      source = 'database'
      mode = 'once'
      options = [ordered]@{
        waitForSubWorkflow = $false
      }
    }
    id = 'e1f2a3b4-0006-4c00-9c00-ejecutaria01'
    name = 'Ejecutar IA'
    type = 'n8n-nodes-base.executeWorkflow'
    typeVersion = 1.3
    position = @(
      ,3760
      ,200
    )
    onError = 'continueRegularOutput'
  }
)

$connections = [ordered]@{
  'Cuando lo Llama el Bot' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Ejecutar Media'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Ejecutar Media' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Prep Debounce'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Prep Debounce' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Guardar Msg'
          type = 'main'
          index = 0
        }
        ,[ordered]@{
          node = 'Llego un Comprobante?'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Llego un Comprobante?' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Sticker Verificando'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Guardar Msg' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Marcar Token'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Marcar Token' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Esperar 30s'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Esperar 30s' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Leer Token'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Leer Token' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Filtrar Ultimo'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Filtrar Ultimo' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Leer Mensajes'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Leer Mensajes' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Borrar Buffer'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Borrar Buffer' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Combinar'
          type = 'main'
          index = 0
        }
      )
    )
  }
  Combinar = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Consultar Admins'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Consultar Admins' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Detectar Comando Admin'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Detectar Comando Admin' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = '¿Es Comando Admin?'
          type = 'main'
          index = 0
        }
      )
    )
  }
  '¿Es Comando Admin?' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Guardar Modo Admin'
          type = 'main'
          index = 0
        }
      )
      ,@(
        ,[ordered]@{
          node = 'Preparar Contexto IA'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Guardar Modo Admin' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = '¿Solo el Comando?'
          type = 'main'
          index = 0
        }
      )
    )
  }
  '¿Solo el Comando?' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Confirmar Modo Admin'
          type = 'main'
          index = 0
        }
      )
      ,@(
        ,[ordered]@{
          node = 'Preparar Contexto IA'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Confirmar Modo Admin' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Enviar texto a WhatsApp'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Preparar Contexto IA' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Ejecutar IA'
          type = 'main'
          index = 0
        }
      )
    )
  }
}

$wf = [ordered]@{
  name = 'Bot JK - Debounce y Admin'
  nodes = $nodes
  connections = $connections
  settings = [ordered]@{ executionOrder = 'v1'; timezone = 'America/Bogota' }
}
$salida = Join-Path $PSScriptRoot 'workflow_debounce_admin.json'
$json = $wf | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($salida, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('JSON generado: ' + $salida + ' | nodos: ' + $nodes.Count)
