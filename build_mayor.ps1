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
# La hoja de tasas publicada (la misma de src/constants.js y del bot del detal): precios de BINANCE / ZELLE del mayor (27/11).
$URL_HOJA_TASAS = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv'

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
// OJO: 'senderKeyDistributionMessage' NO va en esta lista. Es la "llave del grupo" que WhatsApp le PEGA al primer mensaje
// que alguien manda en un rato (junto al texto, la foto o el audio). Estuvo aqui hasta el 26/11 y el bot tiraba ese mensaje
// entero: en 48 h se perdieron ~200 mensajes, entre ellos 8 RST y 8 pedidos de clientes. Un mensaje que solo trae la
// llave (sin texto, foto ni audio) igual se descarta mas abajo, por no tener contenido.
const IGNORAR = ['stickerMessage', 'reactionMessage', 'encReactionMessage', 'protocolMessage', 'albumMessage', 'pollUpdateMessage'];
if (IGNORAR.some(k => msg[k] !== undefined)) return [];

const textoCrudo = String(msg.conversation || (msg.extendedTextMessage && msg.extendedTextMessage.text)
  || (msg.imageMessage && msg.imageMessage.caption) || (msg.videoMessage && msg.videoMessage.caption)
  || (msg.documentMessage && msg.documentMessage.caption) || '').trim();
const esImagen = !!msg.imageMessage, esAudio = !!msg.audioMessage;
// Una EDICION de un mensaje llega como secretEncryptedMessage: trae el id del mensaje original en
// targetMessageKey y el texto nuevo CIFRADO. Evolution no lo descifra, asi que NO hay forma de leer lo que
// quedo escrito; lo unico que se sabe es CUAL mensaje cambio. Paso el 26/11: una clienta edito el codigo de
// su RST en vez de reenviarlo y el bot se quedo con el viejo, sin enterarse. Se registra la edicion para que
// la Fase 2 le pida que lo mande de nuevo.
const editado = (msg.secretEncryptedMessage && msg.secretEncryptedMessage.targetMessageKey && msg.secretEncryptedMessage.targetMessageKey.id)
  ? String(msg.secretEncryptedMessage.targetMessageKey.id) : '';
if (!textoCrudo && !esImagen && !esAudio && !editado) return [];

// Los numeros escritos con emojis ("6️⃣6️⃣5️⃣") se vuelven digitos. PERO un emoji de numero SOLO al inicio de una linea y
// separado por un espacio ("1️⃣ 2403" / "2️⃣ 2790", como los manda Julio) es el ROTULO del codigo 1 y el codigo 2 de
// Guayaquil: se vuelve "C1: 2403". Antes se volvia "1 2403" y ese 1 se tomaba como el monto ("$1", 25/11).
// Los emojis de plata (bolsa, signo de dolar, billete) se vuelven "$": "1️⃣4️⃣8️⃣💰" es 148$. Antes el monto
// quedaba vacio porque el 💰 no contaba como moneda (Elvis Martinez, 26/11). El euro, la libra y el yen no.
const limpio = textoCrudo.normalize('NFKC').replace(/(^|\n)[ \t]*([12])️?⃣[ \t]+(?=\d)/g, '$1C$2: ')
  .replace(/([0-9])️?⃣/g, '$1').replace(/[\u{1F4B0}\u{1F4B2}\u{1F4B5}]️?/gu, () => '$').replace(/[​-‏‪-‮]/g, '');
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
    // El "$" nunca salta de linea: "monto 500$" + (otra linea) "1 2403" -> el $ es del 500, no del 1 (25/11).
    if (/\$[ \t]*$/.test(antes)) { t.marca = 'usd'; continue; }
    if (/^\s*(usdt|usd|dolares|dls|\$)/.test(despues)){
      const sig = toks[i + 1];
      const pegaConElQueSigue = /^\s*\$/.test(despues) && sig && !sig.ruido && sig.marca !== 'local' && /^\s*\$[ \t]*$/.test(b.slice(t.fin, sig.ini));
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
  // Una cuenta de Venezuela sola en su renglon con espacios o guiones donde caigan ("0102 05182300 0007 2054", protocolo de
  // pedidos 27/11): si el renglon es solo numeros y al quitar los separadores quedan 20 digitos que empiezan por 01, es UNA cuenta.
  b = String(b).split('\n').map(l => { const d = l.replace(/[\s.\-]/g, ''); return (/^[\d\s.\-]+$/.test(l.trim()) && /^01\d{18}$/.test(d)) ? d : l; }).join('\n');
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
  // "cod" lleva [a-z]* para aguantar como lo escriba cada quien: cod, cod., codi, codig, codigo, codigos.
  // Antes solo valia "cod" o "codigo" exactos y "primer codi: 1648" se perdia entero (Antonio, 26/11):
  // de un Guayaquil con sus dos codigos solo se leia el segundo y el bot avisaba que faltaba uno.
  // Solo letras, no \w: con \w* un "cod1648" pegado se comeria los digitos del propio codigo.
  for (const m of t.matchAll(/(?:clave|c[oó]d[a-z]*|primero|segundo)\s*[:.]?\s*(\d{3,8})(?!\d)/g)) out.push(m[1]);
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
// ---------- el banco escrito con UNA letra de menos, de mas o cambiada (26/11) ----------
// "produbaco", "pichinca", "guayaqil": el cliente se come una letra (en los nombres largos, de 9 letras o mas, hasta dos).
// Julio E mando "*produbaco*" con todo lo demas bien y el RST se perdio entero. Ahora se reconoce el banco, PERO el
// retiro queda marcado (banco_dudoso) y la Fase 2 le pregunta al cliente "¿Su retiro es de Produbanco?" antes de
// publicarlo. Si la palabra se parece a DOS bancos, no se adivina. Solo sirve para los RST/RCT (no para las cuentas).
// JEP no entra (3 letras: cualquier palabra se le parece).
const BANCOS_PARECIDOS = ['pichincha', 'guayaquil', 'produbanco', 'pacifico', 'bolivariano', 'solidario', 'austro', 'internacional', 'machala'];
const NO_ES_BANCO = ['bolivariana', 'solitario', 'internacionales', 'pacifica'];   // palabras de verdad que se parecen a un banco
function distancia(a, c){
  // Letras de mas, de menos, cambiadas o volteadas ("pichicnha"): cuantos arreglos hacen falta para pasar de a a c.
  const d = [];
  for (let i = 0; i <= a.length; i++) d.push([i]);
  for (let j = 1; j <= c.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) for (let j = 1; j <= c.length; j++){
    d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === c[j - 1] ? 0 : 1));
    if (i > 1 && j > 1 && a[i - 1] === c[j - 2] && a[i - 2] === c[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
  }
  return d[a.length][c.length];
}
function bancosParecidos(b){
  const out = new Map();
  for (const w of (b.match(/[a-z]{5,}/g) || [])){
    if (BANCOS_PARECIDOS.indexOf(w) !== -1 || NO_ES_BANCO.indexOf(w) !== -1) continue;
    for (const k of BANCOS_PARECIDOS){
      if (out.has(k) || Math.abs(w.length - k.length) > 2) continue;
      if (distancia(w, k) <= (k.length >= 9 ? 2 : 1)) out.set(k, w);
    }
  }
  return [...out].map(([banco, escrito]) => ({ banco, escrito }));
}
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
  if (ctx.cuentaVE || ctx.pagoMovil || ctx.cuentaVEmala || /banesco|bicentenario|bancamiga|\bbnc\b|banco de venezuela|\bbdv\b|provincial/.test(b)) senales.push('Venezuela');
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
  // Para los RST/RCT, el banco mal escrito tambien vale (queda marcado para preguntarle al cliente). Las cuentas usan solo bancoEC.
  const parecidos = bancoEC ? [] : bancosParecidos(b);
  const bancoDudoso = parecidos.length === 1 ? parecidos[0] : null;
  const bancoRst = bancoEC || (bancoDudoso ? bancoDudoso.banco : '');
  const marcaDudoso = bancoDudoso && !bancoEC ? { banco_dudoso: bancoDudoso.escrito } : {};
  const mon = extraerMontos(b);
  const largos = numerosLargos(b);
  const cuentaVE = largos.find(n => n.length === 20 && n.startsWith('01')) || '';
  const cedulas = cedulasDe(b);
  // Una cedula de Guayas empieza por 09 y parece un celular: si trae su etiqueta ("Cedula 0966873457"), es cedula.
  const tels = telefonosDe(b).filter(t => !cedulas.some(c => c === t || c === t.replace(/^593/, '0')));
  const pagoMovil = !cuentaVE && /\b01\d\d\b/.test(b) && tels.some(t => /^04/.test(t));
  const rct = /retira(?:r)? con tarjeta|retiro con tarjeta|\brct\b/.test(b);

  // RCT / RST: retiros de los bancos de Ecuador
  if (bancoRst && rct && !cuentaVE){
    const usd = mon.usd !== null ? mon.usd : mon.sinMoneda;
    return { tipo: 'rct', pais: 'Ecuador', banco: BANCOS_EC[bancoRst], monto_usd: usd, monto_local: null, moneda: 'USD',
             datos: Object.assign({ destino_sugerido: GRUPO_RST[bancoRst] || null, telefono: tels[0] || null }, marcaDudoso), bloque };
  }
  // Un telefono y un monto bastan para un RST, salvo que el mensaje hable de una CUENTA ("Banco Pichincha cuenta ahorro ...").
  const hablaDeCuenta = /\bcuenta\b|\bcta\b|ahorros?\b|corriente/.test(b);
  // Sin etiquetas ("Guayaquil / tlf / 2345 / 6543 / 500"): el banco + un telefono + numeros de codigo sueltos bastan.
  const hayCodigoSuelto = !!tels.length && !hablaDeCuenta && codigosSueltosDe(b, tels).some(c => !cedulas.includes(c));
  if (bancoRst && !cuentaVE && (RX_ES_RST.test(b) || hayCodigoSuelto || (tels.length && !hablaDeCuenta && (mon.usd !== null || mon.sinMoneda !== null)))){
    const usd = mon.usd !== null ? mon.usd : mon.sinMoneda;
    const ced = cedulasDe(b)[0] || null;
    let cods = codigosDe(b);
    // JEP: "OTP: 796988" es el codigo y "Clave: 1111" es la clave de la TARJETA (en los demas bancos "clave" es el codigo).
    let clave = null;
    if (bancoRst === 'jep'){
      const otp = (b.match(/\botp\s*[:.]?\s*(\d{3,8})(?!\d)/) || [])[1];
      clave = (b.match(/\bclave(?:\s+(?:de\s+(?:la\s+)?)?tarjeta)?\s*[:.]?\s*(\d{3,6})(?!\d)/) || [])[1] || null;
      if (otp) cods = [otp];
      else if (clave) cods = cods.filter(c => c !== clave);
    }
    let montoInferido = false;
    if (!cods.length) cods = codigosSueltosDe(b, tels).filter(c => c !== ced && c !== clave);
    // Sin etiqueta ("Guayaquil / tlf / 2345 / 6543 / 500"): el unico numero suelto de hasta 3 digitos que sobra es el monto.
    // Antes de contarlos se quitan los TELEFONOS y los codigos ya leidos: un celular escrito en pedazos ("099 000 0004")
    // tiene numeros de 3 cifras que tapaban el monto. Caso real del 26/11: "Pichincha 140 / 099 ... / Codigo ...": el 140 pegado
    // al banco es el monto, y el bot le iba a pedir el monto.
    let usdFinal = usd;
    if (usdFinal === null){
      const sinTel = b.replace(/(?<![\d.,])(\+?593[ -]?)?0?9\d[ -]?\d{3}[ -]?\d{3,4}(?!\d)/g, ' ').replace(/(?<![\d.,])04(?:12|14|16|24|26)[ -]?\d{7}(?!\d)/g, ' ');
      const sueltos = [...sinTel.matchAll(/(?<![\d.,:$])(\d{2,3})(?![\d.,:])/g)].map(m => m[1]).filter(x => cods.indexOf(x) === -1);
      if (sueltos.length === 1){ usdFinal = parseFloat(sueltos[0]); montoInferido = true; }
    }
    const hora = (b.match(/\b(\d{1,2}:\d{2})\b/) || [])[1] || null;
    return { tipo: 'rst', pais: 'Ecuador', banco: BANCOS_EC[bancoRst], monto_usd: usdFinal, monto_local: null, moneda: 'USD',
             datos: Object.assign({ destino_sugerido: GRUPO_RST[bancoRst] || null, telefono: tels[0] || null, codigos: cods, cedula: ced, clave, hora, monto_inferido: montoInferido || undefined }, marcaDudoso), bloque };
  }
  // ---------- parece un RST, pero no dice de que banco (o se parece a dos bancos a la vez) (26/11) ----------
  // Un celular de Ecuador + un codigo o la palabra "RST/retiro" + un monto, sin ninguna cuenta, correo ni billetera: es un
  // retiro al que le falta el banco. Se registra (sin_banco) para que la Fase 2 le pregunte al cliente de que banco es,
  // en vez de perderlo callado.
  if (!bancoRst && !cuentaVE && !hablaDeCuenta && !correosDe(b).length && !billeteraDe(b)){
    const telsEC = tels.filter(t => /^(?:593)?0?9\d{8}$/.test(t));
    const hablaRetiro = /\b(rst|retiro|retirar|retira)\b/.test(b) || /(?:clave|c[oó]d[a-z]*|otp)\s*[:.]?\s*\d{3,8}(?!\d)/.test(b);
    const usd = mon.usd !== null ? mon.usd : mon.sinMoneda;
    if (telsEC.length && hablaRetiro && usd !== null){
      // DOS codigos de 4 cifras ("Primer Codigo / Segundo Codigo") solo los da GUAYAQUIL (protocolo, seccion 9). Si no dice el
      // banco pero trae eso, no se le pregunta "¿de que banco es?": se le pregunta "¿Su retiro es de Guayaquil? sí o no", igual
      // que con un banco mal escrito (banco_dudoso). Caso real del 27/11. Nunca se publica sin su "sí".
      const cods2 = codigosDe(b);
      if (cods2.length === 2 && cods2.every(c => c.length === 4) && (!parecidos.length || parecidos.some(p => p.banco === 'guayaquil'))){
        return { tipo: 'rst', pais: 'Ecuador', banco: 'Guayaquil', monto_usd: usd, monto_local: null, moneda: 'USD',
                 datos: { destino_sugerido: GRUPO_RST.guayaquil, telefono: telsEC[0], codigos: cods2, cedula: cedulas[0] || null, clave: null, hora: null,
                          banco_dudoso: 'sin banco', banco_deducido: true }, bloque };
      }
      return { tipo: 'rst', pais: 'Ecuador', banco: null, monto_usd: usd, monto_local: null, moneda: 'USD',
               datos: { destino_sugerido: null, telefono: telsEC[0], codigos: codigosDe(b), cedula: cedulas[0] || null, sin_banco: true,
                        posibles: parecidos.length > 1 ? parecidos.map(p => BANCOS_EC[p.banco]) : undefined }, bloque };
    }
  }

  // BENEFICIARIO: tiene con que identificar una cuenta (numero, correo, billetera) y pais o monto
  const correos = correosDe(b), billetera = billeteraDe(b);
  let cuentas = largos.filter(n => !cedulas.includes(n) && !tels.includes(n));
  // En Brasil la llave PIX casi siempre es el CPF, que es el mismo numero de la cedula: "Cuenta: Inter / 123.456.789.42 /
  // Cedula: 12345678942 / Brasil". Antes ese numero se descartaba por ser la cedula, la cuenta quedaba vacia y el pedido se
  // tomaba como una pregunta (por la "Tasa"). Paso el 26/11.
  const esBrasil = /\bbrasil\b|\bbrazil\b|🇧🇷|\bpix\b|\bcpf\b/.test(b);
  if (!cuentas.length && esBrasil && cedulas.length && !/[?¿]/.test(b)) cuentas = cedulas.slice(0, 1);
  const hayIdentificador = cuentas.length > 0 || correos.length > 0 || !!billetera || pagoMovil
    || (tels.length > 0 && /nequi|daviplata|yape|plin|pix/.test(b))
    || (cedulas.length > 0 && /\brut\b|cuenta vista|cuenta rut|\bdni\b/.test(b))        // en Chile la cuenta RUT es la cedula
    || /\balias\s*[:.]?\s*[a-z0-9._-]{4,}/.test(b);                                       // Argentina
  // En Venezuela TODA cuenta tiene 20 digitos (protocolo de pedidos, 27/11). Una que empieza por 01 y tiene 16 a 24 digitos
  // pero no 20 casi seguro esta mal copiada: se marca para avisarlo en la vista previa (y cuenta como señal de Venezuela).
  const cuentaVEmala = cuentaVE ? '' : (cuentas.find(n => /^01/.test(n) && n.length >= 16 && n.length <= 24 && n.length !== 20) || '');
  if (hayIdentificador){
    const p = paisDe(b, { cuentaVE, pagoMovil, largos: cuentas, bancoEC, billetera, cuentaVEmala });
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
                        destino_sugerido: destino, candidatos: p.candidatos, senales: p.senales, pago_movil: pagoMovil || undefined,
                        cuenta_ve_digitos: (pais === 'Venezuela' && cuentaVEmala) ? cuentaVEmala.length : undefined }, bloque };
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
  return !!(bancoEcuadorDe(b) || bancosParecidos(b).length === 1) && (RX_ES_RST.test(b) || telefonosDe(b).length > 0);
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

