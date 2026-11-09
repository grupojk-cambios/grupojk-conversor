# ============================================================================
#  DESPLIEGUE DEL BOT DE TASAS DE PROVEEDORES  ->  workflow dDA6DuE7B1ntNUy9
# ============================================================================
#  Uso (desde la raiz del proyecto):
#      powershell -ExecutionPolicy Bypass -File scripts\desplegar_tasas.ps1
#
#  Antes hay que generar el JSON:
#      powershell -ExecutionPolicy Bypass -File build_tasas_proveedores.ps1
#
#  Todas las verificaciones las hace Publish-N8nWorkflow (scripts/n8n_comun.ps1):
#  encoding antes y despues, layout y credenciales del workflow vivo, y una
#  comparacion caracter por caracter de lo enviado contra lo que quedo arriba.
#
#  NO toca el estado activo/inactivo del workflow: queda como estaba.
#
#  Este archivo se mantiene 100% ASCII: los .ps1 sin BOM los lee PowerShell 5.1
#  como Windows-1252 y los caracteres especiales se rompen aqui mismo.
# ============================================================================
$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'n8n_comun.ps1')

Publish-N8nWorkflow (Get-N8nCtx) 'dDA6DuE7B1ntNUy9' (Join-Path $raiz 'workflow_tasas_proveedores.json') `
  @('Compare ', 'Entendi esto')

Write-Host ''
Write-Host 'LISTO. El bot de Tasas quedo igual de activo/inactivo que estaba antes.'
