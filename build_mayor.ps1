# ============================================================================
#  WORKFLOW "Mayor: escuchar y registrar"  (Cambios JK)  -  FASE 1 + FASE 2 (publicar RST/RCT)
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

# Fase 2: modo (ensayo / real), grupo de avisos, horario y reglas de los RST (ver mayor_comun.ps1).
. (Join-Path $PSScriptRoot 'mayor_comun.ps1')
$HORAS_MAPA_PUBLICACION = 24 * 7     # cuanto se recuerda que mensaje del banco corresponde a que cliente

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
// Lo que escribe el propio bot (id "3EB0...", fromMe) no se registra: desde la Fase 2 el bot publica en los
// grupos, y sin esto cada publicacion suya volveria a entrar como un RST nuevo.
if (llave.fromMe === true && /^3EB0/.test(String(llave.id))) return [];

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
  // Los grupos nuevos de cada banco se llaman exactamente como el banco (BOLIVARIANO, SOLIDARIO...): solo si el nombre es ese.
  else if (/^(bolivariano|solidario|austro|internacional)$/.test(g.trim())) r.bancoEC = g.trim();
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
  // Hasta 8 digitos: el codigo de Bolivariano puede tener 6 u 8 (protocolo, seccion 9).
  for (const m of t.matchAll(/(?:clave|codigo|cod\.?|primero|segundo)\s*[:.]?\s*(\d{3,8})(?!\d)/g)) out.push(m[1]);
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
const RX_ES_RST = /(\brst\b|clave|codigo|\bcod\b|\botp\b|primero|segundo|\bc\.?\s?[12]\s*[:.]|\b[12]\s?(?:er|do)\b)/;
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
  // Sin etiquetas ("Guayaquil / tlf / 2345 / 6543 / 500"): el banco + un telefono + numeros de codigo sueltos bastan.
  const hayCodigoSuelto = !!tels.length && !hablaDeCuenta && codigosSueltosDe(b, tels).some(c => !cedulas.includes(c));
  if (bancoEC && !cuentaVE && (RX_ES_RST.test(b) || hayCodigoSuelto || (tels.length && !hablaDeCuenta && (mon.usd !== null || mon.sinMoneda !== null)))){
    const usd = mon.usd !== null ? mon.usd : mon.sinMoneda;
    const ced = cedulasDe(b)[0] || null;
    let cods = codigosDe(b);
    // JEP: "OTP: 796988" es el codigo y "Clave: 1111" es la clave de la TARJETA (en los demas bancos "clave" es el codigo).
    let clave = null;
    if (bancoEC === 'jep'){
      const otp = (b.match(/\botp\s*[:.]?\s*(\d{3,8})(?!\d)/) || [])[1];
      clave = (b.match(/\bclave(?:\s+(?:de\s+(?:la\s+)?)?tarjeta)?\s*[:.]?\s*(\d{3,6})(?!\d)/) || [])[1] || null;
      if (otp) cods = [otp];
      else if (clave) cods = cods.filter(c => c !== clave);
    }
    let montoInferido = false;
    if (!cods.length) cods = codigosSueltosDe(b, tels).filter(c => c !== ced && c !== clave);
    // Sin etiqueta ("Guayaquil / tlf / 2345 / 6543 / 500"): el unico numero suelto de hasta 3 digitos que sobra es el monto.
    let usdFinal = usd;
    if (usdFinal === null){
      const sueltos = [...b.matchAll(/(?<![\d.,:$])(\d{2,3})(?![\d.,:])/g)].map(m => m[1]);
      if (sueltos.length === 1){ usdFinal = parseFloat(sueltos[0]); montoInferido = true; }
    }
    const hora = (b.match(/\b(\d{1,2}:\d{2})\b/) || [])[1] || null;
    return { tipo: 'rst', pais: 'Ecuador', banco: BANCOS_EC[bancoEC], monto_usd: usdFinal, monto_local: null, moneda: 'USD',
             datos: { destino_sugerido: GRUPO_RST[bancoEC] || null, telefono: tels[0] || null, codigos: cods, cedula: ced, clave, hora, monto_inferido: montoInferido || undefined }, bloque };
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
    // Foto con un RST escrito en el PIE: ese texto se entiende como cualquier RST (el bot no lee la foto, solo el pie).
    // Si el pie habla de un retiro y no se entiende, se le pide al cliente que lo mande en texto (pide_texto).
    // Las demas fotos (capturas de pagos) no se tocan.
    if (!hablaNuestro){
      const regs = registrosDe(limpio).filter(r => r.tipo === 'rst' || r.tipo === 'rct');
      if (regs.length){
        fila.datos = Object.assign(fila.datos, { n_registros: regs.length, es_foto: true, registros: regs.map(r => ({ tipo: r.tipo, pais: r.pais, banco: r.banco, monto_usd: r.monto_usd,
                                                                                         monto_local: r.monto_local, moneda: r.moneda, datos: r.datos })) });
      } else if (/\b(rst|retiro|retira|retirar)\b/.test(b) && bancoEcuadorDe(b)) fila.datos.pide_texto = true;
    }
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
// A que mensaje responde (la cita): sirve para reconocer cuando un banco responde a UNA publicacion nuestra.
try {
  const ctx = ev.contextInfo || (msg.extendedTextMessage && msg.extendedTextMessage.contextInfo) || (msg.imageMessage && msg.imageMessage.contextInfo) || {};
  if (ctx.stanzaId) fila.datos.cita_id = String(ctx.stanzaId);
} catch(e){}
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

# ===================== CODIGO: ¿HACE FALTA PUBLICAR? (Fase 2) =====================
$hacePublicarCode = @'
// ===== ¿HACE FALTA PUBLICAR ALGO? =====
// Un filtro barato: casi todos los mensajes de los grupos NO son un retiro, y asi no se consulta Redis ni
// Supabase para ellos. Pasa solo:
//   - un RST/RCT (o una foto que habla de un retiro) que escribio el CLIENTE o su operador extra en su grupo;
//   - una respuesta en un grupo de DESTINO ("Verificar", "se dañó"...) que cita un mensaje;
//   - Solidario: el cobrador que cita nuestro RST y escribe "temporal" (la clave temporal en vivo), o el cliente que la manda;
//   - JEP: un cliente que QUIERE hacer un RST ("quiero retirar por JEP") aunque no mande datos, o el cobrador
//     que avisa en el grupo de JEP, citando nuestro mensaje, que ya esta en el cajero ("listo, ya estoy aca").
// Lo que Kelvin o la operadora escriban en un grupo de cliente nunca dispara nada.
__PUBLICAR_COMUN__
const fila = $('Decidir').first().json;
const ent = $('Cuando lo Llama el Bot').first().json || {};
const grupo = ent.grupo || {};
const guardada = $('Guardar en Supabase').first().json || {};
if (!guardada.id) return [];                          // no se pudo guardar (mensaje repetido): no se publica nada
const d = fila.datos || {};
const regs = Array.isArray(d.registros) ? d.registros : [];
const hayRetiro = regs.some(r => r.tipo === 'rst' || r.tipo === 'rct');
const delCliente = fila.autor_rol === 'cliente' || fila.autor_rol === 'operador_extra';
const t = String(fila.texto || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
// (un mensaje con UN numero de 6 digitos puede ser la clave temporal de Solidario que el cobrador pidio: "Decidir Publicacion" lo confirma)
if (grupo.tipo === 'cliente' && delCliente && (hayRetiro || d.pide_texto || quiereJep(fila.texto) || codigoTemporalDe(fila.texto))) return [{ json: { motivo: 'cliente' } }];
if (grupo.tipo === 'destino' && d.cita_id && /verific|correg|corrij|\bdan(o|ado)\b|salio dan|se dano/.test(t)) return [{ json: { motivo: 'banco' } }];
if (grupo.tipo === 'destino' && d.cita_id && /\bjep\b/.test(quitar(grupo.nombre)) && cobradorListo(fila.texto)) return [{ json: { motivo: 'jep' } }];
if (grupo.tipo === 'destino' && d.cita_id && pideTemporal(fila.texto)) return [{ json: { motivo: 'temporal' } }];
return [];
'@
$hacePublicarCode = $hacePublicarCode.Replace('__PUBLICAR_COMUN__', $publicarJs)

# ===================== CODIGO: DECIDIR PUBLICACION (Fase 2) =====================
$decidirPublicacionCode = @'
// ===== MAYOR, FASE 2: QUE SE PUBLICA, DONDE Y A QUIEN SE LE CONTESTA =====
// Reglas de "EJEMPLOS PARA EL BOT/protocolo_rst_rct.md" y de Kelvin (24/11). Sale una lista de ENVIOS: cada
// item es UN mensaje de WhatsApp (texto o sticker). Este nodo no manda nada; los manda "Enviar".
//
//   RST/RCT completo del cliente  -> bloque al grupo del banco (en horario) o a COBRAR MAÑANA (fuera de horario;
//                                    los que se vencen el mismo dia llevan "cobrar hoy") + sticker "RST Recibido"
//   RST/RCT incompleto            -> al cliente, citando su mensaje: que datos faltan
//   foto con pie de retiro        -> al cliente: que lo mande en texto
//   el banco cita nuestra publicacion con "Verificar" / "se dañó" -> al banco y al cliente
//
// MODO 'ensayo': NADA sale a bancos ni a clientes; todo va junto, como vista previa, al grupo de avisos.
// MODO 'real': publica, pero solo para los grupos de clientes con grupos_mayor.publicar = true.
// Nunca se escribe a un grupo que no este en la tabla grupos_mayor (lista blanca), salvo avisos y el grupo del propio cliente.
const MODO = '__MODO__';
const GRUPO_AVISOS = '__GRUPO_AVISOS__';
const STICKER_RST = '__STICKER_BASE__sticker-rst-recibido.webp';
__HORARIO_JK__
__PUBLICAR_COMUN__
const TEXTO_FOTO = 'Por favor envíe todos los datos en texto escrito para poder procesar su retiro.';
const TEXTO_BANCO_VERIFICAR = 'ok, procedo a mandar a verificar y corregir';
const TEXTO_CLIENTE_VERIFICAR = 'Por favor verifique, corrija y envíe nuevamente todos los datos en un solo texto.';
const TEXTO_CLIENTE_DANADO = 'Estimado cliente, su código se dañó / no pudo ser cobrado. Por favor genere un nuevo código de retiro para poder saldar el saldo pendiente.';

const ent = $('Cuando lo Llama el Bot').first().json || {};
const grupo = ent.grupo || {};
const fila = $('Decidir').first().json;
const datos = fila.datos || {};
const filaId = ($('Guardar en Supabase').first().json || {}).id;
if (!filaId) return [];
// "Redis Leer Publicacion" lee UNA clave y su significado depende del grupo: en un grupo de DESTINO es la publicacion
// que el banco cito (mayorPub:<id>); en un grupo de CLIENTE es el permiso de JEP de ese cliente (jepPend:<grupo>).
let leido = null;
try { const raw = $('Redis Leer Publicacion').first().json.pub; if (raw) leido = (typeof raw === 'string') ? JSON.parse(raw) : raw; } catch(e){ leido = null; }
const pub = (grupo.tipo === 'cliente') ? null : leido;
const jepEstado = (grupo.tipo === 'cliente' && leido && leido.estado) ? leido : null;
// "Redis Leer Temporal": en un grupo de CLIENTE, si el cobrador de Solidario le pidio la clave temporal (solPend:<grupo>).
let leidoTmp = null;
try { const raw = $('Redis Leer Temporal').first().json.temporal; if (raw) leidoTmp = (typeof raw === 'string') ? JSON.parse(raw) : raw; } catch(e){ leidoTmp = null; }
const solEstado = (grupo.tipo === 'cliente' && leidoTmp && leidoTmp.estado) ? leidoTmp : null;
const destinos = {};          // nombre del grupo (sin acentos) -> su id, solo los de la tabla
try { for (const it of $('Grupos Destino').all()){ const g = it.json || {}; if (g.grupo_jid && g.nombre && g.activo !== false) destinos[quitar(g.nombre)] = g.grupo_jid; } } catch(e){}
const abierto = horarioDe(Date.now()).abierto;
const nombre = String(fila.cliente_nombre || 'Cliente');

const envios = [];
let estadoFila = '', grupoDestinoFila = '', real = false;

if (grupo.tipo === 'cliente'){
  // ---------- un retiro del cliente ----------
  real = (MODO === 'real') && grupo.publicar === true;
  // Una charla NO es un pedido ("¿que tanto demora en retirar los rst de guayaquil?", "el Pichincha esta fallando la
  // opcion de RST"): sin ningun dato (ni monto, ni telefono, ni cedula, ni codigo) no se le pide nada a nadie; y
  // una pregunta con datos incompletos tampoco.
  const preguntando = /[?¿]/.test(String(fila.texto || ''));
  const hayDatos = r => (r.monto_usd !== null && r.monto_usd !== undefined) || (r.tipo !== 'rct' && !!(r.datos && (r.datos.telefono || r.datos.cedula || r.datos.clave || (r.datos.codigos || []).length)));
  const regs = (Array.isArray(datos.registros) ? datos.registros : []).filter(r => r.tipo === 'rst' || r.tipo === 'rct')
    .filter(r => (r.tipo === 'rct' ? !preguntando || faltan(r).length === 0 : hayDatos(r) && (!preguntando || faltan(r).length === 0)));
  const incompletos = [], sinGrupo = [], publicados = [], jepMontos = [];
  const enCajero = !!(jepEstado && jepEstado.estado === 'en_cajero');          // el cobrador ya avisó que está en el cajero
  const jepEsperando = !!(jepEstado && jepEstado.estado === 'esperando');       // ya se le pidió al cobrador, todavía no avisa
  let jepPide = false;
  // ---------- SOLIDARIO: el cliente manda la clave TEMPORAL que el cobrador le pidio (protocolo, seccion 9) ----------
  // "B. Solidario te informa tu clave temporal para retiro de efectivo es 919180..." parece un RST (dice banco y clave), pero si el cobrador
  // la pidio hace poco y el mensaje trae UN solo numero de 6 digitos y ningun RST completo, es la clave temporal: se le entrega al grupo.
  const claveTmp = (solEstado && solEstado.estado === 'pide_temporal') ? codigoTemporalDe(fila.texto) : '';
  const esTemporal = !!claveTmp && !regs.some(r => r.tipo === 'rst' && faltan(r).length === 0 && revisar(r).length === 0);
  if (esTemporal){
    const jidSol = solEstado.grupo_jid;
    if (real && Object.keys(destinos).every(k => destinos[k] !== jidSol)){
      const aviso = '⚠️ ' + nombre + ': su clave temporal de Solidario NO se entregó (el grupo no está en la tabla). Pásala a mano: está en su mensaje en ' + (grupo.nombre || 'su grupo') + '.';
      envios.push({ etapa: 'aviso', tipo: 'texto', jid: GRUPO_AVISOS, texto: aviso, vista: aviso });
      estadoFila = 'sin_grupo';
    } else {
      // Primero a la mano del cobrador (que esta frente al cajero con la clave corriendo), despues el "Ok, recibido" al cliente.
      envios.push({ etapa: 'banco', tipo: 'texto', jid: jidSol, texto: String(fila.texto).trim(), citar: solEstado.id_pub,
                    vista: '➡️ iría a SOLIDARIO (citando el RST): "' + String(fila.texto).trim().replace(claveTmp, ocultar(claveTmp)) + '"',
                    redisSet: [{ clave: 'solPend:' + grupo.grupo_jid, valor: JSON.stringify({ estado: 'usado' }), ttl: 60 }] });
      envios.push({ etapa: 'cliente', tipo: 'texto', jid: grupo.grupo_jid, texto: TEXTO_TEMP_RECIBIDO, citar: fila.mensaje_id, vista: '➡️ al cliente (citando su mensaje): "' + TEXTO_TEMP_RECIBIDO + '"' });
      estadoFila = 'temporal_enviado'; grupoDestinoFila = 'SOLIDARIO';
    }
  }
  for (const reg of (esTemporal ? [] : regs)){
    const k = claveBanco(reg);
    // JEP: el codigo dura 15 minutos. Hasta que el cobrador avise que ya esta en el cajero NO se publica nada: se le pide al
    // cobrador que vaya y al cliente que espere (protocolo, seccion 10). Con ese permiso, se publica enseguida.
    if (k === 'jep' && reg.tipo === 'rst' && !enCajero){ jepPide = true; if (reg.monto_usd !== null && reg.monto_usd !== undefined) jepMontos.push(reg.monto_usd); continue; }
    const f = faltan(reg), rv = revisar(reg);                                // lo que falta y lo que viene con el largo equivocado
    if (f.length || rv.length){ incompletos.push({ reg, f, rv }); continue; }
    const dueno = GRUPO_DEL_BANCO[k];
    const conPermisoJep = (k === 'jep' && reg.tipo === 'rst' && enCajero);     // el cobrador ya esta ahi: va directo a JEP, sea la hora que sea
    const enBanco = abierto || conPermisoJep;                                   // en el grupo del banco (y no en COBRAR MAÑANA)
    const destinoClave = enBanco ? dueno : GRUPO_COBRAR_MANANA;
    const jid = destinoClave ? destinos[destinoClave] : null;
    if (!dueno || (real && !jid)){ sinGrupo.push({ reg, donde: !dueno ? 'ese banco no tiene grupo' : ('no encuentro el grupo ' + NOMBRE_GRUPO(destinoClave)) }); continue; }
    const hoy = !enBanco && DURA_24H.indexOf(k) === -1;                    // se vence el mismo dia
    const texto = bloque(nombre, reg, false) + (hoy ? '\n' + AVISO_COBRAR_HOY : '');
    const vistaTexto = bloque(nombre, reg, true) + (hoy ? '\n' + AVISO_COBRAR_HOY : '');
    publicados.push({ k, destinoClave, estado: enBanco ? 'publicado' : (hoy ? 'cobrar_hoy' : 'en_cobrar_manana') });
    envios.push({ etapa: 'banco', tipo: 'texto', jid, texto,
                  vista: '➡️ iría a ' + NOMBRE_GRUPO(destinoClave) + (enBanco ? '' : ' (fuera de horario)') + (jid ? '' : ' (grupo todavía no cargado en la tabla)') + ':\n' + vistaTexto,
                  mapa: { cliente_jid: grupo.grupo_jid, cliente_nombre: nombre, id_msg_cliente: fila.mensaje_id, banco: reg.banco, tipo: reg.tipo, fila_id: filaId, destino: NOMBRE_GRUPO(destinoClave) },
                  // Alerta de vencimiento: un RST que quedo en el grupo de su banco se vigila (en COBRAR MAÑANA no: ahi todavia no corre el reloj del banco).
                  vigila: (enBanco && reg.tipo === 'rst') ? { banco: k, recibido: fila.fecha_mensaje || new Date().toISOString(), resumen: nombre + ' · ' + String(reg.banco || '').toUpperCase() + ' ' + fmtMonto(reg.monto_usd) + '$' } : undefined,
                  redisSet: conPermisoJep ? [{ clave: 'jepPend:' + grupo.grupo_jid, valor: JSON.stringify({ estado: 'usado' }), ttl: 60 }] : undefined });
  }
  if (publicados.length){
    envios.unshift({ etapa: 'cliente', tipo: 'sticker', jid: grupo.grupo_jid, sticker: STICKER_RST, vista: '➡️ al cliente: sticker "RST Recibido"' });
    // El estado de la fila es el mas "pendiente" de sus retiros: si trae uno de 24 h esperando en COBRAR MAÑANA, la fila
    // queda en_cobrar_manana para que el workflow de la mañana lo pase al abrir (aunque otro sea de "cobrar hoy").
    const PESO = { en_cobrar_manana: 3, cobrar_hoy: 2, publicado: 1 };
    estadoFila = publicados.map(p => p.estado).sort((a, b) => PESO[b] - PESO[a])[0];
    grupoDestinoFila = [...new Set(publicados.map(p => NOMBRE_GRUPO(p.destinoClave)))].join(', ');
  }
  // ---------- JEP: "te avisamos cuando el cobrador esté en el cajero" (el código dura 15 minutos) ----------
  // Un pedido de JEP sin datos ("quiero retirar por JEP") tambien cuenta: no hay RST registrado, pero hay que avisar al cobrador.
  if (!jepPide && !enCajero && !esTemporal && quiereJep(fila.texto) && !regs.some(r => claveBanco(r) === 'jep')) jepPide = true;
  if (jepPide){
    const llaveJep = 'jepPend:' + grupo.grupo_jid;
    const estadoEspera = JSON.stringify({ estado: 'esperando', id_msg_cliente: fila.mensaje_id, fila_id: filaId, cliente_nombre: nombre });
    const alCliente = (texto, redisSet) => envios.push({ etapa: 'cliente', tipo: 'texto', jid: grupo.grupo_jid, texto, citar: fila.mensaje_id, redisSet,
                                                         vista: '➡️ al cliente (citando su mensaje): "' + texto + '"' });
    const jidJep = destinos[GRUPO_DEL_BANCO.jep];
    if (jepEsperando){
      alCliente(TEXTO_JEP_REPETIDO);                                       // ya se le pidio al cobrador: no se le pide dos veces
      if (!estadoFila) estadoFila = 'jep_esperando';
    } else if (abierto){
      if (real && !jidJep) sinGrupo.push({ reg: { tipo: 'rst', banco: 'JEP' }, donde: 'no encuentro el grupo ' + NOMBRE_GRUPO(GRUPO_DEL_BANCO.jep) });
      else {
        const pedido = jepSolicitud(nombre, jepMontos);
        envios.push({ etapa: 'banco', tipo: 'texto', jid: jidJep, texto: pedido, vista: '➡️ iría a ' + NOMBRE_GRUPO(GRUPO_DEL_BANCO.jep) + (jidJep ? '' : ' (grupo todavía no cargado en la tabla)') + ':\n' + pedido,
                      mapa: { cliente_jid: grupo.grupo_jid, cliente_nombre: nombre, id_msg_cliente: fila.mensaje_id, banco: 'JEP', tipo: 'rst', fila_id: filaId, destino: NOMBRE_GRUPO(GRUPO_DEL_BANCO.jep), jep: 'solicitud' },
                      // Si en 30 minutos el cobrador no contesta, "Mayor: alertas de vencimiento" avisa en el grupo de avisos.
                      vigila: { banco: 'jep_pedido', recibido: new Date().toISOString(), resumen: nombre + ' · JEP' + (jepMontos.length ? ' ' + fmtMonto(jepMontos[0]) + '$' : '') },
                      redisSet: [{ clave: llaveJep, valor: estadoEspera, ttl: 6 * 3600 }] });
        alCliente(TEXTO_JEP_CLIENTE);
        if (!estadoFila) estadoFila = 'jep_esperando';
        grupoDestinoFila = [...new Set([grupoDestinoFila, NOMBRE_GRUPO(GRUPO_DEL_BANCO.jep)].filter(Boolean))].join(', ');
      }
    } else {
      // Fuera de horario no hay cobrador: se le dice al cliente cuando, y el pedido al cobrador sale al abrir
      // (workflow "Mayor: pasar RST al abrir" lee las filas en_cobrar_manana).
      alCliente('Te avisamos cuando el cobrador esté en el cajero, ' + horarioDe(Date.now()).cuandoAbre + ', para que realices el RST.', [{ clave: llaveJep, valor: estadoEspera, ttl: 20 * 3600 }]);
      estadoFila = 'en_cobrar_manana';
      grupoDestinoFila = [...new Set([grupoDestinoFila, NOMBRE_GRUPO(GRUPO_DEL_BANCO.jep)].filter(Boolean))].join(', ');
    }
  }
  if (incompletos.length){
    // Dos clases de problema: lo que FALTA (f) y lo que viene con el largo equivocado (rv, protocolo seccion 9).
    const cab = i => (i.reg.tipo === 'rct' ? 'retiro con tarjeta' : 'RST') + ' de ' + i.reg.banco;
    const linea = i => cab(i) + ': ' + (i.f.length ? (i.rv.length ? 'falta ' : '') + unir(i.f) + (i.rv.length ? '; ' : '') : '') + unir(i.rv);
    const soloLargo = incompletos.every(i => !i.f.length);
    let texto;
    if (incompletos.length === 1){
      const i = incompletos[0];
      texto = !i.rv.length ? 'Faltan estos datos para tu ' + cab(i) + ': ' + unir(i.f) + '. Envíalos de nuevo en un solo texto, por favor.'
            : !i.f.length ? 'Revisa tu ' + cab(i) + ': ' + unir(i.rv) + '. Corrígelo y envíalo de nuevo con todos los datos en un solo texto, por favor.'
            : 'Faltan estos datos para tu ' + cab(i) + ': ' + unir(i.f) + '. Además, ' + unir(i.rv) + '. Envíalos de nuevo en un solo texto, por favor.';
    } else {
      texto = (soloLargo ? 'Revisa los códigos de tus retiros:' : 'Faltan datos para procesar tus retiros:') + '\n' + incompletos.map(i => '• ' + linea(i)).join('\n') + '\nEnvíalos de nuevo en un solo texto, por favor.';
    }
    envios.push({ etapa: 'cliente', tipo: 'texto', jid: grupo.grupo_jid, texto, citar: fila.mensaje_id, vista: '➡️ al cliente (citando su mensaje): "' + texto + '"' });
    if (!estadoFila) estadoFila = 'falta_datos';
  }
  if (!regs.length && !esTemporal && datos.pide_texto){
    envios.push({ etapa: 'cliente', tipo: 'texto', jid: grupo.grupo_jid, texto: TEXTO_FOTO, citar: fila.mensaje_id, vista: '➡️ al cliente (citando su mensaje): "' + TEXTO_FOTO + '"' });
    estadoFila = 'pide_texto';
  }
  for (const s of sinGrupo){
    const aviso = '⚠️ ' + nombre + ': el ' + (s.reg.tipo === 'rct' ? 'retiro con tarjeta' : 'RST') + ' de ' + s.reg.banco + ' NO se publicó (' + s.donde + '). Revisa su mensaje en ' + (grupo.nombre || 'su grupo') + '.';
    envios.push({ etapa: 'aviso', tipo: 'texto', jid: GRUPO_AVISOS, texto: aviso, vista: aviso });
    if (!estadoFila) estadoFila = 'sin_grupo';
  }
} else if (grupo.tipo === 'destino' && pub && pub.cliente_jid && datos.cita_id){
  // ---------- el banco responde a UNA publicacion nuestra ----------
  // (solo existe si el bot publico de verdad; si el modo volvio a 'ensayo', no se manda nada)
  if (MODO !== 'real') return [];
  real = true;
  grupoDestinoFila = pub.destino || '';                 // la fila del cliente conserva el grupo al que se publico
  const t = quitar(fila.texto);
  if (pub.jep === 'solicitud'){
    // ---------- el cobrador de JEP contesta nuestro pedido: ya llego al cajero ----------
    if (!cobradorListo(fila.texto)) return [];
    envios.push({ etapa: 'banco', tipo: 'texto', jid: grupo.grupo_jid, texto: TEXTO_JEP_LISTO_GRUPO, citar: fila.mensaje_id, vista: '' });
    envios.push({ etapa: 'cliente', tipo: 'texto', jid: pub.cliente_jid, texto: TEXTO_JEP_LISTO_CLIENTE, citar: pub.id_msg_cliente, vista: '',
                  redisSet: [{ clave: 'jepPend:' + pub.cliente_jid, valor: JSON.stringify({ estado: 'en_cajero', id_msg_cliente: pub.id_msg_cliente, fila_id: pub.fila_id, cliente_nombre: pub.cliente_nombre }), ttl: 30 * 60 }] });
    estadoFila = 'jep_en_cajero';
  } else if (quitar(pub.banco) === 'solidario' && pideTemporal(fila.texto)){
    // ---------- Solidario: el cobrador esta frente al cajero y el banco le mando una clave TEMPORAL al cliente ----------
    // (protocolo, seccion 9): se la pedimos al cliente, citando su RST. Cuando la mande, "Decidir Publicacion" se la lleva al grupo.
    envios.push({ etapa: 'banco', tipo: 'texto', jid: grupo.grupo_jid, texto: TEXTO_TEMP_GRUPO, citar: fila.mensaje_id, vista: '' });
    envios.push({ etapa: 'cliente', tipo: 'texto', jid: pub.cliente_jid, texto: TEXTO_TEMP_CLIENTE, citar: pub.id_msg_cliente, vista: '',
                  redisSet: [{ clave: 'solPend:' + pub.cliente_jid, valor: JSON.stringify({ estado: 'pide_temporal', id_pub: datos.cita_id, grupo_jid: grupo.grupo_jid, id_msg_cliente: pub.id_msg_cliente, fila_id: pub.fila_id, cliente_nombre: pub.cliente_nombre }), ttl: 15 * 60 }] });
    estadoFila = 'temporal_pedido';
  } else {
    const danado = /\bdan(o|ado)\b|salio dan|se dano/.test(t);
    const verificar = !danado && /verific|correg|corrij/.test(t);
    if (!danado && !verificar) return [];
    if (verificar) envios.push({ etapa: 'banco', tipo: 'texto', jid: grupo.grupo_jid, texto: TEXTO_BANCO_VERIFICAR, citar: fila.mensaje_id, vista: '' });
    const textoCliente = verificar ? TEXTO_CLIENTE_VERIFICAR : TEXTO_CLIENTE_DANADO;
    envios.push({ etapa: 'cliente', tipo: 'texto', jid: pub.cliente_jid, texto: textoCliente, citar: pub.id_msg_cliente, vista: '' });
    estadoFila = verificar ? 'verificar' : 'danado';
  }
}

if (!envios.length) return [];
// La fila a la que se le anota el estado: la del cliente (en una respuesta del banco, la del RST original).
const filaDestino = (grupo.tipo === 'destino' && pub && pub.fila_id) ? pub.fila_id : filaId;

if (!real){
  // ENSAYO: nada sale a bancos ni a clientes. Una sola vista previa en el grupo de avisos.
  const vista = '🧪 ENSAYO — ' + nombre + (grupo.nombre ? ' (' + grupo.nombre + ')' : '') + '\n\n' + envios.map(e => e.vista).filter(Boolean).join('\n\n');
  return [{ json: { etapa: 'ensayo', tipo: 'texto', jid: GRUPO_AVISOS, texto: vista, fila_id: filaDestino, estado_fila: 'ensayo', grupo_destino: '' } }];
}
return envios.map(e => ({ json: Object.assign({ fila_id: filaDestino, estado_fila: estadoFila, grupo_destino: grupoDestinoFila }, e) }));
'@
$decidirPublicacionCode = $decidirPublicacionCode.Replace('__HORARIO_JK__', $horarioJs).Replace('__PUBLICAR_COMUN__', $publicarJs)
$decidirPublicacionCode = $decidirPublicacionCode.Replace('__MODO__', $MAYOR_MODO).Replace('__GRUPO_AVISOS__', $GRUPO_AVISOS).Replace('__STICKER_BASE__', $STICKER_BASE)

# ===================== CODIGO: ARMAR MAPA (Fase 2) =====================
$armarMapaCode = @'
// Despues de enviar: de cada publicacion al banco que salio bien se anota "este mensaje del banco corresponde
// a este cliente y a este RST", para poder avisarle al cliente cuando el banco responda "Verificar" o "se dañó".
// Tambien se anota lo que el envio dejaba pendiente (redisSet): el permiso de JEP del cliente ("esperando",
// "en_cajero"...). Todo se guarda con su propio tiempo de vida (ttl, en segundos; por defecto 7 dias).
const out = [];
const entradas = $input.all();
for (let i = 0; i < entradas.length; i++){
  let acc = null;
  try { acc = $('Decidir Publicacion').itemMatching(i).json; } catch(e){ continue; }
  const r = entradas[i].json || {};
  const id = (r.key && r.key.id) || (r.data && r.data.key && r.data.key.id) || '';
  if (!acc || !id || r.error) continue;
  if (acc.mapa) out.push({ json: { clave: 'mayorPub:' + id, valor: JSON.stringify(acc.mapa), ttl: 7 * 24 * 3600 } });
  for (const s of (acc.redisSet || [])) out.push({ json: { clave: s.clave, valor: s.valor, ttl: s.ttl || 7 * 24 * 3600 } });
}
return out;
'@

# ===================== CODIGO: ENTENDER COBRO (reacciones y emojis sobre los RST) =====================
$entenderCobroCode = @'
// ===== ALERTAS DE VENCIMIENTO: ¿ESTE RST YA SE COBRO? (protocolo_rst_rct.md, seccion 3 caso C y seccion 7) =====
// En los grupos de los bancos el cobrador marca cada RST:
//   - cobrado: cualquier emoji (✅, 👍, 💵...) EXCEPTO la ❌, puesto como REACCION al mensaje o como respuesta que lo cita;
//   - no cobrado: la ❌ (se dañó o hay que verificarlo), o sin ninguna marca.
// Aqui solo se ENTIENDE el cambio; "Marcar Cobro" lo anota en la tabla vigilancia_rst_mayor. Si el mensaje marcado no esta
// vigilado, no pasa nada. Quitar la reaccion (texto vacio) lo devuelve a pendiente.
// Cuando el banco cita un RST con "verificar" (y de paso le pone la ❌), el cliente ya recibe el pedido de corregirlo y el RST queda en
// "verificar": no se le avisa de vencimiento a un codigo que va a ser reemplazado, llegue primero el texto o la ❌.
const entrada = $input.first().json || {};
const grupo = entrada.grupo || {};
const ev = entrada.data || {};
if (grupo.tipo !== 'destino') return [];
const llave = ev.key || {};
function desenvolver(m){
  let x = m || {};
  for (let i = 0; i < 4; i++){
    const dentro = (x.ephemeralMessage || x.viewOnceMessage || x.viewOnceMessageV2 || x.documentWithCaptionMessage || {}).message;
    if (!dentro) break;
    x = dentro;
  }
  return x;
}
const msg = desenvolver(ev.message);
__PUBLICAR_COMUN__
const esX = e => /[❌✖❎🚫⛔]/u.test(String(e || ''));
const grupoJid = String(grupo.grupo_jid || llave.remoteJid || '');
if (!grupoJid) return [];
const enJep = /\bjep\b/.test(quitar(grupo.nombre));
// Un "verificar" o "se dañó" ya pidio un RST nuevo: una ❌ o un "pendiente" que llegue DESPUES (en cualquier orden) no lo pisa.
const salida = (mensajeId, cobro, emoji) => [{ json: { grupo_jid: grupoJid, mensaje_id: String(mensajeId), cobro, emoji, soloPendiente: cobro === 'pendiente' || cobro === 'no_cobrado' } }];

// 1) Una REACCION al mensaje (lo normal): WhatsApp la manda como un mensaje con reactionMessage; texto vacio = la quito.
if (msg.reactionMessage){
  const r = msg.reactionMessage;
  const objetivo = r.key && r.key.id;
  if (!objetivo) return [];
  const emoji = String(r.text || '').trim();
  return salida(objetivo, !emoji ? 'pendiente' : (esX(emoji) ? 'no_cobrado' : 'cobrado'), emoji);
}

// 2) Una RESPUESTA que cita el RST: solo emojis, "cobrado", o el banco pidiendo verificar / avisando que se dañó.
const texto = String(msg.conversation || (msg.extendedTextMessage && msg.extendedTextMessage.text) || '').trim();
const ctx = ev.contextInfo || (msg.extendedTextMessage && msg.extendedTextMessage.contextInfo) || {};
const cita = ctx.stanzaId ? String(ctx.stanzaId) : '';
if (!texto || !cita) return [];
const t = quitar(texto);
const soloEmoji = !/[\p{L}\p{N}]/u.test(texto) && /\p{Extended_Pictographic}/u.test(texto);
let cobro = '';
if (soloEmoji) cobro = esX(texto) ? 'no_cobrado' : 'cobrado';
else if (/\b(cobrad[oa]s?|cobre|pagad[oa]s?|retirad[oa]s?)\b/.test(t) && !/\bno\b/.test(t)) cobro = 'cobrado';
// En el grupo de JEP, el cobrador que contesta nuestro PEDIDO ("listo, ya estoy aca") lo deja atendido: ya no hay que avisar en 30 minutos.
else if (enJep && cobradorListo(texto)) cobro = 'cobrado';
else if (/\bdan(o|ado)\b|salio dan|se dano/.test(t)) cobro = 'danado';
else if (/verific|correg|corrij/.test(t)) cobro = 'verificar';
if (!cobro) return [];
return salida(cita, cobro, soloEmoji ? texto.slice(0, 16) : '');
'@
$entenderCobroCode = $entenderCobroCode.Replace('__PUBLICAR_COMUN__', $publicarJs)

# ===================== CODIGO: VIGILAR VENCIMIENTO (RST que alguien pego a mano en el grupo de un banco) =====================
$vigilarCode = @'
// ===== ALERTAS DE VENCIMIENTO: ANOTAR LOS RST QUE LLEGAN A LOS GRUPOS DE LOS BANCOS =====
// Un RST que un humano (la operadora, Kelvin...) pega en el grupo de su banco se anota con la hora en que vence, para
// avisar antes de que se pase (workflow "Mayor: alertas de vencimiento"). Los que publica el propio bot se anotan en
// "Armar Vigilancia". Solo se anotan los bancos cuya duracion dice el manual (seccion 7).
__VIGENCIA_COMUN__
const fila = $('Decidir').first().json;
const grupo = (($('Cuando lo Llama el Bot').first().json) || {}).grupo || {};
const guardada = $('Guardar en Supabase').first().json || {};
if (!guardada.id || grupo.tipo !== 'destino') return [];
const regs = ((fila.datos || {}).registros || []).filter(r => r && r.tipo === 'rst');
if (!regs.length) return [];
const recibido = Date.parse(fila.fecha_mensaje || '');
if (!(recibido > 0) || Date.now() - recibido > 30 * 60000) return [];      // un mensaje viejo que se vuelve a entregar no dispara nada
const bancoGrupo = bancoDelGrupo(grupo.nombre);
// El banco que dice el propio mensaje manda (en COOP JEP a veces se publicaba tambien Bolivariano); si no, el del grupo.
let reg = regs.find(r => vigenciaDe(r.banco, recibido)) || null;
const banco = reg ? String(reg.banco).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim() : bancoGrupo;
const v = banco ? vigenciaDe(banco, recibido) : null;
if (!v) return [];
reg = reg || regs[0];
const monto = (reg.monto_usd === null || reg.monto_usd === undefined) ? '' : ' ' + (Math.round(Number(reg.monto_usd) * 100) / 100) + '$';
const iso = ms => new Date(ms).toISOString();
return [{ json: { banco, grupo_jid: fila.grupo_jid, mensaje_id: fila.mensaje_id, resumen: (String(reg.banco || banco)).toUpperCase() + monto,
                  recibido_en: iso(recibido), vence_en: iso(v.venceMs), alerta_en: iso(v.alertaMs), origen: 'manual' } }];
'@
$vigilarCode = $vigilarCode.Replace('__VIGENCIA_COMUN__', $vigenciaJs)

# ===================== CODIGO: ARMAR VIGILANCIA (RST que publico el bot) =====================
# La plantilla vive en mayor_comun.ps1 (la comparte con el workflow de la mañana).
$armarVigilanciaCode = Get-ArmarVigilanciaCode 'Decidir Publicacion'

$nota = @'
## Mayor: escuchar, registrar y publicar RST/RCT (FASE 2)
El bot principal le pasa a este workflow cada mensaje de los **grupos del mayor** que estan en la tabla `grupos_mayor`.

**Fila de arriba (Fase 1): solo entiende y registra.** Guarda una fila por mensaje en `transacciones_mayor_por_whatsapp`: quien escribio, que tipo es (beneficiario, RST, RCT, captura, pregunta...) y sus datos. El pais **nunca se asume**.

**Fase 2 (los nodos de la derecha): publica los RST/RCT** del cliente en el grupo del banco (de noche, en COBRAR MAÑANA) y le contesta al cliente, segun `protocolo_rst_rct.md`. Si el banco cita la publicacion con "Verificar" o "se dañó", avisa al cliente.

**Modo ENSAYO** (`$MAYOR_MODO` en `mayor_comun.ps1`): nada sale a bancos ni a clientes; cada caso se muestra como vista previa en el grupo de avisos. Modo real: solo en los grupos con `publicar = true`.

**JEP**: su codigo dura 15 minutos, asi que el bot NO lo publica de inmediato: le dice al cliente "te avisamos cuando el cobrador este en el cajero", le pide al cobrador (en el grupo de JEP) que vaya a un cajero y avise citando el mensaje, y cuando el cobrador escribe "listo, ya estoy aca" le dice al cliente que haga el RST y lo envie. Solo entonces lo publica.

**Largo de los codigos** (protocolo, seccion 9): Pichincha 4 digitos, Produbanco 6, Guayaquil dos de 4, Pacifico 6, Solidario 6, Bolivariano 6 u 8, JEP codigo 6 + clave de la tarjeta 4. Si el largo no es el que toca, no se publica: se le pide al cliente que lo revise.

**Solidario, clave temporal**: el cobrador cita el RST en el grupo de Solidario y escribe "temporal"; el bot se la pide al cliente, le dice "Ok, recibido" y se la entrega al grupo citando el RST.

**Alertas de vencimiento** (filas de abajo): cada RST que esta en el grupo de su banco se anota en `vigilancia_rst_mayor` con su hora de vencimiento (los pegados a mano y los del bot). Las reacciones de los cobradores (cualquier emoji menos la X = cobrado) se anotan alli. El workflow "Mayor: alertas de vencimiento" avisa en el grupo del banco, citando el RST, cuando falta 1 hora (5 min en JEP) y nadie lo marco como cobrado.

Se ejecuta cuando el bot lo llama, **sin activarlo**. Credenciales: Redis memoria para Cambios JK, Supabase Cambios JK.
Se genera con `build_mayor.ps1`. No lo edites aqui: se pisa en el proximo despliegue.
'@

$nodes = @(
  [ordered]@{
    parameters = @{ content = $nota; height = 720; width = 520; color = 4 }
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
  },
  # ----- FASE 2: publicar los RST / RCT (la fila de arriba solo registra; esta sigue a la derecha) -----
  [ordered]@{
    # Filtro barato: solo pasa un retiro del cliente, o una respuesta de un banco ("Verificar", "se dañó").
    parameters = @{ jsCode = $hacePublicarCode }
    id = 'c1d2e3f4-0010-4b00-8b00-mayor0000010'; name = 'Hace Falta Publicar?'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1056,300)
  },
  [ordered]@{
    # ¿El mensaje que cito el banco es una publicacion nuestra? Esa es toda la autorizacion para contestarle al cliente.
    # Una sola lectura con dos significados segun el grupo: en uno de DESTINO, la publicacion que citaron (mayorPub:<id>);
    # en uno de CLIENTE, el permiso de JEP de ese cliente (jepPend:<grupo>). "Decidir Publicacion" los separa.
    parameters = @{ operation = 'get'; key = "={{ (`$('Cuando lo Llama el Bot').first().json.grupo.tipo === 'cliente') ? ('jepPend:' + `$('Cuando lo Llama el Bot').first().json.grupo.grupo_jid) : ('mayorPub:' + ((`$('Decidir').first().json.datos || {}).cita_id || 'sin-cita')) }}"; keyType = 'string'; propertyName = 'pub'; options = @{} }
    id = 'c1d2e3f4-0011-4b00-8b00-mayor0000011'; name = 'Redis Leer Publicacion'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1232,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $redisCred
  },
  [ordered]@{
    # ¿Hay una clave TEMPORAL de Solidario pedida a este cliente? (solPend:<grupo>). Solo importa en los grupos de cliente.
    # Va debajo de la fila para no mover los nodos que ya estaban acomodados.
    parameters = @{ operation = 'get'; key = "={{ (`$('Cuando lo Llama el Bot').first().json.grupo.tipo === 'cliente') ? ('solPend:' + `$('Cuando lo Llama el Bot').first().json.grupo.grupo_jid) : 'solPend:sin-cliente' }}"; keyType = 'string'; propertyName = 'temporal'; options = @{} }
    id = 'c1d2e3f4-0026-4b00-8b00-mayor0000026'; name = 'Redis Leer Temporal'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1320,480)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $redisCred
  },
  [ordered]@{
    # Los grupos de destino (bancos, COBRAR MAÑANA...): sus ids salen de la tabla, nunca del codigo. Es la lista blanca.
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'grupos_mayor'; returnAll = $true; filterType = 'string'; filterString = 'tipo=eq.destino' }
    id = 'c1d2e3f4-0012-4b00-8b00-mayor0000012'; name = 'Grupos Destino'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(1408,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $supaCred
  },
  [ordered]@{
    parameters = @{ jsCode = $decidirPublicacionCode }
    id = 'c1d2e3f4-0013-4b00-8b00-mayor0000013'; name = 'Decidir Publicacion'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1584,300)
  },
  [ordered]@{
    # UN nodo para texto y sticker. En modo ensayo el unico destino es el grupo de avisos.
    parameters = @{ method = 'POST'; url = '={{ "http://evolution-api:8080/message/" + ($json.tipo === "sticker" ? "sendSticker" : "sendText") + "/BOT%20JK%20Kelvin" }}'
                    authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true
                    headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'
                    jsonBody = '={{ JSON.stringify($json.tipo === "sticker" ? { number: $json.jid, sticker: $json.sticker } : Object.assign({ number: $json.jid, text: $json.texto }, $json.citar ? { quoted: { key: { id: $json.citar } } } : {})) }}'
                    options = @{} }
    id = 'c1d2e3f4-0014-4b00-8b00-mayor0000014'; name = 'Enviar'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1760,300)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = $evoHeaderCred
  },
  [ordered]@{
    # Si fallo y llevaba cita (el mensaje citado a veces ya no esta en Evolution), se reintenta SIN cita:
    # una cita que no funcione nunca puede dejar a un cliente sin su respuesta.
    parameters = @{ conditions = @{ boolean = @( @{ value1 = '={{ !!$json.error && !!$("Decidir Publicacion").item.json.citar }}'; value2 = '={{true}}' } ) } }
    id = 'c1d2e3f4-0015-4b00-8b00-mayor0000015'; name = 'Fallo la Cita?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(1936,300)
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = '={{ "http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin" }}'
                    authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true
                    headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'
                    jsonBody = '={{ JSON.stringify({ number: $("Decidir Publicacion").item.json.jid, text: $("Decidir Publicacion").item.json.texto }) }}'
                    options = @{} }
    id = 'c1d2e3f4-0016-4b00-8b00-mayor0000016'; name = 'Reenviar sin Cita'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(2112,480)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = $evoHeaderCred
  },
  [ordered]@{
    # La fila del mensaje queda con su estado (publicado, falta_datos, ensayo...). Si el envio fallo: error_envio.
    parameters = @{ resource = 'row'; operation = 'update'; tableId = 'transacciones_mayor_por_whatsapp'; filterType = 'string'
                    filterString = '={{ "id=eq." + $("Decidir Publicacion").item.json.fila_id }}'; dataToSend = 'defineBelow'
                    fieldsUi = @{ fieldValues = @(
                      @{ fieldId = 'estado'; fieldValue = '={{ $json.error ? "error_envio" : $("Decidir Publicacion").item.json.estado_fila }}' },
                      @{ fieldId = 'grupo_destino'; fieldValue = '={{ $("Decidir Publicacion").item.json.grupo_destino || "" }}' } ) } }
    id = 'c1d2e3f4-0017-4b00-8b00-mayor0000017'; name = 'Actualizar Fila'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(2288,120)
    onError = 'continueRegularOutput'; credentials = $supaCred
  },
  [ordered]@{
    parameters = @{ jsCode = $armarMapaCode }
    id = 'c1d2e3f4-0018-4b00-8b00-mayor0000018'; name = 'Armar Mapa'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2288,300)
  },
  [ordered]@{
    # Cada valor trae su propio tiempo de vida (ttl en segundos): la publicacion 7 dias, el permiso de JEP unas horas o minutos.
    parameters = @{ operation = 'set'; key = '={{ $json.clave }}'; value = '={{ $json.valor }}'; keyType = 'string'; expire = $true; ttl = ('={{ $json.ttl || ' + ($HORAS_MAPA_PUBLICACION * 3600) + ' }}') }
    id = 'c1d2e3f4-0019-4b00-8b00-mayor0000019'; name = 'Redis Guardar Publicacion'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(2464,300)
    onError = 'continueRegularOutput'; credentials = $redisCred
  },
  # ----- ALERTAS DE VENCIMIENTO (protocolo, seccion 7): reacciones de los cobradores y RST vigilados -----
  [ordered]@{
    # Una reaccion (o una respuesta con emoji) a un mensaje de un grupo de banco: cobrado / no cobrado. No registra ninguna fila.
    parameters = @{ jsCode = $entenderCobroCode }
    id = 'c1d2e3f4-0020-4b00-8b00-mayor0000020'; name = 'Entender Cobro'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(176,700)
  },
  [ordered]@{
    # Anota el estado en la tabla vigilancia_rst_mayor. Si ese mensaje no esta vigilado, no actualiza nada.
    parameters = @{ resource = 'row'; operation = 'update'; tableId = 'vigilancia_rst_mayor'; filterType = 'string'
                    # Una X o un "pendiente" nunca pisa un "verificar" / "se dañó" (ya se pidio un RST nuevo).
                    filterString = '={{ "grupo_jid=eq." + $json.grupo_jid + "&mensaje_id=eq." + $json.mensaje_id + ($json.soloPendiente ? "&cobro=not.in.(verificar,danado)" : "") }}'; dataToSend = 'defineBelow'
                    fieldsUi = @{ fieldValues = @(
                      @{ fieldId = 'cobro'; fieldValue = '={{ $json.cobro }}' },
                      @{ fieldId = 'cobro_en'; fieldValue = '={{ new Date().toISOString() }}' },
                      @{ fieldId = 'cobro_emoji'; fieldValue = '={{ $json.emoji || "" }}' } ) } }
    id = 'c1d2e3f4-0021-4b00-8b00-mayor0000021'; name = 'Marcar Cobro'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(352,700)
    onError = 'continueRegularOutput'; credentials = $supaCred
  },
  [ordered]@{
    # Un RST que alguien pego a mano en el grupo de su banco: se anota con su hora de vencimiento.
    parameters = @{ jsCode = $vigilarCode }
    id = 'c1d2e3f4-0022-4b00-8b00-mayor0000022'; name = 'Vigilar Vencimiento'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1056,900)
  },
  [ordered]@{
    parameters = @{ resource = 'row'; operation = 'create'; tableId = 'vigilancia_rst_mayor'; dataToSend = 'autoMapInputData'; inputsToIgnore = '' }
    id = 'c1d2e3f4-0023-4b00-8b00-mayor0000023'; name = 'Anotar Vigilancia Manual'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(1232,900)
    onError = 'continueRegularOutput'; credentials = $supaCred
  },
  [ordered]@{
    # Un RST que publico el propio bot en el grupo de su banco (solo en modo real).
    parameters = @{ jsCode = $armarVigilanciaCode }
    id = 'c1d2e3f4-0024-4b00-8b00-mayor0000024'; name = 'Armar Vigilancia'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2288,900)
  },
  [ordered]@{
    parameters = @{ resource = 'row'; operation = 'create'; tableId = 'vigilancia_rst_mayor'; dataToSend = 'autoMapInputData'; inputsToIgnore = '' }
    id = 'c1d2e3f4-0025-4b00-8b00-mayor0000025'; name = 'Anotar Vigilancia Bot'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(2464,900)
    onError = 'continueRegularOutput'; credentials = $supaCred
  }
)

