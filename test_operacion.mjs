// Prueba de "Revisar Operacion": captura y cuenta en cualquier orden, y capturas repetidas.
//
// Lo que destapo el problema (20/11): una clienta mando la cuenta destino y 14 minutos despues
// dos capturas del mismo Zelle. El bot solo juntaba lo que llegaba en sus 30-60 segundos de
// espera: le dijo dos veces "Listo, recibido!" y no paso NADA al grupo.
//
// Todos los datos de esta prueba son INVENTADOS: el repositorio es publico.
//
// Correr con:  node test_operacion.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const wfPub = JSON.parse(readFileSync('workflow_operacion_publicar.json', 'utf8').replace(/^﻿/, ''));
const nodo = n => wf.nodes.find(x => x.name === n) || wfPub.nodes.find(x => x.name === n);
const code = n => nodo(n).parameters.jsCode;
const SALTO = String.fromCharCode(10);

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(66) + ' ' + (detalle || ''));
};

// Nuestras cuentas del dia (donde el cliente PAGA). No son cuentas destino.
const NUESTRAS = [
  { Pais: 'Ecuador', Metodo: 'Pichincha', Datos: '*CUENTA AUTORIZADA USD*\n\n1) 2200000001\n*Pichincha ahorro*\nC.I: 0900000001\n*Titular Empresa*' },
  { Pais: 'Zelle', Metodo: 'Zelle', Datos: '*Zelle*\nempresa.zelle@example.com\nTitular Empresa' }
];

let reloj = Date.parse('2026-11-20T22:00:00Z');   // 5:00 pm en Ecuador: ABIERTO (fuera de horario no se aprueba)
const pasan = minutos => { reloj += minutos * 60000; };

function revisar(mensajes, op) {
  const real = Date.now; Date.now = () => reloj;
  try {
    const $ = (n) => {
      if (n === 'Code in JavaScript') return { first: () => ({ json: { cuentas: NUESTRAS, sessionId: 'chat', modo: 'detal' } }) };
      if (n === 'Combinar') return { first: () => ({ json: { mensajes } }) };
      if (n === 'Redis Leer Operacion') return { first: () => ({ json: { operacion: op ? JSON.stringify(op) : null } }) };
      throw new Error('nodo inesperado: ' + n);
    };
    const r = new Function('$', code('Revisar Operacion'))($)[0].json;
    r.op = JSON.parse(r.operacionNueva);
    return r;
  } finally { Date.now = real; }
}

function prep(texto) {
  const $ = (n) => {
    if (n === 'Webhook Evolution API') return { first: () => ({ json: { body: { data: { key: { remoteJid: '584120000000@s.whatsapp.net', id: 'ID1' } } } } }) };
    return { item: { json: {} }, first: () => ({ json: {} }) };
  };
  return new Function('$json', '$', code('Prep Debounce'))({ texto }, $)[0].json;
}

function detectar(ro) {
  const $ = (n) => {
    if (n === 'Revisar Operacion') return { first: () => ({ json: ro }) };
    if (n === 'Combinar') return { item: { json: { mensajeCombinado: 'NO DEBE USARSE', mensajes: [] } } };
    if (n === 'Webhook Evolution API') return { first: () => ({ json: { body: { data: {
      key: { remoteJid: '584120000000@s.whatsapp.net' }, pushName: 'Ana' } } } }) };
    if (n === 'Solo Estos Numeros') return { first: () => ({ json: { nombreCargado: 'Ana Prueba' } }) };
    return { item: { json: {} }, first: () => ({ json: {} }) };
  };
  return new Function('$', code('Detectar Aprobación'))($);
}

function separar(ro, ap) {
  const payload = Object.assign({}, ap, { mensajesAprobar: ro.mensajesAprobar, registro: ro.registro });
  const $ = (n) => {
    if (n === 'Cuando lo Llama el Bot') return { first: () => ({ json: payload }), item: { json: payload } };
    return { item: { json: {} }, first: () => ({ json: {} }) };
  };
  return new Function('$', code('Separar Cuentas'))($).map(i => i.json);
}

const captura = (monto, ref, huella) => '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: $' + monto
  + ', Banco: Zelle, Fecha: nov 20, 2026, ' + (ref ? 'Numero de transaccion: ' + ref : 'Referencia: no visible')
  + (huella ? ' Huella: ' + huella : '') + ']';
const CUENTA_VE = ['Banco Nacional de Credito', '0191-0000-00-0000012345 (Corriente)', 'Ana Prueba', 'Ci 11111111', '$60'].join(SALTO);
const CUENTA_VE2 = ['Venezuela', '01020000000000012345', 'Maria Perez', '12345678', '35$'].join(SALTO);

console.log('=== 1) CUENTA PRIMERO, CAPTURA 14 MIN DESPUES (el caso del 20/11) ===');
{
  const r1 = revisar([{ id: 'CTA1', texto: CUENTA_VE }], null);
  chk(r1.estadoOperacion === 'falta_captura', 'con la cuenta sola: falta la captura', '-> ' + r1.estadoOperacion);
  chk(/NO mando la captura/.test(r1.notaIA), 'y le dice al agente que la pida');
  chk(r1.op.cuenta && r1.op.cuenta.mensajes[0].id === 'CTA1', 'y guarda la cuenta (con el id del mensaje)');
  chk(r1.textoAprobar === '', 'todavia no hay nada que pasar al grupo');

  pasan(14);
  const r2 = revisar([{ id: 'FOTO1', texto: captura('60.00', '', 'aaaa1111bbbb2222') }], r1.op);
  chk(r2.estadoOperacion === 'completo', 'llega la captura: COMPLETO aunque pasaron 14 min', '-> ' + r2.estadoOperacion);
  chk(/Listo, recibido/.test(r2.notaIA), 'el agente confirma "Listo, recibido"');
  chk(/COMPROBANTE/.test(r2.textoAprobar) && /0191-0000/.test(r2.textoAprobar), 'texto para el grupo: captura + cuenta');
  chk(r2.idImagen === 'FOTO1', 'la foto que se publica es la de la captura', '-> ' + r2.idImagen);
  chk(r2.mensajesAprobar.some(m => m.id === 'CTA1'), 'conserva el id del mensaje de la cuenta (para citarlo)');
  chk(r2.op.cuenta === null && r2.op.capturas.length === 0, 'ya no queda nada pendiente');
  chk(r2.op.hechos.length === 1, 'y recuerda ese deposito para reconocer repetidas');

  const ap = detectar(r2);
  chk(ap.length === 1, 'Detectar Aprobacion lo APRUEBA (se pasa al grupo)', '-> ' + ap.length);
  chk(ap.length === 1 && ap[0].json.idImagen === 'FOTO1', 'y entrega la foto de la captura');
  chk(ap.length === 1 && ap[0].json.idCuenta === 'CTA1', 'y el mensaje de la cuenta para citarlo', '-> ' + (ap[0] || { json: {} }).json.idCuenta);
  const sep = separar(r2, ap[0].json);
  chk(sep.length === 1 && sep[0].cuenta.indexOf('Ana Prueba - $60') === 0, 'al grupo va con cabecera nombre + monto',
      '-> ' + JSON.stringify(sep.length ? sep[0].cuenta.split(SALTO)[0] : ''));

  pasan(1.5);
  const r3 = revisar([{ id: 'FOTO2', texto: captura('60.00', '31700000042', 'cccc3333dddd4444') }], r2.op);
  chk(r3.estadoOperacion === 'repetido', 'la 2da pantalla del mismo Zelle: REPETIDO', '-> ' + r3.estadoOperacion);
  chk(/repetido/.test(r3.notaIA), 'el agente le dice al cliente que esta repetido');
  chk(detectar(r3).length === 0, 'y NO se vuelve a pasar al grupo');
}

