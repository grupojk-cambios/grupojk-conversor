// REVISION DIARIA DE LOS CHATS (pedido de Kelvin, 24/11): "que el bot se vaya alimentando a diario con lo
// que le envian los clientes".
//
// Baja de Evolution los chats de clientes de las ultimas 24 horas (sin grupos) y arma un informe con lo que
// sirve para mejorar el bot: como saludan los clientes y quien les contesto, a quien no se le contesto,
// respuestas del bot que se repiten o que mandaron al cliente a "Solo remesas" o a un asesor, como contesta
// Kelvin a mano, y los errores de n8n. NO cambia nada: ni el bot, ni los workflows, ni manda mensajes.
//
// Uso (desde la raiz del proyecto):
//     node scripts/revisar_chats_dia.mjs              # ultimas 24 horas
//     node scripts/revisar_chats_dia.mjs --horas 48
//
// La llave de Evolution se lee de privado/evo.env (EVO_URL, EVO_INST, EVO_KEY) y la de n8n de
// C:\Users\USER\.claude.json (la misma que usan los scripts de despliegue). La carpeta privado/ NO se sube
// a GitHub (es publico). El informe queda en Entrenamiento para el bot/informes/AAAA-MM-DD.md; trae textos de clientes, asi que
// los numeros largos y los correos se tapan.

import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';

const raiz = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const arg = n => { const i = process.argv.indexOf('--' + n); return i === -1 ? null : process.argv[i + 1]; };
const HORAS = Number(arg('horas') || 24);
const WORKFLOW_BOT = 'NWmStkbNexV7s5xY';

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
    method: 'POST', headers: { 'Content-Type': 'application/json', apikey: env.EVO_KEY }, body: JSON.stringify(cuerpo || {}),
    signal: AbortSignal.timeout(60000)
  });
  if (!r.ok) throw new Error('Evolution ' + ruta + ' -> HTTP ' + r.status);
  return r.json();
}

// ---------- utilidades ----------
const ecuador = ms => new Date(ms - 5 * 3600000);                      // hora de Ecuador (UTC-5)
const hhmm = ms => ecuador(ms).toISOString().slice(11, 16);
const dia = ms => ecuador(ms).toISOString().slice(0, 10);
const norm = s => String(s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9ñ ]+/g, ' ').replace(/\s+/g, ' ').trim();
// Los clientes escriben cuentas, cedulas y telefonos: no van al informe.
const limpio = s => String(s || '').replace(/\n+/g, ' / ')
  .replace(/[^\s@]+@[^\s@]+\.[a-z]{2,}/gi, '[correo]')
  .replace(/\d[\d .\-]{6,}\d/g, '[núm]').slice(0, 140);
function textoDe(m) {
  const x = m.message || {};
  if (x.reactionMessage || x.protocolMessage || x.senderKeyDistributionMessage) return null;
  if (x.conversation) return x.conversation;
  if (x.extendedTextMessage) return x.extendedTextMessage.text || '';
  if (x.imageMessage) return '[foto]' + (x.imageMessage.caption ? ' ' + x.imageMessage.caption : '');
  if (x.audioMessage) return '[audio]';
  if (x.stickerMessage) return '[sticker]';
  if (x.videoMessage) return '[video]';
  if (x.documentMessage) return '[documento]';
  return '[' + (m.messageType || 'otro') + ']';
}
const rolDe = m => (!m.key.fromMe ? 'cliente' : (String(m.key.id).startsWith('3EB0') ? 'bot' : 'kelvin'));
// Una persona puede estar en dos chats (el LID, donde escribe, y su telefono, donde contesta el bot): se juntan.
function personaDe(m) {
  const jids = [m.key.remoteJid, m.key.remoteJidAlt].map(x => String(x || ''));
  const pn = jids.find(x => x.endsWith('@s.whatsapp.net'));
  return pn ? pn.split('@')[0] : jids[0];
}
const SALUDO = /\b(hola|holi|holaa|buenas|buenos|buen|saludos|epa|epale|bendiciones|que tal|como estas|como esta)\b/;
const abierto = ms => { const e = ecuador(ms), d = e.getUTCDay(), h = e.getUTCHours() + e.getUTCMinutes() / 60; return d === 0 ? (h >= 10 && h < 14) : (h >= 9 && h < 18); };

// ---------- 1) bajar los mensajes de las ultimas HORAS ----------
const ahora = Date.now();
const desde = ahora - HORAS * 3600000;
console.log('Bajando chats de las ultimas ' + HORAS + ' horas...');
const chats = await evo('/chat/findChats');
const lista = (Array.isArray(chats) ? chats : (chats.chats || []))
  .filter(c => !String(c.remoteJid).endsWith('@g.us') && !String(c.remoteJid).endsWith('@broadcast') && Date.parse(c.updatedAt) >= desde - 3600000);
