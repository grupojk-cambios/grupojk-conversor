
const _strip = s => s ? String(s).replace(/^\d+[\w\.]*\s*/, '') : '';
const _findNode = (nodes, n) => (nodes || []).find(x => x.name === n || _strip(x.name) === _strip(n));
const _getConn = (conns, n) => {
  if (!conns) return null;
  const k = Object.keys(conns).find(x => x === n || _strip(x) === _strip(n));
  return k ? Reflect.get(conns, k) : null;
};
// Prueba de los SALUDOS del bot (pedido de Kelvin, 24/11): "que sepa dar los buenos dias, buenas tardes,
// buenas noches, y si alguien le saluda que conteste".
//
// Lo que paso: un cliente escribio "Buenos dias amigo. Ayudame con ese envio por favor" y el bot no le
// devolvio el saludo, porque su respuesta era una frase fija ("Recibi tu comprobante..."). Ahora
// "Revisar Operacion" detecta el saludo del cliente y le da a la IA una regla:
//   - si dijo "buenos dias / buenas tardes / buenas noches", se le contesta IGUAL (puede escribir desde
//     otro pais, con otra hora);
//   - si solo dijo "hola" o "buenas", el saludo es el de la hora de Ecuador (antes de las 12 dias, de
//     12 a 19 tardes, despues noches);
//   - el saludo va antes de las frases fijas del estado de la operacion;
//   - si no saludo, no se le agrega nada.
//
// Todos los datos son INVENTADOS. Correr con:  node test_saludos.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_ia_atencion.json', 'utf8').replace(/^﻿/, ''));
const nodo = n => _findNode(wf.nodes, n);
const code = n => nodo(n).parameters.jsCode;

let fallos = 0;
const chk = (ok, etiqueta, detalle) => { if (!ok) fallos++; console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(74) + ' ' + (detalle || '')); };

const NUESTRAS = [{ Pais: 'Ecuador', Metodo: 'Pichincha', Datos: '*CUENTA AUTORIZADA USD*\n\n1) 2200000001\n*Pichincha ahorro*\n*Titular Empresa*' }];
let reloj = Date.parse('2026-11-24T15:00:00Z');   // 10:00 am en Ecuador
function revisar(textos, op, extra) {
  const real = Date.now; Date.now = () => reloj;
  try {
    const mensajes = textos.map((t, i) => ({ id: 'M' + i, texto: t }));
    const $ = n => {
      if (n === 'Code in JavaScript' || _strip(n) === 'Code in JavaScript') return { first: () => ({ json: Object.assign({ cuentas: NUESTRAS, sessionId: 'chat', modo: 'detal', nombreCliente: 'Ana Prueba' }, extra || {}) }) };
      if (n === 'Cuando lo Llama el Bot' || _strip(n) === 'Cuando lo Llama el Bot') return { first: () => ({ json: { mensajes } }) };
      if (n === 'Combinar' || _strip(n) === 'Combinar') return { first: () => ({ json: { mensajes } }) };
      if (n === 'Redis Leer Operacion' || _strip(n) === 'Redis Leer Operacion') return { first: () => ({ json: { operacion: op ? JSON.stringify(op) : null } }) };
      throw new Error('nodo inesperado: ' + n);
    };
    return new Function('$', code('Revisar Operacion'))($)[0].json;
  } finally { Date.now = real; }
}
const hora = ecu => { reloj = Date.parse('2026-11-24T00:00:00Z') + (ecu + 5) * 3600000; };   // hora de Ecuador (UTC-5)
const regla = (t, h) => { if (h !== undefined) hora(h); return revisar(Array.isArray(t) ? t : [t]).reglaSaludo; };
const empieza = (r, s) => r.indexOf('Empieza tu respuesta con "' + s + '"') !== -1;

console.log('=== 1) EL CLIENTE DICE LA HORA: SE LE CONTESTA IGUAL ===');
{
  chk(empieza(regla('Buenos días', 15), 'Buenos días'), '"Buenos días" (aunque en Ecuador sean las 3 pm) -> "Buenos días"');
  chk(empieza(regla('buen dia', 9), 'Buenos días'), '"buen dia" -> "Buenos días"');
  chk(empieza(regla('Buenas tardes', 9), 'Buenas tardes'), '"Buenas tardes" (a las 9 am) -> "Buenas tardes"');
  chk(empieza(regla('buenas noches mi pana', 10), 'Buenas noches'), '"buenas noches mi pana" -> "Buenas noches"');
  chk(empieza(regla('Hola buenos dias', 16), 'Buenos días'), '"Hola buenos dias" -> "Buenos días"');
  chk(empieza(regla('buens dias amigo', 8), 'Buenos días'), 'con error de tipeo ("buens dias") -> "Buenos días"');
  chk(empieza(regla('Buenooos diaaas', 20), 'Buenos días') || regla('Buenooos diaaas', 20) === '', 'estirado ("Buenooos diaaas"): o lo entiende o no inventa', '-> ' + regla('Buenooos diaaas', 20).slice(0, 50));
}

