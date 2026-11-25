# ============================================================================
#  DESPLIEGUE DE "Bot JK - Grupos de Operadoras"
# ============================================================================
#  Uso (desde la raiz del proyecto):
#      powershell -ExecutionPolicy Bypass -File build_operadoras.ps1
#      powershell -ExecutionPolicy Bypass -File scripts\desplegar_operadoras.ps1
#
#  - Si el workflow NO existe en n8n, lo CREA (INACTIVO) e imprime su id. Ese
#    id va en $OPERADORAS_WORKFLOW_ID de build_v12.ps1.
#  - Si ya existe, lo ACTUALIZA conservando la posicion de los nodos y NO toca
#    su estado activo/inactivo.
#  - NUNCA lo activa: el usuario lo revisa y publica a mano en n8n.
#
#  Este archivo se mantiene 100% ASCII.
# ============================================================================
$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'n8n_comun.ps1')

$jsonPath = Join-Path $raiz 'workflow_operadoras.json'
if(-not (Test-Path $jsonPath)){ throw 'No existe workflow_operadoras.json. Corre primero build_operadoras.ps1.' }
$ctx = Get-N8nCtx
$nombre = 'Bot JK - Grupos de Operadoras'

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
  Write-Host ('Pon este id en build_v12.ps1:  $OPERADORAS_WORKFLOW_ID = ''' + $resp.id + '''')
}
