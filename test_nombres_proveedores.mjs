// Prueba como el bot de tasas GUARDA y MUESTRA los nombres de los proveedores.
//
// Lo que vigila:
//   1. Un solo nombre por proveedor. Solano estaba guardado DOS veces: como
//      "SOLANO" (como lo llama Kelvin) y como "ACTIVOS X PERU" (el titulo de su
//      mensaje). Y "CORPORACION GRUPO ELITE" ahora se guarda corto: "ELITE".
//   2. Que no se vuelvan a duplicar: al aprender un proveedor se borra la
//      entrada vieja tanto si se llama igual COMO si tiene el mismo formato
//      de mensaje con otro nombre.
//   3. Que el resumen diga siempre de quien salio cada tasa, tambien por el
//      camino del parser (antes solo lo decia cuando entraba la IA).
//
// Correr con:  node test_nombres_proveedores.mjs

import { readFileSync } from 'fs';

const SALTO = String.fromCharCode(10);
const wf = JSON.parse(readFileSync('workflow_tasas_proveedores.json', 'utf8').replace(/^﻿/, ''));
const code = n => wf.nodes.find(x => x.name === n).parameters.jsCode;

// Saca una funcion suelta del codigo REAL del nodo, contando llaves.
function extraer(src, nombre) {
  const firma = 'function ' + nombre + '(';
  const pos = src.indexOf(firma);
  if (pos === -1) throw new Error(`No encontre "${nombre}" en el nodo`);
  const ini = src.indexOf('{', pos);
  let nivel = 0;
  for (let j = ini; j < src.length; j++) {
    if (src[j] === '{') nivel++;
    else if (src[j] === '}') { nivel--; if (nivel === 0) return src.slice(pos, j + 1); }
  }
  throw new Error(`Llaves sin cerrar en "${nombre}"`);
}

const srcInterpretar = code('Interpretar Mensaje');
const alias = srcInterpretar.match(/const ALIAS_PROV = (\[[\s\S]*?\]);/)[1];
const M = new Function(
  alias.replace(/^/, 'const ALIAS_PROV = ') + ';' + SALTO +
  extraer(srcInterpretar, 'nombreOficial') + SALTO +
  extraer(srcInterpretar, 'parecidoPal') + SALTO +
  'return { nombreOficial, parecidoPal };'
)();

let fallos = 0;
const chk = (ok, etiqueta, detalle = '') => {
  if (!ok) fallos++;
  console.log(`  ${ok ? 'OK   ' : 'FALLO'} ${etiqueta.padEnd(50)} ${detalle}`);
};

console.log('=== 1) Cada proveedor con UN solo nombre ===');
const casos = [
  ['ACTIVOS X PERÚ',          'SOLANO'],
  ['activos x peru',          'SOLANO'],
  ['*ACTIVOS X PERÚ 🇵🇪*',     'SOLANO'],
  ['SOLANO',                  'SOLANO'],
  ['CORPORACIÓN GRUPO ELITE', 'ELITE'],
  ['Corporacion Grupo Elite', 'ELITE'],
  ['GRUPO ELITE',             'ELITE'],
  ['ELITE',                   'ELITE'],
  ['MIGUELACHO',              'MIGUELACHO'],   // sin alias: se queda igual
  ['CABALLO',                 'CABALLO'],
  ['Unicambios',              'Unicambios']
];
for (const [entra, sale] of casos) {
  const r = M.nombreOficial(entra);
  chk(r === sale, `"${entra}"`, `-> ${r}`);
}
chk(M.nombreOficial('') === '', 'texto vacio no revienta');
chk(M.nombreOficial(null) === '', 'null no revienta');

