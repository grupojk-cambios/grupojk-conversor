
const _strip = s => s ? String(s).replace(/^\d+[\w\.]*\s*/, '') : '';
const _findNode = (nodes, n) => (nodes || []).find(x => x.name === n || _strip(x.name) === _strip(n));
const _getConn = (conns, n) => {
  if (!conns) return null;
  const k = Object.keys(conns).find(x => x === n || _strip(x) === _strip(n));
  return k ? Reflect.get(conns, k) : null;
};
// Prueba de las ALERTAS DE VENCIMIENTO de los RST (protocolo_rst_rct.md, seccion 7) y del cableado de JEP en la mañana.
//
// Lo que se vigila:
//   - cuanto dura el codigo de cada banco y a que hora se avisa (Pichincha/Pacifico 4 h, Guayaquil/Produbanco 24 h,
//     Bolivariano hasta las 9 pm, JEP 15 min) y que un banco sin duracion en el manual NO se vigila;
//   - las reacciones de los cobradores: cualquier emoji = cobrado, la X = no cobrado, quitarla = pendiente;
//   - que un RST pegado a mano en el grupo de su banco queda anotado, y uno que publica el bot tambien;
//   - el workflow de alertas: solo avisa lo que esta pendiente y vencido pronto, solo en horario, solo al grupo del RST,
//     en ENSAYO solo manda vistas previas a avisos, y nunca escribe a un grupo que no este en la tabla;
//   - el workflow de la mañana pide al cobrador de JEP que vaya al cajero y anota los RST de 24 h al pasarlos a su banco.
//
// Todos los datos son INVENTADOS (el repositorio es publico). Correr con:  node test_mayor_alertas.mjs

import { readFileSync } from 'fs';

const leer = f => JSON.parse(readFileSync(f, 'utf8').replace(/^﻿/, ''));
const mayor = leer('workflow_mayor.json'), noche = leer('workflow_mayor_noche.json'), alertas = leer('workflow_mayor_alertas.json');
const nodo = (w, n) => _findNode(w.nodes, n);
const code = (w, n) => nodo(w, n).parameters.jsCode;
const SALTO = String.fromCharCode(10);

let fallos = 0;
const chk = (ok, etiqueta, detalle) => { if (!ok) fallos++; console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(80) + ' ' + (detalle || '')); };
const conHora = (iso, f) => { const real = Date.now; Date.now = () => new Date(iso).getTime(); try { return f(); } finally { Date.now = real; } };

const AVISOS = '120363413942097019@g.us';
const DESTINOS = ['PICHINCHA', 'GUAYAQUIL', 'PRODUBANCO', 'PACIFICO', 'COOP JEP', 'BOLIVARIANO', 'SOLIDARIO', 'AUSTRO', 'INTERNACIONAL', 'COBRAR MAÑANA']
  .map((nombre, i) => ({ grupo_jid: '1203630000000001' + String(10 + i) + '@g.us', nombre, tipo: 'destino', activo: true }));
const ID = nombre => DESTINOS.find(d => d.nombre === nombre).grupo_jid;
const GRUPO_CLIENTE = { grupo_jid: '120363000000000001@g.us', nombre: 'Cliente Prueba PEDIDOS JK', tipo: 'cliente', cliente_whatsapp: '593990000001' };

const ISO = (ec) => new Date(Date.parse(ec + '-05:00')).toISOString();           // "2026-11-24T10:00" (hora de Ecuador) -> ISO UTC
const MS = (ec) => Date.parse(ec + '-05:00');

