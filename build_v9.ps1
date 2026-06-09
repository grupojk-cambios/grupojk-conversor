$ErrorActionPreference = "Stop"

# ===================== CODIGO NODO PRINCIPAL (Code in JavaScript) =====================
$mainCode = @'
// === JK Remesas - Procesamiento de tasas (espejo de la app JK Conversor) ===
function parseCSV(text){
  const lineas = text.split(/\r?\n/).filter(l => l.trim().length>0);
  const parseLine = (linea)=>{ const row=[]; let inQ=false; let cur=''; for(const c of linea){ if(c==='"') inQ=!inQ; else if(c===',' && !inQ){ row.push(cur); cur=''; } else cur+=c; } row.push(cur); return row.map(s=>s.trim()); };
  return lineas.map(parseLine);
}
function num(s){ if(s===undefined||s===null||s==='') return 0; let v=String(s).replace(/\s/g,'').replace(',', '.'); const n=parseFloat(v); return isNaN(n)?0:n; }

const httpItem = $('Consultar Tasas').first();
const csv = (httpItem && httpItem.json && httpItem.json.data) ? String(httpItem.json.data) : '';

const APP_URL = 'https://grupojk-cambios.github.io/grupojk-conversor/';

// ====== LISTA DE MAYORISTAS (EDITAR AQUI) ======
// Numeros de WhatsApp mayoristas (solo digitos, con codigo de pais).
// Ejemplo: const MAYORISTAS = ['584121234567', '593961230380'];
const MAYORISTAS = [];
// ================================================

let jid = '';
try { jid = $('Webhook Evolution API').first().json.body.data.key.remoteJid || ''; } catch(e) { jid = ''; }
const senderDigits = String(jid).replace(/\D/g,'');
const esMayorista = MAYORISTAS.some(n => { const d=String(n).replace(/\D/g,''); return d && (senderDigits===d || senderDigits.endsWith(d)); });
const modo = esMayorista ? 'mayor' : 'detal';

if(!csv){
  return [{ json: { lista:[], modo, esMayorista, appUrl:APP_URL, hayEfectivoVe:false, totalPaises:0, error:'No se recibieron datos de tasas' } }];
}

const filas = parseCSV(csv);
const head = (filas[0]||[]).map(h=>String(h||'').toUpperCase().normalize('NFD').replace(/[\u0300-\u036f]/g,''));
const idx = {
  factorEUR: head.findIndex(h=>h.includes('FACTOR EUR')||h.includes('VALOR EUR')),
  factorUSDT: head.findIndex(h=>h.includes('FACTOR USDT')||h.includes('VALOR USDT')),
  cod: head.findIndex(h=>h.includes('CODIGO')||h.includes('BANCO')),
  moneda: head.findIndex(h=>h.includes('NOMBRE')||h.includes('MONEDA')),
  mEMayor: head.findIndex(h=>h.includes('MARGEN ENVIO MAYOR')),
  mRMayor: head.findIndex(h=>h.includes('MARGEN RECIBO MAYOR')),
};
const paises=[];
for(let i=1;i<filas.length;i++){
  const row=filas[i]; const nombre=(row[0]||'').trim(); if(!nombre) continue;
  const tE=num(row[1]); const mE=(row[2]!==undefined&&row[2]!=='')?num(row[2]):6;
  const tR=num(row[3]); const mR=(row[4]!==undefined&&row[4]!=='')?num(row[4]):6;
  if(tE===0 && tR===0) continue;
  const codigo = idx.cod!==-1 && row[idx.cod] ? row[idx.cod].toUpperCase() : nombre.substring(0,3).toUpperCase();
  paises.push({ nombre, codigo, moneda: idx.moneda!==-1 && row[idx.moneda] ? row[idx.moneda] : 'Divisa local', tasaProveedorEnvio:tE, margenEnvio:mE, tasaProveedorRecibo:tR, margenRecibo:mR, margenEnvioMayor: idx.mEMayor!==-1?num(row[idx.mEMayor]):0, margenReciboMayor: idx.mRMayor!==-1?num(row[idx.mRMayor]):0, factorEUR: idx.factorEUR!==-1?num(row[idx.factorEUR]):0, factorUSDT: idx.factorUSDT!==-1?num(row[idx.factorUSDT]):0 });
}

// Guardar datos crudos para la calculadora (mismo dato que el prompt)
try { const sd=$getWorkflowStaticData('global'); sd.paisesData = paises; } catch(e){}

function mEnv(p){ return modo==='mayor'&&p.margenEnvioMayor>0?p.margenEnvioMayor:(p.margenEnvio||0); }
function mRec(p){ return modo==='mayor'&&p.margenReciboMayor>0?p.margenReciboMayor:(p.margenRecibo||0); }
function tEnv(p){ const t=p.tasaProveedorEnvio||0; return t? t*(1-mEnv(p)/100):0; }
function tRec(p){ const t=p.tasaProveedorRecibo||0; return t? t*(1+mRec(p)/100):0; }
function esDolar(p){ const c=(p.codigo||'').toUpperCase(); const n=(p.nombre||'').toUpperCase(); return ['USD','USDT'].includes(c)||n.includes('USDT')||n.includes('ZELLE')||n.includes('EFECTIVO VEN'); }

