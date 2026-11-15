// Prueba del filtro "a quien le contesta el bot" (nodo "Solo Estos Numeros",
// el primero despues del webhook en el bot de WhatsApp).
//
// Hay dos formas de limitarlo:
//   1) $SOLO_ESTOS   -> lista escrita en build_v12.ps1 (modo prueba)
//   2) $MODO_SOLO_CLIENTES -> los numeros salen de Supabase, de las tablas
//      clientes_bot_detal y clientes_bot_mayor
//
// Lo que mas importa de todo esto, y por eso va primero, es que el bot NO se
// quede mudo sin que nadie se entere:
//   - sin ninguna de las dos formas -> le contesta a todos;
//   - con el modo prendido pero las tablas vacias -> le contesta a todos;
//   - con el modo prendido pero Supabase caido -> le contesta a todos.
// Un problema de base de datos no puede dejar al negocio sin atender.
//
// Correr con:  node test_solo_estos.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const nodo = wf.nodes.find(n => n.name === 'Solo Estos Numeros');
if (!nodo) { console.log('FALLO: no existe el nodo "Solo Estos Numeros"'); process.exit(1); }

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(56) + ' ' + (detalle || ''));
};

// Corre el codigo REAL del nodo, cambiandole la lista y el interruptor.
//   lista  : lo que tendria $SOLO_ESTOS
//   modo   : lo que tendria $MODO_SOLO_CLIENTES
//   tablas : { detal: [...], mayor: [...] } con las filas que devolveria Supabase.
//            Si una tabla es la cadena 'CAIDA', se simula que el nodo fallo.
//            Si es undefined, se simula que el nodo ni corrio.
function correr(lista, modo, jids, tablas) {
  const js = nodo.parameters.jsCode
    .replace(/const SOLO_ESTOS = .*;/, 'const SOLO_ESTOS = ' + JSON.stringify(lista) + ';')
    .replace(/const MODO_SOLO_CLIENTES = .*;/, 'const MODO_SOLO_CLIENTES = ' + (modo ? 'true' : 'false') + ';');

  const t = tablas || {};
  const items = jids.map(j => ({ json: { body: { data: { key: { remoteJid: j } } } } }));

  const porNodo = {
    'Clientes Detal Permitidos': t.detal,
    'Clientes Mayor Permitidos': t.mayor
  };
  const $ = (n) => {
    // El mensaje de WhatsApp se busca en el webhook, no en $input.
    if (n === 'Webhook Evolution API') return { all: () => items };
    const v = porNodo[n];
    if (v === undefined) throw new Error('Node "' + n + '" not executed');
    const filas = (v === 'CAIDA')
      ? [{ error: { message: 'Supabase no responde' } }]
      : v;
    return { all: () => filas.map(json => ({ json })) };
  };

  // IMPORTANTE: asi es como llega de verdad. Justo antes de este nodo hay dos consultas a
  // Supabase, y un nodo de Supabase devuelve LAS FILAS DE LA TABLA: eso es lo que trae
  // $input. Si el nodo leyera de ahi, creeria que el mensaje es una fila de la tabla.
  const filasQueLleganPorInput = (t.mayor && t.mayor !== 'CAIDA') ? t.mayor : [{}];
  const $input = { all: () => filasQueLleganPorInput.map(json => ({ json })) };

  const salida = new Function('$input', '$', js)($input, $);
  return salida.map(it => it.json.body.data.key.remoteJid);
}

const KELVIN  = '593961230380@s.whatsapp.net';
const CLIENTE = '584121234567@s.whatsapp.net';
const OTRO    = '573001112233@s.whatsapp.net';
const GRUPO   = '120363291497664389@g.us';
const TODOS   = [KELVIN, CLIENTE, OTRO, GRUPO];
const VACIAS  = { detal: [], mayor: [] };

console.log('=== 1) LO MAS IMPORTANTE: el bot no se queda mudo ===');
{
  chk(correr([], false, TODOS, VACIAS).length === 4,
      'sin lista y sin modo -> contesta a todos');
  chk(correr([], true, TODOS, VACIAS).length === 4,
      'modo prendido pero tablas VACIAS -> contesta a todos');
  chk(correr([], true, TODOS, { detal: 'CAIDA', mayor: [] }).length === 4,
      'modo prendido y Supabase CAIDO -> contesta a todos');
  chk(correr([], true, TODOS, { detal: [], mayor: 'CAIDA' }).length === 4,
      'si falla la tabla de mayor, igual contesta a todos');
  chk(correr([], true, TODOS, {}).length === 4,
      'si los nodos de Supabase ni corrieron -> contesta a todos');
}

