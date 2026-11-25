// Prueba de los CIERRES de conversacion: "gracias", "ok" sueltos y mensajes sin texto.
// Tambien: el nombre del cliente una sola vez cada 24 h y el pais por el prefijo del numero.
//
// Lo que lo motivo (revision de los chats, 20/11): el 20% de lo que escriben los clientes es
// "gracias" u "ok". Todo pasaba por la IA, que contestaba con frases de relleno ("Aqui estoy
// para lo que necesites 😊") y repetia el nombre del cliente en cada mensaje.
//
// Ahora:
//   - "gracias" (y parecidos)   -> sticker A SU ORDEN, sin IA, como mucho 1 cada 10 min
//   - "ok", "listo", "perfecto" -> nada, salvo que el ultimo mensaje del bot fuera una pregunta
//   - un mensaje sin texto       -> nada
//   - todo lo demas              -> la IA, como siempre
//
// Todos los datos de esta prueba son INVENTADOS: el repositorio es publico.
//
// Correr con:  node test_cierres.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const wfIa = JSON.parse(readFileSync('workflow_ia_atencion.json', 'utf8').replace(/^﻿/, ''));
const wfDeb = JSON.parse(readFileSync('workflow_debounce_admin.json', 'utf8').replace(/^﻿/, ''));
const nodo = n => wf.nodes.find(x => x.name === n) || wfIa.nodes.find(x => x.name === n) || wfDeb.nodes.find(x => x.name === n);
const code = n => nodo(n).parameters.jsCode;
const SALTO = String.fromCharCode(10);

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(70) + ' ' + (detalle || ''));
};

const NUESTRAS = [
  { Pais: 'Ecuador', Metodo: 'Pichincha', Datos: '*CUENTA AUTORIZADA USD*\n\n1) 2200000001\n*Pichincha ahorro*\nC.I: 0900000001\n*Titular Empresa*' }
];

let reloj = Date.parse('2026-11-21T15:00:00Z');
const pasan = minutos => { reloj += minutos * 60000; };

// ex.pregunta: '1' = el ultimo mensaje del bot fue una pregunta, '0' = no, null = no hay dato,
// 'CAIDA' = Redis no respondio.
function revisar(textos, op, ex) {
  ex = ex || {};
  const mensajes = textos.map((t, i) => ({ id: 'M' + i, texto: t }));
  const real = Date.now; Date.now = () => reloj;
  try {
    const $ = (n) => {
      if (n === 'Code in JavaScript') return { first: () => ({ json: { cuentas: NUESTRAS, modo: 'detal', sessionId: 'chat',
        nombreCliente: (ex.nombre === undefined ? 'Ana Prueba' : ex.nombre) } }) };
      if (n === 'Cuando lo Llama el Bot') return { first: () => ({ json: { mensajes } }) };
      if (n === 'Combinar') return { first: () => ({ json: { mensajes } }) };
      if (n === 'Redis Leer Operacion') return { first: () => ({ json: { operacion: op ? JSON.stringify(op) : null } }) };
      if (n === 'Redis Leer Pregunta') {
        if (ex.pregunta === 'CAIDA') return { first: () => ({ json: { error: { message: 'Redis no responde' } } }) };
        return { first: () => ({ json: { pregunta: (ex.pregunta === undefined ? null : ex.pregunta) } }) };
      }
      throw new Error('nodo inesperado: ' + n);
    };
    const r = new Function('$', code('Revisar Operacion'))($)[0].json;
    r.op = JSON.parse(r.operacionNueva);
    return r;
  } finally { Date.now = real; }
}
const accion = (t, ex) => revisar(Array.isArray(t) ? t : [t], null, ex).accion;

const captura = (monto, ref) => '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: $' + monto
  + ', Banco: Pichincha, Fecha: nov 21, 2026, Numero de transaccion: ' + ref + ']';
const CUENTA = ['Banco Ejemplo', '01020000000000099999', 'Pedro Prueba', 'V 11111111', '$50'].join(SALTO);

