
const _strip = s => s ? String(s).replace(/^\d+[\w\.]*\s*/, '') : '';
const _findNode = (nodes, n) => (nodes || []).find(x => x.name === n || _strip(x.name) === _strip(n));
const _getConn = (conns, n) => {
  if (!conns) return null;
  const k = Object.keys(conns).find(x => x === n || _strip(x) === _strip(n));
  return k ? Reflect.get(conns, k) : null;
};
// Prueba del filtro "a quien le contesta el bot" (nodo "Solo Estos Numeros",
// el primero despues del webhook en el bot de WhatsApp).
//
// Hay dos formas de limitarlo:
//   1) $SOLO_ESTOS   -> lista escrita en build_v12.ps1 (modo prueba)
//   2) $MODO_SOLO_CLIENTES -> los numeros salen de Supabase, de las tablas
//      clientes_bot_detal y clientes_bot_mayor
//
// Lo que mas importa de todo esto, y por eso va primero, es que el bot NO se
// quede mudo sin que nadie se entere:
//   - sin ninguna de las dos formas -> le contesta a todos;
//   - con el modo prendido pero las tablas vacias -> le contesta a todos;
//   - con el modo prendido pero Supabase caido -> le contesta a todos.
// Un problema de base de datos no puede dejar al negocio sin atender.
//
// Correr con:  node test_solo_estos.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const nodo = _findNode(wf.nodes, 'Solo Estos Numeros');
if (!nodo) { console.log('FALLO: no existe el nodo "Solo Estos Numeros"'); process.exit(1); }

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(56) + ' ' + (detalle || ''));
};

// Corre el codigo REAL del nodo, cambiandole la lista y el interruptor.
//   lista  : lo que tendria $SOLO_ESTOS
//   modo   : lo que tendria $MODO_SOLO_CLIENTES
//   tablas : { detal: [...], mayor: [...] } con las filas que devolveria Supabase.
//            Si una tabla es la cadena 'CAIDA', se simula que el nodo fallo.
//            Si es undefined, se simula que el nodo ni corrio.
function correr(lista, modo, jids, tablas, edadMin, extra) {
  const ex = extra || {};
  const js = nodo.parameters.jsCode
    .replace(/const SOLO_ESTOS = .*;/, 'const SOLO_ESTOS = ' + JSON.stringify(lista) + ';')
    .replace(/const MODO_SOLO_CLIENTES = .*;/, 'const MODO_SOLO_CLIENTES = ' + (modo ? 'true' : 'false') + ';');

  const t = tablas || {};
  // Por defecto el mensaje es de AHORA. Con "edadMin" se simula uno viejo.
  const ahora = Math.floor(Date.now() / 1000);
  const items = jids.map(j => ({
    json: { body: { data: {
      key: { remoteJid: j, fromMe: !!ex.fromMe, id: ex.idMensaje || 'A5ABCDEF0123456789ABCDEF01234567' },
      pushName: ex.pushName,
      message: ex.mensaje ? ex.mensaje : (ex.texto ? { conversation: ex.texto } : undefined),
      messageTimestamp: ahora - Math.round((edadMin || 0) * 60)
    } } }
  }));

  // Por defecto las tablas de la app van vacias: la mayoria de las pruebas son de las
  // tablas que carga Kelvin a mano.
  const porNodo = {
    'Clientes Detal Permitidos': t.detal,
    'Clientes Mayor Permitidos': t.mayor,
    'Perfiles Detal App':        (t.appDetal === undefined ? [] : t.appDetal),
    'Perfiles Mayor App':        (t.appMayor === undefined ? [] : t.appMayor),
    'Redis Leer Pausa':          [ ex.enPausa  ? { pausaBot: 'auto' } : {} ],
    'Redis Leer Aviso':          [ ex.yaAvisado ? { avisoPausa: '1' }  : {} ]
  };
  const $ = (n) => {
    // El mensaje de WhatsApp se busca en el webhook, no en $input.
    if (n === 'Webhook Evolution API' || _strip(n) === 'Webhook Evolution API') return { all: () => items, first: () => items[0] };
    const v = porNodo[n];
    if (v === undefined) throw new Error('Node "' + n + '" not executed');
    const filas = (v === 'CAIDA')
      ? [{ error: { message: 'Supabase no responde' } }]
      : v;
    const its = filas.map(json => ({ json }));
    return { all: () => its, first: () => its[0] };
  };

  // IMPORTANTE: asi es como llega de verdad. Justo antes de este nodo hay dos consultas a
  // Supabase, y un nodo de Supabase devuelve LAS FILAS DE LA TABLA: eso es lo que trae
  // $input. Si el nodo leyera de ahi, creeria que el mensaje es una fila de la tabla.
  const filasQueLleganPorInput = (t.appMayor && t.appMayor !== 'CAIDA') ? t.appMayor : [{}];
  const $input = { all: () => filasQueLleganPorInput.map(json => ({ json })) };

  const salida = new Function('$input', '$', js)($input, $);
  return Object.assign(salida.map(it => (it.json.body ? it.json.body.data.key.remoteJid : it.json.jid)), {
    nombres:  salida.map(it => it.json.nombreCargado || ''),
    tarifas:  salida.map(it => it.json.tarifaCargada || ''),
    acciones: salida.map(it => it.json.accionPausa   || ''),
    items:    salida.map(it => it.json)
  });
}

