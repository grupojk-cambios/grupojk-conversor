# ============================================================================
#  WORKFLOW "Avisar deposito que no cuadra"  (Cambios JK)
# ============================================================================
#  Pedido de Kelvin (23/11): cuando el deposito del cliente NO cuadra con la suma de sus cuentas,
#  el bot NO pasa la operacion a transferir y le pide al cliente que confirme los montos. Si el
#  cliente lo arregla, se procesa sola. Este workflow hace lo que pasa DESPUES, en dos modos:
#
#  modo 'vigilar' (el bot lo llama la PRIMERA vez que ve que no cuadra, y no lo espera):
#    Esperar 5 min -> si no lo arreglo: le RECUERDA al cliente
#      ("Por favor confirmame los montos de las cuentas para poder procesar tu operacion")
#    Esperar 5 min mas -> si sigue sin arreglarlo: AVISA al grupo de avisos
#
#  modo 'escalar' (el cliente dijo que esta bien asi): deja un aviso en el grupo de TRANSFERIR
#    para que lo revise un asesor (NO se transfiere).
#
#  "Arreglado" = la operacion del cliente (op:<chat> en Redis) ya no tiene la marca "no cuadra" del
#  MISMO momento (se proceso, lo corrigio o vencio), o ya paso a un asesor ('escalado').
#
#  Genera workflow_vigilar_monto.json. Se sube con scripts\desplegar_vigilar_monto.ps1.
#  Se creo INACTIVO; Kelvin lo publico a mano en n8n (el bot no se puede desplegar llamandolo
#  mientras no este publicado).
# ============================================================================
$ErrorActionPreference = 'Stop'

$MINUTOS_RECORDAR = 5                            # cuanto espera antes de recordarle al cliente
$MINUTOS_AVISAR = 5                              # y despues cuanto mas, antes de avisar al grupo
$GRUPO_AVISOS = '120363413942097019@g.us'        # grupo "Notificaciones Clientes"
$GRUPO_OPERACIONES = '593961230380-1601657528@g.us'   # grupo de TRANSFERIR

$redisCred = @{ redis = @{ id = 'SKkvpS5A65SOcmJs'; name = 'Redis memoria para Cambios JK' } }
$evoCred   = @{ evolutionApi = @{ id = 'iUIvc9Sd8diFJaGU'; name = 'Evolution PARA n8n cambios JK' } }

# Lo que comparten los nodos de codigo: leer la marca y escribir los montos.
$comunJs = @'
const ent = $('Cuando lo Llama el Bot').first().json || {};
// La marca "no cuadra" de la operacion del cliente, solo si es la MISMA que se vigila (mismo token).
function marcaVigente(nodoRedis){
  let op = {};
  try {
    const raw = $(nodoRedis).first().json.operacion;
    if (raw) op = (typeof raw === 'string') ? JSON.parse(raw) : raw;
  } catch(e){ op = {}; }
  const nc = (op && typeof op === 'object') ? op.noCuadra : null;
  if (!nc || !ent.token || Number(nc.ts) !== Number(ent.token)) return null;
  return nc;
}
// Como se escribe un monto: "$10", "$10.50", "12.000 Bs", "100.000 COP".
function montoTexto(n, moneda){
  if (typeof n !== 'number' || isNaN(n)) return '?';
  const dec = Math.round(n * 100) % 100 !== 0;
  if (!moneda || moneda === 'USD') return '$' + (dec ? n.toFixed(2) : String(Math.round(n)));
  const partes = (dec ? n.toFixed(2) : String(Math.round(n))).split('.');
  const miles = partes[0].replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return miles + (partes[1] ? ',' + partes[1] : '') + ' ' + (moneda === 'VES' ? 'Bs' : moneda);
}
function resumen(nc){
  const mon = nc.moneda || ent.moneda || 'USD';
  const montos = (Array.isArray(nc.montos) ? nc.montos : []).filter(m => typeof m === 'number');
  const numero = String(ent.numero || String(ent.jid || '').split('@')[0]);
  return 'Cliente: ' + (ent.nombre || 'Cliente') + (/^[0-9]{8,}$/.test(numero) ? ' (+' + numero + ')' : '') + '\n'
    + 'Depósito: ' + montoTexto(nc.deposito, mon) + '\n'
    + (montos.length > 1 ? ('Cuentas: ' + montos.map(m => montoTexto(m, mon)).join(' + ') + ' = ' + montoTexto(nc.suma, mon))
                         : ('Cuenta: ' + montoTexto(nc.suma, mon)));
}
'@

# ===================== CODIGO: ARMAR AVISO TRANSFERIR (modo escalar) =====================
$avisoTransferirCode = @'
// El cliente dice que esta bien asi, aunque el deposito no cuadra con sus cuentas: lo revisa un asesor.
// Se deja un aviso en el grupo de TRANSFERIR para que nadie la transfiera sin revisarla.
__COMUN__
const nc = { deposito: ent.deposito, suma: ent.suma, montos: ent.montos, moneda: ent.moneda };
const aviso = '⚠️ PARA REVISAR, NO TRANSFERIR TODAVÍA\n\n' + resumen(nc) + '\n\n'
  + 'El depósito no cuadra con las cuentas y el cliente dice que está bien así. Lo revisa un asesor.';
