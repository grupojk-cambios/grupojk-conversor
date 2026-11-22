# ============================================================================
#  WORKFLOW "Mayor: escuchar y registrar"  (Cambios JK)  -  FASE 1
# ============================================================================
#  El bot principal le pasa a este workflow cada mensaje de los grupos de clientes
#  mayoristas que estan en la tabla grupos_mayor. Este workflow SOLO ENTIENDE y
#  REGISTRA: no tiene ningun nodo que envie mensajes (la prueba test_mayor_cableado.mjs
#  lo vigila). Las fases siguientes publicaran en los grupos de destino y responderan.
#
#    Execute Workflow Trigger -> Entender Mensaje -> Redis Leer Visto -> Decidir
#      -> Guardar en Supabase -> Redis Marcar Visto
#
#  - Entender Mensaje: quien escribio, que tipo de mensaje es (beneficiario, RST, RCT,
#    captura, pregunta...) y sus datos (banco, montos, cuenta, clave...). Reglas
#    deterministas, sin IA. NUNCA asume el pais: si no esta claro, queda en null.
#  - Los mensajes de grupo a veces llegan DUPLICADOS: se descartan por su id (Redis).
#
#  Genera workflow_mayor.json. Se sube con scripts\desplegar_mayor.ps1.
#  Se crea INACTIVO: un sub-workflow se ejecuta cuando el bot lo llama, sin activarse.
# ============================================================================
$ErrorActionPreference = 'Stop'

$HORAS_VISTO = 24 * 7        # cuanto se recuerda que un mensaje ya se registro (dedupe)

$supaCred  = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
$redisCred = @{ redis = @{ id = 'SKkvpS5A65SOcmJs'; name = 'Redis memoria para Cambios JK' } }

# ===================== CODIGO: ENTENDER MENSAJE =====================
$entenderCode = @'
// ===== MAYOR, FASE 1: ENTENDER UN MENSAJE DE UN GRUPO DE CLIENTES (solo registra; no responde nada) =====
// Entra: { grupo: <fila de grupos_mayor>, data: <body.data del webhook de Evolution> }
// Sale: UNA fila lista para transacciones_mayor_por_whatsapp, o nada si el mensaje no sirve
// (sticker, reaccion, mensaje borrado...).
//
// Reglas deterministas (sin IA) hechas con los mensajes reales de los grupos: el cliente manda el
// BENEFICIARIO (cuenta + titular + cedula + monto), los RST (retiros sin tarjeta: banco + telefono +
// clave + monto), capturas de sus pagos, y preguntas ("hay Bs hoy?"). El pais NUNCA se asume: si no
// esta claro queda en null (una fase posterior le pregunta al cliente "¿es Argentina?").
const entrada = $input.first().json || {};
const grupo = entrada.grupo || {};
const ev = entrada.data || {};
const llave = ev.key || {};
if (!llave.id) return [];

// ---------- el mensaje ----------
function desenvolver(m){
  let x = m || {};
  for (let i = 0; i < 4; i++){
    const dentro = (x.ephemeralMessage || x.viewOnceMessage || x.viewOnceMessageV2 || x.documentWithCaptionMessage || x.associatedChildMessage || {}).message;
    if (!dentro) break;
    x = dentro;
  }
  return x;
}
const msg = desenvolver(ev.message);
const IGNORAR = ['stickerMessage', 'reactionMessage', 'encReactionMessage', 'protocolMessage', 'albumMessage', 'pollUpdateMessage', 'senderKeyDistributionMessage'];
if (IGNORAR.some(k => msg[k] !== undefined)) return [];

const textoCrudo = String(msg.conversation || (msg.extendedTextMessage && msg.extendedTextMessage.text)
  || (msg.imageMessage && msg.imageMessage.caption) || (msg.videoMessage && msg.videoMessage.caption)
  || (msg.documentMessage && msg.documentMessage.caption) || '').trim();
const esImagen = !!msg.imageMessage, esAudio = !!msg.audioMessage;
if (!textoCrudo && !esImagen && !esAudio) return [];

// Los numeros escritos con emojis ("6️⃣6️⃣5️⃣") se vuelven digitos.
const limpio = textoCrudo.normalize('NFKC').replace(/([0-9])️?⃣/g, '$1').replace(/[​-‏‪-‮]/g, '');
const minus = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
const digitos = x => String(x || '').replace(/\D/g, '');
const mismoNumero = (a, b) => { const x = digitos(a), y = digitos(b); return !!x && !!y && x.slice(-9) === y.slice(-9); };

