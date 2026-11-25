
const _strip = s => s ? String(s).replace(/^\d+[\w\.]*\s*/, '') : '';
const _findNode = (nodes, n) => (nodes || []).find(x => x.name === n || _strip(x.name) === _strip(n));
const _getConn = (conns, n) => {
  if (!conns) return null;
  const k = Object.keys(conns).find(x => x === n || _strip(x) === _strip(n));
  return k ? Reflect.get(conns, k) : null;
};
// Prueba de "Entender Mensaje" (Mayor, Fase 1): como el bot entiende lo que escriben en los grupos de clientes.
//
// Las muestras son INVENTADAS pero imitan los formatos reales que se vieron en los grupos (el repositorio
// es publico: nada de cuentas, cedulas, telefonos ni nombres reales).
//
// Lo que se vigila:
//   - quien escribio (cliente, operador extra, operadora, Kelvin)
//   - RST / RCT de los bancos de Ecuador, con banco, telefono, claves y monto
//   - beneficiarios por pais (Venezuela, Colombia, Brasil, Peru, Chile, Zelle, USDT...) con sus montos
//   - que el pais NUNCA se asuma
//   - que nuestras propias cuentas y tasas (Kelvin / operadora) no se tomen por pedidos del cliente
//
// Correr con:  node test_mayor_parser.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_mayor.json', 'utf8').replace(/^﻿/, ''));
const nodo = n => _findNode(wf.nodes, n);
const code = n => nodo(n).parameters.jsCode;
const SALTO = String.fromCharCode(10);

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(74) + ' ' + (detalle || ''));
};

const GRUPO = { grupo_jid: '120363000000000001@g.us', nombre: 'Cliente Prueba PEDIDOS JK', tipo: 'cliente',
  cliente_whatsapp: '593990000001', operador_extra_whatsapp: '593990000002', operadora_whatsapp: '593990000003' };
const COLUMNAS = ['mensaje_id', 'fecha_mensaje', 'grupo_jid', 'cliente_nombre', 'autor_rol', 'autor_numero', 'tipo', 'pais', 'banco', 'monto_usd',
                  'monto_local', 'moneda', 'datos', 'texto', 'estado'];

let n = 0;
function evento(texto, extra) {
  extra = extra || {};
  n++;
  const key = { remoteJid: GRUPO.grupo_jid, fromMe: !!extra.fromMe, id: extra.id || ('MSG' + n), participant: '123456789@lid',
                participantAlt: (extra.numero === undefined ? '593990000001' : extra.numero) + '@s.whatsapp.net' };
  const message = extra.mensaje || (extra.imagen ? { imageMessage: { caption: texto || '' } } : { conversation: texto });
  return { key, pushName: 'Alguien', message, messageTimestamp: 1795000000 + n };
}
function entender(texto, extra, grupo) {
  const out = new Function('$input', code('Entender Mensaje'))({ first: () => ({ json: { grupo: grupo || GRUPO, data: evento(texto, extra) } }) });
  return out.length ? out[0].json : null;
}
const bloque = (...l) => l.join(SALTO);

console.log('=== 1) Quien escribio ===');
{
  chk(entender('hola', { numero: '593990000001' }).autor_rol === 'cliente', 'el numero del cliente -> cliente');
  chk(entender('hola', { numero: '593990000002' }).autor_rol === 'operador_extra', 'el numero del operador extra -> operador_extra');
  chk(entender('hola', { numero: '593990000003' }).autor_rol === 'operadora', 'el numero de la operadora -> operadora');
  chk(entender('hola', { numero: '593990000009' }).autor_rol === 'otro', 'cualquier otro numero -> otro');
  const k = entender('hola', { fromMe: true });
  chk(k.autor_rol === 'kelvin' && k.autor_numero === null, 'un mensaje mio (fromMe) -> kelvin');
  chk(entender('hola', { numero: '0990000001' }).autor_rol === 'cliente', 'el numero se compara por sus ultimos 9 digitos', '-> ' + entender('hola', { numero: '0990000001' }).autor_rol);
  const sinAlt = new Function('$input', code('Entender Mensaje'))({ first: () => ({ json: { grupo: GRUPO, data: { key: { remoteJid: GRUPO.grupo_jid, id: 'X1', participant: '123@lid' }, message: { conversation: 'hola' } } } }) })[0].json;
  chk(sinAlt.autor_rol === 'otro' && sinAlt.autor_numero === null, 'sin numero real (solo LID): otro, no revienta');
}

