// Prueba la REGLA DE FIN DE SEMANA de las cuentas de Ecuador, con el codigo REAL del nodo
// "Code in JavaScript" del bot de WhatsApp.
//
// Regla pedida por Kelvin (02/11):
//   - Viernes, sabado y domingo: solo cuentas de Banco de Guayaquil o Banco Pichincha.
//   - El domingo se repite EXACTAMENTE la misma cuenta que se dio el sabado.
//   - Lunes a jueves: rotacion normal entre todas.
//   - Solo aplica a Ecuador; los demas paises rotan igual los 7 dias.

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const codigo = wf.nodes.find(n => n.name === 'Code in JavaScript').parameters.jsCode;

const CSV_TASAS = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv';
const tasas = await (await fetch(CSV_TASAS + '&n=' + Date.now())).text();

// Hoja de cuentas SIMULADA: la real todavia no tiene las de Ecuador cargadas.
const cuentasCSV = [
  'Pais,Metodo,Disponible,Datos,Notas,Tipo',
  'Ecuador,Pichincha,si,"*PICHINCHA Ana*",,',
  'Ecuador,Guayaquil,si,"*GUAYAQUIL Luis*",,',
  'Ecuador,Produbanco,si,"*PRODUBANCO Marta*",,',
  'Ecuador,Pacifico,si,"*PACIFICO Jose*",,',
  'Ecuador,Pichincha,si,"*PICHINCHA Carlos*",,',
  'Venezuela,Banesco,si,"*BANESCO Yaylib*",,',
  'Venezuela,Banesco,si,"*BANESCO Isabel*",,',
  'Venezuela,Venezuela,si,"*VENEZUELA Yban*",,'
].join('\n');

// Corre el nodo fijando el reloj en una fecha concreta
function correrEnFecha(iso) {
  const real = Date.now;
  Date.now = () => new Date(iso).getTime();
  try {
    const $ = (n) => {
      const uno = (j) => ({ first: () => ({ json: j }), all: () => [{ json: j }] });
      if (n === 'Consultar Tasas')   return uno({ data: tasas });
      if (n === 'Consultar Cuentas') return uno({ data: cuentasCSV });
      if (n === 'Webhook Evolution API') return uno({ body: { data: { key: { remoteJid: '584121112233@s.whatsapp.net' } } } });
      return { first: () => ({ json: {} }), all: () => [] };
    };
    return new Function('$', codigo)($)[0].json;
  } finally { Date.now = real; }
}

// Identifica la cuenta SIN el encabezado ni el sello de fecha que el bot le
// agrega al enviarla: aqui importa cual cuenta toca, no como se presenta.
const nombreCuenta = (r, pais) => {
  const c = (r.cuentas || []).find(x => x.Pais.toLowerCase() === pais);
  if (!c) return '(ninguna)';
  const cuerpo = String(c.Datos || '')
    .split('\n')
    .filter(l => !/^\*CUENTA AUTORIZADA/i.test(l.trim()) && !/^_Válida solo hoy/i.test(l.trim()))
    .join(' ')
    .replace(/\*/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return `${c.Metodo} — ${cuerpo}`;
};

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log(`  ${ok ? 'OK   ' : 'FALLO'} ${etiqueta.padEnd(42)} ${detalle}`);
};

// Semana completa. 2026-11-02 es LUNES (hora Ecuador: se usa mediodia para no caer en el borde)
const semana = [
  ['2026-11-02T17:00:00Z', 'lunes'],
  ['2026-11-03T17:00:00Z', 'martes'],
  ['2026-11-04T17:00:00Z', 'miercoles'],
  ['2026-11-05T17:00:00Z', 'jueves'],
  ['2026-11-06T17:00:00Z', 'viernes'],
  ['2026-11-07T17:00:00Z', 'sabado'],
  ['2026-11-08T17:00:00Z', 'domingo']
];

console.log('=== Cuenta de ECUADOR dia por dia ===');
const porDia = {};
for (const [iso, dia] of semana) {
  const r = correrEnFecha(iso);
  porDia[dia] = nombreCuenta(r, 'ecuador');
  console.log(`  ${dia.padEnd(10)} ${porDia[dia]}`);
}

console.log('');
console.log('=== Verificacion ===');
const esFindeOk = (s) => /pichincha|guayaquil/i.test(s);
for (const dia of ['viernes', 'sabado', 'domingo']) {
  chk(esFindeOk(porDia[dia]), `${dia}: solo Guayaquil o Pichincha`, `-> ${porDia[dia]}`);
}
chk(porDia.domingo === porDia.sabado, 'domingo repite la MISMA del sabado',
    `-> sab: ${porDia.sabado}  |  dom: ${porDia.domingo}`);

// De lunes a jueves debe poder salir cualquier banco (no estar restringido)
const entreSemana = ['lunes', 'martes', 'miercoles', 'jueves'].map(d => porDia[d]);
chk(entreSemana.some(s => !esFindeOk(s)), 'entre semana SI puede salir otro banco',
    `-> ${entreSemana.join(' | ')}`);

// Venezuela no se ve afectada: debe rotar los 7 dias sin restriccion
console.log('');
console.log('=== Venezuela (no debe cambiar nada) ===');
const ven = semana.map(([iso, dia]) => [dia, nombreCuenta(correrEnFecha(iso), 'venezuela')]);
ven.forEach(([d, c]) => console.log(`  ${d.padEnd(10)} ${c}`));
const venDom = ven.find(v => v[0] === 'domingo')[1];
const venSab = ven.find(v => v[0] === 'sabado')[1];
chk(venDom !== venSab, 'Venezuela el domingo SI rota (no repite)', `-> sab: ${venSab} | dom: ${venDom}`);

// Si no hay ninguna de Guayaquil/Pichincha, Ecuador NO debe entregar cuenta
console.log('');
console.log('=== Si no hay cuentas de esos bancos el fin de semana ===');
const sinFinde = cuentasCSV.split('\n').filter(l => !/Pichincha|Guayaquil/i.test(l)).join('\n');
const realNow = Date.now;
Date.now = () => new Date('2026-11-07T17:00:00Z').getTime();   // sabado
const r2 = (() => {
  const $ = (n) => {
    const uno = (j) => ({ first: () => ({ json: j }), all: () => [{ json: j }] });
    if (n === 'Consultar Tasas')   return uno({ data: tasas });
    if (n === 'Consultar Cuentas') return uno({ data: sinFinde });
    if (n === 'Webhook Evolution API') return uno({ body: { data: { key: { remoteJid: '584121112233@s.whatsapp.net' } } } });
    return { first: () => ({ json: {} }), all: () => [] };
  };
  return new Function('$', codigo)($)[0].json;
})();
Date.now = realNow;
chk(nombreCuenta(r2, 'ecuador') === '(ninguna)', 'no entrega cuenta de Ecuador (mejor que una mala)',
    `-> ${nombreCuenta(r2, 'ecuador')}`);
chk((r2.avisosCuentas || []).length > 0, 'deja el aviso para diagnosticar', `-> ${(r2.avisosCuentas || [])[0] || '(sin aviso)'}`);
chk(nombreCuenta(r2, 'venezuela') !== '(ninguna)', 'Venezuela sigue dando cuenta normal', `-> ${nombreCuenta(r2, 'venezuela')}`);

console.log('');
console.log(fallos ? `❌ ${fallos} fallaron` : '✅ Todas las pruebas pasaron');