const lista = paises
  .filter(p => !/^efectivo venezuela-/i.test(p.nombre))
  .map(p => ({ Pais:p.nombre, Codigo:p.codigo, Moneda:p.moneda, Envio: tEnv(p)? Number(tEnv(p).toFixed(2)):'N/D', Recibo: tRec(p)? Number(tRec(p).toFixed(2)):'N/D', EsDolar: esDolar(p) }));

const hayEfectivoVe = paises.some(p=>/^efectivo venezuela/i.test(p.nombre));

// ===== CUENTAS con ROTACION DIARIA (1 cuenta por pais por dia) =====
let cuentasCsv = '';
try { cuentasCsv = String($('Consultar Cuentas').first().json.data || ''); } catch(e){}
const cuentasTodas = [];
if (cuentasCsv) {
  const filasC = parseCSV(cuentasCsv);
  // Encabezado: Pais, Metodo, Disponible, Datos, Notas. El ORDEN de filas = orden de rotacion.
  for (let i=1; i<filasC.length; i++) {
    const row = filasC[i];
    const pais = (row[0]||'').trim();
    const datos = (row[3]||'').trim();
    if (!pais || !datos) continue;
    if (!/^s/i.test((row[2]||'').trim())) continue; // solo Disponible = Si
    cuentasTodas.push({ Pais: pais, Metodo: (row[1]||'').trim(), Datos: datos });
  }
}
// Agrupar por pais preservando el orden de filas
const porPais = {};
for (const c of cuentasTodas) {
  const k = c.Pais.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim();
  (porPais[k] = porPais[k] || []).push(c);
}
// Indice del dia segun hora de Ecuador (UTC-5): cambia a la medianoche de Ecuador
const diaIndex = Math.floor((Date.now() - 5*3600000) / 86400000);
const cuentas = [];
for (const k in porPais) {
  const arr = porPais[k];
  const idx = ((diaIndex % arr.length) + arr.length) % arr.length; // ciclico 0,1,2,...
  cuentas.push(arr[idx]);
}

return [{ json: { lista, modo, esMayorista, appUrl:APP_URL, hayEfectivoVe, totalPaises: paises.length, cuentas, hayCuentas: cuentas.length>0, diaIndex, error: paises.length? null : 'Lista vacia' } }];
'@

# ===================== CODIGO DE LA CALCULADORA (Code Tool) =====================
$toolCode = @'
// === Calculadora de remesas JK (motor identico a la app) ===
function _safe(fn){ try { return fn(); } catch(e){ return undefined; } }

let _a = {};
const _q = _safe(()=>query);
if (_q && typeof _q === 'object') _a = _q;
const inOrigen   = (_a.pais_origen  !== undefined) ? _a.pais_origen  : _safe(()=>pais_origen);
const inDestino  = (_a.pais_destino !== undefined) ? _a.pais_destino : _safe(()=>pais_destino);
const inMonto    = (_a.monto        !== undefined) ? _a.monto        : _safe(()=>monto);
const inDir      = (_a.direccion    !== undefined) ? _a.direccion    : _safe(()=>direccion);
const inModo     = (_a.modo         !== undefined) ? _a.modo         : _safe(()=>modo);

const origenQ  = String(inOrigen||'').trim();
const destinoQ = String(inDestino||'').trim();
const montoN   = Number(inMonto)||0;
const direccion= (String(inDir||'directa').toLowerCase()==='inversa')?'inversa':'directa';
const modoN    = (String(inModo||'detal').toLowerCase()==='mayor')?'mayor':'detal';

