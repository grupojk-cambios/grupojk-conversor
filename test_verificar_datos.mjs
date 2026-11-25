
const _strip = s => s ? String(s).replace(/^\d+[\w\.]*\s*/, '') : '';
const _findNode = (nodes, n) => (nodes || []).find(x => x.name === n || _strip(x.name) === _strip(n));
const _getConn = (conns, n) => {
  if (!conns) return null;
  const k = Object.keys(conns).find(x => x === n || _strip(x) === _strip(n));
  return k ? Reflect.get(conns, k) : null;
};
// Prueba de "VERIFICAR DATOS" (pedido de Kelvin, 23/11).
//
// Lo que paso: la operadora cito en transferir la cuenta de una clienta con "Verificar datos" (le faltaba
// el banco). El bot no hizo nada y la clienta no se entero. Ahora:
//   1. la operadora cita la publicacion de una cuenta con "verificar", "corregir dato", "datos malos"...
//   2. el bot le escribe al cliente: lo que indico la operadora + esos datos + "corrígelos y envíamelos"
//      (y en el grupo: "Listo, le pedí a ... que verifique")
//   3. el cliente manda los datos corregidos -> el bot los publica en transferir como CORREGIDOS, y la
//      foto de la operadora sobre esa publicacion le llega al cliente como siempre.
// Ademas: "Verificar" (9 letras) citando NUNCA se toma como "entregar la foto".
//
// Todos los datos son INVENTADOS. Correr con:  node test_verificar_datos.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const wfOp = JSON.parse(readFileSync('workflow_operadoras.json', 'utf8').replace(/^﻿/, ''));
const wfPub = JSON.parse(readFileSync('workflow_operacion_publicar.json', 'utf8').replace(/^﻿/, ''));
const wfIa = JSON.parse(readFileSync('workflow_ia_atencion.json', 'utf8').replace(/^﻿/, ''));
const nodo = n => _findNode(wf.nodes, n) || _findNode(wfOp.nodes, n) || _findNode(wfPub.nodes, n) || _findNode(wfIa.nodes, n);
const code = n => nodo(n).parameters.jsCode;
const SALTO = String.fromCharCode(10);
const GRUPO_TRANSFERIR = '593961230380-1601657528@g.us';
const CLIENTE = '593990000001@s.whatsapp.net';

let fallos = 0;
const chk = (ok, etiqueta, detalle) => { if (!ok) fallos++; console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(72) + ' ' + (detalle || '')); };

// "Solo Estos Numeros" con un mensaje del grupo de transferir
function soloEstos(mensaje, contextInfo) {
  const ahora = Math.floor(Date.now() / 1000);
  const items = [{ json: { body: { data: { key: { remoteJid: GRUPO_TRANSFERIR, fromMe: false, id: 'A5OPERADORA0001', participant: '111@lid' },
                                          message: mensaje, contextInfo, messageTimestamp: ahora } } } }];
  const $ = n => {
    if (n === 'Webhook Evolution API' || _strip(n) === 'Webhook Evolution API') return { all: () => items, first: () => items[0] };
    if (n === 'Grupos Mayor' || _strip(n) === 'Grupos Mayor') return { all: () => [] };
    return { all: () => [{ json: {} }], first: () => ({ json: {} }) };
  };
  return new Function('$input', '$', code('Solo Estos Numeros'))({ all: () => [{ json: {} }] }, $).map(i => i.json);
}
const PUBLICACION = 'Ana Prueba - $10' + SALTO + SALTO + '9999999.' + SALTO + 'Telef 04120000000 Venezuela' + SALTO + 'Maria Prueba' + SALTO + '$10';
const citando = (texto, quoted) => ({ stanzaId: '3EB0PUBLICACION01', participant: '593961230380@s.whatsapp.net', quotedMessage: quoted === undefined ? { conversation: PUBLICACION } : quoted });

