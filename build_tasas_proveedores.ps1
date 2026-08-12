$ErrorActionPreference = "Stop"

# =====================================================================================
#  WORKFLOW: "Tasas de Proveedores"
#  Kelvin recibe las tasas de los proveedores (cada uno escribe distinto), las ORDENA el
#  mismo, y se las manda a este bot de Telegram con una plantilla simple. El bot las lee,
#  le muestra lo que entendio, y SOLO si el confirma "si" escribe en el Google Sheet.
#  Se crea INACTIVO: el usuario lo revisa y lo activa a mano desde n8n.
# =====================================================================================

# ID del Google Sheet de tasas (el de EDICION, no el publicado) y gid de la pestana.
$SHEET_ID  = '1bkLLIh0i1ml9KOEl_QiCNIWlQVFErfjtPTnLNYfAp5s'
$SHEET_GID = '0'
# Chats de Telegram autorizados (SOLO estos pueden actualizar tasas). Para sumar a alguien,
# agrega su chat.id a esta lista y vuelve a desplegar.
#   627887509  = Kelvin Krak (@Kelvinrene)  <- cuenta personal, la que usa normalmente
#   8892262444 = Operador Uno
$CHAT_IDS  = @('627887509', '8892262444')
$CHAT_IDS_JS = "[" + (($CHAT_IDS | ForEach-Object { "'" + $_ + "'" }) -join ",") + "]"
# CSV publicado (SOLO LECTURA) para validar nombres de pais. Es el mismo que usa el bot.
$CSV_TASAS = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv'

# ===================== CODIGO: PREP DEBOUNCE =====================
# Prepara el buffer para agrupar varios mensajes seguidos (varios proveedores a la vez).
# Las respuestas cortas (si/no) NO esperan: se atienden al instante.
$prepDebounceCode = @'
let texto = '', chatId = '';
try {
  const msg = $('Telegram Trigger').first().json.message || {};
  texto = String(msg.text || '').trim();
  chatId = String((msg.chat && msg.chat.id) || '');
} catch(e){}
const t = String(texto).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^a-z0-9]/g,'');
const CORTAS = ['si','sii','ok','oka','okey','dale','confirmo','confirmar','listo','ya','correcto','sipi',
                'no','nop','cancelar','cancela','anular','nel','negativo'];
const esRespuestaCorta = CORTAS.indexOf(t) !== -1;
const miTs = String(Date.now()) + '-' + Math.random().toString(36).slice(2,8);
return [{ json: { chatId, texto, esRespuestaCorta, miTs, keyBuf: 'bufTasas:'+chatId, keyTok: 'tokTasas:'+chatId } }];
'@

# ===================== CODIGO: FILTRAR ULTIMO =====================
# Solo la ejecucion del ULTIMO mensaje sigue; las anteriores se cortan aca.
$filtrarUltimoCode = @'
const miTs = $('Prep Debounce').first().json.miTs;
let actual = $json.tokenActual;
if (actual === undefined || actual === null) { try { actual = $('Redis Leer Token').first().json.tokenActual; } catch(e){} }
if (String(actual) !== String(miTs)) return [];   // llego otro mensaje despues: esta ejecucion no responde
return [{ json: { ok: true } }];
'@

# ===================== CODIGO: COMBINAR MENSAJES =====================
$combinarMsgsCode = @'
let arr = [];
try { arr = $('Redis Leer Mensajes').first().json.mensajes; } catch(e){}
if (!Array.isArray(arr)) arr = (arr === undefined || arr === null) ? [] : [arr];
const textoFinal = arr.join('\n\n').trim();
// Se conserva la lista SIN juntar: la IA lee UN mensaje por vez (juntarlos le baja mucho la
// precision; con 3 mensajes de golpe se salteo una seccion entera y se invento un pais).
return [{ json: { textoFinal, mensajes: arr, cuantos: arr.length } }];
'@

# ===================== CODIGO: INTERPRETAR MENSAJE =====================
# Decide que hacer con el mensaje: confirmar / cancelar / tasas nuevas / error.
$interpretarCode = @'
// ===== Utilidades =====
function norm(s){ return String(s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]/g,''); }

// Numeros en formato latino, tolerante. Como el resultado SIEMPRE se le muestra al usuario
// para confirmar, un caso ambiguo se ve antes de escribir en la hoja.
function numLatino(s){
  let v = String(s||'').trim().replace(/\s/g,'');
  if(!v) return null;
  if(v.indexOf(',') !== -1){
    v = v.replace(/\./g,'').replace(',', '.');            // coma = decimal, puntos = miles
  } else {
    const p = v.split('.');
    if(p.length > 2) v = p.join('');                       // 1.000.000 -> 1000000
    else if(p.length === 2 && p[1].length === 3) v = p.join(''); // 3.400 -> 3400 (miles)
    // un punto con 1-2 decimales (4.92) se deja tal cual
  }
  const n = parseFloat(v);
  return isNaN(n) ? null : n;
}

// Parser CSV robusto (mismo criterio que el bot: respeta comillas y celdas multi-linea).
function parseCSV(text){
  const Q = '"';
  const rows=[]; let row=[]; let cur=''; let inQ=false;
  for (let i=0; i<text.length; i++){
    const c = text[i];
    if (inQ){ if (c===Q){ if (text[i+1]===Q){ cur+=Q; i++; } else inQ=false; } else cur+=c; }
    else { if (c===Q) inQ=true; else if (c===',') { row.push(cur); cur=''; } else if (c==='\r') { } else if (c==='\n') { row.push(cur); rows.push(row); row=[]; cur=''; } else cur+=c; }
  }
  if (cur.length>0 || row.length>0){ row.push(cur); rows.push(row); }
  return rows.map(r => r.map(s => s.trim())).filter(r => r.some(c => c.length>0));
}

// ===== Entradas =====
// El texto sale de "Combinar Mensajes" (varios mensajes agrupados en la pausa de 20s).
// Si esa rama no corrio (respuesta corta si/no), se usa el mensaje de Telegram directo.
let texto = '', chatId = '';
try {
  const msg = $('Telegram Trigger').first().json.message || {};
  texto = String(msg.text || '').trim();
  chatId = String((msg.chat && msg.chat.id) || '');
} catch(e){}
try {
  const c = $('Combinar Mensajes').first().json;
  if (c && c.textoFinal) texto = String(c.textoFinal).trim();
} catch(e){}

let pendiente = null;
try {
  const raw = $('Redis Leer Pendiente').first().json.pendienteRaw;
  if (raw) pendiente = (typeof raw === 'string') ? JSON.parse(raw) : raw;
} catch(e){ pendiente = null; }

// Paises validos leidos del CSV en vivo (para no escribir un pais que no existe en la hoja).
const paisesValidos = [];
try {
  const csv = String($('Leer Paises').first().json.data || '');
  const filas = parseCSV(csv);
  for (let i=1; i<filas.length; i++){
    const p = (filas[i][0]||'').trim();
    if (p) paisesValidos.push(p);
  }
} catch(e){}