function parseCSV(text){
  const lineas = text.split(/\r?\n/).filter(l => l.trim().length>0);
  const parseLine = (linea)=>{ const row=[]; let inQ=false; let cur=''; for(const c of linea){ if(c==='"') inQ=!inQ; else if(c===',' && !inQ){ row.push(cur); cur=''; } else cur+=c; } row.push(cur); return row.map(s=>s.trim()); };
  return lineas.map(parseLine);
}
function num(s){ if(s===undefined||s===null||s==='') return 0; let v=String(s).replace(/\s/g,'').replace(',', '.'); const n=parseFloat(v); return isNaN(n)?0:n; }
function norm(s){ return (s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9 ]/g,'').trim(); }
function construirPaises(text){
  const filas = parseCSV(text); if(!filas.length) return [];
  const head=(filas[0]||[]).map(h=>String(h||'').toUpperCase().normalize('NFD').replace(/[\u0300-\u036f]/g,''));
  const idx={ factorEUR:head.findIndex(h=>h.includes('FACTOR EUR')||h.includes('VALOR EUR')), factorUSDT:head.findIndex(h=>h.includes('FACTOR USDT')||h.includes('VALOR USDT')), cod:head.findIndex(h=>h.includes('CODIGO')||h.includes('BANCO')), moneda:head.findIndex(h=>h.includes('NOMBRE')||h.includes('MONEDA')), mEMayor:head.findIndex(h=>h.includes('MARGEN ENVIO MAYOR')), mRMayor:head.findIndex(h=>h.includes('MARGEN RECIBO MAYOR')) };
  const paises=[];
  for(let i=1;i<filas.length;i++){ const row=filas[i]; const nombre=(row[0]||'').trim(); if(!nombre) continue; const tE=num(row[1]); const mE=(row[2]!==undefined&&row[2]!=='')?num(row[2]):6; const tR=num(row[3]); const mR=(row[4]!==undefined&&row[4]!=='')?num(row[4]):6; if(tE===0&&tR===0) continue; const codigo=idx.cod!==-1&&row[idx.cod]?row[idx.cod].toUpperCase():nombre.substring(0,3).toUpperCase(); paises.push({ nombre, codigo, moneda: idx.moneda!==-1&&row[idx.moneda]?row[idx.moneda]:'Divisa local', tasaProveedorEnvio:tE, margenEnvio:mE, tasaProveedorRecibo:tR, margenRecibo:mR, margenEnvioMayor: idx.mEMayor!==-1?num(row[idx.mEMayor]):0, margenReciboMayor: idx.mRMayor!==-1?num(row[idx.mRMayor]):0, factorEUR: idx.factorEUR!==-1?num(row[idx.factorEUR]):0, factorUSDT: idx.factorUSDT!==-1?num(row[idx.factorUSDT]):0 }); }
  return paises;
}
function isCajaDolar(p){ const c=(p.codigo||'').toUpperCase(); const n=(p.nombre||'').toUpperCase(); return ['USD','USDT'].includes(c)||n.includes('USDT')||n.includes('ZELLE')||n.includes('EFECTIVO VEN'); }
function mEnv(p,modo){ return modo==='mayor'&&p.margenEnvioMayor>0?p.margenEnvioMayor:(p.margenEnvio||0); }
function mRec(p,modo){ return modo==='mayor'&&p.margenReciboMayor>0?p.margenReciboMayor:(p.margenRecibo||0); }
function tEnv(p,modo){ const t=p.tasaProveedorEnvio||0; return t? t*(1-mEnv(p,modo)/100):0; }
function tRec(p,modo){ const t=p.tasaProveedorRecibo||0; return t? t*(1+mRec(p,modo)/100):0; }
function obtenerTasasProcesadas(origen,destino,modo){
  let tasaOrigenParaDolares=tRec(origen,modo);
  let tasaDestinoDesdeDolares=tEnv(destino,modo);
  const BASES=['EUR','USDT','GBP','EU']; const FUERTES=['EUR','GBP','EU'];
  const oc=(origen.codigo||'').toUpperCase(); const dc=(destino.codigo||'').toUpperCase();
  let factorAplicado=false;
  if(BASES.includes(oc) && !isCajaDolar(destino) && !BASES.includes(dc)){ const f=parseFloat(destino['factor'+oc]); if(f>0&&!isNaN(f)){ tasaOrigenParaDolares=1/f; factorAplicado=true; } }
  else if(!BASES.includes(oc) && !isCajaDolar(origen) && BASES.includes(dc)){ const f=parseFloat(origen['factor'+dc]); if(f>0&&!isNaN(f)){ tasaDestinoDesdeDolares=1/f; factorAplicado=true; } }
  if(!factorAplicado){
    const oF=FUERTES.includes(oc), dF=FUERTES.includes(dc), oD=isCajaDolar(origen), dD=isCajaDolar(destino);
    if(oF||dF){
      if(oF && !oD) tasaOrigenParaDolares=1/Math.max(tasaOrigenParaDolares,0.001);
      if(oF && dD) tasaDestinoDesdeDolares=1;
      if(oD && dF) tasaOrigenParaDolares=1;
    } else {
      if(oD && !dD){ const mO=mRec(origen,modo), mD=mEnv(destino,modo); tasaOrigenParaDolares=1; const tBaseD=destino.tasaProveedorEnvio||0; tasaDestinoDesdeDolares=tBaseD*(1-(mO+mD)/100); }
      else if(oD && dD){ tasaOrigenParaDolares=1; const tBaseD=destino.tasaProveedorEnvio||0; const mD=mEnv(destino,modo); tasaDestinoDesdeDolares=tBaseD*(1-mD/100); }
      else if(!oD && dD){ const mO=mRec(origen,modo), mD=mEnv(destino,modo); const tBaseO=origen.tasaProveedorRecibo||0; tasaOrigenParaDolares=tBaseO*(1+(mO+mD)/100); tasaDestinoDesdeDolares=1; }
    }
  }
  if(tasaOrigenParaDolares===0) tasaOrigenParaDolares=1;
  return { tasaOrigenParaDolares, tasaDestinoDesdeDolares };
}
function calcularConversion(origen,destino,monto,modo){ const r=obtenerTasasProcesadas(origen,destino,modo); return (monto/r.tasaOrigenParaDolares)*r.tasaDestinoDesdeDolares; }
function calcularConversionInversa(origen,destino,montoRecibir,modo){ const r=obtenerTasasProcesadas(origen,destino,modo); if(r.tasaDestinoDesdeDolares===0) return 0; const tBaseD=destino.tasaProveedorEnvio||0; if(tBaseD>0 && r.tasaDestinoDesdeDolares<tBaseD){ const md=(tBaseD-r.tasaDestinoDesdeDolares)/tBaseD; return (montoRecibir/tBaseD)*(1+md)*r.tasaOrigenParaDolares; } return (montoRecibir/r.tasaDestinoDesdeDolares)*r.tasaOrigenParaDolares; }
function findPais(paises,q){ const nq=norm(q); if(!nq) return null; let p=paises.find(x=>norm(x.nombre)===nq); if(p) return p; const alias={ euros:'europa', eur:'europa', tether:'usdt' }; if(alias[nq]){ p=paises.find(x=>norm(x.nombre)===norm(alias[nq])); if(p) return p; } p=paises.find(x=>norm(x.nombre).includes(nq)||nq.includes(norm(x.nombre))); return p||null; }

