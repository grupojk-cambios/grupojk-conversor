// Prueba del workflow "Avisar deposito que no cuadra" (pedido de Kelvin, 23/11).
//
// Cuando el deposito no cuadra con la suma de las cuentas, el bot no pasa la operacion a transferir
// y le pide al cliente que confirme los montos ("Revisar Operacion", ver test_operacion.mjs 5e).
// Aqui se vigila lo que pasa despues:
//   - modo 'vigilar' (la primera vez): a los 5 min le recuerda al CLIENTE, a los 10 avisa al grupo de
//     avisos; en los dos, solo si no lo arreglo ni paso a un asesor;
//   - modo 'escalar' (dijo que esta bien asi): aviso en el grupo de TRANSFERIR;
//   - el bot lo llama sin esperarlo.
//
// Todos los datos son INVENTADOS. Correr con:  node test_vigilar_monto.mjs

import { readFileSync } from 'fs';

const leer = f => JSON.parse(readFileSync(f, 'utf8').replace(/^﻿/, ''));
const bot = leer('workflow_bot_whatsapp_v12.json');
const vig = leer('workflow_vigilar_monto.json');
const nodoDe = (wf, n) => wf.nodes.find(x => x.name === n);
const GRUPO_AVISOS = '120363413942097019@g.us';
const GRUPO_TRANSFERIR = '593961230380-1601657528@g.us';

let fallos = 0;
const chk = (ok, etiqueta, detalle) => { if (!ok) fallos++; console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(72) + ' ' + (detalle || '')); };

function correr(nodo, entrada, operaciones) {
  const $ = n => {
    if (n === 'Cuando lo Llama el Bot') return { first: () => ({ json: entrada }) };
    if (n === 'Redis Leer Operacion' || n === 'Redis Leer Operacion 2') return { first: () => ({ json: { operacion: (operaciones || {})[n] === undefined ? (operaciones || {}).todas : operaciones[n] } }) };
    throw new Error('nodo inesperado: ' + n);
  };
  return new Function('$', nodoDe(vig, nodo).parameters.jsCode)($);
}
function preparar(ro) {
  const $ = n => {
    if (n === 'Revisar Operacion') return { first: () => ({ json: ro }) };
    if (n === 'Prep Debounce') return { first: () => ({ json: { jid: '593990000001@s.whatsapp.net' } }) };
    if (n === 'Webhook Evolution API') return { first: () => ({ json: { body: { data: { pushName: 'Ana' } } } }) };
    if (n === 'Solo Estos Numeros') return { first: () => ({ json: { nombreCargado: 'Ana Prueba' } }) };
    throw new Error('nodo inesperado: ' + n);
  };
  return new Function('$', nodoDe(bot, 'Preparar Vigilancia Monto').parameters.jsCode)($);
}

const TOKEN = 1795449600000;
const ENTRADA = { modo: 'vigilar', jid: '593990000001@s.whatsapp.net', token: TOKEN, nombre: 'Ana Prueba', numero: '593990000001',
                  deposito: 10, suma: 15, montos: [15], moneda: 'USD' };
const opCon = noCuadra => JSON.stringify({ cuenta: { mensajes: [{ id: 'C1', texto: '0102 1234567 $15' }] }, capturas: [{ id: 'F1', monto: 10 }], hechos: [], noCuadra });
const MARCA = { ts: TOKEN, deposito: 10, suma: 15, montos: [15], moneda: 'USD', paso: 'preguntado' };

console.log('=== 1) A LOS 5 MINUTOS: ¿LE RECUERDA AL CLIENTE? ===');
{
  const r = correr('Decidir Recordatorio', ENTRADA, { todas: opCon(MARCA) });
  chk(r.length === 1 && r[0].json.jid === ENTRADA.jid && /confírmame los montos de las cuentas/.test(r[0].json.texto), 'no lo arreglo: le pide confirmar los montos (al chat del cliente)', '-> ' + (r[0] && r[0].json.texto));
  const c = correr('Decidir Recordatorio', ENTRADA, { todas: opCon(Object.assign({}, MARCA, { paso: 'pidio_captura' })) });
  chk(c.length === 1 && /captura del otro depósito/.test(c[0].json.texto), 'si ya se le pidio la otra captura: le recuerda la captura', '-> ' + (c[0] && c[0].json.texto));
  chk(correr('Decidir Recordatorio', ENTRADA, { todas: opCon(Object.assign({}, MARCA, { paso: 'escalado' })) }).length === 0, 'si ya paso a un asesor: NO le escribe');
  chk(correr('Decidir Recordatorio', ENTRADA, { todas: opCon(undefined) }).length === 0, 'si lo arreglo (ya no hay marca): NO le escribe');
  chk(correr('Decidir Recordatorio', ENTRADA, { todas: opCon(Object.assign({}, MARCA, { ts: TOKEN + 5 })) }).length === 0, 'si la marca es de OTRO momento: NO le escribe');
  chk(correr('Decidir Recordatorio', ENTRADA, { todas: '{roto' }).length === 0, 'si Redis devuelve basura: no hace nada ni revienta');
}