// ---------- pista del GRUPO DE DESTINO ----------
// En los grupos de destino el banco o el pais lo dice el propio grupo: en PICHINCHA se publica
// "Tlf 0999... Codigo 1234 Monto 20" sin repetir "Pichincha"; en VENEZUELA o BANESCO la cuenta es de
// Venezuela. Eso NO es asumir: el grupo existe para eso. En los grupos de clientes no hay pista.
const PISTA = (function(){
  const r = { bancoEC: '', pais: null };
  if (!grupo || grupo.tipo !== 'destino') return r;
  const g = minus(grupo.nombre);
  const m = g.match(/\b(pichincha|guayaquil|produbanco|pacifico|jep)\b/);
  if (m) r.bancoEC = m[1];
  if (/venezuela|banesco|bolivares/.test(g)) r.pais = 'Venezuela';
  else if (/\bzelle\b/.test(g)) r.pais = 'Zelle';
  else if (/\bbinance\b/.test(g)) r.pais = 'USDT';
  else {
    const PAISES_GRUPO = [['Argentina', 'argentina'], ['Brasil', 'brasil'], ['Chile', 'chile'], ['Perú', 'peru'], ['Colombia', 'colombia'], ['Ecuador', 'ecuador'],
                          ['Panamá', 'panama'], ['Paraguay', 'paraguay'], ['Cuba', 'cuba'], ['México', 'mexico']];
    const p = PAISES_GRUPO.find(([n, k]) => new RegExp('\\b' + k + '\\b').test(g));
    if (p) r.pais = p[0];
  }
  return r;
})();

// ---------- quien escribio ----------
function quienEscribio(){
  if (llave.fromMe === true) return { rol: 'kelvin', numero: '' };       // Kelvin (el bot no escribe en la Fase 1)
  const candidato = [llave.participantAlt, llave.participant, llave.remoteJidAlt].map(x => String(x || '')).find(x => /@s\.whatsapp\.net$/.test(x)) || '';
  const numero = digitos(candidato);
  let rol = 'otro';
  if (numero && mismoNumero(numero, grupo.operadora_whatsapp)) rol = 'operadora';
  else if (numero && mismoNumero(numero, grupo.cliente_whatsapp)) rol = 'cliente';
  else if (numero && mismoNumero(numero, grupo.operador_extra_whatsapp)) rol = 'operador_extra';
  return { rol, numero };
}
const autor = quienEscribio();

// ---------- numeros y montos ----------
// Formato latino: 1.026,76 | 300.00 | 112.955 (tres decimales = miles) | 7
function aNumero(s){
  s = String(s || '').replace(/[^0-9.,]/g, '').replace(/[.,]+$/, '');
  if (!s) return null;
  const ult = Math.max(s.lastIndexOf('.'), s.lastIndexOf(','));
  let v;
  if (ult === -1) v = parseFloat(s);
  else {
    const dec = s.slice(ult + 1);
    v = (dec.length === 3) ? parseFloat(s.replace(/[.,]/g, '')) : parseFloat(s.slice(0, ult).replace(/[.,]/g, '') + '.' + dec);
  }
  return isNaN(v) ? null : v;
}
const RX_MONEDA = '(?:bs\\.?s?|bsd|bolivares|cop|clp|brl|pen|ars|mxn|reales|reais|soles|pesos(?:\\s+(?:chilenos|colombianos|argentinos|mexicanos))?)';
function monedaDe(t){
  t = String(t || '');
  if (/chilen|clp/.test(t)) return 'CLP';
  if (/colomb|cop/.test(t)) return 'COP';
  if (/argent|ars/.test(t)) return 'ARS';
  if (/mexic|mxn/.test(t)) return 'MXN';
  if (/^bs|bolivar/.test(t)) return 'VES';
  if (/brl|reales|reais/.test(t)) return 'BRL';
  if (/pen|soles/.test(t)) return 'PEN';
  return '';
}
// Cada monto se reconoce por su MARCA: "$100", "100$", "100 usd" son dolares; "Bs 350.000", "182.000 cop"
// son moneda local. Los numeros sin marca (telefonos, cedulas, claves, fechas) no se toman por monto.
// "100 $ 102,900bs": el $ es del 100. "bs 112.955 $100": ese $ es del 100 que sigue, no del 112.955.
function extraerMontos(b){
  const toks = [];
  const rx = /\d[\d.,]*\d|\d/g; let m;
  while ((m = rx.exec(b))){
    const ini = m.index, fin = ini + m[0].length;
    const antes = b.slice(Math.max(0, ini - 14), ini), despues = b.slice(fin, fin + 18);
    const t = { texto: m[0], ini, fin, valor: aNumero(m[0]), marca: '', moneda: '', ruido: false };
    const pAntes = b.charAt(ini - 1), pDespues = b.charAt(fin);
    if (/[a-z]/.test(pAntes) || /[\/:%@]/.test(pAntes) || /[\/:%@]/.test(pDespues)) t.ruido = true;   // wallet, fecha, hora, porcentaje, correo
    const identificador = /^\d+$/.test(m[0]) && m[0].length >= 7;                                        // telefono, cedula, cuenta
    if (identificador) t.ruido = true;
    const lb = antes.match(new RegExp('(?:^|[^a-z])(' + RX_MONEDA + ')\\s*[:.]?\\s*$'));
    const la = despues.match(new RegExp('^[\\s.]*(' + RX_MONEDA + ')(?![a-z])'));
    if (/[a-z]/.test(pDespues) && !la) t.ruido = true;                                                   // 1er, 2do, 98a...
    // "CI 22222222 bs 112.955": el "bs" es del monto que sigue, no de la cedula: un identificador nunca es monto.
    if (!identificador && (!t.ruido || lb || la)){
      if (lb){ t.marca = 'local'; t.moneda = monedaDe(lb[1]); t.ruido = false; }
      else if (la){ t.marca = 'local'; t.moneda = monedaDe(la[1]); t.ruido = false; }
    }
    toks.push(t);
  }
  for (let i = 0; i < toks.length; i++){
    const t = toks[i]; if (t.ruido || t.marca) continue;
    const antes = b.slice(Math.max(0, t.ini - 4), t.ini), despues = b.slice(t.fin, t.fin + 14);
    if (/\$\s*$/.test(antes)) { t.marca = 'usd'; continue; }
    if (/^\s*(usdt|usd|dolares|dls|\$)/.test(despues)){
      const sig = toks[i + 1];
      const pegaConElQueSigue = /^\s*\$/.test(despues) && sig && !sig.ruido && sig.marca !== 'local' && /^\s*\$\s*$/.test(b.slice(t.fin, sig.ini));
      if (!pegaConElQueSigue) t.marca = 'usd';
    }
  }
  const usd = toks.find(t => t.marca === 'usd'), local = toks.find(t => t.marca === 'local');
  const r = { usd: usd ? usd.valor : null, local: local ? local.valor : null, moneda: local ? local.moneda : '', tasa: null, sinMoneda: null };
  // "Tasa: 3.35 56.95": la tasa y, a continuacion, lo que recibe en moneda local (sin marca).
  const mt = b.match(/tasa\s*:?\s*(\d[\d.,]*\d|\d)/);
  if (mt){
    r.tasa = aNumero(mt[1]);
    if (r.local === null){
      const desdeAqui = mt.index + mt[0].length;
      const t = toks.find(x => x.ini >= desdeAqui && !x.ruido && !x.marca);
      if (t) r.local = t.valor;
    }
  }
  // "Monto: 665" sin simbolo: se guarda aparte (en dolares solo si el contexto lo dice).
  const mm = b.match(/mo[nm]to\s*(?:en\s*)?:?\s*\$?\s*(\d[\d.,]*\d|\d)/);
  if (mm){
    const t = toks.find(x => x.ini >= mm.index && x.ini <= mm.index + mm[0].length);
    if (t && !t.ruido && !t.marca) r.sinMoneda = t.valor;
  }
  return r;
}