function compute(paises){
  if(!paises || !paises.length) return JSON.stringify({ ok:false, error:'No pude cargar las tasas en este momento. Pide disculpas y di que un asesor ayudara.' });
  const o = findPais(paises, origenQ); const d = findPais(paises, destinoQ);
  if(!o) return JSON.stringify({ ok:false, error:'No encontre el pais/moneda de ORIGEN: '+origenQ+'. Pide al cliente que lo aclare.' });
  if(!d) return JSON.stringify({ ok:false, error:'No encontre el pais/moneda de DESTINO: '+destinoQ+'. Pide al cliente que lo aclare.' });
  if(!(montoN>0)) return JSON.stringify({ ok:false, error:'Falta el monto a convertir o no es valido.' });
  const cross = calcularConversion(o,d,1,modoN);
  let resultado, explicacion;
  if(direccion==='inversa'){
    resultado = calcularConversionInversa(o,d,montoN,modoN);
    explicacion = 'Para que el destinatario reciba '+montoN+' '+d.codigo+' en '+d.nombre+', el cliente debe enviar aprox. '+resultado.toFixed(2)+' '+o.codigo+' desde '+o.nombre+'.';
  } else {
    resultado = calcularConversion(o,d,montoN,modoN);
    explicacion = 'Enviando '+montoN+' '+o.codigo+' ('+o.nombre+') el destinatario recibe '+resultado.toFixed(2)+' '+d.codigo+' ('+d.nombre+').';
  }
  return JSON.stringify({ ok:true, modo:modoN, direccion, origen:o.nombre, monedaOrigen:o.moneda, codigoOrigen:o.codigo, destino:d.nombre, monedaDestino:d.moneda, codigoDestino:d.codigo, monto:montoN, resultado:Number(resultado.toFixed(2)), tasaCruzada:Number(cross.toFixed(6)), explicacion });
}

// 1) Camino rapido y seguro: datos ya cargados por el nodo principal (sincrono)
let _data = _safe(()=>{ if(typeof $getWorkflowStaticData==='function'){ const sd=$getWorkflowStaticData('global'); if(sd && Array.isArray(sd.paisesData) && sd.paisesData.length) return sd.paisesData; } return undefined; });
if(_data && _data.length) return compute(_data);

// 2) Respaldo: descargar el CSV (asincrono) solo si no hubo datos en memoria
if(typeof fetch !== 'function') return JSON.stringify({ ok:false, error:'No pude acceder a las tasas. Pide disculpas y di que un asesor ayudara.' });
const _url='https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv';
return (async () => { try { const res = await fetch(_url + '&nocache=' + Date.now()); const text = await res.text(); return compute(construirPaises(text)); } catch(e){ return JSON.stringify({ ok:false, error:'No pude descargar las tasas: '+e.message }); } })();
'@

# ===================== INPUT SCHEMA DE LA CALCULADORA =====================
$inputSchema = @'
{
  "type": "object",
  "properties": {
    "pais_origen": { "type": "string", "description": "Pais o moneda DESDE donde sale el dinero, tal como lo dijo el cliente (ej: Chile, Zelle, USDT, Europa, Colombia)." },
    "pais_destino": { "type": "string", "description": "Pais o moneda HACIA donde llega el dinero (ej: Colombia, Venezuela, Chile)." },
    "monto": { "type": "number", "description": "Cantidad numerica a convertir." },
    "direccion": { "type": "string", "enum": ["directa", "inversa"], "description": "directa = el cliente ENVIA 'monto' en la moneda de origen y quiere saber cuanto llega. inversa = el cliente quiere que LLEGUEN 'monto' a destino y saber cuanto debe enviar." },
    "modo": { "type": "string", "enum": ["detal", "mayor"], "description": "Tipo de tarifa. Usa SIEMPRE el valor indicado en el system prompt para este cliente. Por defecto detal." }
  },
  "required": ["pais_origen", "pais_destino", "monto"]
}
'@

# ===================== SYSTEM MESSAGE DEL AGENTE =====================
$systemMsg = @'
=Eres asistente de *JK Remesas* por WhatsApp. RESPONDE EN MAXIMO 2-3 LINEAS, directo y humano. 1-2 emojis maximo. NO repitas frases de cortesia.

El cliente puede enviarte VARIOS mensajes juntos (separados por saltos de linea). Leelos todos y responde UNA sola vez, corto.