console.log('');
console.log('=== 2) La memoria vieja se limpia sola al leerla ===');
// Replica la normalizacion que hace el nodo al leer Redis.
const memoriaSucia = [
  { nombre: 'SOLANO',                  palabras: ['solano', 'activos', 'peru', 'soles', 'usdt'] },
  { nombre: 'ACTIVOS X PERÚ',          palabras: ['activos', 'peru', 'soles', 'usdt', 'colegas'] },
  { nombre: 'CORPORACIÓN GRUPO ELITE', palabras: ['corporacion', 'grupo', 'elite', 'chile', 'brasil'] },
  { nombre: 'CABALLO',                 palabras: ['caballo', 'pagando', 'usdt'] }
];
const vistos = {};
const limpia = [];
for (const c of memoriaSucia) {
  const nom = M.nombreOficial(c.nombre);
  const k = nom.toLowerCase();
  if (vistos[k]) continue;
  vistos[k] = true;
  limpia.push({ nombre: nom, palabras: c.palabras });
}
console.log('     antes :', memoriaSucia.map(x => x.nombre).join(' | '));
console.log('     ahora :', limpia.map(x => x.nombre).join(' | '));
chk(limpia.length === 3, 'de 4 entradas quedan 3 (Solano se fusiono)', `-> ${limpia.length}`);
chk(limpia.filter(x => x.nombre === 'SOLANO').length === 1, 'SOLANO aparece una sola vez');
chk(!limpia.some(x => /ACTIVOS/i.test(x.nombre)), 'ya no existe "ACTIVOS X PERU"');
chk(limpia.some(x => x.nombre === 'ELITE'), 'quedo como "ELITE"');
chk(!limpia.some(x => /CORPORACI/i.test(x.nombre)), 'ya no existe el nombre largo');

console.log('');
console.log('=== 3) No se vuelve a duplicar al aprender ===');
// Mismo proveedor, pero hoy manda el mensaje con una linea extra y Kelvin lo
// titula distinto: NO debe quedar una segunda entrada.
const palabrasHoy = ['activos', 'peru', 'soles', 'usdt', 'colegas', 'montos'];
const nombreHoy = M.nombreOficial('ACTIVOS X PERÚ');
const mismoNombre  = (x) => String(x.nombre).toLowerCase() === nombreHoy.toLowerCase();
const mismoFormato = (x) => Array.isArray(x.palabras)
  && (M.parecidoPal(palabrasHoy, x.palabras) >= 0.7 || M.parecidoPal(x.palabras, palabrasHoy) >= 0.7);
const tras = limpia.filter(x => !mismoNombre(x) && !mismoFormato(x));
tras.unshift({ nombre: nombreHoy, palabras: palabrasHoy });
console.log('     despues:', tras.map(x => x.nombre).join(' | '));
chk(tras.filter(x => x.nombre === 'SOLANO').length === 1, 'SOLANO sigue siendo uno solo');
chk(tras.length === limpia.length, 'no crecio la lista', `-> ${limpia.length} -> ${tras.length}`);
chk(tras.some(x => x.nombre === 'CABALLO') && tras.some(x => x.nombre === 'ELITE'),
    'los otros proveedores siguen intactos');

console.log('');
console.log('=== 4) El resumen del parser dice de quien es cada tasa ===');
const tasas = await (await fetch('https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv&n=' + Date.now())).text();
// Tal como los manda Kelvin: el nombre arriba, linea en blanco, y abajo las tasas.
const mensajes = [
  ['SOLANO', '', 'Perú 3.47 3.56'].join(SALTO),
  ['CABALLO', '', 'Colombia 3200'].join(SALTO)
];
const r = new Function('$', code('Interpretar Mensaje'))(
  (n) => {
    const j = {
      'Telegram Trigger':       { message: { text: mensajes.join(SALTO + SALTO), chat: { id: '1' } } },
      'Combinar Mensajes':      { mensajes, textoFinal: mensajes.join(SALTO + SALTO) },
      'Leer Paises':            { data: tasas },
      'Redis Leer Pendiente':   {},
      'Redis Leer Proveedores': { provFormatos: JSON.stringify(limpia) }
    }[n] || {};
    return { first: () => ({ json: j }), all: () => [{ json: j }] };
  }
)[0].json;

console.log('     ' + String(r.resumen || '(se fue a la IA)').split(SALTO).join(SALTO + '     '));
chk(r.accion === 'nuevo', 'el parser entendio el formato corto', `-> ${r.accion}`);
chk(/\[SOLANO\]/.test(r.resumen || ''), 'dice de quien es la de Peru');
chk(/\[CABALLO\]/.test(r.resumen || ''), 'dice de quien es la de Colombia');

console.log('');
console.log(fallos ? `❌ ${fallos} fallaron` : '✅ Todas las pruebas pasaron');
process.exit(fallos ? 1 : 0);
