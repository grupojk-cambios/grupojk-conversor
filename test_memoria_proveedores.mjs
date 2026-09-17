// Prueba el CICLO COMPLETO de la memoria de proveedores, ejecutando el codigo REAL de los nodos
// tal como quedo en el JSON del workflow, contra los mensajes REALES de Kelvin (25/08 - 07/09).
//
// Lo que se comprueba:
//   1. Kelvin manda el mensaje CON el nombre puesto a mano  -> el bot aprende la forma
//   2. Otro dia manda el MISMO proveedor SIN nombre         -> el bot lo reconoce solo
//   3. No confunde un proveedor con otro

import { readFileSync } from 'fs';

const RUTA_MSGS = 'C:/Users/USER/AppData/Local/Temp/claude/C--Users-USER-Documents-APP-PARA-CAMBIOS-JK-CONVERSOR/8c796fe4-2b8d-4ce4-81b8-dda81e14fb6a/scratchpad/mensajes_reales.json';
const msgs = JSON.parse(readFileSync(RUTA_MSGS, 'utf8')).map(m => ({ ...m, id: Number(m.id) }));
const wf = JSON.parse(readFileSync('workflow_tasas_proveedores.json', 'utf8').replace(/^\uFEFF/, ''));
const cod = n => wf.nodes.find(x => x.name === n).parameters.jsCode;

const CSV = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv';
const csv = await (await fetch(CSV + '&n=' + Date.now())).text();
const txt = id => msgs.find(m => m.id === id).texto;

// --- Ejecuta "Interpretar Mensaje" con una memoria de proveedores dada ---
function interpretar(textoMsg, memoria) {
  const $ = (n) => {
    const uno = (j) => ({ first: () => ({ json: j }), all: () => [{ json: j }] });
    if (n === 'Telegram Trigger')       return uno({ message: { text: textoMsg, chat: { id: 627887509 } } });
    if (n === 'Redis Leer Pendiente')   return uno({ pendienteRaw: '' });
    if (n === 'Redis Leer Proveedores') return uno({ provFormatos: JSON.stringify(memoria) });
    if (n === 'Leer Paises')            return uno({ data: csv });
    if (n === 'Combinar Mensajes')      return uno({ textoFinal: textoMsg, mensajes: [textoMsg] });
    return uno({});
  };
  return new Function('$', cod('Interpretar Mensaje'))($);
}

// --- Ejecuta "Armar Borrador IA" simulando la respuesta de OpenAI ---
function aprender(itemsIM, respuestasIA, memoria) {
  const items = respuestasIA.map(r => ({ json: { choices: [{ message: { content: JSON.stringify(r) } }] } }));
  const $ = (n) => {
    if (n === 'Interpretar Mensaje')    return { first: () => itemsIM[0], all: () => itemsIM };
    if (n === 'Leer Paises')            return { first: () => ({ json: { data: csv } }) };
    if (n === 'Redis Leer Proveedores') return { first: () => ({ json: { provFormatos: JSON.stringify(memoria) } }) };
    return { first: () => ({ json: {} }), all: () => [] };
  };
  const $input = { all: () => items };
  return new Function('$', '$json', '$input', cod('Armar Borrador IA'))($, items[0].json, $input)[0].json;
}

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log(`  ${ok ? 'OK   ' : 'FALLO'} ${etiqueta.padEnd(52)} ${detalle}`);
};

// ================== PASO 1: aprende de los mensajes etiquetados del 28/08 ==================
console.log('=== PASO 1: Kelvin pone el nombre a mano (28/08) -> el bot aprende la forma ===');
let memoria = [];
for (const [id, nombreEsperado] of [[1209, 'Unicambios'], [1208, 'Miguelacho'], [1207, 'Solano']]) {
  const its = interpretar(txt(id), memoria);
  const salida = aprender(its, [{ proveedores: [{ nombre: nombreEsperado, filas: [{ pais: 'México', envio: 16.2, recibo: 18.1 }] }] }], memoria);
  memoria = JSON.parse(salida.provFormatosJson);
  const guardado = memoria.find(p => p.nombre === nombreEsperado);
  chk(!!guardado && guardado.palabras.length >= 3, `aprende "${nombreEsperado}"`,
      guardado ? `${guardado.palabras.length} palabras: ${guardado.palabras.slice(0, 5).join(', ')}...` : 'NO SE GUARDO');
}