const KELVIN  = '593961230380@s.whatsapp.net';
const CLIENTE = '584121234567@s.whatsapp.net';
const OTRO    = '573001112233@s.whatsapp.net';
const GRUPO   = '120363291497664389@g.us';
const TODOS   = [KELVIN, CLIENTE, OTRO, GRUPO];
const VACIAS  = { detal: [], mayor: [] };

console.log('=== 1) Tablas vacias: NO le contesta a nadie (pedido de Kelvin) ===');
{
  // Kelvin pidio expresamente que el bot solo le responda a quien el vaya registrando.
  // Con el modo prendido y la tabla vacia, no pasa nadie. Es distinto de no poder LEER
  // la tabla: eso se prueba abajo y ahi si se contesta a todos.
  chk(correr([], true, TODOS, VACIAS).length === 0,
      'modo prendido y tablas vacias -> no pasa nadie', '-> ' + correr([], true, TODOS, VACIAS).length);
  chk(correr([], false, TODOS, VACIAS).length === 4,
      'con el modo APAGADO si contesta a todos');
}

console.log('');
console.log('=== 2) Si Supabase no se puede LEER, contesta a todos ===');
{
  // Una falla de base de datos no puede dejar al negocio entero sin atender, y encima
  // en silencio. Esto es distinto de la tabla vacia de arriba.
  chk(correr([], true, TODOS, { detal: 'CAIDA', mayor: [] }).length === 4,
      'modo prendido y Supabase CAIDO -> contesta a todos');
  chk(correr([], true, TODOS, { detal: [], mayor: 'CAIDA' }).length === 4,
      'si falla la tabla de mayor, igual contesta a todos');
  chk(correr([], true, TODOS, {}).length === 4,
      'si los nodos de Supabase ni corrieron -> contesta a todos');
}

console.log('');
console.log('=== 3) Los numeros salen de Supabase ===');
{
  const tablas = {
    detal: [{ whatsapp: '593961230380', nombre: 'Kelvin' }],
    mayor: [{ whatsapp: '584121234567', nombre: 'Cliente mayor' }]
  };
  const r = correr([], true, TODOS, tablas);
  chk(r.length === 2, 'pasan los 2 cargados', '-> ' + r.length);
  chk(r.indexOf(KELVIN) !== -1 && r.indexOf(CLIENTE) !== -1, 'uno de detal y uno de mayor');
  chk(r.indexOf(OTRO) === -1, 'el que no esta cargado NO pasa');
  chk(r.indexOf(GRUPO) === -1, 'los grupos tampoco');
}