const t = norm(texto);

// ===== 1) Hay algo pendiente de confirmar =====
if (pendiente && pendiente.filas && pendiente.filas.length){
  const esSi = ['si','sii','ok','oka','okey','dale','confirmo','confirmar','listo','ya','correcto','sipi'].indexOf(t) !== -1;
  const esNo = ['no','nop','cancelar','cancela','anular','nel','negativo'].indexOf(t) !== -1;
  if (esSi) return [{ json: { accion:'confirmar', chatId, filas: pendiente.filas, resumen: pendiente.resumen } }];
  if (esNo) return [{ json: { accion:'cancelar', chatId } }];
  // Si escribio otra cosa, lo tratamos como un mensaje NUEVO (sobrescribe el pendiente).
}

// ===== 2) Interpretar tasas nuevas =====
// Se aceptan DOS formatos (y mezclados):
//   A) una linea por pais:   "Colombia 3100 3130"  |  "col 3100/3130"  |  "col r 3130"
//   B) bloque multi-linea:   "Colombia" / "Envio: 3100" / "Recibo: 3130"  (: opcional, abreviaturas ok)

// Abreviaturas y codigos de moneda -> nombre de pais. Solo se usan si no hubo match exacto.
const ALIAS = {
  col:'Colombia', colom:'Colombia', cop:'Colombia',
  ven:'Venezuela', vzla:'Venezuela', vzl:'Venezuela', ves:'Venezuela', bs:'Venezuela', bolivares:'Venezuela',
  arg:'Argentina', ars:'Argentina',
  bra:'Brasil', brasil:'Brasil', brl:'Brasil', reales:'Brasil', reais:'Brasil',
  chi:'Chile', chl:'Chile', clp:'Chile',
  per:'Peru', pe:'Peru', pen:'Peru', soles:'Peru', sol:'Peru',
  mex:'Mexico', mx:'Mexico', mxn:'Mexico',
  uru:'Uruguay', uy:'Uruguay', uyu:'Uruguay',
  par:'Paraguay', py:'Paraguay', pyg:'Paraguay', guaranies:'Paraguay',
  rd:'Republica Dominicana', repdom:'Republica Dominicana', dominicana:'Republica Dominicana', dop:'Republica Dominicana',
  gua:'Guatemala', gt:'Guatemala', gtq:'Guatemala', quetzales:'Guatemala',
  bol:'Bolivia', bob:'Bolivia',
  ecu:'Ecuador', ec:'Ecuador',
  pan:'Panama', pa:'Panama',
  cr:'Costa Rica', costarica:'Costa Rica', crc:'Costa Rica', colones:'Costa Rica',
  hon:'Honduras', hn:'Honduras', lempiras:'Honduras',
  nic:'Nicaragua', ni:'Nicaragua', cordobas:'Nicaragua',
  eur:'Europa', euros:'Europa', euro:'Europa'
};

// Reconoce la palabra clave de una linea/token: envio o recibo (con abreviaturas).
function tipoClave(k){
  const n = norm(k);
  if(!n) return null;
  if(/^(e|env|envi|envio|envios|enviar|salida|venta|vender|v)$/.test(n)) return 'envio';
  if(/^(r|rec|recib|recibo|recibos|recibir|recibe|entrada|compra|comprar|c)$/.test(n)) return 'recibo';
  return null;
}

// Resuelve el nombre escrito contra los paises reales de la hoja.
// estricto=true (formato de una linea): NO usa el emparejado laxo por "contiene", porque con texto
// sucio de proveedor (ej. "SOL/ CHILE (CLP)") aceptaba cualquier cosa y escribia tasas equivocadas.
function resolverPais(nombre, estricto){
  const nq = norm(nombre);
  if(!nq) return null;
  let m = paisesValidos.find(p => norm(p) === nq);          // 1) exacto
  if(m) return m;
  if(ALIAS[nq]){                                            // 2) alias/codigo de moneda
    const a = norm(ALIAS[nq]);
    m = paisesValidos.find(p => norm(p) === a);
    if(m) return m;
    const c0 = paisesValidos.filter(p => norm(p).indexOf(a) === 0);
    if(c0.length) return c0.sort((x,y)=>x.length-y.length)[0];
  }
  // 3) empieza por lo escrito -> el nombre MAS CORTO (evita agarrar "Efectivo Venezuela-Zulia")
  const c1 = paisesValidos.filter(p => norm(p).indexOf(nq) === 0);
  if(c1.length) return c1.sort((x,y)=>x.length-y.length)[0];
  if(estricto) return null;
  const c2 = paisesValidos.filter(p => norm(p).indexOf(nq) !== -1 || nq.indexOf(norm(p)) !== -1);
  if(c2.length) return c2.sort((x,y)=>x.length-y.length)[0];
  return null;
}

// FORMATO A: "<pais> [marca] <num> [marca] <num>" en UNA linea.
function parseUnaLinea(linea){
  const l = String(linea||'').trim().replace(/[;,.\-]+$/,'');
  if(!l) return null;
  // OJO: la coma NO separa tokens, es el decimal latino ("257,4" es UN numero, no dos).
  const toks = l.split(/[\s\/|;]+/).filter(Boolean);
  if(toks.length < 2) return null;
  // Se separan desde el FINAL los tokens que son numero o marca (envio/recibo).
  const cola = [];
  while(toks.length){
    const ult = toks[toks.length-1];
    if(numLatino(ult) !== null || tipoClave(ult)) cola.unshift(toks.pop());
    else break;
  }
  if(!toks.length || !cola.length) return null;
  // El nombre del pais tiene que verse LIMPIO: solo letras (con tildes), puntos y espacios, y como
  // mucho 3 palabras. Si trae emojis, banderas, parentesis o codigos raros, es texto de proveedor:
  // se devuelve null para que lo agarre la IA en vez de adivinar mal.
  const crudoPais = toks.join(' ').trim();
  if(!/^[a-zA-ZÀ-ɏ.\s]+$/.test(crudoPais)) return null;
  if(crudoPais.split(/\s+/).filter(Boolean).length > 3) return null;
  const pais = resolverPais(crudoPais, true);
  if(!pais) return { errorPais: crudoPais };

  let envio = null, recibo = null;
  const libres = [];
  for(let i=0; i<cola.length; i++){
    const marca = tipoClave(cola[i]);
    if(marca){
      const val = numLatino(cola[i+1]);
      if(val !== null){ if(marca === 'envio') envio = val; else recibo = val; i++; }
      continue;
    }
    const v = numLatino(cola[i]);
    if(v !== null) libres.push(v);
  }
  if(envio === null && recibo === null){
    if(libres.length >= 1) envio = libres[0];
    if(libres.length >= 2) recibo = libres[1];
  } else {
    for(const v of libres){
      if(envio === null){ envio = v; continue; }
      if(recibo === null){ recibo = v; }
    }
  }
  if(envio === null && recibo === null) return null;
  return { pais, envio, recibo };
}

