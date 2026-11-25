
const _strip = s => s ? String(s).replace(/^\d+[\w\.]*\s*/, '') : '';
const _findNode = (nodes, n) => (nodes || []).find(x => x.name === n || _strip(x.name) === _strip(n));
const _getConn = (conns, n) => {
  if (!conns) return null;
  const k = Object.keys(conns).find(x => x === n || _strip(x) === _strip(n));
  return k ? Reflect.get(conns, k) : null;
};
// Prueba del workflow "Liberar operaciones de la noche" (lo genera build_liberar_noche.ps1).
//
// A las 9:05 (domingo 10:05) toma las operaciones 'en_espera' de Supabase y, una por una, publica
// la captura y cada cuenta en transferir, guarda de quien es cada publicacion, le manda al cliente
// el sticker de PEDIDO APROBADO y pasa las filas a 'en_proceso'.
//
// Todos los datos de esta prueba son INVENTADOS: el repositorio es publico.
//
// Correr con:  node test_liberar_noche.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_liberar_noche.json', 'utf8').replace(/^﻿/, ''));
const nodo = n => _findNode(wf.nodes, n);
const code = n => nodo(n).parameters.jsCode;
const SALTO = String.fromCharCode(10);

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(72) + ' ' + (detalle || ''));
};
const evalExpr = (expr, $, $json) => new Function('$', '$json', 'return (' + String(expr).replace(/^=\{\{/, '').replace(/\}\}$/, '') + ');')($, $json);

const CTA_A = ['Banco Uno', '01020000000000011111', 'Luisa Prueba', 'V 22222222', '$40'].join(SALTO);
const CTA_B = ['Banco Dos', '01020000000000022222', 'Mario Prueba', 'V 33333333', '$60'].join(SALTO);
const CTA_C = ['Banco Tres', '01020000000000033333', 'Rosa Prueba', 'V 44444444'].join(SALTO);
const filas = [
  { id: 12, creado: '2026-11-21T04:10:00Z', whatsapp: '593990000002', nombre_cliente: 'Pedro Prueba', estado: 'en_espera', id_msg_captura: 'CAP-2', cuentas: [{ id: 'C3', texto: CTA_C, monto: null }] },
  { id: 10, creado: '2026-11-21T03:00:00Z', whatsapp: '593990000001', nombre_cliente: 'Ana Prueba', estado: 'en_espera', id_msg_captura: 'CAP-1', cuentas: [{ id: 'C1', texto: CTA_A, monto: 40 }] },
  { id: 11, creado: '2026-11-21T03:00:00Z', whatsapp: '593990000001', nombre_cliente: 'Ana Prueba', estado: 'en_espera', id_msg_captura: 'CAP-1', cuentas: JSON.stringify([{ id: 'C1', texto: CTA_B, monto: 60 }]) },
  { id: 13, creado: '2026-11-21T02:00:00Z', whatsapp: '593990000003', estado: 'en_proceso', id_msg_captura: 'CAP-3', cuentas: [] }
];

console.log('=== 1) Agrupar las operaciones en espera ===');
{
  const ops = new Function('$input', code('Agrupar Operaciones'))({ all: () => filas.map(json => ({ json })) }).map(i => i.json);
  chk(ops.length === 2, 'dos operaciones (la que ya estaba en proceso no cuenta)', '-> ' + ops.length);
  chk(ops[0].nombre === 'Ana Prueba' && ops[1].nombre === 'Pedro Prueba', 'la que llego primero sale primero');
  chk(ops[0].jid === '593990000001@s.whatsapp.net' && ops[0].idImagen === 'CAP-1', 'con el chat del cliente y su captura');
  chk(ops[0].filas.length === 2 && ops[0].filas.map(f => f.filaId).join() === '10,11', 'Ana: sus dos cuentas, cada una con su fila', '-> ' + ops[0].filas.map(f => f.filaId));
  chk(ops[0].filas[0].cuenta.split(SALTO)[0] === 'Ana Prueba - $40' && ops[0].filas[1].cuenta.split(SALTO)[0] === 'Ana Prueba - $60',
      'la misma cabecera que de dia: "nombre - $monto"', '-> ' + ops[0].filas.map(f => f.cuenta.split(SALTO)[0]));
  chk(ops[1].filas[0].cuenta.split(SALTO)[0] === 'Pedro Prueba' && ops[1].filas[0].cuenta.indexOf('01020000000000033333') !== -1, 'sin monto: solo el nombre');
  chk(ops[0].filas[0].idCuenta === 'C1', 'guarda el mensaje de la cuenta (para citarselo al cliente)');
  const vacio = new Function('$input', code('Agrupar Operaciones'))({ all: () => [{ json: {} }] });
  chk(vacio.length === 0, 'si no hay ninguna en espera: no hace nada', '-> ' + vacio.length);
  const caida = new Function('$input', code('Agrupar Operaciones'))({ all: () => [{ json: { error: { message: 'Supabase no responde' } } }] });
  chk(caida.length === 0, 'si Supabase falla: no publica nada');
  chk(/const PRUEBA = null;/.test(code('Agrupar Operaciones')), 'NO esta en modo prueba');
}

