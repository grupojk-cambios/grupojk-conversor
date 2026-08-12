// Prueba del parser del bot de tasas (formatos A + B) contra los mensajes REALES que Kelvin
// mando por Telegram entre el 4 y el 10 de agosto, mas los formatos nuevos.
// Extrae el codigo del nodo "Interpretar Mensaje" directo del JSON generado por el build.

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_tasas_proveedores.json', 'utf8').replace(/^﻿/, ''));
const codigo = wf.nodes.find(n => n.name === 'Interpretar Mensaje').parameters.jsCode;

// Paises reales de la hoja
const CSV = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv';
const csv = await (await fetch(CSV + '&n=' + Date.now())).text();

// Simula el entorno de n8n para poder ejecutar el codigo del nodo tal cual
function correr(texto, pendiente = null) {
  const $ = (nombre) => ({
    first: () => {
      if (nombre === 'Telegram Trigger') return { json: { message: { text: texto, chat: { id: 627887509 } } } };
      if (nombre === 'Redis Leer Pendiente') return { json: { pendienteRaw: pendiente ? JSON.stringify(pendiente) : '' } };
      if (nombre === 'Leer Paises') return { json: { data: csv } };
      return { json: {} };
    }
  });
  const fn = new Function('$', codigo);
  return fn($)[0].json;
}

let fallos = 0;
function t(etiqueta, texto, esperado) {
  const r = correr(texto);
  const real = (r.filas || []).map(f => f.Pais + ':' + (f['Tasa Envio'] ?? '-') + '/' + (f['Tasa Recibo'] ?? '-')).join(' ');
  const ok = real === esperado;
  if (!ok) fallos++;
  console.log(`  ${ok ? 'OK   ' : 'FALLO'} ${etiqueta.padEnd(34)} -> ${real || '(' + r.accion + ')'}`);
  if (!ok) console.log(`         esperaba: ${esperado}`);
}

console.log('=== 1) Mensajes REALES que ya mandaste (deben seguir funcionando igual) ===');
t('largo clasico',        'Uruguay\nenvio: 39\nrecibo: 44',                'Uruguay:39/44');
t('largo con mayusculas', 'Uruguay\nEnvio: 39\nRecibo: 44',                'Uruguay:39/44');
t('largo con acento',     'Venezuela\nEnvío: 835\nRecibo: 850',            'Venezuela:835/850');
t('solo envio',           'Uruguay\nenvio: 39',                            'Uruguay:39/-');
t('decimales',            'Peru\nEnvio: 3.37\nRecibo: 3.55',               'Perú:3.37/3.55');
t('dos paises en bloques','Colombia\nenvio: 3400\nrecibo: 3700\n\nBrasil\nenvio: 4.92', 'Colombia:3400/3700 Brasil:4.92/-');

console.log('');
console.log('=== 2) Los 2 casos que ANTES te fallaron ===');
t('"Recibir:" (fallo 05/08)', 'Colombia\nEnvio: 3130\nRecibir: 3170',      'Colombia:3130/3170');
t('sin dos puntos (fallo 08/08)', 'Venezuela\nEnvío 854\nRecibo 870',      'Venezuela:854/870');

console.log('');
console.log('=== 3) Formato NUEVO: una linea por pais ===');
t('nombre completo',      'Colombia 3100 3130',                            'Colombia:3100/3130');
t('varios paises',        'Colombia 3100 3130\nVenezuela 856 870',         'Colombia:3100/3130 Venezuela:856/870');
t('abreviatura',          'col 3100 3130\nven 856 870',                    'Colombia:3100/3130 Venezuela:856/870');
t('codigo de moneda',     'cop 3100 3130\nves 856 870',                    'Colombia:3100/3130 Venezuela:856/870');
t('con barra',            'col 3100/3130',                                 'Colombia:3100/3130');
t('solo envio',           'col 3100',                                      'Colombia:3100/-');
t('solo recibo (r)',      'col r 3130',                                    'Colombia:-/3130');
t('marcas explicitas',    'col envio 3100 recibo 3130',                    'Colombia:3100/3130');
t('pais de dos palabras', 'Republica Dominicana 56.66 66',                 'República Dominicana:56.66/66');
t('decimales una linea',  'Brasil 5.00 5.38',                              'Brasil:5/5.38');

console.log('');
console.log('=== 4) Tu lote grande del 10/08, en formato corto ===');
t('lote de 8 paises',
  'gua 7.07\narg 1477 1666\nchi 900 990\nbra 5.00 5.38\nuru 39 44\nrd 56.66 66\npar 5577 6291\nmex 16.50 19.40',
  'Guatemala:7.07/- Argentina:1477/1666 Chile:900/990 Brasil:5/5.38 Uruguay:39/44 República Dominicana:56.66/66 Paraguay:5577/6291 México:16.5/19.4');