const bloques = texto.split(/\n\s*\n/).map(b => b.trim()).filter(Boolean);
const filas = [];
const errores = [];

function agregarFila(pais, envio, recibo){
  let f = filas.find(x => x.Pais === pais);
  if(!f){ f = { Pais: pais }; filas.push(f); }
  if(envio  !== null && envio  !== undefined) f['Tasa Envio']  = envio;
  if(recibo !== null && recibo !== undefined) f['Tasa Recibo'] = recibo;
  return f;
}

for (const bloque of bloques){
  const lineas = bloque.split('\n').map(l => l.trim()).filter(Boolean);
  if (!lineas.length) continue;
  // Un bloque SIN ningun numero es un encabezado o un saludo ("Actualizacion", "Buen dia"):
  // se ignora en silencio, no es un error del usuario.
  if (!/\d/.test(bloque)) continue;

  // Si la PRIMERA linea ya trae numeros -> formato A (cada linea es un pais).
  if (/\d/.test(lineas[0])){
    let ultima = null;
    for (const ln of lineas){
      const r = parseUnaLinea(ln);
      if (r && r.pais){ ultima = agregarFila(r.pais, r.envio, r.recibo); continue; }
      if (r && r.errorPais){ errores.push('"' + r.errorPais + '": no existe en la hoja.'); continue; }
      // No es un pais: puede ser una linea suelta "recibo: 3130" del pais anterior.
      const mk = ln.match(/^([a-zA-Zñáéíóúü]+)\s*:?\s*(.+)$/);
      if (mk && ultima){
        const marca = tipoClave(mk[1]);
        const val = numLatino(mk[2]);
        if (marca && val !== null) ultima[marca === 'envio' ? 'Tasa Envio' : 'Tasa Recibo'] = val;
      }
    }
    continue;
  }

  // Formato B: primera linea = pais, el resto claves.
  const nombrePais = lineas[0].replace(/[:\-]+$/,'').trim();
  // Si el "nombre de pais" viene sucio (emojis, banderas, asteriscos, frases largas) NO es algo que
  // el usuario escribio: es texto de proveedor. Se ignora en silencio y se deja que lo lea la IA.
  if(!/^[a-zA-ZÀ-ɏ.\s]+$/.test(nombrePais) || nombrePais.split(/\s+/).filter(Boolean).length > 3) continue;
  let envio = null, recibo = null;
  for (let i=1; i<lineas.length; i++){
    const mk = lineas[i].match(/^([a-zA-Zñáéíóúü]+)\s*:?\s*(.+)$/);   // ":" OPCIONAL
    if (!mk) continue;
    const marca = tipoClave(mk[1]);
    const val = numLatino(mk[2]);
    if (!marca || val === null) continue;
    if (marca === 'envio') envio = val; else recibo = val;
  }
  if (envio === null && recibo === null){
    errores.push('"' + nombrePais + '": no encontre ninguna tasa (envio o recibo).');
    continue;
  }
  const pais = resolverPais(nombrePais, false);
  if (!pais){ errores.push('"' + nombrePais + '": no existe en la hoja de tasas.'); continue; }
  agregarFila(pais, envio, recibo);
}

// ===== 3) Nada reconocido: si tiene numeros, que lo lea la IA =====
// Los "errores" NO bloquean a la IA: frases sueltas de un mensaje de proveedor
// (ej. "Pedidos +573219343265") generaban errores falsos y tapaban el mensaje entero.
// Se pasan igual, para mostrarlos solo si la IA tampoco encuentra nada.
if (!filas.length){
  const cuantosNumeros = (texto.match(/\d+[.,]?\d*/g) || []).length;
  if (cuantosNumeros >= 1 && texto.length >= 12){
    const promptSistema = [
      'Sos un extractor de tasas de cambio. Te paso el texto CRUDO del mensaje de UN proveedor de remesas.',
      'Devolve SOLO JSON valido con esta forma exacta:',
      '{"proveedores":[{"nombre":"<nombre del proveedor>","filas":[{"pais":"<nombre EXACTO de la lista>","envio":<numero o null>,"recibo":<numero o null>}]}]}',
      '',
      'PAISES VALIDOS (usa EXACTAMENTE estos nombres, tal cual estan escritos):',
      paisesValidos.join(' | '),
      '',
      'REGLAS:',
      '- El nombre del proveedor: si el texto empieza con "Proveedor: X" usa X. Si no, usa el titulo del mensaje (ej. "*CORPORACION GRUPO ELITE*"). Si no hay ninguno, usa "Proveedor".',
      '- MUY IMPORTANTE: un mismo mensaje suele traer DOS listas separadas, una de ENVIO y otra de RECIBO (a veces con un titulo tipo "*RECIBO*"). Tenes que extraer las DOS. Recorre el mensaje linea por linea de arriba a abajo y no te saltees ninguna seccion.',
      '- NUNCA asignes un numero a un pais que no aparece en ESA misma linea. Si la linea dice COP es Colombia, si dice ARS es Argentina, etc. No inventes paises.',
      '',
      '=== COMO DECIDIR SI UN NUMERO ES "ENVIO" O "RECIBO" (lo mas importante) ===',
      'ENVIO  = el dolar/USDT va HACIA el pais. Nosotros pagamos dolares y alguien cobra moneda local alla.',
      'RECIBO = la moneda local va HACIA el dolar. Alguien entrega moneda local alla y nosotros recibimos dolares.',
      '',
      'Pista 1 - ORDEN DE LAS MONEDAS (la mas confiable): "X/Y" significa de X hacia Y.',
      '  "USDT/COP", "USD/CHILE", "DOLAR/ARS"  -> ENVIO.',
      '  "COP/USDT", "ARS/DOLAR", "MXN/USDT"   -> RECIBO.',
      '',
      'Pista 2 - CUIDADO: cuando el proveedor habla en primera persona lo dice desde SU lado,',
      'que es el CONTRARIO al nuestro. Fijate SIEMPRE en que moneda menciona:',
      '  "RECIBO USDT" / "USDT RECIBO" / "recibo dolares"  -> el proveedor RECIBE dolares y entrega moneda local -> para nosotros es ENVIO.',
      '  "DOY USDT" / "USDT DOY" / "entrego dolares"       -> el proveedor DA dolares y cobra moneda local     -> para nosotros es RECIBO.',
      '  "RECIBIENDO DEPOSITOS" / "recibo COP" / "recibo pesos" -> el proveedor recibe MONEDA LOCAL -> RECIBO.',
      '  "RETIROS" / "retiros sin tarjeta" (el destinatario retira alla) -> ENVIO.',
      '  "pagando usdt x COP" / "pago usdt por pesos"      -> se pagan dolares para entregar pesos -> ENVIO.',
      '',
      'Pista 3 - CONTROL FINAL: para un mismo pais el numero de ENVIO SIEMPRE es MENOR que el de RECIBO',
      '(esa diferencia es la ganancia del proveedor). Si te quedo un ENVIO mas alto que un RECIBO del mismo',
      'pais, casi seguro invertiste la direccion: revisala antes de responder.',
      '',
      '- IGNORA por completo las lineas cuya moneda base NO sea dolar o USDT (ej. "SOL/CHILE" es base sol peruano: ignorala).',
      '- IGNORA lineas sin numero claro ("CONSULTAR AL MOMENTO", tachadas, vacias) y los telefonos de contacto.',
      '- Numeros en formato latino: la coma es decimal y el punto es de miles. "1.668" = 1668. "4,82" = 4.82. Devolvelos como numero JSON normal (punto decimal).',
      '- Los digitos pueden venir como emoji (1️⃣9️⃣.4️⃣0️⃣ = 19.40). Convertilos a numero normal.',
      '- Si de un pais solo hay envio o solo recibo, pone null en el otro.',
      '- Si un pais del mensaje no esta en la lista de validos, omitilo.',
      '- No inventes ningun numero: si no esta en el mensaje, no lo pongas.'
    ].join('\n');
    // UN item por mensaje original -> UNA llamada a la IA por proveedor. Juntarlos en una sola
    // llamada le baja mucho la precision (se salteo una lista entera de envios y se invento un pais).
    let partes = [];
    try {
      const c = $('Combinar Mensajes').first().json;
      if (c && Array.isArray(c.mensajes)) partes = c.mensajes.filter(x => String(x||'').trim().length > 10);
    } catch(e){}
    if (!partes.length) partes = [texto];
    return partes.map(p => ({ json: { accion:'ia', chatId, textoOriginal: String(p).trim(), promptSistema, errores: errores.join('\n') } }));
  }
  return [{ json: { accion:'error', chatId, errores: errores.join('\n') } }];
}