Tarifa de este cliente: {{ $node["Code in JavaScript"].json.modo }} (detal=publico, mayor=mayorista). Nunca menciones lo mayorista a un cliente detal.

Tasas de hoy (Envio/Recibo ya con margen; "N/D" = no disponible):
{{ JSON.stringify($node["Code in JavaScript"].json.lista) }}

CUENTAS para pagar/depositar (solo estas existen; usa el campo "Datos" tal cual al enviarla):
{{ JSON.stringify($node["Code in JavaScript"].json.cuentas) }}

REGLAS:
- MONTO a convertir, cruce entre paises, o dolares/USDT/euros (EsDolar:true): USA la herramienta calculadora_remesas (pais_origen, pais_destino, monto, direccion "directa"/"inversa", modo "{{ $node["Code in JavaScript"].json.modo }}"). NUNCA calcules tu; da el numero que devuelve la herramienta.
- Solo piden tasa de un pais sin monto: di Envio o Recibo en 1 linea. Si no sabes si quiere enviar o recibir, preguntalo en pocas palabras.
- Disponibilidad: si una moneda esta en "N/D" o no aparece: "Por ahora no manejamos ese servicio." No inventes.
- Preguntan por CUENTA / datos para pagar / donde deposito / a donde transfiero: revisa la lista CUENTAS de abajo. Si hay una para ese pais/metodo, envia su campo "Datos" tal cual (puedes elegir la mas adecuada o preguntar el metodo si hay varias). Si NO hay ninguna para ese pais: "Por ahora no tengo esa cuenta a la mano, un asesor te la pasa enseguida."
- Fuera de tema: "Solo remesas de JK."
- Quejas o problema con un giro: "Un asesor te contacta enseguida."
- Nunca pidas claves, cuentas ni documentos. No des consejo financiero.
- Ver todas las tasas: {{ $node["Code in JavaScript"].json.appUrl }}
{{ $node["Code in JavaScript"].json.hayEfectivoVe ? '- Efectivo Venezuela: pregunta estado/ciudad.' : '' }}

PROHIBIDO repetir en cada mensaje cosas como "estoy aqui", "disponible", "para ayudarte", "cualquier consulta", "no dudes en". Responde lo justo y para. Suena como una persona, no como un bot.
'@

# ===================== CODIGO: PREP DEBOUNCE =====================
$prepCode = @'
// Prepara los datos para el debounce con Redis. El texto ya viene unificado (de texto directo o de audio transcrito).
let jid='', texto='';
try { jid = $('Webhook Evolution API').first().json.body.data.key.remoteJid || ''; } catch(e){}
try { texto = $json.texto || ''; } catch(e){}
const miTs = String(Date.now()) + '-' + Math.random().toString(36).slice(2,8);
return [{ json: { jid, texto: texto || '', miTs, keyBuf: 'buf:'+jid, keyTok: 'tok:'+jid } }];
'@

# ===================== CODIGO: TEXTO DIRECTO (mensajes de texto) =====================
$textoDirectoCode = @'
// Extrae el texto de un mensaje normal (texto, respuesta citada, o pie de imagen/video).
let t='';
try {
  const m = $json.body.data.message || {};
  t = m.conversation
    || (m.extendedTextMessage && m.extendedTextMessage.text)
    || (m.imageMessage && m.imageMessage.caption)
    || (m.videoMessage && m.videoMessage.caption)
    || '';
} catch(e){}
return [{ json: { texto: t } }];
'@

# ===================== CODIGO: AUDIO A BINARIO =====================
$toBinarioCode = @'
// Convierte el base64 del audio (de Evolution) en un archivo binario para Whisper.
const b64 = $json.base64;
if(!b64) return [{ json: { texto: '' } }];
return [{ json: { mimetype: $json.mimetype || '' }, binary: { data: { data: b64, mimeType: 'audio/ogg', fileName: 'audio.ogg' } } }];
'@

# ===================== CODIGO: TEXTO DE AUDIO (transcripcion) =====================
$textoAudioCode = @'
// Toma la transcripcion de Whisper como texto del mensaje.
let t='';
try { t = $('Transcribir Audio').item.json.text || ''; } catch(e){}
t = String(t).trim();
if(!t) t = 'El cliente envio una nota de voz que no se pudo entender. Pidele amablemente que la repita o escriba.';
return [{ json: { texto: t } }];
'@

# ===================== CODIGO: FILTRAR ULTIMO =====================
$filtrarCode = @'
// Tras esperar 30s: solo continua si mi token sigue siendo el ultimo en Redis.
const miTs = $('Prep Debounce').item.json.miTs;
let actual = $json.tokenActual;
if (actual === undefined || actual === null) { try { actual = $('Redis Leer Token').item.json.tokenActual; } catch(e){} }
if (String(actual) !== String(miTs)) {
  return []; // llego un mensaje mas nuevo: esta ejecucion NO responde
}
return [{ json: { jid: $('Prep Debounce').item.json.jid } }];
'@

