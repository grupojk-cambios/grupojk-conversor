
const _strip = s => s ? String(s).replace(/^\d+[\w\.]*\s*/, '') : '';
const _findNode = (nodes, n) => (nodes || []).find(x => x.name === n || _strip(x.name) === _strip(n));
const _getConn = (conns, n) => {
  if (!conns) return null;
  const k = Object.keys(conns).find(x => x === n || _strip(x) === _strip(n));
  return k ? Reflect.get(conns, k) : null;
};
// Prueba de la Entrega 2: el registro de cada operacion en Supabase (tabla transacciones_detal_por_whatsapp).
//
//   - al publicarse una operacion en transferir se guarda UNA FILA POR CUENTA destino ('en_proceso')
//   - cuando la operadora devuelve la foto de una cuenta, ESA fila pasa a 'enviada' (1 por 1)
//   - "¿ya llego?": el agente contesta con el estado de la ultima operacion
//   - "la misma cuenta de siempre": el bot muestra la ultima cuenta y pide un "si"
//   - una captura repetida se reconoce aunque sea de hace semanas (Redis solo recuerda 48 h)
//
// Todos los datos de esta prueba son INVENTADOS: el repositorio es publico.
//
// Correr con:  node test_registro.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const wfOp = JSON.parse(readFileSync('workflow_operadoras.json', 'utf8').replace(/^﻿/, ''));
const wfPub = JSON.parse(readFileSync('workflow_operacion_publicar.json', 'utf8').replace(/^﻿/, ''));
const wfIa = JSON.parse(readFileSync('workflow_ia_atencion.json', 'utf8').replace(/^﻿/, ''));
const nodo = n => _findNode(wf.nodes, n) || _findNode(wfOp.nodes, n) || _findNode(wfPub.nodes, n) || _findNode(wfIa.nodes, n);
const code = n => nodo(n).parameters.jsCode;
const SALTO = String.fromCharCode(10);

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(72) + ' ' + (detalle || ''));
};

const NUESTRAS = [{ Pais: 'Ecuador', Metodo: 'Pichincha', Datos: '*CUENTA AUTORIZADA USD*\n\n1) 2200000001\n*Pichincha ahorro*\nC.I: 0900000001\n*Titular Empresa*' }];
let reloj = Date.parse('2026-11-21T20:00:00Z');   // 3:00 pm en Ecuador
const pasan = minutos => { reloj += minutos * 60000; };
const iso = msAtras => new Date(reloj - msAtras).toISOString();
const DIA = 86400000;

function revisar(textos, op, historial, ex) {
  ex = ex || {};
  const mensajes = textos.map((t, i) => ({ id: (ex.ids && ex.ids[i]) || ('M' + i), texto: t }));
  const real = Date.now; Date.now = () => reloj;
  try {
    const $ = (n) => {
      if (n === 'Code in JavaScript' || _strip(n) === 'Code in JavaScript') return { first: () => ({ json: { cuentas: NUESTRAS, modo: 'detal', nombreCliente: '' } }) };
      if (n === 'Cuando lo Llama el Bot' || _strip(n) === 'Cuando lo Llama el Bot') return { first: () => ({ json: { mensajes } }) };
      if (n === 'Combinar' || _strip(n) === 'Combinar') return { first: () => ({ json: { mensajes } }) };
      if (n === 'Redis Leer Operacion' || _strip(n) === 'Redis Leer Operacion') return { first: () => ({ json: { operacion: op ? JSON.stringify(op) : null } }) };
      if (n === 'Redis Leer Pregunta' || _strip(n) === 'Redis Leer Pregunta') return { first: () => ({ json: { pregunta: '0' } }) };
      if (n === 'Consultar Operaciones WhatsApp' || _strip(n) === 'Consultar Operaciones WhatsApp') {
        if (historial === 'CAIDA') return { all: () => [{ json: { error: { message: 'Supabase no responde' } } }], first: () => ({ json: {} }) };
        const filas = (historial && historial.length) ? historial : [{}];   // asi sale el nodo sin filas
        return { all: () => filas.map(json => ({ json })), first: () => ({ json: filas[0] }) };
      }
      throw new Error('nodo inesperado: ' + n);
    };
    const r = new Function('$', code('Revisar Operacion'))($)[0].json;
    r.op = JSON.parse(r.operacionNueva);
    return r;
  } finally { Date.now = real; }
}