console.log('');
console.log('=== 2) CAPTURA PRIMERO, CUENTA DESPUES ===');
{
  reloj = Date.parse('2026-11-20T19:00:00Z');   // 2:00 pm en Ecuador (abierto)
  const r1 = revisar([{ id: 'FOTO9', texto: captura('35.00', '031299', 'eeee5555ffff6666') }], null);
  chk(r1.estadoOperacion === 'falta_cuenta', 'con la captura sola: falta la cuenta', '-> ' + r1.estadoOperacion);
  chk(/NO tengo la cuenta destino/.test(r1.notaIA), 'y le dice al agente que la pida');
  chk(r1.op.capturas.length === 1, 'y guarda la captura');

  pasan(25);
  const r2 = revisar([{ id: 'CTA9', texto: CUENTA_VE2 }], r1.op);
  chk(r2.estadoOperacion === 'completo', 'llega la cuenta 25 min despues: COMPLETO', '-> ' + r2.estadoOperacion);
  chk(r2.idImagen === 'FOTO9', 'publica la foto de la captura guardada', '-> ' + r2.idImagen);
  chk(detectar(r2).length === 1, 'y se aprueba');

  pasan(180);
  const r3 = revisar([{ id: 'FOTO10', texto: captura('35.00', '', 'eeee5555ffff6666') }], r2.op);
  chk(r3.estadoOperacion === 'repetido', 'la MISMA foto reenviada 3 horas despues: REPETIDO', '-> ' + r3.estadoOperacion);

  const r4 = revisar([{ id: 'FOTO11', texto: captura('35.00', '031299', '9999888877776666') }], r2.op);
  chk(r4.estadoOperacion === 'repetido', 'otra foto con la MISMA referencia: REPETIDO', '-> ' + r4.estadoOperacion);

  const r5 = revisar([{ id: 'FOTO12', texto: captura('35.00', '777001', '1212343456567878') }], r2.op);
  chk(r5.estadoOperacion === 'falta_cuenta', 'mismo monto pero OTRA referencia: es otro deposito', '-> ' + r5.estadoOperacion);
}

console.log('');
console.log('=== 3) LO QUE NO DEBE DISPARAR NADA ===');
{
  reloj = Date.parse('2026-11-21T16:00:00Z');   // 11:00 am en Ecuador (abierto)
  const vieja = revisar([{ id: 'CTA20', texto: CUENTA_VE }], null);
  pasan(180);
  const r1 = revisar([{ id: 'FOTO20', texto: captura('60.00', '555001', 'abab1212cdcd3434') }], vieja.op);
  chk(r1.estadoOperacion === 'falta_cuenta', 'una cuenta de hace 3 horas ya no se usa', '-> ' + r1.estadoOperacion);

  const r2 = revisar([{ id: 'M1', texto: 'Listo, ya deposite en la 2200000001' }, { id: 'FOTO21', texto: captura('60.00', '555002', '') }], null);
  chk(r2.estadoOperacion === 'falta_cuenta', 'NUESTRA cuenta no cuenta como cuenta destino', '-> ' + r2.estadoOperacion);
  const r2b = revisar([{ id: 'M1b', texto: 'Ya te mande a empresa.zelle@example.com' }], null);
  chk(r2b.estadoOperacion === 'nada', 'nuestro correo de Zelle tampoco', '-> ' + r2b.estadoOperacion);

  const cita = '[el cliente respondio citando esto que tu/asesor le dijiste antes: "Pichincha 2200000001 Titular Empresa"]' + SALTO + 'listo';
  const r3 = revisar([{ id: 'M2', texto: cita }], null);
  chk(r3.estadoOperacion === 'nada', 'citar el mensaje con nuestra cuenta no es una cuenta destino', '-> ' + r3.estadoOperacion);

  const r4 = revisar([{ id: 'M3', texto: 'hola, tienes tasa para colombia?' }], null);
  chk(r4.estadoOperacion === 'nada' && r4.notaIA === '', 'una pregunta cualquiera: nada, sin nota');

  const r5 = revisar([{ id: 'M4', texto: 'hola' }], vieja.op);
  chk(r5.estadoOperacion === 'nada', 'un saludo con algo pendiente no cambia nada', '-> ' + r5.estadoOperacion);
}

console.log('');
console.log('=== 4) VARIAS CAPTURAS O CUENTAS ===');
{
  reloj = Date.parse('2026-11-21T15:00:00Z');   // 10:00 am en Ecuador (abierto)
  const r1 = revisar([
    { id: 'F1', texto: captura('60.00', '', '0101010101010101') },
    { id: 'F2', texto: captura('60.00', '31700000099', '0202020202020202') },
    { id: 'C1', texto: CUENTA_VE }
  ], null);
  chk(r1.estadoOperacion === 'completo', 'dos pantallas del mismo pago + cuenta en un solo envio', '-> ' + r1.estadoOperacion);
  chk((r1.textoAprobar.match(/COMPROBANTE/g) || []).length === 1, 'se publica UNA sola vez');
  chk(r1.op.hechos.length === 2, 'pero recuerda las dos pantallas');

  const a = revisar([{ id: 'CA', texto: CUENTA_VE }], null);
  pasan(3);
  const b = revisar([{ id: 'CB', texto: CUENTA_VE2 }], a.op);
  chk(b.op.cuenta.mensajes.length === 2, 'dos cuentas en mensajes separados: se guardan las dos');
  pasan(3);
  const c = revisar([{ id: 'CA2', texto: CUENTA_VE }], b.op);
  chk(c.op.cuenta.mensajes.length === 2, 'la misma cuenta escrita otra vez no se duplica');
  pasan(5);
  const d = revisar([{ id: 'FX', texto: captura('95.00', '444555', '') }], c.op);
  chk(d.estadoOperacion === 'completo' && d.mensajesAprobar.length === 3, 'al llegar la captura van las dos cuentas', '-> ' + d.mensajesAprobar.length);

  const p1 = revisar([{ id: 'FP', texto: captura('40.00', '', 'aaaa0000bbbb0000') }], null);
  pasan(2);
  const p2 = revisar([{ id: 'FP2', texto: captura('40.00', '', 'aaaa0000bbbb0000') }], p1.op);
  chk(p2.estadoOperacion === 'falta_cuenta', 'reenvia la captura mientras falta la cuenta: sigue pidiendo la cuenta', '-> ' + p2.estadoOperacion);
  chk(p2.op.capturas.length === 1, 'y no la cuenta dos veces');
}

console.log('');
console.log('=== 4b) EL CLIENTE CITA SU PROPIO MENSAJE Y COMPLETA LA CUENTA (20/11) ===');
{
  // Mando "cedula / telefono / 0102 / 10$", y despues cito ESE mensaje y escribio "Banco
  // Venezuela / Titular ...". El bot viejo le dijo "Listo, recibido" sin captura.
  reloj = Date.parse('2026-11-21T14:00:00Z');
  const datos = ['11111111', '04120000001', '0102', '10$'].join(SALTO);
  const r1 = revisar([{ id: 'E1', texto: datos }], null);
  chk(r1.estadoOperacion === 'falta_captura', 'los datos de pago movil solos: pide la captura', '-> ' + r1.estadoOperacion);
  pasan(2);
  const cita = '[el cliente respondio citando esto que tu/asesor le dijiste antes: "' + datos + '"]' + SALTO
    + 'Me avisa' + SALTO + 'Banco Venezuela' + SALTO + 'Titular Ana Prueba';
  const r2 = revisar([{ id: 'E2', texto: cita }], r1.op);
  chk(r2.estadoOperacion === 'falta_captura', 'sin captura NO dice "recibido": la sigue pidiendo', '-> ' + r2.estadoOperacion);
  const g = r2.op.cuenta.mensajes;
  chk(g.length === 1, 'las dos partes quedan como UNA sola cuenta', '-> ' + g.length);
  chk(g.length === 1 && /04120000001/.test(g[0].texto) && /Titular Ana Prueba/.test(g[0].texto), 'con el telefono citado Y el titular nuevo');
  pasan(5);
  const r3 = revisar([{ id: 'E3', texto: captura('10.00', '880011', '') }], r2.op);
  chk(r3.estadoOperacion === 'completo', 'llega la captura: completo', '-> ' + r3.estadoOperacion);
  chk(/04120000001/.test(r3.textoAprobar) && /Banco Venezuela/.test(r3.textoAprobar), 'al grupo va la cuenta completa');
  chk(!/respondio citando/.test(r3.textoAprobar), 'sin la nota interna de la cita');
}

