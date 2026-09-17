// Disena y prueba el reconocimiento de proveedor por la FORMA del mensaje, contra los mensajes
// REALES que Kelvin mando al bot entre el 25/08 y el 07/09.
// Objetivo: que el bot sepa de que proveedor viene un mensaje aunque Kelvin no le ponga el nombre.

import { readFileSync } from 'fs';

const RUTA = 'C:/Users/USER/AppData/Local/Temp/claude/C--Users-USER-Documents-APP-PARA-CAMBIOS-JK-CONVERSOR/8c796fe4-2b8d-4ce4-81b8-dda81e14fb6a/scratchpad/mensajes_reales.json';
const msgs = JSON.parse(readFileSync(RUTA, 'utf8')).map(m => ({ ...m, id: Number(m.id) }));

// ---------- El algoritmo que iria dentro del nodo ----------

// Palabras que cambian solas y NO sirven para identificar (dias, saludos, meses)
const IGNORAR = new Set([
  'lunes','martes','miercoles','jueves','viernes','sabado','domingo',
  'buen','buenos','buena','dias','dia','tardes','noches','hoy','ayer',
  'enero','febrero','marzo','abril','mayo','junio','julio','agosto',
  'septiembre','octubre','noviembre','diciembre','tasa','tasas','actualizacion'
]);

// Conjunto de palabras caracteristicas del mensaje (solo letras, sin numeros ni emojis)
function palabrasClave(txt) {
  const limpio = String(txt || '')
    .toLowerCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z]+/g, ' ');
  const set = new Set();
  for (const w of limpio.split(' ')) {
    if (w.length >= 4 && !IGNORAR.has(w)) set.add(w);
  }
  return set;
}

// Parecido entre dos conjuntos (Jaccard): 1 = identicos, 0 = nada en comun
function parecido(a, b) {
  if (!a.size || !b.size) return 0;
  let comunes = 0;
  for (const w of a) if (b.has(w)) comunes++;
  return comunes / (a.size + b.size - comunes);
}

const UMBRAL = 0.5;

// Busca en los proveedores ya conocidos cual se parece mas
function reconocer(txt, conocidos) {
  const p = palabrasClave(txt);
  let mejor = null, mejorPunt = 0;
  for (const c of conocidos) {
    const punt = parecido(p, new Set(c.palabras));
    if (punt > mejorPunt) { mejorPunt = punt; mejor = c; }
  }
  return mejorPunt >= UMBRAL ? { nombre: mejor.nombre, punt: mejorPunt } : null;
}

// ---------- PRUEBA CONTRA LOS MENSAJES REALES ----------

// Lo que Kelvin etiqueto a mano el 28/08 (primera vez que nombro cada uno)
const aprendidos = [
  { nombre: 'Unicambios',  id: 1209 },
  { nombre: 'Miguelacho',  id: 1208 },
  { nombre: 'Solano',      id: 1207 }
];
const conocidos = aprendidos.map(a => {
  const m = msgs.find(x => x.id === a.id);
  return { nombre: a.nombre, palabras: [...palabrasClave(m.texto)] };
});

console.log('=== Proveedores aprendidos el 28/08 (Kelvin les puso el nombre a mano) ===');
conocidos.forEach(c => console.log('  ' + c.nombre.padEnd(14) + ' -> ' + c.palabras.slice(0, 8).join(', ') + '...'));

console.log('');
console.log('=== Ahora: mensajes de OTROS dias, SIN nombre. Los reconoce? ===');
const esperado = {
  1318: 'Unicambios', 1188: 'Unicambios', 1246: 'Unicambios', 1250: 'Unicambios', 1282: 'Unicambios', 1299: 'Unicambios', 1223: 'Unicambios',
  1319: 'Miguelacho', 1186: 'Miguelacho', 1245: 'Miguelacho', 1249: 'Miguelacho', 1281: 'Miguelacho', 1298: 'Miguelacho', 1222: 'Miguelacho',
  1316: 'Solano'
};
let ok = 0, mal = 0;
for (const [id, esp] of Object.entries(esperado)) {
  const m = msgs.find(x => x.id === Number(id));
  if (!m) continue;
  const r = reconocer(m.texto, conocidos);
  const acerto = r && r.nombre === esp;
  if (acerto) ok++; else mal++;
  const l1 = (m.texto.split('\n').find(l => l.trim()) || '').trim().slice(0, 26);
  console.log(`  ${acerto ? 'OK   ' : 'FALLO'} ${m.fecha} #${id} "${l1}"`.padEnd(52) +
    ' -> ' + (r ? `${r.nombre} (${r.punt.toFixed(2)})` : 'NO RECONOCIDO') + (acerto ? '' : `   [esperaba ${esp}]`));
}

console.log('');
console.log('=== Y los que NO debe confundir (Grupo Elite trae su propio nombre, y los formatos cortos) ===');
for (const id of [1317, 1280, 1320, 1210, 1240]) {
  const m = msgs.find(x => x.id === id);
  if (!m) continue;
  const r = reconocer(m.texto, conocidos);
  const l1 = (m.texto.split('\n').find(l => l.trim()) || '').trim().slice(0, 26);
  const bien = !r;
  if (bien) ok++; else mal++;
  console.log(`  ${bien ? 'OK   ' : 'FALLO'} ${m.fecha} #${id} "${l1}"`.padEnd(52) +
    ' -> ' + (r ? `lo confundio con ${r.nombre} (${r.punt.toFixed(2)})` : 'no lo asocia a ninguno (correcto)'));
}

console.log('');
console.log(mal ? `❌ ${mal} fallaron, ${ok} bien` : `✅ Los ${ok} casos correctos`);
