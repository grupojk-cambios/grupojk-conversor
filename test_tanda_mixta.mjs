// Prueba el caso REAL del 23/09 que se perdio 3 proveedores.
// Kelvin mando 4 mensajes seguidos: Grupo Elite, Miguelacho, Solano y "Jesus 960".
// El parser entendio SOLO el de Jesus (por la regla) y con eso dio por leido todo -> nunca llamo
// a la IA -> los otros 3 proveedores se perdieron en silencio.
// Ahora debe: entender Jesus por su cuenta Y mandar los otros 3 a la IA.

import { readFileSync } from 'fs';

const RUTA = 'pruebas/tanda_23sep.json';
const mensajes = JSON.parse(readFileSync(RUTA, 'utf8'));
const wf = JSON.parse(readFileSync('workflow_tasas_proveedores.json', 'utf8').replace(/^\uFEFF/, ''));
const cod = n => wf.nodes.find(x => x.name === n).parameters.jsCode;

const CSV = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv';
const csv = await (await fetch(CSV + '&n=' + Date.now())).text();

function interpretar(lista) {
  const $ = (n) => {
    const uno = (j) => ({ first: () => ({ json: j }), all: () => [{ json: j }] });
    if (n === 'Telegram Trigger')       return uno({ message: { text: lista.join('\n\n'), chat: { id: 627887509 } } });
    if (n === 'Redis Leer Pendiente')   return uno({ pendienteRaw: '' });
    if (n === 'Redis Leer Proveedores') return uno({ provFormatos: '[]' });
    if (n === 'Leer Paises')            return uno({ data: csv });
    if (n === 'Combinar Mensajes')      return uno({ textoFinal: lista.join('\n\n'), mensajes: lista });
    return uno({});
  };
  return new Function('$', cod('Interpretar Mensaje'))($);
}

function armarBorrador(itemsIM, respuestasIA) {
  const items = respuestasIA.map(r => ({ json: { choices: [{ message: { content: JSON.stringify(r) } }] } }));
  const $ = (n) => {
    if (n === 'Interpretar Mensaje')    return { first: () => itemsIM[0], all: () => itemsIM };
    if (n === 'Leer Paises')            return { first: () => ({ json: { data: csv } }) };
    if (n === 'Redis Leer Proveedores') return { first: () => ({ json: { provFormatos: '[]' } }) };
    return { first: () => ({ json: {} }), all: () => [] };
  };
  return new Function('$', '$json', '$input', cod('Armar Borrador IA'))($, items[0].json, { all: () => items })[0].json;
}

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log(`  ${ok ? 'OK   ' : 'FALLO'} ${etiqueta.padEnd(48)} ${detalle}`);
};

console.log('=== Los 4 mensajes del 23/09 ===');
mensajes.forEach((m, i) => {
  const l1 = (m.split('\n').find(l => l.trim()) || '').trim().slice(0, 30);
  console.log(`  ${i + 1}) ${l1}`);
});

console.log('');
console.log('=== Que hace el bot AHORA ===');
const items = interpretar(mensajes);
const j0 = items[0].json;

chk(j0.accion === 'ia', 'manda los no entendidos a la IA', `-> accion=${j0.accion}`);
chk(items.length === 3, 'son 3 mensajes para la IA (Elite, Miguelacho, Solano)', `-> ${items.length} llamadas`);

const previas = j0.filasPrevias || [];
const ven = previas.find(f => f.Pais === 'Venezuela');
chk(!!ven && ven.envio === 960 && ven.recibo === 980,
    'Jesus NO se pierde: viaja como fila previa', ven ? `-> envio ${ven.envio}, recibo ${ven.recibo} (${ven.prov})` : '-> SE PERDIO');

// Ninguno de los 3 que van a la IA debe ser el de Jesus
const vaJesus = items.some(it => /^jesus\s*$/im.test(it.json.textoOriginal.split('\n')[0] || ''));
chk(!vaJesus, 'no gasta IA con el mensaje de Jesus', `-> ${vaJesus ? 'lo manda (mal)' : 'lo resolvio solo (bien)'}`);

// ===== Y al juntar con lo que devuelve la IA, deben estar TODOS =====
console.log('');
console.log('=== Resultado final (IA + lo que el parser ya sabia) ===');
const respuestas = [
  { proveedores: [{ nombre: 'CORPORACIÓN GRUPO ELITE', filas: [
    { pais: 'Colombia', envio: 2989, recibo: 3193 },
    { pais: 'Chile',    envio: 891,  recibo: 1005 },
    { pais: 'Brasil',   envio: 4.99, recibo: 5.41 }] }] },
  { proveedores: [{ nombre: 'Miguelacho', filas: [
    { pais: 'México',   envio: null, recibo: 18.80 },
    { pais: 'Colombia', envio: 3060, recibo: null }] }] },
  { proveedores: [{ nombre: 'ACTIVOS X PERÚ', filas: [
    { pais: 'Perú', envio: 3.33, recibo: 3.41 }] }] }
];
const fin = armarBorrador(items, respuestas);
const paises = fin.filas.map(f => f.Pais);
console.log('  Paises en el borrador: ' + paises.join(', '));

for (const p of ['Venezuela', 'Colombia', 'Chile', 'Brasil', 'México', 'Perú']) {
  chk(paises.includes(p), `esta ${p}`, '');
}
const fVen = fin.filas.find(f => f.Pais === 'Venezuela');
chk(fVen && fVen['Tasa Envio'] === 960 && fVen['Tasa Recibo'] === 980,
    'Venezuela conserva lo de Jesus', `-> ${fVen ? `${fVen['Tasa Envio']} / ${fVen['Tasa Recibo']}` : 'NO ESTA'}`);
chk(/Jesus/.test(fin.resumen), 'el resumen dice que vino de Jesus', '');

console.log('');
console.log('  --- borrador ---');
console.log(fin.borrador.split('\n').map(l => '  ' + l).join('\n'));

// ===== Si TODO es formato corto tuyo, no debe gastar IA =====
console.log('');
console.log('=== Si mandas solo tu formato corto: no debe llamar a la IA ===');
const corto = interpretar(['Colombia 3140 3200\nVenezuela 960 980\nPerú 3.33 3.41'])[0].json;
chk(corto.accion === 'nuevo', 'formato corto -> sin IA', `-> accion=${corto.accion}`);
chk((corto.filas || []).length === 3, 'entendio los 3 paises', `-> ${(corto.filas || []).length}`);

// ===== Jesus solo, sin nada mas: tampoco debe gastar IA =====
const soloJesus = interpretar(['Jesus\n\n960'])[0].json;
chk(soloJesus.accion === 'nuevo', 'Jesus solo -> sin IA', `-> accion=${soloJesus.accion}`);

console.log('');
console.log(fallos ? `❌ ${fallos} fallaron` : '✅ Todas las pruebas pasaron');