console.log('=== 1) CUANTO DURA CADA CODIGO Y CUANDO SE AVISA ===');
const comun = code(mayor, 'Vigilar Vencimiento');
const { vigenciaDe, bancoDelGrupo, VIGENCIA, TEXTO_ALERTA } = new Function(comun.slice(comun.indexOf('// ===== COMUN: VIGENCIA'), comun.indexOf('const fila = $')) + '\nreturn { vigenciaDe, bancoDelGrupo, VIGENCIA, TEXTO_ALERTA };')();
{
  const t0 = MS('2026-11-24T10:00');
  const min = ms => Math.round(ms / 60000);
  const caso = (banco, venceMin, alertaMin) => { const v = vigenciaDe(banco, t0); chk(v && min(v.venceMs - t0) === venceMin && min(v.alertaMs - t0) === alertaMin, banco + ': vence a los ' + venceMin + ' min, avisa a los ' + alertaMin, '-> ' + (v ? min(v.venceMs - t0) + ' / ' + min(v.alertaMs - t0) : 'null')); };
  caso('Pichincha', 240, 180); caso('Pacífico', 240, 180); caso('Guayaquil', 1440, 1380); caso('Produbanco', 1440, 1380); caso('JEP', 15, 5);
  let v = vigenciaDe('Bolivariano', t0);
  chk(v && v.venceMs === MS('2026-11-24T21:00') && v.alertaMs === MS('2026-11-24T20:00'), 'Bolivariano llegado a las 10 am: vence a las 9 pm y avisa a las 8 pm', '-> ' + (v && new Date(v.alertaMs - 5 * 3600000).toISOString()));
  v = vigenciaDe('Bolivariano', MS('2026-11-24T20:30'));
  chk(v && v.venceMs === MS('2026-11-24T21:00') && v.alertaMs === MS('2026-11-24T20:40'), 'Bolivariano llegado a las 8:30 pm (ya falta menos de 1 h): avisa 10 minutos despues', '-> ' + (v && new Date(v.alertaMs - 5 * 3600000).toISOString().slice(11, 16)));
  chk(vigenciaDe('Bolivariano', MS('2026-11-24T20:58')).alertaMs < MS('2026-11-24T21:00'), '   ...pero nunca despues de la hora de vencer');
  chk(vigenciaDe('Bolivariano', MS('2026-11-24T21:30')) === null, 'Bolivariano llegado despues de las 9 pm: no hay nada que vigilar');
  for (const b of ['Solidario', 'Austro', 'Internacional', 'Machala', '']) chk(vigenciaDe(b, t0) === null, b + ': el manual no dice cuanto dura: NO se vigila');
  v = vigenciaDe('jep_pedido', t0);
  chk(v && min(v.alertaMs - t0) === 30 && min(v.venceMs - t0) === 360, 'el PEDIDO al cobrador de JEP: si en 30 minutos no contesta, aviso (y se deja de vigilar a las 6 h)', '-> ' + (v ? min(v.alertaMs - t0) + ' / ' + min(v.venceMs - t0) : 'null'));
  chk(vigenciaDe('Pichincha', NaN) === null && vigenciaDe('Pichincha', 0) === null, 'sin hora de llegada valida: no se vigila');
  chk(bancoDelGrupo('PICHINCHA') === 'pichincha' && bancoDelGrupo('COOP JEP') === 'jep' && bancoDelGrupo('Pacífico') === 'pacifico' && bancoDelGrupo('BOLIVARIANO') === 'bolivariano', 'el banco se saca del NOMBRE del grupo');
  chk(bancoDelGrupo('COBRAR MAÑANA') === '' && bancoDelGrupo('SOLIDARIO') === '' && bancoDelGrupo('VENEZUELA') === '', 'COBRAR MAÑANA, SOLIDARIO y los grupos de paises: ninguno (no se vigilan)');
  chk(TEXTO_ALERTA === '⚠️ ¡Pendiente! Este código está por vencerse, le queda poco tiempo. Favor proceder con el retiro en cajero.', 'el texto de la alerta es EXACTAMENTE el del manual');
}