console.log('');
console.log('=== 2) Lo que no sirve se descarta ===');
{
  chk(entender('', { mensaje: { stickerMessage: {} } }) === null, 'un sticker');
  chk(entender('', { mensaje: { reactionMessage: { text: '👍' } } }) === null, 'una reaccion');
  chk(entender('', { mensaje: { protocolMessage: { type: 0 } } }) === null, 'un mensaje borrado/editado');
  chk(entender('', { mensaje: { albumMessage: {} } }) === null, 'el aviso de album');
  chk(entender('   ') === null, 'un mensaje vacio');
  chk(entender('', { mensaje: { locationMessage: {} } }) === null, 'una ubicacion');
  const sinId = new Function('$input', code('Entender Mensaje'))({ first: () => ({ json: { grupo: GRUPO, data: { key: { remoteJid: GRUPO.grupo_jid }, message: { conversation: 'hola' } } } }) });
  chk(sinId.length === 0, 'sin id de mensaje');
}

console.log('');
console.log('=== 3) RST y RCT (retiros de los bancos de Ecuador) ===');
{
  const casos = [
    ['Pichincha Tlf: 0960000001 Monto: 200 $. Código: 7648.', { banco: 'Pichincha', usd: 200, cod: ['7648'], tel: '0960000001', destino: 'PICHINCHA' }],
    ['Guayaquil 1er Codigo : 7679. 2do Código: 2329. Tlf: 0990000002. Monto: 120 $.', { banco: 'Guayaquil', usd: 120, cod: ['7679', '2329'], tel: '0990000002', destino: 'GUAYAQUIL' }],
    ['GUAYAQUIL C. 1 : 6934 C. 2 : 6749 MONTO: 100$ TLF 096 000 0003', { banco: 'Guayaquil', usd: 100, cod: ['6934', '6749'], tel: '0960000003', destino: 'GUAYAQUIL' }],
    ['PRODUBANCO C.i 1700000001 Código: 206321 Monto: 100$ Hora: 14:26', { banco: 'Produbanco', usd: 100, cod: ['206321'], destino: 'PRODUBANCO', ced: '1700000001', hora: '14:26' }],
    ['rst Pichincha 0990000004 clave 7813 100$', { banco: 'Pichincha', usd: 100, cod: ['7813'], tel: '0990000004', destino: 'PICHINCHA' }],
    ['Pichincha Rst Valor 300$ Clave 8922 Teléfono 0990000005', { banco: 'Pichincha', usd: 300, cod: ['8922'], tel: '0990000005' }],
    ['Guayaquil Tlf 0990000006 Primero 8706 Segundo 9064 100$', { banco: 'Guayaquil', usd: 100, cod: ['8706', '9064'], tel: '0990000006' }],
    ['GUAYAQUIL $150 C. 1: 0360 C. 2: 9650 098 000 0007', { banco: 'Guayaquil', usd: 150, cod: ['0360', '9650'], tel: '0980000007' }],
    ['Banco Pichincha 7396 Tlf+593 98 000 0008 Monto 500', { banco: 'Pichincha', usd: 500, cod: ['7396'], tel: '593980000008' }],
    ['Pichincha Código 5478 Teléfono 0990000009 Momto 200', { banco: 'Pichincha', usd: 200, cod: ['5478'], tel: '0990000009' }],
    ['PICHINCHA 🚛 Tlf 0990000010 COD 6428 MONTO: 100$', { banco: 'Pichincha', usd: 100, cod: ['6428'] }],
    ['jep Tlf 0990000011 otp 874512 clave 1234 monto 80$', { banco: 'JEP', usd: 80, cod: ['874512'], destino: 'COOP JEP' }],
    ['jep Tlf 0990000011 clave 1234 monto 80$', { banco: 'JEP', usd: 80, cod: [], destino: 'COOP JEP' }],     // en JEP "clave" es la de la TARJETA: falta el OTP
    ['Bolivariano Tlf 0990000012 clave 4321 monto 60$', { banco: 'Bolivariano', usd: 60, cod: ['4321'], destino: 'COOP JEP' }]
  ];
  for (const [texto, esp] of casos) {
    const r = entender(texto);
    const d = r.datos.registros ? r.datos.registros[0].datos : {};
    const ok = r.tipo === 'rst' && r.banco === esp.banco && r.monto_usd === esp.usd && r.pais === 'Ecuador'
      && JSON.stringify(d.codigos) === JSON.stringify(esp.cod) && (!esp.tel || d.telefono === esp.tel) && (!esp.destino || d.destino_sugerido === esp.destino)
      && (!esp.ced || d.cedula === esp.ced) && (!esp.hora || d.hora === esp.hora);
    chk(ok, 'RST: ' + texto.slice(0, 52), ok ? '' : '-> ' + JSON.stringify({ tipo: r.tipo, banco: r.banco, usd: r.monto_usd, cod: d.codigos, tel: d.telefono, destino: d.destino_sugerido }));
  }
  const rct = entender('⚠️⚠️ PICHINCHA ⚠️⚠️ 👩🏻‍🦱Miser👩🏻‍🦱 Retira con tarjeta Monto 500$');
  chk(rct.tipo === 'rct' && rct.banco === 'Pichincha' && rct.monto_usd === 500, 'RCT: "Retira con tarjeta Monto 500$"', '-> ' + rct.tipo + ' ' + rct.monto_usd);
}

