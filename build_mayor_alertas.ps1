# ============================================================================
#  WORKFLOW "Mayor: alertas de vencimiento"  (Cambios JK)  -  FASE 3
# ============================================================================
#  Cada RST que esta en el grupo de su banco se anota en la tabla vigilancia_rst_mayor con la hora a la que vence
#  (lo hace "Mayor: escuchar y registrar" y, para los de 24 h, "Mayor: pasar RST al abrir"). Los cobradores lo marcan
#  con una reaccion (cualquier emoji menos la ❌ = cobrado). Este workflow revisa la tabla cada 2 minutos y, cuando
#  falta 1 hora para que venza (5 minutos en JEP) y nadie lo marco como cobrado, CITA el mensaje en el grupo del
#  banco y avisa:  "⚠️ ¡Pendiente! Este código está por vencerse, le queda poco tiempo. Favor proceder con el retiro
#  en cajero."   (protocolo_rst_rct.md, seccion 7)
#
#    Cada 2 Minutos -> Leer RST por Vencer -> Hay Algo? -> Leer Grupos Destino -> Armar Alertas -> Se Envia?
#         -> Enviar Alerta -> Fallo la Cita? -> (Reenviar sin Cita) -> Marcar Alerta
#
#  - Modo ($ALERTAS_MODO en mayor_comun.ps1): 'ensayo' = la alerta se muestra como vista previa en el grupo de avisos;
#    'real' = el bot escribe en el grupo del banco. Se pasa a 'real' solo con el OK de Kelvin.
#  - Solo se avisa en horario de atencion (el cobrador no esta de noche). Si la alerta toca de noche y el codigo
#    sigue vivo cuando abrimos, se avisa al abrir; si ya no, no se avisa.
#  - Solo escribe al grupo donde esta el RST, y solo si ese grupo esta en la tabla grupos_mayor (lista blanca).
#
#  Genera workflow_mayor_alertas.json. Se sube con scripts\desplegar_mayor_alertas.ps1.
#  Se crea INACTIVO (tiene un cron): Kelvin lo activa a mano en n8n.
# ============================================================================
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'mayor_comun.ps1')

$supaCred = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }

# ===================== CODIGO: HAY ALGO? =====================
$hayAlgoCode = @'
// Casi todas las veces no hay nada por avisar: se corta aqui y no se lee nada mas.
let filas = [];
try { filas = $('Leer RST por Vencer').all().map(i => i.json).filter(r => r && r.id && !r.error); } catch(e){ filas = []; }
return filas.length ? [{ json: { cuantas: filas.length } }] : [];
'@

# ===================== CODIGO: ARMAR ALERTAS =====================
$armarAlertasCode = @'
// ===== ALERTAS DE VENCIMIENTO: A QUIEN SE LE AVISA, DONDE Y CON QUE TEXTO =====
// Entran los RST vigilados cuya hora de alerta ya paso, que nadie marco como cobrados y a los que todavia no se les avisó.
// Sale una lista: cada item es UN aviso por enviar, o una actualizacion silenciosa (sinEnvio) de la fila.
const MODO = '__MODO_ALERTAS__';
const GRUPO_AVISOS = '__GRUPO_AVISOS__';
__HORARIO_JK__
__VIGENCIA_COMUN__
const ahora = Date.now();
const hr = horarioDe(ahora);
let filas = [];
try { filas = $('Leer RST por Vencer').all().map(i => i.json).filter(r => r && r.id && !r.error); } catch(e){ filas = []; }
const destinos = {};          // id del grupo -> su nombre, solo los de la tabla (lista blanca)
try { for (const it of $('Leer Grupos Destino').all()){ const g = it.json || {}; if (g.grupo_jid && g.nombre && g.activo !== false) destinos[g.grupo_jid] = g.nombre; } } catch(e){}
const hhmm = ms => new Date(ms - 5 * 3600000).toISOString().slice(11, 16);
const out = [];
const silencioso = (r, resultado, cobro) => out.push({ json: { sinEnvio: true, fila_id: r.id, resultado, cobro: cobro || r.cobro } });
for (const r of filas.slice(0, 25)){                    // si hubiera mas, el resto sale en la proxima vuelta (2 minutos)
  const vence = Date.parse(r.vence_en);
  if (!(vence > 0) || ahora >= vence){ silencioso(r, 'vencido', 'vencido'); continue; }     // ya se paso: no se avisa
  if (!hr.abierto){
    // De noche nadie lo lee. Si el codigo sigue vivo cuando abrimos, se avisa entonces (la fila sigue pendiente); si no, ya no sirve.
    if (hr.proximaApertura >= vence) silencioso(r, 'fuera_de_horario');
    continue;
  }
  const nombreGrupo = destinos[r.grupo_jid] || '';
  const resumen = r.resumen || String(r.banco || '').toUpperCase();
  if (r.banco === 'jep_pedido'){
    // El cobrador de JEP no contesto el pedido ("ir a un cajero y avisar"): el aviso va al grupo de AVISOS (a la gente de la oficina), no al banco.
    out.push({ json: { jid: GRUPO_AVISOS, texto: '⚠️ JEP: el cobrador todavía no avisa que llegó al cajero. Lleva 30 minutos esperando:\n' + resumen + '\nRevisa el grupo ' + (nombreGrupo || 'COOP JEP') + '.', fila_id: r.id, resultado: 'enviada', cobro: r.cobro } });
    continue;
  }
  if (MODO !== 'real'){
    const vista = '🧪 ENSAYO — la alerta iría a ' + (nombreGrupo || String(r.banco || '').toUpperCase()) + ', citando el RST de las ' + hhmm(Date.parse(r.recibido_en)) + ' (' + resumen + '):\n' + TEXTO_ALERTA;
    out.push({ json: { jid: GRUPO_AVISOS, texto: vista, fila_id: r.id, resultado: 'ensayo', cobro: r.cobro } });
    continue;
  }
  if (!nombreGrupo){ silencioso(r, 'sin_grupo'); continue; }       // el grupo no esta en la tabla: no se le escribe
  out.push({ json: { jid: r.grupo_jid, texto: TEXTO_ALERTA, citar: r.mensaje_id, texto_sin_cita: '(' + resumen + ')\n' + TEXTO_ALERTA, fila_id: r.id, resultado: 'enviada', cobro: r.cobro } });
}
return out;
'@
$armarAlertasCode = $armarAlertasCode.Replace('__HORARIO_JK__', $horarioJs).Replace('__VIGENCIA_COMUN__', $vigenciaJs)
$armarAlertasCode = $armarAlertasCode.Replace('__MODO_ALERTAS__', $ALERTAS_MODO).Replace('__GRUPO_AVISOS__', $GRUPO_AVISOS)

