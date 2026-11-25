
const _strip = s => s ? String(s).replace(/^\d+[\w\.]*\s*/, '') : '';
const _findNode = (nodes, n) => (nodes || []).find(x => x.name === n || _strip(x.name) === _strip(n));
const _getConn = (conns, n) => {
  if (!conns) return null;
  const k = Object.keys(conns).find(x => x === n || _strip(x) === _strip(n));
  return k ? Reflect.get(conns, k) : null;
};
// Prueba del RESPALDO cuando Google Sheets no contesta (pedido de Kelvin, 23/11).
//
// Lo que paso: el bot lee las tasas y las cuentas del dia de la hoja de Google, y ese dia Google tardo
// 4 minutos en contestar: una clienta recibio su respuesta 5 minutos tarde. Ahora:
//   - cada lectura tiene tope de tiempo (10 s, 2 intentos = unos 20 s en total);
//   - si Google no contesta (o devuelve una pagina de error), se usa la ULTIMA COPIA BUENA que el bot
//     guardo en su memoria: las tasas hasta 3 horas, las cuentas hasta 24 horas;
//   - una copia vieja de las tasas NO se usa (una tasa vieja puede estar mal): el bot avisa que no pudo
//     cargarlas, como siempre;
//   - la fecha de la cuenta y la rotacion se calculan con el dia de HOY, aunque la hoja sea la guardada.
//
// La hoja es INVENTADA (no se descarga nada). Correr con:  node test_respaldo_google.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_ia_atencion.json', 'utf8').replace(/^﻿/, ''));
const nodo = n => _findNode(wf.nodes, n);
const codigo = nodo('Code in JavaScript').parameters.jsCode;

let fallos = 0;
const chk = (ok, etiqueta, detalle) => { if (!ok) fallos++; console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(74) + ' ' + (detalle || '')); };

const TASAS = [
  'Pais,Tasa Envio,Margen Envio,Tasa Recibo,Margen Recibo,Codigo,Moneda,Factor EUR,Factor USDT',
  'Venezuela,1100,6,1130,6,VES,Bolivar,,',
  'Ecuador,1,1,1,1,USD,Dolar,,',
  'Colombia,3600,6,3700,6,COP,Peso colombiano,,'].join('\n');