console.log('');
console.log(`  Memoria: ${memoria.length} proveedores -> ${memoria.map(p => p.nombre).join(', ')}`);

// ================== PASO 2: otros dias SIN nombre -> debe reconocerlos ==================
console.log('');
console.log('=== PASO 2: otros dias, SIN escribir el nombre -> lo reconoce solo? ===');
const casos = [
  [1318, 'Unicambios', '09-07'], [1188, 'Unicambios', '08-25'], [1246, 'Unicambios', '09-01'],
  [1282, 'Unicambios', '09-03'], [1299, 'Unicambios', '09-04'],
  [1319, 'Miguelacho', '09-07'], [1186, 'Miguelacho', '08-25'], [1245, 'Miguelacho', '09-01'],
  [1281, 'Miguelacho', '09-03'], [1298, 'Miguelacho', '09-04'],
  [1316, 'Solano', '09-07']
];
for (const [id, esperado, fecha] of casos) {
  const its = interpretar(txt(id), memoria);
  const it = its[0].json;
  const l1 = (txt(id).split('\n').find(l => l.trim()) || '').trim().slice(0, 22);
  chk(it.accion === 'ia' && it.nombreConocido === esperado, `${fecha} "${l1}"`,
      `-> ${it.nombreConocido || '(no reconocido)'}`);
}

// ================== PASO 3: no debe confundirse ==================
console.log('');
console.log('=== PASO 3: los que NO debe asociar a ningun proveedor conocido ===');
for (const [id, quees] of [[1317, 'Grupo Elite (trae su nombre)'], [1320, 'formato corto Peru'], [1240, 'formato corto Cop']]) {
  const its = interpretar(txt(id), memoria);
  const it = its[0].json;
  chk(!it.nombreConocido, quees, `-> ${it.nombreConocido || 'ninguno (correcto)'}`);
}

// ================== PASO 4: "si" sin nada pendiente ==================
console.log('');
console.log('=== PASO 4: decir "Si" cuando ya no hay nada pendiente (el bug de estos dias) ===');
for (const t of ['Si', 'si', 'No', 'dale']) {
  const r = interpretar(t, memoria)[0].json;
  chk(r.accion === 'sinPendiente', `"${t}" sin pendiente`, `-> accion=${r.accion}`);
}

// ================== PASO 5: regla automatica de Jesus (Venezuela, recibo = envio + 20) ==================
console.log('');
console.log('=== PASO 5: Jesus manda solo el envio -> el recibo debe salir +20 ===');
const jesus = (envio) => aprender(
  [{ json: { chatId: '627887509', textoOriginal: `Jesus\nVenezuela\n\n${envio}` } }],
  [{ proveedores: [{ nombre: 'Jesus', filas: [{ pais: 'Venezuela', envio, recibo: null }] }] }],
  []
);
for (const [envio, esperado] of [[955, 975], [950, 970], [960, 980]]) {
  const r = jesus(envio);
  const f = r.filas.find(x => x.Pais === 'Venezuela');
  const ok = f && f['Tasa Envio'] === envio && f['Tasa Recibo'] === esperado;
  chk(ok, `Jesus manda ${envio}`, `-> envio ${f?.['Tasa Envio']}, recibo ${f?.['Tasa Recibo']} (esperado ${esperado})`);
}
// Debe avisar que fue calculado, y el borrador debe traer los dos numeros
const rj = jesus(955);
chk(/calculado: envio \+20/.test(rj.resumen), 'avisa que el recibo es calculado', '-> ' + (rj.resumen.split('\n')[2] || '').trim());
chk(/Venezuela 955 975/.test(rj.borrador), 'el borrador trae envio y recibo', '-> ' + rj.borrador);

// Si Jesus SI manda el recibo, no se debe tocar
const rj2 = aprender(
  [{ json: { chatId: '627887509', textoOriginal: 'Jesus\nVenezuela\n955 990' } }],
  [{ proveedores: [{ nombre: 'Jesus', filas: [{ pais: 'Venezuela', envio: 955, recibo: 990 }] }] }], []);
const f2 = rj2.filas.find(x => x.Pais === 'Venezuela');
chk(f2 && f2['Tasa Recibo'] === 990, 'si Jesus manda recibo, se respeta', `-> recibo ${f2?.['Tasa Recibo']}`);