console.log('');
console.log('=== 4c) UNA PREGUNTA NO ES UNA CUENTA (no meter notas falsas al agente) ===');
{
  reloj = Date.parse('2026-11-21T16:00:00Z');
  const preguntas = [
    'Hola, me pasas la cuenta para depositar?', 'Dame los datos del banco porfa', 'cual es la cedula del titular?',
    'Tienes cuenta en Banesco?', 'a que banco deposito', 'quiero enviar 12.500.000 pesos a una cuenta en Venezuela',
    'Mercantil Maria Perez V-12345678'
  ];
  for (const t of preguntas) {
    const r = revisar([{ id: 'Q', texto: t }], null);
    chk(r.estadoOperacion === 'nada' && r.notaIA === '', 'sin captura NO es cuenta: ' + JSON.stringify(t).slice(0, 44), '-> ' + r.estadoOperacion);
  }
  // Con una captura esperando, un dato corto SI completa (lo mismo que ya hacia Detectar Aprobacion)...
  const guardada = revisar([{ id: 'F', texto: captura('20.00', '660011', '') }], null);
  const ok = revisar([{ id: 'C', texto: 'Mercantil Maria Perez V-12345678' }], guardada.op);
  chk(ok.estadoOperacion === 'completo', 'con la captura esperando, "Mercantil Maria Perez V-..." completa', '-> ' + ok.estadoOperacion);
  // ...pero una pregunta, no.
  const preg = revisar([{ id: 'C2', texto: 'me pasas la cuenta donde deposito?' }], guardada.op);
  chk(preg.estadoOperacion === 'falta_cuenta', 'con la captura esperando, una pregunta no es la cuenta', '-> ' + preg.estadoOperacion);
  // Los datos firmes siguen valiendo sin captura
  for (const t of ['04120000001 V-11111111 Banesco', 'maria.perez@example.com', 'USDT T' + 'X'.repeat(33)]) {
    chk(revisar([{ id: 'D', texto: t }], null).estadoOperacion === 'falta_captura', 'datos firmes sin captura: ' + t.slice(0, 36));
  }
}

console.log('');
console.log('=== 4d) CAPTURAS REPETIDAS: monto + referencia + datos bancarios ===');
{
  reloj = Date.parse('2026-11-21T17:00:00Z');
  const cap = (campos) => '[El cliente envio un COMPROBANTE de pago. Datos leidos: ' + campos + ']';
  const hecho = (campos, huella) => revisar([{ id: 'H', texto: cap(campos) + (huella ? '' : '') }, { id: 'K', texto: CUENTA_VE }], null);
  // el caso real del 20/11: una pantalla sin referencia (con destinatario) y otra con banco y referencia
  const p1 = hecho('Monto: $60.00, Destinatario: MARIA PRUEBA');
  chk(p1.estadoOperacion === 'completo', 'la 1ra pantalla (monto + destinatario) completa', '-> ' + p1.estadoOperacion);
  pasan(2);
  const p2 = revisar([{ id: 'X', texto: cap('Monto: $60.00, Banco: BANCO PRUEBA, Fecha: nov 20, 2026, Referencia: 31700000042') }], p1.op);
  chk(p2.estadoOperacion === 'repetido', 'la 2da pantalla (mismo monto, otro dato): REPETIDO', '-> ' + p2.estadoOperacion);

  // misma referencia, monto distinto -> otro deposito
  const a = hecho('Monto: $60.00, Banco: Zelle, Referencia: 555123');
  pasan(1);
  chk(revisar([{ id: 'X', texto: cap('Monto: $80.00, Banco: Zelle, Referencia: 555123') }], a.op).estadoOperacion !== 'repetido',
      'misma referencia pero OTRO monto: no es repetido');
  chk(revisar([{ id: 'X', texto: cap('Monto: $60.00, Banco: Zelle, Referencia: 555123') }], a.op).estadoOperacion === 'repetido',
      'mismo monto + misma referencia: REPETIDO');
  chk(revisar([{ id: 'X', texto: cap('Monto: $60.00, Banco: Zelle, Referencia: 555999') }], a.op).estadoOperacion !== 'repetido',
      'mismo monto y banco, OTRA referencia: otro deposito');

  // sin referencia: el banco decide
  const b = hecho('Monto: $60.00, Banco: Banesco');
  pasan(1);
  chk(revisar([{ id: 'X', texto: cap('Monto: $60.00, Banco: Mercantil') }], b.op).estadoOperacion !== 'repetido',
      'mismo monto, sin referencia, pero OTRO banco: no es repetido');
  chk(revisar([{ id: 'X', texto: cap('Monto: $60.00, Banco: Banesco Banco Universal') }], b.op).estadoOperacion === 'repetido',
      'mismo monto y el mismo banco (escrito distinto): REPETIDO');
  pasan(40);
  chk(revisar([{ id: 'X', texto: cap('Monto: $60.00, Banco: Banesco') }], b.op).estadoOperacion === 'repetido',
      'mismo monto y banco 40 min despues: REPETIDO (el banco confirma)');
  chk(revisar([{ id: 'X', texto: cap('Monto: $60.00') }], b.op).estadoOperacion !== 'repetido',
      'solo el monto, 40 min despues: ya no alcanza');
  const c = hecho('Monto: $60.00');
  pasan(3);
  chk(revisar([{ id: 'X', texto: cap('Monto: $60.00') }], c.op).estadoOperacion === 'repetido',
      'solo el monto pero a los 3 minutos: REPETIDO');
  chk(revisar([{ id: 'X', texto: cap('Monto: $95.00, Banco: Banesco') }], b.op).estadoOperacion !== 'repetido',
      'otro monto: otro deposito');
}

console.log('');
console.log('=== 4e) CUANTO ESPERA ANTES DE CONTESTAR (captura + cuenta, o cuenta + captura) ===');
{
  chk(prep(captura('60.00', '', '')).espera === 100, 'una captura espera 100s', '-> ' + prep(captura('60.00', '', '')).espera);
  chk(prep(CUENTA_VE).espera === 100, 'una cuenta destino espera 100s (el mismo tiempo)', '-> ' + prep(CUENTA_VE).espera);
  chk(prep('04120000001 V-11111111 Banesco').espera === 100, 'pago movil espera 100s');
  chk(prep('maria.perez@example.com').espera === 100, 'un correo (Zelle) espera 100s');
  chk(prep('hola, me pasas la cuenta para depositar?').espera === 30, 'pedir NUESTRA cuenta sigue en 30s');
  chk(prep('tienes cuenta en Banesco?').espera === 30, 'una pregunta con "banco" sigue en 30s');
  chk(prep('cuanto es 12.500.000 pesos en dolares').espera === 30, 'una cifra grande sin datos sigue en 30s');
  chk(prep('[el cliente respondio citando esto que tu/asesor le dijiste antes: "Pichincha 2200000001 Titular Empresa"]' + SALTO + 'listo').espera === 30,
      'citar el mensaje con NUESTRA cuenta sigue en 30s');
  chk(prep(captura('60.00', '', '')).esComprobante === true && prep(CUENTA_VE).esComprobante === false, 'el sticker de "verificando" solo sale con la captura');
}

console.log('');
console.log('=== 5) HUELLA DE LA FOTO (Texto de Imagen) ===');
{
  const leer = (sha) => {
    const $ = (n) => {
      if (n === 'Leer Imagen') return { item: { json: { content: '{"tipo":"comprobante","resumen":"Monto: $60.00, Referencia: 123456"}' } } };
      if (n === 'Webhook Evolution API') return { first: () => ({ json: { body: { data: { key: { id: 'IMG1' }, message: { imageMessage: { fileSha256: sha } } } } } }) };
      return { item: { json: {} }, first: () => ({ json: {} }) };
    };
    return new Function('$', code('Texto de Imagen'))($)[0].json.texto;
  };
  const bytes = { 0: 171, 1: 205, 2: 239, 3: 1, 4: 35, 5: 69, 6: 103, 7: 137, 8: 1, 9: 2 };
  const t1 = leer(bytes);
  chk(/Huella: abcdef0123456789\]/.test(t1), 'con el sha como objeto de bytes', '-> ' + t1.slice(-30));
  const t2 = leer(Buffer.from([171, 205, 239, 1, 35, 69, 103, 137, 9]).toString('base64'));
  chk(/Huella: abcdef0123456789\]/.test(t2), 'con el sha en base64 da la misma huella');
  const t3 = leer(undefined);
  chk(/Referencia: 123456\]$/.test(t3), 'sin sha: la captura sale igual, sin huella');
}

