# ============================================================================
#  DESPLIEGUE DE "Liberar operaciones de la noche"  ->  workflow gg1NY2dIANO41Ut7
# ============================================================================
#  Uso (desde la raiz del proyecto):
#      powershell -ExecutionPolicy Bypass -File build_liberar_noche.ps1
#      powershell -ExecutionPolicy Bypass -File scripts\desplegar_liberar.ps1
#
#  Sube el JSON que genera build_liberar_noche.ps1, conservando la posicion de los
#  nodos que Kelvin haya movido en n8n.
#
#  NO toca el estado activo/inactivo: el workflow se creo INACTIVO y lo activa
#  Kelvin a mano desde n8n.
#
#  Este archivo se mantiene 100% ASCII.
# ============================================================================
$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'n8n_comun.ps1')

$json = Join-Path $raiz 'workflow_liberar_noche.json'
$txt = [System.IO.File]::ReadAllText($json, [System.Text.Encoding]::UTF8)
if($txt -match 'const PRUEBA = \['){
  Write-Host 'OJO: el JSON esta en MODO PRUEBA (publica en el grupo de avisos).'
}

Publish-N8nWorkflow (Get-N8nCtx) 'gg1NY2dIANO41Ut7' $json @('Liberar operaciones de la noche', 'Cada Ma')

Write-Host ''
Write-Host 'LISTO. "Liberar operaciones de la noche" quedo igual de activo/inactivo que estaba antes.'
