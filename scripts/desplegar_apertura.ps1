# ============================================================================
#  DESPLIEGUE DE "APERTURA Y CIERRE AUTOMATICO"  ->  workflow PAneIYAVkE9lPUVw
# ============================================================================
#  Uso (desde la raiz del proyecto):
#      powershell -ExecutionPolicy Bypass -File scripts\desplegar_apertura.ps1
#
#  Este workflow NO se genera con un script de build: su fuente es el propio
#  archivo workflow_apertura_cierre.json, que se bajo del servidor. Si hay que
#  cambiarlo, se edita ese JSON (o se edita en n8n y se vuelve a bajar).
#
#  Las verificaciones las hace Publish-N8nWorkflow (scripts/n8n_comun.ps1).
#  NO toca el estado activo/inactivo del workflow.
#
#  Este archivo se mantiene 100% ASCII: los .ps1 sin BOM los lee PowerShell 5.1
#  como Windows-1252 y los caracteres especiales se rompen aqui mismo.
# ============================================================================
$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'n8n_comun.ps1')

Publish-N8nWorkflow (Get-N8nCtx) 'PAneIYAVkE9lPUVw' (Join-Path $raiz 'workflow_apertura_cierre.json') $null

Write-Host ''
Write-Host 'LISTO. Apertura y cierre quedo igual de activo/inactivo que estaba antes.'