const captura = (monto, ref, banco, huella) => '[El cliente envio un COMPROBANTE de pago. Datos leidos: Monto: $' + monto
  + ', Banco: ' + (banco || 'Pichincha') + ', Fecha: nov 21, 2026, '
  + (ref ? 'Numero de transaccion: ' + ref : 'Referencia: no visible') + (huella ? ' Huella: ' + huella : '') + ']';
const CUENTA = ['Banco Ejemplo', '01020000000000099999', 'Pedro Prueba', 'V 11111111', '$60'].join(SALTO);
const fila = (extra) => Object.assign({
  id: 1, creado: iso(10 * DIA), whatsapp: '593990000001', estado: 'enviada', monto_deposito: 60, ref_deposito: '55550001',
  banco_origen: 'Pichincha', huella_foto: 'aaaa1111bbbb2222', id_msg_captura: 'VIEJA1',
  capturas: [{ id: 'VIEJA1', monto: 60, ref: '55550001', banco: 'Pichincha', huella: 'aaaa1111bbbb2222' }],
  cuentas: [{ id: 'VIEJA2', texto: CUENTA, monto: 60 }], enviada_en: iso(10 * DIA - 3600000)
}, extra || {});

console.log('=== 1) Operacion completa -> lo que se guarda en Supabase ===');
{
  const r = revisar([captura('60.00', '77770001', 'Pichincha', 'cccc3333dddd4444'), CUENTA], null, [], { ids: ['FOTO1', 'CTA1'] });
  chk(r.estadoOperacion === 'completo', 'captura + cuenta: COMPLETO', '-> ' + r.estadoOperacion);
  chk(r.registro && r.registro.capturas.length === 1 && r.registro.cuentas.length === 1, 'entrega el registro (capturas y cuentas)');

  // Lo que hay despues de publicar en el grupo: lo que armo "Separar Cuentas" y lo que respondio Evolution.
  function armar(ro, ap, separadas, idsGrupo, idFoto) {
    const payload = Object.assign({}, ap, { registro: ro.registro });
    const $ = n => {
      if (n === 'Cuando lo Llama el Bot' || _strip(n) === 'Cuando lo Llama el Bot') return { first: () => ({ json: payload }), item: { json: payload } };
      if (n === 'Separar Cuentas' || _strip(n) === 'Separar Cuentas') return { all: () => separadas.map(json => ({ json })) };
      if (n === 'Enviar Cuenta Grupo' || _strip(n) === 'Enviar Cuenta Grupo') return { all: () => idsGrupo.map(id => ({ json: { key: { id } } })) };
      if (n === 'Enviar Imagen Grupo' || _strip(n) === 'Enviar Imagen Grupo') return { first: () => ({ json: { key: { id: idFoto } } }) };
      throw new Error('nodo inesperado: ' + n);
    };
    return new Function('$', code('Armar Fila Supabase'))($).map(i => i.json);
  }
  const ap = { jid: '593990000001@s.whatsapp.net', numero: '593990000001', nombre: 'Ana WhatsApp', nombreMostrar: 'Ana Prueba', idImagen: 'FOTO1' };
  const filas = armar(r, ap, [{ cuenta: 'Ana Prueba - $60\n\n' + CUENTA, idCuenta: 'CTA1', monto: 60, texto: CUENTA }], ['GRUPO-CTA1'], 'GRUPO-FOTO');
  const COLUMNAS = ['whatsapp', 'nombre_cliente', 'estado', 'monto_deposito', 'ref_deposito', 'banco_origen', 'huella_foto',
                    'id_msg_captura', 'capturas', 'cuentas', 'id_msgs_grupo', 'fuera_de_horario', 'publicado_en', 'enviada_en', 'notas'];
  const f = filas[0];
  const sobran = Object.keys(f).filter(k => COLUMNAS.indexOf(k) === -1);
  chk(filas.length === 1, 'una cuenta: una fila', '-> ' + filas.length);
  chk(sobran.length === 0, 'solo trae columnas que existen en la tabla', '-> ' + sobran.join(','));
  chk(f.whatsapp === '593990000001' && f.nombre_cliente === 'Ana Prueba', 'whatsapp (solo digitos) y el nombre que cargo Kelvin', '-> ' + f.whatsapp + ' / ' + f.nombre_cliente);
  chk(f.estado === 'en_proceso' && f.fuera_de_horario === false && !isNaN(Date.parse(f.publicado_en)), 'en_proceso, publicada ahora, dentro de horario');
  chk(f.monto_deposito === 60 && f.ref_deposito === '77770001' && f.banco_origen === 'Pichincha', 'monto, referencia y banco de la captura');
  chk(f.huella_foto === 'cccc3333dddd4444' && f.id_msg_captura === 'FOTO1', 'huella e id de la captura');
  chk(f.cuentas.length === 1 && f.cuentas[0].monto === 60 && f.cuentas[0].id === 'CTA1' && f.cuentas[0].texto === CUENTA, 'la cuenta, sin la cabecera, con su monto');
  chk(f.id_msgs_grupo.join() === 'GRUPO-CTA1,GRUPO-FOTO', 'guarda su publicacion en el grupo (y la de la foto)', '-> ' + f.id_msgs_grupo);

  const CTA_A = ['Banco Uno', '01020000000000011111', 'Luisa Prueba', 'V 22222222', '$40'].join(SALTO);
  const CTA_B = ['Banco Dos', '01020000000000022222', 'Mario Prueba', 'V 33333333', '25,50$'].join(SALTO);
  const r2 = revisar([captura('40.00', '77770002'), captura('25.50', '77770003', 'Produbanco'), CTA_A, CTA_B], null, []);
  const f2 = armar(r2, Object.assign({}, ap, { idImagen: 'M0' }),
                   [{ cuenta: 'x', idCuenta: 'M2', monto: 40, texto: CTA_A }, { cuenta: 'y', idCuenta: 'M3', monto: 25.5, texto: CTA_B }],
                   ['GRUPO-A', 'GRUPO-B'], 'GRUPO-FOTO2');
  chk(f2.length === 2, 'dos cuentas: DOS filas (cada una con su estado)', '-> ' + f2.length);
  chk(f2[0].cuentas[0].monto === 40 && f2[1].cuentas[0].monto === 25.5, 'cada fila con el monto de su cuenta', '-> ' + f2.map(x => x.cuentas[0].monto));
  chk(f2[0].id_msgs_grupo.join() === 'GRUPO-A,GRUPO-FOTO2' && f2[1].id_msgs_grupo.join() === 'GRUPO-B', 'cada una con SU publicacion; la foto va con la primera');
  chk(f2.every(x => x.id_msg_captura === 'M0' && x.monto_deposito === 65.5), 'comparten el deposito (id de la captura y monto total)', '-> ' + f2.map(x => x.monto_deposito));
  chk(f2[0].notas === 'Cuenta 1 de 2 del mismo deposito' && f2[1].notas === 'Cuenta 2 de 2 del mismo deposito', 'notas: cuenta 1 de 2 y 2 de 2');
  chk(f2[0].banco_origen === 'Pichincha, Produbanco', 'los dos bancos de origen', '-> ' + f2[0].banco_origen);
}