return [{ json: { aviso } }];
'@
$avisoTransferirCode = $avisoTransferirCode.Replace('__COMUN__', $comunJs)

# ===================== CODIGO: DECIDIR RECORDATORIO (a los 5 minutos) =====================
$decidirRecordatorioCode = @'
// A los 5 minutos: si todavia no lo arreglo (y no paso a un asesor), se le recuerda al cliente.
// Si ya se le pidio la captura del otro deposito, se le recuerda eso.
__COMUN__
const nc = marcaVigente('Redis Leer Operacion');
if (!nc || nc.paso === 'escalado' || !ent.jid) return [];
const texto = (nc.paso === 'pidio_captura')
  ? 'Por favor envíame la captura del otro depósito para poder procesar tu operación 🙏'
  : 'Por favor confírmame los montos de las cuentas para poder procesar tu operación 🙏';
return [{ json: { jid: String(ent.jid), texto } }];
'@
$decidirRecordatorioCode = $decidirRecordatorioCode.Replace('__COMUN__', $comunJs)

# ===================== CODIGO: DECIDIR AVISO (a los 10 minutos) =====================
$decidirAvisoCode = @'
// 5 minutos despues del recordatorio: si SIGUE sin arreglarlo (y no paso a un asesor), se avisa al
// grupo de avisos. Si lo arreglo, no se avisa nada.
__COMUN__
const MINUTOS = __MINUTOS__;
const nc = marcaVigente('Redis Leer Operacion 2');
if (!nc || nc.paso === 'escalado') return [];
const aviso = '⚠️ DEPÓSITO QUE NO CUADRA (' + MINUTOS + ' min sin corregir)\n\n' + resumen(nc) + '\n\n'
  + 'Ya se le recordó al cliente. NO se pasó a transferir. Revisa su chat.';
return [{ json: { aviso } }];
'@
$decidirAvisoCode = $decidirAvisoCode.Replace('__COMUN__', $comunJs).Replace('__MINUTOS__', [string]($MINUTOS_RECORDAR + $MINUTOS_AVISAR))

$nota = @"
## Avisar depósito que no cuadra

Cuando el depósito del cliente **no cuadra** con la suma de sus cuentas, el bot **no** pasa la operación a transferir y le pide al cliente que confirme los montos. Si el cliente lo arregla, el bot la procesa solo.

**Vigilar** (la primera vez): a los **$MINUTOS_RECORDAR min** le recuerda al cliente; a los **$($MINUTOS_RECORDAR + $MINUTOS_AVISAR) min**, si sigue igual, avisa al **grupo de avisos**.

**Escalar** (el cliente dice que está bien así): deja un aviso en el grupo de **transferir** para que lo revise un asesor.

Lo llama el bot (nodo *Vigilar Monto*).
"@

$espera1 = 'Esperar ' + $MINUTOS_RECORDAR + ' min'
$espera2 = 'Esperar ' + $MINUTOS_AVISAR + ' min mas'