// Resumen legible para que el usuario confirme ANTES de escribir.
const lineasResumen = filas.map(f => {
  const partes = [];
  if (f['Tasa Envio']  !== undefined) partes.push('envio ' + f['Tasa Envio']);
  if (f['Tasa Recibo'] !== undefined) partes.push('recibo ' + f['Tasa Recibo']);
  const noTocado = (f['Tasa Envio'] === undefined) ? ' (envio no se toca)'
                 : (f['Tasa Recibo'] === undefined) ? ' (recibo no se toca)' : '';
  return '• ' + f.Pais + ': ' + partes.join(', ') + noTocado;
});
let resumen = lineasResumen.join('\n');
if (errores.length) resumen += '\n\n⚠️ Ignorado:\n' + errores.join('\n');

return [{ json: { accion:'nuevo', chatId, filas, resumen, pendienteJson: JSON.stringify({ filas, resumen }) } }];
'@

# ===================== CODIGO: EXPANDIR FILAS =====================
# Convierte las filas confirmadas en 1 item por pais, para que Google Sheets actualice fila por fila.
$expandirCode = @'
const d = $('Interpretar Mensaje').first().json;
const filas = (d && d.filas) || [];
if (!filas.length) return [];
return filas.map(f => ({ json: f }));
'@

# ===================== CODIGO: TEXTO CONFIRMADO =====================
$textoOkCode = @'
// Se ejecuta una vez, despues de escribir en la hoja.
const d = $('Interpretar Mensaje').first().json;
const n = ((d && d.filas) || []).length;
return [{ json: { texto: '✅ Listo, actualice ' + n + ' ' + (n === 1 ? 'pais' : 'paises') + ' en la hoja.\n\n' + (d.resumen || '') } }];
'@

# ===================== CODIGO: ARMAR BORRADOR DESDE LA IA =====================
# Toma la respuesta de OpenAI (mensaje crudo de un proveedor ya interpretado) y arma el mismo
# formato que produce "Interpretar Mensaje", para reusar el flujo de confirmacion.
$armarBorradorCode = @'
function norm(s){ return String(s||'').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^a-z0-9]/g,''); }
function parseCSV(text){
  const Q = '"';
  const rows=[]; let row=[]; let cur=''; let inQ=false;
  for (let i=0; i<text.length; i++){
    const c = text[i];
    if (inQ){ if (c===Q){ if (text[i+1]===Q){ cur+=Q; i++; } else inQ=false; } else cur+=c; }
    else { if (c===Q) inQ=true; else if (c===',') { row.push(cur); cur=''; } else if (c==='\r') { } else if (c==='\n') { row.push(cur); rows.push(row); row=[]; cur=''; } else cur+=c; }
  }
  if (cur.length>0 || row.length>0){ row.push(cur); rows.push(row); }
  return rows.map(r => r.map(s => s.trim())).filter(r => r.some(c => c.length>0));
}

const chatId = String($('Interpretar Mensaje').first().json.chatId || '');

// Paises reales de la hoja (para no escribir uno inventado por la IA).
const paisesValidos = [];
try {
  const filas0 = parseCSV(String($('Leer Paises').first().json.data || ''));
  for (let i=1; i<filas0.length; i++){ const p=(filas0[i][0]||'').trim(); if(p) paisesValidos.push(p); }
} catch(e){}

// Respuestas de OpenAI: puede venir UNA por cada mensaje de proveedor (una llamada por mensaje).
const gruposIA = [];
let items = [];
try { items = $input.all(); } catch(e){ items = [{ json: $json }]; }
let n = 0;
for (const it of items){
  let cont = '';
  try { cont = String(it.json.choices[0].message.content || ''); } catch(e){ continue; }
  cont = cont.replace(/^```(?:json)?/i,'').replace(/```$/,'').trim();
  let data = null;
  try { data = JSON.parse(cont); } catch(e){ continue; }
  n++;
  if (data && Array.isArray(data.proveedores)) {
    for (const g of data.proveedores) gruposIA.push(g);
  } else if (data && Array.isArray(data.filas)) {
    gruposIA.push({ nombre: data.nombre || ('Proveedor ' + n), filas: data.filas });
  }
}

// Aplana: una entrada por (proveedor, pais).
const entradas = [];
const omitidos = [];
for (const g of gruposIA){
  const prov = String((g && g.nombre) || 'Proveedor').trim().slice(0,40);
  for (const f of ((g && g.filas) || [])){
    const nq = norm(f.pais);
    const pais = paisesValidos.find(p => norm(p) === nq) || paisesValidos.find(p => norm(p).indexOf(nq) === 0);
    if (!pais){ if(f.pais && omitidos.indexOf(String(f.pais)) === -1) omitidos.push(String(f.pais)); continue; }
    const e = (f.envio  === null || f.envio  === undefined || isNaN(Number(f.envio)))  ? null : Number(f.envio);
    const r = (f.recibo === null || f.recibo === undefined || isNaN(Number(f.recibo))) ? null : Number(f.recibo);
    if (e === null && r === null) continue;
    entradas.push({ pais, prov, envio: e, recibo: r });
  }
}