console.log('=== 1) AGRADECIMIENTOS -> sticker A SU ORDEN ===');
for (const t of ['gracias', 'Gracias 🫂', 'Muchas gracias', 'Dale gracias', 'Ok gracias', 'ok amigo gracias',
                 'Gracias mi pana', 'Listo gracias', 'Graciaaaas', 'Mil gracias!!', 'Te agradezco', 'Muy agradecido',
                 'Muy amable', '🙏', '🙏🏽', 'Gracias ya me llegó 👍🏻', 'ah ok esta bien gracias',
                 'Listo mijo muchas gracias !!', 'jajaja gracias', 'Gracias, bendiciones', 'Gracias hasta mañana 🫱🏻‍🫲🏻',
                 'Muchas gracias, Dios le bendiga', 'gracias kelvin', 'thanks', 'ok ok gracias muchas gracias.']) {
  const a = accion(t);
  chk(a === 'gracias', JSON.stringify(t), '-> ' + a);
}
{
  const a = accion(['ok', 'gracias']);
  chk(a === 'gracias', 'dos mensajes juntos: "ok" + "gracias"', '-> ' + a);
  const b = accion('[el cliente respondio citando esto que tu/asesor le dijiste antes: "Te paso la cuenta?"]' + SALTO + 'gracias');
  chk(b === 'gracias', 'citando un mensaje del bot (con "?" adentro) y "gracias"', '-> ' + b);
}

console.log('');
console.log('=== 2) NO son agradecimientos -> la IA (preguntas normales, lección del 20/11) ===');
for (const t of ['Bien gracias a Dios', 'bien gracias a dios y ustedes!', 'Hola no gracias', 'Gracias, pero no me ha llegado',
                 'gracias rey mañana le paso', 'a esta porfa gracias', 'gracias, cual es la tasa hoy?', 'Gracias ¿y la cuenta?',
                 'Gracias, de verdad mil disculpas', 'gracias, mañana te mando el otro deposito',
                 'me pasas la cuenta?', 'cuanto esta la tasa a colombia', 'Hola buenas tardes', 'Buen día, cuenta pa ecuador']) {
  const a = accion(t);
  chk(a === 'ia', JSON.stringify(t), '-> ' + a);
}
{
  const r = revisar([captura('50.00', '99990001'), 'gracias'], null);
  chk(r.accion === 'ia' && r.estadoOperacion === 'falta_cuenta', 'captura + "gracias": la IA pide la cuenta', '-> ' + r.accion + ' / ' + r.estadoOperacion);
  const r2 = revisar([CUENTA, 'gracias'], null);
  chk(r2.accion === 'ia' && r2.estadoOperacion === 'falta_captura', 'cuenta + "gracias": la IA pide la captura', '-> ' + r2.accion + ' / ' + r2.estadoOperacion);
}

console.log('');
console.log('=== 3) Como mucho 1 sticker cada 10 minutos ===');
{
  reloj = Date.parse('2026-11-21T16:00:00Z');
  const r1 = revisar(['gracias'], null);
  chk(r1.accion === 'gracias', 'primer "gracias": sticker', '-> ' + r1.accion);
  chk(r1.op.ultimoGracias === reloj, 'y se anota la hora');
  pasan(3);
  const r2 = revisar(['Muchas gracias'], r1.op);
  chk(r2.accion === 'callar', 'otro "gracias" a los 3 min: nada (ni sticker ni IA)', '-> ' + r2.accion);
  chk(r2.op.ultimoGracias === r1.op.ultimoGracias, 'y no corre el reloj de los 10 min');
  pasan(8);
  const r3 = revisar(['gracias 🙏'], r2.op);
  chk(r3.accion === 'gracias', 'a los 11 min: sticker otra vez', '-> ' + r3.accion);
}

