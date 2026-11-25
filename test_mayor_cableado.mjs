// Prueba del CABLEADO del Mayor (Fase 1): como el bot principal le pasa los grupos de clientes al
// workflow "Mayor: escuchar y registrar", y que NADA de eso pueda mandar un mensaje.
//
// Lo que se vigila:
//   - un grupo que esta en grupos_mayor va a la salida "mayor" (un solo nodo: Execute Sub-workflow)
//   - un grupo que NO esta en la tabla se ignora como siempre, y la entrega del comprobante del detal sigue igual
//   - la salida nueva es la ULTIMA del switch (los indices de las demas no cambian)
//   - ni el bot en ese camino ni el workflow del mayor tienen nodos que envien mensajes
//   - los chats privados de clientes del detal siguen igual
//
// Todos los datos de esta prueba son INVENTADOS: el repositorio es publico.
//
// Correr con:  node test_mayor_cableado.mjs

import { readFileSync } from 'fs';

const bot = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const mayor = JSON.parse(readFileSync('workflow_mayor.json', 'utf8').replace(/^﻿/, ''));
const nodo = (wf, n) => wf.nodes.find(x => x.name === n);
const code = n => nodo(bot, n).parameters.jsCode;

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(76) + ' ' + (detalle || ''));
};

const GRUPO_CLIENTE = '120363000000000001@g.us';
const GRUPO_OTRO = '120363000000000077@g.us';
const GRUPO_TRANSFERIR = '593961230380-1601657528@g.us';
const FILA_GRUPO = { grupo_jid: GRUPO_CLIENTE, nombre: 'Cliente Prueba PEDIDOS JK', tipo: 'cliente', cliente_whatsapp: '593990000001', activo: true };

// ---------- Arnes de "Solo Estos Numeros" ----------
function filtrar({ jid, fromMe = false, texto = 'hola', mensaje, grupos = [FILA_GRUPO], gruposCaido = false, soloEstos = [], tablas } = {}) {
  const data = { key: { remoteJid: jid, fromMe, id: 'ID1', participant: '123@lid', participantAlt: '593990000001@s.whatsapp.net' }, pushName: 'Alguien',
                 message: mensaje || { conversation: texto }, messageTimestamp: Math.floor(Date.now() / 1000) };
  const items = [{ json: { body: { data } } }];
  // Igual que en produccion: el filtro de clientes esta PRENDIDO (MODO_SOLO_CLIENTES = true) y hay un cliente del detal cargado.
  const t = Object.assign({ 'Clientes Detal Permitidos': [{ whatsapp: '593990000050', nombre: 'Cliente Detal' }], 'Clientes Mayor Permitidos': [], 'Perfiles Detal App': [], 'Perfiles Mayor App': [],
                            'Redis Leer Pausa': [{}], 'Redis Leer Aviso': [{}] }, tablas || {});
  const $ = (n) => {
    if (n === 'Webhook Evolution API') return { all: () => items, first: () => items[0] };
    if (n === 'Grupos Mayor') {
      if (gruposCaido === 'sin nodo') throw new Error('Node "Grupos Mayor" not executed');
      const filas = gruposCaido ? [{ error: { message: 'Supabase no responde' } }] : (grupos.length ? grupos : [{}]);
      return { all: () => filas.map(json => ({ json })), first: () => ({ json: filas[0] }) };
    }
    const v = t[n]; if (v === undefined) throw new Error('Node "' + n + '" not executed');
    const its = v.map(json => ({ json }));
    return { all: () => its, first: () => its[0] };
  };
  const js = code('Solo Estos Numeros')
    .replace(/const SOLO_ESTOS = .*;/, 'const SOLO_ESTOS = ' + JSON.stringify(soloEstos) + ';')
    .replace(/const MODO_SOLO_CLIENTES = .*;/, 'const MODO_SOLO_CLIENTES = true;');
  return new Function('$input', '$', js)({ all: () => [{ json: {} }] }, $).map(i => i.json);
}

