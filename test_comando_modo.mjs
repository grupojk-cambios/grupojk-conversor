// Prueba el comando "modo mayor"/"modo detal" del bot de WhatsApp, ejecutando el codigo REAL
// del nodo "Detectar Comando Admin" tal como quedo en el JSON del workflow.
//
// El caso que fallaba: por la pausa de 30s, si Kelvin manda "Modo detal" justo despues de otros
// mensajes, todo llega junto en UN texto y antes no se reconocia el comando.

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const codigo = wf.nodes.find(n => n.name === 'Detectar Comando Admin').parameters.jsCode;

const ADMIN = '593961230380';   // numero con role=admin en Supabase

function correr(textoCombinado, numero = ADMIN) {
  const $ = (n) => {
    if (n === 'Webhook Evolution API') return { first: () => ({ json: { body: { data: { key: { remoteJid: numero + '@s.whatsapp.net' } } } } }) };
    if (n === 'Consultar Admins')      return { all: () => [{ json: { whatsapp: '+' + ADMIN, role: 'admin' } }] };
    if (n === 'Combinar')              return { item: { json: { mensajeCombinado: textoCombinado } } };
    return { first: () => ({ json: {} }), all: () => [], item: { json: {} } };
  };
  return new Function('$', codigo)($)[0].json;
}

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log(`  ${ok ? 'OK   ' : 'FALLO'} ${etiqueta.padEnd(46)} ${detalle}`);
};

// ===== EL CASO DE LA CAPTURA (14/09) =====
console.log('=== El caso que fallaba: comando pegado a otros mensajes ===');
const pegado = 'Hola buenas tardes como estas?\n\nQuisiera enviar 25$ a ecuador\n\nModo detal';
const r1 = correr(pegado);
chk(r1.esComandoModo === true && r1.modoElegido === 'detal', 'reconoce el comando aunque venga pegado',
    `-> modo=${r1.modoElegido}`);
chk(r1.soloComando === false, 'sabe que venia una pregunta ademas', `-> soloComando=${r1.soloComando}`);
chk(!/modo detal/i.test(r1.textoLimpio) && /25\$ a ecuador/.test(r1.textoLimpio),
    'le quita el comando al texto del agente', `-> "${r1.textoLimpio.replace(/\n/g, ' | ')}"`);

// ===== Comando solo (como ya funcionaba) =====
console.log('');
console.log('=== Comando solo: debe seguir funcionando igual ===');
for (const [txt, esp] of [['Modo detal', 'detal'], ['modo mayor', 'mayor'], ['mayor', 'mayor'], ['al detal', 'detal'], ['DETAL', 'detal']]) {
  const r = correr(txt);
  chk(r.esComandoModo && r.modoElegido === esp && r.soloComando === true, `"${txt}"`, `-> ${r.modoElegido}, solo=${r.soloComando}`);
}

// ===== Variantes del caso pegado =====
console.log('');
console.log('=== Otras formas de mandarlo pegado ===');
for (const [txt, espModo, espSolo] of [
  ['Modo mayor\n\nCuanto es 500 a colombia?', 'mayor', false],
  ['Cuanto es 500 a colombia?\n\nmodo detal', 'detal', false],
  ['Hola\n\nmayor\n\nQuiero enviar a Peru', 'mayor', false],
]) {
  const r = correr(txt);
  chk(r.esComandoModo && r.modoElegido === espModo && r.soloComando === espSolo,
      `"${txt.replace(/\n\n/g, ' | ')}"`, `-> ${r.modoElegido}, solo=${r.soloComando}`);
}

// ===== Lo que NO debe activarlo =====
console.log('');
console.log('=== NO debe cambiar la tarifa (son preguntas reales) ===');
for (const txt of [
  'cuanto es al mayor para 5000',
  'me das la tasa al mayor de colombia',
  'Hola\n\nUn cliente pregunta cuanto es al mayor',
  'tengo un cliente mayorista nuevo',
]) {
  const r = correr(txt);
  chk(r.esComandoModo === false, `"${txt.replace(/\n\n/g, ' | ').slice(0, 40)}"`, `-> comando=${r.esComandoModo}`);
}

// ================== SEGURIDAD: SOLO los admin pueden cambiar la tarifa ==================
// Version que permite simular la lista de admins que devuelve Supabase
function correrCon(textoCombinado, numero, listaAdmins) {
  const $ = (n) => {
    if (n === 'Webhook Evolution API') return { first: () => ({ json: { body: { data: { key: { remoteJid: numero + '@s.whatsapp.net' } } } } }) };
    if (n === 'Consultar Admins')      return { all: () => listaAdmins.map(w => ({ json: { whatsapp: w } })) };
    if (n === 'Combinar')              return { item: { json: { mensajeCombinado: textoCombinado } } };
    return { first: () => ({ json: {} }), all: () => [], item: { json: {} } };
  };
  return new Function('$', codigo)($)[0].json;
}
const ADMINS_OK = ['+593961230380', '+593998053300'];   // Kelvin y Dario

console.log('');
console.log('=== SEGURIDAD: solo numeros con role=admin ===');
for (const [num, etiqueta, esperado] of [
  ['593961230380', 'Kelvin (admin)',            true],
  ['593998053300', 'Dario (admin)',             true],
  ['584121112233', 'cliente venezolano',        false],
  ['573001234567', 'cliente colombiano',        false],
  ['593987654321', 'otro ecuatoriano cualquiera', false],
]) {
  const r = correrCon('Modo mayor', num, ADMINS_OK);
  chk(r.esComandoModo === esperado, etiqueta, `-> esAdmin=${r.esAdmin}, cambia tarifa=${r.esComandoModo}`);
}

// Si Supabase se cae o no devuelve nada, NADIE debe poder cambiar la tarifa
const sinSupabase = correrCon('Modo mayor', '593961230380', []);
chk(sinSupabase.esComandoModo === false, 'Supabase caido -> nadie cambia tarifa', `-> comando=${sinSupabase.esComandoModo}`);

// Un admin con el whatsapp MAL cargado (corto) no debe volver admin a medio mundo
const malCargado = correrCon('Modo mayor', '584121110380', ['+0380']);
chk(malCargado.esComandoModo === false, 'admin con numero corto mal cargado', `-> esAdmin=${malCargado.esAdmin} (debe ser false)`);

// Un cliente que responde "mayor" a una pregunta: NO cambia nada y su respuesta NO se pierde
const respCliente = correrCon('mayor', '584121112233', ADMINS_OK);
chk(respCliente.esComandoModo === false && respCliente.textoLimpio === 'mayor',
    'cliente responde "mayor" -> no se le borra', `-> textoLimpio="${respCliente.textoLimpio}"`);

// El mismo numero guardado sin el "+" o sin codigo de pais debe seguir reconociendose
for (const [guardado, etiqueta] of [['593961230380', 'sin el +'], ['+593 961 230 380', 'con espacios'], ['961230380', 'sin codigo de pais']]) {
  const r = correrCon('Modo mayor', '593961230380', [guardado]);
  chk(r.esComandoModo === true, `admin guardado ${etiqueta}`, `-> esAdmin=${r.esAdmin}`);
}

console.log('');
console.log(fallos ? `❌ ${fallos} fallaron` : '✅ Todas las pruebas pasaron');