console.log('');
console.log('=== 4) "ok" suelto: nada, salvo que el bot haya preguntado algo ===');
for (const t of ['ok', 'Okok', 'oki', 'Okis 🧡', 'okk', 'listo', 'Perfecto', 'vale', 'Esta bien', 'ok amor', 'ahh ok',
                 '👍🏻', '👌', 'Listo hagale', 'Entendido', 'De acuerdo', 'dale']) {
  const a = accion(t, { pregunta: '0' });
  chk(a === 'callar', JSON.stringify(t) + ' (el bot no habia preguntado)', '-> ' + a);
}
{
  chk(accion('ok', { pregunta: '1' }) === 'ia', '"ok" despues de una PREGUNTA del bot: la IA contesta', '-> ' + accion('ok', { pregunta: '1' }));
  chk(accion('dale', { pregunta: '1' }) === 'ia', '"dale" despues de una pregunta: la IA contesta');
  chk(accion('ok', { pregunta: 'CAIDA' }) === 'ia', 'si Redis no responde, ante la duda contesta la IA', '-> ' + accion('ok', { pregunta: 'CAIDA' }));
  chk(accion('ok', { pregunta: null }) === 'callar', 'sin dato (chat nuevo o de hace dias): nada', '-> ' + accion('ok', { pregunta: null }));
}
{
  chk(accion('😂', { pregunta: '0' }) === 'callar', 'solo un emoji ("😂") es como un "ok": nada', '-> ' + accion('😂', { pregunta: '0' }));
  chk(accion('😂', { pregunta: '1' }) === 'ia', 'pero si el bot habia preguntado, la IA contesta');
  for (const t of ['❤️', '🤣🤣🤣', '🤝', 'Ok 👍']) chk(accion(t, { pregunta: '0' }) === 'callar', JSON.stringify(t) + ' (ok, risa o carino): nada');
  for (const t of ['😔', '🚨', '🤔🤔', '🤷🏽‍♀️', '😭😭']) chk(accion(t, { pregunta: '0' }) === 'ia', JSON.stringify(t) + ' (preocupacion o duda): la IA pregunta que pasa');
  for (const t of ['Bien y tu', 'Buen día bien y ustedes', 'bien gracias y tu']) chk(accion(t, { pregunta: '0' }) === 'ia', JSON.stringify(t) + ' pregunta de vuelta: la IA');
}
for (const t of ['.', '...', 'si', 'Si', '?', 'voy', 'ok y la tasa?', 'ok cuanto es 100$ a colombia', 'Hola', 'listo ya deposite',
                 'ok pasame la cuenta', 'no']) {
  const a = accion(t, { pregunta: '0' });
  chk(a === 'ia', JSON.stringify(t) + ' NO es un "ok" suelto: la IA', '-> ' + a);
}

console.log('');
console.log('=== 5) Mensaje sin texto: nada ===');
{
  chk(accion('') === 'callar', 'texto vacio', '-> ' + accion(''));
  chk(accion('   ') === 'callar', 'solo espacios', '-> ' + accion('   '));
  chk(accion(['', 'hola']) === 'ia', 'vacio + "hola" en la misma tanda: la IA', '-> ' + accion(['', 'hola']));
}

console.log('');
console.log('=== 6) Lo pendiente no se pierde con un "gracias" o un "ok" ===');
{
  reloj = Date.parse('2026-11-21T17:00:00Z');
  const r1 = revisar([CUENTA], null);
  chk(r1.estadoOperacion === 'falta_captura', 'llega la cuenta sola: falta la captura', '-> ' + r1.estadoOperacion);
  pasan(1);
  const r2 = revisar(['gracias'], r1.op);
  chk(r2.accion === 'gracias' && r2.op.cuenta && r2.op.cuenta.mensajes.length === 1, '"gracias": sticker y la cuenta sigue guardada');
  pasan(1);
  const r3 = revisar(['ok'], r2.op, { pregunta: '0' });
  chk(r3.accion === 'callar' && r3.op.cuenta && r3.op.cuenta.mensajes.length === 1, '"ok": nada y la cuenta sigue guardada');
  pasan(5);
  const r4 = revisar([captura('50.00', '99990002')], r3.op);
  chk(r4.estadoOperacion === 'completo' && r4.accion === 'ia', 'llega la captura: COMPLETO y contesta la IA', '-> ' + r4.estadoOperacion + ' / ' + r4.accion);
  chk(r4.op.ultimoGracias === r2.op.ultimoGracias, 'y se sigue recordando el ultimo sticker');
}