console.log('');
console.log('=== 2) Publicar una operacion ===');
{
  const op = { jid: '593990000001@s.whatsapp.net', nombre: 'Ana Prueba', idImagen: 'CAP-1',
               filas: [{ filaId: 10, idCuenta: 'C1', monto: 40, cuenta: 'Ana Prueba - $40\n\n' + CTA_A },
                       { filaId: 11, idCuenta: 'C1', monto: 60, cuenta: 'Ana Prueba - $60\n\n' + CTA_B }] };
  const $ = n => {
    if (n === 'Una por Una' || _strip(n) === 'Una por Una') return { first: () => ({ json: op }) };
    if (n === 'Publicar Captura' || _strip(n) === 'Publicar Captura') return { first: () => ({ json: { key: { id: 'G-FOTO' } } }) };
    throw new Error('nodo inesperado: ' + n);
  };
  const separadas = new Function('$', code('Separar Cuentas de la Operacion'))($).map(i => i.json);
  chk(separadas.length === 2 && separadas[0].idFoto === 'G-FOTO' && separadas[1].idFoto === '', 'una publicacion por cuenta; la foto va con la primera');

  const pub = nodo('Publicar Captura').parameters;
  const conFoto = evalExpr(pub.jsonBody, $, { base64: 'AAAA', mimetype: 'image/jpeg' });
  const cf = JSON.parse(conFoto);
  chk(cf.number === '593961230380-1601657528@g.us' && cf.media === 'AAAA' && cf.caption === 'Cliente: Ana Prueba', 'la foto va al grupo de TRANSFERIR con "Cliente: <nombre>"', '-> ' + cf.number);
  chk(/sendMedia/.test(evalExpr(pub.url, $, { base64: 'AAAA' })), 'con foto: sendMedia');
  const sinFoto = JSON.parse(evalExpr(pub.jsonBody, $, {}));
  chk(/sendText/.test(evalExpr(pub.url, $, {})) && /No se pudo bajar la foto/.test(sinFoto.text), 'si no se pudo bajar la foto: avisa con un texto');

  const marca = nodo('Marcar Publicacion Captura').parameters;
  const valor = JSON.parse(evalExpr(marca.value, $, {}));
  chk(valor.jid === op.jid && valor.idCaptura === 'CAP-1' && valor.idCuenta === 'C1', 'guarda de quien es la foto (igual que el bot: grupoMsg)', '-> ' + JSON.stringify(valor));
  chk(evalExpr(marca.key, $, { key: { id: 'G-FOTO' } }) === 'grupoMsg:G-FOTO' && marca.ttl === 172800, 'llave grupoMsg:<id>, 48 h');

  const $2 = n => {
    if (n === 'Separar Cuentas de la Operacion' || _strip(n) === 'Separar Cuentas de la Operacion') return { all: () => separadas.map(json => ({ json })), item: { json: separadas[1] } };
    if (n === 'Publicar Cuenta' || _strip(n) === 'Publicar Cuenta') return { all: () => [{ json: { key: { id: 'G-A' } } }, { json: { data: { key: { id: 'G-B' } } } }] };
    return $(n);
  };
  const vc = JSON.parse(evalExpr(nodo('Marcar Publicacion Cuenta').parameters.value, $2, {}));
  chk(vc.idCuenta === 'C1' && vc.idCaptura === 'CAP-1', 'cada cuenta publicada tambien queda anotada');
  const act = new Function('$', code('Armar Actualizacion'))($2).map(i => i.json);
  chk(act.length === 2 && act[0].filaId === 10 && act[0].estado === 'en_proceso', 'cada fila pasa a en_proceso');
  chk(act[0].id_msgs_grupo.join() === 'G-A,G-FOTO' && act[1].id_msgs_grupo.join() === 'G-B', 'cada fila con SU publicacion (asi el bot la marca enviada 1 por 1)', '-> ' + act.map(a => a.id_msgs_grupo));
  chk(!isNaN(Date.parse(act[0].publicado_en)), 'y la hora en que se publico');

  const up = nodo('Marcar En Proceso').parameters;
  chk(up.operation === 'update' && up.dataToSend === 'autoMapInputData' && up.inputsToIgnore === 'filaId', 'actualiza la fila con lo que armo el nodo anterior');
  chk(evalExpr(up.filterString, $, { filaId: 10 }) === 'id=eq.10&estado=eq.en_espera', 'solo esa fila, y solo si seguia en espera', '-> ' + evalExpr(up.filterString, $, { filaId: 10 }));
  const st = nodo('Sticker Pedido Aprobado').parameters;
  chk(/sticker-pedido-aprobado\.webp/.test(st.jsonBody) && /Una por Una/.test(st.jsonBody), 'le manda al cliente el sticker PEDIDO APROBADO');
  const cuenta = JSON.parse(evalExpr(nodo('Publicar Cuenta').parameters.jsonBody, $, { cuenta: 'Ana Prueba - $40\n\nX' }));
  chk(cuenta.number === '593961230380-1601657528@g.us' && cuenta.text.indexOf('Ana Prueba - $40') === 0, 'cada cuenta va al grupo de transferir');
}