console.log('');
console.log('=== 4) Beneficiarios de Venezuela (Bs) ===');
{
  const a = entender('01020518230000072054 Ana Prueba 11111111 100 $ 102,900bs');
  chk(a.tipo === 'beneficiario' && a.pais === 'Venezuela' && a.banco === 'Venezuela' && a.monto_usd === 100 && a.monto_local === 102900 && a.moneda === 'VES',
      '"cuenta titular cedula 100 $ 102,900bs"', '-> ' + JSON.stringify([a.tipo, a.pais, a.banco, a.monto_usd, a.monto_local]));
  const b = entender('01340946310001116131 BANESCO MARIO PRUEBA C.I. 22222222 bs 112.955 $100');
  chk(b.banco === 'Banesco' && b.monto_usd === 100 && b.monto_local === 112955, '"bs 112.955 $100": el $ es del 100, no del 112.955', '-> ' + JSON.stringify([b.banco, b.monto_usd, b.monto_local]));
  chk(b.datos.registros[0].datos.destino_sugerido === 'BANESCO', 'Banesco -> grupo BANESCO');
  chk(a.datos.registros[0].datos.destino_sugerido === 'VENEZUELA', 'los demas bancos de Venezuela -> grupo VENEZUELA');
  const c = entender('Venezuela Rosa Prueba. 01020459300000054519. 33333333. 230 $. 236.796,50 BsD.');
  chk(c.monto_usd === 230 && c.monto_local === 236796.5 && c.moneda === 'VES', '"230 $. 236.796,50 BsD."', '-> ' + JSON.stringify([c.monto_usd, c.monto_local]));
  const d = entender('Banco Venezuela N° 01020151990000376187 Luis Prueba 44444444 MONTO EN $300.00 MONTO EN Bs 303.351,00');
  chk(d.monto_usd === 300 && d.monto_local === 303351, '"MONTO EN $300.00 MONTO EN Bs 303.351,00"', '-> ' + JSON.stringify([d.monto_usd, d.monto_local]));
  const e = entender('01340023760233092608 ORIANA PRUEBA BANESCO CI: 24000000 BS. 176.207,48 $171,15');
  chk(e.monto_usd === 171.15 && e.monto_local === 176207.48, '"BS. 176.207,48 $171,15"', '-> ' + JSON.stringify([e.monto_usd, e.monto_local]));
  const f = entender('0102 7595768 04245089184');
  chk(f.tipo === 'beneficiario' && f.pais === 'Venezuela' && f.monto_usd === null && f.datos.registros[0].datos.pago_movil === true, 'pago movil sin monto: beneficiario de Venezuela, monto vacio', '-> ' + JSON.stringify([f.tipo, f.pais, f.monto_usd]));
  const g = entender(bloque('Banco Nacional de Credito', '', '0191-0000-00-0000012345 (Corriente)', '', 'Ana Prueba', ' Ci 11111111', '', '', '$60'));
  chk(g.tipo === 'beneficiario' && g.datos.n_registros === 1 && g.monto_usd === 60 && g.banco === 'BNC', 'UNA cuenta con renglones vacios: UN registro, con su monto', '-> ' + JSON.stringify([g.datos.n_registros, g.monto_usd, g.banco]));
  const h = entender(bloque('01340946310001116131 BANESCO OSWALDO PRUEBA C.I. 20000001 bs 112.955 $100', '01020632430100003537 ORIANA PRUEBA VENEZUELA C.I. 24000002 BS. 112.955 $100'));
  chk(h.datos.n_registros === 2 && h.datos.registros[1].banco === 'Venezuela' && h.datos.registros.every(r => r.monto_usd === 100), 'dos cuentas en un mensaje: dos registros', '-> ' + h.datos.n_registros);
  const i = entender(bloque('Venezuela Fernando Prueba. 01020459300000054519. 15000001. 140 $. 144.000 BsD.', 'Banco: Pichincha. Tlf: 0960000020 Monto: 140 $. Código: 1310.'));
  chk(i.tipo === 'mixto' && i.datos.registros.map(r => r.tipo).join() === 'beneficiario,rst', 'un beneficiario y un RST en el mismo mensaje: mixto', '-> ' + i.tipo + ' ' + i.datos.registros.map(r => r.tipo));
}