console.log('');
console.log('=== 5) Mezclado (formato corto y largo en el mismo mensaje) ===');
t('mezcla', 'Colombia 3100 3130\n\nVenezuela\nenvio: 856\nrecibo: 870',    'Colombia:3100/3130 Venezuela:856/870');

console.log('');
console.log('=== 6) Casos que NO deben escribir en la hoja ===');
const noEscribe = [
  ['saludo', 'hola'],
  ['pais inexistente', 'Narnia 100 200'],
  ['sin numeros', 'como vas'],
];
for (const [et, txt] of noEscribe) {
  const r = correr(txt);
  const ok = r.accion === 'error' || r.accion === 'ia';
  if (!ok) fallos++;
  console.log(`  ${ok ? 'OK   ' : 'FALLO'} ${et.padEnd(34)} -> accion=${r.accion}`);
}

console.log('');
console.log('=== 7) Mensaje crudo de proveedor -> debe mandarlo a la IA ===');
const proveedor = `*CORPORACIÓN GRUPO ELITE*
🇵🇪SOL/ CHILE (CLP) 🇨🇱  257,14
USDT🌐/COP🇨🇴 3077
USDT🌐/ARS🇦🇷 1479
USDT 🌐/BRASIL 🇧🇷 4,82
*RECIBO📥*
🇨🇴COP /USDT 🌐 DÓLAR BCP 🇵🇪  3285
🇦🇷ARS/ USDT 🌐/DÓLAR BCP 🇵🇪 1.668`;
const rp = correr(proveedor);
const okIA = rp.accion === 'ia';
if (!okIA) fallos++;
console.log(`  ${okIA ? 'OK   ' : 'FALLO'} mensaje crudo del proveedor       -> accion=${rp.accion}`);

console.log('');
console.log('=== 7b) Mensajes REALES de proveedores del 10/08 -> TODOS deben ir a la IA ===');
console.log('     (el parser NO debe creer que los entiende: eso escribia basura en la hoja)');
const proveedoresReales = {
  'Grupo Elite (decimales con coma)': `*CORPORACIÓN GRUPO ELITE*

🇵🇪SOL/ CHILE (CLP) 🇨🇱  257,4
🇵🇪SOL/ COLOMBIA (COP) 🇨🇴 879,12
🇵🇪SOL/MÉXICO (MXN) 🇲🇽  4,70
USDT🌐/COP🇨🇴 2989
USDT🌐/ARS🇦🇷 1477
USDT 🌐/BRASIL 🇧🇷 4,90

*RECIBO📥*

🇨🇴COP /USDT 🌐 DÓLAR BCP 🇵🇪  3193
🇦🇷ARS/ USDT 🌐/DÓLAR BCP 🇵🇪 1.666`,
  'digitos emoji (1️⃣9️⃣)': `Tasa 🇲🇽🇧🇷🇨🇴
*HOY*  *LUNES*

🇲🇽  1️⃣9️⃣.4️⃣0️⃣ *USDT* DOY
🇵🇪  8️⃣9️⃣0️⃣🇨🇴 Recibo soles
🇧🇷  5️⃣.0️⃣0️⃣ *USDT* RECIBO
🇨🇴  3️⃣0️⃣6️⃣0️⃣ *USDT* RECIBO

Pedidos +573219343265`,
  'Mexico retiros/depositos': `Buen día

TASA HOY MÉXICO 🇲🇽
RETIROS SIN TARJETA
*16.40*📌✅
___

_RECIBIENDO MEXICO DEPÓSITOS_
  *18.40*📌✅

⏬⏬⏬⏬⏬
+57 323 3947051`,
  'frase suelta con 1 numero': `Actualizacion

Tasa

3.100 pagando usdt x Cop`
};
for (const [et, txt] of Object.entries(proveedoresReales)) {
  const r = correr(txt);
  const ok = r.accion === 'ia';
  if (!ok) fallos++;
  console.log(`  ${ok ? 'OK   ' : 'FALLO'} ${et.padEnd(34)} -> accion=${r.accion}`);
  if (!ok && r.resumen) console.log('         IBA A ESCRIBIR: ' + r.resumen.split('\n').slice(0, 3).join(' / '));
}

console.log('');
console.log('=== 8) Confirmar / cancelar ===');
const pend = { filas: [{ Pais: 'Colombia', 'Tasa Envio': 3100 }], resumen: 'x' };
for (const [txt, esp] of [['si', 'confirmar'], ['Si', 'confirmar'], ['dale', 'confirmar'], ['no', 'cancelar'], ['No', 'cancelar']]) {
  const r = correr(txt, pend);
  const ok = r.accion === esp;
  if (!ok) fallos++;
  console.log(`  ${ok ? 'OK   ' : 'FALLO'} "${txt}"`.padEnd(48) + ` -> ${r.accion}`);
}

console.log('');
console.log(fallos ? `❌ ${fallos} fallaron` : '✅ Todas las pruebas pasaron');
