# ============================================================================
#  WORKFLOW "Mayor: pasar RST al abrir"  (Cambios JK)  -  FASE 2
# ============================================================================
#  Los RST que llegan fuera de horario se publican en el grupo COBRAR MAÑANA. Los de Pichincha, Pacifico,
#  Bolivariano, Solidario, Austro... se vencen el MISMO dia (llevan "cobrar hoy" y se quedan ahi). Los de
#  Guayaquil y Produbanco duran 24 horas: la fila queda en estado 'en_cobrar_manana' y este workflow los pasa a
#  su grupo del banco cuando abre (lunes a sabado 9:05; domingo 10:05).
#
#    Cada Mañana -> Leer RST en Espera -> Leer Grupos Destino -> Armar Envios -> Enviar al Banco
#                    -> (Armar Mapa -> Redis Guardar Publicacion) y (Marcar Publicado)
#
#  - Solo trabaja en modo 'real' ($MAYOR_MODO en mayor_comun.ps1): en ensayo no hay filas esperando.
#  - Un RST de mas de 36 horas ya no se pasa (el codigo esta vencido): se avisa en el grupo de avisos.
#  - El destino sale SIEMPRE de la tabla grupos_mayor (por nombre), nunca de un id escrito aqui.
#
#  Genera workflow_mayor_noche.json. Se sube con scripts\desplegar_mayor_noche.ps1.
#  Se crea INACTIVO (tiene un cron): Kelvin lo activa a mano en n8n cuando pase el mayor a modo real.
# ============================================================================
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'mayor_comun.ps1')
$HORAS_MAPA_PUBLICACION = 24 * 7

$supaCred  = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
$redisCred = @{ redis = @{ id = 'SKkvpS5A65SOcmJs'; name = 'Redis memoria para Cambios JK' } }

