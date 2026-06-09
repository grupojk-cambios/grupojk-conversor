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

return [{ json: { lista, modo, esMayorista, appUrl:APP_URL, hayEfectivoVe, totalPaises: paises.length, error: paises.length? null : 'Lista vacia' } }];
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

REGLAS:
- MONTO a convertir, cruce entre paises, o dolares/USDT/euros (EsDolar:true): USA la herramienta calculadora_remesas (pais_origen, pais_destino, monto, direccion "directa"/"inversa", modo "{{ $node["Code in JavaScript"].json.modo }}"). NUNCA calcules tu; da el numero que devuelve la herramienta.
- Solo piden tasa de un pais sin monto: di Envio o Recibo en 1 linea. Si no sabes si quiere enviar o recibir, preguntalo en pocas palabras.
- Disponibilidad: si una moneda esta en "N/D" o no aparece: "Por ahora no manejamos ese servicio." No inventes.
- Preguntan por CUENTA / datos para pagar / donde deposito: "Te paso los datos de la cuenta en un momento." (Aun no tienes las cuentas, solo confirma que se las pasas.)
- Fuera de tema: "Solo remesas de JK."
- Quejas o problema con un giro: "Un asesor te contacta enseguida."
- Nunca pidas claves, cuentas ni documentos. No des consejo financiero.
- Ver todas las tasas: {{ $node["Code in JavaScript"].json.appUrl }}
{{ $node["Code in JavaScript"].json.hayEfectivoVe ? '- Efectivo Venezuela: pregunta estado/ciudad.' : '' }}

PROHIBIDO repetir en cada mensaje cosas como "estoy aqui", "disponible", "para ayudarte", "cualquier consulta", "no dudes en". Responde lo justo y para. Suena como una persona, no como un bot.
'@

# ===================== CODIGO: ACUMULAR MENSAJES (debounce) =====================
$acumularCode = @'
// Acumula los mensajes del cliente en un buffer (por numero) para agruparlos antes de responder.
let jid='', texto='';
try { jid = $('Webhook Evolution API').first().json.body.data.key.remoteJid || ''; } catch(e){}
try { texto = $('Webhook Evolution API').first().json.body.data.message.conversation || ''; } catch(e){}
const ahora = Date.now();
const sd = $getWorkflowStaticData('global');
sd.buffers = sd.buffers || {};
if(!sd.buffers[jid]) sd.buffers[jid] = { mensajes: [], ultimoTs: 0 };
if(texto) sd.buffers[jid].mensajes.push(texto);
sd.buffers[jid].ultimoTs = ahora;
return [{ json: { jid, miTs: ahora } }];
'@

# ===================== CODIGO: FILTRAR ULTIMO (debounce) =====================
$filtrarCode = @'
// Tras esperar 30s: solo continua si NO llego un mensaje mas nuevo. Junta todos los mensajes en uno.
const jid = $json.jid;
const miTs = $json.miTs;
const sd = $getWorkflowStaticData('global');
sd.buffers = sd.buffers || {};
const buf = sd.buffers[jid];
if(!buf || buf.ultimoTs !== miTs){
  return []; // llego un mensaje mas nuevo: esta ejecucion NO responde (lo hara la mas reciente)
}
const combinado = (buf.mensajes || []).join('\n').trim() || '(sin texto)';
delete sd.buffers[jid];
return [{ json: { mensajeCombinado: combinado, jid } }];
'@