console.log('');
console.log('=== 2) Capturas repetidas de hace mas de 48 h (contra la tabla) ===');
{
  const h = [fila()];
  const misma = revisar([captura('60.00', '55550001')], null, h);
  chk(misma.estadoOperacion === 'repetido', 'misma referencia y monto que una de hace 10 dias: REPETIDO', '-> ' + misma.estadoOperacion);
  const foto = revisar([captura('60.00', '', 'Pichincha', 'aaaa1111bbbb2222')], null, h);
  chk(foto.estadoOperacion === 'repetido', 'la misma foto (huella) de hace 10 dias: REPETIDO', '-> ' + foto.estadoOperacion);
  const otra = revisar([captura('60.00', '', 'Pichincha')], null, h);
  chk(otra.estadoOperacion === 'falta_cuenta', 'mismo monto y banco SIN referencia, 10 dias despues: es otro deposito', '-> ' + otra.estadoOperacion);
  const otraRef = revisar([captura('60.00', '55550099')], null, h);
  chk(otraRef.estadoOperacion === 'falta_cuenta', 'mismo monto, otra referencia: es otro deposito', '-> ' + otraRef.estadoOperacion);
  const corta = revisar([captura('60.00', '1234')], null, [fila({ capturas: [{ id: 'V', monto: 60, ref: '1234' }] })]);
  chk(corta.estadoOperacion === 'falta_cuenta', 'referencia muy corta (4 digitos) de hace dias: no basta', '-> ' + corta.estadoOperacion);
  const cancelada = revisar([captura('60.00', '55550001')], null, [fila({ estado: 'cancelada' })]);
  chk(cancelada.estadoOperacion === 'falta_cuenta', 'si esa operacion se cancelo, no cuenta como repetida', '-> ' + cancelada.estadoOperacion);
  const caida = revisar([captura('60.00', '55550001')], null, 'CAIDA');
  chk(caida.estadoOperacion === 'falta_cuenta', 'si Supabase no responde, sigue como antes', '-> ' + caida.estadoOperacion);
}

