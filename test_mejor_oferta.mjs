// Prueba de la eleccion de MEJOR OFERTA (nodo "Armar Borrador IA").
// Criterio del usuario: ENVIO gana el mas ALTO, RECIBO gana el mas BAJO.
// Se simula la respuesta de OpenAI con los datos REALES de los 3 proveedores del 10/08.

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_tasas_proveedores.json', 'utf8').replace(/^﻿/, ''));
const codigo = wf.nodes.find(n => n.name === 'Armar Borrador IA').parameters.jsCode;

const CSV = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv';
const csv = await (await fetch(CSV + '&n=' + Date.now())).text();

// Acepta una respuesta o VARIAS (una por cada llamada a la IA, que ahora es 1 por proveedor).
function correr(...respuestasIA) {
  const $ = (nombre) => ({
    first: () => {
      if (nombre === 'Interpretar Mensaje') return { json: { chatId: '627887509', errores: '' } };
      if (nombre === 'Leer Paises') return { json: { data: csv } };
      return { json: {} };
    }
  });
  const items = respuestasIA.map(r => ({ json: { choices: [{ message: { content: JSON.stringify(r) } }] } }));
  const $input = { all: () => items };
  const $json = items[0].json;
  const fn = new Function('$', '$json', '$input', codigo);
  return fn($, $json, $input)[0].json;
}

// Datos REALES de los 3 mensajes del 10/08, con la clasificacion CORRECTA de direccion:
//   "USDT RECIBO" = el proveedor recibe USDT y entrega moneda local  -> ENVIO para nosotros
//   "USDT DOY"    = el proveedor da USDT y cobra moneda local        -> RECIBO para nosotros
//   "RETIROS"     -> ENVIO   |   "RECIBIENDO DEPOSITOS" -> RECIBO
// Verificado contra lo que Kelvin cargo ese dia (Brasil envio 5.00 salio de "5.00 USDT RECIBO").
const tresProveedores = {
  proveedores: [
    {
      nombre: 'Grupo Elite',                              // USDT/COP = envio | COP/USDT = recibo
      filas: [
        { pais: 'Colombia',  envio: 2989,  recibo: 3193 },
        { pais: 'Argentina', envio: 1477,  recibo: 1666 },
        { pais: 'Brasil',    envio: 4.90,  recibo: 5.38 },
        { pais: 'México',    envio: 15.99, recibo: 18.78 },
        { pais: 'Chile',     envio: 877,   recibo: 990 }
      ]
    },
    {
      nombre: 'Tasa MX/BR/CO',
      filas: [
        { pais: 'México',   envio: null, recibo: 19.40 },  // "19.40 USDT DOY"    -> RECIBO
        { pais: 'Brasil',   envio: 5.00, recibo: null  },  // "5.00 USDT RECIBO"  -> ENVIO
        { pais: 'Colombia', envio: 3060, recibo: null  }   // "3060 USDT RECIBO"  -> ENVIO
      ]
    },
    {
      nombre: 'Retiros MX',
      filas: [
        { pais: 'México', envio: 16.40, recibo: 18.40 }    // RETIROS / RECIBIENDO DEPOSITOS
      ]
    },
    {
      nombre: 'Suelto',
      filas: [
        { pais: 'Colombia', envio: 3100, recibo: null }    // "3.100 pagando usdt x Cop" -> ENVIO
      ]
    }
  ]
};

const r = correr(tresProveedores);

console.log('=== Resumen que te llegaria por Telegram ===');
console.log(r.resumen);
console.log('');
console.log('=== Borrador copiable ===');
console.log(r.borrador);
console.log('');

// Verificacion automatica
// Es el ejemplo EXACTO que dio el usuario: "col envio: 2989, 3100, 3060 -> la mas alta 3100"
const esperado = {
  'Colombia':  { envio: 3100,  recibo: 3193 },   // envio: max(2989, 3060, 3100) | recibo: solo 3193
  'Argentina': { envio: 1477,  recibo: 1666 },
  'Brasil':    { envio: 5,     recibo: 5.38 },   // envio: max(4.90, 5.00) | recibo: solo 5.38
  'México':    { envio: 16.4,  recibo: 18.4 },   // envio: max(15.99, 16.40) | recibo: min(19.40, 18.78, 18.40)
  'Chile':     { envio: 877,   recibo: 990 }
};