// ===== MEJOR OFERTA POR PAIS =====
// Criterio confirmado por el usuario (2026-08-10):
//   ENVIO  -> gana el numero MAS ALTO  (el proveedor entrega mas moneda local por dolar)
//   RECIBO -> gana el numero MAS BAJO  (hacen falta menos pesos para conseguir un dolar)
const porPais = {};
for (const x of entradas){
  if (!porPais[x.pais]) porPais[x.pais] = { envios: [], recibos: [] };
  if (x.envio  !== null) porPais[x.pais].envios.push({ v: x.envio,  prov: x.prov });
  if (x.recibo !== null) porPais[x.pais].recibos.push({ v: x.recibo, prov: x.prov });
}

const filas = [];
const detalle = [];
const sospechosos = [];
for (const pais of Object.keys(porPais)){
  const g = porPais[pais];
  const mejorEnvio  = g.envios.length  ? g.envios.slice().sort((a,b) => b.v - a.v)[0]  : null;  // MAS ALTO
  const mejorRecibo = g.recibos.length ? g.recibos.slice().sort((a,b) => a.v - b.v)[0] : null;  // MAS BAJO
  const fila = { Pais: pais };
  if (mejorEnvio)  fila['Tasa Envio']  = mejorEnvio.v;
  if (mejorRecibo) fila['Tasa Recibo'] = mejorRecibo.v;
  filas.push(fila);

  // Control: el envio SIEMPRE debe ser menor que el recibo (esa diferencia es la ganancia del
  // proveedor). Si sale al reves, lo mas probable es que se haya confundido la direccion.
  const invertido = (mejorEnvio && mejorRecibo && mejorEnvio.v >= mejorRecibo.v);
  if (invertido) sospechosos.push(pais);

  const lin = [pais + (invertido ? '   <-- REVISAR: el envio quedo mayor o igual que el recibo' : '')];
  if (mejorEnvio){
    const otros = g.envios.filter(x => x !== mejorEnvio).sort((a,b) => b.v - a.v);
    lin.push('   envio  ' + mejorEnvio.v + '  <- ' + mejorEnvio.prov
      + (otros.length ? '\n            otros: ' + otros.map(o => o.v + ' (' + o.prov + ')').join(', ') : ''));
  } else lin.push('   envio  -- (ninguno lo trae)');
  if (mejorRecibo){
    const otros = g.recibos.filter(x => x !== mejorRecibo).sort((a,b) => a.v - b.v);
    lin.push('   recibo ' + mejorRecibo.v + '  <- ' + mejorRecibo.prov
      + (otros.length ? '\n            otros: ' + otros.map(o => o.v + ' (' + o.prov + ')').join(', ') : ''));
  } else lin.push('   recibo -- (ninguno lo trae)');
  detalle.push(lin.join('\n'));
}

if (!filas.length){
  let det = '';
  try { const e = $('Interpretar Mensaje').first().json.errores; if(e) det = '\n\nDetalle:\n' + e; } catch(e){}
  const texto = 'Lei el mensaje pero no pude sacar tasas claras de ahi.' + det
    + '\n\nPasamelas en formato corto, una linea por pais:\n\nColombia 3100 3130\nVenezuela 856 870';
  return [{ json: { chatId, filas: [], resumen: '', pendienteJson: '', sinDatos: true, textoDirecto: texto } }];
}

const cuantosProv = [];
for (const x of entradas){ if (cuantosProv.indexOf(x.prov) === -1) cuantosProv.push(x.prov); }

let resumen = detalle.join('\n\n');
if (sospechosos.length) resumen += '\n\n⚠️ Revisa ' + sospechosos.join(', ')
  + ': el envio deberia ser MENOR que el recibo. Puede que el proveedor lo haya escrito al reves.';
if (omitidos.length) resumen += '\n\n(Omiti, no estan en tu hoja: ' + omitidos.join(', ') + ')';

// Borrador copiable: el usuario lo edita con SUS numeros y lo reenvia.
// OJO: si solo hay RECIBO hay que marcarlo con "r", porque un numero suelto se lee como ENVIO.
const borrador = filas.map(f => {
  const e = f['Tasa Envio'], r = f['Tasa Recibo'];
  if (e !== undefined && r !== undefined) return f.Pais + ' ' + e + ' ' + r;
  if (e !== undefined) return f.Pais + ' ' + e;
  return f.Pais + ' r ' + r;
}).join('\n');

// Resumen corto (el que se guarda como pendiente y se muestra al confirmar).
const resumenCorto = filas.map(f => {
  const partes = [];
  if (f['Tasa Envio']  !== undefined) partes.push('envio ' + f['Tasa Envio']);
  if (f['Tasa Recibo'] !== undefined) partes.push('recibo ' + f['Tasa Recibo']);
  const noTocado = (f['Tasa Envio'] === undefined) ? ' (envio no se toca)'
                 : (f['Tasa Recibo'] === undefined) ? ' (recibo no se toca)' : '';
  return '• ' + f.Pais + ': ' + partes.join(', ') + noTocado;
}).join('\n');

return [{ json: { chatId, filas, resumen, resumenCorto, borrador, proveedores: cuantosProv,
                  pendienteJson: JSON.stringify({ filas, resumen: resumenCorto }) } }];
'@

# ===================== CODIGO: TEXTO PEDIR CONFIRMACION =====================
# Sirve para las dos ramas: la del parser normal y la de la IA.
$textoPreguntaCode = @'
let d = null, viaIA = false;
try { const b = $('Armar Borrador IA').first().json; if (b && (b.resumen || b.sinDatos)) { d = b; viaIA = true; } } catch(e){}
if (!d) { try { d = $('Interpretar Mensaje').first().json; } catch(e){} }
if (!d) return [{ json: { texto: 'No pude procesar el mensaje.' } }];

if (d.sinDatos) return [{ json: { texto: d.textoDirecto, borrador: '' } }];

if (viaIA){
  const provs = d.proveedores || [];
  const encabezado = provs.length > 1
    ? ('Compare ' + provs.length + ' proveedores (' + provs.join(', ') + ') y estas son las MEJORES:')
    : ('Lei el mensaje de ' + (provs[0] || 'el proveedor') + '. OJO: son SUS tasas, sin tus ajustes:');
  // El BORRADOR va aparte, en un 2do mensaje limpio (sin encabezado ni explicaciones), asi se puede
  // copiar de un toque en Telegram, editar y reenviar. Pedido del usuario.
  const texto = encabezado + '\n\n' + d.resumen
    + '\n\n(envio: gana el mas alto | recibo: gana el mas bajo)'
    + '\n\nSi las queres tal cual, responde si.'
    + '\nSi no, copia el mensaje de abajo, cambia los numeros y mandamelo.';
  return [{ json: { texto, borrador: d.borrador || '' } }];
}
return [{ json: { texto: 'Entendi esto:\n\n' + d.resumen + '\n\n¿Lo aplico en la hoja? Responde *si* o *no*.', borrador: '' } }];
'@