# ===================== CODIGO: ARMAR ENVIOS =====================
$armarEnviosCode = @'
// ===== LOS RST QUE ESPERAN EN COBRAR MAÑANA Y SE PASAN A SU BANCO AL ABRIR =====
// Lee las filas 'en_cobrar_manana' (los retiros de Guayaquil y Produbanco de la noche) y arma, por cada retiro,
// el bloque para su grupo del banco. No manda nada: lo manda "Enviar al Banco".
const MODO = '__MODO__';
const GRUPO_AVISOS = '__GRUPO_AVISOS__';
const HORAS_MAX = 36;                       // un codigo de 24 h con mas de 36 h ya esta vencido
__PUBLICAR_COMUN__
if (MODO !== 'real') return [];
const destinos = {};
try { for (const it of $('Leer Grupos Destino').all()){ const g = it.json || {}; if (g.grupo_jid && g.nombre && g.activo !== false) destinos[quitar(g.nombre)] = g.grupo_jid; } } catch(e){}
let filas = [];
try { filas = $('Leer RST en Espera').all().map(i => i.json).filter(r => r && r.id && !r.error); } catch(e){ filas = []; }
const ahora = Date.now();
const out = [];
const aviso = (fila, texto, estado) => out.push({ json: { tipo: 'texto', jid: GRUPO_AVISOS, texto, fila_id: fila.id, estado_fila: estado, grupo_destino: '' } });
for (const f of filas){
  const nombre = String(f.cliente_nombre || 'Cliente');
  const edadH = (ahora - Date.parse(f.creado)) / 3600000;
  const todos = (((f.datos || {}).registros) || []).filter(r => r.tipo === 'rst' || r.tipo === 'rct');
  const regs = todos.filter(r => DURA_24H.indexOf(claveBanco(r)) !== -1 && faltan(r).length === 0 && revisar(r).length === 0);
  // JEP: el cliente pidio hacer un RST de noche. Su codigo dura 15 minutos: aqui solo se le PIDE al cobrador que vaya al cajero.
  const jepRst = todos.filter(r => r.tipo === 'rst' && claveBanco(r) === 'jep');
  const pideJep = jepRst.length > 0 || quiereJep(f.texto);
  if (!regs.length && !pideJep){ aviso(f, '⚠️ ' + nombre + ': tenía un RST esperando en COBRAR MAÑANA pero no encuentro qué pasar al banco. Revísalo a mano.', 'sin_grupo'); continue; }
  if (!(edadH <= HORAS_MAX)){ aviso(f, '⚠️ ' + nombre + ': su RST de ' + regs.map(r => r.banco).concat(pideJep ? ['JEP'] : []).join(', ') + ' llevaba más de ' + HORAS_MAX + ' horas esperando en COBRAR MAÑANA y ya está vencido: NO se pasó al banco. Pídele uno nuevo.', 'vencido'); continue; }
  for (const reg of regs){
    const dueno = GRUPO_DEL_BANCO[claveBanco(reg)], jid = dueno ? destinos[dueno] : null;
    if (!jid){ aviso(f, '⚠️ ' + nombre + ': su RST de ' + reg.banco + ' NO se pasó (no encuentro el grupo ' + NOMBRE_GRUPO(dueno || claveBanco(reg)) + '). Pásalo a mano.', 'sin_grupo'); continue; }
    out.push({ json: { tipo: 'texto', jid, texto: bloque(nombre, reg, false), fila_id: f.id, estado_fila: 'publicado', grupo_destino: NOMBRE_GRUPO(dueno),
                       mapa: { cliente_jid: f.grupo_jid, cliente_nombre: nombre, id_msg_cliente: f.mensaje_id, banco: reg.banco, tipo: reg.tipo, fila_id: f.id, destino: NOMBRE_GRUPO(dueno) },
                       // El reloj de estos codigos (24 h) corre desde que el cliente los mando: se vigilan desde que llegan a su banco.
                       vigila: reg.tipo === 'rst' ? { banco: claveBanco(reg), recibido: f.fecha_mensaje || f.creado, resumen: nombre + ' · ' + String(reg.banco || '').toUpperCase() + ' ' + fmtMonto(reg.monto_usd) + '$' } : undefined } });
  }
  if (pideJep){
    const dueno = GRUPO_DEL_BANCO.jep, jid = destinos[dueno];
    if (!jid){ aviso(f, '⚠️ ' + nombre + ': su pedido de JEP NO se pasó (no encuentro el grupo ' + NOMBRE_GRUPO(dueno) + '). Avísale al cobrador a mano.', 'sin_grupo'); continue; }
    const montos = jepRst.map(r => r.monto_usd).filter(m => m !== null && m !== undefined);
    out.push({ json: { tipo: 'texto', jid, texto: jepSolicitud(nombre, montos), fila_id: f.id, estado_fila: regs.length ? 'publicado' : 'jep_esperando', grupo_destino: NOMBRE_GRUPO(dueno),
                       mapa: { cliente_jid: f.grupo_jid, cliente_nombre: nombre, id_msg_cliente: f.mensaje_id, banco: 'JEP', tipo: 'rst', fila_id: f.id, destino: NOMBRE_GRUPO(dueno), jep: 'solicitud' },
                       // Si en 30 minutos el cobrador no contesta, "Mayor: alertas de vencimiento" avisa en el grupo de avisos.
                       vigila: { banco: 'jep_pedido', recibido: new Date(ahora).toISOString(), resumen: nombre + ' · JEP' + (montos.length ? ' ' + fmtMonto(montos[0]) + '$' : '') } } });
  }
}
return out;
'@
$armarEnviosCode = $armarEnviosCode.Replace('__PUBLICAR_COMUN__', $publicarJs).Replace('__MODO__', $MAYOR_MODO).Replace('__GRUPO_AVISOS__', $GRUPO_AVISOS)

# ===================== CODIGO: ARMAR MAPA =====================
# ===================== CODIGO: ARMAR VIGILANCIA =====================
$armarVigilanciaCode = Get-ArmarVigilanciaCode 'Armar Envios'

