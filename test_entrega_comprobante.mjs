// Prueba de la ENTREGA DEL COMPROBANTE: la operadora responde en el grupo con la foto del
// envio y el bot se la hace llegar al cliente correcto.
//
// Como sabe el bot de quien es: cuando publica el pedido en el grupo se anota en Redis
// "este mensaje mio es de Maigreth". La operadora RESPONDE (cita) esa publicacion con la
// foto, y el bot busca el mensaje citado en esa lista.
//
// Lo mas importante que se vigila aca: que citar CUALQUIER OTRA COSA no dispare una entrega.
// La autorizacion es el propio Redis, no de que grupo viene ni quien escribio.
//
// Correr con:  node test_entrega_comprobante.mjs

import { readFileSync } from 'fs';

const SALTO = String.fromCharCode(10);
const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const code = n => wf.nodes.find(x => x.name === n).parameters.jsCode;

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(56) + ' ' + (detalle || ''));
};

const GRUPO   = '593961230380-1601657528@g.us';
const CLIENTE = '593962907849@s.whatsapp.net';
const ID_PUBLICACION = '3EB0AAAA1111BBBB2222CC';      // mensaje que publico el bot en el grupo
const ID_FOTO        = 'AC11223344556677889900AABBCCDDEE';  // la foto de la operadora
const ID_CUENTA      = 'AC99887766554433221100FFEEDDCCBB';  // mensaje del cliente con su cuenta

// ---------- Arnes de "Solo Estos Numeros" ----------
function filtrar({ jid = GRUPO, fromMe = false, conImagen = true, citando = ID_PUBLICACION,
                   texto = '', permitidos = ['593961230380'] } = {}) {
  const data = {
    key: { remoteJid: jid, fromMe, id: ID_FOTO },
    pushName: 'Operadora 1',
    messageTimestamp: Math.floor(Date.now() / 1000),
    message: conImagen ? { imageMessage: { caption: texto } } : { conversation: texto }
  };
  if (citando) data.contextInfo = { stanzaId: citando, participant: '123@lid' };

  const items = [{ json: { body: { data } } }];
  const tablas = {
    'Clientes Detal Permitidos': permitidos.map(w => ({ whatsapp: w })),
    'Clientes Mayor Permitidos': [], 'Perfiles Detal App': [], 'Perfiles Mayor App': [],
    'Redis Leer Pausa': [{}], 'Redis Leer Aviso': [{}]
  };
  const $ = (n) => {
    if (n === 'Webhook Evolution API') return { all: () => items, first: () => items[0] };
    const v = tablas[n];
    if (v === undefined) throw new Error('Node "' + n + '" not executed');
    const its = v.map(json => ({ json }));
    return { all: () => its, first: () => its[0] };
  };
  return new Function('$input', '$', code('Solo Estos Numeros'))({ all: () => [{ json: {} }] }, $);
}

// ---------- Arnes de "Revisar Pedido" ----------
function revisar({ guardado = null, yaEntregado = '' } = {}) {
  const base = {
    stanzaId: ID_PUBLICACION, idFoto: ID_FOTO, jidGrupo: GRUPO,
    claveEntregado: 'entregado:' + ID_PUBLICACION
  };
  const $ = (n) => {
    if (n === 'Solo Estos Numeros')    return { first: () => ({ json: base }) };
    if (n === 'Redis Leer Publicacion') return { first: () => ({ json: { pedido: guardado } }) };
    if (n === 'Redis Leer Entregado')   return { first: () => ({ json: { entregado: yaEntregado } }) };
    throw new Error('Node "' + n + '" not executed');
  };
  return new Function('$', code('Revisar Pedido'))($);
}

console.log('=== 1) LO QUE MAS IMPORTA: solo se entrega lo que publico el bot ===');
{
  // Citar una publicacion del bot: se entrega.
  const r = revisar({ guardado: JSON.stringify({ jid: CLIENTE, nombre: 'Maigreth', idCuenta: ID_CUENTA }) });
  chk(r.length === 1, 'citando un pedido del bot -> se entrega', '-> ' + r.length);
  chk(r.length && r[0].json.jid === CLIENTE, 'al cliente correcto', '-> ' + (r[0] || {}).json?.jid);

  // Citar cualquier otra cosa: Redis no tiene nada guardado.
  chk(revisar({ guardado: '' }).length === 0, 'citando otra cosa -> NO entrega nada');
  chk(revisar({ guardado: null }).length === 0, 'sin nada en Redis -> tampoco');
  chk(revisar({ guardado: 'esto no es json' }).length === 0, 'basura en Redis -> tampoco revienta');
  chk(revisar({ guardado: '{"nombre":"X"}' }).length === 0, 'guardado sin jid -> tampoco');
}

console.log('');
console.log('=== 2) No se entrega dos veces ===');
{
  const pedido = JSON.stringify({ jid: CLIENTE, nombre: 'Maigreth', idCuenta: ID_CUENTA });
  chk(revisar({ guardado: pedido, yaEntregado: '' }).length === 1, 'la primera vez si');
  chk(revisar({ guardado: pedido, yaEntregado: '1' }).length === 0, 'la segunda no');
}

console.log('');
console.log('=== 3) Que lleva la entrega ===');
{
  const r = revisar({ guardado: JSON.stringify({ jid: CLIENTE, nombre: 'Maigreth', idCuenta: ID_CUENTA }) });
  const j = r[0].json;
  chk(j.nombre === 'Maigreth', 'el nombre, para el aviso al grupo', '-> ' + j.nombre);
  chk(j.idCuenta === ID_CUENTA, 'el mensaje a citar en el chat del cliente');
  chk(j.idFoto === ID_FOTO, 'la foto que mando la operadora');
  chk(j.stanzaId === ID_PUBLICACION, 'la publicacion a citar en el grupo');
  chk(j.jidGrupo === GRUPO, 'a que grupo responder');

  // Sin idCuenta guardado, igual se entrega: simplemente no se cita nada.
  const r2 = revisar({ guardado: JSON.stringify({ jid: CLIENTE, nombre: 'Ana' }) });
  chk(r2.length === 1 && r2[0].json.idCuenta === '', 'sin cuenta conocida, entrega sin citar');
}