console.log('=== 1) LA OPERADORA ESCRIBE "VERIFICAR" CITANDO LA CUENTA ===');
{
  const r = soloEstos({ conversation: 'Verificar datos' }, citando());
  chk(r.length === 1 && r[0].accionPausa === 'verificar' && r[0].stanzaId === '3EB0PUBLICACION01' && r[0].claveGrupoMsg === 'grupoMsg:3EB0PUBLICACION01',
      '"Verificar datos" citando la cuenta: VERIFICAR', '-> ' + JSON.stringify(r.map(x => x.accionPausa)));
  chk(r[0].nota === 'Verificar datos' && /Maria Prueba/.test(r[0].citadoTexto) && r[0].idNota === 'A5OPERADORA0001', 'lleva lo que escribio la operadora y la cuenta citada');
  const corto = soloEstos({ conversation: 'Verificar' }, citando());
  chk(corto[0] && corto[0].accionPausa === 'verificar', '"Verificar" (9 letras) es VERIFICAR, no "entregar la foto"', '-> ' + (corto[0] && corto[0].accionPausa));
  for (const t of ['corregir dato', 'Corregir cédula', 'datos malos', 'el dato está errado', 'datos incorrectos', 'no coincide el nombre', 'rebotó']){
    const x = soloEstos({ extendedTextMessage: { text: t } }, citando());
    chk(x[0] && x[0].accionPausa === 'verificar', '"' + t + '": VERIFICAR', '-> ' + (x[0] && x[0].accionPausa));
  }
  const foto = soloEstos({ conversation: 'Verificar' }, citando('Verificar', { imageMessage: {} }));
  chk(foto.length === 0, '"Verificar" citando la FOTO de la captura: no hace nada (ni entrega la foto)', '-> ' + JSON.stringify(foto.map(x => x.accionPausa)));
  const punto = soloEstos({ conversation: '.' }, citando());
  chk(punto[0] && punto[0].accionPausa === 'entregar', 'un "." citando sigue siendo ENTREGAR (como siempre)', '-> ' + (punto[0] && punto[0].accionPausa));
  const ok = soloEstos({ conversation: 'ok' }, citando());
  chk(ok[0] && ok[0].accionPausa === 'entregar', 'un "ok" citando sigue siendo ENTREGAR');
  const charla = soloEstos({ conversation: 'nena esta la hago despues de almuerzo' }, citando());
  chk(charla.length === 0, 'una charla larga citando: nada (como siempre)');
}

console.log('');
console.log('=== 2) EL BOT LE PIDE AL CLIENTE QUE CORRIJA ===');
const BASE = soloEstos({ conversation: 'Verificar datos' }, citando())[0];
const PEDIDO = { jid: CLIENTE, nombre: 'Ana Prueba', idCuenta: 'A5CUENTA01', idCaptura: 'A5CAPTURA01' };
function prepararCorregir(pedido, base) {
  const $ = n => {
    if (n === 'Cuando lo Llama el Bot' || _strip(n) === 'Cuando lo Llama el Bot') return { first: () => ({ json: base || BASE }) };
    if (n === 'Redis Leer Publicacion Verificar' || _strip(n) === 'Redis Leer Publicacion Verificar') return { first: () => ({ json: { pedido: pedido === null ? null : JSON.stringify(pedido) } }) };
    throw new Error('nodo inesperado: ' + n);
  };
  return new Function('$', code('Preparar Corregir Datos'))($).map(i => i.json);
}
{
  const r = prepararCorregir(PEDIDO)[0];
  chk(r && r.jid === CLIENTE && r.publicacion === '3EB0PUBLICACION01', 'se le escribe al CLIENTE de esa publicacion', '-> ' + (r && r.jid));
  chk(/Nos indican: \*Verificar datos\*/.test(r.mensaje) && /Telef 04120000000 Venezuela/.test(r.mensaje) && /corrígelos y envíamelos de nuevo/.test(r.mensaje),
      'el mensaje: lo que indico la operadora + los datos + "corrígelos y envíamelos"', '-> ' + JSON.stringify(r.mensaje));
  chk(!/Ana Prueba - \$10/.test(r.mensaje), 'sin la cabecera interna "Nombre - $10"');
  chk(r.cabecera === 'Ana Prueba - $10' && r.idNota === 'A5OPERADORA0001' && /Listo, le pedí a Ana Prueba/.test(r.confirmacion), 'y en el grupo: "Listo, le pedí a ... que verifique"');
  chk(prepararCorregir(null).length === 0, 'si lo citado NO es una publicacion del bot: no pasa nada');
  const re = prepararCorregir(Object.assign({}, PEDIDO, { publicacion: '3EB0ORIGINAL00' }))[0];
  chk(re.publicacion === '3EB0ORIGINAL00', 'si citaron una correccion: se sigue usando la publicacion ORIGINAL');

  const $m = n => {
    if (n === 'Preparar Corregir Datos' || _strip(n) === 'Preparar Corregir Datos') return { first: () => ({ json: r }) };
    if (n === 'Redis Leer Op Corregir' || _strip(n) === 'Redis Leer Op Corregir') return { first: () => ({ json: { operacion: JSON.stringify({ hechos: [{ ref: '1' }], ultimoSaludo: 5 }) } }) };
    throw new Error('nodo inesperado: ' + n);
  };
  const m = new Function('$', code('Marcar Corregir Datos'))($m)[0].json;
  const op = JSON.parse(m.operacionNueva);
  chk(op.corregir && op.corregir.publicacion === '3EB0PUBLICACION01' && op.corregir.nota === 'Verificar datos' && op.hechos.length === 1 && op.ultimoSaludo === 5,
      'en la operacion del cliente queda "corregir" (sin borrar lo demas)', '-> ' + JSON.stringify(op.corregir).slice(0, 90));
}

