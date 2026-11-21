param([switch]$Prueba, [string]$ImagenPrueba = '', [string]$NumeroPrueba = '', [string]$SoloNumero = '')
# ============================================================================
#  WORKFLOW "Liberar operaciones de la noche"  (Cambios JK)
# ============================================================================
#  Lunes a sabado 9:05 y domingo 10:05 (hora de Ecuador).
#
#  De noche el bot de WhatsApp atiende, pero las operaciones completas (captura +
#  cuenta) NO las pasa a transferir: las deja en Supabase (transacciones_por_whatsapp)
#  con estado 'en_espera', una fila por cuenta destino. Este workflow las toma al
#  abrir y, una operacion por vez:
#    1. publica la captura y cada cuenta en el grupo de transferir, igual que de dia
#    2. guarda en Redis (grupoMsg:<id>) de quien es cada publicacion, para que la foto
#       que devuelva la operadora le llegue al cliente
#    3. le manda al cliente el sticker de PEDIDO APROBADO
#    4. pasa las filas a 'en_proceso'
#
#  Genera workflow_liberar_noche.json. Se sube con scripts\desplegar_liberar.ps1.
#  Se crea INACTIVO: lo activa Kelvin desde n8n.
#
#  PRUEBA sin tocar transferir ni Supabase:
#      powershell -ExecutionPolicy Bypass -File build_liberar_noche.ps1 -Prueba -ImagenPrueba <id de una imagen> -NumeroPrueba <numero admin>
#  publica en el grupo de AVISOS una operacion inventada de un numero ADMIN (nunca de un cliente), y la
#  actualizacion final apunta a una fila que no existe (id -1).
#
#  PRUEBA con filas REALES de un solo numero (el admin), publicando en AVISOS:
#      powershell -ExecutionPolicy Bypass -File build_liberar_noche.ps1 -SoloNumero <numero admin>
# ============================================================================
$ErrorActionPreference = 'Stop'

$GRUPO_OPERACIONES = '593961230380-1601657528@g.us'   # grupo de transferir (igual que el bot)
$GRUPO_AVISOS      = '120363413942097019@g.us'        # grupo "Notificaciones Clientes" (solo para la prueba)
$SEG_MEMORIA_PUBLICACION = 48 * 3600                   # igual que el bot: grupoMsg dura 48 h

$grupo = $(if ($Prueba -or $SoloNumero) { $GRUPO_AVISOS } else { $GRUPO_OPERACIONES })
$filtroEspera = 'estado=eq.en_espera&order=creado.asc'
if ($SoloNumero) { $filtroEspera = 'estado=eq.en_espera&whatsapp=eq.' + ($SoloNumero -replace '\D','') + '&order=creado.asc' }
$filasPrueba = 'null'
if ($Prueba) {
  if (-not $ImagenPrueba -or -not $NumeroPrueba) { throw 'Para la prueba hacen falta -ImagenPrueba (id de una imagen que tenga Evolution) y -NumeroPrueba (un numero ADMIN).' }
  # Operacion INVENTADA de un numero admin (nunca de un cliente). El numero no se escribe aqui: el repositorio es publico.
  $filasPrueba = '[{ "id": -1, "creado": "2026-11-20T03:00:00Z", "whatsapp": "' + ($NumeroPrueba -replace '\D','') + '", "nombre_cliente": "PRUEBA (no transferir)", "estado": "en_espera", "id_msg_captura": "' + $ImagenPrueba + '", "cuentas": [{ "id": "", "texto": "PRUEBA - NO TRANSFERIR\nBanco Ejemplo\n01020000000000099999\nTitular Inventado\nV 11111111\n$1", "monto": 1 }] }]'
}

$evolution = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
$redisCred = @{ redis = @{ id = 'SKkvpS5A65SOcmJs'; name = 'Redis memoria para Cambios JK' } }
$supaCred  = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
$jsonHeader = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }

# ===================== CODIGO: AGRUPAR OPERACIONES =====================
$agruparCode = @'
// Las operaciones que llegaron fuera de horario (estado 'en_espera'), una por deposito: las cuentas
// de un mismo deposito comparten id_msg_captura. Se publican en el orden en que llegaron.
// Si no hay ninguna, el workflow termina aqui sin hacer nada.
const PRUEBA = __FILAS_PRUEBA__;
const listaDe = v => { if (Array.isArray(v)) return v; try { const x = JSON.parse(v); return Array.isArray(x) ? x : []; } catch(e){ return []; } };
const filas = (PRUEBA || $input.all().map(i => i.json))
  .filter(r => r && r.id !== undefined && r.id !== null && !r.error && r.estado === 'en_espera')
  .sort((a, b) => ((Date.parse(a.creado) || 0) - (Date.parse(b.creado) || 0)) || (a.id - b.id));