console.log('');
console.log('=== 2) LAS REACCIONES DE LOS COBRADORES (cobrado / no cobrado) ===');
{
  let n = 0;
  const ev = (mensaje, extra) => { n++; const e = extra || {}; return { key: { remoteJid: ID('PICHINCHA'), fromMe: false, id: 'R' + n, participant: '1@lid' }, message: mensaje, contextInfo: e.cita ? { stanzaId: e.cita } : undefined, messageTimestamp: 1795000000 + n }; };
  const cobro = (mensaje, extra, grupo) => { const o = new Function('$input', code(mayor, 'Entender Cobro'))({ first: () => ({ json: { grupo: grupo || DESTINOS[0], data: ev(mensaje, extra) } }) }); return o.length ? o[0].json : null; };
  const reaccion = (emoji, objetivo) => ({ reactionMessage: { key: { id: objetivo || 'MSGRST1', remoteJid: ID('PICHINCHA') }, text: emoji } });
  for (const e of ['✅', '👍', '👍🏻', '💵', '🙏', '❤️', '🤝']) { const c = cobro(reaccion(e)); chk(c && c.cobro === 'cobrado' && c.mensaje_id === 'MSGRST1' && c.grupo_jid === ID('PICHINCHA'), 'reaccion ' + e + ' -> cobrado (se anota sobre el mensaje reaccionado)', '-> ' + JSON.stringify(c)); }
  for (const e of ['❌', '❌️', '✖️', '🚫']) { const c = cobro(reaccion(e)); chk(c && c.cobro === 'no_cobrado', 'reaccion ' + e + ' -> no cobrado', '-> ' + JSON.stringify(c)); }
  let c = cobro(reaccion(''));
  chk(c && c.cobro === 'pendiente' && c.emoji === '', 'quitar la reaccion (texto vacio) -> vuelve a pendiente', '-> ' + JSON.stringify(c));
  chk(cobro({ reactionMessage: { text: '✅' } }) === null, 'una reaccion sin el mensaje al que apunta: se ignora');
  // respuestas que citan el RST (caso C del manual: "toda actualizacion debe ir citando el mensaje original")
  c = cobro({ conversation: '✅' }, { cita: 'MSGRST2' });
  chk(c && c.cobro === 'cobrado' && c.mensaje_id === 'MSGRST2', 'una respuesta con un emoji citando el RST -> cobrado', '-> ' + JSON.stringify(c));
  c = cobro({ extendedTextMessage: { text: '❌', contextInfo: { stanzaId: 'MSGRST3' } } });
  chk(c && c.cobro === 'no_cobrado' && c.mensaje_id === 'MSGRST3', 'una respuesta ❌ citando el RST -> no cobrado', '-> ' + JSON.stringify(c));
  chk((cobro({ conversation: 'Cobrado' }, { cita: 'M4' }) || {}).cobro === 'cobrado' && (cobro({ conversation: 'ya cobré' }, { cita: 'M4' }) || {}).cobro === 'cobrado', '"cobrado" / "ya cobré" citando el RST -> cobrado');
  chk(cobro({ conversation: 'no cobré' }, { cita: 'M4' }) === null, '"no cobré" no es un cobrado');
  chk((cobro({ conversation: 'Verificar datos' }, { cita: 'M5' }) || {}).cobro === 'verificar' && (cobro({ conversation: 'Se dañó' }, { cita: 'M5' }) || {}).cobro === 'danado', '"Verificar" y "se dañó" citando el RST: ya viene uno nuevo (no hay que avisar)');
  chk(cobro({ conversation: '✅' }) === null && cobro({ conversation: 'ok gracias' }, { cita: 'M6' }) === null && cobro({ conversation: 'hola' }) === null, 'un emoji sin citar nada, o texto cualquiera: no se anota');
  // el pedido a JEP: el cobrador que contesta "listo" (citandolo) o reacciona lo deja atendido
  const JEP = DESTINOS.find(d => d.nombre === 'COOP JEP');
  c = cobro({ conversation: 'listo, ya estoy acá' }, { cita: 'PEDIDO1' }, JEP);
  chk(c && c.cobro === 'cobrado' && c.mensaje_id === 'PEDIDO1' && c.grupo_jid === JEP.grupo_jid, 'JEP: "listo, ya estoy acá" citando el pedido -> atendido (ya no se avisa en 30 min)', '-> ' + JSON.stringify(c));
  chk(cobro({ conversation: 'no hay cajero' }, { cita: 'PEDIDO1' }, JEP) === null && cobro({ conversation: 'listo, ya estoy acá' }, { cita: 'PEDIDO1' }) === null, '"no hay cajero" no lo atiende, y el "listo" solo cuenta en el grupo de JEP');
  chk((cobro(reaccion('👍'), {}, JEP) || {}).cobro === 'cobrado', 'una reaccion al pedido tambien lo deja atendido');
  // una X o "pendiente" nunca pisa un "verificar" / "se dañó": sale marcada para que Marcar Cobro no la aplique en ese caso
  chk(cobro(reaccion('❌')).soloPendiente === true && cobro(reaccion('')).soloPendiente === true && cobro(reaccion('✅')).soloPendiente === false && cobro({ conversation: 'Verificar datos' }, { cita: 'M5' }).soloPendiente === false,
      'la X y quitar la reaccion NO pisan un "verificar"/"se dañó" (en cualquier orden que lleguen); un cobrado o un "verificar" si se aplican siempre');
  chk(cobro(reaccion('✅'), {}, GRUPO_CLIENTE) === null, 'una reaccion en un grupo de CLIENTE no se mira');
  chk(cobro({ imageMessage: { caption: '' } }) === null, 'una foto: nada');
}

