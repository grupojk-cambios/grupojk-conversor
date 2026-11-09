// Prueba de la REGLA DE RECIBO AUTOMATICO de Colombia (Caballo, +25 puntos).
//
// Es la misma idea que ya existia para Venezuela con Jesus (+20): hay proveedores que
// mandan SOLO la tasa de envio y el recibo lo pone Kelvin sumando siempre los mismos puntos.
//
// Datos REALES del 09/11 (ejecucion 2137 del bot):
//   CABALLO manda "3.200 pagando usdt x Cop"  -> Colombia envio 3200, SIN recibo
//   ELITE   manda Colombia 3096 / 3336
// Antes el recibo de Colombia lo ganaba ELITE con 3336. Ahora Caballo da 3225 (3200+25)
// y gana el, porque en RECIBO gana el numero MAS BAJO.
//
// Lo que tambien se vigila aca:
//   - Que el mensaje de Caballo lo siga leyendo la IA y NO el lector rapido. Caballo escribe
//     el sentido con palabras ("pagando usdt x Cop" = envio / "pagando cop x usdt" = recibo);
//     si lo agarrara el lector rapido podria invertir envio y recibo.
//   - Que la regla NO le invente recibo a otros proveedores que manden solo el envio.
//   - Que lo de Jesus con Venezuela siga funcionando igual.
//
// Correr con:  node test_regla_colombia.mjs

import { readFileSync } from 'fs';

const SALTO = String.fromCharCode(10);
const wf = JSON.parse(readFileSync('workflow_tasas_proveedores.json', 'utf8').replace(/^﻿/, ''));
const code = n => wf.nodes.find(x => x.name === n).parameters.jsCode;

const CSV = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv';
const csv = await (await fetch(CSV + '&n=' + Date.now())).text();

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(56) + ' ' + (detalle || ''));
};

// ---- Arnes del nodo que compara proveedores y arma el borrador ----
function compararIA() {
  const respuestasIA = Array.prototype.slice.call(arguments);
  const $ = (nombre) => ({
    first: () => {
      if (nombre === 'Interpretar Mensaje') return { json: { chatId: '627887509', errores: '' } };
      if (nombre === 'Leer Paises') return { json: { data: csv } };
      return { json: {} };
    }
  });
  const items = respuestasIA.map(r => ({ json: { choices: [{ message: { content: JSON.stringify(r) } }] } }));
  const $input = { all: () => items };
  return new Function('$', '$json', '$input', code('Armar Borrador IA'))($, items[0].json, $input)[0].json;
}

// ---- Arnes del lector rapido (sin IA) ----
function leerSinIA() {
  const mensajes = Array.prototype.slice.call(arguments);
  const textoFinal = mensajes.join(SALTO + SALTO);
  const $ = (n) => {
    const j = {
      'Telegram Trigger':       { message: { text: textoFinal, chat: { id: '627887509' } } },
      'Combinar Mensajes':      { mensajes, textoFinal },
      'Leer Paises':            { data: csv },
      'Redis Leer Pendiente':   {},
      'Redis Leer Proveedores': { provFormatos: '[]' }
    }[n] || {};
    return { first: () => ({ json: j }), all: () => [{ json: j }] };
  };
  return new Function('$', code('Interpretar Mensaje'))($)[0].json;
}

const fila = (r, pais) => (r.filas || []).find(f => f.Pais === pais) || {};
const lineaDe = (r, pais) => {
  const bloques = String(r.resumen || '').split(SALTO + SALTO);
  return bloques.find(b => b.split(SALTO)[0].trim().startsWith(pais)) || '';
};
const mostrar = (txt) => console.log('     ' + txt.split(SALTO).join(SALTO + '     '));

console.log('=== 1) Caballo manda SOLO el envio -> el recibo se calcula +25 ===');
{
  // Tal cual el 09/11: CABALLO solo envio, ELITE con las dos.
  const r = compararIA(
    { nombre: 'CABALLO', filas: [{ pais: 'Colombia', envio: 3200, recibo: null }] },
    { nombre: 'ELITE',   filas: [{ pais: 'Colombia', envio: 3096, recibo: 3336 }] }
  );
  const f = fila(r, 'Colombia');
  const linea = lineaDe(r, 'Colombia');
  mostrar(linea);
  chk(f['Tasa Envio'] === 3200,  'envio queda en 3200 (gana el MAS ALTO)', '-> ' + f['Tasa Envio']);
  chk(f['Tasa Recibo'] === 3225, 'recibo calculado 3200 + 25 = 3225',      '-> ' + f['Tasa Recibo']);
  chk(/calculado: envio \+25/.test(linea), 'avisa que el recibo lo calculo el bot');
  chk(/recibo 3225  <- CABALLO/.test(linea), 'dice que el recibo es de CABALLO');
  chk(/3336 \(ELITE\)/.test(linea), 'el 3336 de ELITE queda listado como "otros"');
}