const ops = [], donde = {};
for (const r of filas){
  const clave = r.id_msg_captura || ('fila-' + r.id);
  if (donde[clave] === undefined){
    const w = String(r.whatsapp || '');
    donde[clave] = ops.length;
    ops.push({ jid: w.indexOf('@') !== -1 ? w : w + '@s.whatsapp.net', nombre: r.nombre_cliente || 'Cliente',
               idImagen: r.id_msg_captura || '', filas: [] });
  }
  const op = ops[donde[clave]];
  const c = listaDe(r.cuentas)[0] || {};
  const monto = (typeof c.monto === 'number') ? c.monto : null;
  // La misma cabecera que de dia: "nombre - $monto".
  op.filas.push({ filaId: r.id, idCuenta: c.id || '', monto,
                  cuenta: op.nombre + (monto !== null ? ' - $' + monto : '') + '\n\n' + String(c.texto || '(sin datos de la cuenta: revisar el chat)') });
}
return ops.map(o => ({ json: o }));
'@
$agruparCode = $agruparCode.Replace('__FILAS_PRUEBA__', $filasPrueba)

# ===================== CODIGO: SEPARAR CUENTAS DE LA OPERACION =====================
$separarCode = @'
// Una publicacion por cuenta de ESTA operacion. La foto de la captura va con la primera cuenta:
// si la operadora responde a la foto en vez de a la cuenta, se marca esa.
const op = $('Una por Una').first().json;
const idDe = j => String((j && j.key && j.key.id) || (j && j.data && j.data.key && j.data.key.id) || '');
let idFoto = '';
try { idFoto = idDe($('Publicar Captura').first().json); } catch(e){}
return (op.filas || []).map((f, i) => ({ json: Object.assign({}, f, { idFoto: i === 0 ? idFoto : '' }) }));
'@

# ===================== CODIGO: ARMAR ACTUALIZACION =====================
$actualizarCode = @'
// Lo que se guarda en cada fila: ya esta en transferir ('en_proceso'), cuando, y el id de su
// publicacion (con eso el bot la marca 'enviada' cuando la operadora devuelva la foto).
const separadas = $('Separar Cuentas de la Operacion').all().map(i => i.json);
const enviadas = $('Publicar Cuenta').all().map(i => i.json);
const idDe = j => String((j && j.key && j.key.id) || (j && j.data && j.data.key && j.data.key.id) || '');
const ahora = new Date().toISOString();
return separadas.map((f, i) => ({ json: { filaId: f.filaId, estado: 'en_proceso', publicado_en: ahora,
                                          id_msgs_grupo: [idDe(enviadas[i]), f.idFoto].filter(Boolean) } }));
'@

$nota = @'
## Liberar operaciones de la noche
**Lunes a sábado 9:05 y domingo 10:05** (hora de Ecuador).

De noche el bot atiende, pero NO pasa las operaciones a transferir: las deja en Supabase (`transacciones_por_whatsapp`) con estado **en_espera**. Este workflow, al abrir, toma cada una y:
1. publica la captura y cada cuenta en el grupo de transferir, igual que de día
2. guarda de quién es cada publicación, para que la foto de la operadora le llegue al cliente
3. le manda al cliente el sticker **PEDIDO APROBADO**
4. pasa las filas a **en_proceso**

Credenciales: Evolution apikey Kelvin 0380, Redis memoria para Cambios JK, Supabase Cambios JK.
Se genera con `build_liberar_noche.ps1`. No lo edites aquí: se pisa en el próximo despliegue.
'@

$valorGrupoMsg = "={{ JSON.stringify({ jid: `$('Una por Una').first().json.jid, nombre: `$('Una por Una').first().json.nombre, idCuenta: __IDCUENTA__, idCaptura: `$('Una por Una').first().json.idImagen }) }}"
$claveGrupoMsg = "={{ 'grupoMsg:' + ((`$json.key && `$json.key.id) || (`$json.data && `$json.data.key && `$json.data.key.id) || 'nada') }}"