console.log('');
console.log('=== 5b) MONTO Y REFERENCIA AUNQUE LA IA NO ESCRIBA "Monto:" (caso del 21/11) ===');
{
  // 21/11: la IA leyo la captura como "$30,00 Transferencia a ..., N. de comprobante ..." (sin la palabra
  // "Monto:"). El bot no encontro el monto, la clienta mando la cuenta sin monto, y en transferir la
  // cuenta salio sin precio.
  reloj = Date.parse('2026-11-21T15:00:00Z');   // 10:00 am en Ecuador (abierto)
  const CAP = (ref, huella) => '[El cliente envio un COMPROBANTE de pago. Datos leidos: $30,00 Transferencia a Persona Ejemplo el 21 de noviembre de 2026, Banco Pichincha, N. de comprobante ' + ref + '. Huella: ' + huella + ']';
  const CTA = '0102 1234567 04120000000';
  const r = revisar([{ id: 'F1', texto: CAP('12345678', '0011223344556677') }, { id: 'C1', texto: CTA }], null);
  chk(r.estadoOperacion === 'completo', 'captura + cuenta: COMPLETO', '-> ' + r.estadoOperacion);
  chk(r.registro.capturas[0].monto === 30, 'lee el monto "$30,00" aunque no diga "Monto:"', '-> ' + r.registro.capturas[0].monto);
  chk(r.registro.capturas[0].ref === '12345678', 'y la referencia "N. de comprobante 12345678"', '-> ' + r.registro.capturas[0].ref);
  const ap = detectar(r);
  chk(ap.length === 1 && ap[0].json.montoComprobante === 30, 'Detectar Aprobacion tambien lee el monto', '-> ' + (ap[0] || { json: {} }).json.montoComprobante);
  const sep = separar(r, ap[0].json);
  chk(sep.length === 1 && sep[0].cuenta.split(SALTO)[0] === 'Ana Prueba - $30' && sep[0].monto === 30,
      'UNA sola cuenta sin monto: la cabecera lleva el monto del deposito', '-> ' + JSON.stringify(sep.map(x => x.cuenta.split(SALTO)[0])));

  const r3 = revisar([{ id: 'F3', texto: CAP('12345670', '1111222233334444') }, { id: 'C4', texto: CTA + SALTO + '$25' }], null);
  const sep3 = separar(r3, detectar(r3)[0].json);
  chk(sep3.length === 1 && sep3[0].monto === 25, 'si la cuenta trae su monto, manda el de la cuenta', '-> ' + (sep3[0] || {}).monto);

  const prompt = String(nodo('Leer Imagen').parameters.text);
  chk(/Monto: </.test(prompt) && /Referencia: </.test(prompt), 'la IA lee las capturas siempre con el mismo formato (Monto, Banco, Fecha, Referencia)');
}

console.log('');
console.log('=== 5c) CUENTAS SIN MONTO: SE LE PIDE AL CLIENTE (pedido de Kelvin, 21/11) ===');
{
  // Con VARIAS cuentas, cada una tiene que decir cuanto va. Si a alguna le falta, no se pasa a
  // transferir: se le pide al cliente que le coloque el monto y las vuelva a mandar.
  reloj = Date.parse('2026-11-21T16:00:00Z');   // 11:00 am en Ecuador (abierto)
  const CAP = (monto, ref) => '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: ' + monto + ', Banco: Pichincha, Fecha: 21/11/2026, Referencia: ' + ref + ']';
  const CTA1 = '0102 1234567 04120000000';
  const CTA2 = '0134 7654321 04140000000';

  const r1 = revisar([{ id: 'F1', texto: CAP('$30,00', '55660001') }, { id: 'C1', texto: CTA1 }, { id: 'C2', texto: CTA2 }], null);
  chk(r1.estadoOperacion === 'falta_monto', 'DOS cuentas sin monto: FALTA EL MONTO', '-> ' + r1.estadoOperacion);
  chk(/no traen el monto/.test(r1.notaIA) && /cada una/.test(r1.notaIA), 'le pide que le coloque el monto a cada cuenta', '-> ' + r1.notaIA.slice(-120));
  chk(r1.textoAprobar === '' && detectar(r1).length === 0, 'y NO se pasa a transferir');
  chk(r1.op.capturas.length === 1 && r1.op.cuenta && r1.op.cuenta.mensajes.length === 2, 'la captura y las cuentas quedan guardadas esperando');

  pasan(3);
  const r2 = revisar([{ id: 'C3', texto: CTA1 + SALTO + '$20' + SALTO + SALTO + CTA2 + SALTO + '$10' }], r1.op);
  chk(r2.estadoOperacion === 'completo', 'las vuelve a mandar con monto: COMPLETO', '-> ' + r2.estadoOperacion);
  const sep2 = separar(r2, detectar(r2)[0].json);
  chk(sep2.length === 2 && sep2.map(x => x.monto).join() === '20,10', 'al grupo van las dos, cada una con su monto (sin las viejas sin monto)',
      '-> ' + JSON.stringify(sep2.map(x => x.cuenta.split(SALTO)[0])));

  const r3 = revisar([{ id: 'C4', texto: CTA1 + SALTO + '$20' }], r1.op);
  chk(r3.estadoOperacion === 'falta_monto', 'si corrige solo una de las dos: sigue faltando el monto de la otra', '-> ' + r3.estadoOperacion);
  chk(r3.op.cuenta.mensajes.length === 2 && r3.op.cuenta.mensajes.some(m => /\$20/.test(m.texto)), 'y se guarda la corregida en lugar de la vieja');

  const r4 = revisar([{ id: 'X1', texto: 'ok' }], r1.op);
  chk(r4.estadoOperacion === 'falta_monto' && /si pregunto otra cosa/i.test(r4.notaIA), 'si escribe otra cosa: se lo recuerda, sin dejar de contestarle', '-> ' + r4.notaIA.slice(-90));

  const r5 = revisar([{ id: 'F5', texto: CAP('no visible', '55660005') }, { id: 'C5', texto: CTA1 }], null);
  chk(r5.estadoOperacion === 'falta_monto' && /envíamelos de nuevo/.test(r5.notaIA), 'UNA cuenta sin monto y la captura sin monto legible: se lo pide', '-> ' + r5.estadoOperacion);
  const r6 = revisar([{ id: 'F6', texto: CAP('$30,00', '55660006') }, { id: 'C6', texto: CTA1 }], null);
  chk(r6.estadoOperacion === 'completo', 'UNA cuenta sin monto pero se leyo el deposito: COMPLETO (va con el del deposito)', '-> ' + r6.estadoOperacion);

  const r7 = revisar([{ id: 'F7', texto: CAP('$30,00', '55660007') }, { id: 'C7', texto: CTA1 + SALTO + '$20' + SALTO + SALTO + CTA2 }], null);
  chk(r7.estadoOperacion === 'falta_monto', 'dos cuentas en UN mensaje, una sin monto: tambien se pide', '-> ' + r7.estadoOperacion);
  const r8 = revisar([{ id: 'F8', texto: CAP('$30,00', '55660008') }, { id: 'C8', texto: CTA1 + SALTO + '$20' }, { id: 'C9', texto: CTA2 + SALTO + '10$' }], null);
  chk(r8.estadoOperacion === 'completo', 'dos cuentas con su monto cada una: COMPLETO', '-> ' + r8.estadoOperacion);

  reloj = Date.parse('2026-11-22T03:00:00Z');   // 10:00 pm en Ecuador (cerrado)
  const r9 = revisar([{ id: 'F9', texto: CAP('$30,00', '55660009') }, { id: 'C10', texto: CTA1 }, { id: 'C11', texto: CTA2 }], null);
  chk(r9.estadoOperacion === 'falta_monto' && r9.enEspera === false, 'de noche tambien se pide (no queda en espera sin monto)', '-> ' + r9.estadoOperacion);
}