console.log('');
console.log('=== 4) El numero se puede cargar como sea ===');
{
  const formas = ['+593961230380', '593 961 230 380', '+593-96-123-0380', '961230380'];
  for (const f of formas){
    const r = correr([], true, [KELVIN], { detal: [{ whatsapp: f }], mayor: [] });
    chk(r.length === 1, 'cargado como "' + f + '"');
  }
}

console.log('');
console.log('=== 5) La columna "activo" apaga un numero sin borrarlo ===');
{
  const r = correr([], true, TODOS, {
    detal: [{ whatsapp: '593961230380', activo: false }, { whatsapp: '584121234567', activo: true }],
    mayor: []
  });
  chk(r.indexOf(KELVIN) === -1, 'activo=false queda afuera');
  chk(r.indexOf(CLIENTE) !== -1, 'activo=true sigue pasando');

  // Si la columna no existe (undefined), NO se apaga a nadie.
  const r2 = correr([], true, [KELVIN], { detal: [{ whatsapp: '593961230380' }], mayor: [] });
  chk(r2.length === 1, 'sin columna activo, el numero pasa igual');
}

console.log('');
console.log('=== 6) La lista del codigo le gana a Supabase (modo prueba) ===');
{
  const tablas = { detal: [{ whatsapp: '584121234567' }], mayor: [] };
  const r = correr(['593961230380'], true, TODOS, tablas);
  chk(r.length === 1 && r[0] === KELVIN, 'solo pasa el del codigo', '-> ' + JSON.stringify(r));
  chk(r.indexOf(CLIENTE) === -1, 'el de Supabase NO pasa mientras se prueba');

  // Y en modo prueba NO se hace red de seguridad: si la lista del codigo tiene
  // numeros, manda esa lista aunque Supabase este caido.
  const r2 = correr(['593961230380'], true, TODOS, { detal: 'CAIDA', mayor: 'CAIDA' });
  chk(r2.length === 1, 'con Supabase caido sigue mandando la lista del codigo', '-> ' + r2.length);
}

console.log('');
console.log('=== 7) Un numero corto mal cargado NO abre la puerta a todos ===');
{
  const r = correr([], true, [KELVIN, '584120000380@s.whatsapp.net'],
                   { detal: [{ whatsapp: '0380' }], mayor: [] });
  chk(r.length === 0, 'con 4 digitos no deja pasar a nadie', '-> ' + r.length);
}

console.log('');
console.log('=== 8) Filas basura no revientan el nodo ===');
{
  const r = correr([], true, [KELVIN], {
    detal: [{}, { whatsapp: '' }, { whatsapp: null }, { nombre: 'sin numero' }],
    mayor: []
  });
  // Las filas sin numero se ignoran. Como no queda ningun numero valido, no pasa nadie:
  // una tabla llena de filas rotas cuenta igual que una tabla vacia.
  chk(r.length === 0, 'filas sin numero se ignoran y no pasa nadie', '-> ' + r.length);
}

console.log('');
console.log('=== 9) El nombre cargado viaja pegado al mensaje ===');
{
  // El agente lo usa para saludar por el nombre que Kelvin escribio en Supabase.
  const tablas = {
    detal: [{ whatsapp: '593961230380', nombre: 'Maria Perez' }],
    mayor: [{ whatsapp: '584121234567', nombre: 'Jose Mayorista' }]
  };
  const r = correr([], true, [KELVIN, CLIENTE], tablas);
  chk(r.nombres[0] === 'Maria Perez', 'el de detal trae su nombre', '-> "' + r.nombres[0] + '"');
  chk(r.nombres[1] === 'Jose Mayorista', 'el de mayor tambien', '-> "' + r.nombres[1] + '"');

  // Sin nombre cargado no se inventa nada.
  const r2 = correr([], true, [KELVIN], { detal: [{ whatsapp: '593961230380' }], mayor: [] });
  chk(r2.nombres[0] === '', 'si no le cargaste nombre, va vacio', '-> "' + r2.nombres[0] + '"');

  // Y se busca IGUAL aunque el filtro no este filtrando: el nombre sirve siempre.
  const r3 = correr([], false, [KELVIN], tablas);
  chk(r3.length === 1 && r3.nombres[0] === 'Maria Perez',
      'con el modo apagado igual trae el nombre', '-> "' + r3.nombres[0] + '"');
}