console.log('');
console.log('=== 5) Otros paises, Zelle y USDT ===');
{
  const col = entender('Nequi TLF 3000000001 C.i 7200001 Zaida Prueba 280.000 cop');
  chk(col.pais === 'Colombia' && col.banco === 'Nequi' && col.monto_local === 280000 && col.moneda === 'COP', 'Nequi Colombia 280.000 cop', '-> ' + JSON.stringify([col.pais, col.banco, col.monto_local, col.moneda]));
  const col2 = entender('Nequi. Damarya Prueba Tel: 3000000002 Monto: 120.000 COP.');
  chk(col2.pais === 'Colombia' && col2.monto_local === 120000, '"Monto: 120.000 COP"', '-> ' + col2.monto_local);
  const br = entender('71262800000 Gabriel Prueba Pix 120,00 brl');
  chk(br.pais === 'Brasil' && br.monto_local === 120 && br.moneda === 'BRL', 'Pix Brasil 120,00 brl', '-> ' + JSON.stringify([br.pais, br.monto_local, br.moneda]));
  const pe = entender('Mi número de cuenta BCP Soles es 19100000000063. Mi número de cuenta interbancaria es 00219100000000000056. Titular : Jesús Prueba 910000001 yape/plin 17$ Tasa: 3.35 56.95');
  chk(pe.pais === 'Perú' && pe.monto_usd === 17 && pe.monto_local === 56.95 && pe.datos.registros[0].datos.tasa === 3.35, 'Peru: 17$, tasa 3.35, recibe 56.95', '-> ' + JSON.stringify([pe.pais, pe.monto_usd, pe.monto_local]));
  const cl = entender('Chile 🇨🇱 Banco Estado Cuenta rut/vista 24.000.000-K Angel Prueba Cedula 24.000.000-K 214.82$ Tasa 931 200.000 pesos chilenos');
  chk(cl.pais === 'Chile' && cl.monto_usd === 214.82 && cl.monto_local === 200000 && cl.moneda === 'CLP', 'Chile: 214.82$, 200.000 pesos chilenos', '-> ' + JSON.stringify([cl.pais, cl.monto_usd, cl.monto_local, cl.moneda]));
  const ze = entender('Zelle Jorge Prueba jprueba@example.com Monto: 6️⃣6️⃣5️⃣💰');
  chk(ze.tipo === 'beneficiario' && ze.pais === 'Zelle' && ze.monto_usd === 665, 'Zelle: el monto escrito con emojis (665)', '-> ' + JSON.stringify([ze.pais, ze.monto_usd]));
  const us = entender('prueba@example.com Miser TH3BCimZMs8NAmF3ipaEg4xmbCuHjnCUNV 2500$');
  chk(us.pais === 'USDT' && us.monto_usd === 2500 && us.datos.registros[0].datos.billetera, 'USDT: correo + billetera + 2500$', '-> ' + JSON.stringify([us.pais, us.monto_usd]));
  const ec = entender('Banco Pichincha 2204190743 Monserrat Prueba CI 0401880687 monto: 15$');
  chk(ec.tipo === 'beneficiario' && ec.pais === 'Ecuador' && ec.banco === 'Pichincha' && ec.monto_usd === 15, 'cuenta de Ecuador (no es un RST)', '-> ' + JSON.stringify([ec.tipo, ec.pais, ec.banco, ec.monto_usd]));
  const ec3 = entender('0990000001 Maria Prueba 2200000002 banco pichincha cuenta ahorro monto: 20$');
  chk(ec3.tipo === 'beneficiario' && ec3.pais === 'Ecuador' && ec3.monto_usd === 20, 'un telefono y "cuenta ahorro" con monto: es una cuenta, no un RST', '-> ' + JSON.stringify([ec3.tipo, ec3.pais]));
  const ve2 = entender('Pedido Fulano 12345678 99999999999 Banesco 20$ 20.000 Bs');
  chk(ve2.tipo === 'beneficiario' && ve2.pais === 'Venezuela' && ve2.banco === 'Banesco', 'Banesco sin el numero de 20 digitos: igual indica Venezuela', '-> ' + JSON.stringify([ve2.tipo, ve2.pais, ve2.banco]));
  const ec2 = entender('Banco Guayaquil Cta aho: 0033164632 Cédula 0966873457 Brayan Prueba monto: 20 $');
  chk(ec2.tipo === 'beneficiario' && ec2.pais === 'Ecuador' && ec2.monto_usd === 20, 'cuenta de ahorros de Guayaquil', '-> ' + JSON.stringify([ec2.tipo, ec2.pais, ec2.monto_usd]));
}