console.log('');
console.log('=== 3) "La misma cuenta de siempre" ===');
{
  const h = [fila()];
  const r1 = revisar([captura('80.00', '66660001')], null, h);
  chk(r1.estadoOperacion === 'falta_cuenta', 'llega la captura sola: falta la cuenta');
  pasan(1);
  const r2 = revisar(['a la misma de siempre'], r1.op, h);
  chk(r2.estadoOperacion === 'confirmar_cuenta', '"a la misma de siempre": le muestra la ultima cuenta', '-> ' + r2.estadoOperacion);
  chk(r2.notaIA.indexOf('01020000000000099999') !== -1 && r2.notaIA.indexOf('Pedro Prueba') !== -1, 'la nota trae la cuenta de la vez pasada');
  chk(r2.notaIA.indexOf('$60') === -1, 'SIN el monto viejo (el de hoy puede ser otro)');
  chk(/s[ií]/.test(r2.notaIA) && /confirmar/i.test(r2.notaIA), 'y le pide un "si" para confirmar');
  chk(r2.op.capturas.length === 1 && r2.op.cuentaPropuesta, 'la captura sigue guardada y la cuenta queda propuesta');
  chk(r2.textoAprobar === '', 'todavia NO se pasa nada al grupo');
  pasan(1);
  const r3 = revisar(['Si'], r2.op, h);
  chk(r3.estadoOperacion === 'completo', 'responde "Si": COMPLETO', '-> ' + r3.estadoOperacion);
  chk(r3.textoAprobar.indexOf('01020000000000099999') !== -1 && r3.textoAprobar.indexOf('$60') === -1, 'al grupo va esa cuenta, sin el monto viejo');
  chk(r3.op.cuentaPropuesta === undefined || r3.op.cuentaPropuesta === null, 'y la propuesta se borra');

  const r4 = revisar(['no, a otra'], r2.op, h);
  chk(r4.estadoOperacion === 'falta_cuenta' && !r4.op.cuentaPropuesta, 'si dice que no: vuelve a pedir la cuenta', '-> ' + r4.estadoOperacion);
  const r5 = revisar([['Banco Nuevo', '01020000000000077777', 'Rosa Prueba', 'V 44444444'].join(SALTO)], r2.op, h);
  chk(r5.estadoOperacion === 'completo' && r5.textoAprobar.indexOf('77777') !== -1 && r5.textoAprobar.indexOf('99999') === -1,
      'si en vez de "si" manda otra cuenta: usa la nueva', '-> ' + r5.estadoOperacion);

  const r6 = revisar([captura('80.00', '66660002'), 'a la misma cuenta de siempre porfa'], null, h);
  chk(r6.estadoOperacion === 'confirmar_cuenta', 'captura y "misma cuenta de siempre" juntas: tambien', '-> ' + r6.estadoOperacion);
  for (const t of ['Ok', 'sí, esa misma', 'correcto', 'Dale, esa']) {
    const r = revisar([t], r6.op, h);
    chk(r.estadoOperacion === 'completo', JSON.stringify(t) + ' confirma', '-> ' + r.estadoOperacion);
  }

  const sinCaptura = revisar(['me pasas la misma cuenta de siempre?'], null, h);
  chk(sinCaptura.estadoOperacion === 'nada' && !sinCaptura.op.cuentaPropuesta, 'sin captura (pregunta por NUESTRA cuenta): no propone nada', '-> ' + sinCaptura.estadoOperacion);
  const tasa = revisar(['la misma tasa de antes'], r1.op, h);
  chk(tasa.estadoOperacion !== 'confirmar_cuenta', '"la misma tasa de antes" no es la cuenta', '-> ' + tasa.estadoOperacion);
  const varias = revisar(['la misma de siempre'], r1.op, [fila({ cuentas: [{ texto: CUENTA }, { texto: CUENTA.replace('99999', '88888') }] })]);
  chk(varias.estadoOperacion === 'falta_cuenta' && /p[aá]same los datos/i.test(varias.notaIA), 'la vez pasada fueron varias cuentas: le pide los datos', '-> ' + varias.estadoOperacion);
  const dosFilas = revisar(['la misma de siempre'], r1.op, [fila({ id: 7 }), fila({ id: 8, cuentas: [{ texto: CUENTA.replace('99999', '88888') }] })]);
  chk(dosFilas.estadoOperacion === 'falta_cuenta' && /p[aá]same los datos/i.test(dosFilas.notaIA), 'la vez pasada fueron 2 filas (2 cuentas): le pide los datos', '-> ' + dosFilas.estadoOperacion);
  const nada = revisar(['la misma de siempre'], r1.op, []);
  chk(nada.estadoOperacion === 'falta_cuenta' && /p[aá]same los datos/i.test(nada.notaIA), 'sin historial: le pide los datos', '-> ' + nada.estadoOperacion);
}