console.log('');
console.log('=== 10) Cada tabla da su tarifa ===');
{
  // clientes_bot_mayor -> tarifa mayor | clientes_bot_detal -> tarifa detal.
  const r = correr([], true, [KELVIN, CLIENTE], {
    detal: [{ whatsapp: '593961230380', nombre: 'Kelvin' }],
    mayor: [{ whatsapp: '584121234567', nombre: 'Jose' }]
  });
  chk(r.tarifas[0] === 'detal', 'el de clientes_bot_detal -> detal', '-> "' + r.tarifas[0] + '"');
  chk(r.tarifas[1] === 'mayor', 'el de clientes_bot_mayor -> mayor', '-> "' + r.tarifas[1] + '"');

  // Cargado por error en las DOS: gana detal. Darle tarifa de mayorista a un cliente de
  // detal cuesta plata; al reves solo es un reclamo que se corrige.
  const r2 = correr([], true, [KELVIN], {
    detal: [{ whatsapp: '593961230380' }],
    mayor: [{ whatsapp: '593961230380' }]
  });
  chk(r2.tarifas[0] === 'detal', 'cargado en las dos -> gana detal', '-> "' + r2.tarifas[0] + '"');

  // Apagado con activo=false no deberia fijar tarifa.
  const r3 = correr([], false, [KELVIN], {
    detal: [], mayor: [{ whatsapp: '593961230380', activo: false }]
  });
  chk(r3.tarifas[0] === '', 'un numero apagado no fija tarifa', '-> "' + r3.tarifas[0] + '"');
}

console.log('');
console.log('=== 11) Los registrados en la APP tambien entran ===');
{
  // Kelvin no tiene que cargar a mano a quien ya se registro en la app. Esto se agrego
  // despues de que su propio numero, que SI estaba en perfiles_detal, quedara afuera.
  const r = correr([], true, [KELVIN, CLIENTE, OTRO], {
    detal: [], mayor: [],
    appDetal: [{ whatsapp: '+593961230380' }],
    appMayor: [{ whatsapp: '584121234567' }]
  });
  chk(r.length === 2, 'entran los dos de la app', '-> ' + r.length);
  chk(r.indexOf(OTRO) === -1, 'el que no esta en ningun lado sigue afuera');

  // Estar en la app NO les fija tarifa: eso lo decide perfiles_mayor mas adelante,
  // igual que siempre.
  chk(r.tarifas[0] === '' && r.tarifas[1] === '',
      'estar en la app no fija tarifa', '-> "' + r.tarifas[0] + '" / "' + r.tarifas[1] + '"');

  // Si una de las cuatro consultas falla, se abre la puerta a todos.
  const r2 = correr([], true, [KELVIN, CLIENTE, OTRO], {
    detal: [], mayor: [], appDetal: 'CAIDA', appMayor: []
  });
  chk(r2.length === 3, 'si falla la consulta a la app -> contesta a todos', '-> ' + r2.length);
}

