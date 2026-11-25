
const _strip = s => s ? String(s).replace(/^\d+[\w\.]*\s*/, '') : '';
const _findNode = (nodes, n) => (nodes || []).find(x => x.name === n || _strip(x.name) === _strip(n));
const _getConn = (conns, n) => {
  if (!conns) return null;
  const k = Object.keys(conns).find(x => x === n || _strip(x) === _strip(n));
  return k ? Reflect.get(conns, k) : null;
};
// Prueba de la Entrega 3: el bot fuera de horario.
//
// Horario (hora de Ecuador): lunes a sabado 9:00 a 18:00, domingo 10:00 a 14:00.
// Fuera de horario el bot atiende igual, pero:
//   - una operacion completa (captura + cuenta) NO se pasa a transferir: queda 'en_espera' en
//     Supabase (una fila por cuenta) y al cliente se le dice "Recibido ✅ Se procesa mañana..."
//   - no se manda el sticker de "verificando su deposito" ni el de "pedido aprobado"
//   - lo pendiente (captura sin cuenta, o cuenta sin captura) vale hasta 2 h despues de abrir
//
// Todos los datos de esta prueba son INVENTADOS: el repositorio es publico.
//
// Correr con:  node test_horario.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const wfIa = JSON.parse(readFileSync('workflow_ia_atencion.json', 'utf8').replace(/^﻿/, ''));
const wfDeb = JSON.parse(readFileSync('workflow_debounce_admin.json', 'utf8').replace(/^﻿/, ''));
const nodo = n => _findNode(wf.nodes, n) || _findNode(wfIa.nodes, n) || _findNode(wfDeb.nodes, n);
const code = n => nodo(n).parameters.jsCode;
const SALTO = String.fromCharCode(10);

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(72) + ' ' + (detalle || ''));
};
// Hora de Ecuador -> milisegundos reales (UTC-5)
const ec = (fecha, hora) => Date.parse(fecha + 'T' + hora + ':00-05:00');

const NUESTRAS = [{ Pais: 'Ecuador', Metodo: 'Pichincha', Datos: '*CUENTA AUTORIZADA USD*\n\n1) 2200000001\n*Pichincha ahorro*\nC.I: 0900000001\n*Titular Empresa*' }];
let reloj = 0;
function revisar(textos, op) {
  const mensajes = textos.map((t, i) => ({ id: 'M' + i, texto: t }));
  const real = Date.now; Date.now = () => reloj;
  try {
    const $ = (n) => {
      if (n === 'Code in JavaScript' || _strip(n) === 'Code in JavaScript') return { first: () => ({ json: { cuentas: NUESTRAS, modo: 'detal', nombreCliente: '' } }) };
      if (n === 'Cuando lo Llama el Bot' || _strip(n) === 'Cuando lo Llama el Bot') return { first: () => ({ json: { mensajes } }) };
      if (n === 'Combinar' || _strip(n) === 'Combinar') return { first: () => ({ json: { mensajes } }) };
      if (n === 'Redis Leer Operacion' || _strip(n) === 'Redis Leer Operacion') return { first: () => ({ json: { operacion: op ? JSON.stringify(op) : null } }) };
      if (n === 'Redis Leer Pregunta' || _strip(n) === 'Redis Leer Pregunta') return { first: () => ({ json: { pregunta: '0' } }) };
      if (n === 'Consultar Operaciones WhatsApp' || _strip(n) === 'Consultar Operaciones WhatsApp') return { all: () => [{ json: {} }] };
      throw new Error('nodo inesperado: ' + n);
    };
    const r = new Function('$', code('Revisar Operacion'))($)[0].json;
    r.op = JSON.parse(r.operacionNueva);
    return r;
  } finally { Date.now = real; }
}
const captura = (monto, ref) => '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: $' + monto
  + ', Banco: Pichincha, Fecha: nov 21, 2026, Numero de transaccion: ' + ref + ']';
const CUENTA = ['Banco Ejemplo', '01020000000000099999', 'Pedro Prueba', 'V 11111111', '$60'].join(SALTO);
const CUENTA2 = ['Banco Otro', '01020000000000055555', 'Rosa Prueba', 'V 22222222', '$40'].join(SALTO);

