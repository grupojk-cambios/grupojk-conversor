
const _strip = s => s ? String(s).replace(/^\d+[\w\.]*\s*/, '') : '';
const _findNode = (nodes, n) => (nodes || []).find(x => x.name === n || _strip(x.name) === _strip(n));
const _getConn = (conns, n) => {
  if (!conns) return null;
  const k = Object.keys(conns).find(x => x === n || _strip(x) === _strip(n));
  return k ? Reflect.get(conns, k) : null;
};
// Prueba de la FASE 2 del mayor: el bot publica los RST/RCT en los grupos de los bancos
// (reglas de "EJEMPLOS PARA EL BOT/protocolo_rst_rct.md" y de Kelvin, 24/11).
//
// Lo que se vigila:
//   - los ejemplos del manual (7 bancos + RCT + Guayaquil sin etiquetas) se entienden y se validan por banco;
//   - MODO ENSAYO: nada sale a bancos ni a clientes, todo va junto al grupo de avisos (con codigos tapados);
//   - modo real: bloque al grupo del banco (en horario) o a COBRAR MAÑANA (de noche), con "cobrar hoy" para los
//     bancos que se vencen el mismo dia (todos menos Guayaquil y Produbanco), sticker y mensajes al cliente;
//   - el banco responde "Verificar" o "se dañó" a UNA publicacion nuestra -> se le avisa al cliente;
//   - lista blanca: solo se escribe a avisos, a los grupos de la tabla y al grupo del propio cliente.
//
// Todos los datos son INVENTADOS (el repositorio es publico). Correr con:  node test_mayor_publicar.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_mayor.json', 'utf8').replace(/^﻿/, ''));
const bot = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const nodo = (w, n) => _findNode(w.nodes, n);
const code = n => nodo(wf, n).parameters.jsCode;
const SALTO = String.fromCharCode(10);

let fallos = 0;
const chk = (ok, etiqueta, detalle) => { if (!ok) fallos++; console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(76) + ' ' + (detalle || '')); };

const AVISOS = '120363413942097019@g.us';
const GRUPO = { grupo_jid: '120363000000000001@g.us', nombre: 'Cliente Prueba PEDIDOS JK', tipo: 'cliente', cliente_whatsapp: '593990000001',
                operador_extra_whatsapp: '593990000002', operadora_whatsapp: '593990000003', publicar: true };
const DESTINOS = ['PICHINCHA', 'GUAYAQUIL', 'PRODUBANCO', 'PACIFICO', 'COOP JEP', 'BOLIVARIANO', 'SOLIDARIO', 'AUSTRO', 'INTERNACIONAL', 'COBRAR MAÑANA']
  .map((nombre, i) => ({ grupo_jid: '1203630000000001' + String(10 + i) + '@g.us', nombre, tipo: 'destino', activo: true }));
const ID = nombre => DESTINOS.find(d => d.nombre === nombre).grupo_jid;
const DEST_DE = jid => (DESTINOS.find(d => d.grupo_jid === jid) || {}).nombre;
const BANCO_GRUPO = { tipo: 'destino', nombre: 'PICHINCHA', grupo_jid: ID('PICHINCHA'), operadora_whatsapp: '593990000003' };

const ABIERTO = '2026-11-24T15:00:00Z';      // martes 10:00 am en Ecuador
const CERRADO = '2026-11-25T03:00:00Z';      // martes 10:00 pm en Ecuador
const DOMINGO_TARDE = '2026-11-29T20:00:00Z'; // domingo 3:00 pm en Ecuador (cerrado)

const CAJERO = { estado: 'en_cajero', id_msg_cliente: 'MSGCLIENTE0', fila_id: 70, cliente_nombre: 'Cliente Prueba' };      // el cobrador de JEP ya avisó que está en el cajero
let n = 0;
function evento(texto, extra) {
  extra = extra || {}; n++;
  const key = { remoteJid: extra.jid || GRUPO.grupo_jid, fromMe: !!extra.fromMe, id: extra.id || ('MSG' + n), participant: '123@lid',
                participantAlt: (extra.numero === undefined ? '593990000001' : extra.numero) + '@s.whatsapp.net' };
  const message = extra.mensaje || (extra.imagen ? { imageMessage: { caption: texto || '' } } : { conversation: texto });
  return { key, pushName: 'Alguien', message, contextInfo: extra.cita ? { stanzaId: extra.cita } : undefined, messageTimestamp: 1795000000 + n };
}
const entender = (texto, extra, grupo) => {
  const out = new Function('$input', code('Entender Mensaje'))({ first: () => ({ json: { grupo: grupo || GRUPO, data: evento(texto, extra) } }) });
  return out.length ? out[0].json : null;
};
const reg0 = fila => (((fila || {}).datos || {}).registros || [])[0];

// Corre la rama de la Fase 2 completa: Entender -> Hace Falta Publicar? -> Decidir Publicacion.
function correr(texto, opciones) {
  const o = opciones || {};
  const grupo = o.grupo || GRUPO;
  const fila = entender(texto, o.extra, grupo);
  if (!fila) return { fila: null, pasa: false, envios: [] };
  const real = Date.now; Date.now = () => new Date(o.hora || ABIERTO).getTime();
  try {
    const $ = nombre => {
      if (nombre === 'Decidir') return { first: () => ({ json: fila }) };
      if (nombre === 'Cuando lo Llama el Bot') return { first: () => ({ json: { grupo, data: {} } }) };
      if (nombre === 'Guardar en Supabase') return { first: () => ({ json: o.sinGuardar ? { error: 'duplicate key' } : { id: 77 } }) };
      if (nombre === 'Redis Leer Publicacion') return { first: () => ({ json: { pub: (o.pub || o.jep) ? JSON.stringify(o.pub || o.jep) : null } }) };
      if (nombre === 'Redis Leer Temporal') return { first: () => ({ json: { temporal: o.temporal ? JSON.stringify(o.temporal) : null } }) };
      if (nombre === 'Grupos Destino') return { all: () => (o.destinos || DESTINOS).map(json => ({ json })) };
      if (nombre === 'Retiros Recientes') return { all: () => (o.recientes || []).map(json => ({ json })) };
      if (nombre === 'Redis Leer Sin Banco') return { first: () => ({ json: { sinBanco: o.sinBanco ? JSON.stringify(o.sinBanco) : null } }) };
      throw new Error('nodo inesperado: ' + nombre);
    };
    const pasa = new Function('$', code('Hace Falta Publicar?'))($).length > 0;
    let codigo = code('Decidir Publicacion');
    if (o.modo) codigo = codigo.replace("const MODO = 'ensayo'", "const MODO = '" + o.modo + "'");
    const envios = pasa ? new Function('$', codigo)($).map(i => i.json) : [];
    return { fila, pasa, envios };
  } finally { Date.now = real; }
}
const REAL = { modo: 'real' };
const real = (texto, extra) => correr(texto, Object.assign({ modo: 'real' }, extra || {}));
const bancos = r => r.envios.filter(e => e.etapa === 'banco');
const sticker = r => r.envios.filter(e => e.tipo === 'sticker');
const clienteTxt = r => r.envios.filter(e => e.etapa === 'cliente' && e.tipo === 'texto');

console.log('=== 1) LOS EJEMPLOS DEL MANUAL (numeros inventados) ===');
{
  const casos = [
    ['Produbanco', ['Banco: PRODUBANCO', 'C.I: 1700000001', 'Código: 175588', 'Monto: 130$'], { banco: 'Produbanco', usd: 130, cod: ['175588'], ced: '1700000001' }],
    ['Pacífico', ['PACÍFICO', 'Monto: 100$', 'Código: 474927', 'Cedula: 0900000002', 'Teléfono: 0990000003'], { banco: 'Pacífico', usd: 100, cod: ['474927'], ced: '0900000002', tel: '0990000003' }],
    ['Pichincha', ['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'], { banco: 'Pichincha', usd: 200, cod: ['5478'], tel: '0990000004' }],
    ['Guayaquil', ['Banco: Guayaquil', 'C1: 2403', 'C2: 2790', 'Teléfono: +593 99 000 0005', 'Monto: 500'], { banco: 'Guayaquil', usd: 500, cod: ['2403', '2790'], tel: '593990000005' }],
    ['JEP', ['BANCO: Jep', 'Monto: $300', 'OTP: 796988', 'CI: 2100000006', 'Clave: 1111'], { banco: 'JEP', usd: 300, cod: ['796988'], ced: '2100000006', clave: '1111' }],
    ['Solidario', ['Banco: solidario', 'Monto: 100', 'Tlf: 0990000007', 'Cedula: 1700000008', 'Codigo: 874454'], { banco: 'Solidario', usd: 100, cod: ['874454'], ced: '1700000008', tel: '0990000007' }],
    ['Bolivariano', ['Banco Bolivariano', 'QuickPay', 'Monto: 380', 'Código: 068521', 'Celular: 0990000009', 'Cédula: 0900000010'], { banco: 'Bolivariano', usd: 380, cod: ['068521'], ced: '0900000010', tel: '0990000009' }],
    ['Guayaquil SIN etiquetas', ['Guayaquil', '0990000031', '2345', '6543', '500'], { banco: 'Guayaquil', usd: 500, cod: ['2345', '6543'], tel: '0990000031' }]
  ];
  for (const [etiqueta, lineas, esp] of casos) {
    const fila = entender(lineas.join(SALTO));
    const r = reg0(fila), d = r ? r.datos : {};
    const ok = r && r.tipo === 'rst' && r.banco === esp.banco && r.monto_usd === esp.usd && JSON.stringify(d.codigos) === JSON.stringify(esp.cod)
      && (!esp.ced || d.cedula === esp.ced) && (!esp.tel || d.telefono === esp.tel) && (!esp.clave || d.clave === esp.clave);
    chk(ok, etiqueta, ok ? '' : '-> ' + JSON.stringify(r && { tipo: r.tipo, banco: r.banco, usd: r.monto_usd, d }));
    const p = real(lineas.join(SALTO), etiqueta === 'JEP' ? { jep: CAJERO } : {});
    chk(p.pasa && bancos(p).length === 1 && p.envios.every(e => e.etapa !== 'cliente' || e.tipo === 'sticker'), '   ...y es un RST COMPLETO: se publica (no se le pide nada al cliente)', '-> ' + JSON.stringify(p.envios.map(e => e.etapa + ':' + (e.tipo === 'sticker' ? 'sticker' : String(e.texto).slice(0, 60)))));
  }
  const rct1 = reg0(entender(['Austro', '*Retira con tarjeta*', 'Monto 500$'].join(SALTO)));
  chk(rct1 && rct1.tipo === 'rct' && rct1.banco === 'Austro' && rct1.monto_usd === 500, 'RCT Austro (banco + monto)', '-> ' + JSON.stringify(rct1 && [rct1.tipo, rct1.banco, rct1.monto_usd]));
  const rct2 = reg0(entender(['⚠️⚠️ *PICHINCHA* ⚠️⚠️', '       👩🏻🦱Miser👩🏻🦱', '', '*Retira con tarjeta*', 'Monto 500$'].join(SALTO)));
  chk(rct2 && rct2.tipo === 'rct' && rct2.banco === 'Pichincha' && rct2.monto_usd === 500, 'RCT Pichincha con operadora asignada y emojis', '-> ' + JSON.stringify(rct2 && [rct2.tipo, rct2.banco, rct2.monto_usd]));
}

console.log('');
console.log('=== 2) QUE LE FALTA A CADA RST (se le pide al cliente) ===');
{
  const f = (lineas, extra) => { const p = real(lineas.join(SALTO), extra || {}); return { p, txt: (clienteTxt(p)[0] || {}).texto || '' }; };
  let x = f(['Pichincha', 'Código: 5478', 'Monto: $200']);
  chk(bancos(x.p).length === 0 && /Faltan estos datos para tu RST de Pichincha: el teléfono\./.test(x.txt), 'Pichincha sin teléfono: pide el teléfono y NO publica', '-> ' + x.txt);
  chk(/Envíalos de nuevo en un solo texto, por favor\.$/.test(x.txt) && clienteTxt(x.p)[0].citar === x.p.fila.mensaje_id, 'y le habla citando SU mensaje', '-> cita ' + (clienteTxt(x.p)[0] || {}).citar);
  x = f(['Guayaquil', 'C1: 2403', 'Teléfono: 0990000005', 'Monto: 500']);
  chk(/el código 2/.test(x.txt) && bancos(x.p).length === 0, 'Guayaquil con un solo codigo: pide el codigo 2', '-> ' + x.txt);
  x = f(['BANCO: Jep', 'Monto: $300', 'OTP: 796988', 'CI: 2100000006'], { jep: CAJERO });
  chk(/la clave de la tarjeta/.test(x.txt), 'JEP (con el cobrador en el cajero) sin la clave de la tarjeta: la pide', '-> ' + x.txt);
  x = f(['Pacífico', 'Monto: 100$', 'Código: 474927']);
  chk(/la cédula y el teléfono/.test(x.txt), 'Pacífico sin cedula ni telefono: pide los dos juntos', '-> ' + x.txt);
  x = f(['Produbanco', 'C.I: 1700000001', 'Código: 175588']);
  chk(/el monto/.test(x.txt), 'sin monto: pide el monto', '-> ' + x.txt);
  x = f(['Pichincha Tlf 0990000004 clave 5478 Monto 200$', 'Pichincha clave 6666 Monto 50$']);
  chk(bancos(x.p).length === 1 && /Faltan estos datos para tu RST de Pichincha: el teléfono/.test(x.txt) && sticker(x.p).length === 1, 'DOS RST en un mensaje (uno completo, uno no): publica el bueno y pide lo que falta del otro', '-> ' + bancos(x.p).length + ' publicado(s)');
  x = f(['Pichincha', 'Código: 5478', 'Código: 9999', 'Teléfono: 0990000004', 'Monto: $200']);
  chk(/cuál es el código/.test(x.txt) && bancos(x.p).length === 0, 'dos codigos en un banco que usa uno: NO adivina, pregunta cual es', '-> ' + x.txt);
  const rct = f(['Austro', '*Retira con tarjeta*']);
  chk(/retiro con tarjeta de Austro: el monto/.test(rct.txt), 'RCT sin monto: pide el monto', '-> ' + rct.txt);
  // Charla que NO es un pedido (casos reales de los grupos, sin datos personales): no se le pide nada a nadie
  for (const charla of ['rey que tanto demora en retirar los rst de guayaquil ?', 'El Pichincha está fallando la opción de RST intento nuevamente en un ratico.',
                        'ya se puede retirar con tarjeta en Pichincha?', 'Buenas, el rst de Pichincha sigue sin salir, ¿qué pasó?']) {
    const x = real(charla);
    chk(x.envios.length === 0, 'charla: "' + charla.slice(0, 58) + '" -> no se contesta', '-> ' + JSON.stringify(x.envios.map(e => String(e.texto).slice(0, 50))));
  }
  const plantilla = f(['Banco: Pichincha.', 'Tlf: 0990000004', 'Monto: 100 $.', 'Código:']);
  chk(/el código\./.test(plantilla.txt), 'la plantilla con un campo vacio ("Código:") si es un pedido: pide el codigo', '-> ' + plantilla.txt);
  const conPregunta = real(['Pichincha Tlf 0990000004 clave 5478 Monto 200$', 'ya salio?'].join(SALTO));
  chk(bancos(conPregunta).length === 1, 'un RST completo con "ya salio?" al final se publica igual', '-> ' + bancos(conPregunta).length);
}