# ===================== CODIGO: PREPARAR BORRADOR (2do mensaje) =====================
# El borrador se manda SOLO, sin encabezado, para poder copiarlo de un toque en Telegram.
# Si no hay borrador (el usuario ya mando el formato corto), no se envia nada.
$prepararBorradorCode = @'
let b = '';
try { b = String($('Texto Pregunta').first().json.borrador || '').trim(); } catch(e){}
if (!b) return [];
return [{ json: { texto: b } }];
'@

# ===================== CODIGO: TEXTO ERROR / AYUDA =====================
$textoErrorCode = @'
const d = $('Interpretar Mensaje').first().json;
const detalle = d.errores ? ('\n\nDetalle:\n' + d.errores) : '';
const ayuda = 'No pude leer las tasas.' + detalle
  + '\n\nFormas que entiendo:\n'
  + '\n1) Corto (una linea por pais):\nColombia 3100 3130\nVenezuela 856 870\n   (primer numero = envio, segundo = recibo)\n'
  + '\n2) Con abreviatura:\ncol 3100 3130\nven 856 870\n'
  + '\n3) Solo una de las dos:\ncol 3100        (solo envio)\ncol r 3130      (solo recibo)\n'
  + '\n4) Largo (como antes):\nColombia\nenvio: 3100\nrecibo: 3130\n'
  + '\nTambien podes pegarme el mensaje tal cual te lo manda un proveedor y lo interpreto.';
return [{ json: { texto: ayuda } }];
'@

# Texto fijo con emoji: va en heredoc porque PowerShell 5.1 no tolera emojis en strings inline.
$txtCancelado = @'
Cancelado, no toque nada en la hoja 👍
'@
$txtCancelado = $txtCancelado.Trim()

# ===================== NODOS =====================
# Credencial de Telegram: creada via API con token PLACEHOLDER. El usuario le pone el token real en la UI de n8n.
$telegramCred = @{ telegramApi = @{ id = 'qb4kRPKHUMWXYXLl'; name = 'Telegram Tasas Proveedores' } }
$redisCred    = @{ redis = @{ id = 'SKkvpS5A65SOcmJs'; name = 'Redis memoria para Cambios JK' } }
# Credencial de Google (cuenta de servicio): la crea el usuario en la UI de n8n pegando el email y
# la private_key del archivo .json descargado. Por eso el nodo "Actualizar Hoja" va SIN credencial:
# el usuario la selecciona del desplegable la primera vez que abre el nodo.