$connections = [ordered]@{
  # Del disparador salen dos ramas: la de siempre (entender y registrar) y la de las reacciones de los cobradores.
  'Cuando lo Llama el Bot' = @{ main = @( ,@( @{ node='Entender Mensaje'; type='main'; index=0 }, @{ node='Entender Cobro'; type='main'; index=0 } ) ) }
  'Entender Cobro'         = @{ main = @( ,@( @{ node='Marcar Cobro'; type='main'; index=0 } ) ) }
  'Vigilar Vencimiento'    = @{ main = @( ,@( @{ node='Anotar Vigilancia Manual'; type='main'; index=0 } ) ) }
  'Armar Vigilancia'       = @{ main = @( ,@( @{ node='Anotar Vigilancia Bot'; type='main'; index=0 } ) ) }
  'Entender Mensaje'       = @{ main = @( ,@( @{ node='Redis Leer Visto'; type='main'; index=0 } ) ) }
  'Redis Leer Visto'       = @{ main = @( ,@( @{ node='Decidir'; type='main'; index=0 } ) ) }
  'Decidir'                = @{ main = @( ,@( @{ node='Guardar en Supabase'; type='main'; index=0 } ) ) }
  'Guardar en Supabase'    = @{ main = @( ,@( @{ node='Redis Marcar Visto'; type='main'; index=0 } ) ) }
  # Fase 2
  'Redis Marcar Visto'     = @{ main = @( ,@( @{ node='Hace Falta Publicar?'; type='main'; index=0 }, @{ node='Vigilar Vencimiento'; type='main'; index=0 } ) ) }
  'Hace Falta Publicar?'   = @{ main = @( ,@( @{ node='Redis Leer Publicacion'; type='main'; index=0 } ) ) }
  'Redis Leer Publicacion' = @{ main = @( ,@( @{ node='Redis Leer Temporal'; type='main'; index=0 } ) ) }
  'Redis Leer Temporal'    = @{ main = @( ,@( @{ node='Grupos Destino'; type='main'; index=0 } ) ) }
  'Grupos Destino'         = @{ main = @( ,@( @{ node='Decidir Publicacion'; type='main'; index=0 } ) ) }
  'Decidir Publicacion'    = @{ main = @( ,@( @{ node='Enviar'; type='main'; index=0 } ) ) }
  'Enviar'                 = @{ main = @( ,@( @{ node='Fallo la Cita?'; type='main'; index=0 } ) ) }
  'Fallo la Cita?'         = @{ main = (
      @( ,@( @{ node='Reenviar sin Cita'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Armar Mapa'; type='main'; index=0 }, @{ node='Actualizar Fila'; type='main'; index=0 }, @{ node='Armar Vigilancia'; type='main'; index=0 } ) )
    ) }
  'Reenviar sin Cita'      = @{ main = @( ,@( @{ node='Armar Mapa'; type='main'; index=0 }, @{ node='Actualizar Fila'; type='main'; index=0 }, @{ node='Armar Vigilancia'; type='main'; index=0 } ) ) }
  'Armar Mapa'             = @{ main = @( ,@( @{ node='Redis Guardar Publicacion'; type='main'; index=0 } ) ) }
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