console.log('');
console.log('=== 3) MODO ENSAYO (el que esta puesto): NADA sale a bancos ni a clientes ===');
{
  chk(/const MODO = 'ensayo'/.test(code('Decidir Publicacion')), 'el workflow esta en modo ENSAYO', '-> ' + (code('Decidir Publicacion').match(/const MODO = '(\w+)'/) || [])[1]);
  const p = correr(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO));
  chk(p.envios.length === 1 && p.envios[0].jid === AVISOS, 'una sola vista previa, y va al grupo de AVISOS', '-> ' + p.envios.map(e => e.jid));
  const t = p.envios[0].texto;
  chk(/^🧪 ENSAYO — Cliente Prueba \(Cliente Prueba PEDIDOS JK\)/.test(t) && /iría a PICHINCHA:/.test(t), 'dice que es un ENSAYO y adonde iria', '-> ' + JSON.stringify(t.split(SALTO).slice(0, 3)));
  chk(/Código: ••5478|Código: ••••78|Código: ••78/.test(t) && !/5478/.test(t) && !/0990000004/.test(t), 'los codigos y telefonos salen TAPADOS (solo los 2 ultimos digitos)', '-> ' + (t.match(/Código: [^\n]*/) || [])[0]);
  chk(/sticker "RST Recibido"/.test(t), 'anota el sticker que le mandaria al cliente');
  chk(p.envios[0].estado_fila === 'ensayo', 'la fila queda en estado "ensayo"');
  chk(!p.envios.some(e => e.jid === GRUPO.grupo_jid || DEST_DE(e.jid)), 'no se escribe ni al grupo del cliente ni a ningun banco');
  const inc = correr(['Pichincha', 'Código: 5478', 'Monto: $200'].join(SALTO));
  chk(inc.envios.length === 1 && inc.envios[0].jid === AVISOS && /Faltan estos datos/.test(inc.envios[0].texto), 'un RST incompleto tambien se queda en el ensayo (se ve que le diria al cliente)');
  const sinMonto = correr(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO), { destinos: [] });
  chk(sinMonto.envios.length === 1 && /grupo todavía no cargado/.test(sinMonto.envios[0].texto), 'si el grupo todavia no esta en la tabla, la vista previa lo dice', '-> ' + (sinMonto.envios[0] || {}).texto.split(SALTO)[2]);
  const modoRealSinPermiso = correr(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO), { modo: 'real', grupo: Object.assign({}, GRUPO, { publicar: false }) });
  chk(modoRealSinPermiso.envios.length === 1 && modoRealSinPermiso.envios[0].jid === AVISOS && /ENSAYO/.test(modoRealSinPermiso.envios[0].texto), 'en modo real, un grupo con publicar=false SIGUE en ensayo');
  const sinCampo = correr(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO), { modo: 'real', grupo: (() => { const g = Object.assign({}, GRUPO); delete g.publicar; return g; })() });
  chk(sinCampo.envios.length === 1 && sinCampo.envios[0].jid === AVISOS, 'y si la columna publicar ni existe: ensayo (nunca real por descuido)');
}

console.log('');
console.log('=== 4) MODO REAL, EN HORARIO: directo al grupo del banco ===');
{
  const lin = ['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'];
  const p = real(lin.join(SALTO));
  chk(p.envios.length === 2 && p.envios[0].tipo === 'sticker' && p.envios[0].jid === GRUPO.grupo_jid && /sticker-rst-recibido\.webp$/.test(p.envios[0].sticker), 'primero el sticker "RST Recibido" al grupo del cliente', '-> ' + p.envios.map(e => e.tipo));
  const b = bancos(p)[0];
  chk(DEST_DE(b.jid) === 'PICHINCHA', 'luego el bloque al grupo PICHINCHA', '-> ' + DEST_DE(b.jid));
  chk(b.texto === ['(Cliente Prueba', 'PICHINCHA', 'Monto: 200$', 'Código: 5478', 'Teléfono: 0990000004)'].join(SALTO), 'con el formato EXACTO del manual', '-> ' + JSON.stringify(b.texto));
  chk(p.envios.every(e => e.fila_id === 77 && e.estado_fila === 'publicado'), 'y la fila queda "publicado"');
  chk(b.mapa && b.mapa.cliente_jid === GRUPO.grupo_jid && b.mapa.id_msg_cliente === p.fila.mensaje_id && b.mapa.banco === 'Pichincha', 'con el mapa para saber de quien es si el banco responde');
  chk(!/ENSAYO|COBRAR HOY/.test(b.texto), 'sin marcas de ensayo ni de "cobrar hoy"');
  const g = bancos(real(['Banco: Guayaquil', 'C1: 2403', 'C2: 2790', 'Teléfono: 0990000005', 'Monto: 500'].join(SALTO)))[0];
  chk(DEST_DE(g.jid) === 'GUAYAQUIL' && g.texto === ['(Cliente Prueba', 'GUAYAQUIL', 'Monto: 500$', 'C1: 2403', 'C2: 2790', 'Teléfono: 0990000005)'].join(SALTO), 'Guayaquil: grupo GUAYAQUIL, con C1 y C2', '-> ' + JSON.stringify(g.texto));
  const j = bancos(real(['BANCO: Jep', 'Monto: $300', 'OTP: 796988', 'CI: 2100000006', 'Clave: 1111'].join(SALTO), { jep: CAJERO }))[0];
  chk(DEST_DE(j.jid) === 'COOP JEP' && /Código: 796988/.test(j.texto) && /Clave: 1111/.test(j.texto) && /Cedula: 2100000006/.test(j.texto), 'JEP (con el cobrador en el cajero): grupo COOP JEP, con el codigo, la clave de la tarjeta y la cedula', '-> ' + DEST_DE(j.jid));
  const destinosPor = { Produbanco: ['Produbanco', 'C.I: 1700000001', 'Código: 175588', 'Monto: 130$'], 'Pacífico': ['PACÍFICO', 'Monto: 100$', 'Código: 474927', 'Cedula: 0900000002', 'Teléfono: 0990000003'],
                        Solidario: ['Banco: solidario', 'Monto: 100', 'Tlf: 0990000007', 'Cedula: 1700000008', 'Codigo: 874454'], Bolivariano: ['Banco Bolivariano', 'Monto: 380', 'Código: 068521', 'Celular: 0990000009', 'Cédula: 0900000010'] };
  const esperados = { Produbanco: 'PRODUBANCO', 'Pacífico': 'PACIFICO', Solidario: 'SOLIDARIO', Bolivariano: 'BOLIVARIANO' };
  for (const [banco, l] of Object.entries(destinosPor)) { const x = bancos(real(l.join(SALTO)))[0]; chk(x && DEST_DE(x.jid) === esperados[banco], banco + ' va a su propio grupo (' + esperados[banco] + ')', '-> ' + (x && DEST_DE(x.jid))); }
  const rct = bancos(real(['Austro', '*Retira con tarjeta*', 'Monto 500$'].join(SALTO)))[0];
  chk(rct && DEST_DE(rct.jid) === 'AUSTRO' && rct.texto === ['(Cliente Prueba', 'AUSTRO', 'Retira con tarjeta', 'Monto: 500$)'].join(SALTO), 'RCT: al grupo del banco, con "Retira con tarjeta"', '-> ' + JSON.stringify(rct && rct.texto));
  const por2 = real(['Pichincha Tlf 0990000004 clave 5478 Monto 200$', 'Guayaquil Tlf 0990000005 C1: 2403 C2: 2790 Monto 500$'].join(SALTO));
  chk(bancos(por2).length === 2 && sticker(por2).length === 1 && new Set(bancos(por2).map(e => DEST_DE(e.jid))).size === 2, 'dos retiros de bancos distintos en un mensaje: cada uno a su grupo y UN solo sticker', '-> ' + bancos(por2).map(e => DEST_DE(e.jid)));
}

console.log('');
console.log('=== 5) FUERA DE HORARIO: COBRAR MAÑANA (y "cobrar hoy" para los que se vencen el mismo dia) ===');
{
  const una = (banco) => ({ Pichincha: ['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'], Guayaquil: ['Banco: Guayaquil', 'C1: 2403', 'C2: 2790', 'Teléfono: 0990000005', 'Monto: 500'],
    Produbanco: ['Produbanco', 'C.I: 1700000001', 'Código: 175588', 'Monto: 130$'], 'Pacífico': ['PACÍFICO', 'Monto: 100$', 'Código: 474927', 'Cedula: 0900000002', 'Teléfono: 0990000003'],
    Bolivariano: ['Banco Bolivariano', 'Monto: 380', 'Código: 068521', 'Celular: 0990000009', 'Cédula: 0900000010'], Solidario: ['Banco: solidario', 'Monto: 100', 'Tlf: 0990000007', 'Cedula: 1700000008', 'Codigo: 874454'],
    JEP: ['BANCO: Jep', 'Monto: $300', 'OTP: 796988', 'CI: 2100000006', 'Clave: 1111'] })[banco].join(SALTO);
  for (const banco of ['Pichincha', 'Pacífico', 'Bolivariano', 'Solidario']) {
    const x = real(una(banco), { hora: CERRADO }), b = bancos(x)[0];
    chk(b && DEST_DE(b.jid) === 'COBRAR MAÑANA' && /⚠️ COBRAR HOY para que no se venza$/.test(b.texto) && x.envios[0].estado_fila === 'cobrar_hoy', banco + ' de noche: COBRAR MAÑANA con "cobrar hoy" (se vence el mismo dia)', '-> ' + (b && DEST_DE(b.jid)) + ' / ' + (x.envios[0] || {}).estado_fila);
  }
  for (const banco of ['Guayaquil', 'Produbanco']) {
    const x = real(una(banco), { hora: CERRADO }), b = bancos(x)[0];
    chk(b && DEST_DE(b.jid) === 'COBRAR MAÑANA' && !/COBRAR HOY/.test(b.texto) && x.envios[0].estado_fila === 'en_cobrar_manana', banco + ' de noche: COBRAR MAÑANA SIN aviso (dura 24 h; el bot lo pasa al abrir)', '-> ' + (b && DEST_DE(b.jid)) + ' / ' + (x.envios[0] || {}).estado_fila);
  }
  const dom = bancos(real(una('Pichincha'), { hora: DOMINGO_TARDE }))[0];
  chk(dom && DEST_DE(dom.jid) === 'COBRAR MAÑANA', 'el domingo despues de las 2 pm tambien es fuera de horario', '-> ' + (dom && DEST_DE(dom.jid)));
  const sinCobrar = real(una('Pichincha'), { hora: CERRADO, destinos: DESTINOS.filter(d => d.nombre !== 'COBRAR MAÑANA') });
  chk(bancos(sinCobrar).length === 0 && sinCobrar.envios.some(e => e.jid === AVISOS && /NO se publicó \(no encuentro el grupo COBRAR MAÑANA\)/.test(e.texto)), 'si COBRAR MAÑANA no esta en la tabla: NO publica y avisa en avisos', '-> ' + sinCobrar.envios.map(e => e.etapa));
  const mezcla = real(['Pichincha Tlf 0990000004 clave 5478 Monto 200$', 'Guayaquil Tlf 0990000005 C1: 2403 C2: 2790 Monto 500$'].join(SALTO), { hora: CERRADO });
  chk(bancos(mezcla).length === 2 && mezcla.envios.every(e => e.estado_fila === 'en_cobrar_manana') && /COBRAR HOY/.test(bancos(mezcla).find(e => /PICHINCHA/.test(e.texto)).texto) && !/COBRAR HOY/.test(bancos(mezcla).find(e => /GUAYAQUIL/.test(e.texto)).texto),
      'un mensaje con Pichincha (cobrar hoy) y Guayaquil (24 h): la fila queda "en_cobrar_manana" para que el de Guayaquil se pase al abrir', '-> ' + mezcla.envios.map(e => e.estado_fila));
  const sticker1 = sticker(real(una('Pichincha'), { hora: CERRADO }));
  chk(sticker1.length === 1 && sticker1[0].jid === GRUPO.grupo_jid, 'al cliente se le manda el mismo sticker de recibido');
}

console.log('');
console.log('=== 6) BANCO SIN GRUPO, FOTOS Y LO QUE NO DEBE HACER NADA ===');
{
  const mach = real(['Banco Machala', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO));
  chk(bancos(mach).length === 0 && mach.envios.every(e => e.etapa !== 'banco'), 'un banco sin grupo (Machala, 23 de Julio...) no se publica en ninguna parte', '-> ' + mach.envios.map(e => e.etapa));
  const sinBanco = real(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO), { destinos: DESTINOS.filter(d => d.nombre !== 'PICHINCHA') });
  chk(bancos(sinBanco).length === 0 && sinBanco.envios.some(e => e.jid === AVISOS && /NO se publicó \(no encuentro el grupo PICHINCHA\)/.test(e.texto)) && sticker(sinBanco).length === 0, 'si el grupo del banco no esta en la tabla: avisa en avisos, sin sticker al cliente', '-> ' + sinBanco.envios.map(e => e.etapa));
  const fotoRst = real(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO), { extra: { imagen: true } });
  chk(fotoRst.fila.tipo === 'captura' && fotoRst.fila.datos.es_foto === true && bancos(fotoRst).length === 1, 'foto con el RST COMPLETO escrito en el pie: se publica el texto del pie', '-> ' + fotoRst.fila.tipo + ' ' + bancos(fotoRst).length);
  const fotoIncompleta = real('retiro sin tarjeta Pichincha', { extra: { imagen: true } });
  chk(fotoIncompleta.fila.datos.pide_texto === true && clienteTxt(fotoIncompleta)[0] && /texto escrito/.test(clienteTxt(fotoIncompleta)[0].texto) && bancos(fotoIncompleta).length === 0, 'foto con un pie que habla de un retiro pero sin datos: se le pide el texto', '-> ' + JSON.stringify((clienteTxt(fotoIncompleta)[0] || {}).texto));
  chk(!correr('', { modo: 'real', extra: { imagen: true } }).pasa, 'una foto sin pie (captura de un pago): no se toca');
  chk(!correr('Pago de la cuenta 01020000000000012345 $50', { modo: 'real', extra: { imagen: true } }).pasa, 'una captura de pago con pie normal: no se toca');
  chk(!correr('Pichincha Código: 5478 Teléfono: 0990000004 Monto: $200', { modo: 'real', extra: { fromMe: true, numero: '' } }).pasa, 'lo que escribe KELVIN en un grupo de cliente no publica nada');
  chk(!correr('Pichincha Código: 5478 Teléfono: 0990000004 Monto: $200', { modo: 'real', extra: { numero: '593990000003' } }).pasa, 'ni lo que escribe la OPERADORA');
  chk(!correr('Pichincha Código: 5478 Teléfono: 0990000004 Monto: $200', { modo: 'real', extra: { numero: '593990000077' } }).pasa, 'ni un desconocido del grupo');
  chk(correr('Pichincha Código: 5478 Teléfono: 0990000004 Monto: $200', { modo: 'real', extra: { numero: '593990000002' } }).pasa, 'el operador extra del cliente SI cuenta como el cliente');
  chk(!correr('Hola buenos dias, hay Bs hoy?', { modo: 'real' }).pasa, 'una pregunta cualquiera: nada');
  // Un beneficiario (pedido a un pais) SI pasa desde el 26/11, pero SOLO como vista previa en avisos (seccion 18).
  const ben = correr('Banco Venezuela 01020518230000072054 Ana Prueba 11111111 $40', { modo: 'real' });
  chk(ben.pasa && ben.envios.every(e => e.jid === AVISOS), 'un beneficiario (no es retiro): solo vista previa en avisos, nada a bancos ni al cliente', '-> ' + JSON.stringify(ben.envios.map(e => e.jid)));
  chk(!correr(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO), { modo: 'real', sinGuardar: true }).pasa, 'si la fila no se pudo guardar (mensaje repetido): NO se publica dos veces');
  const propio = new Function('$input', code('Entender Mensaje'))({ first: () => ({ json: { grupo: BANCO_GRUPO, data: evento('(Cliente Prueba' + SALTO + 'PICHINCHA' + SALTO + 'Monto: 200$)', { fromMe: true, id: '3EB0ABCDEF0123456789', numero: '' }) } }) });
  chk(propio.length === 0, 'lo que publica el propio bot (id 3EB0...) no se vuelve a registrar');
  const kelvin = entender('Pichincha Código: 5478 Teléfono: 0990000004 Monto: $200', { fromMe: true, id: 'A5ABCDEF', numero: '' }, BANCO_GRUPO);
  chk(!!kelvin && kelvin.autor_rol === 'kelvin', 'pero lo que Kelvin escribe a mano en un grupo de banco SI se sigue registrando');
}

