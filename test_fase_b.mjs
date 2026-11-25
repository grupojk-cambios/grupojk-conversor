// Prueba de la FASE B: antes de mandarle al cliente la foto que devolvio la operadora, el bot la
// lee (GPT-4o) y la compara con la cuenta destino de ESA publicacion.
//   - algun dato coincide (cuenta/telefono, cedula, correo, billetera)  -> se entrega
//   - los datos se contradicen                                        -> NO se entrega; aviso en el grupo
//   - no se pudo leer o comparar                                      -> se entrega, como antes
//   - respondiendo el aviso con "forzar"                              -> se entrega igual
//
// Todos los datos de esta prueba son INVENTADOS: el repositorio es publico.
//
// Correr con:  node test_fase_b.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_operadoras.json', 'utf8').replace(/^﻿/, ''));
const wfBot = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^﻿/, ''));
const nodo = n => wf.nodes.find(x => x.name === n) || wfBot.nodes.find(x => x.name === n);
const code = n => nodo(n).parameters.jsCode;
const SALTO = String.fromCharCode(10);

let fallos = 0;
const chk = (ok, etiqueta, detalle) => {
  if (!ok) fallos++;
  console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(74) + ' ' + (detalle || ''));
};

const GRUPO = '593961230380-1601657528@g.us';
const PUB_A = 'GRUPO-CTA-A', PUB_B = 'GRUPO-CTA-B', PUB_FOTO = 'GRUPO-FOTO';
const CTA_A = ['Banco de Venezuela', '0102-0000-00-0000012345', 'Luisa Prueba', 'V 22222222', '$40'].join(SALTO);
const CTA_B = ['Pago movil Banesco', '0412-0000099', 'Mario Inventado', 'CI 33333333', '$60'].join(SALTO);
const CTA_Z = ['Zelle', 'rosa.prueba@example.com', 'Rosa Prueba'].join(SALTO);
const fila = (id, pubs, texto, extra) => Object.assign({ id, estado: 'en_proceso', id_msg_captura: 'CAP-1', id_msgs_grupo: pubs,
  cuentas: [{ id: 'MSG-' + id, texto, monto: null }] }, extra || {});

// leido: lo que "leyo" GPT-4o (o un texto crudo); filas: las de Supabase; ped: lo de "Revisar Pedido"
function revisar(leido, filas, ped) {
  const pedido = Object.assign({ jid: '593990000001@s.whatsapp.net', nombre: 'Ana Prueba', idCuenta: 'MSG-PEDIDO', idCaptura: 'CAP-1',
                                 stanzaId: PUB_A, jidGrupo: GRUPO, idFoto: 'FOTO-OP', forzar: false }, ped || {});
  const $ = n => {
    if (n === 'Revisar Pedido') return { first: () => ({ json: pedido }) };
    if (n === 'Leer Comprobante Operadora') {
      if (leido === 'CAIDA') return { first: () => ({ json: { error: { message: 'OpenAI no responde' } } }) };
      return { first: () => ({ json: { content: typeof leido === 'string' ? leido : '```json\n' + JSON.stringify(leido) + '\n```' } }) };
    }
    if (n === 'Leer Cuentas de la Operacion') {
      if (filas === 'CAIDA') return { all: () => [{ json: { error: { message: 'Supabase no responde' } } }] };
      const f = (filas && filas.length) ? filas : [{}];
      return { all: () => f.map(json => ({ json })) };
    }
    throw new Error('nodo inesperado: ' + n);
  };
  return new Function('$', code('Revisar Comprobante'))($)[0].json;
}

const UNA = [fila(1, [PUB_A, PUB_FOTO], CTA_A)];
const DOS = [fila(1, [PUB_A, PUB_FOTO], CTA_A), fila(2, [PUB_B], CTA_B)];