console.log('');
console.log('=== 4) "¿Ya llego?": el estado de la ultima operacion para el agente ===');
{
  reloj = Date.parse('2026-11-21T20:00:00Z');   // 3:00 pm en Ecuador
  const enProceso = revisar(['ya llego?'], null, [fila({ estado: 'en_proceso', creado: iso(40 * 60000), enviada_en: null })]);
  chk(/EN PROCESO/.test(enProceso.contextoOperaciones) && /hoy a las 2:20 pm/.test(enProceso.contextoOperaciones),
      'en proceso: lo dice, con la hora de Ecuador', '-> ' + enProceso.contextoOperaciones);
  const enviada = revisar(['ya llego?'], null, [fila({ creado: iso(DIA + 3600000), enviada_en: iso(DIA) })]);
  chk(/ENVIADA ayer a las 3:00 pm/.test(enviada.contextoOperaciones), 'enviada: cuando salio', '-> ' + enviada.contextoOperaciones);
  const espera = revisar(['ya llego?'], null, [fila({ estado: 'en_espera', creado: iso(14 * 3600000), enviada_en: null })]);
  chk(/EN ESPERA/.test(espera.contextoOperaciones), 'en espera (de noche): lo dice', '-> ' + espera.contextoOperaciones);
  const vieja = revisar(['ya llego?'], null, [fila({ creado: iso(9 * DIA), enviada_en: iso(9 * DIA) })]);
  chk(vieja.contextoOperaciones === '', 'una operacion de hace mas de 7 dias no cuenta', '-> ' + JSON.stringify(vieja.contextoOperaciones));
  chk(revisar(['hola'], null, []).contextoOperaciones === '', 'sin operaciones: nada');
  chk(revisar(['hola'], null, 'CAIDA').contextoOperaciones === '', 'Supabase caido: nada (y no se rompe)');
  const dos = revisar(['ya llego?'], null, [fila({ id: 1, creado: iso(3 * DIA), enviada_en: iso(3 * DIA) }),
                                            fila({ id: 2, id_msg_captura: 'NUEVA', estado: 'en_proceso', creado: iso(30 * 60000), enviada_en: null })]);
  chk(/EN PROCESO/.test(dos.contextoOperaciones) && /1 cuenta destino/.test(dos.contextoOperaciones), 'con varias operaciones, usa la MAS RECIENTE', '-> ' + dos.contextoOperaciones);
  const partes = [fila({ id: 3, id_msg_captura: 'OP2', creado: iso(50 * 60000), enviada_en: iso(10 * 60000) }),
                  fila({ id: 4, id_msg_captura: 'OP2', estado: 'en_proceso', creado: iso(50 * 60000), enviada_en: null })];
  const media = revisar(['ya llego?'], null, partes);
  chk(/2 cuentas destino/.test(media.contextoOperaciones) && /ya salio 1 de 2/.test(media.contextoOperaciones) && /la otra cuenta/.test(media.contextoOperaciones),
      'dos cuentas, solo una enviada: "ya salio 1 de 2"', '-> ' + media.contextoOperaciones);
  partes[1].estado = 'enviada'; partes[1].enviada_en = iso(5 * 60000);
  const todas = revisar(['ya llego?'], null, partes);
  chk(/ENVIADA hoy a las 2:55 pm \(las 2 cuentas\)/.test(todas.contextoOperaciones), 'las dos enviadas: ENVIADA, con la hora de la ultima', '-> ' + todas.contextoOperaciones);
}