console.log('');
console.log('=== 6) El pais NUNCA se asume ===');
{
  const sin = entender('Juan Prueba 12345678901 100$');
  chk(sin.tipo === 'beneficiario' && sin.pais === null, 'una cuenta sin pais claro: pais null (despues se le pregunta)', '-> ' + JSON.stringify([sin.tipo, sin.pais]));
  const dos = entender('Nequi 3000000003 Pix Juan Prueba 50$');
  chk(dos.pais === null && dos.datos.registros[0].datos.candidatos.length === 2, 'senales de dos paises: pais null y los candidatos', '-> ' + JSON.stringify(dos.datos.registros[0].datos.candidatos));
  const explicito = entender('Para Argentina: alias prueba.cuenta Juan Prueba 80$');
  chk(explicito.pais === 'Argentina', 'si el cliente dice el pais, ese es', '-> ' + explicito.pais);
  const numero = entender('Mi numero es 0990000001 gracias');
  chk(numero.tipo !== 'beneficiario' && numero.tipo !== 'rst', 'un telefono suelto en una charla no es un pedido', '-> ' + numero.tipo);
  const clien = entender('Hola');
  chk(clien.pais === null, 'una charla no tiene pais');
}

console.log('');
console.log('=== 7) Capturas, audios y preguntas ===');
{
  const cap = entender('', { imagen: true });
  chk(cap.tipo === 'captura' && cap.monto_usd === null && cap.pais === null && cap.datos.pie === undefined, 'una imagen sin texto: captura (sin monto ni pie)');
  const cap2 = entender('Abono ecuador efectivo 120$ 🇪🇨', { imagen: true });
  chk(cap2.tipo === 'captura' && cap2.monto_usd === 120 && cap2.pais === 'Ecuador' && cap2.datos.pie, 'una imagen con pie: captura, con su monto y su pais', '-> ' + JSON.stringify([cap2.monto_usd, cap2.pais]));
  const aud = entender('', { mensaje: { audioMessage: { seconds: 12 } } });
  chk(aud.tipo === 'audio' && aud.datos.segundos === 12, 'una nota de voz: audio');
  const p1 = entender('Buenas ¿hay Bs hoy?');
  chk(p1.tipo === 'pregunta' && p1.datos.temas.includes('disponibilidad'), '"¿hay Bs hoy?" -> pregunta de disponibilidad', '-> ' + JSON.stringify(p1.datos.temas));
  const p2 = entender('La tasa de Brasil por donde envian? Que banco');
  chk(p2.tipo === 'pregunta' && p2.datos.temas.includes('tasa') && p2.pais === null, 'una pregunta por la tasa de Brasil: pregunta, sin pais de beneficiario', '-> ' + JSON.stringify([p2.tipo, p2.pais]));
  chk(entender('Esperando foto').tipo === 'pregunta', '"Esperando foto" -> pregunta de estado');
  chk(entender('Me pasas la cuenta del dia').datos.temas.includes('cuenta'), '"la cuenta del dia" -> pregunta de cuenta');
  for (const t of ['Hola', 'Gracias', 'Ok', 'Buenos dias', 'Voy']) chk(entender(t).tipo === 'otro', JSON.stringify(t) + ' -> otro');
}

