// Prueba de la aprobacion: comprobante + cuenta destino.
//
// El caso real del 19/11 con Maigreth, que es lo que destapo el problema:
// mando la foto del pago y 36 segundos despues la cuenta en texto. Quedaron en dos
// ejecuciones distintas y en NINGUNA estaban las dos cosas. Peor: en la del comprobante el
// bot aprobo igual y le mando al grupo "(el cliente no escribio la cuenta en texto)".
//
// Por que aprobo: para saber si habia cuenta buscaba palabras como "banco" en el mensaje
// COMPLETO, y la anotacion que el mismo bot escribe al leer el comprobante dice
// "Banco: Banco Guayaquil". Se creia a si mismo.
//
// Correr con:  node test_comprobante.mjs

import { readFileSync } from 'fs';

const SALTO = String.fromCharCode(10);
const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const wfMed = JSON.parse(readFileSync('workflow_media.json', 'utf8').replace(/^﻿/, ''));
const code = n => (wf.nodes.find(x => x.name === n) || wfMed.nodes.find(x => x.name === n)).parameters.jsCode;

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(54) + ' ' + (detalle || ''));
};

// Corre "Detectar Aprobacion" con el texto ya combinado que le llegaria.
function detectar(mensajeCombinado) {
  const $ = (n) => {
    if (n === 'Combinar') return { item: { json: { mensajeCombinado } } };
    if (n === 'Webhook Evolution API') return { first: () => ({ json: { body: { data: {
      key: { remoteJid: '593962907849@s.whatsapp.net' }, pushName: 'Maigre Herrera' } } } }) };
    return { item: { json: {} }, first: () => ({ json: {} }) };
  };
  return new Function('$', code('Detectar Aprobación'))($);
}

// Textos tal como los arma el bot al leer una imagen (nodo "Texto de Imagen").
const COMPROBANTE = '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: $50.00, '
  + 'Banco: Banco Guayaquil, Fecha: 19/11/2026, Referencia: 0011290269]';
const CUENTA_TEXTO = ['Datos de Cuenta', '', 'Banco Digital de los Trabajadores',
  'Cta. Cte. Remunerada PN', '01750567030073572223', 'V-22964577', 'CARLOS MOGUEA BASSA', '$50'].join(SALTO);
const CUENTA_IMAGEN = '[El cliente envio una imagen con una CUENTA bancaria. Datos: '
  + 'Bancolombia ahorro 95700004094, Glendys Rodriguez, CC 1126418505]';

console.log('=== 1) EL CASO REAL: solo el comprobante, sin cuenta ===');
{
  // Antes esto aprobaba y mandaba al grupo "(el cliente no escribio la cuenta)".
  const r = detectar(COMPROBANTE);
  chk(r.length === 0, 'NO aprueba: el cliente todavia no mando la cuenta', '-> ' + r.length + ' items');
}