console.log('');
console.log('=== 7) EL BANCO RESPONDE "VERIFICAR" O "SE DAÑÓ" A NUESTRA PUBLICACION ===');
{
  const PUB = { cliente_jid: GRUPO.grupo_jid, cliente_nombre: 'Cliente Prueba', id_msg_cliente: 'MSGCLIENTE1', banco: 'Pichincha', tipo: 'rst', fila_id: 55, destino: 'PICHINCHA' };
  const v = correr('Verificar datos', { modo: 'real', grupo: BANCO_GRUPO, pub: PUB, extra: { numero: '593990000003', cita: 'IDPUBLICADO1', id: 'OPE1' } });
  chk(v.pasa && v.envios.length === 2, '"Verificar datos" citando nuestra publicacion: dos mensajes', '-> ' + v.envios.length);
  const alBanco = v.envios.find(e => e.etapa === 'banco'), alCliente = v.envios.find(e => e.etapa === 'cliente');
  chk(alBanco && alBanco.jid === BANCO_GRUPO.grupo_jid && alBanco.texto === 'ok, procedo a mandar a verificar y corregir' && alBanco.citar === 'OPE1', 'al banco: "ok, procedo a mandar a verificar y corregir", citando lo que escribio', '-> ' + JSON.stringify(alBanco && alBanco.texto));
  chk(alCliente && alCliente.jid === GRUPO.grupo_jid && alCliente.texto === 'Por favor verifique, corrija y envíe nuevamente todos los datos en un solo texto.' && alCliente.citar === 'MSGCLIENTE1', 'al cliente, citando SU RST: que verifique, corrija y envie todo en un solo texto', '-> ' + JSON.stringify(alCliente && alCliente.citar));
  chk(v.envios.every(e => e.fila_id === 55 && e.estado_fila === 'verificar'), 'y la fila del RST original queda en "verificar"');
  const d = correr('Se dañó', { modo: 'real', grupo: BANCO_GRUPO, pub: PUB, extra: { cita: 'IDPUBLICADO1' } });
  chk(d.envios.length === 1 && d.envios[0].jid === GRUPO.grupo_jid && /su código se dañó \/ no pudo ser cobrado\. Por favor genere un nuevo código de retiro para poder saldar el saldo pendiente\.$/.test(d.envios[0].texto) && d.envios[0].estado_fila === 'danado', '"Se dañó": solo al cliente, pidiendole un codigo nuevo', '-> ' + d.envios.length);
  for (const t of ['Salió dañado', 'se daño', 'Corregir', 'por favor corrijan los datos']) chk(correr(t, { modo: 'real', grupo: BANCO_GRUPO, pub: PUB, extra: { cita: 'IDPUBLICADO1' } }).envios.length > 0, '"' + t + '" tambien se entiende');
  chk(correr('Verificar datos', { modo: 'real', grupo: BANCO_GRUPO, pub: null, extra: { cita: 'OTRO' } }).envios.length === 0, 'si lo citado NO es una publicacion nuestra (no esta en el mapa): no pasa nada');
  chk(correr('Verificar datos', { modo: 'real', grupo: BANCO_GRUPO, pub: PUB }).envios.length === 0 && !correr('Verificar datos', { modo: 'real', grupo: BANCO_GRUPO, pub: PUB }).pasa, 'sin citar nada: no pasa nada');
  chk(correr('ok listo, ya cobre', { modo: 'real', grupo: BANCO_GRUPO, pub: PUB, extra: { cita: 'IDPUBLICADO1' } }).envios.length === 0, 'otra respuesta del banco ("ya cobre"): no pasa nada');
  chk(correr('Verificar datos', { modo: 'ensayo', grupo: BANCO_GRUPO, pub: PUB, extra: { cita: 'IDPUBLICADO1' } }).envios.length === 0, 'en modo ENSAYO nunca le contesta a nadie, aunque haya un mapa viejo');
  chk(!correr('Verificar datos', { modo: 'real', grupo: Object.assign({}, GRUPO), pub: PUB, extra: { cita: 'IDPUBLICADO1' } }).pasa, 'un "verificar" escrito en un grupo de CLIENTE no dispara nada');
}

console.log('');
console.log('=== 8) EL MAPA QUEDA GUARDADO (para poder contestar despues) ===');
{
  const acc = { mapa: { cliente_jid: GRUPO.grupo_jid, fila_id: 77 }, jid: 'X' };
  const armar = (respuestas, accs) => new Function('$input', '$', code('Armar Mapa'))({ all: () => respuestas.map(json => ({ json })) },
    () => ({ itemMatching: i => ({ json: accs[i] }) })).map(i => i.json);
  const ok = armar([{ key: { id: '3EB0NUEVO1' } }], [acc]);
  chk(ok.length === 1 && ok[0].clave === 'mayorPub:3EB0NUEVO1' && JSON.parse(ok[0].valor).fila_id === 77 && ok[0].ttl === 7 * 24 * 3600, 'de un envio al banco que salio bien se guarda mayorPub:<id del mensaje>', '-> ' + JSON.stringify(ok));
  chk(armar([{ error: { message: 'x' } }], [acc]).length === 0, 'si el envio fallo: no se guarda nada');
  chk(armar([{ key: { id: 'A' } }], [{ jid: 'X' }]).length === 0, 'un mensaje sin mapa (sticker, texto al cliente): no se guarda nada');
  const conPermiso = armar([{ key: { id: 'B1' } }], [{ jid: 'X', redisSet: [{ clave: 'jepPend:G1', valor: '{"estado":"esperando"}', ttl: 21600 }] }]);
  chk(conPermiso.length === 1 && conPermiso[0].clave === 'jepPend:G1' && conPermiso[0].ttl === 21600, 'el permiso de JEP (redisSet) se guarda con SU tiempo de vida', '-> ' + JSON.stringify(conPermiso));
  chk(armar([{ error: { message: 'x' } }], [{ jid: 'X', redisSet: [{ clave: 'jepPend:G1', valor: '{}', ttl: 60 }] }]).length === 0, 'y si el envio fallo, tampoco se guarda el permiso');
  const dosRespuestas = armar([{ key: { id: 'A1' } }, { key: { id: 'A2' } }], [acc, { mapa: { fila_id: 88 } }]);
  chk(dosRespuestas.length === 2 && dosRespuestas[1].clave === 'mayorPub:A2', 'con varios envios cada mapa va con su mensaje');
}

console.log('');
console.log('=== 9) LISTA BLANCA: SOLO SE ESCRIBE A DONDE DEBE ===');
{
  const permitido = (jid, extra) => jid === AVISOS || jid === GRUPO.grupo_jid || DESTINOS.some(d => d.grupo_jid === jid) || (extra || []).includes(jid);
  const muestras = [
    real(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO)), real(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO), { hora: CERRADO }),
    real(['Pichincha', 'Código: 5478', 'Monto: $200'].join(SALTO)), real(['Banco Machala', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO)),
    real('retiro Pichincha', { extra: { imagen: true } }), correr(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO))
  ];
  const todos = muestras.flatMap(m => m.envios);
  chk(todos.length >= 8 && todos.every(e => permitido(e.jid)), 'en todos los casos probados, el destino es avisos, un grupo de la tabla o el grupo del propio cliente', '-> ' + [...new Set(todos.map(e => e.jid))].length + ' destinos distintos');
  const sinTabla = real(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO), { destinos: [] });
  chk(sinTabla.envios.every(e => e.jid === AVISOS), 'con la tabla de grupos vacia (o caida): lo unico que sale es un aviso', '-> ' + sinTabla.envios.map(e => e.jid));
  const falso = real(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO), { destinos: [{ grupo_jid: '999@g.us', nombre: 'OTRO GRUPO', tipo: 'destino' }] });
  chk(falso.envios.every(e => e.jid === AVISOS), 'un grupo cuyo nombre no es de un banco no recibe nada');
  const codigos = ['Decidir Publicacion', 'Hace Falta Publicar?', 'Armar Mapa', 'Entender Cobro', 'Vigilar Vencimiento', 'Armar Vigilancia'].map(c => code(c)).join(SALTO);
  chk(!/@g\.us'|@g\.us"|@s\.whatsapp\.net'/.test(codigos.replace(/\/\/.*$/gm, '').replace(/'120363413942097019@g\.us'/, '')), 'ningun id de grupo escrito en el codigo (solo el de avisos, que ya era publico)');
  chk(nodo(wf, 'Enviar').credentials.httpHeaderAuth.name === 'Evolution apikey Kelvin 0380' && !/apikey/i.test(JSON.stringify(nodo(wf, 'Enviar').parameters.headerParameters)), 'la llave de Evolution va en la credencial, no escrita en el nodo');
}

console.log('');
console.log('=== 10) EL HORARIO ES EL MISMO DEL BOT DEL DETAL ===');
{
  const sacar = js => { const i = js.indexOf('// ===== HORARIO DE ATENCION'); const f = js.indexOf('\n}\n', js.indexOf('function horarioDe')); return js.slice(i, f + 3); };
  const botIa = JSON.parse(readFileSync('workflow_ia_atencion.json', 'utf8').replace(/^﻿/, ''));
  const delBot = sacar(nodo(botIa, 'Revisar Operacion').parameters.jsCode), delMayor = sacar(code('Decidir Publicacion'));
  chk(delBot.length > 500 && delBot === delMayor, 'el bloque de horario es identico al de "Revisar Operacion" del bot', '-> ' + delBot.length + ' / ' + delMayor.length);
}

console.log('');
console.log('=== 11) EL WORKFLOW DE LA MAÑANA: pasa de COBRAR MAÑANA a su banco (solo Guayaquil y Produbanco) ===');
{
  const noche = JSON.parse(readFileSync('workflow_mayor_noche.json', 'utf8').replace(/^﻿/, ''));
  const codN = n => nodo(noche, n).parameters.jsCode;
  const ahoraMs = new Date('2026-11-25T14:05:00Z').getTime();       // miercoles 9:05 am en Ecuador
  const hace = horas => new Date(ahoraMs - horas * 3600000).toISOString();
  const fila = (id, nombre, banco, tipoRegistro, datosReg, horas) => ({ id, creado: hace(horas), cliente_nombre: nombre, grupo_jid: GRUPO.grupo_jid, mensaje_id: 'MSGCLI' + id, estado: 'en_cobrar_manana',
    datos: { registros: [Object.assign({ tipo: tipoRegistro || 'rst', banco, monto_usd: 130 }, { datos: datosReg })] } });
  const GUAYAQUIL = { codigos: ['2403', '2790'], telefono: '0990000005' }, PRODU = { codigos: ['175588'], cedula: '1700000001' };
  function armar(filas, opciones) {
    const o = opciones || {};
    const real = Date.now; Date.now = () => ahoraMs;
    try {
      const $ = nombre => {
        if (nombre === 'Leer Grupos Destino') return { all: () => (o.destinos || DESTINOS).map(json => ({ json })) };
        if (nombre === 'Leer RST en Espera') return { all: () => filas.map(json => ({ json })) };
        throw new Error('nodo inesperado: ' + nombre);
      };
      let c = codN('Armar Envios'); if (o.modo !== 'ensayo') c = c.replace("const MODO = 'ensayo'", "const MODO = 'real'");
      return new Function('$', c)($).map(i => i.json);
    } finally { Date.now = real; }
  }
  const x = armar([fila(1, 'Cliente Prueba', 'Guayaquil', 'rst', GUAYAQUIL, 12), fila(2, 'Otro Cliente', 'Produbanco', 'rst', PRODU, 14)]);
  chk(x.length === 2 && DEST_DE(x[0].jid) === 'GUAYAQUIL' && DEST_DE(x[1].jid) === 'PRODUBANCO', 'los RST de Guayaquil y Produbanco van cada uno a su grupo', '-> ' + x.map(e => DEST_DE(e.jid)));
  chk(x[0].texto === ['(Cliente Prueba', 'GUAYAQUIL', 'Monto: 130$', 'C1: 2403', 'C2: 2790', 'Teléfono: 0990000005)'].join(SALTO), 'con el mismo bloque del manual (sin "cobrar hoy")', '-> ' + JSON.stringify(x[0].texto));
  chk(x.every(e => e.estado_fila === 'publicado' && e.mapa && e.mapa.cliente_jid === GRUPO.grupo_jid && e.mapa.id_msg_cliente.startsWith('MSGCLI')), 'quedan "publicado" y con el mapa para poder contestarle al cliente');
  chk(x[0].fila_id === 1 && x[1].fila_id === 2, 'cada envio sabe a que fila pertenece');
  chk(armar([fila(3, 'Cliente Prueba', 'Pichincha', 'rst', { codigos: ['5478'], telefono: '0990000004' }, 12)]).length === 1 && /sin_grupo|NO se pasó|no encuentro qué pasar/.test(armar([fila(3, 'Cliente Prueba', 'Pichincha', 'rst', { codigos: ['5478'], telefono: '0990000004' }, 12)])[0].texto) && armar([fila(3, 'Cliente Prueba', 'Pichincha', 'rst', { codigos: ['5478'], telefono: '0990000004' }, 12)])[0].jid === AVISOS,
      'un RST de Pichincha (se vence el mismo dia) NUNCA se pasa: solo un aviso si por error estaba en la lista');
  const viejo = armar([fila(4, 'Cliente Prueba', 'Guayaquil', 'rst', GUAYAQUIL, 40)]);
  chk(viejo.length === 1 && viejo[0].jid === AVISOS && viejo[0].estado_fila === 'vencido' && /más de 36 horas/.test(viejo[0].texto) && !viejo[0].mapa, 'un RST de mas de 36 horas ya esta vencido: NO se pasa, se avisa y queda "vencido"', '-> ' + viejo.map(e => e.estado_fila));
  const sinGrupo = armar([fila(5, 'Cliente Prueba', 'Guayaquil', 'rst', GUAYAQUIL, 10)], { destinos: DESTINOS.filter(d => d.nombre !== 'GUAYAQUIL') });
  chk(sinGrupo.length === 1 && sinGrupo[0].jid === AVISOS && /no encuentro el grupo GUAYAQUIL/.test(sinGrupo[0].texto), 'si falta el grupo del banco en la tabla: avisa en avisos', '-> ' + sinGrupo.map(e => e.jid));
  const incompleto = armar([fila(6, 'Cliente Prueba', 'Guayaquil', 'rst', { codigos: ['2403'] }, 10)]);
  chk(incompleto.length === 1 && incompleto[0].jid === AVISOS, 'un RST que quedo incompleto no se pasa: aviso');
  chk(armar([fila(1, 'Cliente Prueba', 'Guayaquil', 'rst', GUAYAQUIL, 12)], { modo: 'ensayo' }).length === 0, 'en modo ENSAYO no hace nada');
  chk(armar([]).length === 0 && armar([{ error: 'x' }, {}]).length === 0, 'sin filas esperando (o si Supabase fallo): no hace nada');
  chk(armar([fila(1, 'Cliente Prueba', 'Guayaquil', 'rst', GUAYAQUIL, 12)], { destinos: [] }).every(e => e.jid === AVISOS), 'con la tabla de grupos vacia: lo unico que sale es un aviso');
  const mixto = armar([Object.assign(fila(7, 'Cliente Prueba', 'Guayaquil', 'rst', GUAYAQUIL, 12), { datos: { registros: [
    { tipo: 'rst', banco: 'Pichincha', monto_usd: 100, datos: { codigos: ['5478'], telefono: '0990000004' } }, { tipo: 'rst', banco: 'Guayaquil', monto_usd: 130, datos: GUAYAQUIL }] } })]);
  chk(mixto.length === 1 && DEST_DE(mixto[0].jid) === 'GUAYAQUIL', 'una fila con Pichincha (cobrar hoy) y Guayaquil (24 h): solo se pasa el de Guayaquil', '-> ' + mixto.map(e => DEST_DE(e.jid)));
  const mapa = new Function('$input', '$', codN('Armar Mapa'))({ all: () => [{ json: { key: { id: '3EB0AAA1' } } }, { json: { error: { message: 'x' } } }] }, () => ({ itemMatching: i => ({ json: x[i] }) })).map(i => i.json);
  chk(mapa.length === 1 && mapa[0].clave === 'mayorPub:3EB0AAA1' && JSON.parse(mapa[0].valor).fila_id === 1, 'el mapa se guarda solo de lo que salio bien');
  const cron = nodo(noche, 'Cada Mañana').parameters.rule.interval.map(i => i.expression);
  chk(cron.includes('0 5 9 * * 1-6') && cron.includes('0 5 10 * * 0'), 'se dispara a las 9:05 de lunes a sabado y a las 10:05 el domingo', '-> ' + cron);
  const filtro = nodo(noche, 'Leer RST en Espera').parameters.filterString;
  chk(/estado=eq\.en_cobrar_manana/.test(filtro), 'solo lee lo que esta "en_cobrar_manana"', '-> ' + filtro);
  const envia = noche.nodes.filter(n => /httpRequest/.test(n.type)).map(n => n.name);
  chk(JSON.stringify(envia) === JSON.stringify(['Enviar al Banco']) && /\$json\.jid/.test(nodo(noche, 'Enviar al Banco').parameters.jsonBody) && !/@g\.us/.test(JSON.stringify(nodo(noche, 'Enviar al Banco').parameters)), 'un solo nodo envia, y su destino sale de "Armar Envios" (sin ids escritos)');
  const tiposN = [...new Set(noche.nodes.map(n => n.type.replace('n8n-nodes-base.', '')))].sort();
  chk(tiposN.every(t => ['stickyNote', 'scheduleTrigger', 'code', 'redis', 'supabase', 'httpRequest'].includes(t)), 'y ningun otro tipo de nodo', '-> ' + tiposN);
  const delMayor = code('Decidir Publicacion'), delNoche = codN('Armar Envios');
  const comun = js => js.slice(js.indexOf('// ===== COMUN'), js.indexOf('\nconst unir'));
  chk(comun(delMayor).length > 800 && comun(delMayor) === comun(delNoche), 'las reglas de los bancos son IDENTICAS en los dos workflows (un solo origen)');
}