console.log('');
console.log('=== 8) Lo que escribimos nosotros no se toma por un pedido ===');
{
  const nuestra = '🏦1) 2200000001 *Pichincha ahorro* C.i 0900000001 *Titular Empresa* MOTIVO DE PAGO: contactanos al 0990000050';
  for (const [rol, extra] of [['kelvin', { fromMe: true }], ['operadora', { numero: '593990000003' }]]) {
    const r = entender(nuestra, extra);
    chk(r.tipo === 'otro' && r.autor_rol === rol, 'nuestra cuenta escrita por ' + rol + ': otro', '-> ' + r.tipo);
  }
  chk(entender(nuestra).tipo === 'beneficiario', 'la misma cuenta escrita por el cliente SI es un beneficiario (el cliente la manda)');
  const comp = entender('', { imagen: true, numero: '593990000003' });
  chk(comp.tipo === 'captura' && comp.autor_rol === 'operadora', 'la foto de la operadora: captura de la operadora');
  chk(entender('Tengo 2.500 usdt los quieren? 1.5% Rst', { fromMe: true }).tipo === 'otro', 'una oferta mia de USDT: otro');
}

console.log('');
console.log('=== 9) El grupo de avisos de tasas (VENTAS MAYOR) ===');
{
  const g = { grupo_jid: '120363000000000099@g.us', nombre: 'VENTAS MAYOR', tipo: 'tasas' };
  const r = entender('*TENGO BOLIVARES* 🚛🚀 *BANESCO 1.029,55* RST🏦 *VENEZUELA 1.029,55* RST🏦' + SALTO + '*1.000$ = 1.034,89* RST', { fromMe: true }, g);
  chk(r.tipo === 'tasas' && r.autor_rol === 'kelvin' && r.texto.indexOf('1.029,55') !== -1 && r.datos.lineas === 2, 'una publicacion de tasas se guarda completa', '-> ' + r.tipo);
  chk(entender('', { mensaje: { stickerMessage: {} } }, g) === null, 'los stickers del grupo de tasas se ignoran');
}