// ---------- PEDAZO DE UN PEDIDO mandado en otro mensaje (27/11) ----------
// Un cliente manda "Pedido USDT / 300$" y en el mensaje de al lado "BINANCE / correo / billetera"; otro manda la billetera,
// el correo y "50$" en tres mensajes. Solos no son un pedido (al monto le falta la cuenta, al correo el pais y el monto), pero
// "Decidir Publicacion" los junta con la cuenta del mismo cliente si llegan con menos de 3 minutos de diferencia.
//   monto:  un mensaje CORTO con un monto en dolares o en moneda local y nada mas que lo identifique ("Pedido USDT / 300$").
//   correo: un correo solo, sin monto (puede ser de Binance o de Zelle: el pais lo pone el otro pedazo).
// No cuentan las preguntas ("¿le queda para 300$ en USDT?") ni lo que habla de un retiro, un deposito o un pago del cliente.
function piezaPedidoDe(b){
  if (/[?¿]/.test(b) || b.length > 160 || b.split('\n').filter(l => l.trim()).length > 5) return null;
  // ("Solo falta 238$" es lo que le falta pagar de un saldo, no el monto de un pedido: 27/11)
  if (/\b(rst|rct|retiro|retira|retirar|deposito|depositar|deposite|transferi|transferencia|pago|pague|abono|abone|saldo|restante|resta|debe|falta|faltan|faltaria|queda|quedan|pendiente)\b/.test(b)) return null;
  if (numerosLargos(b).length || billeteraDe(b)) return null;
  const correos = correosDe(b), mon = extraerMontos(b);
  const usd = mon.usd !== null ? mon.usd : mon.sinMoneda;
  if (!correos.length && (usd !== null || mon.local !== null)){
    const p = paisDe(b, { largos: [], bancoEC: '', billetera: '' });
    return { clase: 'monto', monto_usd: usd, monto_local: mon.local, moneda: mon.moneda || (usd !== null ? 'USD' : null),
             pais: p.pais, destino_sugerido: p.pais ? (GRUPO_PAIS[p.pais] || null) : null };
  }
  if (correos.length === 1 && usd === null && mon.local === null) return { clase: 'correo' };
  return null;
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
    // Un pedazo de pedido (un monto suelto o un correo suelto) queda tipo 'otro' con datos.pieza (la tabla no acepta otros tipos).
    const pz = (grupo.tipo === 'cliente') ? piezaPedidoDe(b) : null;
    if (pz && fila.tipo === 'otro') fila.datos.pieza = pz;
  }
}
// ---------- LA CABECERA DE UN PEDIDO QUE PASO EL EQUIPO (27/11) ----------
// En los grupos de PAISES la operadora pasa cada pedido con el NOMBRE del cliente arriba y en la 2da linea COMO PAGA: "RST" o
// "CUENTA" (Kelvin: "esa linea la pone mi operadora porque ya sabemos por donde paga el cliente"; "EST" es un error de tipeo de RST).
// Se guarda (datos.cabecera + datos.forma_pago) para que el bot aprenda como paga SIEMPRE cada cliente.
if (esDestino && PISTA.pais && !PISTA.bancoEC && textoCrudo){
  const ls = limpio.split('\n').map(l => l.trim()).filter(Boolean);
  if (ls.length >= 2 && !/\d/.test(ls[0]) && ls[0].split(/\s+/).length <= 5){
    const l2 = minus(ls[1]).replace(/[^a-z ]/g, ' ').replace(/\s+/g, ' ').trim();
    const forma = /^(rst|est|r s t)$/.test(l2) ? 'RST' : /^(x |por )?(cuenta|transferencia|deposito)$/.test(l2) ? 'CUENTA' : '';
    if (forma){ fila.datos.cabecera = minus(ls[0]).replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim(); fila.datos.forma_pago = forma; }
  }
}
// Una edicion manda sobre el tipo: el mensaje no trae texto, asi que arriba habria quedado en "otro".
if (editado){ fila.tipo = 'edicion'; fila.datos.editado_id = editado; }
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

