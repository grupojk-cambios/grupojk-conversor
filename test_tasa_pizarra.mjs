
const _strip = s => s ? String(s).replace(/^\d+[\w\.]*\s*/, '') : '';
const _findNode = (nodes, n) => (nodes || []).find(x => x.name === n || _strip(x.name) === _strip(n));
const _getConn = (conns, n) => {
  if (!conns) return null;
  const k = Object.keys(conns).find(x => x === n || _strip(x) === _strip(n));
  return k ? Reflect.get(conns, k) : null;
};
// Prueba: la tasa que da el bot se escribe COMO EN LA PIZARRA y en el cotizador de la app.
//
// Por que existe: el 23/11 el bot le cotizo a una clienta de Venezuela a Ecuador y escribio
// "Tasa: 0,000844 VES" (los dolares que da cada bolivar). La pizarra y la app muestran el numero
// grande: cuantos Bs hacen falta por 1 dolar ("1184.24 VES"). Regla (igual que src/Cotizador.jsx):
//   - si el cliente manda moneda local y recibe dolares (o euros): 1 dolar = X moneda local;
//   - en los demas casos: 1 moneda de origen = X moneda de destino.
//
// Las tasas son INVENTADAS (no se descarga la hoja): la prueba siempre da lo mismo.
// Correr con:  node test_tasa_pizarra.mjs

import { readFileSync } from 'fs';
import { calcularConversion, calcularConversionInversa } from './src/motor.js';

const wf = JSON.parse(readFileSync('workflow_ia_atencion.json', 'utf8').replace(/^﻿/, ''));
const code = _findNode(wf.nodes, 'Calculadora de Conversion').parameters.jsCode;

const pais = (nombre, codigo, envio, recibo, extra) => Object.assign({ nombre, codigo, moneda: codigo, tasaProveedorEnvio: envio, margenEnvio: 6,
  tasaProveedorRecibo: recibo, margenRecibo: 6, margenEnvioMayor: 3, margenReciboMayor: 3, factorEUR: 0, factorUSDT: 0, ciudades: '' }, extra || {});
const PAISES = [
  pais('Venezuela', 'VES', 1100, 1130),
  pais('Ecuador', 'USD', 1, 1, { margenEnvio: 1, margenRecibo: 1 }),
  pais('Colombia', 'COP', 3600, 3700),
  pais('Zelle', 'USD', 1, 1, { margenEnvio: 5, margenRecibo: 5 }),
  pais('Europa', 'EUR', 1, 1.08)
];

const correr = q => JSON.parse(new Function('query', '$getWorkflowStaticData', code)(q, () => ({ paisesData: PAISES })));
const buscar = n => PAISES.find(p => p.nombre === n);
const r2 = x => Number(x.toFixed(2));

let fallos = 0;
const chk = (ok, etiqueta, detalle) => { if (!ok) fallos++; console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(66) + ' ' + (detalle || '')); };

for (const modo of ['detal', 'mayor']) {
  console.log('=== Tarifa ' + modo + ' ===');

  // El caso de la clienta: manda Bs, recibe dolares en Ecuador
  const ve = correr({ pais_origen: 'Venezuela', pais_destino: 'Ecuador', monto: 20, direccion: 'inversa', modo });
  const esperadoVe = r2(calcularConversionInversa(buscar('Venezuela'), buscar('Ecuador'), 1, PAISES, modo));
  chk(ve.tasaCruzada === esperadoVe && ve.unidadTasa === 'VES', 'Venezuela -> Ecuador: Bs por 1 dolar, igual que la app', '-> ' + ve.tasaCruzada + ' ' + ve.unidadTasa + ' (app ' + esperadoVe + ')');
  chk(ve.tasaCruzada > 1, 'nunca el numerito al reves (0,000844)', '-> ' + ve.tasaCruzada);
  chk(ve.tasaTexto === '1 USD = ' + ve.tasaCruzada + ' VES', 'tasaTexto dice 1 USD = X VES', '-> ' + ve.tasaTexto);
  chk(ve.resultado === r2(calcularConversionInversa(buscar('Venezuela'), buscar('Ecuador'), 20, PAISES, modo)), 'el monto a enviar no cambia', '-> ' + ve.resultado);

  // Al reves (manda dolares, recibe Bs) ya salia bien: no debe cambiar
  const ec = correr({ pais_origen: 'Ecuador', pais_destino: 'Venezuela', monto: 100, direccion: 'directa', modo });
  const esperadoEc = r2(calcularConversion(buscar('Ecuador'), buscar('Venezuela'), 1, PAISES, modo));
  chk(ec.tasaCruzada === esperadoEc && ec.unidadTasa === 'VES', 'Ecuador -> Venezuela: sigue igual (Bs por 1 dolar)', '-> ' + ec.tasaCruzada + ' ' + ec.unidadTasa);

  // Pesos colombianos a Zelle: COP por 1 dolar
  const co = correr({ pais_origen: 'Colombia', pais_destino: 'Zelle', monto: 100000, direccion: 'directa', modo });
  chk(co.unidadTasa === 'COP' && co.tasaCruzada > 1000, 'Colombia -> Zelle: COP por 1 dolar', '-> ' + co.tasaCruzada + ' ' + co.unidadTasa);

  // Pesos colombianos a euros: COP por 1 euro (igual que la app)
  const eu = correr({ pais_origen: 'Colombia', pais_destino: 'Europa', monto: 100000, direccion: 'directa', modo });
  chk(eu.unidadTasa === 'COP' && eu.tasaCruzada > 1000, 'Colombia -> Europa: COP por 1 euro', '-> ' + eu.tasaCruzada + ' ' + eu.unidadTasa);

  // Entre dos monedas locales: 1 de origen = X de destino (como la app)
  const cv = correr({ pais_origen: 'Colombia', pais_destino: 'Venezuela', monto: 100000, direccion: 'directa', modo });
  chk(cv.unidadTasa === 'VES' && cv.tasaCruzada === r2(calcularConversion(buscar('Colombia'), buscar('Venezuela'), 1, PAISES, modo)), 'Colombia -> Venezuela: 1 COP = X VES (como la app)', '-> ' + cv.tasaCruzada + ' ' + cv.unidadTasa);
}

console.log('');
console.log('=== El prompt le dice a la IA como escribir la linea "Tasa:" ===');
{
  const agente = _findNode(wf.nodes, 'AI Agent');
  const prompt = JSON.stringify(agente.parameters);
  chk(prompt.includes('tasaCruzada') && prompt.includes('unidadTasa'), 'la regla usa tasaCruzada + unidadTasa de la herramienta');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