const esc = s => '"' + s.replace(/"/g, '""') + '"';
const CUENTAS = [
  'Pais,Metodo,Disponible,Datos,Notas,Tipo',
  'Ecuador,Pichincha,si,' + esc('*CUENTA AUTORIZADA USD*\n\n1) 2200000001\n*Pichincha ahorro*\n*Titular Prueba*') + ',,',
  'Colombia,Bancolombia,si,' + esc('1) 5500000001\n*Bancolombia ahorro*\n*Otro Titular*') + ',,'].join('\n');
const PAGINA_DE_ERROR = '<!DOCTYPE html><html><head><title>Error 500</title></head><body>Algo salio mal</body></html>';

// Corre "Code in JavaScript" con lo que devolvieron (o no) las dos consultas a Google y la memoria del bot.
function correr(iso, tasas, cuentas, memoria) {
  const real = Date.now; Date.now = () => new Date(iso).getTime();
  try {
    const $ = n => {
      const uno = j => ({ first: () => ({ json: j }), all: () => [{ json: j }] });
      if (n === 'Consultar Tasas' || _strip(n) === 'Consultar Tasas') return uno(tasas === null ? {} : { data: tasas });
      if (n === 'Consultar Cuentas' || _strip(n) === 'Consultar Cuentas') return uno(cuentas === null ? {} : { data: cuentas });
      if (n === 'Cuando lo Llama el Bot' || _strip(n) === 'Cuando lo Llama el Bot') return uno({ body: { data: { key: { remoteJid: '584121112233@s.whatsapp.net' } } } });
      if (n === 'Webhook Evolution API' || _strip(n) === 'Webhook Evolution API') return uno({ body: { data: { key: { remoteJid: '584121112233@s.whatsapp.net' } } } });
      return { first: () => ({ json: {} }), all: () => [] };
    };
    return new Function('$', '$getWorkflowStaticData', codigo)($, () => memoria)[0].json;
  } finally { Date.now = real; }
}
const PAIS = (r, nombre) => (r.lista || []).find(p => p.Pais === nombre);

console.log('=== 1) TODO BIEN: se usa Google y se guarda la copia ===');
const memoria = {};
const a = correr('2026-11-23T17:00:00Z', TASAS, CUENTAS, memoria);
chk(a.lista.length === 3 && a.respaldo.tasas === false && a.respaldo.cuentas === false, 'con Google bien: 3 paises y sin respaldo', '-> ' + JSON.stringify(a.respaldo));
chk(memoria.csvTasas === TASAS && memoria.csvCuentas === CUENTAS, 'la ultima lectura buena queda guardada (tasas y cuentas)');
chk(a.cuentas.length === 2, 'y entrega las cuentas del dia', '-> ' + a.cuentas.map(c => c.Pais).join(','));
const ts1 = memoria.csvTasasTs;
correr('2026-11-23T17:00:30Z', TASAS, CUENTAS, memoria);
chk(memoria.csvTasasTs === ts1, 'si la hoja es la misma no se reescribe la memoria a cada mensaje (1 vez por minuto)');
correr('2026-11-23T17:01:30Z', TASAS, CUENTAS, memoria);
chk(memoria.csvTasasTs > ts1, 'pasado un minuto si se refresca la fecha de la copia');

console.log('');
console.log('=== 2) GOOGLE NO CONTESTA: se usa la ultima copia buena ===');
{
  const m = JSON.parse(JSON.stringify(memoria));
  const r = correr('2026-11-23T18:00:00Z', null, null, m);
  chk(r.respaldo.tasas === true && r.respaldo.cuentas === true, 'sin respuesta de Google: usa las dos copias', '-> ' + JSON.stringify(r.respaldo));
  chk(r.lista.length === 3 && PAIS(r, 'Venezuela').Envio === PAIS(a, 'Venezuela').Envio && PAIS(r, 'Colombia').Recibo === PAIS(a, 'Colombia').Recibo, 'las tasas salen IGUAL que con Google bien',
      '-> VE envio ' + (PAIS(r, 'Venezuela') || {}).Envio);
  chk(r.cuentas.length === 2 && r.error === null, 'y las cuentas del dia tambien, sin error');
  chk(JSON.stringify(m) === JSON.stringify(memoria) || (m.csvTasas === TASAS && m.csvCuentas === CUENTAS), 'la copia buena NO se pisa con nada');
  const h = correr('2026-11-23T18:00:00Z', PAGINA_DE_ERROR, PAGINA_DE_ERROR, m);
  chk(h.respaldo.tasas === true && h.respaldo.cuentas === true && h.lista.length === 3, 'si Google devuelve una PAGINA DE ERROR en vez de la hoja: igual, la copia', '-> ' + JSON.stringify(h.respaldo));
  chk(m.csvTasas === TASAS && m.csvCuentas === CUENTAS, 'y la pagina de error NO se guarda como copia');
  const v = correr('2026-11-23T18:00:00Z', '', '', m);
  chk(v.respaldo.tasas === true && v.respaldo.cuentas === true, 'respuesta vacia: tambien');
  const s = correr('2026-11-23T18:00:00Z', TASAS, null, JSON.parse(JSON.stringify(memoria)));
  chk(s.respaldo.tasas === false && s.respaldo.cuentas === true && s.cuentas.length === 2, 'solo fallan las cuentas: tasas de Google + cuentas de la copia', '-> ' + JSON.stringify(s.respaldo));
}

console.log('');
console.log('=== 3) LA COPIA SOLO VALE UNAS HORAS ===');
{
  const m = JSON.parse(JSON.stringify(memoria));
  const t3 = correr('2026-11-23T20:00:00Z', null, null, m);          // 3 h despues de la ultima lectura buena (17:01)
  chk(t3.respaldo.tasas === true, 'a las 2 h 59 min: la tasa guardada todavia vale', '-> ' + JSON.stringify(t3.respaldo));
  const t4 = correr('2026-11-23T20:30:00Z', null, null, m);          // 3 h 29 min
  chk(t4.respaldo.tasas === false && t4.lista.length === 0 && /No se recibieron datos de tasas/.test(t4.error), 'pasadas 3 horas: la tasa guardada NO se usa (avisa que no pudo cargarlas)', '-> ' + t4.error);
  const c1 = correr('2026-11-24T14:00:00Z', TASAS, null, m);         // 21 h despues
  chk(c1.respaldo.cuentas === true && c1.cuentas.length === 2, 'las cuentas guardadas aguantan hasta 24 horas (a las 21 h todavia)', '-> ' + JSON.stringify(c1.respaldo));
  const c2 = correr('2026-11-24T18:00:00Z', TASAS, null, m);         // 25 h despues
  chk(c2.respaldo.cuentas === false && c2.cuentas.length === 0 && c2.lista.length === 3, 'pasadas 24 horas: sin cuentas, pero las tasas (de Google) siguen', '-> ' + JSON.stringify(c2.respaldo));
  const sin = correr('2026-11-23T18:00:00Z', null, null, {});
  chk(sin.lista.length === 0 && /No se recibieron datos de tasas/.test(sin.error), 'sin ninguna copia (bot recien reiniciado): avisa que no pudo cargar, como siempre', '-> ' + sin.error);
  const sinMem = new Function('$', codigo)(n => ({ first: () => ({ json: (n === 'Consultar Tasas' || _strip(n) === 'Consultar Tasas') ? { data: TASAS } : {} }), all: () => [] }));
  chk(sinMem[0].json.lista.length === 3, 'si la memoria del bot no esta disponible: sigue funcionando con Google');
}

console.log('');
console.log('=== 4) LA CUENTA GUARDADA TRAE LA FECHA DE HOY ===');
{
  const m = JSON.parse(JSON.stringify(memoria));
  const hoy = correr('2026-11-23T18:00:00Z', null, null, m).cuentas.find(c => c.Pais === 'Ecuador');
  chk(hoy && /_Válida solo hoy, lunes 23 de noviembre_/.test(hoy.Datos), 'el mismo dia: "Válida solo hoy, lunes 23 de noviembre"', '-> ' + (hoy && hoy.Datos.split('\n')[1]));
  const manana = correr('2026-11-24T14:00:00Z', TASAS, null, m).cuentas.find(c => c.Pais === 'Ecuador');   // las tasas de Google; solo las cuentas vienen de la copia
  chk(manana && /_Válida solo hoy, martes 24 de noviembre_/.test(manana.Datos), 'al dia siguiente la fecha cambia sola ("martes 24 de noviembre")', '-> ' + (manana && manana.Datos.split('\n')[1]));
}

console.log('');
console.log('=== 5) LOS NODOS TIENEN TOPE DE TIEMPO ===');
{
  for (const n of ['Consultar Tasas', 'Consultar Cuentas']) {
    const x = nodo(n), t = x.parameters.options.timeout;
    const peor = (t * x.maxTries + x.waitBetweenTries * (x.maxTries - 1)) / 1000;
    chk(t === 10000 && x.maxTries === 2 && x.onError === 'continueRegularOutput' && x.alwaysOutputData === true && peor <= 21,
        n + ': 10 s x 2 intentos = como mucho ' + peor + ' s, y si falla el bot sigue', '-> timeout ' + t + ' maxTries ' + x.maxTries);
  }
  const tool = nodo('Calculadora de Conversion').parameters.jsCode;
  chk(/AbortSignal\.timeout\(15000\)/.test(tool) && /fetch\(_url \+ '&nocache=' \+ Date\.now\(\), _tope\)/.test(tool), 'la calculadora tambien tiene tope si tiene que ir a Google');
  chk(!/__HORAS_RESPALDO/.test(codigo), 'las horas de la copia quedaron escritas en el codigo (3 y 24)', '-> ' + (codigo.match(/HORAS_RESPALDO_TASAS = \d+/) || [''])[0] + ' / ' + (codigo.match(/HORAS_RESPALDO_CUENTAS = \d+/) || [''])[0]);
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