const mensajes = [];
for (const c of lista) {
  try {
    const r = await evo('/chat/findMessages', { where: { key: { remoteJid: c.remoteJid } }, page: 1, offset: 100 });
    for (const m of ((r.messages && r.messages.records) || [])) {
      const ts = Number(m.messageTimestamp) * 1000;
      if (ts < desde || ts > ahora) continue;
      const t = textoDe(m);
      if (t === null) continue;
      mensajes.push({ ts, rol: rolDe(m), persona: personaDe(m), t, id: m.key.id, nombre: m.pushName || '' });
    }
  } catch (e) { console.error('  chat saltado (' + String(c.remoteJid).slice(0, 8) + '...): ' + e.message); }
}
// quitar repetidos (un mensaje puede salir en los dos chats) y ordenar
const vistos = new Set();
const todos = mensajes.filter(m => (vistos.has(m.id) ? false : (vistos.add(m.id), true))).sort((a, b) => a.ts - b.ts);
const personas = {};
for (const m of todos) (personas[m.persona] = personas[m.persona] || []).push(m);

// ---------- 2) analisis ----------
const cli = todos.filter(m => m.rol === 'cliente'), bot = todos.filter(m => m.rol === 'bot'), kel = todos.filter(m => m.rol === 'kelvin');
const contesto = (lista, i, minutos) => {      // quien contesto el mensaje i dentro de N minutos
  for (let j = i + 1; j < lista.length; j++) {
    if (lista[j].ts - lista[i].ts > minutos * 60000) break;
    if (lista[j].rol === 'bot' || lista[j].rol === 'kelvin') return lista[j];
  }
  return null;
};

const saludos = {};      // texto normalizado -> { n, bot, kelvin, nadie, ej }
const sinRespuesta = [];
const repetidas = [];
const remesasOAsesor = [];
const aMano = [];
const frases = {};
for (const p in personas) {
  const l = personas[p];
  const botTextos = {};
  for (let i = 0; i < l.length; i++) {
    const m = l[i];
    if (m.rol === 'bot' && !m.t.startsWith('[')) {
      botTextos[m.t] = (botTextos[m.t] || 0) + 1;
      if (/^Solo remesas|asesor te contacta|Por ahora no manejamos/i.test(m.t)) {
        const ant = [...l.slice(0, i)].reverse().find(x => x.rol === 'cliente');
        if (ant) remesasOAsesor.push({ cliente: limpio(ant.t), bot: limpio(m.t), cuando: dia(m.ts) + ' ' + hhmm(m.ts) });
      }
    }
    if (m.rol !== 'cliente') continue;
    const n = norm(m.t);
    if (!m.t.startsWith('[') && SALUDO.test(n) && n.split(' ').length <= 6) {
      const k = n, r = contesto(l, i, 10);
      const e = saludos[k] = saludos[k] || { n: 0, bot: 0, kelvin: 0, nadie: 0 };
      e.n++; if (!r) e.nadie++; else e[r.rol]++;
    }
    if (!m.t.startsWith('[') && n && n.split(' ').length <= 5 && !SALUDO.test(n)) frases[n] = (frases[n] || 0) + 1;
    if (m.rol === 'cliente' && m.t && !m.t.startsWith('[')) {
      const r = contesto(l, i, 10);
      if (r && r.rol === 'kelvin' && r.t && !r.t.startsWith('[')) aMano.push({ cliente: limpio(m.t), kelvin: limpio(r.t) });
    }
  }
  for (const t in botTextos) if (botTextos[t] >= 3) repetidas.push({ texto: limpio(t), veces: botTextos[t], persona: p.slice(-4) });
  // el ultimo mensaje de la conversacion es del cliente y lleva rato esperando
  const ult = l[l.length - 1];
  if (ult && ult.rol === 'cliente' && ahora - ult.ts >= 15 * 60000 && !/^\[(sticker|foto)\]$/.test(ult.t)) {
    sinRespuesta.push({ cuando: dia(ult.ts) + ' ' + hhmm(ult.ts), espera: Math.round((ahora - ult.ts) / 60000), enHorario: abierto(ult.ts), texto: limpio(ult.t) });
  }
}