console.log('=== 1) Cuadra: se entrega ===');
{
  const r = revisar({ es_comprobante: true, cuenta_destino: '0102****2345', titular_destino: 'LUISA PRUEBA', banco_destino: 'Banco de Venezuela' }, UNA);
  chk(r.cuadra === true && r.verificado === true && r.filaId === 1, 'cuenta enmascarada (…2345) y titular: CUADRA', '-> ' + r.motivo);
  chk(r.idCuenta === 'MSG-1', 'se le cita al cliente el mensaje de ESA cuenta', '-> ' + r.idCuenta);
  const pm = revisar({ es_comprobante: true, cuenta_destino: '+58 412-0000099', cedula_destino: 'V-33.333.333' }, DOS, { stanzaId: PUB_B });
  chk(pm.cuadra && pm.filaId === 2, 'pago movil: telefono y cedula de la cuenta B', '-> ' + pm.motivo);
  const z = revisar({ es_comprobante: true, correo_destino: 'Rosa.Prueba@example.com', titular_destino: 'Rosa P' }, [fila(5, [PUB_A], CTA_Z)]);
  chk(z.cuadra && z.verificado, 'Zelle: el correo', '-> ' + z.motivo);
  const ced = revisar({ es_comprobante: true, cuenta_destino: '', cedula_destino: '22222222', titular_destino: '' }, UNA);
  chk(ced.cuadra && ced.verificado, 'solo la cedula', '-> ' + ced.motivo);
  const nom = revisar({ es_comprobante: true, titular_destino: 'Luisa Fernanda Prueba Gomez' }, UNA);
  chk(nom.cuadra && nom.verificado, 'sin numeros: el titular', '-> ' + nom.motivo);
}

console.log('');
console.log('=== 2) NO cuadra: no se entrega y se avisa en el grupo ===');
{
  const r = revisar({ es_comprobante: true, cuenta_destino: '0102****9876', titular_destino: 'PEDRO OTRO', banco_destino: 'Banesco' }, UNA);
  chk(r.cuadra === false, 'otra cuenta (…9876) y otro titular: NO CUADRA', '-> ' + r.motivo);
  chk(/NO cuadra/.test(r.aviso) && /Ana Prueba/.test(r.aviso), 'el aviso dice que no cuadra y de quien es');
  chk(/9876/.test(r.aviso) && /0102-0000-00-0000012345/.test(r.aviso), 'muestra lo que dice el comprobante y la cuenta del cliente');
  chk(/forzar/.test(r.aviso) && /NO se le mand/.test(r.aviso), 'explica que no se mando y como forzarlo');
  const soloNum = revisar({ es_comprobante: true, cuenta_destino: '0412-5550000', titular_destino: 'Luisa Prueba' }, UNA);
  chk(soloNum.cuadra === false, 'el numero se contradice aunque el nombre coincida: NO CUADRA', '-> ' + soloNum.motivo);
  const soloNom = revisar({ es_comprobante: true, titular_destino: 'Jose Otro Distinto' }, UNA);
  chk(soloNom.cuadra === false, 'sin numeros y el titular es otro: NO CUADRA', '-> ' + soloNom.motivo);
  const correo = revisar({ es_comprobante: true, correo_destino: 'otra.persona@example.com' }, [fila(5, [PUB_A], CTA_Z)]);
  chk(correo.cuadra === false, 'Zelle a otro correo: NO CUADRA', '-> ' + correo.motivo);
}

console.log('');
console.log('=== 3) Varias cuentas ===');
{
  const foto = revisar({ es_comprobante: true, cuenta_destino: '04120000099', titular_destino: 'Mario Inventado' }, DOS, { stanzaId: PUB_FOTO });
  chk(foto.cuadra && foto.filaId === 2 && foto.idCuenta === 'MSG-2', 'respondio a la FOTO: busca entre las cuentas y marca la B', '-> fila ' + foto.filaId);
  const otra = revisar({ es_comprobante: true, cuenta_destino: '04120000099', titular_destino: 'Mario Inventado' }, DOS, { stanzaId: PUB_A });
  chk(otra.cuadra && otra.filaId === 2, 'cito la cuenta A pero la foto es de la B (mismo cliente): se entrega y se marca la B', '-> fila ' + otra.filaId);
  const ninguna = revisar({ es_comprobante: true, cuenta_destino: '0102****7777' }, DOS, { stanzaId: PUB_FOTO });
  chk(ninguna.cuadra === false, 'respondio a la foto y no es de ninguna de sus cuentas: NO CUADRA', '-> ' + ninguna.motivo);
}