console.log('');
console.log('=== 12) JEP: "te avisamos cuando el cobrador este en el cajero" (el codigo dura 15 minutos) ===');
{
  const JEP_GRUPO = { tipo: 'destino', nombre: 'COOP JEP', grupo_jid: ID('COOP JEP'), operadora_whatsapp: '593990000003' };
  const DATOS_JEP = ['BANCO: Jep', 'Monto: $300', 'OTP: 796988', 'CI: 2100000006', 'Clave: 1111'];
  const CLIENTE_TXT = 'Te avisamos cuando el cobrador esté en el cajero, para que realices el RST.';

  // A) el cliente manda los datos de JEP SIN que el cobrador este en el cajero: no se publica el codigo
  let x = real(DATOS_JEP.join(SALTO));
  const pedido = bancos(x)[0], alCli = clienteTxt(x)[0];
  chk(x.pasa && bancos(x).length === 1 && DEST_DE(pedido.jid) === 'COOP JEP' && /^🏧 Cobrador: ir a un cajero y avisar aquí, citando este mensaje, cuando estés para indicarle al cliente que haga el RST\./.test(pedido.texto) && /Cliente: Cliente Prueba\nMonto: 300\$$/.test(pedido.texto),
      'JEP sin permiso: al grupo de JEP va el PEDIDO al cobrador (cliente y monto)', '-> ' + JSON.stringify(pedido && pedido.texto));
  chk(!/796988|1111|2100000006/.test(JSON.stringify(x.envios)), '   ...y el codigo, la clave y la cedula NO se publican', '');
  chk(alCli && alCli.texto === CLIENTE_TXT && alCli.citar === x.fila.mensaje_id && sticker(x).length === 0, 'al cliente, citando su mensaje: "te avisamos cuando el cobrador este en el cajero..." (sin sticker)', '-> ' + JSON.stringify(alCli && alCli.texto));
  chk(pedido.mapa.jep === 'solicitud' && pedido.mapa.cliente_jid === GRUPO.grupo_jid && pedido.mapa.id_msg_cliente === x.fila.mensaje_id && pedido.redisSet && pedido.redisSet[0].clave === 'jepPend:' + GRUPO.grupo_jid
      && JSON.parse(pedido.redisSet[0].valor).estado === 'esperando' && pedido.redisSet[0].ttl === 6 * 3600 && pedido.vigila && pedido.vigila.banco === 'jep_pedido' && /Cliente Prueba · JEP 300\$/.test(pedido.vigila.resumen),
      'se anota el pedido (mapa) y que el cliente "esta esperando" (6 h); y se vigila: si el cobrador no contesta en 30 min, aviso');
  chk(x.envios.every(e => e.estado_fila === 'jep_esperando'), 'la fila queda "jep_esperando"');

  // B) sin datos: "quiero hacer un retiro por JEP"
  x = real('Buenas tardes, quiero hacer un retiro por JEP');
  chk(x.pasa && bancos(x).length === 1 && !/Monto/.test(bancos(x)[0].texto) && clienteTxt(x)[0].texto === CLIENTE_TXT, 'un pedido sin datos ("quiero hacer un retiro por JEP") tambien avisa al cobrador, sin monto', '-> ' + JSON.stringify(bancos(x)[0] && bancos(x)[0].texto));
  x = real('quiero un rst de JEP de 150');
  chk(bancos(x).length === 1 && /Monto: 150\$/.test(bancos(x)[0].texto), '"quiero un rst de JEP de 150": el monto va en el pedido', '-> ' + JSON.stringify(bancos(x)[0] && bancos(x)[0].texto));
  for (const charla of ['que tanto demora el rst de jep ?', 'JEP está fallando hoy', 'ayer hice un retiro por jep y salió bien']) {
    chk(real(charla).envios.length === 0, 'charla sobre JEP, no es un pedido: "' + charla + '"');
  }

  // C) ya se le pidio al cobrador: no se le pide dos veces
  x = real(DATOS_JEP.join(SALTO), { jep: { estado: 'esperando', id_msg_cliente: 'M0', fila_id: 70 } });
  chk(bancos(x).length === 0 && x.envios.length === 1 && x.envios[0].texto === 'Ya avisamos al cobrador. Te escribimos apenas esté en el cajero.', 'si ya esta esperando: "ya avisamos al cobrador", sin repetir el pedido', '-> ' + JSON.stringify(x.envios.map(e => e.texto)));

  // D) fuera de horario: no hay cobrador; el pedido sale al abrir (workflow de la mañana)
  x = real(DATOS_JEP.join(SALTO), { hora: CERRADO });
  chk(bancos(x).length === 0 && x.envios.length === 1 && /^Te avisamos cuando el cobrador esté en el cajero, mañana a partir de las 9:00 am, para que realices el RST\.$/.test(x.envios[0].texto), 'de noche: se le dice al cliente cuando (a partir de que hora), sin pedido todavia', '-> ' + JSON.stringify(x.envios.map(e => e.texto)));
  chk(x.envios[0].estado_fila === 'en_cobrar_manana' && x.envios[0].redisSet[0].ttl === 20 * 3600 && JSON.parse(x.envios[0].redisSet[0].valor).estado === 'esperando', 'y la fila queda "en_cobrar_manana" para que el workflow de la mañana lo pida al abrir');

  // E) el cobrador contesta nuestro pedido: "listo, ya estoy aca"
  const SOLICITUD = { cliente_jid: GRUPO.grupo_jid, cliente_nombre: 'Cliente Prueba', id_msg_cliente: 'MSGCLIENTE1', banco: 'JEP', tipo: 'rst', fila_id: 55, destino: 'COOP JEP', jep: 'solicitud' };
  for (const frase of ['listo, ya estoy acá', 'llegué', 'Ya estoy aqui, pide el rst', 'listo']) {
    const l = correr(frase, { modo: 'real', grupo: JEP_GRUPO, pub: SOLICITUD, extra: { cita: 'IDPEDIDO1', id: 'COB1', numero: '593990000088' } });
    const cli = l.envios.find(e => e.etapa === 'cliente'), grp = l.envios.find(e => e.etapa === 'banco');
    chk(l.pasa && l.envios.length === 2 && cli && cli.jid === GRUPO.grupo_jid && cli.citar === 'MSGCLIENTE1' && cli.texto === 'El cobrador ya está en el cajero. Realiza tu RST ahora y envíame todos los datos en un solo texto.'
        && grp && grp.jid === JEP_GRUPO.grupo_jid && grp.texto === 'ok, ya le aviso al cliente' && grp.citar === 'COB1', '"' + frase + '": le avisa al cliente (citando SU mensaje) y confirma en el grupo', '-> ' + l.envios.length);
    if (frase === 'listo, ya estoy acá') chk(JSON.parse(cli.redisSet[0].valor).estado === 'en_cajero' && cli.redisSet[0].clave === 'jepPend:' + GRUPO.grupo_jid && cli.redisSet[0].ttl === 1800 && l.envios.every(e => e.fila_id === 55 && e.estado_fila === 'jep_en_cajero'), '   ...y el permiso queda "en_cajero" por 30 minutos');
  }
  for (const frase of ['no hay cajero disponible', 'todavia no llego', 'sin efectivo']) chk(correr(frase, { modo: 'real', grupo: JEP_GRUPO, pub: SOLICITUD, extra: { cita: 'IDPEDIDO1' } }).envios.length === 0, '"' + frase + '" no es "ya llegue": no se le avisa al cliente');
  chk(correr('listo', { modo: 'real', grupo: JEP_GRUPO, pub: null, extra: { cita: 'OTRO' } }).envios.length === 0, '"listo" citando algo que NO es nuestro pedido: no pasa nada');
  chk(!correr('listo, ya estoy acá', { modo: 'real', grupo: JEP_GRUPO, pub: SOLICITUD }).pasa, '"listo" sin citar nada: no pasa nada');
  chk(correr('listo, ya estoy acá', { modo: 'real', grupo: BANCO_GRUPO, pub: SOLICITUD, extra: { cita: 'IDPEDIDO1' } }).envios.length === 0 || !correr('listo, ya estoy acá', { modo: 'real', grupo: BANCO_GRUPO, pub: SOLICITUD, extra: { cita: 'IDPEDIDO1' } }).pasa, 'el "listo" solo cuenta en el grupo de JEP (no en el de Pichincha)');
  chk(correr('listo, ya estoy acá', { modo: 'ensayo', grupo: JEP_GRUPO, pub: SOLICITUD, extra: { cita: 'IDPEDIDO1' } }).envios.length === 0, 'en modo ENSAYO no le contesta a nadie');

  // F) con el permiso en_cajero el cliente manda el RST: se publica YA en JEP (aunque sea de noche) y se vigila
  x = real(DATOS_JEP.join(SALTO), { jep: CAJERO });
  const bj = bancos(x)[0];
  chk(bancos(x).length === 1 && DEST_DE(bj.jid) === 'COOP JEP' && /Código: 796988/.test(bj.texto) && /Clave: 1111/.test(bj.texto) && sticker(x).length === 1 && !/COBRAR HOY/.test(bj.texto), 'con el cobrador en el cajero: el RST completo se publica en COOP JEP + sticker "RST Recibido"', '-> ' + (bj && DEST_DE(bj.jid)));
  chk(bj.redisSet && bj.redisSet[0].clave === 'jepPend:' + GRUPO.grupo_jid && JSON.parse(bj.redisSet[0].valor).estado === 'usado' && bj.redisSet[0].ttl === 60, 'y el permiso se gasta (no sirve para un segundo RST)');
  chk(bj.vigila && bj.vigila.banco === 'jep' && bj.vigila.recibido === x.fila.fecha_mensaje && /JEP 300\$/.test(bj.vigila.resumen), 'y se vigila (alerta a los 5 minutos si nadie lo marca cobrado)', '-> ' + JSON.stringify(bj.vigila));
  x = real(DATOS_JEP.join(SALTO), { jep: CAJERO, hora: CERRADO });
  chk(bancos(x).length === 1 && DEST_DE(bancos(x)[0].jid) === 'COOP JEP', 'aunque el reloj diga "cerrado": el cobrador ya esta en el cajero, va directo a COOP JEP (no a COBRAR MAÑANA)', '-> ' + DEST_DE((bancos(x)[0] || {}).jid));
  x = real(['BANCO: Jep', 'Monto: $300', 'OTP: 796988'].join(SALTO), { jep: CAJERO });
  chk(bancos(x).length === 0 && /la cédula y la clave de la tarjeta/.test((clienteTxt(x)[0] || {}).texto || ''), 'con el cobrador en el cajero pero datos incompletos: se piden los que faltan (no se vuelve a llamar al cobrador)', '-> ' + (clienteTxt(x)[0] || {}).texto);

  // G) ENSAYO y lo que NO cambia
  x = correr(DATOS_JEP.join(SALTO));
  chk(x.envios.length === 1 && x.envios[0].jid === AVISOS && /iría a COOP JEP:\n🏧 Cobrador/.test(x.envios[0].texto) && /Te avisamos cuando el cobrador esté en el cajero/.test(x.envios[0].texto) && !/796988/.test(x.envios[0].texto), 'ENSAYO: una sola vista previa en avisos (pedido al cobrador + aviso al cliente)', '-> ' + JSON.stringify(x.envios.map(e => e.jid)));
  x = real(['JEP', '*Retira con tarjeta*', 'Monto 200$'].join(SALTO));
  chk(bancos(x).length === 1 && /Retira con tarjeta/.test(bancos(x)[0].texto) && !/Cobrador/.test(bancos(x)[0].texto), 'un RCT de JEP (retiro con tarjeta) NO pasa por el cajero: va normal', '-> ' + JSON.stringify(bancos(x).map(e => e.texto)));
  x = real(DATOS_JEP.join(SALTO), { destinos: DESTINOS.filter(d => d.nombre !== 'COOP JEP') });
  chk(bancos(x).length === 0 && x.envios.some(e => e.jid === AVISOS && /no encuentro el grupo COOP JEP/.test(e.texto)) && clienteTxt(x).length === 0, 'si el grupo de JEP no esta en la tabla: avisa en avisos y NO le dice al cliente que espere', '-> ' + x.envios.map(e => e.etapa));
  const dos = real(['Pichincha Tlf 0990000004 clave 5478 Monto 200$', 'Jep monto 100 rst'].join(SALTO));
  chk(bancos(dos).length === 2 && bancos(dos).some(e => DEST_DE(e.jid) === 'PICHINCHA' && /Código: 5478/.test(e.texto)) && bancos(dos).some(e => DEST_DE(e.jid) === 'COOP JEP' && /Cobrador/.test(e.texto)), 'un mensaje con Pichincha y JEP: Pichincha se publica y JEP espera al cobrador', '-> ' + bancos(dos).map(e => DEST_DE(e.jid)));
}

console.log('');
console.log('=== 13) ALERTAS: lo que el bot deja anotado al publicar (vigila) ===');
{
  const lin = ['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'];
  let b = bancos(real(lin.join(SALTO)))[0];
  chk(b.vigila && b.vigila.banco === 'pichincha' && b.vigila.recibido && /Cliente Prueba · PICHINCHA 200\$/.test(b.vigila.resumen), 'un RST publicado en el grupo de su banco se anota para vigilarlo', '-> ' + JSON.stringify(b.vigila));
  b = bancos(real(lin.join(SALTO), { hora: CERRADO }))[0];
  chk(!b.vigila, 'uno que se quedo en COBRAR MAÑANA todavia NO (el reloj del banco se mira cuando llegue a su grupo)');
  b = bancos(real(['Austro', '*Retira con tarjeta*', 'Monto 500$'].join(SALTO)))[0];
  chk(!b.vigila, 'un RCT (retiro con tarjeta) no tiene codigo que se venza: no se vigila');
}