console.log('');
console.log('=== 3) UN RST PEGADO A MANO EN EL GRUPO DE SU BANCO QUEDA ANOTADO ===');
{
  let n = 0;
  const entenderEn = (grupo, texto, extra) => {
    n++; const e = extra || {};
    const ev = { key: { remoteJid: grupo.grupo_jid, fromMe: false, id: 'V' + n, participant: '1@lid', participantAlt: '593990000077@s.whatsapp.net' }, pushName: 'Operadora', message: { conversation: texto }, messageTimestamp: e.ts || (1795000000 + n) };
    const o = new Function('$input', code(mayor, 'Entender Mensaje'))({ first: () => ({ json: { grupo, data: ev } }) });
    return o.length ? o[0].json : null;
  };
  const vigilar = (grupo, texto, extra) => {
    const e = extra || {};
    const fila = entenderEn(grupo, texto, e);
    if (!fila) return [];
    const ahora = e.ahora || (Date.parse(fila.fecha_mensaje) + 60000);
    const $ = nombre => {
      if (nombre === 'Decidir') return { first: () => ({ json: fila }) };
      if (nombre === 'Cuando lo Llama el Bot') return { first: () => ({ json: { grupo, data: {} } }) };
      if (nombre === 'Guardar en Supabase') return { first: () => ({ json: e.sinGuardar ? {} : { id: 9 } }) };
      throw new Error('nodo inesperado: ' + nombre);
    };
    const real = Date.now; Date.now = () => ahora;
    try { return new Function('$', code(mayor, 'Vigilar Vencimiento'))($).map(i => i.json); } finally { Date.now = real; }
  };
  const PICH = DESTINOS.find(d => d.nombre === 'PICHINCHA'), JEP = DESTINOS.find(d => d.nombre === 'COOP JEP'), SOLI = DESTINOS.find(d => d.nombre === 'SOLIDARIO');
  const RST_PICH = ['Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO);
  let r = vigilar(PICH, RST_PICH);
  chk(r.length === 1 && r[0].banco === 'pichincha' && r[0].grupo_jid === ID('PICHINCHA') && r[0].origen === 'manual' && /^PICHINCHA 200\$/.test(r[0].resumen), 'un RST en el grupo PICHINCHA (sin escribir "Pichincha"): se anota', '-> ' + JSON.stringify(r[0]));
  chk(r.length && Date.parse(r[0].vence_en) - Date.parse(r[0].recibido_en) === 4 * 3600000 && Date.parse(r[0].alerta_en) - Date.parse(r[0].recibido_en) === 3 * 3600000, '   ...vence a las 4 h y avisa a las 3 h', '');
  chk(r.length && !!r[0].mensaje_id && /^V\d+$/.test(r[0].mensaje_id), '   ...con el id del mensaje (a ese se le pone la reaccion y se cita en la alerta)', '');
  const campos = r.length ? Object.keys(r[0]).sort().join(',') : '';
  chk(campos === 'alerta_en,banco,grupo_jid,mensaje_id,origen,recibido_en,resumen,vence_en', 'la fila trae solo columnas que existen en la tabla (si no, Supabase la rechaza)', '-> ' + campos);
  r = vigilar(JEP, ['Banco Bolivariano', 'Monto: 380', 'Código: 068521', 'Celular: 0990000009', 'Cédula: 0900000010'].join(SALTO));
  chk(r.length === 1 && r[0].banco === 'bolivariano', 'en COOP JEP un RST que dice "Bolivariano": manda el banco que dice el mensaje (no el del grupo)', '-> ' + (r[0] && r[0].banco));
  r = vigilar(JEP, ['Jep', 'Monto: $300', 'OTP: 796988', 'CI: 2100000006', 'Clave: 1111'].join(SALTO));
  chk(r.length === 1 && r[0].banco === 'jep' && Date.parse(r[0].vence_en) - Date.parse(r[0].recibido_en) === 15 * 60000 && Date.parse(r[0].alerta_en) - Date.parse(r[0].recibido_en) === 5 * 60000, 'un RST de JEP: vence a los 15 min y avisa a los 5', '');
  chk(vigilar(SOLI, ['Banco: solidario', 'Monto: 100', 'Tlf: 0990000007', 'Cedula: 1700000008', 'Codigo: 874454'].join(SALTO)).length === 0, 'un RST de Solidario (el manual no dice su duracion): no se vigila');
  chk(vigilar(PICH, 'Hola buenas, ya voy al cajero').length === 0 && vigilar(PICH, 'listo cobrado').length === 0, 'un mensaje que no es un RST: nada');
  chk(vigilar(PICH, ['Austro', '*Retira con tarjeta*', 'Monto 500$'].join(SALTO)).length === 0, 'un RCT (retiro con tarjeta): nada');
  chk(vigilar(PICH, RST_PICH, { sinGuardar: true }).length === 0, 'si la fila no se pudo guardar (mensaje repetido): no se anota dos veces');
  chk(vigilar(PICH, RST_PICH, { ahora: Date.parse('2026-11-18T11:06:40Z') + 45 * 60000 }).length === 0, 'un mensaje viejo que se vuelve a entregar (mas de 30 min): no dispara nada');
  chk(vigilar(GRUPO_CLIENTE, RST_PICH.replace('Código', 'Pichincha Código')).length === 0, 'un RST en un grupo de CLIENTE no se vigila (todavia no esta en el banco)');

  // lo que publica el propio bot
  const armarBot = (acc, respuesta) => new Function('$input', '$', code(mayor, 'Armar Vigilancia'))({ all: () => [{ json: respuesta }] }, () => ({ itemMatching: () => ({ json: acc }) })).map(i => i.json);
  const acc = { jid: ID('GUAYAQUIL'), vigila: { banco: 'guayaquil', recibido: ISO('2026-11-24T10:00'), resumen: 'Cliente Prueba · GUAYAQUIL 500$' } };
  r = armarBot(acc, { key: { id: '3EB0BOT1' } });
  chk(r.length === 1 && r[0].mensaje_id === '3EB0BOT1' && r[0].grupo_jid === ID('GUAYAQUIL') && r[0].origen === 'bot' && r[0].alerta_en === ISO('2026-11-25T09:00') && r[0].vence_en === ISO('2026-11-25T10:00'), 'un RST que el bot publica queda anotado con el id del mensaje que salio (24 h, aviso a las 23 h)', '-> ' + JSON.stringify(r[0]));
  chk(armarBot(acc, { error: { message: 'x' } }).length === 0 && armarBot({ jid: 'X' }, { key: { id: 'A' } }).length === 0 && armarBot({ jid: 'X', vigila: { banco: 'solidario', recibido: ISO('2026-11-24T10:00') } }, { key: { id: 'A' } }).length === 0, 'si el envio fallo, si no trae "vigila" (COBRAR MAÑANA, RCT, pedido a JEP) o el banco no se vigila: nada');
}

console.log('');
console.log('=== 4) EL WORKFLOW DE ALERTAS: a quien se le avisa y cuando ===');
{
  const fila = (extra) => Object.assign({ id: 1, banco: 'pichincha', grupo_jid: ID('PICHINCHA'), mensaje_id: 'MSGRST1', resumen: 'PICHINCHA 200$', recibido_en: ISO('2026-11-24T10:00'), vence_en: ISO('2026-11-24T14:00'),
                                          alerta_en: ISO('2026-11-24T13:00'), cobro: 'pendiente', alerta_enviada_en: null, origen: 'manual' }, extra || {});
  const armar = (filas, ahoraEc, opciones) => {
    const o = opciones || {};
    let c = code(alertas, 'Armar Alertas'); if (o.modo === 'real') c = c.replace("const MODO = 'ensayo'", "const MODO = 'real'");
    return conHora(ISO(ahoraEc), () => new Function('$', c)(nombre => {
      if (nombre === 'Leer RST por Vencer') return { all: () => filas.map(json => ({ json })) };
      if (nombre === 'Leer Grupos Destino') return { all: () => (o.destinos || DESTINOS).map(json => ({ json })) };
      throw new Error('nodo inesperado: ' + nombre);
    })).map(i => i.json);
  };
  const MARTES_1PM = '2026-11-24T13:05';
  chk(/const MODO = 'ensayo'/.test(code(alertas, 'Armar Alertas')), 'el workflow de alertas esta en modo ENSAYO', '-> ' + (code(alertas, 'Armar Alertas').match(/const MODO = '(\w+)'/) || [])[1]);

  let x = armar([fila()], MARTES_1PM);
  chk(x.length === 1 && x[0].jid === AVISOS && /^🧪 ENSAYO — la alerta iría a PICHINCHA, citando el RST de las 10:00 \(PICHINCHA 200\$\):\n⚠️ ¡Pendiente!/.test(x[0].texto) && !x[0].citar && x[0].resultado === 'ensayo', 'ENSAYO: la alerta se muestra como vista previa en AVISOS (a ningun banco)', '-> ' + JSON.stringify(x.map(e => e.jid) + ' ' + (x[0] || {}).texto));
  x = armar([fila()], MARTES_1PM, { modo: 'real' });
  chk(x.length === 1 && x[0].jid === ID('PICHINCHA') && x[0].citar === 'MSGRST1' && x[0].texto === TEXTO_ALERTA && x[0].resultado === 'enviada' && x[0].fila_id === 1 && !x[0].sinEnvio, 'REAL: cita el RST en el grupo del banco y dice el texto del manual', '-> ' + JSON.stringify(x[0]));
  chk(/^\(PICHINCHA 200\$\)\n⚠️ ¡Pendiente!/.test(x[0].texto_sin_cita), '   ...y si la cita falla, el aviso sin cita lleva el resumen del RST', '-> ' + JSON.stringify(x[0].texto_sin_cita));
  x = armar([fila({ cobro: 'no_cobrado' })], MARTES_1PM, { modo: 'real' });
  chk(x.length === 1 && x[0].jid === ID('PICHINCHA'), 'un RST marcado con ❌ (no cobrado) tambien se avisa (asi lo dice el manual)');
  chk(armar([fila({ vence_en: ISO('2026-11-24T13:00') })], MARTES_1PM, { modo: 'real' }).every(e => e.sinEnvio && e.resultado === 'vencido' && e.cobro === 'vencido'), 'ya se vencio: no se avisa, se anota "vencido"');
  chk(armar([fila()], '2026-11-24T20:00', { modo: 'real' }).every(e => e.sinEnvio), 'a las 8 pm (cerrado) con el codigo ya vencido: nada que enviar');
  // fuera de horario
  x = armar([fila({ vence_en: ISO('2026-11-25T14:00'), alerta_en: ISO('2026-11-25T08:00') })], '2026-11-25T08:30', { modo: 'real' });
  chk(x.length === 0, 'las 8:30 am (todavia cerrado) y el codigo sigue vivo despues de abrir: espera (no avisa de madrugada)', '-> ' + x.length);
  x = armar([fila({ vence_en: ISO('2026-11-25T08:50'), alerta_en: ISO('2026-11-25T07:50') })], '2026-11-25T08:00', { modo: 'real' });
  chk(x.length === 1 && x[0].sinEnvio && x[0].resultado === 'fuera_de_horario', 'cerrado y el codigo vence ANTES de que abramos: ya no sirve avisar (se anota)', '-> ' + JSON.stringify(x[0]));
  x = armar([fila({ vence_en: ISO('2026-11-25T09:30'), alerta_en: ISO('2026-11-25T08:30') })], '2026-11-25T09:02', { modo: 'real' });
  chk(x.length === 1 && x[0].jid === ID('PICHINCHA'), 'al abrir (9:02) el codigo sigue vivo: SI se avisa');
  x = armar([fila({ vence_en: ISO('2026-11-29T15:00'), alerta_en: ISO('2026-11-29T14:00') })], '2026-11-29T14:30', { modo: 'real' });
  chk(x.length === 1 && x[0].sinEnvio, 'el domingo despues de las 2 pm (cerrado) y el codigo ya vencio... no se avisa', '-> ' + JSON.stringify(x[0]));
  // lista blanca
  x = armar([fila()], MARTES_1PM, { modo: 'real', destinos: [] });
  chk(x.length === 1 && x[0].sinEnvio && x[0].resultado === 'sin_grupo' && !x[0].jid, 'si el grupo NO esta en la tabla: no se le escribe (se anota "sin_grupo")');
  x = armar([fila({ grupo_jid: '999@g.us' })], MARTES_1PM, { modo: 'real' });
  chk(x.length === 1 && x[0].sinEnvio && !x[0].jid, 'un grupo que no es de la tabla jamas recibe una alerta');
  x = armar(Array.from({ length: 40 }, (_, i) => fila({ id: i + 1, mensaje_id: 'M' + i })), MARTES_1PM, { modo: 'real' });
  chk(x.length === 25, 'si hay muchas a la vez: salen 25 por vuelta (el resto en 2 minutos)', '-> ' + x.length);
  chk(armar([], MARTES_1PM).length === 0 && armar([{ error: 'x' }, {}], MARTES_1PM).length === 0, 'sin filas (o si Supabase fallo): nada');
  // el pedido a JEP sin respuesta: el aviso va a AVISOS (a la gente de la oficina), nunca al banco
  const pedido = fila({ banco: 'jep_pedido', grupo_jid: ID('COOP JEP'), mensaje_id: 'PEDIDO1', resumen: 'Cliente Prueba · JEP 300$', recibido_en: ISO('2026-11-24T12:30'), vence_en: ISO('2026-11-24T18:30'), alerta_en: ISO('2026-11-24T13:00') });
  for (const modo of ['ensayo', 'real']) {
    x = armar([pedido], MARTES_1PM, { modo });
    chk(x.length === 1 && x[0].jid === AVISOS && !x[0].citar && /^⚠️ JEP: el cobrador todavía no avisa que llegó al cajero\. Lleva 30 minutos esperando:\nCliente Prueba · JEP 300\$\nRevisa el grupo COOP JEP\.$/.test(x[0].texto) && x[0].resultado === 'enviada', 'pedido de JEP sin respuesta (modo ' + modo + '): aviso a AVISOS con el cliente y el monto', '-> ' + JSON.stringify(x.map(e => e.jid) + ' ' + (x[0] || {}).texto));
  }
  x = armar([pedido], '2026-11-24T20:00');
  chk(x.every(e => e.sinEnvio), 'de noche (cerrado) y el pedido ya vencio: no se avisa');
  // "Hay Algo?" corta la vuelta si no hay nada
  const hay = filas => new Function('$', code(alertas, 'Hay Algo?'))(() => ({ all: () => filas.map(json => ({ json })) }));
  chk(hay([]).length === 0 && hay([{}]).length === 0 && hay([{ error: 'x' }]).length === 0 && hay([fila()]).length === 1, '"Hay Algo?": sin nada pendiente corta la vuelta (no consulta los grupos)');
}

console.log('');
console.log('=== 5) EL CABLEADO DEL WORKFLOW DE ALERTAS ===');
{
  const filtro = nodo(alertas, 'Leer RST por Vencer').parameters.filterString;
  chk(/alerta_enviada_en=is\.null/.test(filtro) && /cobro=in\.\(pendiente,no_cobrado\)/.test(filtro) && /alerta_en=lte\./.test(filtro), 'solo lee lo pendiente, sin aviso enviado y con la hora de alerta ya cumplida', '-> ' + filtro);
  const cron = nodo(alertas, 'Cada 2 Minutos').parameters.rule.interval.map(i => i.expression);
  chk(cron.length === 1 && cron[0] === '0 */2 * * * *', 'corre cada 2 minutos (asi el aviso de JEP llega entre los 5 y los 7 min)', '-> ' + cron);
  const envia = alertas.nodes.filter(n => /httpRequest/.test(n.type)).map(n => n.name).sort();
  chk(JSON.stringify(envia) === JSON.stringify(['Enviar Alerta', 'Reenviar sin Cita']), 'solo dos nodos envian mensajes (el envio y su reintento sin cita)', '-> ' + envia);
  chk(!/@g\.us/.test(JSON.stringify(nodo(alertas, 'Enviar Alerta').parameters) + JSON.stringify(nodo(alertas, 'Reenviar sin Cita').parameters)), 'y su destino sale de "Armar Alertas", sin ids escritos');
  chk(nodo(alertas, 'Enviar Alerta').credentials.httpHeaderAuth.name === 'Evolution apikey Kelvin 0380' && !/apikey/i.test(JSON.stringify(nodo(alertas, 'Enviar Alerta').parameters.headerParameters)), 'la llave de Evolution va en la credencial');
  const marca = nodo(alertas, 'Marcar Alerta').parameters;
  chk(/cobro=in\.\(pendiente,no_cobrado\)/.test(marca.filterString), 'al anotar el resultado no pisa una fila que alguien marco cobrada en ese instante', '-> ' + marca.filterString);
  chk(!/@g\.us/.test(code(alertas, 'Armar Alertas').replace(/\/\/.*$/gm, '').replace("'120363413942097019@g.us'", '')), 'ningun id de grupo escrito en el codigo (solo el de avisos)');
  const tipos = [...new Set(alertas.nodes.map(n => n.type.replace('n8n-nodes-base.', '')))].sort();
  chk(tipos.every(t => ['stickyNote', 'scheduleTrigger', 'code', 'supabase', 'if', 'httpRequest'].includes(t)), 'y ningun otro tipo de nodo', '-> ' + tipos);
  // el mismo horario y las mismas reglas que el resto
  const sacar = js => { const i = js.indexOf('// ===== HORARIO DE ATENCION'); const f = js.indexOf('\n}\n', js.indexOf('function horarioDe')); return js.slice(i, f + 3); };
  const bot = leer('workflow_ia_atencion.json');
  chk(sacar(code(alertas, 'Armar Alertas')) === sacar(code(bot, 'Revisar Operacion')) && sacar(code(alertas, 'Armar Alertas')).length > 500, 'el horario es el MISMO bloque del bot del detal');
  const reglas = js => js.slice(js.indexOf('// ===== COMUN: VIGENCIA'), js.indexOf('\nconst ', js.indexOf('function bancoDelGrupo')));
  chk(reglas(code(alertas, 'Armar Alertas')).length > 900 && reglas(code(alertas, 'Armar Alertas')) === reglas(code(mayor, 'Vigilar Vencimiento')) && reglas(code(mayor, 'Armar Vigilancia')) === reglas(code(mayor, 'Vigilar Vencimiento')) && reglas(code(noche, 'Armar Vigilancia')) === reglas(code(mayor, 'Vigilar Vencimiento')), 'las reglas de duracion son IDENTICAS en los 4 sitios que las usan (un solo origen)');
  // el workflow del mayor: lo nuevo no puede enviar nada
  const mayorEnvia = mayor.nodes.filter(n => /httpRequest/.test(n.type)).map(n => n.name).sort();
  chk(JSON.stringify(mayorEnvia) === JSON.stringify(['Enviar', 'Reenviar sin Cita']), 'en el workflow del mayor los reaccionar/anotar NO envian: solo "Enviar" y "Reenviar sin Cita"', '-> ' + mayorEnvia);
  const cobro = nodo(mayor, 'Marcar Cobro').parameters;
  chk(/grupo_jid=eq\./.test(cobro.filterString) && /mensaje_id=eq\./.test(cobro.filterString) && cobro.fieldsUi.fieldValues.map(f => f.fieldId).join() === 'cobro,cobro_en,cobro_emoji', '"Marcar Cobro" actualiza solo ese mensaje de ese grupo', '-> ' + cobro.filterString);
  chk(/cobro=not\.in\.\(verificar,danado\)/.test(cobro.filterString), '"Marcar Cobro" no deja que una X pise un "verificar"/"se dañó"', '-> ' + cobro.filterString);
  const con = mayor.connections;
  chk(con['Redis Leer Publicacion'].main[0].map(x => _strip(x.node)).join() === 'Redis Leer Temporal' && con['Redis Leer Temporal'].main[0].map(x => _strip(x.node)).join() === 'Grupos Destino' && nodo(mayor, 'Redis Leer Temporal').type === 'n8n-nodes-base.redis', 'la clave temporal de Solidario se lee en la cadena (Redis Leer Publicacion -> Redis Leer Temporal -> Grupos Destino)');
  chk(con['Cuando lo Llama el Bot'].main[0].map(x => _strip(x.node)).sort().join() === 'Entender Cobro,Entender Mensaje' && con['Redis Marcar Visto'].main[0].map(x => _strip(x.node)).sort().join() === 'Hace Falta Publicar?,Vigilar Vencimiento', 'el workflow del mayor tiene las dos ramas nuevas (reacciones y vigilancia) sin tocar las de siempre');
  chk(['Fallo la Cita?', 'Reenviar sin Cita'].every(n => con[n].main.flat().some(x => x.node === 'Armar Vigilancia')), 'lo que el bot publica pasa por "Armar Vigilancia" (con o sin cita)');
}

console.log('');
console.log('=== 6) LA MAÑANA: pide al cobrador de JEP que vaya al cajero y anota los RST de 24 h ===');
{
  const ahoraMs = Date.parse('2026-11-25T14:05:00Z');            // miercoles 9:05 am en Ecuador
  const hace = h => new Date(ahoraMs - h * 3600000).toISOString();
  const armar = filas => { const real = Date.now; Date.now = () => ahoraMs; try { return new Function('$', code(noche, 'Armar Envios').replace("const MODO = 'ensayo'", "const MODO = 'real'"))(nombre => {
    if (nombre === 'Leer Grupos Destino') return { all: () => DESTINOS.map(json => ({ json })) };
    if (nombre === 'Leer RST en Espera') return { all: () => filas.map(json => ({ json })) };
    throw new Error('nodo inesperado: ' + nombre); }).map(i => i.json); } finally { Date.now = real; } };
  const fila = (id, regs, horas, texto) => ({ id, creado: hace(horas), fecha_mensaje: hace(horas), cliente_nombre: 'Cliente Prueba', grupo_jid: GRUPO_CLIENTE.grupo_jid, mensaje_id: 'MSGCLI' + id, estado: 'en_cobrar_manana', texto: texto || '', datos: { registros: regs } });
  const JEP_REG = { tipo: 'rst', banco: 'JEP', monto_usd: 300, datos: { codigos: ['796988'], cedula: '2100000006', clave: '1111' } };
  let x = armar([fila(1, [JEP_REG], 10)]);
  chk(x.length === 1 && x[0].jid === ID('COOP JEP') && /^🏧 Cobrador: ir a un cajero y avisar aquí/.test(x[0].texto) && /Cliente: Cliente Prueba\nMonto: 300\$$/.test(x[0].texto) && !/796988|1111/.test(x[0].texto), 'un RST de JEP que quedo de noche: al abrir se le PIDE al cobrador que vaya al cajero (sin el codigo)', '-> ' + JSON.stringify(x.map(e => e.texto)));
  chk(x[0].mapa.jep === 'solicitud' && x[0].mapa.cliente_jid === GRUPO_CLIENTE.grupo_jid && x[0].mapa.id_msg_cliente === 'MSGCLI1' && x[0].estado_fila === 'jep_esperando' && x[0].vigila && x[0].vigila.banco === 'jep_pedido' && x[0].vigila.recibido === new Date(ahoraMs).toISOString() && /Cliente Prueba · JEP 300\$/.test(x[0].vigila.resumen), 'queda el mapa (para saber de quien es cuando el cobrador diga "listo") y el pedido se vigila: 30 min sin respuesta = aviso');
  x = armar([fila(2, [], 10, 'Buenas noches, quiero hacer un retiro por JEP')]);
  chk(x.length === 1 && x[0].jid === ID('COOP JEP') && !/Monto/.test(x[0].texto), 'un pedido de JEP sin datos ("quiero hacer un retiro por JEP") tambien se pasa', '-> ' + JSON.stringify(x.map(e => e.texto)));
  x = armar([fila(3, [JEP_REG], 40)]);
  chk(x.length === 1 && x[0].jid === AVISOS && x[0].estado_fila === 'vencido' && /JEP/.test(x[0].texto), 'un pedido de JEP de mas de 36 horas: no se pasa, se avisa');
  const GUAYAQUIL = { tipo: 'rst', banco: 'Guayaquil', monto_usd: 500, datos: { codigos: ['2403', '2790'], telefono: '0990000005' } };
  x = armar([fila(4, [GUAYAQUIL, JEP_REG], 12)]);
  chk(x.length === 2 && x.some(e => e.jid === ID('GUAYAQUIL') && /C1: 2403/.test(e.texto)) && x.some(e => e.jid === ID('COOP JEP') && /Cobrador/.test(e.texto)) && x.every(e => e.estado_fila === 'publicado'), 'una fila con Guayaquil y JEP: Guayaquil se pasa con su bloque y JEP con el pedido', '-> ' + x.map(e => e.estado_fila));
  const g = x.find(e => e.jid === ID('GUAYAQUIL'));
  chk(g.vigila && g.vigila.banco === 'guayaquil' && g.vigila.recibido === hace(12) && /GUAYAQUIL 500\$/.test(g.vigila.resumen), 'el RST de Guayaquil que se pasa queda para vigilar, con la hora en que lo mando el cliente', '-> ' + JSON.stringify(g.vigila));
  const vig = new Function('$input', '$', code(noche, 'Armar Vigilancia'))({ all: () => [{ json: { key: { id: '3EB0MAÑ1' } } }, { json: { key: { id: '3EB0MAÑ2' } } }] }, () => ({ itemMatching: i => ({ json: x[i] }) })).map(i => i.json);
  const vg = vig.find(v => v.banco === 'guayaquil'), vp = vig.find(v => v.banco === 'jep_pedido');
  chk(vig.length === 2 && vg && vg.mensaje_id === '3EB0MAÑ1' && vg.grupo_jid === ID('GUAYAQUIL') && vg.recibido_en === hace(12) && vg.alerta_en === new Date(Date.parse(hace(12)) + 23 * 3600000).toISOString(), 'al llegar al grupo se anota con SU reloj: avisa a las 23 h de que el cliente lo mando', '-> ' + JSON.stringify(vig[0]));
  chk(vp && vp.mensaje_id === '3EB0MAÑ2' && vp.grupo_jid === ID('COOP JEP') && vp.alerta_en === new Date(ahoraMs + 30 * 60000).toISOString(), 'y el pedido a JEP se anota con su aviso a los 30 minutos (contados desde que se publica, no desde anoche)', '-> ' + JSON.stringify(vp));
  // un RST de 24 h con el largo mal no se pasa al banco (seccion 9)
  const GUAYAQUIL_MAL = { tipo: 'rst', banco: 'Guayaquil', monto_usd: 500, datos: { codigos: ['24031', '2790'], telefono: '0990000005' } };
  chk(armar([fila(8, [GUAYAQUIL_MAL], 12)]).every(e => e.jid === AVISOS), 'un RST de 24 h con el largo del codigo mal (si por error estaba esperando) no se pasa al banco: solo un aviso');
  chk(!nodo(noche, 'Enviar al Banco') || noche.nodes.filter(n => /httpRequest/.test(n.type)).length === 1, 'en la mañana sigue habiendo un solo nodo que envia');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