$nodes = @(
  [ordered]@{
    parameters = @{ content = $nota; height = 340; width = 520; color = 4 }
    id = 'b7c8d9e0-1000-4f00-9b00-vigilarnota00'; name = 'Nota'; type = 'n8n-nodes-base.stickyNote'; typeVersion = 1; position = @(-40,-160)
  },
  [ordered]@{
    parameters = @{ inputSource = 'passthrough' }
    id = 'b7c8d9e0-1001-4f00-9b00-vigilartrig01'; name = 'Cuando lo Llama el Bot'; type = 'n8n-nodes-base.executeWorkflowTrigger'; typeVersion = 1.1; position = @(0,300)
  },
  [ordered]@{
    # 'escalar' -> aviso en transferir (arriba). Cualquier otra cosa -> vigilar (abajo).
    parameters = @{ conditions = @{ boolean = @( @{ value1 = "={{ `$json.modo === 'escalar' }}"; value2 = '={{true}}' } ) } }
    id = 'b7c8d9e0-1006-4f00-9b00-vigilarmodo01'; name = 'Es Escalar?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(176,300)
  },
  [ordered]@{
    parameters = @{ jsCode = $avisoTransferirCode }
    id = 'b7c8d9e0-1007-4f00-9b00-vigilarescal1'; name = 'Armar Aviso Transferir'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(352,140)
  },
  [ordered]@{
    parameters = @{ resource = 'messages-api'; instanceName = 'BOT JK Kelvin'; remoteJid = $GRUPO_OPERACIONES; messageText = '={{ $json.aviso }}'; options_message = @{} }
    id = 'b7c8d9e0-1008-4f00-9b00-vigilarescal2'; name = 'Avisar en Transferir'; type = 'n8n-nodes-evolution-api.evolutionApi'; typeVersion = 1; position = @(528,140)
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 3000
    onError = 'continueRegularOutput'; credentials = $evoCred
  },
  [ordered]@{
    parameters = @{ resume = 'timeInterval'; amount = $MINUTOS_RECORDAR; unit = 'minutes' }
    id = 'b7c8d9e0-1002-4f00-9b00-vigilarwait01'; name = $espera1; type = 'n8n-nodes-base.wait'; typeVersion = 1.1; position = @(352,460)
    webhookId = 'b7c8d9e0-1102-4f00-9b00-vigilarhook01'
  },
  [ordered]@{
    parameters = @{ operation = 'get'; key = "={{ 'op:' + `$('Cuando lo Llama el Bot').first().json.jid }}"; propertyName = 'operacion'; keyType = 'string'; options = @{} }
    id = 'b7c8d9e0-1003-4f00-9b00-vigilarredis1'; name = 'Redis Leer Operacion'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(528,460)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $decidirRecordatorioCode }
    id = 'b7c8d9e0-1009-4f00-9b00-vigilarrecor1'; name = 'Decidir Recordatorio'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(704,460)
  },
  [ordered]@{
    # El UNICO mensaje al cliente: el recordatorio. Lo manda el bot (id 3EB0...), asi que no pausa su chat.
    parameters = @{ resource = 'messages-api'; instanceName = 'BOT JK Kelvin'; remoteJid = '={{ $json.jid }}'; messageText = '={{ $json.texto }}'; options_message = @{} }
    id = 'b7c8d9e0-1010-4f00-9b00-vigilarrecor2'; name = 'Recordar al Cliente'; type = 'n8n-nodes-evolution-api.evolutionApi'; typeVersion = 1; position = @(880,460)
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 3000
    onError = 'continueRegularOutput'; credentials = $evoCred
  },
  [ordered]@{
    parameters = @{ resume = 'timeInterval'; amount = $MINUTOS_AVISAR; unit = 'minutes' }
    id = 'b7c8d9e0-1011-4f00-9b00-vigilarwait02'; name = $espera2; type = 'n8n-nodes-base.wait'; typeVersion = 1.1; position = @(1056,460)
    webhookId = 'b7c8d9e0-1111-4f00-9b00-vigilarhook02'
  },
  [ordered]@{
    parameters = @{ operation = 'get'; key = "={{ 'op:' + `$('Cuando lo Llama el Bot').first().json.jid }}"; propertyName = 'operacion'; keyType = 'string'; options = @{} }
    id = 'b7c8d9e0-1012-4f00-9b00-vigilarredis2'; name = 'Redis Leer Operacion 2'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1232,460)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $decidirAvisoCode }
    id = 'b7c8d9e0-1004-4f00-9b00-vigilardecid1'; name = 'Decidir Aviso'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1408,460)
  },
  [ordered]@{
    parameters = @{ resource = 'messages-api'; instanceName = 'BOT JK Kelvin'; remoteJid = $GRUPO_AVISOS; messageText = '={{ $json.aviso }}'; options_message = @{} }
    id = 'b7c8d9e0-1005-4f00-9b00-vigilaraviso1'; name = 'Avisar al Grupo'; type = 'n8n-nodes-evolution-api.evolutionApi'; typeVersion = 1; position = @(1584,460)
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 3000
    onError = 'continueRegularOutput'; credentials = $evoCred
  }
)

$connections = [ordered]@{
  'Cuando lo Llama el Bot' = @{ main = @( ,@( @{ node='Es Escalar?'; type='main'; index=0 } ) ) }
  'Es Escalar?'            = @{ main = (
      @( ,@( @{ node='Armar Aviso Transferir'; type='main'; index=0 } ) ) +
      @( ,@( @{ node=$espera1; type='main'; index=0 } ) )
    ) }
  'Armar Aviso Transferir' = @{ main = @( ,@( @{ node='Avisar en Transferir'; type='main'; index=0 } ) ) }
  $espera1                 = @{ main = @( ,@( @{ node='Redis Leer Operacion'; type='main'; index=0 } ) ) }
  'Redis Leer Operacion'   = @{ main = @( ,@( @{ node='Decidir Recordatorio'; type='main'; index=0 } ) ) }
  'Decidir Recordatorio'   = @{ main = @( ,@( @{ node='Recordar al Cliente'; type='main'; index=0 } ) ) }
  'Recordar al Cliente'    = @{ main = @( ,@( @{ node=$espera2; type='main'; index=0 } ) ) }
  $espera2                 = @{ main = @( ,@( @{ node='Redis Leer Operacion 2'; type='main'; index=0 } ) ) }
  'Redis Leer Operacion 2' = @{ main = @( ,@( @{ node='Decidir Aviso'; type='main'; index=0 } ) ) }
  'Decidir Aviso'          = @{ main = @( ,@( @{ node='Avisar al Grupo'; type='main'; index=0 } ) ) }
}

$wf = [ordered]@{
  name = 'Avisar deposito que no cuadra'
  nodes = $nodes
  connections = $connections
  settings = [ordered]@{ executionOrder = 'v1'; timezone = 'America/Guayaquil' }
}
$salida = Join-Path $PSScriptRoot 'workflow_vigilar_monto.json'
$json = $wf | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($salida, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('JSON generado: ' + $salida + ' | nodos: ' + $nodes.Count)