console.log('');
console.log('=== 9b) Grupos de DESTINO (abonos, RST por banco, paises...): se registra todo, escriba quien escriba ===');
{
  const D = { grupo_jid: '120363000000000050@g.us', nombre: 'PICHINCHA', tipo: 'destino', operadora_whatsapp: '593990000003' };
  // en un grupo de destino publican ustedes: la cuenta, el RST, la captura del cliente
  const kelvin = entender('Cliente Prueba - $40' + SALTO + SALTO + 'Banco Venezuela 01020518230000072054 Ana Prueba 11111111 $40 41.200 Bs', { fromMe: true }, D);
  chk(kelvin.tipo === 'beneficiario' && kelvin.autor_rol === 'kelvin' && kelvin.monto_usd === 40, 'lo que publica Kelvin en un grupo de destino SI se entiende', '-> ' + JSON.stringify([kelvin.tipo, kelvin.autor_rol, kelvin.monto_usd]));
  const ope = entender('Pichincha Tlf 0990000099 clave 1234 monto 10$', { numero: '593990000003' }, D);
  chk(ope.tipo === 'rst' && ope.autor_rol === 'operadora' && ope.monto_usd === 10, 'y lo que publica la operadora', '-> ' + JSON.stringify([ope.tipo, ope.autor_rol]));
  const otro = entender('Pichincha Tlf 0990000098 clave 4321 monto 20$', { numero: '593990000077' }, D);
  chk(otro.tipo === 'rst' && otro.autor_rol === 'otro', 'y lo de otro miembro del grupo (queda su numero)', '-> ' + otro.autor_numero);
  chk(kelvin.cliente_nombre === null && kelvin.datos.grupo_nombre === 'PICHINCHA', 'el nombre del grupo queda en datos.grupo_nombre (el cliente no es el del grupo)', '-> ' + JSON.stringify(kelvin.datos.grupo_nombre));
  const img = entender('Cliente: Cliente Prueba', { imagen: true, fromMe: true }, D);
  chk(img.tipo === 'captura' && img.datos.pie === 'Cliente: Cliente Prueba' && img.datos.grupo_nombre === 'PICHINCHA', 'una foto con su pie ("Cliente: nombre"): captura, con el pie');
  // en un grupo de CLIENTES lo nuestro sigue sin tomarse por pedido
  const cl = entender('Pichincha Tlf 0990000099 clave 1234 monto 10$', { fromMe: true });
  chk(cl.tipo === 'otro', 'en un grupo de CLIENTES, lo que escribe Kelvin sigue siendo "otro"', '-> ' + cl.tipo);
  chk(cl.datos.grupo_nombre === undefined, 'y no lleva grupo_nombre');
  const nom = entender('hola', {}, GRUPO);
  chk(nom.datos.autor_nombre === 'Alguien', 'cada fila guarda el nombre de quien escribio (autor_nombre)', '-> ' + JSON.stringify(nom.datos));

  // El grupo dice el banco o el pais: en PICHINCHA no se repite "Pichincha"
  const sinBanco = entender('Tlf 0999999999 Código 5678 Monto 20', { numero: '593990000003' }, D);
  chk(sinBanco.tipo === 'rst' && sinBanco.banco === 'Pichincha' && sinBanco.monto_usd === 20 && sinBanco.datos.registros[0].datos.codigos[0] === '5678',
      'en el grupo PICHINCHA un RST sin nombrar el banco se entiende igual', '-> ' + JSON.stringify([sinBanco.tipo, sinBanco.banco, sinBanco.monto_usd]));
  const GQ = { grupo_jid: '120363000000000051@g.us', nombre: 'GUAYAQUIL', tipo: 'destino', operadora_whatsapp: '593990000003' };
  const gq = entender('C.1: 1111 C.2: 2222 Tlf 0990000055 Monto 60', { fromMe: true }, GQ);
  chk(gq.tipo === 'rst' && gq.banco === 'Guayaquil' && gq.datos.registros[0].datos.codigos.join() === '1111,2222', 'y en GUAYAQUIL con sus dos claves', '-> ' + JSON.stringify([gq.tipo, gq.banco]));
  const otroBanco = entender('Produbanco C.i 1700000001 Código: 206321 Monto: 100$', { fromMe: true }, D);
  chk(otroBanco.banco === 'Produbanco', 'si el texto nombra otro banco, manda el texto', '-> ' + otroBanco.banco);
  const AR = { grupo_jid: '120363000000000052@g.us', nombre: 'ARGENTINA', tipo: 'destino', operadora_whatsapp: '593990000003' };
  const ar = entender('Cliente Prueba' + SALTO + 'CBU 0000003100000000000001 Ana Prueba 50$', { fromMe: true }, AR);
  chk(ar.tipo === 'beneficiario' && ar.pais === 'Argentina', 'en el grupo ARGENTINA la cuenta es de Argentina', '-> ' + JSON.stringify([ar.tipo, ar.pais]));
  const arSolo = entender('Ana Prueba 1234567890 50$', { fromMe: true }, AR);
  chk(arSolo.pais === 'Argentina', 'aunque el texto no traiga ninguna señal del pais', '-> ' + JSON.stringify([arSolo.tipo, arSolo.pais]));
  const VE = { grupo_jid: '120363000000000053@g.us', nombre: 'BANESCO', tipo: 'destino', operadora_whatsapp: '593990000003' };
  const fotoVe = entender('', { imagen: true, fromMe: true }, VE);
  chk(fotoVe.tipo === 'captura' && fotoVe.pais === 'Venezuela', 'una foto en BANESCO queda con pais Venezuela', '-> ' + fotoVe.pais);
  const CAP = { grupo_jid: '120363000000000054@g.us', nombre: 'Captures USDT', tipo: 'destino', operadora_whatsapp: '593990000003' };
  chk(entender('', { imagen: true, fromMe: true }, CAP).pais === null, 'Captures USDT NO pone pais (ahi llegan abonos de todo tipo)');
  const cliPich = entender('Tlf 0999999999 Código 5678 Monto 20', {}, Object.assign({}, GRUPO, { nombre: 'Pichincha Prueba PEDIDOS' }));
  chk(cliPich.tipo !== 'rst', 'en un grupo de CLIENTES no hay pista, aunque su nombre diga un banco', '-> ' + cliPich.tipo);
}

