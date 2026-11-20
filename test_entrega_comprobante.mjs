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
function revisar({ guardado = null, yaEntregado = '', idFoto = ID_FOTO, fotoRecordada = '' } = {}) {
  const base = {
    stanzaId: ID_PUBLICACION, idFoto, jidGrupo: GRUPO,
    claveEntregado: 'entregado:' + ID_PUBLICACION,
    claveFoto: 'ultimaFoto:' + GRUPO + ':quien'
  };
  const $ = (n) => {
    if (n === 'Solo Estos Numeros')     return { first: () => ({ json: base }) };
    if (n === 'Redis Leer Publicacion') return { first: () => ({ json: { pedido: guardado } }) };
    if (n === 'Redis Leer Entregado')   return { first: () => ({ json: { entregado: yaEntregado } }) };
    if (n === 'Redis Leer Ultima Foto') return { first: () => ({ json: { ultimaFoto: fotoRecordada } }) };
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
  const rep = revisar({ guardado: pedido, yaEntregado: '1' });
  chk(rep.length === 1 && rep[0].json.accion === 'repetido', 'la segunda avisa que esta repetido',
      '-> ' + (rep[0] || {}).json?.accion);
  chk(/ya se le envio a Maigreth/i.test((rep[0] || {}).json?.aviso || ''), 'y dice a quien');
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
console.log('=== 7) Foto suelta y despues un punto ===');
{
  // Kelvin pidio poder mandar la foto sola y despues responder con un punto.
  const r = filtrar({ citando: null });
  chk(r.length === 1 && r[0].json.accionPausa === 'recordarFoto',
      'foto sin citar -> se recuerda', '-> ' + (r[0] || {}).json?.accionPausa);
  chk(/^ultimaFoto:/.test((r[0] || {}).json?.claveFoto || ''), 'con una clave por operadora',
      '-> ' + (r[0] || {}).json?.claveFoto);

  // Despues cita con un punto: se dispara la entrega, sin foto propia.
  const r2 = filtrar({ conImagen: false, texto: '.' });
  chk(r2.length === 1 && r2[0].json.accionPausa === 'entregar', 'punto citando -> entregar',
      '-> ' + (r2[0] || {}).json?.accionPausa);
  chk(r2[0].json.idFoto === '', 'sin foto propia: usara la recordada');

  for (const t of ['.', 'ok', 'listo', 'ya']) {
    chk(filtrar({ conImagen: false, texto: t })[0].json.accionPausa === 'entregar',
        'tambien con "' + t + '"');
  }

  // Un comentario largo citando NO debe disparar una entrega.
  const largo = filtrar({ conImagen: false, texto: 'esta cuenta esta mal, revisala por favor' });
  chk(largo.length === 0, 'un comentario largo citando no entrega nada', '-> ' + largo.length);
}

console.log('');
console.log('=== 8) De donde sale la foto que se entrega ===');
{
  const pedido = JSON.stringify({ jid: CLIENTE, nombre: 'Maigreth', idCuenta: ID_CUENTA });
  const propia = revisar({ guardado: pedido, idFoto: ID_FOTO });
  chk(propia[0].json.idFoto === ID_FOTO, 'si cito CON la foto, se usa esa');

  const recordada = revisar({ guardado: pedido, idFoto: '', fotoRecordada: 'AC_FOTO_VIEJA' });
  chk(recordada[0].json.idFoto === 'AC_FOTO_VIEJA', 'si cito con un punto, la recordada');

  const ninguna = revisar({ guardado: pedido, idFoto: '', fotoRecordada: '' });
  chk(ninguna.length === 0, 'punto sin ninguna foto -> no hace nada', '-> ' + ninguna.length);
}

console.log('');
console.log('=== 9) Cuentas multiples: cabecera, monto y a que mensaje citan ===');
{
  const separar = (mensajes, nombreMostrar) => {
    const ap = { nombreMostrar, nombre: 'Maigre Herrera', datosCuenta: 'algo', idCuenta: 'XX' };
    const $ = (n) => {
      if (n === 'Detectar Aprobación') return { item: { json: ap } };
      if (n === 'Combinar') return { item: { json: { mensajes } } };
      return { item: { json: {} } };
    };
    return new Function('$', code('Separar Cuentas'))($).map(i => i.json);
  };

  // Las 4 cuentas en UN solo mensaje.
  const unMensaje = [{ id: 'M1', texto: [
    'Banco Pichincha 2100111111 Ana Perez $30', '',
    'Banco Guayaquil 2200222222 Luis Gomez $40', '',
    'Produbanco 2300333333 Eva Diaz $15', '',
    'Banco Pacifico 2400444444 Juan Mora $35'
  ].join(SALTO) }];
  const r1 = separar(unMensaje, 'Maigreth Herrera');
  chk(r1.length === 4, 'salen las 4 cuentas', '-> ' + r1.length);
  console.log('     ' + r1[0].cuenta.split(SALTO).join(SALTO + '     '));
  chk(r1[0].cuenta.indexOf('Maigreth Herrera - $30') === 0, 'cabecera con nombre y monto');
  chk(r1.every(c => c.idCuenta === 'M1'), 'las 4 citan ese mismo mensaje');
  chk(r1.map(c => c.monto).join(',') === '30,40,15,35', 'y se leyeron los montos',
      '-> ' + r1.map(c => c.monto).join(','));

  // Las 4 en CUATRO mensajes distintos: cada una debe citar el suyo.
  const cuatro = [
    { id: 'A', texto: 'Banco Pichincha 2100111111 Ana $30' },
    { id: 'B', texto: 'Banco Guayaquil 2200222222 Luis $40' },
    { id: 'C', texto: 'Produbanco 2300333333 Eva $15' },
    { id: 'D', texto: 'Banco Pacifico 2400444444 Juan $35' }
  ];
  const r2 = separar(cuatro, 'Maigreth Herrera');
  chk(r2.length === 4, 'tambien salen 4', '-> ' + r2.length);
  chk(r2.map(c => c.idCuenta).join(',') === 'A,B,C,D', 'cada una cita SU mensaje',
      '-> ' + r2.map(c => c.idCuenta).join(','));

  // Las notas del bot no son cuentas.
  const conNota = [
    { id: 'N', texto: '[El cliente envio un COMPROBANTE de pago. Datos leidos: Banco: Guayaquil]' },
    { id: 'A', texto: 'Banco Pichincha 2100111111 Ana $30' }
  ];
  chk(separar(conNota, 'Ana').length === 1, 'la nota del comprobante no cuenta como cuenta');

  // Sin monto escrito: sale solo el nombre, sin inventar.
  const sinMonto = separar([{ id: 'A', texto: 'Banco Pichincha 2100111111 Ana Perez' }], 'Ana Perez');
  chk(sinMonto[0].cuenta.indexOf('Ana Perez' + SALTO) === 0, 'sin monto, solo el nombre',
      '-> ' + JSON.stringify(sinMonto[0].cuenta.split(SALTO)[0]));
  chk(sinMonto[0].monto === null, 'y el monto queda vacio');

  // Caso del 20/11: cuenta sin la palabra "banco". Antes no salia nada al grupo.
  const luis = separar([
    { id: 'C1', texto: '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: 35.00 USD, Banco: Banco Pichincha C.A.]' },
    { id: 'L1', texto: ['Venezuela', '01020000000000012345', 'Maria Perez', '12345678', '35$'].join(SALTO) }
  ], 'Cliente Prueba');
  chk(luis.length === 1, 'la cuenta del caso real (sin la palabra banco) SI sale al grupo', '-> ' + luis.length);
  chk(luis.length === 1 && luis[0].cuenta.indexOf('Cliente Prueba - $35') === 0, 'con cabecera nombre + monto',
      '-> ' + JSON.stringify(luis.length ? luis[0].cuenta.split(SALTO)[0] : ''));
  chk(luis.length === 1 && luis[0].idCuenta === 'L1', 'y cita el mensaje donde dio la cuenta');
}

console.log('');
console.log('=== 10) Aviso si los montos no cuadran ===');
{
  const montos = (lista, total) => {
    const $ = (n) => {
      if (n === 'Separar Cuentas') return { all: () => lista.map(m => ({ json: { monto: m } })) };
      if (n === 'Detectar Aprobación') return { first: () => ({ json: { montoComprobante: total } }) };
      return { all: () => [], first: () => ({ json: {} }) };
    };
    return new Function('$', code('Revisar Montos'))($);
  };

  chk(montos([30, 40, 15, 35], 120).length === 0, 'si suman, no dice nada');
  const r = montos([30, 40, 15, 30], 120);
  chk(r.length === 1, 'si NO suman, avisa', '-> ' + r.length);
  console.log('     ' + (r[0] || {}).json?.aviso);
  chk(/\$5/.test((r[0] || {}).json?.aviso || ''), 'y dice la diferencia');

  chk(montos([30, null, 15, 35], 120).length === 0, 'si falta un monto, se calla');
  chk(montos([30, 40], null).length === 0, 'si no se leyo el comprobante, se calla');
  chk(montos([120], 120).length === 0, 'con una sola cuenta no hay nada que sumar');
}

console.log('');
console.log(fallos ? (fallos + ' fallaron') : 'Todas las pruebas pasaron');
process.exit(fallos ? 1 : 0);