$nodes = @(
  [ordered]@{
    parameters = @{ content = $nota; height = 360; width = 520; color = 4 }
    id = 'b1c2d3e4-0000-4a00-8a00-liberar00000'; name = 'Nota'; type = 'n8n-nodes-base.stickyNote'; typeVersion = 1; position = @(-40,-120)
  },
  [ordered]@{
    parameters = @{ rule = @{ interval = @( @{ field = 'cronExpression'; expression = '0 5 9 * * 1-6' }, @{ field = 'cronExpression'; expression = '0 5 10 * * 0' } ) } }
    id = 'b1c2d3e4-0001-4a00-8a00-liberar00001'; name = 'Cada Mañana'; type = 'n8n-nodes-base.scheduleTrigger'; typeVersion = 1.1; position = @(0,300)
  },
  [ordered]@{
    # Las filas en espera, la mas vieja primero. Si Supabase falla, no se publica nada (se reintenta
    # al dia siguiente; Kelvin ve el error en las ejecuciones).
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'transacciones_por_whatsapp'; returnAll = $true; filterType = 'string'; filterString = $filtroEspera }
    id = 'b1c2d3e4-0002-4a00-8a00-liberar00002'; name = 'Leer Operaciones en Espera'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(176,300)
    alwaysOutputData = $true; credentials = $supaCred
  },
  [ordered]@{
    parameters = @{ jsCode = $agruparCode }
    id = 'b1c2d3e4-0003-4a00-8a00-liberar00003'; name = 'Agrupar Operaciones'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(352,300)
  },
  [ordered]@{
    # Una operacion por vez: asi en el grupo queda cada captura seguida de SUS cuentas.
    parameters = @{ batchSize = 1; options = @{} }
    id = 'b1c2d3e4-0004-4a00-8a00-liberar00004'; name = 'Una por Una'; type = 'n8n-nodes-base.splitInBatches'; typeVersion = 3; position = @(528,300)
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/chat/getBase64FromMediaMessage/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = $jsonHeader; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "message": { "key": { "id": "{{ $json.idImagen }}" } }, "convertToMp4": false }'; options = @{} }
    id = 'b1c2d3e4-0005-4a00-8a00-liberar00005'; name = 'Bajar Captura'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(704,300)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true; credentials = $evolution
  },
  [ordered]@{
    # La foto de la captura con "Cliente: <nombre>". Si no se pudo bajar, va un texto avisando,
    # para que la operadora no se quede sin saber de quien son las cuentas que siguen.
    parameters = @{ method = 'POST'; url = '={{ $json.base64 ? "http://evolution-api:8080/message/sendMedia/BOT%20JK%20Kelvin" : "http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin" }}'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = $jsonHeader; sendBody = $true; specifyBody = 'json'; jsonBody = '={{ JSON.stringify($json.base64 ? { number: "' + $grupo + '", mediatype: "image", mimetype: ($json.mimetype || "image/jpeg"), media: $json.base64, caption: ("Cliente: " + $("Una por Una").first().json.nombre) } : { number: "' + $grupo + '", text: ("Cliente: " + $("Una por Una").first().json.nombre + "\n(No se pudo bajar la foto de la captura: revisala en el chat del cliente)") }) }}'; options = @{} }
    id = 'b1c2d3e4-0006-4a00-8a00-liberar00006'; name = 'Publicar Captura'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(880,300)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true; credentials = $evolution
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = $claveGrupoMsg; value = $valorGrupoMsg.Replace('__IDCUENTA__', "((`$('Una por Una').first().json.filas[0] || {}).idCuenta || '')"); keyType = 'string'; expire = $true; ttl = $SEG_MEMORIA_PUBLICACION }
    id = 'b1c2d3e4-0007-4a00-8a00-liberar00007'; name = 'Marcar Publicacion Captura'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1056,300)
    onError = 'continueRegularOutput'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendSticker/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = $jsonHeader; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "number": "{{ $("Una por Una").first().json.jid }}", "sticker": "https://grupojk-cambios.github.io/grupojk-conversor/logos/sticker-pedido-aprobado.webp" }'; options = @{} }
    id = 'b1c2d3e4-0008-4a00-8a00-liberar00008'; name = 'Sticker Pedido Aprobado'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1232,300)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true; credentials = $evolution
  },
  [ordered]@{
    parameters = @{ jsCode = $separarCode }
    id = 'b1c2d3e4-0009-4a00-8a00-liberar00009'; name = 'Separar Cuentas de la Operacion'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1408,300)
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = $jsonHeader; sendBody = $true; specifyBody = 'json'; jsonBody = '={{ JSON.stringify({ number: "' + $grupo + '", text: $json.cuenta }) }}'; options = @{} }
    id = 'b1c2d3e4-0010-4a00-8a00-liberar00010'; name = 'Publicar Cuenta'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1584,300)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true; credentials = $evolution
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = $claveGrupoMsg; value = $valorGrupoMsg.Replace('__IDCUENTA__', "(`$('Separar Cuentas de la Operacion').item.json.idCuenta || '')"); keyType = 'string'; expire = $true; ttl = $SEG_MEMORIA_PUBLICACION }
    id = 'b1c2d3e4-0011-4a00-8a00-liberar00011'; name = 'Marcar Publicacion Cuenta'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1760,300)
    onError = 'continueRegularOutput'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $actualizarCode }
    id = 'b1c2d3e4-0012-4a00-8a00-liberar00012'; name = 'Armar Actualizacion'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1936,300)
  },
  [ordered]@{
    # Solo si sigue en espera: si por algo ya se habia publicado, no se toca.
    parameters = @{ resource = 'row'; operation = 'update'; tableId = 'transacciones_por_whatsapp'; filterType = 'string'; filterString = "={{ 'id=eq.' + `$json.filaId + '&estado=eq.en_espera' }}"; dataToSend = 'autoMapInputData'; inputsToIgnore = 'filaId' }
    id = 'b1c2d3e4-0013-4a00-8a00-liberar00013'; name = 'Marcar En Proceso'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(2112,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $supaCred
  }
)

