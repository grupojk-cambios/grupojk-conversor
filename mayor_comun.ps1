# ============================================================================
#  MAYOR, FASE 2: lo que comparten los workflows del mayor (se carga con ". .\mayor_comun.ps1").
#
#  - Constantes: modo (ensayo / real), grupo de avisos, base de los stickers y credenciales.
#  - $horarioJs: el MISMO bloque de horario del bot del detal (se lee de build_v12.ps1, asi las horas
#    de atencion viven en un solo sitio).
#  - $publicarJs: reglas de los RST/RCT sacadas de "EJEMPLOS PARA EL BOT/protocolo_rst_rct.md" (campos
#    que pide cada banco, cual vence el mismo dia y cual dura 24 h, y el formato del bloque que se
#    publica en el grupo del banco). Lo usan "Decidir Publicacion" y el workflow que pasa los RST al abrir.
# ============================================================================

# 'ensayo' = NADA sale a bancos ni a clientes: cada caso se muestra como vista previa en el grupo de avisos.
# 'real'   = publica de verdad, pero SOLO en los grupos de clientes con grupos_mayor.publicar = true.
# Se cambia a 'real' solo con el OK de Kelvin, despues de revisar las vistas previas.
$MAYOR_MODO = 'ensayo'

# Lo mismo para las ALERTAS DE VENCIMIENTO (workflow "Mayor: alertas de vencimiento"), que se enciende aparte:
# 'ensayo' = la alerta que tocaria se muestra como vista previa en el grupo de avisos; 'real' = el bot cita el
# RST en el grupo del banco y avisa al cobrador. Tambien solo con el OK de Kelvin.
$ALERTAS_MODO = 'ensayo'

$GRUPO_AVISOS = '120363413942097019@g.us'      # grupo "Notificaciones Clientes" (el mismo de build_v12.ps1)
$STICKER_BASE = 'https://grupojk-cambios.github.io/grupojk-conversor/logos/'
$evoHeaderCred = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }

# ---------- horario: se lee de build_v12.ps1 ----------
$v12 = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'build_v12.ps1'), [System.Text.Encoding]::UTF8)
function Get-ConstV12($nombre) {
  $m = [regex]::Match($v12, '(?m)^\$' + $nombre + '\s*=\s*(\d+)')
  if (-not $m.Success) { throw ('No encontre $' + $nombre + ' en build_v12.ps1') }
  return $m.Groups[1].Value
}
$mh = [regex]::Match($v12, '(?s)\$horarioJs = @''\r?\n(.*?)\r?\n''@')
if (-not $mh.Success) { throw 'No encontre $horarioJs en build_v12.ps1' }
$horarioJs = $mh.Groups[1].Value
$horarioJs = $horarioJs.Replace('__ABRE_SEMANA__', (Get-ConstV12 'HORA_ABRE_SEMANA')).Replace('__CIERRA_SEMANA__', (Get-ConstV12 'HORA_CIERRA_SEMANA'))
$horarioJs = $horarioJs.Replace('__ABRE_DOMINGO__', (Get-ConstV12 'HORA_ABRE_DOMINGO')).Replace('__CIERRA_DOMINGO__', (Get-ConstV12 'HORA_CIERRA_DOMINGO'))

# ---------- reglas de los RST / RCT (protocolo_rst_rct.md) ----------
$publicarJs = @'
// ===== COMUN: REGLAS DE LOS RST / RCT (protocolo_rst_rct.md) =====
const quitar = s => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();

// Que grupo recibe a cada banco (por el NOMBRE del grupo en la tabla grupos_mayor, nunca por su id).
const GRUPO_DEL_BANCO = { pichincha: 'pichincha', guayaquil: 'guayaquil', produbanco: 'produbanco', pacifico: 'pacifico',
                          jep: 'coop jep', bolivariano: 'bolivariano', solidario: 'solidario', austro: 'austro', internacional: 'internacional' };