console.log('');
console.log('=== 3) EL CLIENTE MANDA LOS DATOS CORREGIDOS ===');
let reloj = Date.parse('2026-11-23T18:10:00Z');   // 1:10 pm en Ecuador
function revisar(mensajes, op) {
  const real = Date.now; Date.now = () => reloj;
  try {
    const $ = n => {
      if (n === 'Code in JavaScript' || _strip(n) === 'Code in JavaScript') return { first: () => ({ json: { cuentas: [], sessionId: 'chat', modo: 'detal' } }) };
      if (n === 'Cuando lo Llama el Bot' || _strip(n) === 'Cuando lo Llama el Bot') return { first: () => ({ json: { mensajes } }) };
      if (n === 'Combinar' || _strip(n) === 'Combinar') return { first: () => ({ json: { mensajes } }) };
      if (n === 'Redis Leer Operacion' || _strip(n) === 'Redis Leer Operacion') return { first: () => ({ json: { operacion: op ? JSON.stringify(op) : null } }) };
      throw new Error('nodo inesperado: ' + n);
    };
    const r = new Function('$', code('Revisar Operacion'))($)[0].json;
    r.op = JSON.parse(r.operacionNueva);
    return r;
  } finally { Date.now = real; }
}
const CORREGIR = { ts: Date.parse('2026-11-23T18:07:00Z'), publicacion: '3EB0PUBLICACION01', nombre: 'Ana Prueba', cabecera: 'Ana Prueba - $10',
                   idCaptura: 'A5CAPTURA01', nota: 'Verificar datos', datos: '9999999. Telef 04120000000 Venezuela Maria Prueba $10' };
const CORREGIDA = 'Banco Venezuela' + SALTO + 'Telef 04120000000' + SALTO + 'CI 9999999' + SALTO + 'Maria Prueba' + SALTO + '$10';
{
  const r = revisar([{ id: 'A5NUEVA01', texto: CORREGIDA }], { corregir: CORREGIR, hechos: [] });
  chk(r.estadoOperacion === 'correccion', 'manda la cuenta corregida: CORRECCION', '-> ' + r.estadoOperacion);
  chk(/datos corregidos/.test(r.notaIA) && /Ya se lo pasé a la operadora/.test(r.notaIA), 'le contesta "Listo, recibido ✅ Ya se lo pasé a la operadora..."');
  chk(r.correccion && r.correccion.publicacion === '3EB0PUBLICACION01' && r.correccion.idCuenta === 'A5NUEVA01' && /Banco Venezuela/.test(r.correccion.texto),
      'arma la correccion con la publicacion original y los datos nuevos', '-> ' + JSON.stringify(r.correccion).slice(0, 100));
  chk(!r.op.corregir && r.textoAprobar === '', 'la marca se borra y NO se trata como una operacion nueva');
  const solo = revisar([{ id: 'A5NUEVA02', texto: 'el banco es Banesco' }], { corregir: CORREGIR, hechos: [] });
  chk(solo.estadoOperacion === 'correccion', 'aunque corrija solo un dato ("el banco es Banesco"): CORRECCION', '-> ' + solo.estadoOperacion);
  const pregunta = revisar([{ id: 'A5PREG', texto: 'que esta mal?' }], { corregir: CORREGIR, hechos: [] });
  chk(pregunta.estadoOperacion === 'nada' && /revise bien los datos/.test(pregunta.notaIA) && pregunta.op.corregir, 'si pregunta "¿que esta mal?": le explica, y la marca sigue', '-> ' + pregunta.notaIA.slice(-80));
  const nueva = revisar([{ id: 'F1', texto: '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: $20,00, Moneda: USD, Banco: Pichincha, Fecha: 23/11/2026, Referencia: 88001]' },
                         { id: 'C1', texto: '0134 7654321 04140000000' + SALTO + '$20' }], { corregir: CORREGIR, hechos: [] });
  chk(nueva.estadoOperacion === 'completo' && !nueva.correccion && !nueva.op.corregir, 'si manda captura + cuenta: es una operacion NUEVA (y la marca se borra)', '-> ' + nueva.estadoOperacion);
  const vieja = revisar([{ id: 'A5NUEVA03', texto: CORREGIDA }], { corregir: Object.assign({}, CORREGIR, { ts: reloj - 13 * 3600000 }), hechos: [] });
  chk(vieja.estadoOperacion === 'falta_captura', 'pasadas 12 horas la marca ya no vale (la cuenta es para otra operacion)', '-> ' + vieja.estadoOperacion);
}