// La regla NO debe aplicar a otro proveedor ni a otro pais
const otro = aprender(
  [{ json: { chatId: '627887509', textoOriginal: 'Caballo\nVenezuela\n955' } }],
  [{ proveedores: [{ nombre: 'Caballo', filas: [{ pais: 'Venezuela', envio: 955, recibo: null }] }] }], []);
const fo = otro.filas.find(x => x.Pais === 'Venezuela');
chk(fo && fo['Tasa Recibo'] === undefined, 'otro proveedor NO recibe el +20', `-> recibo ${fo?.['Tasa Recibo'] ?? '(ninguno, correcto)'}`);

const otroPais = aprender(
  [{ json: { chatId: '627887509', textoOriginal: 'Jesus\nColombia\n3060' } }],
  [{ proveedores: [{ nombre: 'Jesus', filas: [{ pais: 'Colombia', envio: 3060, recibo: null }] }] }], []);
const fp = otroPais.filas.find(x => x.Pais === 'Colombia');
chk(fp && fp['Tasa Recibo'] === undefined, 'Jesus en otro pais NO recibe el +20', `-> recibo ${fp?.['Tasa Recibo'] ?? '(ninguno, correcto)'}`);

// ============ PASO 6: Jesus manda SOLO el numero, sin decir el pais (caso real 07/09) ============
console.log('');
console.log('=== PASO 6: Jesus no escribe "Venezuela", solo el numero ===');

// 6a) Por el parser normal (sin gastar IA): "Jesus" + numero suelto
const porParser = (texto) => {
  const r = interpretar(texto, memoria)[0].json;
  const f = (r.filas || []).find(x => x.Pais === 'Venezuela');
  return { accion: r.accion, envio: f && f['Tasa Envio'], recibo: f && f['Tasa Recibo'], resumen: r.resumen };
};
for (const [texto, etiqueta] of [
  ['Jesus\n\n\n955', 'bloque "Jesus" + 955 (como llega de Telegram)'],
  ['jesus 955',      'una linea: jesus 955'],
  ['Jesus\n955',     'dos lineas'],
]) {
  const r = porParser(texto);
  chk(r.envio === 955 && r.recibo === 975, etiqueta, `-> envio ${r.envio}, recibo ${r.recibo}`);
}
// Debe avisar que el recibo lo calculo el
const av = porParser('jesus 955');
chk(/recibo calculado: envio \+20/.test(av.resumen || ''), 'avisa que lo calculo', '-> ' + (av.resumen || '').trim());

// Si manda los dos numeros, se respetan
const dos = porParser('jesus 955 990');
chk(dos.envio === 955 && dos.recibo === 990, 'si manda los dos numeros, los respeta', `-> envio ${dos.envio}, recibo ${dos.recibo}`);

// 6b) Por la rama de IA: la IA devuelve filas VACIAS (no sabe el pais) y el codigo lo resuelve
const iaVacia = aprender(
  [{ json: { chatId: '627887509', textoOriginal: 'Jesus\n\n\n955' } }],
  [{ proveedores: [{ nombre: 'Jesus', filas: [] }] }], []);
const fv = (iaVacia.filas || []).find(x => x.Pais === 'Venezuela');
chk(fv && fv['Tasa Envio'] === 955 && fv['Tasa Recibo'] === 975,
    'rama IA: filas vacias -> se arma sola', `-> ${fv ? `envio ${fv['Tasa Envio']}, recibo ${fv['Tasa Recibo']}` : 'NADA'}`);

// Y que el bloque "Colombia / 3100 / 3130" (numeros sueltos) tambien funcione
const colSueltos = interpretar('Colombia\n3100\n3130', memoria)[0].json;
const fc = (colSueltos.filas || []).find(x => x.Pais === 'Colombia');
chk(fc && fc['Tasa Envio'] === 3100 && fc['Tasa Recibo'] === 3130,
    'numeros sueltos en bloque: Colombia/3100/3130', `-> envio ${fc?.['Tasa Envio']}, recibo ${fc?.['Tasa Recibo']}`);

// La fila que se escribe en el Sheet NO debe traer campos de mas
const filaLimpia = Object.keys((porParser('jesus 955'), interpretar('jesus 955', memoria)[0].json.filas[0]));
chk(filaLimpia.every(k => ['Pais','Tasa Envio','Tasa Recibo'].includes(k)),
    'la fila del Sheet no trae campos extra', '-> ' + filaLimpia.join(', '));

console.log('');
console.log(fallos ? `❌ ${fallos} fallaron` : '✅ Todas las pruebas pasaron');