console.log('');
console.log('=== 4) Cuando se dispara la entrega y cuando no ===');
{
  const esEntrega = (r) => r.length === 1 && r[0].json.accionPausa === 'entregar';

  chk(esEntrega(filtrar({})), 'foto citando, en el grupo -> entregar');
  chk(filtrar({}) [0].json.stanzaId === ID_PUBLICACION, 'se queda con el mensaje citado');
  chk(filtrar({})[0].json.idFoto === ID_FOTO, 'y con el id de la foto');

  // Lo manda Kelvin desde su propio telefono: tambien tiene que valer.
  chk(esEntrega(filtrar({ fromMe: true })), 'lo manda Kelvin (fromMe) -> igual entrega');

  // Casos que NO son una entrega.
  chk(!esEntrega(filtrar({ citando: null })), 'foto SIN citar -> no');
  chk(!esEntrega(filtrar({ conImagen: false, texto: 'listo ya transferi' })), 'solo texto citando -> no');
  chk(!esEntrega(filtrar({ jid: CLIENTE, fromMe: false })), 'foto citada en un chat privado -> no');
}

console.log('');
console.log('=== 5) Lo de siempre sigue funcionando ===');
{
  // Un cliente autorizado escribiendo normal.
  const r = filtrar({ jid: '593961230380@s.whatsapp.net', conImagen: false, citando: null,
                      texto: 'hola', permitidos: ['593961230380'] });
  chk(r.length === 1 && r[0].json.accionPausa === 'seguir', 'un cliente autorizado pasa',
      '-> ' + (r[0] || {}).json?.accionPausa);

  // Un numero que no esta en ninguna lista.
  chk(filtrar({ jid: '584121234567@s.whatsapp.net', conImagen: false, citando: null,
                texto: 'hola', permitidos: ['593961230380'] }).length === 0,
      'uno no autorizado sigue sin pasar');

  // Mensajes de grupo que no son entregas se siguen descartando.
  chk(filtrar({ conImagen: false, citando: null, texto: 'buenos dias equipo' }).length === 0,
      'charla del grupo se descarta');
}

console.log('');
console.log('=== 6) El id del mensaje con la cuenta viaja hasta el final ===');
{
  // "Combinar" tiene que entender el formato nuevo {id,texto} Y el viejo (texto pelado),
  // porque al desplegar puede haber mensajes guardados de antes en Redis.
  const combinar = (mensajes) => {
    const $ = (n) => ({ item: { json: { mensajes } } });
    return new Function('$', code('Combinar'))($)[0].json;
  };

  const nuevo = combinar([
    JSON.stringify({ id: 'AA1', texto: '[El cliente envio un COMPROBANTE de pago. Datos leidos: Banco: Guayaquil]' }),
    JSON.stringify({ id: ID_CUENTA, texto: 'Banco Pichincha 2100123456 Carlos Mogue' })
  ]);
  chk(nuevo.mensajes.length === 2, 'formato nuevo: separa los mensajes', '-> ' + nuevo.mensajes.length);
  chk(nuevo.mensajes[1].id === ID_CUENTA, 'y conserva el id de cada uno');
  chk(/Banco Pichincha/.test(nuevo.mensajeCombinado), 'el texto combinado sale igual que antes');

  const viejo = combinar(['hola', 'que tasa hay']);
  chk(viejo.mensajeCombinado.indexOf('hola') === 0, 'formato viejo (texto pelado) no se pierde');
  chk(viejo.mensajes.length === 2 && viejo.mensajes[0].id === '', 'queda sin id, pero no revienta');

  // Y "Detectar Aprobacion" saca de ahi cual era el mensaje de la cuenta.
  const detectar = (mensajes) => {
    const combinado = mensajes.map(m => m.texto).join(SALTO + SALTO);
    const $ = (n) => {
      if (n === 'Combinar') return { item: { json: { mensajeCombinado: combinado, mensajes } } };
      if (n === 'Webhook Evolution API') return { first: () => ({ json: { body: { data: {
        key: { remoteJid: CLIENTE }, pushName: 'Maigre Herrera' } } } }) };
      return { item: { json: {} }, first: () => ({ json: {} }) };
    };
    return new Function('$', code('Detectar Aprobación'))($);
  };

  const r = detectar([
    { id: 'AA1', texto: '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: $50, Banco: Guayaquil]' },
    { id: ID_CUENTA, texto: 'Banco Pichincha' + SALTO + '2100123456' + SALTO + 'Carlos Mogue' }
  ]);
  chk(r.length === 1, 'aprueba con comprobante + cuenta', '-> ' + r.length);
  chk(r.length && r[0].json.idCuenta === ID_CUENTA, 'y sabe cual mensaje citarle al cliente',
      '-> ' + (r[0] || {}).json?.idCuenta);

  // La nota del comprobante NO debe tomarse como el mensaje de la cuenta.
  const soloComprobante = detectar([
    { id: 'AA1', texto: '[El cliente envio un COMPROBANTE de pago. Datos leidos: Banco: Guayaquil, Cuenta: 123]' }
  ]);
  chk(soloComprobante.length === 0, 'solo el comprobante sigue sin aprobar');
}

console.log('');
console.log(fallos ? (fallos + ' fallaron') : 'Todas las pruebas pasaron');
process.exit(fallos ? 1 : 0);