console.log('');
console.log('=== 2) Los numeros salen de Supabase ===');
{
  const tablas = {
    detal: [{ whatsapp: '593961230380', nombre: 'Kelvin' }],
    mayor: [{ whatsapp: '584121234567', nombre: 'Cliente mayor' }]
  };
  const r = correr([], true, TODOS, tablas);
  chk(r.length === 2, 'pasan los 2 cargados', '-> ' + r.length);
  chk(r.indexOf(KELVIN) !== -1 && r.indexOf(CLIENTE) !== -1, 'uno de detal y uno de mayor');
  chk(r.indexOf(OTRO) === -1, 'el que no esta cargado NO pasa');
  chk(r.indexOf(GRUPO) === -1, 'los grupos tampoco');
}

console.log('');
console.log('=== 3) El numero se puede cargar como sea ===');
{
  const formas = ['+593961230380', '593 961 230 380', '+593-96-123-0380', '961230380'];
  for (const f of formas){
    const r = correr([], true, [KELVIN], { detal: [{ whatsapp: f }], mayor: [] });
    chk(r.length === 1, 'cargado como "' + f + '"');
  }
}

console.log('');
console.log('=== 4) La columna "activo" apaga un numero sin borrarlo ===');
{
  const r = correr([], true, TODOS, {
    detal: [{ whatsapp: '593961230380', activo: false }, { whatsapp: '584121234567', activo: true }],
    mayor: []
  });
  chk(r.indexOf(KELVIN) === -1, 'activo=false queda afuera');
  chk(r.indexOf(CLIENTE) !== -1, 'activo=true sigue pasando');

  // Si la columna no existe (undefined), NO se apaga a nadie.
  const r2 = correr([], true, [KELVIN], { detal: [{ whatsapp: '593961230380' }], mayor: [] });
  chk(r2.length === 1, 'sin columna activo, el numero pasa igual');
}

console.log('');
console.log('=== 5) La lista del codigo le gana a Supabase (modo prueba) ===');
{
  const tablas = { detal: [{ whatsapp: '584121234567' }], mayor: [] };
  const r = correr(['593961230380'], true, TODOS, tablas);
  chk(r.length === 1 && r[0] === KELVIN, 'solo pasa el del codigo', '-> ' + JSON.stringify(r));
  chk(r.indexOf(CLIENTE) === -1, 'el de Supabase NO pasa mientras se prueba');

  // Y en modo prueba NO se hace red de seguridad: si la lista del codigo tiene
  // numeros, manda esa lista aunque Supabase este caido.
  const r2 = correr(['593961230380'], true, TODOS, { detal: 'CAIDA', mayor: 'CAIDA' });
  chk(r2.length === 1, 'con Supabase caido sigue mandando la lista del codigo', '-> ' + r2.length);
}

console.log('');
console.log('=== 6) Un numero corto mal cargado NO abre la puerta a todos ===');
{
  const r = correr([], true, [KELVIN, '584120000380@s.whatsapp.net'],
                   { detal: [{ whatsapp: '0380' }], mayor: [] });
  chk(r.length === 0, 'con 4 digitos no deja pasar a nadie', '-> ' + r.length);
}

console.log('');
console.log('=== 7) Filas basura no revientan el nodo ===');
{
  const r = correr([], true, [KELVIN], {
    detal: [{}, { whatsapp: '' }, { whatsapp: null }, { nombre: 'sin numero' }],
    mayor: []
  });
  chk(r.length === 1, 'filas sin numero se ignoran y pasa todo (lista vacia)', '-> ' + r.length);
}

console.log('');
console.log('=== 8) Como quedo desplegado AHORA MISMO ===');
{
  const l = nodo.parameters.jsCode.match(/const SOLO_ESTOS = (.*);/)[1];
  const m = nodo.parameters.jsCode.match(/const MODO_SOLO_CLIENTES = (.*);/)[1];
  console.log('     SOLO_ESTOS = ' + l + '   |   MODO_SOLO_CLIENTES = ' + m);
  chk(l === '[]', 'la lista del codigo esta vacia');
  chk(m === 'false', 'el modo esta APAGADO -> el bot le contesta a todos');
}

console.log('');
console.log(fallos ? (fallos + ' fallaron') : 'Todas las pruebas pasaron');
process.exit(fallos ? 1 : 0);