$nodes = @(
  [ordered]@{
    parameters = @{ updates = @('message'); additionalFields = @{} }
    id = 'a1000000-0000-4000-9000-telegramtrig1'; name = 'Telegram Trigger'; type = 'n8n-nodes-base.telegramTrigger'; typeVersion = 1.2; position = @(-400,300)
    credentials = $telegramCred
  },
  [ordered]@{
    # Solo los chats autorizados pueden tocar las tasas. Cualquier otro mensaje se ignora en silencio.
    # Ojo: Telegram manda chat.id como NUMERO, por eso se compara con String(...) contra la lista.
    parameters = @{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'admin-chat-1'; leftValue = "={{ $CHAT_IDS_JS.indexOf(String(`$json.message.chat.id)) !== -1 }}"; rightValue = $true; operator = @{ type = 'boolean'; operation = 'equals' } } ); combinator = 'and' } }
    id = 'a2000000-0000-4000-9000-soloadmin0001'; name = '¿Chat Autorizado?'; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(-200,300)
  },
  # ---------- PAUSA DE 20s: agrupa varios mensajes seguidos (varios proveedores a la vez) ----------
  [ordered]@{
    parameters = @{ jsCode = $prepDebounceCode }
    id = 'g1000000-0000-4000-9000-prepdebounce1'; name = 'Prep Debounce'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(-60,300)
  },
  [ordered]@{
    # si/no NO esperan (salida true = atajo); cualquier otra cosa entra al buffer de 20s.
    parameters = @{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'corta-1'; leftValue = '={{ $json.esRespuestaCorta }}'; rightValue = $true; operator = @{ type = 'boolean'; operation = 'equals' } } ); combinator = 'and' } }
    id = 'g2000000-0000-4000-9000-escorta000001'; name = '¿Respuesta Corta?'; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(60,300)
  },
  [ordered]@{
    parameters = @{ operation = 'push'; list = "={{ `$('Prep Debounce').first().json.keyBuf }}"; messageData = "={{ `$('Prep Debounce').first().json.texto }}"; tail = $true }
    id = 'g3000000-0000-4000-9000-rpushtasas001'; name = 'Redis Guardar Msg'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(60,460); credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = "={{ `$('Prep Debounce').first().json.keyTok }}"; value = "={{ `$('Prep Debounce').first().json.miTs }}"; keyType = 'string'; expire = $true; ttl = 180 }
    id = 'g4000000-0000-4000-9000-rsettoktasas1'; name = 'Redis Marcar Token'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(200,460); credentials = $redisCred
  },
  [ordered]@{
    # 45s: con 20s se partia en dos respuestas (el 4to mensaje llego 22s despues del 3ro).
    parameters = @{ unit = 'seconds'; amount = 45 }
    id = 'g5000000-0000-4000-9000-esperar20s001'; name = 'Esperar Mensajes'; type = 'n8n-nodes-base.wait'; typeVersion = 1.1; position = @(340,460); webhookId = 'b7c8d9e0-1122-4334-9556-esperatasas01'
  },
  [ordered]@{
    parameters = @{ operation = 'get'; key = "={{ `$('Prep Debounce').first().json.keyTok }}"; propertyName = 'tokenActual'; keyType = 'string'; options = @{} }
    id = 'g6000000-0000-4000-9000-rgettoktasas1'; name = 'Redis Leer Token'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(480,460); credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $filtrarUltimoCode }
    id = 'g7000000-0000-4000-9000-filtrarult001'; name = 'Filtrar Ultimo'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(620,460)
  },
  [ordered]@{
    parameters = @{ operation = 'get'; key = "={{ `$('Prep Debounce').first().json.keyBuf }}"; propertyName = 'mensajes'; keyType = 'list'; options = @{} }
    id = 'g8000000-0000-4000-9000-rgetlisttasas'; name = 'Redis Leer Mensajes'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(760,460); credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ operation = 'delete'; key = "={{ `$('Prep Debounce').first().json.keyBuf }}" }
    id = 'g9000000-0000-4000-9000-rdelbuftasas1'; name = 'Redis Borrar Buffer'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(900,460); credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $combinarMsgsCode }
    id = 'ga000000-0000-4000-9000-combinarmsgs1'; name = 'Combinar Mensajes'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1040,460)
  },

  [ordered]@{
    # Lee la hoja de tasas (CSV publicado, solo lectura) para validar los nombres de pais.
    parameters = @{ url = $CSV_TASAS; options = @{} }
    id = 'a3000000-0000-4000-9000-leerpaises001'; name = 'Leer Paises'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(0,300)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 1500; alwaysOutputData = $true
  },
  [ordered]@{
    # ¿Hay una actualizacion esperando confirmacion de este chat?
    parameters = @{ operation = 'get'; key = "={{ 'pendiente:tasas:' + `$('Telegram Trigger').first().json.message.chat.id }}"; propertyName = 'pendienteRaw'; keyType = 'string'; options = @{} }
    id = 'a4000000-0000-4000-9000-rgetpend00001'; name = 'Redis Leer Pendiente'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(200,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $interpretarCode }
    id = 'a5000000-0000-4000-9000-interpretar01'; name = 'Interpretar Mensaje'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(400,300)
  },
  [ordered]@{
    parameters = @{
      rules = @{ values = @(
        [ordered]@{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'r-conf'; leftValue = '={{ $json.accion }}'; rightValue = 'confirmar'; operator = @{ type = 'string'; operation = 'equals' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'confirmar' },
        [ordered]@{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'r-canc'; leftValue = '={{ $json.accion }}'; rightValue = 'cancelar'; operator = @{ type = 'string'; operation = 'equals' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'cancelar' },
        [ordered]@{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'r-nuevo'; leftValue = '={{ $json.accion }}'; rightValue = 'nuevo'; operator = @{ type = 'string'; operation = 'equals' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'nuevo' },
        [ordered]@{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'r-err'; leftValue = '={{ $json.accion }}'; rightValue = 'error'; operator = @{ type = 'string'; operation = 'equals' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'error' },
        [ordered]@{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'r-ia'; leftValue = '={{ $json.accion }}'; rightValue = 'ia'; operator = @{ type = 'string'; operation = 'equals' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'ia' }
      ) }
      options = @{}
    }
    id = 'a6000000-0000-4000-9000-router0000001'; name = 'Router'; type = 'n8n-nodes-base.switch'; typeVersion = 3.2; position = @(600,300)
  },

  # ---------- RAMA: CONFIRMAR (escribe en la hoja) ----------
  [ordered]@{
    parameters = @{ jsCode = $expandirCode }
    id = 'b1000000-0000-4000-9000-expandirfila1'; name = 'Expandir Filas'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(820,60)
  },
  [ordered]@{
    # autoMapInputData: SOLO escribe las columnas que vienen en el item.
    # Si mandaste solo "envio", la columna "Tasa Recibo" queda intacta.
    parameters = [ordered]@{
      authentication = 'serviceAccount'
      resource = 'sheet'
      operation = 'update'
      documentId = @{ __rl = $true; mode = 'id'; value = $SHEET_ID }
      sheetName  = @{ __rl = $true; mode = 'id'; value = $SHEET_GID }
      columns = @{ mappingMode = 'autoMapInputData'; matchingColumns = @('Pais'); value = @{}; schema = @() }
      options = @{}
    }
    id = 'b2000000-0000-4000-9000-updatesheet01'; name = 'Actualizar Hoja'; type = 'n8n-nodes-base.googleSheets'; typeVersion = 4.5; position = @(1020,60)
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 2000
  },
  [ordered]@{
    parameters = @{ operation = 'delete'; key = "={{ 'pendiente:tasas:' + `$('Telegram Trigger').first().json.message.chat.id }}" }
    id = 'b3000000-0000-4000-9000-rdelpend00001'; name = 'Redis Borrar Pendiente'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1220,60)
    onError = 'continueRegularOutput'
    credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $textoOkCode }
    id = 'b4000000-0000-4000-9000-textook000001'; name = 'Texto Confirmado'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1420,60)
    executeOnce = $true
  },
  [ordered]@{
    parameters = @{ chatId = "={{ `$('Telegram Trigger').first().json.message.chat.id }}"; text = '={{ $json.texto }}'; additionalFields = @{} }
    id = 'b5000000-0000-4000-9000-tgok00000001'; name = 'Avisar Actualizado'; type = 'n8n-nodes-base.telegram'; typeVersion = 1.2; position = @(1620,60)
    executeOnce = $true; retryOnFail = $true; maxTries = 3; waitBetweenTries = 2000
    credentials = $telegramCred
  },

  # ---------- RAMA: CANCELAR ----------
  [ordered]@{
    parameters = @{ operation = 'delete'; key = "={{ 'pendiente:tasas:' + `$('Telegram Trigger').first().json.message.chat.id }}" }
    id = 'c1000000-0000-4000-9000-rdelcancel001'; name = 'Redis Borrar (Cancelar)'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(820,220)
    onError = 'continueRegularOutput'
    credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ chatId = "={{ `$('Telegram Trigger').first().json.message.chat.id }}"; text = $txtCancelado; additionalFields = @{} }
    id = 'c2000000-0000-4000-9000-tgcancel00001'; name = 'Avisar Cancelado'; type = 'n8n-nodes-base.telegram'; typeVersion = 1.2; position = @(1020,220)
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 2000
    credentials = $telegramCred
  },

  # ---------- RAMA: TASAS NUEVAS (guarda pendiente y pregunta) ----------
  [ordered]@{
    parameters = @{ operation = 'set'; key = "={{ 'pendiente:tasas:' + `$json.chatId }}"; value = '={{ $json.pendienteJson }}'; keyType = 'string'; expire = $true; ttl = 900 }
    id = 'd1000000-0000-4000-9000-rsetpend00001'; name = 'Redis Guardar Pendiente'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(820,380)
    credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $textoPreguntaCode }
    id = 'd2000000-0000-4000-9000-textoask00001'; name = 'Texto Pregunta'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1020,380)
  },
  [ordered]@{
    parameters = @{ chatId = "={{ `$('Telegram Trigger').first().json.message.chat.id }}"; text = '={{ $json.texto }}'; additionalFields = @{} }
    id = 'd3000000-0000-4000-9000-tgask00000001'; name = 'Pedir Confirmacion'; type = 'n8n-nodes-base.telegram'; typeVersion = 1.2; position = @(1220,380)
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 2000
    credentials = $telegramCred
  },
  [ordered]@{
    parameters = @{ jsCode = $prepararBorradorCode }
    id = 'd4000000-0000-4000-9000-prepborrador1'; name = 'Preparar Borrador'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1420,380)
  },
  [ordered]@{
    # 2do mensaje: SOLO el borrador, listo para copiar/editar/reenviar.
    parameters = @{ chatId = "={{ `$('Telegram Trigger').first().json.message.chat.id }}"; text = '={{ $json.texto }}'; additionalFields = @{} }
    id = 'd5000000-0000-4000-9000-tgborrador001'; name = 'Enviar Borrador'; type = 'n8n-nodes-base.telegram'; typeVersion = 1.2; position = @(1620,380)
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 2000
    credentials = $telegramCred
  },

  # ---------- RAMA: ERROR / AYUDA ----------
  [ordered]@{
    parameters = @{ jsCode = $textoErrorCode }
    id = 'e1000000-0000-4000-9000-textoerr00001'; name = 'Texto Ayuda'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(820,540)
  },
  [ordered]@{
    parameters = @{ chatId = "={{ `$('Telegram Trigger').first().json.message.chat.id }}"; text = '={{ $json.texto }}'; additionalFields = @{} }
    id = 'e2000000-0000-4000-9000-tgerr00000001'; name = 'Avisar Formato'; type = 'n8n-nodes-base.telegram'; typeVersion = 1.2; position = @(1020,540)
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 2000
    credentials = $telegramCred
  },

  # ---------- RAMA: IA (mensaje crudo de un proveedor) ----------
  [ordered]@{
    # Solo corre cuando el parser normal NO entendio nada y el texto parece una lista de tasas.
    # Asi el gasto de OpenAI es minimo: el uso diario normal no pasa por aca.
    parameters = [ordered]@{
      method = 'POST'
      url = 'https://api.openai.com/v1/chat/completions'
      authentication = 'predefinedCredentialType'
      nodeCredentialType = 'openAiApi'
      sendBody = $true
      specifyBody = 'json'
      # gpt-4o (no mini): una tasa mal leida cuesta plata real y el volumen es de pocas llamadas por dia.
      jsonBody = "={{ JSON.stringify({ model: 'gpt-4o', temperature: 0, response_format: { type: 'json_object' }, messages: [ { role: 'system', content: `$json.promptSistema }, { role: 'user', content: `$json.textoOriginal } ] }) }}"
      options = @{}
    }
    id = 'f1000000-0000-4000-9000-openaitasas01'; name = 'Leer con IA'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(820,700)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 2000; alwaysOutputData = $true
    credentials = @{ openAiApi = @{ id = '44lRGIyEnSk1lMc5'; name = 'cambios jk para n8n' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $armarBorradorCode }
    id = 'f2000000-0000-4000-9000-borradoria001'; name = 'Armar Borrador IA'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1020,700)
  }
)