console.log('');
console.log('=== 5) Cuando la operadora devuelve la foto: la fila pasa a "enviada" ===');
{
  for (const n of ['Marcar Publicacion Imagen', 'Marcar Publicacion Cuenta']) {
    chk(/idCaptura:\s*\$\('Cuando lo Llama el Bot'\)\.first\(\)\.json\.idImagen/.test(nodo(n).parameters.value), n + ' guarda el id de la captura');
  }
  const base = { stanzaId: 'GRUPO1', claveEntregado: 'entregado:GRUPO1', jidGrupo: 'grupo@g.us', idFoto: 'FOTOOP' };
  const $ = n => {
    if (n === 'Cuando lo Llama el Bot' || _strip(n) === 'Cuando lo Llama el Bot') return { first: () => ({ json: base }) };
    if (n === 'Redis Leer Publicacion' || _strip(n) === 'Redis Leer Publicacion') return { first: () => ({ json: { pedido: JSON.stringify({ jid: '593990000001@s.whatsapp.net', nombre: 'Ana', idCuenta: 'CTA1', idCaptura: 'FOTO1' }) } }) };
    if (n === 'Redis Leer Entregado' || _strip(n) === 'Redis Leer Entregado') return { first: () => ({ json: {} }) };
    return { first: () => ({ json: {} }) };
  };
  const rp = new Function('$', code('Revisar Pedido'))($)[0].json;
  chk(rp.idCaptura === 'FOTO1', 'Revisar Pedido pasa el id de la captura', '-> ' + rp.idCaptura);
  const up = nodo('Marcar Enviada en Supabase').parameters;
  chk(up.operation === 'update' && up.tableId === 'transacciones_detal_por_whatsapp', 'actualiza la tabla transacciones_detal_por_whatsapp');
  chk(/id_msgs_grupo=cs\./.test(up.filterString) && /Revisar Pedido[^}]*stanzaId/.test(up.filterString), 'busca la fila de ESA cuenta: la publicacion que cito la operadora');
  const expr = String(up.filterString).replace(/^=\{\{/, '').replace(/\}\}$/, '');
  const filtro = new Function('$', 'return (' + expr + ');')(n => ({ first: () => ({ json: { stanzaId: 'GRUPO-B' } }) }));
  chk(filtro === 'id_msgs_grupo=cs.["GRUPO-B"]&estado=in.(en_proceso,en_espera)', 'el filtro queda bien armado', '-> ' + filtro);
  chk(/estado=in\.\(en_proceso,en_espera\)/.test(up.filterString), 'solo si estaba en proceso (no toca canceladas)');
  const campos = (up.fieldsUi.fieldValues || []).map(f => f.fieldId + '=' + f.fieldValue).join(' ; ');
  chk(/estado=enviada/.test(campos) && /enviada_en=/.test(campos), 'estado enviada y la hora', '-> ' + campos);
}

