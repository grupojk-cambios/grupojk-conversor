// Prueba del aviso de fallas de la apertura y el cierre (workflow_apertura_cierre.json).
//
// Por que existe: los nodos que mandan a los grupos ahora tienen "seguir aunque falle", asi
// que un bajon de Evolution ya no tumba el resto del envio. El precio es que la ejecucion
// queda marcada como exitosa aunque algo no haya salido. Los nodos "Revisar Apertura" y
// "Revisar Cierre" son los que avisan por Telegram, y aca se comprueba que:
//   - si todo salio bien NO manda nada (devuelve lista vacia);
//   - si fallo un grupo, dice CUAL grupo y por que;
//   - si fallo el estado de WhatsApp, tambien lo dice;
//   - si un nodo ni corrio, lo reporta en vez de reventar;
//   - el texto sale limpio de * _ ` [ ] , que a Telegram le rompen el mensaje.
//
// Correr con:  node test_aviso_apertura.mjs

import { readFileSync } from 'fs';

const SALTO = String.fromCharCode(10);
const wf = JSON.parse(readFileSync('workflow_apertura_cierre.json', 'utf8').replace(/^﻿/, ''));
const code = n => wf.nodes.find(x => x.name === n).parameters.jsCode;

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(52) + ' ' + (detalle || ''));
};

const GRUPOS = [
  '593961230380-1588719606@g.us',
  '120363291497664389@g.us',
  '593961230380-1588719963@g.us'
];

// Simula el nodo. "salidas" dice que devolvio cada nodo; si un nombre no esta, se hace de
// cuenta que ese nodo NI CORRIO (igual que en n8n, donde $('...') revienta).
function correr(nombreNodo, salidas) {
  const $ = (n) => {
    if (!(n in salidas)) throw new Error('Node "' + n + '" not executed');
    return { all: () => salidas[n].map(json => ({ json })) };
  };
  const $now = { toFormat: () => '14/11 09:01' };
  return new Function('$', '$now', code(nombreNodo))($, $now);
}

// Atajos para armar las salidas de un envio a los 3 grupos.
const todoBien  = GRUPOS.map(() => ({ key: { id: 'ABC' }, status: 'PENDING' }));
const grupos3   = GRUPOS.map(g => ({ grupos: g }));
const errEvo    = '500 - {"status":500,"error":"Internal Server Error","response":{"message":["Error: Connection Closed"]}}';

console.log('=== 1) Todo salio bien -> no manda nada ===');
{
  const r = correr('Revisar Apertura', {
    'Enviar Sticker (Grupos)':  todoBien,
    'Separar Grupos (Apertura)': grupos3,
    'Estado Texto (Apertura)':  [{ key: { id: 'X' } }]
  });
  chk(Array.isArray(r) && r.length === 0, 'no sale ningun mensaje a Telegram', '-> ' + r.length + ' items');
}

console.log('');
console.log('=== 2) Fallo UN grupo -> dice cual ===');
{
  const envios = todoBien.slice();
  envios[1] = { error: errEvo };
  const r = correr('Revisar Apertura', {
    'Enviar Sticker (Grupos)':  envios,
    'Separar Grupos (Apertura)': grupos3,
    'Estado Texto (Apertura)':  [{ key: { id: 'X' } }]
  });
  chk(r.length === 1, 'manda un mensaje', '-> ' + r.length);
  const t = r.length ? r[0].json.texto : '';
  console.log('     ' + t.split(SALTO).join(SALTO + '     '));
  chk(t.indexOf(GRUPOS[1]) !== -1, 'nombra el grupo que fallo');
  chk(t.indexOf(GRUPOS[0]) === -1 && t.indexOf(GRUPOS[2]) === -1, 'no nombra los que si salieron');
  chk(/Connection Closed/.test(t), 'dice el motivo');
  chk(/APERTURA/.test(t), 'dice que fue la apertura');
  chk(r[0].json.chatId === '627887509', 'va al chat de Kelvin', '-> ' + r[0].json.chatId);
}