console.log('');
console.log('=== 5d) UNA CUENTA ESCRITA CON RENGLONES VACIOS SIGUE SIENDO UNA SOLA ===');
{
  // Revision de los chats reales (21/11): muchos clientes escriben UNA cuenta con renglones vacios en el
  // medio ("Banco / (vacio) / numero / (vacio) / titular y cedula / (vacio) / $60"). El bot partia cada
  // pedazo como una cuenta distinta: al grupo iban 2 o 3 mensajes sin monto.
  reloj = Date.parse('2026-11-21T16:00:00Z');   // 11:00 am en Ecuador
  const CAP = (monto, ref) => '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: ' + monto + ', Banco: Pichincha, Fecha: 21/11/2026, Referencia: ' + ref + ']';
  const V = '';   // renglon vacio
  const una = ['Banco Nacional de Credito', V, '0191-0000-00-0000012345 (Corriente)', V, 'Ana Prueba', ' Ci 11111111', V, V, '$60'].join(SALTO);
  const r1 = revisar([{ id: 'F1', texto: CAP('$60,00', '77880001') }, { id: 'C1', texto: una }], null);
  chk(r1.estadoOperacion === 'completo', 'una cuenta con renglones vacios: COMPLETO (no le pide el monto)', '-> ' + r1.estadoOperacion);
  const s1 = separar(r1, detectar(r1)[0].json);
  chk(s1.length === 1 && s1[0].monto === 60, 'al grupo va UNA sola publicacion, con su monto', '-> ' + s1.length + ' publicaciones, monto ' + (s1[0] || {}).monto);
  chk(s1.length === 1 && /Banco Nacional/.test(s1[0].cuenta) && /0191-0000/.test(s1[0].cuenta) && /Ana Prueba/.test(s1[0].cuenta), 'con el banco, el numero y el titular juntos');

  const saludo = ['Buenos dias amigo', V, 'Banco Ejemplo', '01020000000000099999', 'Pedro Prueba', V, '$25'].join(SALTO);
  const r2 = revisar([{ id: 'F2', texto: CAP('$25,00', '77880002') }, { id: 'C2', texto: saludo }], null);
  const s2 = separar(r2, detectar(r2)[0].json);
  chk(r2.estadoOperacion === 'completo' && s2.length === 1 && !/Buenos dias/.test(s2[0].cuenta) && s2[0].monto === 25, 'el saludo de antes no va en la cuenta', '-> ' + JSON.stringify(s2.map(x => x.cuenta)));

  const dos = ['Banco Uno', '01020000000000011111', 'Luisa Prueba', '$40', V, 'Banco Dos', '01340000000000022222', 'Mario Prueba', '$20'].join(SALTO);
  const r3 = revisar([{ id: 'F3', texto: CAP('$60,00', '77880003') }, { id: 'C3', texto: dos }], null);
  const s3 = separar(r3, detectar(r3)[0].json);
  chk(r3.estadoOperacion === 'completo' && s3.length === 2 && s3.map(x => x.monto).join() === '40,20', 'dos cuentas separadas por un renglon vacio: dos publicaciones', '-> ' + s3.length);

  const dosLargas = ['Banco Uno', V, '01020000000000011111', V, 'Luisa Prueba', V, '$40', V, 'Banco Dos', V, '01340000000000022222', V, 'Mario Prueba', V, '$20'].join(SALTO);
  const r4 = revisar([{ id: 'F4', texto: CAP('$60,00', '77880004') }, { id: 'C4', texto: dosLargas }], null);
  const s4 = separar(r4, detectar(r4)[0].json);
  chk(r4.estadoOperacion === 'completo' && s4.length === 2 && s4.map(x => x.monto).join() === '40,20' && /Luisa/.test(s4[0].cuenta) && /Mario/.test(s4[1].cuenta),
      'dos cuentas, cada una con renglones vacios: se arman bien', '-> ' + JSON.stringify(s4.map(x => x.cuenta.split(SALTO)[0])));

  const ecu = ['Pichincha ahorro', '2200000002', V, 'C.I: 0900000002', V, 'Rosa Prueba'].join(SALTO);
  const r5 = revisar([{ id: 'F5', texto: CAP('$15,00', '77880005') }, { id: 'C5', texto: ecu }], null);
  const s5 = separar(r5, detectar(r5)[0].json);
  chk(r5.estadoOperacion === 'completo' && s5.length === 1 && s5[0].monto === 15 && /Rosa Prueba/.test(s5[0].cuenta), 'la cedula de 10 digitos no se toma como otra cuenta', '-> ' + s5.length);
}