console.log('=== Verificacion (envio = MAS ALTO, recibo = MAS BAJO) ===');
let fallos = 0;
for (const [pais, esp] of Object.entries(esperado)) {
  const f = r.filas.find(x => x.Pais === pais);
  const e = f ? f['Tasa Envio'] : undefined;
  const rc = f ? f['Tasa Recibo'] : undefined;
  const ok = e === esp.envio && rc === esp.recibo;
  if (!ok) fallos++;
  console.log(`  ${ok ? 'OK   ' : 'FALLO'} ${pais.padEnd(12)} envio=${e} recibo=${rc}` +
    (ok ? '' : `   [esperaba envio=${esp.envio} recibo=${esp.recibo}]`));
}

// Un solo proveedor debe seguir funcionando
const uno = correr({ proveedores: [{ nombre: 'Grupo Elite', filas: [{ pais: 'Uruguay', envio: 39, recibo: 44 }] }] });
const fu = uno.filas.find(x => x.Pais === 'Uruguay');
const okUno = fu && fu['Tasa Envio'] === 39 && fu['Tasa Recibo'] === 44;
if (!okUno) fallos++;
console.log(`  ${okUno ? 'OK   ' : 'FALLO'} un solo proveedor  -> ${JSON.stringify(fu)}`);

// Formato viejo {filas:[...]} debe seguir siendo aceptado
const viejo = correr({ filas: [{ pais: 'Colombia', envio: 3100, recibo: 3130 }] });
const fv = viejo.filas.find(x => x.Pais === 'Colombia');
const okViejo = fv && fv['Tasa Envio'] === 3100;
if (!okViejo) fallos++;
console.log(`  ${okViejo ? 'OK   ' : 'FALLO'} formato viejo      -> ${JSON.stringify(fv)}`);

// Control de direccion invertida: si el envio sale >= que el recibo, debe AVISAR.
const invertido = correr({ proveedores: [{ nombre: 'X', filas: [{ pais: 'Colombia', envio: 3193, recibo: 2989 }] }] });
const avisa = /REVISAR/.test(invertido.resumen) && /Revisa Colombia/.test(invertido.resumen);
if (!avisa) fallos++;
console.log(`  ${avisa ? 'OK   ' : 'FALLO'} avisa si envio >= recibo`);

// BUG que hubo: si un pais solo trae RECIBO, el borrador ponia "Peru  890" y eso en formato
// corto significa ENVIO 890 -> escribia el recibo en la columna equivocada. Debe salir "Peru r 890".
const soloRecibo = correr({ proveedores: [{ nombre: 'X', filas: [
  { pais: 'Perú', envio: null, recibo: 890 },
  { pais: 'Colombia', envio: 3100, recibo: null }
] }] });
const okBorr = /Perú r 890/.test(soloRecibo.borrador) && /Colombia 3100/.test(soloRecibo.borrador);
if (!okBorr) fallos++;
console.log(`  ${okBorr ? 'OK   ' : 'FALLO'} borrador marca "r" si solo hay recibo -> ${JSON.stringify(soloRecibo.borrador)}`);

// Varias llamadas a la IA (una por proveedor) deben juntarse en un solo resultado.
const multi = correr(
  { proveedores: [{ nombre: 'Elite',  filas: [{ pais: 'Colombia', envio: 2989, recibo: 3193 }] }] },
  { proveedores: [{ nombre: 'Suelto', filas: [{ pais: 'Colombia', envio: 3100, recibo: null }] }] }
);
const fm = multi.filas.find(x => x.Pais === 'Colombia');
const okMulti = fm && fm['Tasa Envio'] === 3100 && fm['Tasa Recibo'] === 3193 && multi.proveedores.length === 2;
if (!okMulti) fallos++;
console.log(`  ${okMulti ? 'OK   ' : 'FALLO'} junta 2 llamadas de IA -> ${JSON.stringify(fm)} provs=${multi.proveedores}`);

console.log('');
console.log(fallos ? `❌ ${fallos} fallaron` : '✅ Todas las pruebas pasaron');