// ---------- datos sueltos ----------
// Numeros de 8 o mas digitos (cuentas, cedulas, telefonos): pegados, con guiones o puntos entre grupos
// ("0191-0000-00-0000012345", "24.000.000"), o en bloques de 4 separados por espacio ("0102 0518 2300 0007 2054").
// Los espacios sueltos NO se juntan: "9650 098 715 8373" son una clave y un telefono.
function numerosLargos(b){
  const out = [];
  for (const m of b.matchAll(/(?<![\d.,])(\d{4}(?: \d{4}){3,})(?!\d)/g)) out.push(m[1].replace(/ /g, ''));
  const resto = b.replace(/\d{4}(?: \d{4}){3,}/g, ' ');
  for (const m of resto.matchAll(/\d+(?:[-.]\d+)*/g)){ const d = m[0].replace(/[-.]/g, ''); if (d.length >= 8) out.push(d); }
  return out;
}
// Telefonos de Ecuador (0991749886, 098 715 8373, +593 98 758 2320) y de Venezuela (04245089184, 0424-5089184).
function telefonosDe(b){
  const out = [];
  for (const m of b.matchAll(/(?<![\d.,])(\+?593[ -]?)?(0?9\d{8})(?!\d)/g)) out.push((m[1] ? '593' : '') + m[2]);
  for (const m of b.matchAll(/(?<![\d.,])(\+?593[ -]?)?(0?9\d)[ -](\d{3})[ -](\d{3,4})(?!\d)/g)) out.push((m[1] ? '593' : '') + m[2] + m[3] + m[4]);
  for (const m of b.matchAll(/(?<![\d.,])(04(?:12|14|16|24|26))[ -]?(\d{7})(?!\d)/g)) out.push(m[1] + m[2]);
  return [...new Set(out)];
}
function codigosDe(b){
  const t = b.replace(/\bc\.?\s?([12])\s*[:.]?\s*/g, 'codigo ').replace(/\b([12])\s?(?:er|ro|do|ero|da)\b/g, 'codigo ');
  const out = [];
  for (const m of t.matchAll(/(?:clave|codigo|cod\.?|primero|segundo)\s*[:.]?\s*(\d{3,7})(?!\d)/g)) out.push(m[1]);
  return out;
}
// Un RST a veces trae su codigo sin etiqueta ("Banco Pichincha 7396 Tlf ... Monto 500"): se toma el
// numero suelto de 4 a 6 digitos que no es un monto, un telefono ni una hora.
function codigosSueltosDe(b, tels){
  const t = b, out = [];
  for (const m of t.matchAll(/(?<![\d.,:$])(\d{4,6})(?![\d.,:])/g)){
    const despues = t.slice(m.index + m[0].length, m.index + m[0].length + 4);
    if (/^\s*(\$|usd|bs)/.test(despues) || tels.some(x => x.includes(m[1]))) continue;
    out.push(m[1]);
  }
  return out;
}
function cedulasDe(b){
  const out = [];
  for (const m of b.matchAll(/(?:\bc\.?\s?[il1]\.?|\bc\.?\s?c\.?|cedula|\bdni\b|\brut\b|\brif\b|\b[ve]-)\s*[:.]?\s*(\d[\d.\-]{5,12}\d)/g)) out.push(digitos(m[1]));
  return [...new Set(out)];
}
const correosDe = b => (b.match(/[^\s@*]+@[^\s@*]+\.[a-z]{2,}/g) || []);
const billeteraDe = b => (b.match(/\b(?:t[1-9a-hj-np-za-km-z]{33}|0x[a-f0-9]{40})\b/i) || [''])[0] || ((b.match(/\b[a-z0-9]{26,60}\b/i) || [''])[0]);