# ===================== CODIGO: COMBINAR MENSAJES =====================
$combinarCode = @'
// Junta todos los mensajes leidos de Redis en un solo texto.
let arr = [];
try { arr = $('Redis Leer Mensajes').item.json.mensajes; } catch(e){}
if (!Array.isArray(arr)) arr = (arr === undefined || arr === null) ? [] : [arr];
const combinado = arr.join('\n').trim() || '(sin texto)';
return [{ json: { mensajeCombinado: combinado } }];
'@

# ===================== CODIGO: DETECTAR ASESOR (alerta) =====================
$detectarCode = @'
// Si la respuesta del bot indica que se necesita un asesor, arma la alerta. Si no, no hace nada.
const out = String($json.output || '');
if (!/asesor/i.test(out)) { return []; } // no es escalamiento -> no notificar
let jid = '';
try { jid = $('Webhook Evolution API').first().json.body.data.key.remoteJid || ''; } catch(e){}
const numero = String(jid).replace(/\D/g,'');
let msg = '';
try { msg = $('Combinar').item.json.mensajeCombinado || ''; } catch(e){}
const texto = '*Cliente necesita atencion*\n\nNumero: +' + numero + '\nhttps://wa.me/' + numero + '\n\nCliente escribio:\n' + msg + '\n\nBot respondio:\n' + out;
return [{ json: { alerta: texto, numeroCliente: numero } }];
'@