console.log('=== 1) Un grupo de la tabla va a "mayor" ===');
{
  const r = filtrar({ jid: GRUPO_CLIENTE, texto: 'Pichincha Tlf 0990000001 clave 1234 100$' });
  chk(r.length === 1 && r[0].accionPausa === 'mayor', 'un mensaje del grupo del cliente: accionPausa = mayor', '-> ' + JSON.stringify(r.map(x => x.accionPausa)));
  chk(r[0].grupo.grupo_jid === GRUPO_CLIENTE && r[0].grupo.nombre === 'Cliente Prueba PEDIDOS JK', 'lleva la fila del grupo');
  chk(r[0].data.key.id === 'ID1' && r[0].data.key.participantAlt && r[0].data.message.conversation, 'y el mensaje de Evolution tal cual (id, quien, texto)');
  const k = filtrar({ jid: GRUPO_CLIENTE, fromMe: true, texto: 'ok' });
  chk(k.length === 1 && k[0].accionPausa === 'mayor', 'lo que escribe Kelvin en ese grupo tambien se registra (y NO pausa nada)', '-> ' + JSON.stringify(k.map(x => x.accionPausa)));
  chk(filtrar({ jid: GRUPO_CLIENTE, mensaje: { imageMessage: { caption: '' } } })[0].accionPausa === 'mayor', 'una foto del grupo tambien');
  chk(filtrar({ jid: GRUPO_CLIENTE, mensaje: { stickerMessage: {} } })[0].accionPausa === 'mayor', 'un sticker llega (el workflow lo descarta)');
  const inactivo = filtrar({ jid: GRUPO_CLIENTE, grupos: [Object.assign({}, FILA_GRUPO, { activo: false })] });
  chk(inactivo.length === 0, 'un grupo marcado inactivo se ignora', '-> ' + inactivo.length);
}

console.log('');
console.log('=== 2) Lo demas sigue igual ===');
{
  chk(filtrar({ jid: GRUPO_OTRO, texto: 'hola' }).length === 0, 'un grupo que NO esta en la tabla se ignora, como siempre');
  chk(filtrar({ jid: GRUPO_TRANSFERIR, texto: 'hola' }).length === 0, 'el grupo de transferir (detal) no se toca');
  chk(filtrar({ jid: GRUPO_OTRO, mensaje: { imageMessage: { caption: '' } }, texto: '' })[0].accionPausa === 'recordarFoto', 'la foto suelta en un grupo del detal: se recuerda, como antes');
  // aunque alguien cargue por error el grupo de transferir (detal) en grupos_mayor, NO se enruta al mayor
  const filaTransferir = { grupo_jid: GRUPO_TRANSFERIR, nombre: 'TRANSFERIR', tipo: 'destino', activo: true };
  const errorCargado = filtrar({ jid: GRUPO_TRANSFERIR, texto: 'hola', grupos: [filaTransferir] });
  chk(errorCargado.every(x => x.accionPausa !== 'mayor'), 'el grupo de TRANSFERIR del detal nunca va a mayor (aunque este en la tabla)', '-> ' + JSON.stringify(errorCargado.map(x => x.accionPausa)));
  const entregaIntacta = filtrar({ jid: GRUPO_TRANSFERIR, mensaje: { imageMessage: { caption: '', contextInfo: { stanzaId: 'PUB1' } } }, grupos: [filaTransferir] });
  chk(entregaIntacta.length === 1 && entregaIntacta[0].accionPausa === 'entregar', 'y la entrega del comprobante en ese grupo sigue funcionando', '-> ' + JSON.stringify(entregaIntacta.map(x => x.accionPausa)));
  const filaAvisos = { grupo_jid: '120363413942097019@g.us', nombre: 'AVISOS', tipo: 'destino', activo: true };
  chk(filtrar({ jid: '120363413942097019@g.us', texto: 'hola', grupos: [filaAvisos] }).every(x => x.accionPausa !== 'mayor'), 'el grupo de avisos (Notificaciones Clientes) tampoco');
  const destino = filtrar({ jid: GRUPO_OTRO, texto: 'Pichincha Tlf 0990000001 clave 1234 100$', grupos: [{ grupo_jid: GRUPO_OTRO, nombre: 'PICHINCHA', tipo: 'destino', activo: true }] });
  chk(destino.length === 1 && destino[0].accionPausa === 'mayor' && destino[0].grupo.tipo === 'destino', 'un grupo de destino de la tabla SI va a mayor', '-> ' + JSON.stringify(destino.map(x => x.accionPausa)));
  const grupoSinNodo = filtrar({ jid: GRUPO_OTRO, texto: 'hola', gruposCaido: 'sin nodo' });
  chk(grupoSinNodo.length === 0, 'si el nodo Grupos Mayor no corrio: no se rompe, se ignora el grupo');
  chk(filtrar({ jid: GRUPO_CLIENTE, gruposCaido: true }).length === 0, 'si Supabase no responde: el grupo se ignora (no se rompe)');
  chk(filtrar({ jid: GRUPO_CLIENTE, grupos: [] }).length === 0, 'tabla vacia: nada va a mayor');
  const privado = filtrar({ jid: '593990000050@s.whatsapp.net', texto: 'hola' });
  chk(privado.length === 1 && privado[0].accionPausa === 'seguir', 'un chat privado del detal sigue como siempre', '-> ' + JSON.stringify(privado.map(x => x.accionPausa)));
  const privFromMe = filtrar({ jid: '593990000050@s.whatsapp.net', fromMe: true, texto: 'hola' });
  chk(privFromMe.length === 1 && privFromMe[0].accionPausa === 'pausar', 'Kelvin escribiendole a un cliente privado: pausa, como siempre', '-> ' + JSON.stringify(privFromMe.map(x => x.accionPausa)));
  const falsaCoincidencia = filtrar({ jid: '593990000001@s.whatsapp.net', texto: 'hola' });
  chk(falsaCoincidencia.every(x => x.accionPausa !== 'mayor'), 'un privado (aunque sea el numero del cliente del grupo) nunca se toma por el grupo', '-> ' + JSON.stringify(falsaCoincidencia.map(x => x.accionPausa)));
}