console.log('');
console.log('=== 3) Horario, conexiones y seguridad ===');
{
  const cron = nodo('Cada Mañana').parameters.rule.interval.map(i => i.expression).join(' | ');
  chk(cron === '0 5 9 * * 1-6 | 0 5 10 * * 0', 'lunes a sabado 9:05 y domingo 10:05', '-> ' + cron);
  chk(wf.settings.timezone === 'America/Guayaquil', 'hora de Ecuador');
  const sale = (n, i) => ((((wf.connections[n] || {}).main || [])[i || 0]) || []).map(c => _strip(c.node)).join();
  chk(sale('Una por Una', 0) === '' && sale('Una por Una', 1) === 'Bajar Captura', 'una operacion por vuelta');
  chk(sale('Marcar En Proceso') === 'Una por Una', 'al terminar una, vuelve por la siguiente');
  const orden = ['Cada Mañana', 'Leer Operaciones en Espera', 'Agrupar Operaciones'];
  chk(sale(orden[0]) === orden[1] && sale(orden[1]) === orden[2], 'lee Supabase y agrupa');
  for (const n of wf.nodes.filter(x => /httpRequest|redis|supabase/.test(x.type))) {
    chk(!!n.credentials, n.name + ': con credencial (sin claves en el codigo)');
  }
  // Dentro de la vuelta, ningun nodo puede quedarse sin salida: si no, el resto de las operaciones
  // no se publicaria nunca.
  for (const n of ['Bajar Captura', 'Publicar Captura', 'Sticker Pedido Aprobado', 'Publicar Cuenta', 'Marcar En Proceso']) {
    chk(nodo(n).alwaysOutputData === true && nodo(n).onError === 'continueRegularOutput', n + ': si falla, la vuelta sigue');
  }
  chk(!!nodo('Nota') && /Liberar operaciones de la noche/.test(nodo('Nota').parameters.content), 'trae la nota que explica el workflow');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