# ===================== CONSTRUCCION DEL WORKFLOW =====================
$redisCred = @{ redis = @{ id = 'SKkvpS5A65SOcmJs'; name = 'Redis memoria para Cambios JK' } }
$nodes = @(
  [ordered]@{
    parameters = @{ httpMethod = 'POST'; path = 'webhook-whatsapp'; options = @{} }
    id = '75799f35-f979-4b45-9dab-861127bd5f9d'; name = 'Webhook Evolution API'; type = 'n8n-nodes-base.webhook'; typeVersion = 1; position = @(-380,128); webhookId = 'a9ba9382-d166-495a-8309-e13a9d839b06'
  },
  [ordered]@{
    parameters = @{ conditions = @{ boolean = @( @{ value1 = '={{ $json.body.data.key.fromMe }}'; value2 = '={{false}}' } ) } }
    id = '4c9f6989-54ed-4990-89d5-283dd59b7ce2'; name = 'Es mensaje de cliente?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(-200,128)
  },
  [ordered]@{
    parameters = @{ jsCode = $prepCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(140,128); id = 'c1a2b3c4-1111-4a11-9111-prep00000001'; name = 'Prep Debounce'
  },
  [ordered]@{
    parameters = @{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'aud-cond-1'; leftValue = '={{ $json.body.data.messageType }}'; rightValue = 'audioMessage'; operator = @{ type = 'string'; operation = 'equals' } } ); combinator = 'and' } }
    id = 'd0a1b2c3-e4f5-4060-9788-esaudio00001'; name = 'Es Audio?'; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(-60,60)
  },
  [ordered]@{
    parameters = @{ jsCode = $textoDirectoCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(-60,220); id = 'e1f2a3b4-c5d6-4071-9899-txtdirecto01'; name = 'Texto Directo'
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/chat/getBase64FromMediaMessage/bot-JK-prueba-operador1'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "message": { "key": { "id": "{{ $json.body.data.key.id }}" } }, "convertToMp4": false }'; options = @{} }
    id = 'f2a3b4c5-d6e7-4082-9900-getbase64001'; name = 'Descargar Audio'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(120,-60)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 2000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = 'FKESFx8q5vHdJoM4'; name = 'Evolution apikey header para operador 1' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $toBinarioCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(300,-60); id = 'a3b4c5d6-e7f8-4093-9a11-tobinario001'; name = 'Audio a Binario'
  },
  [ordered]@{
    parameters = @{ resource = 'audio'; operation = 'transcribe'; binaryPropertyName = 'data'; options = @{ language = 'es' } }
    id = 'b4c5d6e7-f8a9-4004-9b22-transcribe01'; name = 'Transcribir Audio'; type = '@n8n/n8n-nodes-langchain.openAi'; typeVersion = 1.8; position = @(480,-60)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 2000; alwaysOutputData = $true
    credentials = @{ openAiApi = @{ id = '44lRGIyEnSk1lMc5'; name = 'cambios jk para n8n' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $textoAudioCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(660,-60); id = 'c5d6e7f8-a9b0-4015-9c33-txtaudio0001'; name = 'Texto de Audio'
  },
  [ordered]@{
    parameters = @{ operation = 'push'; list = "={{ `$('Prep Debounce').item.json.keyBuf }}"; messageData = "={{ `$('Prep Debounce').item.json.texto }}"; tail = $true }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(160,128); id = 'c2a2b3c4-2222-4a22-9222-rpush0000001'; name = 'Redis Guardar Msg'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = "={{ `$('Prep Debounce').item.json.keyTok }}"; value = "={{ `$('Prep Debounce').item.json.miTs }}"; keyType = 'string'; expire = $true; ttl = 120 }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(340,128); id = 'c3a2b3c4-3333-4a33-9333-rset00000001'; name = 'Redis Marcar Token'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ amount = 30; unit = 'seconds' }
    type = 'n8n-nodes-base.wait'; typeVersion = 1.1; position = @(520,128); id = 'd2b3c4d5-4444-4a44-9444-wait00000001'; name = 'Esperar 30s'; webhookId = 'e7c1a2b3-5555-4a55-9555-waithook0001'
  },
  [ordered]@{
    parameters = @{ operation = 'get'; key = "={{ `$('Prep Debounce').item.json.keyTok }}"; propertyName = 'tokenActual'; keyType = 'string'; options = @{} }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(700,128); id = 'c4a2b3c4-6666-4a66-9666-rget00000001'; name = 'Redis Leer Token'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $filtrarCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(880,128); id = 'f3c4d5e6-7777-4a77-9777-filtrar00001'; name = 'Filtrar Ultimo'
  },
  [ordered]@{
    parameters = @{ operation = 'get'; key = "={{ `$('Prep Debounce').item.json.keyBuf }}"; propertyName = 'mensajes'; keyType = 'list'; options = @{} }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1060,128); id = 'c5a2b3c4-8888-4a88-9888-rgetlist0001'; name = 'Redis Leer Mensajes'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ operation = 'delete'; key = "={{ `$('Prep Debounce').item.json.keyBuf }}" }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1240,128); id = 'c6a2b3c4-9999-4a99-9999-rdel00000001'; name = 'Redis Borrar Buffer'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $combinarCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1420,128); id = 'a7b8c9d0-aaaa-4aaa-9aaa-combinar0001'; name = 'Combinar'
  },
  [ordered]@{
    parameters = @{ url = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv'; options = @{} }
    id = 'd117ce37-c8f2-4d1d-8c17-2e2ac16dcc5a'; name = 'Consultar Tasas'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1600,128)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 1500; alwaysOutputData = $true
  },
  [ordered]@{
    parameters = @{ url = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?gid=908170655&single=true&output=csv'; options = @{} }
    id = 'e2f3a4b5-c6d7-4e88-9f00-cuentas00001'; name = 'Consultar Cuentas'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1690,300)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 1500; alwaysOutputData = $true
  },
  [ordered]@{
    parameters = @{ jsCode = $mainCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1860,128); id = '6ac06fc7-1afb-49ab-893c-e2f2b5f8b995'; name = 'Code in JavaScript'
  },
  [ordered]@{
    parameters = @{ promptType = 'define'; text = "={{ `$('Combinar').item.json.mensajeCombinado }}"; options = @{ systemMessage = $systemMsg } }
    type = '@n8n/n8n-nodes-langchain.agent'; typeVersion = 3.1; position = @(1960,128); id = '2ac354a3-fe77-4708-80c5-b238454cfdd6'; name = 'AI Agent'; executeOnce = $true
  },
  [ordered]@{
    parameters = @{ resource = 'messages-api'; instanceName = 'bot-JK-prueba-operador1'; remoteJid = "={{ `$('Webhook Evolution API').item.json.body.data.key.remoteJid }}"; messageText = '={{ $json.output }}'; options_message = @{} }
    type = 'n8n-nodes-evolution-api.evolutionApi'; typeVersion = 1; position = @(2320,128); id = '02d01e05-a9f8-4caa-a02e-37a660aa662c'; name = 'Enviar texto a WhatsApp'
    retryOnFail = $true; maxTries = 4; waitBetweenTries = 5000
    credentials = @{ evolutionApi = @{ id = 'iUIvc9Sd8diFJaGU'; name = 'Evolution PARA n8n cambios JK' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $detectarCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2200,320); id = 'aa11bb22-cc33-4d44-9e55-detasesor001'; name = 'Detectar Asesor'
  },
  [ordered]@{
    parameters = @{ resource = 'messages-api'; instanceName = 'bot-JK-prueba-operador1'; remoteJid = '593961230380@s.whatsapp.net'; messageText = '={{ $json.alerta }}'; options_message = @{} }
    type = 'n8n-nodes-evolution-api.evolutionApi'; typeVersion = 1; position = @(2420,320); id = 'bb22cc33-dd44-4e55-9f66-notasesor001'; name = 'Notificar Asesor'
    retryOnFail = $true; maxTries = 4; waitBetweenTries = 5000
    credentials = @{ evolutionApi = @{ id = 'iUIvc9Sd8diFJaGU'; name = 'Evolution PARA n8n cambios JK' } }
  },
  [ordered]@{
    parameters = @{ model = 'gpt-4o-mini'; options = @{ temperature = 0.3 } }
    id = '073e3eb0-3806-4654-8016-ed7207a45715'; name = 'OpenAI Model'; type = '@n8n/n8n-nodes-langchain.lmChatOpenAi'; typeVersion = 1; position = @(1820,400)
    credentials = @{ openAiApi = @{ id = '44lRGIyEnSk1lMc5'; name = 'cambios jk para n8n' } }
  },
  [ordered]@{
    parameters = @{ sessionIdType = 'customKey'; sessionKey = "={{ `$('Webhook Evolution API').item.json.body.data.key.remoteJid }}"; contextWindowLength = 15 }
    id = 'bff6d1ec-1a12-45f2-a96a-327e1edd3f0e'; name = 'Memoria de Chat'; type = '@n8n/n8n-nodes-langchain.memoryBufferWindow'; typeVersion = 1.3; position = @(2040,400)
  },
  [ordered]@{
    parameters = @{ name = 'calculadora_remesas'; description = 'Convierte montos de dinero entre paises/monedas con las tasas oficiales del dia de JK Remesas. Usala para cualquier conversion de monto, para cruces entre dos paises, o cuando intervengan dolares, USDT o euros. Devuelve el resultado exacto.'; language = 'javaScript'; jsCode = $toolCode; specifyInputSchema = $true; schemaType = 'manual'; inputSchema = $inputSchema }
    type = '@n8n/n8n-nodes-langchain.toolCode'; typeVersion = 1.1; position = @(2200,400); id = 'b1f2c3d4-0000-4a00-9000-aabbccddeeff'; name = 'Calculadora de Conversion'
  }
)