const GRUPO_COBRAR_MANANA = 'cobrar manana';
const NOMBRE_GRUPO = k => (k === GRUPO_COBRAR_MANANA ? 'COBRAR MAÑANA' : String(k).toUpperCase());
// Los codigos de Guayaquil y Produbanco duran 24 horas; los de los demas bancos se vencen el MISMO dia
// (24/11, Kelvin): de noche esos llevan el aviso de cobrar hoy y se quedan en COBRAR MAÑANA.
const DURA_24H = ['guayaquil', 'produbanco'];
const AVISO_COBRAR_HOY = '⚠️ COBRAR HOY para que no se venza';

// Campos que pide cada banco (protocolo, seccion 5). 'c1' y 'c2' son los dos codigos de Guayaquil.
const REQUISITOS = {
  produbanco:  ['cedula', 'codigo', 'monto'],
  pacifico:    ['cedula', 'codigo', 'telefono', 'monto'],
  pichincha:   ['telefono', 'codigo', 'monto'],
  guayaquil:   ['telefono', 'c1', 'c2', 'monto'],
  jep:         ['cedula', 'codigo', 'monto', 'clave'],
  solidario:   ['cedula', 'telefono', 'codigo', 'monto'],
  bolivariano: ['cedula', 'telefono', 'codigo', 'monto']
};
const REQUISITOS_OTROS = ['codigo', 'monto'];      // un banco sin protocolo: lo minimo

const claveBanco = reg => quitar(reg && reg.banco);
// Que le falta a un registro (lista de frases para decirle al cliente). RCT: solo banco y monto.
function faltan(reg){
  const d = (reg && reg.datos) || {};
  const f = [];
  if (reg.tipo === 'rct'){ if (reg.monto_usd === null || reg.monto_usd === undefined) f.push('el monto'); return f; }
  const k = claveBanco(reg);
  const req = REQUISITOS[k] || REQUISITOS_OTROS;
  const cods = Array.isArray(d.codigos) ? d.codigos : [];
  for (const r of req){
    if (r === 'monto' && (reg.monto_usd === null || reg.monto_usd === undefined)) f.push('el monto');
    else if (r === 'codigo' && cods.length < 1) f.push('el código');
    else if (r === 'c1' && cods.length < 1) f.push('el código 1');
    else if (r === 'c2' && cods.length < 2) f.push('el código 2');
    else if (r === 'cedula' && !d.cedula) f.push('la cédula');
    else if (r === 'telefono' && !d.telefono) f.push('el teléfono');
    else if (r === 'clave' && !d.clave) f.push('la clave de la tarjeta');
  }
  // Mas numeros de codigo que los que pide el banco: no se adivina cual es el bueno.
  const maxCods = (k === 'guayaquil') ? 2 : 1;
  if (cods.length > maxCods) f.push('cuál es el código (me llegaron varios números)');
  return f;
}
const unir = l => (l.length <= 1 ? (l[0] || '') : l.slice(0, -1).join(', ') + ' y ' + l[l.length - 1]);

// Largo EXACTO de los codigos (protocolo, seccion 9). Solo se revisa lo que el cliente SI mando (lo que falta lo dice faltan()).
// Pichincha 4 | Produbanco 6 | Guayaquil dos codigos de 4 | Pacifico 6 | Solidario 6 | Bolivariano 6 u 8 | JEP codigo 6 + clave de la tarjeta 4.
// Un banco que no esta aqui (Austro, Internacional...) no se revisa: no hay regla.
const LARGOS = { pichincha: { codigo: [4] }, produbanco: { codigo: [6] }, guayaquil: { codigo: [4], codigo2: [4] }, pacifico: { codigo: [6] },
                 solidario: { codigo: [6] }, bolivariano: { codigo: [6, 8] }, jep: { codigo: [6], clave: [4] } };