console.log('');
console.log('=== 4) LA CORRECCION VA A TRANSFERIR ===');
{
  const ro = revisar([{ id: 'A5NUEVA01', texto: CORREGIDA }], { corregir: CORREGIR, hechos: [] });
  const $ = n => {
    if (n === 'Revisar Operacion' || _strip(n) === 'Revisar Operacion') return { first: () => ({ json: ro }) };
    if (n === 'Cuando lo Llama el Bot' || _strip(n) === 'Cuando lo Llama el Bot') return { first: () => ({ json: { jid: CLIENTE } }) };
    if (n === 'Prep Debounce' || _strip(n) === 'Prep Debounce') return { first: () => ({ json: { jid: CLIENTE } }) };
    throw new Error('nodo inesperado: ' + n);
  };
  const p = new Function('$', code('Preparar Correccion'))($)[0].json;
  chk(/^✏️ DATOS CORREGIDOS \(la operadora pidió: Verificar datos\)/.test(p.texto) && p.texto.split(SALTO)[1] === 'Ana Prueba - $10' && /Banco Venezuela/.test(p.texto),
      'se publica: "✏️ DATOS CORREGIDOS" + "Nombre - $10" + los datos nuevos', '-> ' + JSON.stringify(p.texto));
  chk(p.jid === CLIENTE && p.publicacion === '3EB0PUBLICACION01' && p.idCuenta === 'A5NUEVA01' && p.monto === 10, 'con el cliente, la publicacion original y el monto');
  const sinNada = new Function('$', code('Preparar Correccion'))(n => n === 'Revisar Operacion' ? { first: () => ({ json: { correccion: null } }) } : { first: () => ({ json: { jid: CLIENTE } }) });
  chk(sinNada.length === 0, 'si no hay correccion: no publica nada');

  const d = new Function('$', code('Datos Correccion Supabase'))(n => ({ first: () => ({ json: p }) }))[0].json;
  chk(JSON.stringify(Object.keys(d).sort()) === '["cuentas","notas"]' && d.cuentas[0].texto === p.datos && d.cuentas[0].monto === 10 && /Verificar datos/.test(d.notas),
      'Supabase: la fila queda con los datos corregidos (solo cuentas y notas)', '-> ' + JSON.stringify(d).slice(0, 100));
  const sb = nodo('Corregir Cuenta en Supabase').parameters;
  chk(sb.operation === 'update' && sb.dataToSend === 'autoMapInputData' && /id_msgs_grupo=cs\./.test(sb.filterString) && /Cuando lo Llama el Bot/.test(sb.filterString),
      'se actualiza la fila de la publicacion ORIGINAL');
  const rg = nodo('Redis Guardar Publicacion Correccion').parameters;
  chk(/publicacion: \$\("Cuando lo Llama el Bot"\)\.first\(\)\.json\.publicacion/.test(rg.value) && /grupoMsg:/.test(rg.key),
      'la publicacion corregida queda apuntando al cliente y a la publicacion original');
  chk(nodo('Publicar Correccion').parameters.jsonBody.indexOf(GRUPO_TRANSFERIR) !== -1, 'y se publica en el grupo de transferir');
}