$connections = [ordered]@{
  'Webhook Evolution API'  = @{ main = @( ,@( @{ node='Es mensaje de cliente?'; type='main'; index=0 } ) ) }
  'Es mensaje de cliente?' = @{ main = @( ,@( @{ node='Es Audio?'; type='main'; index=0 } ) ) }
  'Es Audio?'              = @{ main = (@( ,@( @{ node='Descargar Audio'; type='main'; index=0 } ) ) + @( ,@( @{ node='Texto Directo'; type='main'; index=0 } ) )) }
  'Descargar Audio'        = @{ main = @( ,@( @{ node='Audio a Binario'; type='main'; index=0 } ) ) }
  'Audio a Binario'        = @{ main = @( ,@( @{ node='Transcribir Audio'; type='main'; index=0 } ) ) }
  'Transcribir Audio'      = @{ main = @( ,@( @{ node='Texto de Audio'; type='main'; index=0 } ) ) }
  'Texto de Audio'         = @{ main = @( ,@( @{ node='Prep Debounce'; type='main'; index=0 } ) ) }
  'Texto Directo'          = @{ main = @( ,@( @{ node='Prep Debounce'; type='main'; index=0 } ) ) }
  'Prep Debounce'          = @{ main = @( ,@( @{ node='Redis Guardar Msg'; type='main'; index=0 } ) ) }
  'Redis Guardar Msg'      = @{ main = @( ,@( @{ node='Redis Marcar Token'; type='main'; index=0 } ) ) }
  'Redis Marcar Token'     = @{ main = @( ,@( @{ node='Esperar 30s'; type='main'; index=0 } ) ) }
  'Esperar 30s'            = @{ main = @( ,@( @{ node='Redis Leer Token'; type='main'; index=0 } ) ) }
  'Redis Leer Token'       = @{ main = @( ,@( @{ node='Filtrar Ultimo'; type='main'; index=0 } ) ) }
  'Filtrar Ultimo'         = @{ main = @( ,@( @{ node='Redis Leer Mensajes'; type='main'; index=0 } ) ) }
  'Redis Leer Mensajes'    = @{ main = @( ,@( @{ node='Redis Borrar Buffer'; type='main'; index=0 } ) ) }
  'Redis Borrar Buffer'    = @{ main = @( ,@( @{ node='Combinar'; type='main'; index=0 } ) ) }
  'Combinar'               = @{ main = @( ,@( @{ node='Consultar Tasas'; type='main'; index=0 } ) ) }
  'Consultar Tasas'        = @{ main = @( ,@( @{ node='Consultar Cuentas'; type='main'; index=0 } ) ) }
  'Consultar Cuentas'      = @{ main = @( ,@( @{ node='Code in JavaScript'; type='main'; index=0 } ) ) }
  'Code in JavaScript'     = @{ main = @( ,@( @{ node='AI Agent'; type='main'; index=0 } ) ) }
  'OpenAI Model'           = @{ ai_languageModel = @( ,@( @{ node='AI Agent'; type='ai_languageModel'; index=0 } ) ) }
  'Memoria de Chat'        = @{ ai_memory = @( ,@( @{ node='AI Agent'; type='ai_memory'; index=0 } ) ) }
  'Calculadora de Conversion' = @{ ai_tool = @( ,@( @{ node='AI Agent'; type='ai_tool'; index=0 } ) ) }
  'AI Agent'               = @{ main = @( ,@( @{ node='Enviar texto a WhatsApp'; type='main'; index=0 }, @{ node='Detectar Asesor'; type='main'; index=0 } ) ) }
  'Detectar Asesor'        = @{ main = @( ,@( @{ node='Notificar Asesor'; type='main'; index=0 } ) ) }
}

$body = [ordered]@{ name = 'Bot WhatsApp JK Remesas - V2 (Mejorado)'; nodes = $nodes; connections = $connections; settings = @{ executionOrder = 'v1' } }

$json = $body | ConvertTo-Json -Depth 40
$json | Out-File -FilePath "C:\Users\USER\Documents\APP PARA CAMBIOS JK CONVERSOR\workflow_bot_whatsapp_v9.json" -Encoding utf8
Write-Output ("JSON v9 generado. Longitud: " + $json.Length + " chars. Nodos: " + $nodes.Count)