console.log('');
console.log('=== 5e) EL DEPOSITO TIENE QUE CUADRAR CON LAS CUENTAS (pedido de Kelvin, 23/11) ===');
{
  // Con la captura en dolares y las cuentas con su monto, la suma de las cuentas tiene que dar lo
  // mismo que el deposito. Si no, NO se pasa a transferir: se le pide que confirme los montos, y
  // cuando lo corrige se procesa solo.
  reloj = Date.parse('2026-11-23T16:00:00Z');   // 11:00 am en Ecuador (abierto)
  const CAP = (monto, ref, extra) => '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: ' + monto + (extra || '')
    + ', Banco: Pichincha, Fecha: 23/11/2026, Referencia: ' + ref + ']';
  const CTA1 = '0102 1234567 04120000000';
  const CTA2 = '0134 7654321 04140000000';

  // UNA cuenta
  const a1 = revisar([{ id: 'F1', texto: CAP('$10,00', '77001') }, { id: 'C1', texto: CTA1 + SALTO + '$15' }], null);
  chk(a1.estadoOperacion === 'no_cuadra', 'deposito $10 y la cuenta dice $15: NO CUADRA', '-> ' + a1.estadoOperacion);
  chk(/tu depósito es de \$10 pero la cuenta dice \$15/.test(a1.notaIA) && /¿Me confirmas los montos\?/.test(a1.notaIA), 'le dice cuanto deposito y cuanto dice la cuenta, y pide confirmar', '-> ' + a1.notaIA.slice(-170));
  chk(!/otro depósito/.test(a1.notaIA), 'la primera vez NO le habla de otro deposito (lo mismo deposite de mas o de menos)');
  chk(a1.textoAprobar === '' && detectar(a1).length === 0, 'y NO se pasa a transferir');
  chk(a1.op.capturas.length === 1 && a1.op.cuenta && a1.op.cuenta.mensajes.length === 1, 'la captura y la cuenta quedan guardadas esperando');
  chk(a1.op.noCuadra && a1.op.noCuadra.ts === reloj && a1.op.noCuadra.deposito === 10 && a1.op.noCuadra.suma === 15 && a1.op.noCuadra.paso === 'preguntado',
      'queda la marca "no cuadra" con desde cuando y en que paso va', '-> ' + JSON.stringify(a1.op.noCuadra));
  chk(a1.vigilarMonto && a1.vigilarMonto.modo === 'vigilar' && a1.vigilarMonto.token === reloj, 'y se pide vigilarla (recordatorio a los 5 min, aviso a los 10)');

  pasan(2);
  const a2 = revisar([{ id: 'X1', texto: 'a que hora cierran hoy?' }], a1.op);
  chk(a2.estadoOperacion === 'no_cuadra' && /si pregunto otra cosa/i.test(a2.notaIA) && /confirme los montos/.test(a2.notaIA), 'si escribe otra cosa: le contesta y le recuerda confirmar', '-> ' + a2.notaIA.slice(-120));
  chk(a2.op.noCuadra.ts === a1.op.noCuadra.ts && a2.vigilarMonto === null, 'es el MISMO caso: no se vuelve a pedir vigilancia');

  // Dice que SI (los montos de las cuentas estan bien) y deposito de MENOS: se le pide la otra captura
  pasan(1);
  const s1 = revisar([{ id: 'X2', texto: 'Si, asi esta bien' }], a1.op);
  chk(s1.estadoOperacion === 'no_cuadra' && /envíame la captura del otro depósito/.test(s1.notaIA) && s1.op.noCuadra.paso === 'pidio_captura',
      'dice "si" y deposito de MENOS: le pide la captura del otro deposito', '-> ' + s1.notaIA.slice(-90));
  chk(s1.vigilarMonto === null && detectar(s1).length === 0, 'sigue sin pasar a transferir y sin escalar');
  const s2 = revisar([{ id: 'F1b', texto: CAP('$5,00', '77001b') }], s1.op);
  chk(s2.estadoOperacion === 'completo' && !s2.op.noCuadra, 'manda la otra captura ($10 + $5 = $15): COMPLETO', '-> ' + s2.estadoOperacion);
  const s3 = revisar([{ id: 'X3', texto: 'si' }], s1.op);
  chk(s3.estadoOperacion === 'no_cuadra' && /Un asesor lo revisa/.test(s3.notaIA) && s3.op.noCuadra.paso === 'escalado', 'si vuelve a decir "si" sin mandar la captura: pasa a un asesor', '-> ' + s3.notaIA.slice(-70));
  chk(s3.vigilarMonto && s3.vigilarMonto.modo === 'escalar' && s3.vigilarMonto.token === a1.op.noCuadra.ts, 'y se deja el aviso en transferir (modo escalar)');
  chk(detectar(s3).length === 0, 'pero NO se transfiere');
  const s4 = revisar([{ id: 'X4', texto: 'ya?' }], s3.op);
  chk(s4.estadoOperacion === 'no_cuadra' && /un asesor la esta revisando/.test(s4.notaIA) && s4.vigilarMonto === null, 'despues: "un asesor lo esta revisando", sin volver a escalar', '-> ' + s4.notaIA.slice(-90));
  const s5 = revisar([{ id: 'C1c', texto: CTA1 + SALTO + '$10' }], s3.op);
  chk(s5.estadoOperacion === 'completo', 'y si igual corrige la cuenta a $10: se procesa', '-> ' + s5.estadoOperacion);

  // Dice que SI y deposito de MAS: un asesor, y aviso en transferir
  const m1 = revisar([{ id: 'F1m', texto: CAP('$20,00', '77001m') }, { id: 'C1m', texto: CTA1 + SALTO + '$15' }], null);
  pasan(1);
  const m2 = revisar([{ id: 'X5', texto: 'correcto' }], m1.op);
  chk(m2.estadoOperacion === 'no_cuadra' && /Un asesor lo revisa/.test(m2.notaIA) && m2.vigilarMonto && m2.vigilarMonto.modo === 'escalar',
      'deposito de MAS ($20 / $15) y dice "correcto": pasa a un asesor y avisa en transferir', '-> ' + m2.notaIA.slice(-70));
  const m3 = revisar([{ id: 'X6', texto: 'no, espera' }], m1.op);
  chk(m3.estadoOperacion === 'no_cuadra' && m3.vigilarMonto === null && m3.op.noCuadra.paso === 'preguntado', '"no, espera" no es un si: sigue esperando');

  pasan(3);
  const a3 = revisar([{ id: 'C2', texto: CTA1 + SALTO + '$10' }], a2.op);
  chk(a3.estadoOperacion === 'completo', 'manda la cuenta corregida con $10: COMPLETO', '-> ' + a3.estadoOperacion);
  chk(/\$10/.test(a3.textoAprobar) && !/\$15/.test(a3.textoAprobar), 'al grupo va la cuenta CORREGIDA (no la de $15)', '-> ' + JSON.stringify(a3.textoAprobar.slice(-40)));
  chk(!a3.op.noCuadra && a3.vigilarMonto === null, 'y la marca "no cuadra" se borra');
  chk(detectar(a3).length === 1, 'y se pasa a transferir');

  // VARIAS cuentas: se suman
  const b1 = revisar([{ id: 'F2', texto: CAP('$15,00', '77002') }, { id: 'C3', texto: CTA1 + SALTO + '$10' }, { id: 'C4', texto: CTA2 + SALTO + '$5' }], null);
  chk(b1.estadoOperacion === 'completo', 'deposito $15 y dos cuentas de $10 + $5: COMPLETO', '-> ' + b1.estadoOperacion);
  const b2 = revisar([{ id: 'F3', texto: CAP('$10,00', '77003') }, { id: 'C5', texto: CTA1 + SALTO + '$10' + SALTO + SALTO + CTA2 + SALTO + '$5' }], null);
  chk(b2.estadoOperacion === 'no_cuadra' && /las cuentas suman \$15/.test(b2.notaIA), 'deposito $10 y las cuentas suman $15: NO CUADRA', '-> ' + b2.estadoOperacion);
  pasan(2);
  const b3 = revisar([{ id: 'C6', texto: CTA1 + SALTO + '$10' }], b2.op);
  chk(b3.estadoOperacion === 'completo' && b3.op.cuenta === null, 'manda solo la de $10: esas son las buenas, COMPLETO', '-> ' + b3.estadoOperacion);
  const sep3 = separar(b3, detectar(b3)[0].json);
  chk(sep3.length === 1 && sep3[0].monto === 10, 'al grupo va UNA cuenta, la de $10 (la de $5 se descarta)', '-> ' + JSON.stringify(sep3.map(x => x.monto)));
  pasan(1);
  const b4 = revisar([{ id: 'F4', texto: CAP('$5,00', '77004') }], b2.op);
  chk(b4.estadoOperacion === 'completo', 'o manda la captura del otro deposito de $5 ($10 + $5 = $15): COMPLETO', '-> ' + b4.estadoOperacion);
  const b5 = revisar([{ id: 'F5', texto: CAP('$20,00', '77005') }, { id: 'C7', texto: CTA1 + SALTO + '$10' }, { id: 'C8', texto: CTA2 + SALTO + '$5' }], null);
  chk(b5.estadoOperacion === 'no_cuadra' && !/otro depósito/.test(b5.notaIA), 'deposito MAYOR ($20) que las cuentas ($15): tambien pregunta (sin lo del otro deposito)', '-> ' + b5.estadoOperacion);
  const b6 = revisar([{ id: 'F6', texto: CAP('$10,00', '77006') }, { id: 'C9', texto: CTA1 + SALTO + '$10' + SALTO + SALTO + CTA2 }], null);
  chk(b6.estadoOperacion === 'falta_monto', 'si a una cuenta le falta el monto, primero se pide el monto', '-> ' + b6.estadoOperacion);

  // EXACTO: ni un centavo de diferencia
  const c1 = revisar([{ id: 'F7', texto: CAP('$10,30', '77007') }, { id: 'C10', texto: CTA1 + SALTO + '$10' }], null);
  chk(c1.estadoOperacion === 'no_cuadra' && /\$10\.30/.test(c1.notaIA), 'tiene que ser EXACTO: $10,30 contra $10 NO cuadra', '-> ' + c1.estadoOperacion);
  const c1b = revisar([{ id: 'F7b', texto: CAP('$10,50', '77007b') }, { id: 'C10b', texto: CTA1 + SALTO + '$10,50' }], null);
  chk(c1b.estadoOperacion === 'completo', '$10,50 contra $10,50: cuadra', '-> ' + c1b.estadoOperacion);
  const c2 = revisar([{ id: 'F8', texto: CAP('$30,00', '77008') }, { id: 'C11', texto: CTA1 }], null);
  chk(c2.estadoOperacion === 'completo', 'UNA cuenta sin monto: va con el del deposito, como siempre', '-> ' + c2.estadoOperacion);

  // OTRAS MONEDAS: las cuentas en la misma moneda del deposito
  const CAPM = (monto, banco, ref, moneda) => '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: ' + monto + (moneda ? ', Moneda: ' + moneda : '')
    + ', Banco: ' + banco + ', Fecha: 23/11/2026, Referencia: ' + ref + ']';
  const v1 = revisar([{ id: 'F20', texto: CAPM('Bs 12.000,00', 'Banesco', '77020', 'VES') }, { id: 'C20', texto: CTA1 + SALTO + '12.000 Bs' }], null);
  chk(v1.estadoOperacion === 'completo', 'deposito Bs 12.000 y la cuenta "12.000 Bs": cuadra', '-> ' + v1.estadoOperacion);
  const v2 = revisar([{ id: 'F21', texto: CAPM('Bs 12.000,00', 'Banesco', '77021', 'VES') }, { id: 'C21', texto: CTA1 + SALTO + 'Bs 8.000' + SALTO + SALTO + CTA2 + SALTO + 'Bs 5.000' }], null);
  chk(v2.estadoOperacion === 'no_cuadra' && /12\.000 Bs/.test(v2.notaIA) && /13\.000 Bs/.test(v2.notaIA), 'deposito 12.000 Bs y las cuentas suman 13.000 Bs: NO cuadra', '-> ' + v2.notaIA.slice(60, 160));
  const v3 = revisar([{ id: 'F22', texto: CAPM('$100.000', 'Bancolombia', '77022', 'COP') }, { id: 'C22', texto: CTA1 + SALTO + '60.000 pesos' + SALTO + SALTO + CTA2 + SALTO + '$40.000' }], null);
  chk(v3.estadoOperacion === 'completo', 'deposito 100.000 COP = 60.000 pesos + $40.000 (pesos): cuadra', '-> ' + v3.estadoOperacion);
  const v4 = revisar([{ id: 'F23', texto: CAPM('$100.000', 'Bancolombia', '77023', 'COP') }, { id: 'C23', texto: CTA1 + SALTO + '90.000 COP' }], null);
  chk(v4.estadoOperacion === 'no_cuadra' && /100\.000 COP/.test(v4.notaIA), 'deposito 100.000 COP y la cuenta 90.000 COP: NO cuadra', '-> ' + v4.estadoOperacion);
  const v5 = revisar([{ id: 'F24', texto: CAPM('$100.000', 'Bancolombia', '77024') }, { id: 'C24', texto: CTA1 + SALTO + '100.000 cop' }], null);
  chk(v5.estadoOperacion === 'completo', 'sin "Moneda:" pero de Bancolombia: son pesos, y cuadra', '-> ' + v5.estadoOperacion);
  const v6 = revisar([{ id: 'F25', texto: CAPM('S/ 50,00', 'BCP', '77025', 'PEN') }, { id: 'C25', texto: CTA1 + SALTO + 'S/ 50' }], null);
  chk(v6.estadoOperacion === 'completo', 'deposito S/ 50 y la cuenta S/ 50: cuadra', '-> ' + v6.estadoOperacion);
  // Las demas monedas de la hoja (pedido de Kelvin: "que compare y las sume en las mismas monedas")
  const OTRAS = [
    ['ARS', '$50.000', 'Mercado Pago', '30.000 pesos', '$20.000', '$60.000'],
    ['PYG', 'Gs 500.000', 'Ueno', '300.000 gs', 'Gs 200.000', 'Gs 600.000'],
    ['DOP', 'RD$ 5.000', 'Banreservas', 'RD$ 3.000', '2.000 pesos', 'RD$ 6.000'],
    ['UYU', '$U 2.000', 'BROU', '$U 1.500', '500 pesos', '$U 2.500'],
    ['CLP', '$90.000', 'BancoEstado', '50.000 pesos', '$40.000', '$100.000'],
    ['MXN', '$1.500', 'Banorte', '1.000 pesos', '$500', '$2.000'],
    ['GTQ', 'Q 800', 'Banrural', 'Q 500', '300 quetzales', 'Q 900'],
    ['CRC', '₡ 50.000', 'BCR', '30.000 colones', '₡ 20.000', '₡ 60.000'],
    ['EUR', '100 €', 'Santander', '60 €', '40 euros', '120 €']];
  OTRAS.forEach(([mon, dep, banco, c1, c2, malo], i) => {
    const ok = revisar([{ id: 'FO' + i, texto: CAPM(dep, banco, '7710' + i, mon) }, { id: 'CO' + i, texto: CTA1 + SALTO + c1 + SALTO + SALTO + CTA2 + SALTO + c2 }], null);
    const no = revisar([{ id: 'FN' + i, texto: CAPM(dep, banco, '7720' + i, mon) }, { id: 'CN' + i, texto: CTA1 + SALTO + malo }], null);
    chk(ok.estadoOperacion === 'completo' && no.estadoOperacion === 'no_cuadra', mon + ': ' + dep + ' = ' + c1 + ' + ' + c2 + ' cuadra; contra ' + malo + ' NO',
        '-> ' + ok.estadoOperacion + ' / ' + no.estadoOperacion + (no.estadoOperacion === 'no_cuadra' ? '' : ' ' + JSON.stringify(no.notaIA.slice(0, 80))));
  });
  const sinCampo = revisar([{ id: 'FS1', texto: CAPM('RD$ 5.000', 'Banreservas', '77301') }, { id: 'CS1', texto: CTA1 + SALTO + 'RD$ 4.000' }], null);
  chk(sinCampo.estadoOperacion === 'no_cuadra', 'sin "Moneda:" el "RD$" dice que son pesos dominicanos (y se compara)', '-> ' + sinCampo.estadoOperacion);

  // Lo que NO se compara (no hay con que)
  const c3 = revisar([{ id: 'F9', texto: '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: Bs 12.000,00, Banco: Banesco, Fecha: 23/11/2026, Referencia: 77009]' },
                      { id: 'C12', texto: CTA1 + SALTO + '$10' }], null);
  chk(c3.estadoOperacion === 'completo', 'deposito en Bs y la cuenta en $: no se compara (no hay monto en Bs)', '-> ' + c3.estadoOperacion);
  const c4 = revisar([{ id: 'F10', texto: '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: $100.000, Banco: Bancolombia, Fecha: 23/11/2026, Referencia: 77010]' },
                      { id: 'C13', texto: CTA1 + SALTO + '$25' }], null);
  chk(c4.estadoOperacion === 'completo', '"$100.000" de Bancolombia y la cuenta "$25": otra moneda, no se compara', '-> ' + c4.estadoOperacion);
  const c5 = revisar([{ id: 'F11', texto: CAP('$100.000', '77011', ', Moneda: COP') }, { id: 'C14', texto: CTA1 + SALTO + '25 usd' }], null);
  chk(c5.estadoOperacion === 'completo', '"Moneda: COP" y la cuenta en "usd": no se compara', '-> ' + c5.estadoOperacion);
  const c6 = revisar([{ id: 'F12', texto: CAP('$10,00', '77012', ', Moneda: USD') }, { id: 'C15', texto: CTA1 + SALTO + '$15' }], null);
  chk(c6.estadoOperacion === 'no_cuadra', 'con "Moneda: USD" si se compara', '-> ' + c6.estadoOperacion);
  const c7 = revisar([{ id: 'F13', texto: CAP('no visible', '77013') }, { id: 'C16', texto: CTA1 + SALTO + '$15' }], null);
  chk(c7.estadoOperacion === 'completo', 'si no se leyo el monto de la captura: no se compara', '-> ' + c7.estadoOperacion);

  // De noche tambien se pregunta (no queda en espera algo que no cuadra)
  reloj = Date.parse('2026-11-24T03:00:00Z');   // 10:00 pm en Ecuador (cerrado)
  const d1 = revisar([{ id: 'F14', texto: CAP('$10,00', '77014') }, { id: 'C17', texto: CTA1 + SALTO + '$15' }], null);
  chk(d1.estadoOperacion === 'no_cuadra' && d1.enEspera === false, 'de noche tambien se pregunta (no queda en espera)', '-> ' + d1.estadoOperacion);
}