// ---------- bancos ----------
const BANCOS_EC = { pichincha: 'Pichincha', guayaquil: 'Guayaquil', produbanco: 'Produbanco', pacifico: 'Pacífico', jep: 'JEP',
                    bolivariano: 'Bolivariano', solidario: 'Solidario', austro: 'Austro', internacional: 'Internacional', machala: 'Machala' };
const bancoEcuadorDe = b => { const m = b.match(/\b(pichincha|guayaquil|produbanco|pacifico|jep|bolivariano|solidario|austro|internacional|machala)\b/); return m ? m[1] : ''; };
const BANCOS_VE = { '0102': 'Venezuela', '0104': 'Venezolano de Crédito', '0105': 'Mercantil', '0108': 'Provincial', '0114': 'Bancaribe', '0115': 'Exterior',
  '0128': 'Caroní', '0134': 'Banesco', '0137': 'Sofitasa', '0138': 'Plaza', '0151': 'BFC', '0156': '100% Banco', '0157': 'Del Sur', '0163': 'Tesoro',
  '0166': 'Agrícola', '0168': 'Bancrecer', '0169': 'Mi Banco', '0171': 'Activo', '0172': 'Bancamiga', '0174': 'Banplus', '0175': 'Bicentenario',
  '0177': 'Banfanb', '0191': 'BNC' };
const NOMBRES_BANCO = [['banesco', 'Banesco'], ['mercantil', 'Mercantil'], ['provincial', 'Provincial'], ['bicentenario', 'Bicentenario'],
  ['bancamiga', 'Bancamiga'], ['\\bbnc\\b', 'BNC'], ['bancaribe', 'Bancaribe'], ['banco de venezuela|banco venezuela|\\bbdv\\b', 'Venezuela'],
  ['bancolombia', 'Bancolombia'], ['nequi', 'Nequi'], ['daviplata', 'Daviplata'], ['davivienda', 'Davivienda'], ['\\bbcp\\b', 'BCP'],
  ['interbank', 'Interbank'], ['scotiabank', 'Scotiabank'], ['banco estado|bancoestado', 'BancoEstado'], ['\\byape\\b', 'Yape'], ['\\bplin\\b', 'Plin'],
  ['mercado pago', 'Mercado Pago'], ['\\bpix\\b', 'Pix']];
function bancoDe(b, cuentaVE){
  if (cuentaVE && BANCOS_VE[cuentaVE.slice(0, 4)]) return BANCOS_VE[cuentaVE.slice(0, 4)];
  for (const [rx, nombre] of NOMBRES_BANCO) if (new RegExp(rx).test(b)) return nombre;
  const ec = bancoEcuadorDe(b);
  return ec ? BANCOS_EC[ec] : '';
}
// A que grupo de operaciones iria (solo informativo en la Fase 1; la Fase 2 publica de verdad).
const GRUPO_RST = { pichincha: 'PICHINCHA', guayaquil: 'GUAYAQUIL', produbanco: 'PRODUBANCO', pacifico: 'PACIFICO', jep: 'COOP JEP', bolivariano: 'COOP JEP', solidario: 'COOP JEP' };