console.log('');
console.log('=== 10) La fila que sale ===');
{
  const r = entender('01020518230000072054 Ana Prueba 11111111 100 $ 102,900bs');
  const sobran = Object.keys(r).filter(k => COLUMNAS.indexOf(k) === -1), faltan = COLUMNAS.filter(k => !(k in r));
  chk(sobran.length === 0 && faltan.length === 0, 'trae exactamente las columnas de la tabla', '-> sobran ' + sobran + ' faltan ' + faltan);
  chk(r.cliente_nombre === 'Cliente Prueba' && r.grupo_jid === GRUPO.grupo_jid && r.estado === 'visto' && r.mensaje_id.startsWith('MSG'), 'nombre del cliente, grupo, estado visto, id del mensaje', '-> ' + r.cliente_nombre);
  chk(!isNaN(Date.parse(r.fecha_mensaje)), 'con la fecha del mensaje');
  chk(r.texto.indexOf('Ana Prueba') !== -1, 'y el texto original');
  const largo = entender('x'.repeat(5000));
  chk(largo.texto.length === 3000, 'el texto se recorta a 3000 caracteres');
  const nombres = [['Julio E PEDIDOS JK', 'Julio E'], ['Pedidos JESUS', 'JESUS'], ['Lizandro PEDIDOS JK/ KELVIN💸', 'Lizandro'], ['Kelvin pedidos - Mauro C', 'Mauro C']];
  for (const [g, esp] of nombres) {
    const x = entender('hola', {}, Object.assign({}, GRUPO, { nombre: g }));
    chk(x.cliente_nombre === esp, 'nombre del cliente desde "' + g + '"', '-> ' + x.cliente_nombre);
  }
}

console.log('');
console.log('=== 11) Mensajes repetidos (dedupe) ===');
{
  const fila = entender('hola', { id: 'REPETIDO1' });
  const decidir = (visto) => new Function('$', code('Decidir'))(nn => nn === 'Entender Mensaje' ? { first: () => ({ json: fila }) } : { first: () => ({ json: { visto } }) });
  chk(decidir(undefined).length === 1 && decidir('').length === 1, 'un mensaje nuevo pasa');
  chk(decidir('1').length === 0, 'un mensaje que ya se vio se descarta');
  const sale = (nombre) => ((((wf.connections[nombre] || {}).main || [])[0]) || []).map(c => _strip(c.node)).join();
  chk(nodo('Redis Leer Visto').parameters.key.indexOf('mayorMsg:') !== -1 && nodo('Redis Marcar Visto').parameters.ttl === 24 * 7 * 3600, 'llave mayorMsg:<id>, 7 dias');
  chk(sale('Decidir') === 'Guardar en Supabase' && sale('Guardar en Supabase') === 'Redis Marcar Visto', 'se guarda y despues se marca como visto');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