console.log('');
console.log('=== 2) SOLO DICE "HOLA": EL SALUDO ES EL DE LA HORA DE ECUADOR ===');
{
  chk(empieza(regla('Hola', 8), 'Buenos días'), '"Hola" a las 8 am -> "Buenos días"');
  chk(empieza(regla('Hola', 11), 'Buenos días'), '"Hola" a las 11 am -> "Buenos días"');
  chk(empieza(regla('Hola', 12), 'Buenas tardes'), '"Hola" a las 12 del dia -> "Buenas tardes"');
  chk(empieza(regla('hola que tal', 15), 'Buenas tardes'), '"hola que tal" a las 3 pm -> "Buenas tardes"');
  chk(empieza(regla('Buenas', 18), 'Buenas tardes'), '"Buenas" a las 6 pm -> "Buenas tardes"');
  chk(empieza(regla('Buenas', 19), 'Buenas noches'), '"Buenas" a las 7 pm -> "Buenas noches"');
  chk(empieza(regla('holaaa', 22), 'Buenas noches'), '"holaaa" a las 10 pm -> "Buenas noches"');
  chk(empieza(regla('Saludos', 10), 'Buenos días') && empieza(regla('Epa', 10), 'Buenos días') && empieza(regla('Holi', 10), 'Buenos días'), '"Saludos", "Epa", "Holi" tambien son saludos');
  chk(empieza(regla('Hola', 0), 'Buenas noches') && empieza(regla('Hola', 4), 'Buenas noches') && empieza(regla('Hola', 23), 'Buenas noches'), 'de madrugada (0 a 4 am) y a las 11 pm -> "Buenas noches"');
  chk(empieza(regla('Hola', 5), 'Buenos días'), 'desde las 5 am -> "Buenos días"');
}

console.log('');
console.log('=== 3) SALUDO + OTRA COSA (el caso de Cesar) ===');
{
  hora(10);
  const r = revisar(['Buenos días amigo. Ayúdame con ese envío por favor.']);
  chk(empieza(r.reglaSaludo, 'Buenos días') && /UNICA excepcion/.test(r.reglaSaludo) && /\[ESTADO DE LA OPERACION\]/.test(r.reglaSaludo), 'el saludo va ANTES de las frases fijas del estado (unica excepcion a "Responde SOLO")');
  chk(/Si SOLO te saludo/.test(r.reglaSaludo) && /Bien, gracias/.test(r.reglaSaludo), 'y le dice a la IA que hacer si solo saluda o pregunta como estas');
  const CAP = '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: $20,00, Moneda: USD, Banco: Pichincha, Fecha: 24/11/2026, Referencia: 99001]';
  const c = revisar(['Buenas tardes', CAP]);
  chk(c.estadoOperacion === 'falta_cuenta' && empieza(c.reglaSaludo, 'Buenas tardes') && /Recibi tu comprobante/.test(c.notaIA), 'saludo + captura sin cuenta: la nota pide la cuenta Y hay saludo');
  const d = revisar(['Hola', CAP + '\n0102 1234567 04120000000\n$20']);
  chk(d.estadoOperacion === 'completo' && d.reglaSaludo !== '', 'saludo + captura + cuenta (en el pie): COMPLETO y con saludo', '-> ' + d.estadoOperacion);
}

console.log('');
console.log('=== 4) CUANDO NO SE AGREGA NADA ===');
{
  hora(10);
  chk(regla('Que tasa hay pa Colombia?') === '', 'si no saluda, no hay regla de saludo');
  chk(regla('Pasame la cuenta pa Ecuador') === '', '"Pasame la cuenta pa Ecuador": sin saludo');
  chk(regla('buen provecho') === '' && regla('que bueno, gracias') === '', '"buen provecho" y "que bueno" NO son saludos', '-> ' + regla('buen provecho'));
  chk(regla('Buenos días') !== '' && revisar(['gracias']).reglaSaludo === '', '"gracias": el sticker de siempre, sin saludo');
  const ok = revisar(['ok']);
  chk(ok.reglaSaludo === '', '"ok" suelto: sin saludo');
  const g = revisar(['Buenos días, gracias']);
  chk(g.accion === 'gracias' && g.reglaSaludo === '', '"Buenos dias, gracias": sticker (sin IA), asi que no hay regla de saludo', '-> ' + g.accion);
  const cita = revisar(['[el cliente respondio citando "Buenos días, aqui tienes la cuenta"] listo']);
  chk(cita.reglaSaludo === '', 'un saludo que el cliente CITA (del bot) no cuenta como saludo suyo');
}

console.log('');
console.log('=== 5) EL PROMPT DE LA IA ===');
{
  const sys = nodo('AI Agent').parameters.options.systemMessage;
  chk(/json\.reglaSaludo/.test(sys), 'el prompt incluye la regla de saludo del turno');
  chk(/"Buenas tardes" -> "Buenas tardes 👋 Dime, ¿qué necesitas\?"/.test(sys) && /"Buen provecho" -> "Igualmente/.test(sys), 'y trae ejemplos de buenas tardes, buen provecho y bendiciones');
  chk(!/😊/.test(sys.slice(sys.indexOf('Ejemplos (cliente -> tu)'))), 'sin el emoji prohibido 😊 (el tono de Kelvin)');
  chk(/Nunca uses 😊/.test(sys), 'la regla de tono de Kelvin sigue ahi');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