function revisar(reg){
  if (!reg || reg.tipo === 'rct') return [];
  const k = claveBanco(reg), L = LARGOS[k];
  if (!L) return [];
  const d = reg.datos || {}, cods = Array.isArray(d.codigos) ? d.codigos : [];
  const malo = (v, ok) => ok.indexOf(String(v).replace(/\D/g, '').length) === -1;
  const dig = ok => ok.join(' u ') + ' dígitos';
  const r = [];
  if (k === 'guayaquil'){
    if (cods[0] && malo(cods[0], L.codigo)) r.push('el código 1 debe tener ' + dig(L.codigo));
    if (cods[1] && malo(cods[1], L.codigo2)) r.push('el código 2 debe tener ' + dig(L.codigo2));
  } else if (cods[0] && malo(cods[0], L.codigo)) r.push('el código debe tener ' + dig(L.codigo));
  if (L.clave && d.clave && malo(d.clave, L.clave)) r.push('la clave de la tarjeta debe tener ' + dig(L.clave));
  return r;
}

// ===== SOLIDARIO: la clave TEMPORAL en vivo (protocolo, seccion 9) =====
// El cobrador, frente al cajero, cita nuestro RST en el grupo de Solidario y escribe "temporal" / "segundo codigo": el banco le acaba
// de mandar una clave temporal al cliente por SMS. El bot se la pide al cliente, le dice "Ok, recibido" y se la entrega al grupo.
const RX_TEMPORAL = /temporal|segundo cod|2do cod|segunda clave|2da clave/;
const pideTemporal = t => RX_TEMPORAL.test(quitar(t));
const TEXTO_TEMP_CLIENTE = 'Por favor envíame de inmediato el código temporal que te acaba de llegar.';
const TEXTO_TEMP_GRUPO = 'ok, se lo pido al cliente';
const TEXTO_TEMP_RECIBIDO = 'Ok, recibido';
// La clave temporal: UN numero de 6 digitos suelto en el mensaje ("...clave temporal para retiro de efectivo es 919180, ...hasta 17:12").
const codigoTemporalDe = texto => { const m = [...new Set(String(texto || '').match(/(?<!\d)\d{6}(?!\d)/g) || [])]; return m.length === 1 ? m[0] : ''; };

const fmtMonto = n => { const x = Math.round(Number(n) * 100) / 100; return (x % 1 === 0) ? String(x) : x.toFixed(2); };
const ocultar = v => String(v).replace(/\d(?=\d{2})/g, '•');      // en las vistas previas solo se ven los 2 ultimos digitos

// El bloque que se publica en el grupo del banco (protocolo, seccion 2):
//   (Nombre / BANCO / Monto / Codigo / Cedula / Telefono)
function bloque(nombre, reg, ocultarDatos){
  const d = reg.datos || {}, k = claveBanco(reg);
  const m = v => (ocultarDatos ? ocultar(v) : String(v));
  const L = ['(' + nombre, String(reg.banco || '').toUpperCase()];
  if (reg.tipo === 'rct'){
    L.push('Retira con tarjeta');
    L.push('Monto: ' + fmtMonto(reg.monto_usd) + '$');
  } else {
    L.push('Monto: ' + fmtMonto(reg.monto_usd) + '$');
    const cods = Array.isArray(d.codigos) ? d.codigos : [];
    if (k === 'guayaquil'){ if (cods[0]) L.push('C1: ' + m(cods[0])); if (cods[1]) L.push('C2: ' + m(cods[1])); }
    else if (cods[0]) L.push('Código: ' + m(cods[0]));
    if (d.clave) L.push('Clave: ' + m(d.clave));
    if (d.cedula) L.push('Cedula: ' + m(d.cedula));
    if (d.telefono) L.push('Teléfono: ' + m(d.telefono));
    if (d.hora) L.push('Hora: ' + d.hora);
  }
  L[L.length - 1] += ')';
  return L.join('\n');
}