$connections = [ordered]@{
  'Cada Mañana'                     = @{ main = @( ,@( @{ node='Leer Operaciones en Espera'; type='main'; index=0 } ) ) }
  'Leer Operaciones en Espera'      = @{ main = @( ,@( @{ node='Agrupar Operaciones'; type='main'; index=0 } ) ) }
  'Agrupar Operaciones'             = @{ main = @( ,@( @{ node='Una por Una'; type='main'; index=0 } ) ) }
  # Salida 0 = "listo" (ya no quedan): no hace nada. Salida 1 = la operacion de esta vuelta.
  'Una por Una'                     = @{ main = (@( ,@() ) + @( ,@( @{ node='Bajar Captura'; type='main'; index=0 } ) )) }
  'Bajar Captura'                   = @{ main = @( ,@( @{ node='Publicar Captura'; type='main'; index=0 } ) ) }
  'Publicar Captura'                = @{ main = @( ,@( @{ node='Marcar Publicacion Captura'; type='main'; index=0 } ) ) }
  'Marcar Publicacion Captura'      = @{ main = @( ,@( @{ node='Sticker Pedido Aprobado'; type='main'; index=0 } ) ) }
  'Sticker Pedido Aprobado'         = @{ main = @( ,@( @{ node='Separar Cuentas de la Operacion'; type='main'; index=0 } ) ) }
  'Separar Cuentas de la Operacion' = @{ main = @( ,@( @{ node='Publicar Cuenta'; type='main'; index=0 } ) ) }
  'Publicar Cuenta'                 = @{ main = @( ,@( @{ node='Marcar Publicacion Cuenta'; type='main'; index=0 } ) ) }
  'Marcar Publicacion Cuenta'       = @{ main = @( ,@( @{ node='Armar Actualizacion'; type='main'; index=0 } ) ) }
  'Armar Actualizacion'             = @{ main = @( ,@( @{ node='Marcar En Proceso'; type='main'; index=0 } ) ) }
  # Vuelve al principio por la siguiente operacion.
  'Marcar En Proceso'               = @{ main = @( ,@( @{ node='Una por Una'; type='main'; index=0 } ) ) }
}

$wf = [ordered]@{
  name = 'Liberar operaciones de la noche'
  nodes = $nodes
  connections = $connections
  settings = [ordered]@{ executionOrder = 'v1'; timezone = 'America/Guayaquil' }
}
$salida = Join-Path $PSScriptRoot 'workflow_liberar_noche.json'
$json = $wf | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($salida, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('JSON generado: ' + $salida + ' | nodos: ' + $nodes.Count + ' | grupo: ' + $(if ($Prueba -or $SoloNumero) { 'AVISOS (prueba)' } else { 'transferir' }) + ' | filtro: ' + $filtroEspera)