$nota = @'
## Mayor: alertas de vencimiento (FASE 3)
Cada RST que esta en el grupo de su banco se anota en la tabla `vigilancia_rst_mayor` con su hora de vencimiento. Los cobradores lo marcan con una **reaccion** (cualquier emoji menos la ❌ = cobrado).

Este workflow revisa la tabla **cada 2 minutos**. Cuando falta **1 hora** para que venza (**5 minutos en JEP**) y nadie lo marco como cobrado, **cita el mensaje en el grupo del banco** y avisa: "⚠️ ¡Pendiente! Este código está por vencerse...".

| Banco | Dura | Aviso |
|---|---|---|
| Pichincha, Pacifico | 4 h | a las 3 h |
| Guayaquil, Produbanco | 24 h | a las 23 h |
| Bolivariano | hasta las 9 pm | a las 8 pm |
| JEP | 15 min | a los 5 min |

Ademas: si el cobrador de JEP no contesta el PEDIDO ("ir a un cajero y avisar") en **30 minutos**, avisa en el grupo de **avisos**.

Solo avisa en **horario de atencion**. Solo escribe al grupo donde esta el RST y solo si esta en `grupos_mayor`.

**Modo ENSAYO** (`$ALERTAS_MODO` en `mayor_comun.ps1`): la alerta se muestra como vista previa en el grupo de avisos; no se escribe a ningun banco.

Se crea **INACTIVO**: se activa a mano. Credenciales: Supabase Cambios JK, Evolution apikey. Se genera con `build_mayor_alertas.ps1`.
'@