// ===== JEP: el codigo dura 15 minutos, asi que NO se genera hasta que el cobrador este en el cajero =====
// (24/11, Kelvin) El cliente que quiere hacer un RST de JEP recibe "te avisamos al estar en el cajero"; el bot le pide al
// cobrador (en el grupo de JEP) que vaya a un cajero y avise citando el mensaje; cuando el cobrador escribe "listo, ya
// estoy aca", el bot le dice al cliente que haga el RST ahora. Solo con ese permiso se publica el codigo.
const TEXTO_JEP_CLIENTE = 'Te avisamos cuando el cobrador esté en el cajero, para que realices el RST.';
const TEXTO_JEP_REPETIDO = 'Ya avisamos al cobrador. Te escribimos apenas esté en el cajero.';
const TEXTO_JEP_LISTO_CLIENTE = 'El cobrador ya está en el cajero. Realiza tu RST ahora y envíame todos los datos en un solo texto.';
const TEXTO_JEP_LISTO_GRUPO = 'ok, ya le aviso al cliente';
const jepSolicitud = (nombre, montos) => '🏧 Cobrador: ir a un cajero y avisar aquí, citando este mensaje, cuando estés para indicarle al cliente que haga el RST.\n\nCliente: ' + nombre
  + (montos.length ? '\n' + (montos.length === 1 ? 'Monto: ' : 'Montos: ') + montos.map(m => fmtMonto(m) + '$').join(', ') : '');
// El cobrador avisa que ya llego (citando el mensaje del bot): "listo", "ya estoy aca", "llegue", "pide rst"...
const RX_COBRADOR_LISTO = /list[oa]s?\b|llegu|\bya\b|\baqui\b|\baca\b|estoy|\bpid[ae]n?\b|genera|adelante|puede[ns]?\b/;
const RX_NEGACION = /\bno\b|\bsin\b|\bnunca\b|\btodavia\b|\baun\b/;
const cobradorListo = t => { t = quitar(t); return RX_COBRADOR_LISTO.test(t) && !RX_NEGACION.test(t); };
// ¿El cliente QUIERE hacer un RST de JEP aunque todavia no mande datos? ("quiero hacer un retiro por JEP"). Una charla o una
// pregunta suelta ("¿que tanto demora el rst de JEP?") no es un pedido.
function quiereJep(texto){
  const t = quitar(texto);
  if (!/\bjep\b/.test(t) || !/\b(rst|retiro|retirar|retira|codigo|cobrar|sacar)\b/.test(t)) return false;
  const quiero = /\b(quiero|quisiera|quisieramos|voy a|vamos a|necesito|necesitamos|deseo|solicito|me gustaria)\b/.test(t);
  const pregunta = /\b(puedo|podemos|podria|podriamos|se puede)\b/.test(t);
  return quiero || pregunta;
}
'@