console.log('');
console.log('=== 7) El nombre del cliente: una sola vez cada 24 h ===');
{
  reloj = Date.parse('2026-11-21T18:00:00Z');
  const r1 = revisar(['Hola buen dia'], null);
  chk(/puedes saludarlo por su nombre/i.test(r1.reglaNombre) && r1.reglaNombre.indexOf('Ana Prueba') !== -1,
      'primer mensaje: puede saludarlo por su nombre', '-> ' + r1.reglaNombre);
  chk(r1.op.ultimoSaludo === reloj, 'y se anota la hora del saludo');
  pasan(30);
  const r2 = revisar(['cuanto esta la tasa a colombia'], r1.op);
  chk(/NO escribas el nombre/i.test(r2.reglaNombre) && r2.reglaNombre.indexOf('Ana') === -1,
      'a los 30 min: que NO use el nombre (y no se lo pasa)', '-> ' + r2.reglaNombre);
  chk(r2.op.ultimoSaludo === r1.op.ultimoSaludo, 'el reloj de las 24 h no se mueve');
  pasan(24 * 60);
  const r3 = revisar(['gracias'], r2.op);
  chk(r3.accion === 'gracias' && r3.op.ultimoSaludo === r1.op.ultimoSaludo, 'un "gracias" (sticker) no gasta el saludo del dia');
  const r4 = revisar(['Hola, me pasas la cuenta?'], r3.op);
  chk(/puedes saludarlo/i.test(r4.reglaNombre), 'pasadas 24 h: puede usar el nombre otra vez', '-> ' + r4.reglaNombre);
  const r5 = revisar(['Hola'], null, { nombre: '' });
  chk(r5.reglaNombre === '', 'sin nombre conocido: ninguna regla', '-> ' + JSON.stringify(r5.reglaNombre));
}