console.log('');
console.log('=== 12) No contesta mensajes viejos ===');
{
  // Cuando Evolution se reconecta manda de golpe todo lo pendiente, hasta de dias atras.
  // El 18/11 entraron dos rafagas (70 y 200 mensajes) con cosas de 2 dias antes.
  const tablas = { detal: [{ whatsapp: '593961230380' }], mayor: [] };

  chk(correr([], true, [KELVIN], tablas, 0).length === 1,
      'un mensaje de ahora pasa');
  chk(correr([], true, [KELVIN], tablas, 19).length === 1,
      'de 19 minutos todavia pasa');
  chk(correr([], true, [KELVIN], tablas, 21).length === 0,
      'de 21 minutos se ignora');
  chk(correr([], true, [KELVIN], tablas, 60 * 48).length === 0,
      'de 2 dias se ignora (el caso real del 18/11)');

  // Sin fecha no se descarta: ante la duda, mejor contestar de mas.
  const js = nodo.parameters.jsCode;
  const $ = (n) => {
    if (n === 'Webhook Evolution API' || _strip(n) === 'Webhook Evolution API') return { all: () => [{ json: { body: { data: {
      key: { remoteJid: KELVIN } } } } }] };
    const v = { 'Clientes Detal Permitidos': [{ whatsapp: '593961230380' }],
                'Clientes Mayor Permitidos': [], 'Perfiles Detal App': [],
                'Perfiles Mayor App': [] }[n];
    return { all: () => v.map(json => ({ json })) };
  };
  const r = new Function('$input', '$', js)({ all: () => [{ json: {} }] }, $);
  chk(r.length === 1, 'un mensaje SIN fecha no se descarta', '-> ' + r.length);
}

console.log('');
console.log('=== 13) Pausa: cuando Kelvin escribe, el bot se calla ===');
{
  // El numero del bot es tambien el personal de Kelvin. Si el escribe en un chat, el bot
  // no debe meterse. Los dos llegan con fromMe=true; se distinguen por el id: los que manda
  // el bot (Baileys) empiezan por "3EB0".
  const tablas = { detal: [{ whatsapp: '593961230380' }], mayor: [] };
  const BOT = { fromMe: true, idMensaje: '3EB0931FEBF312F8C482CF', texto: 'Hola, en que te ayudo' };
  const KEL = { fromMe: true, idMensaje: 'A5E490C02815D6233FFA3BABA756F989', texto: 'ya te paso la cuenta' };

  const r1 = correr([], true, [CLIENTE], tablas, 0, KEL);
  chk(r1.acciones[0] === 'pausar', 'si escribe Kelvin -> pausar', '-> ' + r1.acciones[0]);
  chk(r1.items[0].segundos === 3600, 'la pausa dura 1 hora', '-> ' + r1.items[0].segundos + 's');
  chk(r1.items[0].clave === 'pausaBot:' + CLIENTE, 'la pausa es de ESE chat', '-> ' + r1.items[0].clave);

  const r2 = correr([], true, [CLIENTE], tablas, 0, BOT);
  chk(r2.length === 0, 'el bot NO se pausa a si mismo al responder', '-> ' + r2.length);

  // En grupos no hay nada que pausar.
  const r3 = correr([], true, [GRUPO], tablas, 0, KEL);
  chk(r3.length === 0, 'en un grupo no se pausa nada', '-> ' + r3.length);
}

console.log('');
console.log('=== 14) Pausa: los comandos bot on / bot off ===');
{
  const tablas = { detal: [{ whatsapp: '593961230380' }], mayor: [] };
  const como = (t) => ({ fromMe: true, idMensaje: 'A5AAAA1111BBBB2222CCCC3333DDDD44', texto: t });

  for (const t of ['bot on', 'Bot On', 'BOT ON', ' bot on ']) {
    const r = correr([], true, [CLIENTE], tablas, 0, como(t));
    chk(r.acciones[0] === 'reanudar', 'reanuda con "' + t + '"', '-> ' + r.acciones[0]);
  }
  const rOff = correr([], true, [CLIENTE], tablas, 0, como('bot off'));
  chk(rOff.acciones[0] === 'pausar', '"bot off" pausa', '-> ' + rOff.acciones[0]);
  chk(rOff.items[0].segundos === 12 * 3600, '"bot off" dura 12 horas', '-> ' + rOff.items[0].segundos + 's');

  // Un mensaje normal de Kelvin NO es un comando: pausa normal, no 12 horas.
  const rNorm = correr([], true, [CLIENTE], tablas, 0, como('dame un momento y te digo'));
  chk(rNorm.items[0].segundos === 3600, 'un mensaje normal pausa 1 hora, no 12');
}