console.log('');
console.log('=== 5) LA FOTO DE LA OPERADORA SOBRE LA CORRECCION LE LLEGA AL CLIENTE ===');
{
  const mapa = { jid: CLIENTE, nombre: 'Ana Prueba', idCuenta: 'A5NUEVA01', idCaptura: 'A5CAPTURA01', publicacion: '3EB0PUBLICACION01' };
  const base = { stanzaId: '3EB0CORRECCION01', claveEntregado: 'entregado:3EB0CORRECCION01', idFoto: 'A5FOTO01', jidGrupo: GRUPO_TRANSFERIR };
  const $ = n => {
    if (n === 'Cuando lo Llama el Bot' || _strip(n) === 'Cuando lo Llama el Bot') return { first: () => ({ json: base }) };
    if (n === 'Redis Leer Publicacion' || _strip(n) === 'Redis Leer Publicacion') return { first: () => ({ json: { pedido: JSON.stringify(mapa) } }) };
    if (n === 'Redis Leer Entregado' || _strip(n) === 'Redis Leer Entregado') return { first: () => ({ json: {} }) };
    if (n === 'Redis Leer Ultima Foto' || _strip(n) === 'Redis Leer Ultima Foto') return { first: () => ({ json: {} }) };
    throw new Error('nodo inesperado: ' + n);
  };
  const r = new Function('$', code('Revisar Pedido'))($)[0].json;
  chk(r.accion === 'entregar' && r.jid === CLIENTE && r.idFoto === 'A5FOTO01' && r.idCuenta === 'A5NUEVA01', 'se le entrega al cliente, citando su mensaje corregido', '-> ' + JSON.stringify([r.accion, r.jid, r.idCuenta]));
  chk(r.stanzaId === '3EB0PUBLICACION01' && r.claveEntregado === 'entregado:3EB0PUBLICACION01', 'y cuenta como la publicacion ORIGINAL (su fila de Supabase se marca enviada)');
}

console.log('');
console.log('=== 6) CABLEADO ===');
{
  const c = wf.connections;
  const cOp = wfOp.connections;
  const cPub = wfPub.connections;
  const cIa = wfIa.connections;
  const sig = (n, i, mapa) => { const m = mapa || c; const conn = _getConn(m, n); return ((conn && conn.main && conn.main[i || 0]) || []).map(x => _strip(x.node)).join(','); };
  const reglas = nodo('Router Pausa').parameters.rules.values.map(v => v.outputKey);
  chk(reglas[7] === 'verificar' && sig('Router Pausa', 7) === 'Ejecutar Operadoras', 'Router Pausa: la salida "verificar" (la ultima) -> Ejecutar Operadoras');
  chk(sig('Router Operadoras', 2, cOp) === 'Redis Leer Publicacion Verificar', 'Router Operadoras: salida "verificar" (2) -> Redis Leer Publicacion Verificar');
  chk(sig('Redis Leer Publicacion Verificar', 0, cOp) === 'Preparar Corregir Datos' && sig('Preparar Corregir Datos', 0, cOp) === 'Redis Leer Op Corregir'
      && sig('Redis Leer Op Corregir', 0, cOp) === 'Marcar Corregir Datos' && sig('Marcar Corregir Datos', 0, cOp) === 'Redis Guardar Op Corregir'
      && sig('Redis Guardar Op Corregir', 0, cOp) === 'Pedir Corregir al Cliente' && sig('Pedir Corregir al Cliente', 0, cOp) === 'Confirmar Verificar en Grupo',
      'verificar: publicacion -> preparar -> op del cliente -> marcar -> guardar -> cliente -> grupo');
  chk(/Preparar Corregir Datos.*\.jid/.test(nodo('Pedir Corregir al Cliente').parameters.remoteJid), 'el mensaje va al chat del CLIENTE');
  chk(/idNota/.test(nodo('Confirmar Verificar en Grupo').parameters.jsonBody) && /jidGrupo/.test(nodo('Confirmar Verificar en Grupo').parameters.jsonBody),
      'la confirmacion va al grupo, citando lo que escribio la operadora');
  chk(sig('Redis Guardar Operacion', 0, cIa).split(',').indexOf('Preparar Correccion') !== -1 && sig('Preparar Correccion', 0, cIa) === 'Ejecutar Publicacion'
      && sig('Router Publicacion', 1, cPub) === 'Publicar Correccion'
      && sig('Publicar Correccion', 0, cPub) === 'Redis Guardar Publicacion Correccion' && sig('Redis Guardar Publicacion Correccion', 0, cPub) === 'Datos Correccion Supabase'
      && sig('Datos Correccion Supabase', 0, cPub) === 'Corregir Cuenta en Supabase', 'correccion: preparar -> Ejecutar Publicacion -> publicar -> Redis -> Supabase');
  chk(sig('Redis Guardar Operacion', 0, cIa).split(',')[0] === '¿Qué Responder?', 'la respuesta al cliente sigue siendo la primera rama');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