console.log('=== 1) Abierto o cerrado, y cuando abre ===');
// 2026-11-20 es viernes, 11-21 sabado, 11-22 domingo, 11-23 lunes.
for (const [fecha, hora, abierto, cuando] of [
  ['2026-11-20', '08:59', false, 'hoy a partir de las 9:00 am'],
  ['2026-11-20', '09:00', true, 'mañana a partir de las 9:00 am'],
  ['2026-11-20', '17:59', true, 'mañana a partir de las 9:00 am'],
  ['2026-11-20', '18:00', false, 'mañana a partir de las 9:00 am'],
  ['2026-11-20', '23:30', false, 'mañana a partir de las 9:00 am'],
  ['2026-11-21', '02:00', false, 'hoy a partir de las 9:00 am'],
  ['2026-11-21', '19:00', false, 'mañana domingo a partir de las 10:00 am'],
  ['2026-11-22', '09:30', false, 'hoy domingo a partir de las 10:00 am'],
  ['2026-11-22', '10:00', true, 'mañana lunes a partir de las 9:00 am'],
  ['2026-11-22', '13:59', true, 'mañana lunes a partir de las 9:00 am'],
  ['2026-11-22', '14:00', false, 'mañana lunes a partir de las 9:00 am'],
  ['2026-11-23', '01:00', false, 'hoy a partir de las 9:00 am']]) {
  reloj = ec(fecha, hora);
  const r = revisar(['hola']);
  chk(r.abierto === abierto && r.cuandoAbre === cuando, fecha + ' ' + hora + ' -> ' + (abierto ? 'ABIERTO' : 'cerrado'), '-> ' + r.abierto + ', ' + r.cuandoAbre);
}

console.log('');
console.log('=== 2) Captura + cuenta de noche: "Recibido", en espera, NO se publica ===');
{
  reloj = ec('2026-11-20', '22:15');
  const r = revisar([captura('60.00', '44440001'), CUENTA]);
  chk(r.estadoOperacion === 'completo' && r.enEspera === true, 'completa y EN ESPERA', '-> ' + r.estadoOperacion + ' / ' + r.enEspera);
  chk(/Recibido ✅ Se procesa mañana a partir de las 9:00 am/.test(r.notaIA), 'le dice "Recibido ✅ Se procesa mañana a partir de las 9:00 am"', '-> ' + r.notaIA.slice(0, 160));
  chk(!/enseguida/.test(r.notaIA), 'NO le dice "procesamos tu remesa enseguida"');
  chk(r.op.hechos.length === 1, 'recuerda el deposito (si la reenvia, sale repetida)');

  const $ = n => {
    if (n === 'Revisar Operacion' || _strip(n) === 'Revisar Operacion') return { first: () => ({ json: r }) };
    if (n === 'Cuando lo Llama el Bot' || _strip(n) === 'Cuando lo Llama el Bot') return { first: () => ({ json: { mensajeCombinado: '', mensajes: [], body: { data: { key: { remoteJid: '593990000001@s.whatsapp.net' }, pushName: 'Ana' } }, nombreCargado: 'Ana Prueba' } }) };
    if (n === 'Combinar' || _strip(n) === 'Combinar') return { item: { json: { mensajeCombinado: '', mensajes: [] } } };
    if (n === 'Webhook Evolution API' || _strip(n) === 'Webhook Evolution API') return { first: () => ({ json: { body: { data: { key: { remoteJid: '593990000001@s.whatsapp.net' }, pushName: 'Ana' } } } }) };
    if (n === 'Solo Estos Numeros' || _strip(n) === 'Solo Estos Numeros') return { first: () => ({ json: { nombreCargado: 'Ana Prueba' } }) };
    return { item: { json: {} }, first: () => ({ json: {} }) };
  };
  const ap = new Function('$', code('Detectar Aprobación'))($);
  chk(ap.length === 0, 'Detectar Aprobacion NO la aprueba (no va a transferir ni sticker de aprobado)', '-> ' + ap.length);

  const filas = new Function('$', code('Armar Filas Noche'))($).map(i => i.json);
  chk(filas.length === 1 && filas[0].estado === 'en_espera', 'Armar Filas Noche: una fila en_espera', '-> ' + filas.length + ' ' + (filas[0] || {}).estado);
  chk(filas[0].fuera_de_horario === true && filas[0].publicado_en === null && filas[0].id_msgs_grupo.length === 0, 'fuera de horario, sin publicar');
  chk(filas[0].whatsapp === '593990000001' && filas[0].nombre_cliente === 'Ana Prueba' && filas[0].id_msg_captura === 'M0', 'con el cliente y la captura (para publicarla al abrir)');
  chk(filas[0].cuentas[0].texto === CUENTA && filas[0].cuentas[0].monto === 60 && filas[0].cuentas[0].id === 'M1', 'la cuenta con su monto y su mensaje', '-> ' + JSON.stringify(filas[0].cuentas[0].monto));

  const r2 = revisar([captura('100.00', '44440002'), CUENTA + SALTO + SALTO + CUENTA2]);
  const $2 = n => (n === 'Revisar Operacion' || _strip(n) === 'Revisar Operacion') ? { first: () => ({ json: r2 }) } : $(n);
  const f2 = new Function('$', code('Armar Filas Noche'))($2).map(i => i.json);
  chk(f2.length === 2 && f2[1].cuentas[0].monto === 40 && f2[1].notas === 'Cuenta 2 de 2 del mismo deposito', 'dos cuentas en un mensaje: dos filas en espera', '-> ' + f2.length);
}

