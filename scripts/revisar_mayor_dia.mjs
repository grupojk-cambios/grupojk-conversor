// REVISION DIARIA DEL MAYOR (pedido de Kelvin, 24/11): "que la revision tambien incluya el mayor, para estudiarla juntos".
//
// Baja de Evolution lo que se escribio en los grupos del mayor (clientes y bancos) en las ultimas 24 horas y corre
// sobre cada mensaje el MISMO codigo que usa el bot (los nodos "Entender Mensaje", "Hace Falta Publicar?" y
// "Decidir Publicacion" de workflow_mayor.json), asi el informe dice que habria hecho el bot en modo REAL con cada
// mensaje de un cliente. Tambien cuenta cuantos RST de los grupos de bancos recibieron una reaccion de "cobrado"
// (para saber si las alertas de vencimiento van a ser utiles o ruidosas), las vistas previas de ensayo que salieron
// en el grupo de avisos y los errores de n8n. Desde el 26/11 tambien mide los PEDIDOS A PAISES (cuentas de beneficiario):
// que tan bien los lee el bot y si coinciden con lo que el equipo paso a mano a cada grupo de pais.
// NO cambia nada: ni el bot, ni los workflows, ni manda mensajes.
//
// Uso (desde la raiz del proyecto):
//     node scripts/revisar_mayor_dia.mjs              # ultimas 24 horas
//     node scripts/revisar_mayor_dia.mjs --horas 72
//
// Las llaves salen de privado/evo.env (Evolution) y de C:\Users\USER\.claude.json (n8n). La lista de grupos sale de
// sql/privado/mayor_*.sql (los INSERT de grupos_mayor). Nada de eso se sube a GitHub. El informe queda en
// Entrenamiento para el bot/informes/AAAA-MM-DD_mayor.md; trae textos de clientes, asi que los numeros largos y los correos se tapan.

import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const arg = n => { const i = process.argv.indexOf('--' + n); return i === -1 ? null : process.argv[i + 1]; };
const HORAS = Number(arg('horas') || 24);
const GRUPO_AVISOS = '120363413942097019@g.us';
const WORKFLOWS = { 'Mayor: escuchar y registrar': 'HIERZLV4lwtuBRbZ', 'Mayor: pasar RST al abrir': 'Pgmw9X5zuiRsrct4', 'Mayor: alertas de vencimiento': 'OPZUsQIyPOB8zj9r' };
const BANCOS_CON_ALERTA = ['pichincha', 'pacifico', 'guayaquil', 'produbanco', 'bolivariano', 'jep'];

// ---------- credenciales (nunca se imprimen) ----------
function leerEnv(ruta) {
  const env = {};
  for (const l of fs.readFileSync(ruta, 'utf8').split(/\r?\n/)) { const i = l.indexOf('='); if (i > 0) env[l.slice(0, i).trim()] = l.slice(i + 1).trim(); }
  return env;
}
const rutaEnv = path.join(raiz, 'privado', 'evo.env');
if (!fs.existsSync(rutaEnv)) { console.error('Falta privado/evo.env (EVO_URL, EVO_INST, EVO_KEY).'); process.exit(1); }
const env = leerEnv(rutaEnv);
for (const k of ['EVO_URL', 'EVO_INST', 'EVO_KEY']) if (!env[k]) { console.error('privado/evo.env no tiene ' + k); process.exit(1); }
async function evo(ruta, cuerpo) {
  const r = await fetch(env.EVO_URL.replace(/\/$/, '') + ruta + '/' + encodeURIComponent(env.EVO_INST), {
    method: 'POST', headers: { 'Content-Type': 'application/json', apikey: env.EVO_KEY }, body: JSON.stringify(cuerpo || {}), signal: AbortSignal.timeout(60000)
  });
  if (!r.ok) throw new Error('Evolution ' + ruta + ' -> HTTP ' + r.status);
  return r.json();
}

