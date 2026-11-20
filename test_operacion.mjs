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
const nodo = n => wf.nodes.find(x => x.name === n);
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

let reloj = Date.parse('2026-11-20T22:00:00Z');
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
  const $ = (n) => {
    if (n === 'Detectar Aprobación') return { item: { json: ap } };
    if (n === 'Revisar Operacion') return { first: () => ({ json: ro }) };
    if (n === 'Combinar') return { item: { json: { mensajes: [] } } };
    return { item: { json: {} } };
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
  reloj = Date.parse('2026-11-20T23:00:00Z');
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
  reloj = Date.parse('2026-11-21T10:00:00Z');
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
  reloj = Date.parse('2026-11-21T12:00:00Z');
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
console.log('=== 6) COMO QUEDA CABLEADO ===');
{
  const c = wf.connections;
  const sig = n => ((c[n] && c[n].main && c[n].main[0]) || []).map(x => x.node).join(',');
  chk(sig('Code in JavaScript') === 'Redis Leer Operacion', 'Code in JavaScript -> Redis Leer Operacion');
  chk(sig('Redis Leer Operacion') === 'Revisar Operacion', 'Redis Leer Operacion -> Revisar Operacion');
  chk(sig('Revisar Operacion') === 'Redis Guardar Operacion', 'Revisar Operacion -> Redis Guardar Operacion');
  chk(sig('Redis Guardar Operacion') === 'AI Agent', 'Redis Guardar Operacion -> AI Agent');
  const txt = nodo('AI Agent').parameters.text;
  chk(/notaIA/.test(txt) && /Huella/.test(txt), 'el agente recibe la nota y no ve la huella');
  chk(/ESTADO DE LA OPERACION/.test(nodo('AI Agent').parameters.options.systemMessage), 'el prompt explica la nota');
  chk(/idImagen/.test(nodo('Re-descargar Imagen').parameters.jsonBody), 'se baja la foto de la captura, no la ultima imagen');
  chk(nodo('Redis Guardar Operacion').parameters.ttl === 172800, 'lo pendiente vive en Redis 48 h', '-> ' + nodo('Redis Guardar Operacion').parameters.ttl);
}

console.log('');
console.log(fallos ? (fallos + ' fallaron') : 'Todas las pruebas pasaron');
process.exit(fallos ? 1 : 0);