console.log('');
console.log('=== 3) Fallo el estado de WhatsApp ===');
{
  const r = correr('Revisar Cierre', {
    'Enviar Imagen (Grupos)':  todoBien,
    'Separar Grupos (Cierre)': grupos3,
    'Estado Imagen (Cierre)':  [{ error: errEvo }]
  });
  const t = r.length ? r[0].json.texto : '';
  chk(r.length === 1, 'manda un mensaje', '-> ' + r.length);
  chk(/Estado de WhatsApp/.test(t), 'dice que fue el estado');
  chk(/CIERRE/.test(t), 'dice que fue el cierre');
  chk(!/Grupo /.test(t), 'no inventa fallas de grupos');
}

console.log('');
console.log('=== 4) Fallo TODO ===');
{
  const r = correr('Revisar Cierre', {
    'Enviar Imagen (Grupos)':  GRUPOS.map(() => ({ error: errEvo })),
    'Separar Grupos (Cierre)': grupos3,
    'Estado Imagen (Cierre)':  [{ error: errEvo }]
  });
  const t = r.length ? r[0].json.texto : '';
  console.log('     ' + t.split(SALTO).join(SALTO + '     '));
  chk((t.match(/- Grupo /g) || []).length === 3, 'lista los 3 grupos');
  chk(/Estado de WhatsApp/.test(t), 'y tambien el estado');
}

console.log('');
console.log('=== 5) Un nodo ni corrio -> lo reporta, no revienta ===');
{
  // El estado no llego a ejecutarse (la ejecucion se corto antes).
  const r = correr('Revisar Apertura', {
    'Enviar Sticker (Grupos)':  todoBien,
    'Separar Grupos (Apertura)': grupos3
  });
  chk(r.length === 1 && /estado de WhatsApp ni se intento/.test(r[0].json.texto),
      'avisa que el estado no se intento');

  // El envio a los grupos no llego a ejecutarse.
  const r2 = correr('Revisar Apertura', { 'Estado Texto (Apertura)': [{ key: { id: 'X' } }] });
  chk(r2.length === 1 && /No se mando nada a los grupos/.test(r2[0].json.texto),
      'avisa que no se mando nada a los grupos');
}

console.log('');
console.log('=== 6) El texto sale limpio para Telegram ===');
{
  // Telegram interpreta * _ ` [ ] como formato: si viene uno suelto responde 400 y el aviso
  // NO llega. Tienen que salir filtrados.
  const r = correr('Revisar Apertura', {
    'Enviar Sticker (Grupos)':  [{ error: 'falla con *asterisco* y _guion_ y `tilde` y [corchete]' }],
    'Separar Grupos (Apertura)': [{ grupos: GRUPOS[0] }],
    'Estado Texto (Apertura)':  [{ key: { id: 'X' } }]
  });
  const t = r[0].json.texto;
  console.log('     ' + t.split(SALTO)[2]);
  chk(!/[*_`\[\]]/.test(t), 'no queda ningun caracter que rompa Telegram');
  chk(/asterisco/.test(t) && /corchete/.test(t), 'pero el texto del error se entiende igual');
}

console.log('');
console.log('=== 7) Un error raro (objeto, null) no tumba el nodo ===');
{
  const r = correr('Revisar Apertura', {
    'Enviar Sticker (Grupos)':  [{ error: { message: 'algo feo' } }, { error: null }],
    'Separar Grupos (Apertura)': [{ grupos: GRUPOS[0] }, { grupos: GRUPOS[1] }],
    'Estado Texto (Apertura)':  [{ key: { id: 'X' } }]
  });
  const t = r[0].json.texto;
  chk(/algo feo/.test(t), 'un error con .message se lee bien');
  chk(/sin detalle/.test(t), 'un error null no revienta');
}

console.log('');
console.log(fallos ? (fallos + ' fallaron') : 'Todas las pruebas pasaron');
process.exit(fallos ? 1 : 0);