console.log('');
console.log('=== 3) Router Pausa y el nodo que llama al workflow ===');
{
  const sw = nodo(bot, 'Router Pausa').parameters.rules.values.map(v => v.outputKey);
  // Despues de "mayor" se agrego "verificar" (23/11), tambien al final: las de antes no cambian de numero.
  chk(sw.join() === 'seguir,pausar,reanudar,avisar,entregar,recordarFoto,mayor,verificar', 'la salida "mayor" sigue siendo la 7 (las nuevas van despues)', '-> ' + sw.join());
  const salidas = (bot.connections['Router Pausa'] || {}).main || [];
  chk(salidas.length === 8 && salidas[6].map(c => c.node).join() === 'Mayor Escuchar', 'la salida 7 va solo a "Mayor Escuchar"', '-> ' + (salidas[6] || []).map(c => c.node));
  chk(salidas.slice(0, 6).map(s => s.map(c => c.node).join()).join('|') === 'Es mensaje de cliente?|Redis Guardar Pausa|Redis Borrar Pausa|Avisar Pausa|Ejecutar Operadoras|Ejecutar Operadoras',
      'las 6 salidas de antes siguen yendo donde iban (entregar y recordarFoto -> Ejecutar Operadoras)');
  const cond = nodo(bot, 'Router Pausa').parameters.rules.values[6].conditions.conditions[0];
  chk(cond.rightValue === 'mayor' && /accionPausa/.test(cond.leftValue), 'la regla compara accionPausa con "mayor"');
  const e = nodo(bot, 'Mayor Escuchar');
  chk(e.type === 'n8n-nodes-base.executeWorkflow' && e.typeVersion === 1.3, '"Mayor Escuchar" es un Execute Sub-workflow (1.3)');
  chk(e.parameters.workflowId && e.parameters.workflowId.value === 'HIERZLV4lwtuBRbZ', 'apunta al workflow "Mayor: escuchar y registrar"', '-> ' + (e.parameters.workflowId || {}).value);
  chk(e.parameters.options && e.parameters.options.waitForSubWorkflow === false, 'no espera al sub-workflow (el bot no se frena por el mayor)');
  chk(e.onError === 'continueRegularOutput', 'si el sub-workflow falla, el bot sigue');
  const sale = (n) => (((bot.connections[n] || {}).main || [])[0] || []).map(c => c.node).join();
  chk(sale('Mayor Escuchar') === '', 'y no sigue a ningun otro nodo (despues de llamarlo, termina)');
  chk(sale('Perfiles Mayor App') === 'Grupos Mayor' && sale('Grupos Mayor') === 'Redis Leer Pausa', 'Grupos Mayor va entre Perfiles Mayor App y Redis Leer Pausa');
  const g = nodo(bot, 'Grupos Mayor');
  chk(g.parameters.tableId === 'grupos_mayor' && g.parameters.operation === 'getAll' && g.parameters.returnAll === true, 'lee toda la tabla grupos_mayor');
  chk(g.executeOnce === true && g.onError === 'continueRegularOutput' && g.alwaysOutputData === true, 'una vez por evento, y si falla sigue');
  chk(g.credentials && g.credentials.supabaseApi && g.credentials.supabaseApi.name === 'Supabase Cambios JK', 'con la credencial de servicio (sin claves en el codigo)');
}