// ---------- 3) errores de n8n ----------
let errores = null;
try {
  const cfg = fs.readFileSync(path.join(os.homedir(), '.claude.json'), 'utf8');
  const url = (cfg.match(/"N8N_API_URL"\s*:\s*"([^"]+)"/) || [])[1], key = (cfg.match(/"N8N_API_KEY"\s*:\s*"([^"]+)"/) || [])[1];
  if (url && key) {
    const base = url.replace(/\/$/, '') + (/\/api\/v1$/.test(url) ? '' : '/api/v1');
    const r = await fetch(base + '/executions?workflowId=' + WORKFLOW_BOT + '&status=error&limit=50', { headers: { 'X-N8N-API-KEY': key }, signal: AbortSignal.timeout(30000) });
    if (r.ok) errores = ((await r.json()).data || []).filter(e => Date.parse(e.startedAt) >= desde).map(e => ({ id: e.id, cuando: dia(Date.parse(e.startedAt)) + ' ' + hhmm(Date.parse(e.startedAt)) }));
  }
} catch (e) { errores = null; }

// ---------- 4) el informe ----------
const top = (obj, n) => Object.entries(obj).sort((a, b) => b[1] - a[1]).slice(0, n);
const L = [];
L.push('# Revisión de los chats — ' + dia(ahora) + ' ' + hhmm(ahora) + ' (últimas ' + HORAS + ' h)');
L.push('');
L.push('> Informe PRIVADO (no se sube a GitHub). Solo informa: no cambia nada del bot.');
L.push('');
L.push('## Resumen');
L.push('- Personas que escribieron: **' + Object.keys(personas).filter(p => personas[p].some(m => m.rol === 'cliente')).length + '**; mensajes de clientes: **' + cli.length + '**');
L.push('- Respuestas del bot: **' + bot.length + '**; respuestas a mano de Kelvin/operadora: **' + kel.length + '**');
L.push('- Errores del bot en n8n: ' + (errores === null ? '(no se pudo consultar)' : '**' + errores.length + '**' + (errores.length ? ' (ejecuciones ' + errores.map(e => e.id + ' ' + e.cuando).join(', ') + ')' : '')));
L.push('');
L.push('## Saludos de los clientes (y quién les contestó en 10 min)');
const sal = top(Object.fromEntries(Object.entries(saludos).map(([k, v]) => [k, v.n])), 25);
if (!sal.length) L.push('- (ninguno)');
for (const [k, n] of sal) { const v = saludos[k]; L.push('- "' + k + '" ×' + n + ' → bot ' + v.bot + ', Kelvin ' + v.kelvin + ', **nadie ' + v.nadie + '**'); }
L.push('');
L.push('## Clientes que quedaron esperando (último mensaje suyo, sin respuesta hace 15+ min)');
if (!sinRespuesta.length) L.push('- (ninguno)');
for (const s of sinRespuesta.sort((a, b) => b.espera - a.espera).slice(0, 30)) L.push('- ' + s.cuando + ' (' + s.espera + ' min' + (s.enHorario ? '' : ', fuera de horario') + '): "' + s.texto + '"');
L.push('');
L.push('## Respuestas del bot repetidas 3 o más veces a la misma persona (posible ciclo)');
if (!repetidas.length) L.push('- (ninguna)');
for (const r of repetidas.slice(0, 20)) L.push('- ×' + r.veces + ' (persona …' + r.persona + '): "' + r.texto + '"');
L.push('');
L.push('## Lo que el cliente pidió y el bot mandó a "Solo remesas" / asesor / "no manejamos"');
if (!remesasOAsesor.length) L.push('- (ninguno)');
for (const r of remesasOAsesor.slice(0, 30)) L.push('- ' + r.cuando + ': cliente "' + r.cliente + '" → bot "' + r.bot + '"');
L.push('');
L.push('## Cómo contestó Kelvin a mano (para parecerse más a él)');
if (!aMano.length) L.push('- (nada)');
for (const a of aMano.slice(0, 40)) L.push('- cliente "' + a.cliente + '" → Kelvin "' + a.kelvin + '"');
L.push('');
L.push('## Frases cortas más repetidas de los clientes (no saludos)');
const fr = top(frases, 30).filter(([, n]) => n >= 2);
if (!fr.length) L.push('- (ninguna se repitió)');
for (const [k, n] of fr) L.push('- "' + k + '" ×' + n);
L.push('');

const carpeta = path.join(raiz, 'Entrenamiento para el bot', 'informes');
fs.mkdirSync(carpeta, { recursive: true });
const salida = path.join(carpeta, dia(ahora) + '.md');
fs.writeFileSync(salida, L.join('\n'), 'utf8');
console.log('Informe listo: ' + path.relative(raiz, salida) + '  (' + cli.length + ' mensajes de clientes, ' + bot.length + ' del bot, ' + (errores === null ? 'errores de n8n sin consultar' : errores.length + ' errores de n8n') + ')');