console.log('');
console.log('=== 14) LARGO EXACTO DE LOS CODIGOS (seccion 9 del manual) ===');
{
  const RST = (banco, ...lineas) => [banco].concat(lineas).join(SALTO);
  const res = (texto, extra) => { const p = real(texto, extra); return { p, txt: (clienteTxt(p)[0] || {}).texto || '' }; };
  const REVISA = (b, que) => 'Revisa tu RST de ' + b + ': ' + que + '. Corrígelo y envíalo de nuevo con todos los datos en un solo texto, por favor.';
  let x = res(RST('Pichincha', 'Código: 54781', 'Teléfono: 0990000004', 'Monto: $200'));
  chk(bancos(x.p).length === 0 && x.txt === REVISA('Pichincha', 'el código debe tener 4 dígitos'), 'Pichincha con un codigo de 5 digitos: NO se publica, se le dice que debe tener 4', '-> ' + x.txt);
  chk(x.p.envios.every(e => e.estado_fila === 'falta_datos') && clienteTxt(x.p)[0].citar === x.p.fila.mensaje_id, '   ...citando SU mensaje, y la fila queda "falta_datos"');
  x = res(RST('Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'));
  chk(bancos(x.p).length === 1 && clienteTxt(x.p).length === 0, 'Pichincha con 4 digitos: se publica');
  x = res(RST('Produbanco', 'C.I: 1700000001', 'Código: 17558', 'Monto: 130$'));
  chk(bancos(x.p).length === 0 && x.txt === REVISA('Produbanco', 'el código debe tener 6 dígitos'), 'Produbanco con 5 digitos: debe tener 6', '-> ' + x.txt);
  x = res(RST('PACÍFICO', 'Monto: 100$', 'Código: 4749271', 'Cedula: 0900000002', 'Teléfono: 0990000003'));
  chk(bancos(x.p).length === 0 && x.txt === REVISA('Pacífico', 'el código debe tener 6 dígitos'), 'Pacifico con 7 digitos: debe tener 6', '-> ' + x.txt);
  x = res(RST('Banco: solidario', 'Monto: 100', 'Tlf: 0990000007', 'Cedula: 1700000008', 'Codigo: 87445'));
  chk(bancos(x.p).length === 0 && x.txt === REVISA('Solidario', 'el código debe tener 6 dígitos'), 'Solidario con 5 digitos: debe tener 6', '-> ' + x.txt);
  for (const c of ['068521', '57913864']) {
    x = res(RST('Banco Bolivariano', 'Monto: 380', 'Código: ' + c, 'Celular: 0990000009', 'Cédula: 0900000010'));
    chk(bancos(x.p).length === 1, 'Bolivariano con ' + c.length + ' digitos: se publica (6 u 8 son validos)');
  }
  x = res(RST('Banco Bolivariano', 'Monto: 380', 'Código: 0685211', 'Celular: 0990000009', 'Cédula: 0900000010'));
  chk(bancos(x.p).length === 0 && x.txt === REVISA('Bolivariano', 'el código debe tener 6 u 8 dígitos'), 'Bolivariano con 7 digitos: NO (solo 6 u 8)', '-> ' + x.txt);
  x = res(RST('Banco: Guayaquil', 'C1: 24031', 'C2: 2790', 'Teléfono: 0990000005', 'Monto: 500'));
  chk(bancos(x.p).length === 0 && x.txt === REVISA('Guayaquil', 'el código 1 debe tener 4 dígitos'), 'Guayaquil con el codigo 1 de 5 digitos: debe tener 4', '-> ' + x.txt);
  x = res(RST('Banco: Guayaquil', 'C1: 2403', 'C2: 279', 'Teléfono: 0990000005', 'Monto: 500'));
  chk(bancos(x.p).length === 0 && x.txt === REVISA('Guayaquil', 'el código 2 debe tener 4 dígitos'), 'Guayaquil con el codigo 2 de 3 digitos: debe tener 4', '-> ' + x.txt);
  x = res(RST('BANCO: Jep', 'Monto: $300', 'OTP: 796988', 'CI: 2100000006', 'Clave: 123'), { jep: CAJERO });
  chk(bancos(x.p).length === 0 && x.txt === REVISA('JEP', 'la clave de la tarjeta debe tener 4 dígitos'), 'JEP con la clave de la tarjeta de 3 digitos: debe tener 4', '-> ' + x.txt);
  x = res(RST('BANCO: Jep', 'Monto: $300', 'OTP: 79698', 'CI: 2100000006', 'Clave: 1111'), { jep: CAJERO });
  chk(bancos(x.p).length === 0 && x.txt === REVISA('JEP', 'el código debe tener 6 dígitos'), 'JEP con el OTP de 5 digitos: debe tener 6', '-> ' + x.txt);
  x = res(RST('Pichincha', 'Código: 54781', 'Monto: $200'));
  chk(x.txt === 'Faltan estos datos para tu RST de Pichincha: el teléfono. Además, el código debe tener 4 dígitos. Envíalos de nuevo en un solo texto, por favor.', 'si falta algo Y el largo esta mal: se dicen las dos cosas en un solo mensaje', '-> ' + x.txt);
  x = res(['Pichincha Tlf 0990000004 clave 54781 Monto 200$', 'Guayaquil Tlf 0990000005 C1: 24031 C2: 27901 Monto 500$'].join(SALTO));
  chk(bancos(x.p).length === 0 && /^Revisa los códigos de tus retiros:\n• RST de Pichincha: el código debe tener 4 dígitos\n• RST de Guayaquil: el código 1 debe tener 4 dígitos y el código 2 debe tener 4 dígitos\nEnvíalos de nuevo/.test(x.txt), 'dos retiros con el largo mal en un mensaje: una sola lista', '-> ' + JSON.stringify(x.txt));
  x = res(RST('Austro', 'Código: 12345', 'Teléfono: 0990000004', 'Monto: $50'));
  chk(bancos(x.p).length === 1, 'un banco sin regla de largo (Austro, Internacional...): no se revisa, se publica');
  const rctAustro = res(['Austro', '*Retira con tarjeta*', 'Monto 500$'].join(SALTO));
  chk(bancos(rctAustro.p).length === 1, 'un RCT no tiene codigo: nada que revisar');
  const ens = correr(RST('Pichincha', 'Código: 54781', 'Teléfono: 0990000004', 'Monto: $200'));
  chk(ens.envios.length === 1 && ens.envios[0].jid === AVISOS && /Revisa tu RST de Pichincha: el código debe tener 4 dígitos/.test(ens.envios[0].texto), 'en ENSAYO tambien se ve en la vista previa');
}

console.log('');
console.log('=== 15) SOLIDARIO: la CLAVE TEMPORAL en vivo (seccion 9 del manual) ===');
{
  const SOL = DESTINOS.find(d => d.nombre === 'SOLIDARIO');
  const SOL_GRUPO = { tipo: 'destino', nombre: 'SOLIDARIO', grupo_jid: SOL.grupo_jid, operadora_whatsapp: '593990000003' };
  const SOL_PUB = { cliente_jid: GRUPO.grupo_jid, cliente_nombre: 'Cliente Prueba', id_msg_cliente: 'MSGCLIENTE1', banco: 'Solidario', tipo: 'rst', fila_id: 55, destino: 'SOLIDARIO' };
  const TEMP = { estado: 'pide_temporal', id_pub: 'IDPUB1', grupo_jid: SOL.grupo_jid, id_msg_cliente: 'MSGCLIENTE1', fila_id: 55, cliente_nombre: 'Cliente Prueba' };
  const SMS = 'B. Solidario te informa tu clave temporal para retiro de efectivo es 919180, recuerda que esta clave podra ser utilizada hasta 17:12';
  // 1) el cobrador (frente al cajero) cita nuestro RST y escribe "temporal"
  for (const frase of ['temporal', 'código temporal', 'segundo código', 'Segundo codigo por favor']) {
    const t = correr(frase, { modo: 'real', grupo: SOL_GRUPO, pub: SOL_PUB, extra: { cita: 'IDPUB1', id: 'COB1', numero: '593990000088' } });
    const alGrupo = t.envios.find(e => e.etapa === 'banco'), alCli = t.envios.find(e => e.etapa === 'cliente');
    chk(t.pasa && t.envios.length === 2 && alGrupo.jid === SOL.grupo_jid && alGrupo.texto === 'ok, se lo pido al cliente' && alGrupo.citar === 'COB1'
        && alCli.jid === GRUPO.grupo_jid && alCli.citar === 'MSGCLIENTE1' && alCli.texto === 'Por favor envíame de inmediato el código temporal que te acaba de llegar.', '"' + frase + '": se lo pide al cliente (citando SU RST) y confirma en el grupo', '-> ' + t.envios.length);
    if (frase === 'temporal') {
      const v = JSON.parse(alCli.redisSet[0].valor);
      chk(alCli.redisSet[0].clave === 'solPend:' + GRUPO.grupo_jid && v.estado === 'pide_temporal' && v.id_pub === 'IDPUB1' && v.grupo_jid === SOL.grupo_jid && alCli.redisSet[0].ttl === 900 && t.envios.every(e => e.fila_id === 55 && e.estado_fila === 'temporal_pedido'),
          '   ...y deja anotado que la espera (15 min), con el RST y el grupo al que hay que llevarla');
    }
  }
  chk(correr('temporal', { modo: 'real', grupo: SOL_GRUPO, pub: Object.assign({}, SOL_PUB, { banco: 'Pichincha' }), extra: { cita: 'IDPUB1' } }).envios.length === 0, '"temporal" citando un RST que NO es de Solidario: no pasa nada');
  chk(correr('temporal', { modo: 'real', grupo: SOL_GRUPO, pub: null, extra: { cita: 'OTRO' } }).envios.length === 0, '"temporal" citando algo que NO es nuestro: no pasa nada');
  chk(!correr('temporal', { modo: 'real', grupo: SOL_GRUPO, pub: SOL_PUB }).pasa, '"temporal" sin citar nada: no pasa nada');
  chk(correr('temporal', { modo: 'ensayo', grupo: SOL_GRUPO, pub: SOL_PUB, extra: { cita: 'IDPUB1' } }).envios.length === 0, 'en modo ENSAYO no le contesta a nadie');

  // 2) el cliente manda la clave que le llego
  for (const [etiqueta, texto] of [['el mensaje del banco', SMS], ['solo los digitos', '919180'], ['digitos con una palabra', 'clave 919180']]) {
    const t = real(texto, { temporal: TEMP });
    const alGrupo = t.envios.find(e => e.etapa === 'banco'), alCli = t.envios.find(e => e.etapa === 'cliente');
    chk(t.pasa && t.envios.length === 2 && t.envios[0].etapa === 'banco' && alGrupo.jid === SOL.grupo_jid && alGrupo.texto === texto && alGrupo.citar === 'IDPUB1'
        && alCli.texto === 'Ok, recibido' && alCli.jid === GRUPO.grupo_jid && alCli.citar === t.fila.mensaje_id && sticker(t).length === 0, 'el cliente manda ' + etiqueta + ': "Ok, recibido" y se la lleva al grupo Solidario CITANDO el RST (primero al grupo)', '-> ' + t.envios.map(e => e.etapa + ':' + String(e.texto).slice(0, 20)));
    if (etiqueta === 'el mensaje del banco') chk(JSON.parse(alGrupo.redisSet[0].valor).estado === 'usado' && alGrupo.redisSet[0].ttl === 60 && t.envios.every(e => e.estado_fila === 'temporal_enviado') && !t.envios.some(e => /Faltan/.test(String(e.texto))), '   ...se gasta (no se vuelve a entregar) y NO lo toma por un RST con datos faltantes');
  }
  chk(real(SMS).envios.length === 0 && real('919180').envios.length === 0, 'si el cobrador NO la habia pedido (o ya paso el tiempo): no se hace nada con ese numero');
  chk(real('mi cedula es 123456 y mi otro numero 654321', { temporal: TEMP }).envios.length === 0, 'con dos numeros de 6 digitos distintos no adivina cual es: no hace nada');
  chk(real('ya te la mando en un momento', { temporal: TEMP }).envios.length === 0, 'una charla mientras espera: nada');
  const nuevo = real(['Banco: solidario', 'Monto: 100', 'Tlf: 0990000007', 'Cedula: 1700000008', 'Codigo: 874454'].join(SALTO), { temporal: TEMP });
  chk(bancos(nuevo).length === 1 && DEST_DE(bancos(nuevo)[0].jid) === 'SOLIDARIO' && /Código: 874454/.test(bancos(nuevo)[0].texto) && !nuevo.envios.some(e => e.texto === 'Ok, recibido'), 'un RST NUEVO de Solidario completo mientras espera: es un RST, no la clave temporal');
  const sinGrupo = real(SMS, { temporal: Object.assign({}, TEMP, { grupo_jid: '999@g.us' }) });
  chk(sinGrupo.envios.length === 1 && sinGrupo.envios[0].jid === AVISOS && /NO se entregó/.test(sinGrupo.envios[0].texto), 'si el grupo no es de la tabla: no se le escribe, solo un aviso en avisos');
  const ens = correr(SMS, { temporal: TEMP });
  chk(ens.envios.length === 1 && ens.envios[0].jid === AVISOS && !/919180/.test(ens.envios[0].texto) && /iría a SOLIDARIO/.test(ens.envios[0].texto), 'en ENSAYO la vista previa tapa la clave');
  // 3) lo que dejaba pasar el filtro
  chk(correr('919180', { modo: 'real', temporal: TEMP }).pasa && correr(SMS, { modo: 'real' }).pasa, 'el filtro deja pasar un mensaje con un numero de 6 digitos (despues se confirma si esperaban esa clave)');
  chk(!correr('hola buenas tardes', { modo: 'real', temporal: TEMP }).pasa, 'y no deja pasar una charla');
}