console.log('');
console.log('=== 2) A LOS 10 MINUTOS: ¿AVISA AL GRUPO DE AVISOS? ===');
{
  const r = correr('Decidir Aviso', ENTRADA, { todas: opCon(MARCA) });
  const t = (r[0] || { json: {} }).json.aviso || '';
  chk(r.length === 1 && /NO CUADRA \(10 min sin corregir\)/.test(t), 'sigue sin arreglarlo: AVISA, diciendo hace cuanto', '-> ' + JSON.stringify(t.split('\n')[0]));
  chk(/Ana Prueba \(\+593990000001\)/.test(t) && /Depósito: \$10/.test(t) && /Cuenta: \$15/.test(t) && /recordó al cliente/.test(t) && /NO se pasó a transferir/.test(t),
      'con el cliente, el deposito, la cuenta y que ya se le recordo', '-> ' + JSON.stringify(t));
  const v = correr('Decidir Aviso', ENTRADA, { todas: opCon(Object.assign({}, MARCA, { montos: [10, 5] })) });
  chk(/Cuentas: \$10 \+ \$5 = \$15/.test(v[0].json.aviso), 'con varias cuentas muestra la suma');
  const b = correr('Decidir Aviso', ENTRADA, { todas: opCon(Object.assign({}, MARCA, { deposito: 12000, suma: 13000, montos: [8000, 5000], moneda: 'VES' })) });
  chk(/Depósito: 12\.000 Bs/.test(b[0].json.aviso) && /8\.000 Bs \+ 5\.000 Bs = 13\.000 Bs/.test(b[0].json.aviso), 'en bolivares se escribe en Bs', '-> ' + b[0].json.aviso.split('\n').slice(3, 5).join(' | '));
  chk(correr('Decidir Aviso', ENTRADA, { todas: opCon(undefined) }).length === 0, 'lo arreglo despues del recordatorio: NO avisa');
  chk(correr('Decidir Aviso', ENTRADA, { todas: opCon(Object.assign({}, MARCA, { paso: 'escalado' })) }).length === 0, 'ya paso a un asesor: NO avisa (ya se aviso en transferir)');
  chk(correr('Decidir Aviso', Object.assign({}, ENTRADA, { token: null }), { todas: opCon(MARCA) }).length === 0, 'sin token: NO avisa');
}

console.log('');
console.log('=== 3) MODO ESCALAR: AVISO EN TRANSFERIR ===');
{
  const r = correr('Armar Aviso Transferir', Object.assign({}, ENTRADA, { modo: 'escalar', deposito: 20, suma: 15, montos: [10, 5] }));
  const t = r[0].json.aviso;
  chk(/NO TRANSFERIR/.test(t) && /Depósito: \$20/.test(t) && /\$10 \+ \$5 = \$15/.test(t) && /está bien así/.test(t) && /asesor/.test(t),
      'dice que NO se transfiera, los montos y que el cliente dice que esta bien asi', '-> ' + JSON.stringify(t));
}

