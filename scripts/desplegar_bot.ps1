# ============================================================================
#  DESPLIEGUE DEL BOT DE WHATSAPP  ->  workflow NWmStkbNexV7s5xY
# ============================================================================
#  Uso (desde la raiz del proyecto):
#      powershell -ExecutionPolicy Bypass -File scripts\desplegar_bot.ps1
#
#  Antes hay que generar el JSON:
#      powershell -ExecutionPolicy Bypass -File build_v12.ps1
#
#  Paso 0 = CANDADO: corre compare_motor.mjs. Si el bot no calcula igual que la
#  app, se detiene y NO despliega. (Asi llegamos a tener 581 diferencias en
#  produccion sin darnos cuenta: el bot regalaba plata en las rutas de Europa.)
#  Los pasos 1 a 4 los hace Publish-N8nWorkflow (ver scripts/n8n_comun.ps1).
#
#  NO toca el estado activo/inactivo del workflow: queda como estaba.
#
#  Este archivo se mantiene 100% ASCII: los .ps1 sin BOM los lee PowerShell 5.1
#  como Windows-1252 y los caracteres especiales se rompen aqui mismo.
# ============================================================================
$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'n8n_comun.ps1')

Write-Host '  [0/4] Verificando que el bot calcule igual que la app...'
Push-Location $raiz
try { & node 'compare_motor.mjs' } finally { Pop-Location }
if($LASTEXITCODE -ne 0){
  throw 'ABORTADO: el bot NO calcula igual que la app. Arregla src/motor.js, corre .\build_v12.ps1 y vuelve a intentar.'
}

Publish-N8nWorkflow (Get-N8nCtx) 'NWmStkbNexV7s5xY' (Join-Path $raiz 'workflow_bot_whatsapp_v12.json') `
  @('Eres asistente de *Cambios JK', 'tarifa MAYOR ', 'tu comprobante! ')

Write-Host ''
Write-Host 'LISTO. El bot de WhatsApp quedo igual de activo/inactivo que estaba antes.'