# ===================== CODIGO: ARMAR MAPA =====================
$armarMapaCode = @'
// De cada RST que llego bien al grupo del banco se anota "este mensaje corresponde a este cliente", para poder
// avisarle cuando el banco responda "Verificar" o "se dañó" (lo hace el workflow "Mayor: escuchar y registrar").
const out = [];
const entradas = $input.all();
for (let i = 0; i < entradas.length; i++){
  let acc = null;
  try { acc = $('Armar Envios').itemMatching(i).json; } catch(e){ continue; }
  const r = entradas[i].json || {};
  const id = (r.key && r.key.id) || (r.data && r.data.key && r.data.key.id) || '';
  if (acc && acc.mapa && id && !r.error) out.push({ json: { clave: 'mayorPub:' + id, valor: JSON.stringify(acc.mapa) } });
}
return out;
'@

$nota = @'
## Mayor: pasar RST al abrir (FASE 2)
Los RST que llegaron **fuera de horario** esperan en el grupo **COBRAR MAÑANA**.

- Los de **Guayaquil y Produbanco** (el codigo dura 24 horas): este workflow los pasa a su grupo del banco cuando abre (lunes a sabado 9:05, domingo 10:05).
- Los de **Pichincha, Pacifico, Bolivariano, Solidario, Austro...** se vencen el mismo dia: llevan "cobrar hoy" y se quedan en COBRAR MAÑANA (no pasan por aqui).
- **JEP**: su codigo dura 15 minutos, asi que de noche solo se le avisa al cliente cuando abrimos; aqui se le **pide al cobrador** (en el grupo de JEP) que vaya a un cajero y avise. El RST lo manda el cliente despues.
- Un RST de mas de 36 horas ya no se pasa: se avisa en el grupo de avisos.
- Cada RST de 24 horas que llega a su banco se anota para las **alertas de vencimiento** (tabla `vigilancia_rst_mayor`).

Solo trabaja en **modo real**. Se crea INACTIVO: se activa a mano cuando el mayor pase a modo real. Se genera con `build_mayor_noche.ps1`.
'@