console.log('');
console.log('=== 2) Comprobante + cuenta juntos: aprueba y manda la cuenta real ===');
{
  const r = detectar(COMPROBANTE + SALTO + SALTO + CUENTA_TEXTO);
  chk(r.length === 1, 'aprueba', '-> ' + r.length);
  const d = r.length ? r[0].json.datosCuenta : '';
  console.log('     ' + d.split(SALTO).join(SALTO + '     '));
  chk(/01750567030073572223/.test(d), 'manda el numero de cuenta del cliente');
  chk(/CARLOS MOGUEA BASSA/.test(d), 'y el titular');
  chk(!/Banco Guayaquil/.test(d), 'NO cuela el banco del comprobante');
  chk(!/no escribio la cuenta/.test(d), 'ya no sale la frase vieja');
  chk(!/\[El cliente envio/.test(d), 'no van las anotaciones internas del bot');
}

console.log('');
console.log('=== 3) La cuenta llego como IMAGEN, no en texto ===');
{
  const r = detectar(COMPROBANTE + SALTO + SALTO + CUENTA_IMAGEN);
  chk(r.length === 1, 'tambien aprueba', '-> ' + r.length);
  const d = r.length ? r[0].json.datosCuenta : '';
  chk(/Cuenta \(imagen\)/.test(d), 'la marca como leida de una imagen');
  chk(/95700004094/.test(d), 'y lleva los datos', '-> ' + d.slice(0, 60));
}

console.log('');
console.log('=== 4) Casos que NO deben aprobar ===');
{
  chk(detectar(CUENTA_TEXTO).length === 0, 'solo la cuenta, sin comprobante');
  chk(detectar('hola, tienes tasa para colombia?').length === 0, 'una pregunta cualquiera');
  chk(detectar('').length === 0, 'mensaje vacio');
  chk(detectar('[El cliente envio una imagen que no parece comprobante ni cuenta de banco]').length === 0,
      'una foto cualquiera');
  // Un comprobante cuyo resumen trae varias palabras de la lista: sigue sin aprobar.
  chk(detectar('[El cliente envio un COMPROBANTE de pago. Datos leidos: Banco: Nequi, '
      + 'Cuenta: 3001234567, Titular: Juan, Cedula: 123]').length === 0,
      'comprobante con banco, cuenta, titular y cedula adentro');
}

console.log('');
console.log('=== 4b) CUENTAS SIN PALABRA DE BANCO (caso del 20/11) ===');
{
  // Un cliente mando el comprobante y esto: pais, numero de cuenta, titular, cedula y monto. Ninguna
  // de las palabras de la lista (banco, cuenta, cedula...) aparece, asi que el bot le dijo
  // "Listo, recibido!" al cliente y NO paso nada al grupo.
  const COMP_CASO = '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: 35.00 USD, '
    + 'Banco: Banco Pichincha C.A., Fecha: 2026/nov/20, Referencia: 031299]';
  const CASO = ['Venezuela', '01020000000000012345', 'Maria Perez', '12345678', '35$'].join(SALTO);
  const r = detectar(COMP_CASO + SALTO + SALTO + CASO);
  chk(r.length === 1, 'aprueba la cuenta del caso real (20 digitos, sin la palabra banco)', '-> ' + r.length);
  const d = r.length ? r[0].json.datosCuenta : '';
  chk(/01020000000000012345/.test(d) && /Maria Perez/.test(d), 'y manda cuenta y titular');
  chk(!/Banco Pichincha/.test(d), 'sin colar el banco del comprobante');

  // Otras formas habituales de escribir una cuenta, todas sin la palabra "banco":
  const otras = [
    ['pago movil: telefono + banco + cedula', 'Banesco' + SALTO + '04120000000' + SALTO + 'V-12345678' + SALTO + '35$'],
    ['cuenta con espacios', '0102 0000 0000 0001 2345' + SALTO + 'Maria Perez' + SALTO + '35$'],
    ['solo nombre de banco venezolano', 'Mercantil Maria Perez V-12345678'],
    ['correo (Zelle / PayPal)', 'maria.perez@example.com' + SALTO + 'Maria Perez'],
    ['cuenta de Ecuador', 'Pichincha ahorro 2200000000 Ana Gomez 3000'],
    ['wallet', 'USDT TRC20 TXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX'],
  ];
  for (const [nombre, texto] of otras) {
    chk(detectar(COMP_CASO + SALTO + SALTO + texto).length === 1, 'aprueba: ' + nombre);
  }

  // Y lo que NO debe aprobar aunque haya comprobante:
  const no = [
    ['solo un monto', '35$'],
    ['un agradecimiento', 'Gracias, ya envie'],
    ['una hora y un monto', 'Lo hice a las 10:30 por 35 dolares'],
    ['un numero corto', 'Mi codigo es 123456'],
  ];
  for (const [nombre, texto] of no) {
    chk(detectar(COMP_CASO + SALTO + SALTO + texto).length === 0, 'NO aprueba: ' + nombre);
  }
}

console.log('');
console.log('=== 5) Cuanto espera antes de contestar ===');
{
  const prep = code('Prep Debounce');
  const correr = (texto) => {
    const $ = (n) => ({ first: () => ({ json: { body: { data: { key: {
      remoteJid: '593962907849@s.whatsapp.net' } } } } }) });
    return new Function('$', '$json', prep)($, { texto })[0].json;
  };
  const conComprobante = correr(COMPROBANTE);
  const normal = correr('hola, cuanto esta la tasa?');
  chk(conComprobante.espera === 100, 'con comprobante espera 100s', '-> ' + conComprobante.espera);
  chk(conComprobante.esComprobante === true, 'y lo marca para el sticker');
  chk(normal.espera === 30, 'un mensaje normal sigue en 30s', '-> ' + normal.espera);
  chk(normal.esComprobante === false, 'y no dispara el sticker');

  const sig = n => (((wf.connections[n] && wf.connections[n].main) || [])[0] || []).map(c => c.node).join();
  const ej = wf.nodes.find(x => x.name === 'Ejecutar Media');
  chk(!!ej && ej.type === 'n8n-nodes-base.executeWorkflow' && ej.parameters?.workflowId?.value === 'UMQqyE6H4HVrIDoy',
      'Ejecutar Media apunta a UMQqyE6H4HVrIDoy');
  chk(ej && ej.parameters?.options?.waitForSubWorkflow === true, 'espera al sub-workflow de Media (sincrono, sin Wait)');
  chk(sig('Es mensaje de cliente?') === 'Ejecutar Media' && sig('Ejecutar Media') === 'Prep Debounce',
      'Es mensaje de cliente? -> Ejecutar Media -> Prep Debounce');
}

console.log('');
console.log(fallos ? (fallos + ' fallaron') : 'Todas las pruebas pasaron');
process.exit(fallos ? 1 : 0);