console.log('');
console.log('=== 8) Code in JavaScript: el pais por el prefijo (solo por defecto) y sin "saludalo" fijo ===');
{
  const TASAS = ['Pais,Tasa Envio,Margen Envio,Tasa Recibo,Margen Recibo', 'Ecuador,1,0,1,0', 'Colombia,3800,6,3700,6'].join(SALTO);
  const esc = s => '"' + s.replace(/"/g, '""') + '"';
  const CUENTAS = ['Pais,Metodo,Disponible,Datos,Notas,Tipo', 'Ecuador,Pichincha,si,' + esc(NUESTRAS[0].Datos) + ',,'].join(SALTO);
  function principal(jid, nombre, historial) {
    const uno = j => ({ first: () => ({ json: j }), all: () => [{ json: j }] });
    const $ = (n) => {
      if (n === 'Consultar Tasas') return uno({ data: TASAS });
      if (n === 'Consultar Cuentas') return uno({ data: CUENTAS });
      if (n === 'Cuando lo Llama el Bot') return uno({ body: { data: { key: { remoteJid: jid } } }, nombreCargado: nombre || '' });
      if (n === 'Webhook Evolution API') return uno({ body: { data: { key: { remoteJid: jid } } } });
      if (n === 'Solo Estos Numeros') return uno({ nombreCargado: nombre || '' });
      if (n === 'Consultar Cliente') return { first: () => ({ json: (historial || [])[0] || {} }), all: () => (historial || []).map(json => ({ json })) };
      return { first: () => ({ json: {} }), all: () => [] };
    };
    return new Function('$', '$getWorkflowStaticData', code('Code in JavaScript'))($, () => ({}))[0].json;
  }
  for (const [jid, pais] of [['593990000001@s.whatsapp.net', 'Ecuador'], ['573000000001@s.whatsapp.net', 'Colombia'],
                             ['584120000001@s.whatsapp.net', 'Venezuela'], ['51900000001@s.whatsapp.net', 'Perú'],
                             ['13050000001@s.whatsapp.net', 'Estados Unidos (Zelle)']]) {
    const r = principal(jid, '');
    chk(r.paisPorPrefijo === pais, jid.split('@')[0] + ' -> ' + pais, '-> ' + r.paisPorPrefijo);
    chk(r.clienteContexto.indexOf('Te paso la cuenta de ' + pais) !== -1, '   y le dice al agente que lo diga claro al dar la cuenta');
  }
  const ec = principal('593990000001@s.whatsapp.net', '');
  chk(/deposita otra persona desde otro pais/i.test(ec.clienteContexto), 'lo que diga el cliente manda (otra persona, otro pais)');
  chk(/DESTINO[^.]*NUNCA/i.test(ec.clienteContexto), 'el pais DESTINO nunca se asume por el numero');
  const es = principal('34600000001@s.whatsapp.net', '');
  chk(es.paisPorPrefijo === '' && es.clienteContexto.indexOf('Su numero es de') === -1, 'prefijo sin pais conocido (+34): no asume nada', '-> ' + JSON.stringify(es.paisPorPrefijo));
  const lid = principal('123456789012345@lid', '');
  chk(lid.paisPorPrefijo === '', 'chat @lid (sin telefono): no asume nada', '-> ' + JSON.stringify(lid.paisPorPrefijo));
  const conNombre = principal('593990000001@s.whatsapp.net', 'Ana Prueba', [{ pais_destino: 'Colombia', nombre_cliente: 'Ana' }]);
  chk(conNombre.nombreCliente === 'Ana Prueba', 'entrega el nombre aparte (para la regla de las 24 h)', '-> ' + conNombre.nombreCliente);
  chk(!/saludalo por su nombre/i.test(conNombre.clienteContexto), 'el contexto ya NO dice "saludalo por su nombre"');
  chk(/suele enviar a Colombia/.test(conNombre.clienteContexto) && /no lo asumas/i.test(conNombre.clienteContexto),
      'el destino habitual queda solo como contexto, no se asume');
  chk(conNombre.sessionId === '593990000001@s.whatsapp.net', 'sigue entregando sessionId (red de seguridad de la memoria)');
}

console.log('');
console.log('=== 9) Como quedo conectado ===');
{
  const saleV12 = (n, i) => ((((wf.connections[n] || {}).main || [])[i || 0]) || []).map(c => c.node);
  const saleDeb = (n, i) => ((((wfDeb.connections[n] || {}).main || [])[i || 0]) || []).map(c => c.node);
  const sale = (n, i) => ((((wfIa.connections[n] || {}).main || [])[i || 0]) || []).map(c => c.node);
  chk(saleV12('Es mensaje de cliente?').join() === 'Ejecutar Debounce'
      && saleDeb('¿Es Comando Admin?', 1).join() === 'Preparar Contexto IA' && saleDeb('¿Solo el Comando?', 1).join() === 'Preparar Contexto IA'
      && saleDeb('Preparar Contexto IA').join() === 'Ejecutar IA' && sale('Cuando lo Llama el Bot').join() === 'Consultar Tasas',
      'v12 -> Ejecutar Debounce -> Preparar Contexto IA -> Ejecutar IA -> Consultar Tasas');
  chk(sale('Redis Leer Operacion').join() === 'Redis Leer Pregunta', 'Redis Leer Operacion -> Redis Leer Pregunta', '-> ' + sale('Redis Leer Operacion'));
  chk(sale('Redis Leer Pregunta').join() === 'Consultar Operaciones WhatsApp' && sale('Consultar Operaciones WhatsApp').join() === 'Revisar Operacion',
      'Redis Leer Pregunta -> Consultar Operaciones WhatsApp -> Revisar Operacion');
  chk(sale('Redis Guardar Operacion')[0] === '¿Qué Responder?', 'Redis Guardar Operacion -> ¿Qué Responder?', '-> ' + sale('Redis Guardar Operacion'));
  chk(sale('¿Qué Responder?', 0).join() === 'Sticker A Su Orden', 'salida "gracias" -> Sticker A Su Orden');
  chk(sale('¿Qué Responder?', 1).length === 0, 'salida "callar" -> nada');
  chk(sale('¿Qué Responder?', 2).join() === 'AI Agent', 'todo lo demas (incluido lo inesperado) -> AI Agent');
  chk(sale('AI Agent').indexOf('Redis Marcar Pregunta') !== -1, 'AI Agent -> Redis Marcar Pregunta (recuerda si pregunto)');

  const sw = nodo('¿Qué Responder?');
  const reglas = sw.parameters.rules.values.map(v => v.outputKey + '=' + v.conditions.conditions[0].rightValue);
  chk(reglas.join() === 'gracias=gracias,callar=callar', 'reglas del switch', '-> ' + reglas);
  chk(sw.parameters.options.fallbackOutput === 'extra', 'con salida de respaldo (lo inesperado va a la IA, como antes)');
  chk(/Revisar Operacion/.test(sw.parameters.rules.values[0].conditions.conditions[0].leftValue), 'lee la accion de Revisar Operacion');

  const st = nodo('Sticker A Su Orden');
  chk(/sticker-a-su-orden\.webp/.test(st.parameters.jsonBody), 'el sticker es el de A SU ORDEN');
  chk(/Cuando lo Llama el Bot/.test(st.parameters.jsonBody) && /sendSticker/.test(st.parameters.url), 'se manda al chat del cliente');
  chk(!!(st.credentials && st.credentials.httpHeaderAuth), 'con la credencial de Evolution (sin apikey en el codigo)');

  const leer = nodo('Redis Leer Pregunta'), marcar = nodo('Redis Marcar Pregunta');
  chk(leer.parameters.key === marcar.parameters.key && /'preg:'/.test(leer.parameters.key), 'leen y escriben la misma llave preg:<chat>', '-> ' + leer.parameters.key);
  chk(leer.onError === 'continueRegularOutput' && marcar.onError === 'continueRegularOutput', 'si Redis falla, el bot sigue');
  const expr = String(marcar.parameters.value).replace(/^=\{\{/, '').replace(/\}\}$/, '');
  const valor = out => new Function('$json', 'return (' + expr + ');')({ output: out });
  chk(valor('Desde donde envias y cuanto? Asi te cotizo exacto.') === '1', 'respuesta con pregunta -> "1"');
  chk(valor('¿Lo quieres en bolivares o en efectivo') === '1', 'con "¿" tambien cuenta');
  chk(valor('Listo, recibido! Procesamos tu remesa enseguida ✅') === '0', 'respuesta sin pregunta -> "0"');
}

console.log('');
console.log('=== 10) El prompt ===');
{
  const ai = nodo('AI Agent').parameters;
  const sm = ai.options.systemMessage;
  chk(/Revisar Operacion[^}]*reglaNombre/.test(sm), 'trae la regla del nombre (una vez cada 24 h)');
  chk(sm.indexOf('😊') !== -1 && /Nunca uses 😊/.test(sm), 'prohibe 😊');
  chk(/aqui estoy/i.test(sm), 'prohibe "aqui estoy"');
  const ejemplos = sm.split(SALTO).filter(l => /^- "[^"]+".* -> /.test(l));
  chk(ejemplos.length >= 8, 'trae al menos 8 ejemplos de tono', '-> ' + ejemplos.length);
  chk(!/[0-9]{8,}/.test(ejemplos.join(' ')), 'los ejemplos no traen numeros de cuenta ni telefonos');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
