# ============================================================================
#  DESPLIEGUE DE "Bot JK - Debounce y Admin"
# ============================================================================
#  Uso (desde la raiz del proyecto):
#      powershell -ExecutionPolicy Bypass -File build_debounce_admin.ps1
#      powershell -ExecutionPolicy Bypass -File scripts\desplegar_debounce_admin.ps1
#
#  - Si el workflow NO existe en n8n, lo CREA (INACTIVO) e imprime su id. Ese
#    id va en $DEBOUNCE_ADMIN_WORKFLOW_ID de build_v12.ps1.
#  - Si ya existe, lo ACTUALIZA conservando la posicion de los nodos y NO toca
#    su estado activo/inactivo.
#  - NUNCA lo activa: el usuario lo revisa y publica a mano en n8n.
#
#  Este archivo se mantiene 100% ASCII.
# ============================================================================
$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'n8n_comun.ps1')

$jsonPath = Join-Path $raiz 'workflow_debounce_admin.json'
if(-not (Test-Path $jsonPath)){ throw 'No existe workflow_debounce_admin.json. Corre primero build_debounce_admin.ps1.' }
$ctx = Get-N8nCtx
$nombre = 'Bot JK - Debounce y Admin'

$lista = Get-N8nJson $ctx '/workflows?limit=100'
$ya = @($lista.data | Where-Object { $_.name -eq $nombre })

if($ya.Count -gt 1){ throw ('Hay ' + $ya.Count + ' workflows con ese nombre. Borra los repetidos a mano y vuelve a correr.') }

if($ya.Count -eq 1){
  Write-Host ('Ya existe (id=' + $ya[0].id + '): se actualiza.')
  Publish-N8nWorkflow $ctx $ya[0].id $jsonPath @('Preparar Contexto IA', 'Ejecutar IA', 'Prep Debounce')
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
  Write-Host ('Pon este id en build_v12.ps1:  $DEBOUNCE_ADMIN_WORKFLOW_ID = ''' + $resp.id + '''')
}