console.log('');
console.log('=== 6) Como quedo conectado ===');
{
  const sale = (n, i) => ((((_getConn(wfIa.connections, n) || {}).main || [])[i || 0]) || []).map(c => _strip(c.node));
  const salePub = (n, i) => ((((wfPub.connections[n] || {}).main || [])[i || 0]) || []).map(c => _strip(c.node));
  chk(sale('Redis Leer Pregunta').join() === 'Consultar Operaciones WhatsApp', 'Redis Leer Pregunta -> Consultar Operaciones WhatsApp', '-> ' + sale('Redis Leer Pregunta'));
  chk(sale('Consultar Operaciones WhatsApp').join() === 'Revisar Operacion', 'Consultar Operaciones WhatsApp -> Revisar Operacion');
  chk(sale('Detectar Aprobación').join() === 'Ejecutar Publicacion', 'Detectar Aprobación -> Ejecutar Publicacion');
  chk(salePub('Marcar Publicacion Cuenta').indexOf('Armar Fila Supabase') !== -1, 'Marcar Publicacion Cuenta -> Armar Fila Supabase (despues de publicar)');
  chk(salePub('Armar Fila Supabase').join() === 'Guardar Operacion en Supabase', 'Armar Fila Supabase -> Guardar Operacion en Supabase');
  chk(sale('Redis Guardar Operacion').indexOf('Armar Filas Noche') !== -1 && sale('Armar Filas Noche').join() === 'Empaquetar Noche'
      && sale('Empaquetar Noche').join() === 'Ejecutar Publicacion',
      'de noche: Redis Guardar Operacion -> Armar Filas Noche -> Empaquetar Noche -> Ejecutar Publicacion');
  chk(salePub('Router Publicacion', 2).join() === 'Desempacar Filas Noche' && salePub('Desempacar Filas Noche').join() === 'Guardar Operacion en Supabase',
      'sub-workflow noche: Router Publicacion (2) -> Desempacar Filas Noche -> Guardar Operacion en Supabase');
  const saleOp = (n, i) => ((((wfOp.connections[n] || {}).main || [])[i || 0]) || []).map(c => _strip(c.node));
  chk(saleOp('Redis Marcar Entregado').join() === 'Marcar Enviada en Supabase', 'Redis Marcar Entregado -> Marcar Enviada en Supabase');

  const leer = nodo('Consultar Operaciones WhatsApp');
  chk(leer.parameters.tableId === 'transacciones_detal_por_whatsapp' && leer.parameters.operation === 'getAll', 'lee la tabla nueva');
  chk(/whatsapp=eq\./.test(leer.parameters.filterString) && /order=creado\.desc/.test(leer.parameters.filterString), 'del cliente, las mas recientes primero');
  const guardar = nodo('Guardar Operacion en Supabase');
  chk(guardar.parameters.operation === 'create' && guardar.parameters.dataToSend === 'autoMapInputData', 'guarda la fila tal cual la arma el nodo anterior');
  for (const n of ['Consultar Operaciones WhatsApp', 'Guardar Operacion en Supabase', 'Marcar Enviada en Supabase']) {
    const x = nodo(n);
    chk(x.credentials && x.credentials.supabaseApi && x.credentials.supabaseApi.name === 'Supabase Cambios JK', n + ': credencial de servicio (sin claves en el codigo)');
    chk(x.onError === 'continueRegularOutput', n + ': si Supabase falla, el bot sigue');
  }
}

console.log('');
console.log('=== 6b) Los nodos IF viejos (v1) usan operaciones que existen ===');
{
  // El 20/11 "Ya Se Entrego?" tenia operation 'equals' (no existe: es 'equal') y n8n se caia justo
  // antes de mandarle al cliente la foto de la operadora.
  const VALIDAS = { boolean: ['equal', 'notEqual'], number: ['smaller', 'smallerEqual', 'equal', 'notEqual', 'larger', 'largerEqual', 'isEmpty', 'isNotEmpty'],
                    string: ['contains', 'notContains', 'endsWith', 'notEndsWith', 'equal', 'notEqual', 'regex', 'notRegex', 'startsWith', 'notStartsWith', 'isEmpty', 'isNotEmpty'] };
  for (const n of [...wf.nodes, ...wfOp.nodes, ...wfPub.nodes, ...wfIa.nodes].filter(x => x.type === 'n8n-nodes-base.if' && x.typeVersion === 1)) {
    const malas = [];
    for (const tipo of Object.keys(n.parameters.conditions || {})) {
      for (const c of (n.parameters.conditions[tipo] || [])) if (c.operation && (VALIDAS[tipo] || []).indexOf(c.operation) === -1) malas.push(tipo + ':' + c.operation);
    }
    chk(malas.length === 0, n.name + ': operaciones validas', malas.join(','));
  }
  const ya = nodo('Ya Se Entrego?').parameters.conditions.boolean[0];
  const v = s => new Function('$json', 'return (' + String(s).replace(/^=\{\{/, '').replace(/\}\}$/, '') + ');');
  chk(v(ya.value1)({ accion: 'repetido' }) === true && v(ya.value1)({ accion: 'entregar' }) === false && v(ya.value2)({}) === true,
      '"Ya Se Entrego?": repetido -> aviso, entregar -> manda la foto');
}

console.log('');
console.log('=== 7) El prompt ===');
{
  const sm = nodo('AI Agent').parameters.options.systemMessage;
  chk(/Revisar Operacion[^}]*contextoOperaciones/.test(sm), 'trae el estado de la ultima operacion');
  chk(/YA LLEGO/.test(sm), 'regla para "¿ya llego?"');
  chk(/nunca ofrezcas cuentas guardadas/i.test(sm), 'no ofrece listas de beneficiarios');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