// ---------- pais: NUNCA se asume ----------
const PAISES_EXPLICITOS = [['Venezuela', /\bvenezuela\b|🇻🇪/], ['Colombia', /\bcolombia\b|🇨🇴/], ['Brasil', /\bbrasil\b|\bbrazil\b|🇧🇷/], ['Perú', /\bperu\b|🇵🇪/],
  ['Chile', /\bchile\b|🇨🇱/], ['Argentina', /\bargentina\b|🇦🇷/], ['México', /\bmexico\b|🇲🇽/], ['Ecuador', /\becuador\b|🇪🇨/], ['Panamá', /\bpanama\b|🇵🇦/],
  ['Cuba', /\bcuba\b|🇨🇺/], ['Uruguay', /\buruguay\b|🇺🇾/], ['Paraguay', /\bparaguay\b|🇵🇾/], ['Bolivia', /\bbolivia\b|🇧🇴/], ['Costa Rica', /\bcosta rica\b|🇨🇷/],
  ['Nicaragua', /\bnicaragua\b|🇳🇮/], ['Honduras', /\bhonduras\b|🇭🇳/], ['Guatemala', /\bguatemala\b|🇬🇹/], ['República Dominicana', /\bdominicana\b|🇩🇴/],
  ['España', /\bespana\b|🇪🇸/]];
function paisDe(b, ctx){
  const explicitos = PAISES_EXPLICITOS.filter(([n, rx]) => rx.test(b)).map(([n]) => n);
  const senales = [];
  if (ctx.cuentaVE || ctx.pagoMovil || /banesco|bicentenario|bancamiga|\bbnc\b|banco de venezuela|\bbdv\b|provincial/.test(b)) senales.push('Venezuela');
  if (/nequi|daviplata|bancolombia|davivienda|\bcop\b|pesos colombianos/.test(b)) senales.push('Colombia');
  if (/\bpix\b|\bbrl\b|reais|\bcpf\b/.test(b)) senales.push('Brasil');
  if (/\byape\b|\bplin\b|\bbcp\b|interbank|\bcci\b|\bsoles\b|\bdni\b|scotiabank/.test(b)) senales.push('Perú');
  if (/\brut\b|banco estado|bancoestado|cuenta vista|\bclp\b|pesos chilenos/.test(b)) senales.push('Chile');
  if (/\bcbu\b|\bcvu\b|\balias\b|mercado pago|pesos argentinos/.test(b)) senales.push('Argentina');
  if (/\bclabe\b|\bspei\b|pesos mexicanos/.test(b) || ctx.largos.some(n => n.length === 18)) senales.push('México');
  if (ctx.bancoEC && ctx.largos.some(n => n.length >= 8 && n.length <= 12) && !senales.length) senales.push('Ecuador');
  if (/\bzelle\b/.test(b)) senales.push('Zelle');
  if (/trc20|erc20|bep20|binance|usdt|billetera|\bwallet\b/.test(b) || ctx.billetera) senales.push('USDT');
  const todos = [...new Set(explicitos.concat(senales))];
  let pais = null, candidatos = [];
  if (explicitos.length === 1 && !(explicitos[0] === 'Venezuela' && senales.some(s => s !== 'Venezuela'))) pais = explicitos[0];
  else if (!explicitos.length && senales.length) { const u = [...new Set(senales)]; if (u.length === 1) pais = u[0]; else candidatos = u; }
  else if (todos.length > 1) candidatos = todos;
  else if (explicitos.length === 1) pais = explicitos[0];
  if (!pais && PISTA.pais && (!candidatos.length || candidatos.indexOf(PISTA.pais) !== -1)){ pais = PISTA.pais; candidatos = []; }
  return { pais, candidatos, senales: todos };
}
const GRUPO_PAIS = { 'Venezuela': 'VENEZUELA', 'Colombia': 'COLOMBIA', 'Brasil': 'BRASIL', 'Perú': 'PERÚ', 'Chile': 'CHILE', 'Argentina': 'ARGENTINA', 'México': 'MÉXICO',
  'Ecuador': 'ECUADOR', 'Panamá': 'PANAMÁ', 'Cuba': 'CUBA', 'Paraguay': 'PARAGUAY', 'Zelle': 'ZELLE', 'USDT': 'BINANCE', 'España': 'EURO' };