console.log('');
console.log('=== 4) No se pudo comparar: se entrega como antes ===');
{
  const borrosa = revisar({ es_comprobante: true, cuenta_destino: '', titular_destino: '' }, UNA);
  chk(borrosa.cuadra && !borrosa.verificado && borrosa.filaId === 1, 'no se leyo nada: se entrega (sin verificar)', '-> ' + borrosa.motivo);
  const efectivo = revisar({ es_comprobante: false }, UNA);
  chk(efectivo.cuadra && !efectivo.verificado, 'no es un comprobante (ej. foto de una entrega en efectivo): se entrega');
  chk(revisar('CAIDA', UNA).cuadra === true, 'si la IA falla: se entrega');
  chk(revisar('esto no es json', UNA).cuadra === true, 'si la IA contesta cualquier cosa: se entrega');
  const sinFilas = revisar({ es_comprobante: true, cuenta_destino: '0102****9876' }, []);
  chk(sinFilas.cuadra && sinFilas.filaId === null && sinFilas.idCuenta === 'MSG-PEDIDO', 'publicacion vieja (sin fila en Supabase): se entrega como antes');
  chk(revisar({ es_comprobante: true, cuenta_destino: '0102****9876' }, 'CAIDA').cuadra === true, 'si Supabase falla: se entrega');
}

console.log('');
console.log('=== 5) "forzar" ===');
{
  const f = revisar({ es_comprobante: true, cuenta_destino: '0102****9876' }, UNA, { forzar: true });
  chk(f.cuadra === true && f.filaId === 1, 'respondiendo el aviso con "forzar": se entrega aunque no cuadre', '-> ' + f.motivo);

  // Solo Estos Numeros: citar con "forzar" dispara la entrega con la marca
  const data = { key: { remoteJid: GRUPO, fromMe: false, id: 'TXT-1' }, pushName: 'Operadora', messageTimestamp: Math.floor(Date.now() / 1000),
                 message: { conversation: 'forzar' }, contextInfo: { stanzaId: 'AVISO-1', participant: '123@lid' } };
  const items = [{ json: { body: { data } } }];
  const tablas = { 'Clientes Detal Permitidos': [], 'Clientes Mayor Permitidos': [], 'Perfiles Detal App': [], 'Perfiles Mayor App': [], 'Redis Leer Pausa': [{}], 'Redis Leer Aviso': [{}] };
  const $ = n => n === 'Webhook Evolution API' ? { all: () => items, first: () => items[0] } : { all: () => (tablas[n] || []).map(json => ({ json })), first: () => ({ json: (tablas[n] || [{}])[0] }) };
  const s = new Function('$input', '$', code('Solo Estos Numeros'))({ all: () => [{ json: {} }] }, $);
  chk(s.length === 1 && s[0].json.accionPausa === 'entregar' && s[0].json.forzar === true, '"forzar" citando: entregar, con la marca de forzar');
  data.message = { conversation: '.' };
  const punto = new Function('$input', '$', code('Solo Estos Numeros'))({ all: () => [{ json: {} }] }, $);
  chk(punto[0].json.forzar === false, 'un "." no fuerza nada');

  // Revisar Pedido: si citaron el AVISO, la entrega es de la publicacion original, con la misma foto
  const aviso = JSON.stringify({ jid: '593990000001@s.whatsapp.net', nombre: 'Ana Prueba', idCuenta: 'MSG-1', idCaptura: 'CAP-1', publicacion: PUB_A, idFotoOperadora: 'FOTO-OP' });
  const rp = (forzar, idFoto, pedido) => new Function('$', code('Revisar Pedido'))(n => {
    if (n === 'Cuando lo Llama el Bot') return { first: () => ({ json: { stanzaId: 'AVISO-1', idFoto, jidGrupo: GRUPO, claveEntregado: 'entregado:AVISO-1', forzar } }) };
    if (n === 'Redis Leer Publicacion') return { first: () => ({ json: { pedido } }) };
    return { first: () => ({ json: {} }) };
  });
  const r = rp(true, '', aviso)[0].json;
  chk(r.forzar === true && r.stanzaId === PUB_A && r.claveEntregado === 'entregado:' + PUB_A, 'citando el aviso: vale "forzar" y se usa la publicacion original', '-> ' + r.stanzaId);
  chk(r.idFoto === 'FOTO-OP', 'y la misma foto que no cuadraba', '-> ' + r.idFoto);
  const nueva = rp(false, 'FOTO-NUEVA', aviso)[0].json;
  chk(nueva.forzar === false && nueva.idFoto === 'FOTO-NUEVA' && nueva.stanzaId === PUB_A, 'si responde el aviso con OTRA foto: se revisa esa (sin forzar)');
  const normal = JSON.stringify({ jid: '593990000001@s.whatsapp.net', nombre: 'Ana Prueba', idCuenta: 'MSG-1', idCaptura: 'CAP-1' });
  const sinAviso = rp(true, '', normal);
  chk(sinAviso.length === 0 || sinAviso[0].json.forzar === false, '"forzar" citando la publicacion (no el aviso) no salta la revision');
}