console.log('');
console.log('=== 2) Si Caballo manda las DOS, no se le toca nada ===');
{
  const r = compararIA({ nombre: 'CABALLO', filas: [{ pais: 'Colombia', envio: 3070, recibo: 3120 }] });
  const f = fila(r, 'Colombia');
  chk(f['Tasa Recibo'] === 3120, 'el recibo del proveedor manda (no 3095)', '-> ' + f['Tasa Recibo']);
  chk(!/calculado/.test(lineaDe(r, 'Colombia')), 'no dice "calculado"');
}

console.log('');
console.log('=== 3) La regla es SOLO para Caballo en Colombia ===');
{
  // Otro proveedor con solo el envio de Colombia: no se le inventa recibo.
  const r1 = compararIA({ nombre: 'Tasa MX/BR/CO', filas: [{ pais: 'Colombia', envio: 3060, recibo: null }] });
  chk(fila(r1, 'Colombia')['Tasa Recibo'] === undefined,
      'a otro proveedor NO se le inventa el recibo', '-> ' + fila(r1, 'Colombia')['Tasa Recibo']);
  chk(/recibo -- \(ninguno lo trae\)/.test(lineaDe(r1, 'Colombia')), 'dice que nadie trae el recibo');

  // Caballo en otro pais: tampoco.
  const r2 = compararIA({ nombre: 'CABALLO', filas: [{ pais: 'Perú', envio: 3.47, recibo: null }] });
  chk(fila(r2, 'Perú')['Tasa Recibo'] === undefined,
      'Caballo en Peru tampoco suma +25', '-> ' + fila(r2, 'Perú')['Tasa Recibo']);
}

console.log('');
console.log('=== 4) Venezuela con Jesus sigue igual (+20) ===');
{
  const r = compararIA({ nombre: 'Jesus', filas: [{ pais: 'Venezuela', envio: 1030, recibo: null }] });
  const f = fila(r, 'Venezuela');
  mostrar(lineaDe(r, 'Venezuela'));
  chk(f['Tasa Recibo'] === 1050, 'recibo 1030 + 20 = 1050', '-> ' + f['Tasa Recibo']);
  chk(/calculado: envio \+20/.test(lineaDe(r, 'Venezuela')), 'avisa el +20');
}

console.log('');
console.log('=== 5) El mensaje de Caballo lo sigue leyendo la IA ===');
{
  // Mensaje REAL del 09/11. El sentido esta en las palabras, no en el orden de los numeros.
  const caballo = ['CABALLO', '', 'Actualizacion', '', 'Tasa ', '', '3.200 pagando usdt x Cop'].join(SALTO);
  const r = leerSinIA(caballo);
  chk(r.accion === 'ia', 'se manda a la IA, no lo adivina el lector rapido', '-> ' + r.accion);
  chk(!(r.filas || []).some(f => f.Pais === 'Colombia'),
      'el lector rapido NO arma la fila de Colombia solo');

  // Y Jesus, que manda el numero pelado, lo sigue resolviendo sin IA.
  const jesus = ['Jesus', '', '1030'].join(SALTO);
  const rj = leerSinIA(jesus);
  const fj = fila(rj, 'Venezuela');
  chk(rj.accion === 'nuevo', 'Jesus se sigue resolviendo sin IA', '-> ' + rj.accion);
  chk(fj['Tasa Envio'] === 1030 && fj['Tasa Recibo'] === 1050,
      'Jesus: 1030 -> 1050 sin IA', '-> ' + fj['Tasa Envio'] + ' / ' + fj['Tasa Recibo']);
}

console.log('');
console.log('=== 6) La regla vale tambien por el lector rapido ===');
{
  // Kelvin pone el nombre arriba y escribe la tasa en formato corto: igual se suman los +25.
  const r = leerSinIA(['CABALLO', '', 'Colombia 3200'].join(SALTO));
  const f = fila(r, 'Colombia');
  mostrar(r.resumen || '(se fue a la IA)');
  chk(r.accion === 'nuevo', 'lo resolvio sin IA', '-> ' + r.accion);
  chk(f['Tasa Envio'] === 3200 && f['Tasa Recibo'] === 3225,
      'Colombia 3200 -> 3225', '-> ' + f['Tasa Envio'] + ' / ' + f['Tasa Recibo']);
  chk(/recibo calculado: envio \+25/.test(r.resumen || ''), 'avisa que el recibo lo calculo el bot');

  // Si manda las dos, se respetan las dos.
  const r2 = leerSinIA(['CABALLO', '', 'Colombia 3200 3150'].join(SALTO));
  const f2 = fila(r2, 'Colombia');
  chk(f2['Tasa Recibo'] === 3150, 'si manda las dos, manda el proveedor', '-> ' + f2['Tasa Recibo']);
  chk(!/calculado/.test(r2.resumen || ''), 'y no dice "calculado"');

  // Sin nombre de proveedor NO se inventa nada: puede ser Kelvin poniendo la tasa a mano.
  const r3 = leerSinIA('Colombia 3200');
  chk(fila(r3, 'Colombia')['Tasa Recibo'] === undefined,
      'sin proveedor no se inventa recibo', '-> ' + fila(r3, 'Colombia')['Tasa Recibo']);
}

console.log('');
console.log(fallos ? (fallos + ' fallaron') : 'Todas las pruebas pasaron');
process.exit(fallos ? 1 : 0);