# ===================== CONSTRUCCION DEL WORKFLOW =====================
$nodes = @(
  [ordered]@{
    parameters = @{ conditions = @{ boolean = @( @{ value1 = '={{ $json.body.data.key.fromMe }}'; value2 = '={{false}}' } ) } }
    id = '4c9f6989-54ed-4990-89d5-283dd59b7ce2'; name = 'Es mensaje de cliente?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(48,144)
  },
  [ordered]@{
    parameters = @{ url = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv'; options = @{} }
    id = 'd117ce37-c8f2-4d1d-8c17-2e2ac16dcc5a'; name = 'Consultar Tasas'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(304,128)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 1500; alwaysOutputData = $true
  },
  [ordered]@{
    parameters = @{ model = 'gpt-4o-mini'; options = @{ temperature = 0.3 } }
    id = '073e3eb0-3806-4654-8016-ed7207a45715'; name = 'OpenAI Model'; type = '@n8n/n8n-nodes-langchain.lmChatOpenAi'; typeVersion = 1; position = @(560,416)
    credentials = @{ openAiApi = @{ id = '44lRGIyEnSk1lMc5'; name = 'cambios jk para n8n' } }
  },
  [ordered]@{
    parameters = @{ sessionIdType = 'customKey'; sessionKey = "={{ `$('Webhook Evolution API').item.json.body.data.key.remoteJid }}"; contextWindowLength = 15 }
    id = 'bff6d1ec-1a12-45f2-a96a-327e1edd3f0e'; name = 'Memoria de Chat'; type = '@n8n/n8n-nodes-langchain.memoryBufferWindow'; typeVersion = 1.3; position = @(880,400)
  },
  [ordered]@{
    parameters = @{ promptType = 'define'; text = '={{ $item(0).$node["Filtrar Ultimo"].json.mensajeCombinado }}'; options = @{ systemMessage = $systemMsg } }
    type = '@n8n/n8n-nodes-langchain.agent'; typeVersion = 3.1; position = @(752,128); id = '2ac354a3-fe77-4708-80c5-b238454cfdd6'; name = 'AI Agent'; executeOnce = $true
  },
  [ordered]@{
    parameters = @{ resource = 'messages-api'; instanceName = 'bot-JK-prueba-operador1'; remoteJid = "={{ `$('Webhook Evolution API').item.json.body.data.key.remoteJid }}"; messageText = '={{ $json.output }}'; options_message = @{} }
    type = 'n8n-nodes-evolution-api.evolutionApi'; typeVersion = 1; position = @(1104,128); id = '02d01e05-a9f8-4caa-a02e-37a660aa662c'; name = 'Enviar texto a WhatsApp'
    credentials = @{ evolutionApi = @{ id = 'iUIvc9Sd8diFJaGU'; name = 'Evolution PARA n8n cambios JK' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $mainCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(512,128); id = '6ac06fc7-1afb-49ab-893c-e2f2b5f8b995'; name = 'Code in JavaScript'
  },
  [ordered]@{
    parameters = @{ httpMethod = 'POST'; path = 'webhook-whatsapp'; options = @{} }
    id = '75799f35-f979-4b45-9dab-861127bd5f9d'; name = 'Webhook Evolution API'; type = 'n8n-nodes-base.webhook'; typeVersion = 1; position = @(-240,144); webhookId = 'a9ba9382-d166-495a-8309-e13a9d839b06'
  },
  [ordered]@{
    parameters = @{ name = 'calculadora_remesas'; description = 'Convierte montos de dinero entre paises/monedas con las tasas oficiales del dia de JK Remesas. Usala para cualquier conversion de monto, para cruces entre dos paises, o cuando intervengan dolares, USDT o euros. Devuelve el resultado exacto.'; language = 'javaScript'; jsCode = $toolCode; specifyInputSchema = $true; schemaType = 'manual'; inputSchema = $inputSchema }
    type = '@n8n/n8n-nodes-langchain.toolCode'; typeVersion = 1.1; position = @(992,400); id = 'b1f2c3d4-0000-4a00-9000-aabbccddeeff'; name = 'Calculadora de Conversion'
  },
  [ordered]@{
    parameters = @{ jsCode = $acumularCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(48,320); id = 'c1a2b3c4-1111-4a11-9111-acumular0001'; name = 'Acumular Mensajes'
  },
  [ordered]@{
    parameters = @{ amount = 30; unit = 'seconds' }
    type = 'n8n-nodes-base.wait'; typeVersion = 1.1; position = @(208,320); id = 'd2b3c4d5-2222-4a22-9222-esperar00001'; name = 'Esperar 30s'; webhookId = 'e7c1a2b3-3333-4a33-9333-waithook0001'
  },
  [ordered]@{
    parameters = @{ jsCode = $filtrarCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(368,320); id = 'f3c4d5e6-4444-4a44-9444-filtrar00001'; name = 'Filtrar Ultimo'
  }
)

$connections = [ordered]@{
  'Webhook Evolution API'  = @{ main = @( ,@( @{ node='Es mensaje de cliente?'; type='main'; index=0 } ) ) }
  'Es mensaje de cliente?' = @{ main = @( ,@( @{ node='Acumular Mensajes'; type='main'; index=0 } ) ) }
  'Acumular Mensajes'      = @{ main = @( ,@( @{ node='Esperar 30s'; type='main'; index=0 } ) ) }
  'Esperar 30s'            = @{ main = @( ,@( @{ node='Filtrar Ultimo'; type='main'; index=0 } ) ) }
  'Filtrar Ultimo'         = @{ main = @( ,@( @{ node='Consultar Tasas'; type='main'; index=0 } ) ) }
  'Consultar Tasas'        = @{ main = @( ,@( @{ node='Code in JavaScript'; type='main'; index=0 } ) ) }
  'Code in JavaScript'     = @{ main = @( ,@( @{ node='AI Agent'; type='main'; index=0 } ) ) }
  'OpenAI Model'           = @{ ai_languageModel = @( ,@( @{ node='AI Agent'; type='ai_languageModel'; index=0 } ) ) }
  'Memoria de Chat'        = @{ ai_memory = @( ,@( @{ node='AI Agent'; type='ai_memory'; index=0 } ) ) }
  'Calculadora de Conversion' = @{ ai_tool = @( ,@( @{ node='AI Agent'; type='ai_tool'; index=0 } ) ) }
  'AI Agent'               = @{ main = @( ,@( @{ node='Enviar texto a WhatsApp'; type='main'; index=0 } ) ) }
}

$body = [ordered]@{ name = 'Bot WhatsApp JK Remesas - V2 (Mejorado)'; nodes = $nodes; connections = $connections; settings = @{ executionOrder = 'v1' } }

$json = $body | ConvertTo-Json -Depth 40
$json | Out-File -FilePath "C:\Users\USER\Documents\APP PARA CAMBIOS JK CONVERSOR\workflow_bot_whatsapp_v4.json" -Encoding utf8
Write-Output ("JSON v4 generado. Longitud: " + $json.Length + " chars. Nodos: " + $nodes.Count)