console.log('');
console.log('=== 15) Pausa: el cliente escribe mientras Kelvin atiende ===');
{
  const tablas = { detal: [{ whatsapp: '584121234567', nombre: 'Maria' }], mayor: [] };

  // Sin pausa, pasa normal.
  const r1 = correr([], true, [CLIENTE], tablas, 0, { texto: 'hola' });
  chk(r1.acciones[0] === 'seguir', 'sin pausa el bot atiende', '-> ' + r1.acciones[0]);

  // Con pausa, no se le contesta pero se avisa.
  const r2 = correr([], true, [CLIENTE], tablas, 0,
                    { texto: 'Tienes tasa para Colombia?', pushName: 'Maria', enPausa: true });
  chk(r2.acciones[0] === 'avisar', 'con pausa NO contesta, avisa', '-> ' + r2.acciones[0]);
  const aviso = (r2.items[0] || {}).aviso || '';
  const SALTO = String.fromCharCode(10);
  console.log('     ' + aviso.split(SALTO).join(SALTO + '     '));
  chk(/Maria/.test(aviso), 'el aviso dice quien escribio');
  chk(/Tienes tasa para Colombia/.test(aviso), 'y que escribio');
  chk(/bot on/.test(aviso), 'y como reactivarlo');

  // A alguien NO autorizado no se avisa aunque haya pausa: seria puro ruido.
  const r3 = correr([], true, [OTRO], tablas, 0, { texto: 'hola', enPausa: true });
  chk(r3.length === 0, 'de un no autorizado no se avisa nada', '-> ' + r3.length);
}

console.log('');
console.log('=== 16) Pausa: solo avisa de lo que importa, y una vez ===');
{
  const tablas = { detal: [{ whatsapp: '584121234567', nombre: 'Maria' }], mayor: [] };
  const enPausa = (texto, yaAvisado) => correr([], true, [CLIENTE], tablas, 0,
                                               { texto, pushName: 'Maria', enPausa: true, yaAvisado });

  // Charla personal: ni contesta ni molesta al grupo.
  for (const t of ['jajaja', 'ok gracias', 'dale pues', 'buenas noches', 'ya vi']) {
    chk(enPausa(t).length === 0, 'no avisa por "' + t + '"');
  }

  // Cosas del negocio: si avisa.
  for (const t of ['tienes tasa para colombia?', 'pasame la CUENTA', 'cuanto es en dolares',
                   'quiero enviar a peru', 'me llego el comprobante?']) {
    chk(enPausa(t).acciones[0] === 'avisar', 'avisa por "' + t + '"');
  }

  // Sin acentos ni mayusculas tambien.
  chk(enPausa('¿Cuál es la TASA?').acciones[0] === 'avisar', 'aguanta acentos y mayusculas');

  // Y una sola vez: si ya se aviso hace poco, el resto no molesta.
  chk(enPausa('tienes tasa?', true).length === 0, 'si ya se aviso, no repite');

  // El aviso lleva los datos para marcar que ya se aviso.
  const r = enPausa('tienes tasa?');
  chk(r.items[0].claveAviso === 'avisoPausa:' + CLIENTE, 'lleva la clave del aviso',
      '-> ' + r.items[0].claveAviso);
  chk(r.items[0].segundosAviso === 900, 'no repite en 15 minutos',
      '-> ' + r.items[0].segundosAviso + 's');
}