console.log('');
console.log('=== 6) Como quedo conectado ===');
{
  const sale = (n, i) => ((((wf.connections[n] || {}).main || [])[i || 0]) || []).map(c => c.node).join();
  const cadena = ['Bajar Foto Operadora', 'Foto Operadora a Binario', 'Leer Comprobante Operadora', 'Leer Cuentas de la Operacion', 'Revisar Comprobante', '¿Cuadra el Comprobante?'];
  for (let i = 0; i < cadena.length - 1; i++) chk(sale(cadena[i]) === cadena[i + 1], cadena[i] + ' -> ' + cadena[i + 1], '-> ' + sale(cadena[i]));
  chk(sale('¿Cuadra el Comprobante?', 0) === 'Enviar Comprobante al Cliente', 'si cuadra -> Enviar Comprobante al Cliente');
  chk(sale('¿Cuadra el Comprobante?', 1) === 'Avisar Comprobante No Cuadra' && sale('Avisar Comprobante No Cuadra') === 'Marcar Aviso No Cuadra',
      'si no cuadra -> Avisar Comprobante No Cuadra -> Marcar Aviso No Cuadra');
  const cond = nodo('¿Cuadra el Comprobante?').parameters.conditions.boolean[0];
  const pasa = j => new Function('$json', 'return (' + String(cond.value1).replace(/^=\{\{/, '').replace(/\}\}$/, '') + ');')(j);
  chk(pasa({ cuadra: true }) === true && pasa({ cuadra: false }) === false, 'el IF: cuadra -> entrega, no cuadra -> aviso');
  chk(pasa({ error: { message: 'algo fallo' } }) === true && nodo('Revisar Comprobante').onError === 'continueRegularOutput',
      'si la revision falla por un error: se entrega como antes');
  const leer = nodo('Leer Comprobante Operadora');
  chk(leer.parameters.modelId.value === 'gpt-4o' && /DESTINO/.test(leer.parameters.text), 'lee con GPT-4o, solo los datos del DESTINO');
  chk(leer.onError === 'continueRegularOutput' && !!leer.credentials, 'si la IA falla, sigue (y se entrega como antes)');
  const env = nodo('Enviar Comprobante al Cliente').parameters.jsonBody;
  chk(/Bajar Foto Operadora/.test(env) && /Revisar Comprobante/.test(env), 'manda la foto bajada y cita el mensaje de la cuenta que cuadro');
  const av = nodo('Avisar Comprobante No Cuadra').parameters.jsonBody;
  chk(/jidGrupo/.test(av) && /idFoto/.test(av) && /aviso/.test(av), 'el aviso va al grupo, citando la foto de la operadora');
  const marca = nodo('Marcar Aviso No Cuadra').parameters;
  chk(/publicacion/.test(marca.value) && /idFotoOperadora/.test(marca.value) && /grupoMsg:/.test(marca.key), 'se anota el aviso (para poder responderlo con "forzar")');
  const up = nodo('Marcar Enviada en Supabase').parameters.filterString;
  const ev = (filaId) => new Function('$', 'return (' + String(up).replace(/^=\{\{/, '').replace(/\}\}$/, '') + ');')(n => ({ first: () => ({ json: n === 'Revisar Comprobante' ? { filaId } : { stanzaId: PUB_A } }) }));
  chk(ev(7) === 'id=eq.7&estado=in.(en_proceso,en_espera)', 'marca enviada la fila de la cuenta que cuadro', '-> ' + ev(7));
  chk(ev(null) === 'id_msgs_grupo=cs.["' + PUB_A + '"]&estado=in.(en_proceso,en_espera)', 'sin fila elegida: por la publicacion, como antes', '-> ' + ev(null));
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