console.log('=== 16) RST REPETIDO: el mismo codigo dos veces en poco tiempo NO se publica dos veces (revision diaria 25/11) ===');
{
  // Caso real (datos inventados): el cliente mando un Pichincha y al minuto el mismo, con el mismo codigo pero otro telefono.
  const PICH = ['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO);
  const PICH_OTRO_TEL = ['Pichincha', 'Código: 5478', 'Teléfono: 0990000044', 'Monto: $200'].join(SALTO);
  // una fila de "Retiros Recientes": un retiro de este mismo grupo, de hace 2 minutos
  const antes = (texto, extra) => Object.assign({ mensaje_id: 'ANTES' + (++n), estado: 'publicado',
    fecha_mensaje: new Date(new Date(ABIERTO).getTime() - 2 * 60000).toISOString(), datos: entender(texto).datos }, extra || {});
  const avisos = r => r.envios.filter(e => e.etapa === 'aviso' && e.jid === AVISOS);

  let p = real(PICH_OTRO_TEL, { recientes: [antes(PICH)] });
  chk(bancos(p).length === 0, 'mismo banco y mismo codigo de hace 2 min -> NO se publica otra vez en el banco', '-> ' + bancos(p).length);
  chk(avisos(p).length === 1 && /MISMO código/.test(avisos(p)[0].texto) && /corrección/.test(avisos(p)[0].texto), '...y se avisa en avisos que parece una corrección', '-> ' + JSON.stringify(avisos(p).map(e => e.texto)));
  chk(!avisos(p).some(e => /5478/.test(e.texto)), '...sin escribir el codigo en el aviso');
  chk(sticker(p).length === 0 && clienteTxt(p).length === 0, '...y al cliente no se le manda nada (ni sticker)');
  chk(p.envios.every(e => e.estado_fila === 'repetido'), '...la fila queda en estado "repetido"', '-> ' + JSON.stringify(p.envios.map(e => e.estado_fila)));

  p = real(PICH, { recientes: [antes(PICH)] });
  chk(bancos(p).length === 0 && avisos(p).length === 1, 'el MISMO mensaje mandado dos veces (otro id) -> tampoco se publica dos veces');

  p = real(PICH_OTRO_TEL, { recientes: [antes(PICH, { estado: 'verificar' })] });
  chk(bancos(p).length === 1 && avisos(p).length === 0, 'si el banco lo devolvio con "Verificar", el corregido SI se publica (es a proposito)');

  p = real(PICH, { recientes: [antes(['Pichincha', 'Código: 5478', 'Monto: $200'].join(SALTO))] });
  chk(bancos(p).length === 1, 'si el de antes estaba INCOMPLETO (le faltaba el telefono), el completo SI se publica');

  p = real(PICH, { recientes: [antes(['Pichincha', 'Código: 1111', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO))] });
  chk(bancos(p).length === 1, 'otro codigo (aunque sea el mismo banco y monto) -> SI se publica');

  p = real(PICH, { recientes: [antes(['Produbanco', 'C.I: 1700000001', 'Código: 5478', 'Monto: 200$'].join(SALTO))] });
  chk(bancos(p).length === 1, 'el mismo numero en OTRO banco -> SI se publica');

  const GYE = c2 => ['Banco: Guayaquil', 'C1: 2403', 'C2: ' + c2, 'Teléfono: +593 99 000 0005', 'Monto: 500'].join(SALTO);
  p = real(GYE('9999'), { recientes: [antes(GYE('2790'))] });
  chk(bancos(p).length === 1, 'Guayaquil con UNO solo de los dos codigos igual -> SI se publica (son otros codigos)');
  p = real(GYE('2790'), { recientes: [antes(GYE('2790'))] });
  chk(bancos(p).length === 0 && avisos(p).length === 1, 'Guayaquil con los DOS codigos iguales -> no se publica otra vez');

  p = real(PICH, { recientes: [antes(PICH), { mensaje_id: 'ROTA', estado: 'publicado', fecha_mensaje: 'x', datos: '{no es json' }] });
  chk(bancos(p).length === 0 && avisos(p).length === 1, 'una fila rara en "Retiros Recientes" no rompe nada');

  const JEP = ['BANCO: Jep', 'Monto: $300', 'OTP: 796988', 'CI: 2100000006', 'Clave: 1111'].join(SALTO);
  p = real(JEP, { jep: CAJERO, recientes: [antes(JEP)] });
  chk(bancos(p).length === 1, 'JEP: el RST que espero al cobrador y se reenvia con el mismo codigo SI se publica');

  p = correr(PICH_OTRO_TEL, { recientes: [antes(PICH)] });
  chk(p.envios.length === 1 && p.envios[0].etapa === 'ensayo' && /MISMO código/.test(p.envios[0].texto) && !/iría a PICHINCHA/.test(p.envios[0].texto),
      'en ENSAYO la vista previa muestra el aviso de repetido (y no "iría a PICHINCHA")');
}

console.log('');
console.log('=== 17) EL CLIENTE EDITA UN MENSAJE: WhatsApp manda la edicion cifrada (26/11) ===');
{
  // Una edicion llega como secretEncryptedMessage: trae el id del mensaje original y el texto CIFRADO.
  // El bot no puede leer lo que quedo escrito, asi que pide que lo manden de nuevo.
  const editar = idOriginal => ({ extra: { mensaje: { secretEncryptedMessage: { targetMessageKey: { id: idOriginal } } } } });
  const PICH = ['Banco: Pichincha', 'Código: 4321', 'Teléfono: 0990000009', 'Monto: 150'].join(SALTO);
  const filaRst = { id: 931, mensaje_id: 'MSGRST1', tipo: 'rst', banco: 'Pichincha', estado: 'publicado',
                    fecha_mensaje: new Date(new Date(ABIERTO).getTime() - 60000).toISOString(),
                    datos: { n_registros: 1, registros: [{ tipo: 'rst', banco: 'Pichincha', monto_usd: 150, datos: { codigos: ['4321'], telefono: '0990000009' } }] } };

  const f = entender('', editar('MSGRST1').extra);
  chk(!!f && f.tipo === 'edicion' && f.datos.editado_id === 'MSGRST1', 'la edicion se registra con el id del mensaje que cambio', '-> ' + JSON.stringify(f && [f.tipo, f.datos.editado_id]));

  let p = correr('', Object.assign({ recientes: [filaRst] }, editar('MSGRST1')));
  chk(p.pasa, 'una edicion de un RST reciente llega a Decidir Publicacion');
  chk(p.envios.length === 1 && p.envios[0].etapa === 'ensayo' && /editó un retiro/.test(p.envios[0].texto) && /Pichincha/.test(p.envios[0].texto),
      'en ENSAYO sale la vista previa avisando que edito un retiro', '-> ' + JSON.stringify(p.envios.map(e => String(e.texto).slice(0, 70))));
  chk(p.envios[0].fila_id === 931 && p.envios[0].estado_fila === 'verificar',
      'el estado va a la fila del RST ORIGINAL (931) y queda en "verificar", aun en ensayo', '-> ' + JSON.stringify([p.envios[0].fila_id, p.envios[0].estado_fila]));

  const r = correr('', Object.assign({ recientes: [filaRst], modo: 'real' }, editar('MSGRST1')));
  const alCliente = r.envios.filter(e => e.etapa === 'cliente');
  chk(alCliente.length === 1 && alCliente[0].citar === 'MSGRST1' && /envíe los datos de nuevo/.test(alCliente[0].texto),
      'en REAL se le escribe al cliente citando el mensaje que edito', '-> ' + JSON.stringify(alCliente.map(e => String(e.texto).slice(0, 60))));
  chk(r.envios.some(e => e.etapa === 'aviso' && e.jid === AVISOS), 'y queda un aviso para que una persona lo revise');
  chk(!r.envios.some(e => DEST_DE(e.jid)), 'una edicion NUNCA publica nada en un grupo de banco');

  // Lo que se edita puede no ser un retiro: ahi no hay nada que corregir.
  chk(!correr('', Object.assign({ recientes: [filaRst] }, editar('OTRO-MSG'))).envios.length, 'si edito un mensaje que no es RST ni cuenta: el bot no dice nada');
  chk(!correr('', Object.assign({ recientes: [] }, editar('MSGRST1'))).envios.length, 'si no hay nada reciente que casar: el bot no dice nada');

  const cuenta = { id: 940, mensaje_id: 'MSGCTA1', tipo: 'beneficiario', banco: 'Venezuela', estado: 'visto',
                   fecha_mensaje: new Date(new Date(ABIERTO).getTime() - 60000).toISOString(), datos: {} };
  p = correr('', Object.assign({ recientes: [cuenta] }, editar('MSGCTA1')));
  chk(p.envios.length === 1 && /editó una cuenta/.test(p.envios[0].texto) && p.envios[0].fila_id === 940,
      'si lo que edito fue una CUENTA, el aviso lo dice y apunta a esa fila', '-> ' + JSON.stringify(p.envios.map(e => String(e.texto).slice(0, 70))));

  // El reenvio corregido no se puede rechazar como "repetido": por eso la fila vieja queda en 'verificar'.
  const viejaVerificar = Object.assign({}, filaRst, { estado: 'verificar' });
  const reenvio = correr(PICH, { modo: 'real', recientes: [viejaVerificar] });
  chk(reenvio.envios.some(e => DEST_DE(e.jid)), 'el RST que el cliente reenvia despues SI se publica (la fila vieja esta en verificar)',
      '-> ' + JSON.stringify(reenvio.envios.map(e => DEST_DE(e.jid)).filter(Boolean)));
}

console.log('');
console.log('=== 18) PEDIDOS A PAISES: solo VISTA PREVIA en avisos, aun en modo real (pedido de Kelvin, 26/11) ===');
{
  // Los grupos de paises de la tabla (en la tabla real se llaman asi, sin acentos).
  const PAISES = ['VENEZUELA', 'BANESCO', 'COLOMBIA', 'PERU', 'BINANCE'].map((nombre, i) => ({ grupo_jid: '1203630000000002' + String(10 + i) + '@g.us', nombre, tipo: 'destino', activo: true }));
  const CON_PAISES = { destinos: DESTINOS.concat(PAISES) };
  const ES_PAIS = jid => PAISES.some(p => p.grupo_jid === jid) || !!DEST_DE(jid);
  const VE = ['Banco de Venezuela', '01020000000000000001', 'Maria Prueba', 'CI 10000001', '100$'].join(SALTO);
  const BANESCO = ['01340000000000000002', 'Jose Prueba', 'V-10000002', 'Bs 50.000'].join(SALTO);
  const NEQUI = ['Nequi 3000000001', 'Pedro Prueba', 'cc 1000000001', '150.000 cop'].join(SALTO);
  const BILLETERA = 'TXyzPRUEBAprueba12345678901234567';
  // OJO: el RST tiene que tener el banco y el codigo en el MISMO renglon para que el lector lo separe de la cuenta que
  // viene despues ("Pichincha" solo en un renglon + la cuenta = se lee todo como UNA cuenta; limitacion conocida, 26/11).
  const PICH = ['Pichincha código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO);

  let p = correr(VE, CON_PAISES);
  chk(p.pasa, 'un pedido del cliente SI pasa el filtro "Hace Falta Publicar?"');
  chk(p.envios.length === 1 && p.envios[0].jid === AVISOS && p.envios[0].etapa === 'ensayo', 'en ENSAYO: una sola vista previa, en el grupo de avisos',
      '-> ' + JSON.stringify(p.envios.map(e => [e.etapa, e.jid])));
  const t = p.envios[0].texto;
  console.log('     ' + t.split(SALTO).join(SALTO + '     '));
  chk(/📦 PEDIDO → iría a VENEZUELA:/.test(t), 'dice a que grupo iria (VENEZUELA)');
  chk(t.indexOf('CLIENTE PRUEBA' + SALTO + 'Banco de Venezuela') !== -1, 'como lo pasa la operadora: el NOMBRE del cliente en mayusculas y debajo sus datos');
  chk(/01020000000000000001/.test(t) && /Maria Prueba/.test(t), 'con la cuenta y el titular tal cual los mando el cliente');
  chk(!/⚠️/.test(t), 'un pedido completo no lleva advertencias');

  chk(/iría a BANESCO:/.test(correr(BANESCO, CON_PAISES).envios[0].texto), 'una cuenta Banesco (0134) iria a BANESCO');
  chk(/iría a COLOMBIA:/.test(correr(NEQUI, CON_PAISES).envios[0].texto), 'un Nequi iria a COLOMBIA');
  p = correr(['Yape 900000001', 'Rosa Prueba', 'Perú', '105 soles'].join(SALTO), CON_PAISES);
  chk(/iría a PERÚ:/.test(p.envios[0].texto) && !/No hay grupo/.test(p.envios[0].texto), 'un Yape iria a PERU (el grupo sin acento de la tabla SI se encuentra)', '-> ' + p.envios[0].texto.split(SALTO)[2]);

  p = correr('USDT TRC20' + SALTO + BILLETERA, CON_PAISES);
  chk(/iría a BINANCE:/.test(p.envios[0].texto) && /Sin monto: falta que diga cuánto/.test(p.envios[0].texto), 'una billetera sin monto: va a BINANCE y avisa que falta el monto',
      '-> ' + JSON.stringify(p.envios[0].texto.split(SALTO).slice(-1)));

  p = correr(NEQUI, { destinos: DESTINOS.concat(PAISES.filter(x => x.nombre !== 'COLOMBIA')) });
  chk(/No hay grupo COLOMBIA en la tabla/.test(p.envios[0].texto), 'si el grupo del pais no esta en la tabla, lo dice');
  p = correr(['Uruguay', 'Cuenta 1234567890123', 'Ana Prueba', '100$'].join(SALTO), CON_PAISES);
  chk(p.envios.length === 1 && /Uruguay: no hay grupo para ese país/.test(p.envios[0].texto), 'un pais sin grupo (Uruguay): lo dice', '-> ' + JSON.stringify((p.envios[0] || {}).texto));

  // Dos cuentas en un mensaje
  p = correr(VE + SALTO + BANESCO, CON_PAISES);
  chk(/📦 PEDIDO \(2 cuentas\) → iría a VENEZUELA y BANESCO:/.test(p.envios[0].texto), 'dos cuentas en un mensaje: las dos, cada una a su grupo', '-> ' + p.envios[0].texto.split(SALTO)[2]);

  // EN REAL tampoco se publica nada en un grupo de pais (todavia no se decidio cuando: ¿al confirmar el pago?)
  p = correr(VE, Object.assign({ modo: 'real' }, CON_PAISES));
  chk(p.envios.length === 1 && p.envios[0].jid === AVISOS && /🧪 ENSAYO/.test(p.envios[0].texto) && /📦 PEDIDO/.test(p.envios[0].texto),
      'en modo REAL un pedido sigue siendo SOLO vista previa en avisos', '-> ' + JSON.stringify(p.envios.map(e => [e.etapa, e.jid])));
  chk(!p.envios.some(e => ES_PAIS(e.jid)), 'y NUNCA va a un grupo de pais ni de banco');
  chk(!p.envios.some(e => e.soloEnsayo), 'la marca interna "soloEnsayo" no sale del nodo');
  chk(p.envios[0].estado_fila === 'ensayo', 'la fila del pedido queda en "ensayo"', '-> ' + p.envios[0].estado_fila);

  // Un RST y un pedido en el MISMO mensaje, en real: el RST se publica; el pedido, solo vista previa.
  p = correr(PICH + SALTO + SALTO + VE, Object.assign({ modo: 'real' }, CON_PAISES));
  const alBanco = p.envios.filter(e => e.etapa === 'banco');
  const previa = p.envios.filter(e => e.jid === AVISOS && /📦 PEDIDO/.test(e.texto));
  chk(alBanco.length === 1 && DEST_DE(alBanco[0].jid) === 'PICHINCHA', 'RST + pedido en real: el RST SI va a PICHINCHA', '-> ' + JSON.stringify(p.envios.map(e => [e.etapa, DEST_DE(e.jid) || e.jid])));
  chk(previa.length === 1 && !/Pichincha/i.test(previa[0].texto.split('📦')[0].split(SALTO).slice(2).join(' ')), 'y el pedido va aparte, solo como vista previa');
  chk(!p.envios.some(e => PAISES.some(x => x.grupo_jid === e.jid)), 'ningun mensaje a un grupo de pais');

  // Lo que escribe la operadora o Kelvin en el grupo del cliente NO es un pedido del cliente.
  chk(!correr(VE, Object.assign({ extra: { numero: '593990000003' } }, CON_PAISES)).envios.length, 'la cuenta que escribe la OPERADORA en el grupo no dispara nada');
  chk(!correr(VE, Object.assign({ extra: { fromMe: true, numero: '' } }, CON_PAISES)).envios.length, 'ni la que escribe Kelvin');
  // Y en un grupo de DESTINO tampoco (ahi el equipo publica los pedidos).
  chk(!correr(VE, Object.assign({ grupo: Object.assign({}, BANCO_GRUPO, { nombre: 'VENEZUELA' }) }, CON_PAISES)).envios.length, 'un pedido publicado en un grupo de pais no dispara nada');
}

console.log('');
console.log('=== 19) LA "LLAVE DEL GRUPO" pegada al mensaje NO lo tira (bug encontrado el 26/11) ===');
{
  // WhatsApp le pega la llave del grupo (senderKeyDistributionMessage) al PRIMER mensaje que alguien manda en un rato.
  // El bot tiraba ese mensaje entero: en 48 h se perdieron ~200, entre ellos 8 RST y 8 pedidos de clientes.
  const LLAVE = { senderKeyDistributionMessage: { groupId: '120363000000000001@g.us', axolotlSenderKeyDistributionMessage: 'AAAA' }, messageContextInfo: {} };
  const PICH1 = ['Pichincha código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO);
  let f = entender('', { mensaje: Object.assign({ conversation: PICH1 }, LLAVE) });
  chk(f && f.tipo === 'rst', 'un RST con la llave pegada SI se lee', '-> ' + (f && f.tipo));
  const p = correr('', { modo: 'real', extra: { mensaje: Object.assign({ conversation: PICH1 }, LLAVE) } });
  chk(p.envios.some(e => DEST_DE(e.jid) === 'PICHINCHA'), 'y en real se publica en su banco, como cualquier RST');
  f = entender('', { mensaje: Object.assign({ conversation: ['Nequi 3000000001', 'Pedro Prueba', '150.000 cop'].join(SALTO) }, LLAVE) });
  chk(f && f.tipo === 'beneficiario', 'un pedido con la llave pegada SI se lee', '-> ' + (f && f.tipo));
  f = entender('', { mensaje: Object.assign({ imageMessage: { caption: '' } }, LLAVE) });
  chk(f && f.tipo === 'captura', 'una foto con la llave pegada SI se registra');
  chk(entender('', { mensaje: LLAVE }) === null, 'la llave SOLA (sin texto, foto ni audio) se sigue ignorando');
  chk(entender('', { mensaje: Object.assign({ stickerMessage: {} }, LLAVE) }) === null, 'un sticker con la llave se sigue ignorando');
}

console.log('');
console.log('=== 20) BANCO MAL ESCRITO: "¿Su retiro es de Produbanco?" y el si / no del cliente (Julio E, 26/11) ===');
{
  // Caso real (datos inventados): "*produbaco*" con todo lo demas bien. Antes el RST se perdia entero.
  const PRODUBACO = ['*produbaco*', 'marquez', '', ' monto  350$', 'cedula  1700000011', 'clave 167688', 'celular  0990000012'].join(SALTO);
  let f = entender(PRODUBACO);
  let r = reg0(f);
  chk(f.tipo === 'rst' && r.banco === 'Produbanco' && r.datos.banco_dudoso === 'produbaco' && r.monto_usd === 350, '"produbaco" se lee como un RST de Produbanco, marcado como dudoso',
      '-> ' + JSON.stringify(r && { tipo: r.tipo, banco: r.banco, dudoso: r.datos.banco_dudoso, usd: r.monto_usd }));
  let p = real(PRODUBACO);
  chk(p.pasa && bancos(p).length === 0 && sticker(p).length === 0, 'NO se publica en el banco todavia (ni sticker)', '-> ' + JSON.stringify(p.envios.map(e => e.etapa)));
  chk(clienteTxt(p).length === 1 && clienteTxt(p)[0].texto === '¿Su retiro de 350$ es de Produbanco? Responda sí o no, por favor.' && clienteTxt(p)[0].citar,
      'al cliente, citando su mensaje: "¿Su retiro de 350$ es de Produbanco? Responda sí o no"', '-> ' + JSON.stringify(clienteTxt(p).map(e => e.texto)));
  chk(p.envios.every(e => e.estado_fila === 'confirmar_banco'), 'la fila queda en "confirmar_banco"', '-> ' + JSON.stringify(p.envios.map(e => e.estado_fila)));
  p = correr(PRODUBACO);
  chk(p.envios.length === 1 && p.envios[0].jid === AVISOS && /Responda sí o no/.test(p.envios[0].texto) && /escribió "produbaco"/.test(p.envios[0].texto)
      && p.envios[0].estado_fila === 'confirmar_banco', 'en ENSAYO: la pregunta va como vista previa y la fila igual queda en "confirmar_banco"', '-> ' + JSON.stringify(p.envios.map(e => [e.jid, e.estado_fila])));

  // Otras letras comidas, de mas o volteadas
  const otros = [['pichinca', 'Pichincha', ['pichinca', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200']],
                 ['pinchincha', 'Pichincha', ['Banco pinchincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200']],
                 ['guayaqil', 'Guayaquil', ['guayaqil', 'C1: 2403', 'C2: 2790', 'Teléfono: 0990000005', 'Monto: 500']],
                 ['guallaquil (2 letras en un nombre largo)', 'Guayaquil', ['guallaquil', 'C1: 2403', 'C2: 2790', 'Teléfono: 0990000005', 'Monto: 500']],
                 ['pacfico', 'Pacífico', ['pacfico', 'Monto: 100$', 'Código: 474927', 'Cedula: 0900000002', 'Teléfono: 0990000003']],
                 ['bolivarino', 'Bolivariano', ['Banco bolivarino', 'Monto: 380', 'Código: 068521', 'Celular: 0990000009', 'Cédula: 0900000010']]];
  for (const [et, banco, lineas] of otros){
    const x = reg0(entender(lineas.join(SALTO)));
    chk(x && x.tipo === 'rst' && x.banco === banco && !!x.datos.banco_dudoso, '"' + et + '" -> ' + banco + ' (dudoso)', '-> ' + JSON.stringify(x && { banco: x.banco, d: x.datos.banco_dudoso }));
  }
  // El banco bien escrito NO pregunta nada
  const BIEN = ['Produbanco', 'monto 350$', 'cedula 1700000011', 'clave 167688', 'celular 0990000012'].join(SALTO);
  chk(!reg0(entender(BIEN)).datos.banco_dudoso && bancos(real(BIEN)).length === 1, 'bien escrito: se publica directo, sin preguntar');
  // Una cuenta de Venezuela con "Bolivariana" no se vuelve un RST de Bolivariano
  const VE = ['Banco de Venezuela', '01020000000000000001', 'Republica Bolivariana', 'Maria Prueba', 'CI 10000001', '100$'].join(SALTO);
  chk(reg0(entender(VE)).tipo === 'beneficiario', '"República Bolivariana" en una cuenta de Venezuela sigue siendo una cuenta');
  // Incompleto y mal escrito: se piden los datos que faltan (el mensaje ya nombra el banco) y no se pregunta si/no
  p = real(['produbaco', 'monto 350$', 'clave 167688'].join(SALTO));
  chk(clienteTxt(p).length === 1 && /^Faltan estos datos para tu RST de Produbanco: la cédula/.test(clienteTxt(p)[0].texto), 'mal escrito e incompleto: se le piden los datos que faltan', '-> ' + JSON.stringify(clienteTxt(p).map(e => e.texto)));

  // ---------- el cliente contesta ----------
  const pendiente = (extra) => Object.assign({ id: 501, mensaje_id: 'PREGUNTADO1', tipo: 'rst', banco: 'Produbanco', autor_rol: 'cliente', estado: 'confirmar_banco',
    fecha_mensaje: new Date(new Date(ABIERTO).getTime() - 3 * 60000).toISOString(), datos: entender(PRODUBACO).datos }, extra || {});
  for (const si of ['si', 'Sí', 'siii', 'Si señor', 'claro', 'correcto', '👍']){
    p = real(si, { recientes: [pendiente()] });
    chk(p.pasa && bancos(p).length === 1 && DEST_DE(bancos(p)[0].jid) === 'PRODUBANCO', '"' + si + '" -> se publica en PRODUBANCO', '-> ' + JSON.stringify(p.envios.map(e => e.etapa)));
  }
  p = real('si', { recientes: [pendiente()] });
  chk(sticker(p).length === 1, '...con su sticker "RST Recibido"');
  chk(/\(Cliente Prueba\nPRODUBANCO\nMonto: 350\$\nCódigo: 167688/.test(bancos(p)[0].texto), '...con el bloque de siempre (PRODUBANCO bien escrito)', '-> ' + JSON.stringify(bancos(p)[0].texto));
  chk(bancos(p)[0].mapa.id_msg_cliente === 'PREGUNTADO1' && bancos(p)[0].mapa.fila_id === 501, '...y el banco queda conectado con el mensaje ORIGINAL del retiro (para el "Verificar")', '-> ' + JSON.stringify(bancos(p)[0].mapa));
  chk(p.envios.every(e => e.fila_id === 501 && e.estado_fila === 'publicado'), '...la fila del retiro (no la del "si") queda "publicado"', '-> ' + JSON.stringify(p.envios.map(e => [e.fila_id, e.estado_fila])));
  chk(!!bancos(p)[0].vigila, '...y se vigila su vencimiento');
  p = correr('si', { recientes: [pendiente()] });
  chk(p.envios.length === 1 && p.envios[0].jid === AVISOS && /iría a PRODUBANCO/.test(p.envios[0].texto) && p.envios[0].fila_id === 501 && p.envios[0].estado_fila === 'ensayo',
      'en ENSAYO: el "si" muestra la publicacion como vista previa y la fila queda en "ensayo"', '-> ' + JSON.stringify(p.envios.map(e => [e.fila_id, e.estado_fila])));

  for (const no of ['no', 'No', 'nop', 'negativo']){
    p = real(no, { recientes: [pendiente()] });
    chk(bancos(p).length === 0 && clienteTxt(p).length === 1 && /verifique, corrija y envíe nuevamente/.test(clienteTxt(p)[0].texto) && clienteTxt(p)[0].citar === 'PREGUNTADO1',
        '"' + no + '" -> no se publica; se le pide que lo mande de nuevo (citando su retiro)', '-> ' + JSON.stringify(p.envios.map(e => e.texto)));
  }
  p = real('no', { recientes: [pendiente()] });
  chk(p.envios.every(e => e.fila_id === 501 && e.estado_fila === 'verificar'), '...y la fila del retiro queda en "verificar"');

  // Lo que NO es la respuesta
  chk(!real('si', { recientes: [] }).envios.length, '"si" sin ninguna pregunta pendiente: no pasa nada');
  chk(!real('si', { recientes: [pendiente({ estado: 'publicado' })] }).envios.length, '"si" si el ultimo retiro ya estaba publicado: no pasa nada');
  chk(!real('si', { recientes: [pendiente(), pendiente({ id: 502, mensaje_id: 'OTRO', estado: 'publicado', fecha_mensaje: new Date(new Date(ABIERTO).getTime() - 60000).toISOString() })] }).envios.length,
      '"si" si DESPUES de la pregunta mando otro retiro: no se toca el viejo');
  chk(!real('no se', { recientes: [pendiente()] }).envios.length, '"no sé" no es un no');
  chk(!real('no tengo el codigo todavia, ya se lo paso apenas me llegue', { recientes: [pendiente()] }).envios.length, 'un mensaje largo que empieza con "no" no es la respuesta');
  chk(!real('si', { recientes: [pendiente()], extra: { numero: '593990000003' } }).envios.length, 'el "si" de la OPERADORA no cuenta');
  // Un RST nuevo (bien escrito) mientras hay una pregunta pendiente: se trata normal
  p = real(['Pichincha', 'Código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO), { recientes: [pendiente()] });
  chk(bancos(p).length === 1 && DEST_DE(bancos(p)[0].jid) === 'PICHINCHA' && p.envios.every(e => e.fila_id === 77), 'un RST nuevo con la pregunta pendiente: se publica el nuevo, normal');
  // El retiro que espera la respuesta no cuenta como "repetido" de otro
  p = real(BIEN, { recientes: [pendiente()] });
  chk(bancos(p).length === 1, 'si lo reenvia bien escrito (mismo codigo) mientras espera: SI se publica, no es "repetido"');
  // Editar el mensaje que se le pregunto: se le pide que lo mande de nuevo (como cualquier edicion)
  p = real('', { recientes: [pendiente()], extra: { mensaje: { secretEncryptedMessage: { targetMessageKey: { id: 'PREGUNTADO1' } } } } });
  chk(clienteTxt(p).length === 1 && /editó su mensaje/.test(clienteTxt(p)[0].texto) && p.envios.every(e => e.fila_id === 501), 'si edita el mensaje que se le pregunto: se le pide que lo mande de nuevo');

  // Mal escrito junto con otro retiro en el MISMO mensaje: se publica el bueno y del dudoso se pide revisar
  p = real(['Pichincha código: 5478', 'Teléfono: 0990000004', 'Monto: $200', '', 'produbaco cedula 1700000011 clave 167688 monto 350$'].join(SALTO));
  chk(bancos(p).length === 1 && DEST_DE(bancos(p)[0].jid) === 'PICHINCHA', 'mal escrito junto con otro retiro: el bueno SI se publica', '-> ' + JSON.stringify(p.envios.map(e => [e.etapa, DEST_DE(e.jid)])));
  chk(clienteTxt(p).length === 1 && /produbaco/.test(clienteTxt(p)[0].texto) && !/Responda sí o no/.test(clienteTxt(p)[0].texto), '...y del mal escrito se le pide revisarlo (sin pregunta si/no)', '-> ' + JSON.stringify(clienteTxt(p).map(e => e.texto)));
  chk(p.envios.every(e => e.estado_fila !== 'confirmar_banco'), '...y la fila no queda esperando respuesta');

  // ---------- parece un RST pero no dice el banco ----------
  const SIN = ['RST', 'monto 200$', 'codigo 5478', 'celular 0990000004'].join(SALTO);
  r = reg0(entender(SIN));
  chk(r && r.tipo === 'rst' && r.banco === null && r.datos.sin_banco === true, 'un RST sin banco se registra (sin_banco)', '-> ' + JSON.stringify(r && { tipo: r.tipo, banco: r.banco }));
  p = real(SIN);
  chk(bancos(p).length === 0 && clienteTxt(p).length === 1 && /^¿Ese mensaje es un RST\? No reconocí de qué banco es/.test(clienteTxt(p)[0].texto), '...y se le pregunta: "¿Ese mensaje es un RST? No reconocí de qué banco es..."',
      '-> ' + JSON.stringify(p.envios.map(e => e.texto)));
  chk(!real(['monto 200$', 'celular 0990000004'].join(SALTO)).envios.length, 'un celular y un monto sin codigo ni "RST": no se pregunta nada (puede ser cualquier cosa)');
  chk(reg0(entender(['Nequi 3000000001', 'Pedro Prueba', 'cc 1000000001', '150.000 cop'].join(SALTO))).tipo === 'beneficiario', 'una cuenta (Nequi) sigue siendo una cuenta');
  chk(!real('Retiro de 200$ por favor, codigo 5478 mi correo es prueba@example.com 0990000004').envios.some(e => /No reconocí/.test(e.texto || '')), 'con un correo no se toma como RST sin banco');
}

console.log('');
console.log('=== 21) REVISION DEL 27/11: monto pegado al banco, Guayaquil sin banco, pedido en varios mensajes y Brasil con CPF ===');
{
  // ---------- a) el monto pegado al nombre del banco (caso real, 26/11) ----------
  // Los pedazos del celular ("099 000 0004") tenian numeros de 3 cifras que tapaban el monto.
  const MONTO_PEGADO = ['Pichincha 140', '099 000 0004', 'Codigo 5478'].join(SALTO);
  let r = reg0(entender(MONTO_PEGADO));
  chk(r && r.banco === 'Pichincha' && r.monto_usd === 140, '"Pichincha 140 / 099 000 0004 / Codigo 5478": el 140 es el monto', '-> ' + JSON.stringify(r && { banco: r.banco, usd: r.monto_usd }));
  let p = real(MONTO_PEGADO);
  chk(bancos(p).length === 1 && DEST_DE(bancos(p)[0].jid) === 'PICHINCHA', '...y se publica en PICHINCHA', '-> ' + JSON.stringify(p.envios.map(e => e.texto)));
  p = real(['Pichincha', '099 000 0004', 'Codigo 5478'].join(SALTO));
  chk(bancos(p).length === 0 && clienteTxt(p).length === 1 && /el monto/.test(clienteTxt(p)[0].texto), 'sin monto de verdad: se le sigue pidiendo el monto', '-> ' + JSON.stringify(p.envios.map(e => e.texto)));
  p = real(['Produbanco 300', 'Cedula 1700000011', 'Codigo 175588'].join(SALTO));
  chk(bancos(p).length === 1 && /Monto: 300\$/.test(bancos(p)[0].texto), 'sin celular tambien: "Produbanco 300" -> monto 300', '-> ' + JSON.stringify(p.envios.map(e => e.texto)));

  // ---------- b) no dice el banco, pero trae 2 codigos de 4 cifras = Guayaquil (caso real, 27/11) ----------
  const SIN_BANCO_2COD = ['Primer Código: 2403', '', 'Segundo Código: 2790', '', 'Cedula: 0900000010', '', 'Celular: 0990000005', '', '$470'].join(SALTO);
  r = reg0(entender(SIN_BANCO_2COD));
  chk(r && r.tipo === 'rst' && r.banco === 'Guayaquil' && r.datos.banco_deducido === true && r.monto_usd === 470, '2 códigos de 4 sin banco: se lee como Guayaquil (deducido)',
      '-> ' + JSON.stringify(r && { banco: r.banco, d: r.datos.banco_deducido, usd: r.monto_usd }));
  p = real(SIN_BANCO_2COD);
  chk(bancos(p).length === 0 && sticker(p).length === 0, '...NO se publica sin preguntar');
  chk(clienteTxt(p).length === 1 && clienteTxt(p)[0].texto === '¿Su retiro de 470$ es de Guayaquil? Responda sí o no, por favor.' && clienteTxt(p)[0].citar,
      '...se le pregunta "¿Su retiro de 470$ es de Guayaquil? Responda sí o no"', '-> ' + JSON.stringify(clienteTxt(p).map(e => e.texto)));
  chk(p.envios.every(e => e.estado_fila === 'confirmar_banco'), '...y la fila queda en "confirmar_banco"');
  p = correr(SIN_BANCO_2COD);
  chk(p.envios.length === 1 && /no dijo el banco, pero 2 códigos de 4 cifras son de Guayaquil/.test(p.envios[0].texto), 'en ENSAYO la vista previa dice por qué pregunta', '-> ' + JSON.stringify(p.envios.map(e => e.texto)));
  const PEND = { id: 601, mensaje_id: 'GYE1', tipo: 'rst', banco: 'Guayaquil', autor_rol: 'cliente', estado: 'confirmar_banco',
                 fecha_mensaje: new Date(new Date(ABIERTO).getTime() - 2 * 60000).toISOString(), datos: entender(SIN_BANCO_2COD).datos };
  p = real('si', { recientes: [PEND] });
  chk(bancos(p).length === 1 && DEST_DE(bancos(p)[0].jid) === 'GUAYAQUIL' && /C1: 2403/.test(bancos(p)[0].texto), 'con su "sí" se publica en GUAYAQUIL', '-> ' + JSON.stringify(p.envios.map(e => [e.etapa, DEST_DE(e.jid)])));
  p = real('no', { recientes: [PEND] });
  chk(bancos(p).length === 0 && clienteTxt(p).length === 1 && /verifique, corrija/.test(clienteTxt(p)[0].texto), 'con un "no" se le pide que lo mande de nuevo');

  // ---------- el recordatorio despues del "sí": "Por favor, siempre colócale el nombre del banco." (pedido de Kelvin, 27/11) ----------
  const T0 = new Date(ABIERTO).getTime(), HACE = dias => T0 - dias * 86400000;
  const recordatorio = q => clienteTxt(q).filter(e => /nombre del banco\.$/.test(e.texto));
  p = real('si', { recientes: [PEND], sinBanco: [HACE(0.01)] });
  chk(recordatorio(p).length === 1 && recordatorio(p)[0].texto === 'Por favor, siempre colócale el nombre del banco.' && recordatorio(p)[0].citar === 'GYE1',
      'con el "sí": se publica y se le deja "Por favor, siempre colócale el nombre del banco." (citando su retiro)', '-> ' + JSON.stringify(clienteTxt(p).map(e => e.texto)));
  chk(p.envios.findIndex(e => e.etapa === 'banco') < p.envios.findIndex(e => e === recordatorio(p)[0]), '...despues de publicarlo en el banco');
  p = real('si', { recientes: [PEND], sinBanco: [HACE(3), HACE(0.01)] });
  chk(recordatorio(p).length === 1 && /^Por favor/.test(recordatorio(p)[0].texto), '2 veces en 7 días: sigue el "Por favor"');
  p = real('si', { recientes: [PEND], sinBanco: [HACE(5), HACE(2), HACE(0.01)] });
  chk(recordatorio(p).length === 1 && recordatorio(p)[0].texto === 'Es obligatorio que le coloques el nombre del banco.', 'la 3ra vez en 7 días: "Es obligatorio que le coloques el nombre del banco."',
      '-> ' + JSON.stringify(clienteTxt(p).map(e => e.texto)));
  p = real('si', { recientes: [PEND], sinBanco: [HACE(20), HACE(10), HACE(0.01)] });
  chk(recordatorio(p).length === 1 && /^Por favor/.test(recordatorio(p)[0].texto), 'las de hace más de 7 días no cuentan');
  p = correr('si', { recientes: [PEND], sinBanco: [HACE(5), HACE(2), HACE(0.01)] });
  chk(p.envios.length === 1 && /Es obligatorio que le coloques el nombre del banco/.test(p.envios[0].texto) && /ya van 3 veces/.test(p.envios[0].texto), 'en ENSAYO la vista previa muestra el recordatorio');
  // se cuenta cada RST sin el nombre del banco (tambien el de "¿de qué banco es?")
  const anota = q => (q.envios.flatMap(e => e.redisSet || []).find(s => /^sinBanco:/.test(s.clave)) || null);
  p = real(SIN_BANCO_2COD, { sinBanco: [HACE(2)] });
  let s = anota(p);
  chk(!!s && s.clave === 'sinBanco:' + GRUPO.grupo_jid && JSON.parse(s.valor).length === 2 && s.ttl === 7 * 24 * 3600, 'al preguntar "¿es de Guayaquil?" se anota la vez (7 días)', '-> ' + JSON.stringify(s));
  s = anota(correr(SIN_BANCO_2COD));
  chk(!!s && JSON.parse(s.valor).length === 1, '...tambien en ENSAYO');
  chk(!!anota(real(['RST', 'monto 200$', 'codigo 5478', 'celular 0990000004'].join(SALTO))), 'un RST sin banco (pregunta general) tambien cuenta');
  chk(!anota(real(['Pichincha código: 5478', 'Teléfono: 0990000004', 'Monto: $200'].join(SALTO))), 'un RST con su banco no cuenta');
  chk(!anota(real('si', { recientes: [PEND] })), 'el "sí" no cuenta otra vez');
  // el banco MAL ESCRITO ("produbaco") no lleva recordatorio: el nombre si lo puso
  const PEND2 = Object.assign({}, PEND, { mensaje_id: 'PRODU1', banco: 'Produbanco',
    datos: entender(['*produbaco*', 'monto 350$', 'cedula 1700000011', 'clave 167688', 'celular 0990000012'].join(SALTO)).datos });
  chk(!recordatorio(real('si', { recientes: [PEND2] })).length, 'el "sí" a un banco mal escrito ("produbaco") no lleva recordatorio');
  p = real(['RST', 'monto 200$', 'codigo 5478', 'celular 0990000004'].join(SALTO));
  chk(clienteTxt(p).length === 1 && /^¿Ese mensaje es un RST\?/.test(clienteTxt(p)[0].texto), 'un solo código sin banco: sigue la pregunta general');
  p = real(['RST', 'monto 200$', 'codigo 175588', 'codigo 175599', 'celular 0990000004'].join(SALTO));
  chk(clienteTxt(p).length === 1 && /^¿Ese mensaje es un RST\?/.test(clienteTxt(p)[0].texto), 'dos códigos de 6 sin banco: no se adivina');

  // ---------- d) Brasil: la llave PIX es el mismo numero de la cedula (CPF) (caso real, 26/11) ----------
  const BRASIL = ['Cuenta: Inter ', '123.456.789.42', 'Nombre: Pedro Prueba Rivera', 'Cédula: 12345678942', 'Brasil 🇧🇷', '20$', 'Tasa 5.40', '108'].join(SALTO);
  r = reg0(entender(BRASIL));
  chk(r && r.tipo === 'beneficiario' && r.pais === 'Brasil' && r.monto_usd === 20 && r.datos.destino_sugerido === 'BRASIL', 'cuenta de Brasil con el CPF igual a la cédula: es un pedido a BRASIL (antes: "pregunta")',
      '-> ' + JSON.stringify(r && { tipo: r.tipo, pais: r.pais, usd: r.monto_usd }));
  chk(entender(['Hay tasa para Brasil hoy?', 'Cédula: 12345678942'].join(SALTO)).tipo !== 'beneficiario', 'una pregunta de Brasil con una cédula no es un pedido');

  // ---------- c) un pedido en VARIOS mensajes del mismo cliente (casos reales, 26/11) ----------
  const PAISES = ['BINANCE', 'VENEZUELA', 'ZELLE'].map((nombre, i) => ({ grupo_jid: '1203630000000003' + String(10 + i) + '@g.us', nombre, tipo: 'destino', activo: true }));
  const CON = extra => Object.assign({ destinos: DESTINOS.concat(PAISES) }, extra || {});
  const BILL = 'Tabcdefghijkmnopqrstuvwxyz12345678';                     // billetera inventada
  const BIN = ['BINANCE 🔶', '', 'prueba.cliente@example.com', '', BILL].join(SALTO);
  const MONTO = ['Pedido USDT ', '', '300$'].join(SALTO);
  const fila = (texto, extra) => Object.assign({ id: 700 + (++n), estado: 'visto' }, entender(texto, extra));
  const previa = q => (q.envios.find(e => /📦 PEDIDO/.test(e.texto || '')) || {}).texto || '';

  let f = entender(MONTO);
  chk(f.tipo === 'otro' && f.datos.pieza && f.datos.pieza.clase === 'monto' && f.datos.pieza.monto_usd === 300 && f.datos.pieza.destino_sugerido === 'BINANCE',
      '"Pedido USDT / 300$" es un PEDAZO de pedido: monto 300$, Binance', '-> ' + JSON.stringify(f.datos.pieza));
  p = correr(MONTO, CON());
  chk(p.pasa && !p.envios.length, 'solo (sin la cuenta al lado) no manda nada todavia');
  // el monto primero y la billetera despues
  p = correr(BIN, CON({ recientes: [fila(MONTO)] }));
  let t = previa(p);
  chk(/📦 PEDIDO \(junté 2 mensajes\) → iría a BINANCE:/.test(t) && /300\$/.test(t) && t.indexOf(BILL) !== -1 && !/Sin monto/.test(t),
      'monto + billetera (en 2 mensajes): UN pedido a BINANCE con los 300$', '-> ' + JSON.stringify(t));
  chk(t.indexOf('Pedido USDT') < t.indexOf('BINANCE 🔶'), '...con los textos en el orden en que llegaron');
  // la billetera primero (sale "sin monto") y el monto despues (sale el pedido entero)
  p = correr(BIN, CON());
  chk(/Sin monto/.test(previa(p)), 'la billetera sola: sale "sin monto" (como antes)');
  p = correr(MONTO, CON({ recientes: [fila(BIN)] }));
  t = previa(p);
  chk(/junté 2 mensajes\) → iría a BINANCE/.test(t) && /300\$/.test(t) && !/Sin monto/.test(t), 'billetera + monto despues: sale el pedido entero', '-> ' + JSON.stringify(t));
  // tres mensajes: billetera, correo y monto
  const SOLO_BILL = BILL, CORREO = 'prueba.cliente@example.com', CINCUENTA = '50$';
  chk((entender(CORREO).datos.pieza || {}).clase === 'correo', 'un correo solo es un pedazo (correo)');
  p = correr(CINCUENTA, CON({ recientes: [fila(SOLO_BILL), fila(CORREO)] }));
  t = previa(p);
  chk(/junté 3 mensajes\) → iría a BINANCE/.test(t) && /50\$/.test(t) && t.indexOf(CORREO) !== -1, 'billetera + correo + monto (3 mensajes): UN pedido a BINANCE', '-> ' + JSON.stringify(t));
  // correo + monto: el pais lo pone el monto ("USDT")
  p = correr('USDT 120$', CON({ recientes: [fila(CORREO)] }));
  chk(/junté 2 mensajes\) → iría a BINANCE/.test(previa(p)), 'correo + "USDT 120$": a BINANCE', '-> ' + JSON.stringify(previa(p)));
  p = correr('120$', CON({ recientes: [fila(CORREO)] }));
  chk(/sin país claro/.test(previa(p)), 'correo + "120$" (sin decir Binance ni Zelle): avisa que no sabe el país', '-> ' + JSON.stringify(previa(p)));
  // lo que NO se junta
  const lejos = fila(MONTO); lejos.fecha_mensaje = new Date(Date.parse(lejos.fecha_mensaje) - 5 * 60000).toISOString();
  chk(/Sin monto/.test(previa(correr(BIN, CON({ recientes: [lejos] })))), 'con mas de 3 minutos entre uno y otro: no se juntan');
  chk(/Sin monto/.test(previa(correr(BIN, CON({ recientes: [fila(MONTO, { numero: '593990000003' })] })))), 'el monto que escribe la OPERADORA no se junta con la cuenta del cliente');
  const VE_COMPLETA = ['Banco de Venezuela', '01020000000000000001', 'Maria Prueba', 'CI 10000001', '100$'].join(SALTO);
  p = correr(MONTO, CON({ recientes: [fila(VE_COMPLETA)] }));
  chk(!p.envios.length, 'un monto despues de una cuenta que YA traia su monto: no se junta (nada que completar)');
  // dos cuentas, cada una con su monto: no se cruzan
  const c1 = fila(BIN), m1 = fila(MONTO), c2 = fila(['Zelle', 'otra.persona@example.com', 'Ana Prueba'].join(SALTO));
  p = correr(MONTO, CON({ recientes: [c1, m1, c2] }));
  t = previa(p);
  chk(/→ iría a ZELLE/.test(t) && t.indexOf('otra.persona@example.com') !== -1 && t.indexOf(BILL) === -1, 'cuenta1 + monto1 + cuenta2 + monto2: el 2do monto va con la 2da cuenta', '-> ' + JSON.stringify(t));
  p = correr(VE_COMPLETA.replace('100$', ''), CON({ recientes: [c1, m1] }));
  chk(/Sin monto/.test(previa(p)) && !/junté/.test(previa(p)), 'un monto ya usado no se vuelve a usar para otra cuenta', '-> ' + JSON.stringify(previa(p)));
  // los pedazos que no son pedazos
  for (const no of ['De casualidad le queda para 300$ en USDT?', 'Voy a pasar retiro por 300$', 'ya te pague 300$', 'Buenos dias', 'Solo falta 238$', 'quedan 50$ pendientes']){
    chk(!(entender(no).datos || {}).pieza, '"' + no + '" no es un pedazo de pedido');
  }
  // en modo REAL el pedido juntado sigue siendo solo vista previa
  p = correr(BIN, CON({ modo: 'real', recientes: [fila(MONTO)] }));
  chk(p.envios.length === 1 && p.envios[0].jid === AVISOS && /junté 2 mensajes/.test(p.envios[0].texto), 'en modo REAL el pedido juntado sigue siendo solo vista previa en avisos',
      '-> ' + JSON.stringify(p.envios.map(e => [e.etapa, e.jid])));
  // un saludo editado no dispara nada (ahora "Retiros Recientes" tambien trae las filas 'otro')
  p = real('', { recientes: [Object.assign(fila('Buenos dias'), { mensaje_id: 'SALUDO1' })], extra: { mensaje: { secretEncryptedMessage: { targetMessageKey: { id: 'SALUDO1' } } } } });
  chk(!p.envios.length, 'editar un saludo sigue sin disparar nada');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