$connections = [ordered]@{
  'Telegram Trigger'     = @{ main = @( ,@( @{ node='¿Chat Autorizado?'; type='main'; index=0 } ) ) }
  '¿Chat Autorizado?'    = @{ main = @( ,@( @{ node='Prep Debounce'; type='main'; index=0 } ) ) }
  'Prep Debounce'        = @{ main = @( ,@( @{ node='¿Respuesta Corta?'; type='main'; index=0 } ) ) }
  # true (si/no) -> directo, sin esperar. false -> buffer de 20s para juntar varios mensajes.
  '¿Respuesta Corta?'    = @{ main = (
      @( ,@( @{ node='Leer Paises'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Redis Guardar Msg'; type='main'; index=0 } ) )
    ) }
  'Redis Guardar Msg'    = @{ main = @( ,@( @{ node='Redis Marcar Token'; type='main'; index=0 } ) ) }
  'Redis Marcar Token'   = @{ main = @( ,@( @{ node='Esperar Mensajes'; type='main'; index=0 } ) ) }
  'Esperar Mensajes'          = @{ main = @( ,@( @{ node='Redis Leer Token'; type='main'; index=0 } ) ) }
  'Redis Leer Token'     = @{ main = @( ,@( @{ node='Filtrar Ultimo'; type='main'; index=0 } ) ) }
  'Filtrar Ultimo'       = @{ main = @( ,@( @{ node='Redis Leer Mensajes'; type='main'; index=0 } ) ) }
  'Redis Leer Mensajes'  = @{ main = @( ,@( @{ node='Redis Borrar Buffer'; type='main'; index=0 } ) ) }
  'Redis Borrar Buffer'  = @{ main = @( ,@( @{ node='Combinar Mensajes'; type='main'; index=0 } ) ) }
  'Combinar Mensajes'    = @{ main = @( ,@( @{ node='Leer Paises'; type='main'; index=0 } ) ) }
  'Leer Paises'          = @{ main = @( ,@( @{ node='Redis Leer Pendiente'; type='main'; index=0 } ) ) }
  'Redis Leer Pendiente' = @{ main = @( ,@( @{ node='Interpretar Mensaje'; type='main'; index=0 } ) ) }
  'Interpretar Mensaje'  = @{ main = @( ,@( @{ node='Router'; type='main'; index=0 } ) ) }
  'Router'               = @{ main = (
      @( ,@( @{ node='Expandir Filas'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Redis Borrar (Cancelar)'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Redis Guardar Pendiente'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Texto Ayuda'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Leer con IA'; type='main'; index=0 } ) )
    ) }
  'Leer con IA'          = @{ main = @( ,@( @{ node='Armar Borrador IA'; type='main'; index=0 } ) ) }
  'Armar Borrador IA'    = @{ main = @( ,@( @{ node='Redis Guardar Pendiente'; type='main'; index=0 } ) ) }
  'Expandir Filas'          = @{ main = @( ,@( @{ node='Actualizar Hoja'; type='main'; index=0 } ) ) }
  'Actualizar Hoja'         = @{ main = @( ,@( @{ node='Redis Borrar Pendiente'; type='main'; index=0 } ) ) }
  'Redis Borrar Pendiente'  = @{ main = @( ,@( @{ node='Texto Confirmado'; type='main'; index=0 } ) ) }
  'Texto Confirmado'        = @{ main = @( ,@( @{ node='Avisar Actualizado'; type='main'; index=0 } ) ) }
  'Redis Borrar (Cancelar)' = @{ main = @( ,@( @{ node='Avisar Cancelado'; type='main'; index=0 } ) ) }
  'Redis Guardar Pendiente' = @{ main = @( ,@( @{ node='Texto Pregunta'; type='main'; index=0 } ) ) }
  'Texto Pregunta'          = @{ main = @( ,@( @{ node='Pedir Confirmacion'; type='main'; index=0 } ) ) }
  'Pedir Confirmacion'      = @{ main = @( ,@( @{ node='Preparar Borrador'; type='main'; index=0 } ) ) }
  'Preparar Borrador'       = @{ main = @( ,@( @{ node='Enviar Borrador'; type='main'; index=0 } ) ) }
  'Texto Ayuda'             = @{ main = @( ,@( @{ node='Avisar Formato'; type='main'; index=0 } ) ) }
}

$body = [ordered]@{ name = 'Tasas de Proveedores'; nodes = $nodes; connections = $connections; settings = @{ executionOrder = 'v1' } }

$json = $body | ConvertTo-Json -Depth 40
$json | Out-File -FilePath "C:\Users\USER\Documents\APP PARA CAMBIOS JK CONVERSOR\workflow_tasas_proveedores.json" -Encoding utf8
Write-Output ("JSON 'Tasas de Proveedores' generado. Longitud: " + $json.Length + " chars. Nodos: " + $nodes.Count)