// ---------- un registro (un bloque del mensaje) ----------
const RX_ES_RST = /(\brst\b|clave|codigo|\bcod\b|primero|segundo|\bc\.?\s?[12]\s*[:.]|\b[12]\s?(?:er|do)\b)/;
function entenderBloque(bloque){
  const b = minus(bloque);
  const bancoEC = bancoEcuadorDe(b) || PISTA.bancoEC;
  const mon = extraerMontos(b);
  const largos = numerosLargos(b);
  const cuentaVE = largos.find(n => n.length === 20 && n.startsWith('01')) || '';
  const cedulas = cedulasDe(b);
  // Una cedula de Guayas empieza por 09 y parece un celular: si trae su etiqueta ("Cedula 0966873457"), es cedula.
  const tels = telefonosDe(b).filter(t => !cedulas.some(c => c === t || c === t.replace(/^593/, '0')));
  const pagoMovil = !cuentaVE && /\b01\d\d\b/.test(b) && tels.some(t => /^04/.test(t));
  const rct = /retira(?:r)? con tarjeta|retiro con tarjeta|\brct\b/.test(b);

  // RCT / RST: retiros de los bancos de Ecuador
  if (bancoEC && rct && !cuentaVE){
    const usd = mon.usd !== null ? mon.usd : mon.sinMoneda;
    return { tipo: 'rct', pais: 'Ecuador', banco: BANCOS_EC[bancoEC], monto_usd: usd, monto_local: null, moneda: 'USD',
             datos: { destino_sugerido: GRUPO_RST[bancoEC] || null, telefono: tels[0] || null }, bloque };
  }
  // Un telefono y un monto bastan para un RST, salvo que el mensaje hable de una CUENTA ("Banco Pichincha cuenta ahorro ...").
  const hablaDeCuenta = /\bcuenta\b|\bcta\b|ahorros?\b|corriente/.test(b);
  if (bancoEC && !cuentaVE && (RX_ES_RST.test(b) || (tels.length && !hablaDeCuenta && (mon.usd !== null || mon.sinMoneda !== null)))){
    const usd = mon.usd !== null ? mon.usd : mon.sinMoneda;
    const ced = cedulasDe(b)[0] || null;
    let cods = codigosDe(b);
    if (!cods.length) cods = codigosSueltosDe(b, tels).filter(c => c !== ced);
    const hora = (b.match(/\b(\d{1,2}:\d{2})\b/) || [])[1] || null;
    return { tipo: 'rst', pais: 'Ecuador', banco: BANCOS_EC[bancoEC], monto_usd: usd, monto_local: null, moneda: 'USD',
             datos: { destino_sugerido: GRUPO_RST[bancoEC] || null, telefono: tels[0] || null, codigos: cods, cedula: ced, hora }, bloque };
  }

  // BENEFICIARIO: tiene con que identificar una cuenta (numero, correo, billetera) y pais o monto
  const correos = correosDe(b), billetera = billeteraDe(b);
  const cuentas = largos.filter(n => !cedulas.includes(n) && !tels.includes(n));
  const hayIdentificador = cuentas.length > 0 || correos.length > 0 || !!billetera || pagoMovil
    || (tels.length > 0 && /nequi|daviplata|yape|plin|pix/.test(b))
    || (cedulas.length > 0 && /\brut\b|cuenta vista|cuenta rut|\bdni\b/.test(b))        // en Chile la cuenta RUT es la cedula
    || /\balias\s*[:.]?\s*[a-z0-9._-]{4,}/.test(b);                                       // Argentina
  if (hayIdentificador){
    const p = paisDe(b, { cuentaVE, pagoMovil, largos: cuentas, bancoEC, billetera });
    const hayMonto = mon.usd !== null || mon.local !== null || mon.sinMoneda !== null;
    if (p.pais || hayMonto){
      const pais = p.pais;
      let usd = mon.usd;
      if (usd === null && mon.sinMoneda !== null && (pais === 'Zelle' || pais === 'USDT' || pais === 'Ecuador')) usd = mon.sinMoneda;
      let moneda = mon.moneda;
      if (!moneda && mon.local !== null) moneda = ({ 'Venezuela': 'VES', 'Colombia': 'COP', 'Brasil': 'BRL', 'Perú': 'PEN', 'Chile': 'CLP', 'Argentina': 'ARS', 'México': 'MXN' })[pais] || '';
      if (!moneda && (pais === 'Zelle' || pais === 'USDT')) moneda = 'USD';
      const banco = bancoDe(b, cuentaVE);
      let destino = pais ? (GRUPO_PAIS[pais] || null) : null;
      if (pais === 'Venezuela') destino = (banco === 'Banesco') ? 'BANESCO' : 'VENEZUELA';
      return { tipo: 'beneficiario', pais, banco: banco || null, monto_usd: usd, monto_local: mon.local, moneda: moneda || null,
               datos: { cuentas, cedulas, telefonos: tels, correos, billetera: billetera || null, tasa: mon.tasa, monto_sin_moneda: (usd === null ? mon.sinMoneda : null),
                        destino_sugerido: destino, candidatos: p.candidatos, senales: p.senales, pago_movil: pagoMovil || undefined }, bloque };
    }
  }
  return null;
}

// Un mensaje puede traer varios registros. NO se parte por los renglones vacios (muchos clientes escriben
// UNA cuenta con renglones vacios en el medio: "Banco / (vacio) / numero / (vacio) / titular / (vacio) / $60"):
// se parte en cada linea que trae su propia ANCLA, o sea su propia cuenta de 20 digitos (Venezuela) o su
// propio RST. Lo que viene antes de la primera ancla y lo que viene despues de cada una (titular, cedula,
// monto) es del mismo registro. Sin anclas, todo el mensaje es un solo registro.
function esAncla(linea){
  const b = minus(linea);
  if (numerosLargos(b).some(n => n.length === 20 && n.startsWith('01'))) return true;
  return !!bancoEcuadorDe(b) && (RX_ES_RST.test(b) || telefonosDe(b).length > 0);
}
function registrosDe(texto){
  const lineas = texto.split('\n').map(l => l.trim()).filter(Boolean);
  const partes = []; let actual = null;
  for (const l of lineas){
    const ancla = esAncla(l);
    if (!actual || (ancla && actual.ancla)){ actual = { lineas: [], ancla: false }; partes.push(actual); }
    actual.lineas.push(l); if (ancla) actual.ancla = true;
  }
  const registros = [];
  for (const p of partes){ const r = entenderBloque(p.lineas.join('\n')); if (r) registros.push(r); }
  return registros;
}