console.log('');
console.log('=== 4) QUIEN PUEDE MANDAR MENSAJES (Fase 2: solo 2 nodos, y a un destino que decide "Decidir Publicacion") ===');
{
  const ENVIA = /sendText|sendMedia|sendSticker|sendWhatsAppAudio|sendReaction|sendPoll|sendList|sendButtons|message\/send/i;
  const tipoEnvia = n => /evolutionApi|telegram|slack|whatsApp|gmail|emailSend|sendEmail/i.test(n.type) || (/httpRequest/.test(n.type) && ENVIA.test(JSON.stringify(n.parameters)));
  const enviaMayor = mayor.nodes.filter(tipoEnvia).map(n => n.name).sort();
  chk(JSON.stringify(enviaMayor) === JSON.stringify(['Enviar', 'Reenviar sin Cita']), 'solo dos nodos mandan mensajes: "Enviar" y "Reenviar sin Cita"', '-> ' + enviaMayor);
  // el destino de cada mensaje sale SIEMPRE del item que armo "Decidir Publicacion" (nunca un id escrito a mano)
  const enviar = nodo(mayor, 'Enviar').parameters, reenviar = nodo(mayor, 'Reenviar sin Cita').parameters;
  chk(/\$json\.jid/.test(enviar.jsonBody) && !/@g\.us|@s\.whatsapp\.net/.test(JSON.stringify(enviar)), '"Enviar": el destino sale del item (json.jid), sin ids escritos a mano');
  chk(/Decidir Publicacion"\)\.item\.json\.jid/.test(reenviar.jsonBody) && !/@g\.us|@s\.whatsapp\.net/.test(JSON.stringify(reenviar)), '"Reenviar sin Cita": igual');
  const hacia = nombreNodo => { const r = []; for (const [de, c] of Object.entries(mayor.connections)) for (const sal of (c.main || [])) for (const x of sal) if (x.node === nombreNodo) r.push(de); return r.sort(); };
  chk(JSON.stringify(hacia('Enviar')) === JSON.stringify(['Decidir Publicacion']), '"Enviar" solo recibe de "Decidir Publicacion"', '-> ' + hacia('Enviar'));
  chk(JSON.stringify(hacia('Reenviar sin Cita')) === JSON.stringify(['Fallo la Cita?']), '"Reenviar sin Cita" solo recibe del reintento', '-> ' + hacia('Reenviar sin Cita'));
  const codigos = mayor.nodes.filter(n => n.type.endsWith('.code')).map(n => n.parameters.jsCode).join(String.fromCharCode(10));
  chk(!/\$helpers|httpRequest|fetch\(|axios|XMLHttpRequest/.test(codigos), 'ningun nodo de codigo hace llamadas a internet');
  const tipos = [...new Set(mayor.nodes.map(n => n.type.replace('n8n-nodes-base.', '')))].sort();
  chk(tipos.every(t => ['stickyNote', 'executeWorkflowTrigger', 'code', 'redis', 'supabase', 'httpRequest', 'if'].includes(t)), 'y no hay ningun otro tipo de nodo (nada de IA, correo, Telegram...)', '-> ' + tipos.join());
  // Desde "Mayor Escuchar" nada puede llegar a un nodo que envie
  const alcanzables = new Set(); const pila = ['Mayor Escuchar'];
  while (pila.length) { const x = pila.pop(); for (const s of ((bot.connections[x] || {}).main || [])) for (const c of s) if (!alcanzables.has(c.node)) { alcanzables.add(c.node); pila.push(c.node); } }
  chk(alcanzables.size === 0, 'desde "Mayor Escuchar" no se llega a ningun otro nodo del bot', '-> ' + [...alcanzables]);
  const codigoMayor = nodo(bot, 'Solo Estos Numeros').parameters.jsCode;
  chk(/accionPausa: 'mayor'/.test(codigoMayor) && !/enviar|sendText/.test(codigoMayor.slice(codigoMayor.indexOf("accionPausa: 'mayor'") - 200, codigoMayor.indexOf("accionPausa: 'mayor'") + 200)), 'la rama "mayor" de Solo Estos Numeros solo devuelve datos');
}

console.log('');
console.log('=== 5) El workflow del mayor ===');
{
  chk(mayor.name === 'Mayor: escuchar y registrar', 'se llama "Mayor: escuchar y registrar"');
  const t = nodo(mayor, 'Cuando lo Llama el Bot');
  chk(t.type === 'n8n-nodes-base.executeWorkflowTrigger' && t.parameters.inputSource === 'passthrough', 'empieza con Execute Workflow Trigger que acepta todos los datos');
  const g = nodo(mayor, 'Guardar en Supabase').parameters;
  chk(g.tableId === 'transacciones_mayor_por_whatsapp' && g.operation === 'create' && g.dataToSend === 'autoMapInputData', 'guarda en transacciones_mayor_por_whatsapp');
  for (const n of ['Redis Leer Visto', 'Guardar en Supabase', 'Redis Marcar Visto']) chk(!!nodo(mayor, n).credentials, n + ': con credencial (sin claves en el codigo)');
  for (const n of ['Redis Leer Visto', 'Guardar en Supabase', 'Redis Marcar Visto', 'Redis Leer Publicacion', 'Grupos Destino', 'Enviar', 'Reenviar sin Cita', 'Actualizar Fila', 'Redis Guardar Publicacion'])
    chk(nodo(mayor, n).onError === 'continueRegularOutput', n + ': si falla, no se cae');
  chk(!!nodo(mayor, 'Nota') && /FASE 2/.test(nodo(mayor, 'Nota').parameters.content) && /ENSAYO/.test(nodo(mayor, 'Nota').parameters.content), 'trae la nota que explica la Fase 2 y el modo ensayo');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);

