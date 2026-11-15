// Prueba del filtro "solo responderle a estos numeros" del bot de WhatsApp
// (nodo "Solo Estos Numeros", el primero despues del webhook).
//
// Lo que vigila, en orden de importancia:
//   1. LISTA VACIA = el bot le responde A TODO EL MUNDO. Es el estado normal, y si esto
//      se rompe el bot deja de atender clientes sin que nadie se entere.
//   2. Con numeros, solo pasan esos.
//   3. Un numero corto mal cargado NO puede dejar pasar a medio mundo (por eso el
//      "termina en" exige 8 digitos de cada lado).
//   4. Aguanta que el numero este escrito con o sin codigo de pais.
//
// Correr con:  node test_solo_estos.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const nodo = wf.nodes.find(n => n.name === 'Solo Estos Numeros');
if (!nodo) { console.log('FALLO: no existe el nodo "Solo Estos Numeros"'); process.exit(1); }

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(54) + ' ' + (detalle || ''));
};

// Corre el codigo REAL del nodo, pero cambiandole la lista para probar varios casos.
function correr(lista, jids) {
  const js = nodo.parameters.jsCode.replace(
    /const SOLO_ESTOS = .*;/,
    'const SOLO_ESTOS = ' + JSON.stringify(lista) + ';'
  );
  const items = jids.map(j => ({ json: { body: { data: { key: { remoteJid: j } } } } }));
  const $input = { all: () => items };
  const salida = new Function('$input', js)($input);
  return salida.map(it => it.json.body.data.key.remoteJid);
}

const KELVIN  = '593961230380@s.whatsapp.net';
const CLIENTE = '584121234567@s.whatsapp.net';
const OTRO    = '573001112233@s.whatsapp.net';
const GRUPO   = '120363291497664389@g.us';
const TODOS   = [KELVIN, CLIENTE, OTRO, GRUPO];

console.log('=== 1) Lista VACIA -> pasa TODO (es como trabaja normalmente) ===');
{
  const r = correr([], TODOS);
  chk(r.length === 4, 'pasan los 4 mensajes', '-> ' + r.length);
  chk(r.indexOf(CLIENTE) !== -1, 'un cliente cualquiera SI recibe respuesta');
  chk(r.indexOf(GRUPO) !== -1, 'los grupos tambien siguen pasando');
}

console.log('');
console.log('=== 2) Con un numero -> solo ese ===');
{
  const r = correr(['593961230380'], TODOS);
  chk(r.length === 1 && r[0] === KELVIN, 'solo pasa Kelvin', '-> ' + JSON.stringify(r));
  chk(r.indexOf(CLIENTE) === -1, 'el cliente queda sin respuesta (es lo que se busca)');
  chk(r.indexOf(GRUPO) === -1, 'los grupos tampoco pasan mientras se prueba');
}

console.log('');
console.log('=== 3) Con dos numeros -> pasan los dos ===');
{
  const r = correr(['593961230380', '584121234567'], TODOS);
  chk(r.length === 2, 'pasan 2', '-> ' + r.length);
  chk(r.indexOf(OTRO) === -1, 'el tercero sigue afuera');
}

console.log('');
console.log('=== 4) Con o sin codigo de pais, lo reconoce igual ===');
{
  chk(correr(['961230380'], [KELVIN]).length === 1, 'lista sin codigo de pais, jid con el');
  chk(correr(['593961230380'], ['961230380@s.whatsapp.net']).length === 1, 'al reves');
  chk(correr(['+593 96 123 0380'], [KELVIN]).length === 1, 'con signos y espacios tambien');
}

console.log('');
console.log('=== 5) Un numero corto mal cargado NO abre la puerta a todos ===');
{
  // Si alguien escribe '0380' por error, sin el minimo de 8 digitos CUALQUIER cliente
  // cuyo telefono termine en 0380 entraria. Tiene que quedar afuera.
  const r = correr(['0380'], [KELVIN, '584120000380@s.whatsapp.net']);
  chk(r.length === 0, 'con 4 digitos no deja pasar a nadie', '-> ' + r.length);

  const r2 = correr(['380'], TODOS);
  chk(r2.length === 0, 'con 3 digitos tampoco');
}

console.log('');
console.log('=== 6) Casos raros no revientan el nodo ===');
{
  chk(correr(['593961230380'], []).length === 0, 'sin mensajes no revienta');
  const items = [{ json: {} }, { json: { body: {} } }];
  const js = nodo.parameters.jsCode.replace(/const SOLO_ESTOS = .*;/, "const SOLO_ESTOS = ['593961230380'];");
  const r = new Function('$input', js)({ all: () => items });
  chk(Array.isArray(r) && r.length === 0, 'un mensaje sin remoteJid se descarta sin error');

  // Y con la lista vacia, ese mismo mensaje raro tiene que pasar igual: no es tarea de
  // este nodo decidir si el mensaje sirve, solo filtrar por numero.
  const js2 = nodo.parameters.jsCode.replace(/const SOLO_ESTOS = .*;/, 'const SOLO_ESTOS = [];');
  const r2 = new Function('$input', js2)({ all: () => items });
  chk(r2.length === 2, 'con lista vacia ese mismo mensaje pasa igual', '-> ' + r2.length);
}

console.log('');
console.log('=== 7) Como quedo desplegado AHORA MISMO ===');
{
  const m = nodo.parameters.jsCode.match(/const SOLO_ESTOS = (.*);/);
  console.log('     ' + m[0]);
  chk(m[1] === '[]', 'la lista esta VACIA -> el bot le responde a todos', '-> ' + m[1]);
}

console.log('');
console.log(fallos ? (fallos + ' fallaron') : 'Todas las pruebas pasaron');
process.exit(fallos ? 1 : 0);