console.log('');
console.log('=== 4) EL WORKFLOW ===');
{
  const c = vig.connections;
  const sig = (n, i) => ((c[n] && c[n].main && c[n].main[i || 0]) || []).map(x => x.node).join(',');
  chk(sig('Cuando lo Llama el Bot') === 'Es Escalar?' && sig('Es Escalar?', 0) === 'Armar Aviso Transferir' && sig('Armar Aviso Transferir') === 'Avisar en Transferir'
      && sig('Es Escalar?', 1) === 'Esperar 5 min', 'escalar -> aviso en transferir; si no -> vigilar');
  chk(sig('Esperar 5 min') === 'Redis Leer Operacion' && sig('Redis Leer Operacion') === 'Decidir Recordatorio' && sig('Decidir Recordatorio') === 'Recordar al Cliente'
      && sig('Recordar al Cliente') === 'Esperar 5 min mas' && sig('Esperar 5 min mas') === 'Redis Leer Operacion 2' && sig('Redis Leer Operacion 2') === 'Decidir Aviso'
      && sig('Decidir Aviso') === 'Avisar al Grupo', 'vigilar: 5 min -> recordatorio -> 5 min mas -> aviso');
  const w1 = nodoDe(vig, 'Esperar 5 min').parameters, w2 = nodoDe(vig, 'Esperar 5 min mas').parameters;
  chk(w1.amount === 5 && w1.unit === 'minutes' && w2.amount === 5 && w2.unit === 'minutes', 'espera 5 y 5 minutos');
  chk(/\$json\.modo === 'escalar'/.test(JSON.stringify(nodoDe(vig, 'Es Escalar?').parameters)), 'el IF mira el modo');
  const envios = vig.nodes.filter(n => /evolution|whatsapp|telegram|httpRequest/i.test(n.type)).map(n => n.name + ':' + n.parameters.remoteJid).sort();
  chk(JSON.stringify(envios) === JSON.stringify(['Avisar al Grupo:' + GRUPO_AVISOS, 'Avisar en Transferir:' + GRUPO_TRANSFERIR, 'Recordar al Cliente:={{ $json.jid }}']),
      'manda SOLO: el recordatorio al cliente, el aviso a avisos y el de transferir', '-> ' + envios.join(' | '));
}

console.log('');
console.log('=== 5) EL BOT LO LLAMA Y NO LO ESPERA ===');
{
  const c = bot.connections;
  const sig = n => ((c[n] && c[n].main && c[n].main[0]) || []).map(x => x.node);
  chk(sig('Redis Guardar Operacion').includes('Preparar Vigilancia Monto') && sig('Preparar Vigilancia Monto').join() === 'Vigilar Monto',
      'Redis Guardar Operacion -> Preparar Vigilancia Monto -> Vigilar Monto');
  chk(sig('Redis Guardar Operacion')[0] === '¿Qué Responder?', 'la respuesta al cliente sigue siendo la primera rama');
  const v = nodoDe(bot, 'Vigilar Monto');
  chk(v.type === 'n8n-nodes-base.executeWorkflow' && v.parameters.options.waitForSubWorkflow === false, 'Vigilar Monto no espera al otro workflow (el bot no se frena)');
  chk(/^[A-Za-z0-9]{16}$/.test(v.parameters.workflowId.value), 'apunta a un workflow de verdad (no al marcador __PENDIENTE__)', '-> ' + v.parameters.workflowId.value);
  chk(v.onError === 'continueRegularOutput' && sig('Vigilar Monto').length === 0, 'si falla, el bot sigue igual; y ahi termina esa rama');

  chk(preparar({ vigilarMonto: null }).length === 0, 'si no hay nada que hacer: no llama a nadie');
  const p = preparar({ vigilarMonto: { modo: 'vigilar', token: TOKEN, deposito: 10, suma: 15, montos: [15], moneda: 'USD' } });
  chk(p.length === 1 && p[0].json.modo === 'vigilar' && p[0].json.jid === '593990000001@s.whatsapp.net' && p[0].json.token === TOKEN && p[0].json.nombre === 'Ana Prueba',
      'vigilar: le pasa el modo, el chat, el token y el nombre', '-> ' + JSON.stringify(p[0] && p[0].json));
  const e = preparar({ vigilarMonto: { modo: 'escalar', token: TOKEN, deposito: 20, suma: 15, montos: [15], moneda: 'USD' } });
  chk(e[0].json.modo === 'escalar' && e[0].json.deposito === 20, 'escalar: igual, con modo escalar');
}

console.log('');
console.log('=== 6) LA IA QUE LEE LA CAPTURA DICE LA MONEDA ===');
{
  const leer = nodoDe(bot, 'Leer Imagen').parameters.text;
  chk(/Moneda: <codigo de la moneda/.test(leer) && /tambien usan el simbolo \$/.test(leer), 'el prompt pide "Moneda: USD/VES/COP..." y avisa que el $ no siempre es dolar');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