$nodes = @(
  [ordered]@{
    parameters = @{ content = $nota; height = 440; width = 520; color = 4 }
    id = 'd2e3f4a5-0000-4c00-8c00-mayornoche00'; name = 'Nota'; type = 'n8n-nodes-base.stickyNote'; typeVersion = 1; position = @(-40,-120)
  },
  [ordered]@{
    parameters = @{ rule = @{ interval = @( @{ field = 'cronExpression'; expression = '0 5 9 * * 1-6' }, @{ field = 'cronExpression'; expression = '0 5 10 * * 0' } ) } }
    id = 'd2e3f4a5-0001-4c00-8c00-mayornoche01'; name = 'Cada Mañana'; type = 'n8n-nodes-base.scheduleTrigger'; typeVersion = 1.1; position = @(0,300)
  },
  [ordered]@{
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'transacciones_mayor_por_whatsapp'; returnAll = $true; filterType = 'string'; filterString = 'estado=eq.en_cobrar_manana&order=creado.asc' }
    id = 'd2e3f4a5-0002-4c00-8c00-mayornoche02'; name = 'Leer RST en Espera'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(176,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $supaCred
  },
  [ordered]@{
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'grupos_mayor'; returnAll = $true; filterType = 'string'; filterString = 'tipo=eq.destino' }
    id = 'd2e3f4a5-0003-4c00-8c00-mayornoche03'; name = 'Leer Grupos Destino'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(352,300)
    executeOnce = $true; onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $supaCred
  },
  [ordered]@{
    parameters = @{ jsCode = $armarEnviosCode }
    id = 'd2e3f4a5-0004-4c00-8c00-mayornoche04'; name = 'Armar Envios'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(528,300)
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true
                    headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'
                    jsonBody = '={{ JSON.stringify({ number: $json.jid, text: $json.texto }) }}'; options = @{} }
    id = 'd2e3f4a5-0005-4c00-8c00-mayornoche05'; name = 'Enviar al Banco'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(704,300)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = $evoHeaderCred
  },
  [ordered]@{
    parameters = @{ resource = 'row'; operation = 'update'; tableId = 'transacciones_mayor_por_whatsapp'; filterType = 'string'
                    filterString = '={{ "id=eq." + $("Armar Envios").item.json.fila_id }}'; dataToSend = 'defineBelow'
                    fieldsUi = @{ fieldValues = @(
                      @{ fieldId = 'estado'; fieldValue = '={{ $json.error ? "error_envio" : $("Armar Envios").item.json.estado_fila }}' },
                      @{ fieldId = 'grupo_destino'; fieldValue = '={{ $("Armar Envios").item.json.grupo_destino || "" }}' } ) } }
    id = 'd2e3f4a5-0006-4c00-8c00-mayornoche06'; name = 'Marcar Publicado'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(880,120)
    onError = 'continueRegularOutput'; credentials = $supaCred
  },
  [ordered]@{
    parameters = @{ jsCode = $armarMapaCode }
    id = 'd2e3f4a5-0007-4c00-8c00-mayornoche07'; name = 'Armar Mapa'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(880,300)
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = '={{ $json.clave }}'; value = '={{ $json.valor }}'; keyType = 'string'; expire = $true; ttl = ($HORAS_MAPA_PUBLICACION * 3600) }
    id = 'd2e3f4a5-0008-4c00-8c00-mayornoche08'; name = 'Redis Guardar Publicacion'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1056,300)
    onError = 'continueRegularOutput'; credentials = $redisCred
  },
  # Alertas de vencimiento: el RST de 24 h que acaba de llegar a su banco se anota para vigilarlo (sale de "Armar Envios").
  [ordered]@{
    parameters = @{ jsCode = $armarVigilanciaCode }
    id = 'd2e3f4a5-0009-4c00-8c00-mayornoche09'; name = 'Armar Vigilancia'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(880,480)
  },
  [ordered]@{
    parameters = @{ resource = 'row'; operation = 'create'; tableId = 'vigilancia_rst_mayor'; dataToSend = 'autoMapInputData'; inputsToIgnore = '' }
    id = 'd2e3f4a5-0010-4c00-8c00-mayornoche10'; name = 'Anotar Vigilancia'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(1056,480)
    onError = 'continueRegularOutput'; credentials = $supaCred
  }
)

$connections = [ordered]@{
  'Cada Mañana'         = @{ main = @( ,@( @{ node='Leer RST en Espera'; type='main'; index=0 } ) ) }
  'Leer RST en Espera'  = @{ main = @( ,@( @{ node='Leer Grupos Destino'; type='main'; index=0 } ) ) }
  'Leer Grupos Destino' = @{ main = @( ,@( @{ node='Armar Envios'; type='main'; index=0 } ) ) }
  'Armar Envios'        = @{ main = @( ,@( @{ node='Enviar al Banco'; type='main'; index=0 } ) ) }
  'Enviar al Banco'     = @{ main = @( ,@( @{ node='Armar Mapa'; type='main'; index=0 }, @{ node='Marcar Publicado'; type='main'; index=0 }, @{ node='Armar Vigilancia'; type='main'; index=0 } ) ) }
  'Armar Mapa'          = @{ main = @( ,@( @{ node='Redis Guardar Publicacion'; type='main'; index=0 } ) ) }
  'Armar Vigilancia'    = @{ main = @( ,@( @{ node='Anotar Vigilancia'; type='main'; index=0 } ) ) }
}

$wf = [ordered]@{
  name = 'Mayor: pasar RST al abrir'
  nodes = $nodes
  connections = $connections
  settings = [ordered]@{ executionOrder = 'v1'; timezone = 'America/Guayaquil' }
}
$salida = Join-Path $PSScriptRoot 'workflow_mayor_noche.json'
$json = $wf | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($salida, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('JSON generado: ' + $salida + ' | nodos: ' + $nodes.Count)