console.log('');
console.log('=== 5f) LA CUENTA VIENE EN EL PIE DE LA FOTO (caso real del 24/11) ===');
{
  // El cliente manda la captura y escribe la cuenta destino en el pie de la MISMA foto. Antes el pie se
  // descartaba: el bot contestaba "Pasame la cuenta destino" teniendola ahi.
  reloj = Date.parse('2026-11-24T15:00:00Z');   // 10:00 am en Ecuador (abierto)
  const PIE = 'Tipo de cuenta: VES' + SALTO + '01020000000000012345' + SALTO + 'V11111111' + SALTO + '200$';
  const imagen = (resumen, caption, id) => {
    const $ = (n) => {
      if (n === 'Leer Imagen') return { item: { json: { content: JSON.stringify({ tipo: 'comprobante', resumen }) } } };
      if (n === 'Webhook Evolution API') return { first: () => ({ json: { body: { data: { key: { id }, message: { imageMessage: { caption } } } } } }) };
      return { item: { json: {} }, first: () => ({ json: {} }) };
    };
    return new Function('$', code('Texto de Imagen'))($)[0].json.texto;
  };
  const RES = 'Monto: $200,00, Moneda: USD, Banco: Banco Guayaquil, Fecha: 24/11/2026, Referencia: 55001122';
  const t = imagen(RES, PIE, 'IMGPIE1');
  chk(t.indexOf('[El cliente envio un COMPROBANTE') === 0 && t.endsWith(SALTO + PIE), 'el pie de foto va a continuacion de la nota de la captura', '-> ' + JSON.stringify(t.slice(-70)));
  chk(imagen(RES, '', 'IMGPIE2').endsWith(']') && imagen(RES, undefined, 'IMGPIE3').endsWith(']'), 'una foto SIN pie queda igual que siempre');
  const cuenta = new Function('$', code('Texto de Imagen'))(n => n === 'Leer Imagen' ? { item: { json: { content: '{"tipo":"cuenta","resumen":"Banco: X"}' } } } : { first: () => ({ json: { body: { data: { key: { id: 'I4' }, message: { imageMessage: { caption: 'para mi pana' } } } } } }) })[0].json.texto;
  chk(/CUENTA bancaria/.test(cuenta) && cuenta.endsWith(SALTO + 'para mi pana'), 'una foto de cuenta con pie: tambien se conserva el pie');

  // Y el bot lo entiende: captura + cuenta en el MISMO mensaje, sin que pida la cuenta
  const r = revisar([{ id: 'IMG1', texto: t }], null);
  chk(r.estadoOperacion === 'completo', 'captura con la cuenta en el pie: COMPLETO (no pide la cuenta)', '-> ' + r.estadoOperacion + ' ' + r.notaIA.slice(-60));
  chk(/Listo, recibido/.test(r.notaIA) && detectar(r).length === 1, 'le dice "recibido" y se pasa a transferir');
  const sep = separar(r, detectar(r)[0].json);
  chk(sep.length === 1 && sep[0].monto === 200 && /01020000000000012345/.test(sep[0].cuenta), 'a transferir va UNA cuenta con su monto ($200)', '-> ' + JSON.stringify(sep.map(x => x.monto)));
  // el pie tambien cuenta para el cuadre del deposito
  const mal = revisar([{ id: 'IMG2', texto: imagen(RES.replace('$200,00', '$150,00').replace('55001122', '55001133'), PIE, 'IMGPIE5') }], null);
  chk(mal.estadoOperacion === 'no_cuadra' && /\$150 pero la cuenta dice \$200/.test(mal.notaIA), 'y cuadra contra el deposito: $150 vs $200 NO cuadra', '-> ' + mal.estadoOperacion);
  // el comentario del cliente que viene despues, aparte
  const r2 = revisar([{ id: 'IMG3', texto: imagen(RES.replace('55001122', '55001144'), PIE, 'IMGPIE6') }, { id: 'TX1', texto: 'Buenos días amigo. Ayúdame con ese envío por favor.' }], null);
  chk(r2.estadoOperacion === 'completo', 'si despues escribe "ayudame con ese envio": sigue COMPLETO', '-> ' + r2.estadoOperacion);
  // sin pie: sigue pidiendo la cuenta
  const s = revisar([{ id: 'IMG4', texto: imagen(RES.replace('55001122', '55001155'), '', 'IMGPIE7') }], null);
  chk(s.estadoOperacion === 'falta_cuenta', 'sin pie ni cuenta: sigue pidiendo la cuenta', '-> ' + s.estadoOperacion);

  // El pie tiene que SER una cuenta: "buenos dias" u otra charla no lo es (pedido de Kelvin, 24/11)
  let n = 60;
  const conPie = pie => revisar([{ id: 'IMGX' + (++n), texto: imagen(RES.replace('55001122', '5500' + n), pie, 'IMGPIE' + n) }], null);
  for (const charla of ['Buenos días', 'buens dias amigo', 'Hola, aquí mi pago', 'Para la cuenta de mi mamá', 'Ayúdame con ese envío por favor', 'gracias 🙏', 'Ya hice el depósito, ¿me confirmas?', 'Banco de Venezuela']) {
    const r = conPie(charla);
    chk(r.estadoOperacion === 'falta_cuenta' && r.op.cuenta === null, 'el pie "' + charla + '" NO es una cuenta: sigue pidiendo la cuenta', '-> ' + r.estadoOperacion);
  }
  for (const cuentaPie of ['Pago móvil 04141234567 V12345678 Ana Prueba 200$', 'Banesco 0134 123456 Juan V123 $200', 'ana.prueba@example.com Zelle $200', 'Binance ID 82349723 $200', 'Tipo de cuenta: VES' + SALTO + '01020000000000099999' + SALTO + 'V22222222' + SALTO + '200$']) {
    const r = conPie(cuentaPie);
    chk(r.estadoOperacion === 'completo', 'el pie "' + cuentaPie.replace(/\n/g, ' / ').slice(0, 44) + '" SI es una cuenta: COMPLETO', '-> ' + r.estadoOperacion);
  }
  // charla en el pie + la cuenta en un mensaje aparte: sigue funcionando como siempre
  const sep2 = revisar([{ id: 'IMGY1', texto: imagen(RES.replace('55001122', '55009001'), 'Buenos días', 'IMGPIEY') }, { id: 'TXY1', texto: '01020000000000099999' + SALTO + 'V22222222' + SALTO + '$200' }], null);
  chk(sep2.estadoOperacion === 'completo', 'saludo en el pie y la cuenta en otro mensaje: COMPLETO', '-> ' + sep2.estadoOperacion);
}