# ===================== CODIGO COMUN: ¿EL CLIENTE CONTESTA SI O NO? =====================
# Lo usan "Hace Falta Publicar?" (para dejarlo pasar) y "Decidir Publicacion" (para saber que contesto).
$siNoJs = @'
// "corte hasta aqui" / "corte" / "dame el corte" de un cobrador en el grupo de un BANCO (27/11). Corto, y no de Kelvin.
// (Lo usan "Hace Falta Publicar?" y "Decidir Publicacion".)
function esCorte(grupo, fila){
  const t = String((fila && fila.texto) || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
  // (Kelvin, la operadora y los de operadores_caja no son cobradores: su "corte" no es el corte de un cobrador)
  return !!grupo && grupo.tipo === 'destino' && !!fila && !puedeConfirmarCaja(grupo, fila) && t.length > 0 && t.length <= 60 && /\bcorte\b/.test(t);
}
// "recibido 4100" (o solo "recibido") de KELVIN o de la OPERADORA en el grupo de un banco, CITANDO el "corte hasta aqui" de un
// cobrador: el cobrador entrego el efectivo y se anota la entrega (27/11). Corto y con cita.
// Ademas de Kelvin y la operadora del grupo, los numeros de grupos_mayor.operadores_caja (Kelvin, 27/11; los numeros estan en
// Supabase, no en el codigo, porque el repositorio es publico). Se comparan los ultimos 9 digitos.
function puedeConfirmarCaja(grupo, fila){
  if (!fila) return false;
  if (fila.autor_rol === 'kelvin' || fila.autor_rol === 'operadora') return true;
  const mio = String(fila.autor_numero || '').replace(/\D/g, '').slice(-9);
  return !!mio && String((grupo && grupo.operadores_caja) || '').split(/[,;\s]+/).some(n => n.replace(/\D/g, '').slice(-9) === mio);
}
function esRecibido(grupo, fila){
  const t = String((fila && fila.texto) || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
  return !!grupo && grupo.tipo === 'destino' && !!fila && puedeConfirmarCaja(grupo, fila)
    && !!(fila.datos && fila.datos.cita_id) && t.length > 0 && t.length <= 60 && /\brecibid[oa]s?\b/.test(t);
}
// "si", "sí", "siii", "claro", "correcto", "👍" = 'si' | "no", "nop", "negativo" = 'no' | lo demas = ''. Solo mensajes CORTOS:
// un "no tengo el codigo todavia, ya se lo paso" no es contestar la pregunta. "no se" (no sé) tampoco.
function respuestaSiNo(texto){
  const t = String(texto || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
  if (!t || t.length > 40) return '';
  if (/^(?:👍|✅|✔️?|👌)+$/u.test(t.replace(/\s+/g, ''))) return 'si';
  if (/^[^a-z0-9]*(?:si+|sip|sep|claro|correcto|exacto|afirmativo|asi es|eso es|ese mismo|es correcto|ok si|okey si)\b/.test(t)) return 'si';
  if (/^[^a-z0-9]*no\s+se\b/.test(t)) return '';
  if (/^[^a-z0-9]*(?:no+|nop|nope|negativo)\b/.test(t)) return 'no';
  return '';
}
'@

# ===================== CODIGO: ¿HACE FALTA PUBLICAR? (Fase 2) =====================
$hacePublicarCode = @'
// ===== ¿HACE FALTA PUBLICAR ALGO? =====
// Un filtro barato: casi todos los mensajes de los grupos NO son un retiro, y asi no se consulta Redis ni
// Supabase para ellos. Pasa solo:
//   - un RST/RCT (o una foto que habla de un retiro) que escribio el CLIENTE o su operador extra en su grupo;
//   - un PEDIDO a un pais (beneficiario: la cuenta a la que hay que pagar) del cliente: por ahora SOLO vista previa (26/11);
//     o un PEDAZO de pedido (un monto o un correo suelto, datos.pieza) que se junta con la cuenta de al lado (27/11);
//   - una respuesta en un grupo de DESTINO ("Verificar", "se dañó"...) que cita un mensaje;
//   - Solidario: el cobrador que cita nuestro RST y escribe "temporal" (la clave temporal en vivo), o el cliente que la manda;
//   - JEP: un cliente que QUIERE hacer un RST ("quiero retirar por JEP") aunque no mande datos, o el cobrador
//     que avisa en el grupo de JEP, citando nuestro mensaje, que ya esta en el cajero ("listo, ya estoy aca").
//   - un "si" / "no" corto del cliente: puede ser la respuesta a "¿Su retiro es de Produbanco?" ("Decidir Publicacion" lo confirma);
//   - una FOTO del cliente: puede ser la captura de su pago (se lee con IA para el saldo, 27/11);
// Lo que Kelvin o la operadora escriban en un grupo de cliente nunca dispara nada.
__PUBLICAR_COMUN__
__SI_NO__
const fila = $('Decidir').first().json;
const ent = $('Cuando lo Llama el Bot').first().json || {};
const grupo = ent.grupo || {};
const guardada = $('Guardar en Supabase').first().json || {};
if (!guardada.id) return [];                          // no se pudo guardar (mensaje repetido): no se publica nada
const d = fila.datos || {};
const regs = Array.isArray(d.registros) ? d.registros : [];
const hayRetiro = regs.some(r => r.tipo === 'rst' || r.tipo === 'rct');
const hayPedido = regs.some(r => r.tipo === 'beneficiario');
const delCliente = fila.autor_rol === 'cliente' || fila.autor_rol === 'operador_extra';
const t = String(fila.texto || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
// (un mensaje con UN numero de 6 digitos puede ser la clave temporal de Solidario que el cobrador pidio: "Decidir Publicacion" lo confirma)
// (cabecera: la 1ra palabra del nombre del cliente, para buscar como pasa la operadora sus pedidos en los grupos de paises, 27/11)
const cabeceraCliente = String(fila.cliente_nombre || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().split(/[^a-z0-9]+/).filter(w => w.length >= 3)[0] || '';
if (grupo.tipo === 'cliente' && delCliente && (hayRetiro || hayPedido || d.pieza || d.pide_texto || quiereJep(fila.texto) || codigoTemporalDe(fila.texto) || respuestaSiNo(fila.texto))) return [{ json: { motivo: 'cliente', cabecera: cabeceraCliente } }];
// Una FOTO del cliente (sin un RST en el pie): puede ser la captura de su PAGO. "Leer Pago" la lee con IA, como en el detal (27/11).
if (grupo.tipo === 'cliente' && delCliente && fila.tipo === 'captura') return [{ json: { motivo: 'foto', cabecera: cabeceraCliente } }];
// Un cobrador pide su CORTE en el grupo de su banco ("corte hasta aqui"): se le dice cuanto cobro desde su ultimo corte (27/11).
if (esCorte(grupo, fila)) return [{ json: { motivo: 'corte', cabecera: '' } }];
// Kelvin o la operadora: "recibido 4100" citando el corte de un cobrador -> se anota la entrega (27/11).
if (esRecibido(grupo, fila)) return [{ json: { motivo: 'recibido', cabecera: '' } }];
// El cliente edito un mensaje suyo. Solo importa si lo que edito fue un RST/RCT o una cuenta: eso lo mira
// "Decidir Publicacion" contra los mensajes recientes del grupo.
if (grupo.tipo === 'cliente' && delCliente && fila.tipo === 'edicion' && d.editado_id) return [{ json: { motivo: 'edicion' } }];
if (grupo.tipo === 'destino' && d.cita_id && /verific|correg|corrij|\bdan(o|ado)\b|salio dan|se dano/.test(t)) return [{ json: { motivo: 'banco' } }];
if (grupo.tipo === 'destino' && d.cita_id && /\bjep\b/.test(quitar(grupo.nombre)) && cobradorListo(fila.texto)) return [{ json: { motivo: 'jep' } }];
if (grupo.tipo === 'destino' && d.cita_id && pideTemporal(fila.texto)) return [{ json: { motivo: 'temporal' } }];
return [];
'@
$hacePublicarCode = $hacePublicarCode.Replace('__PUBLICAR_COMUN__', $publicarJs).Replace('__SI_NO__', $siNoJs)

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
__SI_NO__
const TEXTO_FOTO ='Por favor envíe todos los datos en texto escrito para poder procesar su retiro.';
const TEXTO_BANCO_VERIFICAR = 'ok, procedo a mandar a verificar y corregir';
const TEXTO_CLIENTE_VERIFICAR = 'Por favor verifique, corrija y envíe nuevamente todos los datos en un solo texto.';
const TEXTO_CLIENTE_DANADO = 'Estimado cliente, su código se dañó / no pudo ser cobrado. Por favor genere un nuevo código de retiro para poder saldar el saldo pendiente.';
const TEXTO_CLIENTE_EDITO = 'Vimos que editó su mensaje, pero WhatsApp no nos deja leer las ediciones. Por favor envíe los datos de nuevo, completos y en un solo texto.';
const TEXTO_SIN_BANCO = '¿Ese mensaje es un RST? No reconocí de qué banco es. Si es un retiro, envíe todos los datos de nuevo en un solo texto, con el nombre del banco, por favor.';
// Despues del "sí" a "¿Su retiro es de Guayaquil?" (no puso el banco), un recordatorio. Si en 7 dias ya van VECES_OBLIGATORIO
// retiros suyos sin el nombre del banco (contando este), el recordatorio es mas firme (pedido de Kelvin, 27/11).
const TEXTO_PONER_BANCO = 'Por favor, siempre colócale el nombre del banco.';
const TEXTO_BANCO_OBLIGATORIO = 'Es obligatorio que le coloques el nombre del banco.';
const VECES_OBLIGATORIO = 3;

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
// "Redis Leer Sin Banco": cuando (en los ultimos 7 dias) este cliente mando un RST SIN el nombre del banco (sinBanco:<grupo>).
let vecesSinBanco = [];
try {
  const raw = $('Redis Leer Sin Banco').first().json.sinBanco;
  const l = raw ? ((typeof raw === 'string') ? JSON.parse(raw) : raw) : [];
  vecesSinBanco = (Array.isArray(l) ? l : []).map(Number).filter(t => t && Date.now() - t < 7 * 86400000);
} catch(e){ vecesSinBanco = []; }
const redisSiempre = [];       // lo que se anota en Redis tambien en ENSAYO (el contador de "sin banco")
const destinos = {};          // nombre del grupo (sin acentos) -> su id, solo los de la tabla
try { for (const it of $('Grupos Destino').all()){ const g = it.json || {}; if (g.grupo_jid && g.nombre && g.activo !== false) destinos[quitar(g.nombre)] = g.grupo_jid; } } catch(e){}
const abierto = horarioDe(Date.now()).abierto;
const nombre = String(fila.cliente_nombre || 'Cliente');
// ---------- RST REPETIDO (revision diaria del 25/11) ----------
// Un cliente mando dos veces el mismo Pichincha (mismo monto y mismo codigo, con otro telefono) en 1 minuto: parece una
// correccion, pero en modo real se publicaria DOS veces en el banco. Un codigo de retiro se cobra UNA sola vez: si un retiro
// completo trae el mismo banco y los mismos codigos que otro retiro completo de este grupo de los ultimos 30 minutos
// ("Retiros Recientes"), NO se publica otra vez y se avisa en avisos para que una persona lo revise.
// No cuentan los que el banco devolvio con "Verificar" o "se dañó": ahi el cliente lo reenvia corregido a proposito.
const codigosDeReg = r => ((r && r.datos && Array.isArray(r.datos.codigos)) ? r.datos.codigos : []).map(String).filter(Boolean).sort().join(',');
const recientes = [];
try {
  for (const it of $('Retiros Recientes').all()){
    const r = it.json || {};
    // 'confirmar_banco': esperando que el cliente diga si el banco mal escrito es el que creemos; todavia no se publico.
    if (!r.mensaje_id || r.mensaje_id === fila.mensaje_id || r.estado === 'verificar' || r.estado === 'danado' || r.estado === 'confirmar_banco') continue;
    let d = r.datos;
    if (typeof d === 'string'){ try { d = JSON.parse(d); } catch(e){ d = {}; } }
    for (const x of ((d && Array.isArray(d.registros)) ? d.registros : [])){
      if ((x.tipo !== 'rst' && x.tipo !== 'rct') || faltan(x).length || revisar(x).length) continue;
      const cods = codigosDeReg(x);
      if (cods) recientes.push({ banco: claveBanco(x), cods, ts: Date.parse(r.fecha_mensaje) || 0 });
    }
  }
} catch(e){}
// JEP no entra: su RST se queda esperando hasta que el cobrador este en el cajero, y ahi el cliente lo vuelve a mandar a proposito.
const repetidoDe = reg => { const cods = codigosDeReg(reg), k = claveBanco(reg); return (cods && k !== 'jep') ? (recientes.find(x => x.banco === k && x.cods === cods) || null) : null; };

// ---------- ¿EL CLIENTE CONTESTA "¿Su retiro es de Produbanco?"? (26/11) ----------
// Cuando el banco venia mal escrito ("produbaco"), el bot le pregunto al cliente y la fila quedo en 'confirmar_banco'. Si
// ahora el cliente contesta un "si" / "no" corto y ESE es su ultimo retiro de los ultimos 30 minutos, es la respuesta:
//   si -> se publica ese retiro como cualquier otro;  no -> se le pide que lo mande de nuevo y la fila pasa a 'verificar'.
// Si despues de la pregunta mando otro retiro, el "si" ya no es para el viejo (no se toca nada).
const respuesta = (grupo.tipo === 'cliente' && !(Array.isArray(datos.registros) && datos.registros.length)) ? respuestaSiNo(fila.texto) : '';
let pendiente = null;
if (respuesta){
  try {
    const delCliente = r => r.autor_rol === 'cliente' || r.autor_rol === 'operador_extra';
    const ult = $('Retiros Recientes').all().map(i => i.json).filter(r => r && r.id && ['rst', 'rct', 'mixto'].indexOf(r.tipo) !== -1 && delCliente(r))
      .sort((a, b) => (Date.parse(b.fecha_mensaje) || 0) - (Date.parse(a.fecha_mensaje) || 0))[0];
    if (ult && ult.estado === 'confirmar_banco'){
      let d = ult.datos;
      if (typeof d === 'string'){ try { d = JSON.parse(d); } catch(e){ d = {}; } }
      pendiente = { id: ult.id, mensaje_id: String(ult.mensaje_id), banco: ult.banco, registros: (d && Array.isArray(d.registros)) ? d.registros : [] };
    }
  } catch(e){ pendiente = null; }
}
const confirmado = !!pendiente && respuesta === 'si';
// La fila y el mensaje del retiro: los de ahora, o (si el cliente confirmo el banco) los del mensaje que pregunto.
const filaRef = confirmado ? pendiente.id : filaId;
const msgRef = confirmado ? pendiente.mensaje_id : fila.mensaje_id;

// ---------- PEDIDO EN VARIOS MENSAJES (27/11) ----------
// Una cuenta sin monto y un monto suelto ("Pedido USDT / 300$") del MISMO cliente, con menos de 3 minutos entre uno y otro, son
// UN pedido, lleguen en el orden que lleguen. Un correo suelto se pega a la cuenta de al lado (Binance: billetera + correo).
// Se recorren en orden los mensajes del cliente de los ultimos 10 minutos ("Retiros Recientes" + este): cada cuenta sin monto
// espera su monto y cada monto espera su cuenta; una cuenta que ya trae su monto corta la espera. Solo sale algo si ESTE mensaje
// es el que completa el pedido (si la cuenta llego primero, ella ya salio como "sin monto" y ahora sale el pedido entero).
const JUNTAR_MS = 3 * 60000;
function piezaDe(r){
  let d = r && r.datos;
  if (typeof d === 'string'){ try { d = JSON.parse(d); } catch(e){ d = {}; } }
  d = d || {};
  const regs = Array.isArray(d.registros) ? d.registros : [];
  const bens = regs.filter(x => x.tipo === 'beneficiario');
  if (bens.length){
    const sinMonto = x => [x.monto_usd, x.monto_local, x.datos && x.datos.monto_sin_moneda].every(v => v === null || v === undefined);
    return (bens.length === 1 && regs.length === 1 && sinMonto(bens[0])) ? { k: 'cuenta', reg: bens[0] } : { k: 'completo' };
  }
  if (d.pieza && d.pieza.clase === 'monto') return { k: 'monto', pz: d.pieza };
  if (d.pieza && d.pieza.clase === 'correo') return { k: 'correo' };
  return null;
}
function pedidoJuntado(){
  if (grupo.tipo !== 'cliente') return null;
  const yo = piezaDe(fila);
  if (!yo || yo.k === 'completo') return null;
  const ahoraMs = Date.parse(fila.fecha_mensaje) || Date.now();
  const mismoAutor = r => fila.autor_numero ? String(r.autor_numero || '') === String(fila.autor_numero) : r.autor_rol === fila.autor_rol;
  let previas = [];
  try { previas = $('Retiros Recientes').all().map(i => i.json).filter(r => r && r.id && r.mensaje_id !== fila.mensaje_id && mismoAutor(r)); } catch(e){ previas = []; }
  const seq = previas.map(r => ({ r, ts: Date.parse(r.fecha_mensaje) || 0, id: Number(r.id) || 0 }))
    .filter(x => x.ts <= ahoraMs && ahoraMs - x.ts <= 10 * 60000)
    .sort((a, b) => (a.ts - b.ts) || (a.id - b.id));
  seq.push({ r: fila, ts: ahoraMs, id: Infinity, actual: true, p: yo });
  let espera = null, par = null;
  for (const it of seq){
    if (!it.actual) it.p = piezaDe(it.r);
    if (!it.p) continue;                                            // charla, RST, foto: no cortan la espera
    const cerca = !!espera && (it.ts - espera.ultimo) <= JUNTAR_MS;
    if (it.p.k === 'completo'){ espera = null; continue; }
    if (it.p.k === 'cuenta' || it.p.k === 'correo'){
      // un correo se pega a la cuenta que espera (o una cuenta al correo que espera)
      if (cerca && espera.tipo === 'cuenta' && (it.p.k === 'correo' || espera.items.every(x => x.p.k === 'correo'))){ espera.items.push(it); espera.ultimo = it.ts; continue; }
      if (cerca && espera.tipo === 'monto'){ if (it.actual) par = { cuentas: [it], monto: espera.items[0] }; espera = null; continue; }
      espera = { tipo: 'cuenta', items: [it], ultimo: it.ts };
      continue;
    }
    if (cerca && espera.tipo === 'cuenta'){ if (it.actual) par = { cuentas: espera.items, monto: it }; espera = null; continue; }
    espera = { tipo: 'monto', items: [it], ultimo: it.ts };
  }
  if (!par) return null;
  const conCuenta = par.cuentas.find(x => x.p.k === 'cuenta');
  const base = conCuenta ? conCuenta.p.reg : { tipo: 'beneficiario', pais: null, banco: null, datos: {} };
  const pz = par.monto.p.pz || {};
  const pais = base.pais || pz.pais || null;
  const destino = (base.datos && base.datos.destino_sugerido) || (!base.pais ? pz.destino_sugerido : null) || null;
  const piezas = par.cuentas.concat([par.monto]).sort((a, b) => (a.ts - b.ts) || (a.id - b.id));
  return {
    n: piezas.length,
    texto: piezas.map(x => String(x.r.texto || '').trim()).filter(Boolean).join('\n'),
    pedido: { tipo: 'beneficiario', pais, banco: base.banco || null, monto_usd: pz.monto_usd, monto_local: pz.monto_local, moneda: pz.moneda || base.moneda || null,
              datos: Object.assign({}, base.datos || {}, { destino_sugerido: destino, candidatos: pais ? [] : ((base.datos && base.datos.candidatos) || []), juntado: true }) }
  };
}

// ---------- PRECIOS DEL MAYOR: los de la APP (hoja de tasas + src/motor.js), 27/11 ----------
// El bot no tiene precios propios: "Leer Tasas" baja la hoja publicada y el motor (src/motor.js, el MISMO de la app, inyectado
// por el build) saca la tasa. Paga con RST -> 'mayor_rst' (columna "Margen Mayor X RST"); por CUENTA -> 'mayor' ("Margen Envio
// Mayor"); un pedido de $1,000+ -> 'mayor_volumen' ("Margen Mayor 1000"), si esta llena. Es lo mismo que dice el "Aviso USDT".
__MOTOR_JK__
function paisesDeLaHoja(csv){
  const lineas = String(csv || '').split('\n').filter(l => l.trim());
  if (lineas.length < 2) return [];
  const celdas = l => { const out = []; let q = false, cur = ''; for (const c of l.trim()){ if (c === '"') q = !q; else if (c === ',' && !q){ out.push(cur); cur = ''; } else cur += c; } out.push(cur); return out; };
  const head = celdas(lineas[0]).map(h => h.toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g, ''));
  const col = (...k) => head.findIndex(h => k.some(x => h.includes(x)));
  const iCod = col('CODIGO', 'BANCO'), iEM = col('MARGEN ENVIO MAYOR', 'TASA 1 X CUENTA', 'TASA 1 CUENTA'), iRM = col('MARGEN RECIBO MAYOR'),
        iRST = col('MARGEN MAYOR X RST', 'MARGEN MAYOR RST', 'MAYOR X RST', 'MAYOR RST'), iVol = col('MARGEN MAYOR 1000', 'MARGEN MAYOR VOLUMEN', 'MAYOR 1000');
  const num = s => { const v = parseFloat(String(s || '').replace(/\s/g, '').replace(',', '.')); return isNaN(v) ? 0 : v; };
  const numN = s => { if (s === undefined || s === null || String(s).trim() === '') return null; const v = parseFloat(String(s).replace(/\s/g, '').replace(',', '.')); return isNaN(v) ? null : v; };
  const out = [];
  for (const l of lineas.slice(1)){
    const r = celdas(l), nombrePais = (r[0] || '').trim();
    if (!nombrePais) continue;
    out.push({ nombre: nombrePais, codigo: (iCod !== -1 && r[iCod]) ? r[iCod].trim().toUpperCase() : nombrePais.slice(0, 3).toUpperCase(),
               tasaProveedorEnvio: num(r[1]), margenEnvio: num(r[2]), tasaProveedorRecibo: num(r[3]), margenRecibo: num(r[4]),
               margenEnvioMayor: iEM !== -1 ? numN(r[iEM]) : null, margenReciboMayor: iRM !== -1 ? numN(r[iRM]) : null,
               margenMayorRST: iRST !== -1 ? numN(r[iRST]) : null, margenMayorVolumen: iVol !== -1 ? numN(r[iVol]) : null });
  }
  return out;
}
let PAISES_HOJA = [];
try { PAISES_HOJA = paisesDeLaHoja(($('Leer Tasas').first().json || {}).data); } catch(e){ PAISES_HOJA = []; }
const paisDeLaHoja = g => PAISES_HOJA.find(p => g === 'BINANCE' ? (p.codigo === 'USDT' || /usdt/i.test(p.nombre)) : (g === 'ZELLE' && /zelle/i.test(p.nombre))) || null;
// La tasa para ENTREGAR en esa caja dolar (BINANCE / ZELLE) segun como paga el cliente y cuanto es.
function precioMayor(g, forma, monto){
  const p = paisDeLaHoja(g);
  if (!p) return null;
  const modo = (monto >= 1000 && tieneTasaMayorVolumen(p)) ? 'mayor_volumen' : (forma === 'CUENTA' ? 'mayor' : 'mayor_rst');
  const tasa = calcularTasaEnvio(p, modo);
  if (!(tasa > 0) || tasa > 1.5) return null;
  return { modo, tasa, pct: Math.round((1 - tasa) * 10000) / 100, nombreModo: modo === 'mayor_volumen' ? '$1,000+' : (modo === 'mayor' ? 'por cuenta' : 'RST') };
}
const redondear = v => Math.round(v * 100) / 100;
const fmt2 = v => (v === null || v === undefined) ? '¿?' : (Number.isInteger(v) ? String(v) : v.toFixed(2));
// ---------- ¿COMO PAGA? "RST" o "CUENTA" (Kelvin, 27/11) ----------
// La 2da linea del pedido la pone la operadora porque ya sabe por donde paga cada cliente, y de eso depende el PRECIO. El bot
// lo saca asi, en este orden:
//   1) por la TASA que uso el cliente: con los dos montos del pedido (Bs / $; en Binance y Zelle, el % entre los dos) se compara
//      con la tasa RST, la de cuenta y la de $1,000+ de la hoja. Si cuadra con una sola (±0,3% por redondeo), esa es.
//   2) lo que Kelvin anoto a mano en grupos_mayor.forma_pago ('rst' / 'cuenta').
//   3) como pasa SIEMPRE la operadora los pedidos de este cliente ("NOMBRE / RST" en los grupos de paises, ultimos 45 dias).
// Si no se sabe: "RST o CUENTA (?)". Si la tasa que uso no cuadra con ninguna, se avisa con los numeros.
const PAIS_EN_LA_HOJA = { 'España': 'Europa' };
function filaDeLaHoja(pais){
  if (!pais) return null;
  if (pais === 'USDT') return paisDeLaHoja('BINANCE');
  if (pais === 'Zelle') return paisDeLaHoja('ZELLE');
  const k = quitar(PAIS_EN_LA_HOJA[pais] || pais);
  return PAISES_HOJA.find(p => quitar(p.nombre) === k) || null;
}
const fmtTasa = v => (v >= 100 ? (Math.round(v * 10) / 10) : (Math.round(v * 1000) / 1000)).toString().replace('.', ',');
const fmtPct = t => (Math.round((1 - t) * 10000) / 100) + '%';
function formaPorTasa(ped, texto, caja){
  const p = caja ? paisDeLaHoja(caja) : filaDeLaHoja(ped.pais);
  if (!p) return null;
  let usada = null;
  if (caja){
    const ord = [...new Set(montosEnDolares(texto))].sort((a, b) => b - a);
    if (ord.length < 2 || !(ord[1] > 0)) return null;
    usada = (caja === 'BINANCE') ? ord[1] / ord[0] : 2 - ord[0] / ord[1];       // Zelle suma el %: cobrado = entregar x (1 + %)
  } else {
    if (!(ped.monto_usd > 0 && ped.monto_local > 0)) return null;
    usada = ped.monto_local / ped.monto_usd;
  }
  const tasas = { RST: calcularTasaEnvio(p, 'mayor_rst'), CUENTA: calcularTasaEnvio(p, 'mayor') };
  if (tieneTasaMayorVolumen(p)) tasas.VOLUMEN = calcularTasaEnvio(p, 'mayor_volumen');
  // margen por redondeo: 0,3% (en Venezuela la RST y la de $1,000+ estan a 0,5% una de otra, y la de cuenta a 1%)
  const tol = caja ? 0.002 : 0.003;
  const cuadran = Object.keys(tasas).filter(k => tasas[k] > 0 && Math.abs(usada - tasas[k]) / tasas[k] <= tol);
  const formas = [...new Set(cuadran.map(k => k === 'VOLUMEN' ? 'RST' : k))];        // la de $1,000+ es un precio RST
  const mostrar = caja ? fmtPct(usada) : fmtTasa(usada), ver = t => caja ? fmtPct(t) : fmtTasa(t);
  if (formas.length === 1) return { forma: formas[0], usada: mostrar, volumen: cuadran.indexOf('VOLUMEN') !== -1 && cuadran.indexOf('RST') === -1 };
  if (formas.length > 1) return { forma: '', usada: mostrar, igual: true };              // en ese pais la RST y la de cuenta son iguales
  return { forma: '', usada: mostrar, noCuadra: true, rst: ver(tasas.RST), cuenta: ver(tasas.CUENTA) };
}
function formaDeHabito(){
  let filas = [];
  try { filas = $('Formas de Pago Vistas').all().map(i => i.json).filter(r => r && r.id); } catch(e){ filas = []; }
  const tok = s => quitar(s).split(/[^a-z0-9]+/).filter(w => w.length >= 2);
  const mios = tok(nombre.replace(/pedidos?|\bjk\b|kelvin/gi, ' '));
  if (!mios.length) return null;
  const veces = { RST: 0, CUENTA: 0 };
  for (const r of filas){
    let d = r.datos;
    if (typeof d === 'string'){ try { d = JSON.parse(d); } catch(e){ d = {}; } }
    if (!d || !d.cabecera || !veces.hasOwnProperty(d.forma_pago)) continue;
    const cab = tok(d.cabecera);
    if (cab.length && cab.every(w => mios.some(m => m.startsWith(w)))) veces[d.forma_pago]++;
  }
  const n = veces.RST + veces.CUENTA;
  if (!n) return null;
  const forma = veces.RST >= veces.CUENTA ? 'RST' : 'CUENTA';
  return { forma, veces: veces[forma], de: n, clara: veces[forma] / n >= 0.7 };
}
function comoPaga(ped, texto, caja){
  const notas = [];
  const t = formaPorTasa(ped, texto, caja);
  const manual = String(grupo.forma_pago || '').toUpperCase();
  const habito = formaDeHabito();
  const esperado = (manual === 'RST' || manual === 'CUENTA') ? manual : (habito && habito.clara ? habito.forma : '');
  let forma = '', por = '';
  if (t && t.forma){ forma = t.forma; por = 'por la tasa que usó: ' + t.usada + (t.volumen ? ' (la de $1,000+)' : ''); }
  else if (manual === 'RST' || manual === 'CUENTA'){ forma = manual; por = 'lo anotó Kelvin en grupos_mayor'; }
  else if (habito && habito.clara){ forma = habito.forma; por = 'así lo pasa siempre la operadora (' + habito.veces + ' de ' + habito.de + ')'; }
  if (t && t.noCuadra) notas.push('⚠️ Calculó a ' + t.usada + ': no cuadra con la tasa RST (' + t.rst + ') ni con la de cuenta (' + t.cuenta + ') de la hoja.');
  if (t && t.forma && esperado && esperado !== t.forma) notas.push('⚠️ Calculó con el precio ' + t.forma + ', pero normalmente paga ' + esperado + '.');
  // por que no se sabe (para la vista previa)
  const porQueNo = forma ? '' : (!t ? 'el pedido no trae los dos montos para ver la tasa' : t.igual ? 'ahí la tasa RST y la de cuenta son iguales' : 'la tasa no cuadra')
    + ', y no hay nada anotado para este cliente';
  return { forma, por, notas, porQueNo };
}
// ---------- SALDO DEL CLIENTE: pago + pedidos / pedidos + pago (Parte B, Kelvin 27/11) ----------
// Cada pago (un RST completo, apenas llega; o la foto de su pago leida con IA) y cada pedido (en $) se anota en movimientos_mayor
// ("Armar Movimientos" -> "Guardar Movimientos"). "Saldo del Cliente" trae el saldo CORRIDO y los movimientos de HOY.
// Saldo del dia = pagos + ajustes - pedidos. Los pedidos del dia se cubren en orden de llegada con todo lo pagado en el dia:
// si alcanza, el pedido esta pagado; si no, espera su pago (sticker "esperando su pago para procesar"). Cuando llega un pago,
// se dice que pedidos que esperaban ya pasarian. Por ahora todo eso es SOLO vista previa en avisos (los pedidos no se publican).
const STICKER_ESPERANDO = '__STICKER_BASE__sticker-esperando-su-pago-para-procesar.webp';
let SALDO = { corrido: 0, hoy: [], error: false };
try {
  const s = $('Saldo del Cliente').first().json || {};
  let hoy = s.hoy;
  if (typeof hoy === 'string'){ try { hoy = JSON.parse(hoy); } catch(e){ hoy = []; } }
  SALDO = { corrido: Number(s.saldo_corrido) || 0, hoy: Array.isArray(hoy) ? hoy : [], error: !!s.error };
} catch(e){ SALDO = { corrido: 0, hoy: [], error: true }; }
// Lo que leyo la IA de la FOTO del cliente ("Leer Pago"): {"tipo":"comprobante|cuenta|otra","monto":..,"moneda":..,"banco":..,"referencia":..}
let FOTO = null;
try {
  const j = $('Leer Pago').first().json || {};
  FOTO = JSON.parse(String(j.content || j.text || '').replace(/```json/gi, '').replace(/```/g, '').trim());
} catch(e){ FOTO = null; }
// El corte que pide un cobrador ("Corte del Cobrador" lee la vista corte_pendiente: lo que cobro desde su ultimo corte, 27/11).
let CORTE = null;
try { const c = $('Corte del Cobrador').first().json || {}; CORTE = c.error ? { error: true } : c; } catch(e){ CORTE = null; }
const cortes = [];                 // el corte de ESTE mensaje (se guarda en cortes_cobradores: el proximo corte empieza aqui)
const entregas = [];               // el "recibido" de ESTE mensaje (se guarda en entregas_cobradores)
const nuevos = [];                 // los movimientos de ESTE mensaje (se anotan y se usan para el saldo)
const diaEcuador = iso => new Date((Date.parse(iso) || Date.now()) - 5 * 3600000).toISOString().slice(0, 10);
function anotar(tipo, forma, monto, detalle, msgId){
  const v = Math.round(Number(monto) * 100) / 100;
  if (!(v > 0)) return null;
  const m = { grupo_jid: grupo.grupo_jid, cliente_nombre: nombre, fecha: fila.fecha_mensaje || new Date().toISOString(), dia: diaEcuador(fila.fecha_mensaje),
              tipo, forma: forma ? String(forma).toLowerCase() : null, monto_usd: v, detalle: String(detalle || '').slice(0, 200),
              mensaje_id: msgId || fila.mensaje_id, clave: (msgId || fila.mensaje_id) + ':' + tipo + ':' + nuevos.length, estado: 'ok', origen: 'bot' };
  nuevos.push(m);
  return m;
}
// Que pedidos del dia quedan cubiertos con lo pagado (en orden de llegada; 1$ de tolerancia por redondeo).
function cubiertos(movs){
  const pagos = movs.filter(m => m.tipo !== 'pedido').reduce((a, m) => a + (Number(m.monto_usd) || 0), 0);
  let acum = 0; const out = new Map();
  for (const m of movs.filter(m => m.tipo === 'pedido')){ acum += Number(m.monto_usd) || 0; out.set(m, acum <= pagos + 1); }
  return out;
}
const cuentasDelDia = movs => { let pagos = 0, pedidos = 0; for (const m of movs){ const v = Number(m.monto_usd) || 0; if (m.tipo === 'pedido') pedidos += v; else pagos += v; } return { pagos, pedidos, saldo: pagos - pedidos }; };
const conSigno = v => (v >= 0 ? '+' : '-') + fmt2(Math.abs(Math.round(v * 100) / 100)) + '$';
const horaDe = iso => new Date((Date.parse(iso) || Date.now()) - 5 * 3600000).toISOString().slice(11, 16);
// Lo que cuesta un pedido en $: el $ del pedido; si solo trae la moneda local, la moneda local / la tasa (RST o cuenta).
function dolaresDelPedido(ped, forma){
  if (ped.monto_usd > 0) return ped.monto_usd;
  if (!(ped.monto_local > 0)) return null;
  const p = filaDeLaHoja(ped.pais);
  if (!p) return null;
  const t = calcularTasaEnvio(p, forma === 'CUENTA' ? 'mayor' : 'mayor_rst');
  return (t > 0) ? ped.monto_local / t : null;
}
// Los montos en dolares escritos en el pedido, en orden ("Pedido USDT / 150$ / Cliente / 145.5$" -> [150, 145.5]).
function montosEnDolares(texto){
  const aNum = s => { s = String(s).replace(/[^0-9.,]/g, '').replace(/[.,]+$/, ''); if (!s) return null; const u = Math.max(s.lastIndexOf('.'), s.lastIndexOf(','));
    let v; if (u === -1) v = parseFloat(s); else { const dec = s.slice(u + 1); v = (dec.length === 3) ? parseFloat(s.replace(/[.,]/g, '')) : parseFloat(s.slice(0, u).replace(/[.,]/g, '') + '.' + dec); }
    return isNaN(v) ? null : v; };
  const out = [];
  for (const m of String(texto || '').matchAll(/\$[ \t]*(\d[\d.,]*\d|\d)|(?<![\w.@$])(\d[\d.,]*\d|\d)[ \t]*(?:\$|usdt\b|usd\b|d[oó]lares)/gi)){
    const v = aNum(m[1] || m[2]);
    if (v !== null && v > 0 && out.indexOf(v) === -1) out.push(v);
  }
  return out;
}
// BINANCE: de todo lo que mando el cliente se pega UNA sola cosa, en este orden (protocolo de pedidos, seccion 8):
// BEP20 (0x..., 42) > TRC20 (T..., 34) > correo > telefono > ID Binance. Se lee del texto ORIGINAL (las direcciones distinguen mayusculas).
function destinosBinance(texto){
  const t = String(texto || ''), out = [];
  const bep = t.match(/\b0x[a-fA-F0-9]{40}\b/); if (bep) out.push({ tipo: 'BEP20', valor: bep[0] });
  const trc = t.match(/\bT[1-9A-HJ-NP-Za-km-z]{33}\b/); if (trc) out.push({ tipo: 'TRC20', valor: trc[0] });
  // otra billetera (ni BEP20 ni TRC20: otra red o mal copiada): se pega, pero se avisa que hay que confirmar la red
  const otra = (bep || trc) ? null : t.match(/\b(?=[A-Za-z0-9]*\d)(?=[A-Za-z0-9]*[A-Za-z])[A-Za-z0-9]{26,60}\b/); if (otra) out.push({ tipo: 'billetera', valor: otra[0] });
  const correo = t.match(/[^\s@*:]+@[^\s@*]+\.[a-zA-Z]{2,}/); if (correo) out.push({ tipo: 'correo', valor: correo[0] });
  const tel = t.match(/(?:\+\d{1,3}[\s-]?)\d[\d\s-]{6,14}\d/); if (tel) out.push({ tipo: 'teléfono', valor: tel[0].replace(/[\s-]/g, '') });
  const id = t.match(/\b(?:binance\s*)?(?:pay\s*)?id\b(?:\s*(?:de\s*)?binance)?\s*[:./]?\s*([A-Za-z0-9_.-]{4,30})/i); if (id) out.push({ tipo: 'ID Binance', valor: id[1] });
  return out;
}
// Un pedido a BINANCE o ZELLE (caja dolar) va en 2 mensajes (protocolo, secciones 1.4, 8 y 9; fotos de los grupos):
//   1) BINANCE: solo el destino ganador (si es BEP20, otro mensaje que dice "BEP20") | ZELLE: los datos tal cual los mando el cliente
//   2) lo COBRADO en $ / el NOMBRE del cliente / lo que se ENTREGA ("150 / NOMBRE / 145.5")
// Binance: el cliente dice lo que paga en $ y se le resta el % ("$1500 - 3% = 1455"). Zelle: dice lo que hay que mandar por Zelle y
// se le suma el % ("$240 + 3% = 247.20"). Si el cliente escribe los dos montos se usan esos, y se avisa si no cuadran con la hoja.
function pedidoEnDolares(g, ped, texto, forma, por){
  const notas = [], info = [];
  const lista = montosEnDolares(texto);
  const base = lista.length ? lista : [ped.monto_usd, ped.datos && ped.datos.monto_sin_moneda].filter(v => v !== null && v !== undefined).map(Number);
  let cobrado = null, entregar = null;
  if (base.length >= 2){ const ord = [...new Set(base)].sort((a, b) => b - a); cobrado = ord[0]; entregar = ord[1]; }
  else if (base.length === 1){ if (g === 'BINANCE') cobrado = base[0]; else entregar = base[0]; }
  const precio = precioMayor(g, forma, cobrado || entregar || 0);
  if (precio){
    if (cobrado !== null && entregar === null) entregar = redondear(cobrado * precio.tasa);
    else if (entregar !== null && cobrado === null) cobrado = redondear(entregar * (1 + precio.pct / 100));
    else if (cobrado !== null && entregar !== null){
      // Binance: lo que se entrega sale de lo cobrado (- %). Zelle: lo cobrado sale de lo que se entrega (+ %).
      const [c2, e2] = (g === 'BINANCE') ? [cobrado, redondear(cobrado * precio.tasa)] : [redondear(entregar * (1 + precio.pct / 100)), entregar];
      if (Math.abs(c2 - cobrado) > 0.05 || Math.abs(e2 - entregar) > 0.05)
        notas.push('⚠️ El cliente puso ' + fmt2(cobrado) + ' → ' + fmt2(entregar) + ', pero con el precio ' + precio.nombreModo + ' (' + precio.pct + '%) sería ' + fmt2(c2) + ' → ' + fmt2(e2) + '.');
    }
    info.push((forma ? 'Paga con ' + forma + (por ? ' (' + por + ')' : '') : 'No sé si paga con RST o por cuenta: lo calculé con el precio RST')
      + ' → ' + precio.pct + '% (' + precio.nombreModo + ', de la hoja de tasas).');
    if (!forma && cobrado !== null){ const pc = precioMayor(g, 'CUENTA', cobrado); if (pc && pc.pct !== precio.pct) info.push('Por cuenta sería ' + pc.pct + '%: ' + fmt2(g === 'BINANCE' ? redondear(cobrado * pc.tasa) : redondear(entregar * (1 + pc.pct / 100))) + '.'); }
  } else if (cobrado === null || entregar === null) notas.push('⚠️ No pude leer el precio en la hoja de tasas: falta calcular ' + (cobrado === null ? 'lo que se cobra' : 'lo que se entrega') + '.');
  if (cobrado === null && entregar === null) notas.push('⚠️ Sin monto: falta que diga cuánto.');
  const msgs = [];
  if (g === 'BINANCE'){
    const ds = destinosBinance(texto);
    if (!ds.length) notas.push('⚠️ No encontré la billetera (BEP20/TRC20), el correo, el teléfono ni el ID de Binance.');
    else {
      msgs.push(ds[0].valor);
      if (ds[0].tipo === 'BEP20') msgs.push('BEP20');
      if (ds[0].tipo === 'billetera') notas.push('⚠️ La billetera no parece BEP20 ni TRC20: confirma la red con el cliente.');
      info.push('Se pega ' + (['correo', 'teléfono', 'ID Binance'].indexOf(ds[0].tipo) !== -1 ? 'el ' : 'la ') + ds[0].tipo + (ds.length > 1 ? ' (también mandó ' + unir(ds.slice(1).map(d => d.tipo)) + ': no se pega).' : '.'));
    }
  } else msgs.push(texto);
  msgs.push([fmt2(cobrado), nombre.toUpperCase(), fmt2(entregar)].join('\n'));
  return { msgs, notas, info, cobrado, entregar };
}

const envios = [];
let estadoFila = '', grupoDestinoFila = '', real = false;
let filaPendiente = 0;

// ---------- EL CLIENTE EDITO UN MENSAJE SUYO (26/11) ----------
// WhatsApp manda las ediciones CIFRADAS: se sabe cual mensaje cambio, nunca que dice ahora. Si lo que edito
// fue un retiro o una cuenta, el dato guardado quedo viejo y no hay forma de saber en que. Se le pide que lo
// mande de nuevo y la fila vieja pasa a 'verificar': asi no cuenta como repetida cuando llegue el reenvio
// (mismo banco y mismo codigo) ni se le avisa de vencimiento a un codigo que va a ser reemplazado.
let filaEditada = 0;
if (fila.tipo === 'edicion'){
  const idEditado = String(datos.editado_id || '');
  let orig = null;
  // (desde el 27/11 "Retiros Recientes" tambien trae las filas 'otro' de los pedazos de pedido: editar un saludo no cuenta)
  try { orig = $('Retiros Recientes').all().map(i => i.json).find(r => r && r.id && String(r.mensaje_id) === idEditado && ['rst', 'rct', 'mixto', 'beneficiario'].indexOf(r.tipo) !== -1) || null; } catch(e){}
  if (!orig) return [];                      // edito un saludo, una foto o algo viejo: no hay nada que corregir
  real = (MODO === 'real') && grupo.publicar === true;
  filaEditada = orig.id;
  estadoFila = 'verificar';
  envios.push({ etapa: 'cliente', tipo: 'texto', jid: grupo.grupo_jid, texto: TEXTO_CLIENTE_EDITO, citar: idEditado,
                vista: '➡️ al cliente (citando el mensaje que editó): "' + TEXTO_CLIENTE_EDITO + '"' });
  const queEs = (orig.tipo === 'beneficiario') ? 'una cuenta' : 'un retiro';
  const aviso = '✏️ ' + nombre + ' editó ' + queEs + ' que ya había mandado' + (orig.banco ? ' (' + orig.banco + ')' : '') +
                '. WhatsApp no deja leer las ediciones, así que se le pidió que lo mande de nuevo; la fila ' + orig.id + ' queda en verificar.';
  envios.push({ etapa: 'aviso', tipo: 'texto', jid: GRUPO_AVISOS, texto: aviso, vista: aviso });
}
else if (pendiente && respuesta === 'no'){
  // ---------- el cliente dice que NO es ese banco ----------
  real = (MODO === 'real') && grupo.publicar === true;
  filaPendiente = pendiente.id;
  estadoFila = 'verificar';
  envios.push({ etapa: 'cliente', tipo: 'texto', jid: grupo.grupo_jid, texto: TEXTO_CLIENTE_VERIFICAR, citar: pendiente.mensaje_id,
                vista: '➡️ al cliente (dijo que NO es ' + (pendiente.banco || 'ese banco') + '; citando su retiro): "' + TEXTO_CLIENTE_VERIFICAR + '"' });
}
else if (grupo.tipo === 'cliente'){
  // ---------- un retiro del cliente ----------
  real = (MODO === 'real') && grupo.publicar === true;
  if (confirmado) filaPendiente = pendiente.id;
  // Una charla NO es un pedido ("¿que tanto demora en retirar los rst de guayaquil?", "el Pichincha esta fallando la
  // opcion de RST"): sin ningun dato (ni monto, ni telefono, ni cedula, ni codigo) no se le pide nada a nadie; y
  // una pregunta con datos incompletos tampoco.
  const preguntando = /[?¿]/.test(String(fila.texto || ''));
  const hayDatos = r => (r.monto_usd !== null && r.monto_usd !== undefined) || (r.tipo !== 'rct' && !!(r.datos && (r.datos.telefono || r.datos.cedula || r.datos.clave || (r.datos.codigos || []).length)));
  // Si el cliente confirmo el banco, los retiros son los del mensaje que se le pregunto (solo los del banco dudoso: los demas ya se trataron).
  const fuente = confirmado ? pendiente.registros.filter(r => r.datos && r.datos.banco_dudoso) : (Array.isArray(datos.registros) ? datos.registros : []);
  const regs = fuente.filter(r => r.tipo === 'rst' || r.tipo === 'rct')
    .filter(r => confirmado || (r.tipo === 'rct' ? !preguntando || faltan(r).length === 0 : hayDatos(r) && (!preguntando || faltan(r).length === 0)));
  const incompletos = [], sinGrupo = [], publicados = [], jepMontos = [], repetidos = [], dudosos = [], sinBanco = [];
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
    if (reg.datos && reg.datos.sin_banco){ sinBanco.push(reg); continue; }       // parece un RST pero no dice de que banco
    // JEP: el codigo dura 15 minutos. Hasta que el cobrador avise que ya esta en el cajero NO se publica nada: se le pide al
    // cobrador que vaya y al cliente que espere (protocolo, seccion 10). Con ese permiso, se publica enseguida.
    if (k === 'jep' && reg.tipo === 'rst' && !enCajero){ jepPide = true; if (reg.monto_usd !== null && reg.monto_usd !== undefined) jepMontos.push(reg.monto_usd); continue; }
    const f = faltan(reg), rv = revisar(reg);                                // lo que falta y lo que viene con el largo equivocado
    if (f.length || rv.length){ incompletos.push({ reg, f, rv }); continue; }
    // Completo, pero con el banco mal escrito ("produbaco"): antes de publicarlo se le pregunta al cliente (mas abajo).
    if (!confirmado && reg.datos && reg.datos.banco_dudoso){ dudosos.push(reg); continue; }
    const rep = repetidoDe(reg);
    if (rep){ const ahoraMsg = Date.parse(fila.fecha_mensaje) || Date.now(); repetidos.push({ reg, min: rep.ts ? Math.max(1, Math.round((ahoraMsg - rep.ts) / 60000)) : 0 }); continue; }
    const dueno = GRUPO_DEL_BANCO[k];
    const conPermisoJep = (k === 'jep' && reg.tipo === 'rst' && enCajero);     // el cobrador ya esta ahi: va directo a JEP, sea la hora que sea
    const enBanco = abierto || conPermisoJep;                                   // en el grupo del banco (y no en COBRAR MAÑANA)
    const destinoClave = enBanco ? dueno : GRUPO_COBRAR_MANANA;
    const jid = destinoClave ? destinos[destinoClave] : null;
    if (!dueno || (real && !jid)){ sinGrupo.push({ reg, donde: !dueno ? 'ese banco no tiene grupo' : ('no encuentro el grupo ' + NOMBRE_GRUPO(destinoClave)) }); continue; }
    const hoy = !enBanco && DURA_24H.indexOf(k) === -1;                    // se vence el mismo dia
    const texto = bloque(nombre, reg, false) + (hoy ? '\n' + AVISO_COBRAR_HOY : '');
    const vistaTexto = bloque(nombre, reg, true) + (hoy ? '\n' + AVISO_COBRAR_HOY : '');
    publicados.push({ k, destinoClave, estado: enBanco ? 'publicado' : (hoy ? 'cobrar_hoy' : 'en_cobrar_manana'), reg });
    envios.push({ etapa: 'banco', tipo: 'texto', jid, texto,
                  vista: '➡️ iría a ' + NOMBRE_GRUPO(destinoClave) + (enBanco ? '' : ' (fuera de horario)') + (jid ? '' : ' (grupo todavía no cargado en la tabla)') + ':\n' + vistaTexto,
                  mapa: { cliente_jid: grupo.grupo_jid, cliente_nombre: nombre, id_msg_cliente: msgRef, banco: reg.banco, tipo: reg.tipo, fila_id: filaRef, destino: NOMBRE_GRUPO(destinoClave) },
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
  // ---------- el RST/RCT que se publica es un PAGO del cliente: cuenta apenas llega (Kelvin, 27/11) ----------
  for (const p of publicados) anotar('pago', 'rst', p.reg.monto_usd, (p.reg.tipo === 'rct' ? 'RCT ' : 'RST ') + (p.reg.banco || ''), msgRef);
  // ---------- la FOTO del cliente, leida con IA ("Leer Pago"): si es el comprobante de su pago en dolares, es un PAGO por cuenta ----------
  var fotoNota = '';
  if (fila.tipo === 'captura' && !regs.length && FOTO){
    const numero = x => { if (typeof x === 'number') return x; const s = String(x || '').replace(/[^0-9.,]/g, '').replace(/[.,]+$/, ''); const u = Math.max(s.lastIndexOf('.'), s.lastIndexOf(','));
      const v = u === -1 ? parseFloat(s) : (s.length - u - 1 === 3 ? parseFloat(s.replace(/[.,]/g, '')) : parseFloat(s.slice(0, u).replace(/[.,]/g, '') + '.' + s.slice(u + 1))); return isNaN(v) ? 0 : v; };
    const visible = x => x && !/no visible/i.test(String(x));
    if (FOTO.tipo === 'comprobante'){
      const monto = numero(FOTO.monto), mon = String(FOTO.moneda || '').toUpperCase();
      if (monto > 0 && (!mon || mon === 'USD' || mon === 'USDT')) anotar('pago', 'cuenta', monto, 'foto de pago' + (visible(FOTO.banco) ? ': ' + FOTO.banco : '') + (visible(FOTO.referencia) ? ' ref ' + FOTO.referencia : ''));
      else fotoNota = '⚠️ La foto parece un pago, pero no pude leer el monto en dólares' + (visible(FOTO.monto) ? ' (leí ' + FOTO.monto + (mon ? ' ' + mon : '') + ')' : '') + ': revísala.';
    } else if (FOTO.tipo === 'cuenta') fotoNota = '📷 La foto parece los datos de una CUENTA (un pedido en foto): todavía no los leo.';
  }
  // ---------- NO PUSO EL NOMBRE DEL BANCO (27/11) ----------
  // Cada RST sin el nombre del banco (el de "¿es de Guayaquil?" y el de "¿de qué banco es?") se anota (7 dias). Cuando el
  // cliente contesta "sí" a "¿Su retiro es de Guayaquil?" y se publica, se le deja el recordatorio: "Por favor, siempre colócale
  // el nombre del banco."; desde la 3ra vez en 7 dias: "Es obligatorio que le coloques el nombre del banco."
  if (!confirmado && regs.some(r => r.datos && (r.datos.banco_deducido || r.datos.sin_banco))){
    redisSiempre.push({ clave: 'sinBanco:' + grupo.grupo_jid, valor: JSON.stringify(vecesSinBanco.concat([Date.now()]).slice(-20)), ttl: 7 * 24 * 3600 });
  }
  if (confirmado && publicados.length && pendiente.registros.some(r => r.datos && r.datos.banco_deducido)){
    const firme = vecesSinBanco.length >= VECES_OBLIGATORIO;
    const recordar = firme ? TEXTO_BANCO_OBLIGATORIO : TEXTO_PONER_BANCO;
    envios.push({ etapa: 'cliente', tipo: 'texto', jid: grupo.grupo_jid, texto: recordar, citar: msgRef,
                  vista: '➡️ al cliente (citando su retiro' + (firme ? '; ya van ' + vecesSinBanco.length + ' veces en 7 días sin el banco' : '') + '): "' + recordar + '"' });
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
  // ---------- el banco venia mal escrito ("produbaco"): ¿Su retiro es de Produbanco? (26/11) ----------
  // Solo si es lo UNICO del mensaje: la fila queda en 'confirmar_banco' y el "si" / "no" del cliente decide (arriba).
  // Si el mensaje trae ademas otros retiros, se le pide que lo revise y lo mande de nuevo (una fila no puede esperar y estar publicada a la vez).
  if (dudosos.length){
    const solo = !publicados.length && !incompletos.length && !sinGrupo.length && !repetidos.length && !jepPide && !sinBanco.length;
    if (solo){
      const montos = dudosos.filter(r => r.monto_usd !== null && r.monto_usd !== undefined).map(r => fmtMonto(r.monto_usd) + '$');
      const bancos = [...new Set(dudosos.map(r => r.banco))];
      const texto = (dudosos.length === 1 ? '¿Su retiro' : '¿Sus retiros') + (montos.length ? ' de ' + unir(montos) : '') + (dudosos.length === 1 ? ' es' : ' son') + ' de ' + unir(bancos) + '? Responda sí o no, por favor.';
      // Por que se pregunta: el banco mal escrito ("produbaco"), o no dijo el banco pero trae 2 codigos de 4 (Guayaquil, 27/11).
      const escritos = [...new Set(dudosos.filter(r => !r.datos.banco_deducido).map(r => r.datos.banco_dudoso))];
      const porque = [escritos.length ? 'escribió "' + escritos.join('", "') + '"' : '', dudosos.some(r => r.datos.banco_deducido) ? 'no dijo el banco, pero 2 códigos de 4 cifras son de Guayaquil' : ''].filter(Boolean).join('; ');
      envios.push({ etapa: 'cliente', tipo: 'texto', jid: grupo.grupo_jid, texto, citar: fila.mensaje_id,
                    vista: '➡️ al cliente (' + porque + '; citando su mensaje): "' + texto + '"' });
      estadoFila = 'confirmar_banco';
    } else {
      for (const reg of dudosos){
        if (reg.datos.banco_deducido) sinBanco.push(reg);                     // "¿Ese mensaje es un RST? No reconocí de qué banco es..."
        else incompletos.push({ reg, f: [], rv: ['el nombre del banco ("' + reg.datos.banco_dudoso + '") no se entiende bien'] });
      }
    }
  }
  // ---------- parece un RST pero no dice de que banco ----------
  if (sinBanco.length){
    const posibles = [...new Set(sinBanco.flatMap(r => (r.datos && r.datos.posibles) || []))];
    const texto = posibles.length > 1
      ? '¿Su retiro es de ' + posibles.slice(0, -1).join(', ') + ' o de ' + posibles[posibles.length - 1] + '? Envíe todos los datos de nuevo en un solo texto, con el nombre del banco, por favor.'
      : TEXTO_SIN_BANCO;
    envios.push({ etapa: 'cliente', tipo: 'texto', jid: grupo.grupo_jid, texto, citar: fila.mensaje_id, vista: '➡️ al cliente (citando su mensaje): "' + texto + '"' });
    if (!estadoFila) estadoFila = 'falta_datos';
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
  for (const r of repetidos){
    const monto = (r.reg.monto_usd !== null && r.reg.monto_usd !== undefined) ? ' ' + fmtMonto(r.reg.monto_usd) + '$' : '';
    const aviso = '⚠️ ' + nombre + ': llegó otra vez un ' + (r.reg.tipo === 'rct' ? 'retiro con tarjeta' : 'RST') + ' de ' + r.reg.banco + monto
      + ' con el MISMO código que uno de ' + (r.min ? 'hace ' + r.min + ' min' : 'hace un rato') + '. NO lo publiqué otra vez. '
      + 'Si es una corrección (otro teléfono u otro dato), pásale tú el cambio al banco. Su mensaje está en ' + (grupo.nombre || 'su grupo') + '.';
    envios.push({ etapa: 'aviso', tipo: 'texto', jid: GRUPO_AVISOS, texto: aviso, vista: aviso });
    if (!estadoFila) estadoFila = 'repetido';
  }
  // ---------- PEDIDOS A PAISES (beneficiario): SOLO VISTA PREVIA, aun en modo real (pedido de Kelvin, 26/11) ----------
  // La cuenta a la que hay que pagarle al cliente (Venezuela, Banesco, Colombia, Perú, Binance...). Hoy los pasa la operadora
  // a mano al grupo del pais: el NOMBRE del cliente en mayusculas arriba y debajo los datos que mando el cliente. Aqui solo se
  // muestra en el grupo de avisos COMO los pasaria el bot, para estudiarlo. Todavia NO se publica en ningun grupo: falta
  // decidir con Kelvin cuando (¿al confirmar el pago?) y que significa la linea "RST" que pone la operadora.
  // Si este mensaje COMPLETA un pedido mandado en dos o tres mensajes (la cuenta en uno y el monto en otro, 27/11), la vista
  // previa es la del pedido entero y lleva el texto de todos los pedazos.
  const juntado = pedidoJuntado();
  const pedidos = juntado ? [juntado.pedido] : (Array.isArray(datos.registros) ? datos.registros : []).filter(r => r.tipo === 'beneficiario');
  const textoPedido = juntado ? juntado.texto : String(fila.texto || '').trim();
  if (pedidos.length){
    const grupoDe = p => (p.datos && p.datos.destino_sugerido) || '';
    const nombres = [...new Set(pedidos.map(grupoDe).filter(Boolean))];
    const notas = [];
    const sinPais = pedidos.filter(p => !p.pais);
    if (sinPais.length){
      const cands = [...new Set(sinPais.flatMap(p => (p.datos && p.datos.candidatos) || []))];
      notas.push('⚠️ ' + (pedidos.length > 1 ? sinPais.length + ' de las cuentas' : 'La cuenta') + ' sin país claro' + (cands.length ? ' (podría ser ' + unir(cands) + ')' : '') + ': no sabría a qué grupo pasarla.');
    }
    const paisSinGrupo = [...new Set(pedidos.filter(p => p.pais && !grupoDe(p)).map(p => p.pais))];
    if (paisSinGrupo.length) notas.push('⚠️ ' + unir(paisSinGrupo) + ': no hay grupo para ese país.');
    const noCargados = nombres.filter(n => !destinos[quitar(n)]);
    if (noCargados.length) notas.push('⚠️ No hay grupo ' + unir(noCargados) + ' en la tabla de grupos.');
    // Venezuela: toda cuenta tiene 20 digitos (protocolo de pedidos). El Pago Movil por ahora SI se acepta (Kelvin, 27/11).
    for (const p of pedidos.filter(p => p.datos && p.datos.cuenta_ve_digitos)) notas.push('⚠️ La cuenta de Venezuela tiene ' + p.datos.cuenta_ve_digitos + ' dígitos (deben ser 20): hay que pedirle que la revise.');
    const cabecera = juntado ? ' (junté ' + juntado.n + ' mensajes)' : '';
    const caja = (pedidos.length === 1 && nombres.length === 1 && (nombres[0] === 'BINANCE' || nombres[0] === 'ZELLE')) ? nombres[0] : '';
    // RST o CUENTA: por la tasa que uso, lo que anoto Kelvin o como lo pasa siempre la operadora (ver comoPaga)
    const cp = comoPaga(pedidos[0], textoPedido, caja);
    const forma = cp.forma;
    notas.push(...cp.notas);
    let vista, pedidoCaja = null;
    if (caja){
      // ---------- BINANCE / ZELLE: en 2 mensajes, con lo cobrado y lo que se entrega calculados con la hoja de tasas ----------
      const r = pedidoEnDolares(caja, pedidos[0], textoPedido, forma, cp.por);
      pedidoCaja = r;
      vista = '📦 PEDIDO' + cabecera + ' → iría a ' + caja + ', en ' + r.msgs.length + ' mensajes:\n' + r.msgs.map((m, i) => '— ' + (i + 1) + ' —\n' + m).join('\n')
        + (r.info.length ? '\n\nℹ️ ' + r.info.join(' ') : '') + (notas.concat(r.notas).length ? '\n\n' + notas.concat(r.notas).join('\n') : '');
    } else {
      // ---------- los demas paises: el NOMBRE arriba, en la 2da linea como paga (RST o CUENTA) y debajo los datos ----------
      const sinMonto = pedidos.filter(p => [p.monto_usd, p.monto_local, p.datos && p.datos.monto_sin_moneda].every(v => v === null || v === undefined));
      if (sinMonto.length) notas.push('⚠️ ' + (pedidos.length > 1 ? sinMonto.length + ' sin monto' : 'Sin monto') + ': falta que diga cuánto.');
      notas.push(forma ? 'ℹ️ ' + forma + ': ' + cp.por + '.' : 'ℹ️ No sé si paga con RST o por cuenta: ' + cp.porQueNo + '.');
      const donde = nombres.length ? unir(nombres) : 'NINGÚN grupo';
      vista = '📦 PEDIDO' + (pedidos.length > 1 ? ' (' + pedidos.length + ' cuentas)' : '') + cabecera + ' → iría a ' + donde + ':\n'
        + nombre.toUpperCase() + '\n' + (forma || 'RST o CUENTA (?)') + '\n\n' + textoPedido + (notas.length ? '\n\n' + notas.join('\n') : '');
    }
    envios.push({ etapa: 'pedido', soloEnsayo: true, tipo: 'texto', jid: GRUPO_AVISOS, texto: vista, vista });
    // el pedido se anota en $, al precio de como paga (Binance/Zelle: lo cobrado)
    if (caja){ if (pedidoCaja && pedidoCaja.cobrado > 0) anotar('pedido', forma || null, pedidoCaja.cobrado, caja + ' ' + fmt2(pedidoCaja.cobrado) + ' → ' + fmt2(pedidoCaja.entregar)); }
    else for (const p of pedidos){
      const usd = dolaresDelPedido(p, forma);
      if (usd > 0) anotar('pedido', forma || null, usd, (grupoDe(p) || p.pais || 'pedido') + (p.monto_usd > 0 ? '' : ' ' + fmt2(p.monto_local) + ' ' + (p.moneda || '') + ' (convertido)'));
    }
  }
  // ---------- SALDO DEL DIA (vista previa): pago + pedidos / pedidos + pago ----------
  // Solo sale cuando importa: hay un pedido nuevo, un pago que libera pedidos o que llega con pedidos esperando, o algo raro en la
  // foto. Un RST cualquiera sin pedidos de por medio se anota callado (si no, en modo real cada RST mandaria un aviso de mas).
  const antesS = SALDO.hoy, despuesS = antesS.concat(nuevos), cubAS = cubiertos(antesS), cubDS = cubiertos(despuesS);
  const hayEsperando = [...cubDS.values()].some(v => v === false);
  const importa = nuevos.some(m => m.tipo === 'pedido') || antesS.some(m => m.tipo === 'pedido' && cubAS.get(m) === false) || hayEsperando || !!fotoNota
    || (fila.tipo === 'captura' && nuevos.length > 0);
  if (importa && (nuevos.length || fotoNota)){
    const antes = antesS, despues = despuesS;
    const cubA = cubAS, cubD = cubDS, d = cuentasDelDia(despues);
    const lineas = [];
    for (const m of nuevos.filter(m => m.tipo === 'pago')) lineas.push('💵 Pago: ' + fmt2(m.monto_usd) + '$ (' + m.detalle + ')');
    for (const m of nuevos.filter(m => m.tipo === 'pedido')) lineas.push((cubD.get(m) ? '✅ Pedido pagado: ' : '⏳ Pedido esperando su pago: ') + m.detalle + ' = ' + fmt2(m.monto_usd) + '$');
    const liberados = antes.filter(m => m.tipo === 'pedido' && cubA.get(m) === false && cubD.get(m) === true);
    if (liberados.length) lineas.push('✅ Con este pago ya pasarían: ' + liberados.map(m => m.detalle + ' (' + horaDe(m.fecha) + ', ' + fmt2(Number(m.monto_usd)) + '$)').join('; '));
    if (fotoNota) lineas.push(fotoNota);
    if (nuevos.length){
      const r2 = v => Math.round(v * 100) / 100;
      const delta = nuevos.reduce((a, m) => a + (m.tipo === 'pedido' ? -m.monto_usd : m.monto_usd), 0);
      lineas.push('💰 Hoy: pagó ' + fmt2(r2(d.pagos)) + '$ · pidió ' + fmt2(r2(d.pedidos)) + '$ → ' + (d.saldo >= 0 ? 'le sobran ' + fmt2(r2(d.saldo)) : 'le faltan ' + fmt2(r2(-d.saldo))) + '$ · corrido: ' + conSigno(SALDO.corrido + delta));
    }
    if (nuevos.some(m => m.tipo === 'pedido' && !cubD.get(m))) lineas.push('➡️ al cliente: sticker "Esperando su pago para procesar"');
    if (SALDO.error) lineas.push('⚠️ No pude leer los saldos: ¿ya está creada la tabla movimientos_mayor en Supabase (sql/mayor_saldos.sql)?');
    const vistaSaldo = lineas.join('\n');
    envios.push({ etapa: 'saldo', soloEnsayo: true, tipo: 'texto', jid: GRUPO_AVISOS, texto: vistaSaldo, vista: vistaSaldo });
  }
} else if (esCorte(grupo, fila)){
  // ---------- CORTE DEL COBRADOR: "corte hasta aqui" (Kelvin, 27/11) ----------
  // Lo que cobro este cobrador (los RST que el marco como cobrados, en todos los bancos) desde su ultimo corte hasta la hora de
  // este mensaje. Solo el total: Kelvin lo compara con el efectivo que le entrega. El corte se guarda: el proximo empieza aqui.
  real = (MODO === 'real') && grupo.publicar === true;
  const hasta = fila.fecha_mensaje || new Date().toISOString();
  const ec = iso => new Date((Date.parse(iso) || Date.now()) - 5 * 3600000);
  const hora12 = iso => { const d = ec(iso); let h = d.getUTCHours(); const ap = h >= 12 ? 'pm' : 'am'; h = h % 12 || 12; return h + ':' + String(d.getUTCMinutes()).padStart(2, '0') + ' ' + ap; };
  const mismoDia = iso => ec(iso).toISOString().slice(0, 10) === ec(hasta).toISOString().slice(0, 10);
  const cuando = iso => (mismoDia(iso) ? 'las ' : 'el ' + ec(iso).toISOString().slice(8, 10) + '/' + ec(iso).toISOString().slice(5, 7) + ' a las ') + hora12(iso);
  const desdeCorte = iso => (mismoDia(iso) ? 'de las ' : 'del ' + ec(iso).toISOString().slice(8, 10) + '/' + ec(iso).toISOString().slice(5, 7) + ' a las ') + hora12(iso);
  const quien = String(datos.autor_nombre || '').trim() || 'el cobrador';
  if (!CORTE || CORTE.error){
    const aviso = '⚠️ ' + quien + ' pidió su corte en ' + (grupo.nombre || 'un banco') + ', pero no pude sacarlo: ¿ya está creada la vista corte_pendiente en Supabase (sql/mayor_caja_cobradores.sql)?';
    envios.push({ etapa: 'aviso', tipo: 'texto', jid: GRUPO_AVISOS, texto: aviso, vista: aviso });
  } else {
    const n = Number(CORTE.n_rst) || 0, total = Math.round((Number(CORTE.total_usd) || 0) * 100) / 100;
    const texto = '✂️ Corte hasta ' + cuando(hasta) + ': ' + (n ? fmt2(total) + '$ (' + n + ' RST)' : 'no tienes RST cobrados') + (CORTE.ultimo_corte ? ', desde tu corte ' + desdeCorte(CORTE.ultimo_corte) : '') + '.';
    envios.push({ etapa: 'banco', tipo: 'texto', jid: grupo.grupo_jid, texto, citar: fila.mensaje_id, vista: '➡️ a ' + quien + ' en ' + (grupo.nombre || 'su grupo') + ' (citando su mensaje): "' + texto + '"' });
    cortes.push({ hasta, cobrador: fila.autor_numero || 'desconocido', cobrador_nombre: String(datos.autor_nombre || '').slice(0, 60) || null, grupo_jid: grupo.grupo_jid,
                  n_rst: n, total_usd: total, mensaje_id: fila.mensaje_id });
  }
} else if (esRecibido(grupo, fila)){
  // ---------- "RECIBIDO": el cobrador entrego el efectivo de su corte (Kelvin, 27/11) ----------
  // Kelvin o la operadora citan el "corte hasta aqui" del cobrador y escriben "recibido 4100" (o solo "recibido" = el total del
  // corte). Se anota la entrega a nombre de ESE cobrador y se dice cuanto queda debiendo (lo cobrado menos lo entregado).
  real = (MODO === 'real') && grupo.publicar === true;
  const quienRecibe = fila.autor_rol === 'kelvin' ? 'Kelvin' : fila.autor_rol === 'operadora' ? 'la operadora' : (String(datos.autor_nombre || '').trim() || 'un operador');
  if (!CORTE || CORTE.error || !CORTE.cobrador){
    const aviso = '⚠️ ' + quienRecibe + ' escribió "recibido" en ' + (grupo.nombre || 'un banco') + ', pero no encontré el corte que citó'
      + (CORTE && CORTE.error ? ' (¿ya está creada la vista caja_consulta en Supabase? sql/mayor_caja_recibido.sql)' : ': hay que citar el mensaje "corte hasta aquí" del cobrador') + '.';
    envios.push({ etapa: 'aviso', tipo: 'texto', jid: GRUPO_AVISOS, texto: aviso, vista: aviso });
  } else {
    // el monto que escribio ("recibido 4.100" / "recibido 4100,50"); si no escribio ninguno, es el total del corte
    const s = (String(fila.texto || '').match(/\d[\d.,]*/) || [''])[0].replace(/[.,]+$/, '');
    const u = Math.max(s.lastIndexOf('.'), s.lastIndexOf(','));
    const escrito = !s ? null : (u === -1 ? parseFloat(s) : (s.length - u - 1 === 3 ? parseFloat(s.replace(/[.,]/g, '')) : parseFloat(s.slice(0, u).replace(/[.,]/g, '') + '.' + s.slice(u + 1))));
    const total = Math.round((Number(CORTE.total_usd) || 0) * 100) / 100;
    const monto = Math.round(((escrito > 0) ? escrito : total) * 100) / 100;
    const cobrador = String(CORTE.cobrador_nombre || '').trim() || 'el cobrador';
    if (!(monto > 0)){
      const aviso = '⚠️ ' + quienRecibe + ' escribió "recibido" para el corte de ' + cobrador + ', pero ese corte era de 0$ y no dijo cuánto recibió.';
      envios.push({ etapa: 'aviso', tipo: 'texto', jid: GRUPO_AVISOS, texto: aviso, vista: aviso });
    } else {
      const debe = Math.round(((Number(CORTE.debe_entregar) || 0) - monto) * 100) / 100;
      const texto = '💵 Recibido de ' + cobrador + ': ' + fmt2(monto) + '$' + (Math.abs(monto - total) > 0.5 ? ' (el corte era de ' + fmt2(total) + '$)' : '') + '. '
        + (debe > 0.5 ? 'Queda debiendo ' + fmt2(debe) + '$.' : debe < -0.5 ? 'Entregó ' + fmt2(-debe) + '$ de más.' : 'Queda en cero.');
      envios.push({ etapa: 'banco', tipo: 'texto', jid: grupo.grupo_jid, texto, citar: fila.mensaje_id, vista: '➡️ en ' + (grupo.nombre || 'el grupo') + ' (citando el "recibido" de ' + quienRecibe + '): "' + texto + '"' });
      entregas.push({ fecha: fila.fecha_mensaje || new Date().toISOString(), cobrador: CORTE.cobrador, cobrador_nombre: CORTE.cobrador_nombre || null, monto_usd: monto,
                      nota: 'recibido por ' + quienRecibe + ' (corte de ' + fmt2(total) + '$)', mensaje_id: fila.mensaje_id });
    }
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
// La fila a la que se le anota el estado: la del cliente (en una respuesta del banco, la del RST original;
// en una edicion, la del mensaje que edito, no la de la edicion en si).
// (Cuando el cliente contesta "si" / "no" a la pregunta del banco, es la fila del retiro que se le pregunto.)
const filaDestino = filaEditada || filaPendiente || ((grupo.tipo === 'destino' && pub && pub.fila_id) ? pub.fila_id : filaId);
// El encabezado de la vista previa: el cliente y su grupo; en un grupo de BANCO (un corte), solo el nombre del grupo.
const cabeceraVista = (grupo.tipo === 'destino') ? String(grupo.nombre || 'grupo del banco') : nombre + (grupo.nombre ? ' (' + grupo.nombre + ')' : '');

if (!real){
  // ENSAYO: nada sale a bancos ni a clientes. Una sola vista previa en el grupo de avisos.
  const vista = '🧪 ENSAYO — ' + cabeceraVista + '\n\n' + envios.map(e => e.vista).filter(Boolean).join('\n\n');
  // En una edicion el estado SI se anota aunque sea ensayo: 'verificar' es lo que hace que el reenvio del
  // cliente no se rechace despues como "repetido" (mismo banco y mismo codigo). No se ve desde afuera.
  // Igual 'confirmar_banco' (la pregunta del banco mal escrito) y el 'verificar' de un "no": son los que dicen si el retiro
  // sigue esperando la respuesta. Un "si" en ensayo deja la fila en 'ensayo' (no se publico nada de verdad).
  const anotar = filaEditada || estadoFila === 'confirmar_banco' || (pendiente && respuesta === 'no');
  // El contador de "sin banco" SI se anota en ensayo: asi la vista previa muestra el recordatorio firme cuando toca.
  return [{ json: { etapa: 'ensayo', tipo: 'texto', jid: GRUPO_AVISOS, texto: vista, fila_id: filaDestino, estado_fila: (anotar ? estadoFila : 'ensayo'), grupo_destino: '',
                    redisSet: redisSiempre.length ? redisSiempre : undefined, movimientos: nuevos.length ? nuevos : undefined, cortes: cortes.length ? cortes : undefined, entregas: entregas.length ? entregas : undefined } }];
}
// REAL: los RST salen de verdad, pero los PEDIDOS siguen siendo solo vista previa en el grupo de avisos.
const salida = envios.filter(e => !e.soloEnsayo).map(e => ({ json: Object.assign({ fila_id: filaDestino, estado_fila: estadoFila, grupo_destino: grupoDestinoFila }, e) }));
const soloVista = envios.filter(e => e.soloEnsayo);
if (soloVista.length){
  const vista = '🧪 ENSAYO — ' + cabeceraVista + '\n\n' + soloVista.map(e => e.vista).join('\n\n');
  salida.push({ json: { etapa: 'ensayo', tipo: 'texto', jid: GRUPO_AVISOS, texto: vista, fila_id: filaDestino, estado_fila: estadoFila || 'ensayo', grupo_destino: grupoDestinoFila } });
}
// (despues de armar TODA la salida: un mensaje que solo trae un pedido sale solo con la vista previa, y ahi van tambien)
if (redisSiempre.length && salida.length) salida[0].json.redisSet = (salida[0].json.redisSet || []).concat(redisSiempre);
// los pagos y pedidos de este mensaje se anotan en movimientos_mayor ("Armar Movimientos"), en ensayo y en real
if (nuevos.length && salida.length) salida[0].json.movimientos = nuevos;
// y el corte del cobrador ("Armar Corte" -> "Guardar Corte")
if (cortes.length && salida.length) salida[0].json.cortes = cortes;
// y la entrega del cobrador ("Armar Entrega" -> "Guardar Entrega")
if (entregas.length && salida.length) salida[0].json.entregas = entregas;
return salida;
'@
$decidirPublicacionCode = $decidirPublicacionCode.Replace('__HORARIO_JK__', $horarioJs).Replace('__PUBLICAR_COMUN__', $publicarJs).Replace('__SI_NO__', $siNoJs)
$decidirPublicacionCode = $decidirPublicacionCode.Replace('__MODO__', $MAYOR_MODO).Replace('__GRUPO_AVISOS__', $GRUPO_AVISOS).Replace('__STICKER_BASE__', $STICKER_BASE)

# ===================== MOTOR DE CALCULO (src/motor.js, el MISMO de la app) =====================
# Los precios de los pedidos a BINANCE / ZELLE salen de aqui (27/11). Igual que en build_ia_atencion.ps1: se le quitan los
# "export" y se inyecta el texto tal cual. Si el motor cambia, hay que volver a construir y desplegar el mayor.
$motorPath = Join-Path $PSScriptRoot 'src\motor.js'
if(-not (Test-Path $motorPath)){ throw "No encontre el motor en $motorPath." }
$motorJs = [System.IO.File]::ReadAllText($motorPath, [System.Text.Encoding]::UTF8)
if($motorJs.Length -gt 0 -and [int][char]$motorJs[0] -eq 0xFEFF){ $motorJs = $motorJs.Substring(1) }
$motorJs = $motorJs -replace '(?m)^export\s+function\s+', 'function '
if($motorJs -match '(?m)^\s*(export|import)\s'){ throw 'src/motor.js tiene import/export que no supe quitar.' }
foreach($obligatoria in @('calcularTasaEnvio','tieneTasaMayorVolumen','tieneTasaMayorRST')){
  if($motorJs -notmatch ('(?m)^function\s+' + $obligatoria + '\b')){ throw "A src/motor.js le falta la funcion '$obligatoria'. El mayor la necesita." }
}
$decidirPublicacionCode = $decidirPublicacionCode.Replace('__MOTOR_JK__', $motorJs)
if($decidirPublicacionCode.Contains('__MOTOR_JK__')){ throw 'Quedo un __MOTOR_JK__ sin reemplazar en Decidir Publicacion.' }

# ===================== PARTE B (27/11): LA FOTO DEL PAGO Y LOS MOVIMIENTOS DEL SALDO =====================
$fotoABinarioCode = @'
// Convierte el base64 de la foto (de Evolution) en binario para que GPT-4o-mini la lea (igual que en "Bot JK - Procesar Media").
const b64 = $json.base64;
if (!b64) return [{ json: { sinImagen: true } }];
return [{ json: { mimetype: $json.mimetype || 'image/jpeg' }, binary: { data: { data: b64, mimeType: $json.mimetype || 'image/jpeg', fileName: 'pago.jpg' } } }];
'@
$PROMPT_LEER_PAGO = @'
Esta imagen la envio un cliente MAYORISTA de una casa de cambio de Ecuador (Cambios JK) en su grupo de WhatsApp. Responde SOLO un JSON valido, sin texto extra. Si es el comprobante o la captura de un pago, deposito o transferencia que hizo el cliente: {"tipo": "comprobante", "monto": <numero con punto decimal, sin simbolos ni separador de miles>, "moneda": "USD | USDT | VES | COP | PEN | ... (el codigo de la moneda del monto; en Ecuador es USD)", "banco": "<banco desde donde pago o al que deposito>", "fecha": "<fecha>", "referencia": "<numero de referencia o de comprobante>"}. Si son los datos de una cuenta bancaria o una billetera (un pedido): {"tipo": "cuenta"}. Si es otra cosa: {"tipo": "otra"}. Si un dato no se ve, escribe "no visible".
'@
$armarCorteCode = @'
// El corte que pidio un cobrador ("corte hasta aqui", 27/11): "Decidir Publicacion" lo trae en el campo "cortes". Se guarda en
// cortes_cobradores: el proximo corte de ese cobrador cuenta desde aqui. El mensaje_id es unico: no se guarda dos veces.
const out = [], vistos = new Set();
for (const it of $input.all()){
  for (const c of ((it.json || {}).cortes || [])){
    if (!c || !c.mensaje_id || vistos.has(c.mensaje_id)) continue;
    vistos.add(c.mensaje_id);
    out.push({ json: c });
  }
}
return out;
'@
$armarEntregaCode = @'
// El "recibido" de Kelvin o de la operadora (27/11): "Decidir Publicacion" trae la entrega del cobrador en el campo "entregas".
// Se guarda en entregas_cobradores. El mensaje_id es unico: un mismo "recibido" no se anota dos veces.
const out = [], vistos = new Set();
for (const it of $input.all()){
  for (const e of ((it.json || {}).entregas || [])){
    if (!e || !e.mensaje_id || vistos.has(e.mensaje_id)) continue;
    vistos.add(e.mensaje_id);
    out.push({ json: e });
  }
}
return out;
'@
$armarMovimientosCode = @'
// Los pagos y pedidos de este mensaje (Parte B, 27/11): "Decidir Publicacion" los trae en el campo "movimientos".
// Uno por fila para "Guardar Movimientos" (movimientos_mayor). La "clave" es unica: si llegara dos veces, no se cuenta dos veces.
const out = [], vistos = new Set();
for (const it of $input.all()){
  for (const m of ((it.json || {}).movimientos || [])){
    if (!m || !m.clave || vistos.has(m.clave)) continue;
    vistos.add(m.clave);
    out.push({ json: m });
  }
}
return out;
'@

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
// QUIEN lo marco (el cobrador): su numero y su nombre en WhatsApp. La caja va por cobrador: en un grupo puede haber varios (27/11).
const quienMarca = [llave.participantAlt, llave.participant, llave.remoteJidAlt].map(x => String(x || '')).find(x => /@s\.whatsapp\.net$/.test(x)) || '';
const porNumero = (llave.fromMe === true) ? 'kelvin' : quienMarca.replace(/\D/g, '');
const porNombre = String(ev.pushName || '').slice(0, 60);
// Un "verificar" o "se dañó" ya pidio un RST nuevo: una ❌ o un "pendiente" que llegue DESPUES (en cualquier orden) no lo pisa.
const salida = (mensajeId, cobro, emoji) => [{ json: { grupo_jid: grupoJid, mensaje_id: String(mensajeId), cobro, emoji, soloPendiente: cobro === 'pendiente' || cobro === 'no_cobrado',
                                                      por: porNumero, por_nombre: porNombre } }];

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

**Si el cliente EDITA un mensaje** (26/11): WhatsApp manda las ediciones cifradas, asi que el bot sabe CUAL mensaje cambio pero nunca que dice ahora. Si lo editado fue un retiro o una cuenta de los ultimos 30 minutos, se le pide que lo mande de nuevo y la fila vieja queda en **verificar** (asi el reenvio no se rechaza como repetido ni se le avisa de vencimiento a un codigo que va a ser reemplazado). Editar un saludo o una foto no dispara nada.

**Banco mal escrito** (26/11): si al nombre del banco le falta, le sobra o le cambia una letra ("produbaco", "pichinca"; en los nombres largos hasta dos), el bot lo reconoce pero NO lo publica: le pregunta al cliente "¿Su retiro es de Produbanco? Responda sí o no" y la fila queda en **confirmar_banco**. Con un "sí" lo publica normal; con un "no" le pide que lo mande de nuevo (fila en verificar). Si la palabra se parece a dos bancos, o el mensaje parece un RST (celular + código + monto) sin ningún banco, le pregunta de qué banco es y que lo mande de nuevo. Si no dice el banco pero trae **dos códigos de 4 cifras** (27/11), eso es Guayaquil: le pregunta "¿Su retiro es de Guayaquil? Responda sí o no". Con el "sí" lo publica y le deja un recordatorio: "Por favor, siempre colócale el nombre del banco."; si en 7 días ya van 3 retiros suyos sin el banco: "Es obligatorio que le coloques el nombre del banco." (el conteo está en Redis, `sinBanco:<grupo>`).

**Monto pegado al banco** (27/11): "Pichincha 140 / 099 ... / Código ..." -> el 140 es el monto (antes los pedazos del celular lo tapaban).

**Pedidos a países** (solo vista previa en avisos, aun en modo real), según `EJEMPLOS PARA EL BOT/protocolo_para_pedidos.md` (27/11): el NOMBRE del cliente arriba, en la 2da línea cómo paga (**RST** o **CUENTA**: un RST suyo de los últimos 30 min = RST; la foto de su pago = CUENTA) y debajo los datos. **BINANCE y ZELLE van en 2 mensajes**: 1) Binance: solo el destino que gana (BEP20 > TRC20 > correo > teléfono > ID; si es BEP20, otro mensaje "BEP20") / Zelle: los datos tal cual; 2) lo cobrado / NOMBRE / lo que se entrega, con los precios de la APP (nodo "Leer Tasas" = la hoja publicada + `src/motor.js`: RST, por cuenta o $1,000+). Venezuela: la cuenta debe tener 20 dígitos (si no, avisa); el Pago Móvil por ahora sí se acepta. La 2da línea (RST o CUENTA) sale de la tasa que usó el cliente, de `grupos_mayor.forma_pago` o de cómo pasa siempre la operadora a ese cliente (nodo "Formas de Pago Vistas").

**Saldo del cliente** (Parte B, 27/11, en ensayo): cada pago (un RST completo apenas llega, o la FOTO de su pago leída con IA en "Leer Pago") y cada pedido en $ se anotan en `movimientos_mayor` ("Armar Movimientos" → "Guardar Movimientos"); "Saldo del Cliente" lee la vista `saldo_mayor` (saldo corrido + movimientos de hoy). Con el saldo del DÍA se ve si cada pedido ya está pagado o espera su pago (sticker "esperando su pago para procesar"), y cuando llega un pago, qué pedidos ya pasarían. Los saldos de antes los anota Kelvin a mano como "ajuste" (ver `sql/mayor_saldos.sql`).

**Caja de los bancos y de cada cobrador** (27/11): cuando un cobrador marca un RST como cobrado (su reacción), "Marcar Cobro" guarda también QUIÉN fue (`cobrado_por`). En Supabase: `caja_bancos_diario` (por banco y día: llegados, cobrados, pendientes, con problema, vencidos), `caja_cobradores` (por cobrador: cobrado, entregado —Kelvin anota las entregas en efectivo en `entregas_cobradores`— y lo que debe). Si el cobrador escribe "corte hasta aquí" en el grupo de su banco, "Corte del Cobrador" lee lo que cobró desde su último corte, el bot le contesta solo el total (en ensayo, vista previa) y el corte se guarda en `cortes_cobradores` ("Armar Corte" → "Guardar Corte"). Cuando el cobrador entrega el efectivo, Kelvin o la operadora citan su "corte hasta aquí" con **"recibido 4100"** (o solo "recibido" = el total del corte): se anota en `entregas_cobradores` ("Armar Entrega" → "Guardar Entrega") y el bot dice cuánto queda debiendo. Ver `sql/mayor_caja_cobradores.sql` y `sql/mayor_caja_recibido.sql`. Si el pedido viene en varios mensajes del mismo cliente con menos de 3 minutos entre uno y otro (la cuenta en uno y el monto en otro, o billetera + correo + monto), los junta en un solo pedido. En Brasil la llave PIX puede ser el mismo número de la cédula (CPF).

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
    # Los retiros de este mismo grupo de los ultimos 30 minutos (sin el mensaje de ahora): para no publicar DOS veces el mismo
    # codigo cuando el cliente lo manda repetido o corregido (revision diaria del 25/11). executeOnce: "Grupos Destino" sale con
    # una fila por banco y esta consulta se hace UNA sola vez.
    # Desde el 27/11 tambien trae las filas 'otro' (ahi quedan los pedazos de pedido: un monto o un correo suelto) para juntar un
    # pedido mandado en varios mensajes; por eso van primero las mas nuevas (order) y el limite es 60. Y las 'captura' (la foto
    # del pago del cliente): con eso se sabe si un pedido se paga por CUENTA (con un RST reciente, se paga con RST).
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'transacciones_mayor_por_whatsapp'; returnAll = $false; limit = 60; filterType = 'string'
                    filterString = '={{ "grupo_jid=eq." + $("Cuando lo Llama el Bot").first().json.grupo.grupo_jid + "&tipo=in.(rst,rct,mixto,beneficiario,otro,captura)&fecha_mensaje=gte." + new Date(Date.now() - 30 * 60000).toISOString() + "&mensaje_id=neq." + $("Decidir").first().json.mensaje_id + "&order=fecha_mensaje.desc" }}' }
    id = 'c1d2e3f4-0027-4b00-8b00-mayor0000027'; name = 'Retiros Recientes'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(1496,480)
    executeOnce = $true; onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $supaCred
  },
  [ordered]@{
    # ¿Cuantas veces (7 dias) este cliente mando un RST SIN el nombre del banco? (sinBanco:<grupo>, 27/11). Decide si el
    # recordatorio despues del "sí" es "Por favor, siempre colócale el nombre del banco." o "Es obligatorio...".
    # executeOnce: "Retiros Recientes" sale con una fila por mensaje reciente y esta lectura se hace UNA sola vez.
    parameters = @{ operation = 'get'; key = "={{ (`$('Cuando lo Llama el Bot').first().json.grupo.tipo === 'cliente') ? ('sinBanco:' + `$('Cuando lo Llama el Bot').first().json.grupo.grupo_jid) : 'sinBanco:sin-cliente' }}"; keyType = 'string'; propertyName = 'sinBanco'; options = @{} }
    id = 'c1d2e3f4-0028-4b00-8b00-mayor0000028'; name = 'Redis Leer Sin Banco'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1672,480)
    executeOnce = $true; onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $redisCred
  },
  [ordered]@{
    # La hoja de tasas PUBLICADA (la misma que lee la app y el bot del detal; solo lectura, sin credenciales). De ahi salen los
    # precios del mayor para los pedidos a BINANCE y ZELLE (27/11). Si Google no contesta, sigue: la vista previa avisa que no pudo.
    parameters = @{ method = 'GET'; url = $URL_HOJA_TASAS; options = @{ timeout = 10000; response = @{ response = @{ responseFormat = 'text'; outputPropertyName = 'data' } } } }
    id = 'c1d2e3f4-0029-4b00-8b00-mayor0000029'; name = 'Leer Tasas'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1848,480)
    executeOnce = $true; onError = 'continueRegularOutput'; alwaysOutputData = $true
  },
  [ordered]@{
    # ¿Como pasa la operadora los pedidos de ESTE cliente en los grupos de paises? ("NOMBRE / RST" o "NOMBRE / CUENTA", 27/11).
    # Busca las cabeceras de los ultimos 45 dias que tengan la 1ra palabra del nombre del cliente ("Hace Falta Publicar?" la
    # saca); "Decidir Publicacion" se queda solo con las que son de verdad de este cliente.
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'transacciones_mayor_por_whatsapp'; returnAll = $false; limit = 40; filterType = 'string'
                    filterString = '={{ "datos->>cabecera=ilike.*" + ($("Hace Falta Publicar?").first().json.cabecera || "sin-cliente-xyz") + "*&fecha_mensaje=gte." + new Date(Date.now() - 45 * 86400000).toISOString() + "&order=fecha_mensaje.desc" }}' }
    id = 'c1d2e3f4-0030-4b00-8b00-mayor0000030'; name = 'Formas de Pago Vistas'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(2024,480)
    executeOnce = $true; onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $supaCred
  },
  [ordered]@{
    # El saldo del cliente (Parte B, 27/11): la vista saldo_mayor (sql/mayor_saldos.sql) trae el saldo CORRIDO y los movimientos de HOY.
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'saldo_mayor'; returnAll = $false; limit = 1; filterType = 'string'
                    filterString = '={{ "grupo_jid=eq." + $("Cuando lo Llama el Bot").first().json.grupo.grupo_jid }}' }
    id = 'c1d2e3f4-0031-4b00-8b00-mayor0000031'; name = 'Saldo del Cliente'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(2200,480)
    executeOnce = $true; onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $supaCred
  },
  [ordered]@{
    # La caja del cobrador (27/11), vista caja_consulta (sql/mayor_caja_recibido.sql), una sola consulta con una "clave":
    #   "corte hasta aqui" -> 'cobrador:<su numero>': lo que cobro desde su ultimo corte;
    #   "recibido" (citando su corte) -> 'corte:<el mensaje citado>': de quien es ese corte y cuanto debe hoy.
    # Si el mensaje no es ninguna de las dos cosas, busca "nadie" y no trae nada.
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'caja_consulta'; returnAll = $false; limit = 1; filterType = 'string'
                    filterString = '={{ "clave=eq." + (($("Hace Falta Publicar?").first().json.motivo === "corte") ? ("cobrador:" + ($("Decidir").first().json.autor_numero || "nadie")) : ($("Hace Falta Publicar?").first().json.motivo === "recibido") ? ("corte:" + ((($("Decidir").first().json.datos) || {}).cita_id || "nadie")) : "nadie") }}' }
    id = 'c1d2e3f4-0038-4b00-8b00-mayor0000038'; name = 'Corte del Cobrador'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(2376,480)
    executeOnce = $true; onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $supaCred
  },
  [ordered]@{
    # Solo las FOTOS del cliente van a la IA (cuesta plata): lo demas sigue directo a "Decidir Publicacion".
    parameters = [ordered]@{ conditions = [ordered]@{
        options = [ordered]@{ version = 2; typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }
        conditions = @( ,[ordered]@{ id = 'foto-pago-1'; leftValue = '={{ $("Hace Falta Publicar?").first().json.motivo }}'; rightValue = 'foto'; operator = [ordered]@{ operation = 'equals'; type = 'string' } } )
        combinator = 'and' }; options = @{} }
    id = 'c1d2e3f4-0032-4b00-8b00-mayor0000032'; name = '¿Foto de Pago?'; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(2552,480)
  },
  [ordered]@{
    # Baja la foto de Evolution (igual que "Bot JK - Procesar Media" del detal).
    parameters = [ordered]@{ method = 'POST'; url = 'http://evolution-api:8080/chat/getBase64FromMediaMessage/BOT%20JK%20Kelvin'
                    authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true
                    headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'
                    jsonBody = '={{ JSON.stringify({ message: { key: { id: $("Decidir").first().json.mensaje_id } }, convertToMp4: false }) }}'; options = @{ timeout = 30000 } }
    id = 'c1d2e3f4-0033-4b00-8b00-mayor0000033'; name = 'Descargar Foto'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(2728,660)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 2000; alwaysOutputData = $true; credentials = $evoHeaderCred
  },
  [ordered]@{
    parameters = @{ jsCode = $fotoABinarioCode }
    id = 'c1d2e3f4-0034-4b00-8b00-mayor0000034'; name = 'Foto a Binario'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2904,660)
  },
  [ordered]@{
    # GPT-4o-mini lee la foto (el mismo modelo y la misma credencial que el detal). Solo dice que es y, si es un pago, cuanto.
    parameters = [ordered]@{ resource = 'image'; operation = 'analyze'; inputType = 'base64'; binaryPropertyName = 'data'; text = $PROMPT_LEER_PAGO
                    modelId = [ordered]@{ __rl = $true; mode = 'list'; value = 'gpt-4o-mini'; cachedResultName = 'gpt-4o-mini' }; options = @{} }
    id = 'c1d2e3f4-0035-4b00-8b00-mayor0000035'; name = 'Leer Pago'; type = '@n8n/n8n-nodes-langchain.openAi'; typeVersion = 1.8; position = @(3080,660)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 2000; alwaysOutputData = $true
    credentials = @{ openAiApi = @{ id = '44lRGIyEnSk1lMc5'; name = 'cambios jk para n8n' } }
  },
  [ordered]@{
    # Los pagos y pedidos que "Decidir Publicacion" saco de este mensaje (Parte B): uno por fila, para "Guardar Movimientos".
    parameters = @{ jsCode = $armarMovimientosCode }
    id = 'c1d2e3f4-0036-4b00-8b00-mayor0000036'; name = 'Armar Movimientos'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(3432,-60)
  },
  [ordered]@{
    # Se anotan en movimientos_mayor (sql/mayor_saldos.sql). La "clave" es unica: un mismo mensaje no se cuenta dos veces.
    parameters = @{ resource = 'row'; operation = 'create'; tableId = 'movimientos_mayor'; dataToSend = 'autoMapInputData' }
    id = 'c1d2e3f4-0037-4b00-8b00-mayor0000037'; name = 'Guardar Movimientos'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(3608,-60)
    onError = 'continueRegularOutput'; credentials = $supaCred
  },
  [ordered]@{
    # El corte que pidio un cobrador (27/11), para "Guardar Corte".
    parameters = @{ jsCode = $armarCorteCode }
    id = 'c1d2e3f4-0039-4b00-8b00-mayor0000039'; name = 'Armar Corte'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(3432,-240)
  },
  [ordered]@{
    # Se guarda en cortes_cobradores (sql/mayor_caja_cobradores.sql): el proximo corte de ese cobrador cuenta desde aqui.
    parameters = @{ resource = 'row'; operation = 'create'; tableId = 'cortes_cobradores'; dataToSend = 'autoMapInputData' }
    id = 'c1d2e3f4-0040-4b00-8b00-mayor0000040'; name = 'Guardar Corte'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(3608,-240)
    onError = 'continueRegularOutput'; credentials = $supaCred
  },
  [ordered]@{
    # El "recibido" de Kelvin o de la operadora citando el corte de un cobrador (27/11), para "Guardar Entrega".
    parameters = @{ jsCode = $armarEntregaCode }
    id = 'c1d2e3f4-0041-4b00-8b00-mayor0000041'; name = 'Armar Entrega'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(3432,-420)
  },
  [ordered]@{
    # Se guarda en entregas_cobradores: lo que el cobrador ya entrego se le resta de lo que debe (caja_cobradores).
    parameters = @{ resource = 'row'; operation = 'create'; tableId = 'entregas_cobradores'; dataToSend = 'autoMapInputData' }
    id = 'c1d2e3f4-0042-4b00-8b00-mayor0000042'; name = 'Guardar Entrega'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(3608,-420)
    onError = 'continueRegularOutput'; credentials = $supaCred
  },
  [ordered]@{
    parameters = @{ jsCode = $decidirPublicacionCode }
    id = 'c1d2e3f4-0013-4b00-8b00-mayor0000013'; name = 'Decidir Publicacion'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(3256,300)
  },
  [ordered]@{
    # UN nodo para texto y sticker. En modo ensayo el unico destino es el grupo de avisos.
    parameters = @{ method = 'POST'; url = '={{ "http://evolution-api:8080/message/" + ($json.tipo === "sticker" ? "sendSticker" : "sendText") + "/BOT%20JK%20Kelvin" }}'
                    authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true
                    headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'
                    jsonBody = '={{ JSON.stringify($json.tipo === "sticker" ? { number: $json.jid, sticker: $json.sticker } : Object.assign({ number: $json.jid, text: $json.texto }, $json.citar ? { quoted: { key: { id: $json.citar } } } : {})) }}'
                    options = @{} }
    id = 'c1d2e3f4-0014-4b00-8b00-mayor0000014'; name = 'Enviar'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(3432,300)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = $evoHeaderCred
  },
  [ordered]@{
    # Si fallo y llevaba cita (el mensaje citado a veces ya no esta en Evolution), se reintenta SIN cita:
    # una cita que no funcione nunca puede dejar a un cliente sin su respuesta.
    parameters = @{ conditions = @{ boolean = @( @{ value1 = '={{ !!$json.error && !!$("Decidir Publicacion").item.json.citar }}'; value2 = '={{true}}' } ) } }
    id = 'c1d2e3f4-0015-4b00-8b00-mayor0000015'; name = 'Fallo la Cita?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(3608,300)
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = '={{ "http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin" }}'
                    authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true
                    headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'
                    jsonBody = '={{ JSON.stringify({ number: $("Decidir Publicacion").item.json.jid, text: $("Decidir Publicacion").item.json.texto }) }}'
                    options = @{} }
    id = 'c1d2e3f4-0016-4b00-8b00-mayor0000016'; name = 'Reenviar sin Cita'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(3784,480)
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
    id = 'c1d2e3f4-0017-4b00-8b00-mayor0000017'; name = 'Actualizar Fila'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(3960,120)
    onError = 'continueRegularOutput'; credentials = $supaCred
  },
  [ordered]@{
    parameters = @{ jsCode = $armarMapaCode }
    id = 'c1d2e3f4-0018-4b00-8b00-mayor0000018'; name = 'Armar Mapa'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(3960,300)
  },
  [ordered]@{
    # Cada valor trae su propio tiempo de vida (ttl en segundos): la publicacion 7 dias, el permiso de JEP unas horas o minutos.
    parameters = @{ operation = 'set'; key = '={{ $json.clave }}'; value = '={{ $json.valor }}'; keyType = 'string'; expire = $true; ttl = ('={{ $json.ttl || ' + ($HORAS_MAPA_PUBLICACION * 3600) + ' }}') }
    id = 'c1d2e3f4-0019-4b00-8b00-mayor0000019'; name = 'Redis Guardar Publicacion'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(4136,300)
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
                      @{ fieldId = 'cobro_emoji'; fieldValue = '={{ $json.emoji || "" }}' },
                      # quien lo marco cobrado (la caja de cada cobrador, 27/11; columnas de sql/mayor_caja_cobradores.sql). Si se desmarca, se borra.
                      @{ fieldId = 'cobrado_por'; fieldValue = '={{ $json.cobro === "cobrado" ? ($json.por || "") : "" }}' },
                      @{ fieldId = 'cobrado_por_nombre'; fieldValue = '={{ $json.cobro === "cobrado" ? ($json.por_nombre || "") : "" }}' } ) } }
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
    id = 'c1d2e3f4-0024-4b00-8b00-mayor0000024'; name = 'Armar Vigilancia'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(3960,900)
  },
  [ordered]@{
    parameters = @{ resource = 'row'; operation = 'create'; tableId = 'vigilancia_rst_mayor'; dataToSend = 'autoMapInputData'; inputsToIgnore = '' }
    id = 'c1d2e3f4-0025-4b00-8b00-mayor0000025'; name = 'Anotar Vigilancia Bot'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(4136,900)
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
  'Grupos Destino'         = @{ main = @( ,@( @{ node='Retiros Recientes'; type='main'; index=0 } ) ) }
  'Retiros Recientes'      = @{ main = @( ,@( @{ node='Redis Leer Sin Banco'; type='main'; index=0 } ) ) }
  'Redis Leer Sin Banco'   = @{ main = @( ,@( @{ node='Leer Tasas'; type='main'; index=0 } ) ) }
  'Leer Tasas'             = @{ main = @( ,@( @{ node='Formas de Pago Vistas'; type='main'; index=0 } ) ) }
  'Formas de Pago Vistas'  = @{ main = @( ,@( @{ node='Saldo del Cliente'; type='main'; index=0 } ) ) }
  'Saldo del Cliente'      = @{ main = @( ,@( @{ node='Corte del Cobrador'; type='main'; index=0 } ) ) }
  'Corte del Cobrador'     = @{ main = @( ,@( @{ node='¿Foto de Pago?'; type='main'; index=0 } ) ) }
  '¿Foto de Pago?'         = @{ main = (
      @( ,@( @{ node='Descargar Foto'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Decidir Publicacion'; type='main'; index=0 } ) )
    ) }
  'Descargar Foto'         = @{ main = @( ,@( @{ node='Foto a Binario'; type='main'; index=0 } ) ) }
  'Foto a Binario'         = @{ main = @( ,@( @{ node='Leer Pago'; type='main'; index=0 } ) ) }
  'Leer Pago'              = @{ main = @( ,@( @{ node='Decidir Publicacion'; type='main'; index=0 } ) ) }
  'Decidir Publicacion'    = @{ main = @( ,@( @{ node='Enviar'; type='main'; index=0 }, @{ node='Armar Movimientos'; type='main'; index=0 }, @{ node='Armar Corte'; type='main'; index=0 }, @{ node='Armar Entrega'; type='main'; index=0 } ) ) }
  'Armar Movimientos'      = @{ main = @( ,@( @{ node='Guardar Movimientos'; type='main'; index=0 } ) ) }
  'Armar Corte'            = @{ main = @( ,@( @{ node='Guardar Corte'; type='main'; index=0 } ) ) }
  'Armar Entrega'          = @{ main = @( ,@( @{ node='Guardar Entrega'; type='main'; index=0 } ) ) }
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