console.log('');
console.log('=== 16b) Una reaccion (emoji) NO es un mensaje ===');
{
  // 20/11: un cliente reacciono con un emoji a un mensaje del bot y el bot le contesto
  // "Hola Luis, en que puedo ayudarte hoy?". WhatsApp manda la reaccion como un mensaje sin
  // texto; el bot lo tomaba por un mensaje vacio.
  const tablas = { detal: [{ whatsapp: '584121234567', nombre: 'Maria' }], mayor: [] };
  const reaccion = { reactionMessage: { key: { id: 'XYZ' }, text: '❤️' } };
  const r1 = correr([], true, [CLIENTE], tablas, 0, { mensaje: reaccion });
  chk(r1.length === 0, 'la reaccion de un cliente se descarta', '-> ' + r1.length + ' items');
  const r2 = correr([], true, [CLIENTE], tablas, 0, { mensaje: reaccion, enPausa: true });
  chk(r2.length === 0, 'tampoco avisa al grupo si el chat esta en pausa', '-> ' + r2.length);
  const r3 = correr([], true, [CLIENTE], tablas, 0, { texto: 'hola' });
  chk(r3.acciones[0] === 'seguir', 'un mensaje normal sigue pasando', '-> ' + r3.acciones[0]);
  const r4 = correr([], true, [CLIENTE], tablas, 0, { mensaje: { imageMessage: { caption: '' } } });
  chk(r4.acciones[0] === 'seguir', 'una foto sigue pasando', '-> ' + r4.acciones[0]);
}

console.log('');
console.log('=== 16c) Sticker, ubicacion o mensaje borrado: NO se contesta ===');
{
  // Revision de los chats (20/11): los clientes mandaron 102 stickers y 16 ubicaciones. El bot
  // los tomaba por mensajes vacios y contestaba "Hola, en que puedo ayudarte?".
  const tablas = { detal: [{ whatsapp: '584121234567', nombre: 'Maria' }], mayor: [] };
  for (const [etiqueta, mensaje] of [
    ['un sticker', { stickerMessage: { url: 'x', mimetype: 'image/webp' } }],
    ['una ubicacion', { locationMessage: { degreesLatitude: -2.1, degreesLongitude: -79.9 } }],
    ['una ubicacion en vivo', { liveLocationMessage: { degreesLatitude: -2.1 } }],
    ['un mensaje borrado/editado', { protocolMessage: { type: 0 } }]
  ]) {
    const r = correr([], true, [CLIENTE], tablas, 0, { mensaje });
    chk(r.length === 0, etiqueta + ' de un cliente se descarta', '-> ' + r.length + ' items');
  }
  const pausa = correr([], true, [CLIENTE], tablas, 0, { mensaje: { stickerMessage: {} }, enPausa: true });
  chk(pausa.length === 0, 'un sticker tampoco avisa al grupo si el chat esta en pausa', '-> ' + pausa.length);
  const audio = correr([], true, [CLIENTE], tablas, 0, { mensaje: { audioMessage: { seconds: 5 } } });
  chk(audio.acciones[0] === 'seguir', 'una nota de voz sigue pasando', '-> ' + audio.acciones[0]);
  const conPie = correr([], true, [CLIENTE], tablas, 0, { mensaje: { videoMessage: { caption: 'mira' } } });
  chk(conPie.acciones[0] === 'seguir', 'un video con texto sigue pasando', '-> ' + conPie.acciones[0]);
}

console.log('');
console.log('=== 17) Como quedo desplegado AHORA MISMO ===');
{
  const l = nodo.parameters.jsCode.match(/const SOLO_ESTOS = (.*);/)[1];
  const m = nodo.parameters.jsCode.match(/const MODO_SOLO_CLIENTES = (.*);/)[1];
  console.log('     SOLO_ESTOS = ' + l + '   |   MODO_SOLO_CLIENTES = ' + m);
  // Esto no prueba logica: deja a la vista como quedo configurado, para que un cambio
  // de estado no pase desapercibido. Si algun dia hay que apagarlo, se cambia el $true
  // de build_v12.ps1 y tambien este 'true'.
  chk(l === '[]', 'la lista del codigo esta vacia (no estamos en modo prueba)');
  chk(m === 'true', 'el modo SOLO CLIENTES esta prendido');
}

console.log('');
console.log(fallos ? (fallos + ' fallaron') : 'Todas las pruebas pasaron');
process.exit(fallos ? 1 : 0);