// ---------- preguntas ----------
function preguntaDe(b){
  const temas = [];
  if (/\btasas?\b|precio|a como|cuanto (?:esta|vale|me|pagan)|cual es la/.test(b)) temas.push('tasa');
  if (/cuenta|donde (?:pago|deposito|transfiero|le paso)/.test(b)) temas.push('cuenta');
  if (/\bhay\b|disponib|chance|tienes|tienen|tiene |tendras/.test(b)) temas.push('disponibilidad');
  if (/esperando|ya sal|ya llego|me avisa|foto|verificar|cuando/.test(b)) temas.push('estado');
  return (temas.length || /\?/.test(b)) ? { temas } : null;
}

// ---------- armar la fila ----------
const nombreGrupo = String(grupo.nombre || '');
const clienteNombre = nombreGrupo.replace(/[^\p{L}\p{N} .'-]/gu, ' ').replace(/\b(pedidos?|jk|kelvin)\b/gi, ' ').replace(/[-/]+/g, ' ').replace(/\s+/g, ' ').trim() || nombreGrupo;
const fila = {
  mensaje_id: String(llave.id), fecha_mensaje: null, grupo_jid: String(grupo.grupo_jid || llave.remoteJid || ''), cliente_nombre: clienteNombre,
  autor_rol: autor.rol, autor_numero: autor.numero || null, tipo: 'otro', pais: null, banco: null, monto_usd: null, monto_local: null,
  moneda: null, datos: {}, texto: limpio.slice(0, 3000), estado: 'visto'
};
const ts = Number(ev.messageTimestamp);
if (ts) fila.fecha_mensaje = new Date((ts > 1e12 ? ts : ts * 1000)).toISOString();

const b = minus(limpio);
// GRUPOS DE DESTINO (abonos, RST por banco, Banesco, Venezuela, MONEY Venezuela, los de cada pais): ahi
// publican ustedes los pedidos del dia (el cliente + su cuenta, el RST, las capturas). Se registra TODO lo
// que se entienda, escriba quien escriba, para aprender como llega cada cosa. El nombre del grupo queda
// en datos.grupo_nombre (en estos grupos el "cliente" no es el del nombre del grupo).
const esDestino = grupo.tipo === 'destino';
// En los grupos de CLIENTES, nuestras cuentas, tasas y comprobantes (Kelvin / operadora) no son pedidos del cliente.
const hablaNuestro = !esDestino && (autor.rol === 'kelvin' || autor.rol === 'operadora');
if (esDestino){ fila.cliente_nombre = null; fila.datos.grupo_nombre = nombreGrupo; }

if (grupo.tipo === 'tasas'){
  fila.tipo = textoCrudo ? 'tasas' : 'otro';
  fila.texto = limpio.slice(0, 4000);
  fila.datos = { lineas: limpio.split('\n').filter(l => l.trim()).length };
} else if (esAudio && !textoCrudo){
  fila.tipo = 'audio';
  fila.datos = Object.assign(fila.datos, { segundos: (msg.audioMessage && msg.audioMessage.seconds) || null });
} else if (esImagen){
  fila.tipo = 'captura';
  if (PISTA.pais) fila.pais = PISTA.pais;
  if (textoCrudo){
    const mon = extraerMontos(b), p = paisDe(b, { largos: [], bancoEC: bancoEcuadorDe(b), billetera: '' });
    fila.monto_usd = mon.usd !== null ? mon.usd : mon.sinMoneda; fila.pais = p.pais || PISTA.pais;
    fila.datos = Object.assign(fila.datos, { pie: limpio.slice(0, 300) });
  }
} else if (!hablaNuestro){
  const registros = registrosDe(limpio);
  if (registros.length){
    const tipos = [...new Set(registros.map(r => r.tipo))];
    const primero = registros[0];
    fila.tipo = tipos.length > 1 ? 'mixto' : primero.tipo;
    fila.pais = primero.pais; fila.banco = primero.banco; fila.monto_usd = primero.monto_usd; fila.monto_local = primero.monto_local; fila.moneda = primero.moneda;
    fila.datos = Object.assign(fila.datos, { n_registros: registros.length, registros: registros.map(r => ({ tipo: r.tipo, pais: r.pais, banco: r.banco, monto_usd: r.monto_usd, monto_local: r.monto_local,
                                                                                     moneda: r.moneda, datos: r.datos })) });
  } else {
    const q = preguntaDe(b);
    if (q){ fila.tipo = 'pregunta'; fila.datos = Object.assign(fila.datos, q); }
  }
}
// Quien escribio (el nombre que tiene en WhatsApp): sirve para reconocer a cada operador.
if (ev.pushName) fila.datos.autor_nombre = String(ev.pushName).slice(0, 60);
return [{ json: fila }];
'@

# ===================== CODIGO: DECIDIR (dedupe) =====================
$decidirCode = @'
// Los mensajes de grupo a veces llegan DOS veces: si este id ya se registro, se descarta.
const fila = $('Entender Mensaje').first().json;
let visto = '';
try { visto = $('Redis Leer Visto').first().json.visto; } catch(e){}
if (visto) return [];
return [{ json: fila }];
'@

$nota = @'
## Mayor: escuchar y registrar (FASE 1)
El bot principal le pasa a este workflow cada mensaje de los **grupos de clientes mayoristas** que estan en la tabla `grupos_mayor`.

**Solo entiende y registra. No envia ningun mensaje** a nadie. Guarda una fila por mensaje en `transacciones_mayor_por_whatsapp`: quien escribio, que tipo es (beneficiario, RST, RCT, captura, pregunta...) y sus datos (banco, montos, cuenta, clave...).

El pais **nunca se asume**: si no esta claro queda vacio.

Se ejecuta cuando el bot lo llama, **sin activarlo**. Credenciales: Redis memoria para Cambios JK, Supabase Cambios JK.
Se genera con `build_mayor.ps1`. No lo edites aqui: se pisa en el proximo despliegue.
'@

$nodes = @(
  [ordered]@{
    parameters = @{ content = $nota; height = 300; width = 460; color = 4 }
    id = 'c1d2e3f4-0000-4b00-8b00-mayor0000000'; name = 'Nota'; type = 'n8n-nodes-base.stickyNote'; typeVersion = 1; position = @(-40,-100)
  },
  [ordered]@{
    parameters = @{ inputSource = 'passthrough' }
    id = 'c1d2e3f4-0001-4b00-8b00-mayor0000001'; name = 'Cuando lo Llama el Bot'; type = 'n8n-nodes-base.executeWorkflowTrigger'; typeVersion = 1.1; position = @(0,300)
  },
  [ordered]@{
    parameters = @{ jsCode = $entenderCode }
    id = 'c1d2e3f4-0002-4b00-8b00-mayor0000002'; name = 'Entender Mensaje'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(176,300)
  },
  [ordered]@{
    parameters = @{ operation = 'get'; key = "={{ 'mayorMsg:' + `$json.mensaje_id }}"; keyType = 'string'; propertyName = 'visto'; options = @{} }
    id = 'c1d2e3f4-0003-4b00-8b00-mayor0000003'; name = 'Redis Leer Visto'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(352,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $decidirCode }
    id = 'c1d2e3f4-0004-4b00-8b00-mayor0000004'; name = 'Decidir'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(528,300)
  },
  [ordered]@{
    # Una fila por mensaje. mensaje_id es unico: si dos copias llegan a la vez, la segunda se rechaza
    # (onError continua) y no pasa nada.
    parameters = @{ resource = 'row'; operation = 'create'; tableId = 'transacciones_mayor_por_whatsapp'; dataToSend = 'autoMapInputData'; inputsToIgnore = '' }
    id = 'c1d2e3f4-0005-4b00-8b00-mayor0000005'; name = 'Guardar en Supabase'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(704,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $supaCred
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = "={{ 'mayorMsg:' + `$('Decidir').first().json.mensaje_id }}"; value = '1'; keyType = 'string'; expire = $true; ttl = ($HORAS_VISTO * 3600) }
    id = 'c1d2e3f4-0006-4b00-8b00-mayor0000006'; name = 'Redis Marcar Visto'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(880,300)
    onError = 'continueRegularOutput'; credentials = $redisCred
  }
)

$connections = [ordered]@{
  'Cuando lo Llama el Bot' = @{ main = @( ,@( @{ node='Entender Mensaje'; type='main'; index=0 } ) ) }
  'Entender Mensaje'       = @{ main = @( ,@( @{ node='Redis Leer Visto'; type='main'; index=0 } ) ) }
  'Redis Leer Visto'       = @{ main = @( ,@( @{ node='Decidir'; type='main'; index=0 } ) ) }
  'Decidir'                = @{ main = @( ,@( @{ node='Guardar en Supabase'; type='main'; index=0 } ) ) }
  'Guardar en Supabase'    = @{ main = @( ,@( @{ node='Redis Marcar Visto'; type='main'; index=0 } ) ) }
}

$wf = [ordered]@{
  name = 'Mayor: escuchar y registrar'
  nodes = $nodes
  connections = $connections
  settings = [ordered]@{ executionOrder = 'v1'; timezone = 'America/Guayaquil' }
}
$salida = Join-Path $PSScriptRoot 'workflow_mayor.json'
$json = $wf | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($salida, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('JSON generado: ' + $salida + ' | nodos: ' + $nodes.Count)