$nodes = @(
  [ordered]@{
    parameters = @{ content = $nota; height = 560; width = 520; color = 4 }
    id = 'e3f4a5b6-0000-4d00-8d00-mayoralert000'; name = 'Nota'; type = 'n8n-nodes-base.stickyNote'; typeVersion = 1; position = @(-40,-640)
  },
  [ordered]@{
    parameters = @{ rule = @{ interval = @( @{ field = 'cronExpression'; expression = '0 */2 * * * *' } ) } }
    id = 'e3f4a5b6-0001-4d00-8d00-mayoralert001'; name = 'Cada 2 Minutos'; type = 'n8n-nodes-base.scheduleTrigger'; typeVersion = 1.1; position = @(0,300)
  },
  [ordered]@{
    # Los RST vigilados que ya llegaron a su hora de alerta, sin marca de cobrado y sin aviso enviado.
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'vigilancia_rst_mayor'; returnAll = $true; filterType = 'string'
                    filterString = "={{ 'alerta_enviada_en=is.null&cobro=in.(pendiente,no_cobrado)&alerta_en=lte.' + new Date().toISOString() + '&order=alerta_en.asc' }}" }
    id = 'e3f4a5b6-0002-4d00-8d00-mayoralert002'; name = 'Leer RST por Vencer'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(176,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $supaCred
  },
  [ordered]@{
    parameters = @{ jsCode = $hayAlgoCode }
    id = 'e3f4a5b6-0003-4d00-8d00-mayoralert003'; name = 'Hay Algo?'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(352,300)
  },
  [ordered]@{
    # Los grupos de destino de la tabla: la lista blanca (el bot nunca escribe a un grupo que no este aqui).
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'grupos_mayor'; returnAll = $true; filterType = 'string'; filterString = 'tipo=eq.destino' }
    id = 'e3f4a5b6-0004-4d00-8d00-mayoralert004'; name = 'Leer Grupos Destino'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(528,300)
    executeOnce = $true; onError = 'continueRegularOutput'; alwaysOutputData = $true; credentials = $supaCred
  },
  [ordered]@{
    parameters = @{ jsCode = $armarAlertasCode }
    id = 'e3f4a5b6-0005-4d00-8d00-mayoralert005'; name = 'Armar Alertas'; type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(704,300)
  },
  [ordered]@{
    # Verdadero = hay un mensaje por enviar. Falso = solo se actualiza la fila (vencido, fuera de horario, sin grupo).
    parameters = @{ conditions = @{ boolean = @( @{ value1 = '={{ !$json.sinEnvio }}'; value2 = '={{true}}' } ) } }
    id = 'e3f4a5b6-0006-4d00-8d00-mayoralert006'; name = 'Se Envia?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(880,300)
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'
                    authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true
                    headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'
                    jsonBody = '={{ JSON.stringify(Object.assign({ number: $json.jid, text: $json.texto }, $json.citar ? { quoted: { key: { id: $json.citar } } } : {})) }}'
                    options = @{} }
    id = 'e3f4a5b6-0007-4d00-8d00-mayoralert007'; name = 'Enviar Alerta'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1056,300)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = $evoHeaderCred
  },
  [ordered]@{
    # Si fallo y llevaba cita (a veces el mensaje citado ya no esta en Evolution), se reintenta SIN cita (con el resumen en el texto).
    parameters = @{ conditions = @{ boolean = @( @{ value1 = '={{ !!$json.error && !!$("Armar Alertas").item.json.citar }}'; value2 = '={{true}}' } ) } }
    id = 'e3f4a5b6-0008-4d00-8d00-mayoralert008'; name = 'Fallo la Cita?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(1232,300)
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'
                    authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true
                    headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'
                    jsonBody = '={{ JSON.stringify({ number: $("Armar Alertas").item.json.jid, text: $("Armar Alertas").item.json.texto_sin_cita || $("Armar Alertas").item.json.texto }) }}'
                    options = @{} }
    id = 'e3f4a5b6-0009-4d00-8d00-mayoralert009'; name = 'Reenviar sin Cita'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1408,480)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = $evoHeaderCred
  },
  [ordered]@{
    # Anota el resultado. Solo toca filas que siguen pendientes: si alguien la marco cobrada en este instante, no se pisa.
    parameters = @{ resource = 'row'; operation = 'update'; tableId = 'vigilancia_rst_mayor'; filterType = 'string'
                    filterString = '={{ "id=eq." + $("Armar Alertas").item.json.fila_id + "&cobro=in.(pendiente,no_cobrado)" }}'; dataToSend = 'defineBelow'
                    fieldsUi = @{ fieldValues = @(
                      @{ fieldId = 'alerta_enviada_en'; fieldValue = '={{ new Date().toISOString() }}' },
                      @{ fieldId = 'alerta_resultado'; fieldValue = '={{ $json.error ? "error" : $("Armar Alertas").item.json.resultado }}' },
                      @{ fieldId = 'cobro'; fieldValue = '={{ $("Armar Alertas").item.json.cobro }}' } ) } }
    id = 'e3f4a5b6-0010-4d00-8d00-mayoralert010'; name = 'Marcar Alerta'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(1584,300)
    onError = 'continueRegularOutput'; credentials = $supaCred
  }
)

$connections = [ordered]@{
  'Cada 2 Minutos'      = @{ main = @( ,@( @{ node='Leer RST por Vencer'; type='main'; index=0 } ) ) }
  'Leer RST por Vencer' = @{ main = @( ,@( @{ node='Hay Algo?'; type='main'; index=0 } ) ) }
  'Hay Algo?'           = @{ main = @( ,@( @{ node='Leer Grupos Destino'; type='main'; index=0 } ) ) }
  'Leer Grupos Destino' = @{ main = @( ,@( @{ node='Armar Alertas'; type='main'; index=0 } ) ) }
  'Armar Alertas'       = @{ main = @( ,@( @{ node='Se Envia?'; type='main'; index=0 } ) ) }
  'Se Envia?'           = @{ main = (
      @( ,@( @{ node='Enviar Alerta'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Marcar Alerta'; type='main'; index=0 } ) )
    ) }
  'Enviar Alerta'       = @{ main = @( ,@( @{ node='Fallo la Cita?'; type='main'; index=0 } ) ) }
  'Fallo la Cita?'      = @{ main = (
      @( ,@( @{ node='Reenviar sin Cita'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Marcar Alerta'; type='main'; index=0 } ) )
    ) }
  'Reenviar sin Cita'   = @{ main = @( ,@( @{ node='Marcar Alerta'; type='main'; index=0 } ) ) }
}

$wf = [ordered]@{
  name = 'Mayor: alertas de vencimiento'
  nodes = $nodes
  connections = $connections
  settings = [ordered]@{ executionOrder = 'v1'; timezone = 'America/Guayaquil'; saveDataSuccessExecution = 'none' }
}
$salida = Join-Path $PSScriptRoot 'workflow_mayor_alertas.json'
$json = $wf | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($salida, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('JSON generado: ' + $salida + ' | nodos: ' + $nodes.Count)