console.log('');
console.log('=== 3) De dia sigue como siempre ===');
{
  reloj = ec('2026-11-20', '15:00');
  const r = revisar([captura('60.00', '44440003'), CUENTA]);
  chk(r.estadoOperacion === 'completo' && r.enEspera === false && /enseguida/.test(r.notaIA), 'completa, NO en espera, "procesamos enseguida"');
  const $ = n => n === 'Revisar Operacion' ? { first: () => ({ json: r }) } : { first: () => ({ json: {} }), item: { json: {} } };
  chk(new Function('$', code('Armar Filas Noche'))($).length === 0, 'Armar Filas Noche no hace nada de dia');
  chk(r.horarioTexto === '', 'el agente no recibe la nota de cerrado');
}

console.log('');
console.log('=== 4) Lo pendiente de noche vale hasta 2 h despues de abrir ===');
{
  reloj = ec('2026-11-20', '23:00');
  const r1 = revisar([captura('60.00', '44440004')]);
  chk(r1.estadoOperacion === 'falta_cuenta', '11 pm: llega la captura sola');
  reloj = ec('2026-11-21', '10:30');
  const r2 = revisar([CUENTA], r1.op);
  chk(r2.estadoOperacion === 'completo' && r2.enEspera === false, '10:30 am del dia siguiente llega la cuenta: COMPLETO y se publica', '-> ' + r2.estadoOperacion);
  reloj = ec('2026-11-21', '11:30');
  const r3 = revisar([CUENTA], r1.op);
  chk(r3.estadoOperacion === 'falta_captura', '11:30 am (mas de 2 h despues de abrir): la captura ya no vale', '-> ' + r3.estadoOperacion);

  reloj = ec('2026-11-20', '15:00');
  const d1 = revisar([captura('60.00', '44440005')]);
  reloj = ec('2026-11-20', '17:30');
  chk(revisar([CUENTA], d1.op).estadoOperacion === 'falta_captura', 'de dia sigue valiendo 2 h (a las 2:30 h ya no)');
}

console.log('');
console.log('=== 5) Lo que el agente sabe cuando esta cerrado ===');
{
  reloj = ec('2026-11-21', '20:00');
  const r = revisar(['cuanto esta la tasa a colombia']);
  chk(/CERRADOS/.test(r.horarioTexto) && /mañana domingo a partir de las 10:00 am/.test(r.horarioTexto), 'sabado de noche: cerrados, abrimos el domingo a las 10', '-> ' + r.horarioTexto.slice(0, 90));
  chk(/Estamos cerrados, abrimos/.test(r.horarioTexto), 'si cotiza: agrega que estamos cerrados');
  chk(/El depósito se procesa/.test(r.horarioTexto) && /dasela igual/.test(r.horarioTexto), 'si pide la cuenta: se la da y avisa cuando se procesa');
  chk(/Un asesor te contacta/.test(r.horarioTexto), 'si es una queja: un asesor lo contacta al abrir');
  const sm = nodo('AI Agent').parameters.options.systemMessage;
  chk(/Revisar Operacion[^}]*horarioTexto/.test(sm), 'el prompt trae la nota del horario');
}

console.log('');
console.log('=== 6) Sticker de "verificando": solo en horario ===');
{
  function prep(texto, cuando) {
    const real = Date.now; Date.now = () => cuando;
    try {
      const $ = n => (n === 'Webhook Evolution API' || n === 'Cuando lo Llama el Bot') ? { first: () => ({ json: { body: { data: { key: { remoteJid: '593990000001@s.whatsapp.net', id: 'X' } } } } }) } : { first: () => ({ json: {} }) };
      return new Function('$json', '$', code('Prep Debounce'))({ texto }, $)[0].json;
    } finally { Date.now = real; }
  }
  const cap = captura('60.00', '44440006');
  chk(prep(cap, ec('2026-11-20', '15:00')).stickerVerificando === true, 'captura de dia: sticker');
  chk(prep(cap, ec('2026-11-20', '22:00')).stickerVerificando === false, 'captura de noche: sin sticker');
  chk(prep(cap, ec('2026-11-20', '22:00')).espera === 100, 'de noche igual espera 100 s (para juntar captura y cuenta)');
  chk(prep('hola', ec('2026-11-20', '15:00')).stickerVerificando === false, 'un texto: nunca');
  const cond = JSON.stringify(nodo('Llego un Comprobante?').parameters);
  chk(/stickerVerificando/.test(cond), 'el nodo "Llego un Comprobante?" mira stickerVerificando');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