// ---------- utilidades ----------
const ecuador = ms => new Date(ms - 5 * 3600000);
const hhmm = ms => ecuador(ms).toISOString().slice(11, 16);
const dia = ms => ecuador(ms).toISOString().slice(0, 10);
const quitar = s => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
const limpio = (s, n) => String(s || '').replace(/\n+/g, ' / ').replace(/[^\s@]+@[^\s@]+\.[a-z]{2,}/gi, '[correo]').replace(/\d[\d .\-]{5,}\d/g, '[núm]').slice(0, n || 160);
const tapar = s => String(s || '').replace(/\n+/g, ' / ').replace(/\d/g, '#').slice(0, 170);
const pct = (a, n) => (n ? Math.round((100 * a) / n) + '%' : '-');
const contar = (lista, f) => { const o = {}; for (const x of lista) { const k = f(x); o[k] = (o[k] || 0) + 1; } return o; };
const top = (obj, n) => Object.entries(obj).sort((a, b) => b[1] - a[1]).slice(0, n);
const mediana = l => { if (!l.length) return null; const s = [...l].sort((a, b) => a - b); return s[Math.floor(s.length / 2)]; };
const p90 = l => { if (!l.length) return null; const s = [...l].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(s.length * 0.9))]; };

// ---------- 0) los grupos y el codigo REAL del bot ----------
function leerGrupos() {
  const carpeta = path.join(raiz, 'sql', 'privado');
  const grupos = new Map();
  if (!fs.existsSync(carpeta)) return grupos;
  const rx = /\(\s*'([^']+@g\.us)'\s*,\s*'((?:[^']|'')*)'\s*,\s*'(cliente|tasas|destino)'\s*,\s*(?:null|'(\d*)')\s*,\s*(?:null|'(\d*)')\s*,\s*(?:null|'(\d*)')\s*\)/g;
  for (const f of fs.readdirSync(carpeta).filter(x => /^mayor_.*\.sql$/.test(x)).sort()) {
    const txt = fs.readFileSync(path.join(carpeta, f), 'utf8');
    for (const m of txt.matchAll(rx)) grupos.set(m[1], { grupo_jid: m[1], nombre: m[2].replace(/''/g, "'"), tipo: m[3], cliente_whatsapp: m[4] || null, operador_extra_whatsapp: m[5] || null, operadora_whatsapp: m[6] || null, activo: true, publicar: true });
  }
  return grupos;
}
const grupos = leerGrupos();
if (!grupos.size) { console.error('No encontre grupos en sql/privado/mayor_*.sql'); process.exit(1); }
const wf = JSON.parse(fs.readFileSync(path.join(raiz, 'workflow_mayor.json'), 'utf8').replace(/^\uFEFF/, ''));
const codigo = n => wf.nodes.find(x => x.name === n).parameters.jsCode;
const CODIGO_ENTENDER = codigo('Entender Mensaje'), CODIGO_HACE = codigo('Hace Falta Publicar?'), CODIGO_DECIDIR = codigo('Decidir Publicacion').replace(/const MODO = '\w+'/, "const MODO = 'real'");
const destinosTabla = [...grupos.values()].filter(g => g.tipo === 'destino');
const nombreDe = jid => (grupos.get(jid) || {}).nombre || String(jid).slice(0, 8);

function entender(grupo, m) {
  const data = { key: m.key, pushName: m.pushName, message: m.message, messageTimestamp: m.messageTimestamp, contextInfo: m.contextInfo };
  try { const r = new Function('$input', CODIGO_ENTENDER)({ first: () => ({ json: { grupo, data } }) }); return r.length ? r[0].json : null; } catch (e) { return null; }
}
// Que habria hecho el bot en modo REAL con este mensaje de un cliente (sin la memoria de Redis: JEP y temporal de Solidario parten de cero).
function simular(grupo, fila, ms) {
  const real = Date.now; Date.now = () => ms;
  try {
    const $ = nombre => {
      if (nombre === 'Decidir') return { first: () => ({ json: fila }) };
      if (nombre === 'Cuando lo Llama el Bot') return { first: () => ({ json: { grupo, data: {} } }) };
      if (nombre === 'Guardar en Supabase') return { first: () => ({ json: { id: 1 } }) };
      if (nombre === 'Redis Leer Publicacion') return { first: () => ({ json: { pub: null } }) };
      if (nombre === 'Redis Leer Temporal') return { first: () => ({ json: { temporal: null } }) };
      if (nombre === 'Grupos Destino') return { all: () => destinosTabla.map(json => ({ json })) };
      throw new Error('nodo inesperado ' + nombre);
    };
    if (!new Function('$', CODIGO_HACE)($).length) return null;
    return new Function('$', CODIGO_DECIDIR)($).map(i => i.json);
  } catch (e) { return [{ etapa: 'error', texto: e.message }]; } finally { Date.now = real; }
}
function clasificar(envios) {
  if (envios === null) return 'sin accion';
  if (!envios.length) return 'nada (charla o datos sueltos)';
  const t = envios.map(e => String(e.texto || ''));
  if (envios.some(e => e.etapa === 'error')) return 'ERROR en el codigo';
  if (envios.some(e => e.etapa === 'aviso')) return 'aviso: banco sin grupo';
  if (t.some(x => /^🏧 Cobrador/.test(x))) return 'JEP: pedido al cobrador';
  if (t.some(x => /^Te avisamos cuando el cobrador|^Ya avisamos/.test(x))) return 'JEP: pedido al cobrador';
  if (envios.some(e => e.etapa === 'banco')) return envios.some(e => /COBRAR MAÑANA/.test(nombreDe(e.jid))) ? 'se publicaria en COBRAR MAÑANA (fuera de horario)' : 'se publicaria en su banco';
  if (t.some(x => /^¿Sus? retiros? .*Responda sí o no/.test(x))) return 'banco mal escrito: se le preguntaria si es ese banco';
  if (t.some(x => /^¿Ese mensaje es un RST\?|^¿Su retiro es de .* o de /.test(x))) return 'parece un RST sin banco: se le preguntaria de que banco es';
  if (t.some(x => /^Revisa /.test(x))) return 'se le pediria revisar el largo de un codigo';
  if (t.some(x => /^Faltan /.test(x))) return 'se le pediria un dato que falta';
  if (t.some(x => /texto escrito/.test(x))) return 'foto: se le pediria el texto';
  if (t.some(x => /^Ok, recibido/.test(x))) return 'clave temporal de Solidario';
  return 'otra respuesta';
}

// ---------- 1) bajar los mensajes de cada grupo ----------
const ahora = Date.now(), desde = ahora - HORAS * 3600000;
console.log('Bajando los grupos del mayor (' + grupos.size + ') de las ultimas ' + HORAS + ' horas...');
const porGrupo = new Map();
for (const g of grupos.values()) {
  const recs = [];
  try {
    for (let p = 1; p <= 8; p++) {
      const r = await evo('/chat/findMessages', { where: { key: { remoteJid: g.grupo_jid }, messageTimestamp: { gte: Math.floor(desde / 1000) } }, page: p, offset: 100 });
      const lote = (r.messages && r.messages.records) || [];
      recs.push(...lote);
      if (!lote.length || p >= (r.messages.pages || 1)) break;
    }
  } catch (e) { console.error('  grupo saltado (' + g.nombre + '): ' + e.message); }
  porGrupo.set(g.grupo_jid, recs.filter(m => Number(m.messageTimestamp) * 1000 >= desde).sort((a, b) => a.messageTimestamp - b.messageTimestamp));
}
// lo que salio en el grupo de avisos (vistas previas del ensayo)
let avisos = [];
try {
  const r = await evo('/chat/findMessages', { where: { key: { remoteJid: GRUPO_AVISOS }, messageTimestamp: { gte: Math.floor(desde / 1000) } }, page: 1, offset: 100 });
  avisos = ((r.messages && r.messages.records) || []).map(m => ({ ts: Number(m.messageTimestamp) * 1000, t: (m.message && (m.message.conversation || (m.message.extendedTextMessage || {}).text)) || '' })).filter(x => /^🧪 ENSAYO/.test(x.t)).sort((a, b) => a.ts - b.ts);
} catch (e) { avisos = null; }

// ---------- 2) analisis ----------
const filas = [];                       // lo que "Entender Mensaje" saco de cada mensaje
let mensajes = 0, ignorados = 0;
const reacciones = new Map();           // id del mensaje reaccionado -> [{ ts, emoji }]
for (const g of grupos.values()) {
  for (const m of porGrupo.get(g.grupo_jid) || []) {
    mensajes++;
    const rx = m.message && m.message.reactionMessage;
    if (rx && rx.key && rx.key.id) { const l = reacciones.get(rx.key.id) || []; l.push({ ts: Number(m.messageTimestamp) * 1000, emoji: String(rx.text || '') }); reacciones.set(rx.key.id, l); continue; }
    if (String(m.key.id).startsWith('3EB0') && m.key.fromMe) continue;       // lo que escribio el propio bot
    const f = entender(g, m);
    if (!f) { ignorados++; continue; }
    filas.push({ grupo: g, fila: f, ts: Number(m.messageTimestamp) * 1000, id: m.key.id });
  }
}
const deClientes = filas.filter(x => x.grupo.tipo === 'cliente' && (x.fila.autor_rol === 'cliente' || x.fila.autor_rol === 'operador_extra'));
const retiros = deClientes.filter(x => ((x.fila.datos || {}).registros || []).some(r => r.tipo === 'rst' || r.tipo === 'rct') || (x.fila.datos || {}).pide_texto);
const resultado = contar(retiros.map(x => ({ x, c: clasificar(simular(x.grupo, x.fila, x.ts)) })), o => o.c);
// mensajes de clientes que no se entendieron pero parecen un pedido
const NO_ENTENDIDOS = deClientes.filter(x => x.fila.tipo === 'otro' && /\d{4,}|\brst\b|retiro|clave|cuenta|banco|monto|\$|usd/i.test(x.fila.texto) && !retiros.includes(x));
// codigos con el largo que no es
const largos = {};
for (const x of retiros) for (const r of (x.fila.datos.registros || [])) if (r.tipo === 'rst') { const b = String(r.banco); const l = (r.datos.codigos || []).map(c => String(c).length).join('+') || 'sin codigo'; largos[b] = largos[b] || {}; largos[b][l] = (largos[b][l] || 0) + 1; }
// bancos mencionados que no tienen grupo
const bancosSinGrupo = contar(retiros.flatMap(x => (x.fila.datos.registros || []).filter(r => (r.tipo === 'rst' || r.tipo === 'rct') && r.banco && !['pichincha', 'guayaquil', 'produbanco', 'pacifico', 'jep', 'bolivariano', 'solidario', 'austro', 'internacional'].includes(quitar(r.banco)))), r => String(r.banco));
const fueraHorario = retiros.filter(x => { const e = ecuador(x.ts), d = e.getUTCDay(), h = e.getUTCHours() + e.getUTCMinutes() / 60; return !(d === 0 ? (h >= 10 && h < 14) : (h >= 9 && h < 18)); }).length;
// RST en los grupos de los bancos y si alguien los marco como cobrados
const enBancos = filas.filter(x => x.grupo.tipo === 'destino' && ((x.fila.datos || {}).registros || []).some(r => r.tipo === 'rst'));
const marcados = enBancos.map(x => {
  const banco = quitar(((x.fila.datos.registros.find(r => r.tipo === 'rst') || {}).banco) || x.grupo.nombre.replace(/coop /, ''));
  const rs = (reacciones.get(x.id) || []).filter(r => r.emoji);
  const buenas = rs.filter(r => !/[❌✖❎🚫⛔]/u.test(r.emoji)), malas = rs.filter(r => /[❌✖❎🚫⛔]/u.test(r.emoji));
  return { banco, vigilado: BANCOS_CON_ALERTA.includes(banco), cobrado: buenas.length > 0, conX: malas.length > 0, minutos: buenas.length ? Math.round((Math.min(...buenas.map(r => r.ts)) - x.ts) / 60000) : null, ts: x.ts };
});
const vigilados = marcados.filter(m => m.vigilado);
const tardanzas = vigilados.filter(m => m.cobrado).map(m => m.minutos).filter(n => n >= 0);
const porBanco = {};
for (const m of vigilados) { const b = porBanco[m.banco] = porBanco[m.banco] || { n: 0, cobrados: 0 }; b.n++; if (m.cobrado) b.cobrados++; }
const alertasEnsayo = (avisos || []).filter(a => /la alerta iría/.test(a.t));
// La vista previa de un pedido dice "📦 PEDIDO → iría a..."; las de retiros usan "➡️". Un mensaje con las dos cuenta en las dos.
const previasDePedidos = (avisos || []).filter(a => /📦 PEDIDO/.test(a.t));
const previas = (avisos || []).filter(a => !/la alerta iría/.test(a.t) && (/➡️/.test(a.t) || !/📦 PEDIDO/.test(a.t)));

// ---------- PEDIDOS A PAISES (beneficiario): como los lee el bot (pedido de Kelvin, 26/11) ----------
// Un pedido = la cuenta a la que hay que pagarle al cliente (Venezuela, Banesco, Colombia, Peru, Binance...). Hoy los pasa
// la operadora a mano al grupo del pais: el NOMBRE del cliente en el primer renglon y debajo sus datos. El bot solo hace
// una vista previa en avisos. Aqui se mide que tan bien los lee y se compara con lo que el equipo paso de verdad.
const regsDe = x => ((x.fila.datos || {}).registros || []);
const conPedido = deClientes.filter(x => regsDe(x).some(r => r.tipo === 'beneficiario'));
const pedidosRegs = conPedido.flatMap(x => regsDe(x).filter(r => r.tipo === 'beneficiario').map(r => ({ x, r })));
const destinoDe = r => (r.datos && r.datos.destino_sugerido) || '';
const sinMontoP = o => [o.r.monto_usd, o.r.monto_local, o.r.datos && o.r.datos.monto_sin_moneda].every(v => v === null || v === undefined);
const pedidosPorDestino = contar(pedidosRegs, o => destinoDe(o.r) || (o.r.pais ? o.r.pais + ' (sin grupo)' : 'SIN PAÍS'));
const previasSimuladas = conPedido.map(x => ((simular(x.grupo, x.fila, x.ts) || []).find(e => /📦 PEDIDO/.test(String(e.texto || ''))) || {}).texto || '').filter(Boolean);
const GRUPOS_PAIS = ['venezuela', 'banesco', 'colombia', 'peru', 'brasil', 'chile', 'argentina', 'mexico', 'ecuador', 'panama', 'cuba', 'paraguay', 'zelle', 'binance', 'euro'];
const tokens = s => quitar(s).split(/[^a-z0-9ñ]+/).filter(w => w.length >= 2);
const clientesG = [...grupos.values()].filter(g => g.tipo === 'cliente').map(g => ({ g, toks: tokens(g.nombre.replace(/pedidos?|\bjk\b|kelvin/gi, ' ')) }));
// "LINDA OM" -> el grupo "Linda Omaña PEDIDOS JK"; si hay dos grupos posibles, no se adivina.
const grupoDelNombre = cab => { const t = tokens(cab); if (!t.length) return null; const c = clientesG.filter(o => t.every(w => o.toks.some(k => k.startsWith(w)))); return c.length === 1 ? c[0].g : null; };
const textoMsg = m => { const x = m.message || {}; return x.conversation || (x.extendedTextMessage || {}).text || (x.imageMessage || {}).caption || ''; };
const pasados = [];
// Solo los que el equipo paso en la SEGUNDA mitad del periodo (hasta 12 h): el equipo pasa el pedido horas despues de que
// el cliente lo manda (al llegar el pago), y si el cliente lo mando antes del periodo el informe no lo tiene y saldria
// como "no lo leyo" sin serlo.
const HORAS_COMPARA = Math.min(12, HORAS / 2);
const desdeComparar = desde + (HORAS - HORAS_COMPARA) * 3600000;
for (const g of destinosTabla.filter(g => GRUPOS_PAIS.includes(quitar(g.nombre)))) {
  for (const m of porGrupo.get(g.grupo_jid) || []) {
    const lineas = textoMsg(m).split('\n').map(s => s.trim()).filter(Boolean);
    if (lineas.length < 3 || /\d/.test(lineas[0]) || lineas[0].split(/\s+/).length > 4) continue;
    const gc = grupoDelNombre(lineas[0]);
    if (!gc) continue;
    const ts = Number(m.messageTimestamp) * 1000;
    if (ts < desdeComparar) continue;
    const delCliente = pedidosRegs.filter(o => o.x.grupo.grupo_jid === gc.grupo_jid && o.x.ts <= ts && o.x.ts >= ts - 24 * 3600000);
    const mismo = delCliente.some(o => quitar(destinoDe(o.r)) === quitar(g.nombre));
    pasados.push({ pais: g.nombre, cliente: gc.nombre, resultado: mismo ? 'igual' : (delCliente.length ? 'otro grupo' : 'no lo leyó'),
                   botDijo: [...new Set(delCliente.map(o => destinoDe(o.r) || 'sin país'))].join(', '), texto: lineas.slice(1).join('\n') });
  }
}
// mensajes de clientes que parecen un pedido (cuenta, billetera, Nequi...) y el bot no saco ningun registro
const PEDIDO_NO_LEIDO = deClientes.filter(x => !regsDe(x).length && x.fila.tipo !== 'captura' && !NO_ENTENDIDOS.includes(x)
  && /\d{8,}|nequi|yape|\bpix\b|binance|usdt|trc20|pago movil|bancolombia|banesco|@[a-z0-9.-]+\.[a-z]{2,}/i.test(x.fila.texto));

// ---------- 3) errores de n8n ----------
let errores = null;
try {
  const cfg = fs.readFileSync(path.join(os.homedir(), '.claude.json'), 'utf8');
  const url = (cfg.match(/"N8N_API_URL"\s*:\s*"([^"]+)"/) || [])[1], key = (cfg.match(/"N8N_API_KEY"\s*:\s*"([^"]+)"/) || [])[1];
  if (url && key) {
    const base = url.replace(/\/$/, '') + (/\/api\/v1$/.test(url) ? '' : '/api/v1');
    errores = [];
    for (const [nombre, id] of Object.entries(WORKFLOWS)) {
      const r = await fetch(base + '/executions?workflowId=' + id + '&status=error&limit=50', { headers: { 'X-N8N-API-KEY': key }, signal: AbortSignal.timeout(30000) });
      if (r.ok) for (const e of ((await r.json()).data || [])) if (Date.parse(e.startedAt) >= desde) errores.push({ nombre, id: e.id, cuando: dia(Date.parse(e.startedAt)) + ' ' + hhmm(Date.parse(e.startedAt)) });
    }
  }
} catch (e) { errores = null; }

// ---------- 4) el informe ----------
const L = [];
L.push('# Revisión del MAYOR — ' + dia(ahora) + ' ' + hhmm(ahora) + ' (últimas ' + HORAS + ' h)');
L.push('');
L.push('> Informe PRIVADO (no se sube a GitHub). Solo informa: no cambia nada del bot. Todo es "qué habría hecho el bot en modo REAL" (hoy está en ENSAYO).');
L.push('');
L.push('## Resumen');
L.push('- Grupos del mayor que el informe mira: **' + grupos.size + '** (' + [...grupos.values()].filter(g => g.tipo === 'cliente').length + ' de clientes, ' + destinosTabla.length + ' de destino). Con mensajes en el período: **' + [...porGrupo.values()].filter(l => l.length).length + '**');
L.push('- Mensajes: **' + mensajes + '** (' + ignorados + ' ignorados por el lector: stickers, reacciones sueltas...). Mensajes de clientes / su operador: **' + deClientes.length + '**');
L.push('- Retiros (RST/RCT/fotos de retiro) escritos por clientes: **' + retiros.length + '**; fuera de horario: **' + fueraHorario + '**');
L.push('- Errores en los 3 workflows del mayor (n8n): ' + (errores === null ? '(no se pudo consultar)' : '**' + errores.length + '**' + (errores.length ? ' (' + errores.map(e => e.nombre.replace('Mayor: ', '') + ' #' + e.id + ' ' + e.cuando).join(', ') + ')' : '')));
L.push('- Pedidos a países (cuentas de beneficiario) escritos por clientes: **' + pedidosRegs.length + '** cuentas en ' + conPedido.length + ' mensajes');
L.push('- Vistas previas de ENSAYO que salieron en el grupo de avisos: **' + (avisos === null ? '(no se pudo leer)' : previas.length + ' de retiros + ' + previasDePedidos.length + ' de pedidos + ' + alertasEnsayo.length + ' de alertas') + '**');
L.push('');
L.push('## Pedidos a países: qué tan bien los lee el bot');
if (!pedidosRegs.length) L.push('- (ningún pedido en el período)');
else {
  const n = pedidosRegs.length;
  L.push('- Con país: **' + pedidosRegs.filter(o => o.r.pais).length + '** de ' + n + ' (' + pct(pedidosRegs.filter(o => o.r.pais).length, n) + ') · con grupo al que pasarlo: **' + pedidosRegs.filter(o => destinoDe(o.r)).length + '** · sin monto: **' + pedidosRegs.filter(sinMontoP).length + '**');
  L.push('- A qué grupo iría cada uno: ' + top(pedidosPorDestino, 20).map(([k, v]) => k + ' ×' + v).join(' · '));
}
const cmp = contar(pasados, p => p.resultado);
L.push('- Comparado con lo que **el equipo pasó a mano** a los grupos de países en las últimas ' + HORAS_COMPARA + ' h (nombre del cliente arriba): **' + pasados.length + '** reconocidos → igual que el bot: **' + (cmp['igual'] || 0) + '** · el bot lo mandaba a otro grupo: **' + (cmp['otro grupo'] || 0) + '** · el bot no lo leyó: **' + (cmp['no lo leyó'] || 0) + '**');
L.push('  ("no lo leyó" también puede ser un pedido mandado en foto, por audio, en varios mensajes o antes del período.)');
const difs = pasados.filter(p => p.resultado !== 'igual');
if (difs.length) {
  L.push('');
  L.push('### Diferencias con el equipo (datos tapados)');
  for (const p of difs.slice(0, 20)) L.push('- [' + p.pais + ' ← ' + p.cliente.replace(/PEDIDOS?( JK)?/i, '').trim().slice(0, 18) + '] ' + (p.resultado === 'otro grupo' ? 'el bot decía ' + p.botDijo : 'el bot no lo leyó') + ' · ' + tapar(p.texto));
}
L.push('');
L.push('### Mensajes de clientes que parecen un pedido y el bot no leyó (datos tapados)');
const vistosP = new Set();
for (const x of PEDIDO_NO_LEIDO) { const t = tapar(x.fila.texto); if (vistosP.has(t)) continue; vistosP.add(t); if (vistosP.size <= 15) L.push('- [' + x.grupo.nombre.replace(/PEDIDOS?( JK)?/i, '').trim().slice(0, 14) + '] (' + x.fila.tipo + ') ' + t); }
if (!vistosP.size) L.push('- (ninguno)');
L.push('');
L.push('### Cómo se ve la vista previa de un pedido (3 ejemplos, datos tapados)');
if (!previasSimuladas.length) L.push('- (ninguna)');
for (const t of previasSimuladas.slice(0, 3)) L.push('- ' + tapar(t));
L.push('');
L.push('## Qué habría hecho el bot con cada retiro de un cliente');
if (!retiros.length) L.push('- (ningún retiro en el período)');
for (const [k, n] of top(resultado, 15)) L.push('- ' + k + ': **' + n + '** (' + pct(n, retiros.length) + ')');
L.push('');
L.push('## Largo de los códigos que mandaron los clientes (por banco)');
if (!Object.keys(largos).length) L.push('- (ningún RST)');
for (const [b, l] of Object.entries(largos)) L.push('- ' + b + ': ' + Object.entries(l).map(([k, n]) => k + ' dígitos ×' + n).join(', ').replace(/ dígitos ×(\d+)$/, ' ×$1').replace('sin codigo dígitos', 'sin código'));
L.push('  (reglas del manual: Pichincha 4 · Produbanco 6 · Guayaquil 4+4 · Pacífico 6 · Solidario 6 · Bolivariano 6 u 8 · JEP 6 + clave 4)');
L.push('');
L.push('## ¿Los cobradores marcan los RST? (para saber si las alertas serán útiles)');
if (!vigilados.length) L.push('- (ningún RST de bancos vigilados en el período)');
else {
  L.push('- RST en grupos de bancos con alerta: **' + vigilados.length + '**; con una reacción de cobrado: **' + vigilados.filter(m => m.cobrado).length + '** (' + pct(vigilados.filter(m => m.cobrado).length, vigilados.length) + '); con ❌: ' + vigilados.filter(m => m.conX).length);
  L.push('- Tiempo hasta la reacción de cobrado: mediana **' + (mediana(tardanzas) === null ? '-' : mediana(tardanzas) + ' min') + '**, el 90% antes de **' + (p90(tardanzas) === null ? '-' : p90(tardanzas) + ' min') + '**');
  for (const [b, v] of Object.entries(porBanco)) L.push('  - ' + b + ': ' + v.cobrados + ' de ' + v.n + ' con reacción');
  L.push('- Alertas de ensayo que salieron en avisos: **' + alertasEnsayo.length + '** (si los cobradores casi nunca reaccionan, serán muchas)');
}
L.push('');
L.push('## Mensajes de clientes que el bot NO entendió y parecen un pedido (datos tapados)');
const vistos = new Set();
for (const x of NO_ENTENDIDOS) { const t = tapar(x.fila.texto); if (vistos.has(t)) continue; vistos.add(t); if (vistos.size <= 25) L.push('- [' + x.grupo.nombre.replace(/PEDIDOS?( JK)?/i, '').trim().slice(0, 14) + '] ' + t); }
if (!vistos.size) L.push('- (ninguno)');
L.push('');
L.push('## Bancos que piden los clientes y no tienen grupo');
const sg = Object.entries(bancosSinGrupo);
if (!sg.length) L.push('- (ninguno)');
for (const [b, n] of sg) L.push('- ' + b + ' ×' + n);
L.push('');
L.push('## Últimas vistas previas del ensayo en avisos (códigos ya tapados por el bot)');
if (avisos === null || !previas.length) L.push('- (ninguna)');
for (const a of previas.slice(-12)) L.push('- ' + hhmm(a.ts) + ' ' + limpio(a.t, 260));
L.push('');
const carpeta = path.join(raiz, 'Entrenamiento para el bot', 'informes');
fs.mkdirSync(carpeta, { recursive: true });
const salida = path.join(carpeta, dia(ahora) + '_mayor.md');
fs.writeFileSync(salida, L.join('\n'), 'utf8');
console.log('Informe listo: ' + path.relative(raiz, salida) + '  (' + mensajes + ' mensajes, ' + retiros.length + ' retiros de clientes, ' + (errores === null ? 'errores sin consultar' : errores.length + ' errores de n8n') + ')');