console.log('');
console.log('=== 6) COMO QUEDA CABLEADO ===');
{
  const c = wf.connections;
  const sig = n => ((c[n] && c[n].main && c[n].main[0]) || []).map(x => x.node).join(',');
  chk(sig('Code in JavaScript') === 'Redis Leer Operacion', 'Code in JavaScript -> Redis Leer Operacion');
  chk(sig('Redis Leer Operacion') === 'Redis Leer Pregunta' && sig('Redis Leer Pregunta') === 'Consultar Operaciones WhatsApp'
      && sig('Consultar Operaciones WhatsApp') === 'Revisar Operacion',
      'Redis Leer Operacion -> Leer Pregunta -> Consultar Operaciones -> Revisar Operacion');
  chk(sig('Revisar Operacion') === 'Redis Guardar Operacion', 'Revisar Operacion -> Redis Guardar Operacion');
  // Entre los dos esta "¿Qué Responder?" (gracias -> sticker, ok suelto -> nada); lo demas, a la IA.
  const respaldo = ((c['¿Qué Responder?'] || {}).main || [])[2] || [];
  chk(sig('Redis Guardar Operacion').split(',')[0] === '¿Qué Responder?' && respaldo.map(x => x.node).join() === 'AI Agent',
      'Redis Guardar Operacion -> ¿Qué Responder? -> AI Agent');
  const txt = nodo('AI Agent').parameters.text;
  chk(/notaIA/.test(txt) && /Huella/.test(txt), 'el agente recibe la nota y no ve la huella');
  chk(/ESTADO DE LA OPERACION/.test(nodo('AI Agent').parameters.options.systemMessage), 'el prompt explica la nota');
  chk(/idImagen/.test(nodo('Re-descargar Imagen').parameters.jsonBody), 'se baja la foto de la captura, no la ultima imagen');
  chk(nodo('Redis Guardar Operacion').parameters.ttl === 172800, 'lo pendiente vive en Redis 48 h', '-> ' + nodo('Redis Guardar Operacion').parameters.ttl);
}

console.log('');
console.log(fallos ? (fallos + ' fallaron') : 'Todas las pruebas pasaron');
process.exit(fallos ? 1 : 0);