# ---------- vigencia de los RST y alertas de vencimiento (protocolo_rst_rct.md, seccion 7) ----------
# Se usa en tres sitios: al anotar un RST para vigilarlo, al pasar los RST de COBRAR MAÑANA a su banco y en el
# workflow que dispara las alertas. Un banco que no esta aqui (Solidario, Austro, Internacional...) NO se vigila,
# porque la tabla del manual no dice cuanto dura su codigo.
$vigenciaJs = @'
// ===== COMUN: VIGENCIA DE LOS RST Y ALERTAS (protocolo_rst_rct.md, seccion 7) =====
// horas / minutos = lo que dura el codigo desde que el cliente lo envia; avisoAntesMin = cuanto antes de vencer se avisa.
// Bolivariano vence a las 9:00 pm del MISMO dia (hora de Ecuador). JEP dura 15 minutos y se avisa a los 5 (el workflow corre cada 2 minutos: llega entre los 5 y los 7).
const VIGENCIA = {
  pichincha:   { horas: 4,  avisoAntesMin: 60 },
  pacifico:    { horas: 4,  avisoAntesMin: 60 },
  guayaquil:   { horas: 24, avisoAntesMin: 60 },
  produbanco:  { horas: 24, avisoAntesMin: 60 },
  bolivariano: { hastaHora: 21, avisoAntesMin: 60 },
  jep:         { minutos: 15, avisoDespuesMin: 5 },
  // El PEDIDO al cobrador de JEP ("ir a un cajero y avisar"): si en 30 minutos no contesta, se avisa en el grupo de avisos.
  // No es un RST: "Entender Cobro" lo da por atendido cuando el cobrador escribe "listo" o reacciona a ese mensaje.
  jep_pedido:  { minutos: 360, avisoDespuesMin: 30 }
};
const TEXTO_ALERTA = '⚠️ ¡Pendiente! Este código está por vencerse, le queda poco tiempo. Favor proceder con el retiro en cajero.';
// { venceMs, alertaMs } de un RST recibido en recibidoMs, o null si ese banco no se vigila.
function vigenciaDe(banco, recibidoMs){
  const k = String(banco || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();
  const v = VIGENCIA[k];
  if (!v || !(recibidoMs > 0)) return null;
  const MIN = 60000;
  if (v.minutos){
    const venceMs = recibidoMs + v.minutos * MIN;
    return { venceMs, alertaMs: recibidoMs + v.avisoDespuesMin * MIN };
  }
  let venceMs;
  if (v.hastaHora){
    const ec = new Date(recibidoMs - 5 * 3600000);                                  // hora de Ecuador
    const medianoche = recibidoMs - (((ec.getUTCHours() * 60 + ec.getUTCMinutes()) * 60 + ec.getUTCSeconds()) * 1000 + ec.getUTCMilliseconds());
    venceMs = medianoche + v.hastaHora * 3600000;
    if (venceMs <= recibidoMs) return null;                                         // llego despues de las 9 pm: no hay nada que vigilar
  } else venceMs = recibidoMs + v.horas * 3600000;
  let alertaMs = venceMs - v.avisoAntesMin * MIN;
  // Si el codigo llego cuando ya faltaba menos de una hora, se avisa 10 minutos despues (nunca pasada la hora de vencer).
  if (alertaMs < recibidoMs + 10 * MIN) alertaMs = Math.min(recibidoMs + 10 * MIN, venceMs - 5 * MIN);
  return { venceMs, alertaMs };
}
// Que banco vigila un grupo de destino (por el NOMBRE del grupo en la tabla, nunca por su id).
function bancoDelGrupo(nombreGrupo){
  const g = String(nombreGrupo || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
  const hallado = Object.keys(VIGENCIA).find(k => (k === 'jep' ? g === 'coop jep' || g === 'jep' : g === k));
  return hallado || '';
}
'@

# ---------- anotar para vigilar un RST que se acaba de publicar en el grupo de su banco ----------
# Lo usan "Mayor: escuchar y registrar" (nodo 'Decidir Publicacion') y "Mayor: pasar RST al abrir" (nodo 'Armar Envios'):
# cambia solo el nombre del nodo que armo el envio. Un envio sin "vigila" (COBRAR MAÑANA, RCT, pedidos a JEP) no se anota.
$armarVigilanciaPlantilla = @'
// Despues de publicar el RST en el grupo de su banco: se anota con su hora de vencimiento para vigilarlo
// (alerta de vencimiento, protocolo seccion 7). Un envio sin "vigila" no se anota.
__VIGENCIA_COMUN__
const out = [];
const entradas = $input.all();
for (let i = 0; i < entradas.length; i++){
  let acc = null;
  try { acc = $('__NODO_ENVIOS__').itemMatching(i).json; } catch(e){ continue; }
  const r = entradas[i].json || {};
  const id = (r.key && r.key.id) || (r.data && r.data.key && r.data.key.id) || '';
  if (!acc || !acc.vigila || !id || r.error) continue;
  const recibido = Date.parse(acc.vigila.recibido);
  const v = vigenciaDe(acc.vigila.banco, recibido);
  if (!v) continue;
  const iso = ms => new Date(ms).toISOString();
  out.push({ json: { banco: String(acc.vigila.banco).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim(), grupo_jid: acc.jid, mensaje_id: id, resumen: acc.vigila.resumen || '',
                     recibido_en: iso(recibido), vence_en: iso(v.venceMs), alerta_en: iso(v.alertaMs), origen: 'bot' } });
}
return out;
'@
function Get-ArmarVigilanciaCode($nodoEnvios) {
  return $armarVigilanciaPlantilla.Replace('__VIGENCIA_COMUN__', $vigenciaJs).Replace('__NODO_ENVIOS__', $nodoEnvios)
}
