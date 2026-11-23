# ============================================================================
#  DESPLIEGUE DE "Avisar deposito que no cuadra"
# ============================================================================
#  Uso (desde la raiz del proyecto):
#      powershell -ExecutionPolicy Bypass -File build_vigilar_monto.ps1
#      powershell -ExecutionPolicy Bypass -File scripts\desplegar_vigilar_monto.ps1
#
#  - Si el workflow NO existe en n8n, lo CREA (inactivo) e imprime su id. Ese id va en
#    $VIGILAR_MONTO_WORKFLOW_ID de build_v12.ps1 (el bot principal lo llama con un nodo
#    "Vigilar Monto").
#  - Si ya existe, lo ACTUALIZA conservando la posicion de los nodos.
#  - NUNCA lo activa: Kelvin lo publica a mano en n8n (sin eso el bot no se puede desplegar).
#
#  Este archivo se mantiene 100% ASCII.
# ============================================================================
$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'n8n_comun.ps1')

$jsonPath = Join-Path $raiz 'workflow_vigilar_monto.json'
if(-not (Test-Path $jsonPath)){ throw 'No existe workflow_vigilar_monto.json. Corre primero build_vigilar_monto.ps1.' }
$ctx = Get-N8nCtx
$nombre = 'Avisar deposito que no cuadra'

$lista = Get-N8nJson $ctx '/workflows?limit=100'
$ya = @($lista.data | Where-Object { $_.name -eq $nombre })

if($ya.Count -gt 1){ throw ('Hay ' + $ya.Count + ' workflows con ese nombre. Borra los repetidos a mano y vuelve a correr.') }

if($ya.Count -eq 1){
  Write-Host ('Ya existe (id=' + $ya[0].id + '): se actualiza.')
  Publish-N8nWorkflow $ctx $ya[0].id $jsonPath $null
  Write-Host ''
  Write-Host ('LISTO. Workflow id=' + $ya[0].id + ' (activo=' + $ya[0].active + ').')
} else {
  Write-Host 'No existe: se crea INACTIVO.'
  $txt = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
  if((Test-N8nEncoding $txt).Count -gt 0){ throw 'ABORTADO: el JSON local trae encoding roto.' }
  $wf = $txt | ConvertFrom-Json
  $payload = ([ordered]@{ name = $wf.name; nodes = $wf.nodes; connections = $wf.connections; settings = $wf.settings }) | ConvertTo-Json -Depth 40 -Compress
  $resp = Send-N8nJson $ctx '/workflows' 'POST' $payload
  Write-Host ''
  Write-Host ('CREADO. id=' + $resp.id + ' | activo=' + $resp.active + ' | nodos=' + $resp.nodes.Count)
  Write-Host ('Pon este id en build_v12.ps1:  $VIGILAR_MONTO_WORKFLOW_ID = ''' + $resp.id + '''')
}
