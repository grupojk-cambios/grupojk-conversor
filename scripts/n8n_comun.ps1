# Utilidades para hablar con la API de n8n.
#
# REGLA DE ORO: usar System.Net.WebClient con Encoding UTF8.
# NUNCA Invoke-RestMethod / Invoke-WebRequest para un PUT con texto en espanol
# (tildes, enes) o emojis: los corrompen EN SILENCIO. Ya paso dos veces: una
# dejo el nombre del bot como "Cambios JK??" frente a los clientes.
#
# Este archivo se mantiene 100% ASCII a proposito: los .ps1 sin BOM los lee
# PowerShell 5.1 como Windows-1252 y cualquier caracter especial se rompe aqui mismo.
#
# La llave de la API NO va escrita aqui. Se lee de C:\Users\USER\.claude.json,
# que es donde ya la tiene configurada el servidor MCP de n8n.

function Get-N8nCtx {
  $cfgPath = Join-Path $env:USERPROFILE '.claude.json'
  if(-not (Test-Path $cfgPath)){ throw "No encontre $cfgPath (ahi vive la llave de n8n)." }
  $raw = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
  $m = [regex]::Match($raw, '"N8N_API_URL"\s*:\s*"([^"]+)"')
  $k = [regex]::Match($raw, '"N8N_API_KEY"\s*:\s*"([^"]+)"')
  if(-not $m.Success -or -not $k.Success){ throw 'No encontre N8N_API_URL / N8N_API_KEY en .claude.json' }
  $base = $m.Groups[1].Value.TrimEnd('/')
  if($base -notmatch '/api/v1$'){ $base = $base + '/api/v1' }
  return @{ base = $base; key = $k.Groups[1].Value }
}

function New-N8nClient($ctx) {
  [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
  $wc = New-Object System.Net.WebClient
  $wc.Encoding = [System.Text.Encoding]::UTF8
  $wc.Headers.Add('X-N8N-API-KEY', $ctx.key)
  $wc.Headers.Add('Content-Type', 'application/json; charset=utf-8')
  $wc.Headers.Add('Accept', 'application/json')
  return $wc
}

function Get-N8nRaw($ctx, $ruta) {
  $wc = New-N8nClient $ctx
  try { return $wc.DownloadString($ctx.base + $ruta) } finally { $wc.Dispose() }
}

function Get-N8nJson($ctx, $ruta) {
  return (Get-N8nRaw $ctx $ruta) | ConvertFrom-Json
}

function Send-N8nJson($ctx, $ruta, $metodo, $payload) {
  $wc = New-N8nClient $ctx
  try {
    return ($wc.UploadString($ctx.base + $ruta, $metodo, $payload) | ConvertFrom-Json)
  } catch [System.Net.WebException] {
    $r = $_.Exception.Response
    if($r){
      $sr = New-Object System.IO.StreamReader($r.GetResponseStream(), [System.Text.Encoding]::UTF8)
      $cuerpo = $sr.ReadToEnd(); $sr.Close()
      throw ("n8n respondio error: " + $cuerpo)
    }
    throw
  } finally { $wc.Dispose() }
}

# Busca senales de encoding roto (mojibake) en un texto.
# Los patrones se arman por codigo de caracter para que este archivo siga siendo ASCII.
#
# Cuando UTF-8 se lee como Windows-1252, cada caracter especial se parte en varios.
# Hay que buscar la SEGUNDA mitad con el valor de cp1252, no con el byte crudo:
# cp1252 mapea 0x80 -> U+20AC (euro), 0x9F -> U+0178, etc.
# ERROR QUE YA COMETI: buscar "a-circunfleja + U+0080" en vez de "+ U+20AC". Por eso
# el detector daba "0 problemas" en un workflow que SI tenia el guion largo roto
# (U+2014 -> E2 80 94 -> "a-circunfleja, euro, comilla-cierre").
#
function Test-N8nEncoding($texto) {
  $problemas = @()

  # Secuencias literales: la 1ra mitad + la 2da mitad ya traducida por cp1252.
  $patrones = @(
    @{ p = ([char]0x00C3);                        d = 'tilde/enie corrompida (C3: a-con-tilde, enie, o-con-tilde...)' },
    @{ p = ([string][char]0x00E2 + [char]0x20AC); d = 'guion largo, comilla curva o puntos suspensivos corrompidos (E2 80)' },
    @{ p = ([string][char]0x00F0 + [char]0x0178); d = 'emoji corrompido (F0 9F)' },
    @{ p = ([char]0xFFFD);                        d = 'caracter de reemplazo (dato PERDIDO, no se recupera)' }
  )
  # OJO: IndexOf(string) compara segun la CULTURA y los caracteres "ignorables"
  # (U+FFFD, U+0080) matchean en el indice 0 de cualquier texto -> falso positivo
  # que aborta despliegues sanos. Hay que forzar Ordinal.
  foreach($x in $patrones){
    $i = $texto.IndexOf([string]$x.p, [System.StringComparison]::Ordinal)
    if($i -ge 0){
      $ini = [Math]::Max(0, $i - 30)
      $len = [Math]::Min(70, $texto.Length - $ini)
      $problemas += ("MOJIBAKE [" + $x.d + "] ... " + $texto.Substring($ini, $len) + " ...")
    }
  }

  # C2 xx: NBSP, abre-interrogacion, abre-exclamacion, grados... quedan como
  # "A-circunfleja" + el simbolo. Se exige el segundo caracter para no marcar
  # una "A-circunfleja" legitima (portugues/frances).
  # El patron se arma con CODIGOS de caracter a proposito: si se escribiera con los
  # caracteres literales, este .ps1 dejaria de ser ASCII y PowerShell 5.1 (que lo lee
  # como Windows-1252 por no tener BOM) corromperia el propio patron. Ya paso: el
  # detector daba 0 problemas porque su regex llegaba roto.
  $patC2 = '[' + [char]0x00C2 + '][' + [char]0x00A0 + '-' + [char]0x00BF + ']'
  $mC2 = [regex]::Match($texto, $patC2)
  if($mC2.Success){
    $ini = [Math]::Max(0, $mC2.Index - 30)
    $len = [Math]::Min(70, $texto.Length - $ini)
    $problemas += ("MOJIBAKE [signo de apertura, NBSP o grados corrompido (C2)] ... " + $texto.Substring($ini, $len) + " ...")
  }

  return $problemas
}

#
# Compara los caracteres NO-ASCII de dos textos (lo que se mando vs lo que quedo
# en el servidor). Es la red mas fina que hay: detecta EXACTAMENTE cualquier
# destruccion -- mojibake, U+FFFD, y tambien los emojis que Invoke-RestMethod
# convierte en "??" (que no son mojibake y no se pueden detectar por patron,
# porque "??" tambien es el operador de JavaScript y daria falsos positivos).
#
# Devuelve una lista de diferencias; vacia = todo llego intacto.
#
function Compare-N8nNoAscii($enviado, $recibido) {
  $contar = {
    param($s)
    $h = @{}
    foreach($c in $s.ToCharArray()){
      if([int]$c -gt 127){ $k = [int]$c; if($h.ContainsKey($k)){ $h[$k]++ } else { $h[$k] = 1 } }
    }
    return $h
  }
  $a = & $contar $enviado
  $b = & $contar $recibido
  $difs = @()
  $todas = @($a.Keys) + @($b.Keys) | Sort-Object -Unique
  foreach($k in $todas){
    $na = if($a.ContainsKey($k)){ $a[$k] } else { 0 }
    $nb = if($b.ContainsKey($k)){ $b[$k] } else { 0 }
    if($na -ne $nb){
      $difs += ("U+" + ([int]$k).ToString('X4') + " '" + [char]$k + "'  enviado=" + $na + "  en el servidor=" + $nb)
    }
  }
  return $difs
}

#
# Publica un workflow a n8n haciendo TODAS las verificaciones.
# Usada por scripts/desplegar_bot.ps1 y scripts/desplegar_cuentas.ps1.
#
#   - Revisa el encoding del JSON local ANTES de mandar nada.
#   - Conserva del workflow VIVO: la posicion de los nodos (para no desordenar el
#     lienzo) y las credenciales, pero SOLO las que el build no trae (copiarlas
#     siempre ya rompio un despliegue: puso una credencial postgres en un nodo redis).
#   - Sube con WebClient + UTF8. NUNCA Invoke-RestMethod: destruye los emojis.
#   - Vuelve a bajar y compara caracter por caracter los no-ASCII contra lo enviado.
#   - NO toca el estado activo/inactivo del workflow.
#
# Lanza una excepcion si algo no cuadra. No devuelve nada util.
#
function Publish-N8nWorkflow($ctx, $wfId, $jsonPath, $anclas) {
  if(-not (Test-Path $jsonPath)){ throw "No existe $jsonPath. Corre primero el script de build." }

  Write-Host '  [1/4] Revisando el encoding del JSON local...'
  $txt = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
  $pre = Test-N8nEncoding $txt
  if($pre.Count -gt 0){
    foreach($x in $pre){ Write-Host ('        ' + $x) }
    throw 'ABORTADO: el JSON local trae encoding roto. Revisa que el .ps1 del build tenga BOM UTF-8.'
  }
  Write-Host '        OK, sin corrupcion.'

  Write-Host '  [2/4] Leyendo el workflow vivo (layout y credenciales)...'
  $live = Get-N8nJson $ctx ('/workflows/' + $wfId)
  $pos = @{}; $creds = @{}
  foreach($n in $live.nodes){
    if($n.position){ $pos[$n.name] = $n.position }
    if($n.credentials){ $creds[$n.name] = $n.credentials }
  }
  Write-Host ('        Vivo: ' + $live.nodes.Count + ' nodos | active=' + $live.active)

  $new = $txt | ConvertFrom-Json
  $rp=0; $rc=0; $nuevos=0
  foreach($n in $new.nodes){
    if($pos.ContainsKey($n.name)){ $n.position = $pos[$n.name]; $rp++ } else { $nuevos++ }
    $tieneCred = ($n.PSObject.Properties.Name -contains 'credentials') -and $n.credentials
    if(-not $tieneCred -and $creds.ContainsKey($n.name)){
      $n | Add-Member -NotePropertyName credentials -NotePropertyValue $creds[$n.name] -Force
      $rc++
    }
  }
  Write-Host ('        Nuevo: ' + $new.nodes.Count + ' nodos | layout conservado=' + $rp + ' nuevos=' + $nuevos + ' | creds del vivo=' + $rc)

  Write-Host '  [3/4] Subiendo (WebClient + UTF8)...'
  # El PUT de la API publica SOLO acepta estos campos dentro de settings. Un workflow
  # bajado del servidor trae ademas binaryMode, timeSavedMode, availableInMCP, etc., y
  # entonces n8n responde "settings must NOT have additional properties".
  # Los campos que se filtran aqui NO se pierden: n8n conserva los suyos al actualizar.
  $permitidos = @('executionOrder','timezone','callerPolicy','saveDataErrorExecution','saveDataSuccessExecution','saveManualExecutions','saveExecutionProgress','executionTimeout','errorWorkflow')
  $settings = [ordered]@{}
  $quitados = @()
  if($new.settings){
    foreach($p in $new.settings.PSObject.Properties){
      if($permitidos -contains $p.Name){ $settings[$p.Name] = $p.Value } else { $quitados += $p.Name }
    }
  }
  if($settings.Count -eq 0){ $settings['executionOrder'] = 'v1' }
  if($quitados.Count -gt 0){ Write-Host ('        settings no aceptados por la API, se omiten: ' + ($quitados -join ', ')) }

  $body    = [ordered]@{ name=$new.name; nodes=$new.nodes; connections=$new.connections; settings=$settings }
  $payload = $body | ConvertTo-Json -Depth 40 -Compress
  $chk = Test-N8nEncoding $payload
  if($chk.Count -gt 0){
    foreach($x in $chk){ Write-Host ('        ' + $x) }
    throw 'ABORTADO: el payload se corrompio al serializar.'
  }
  $resp = Send-N8nJson $ctx ('/workflows/' + $wfId) 'PUT' $payload
  Write-Host ('        PUT OK -> nodos=' + $resp.nodes.Count + ' active=' + $resp.active)

  Write-Host '  [4/4] Verificando lo que quedo en el servidor...'
  $raw  = Get-N8nRaw $ctx ('/workflows/' + $wfId)
  $post = Test-N8nEncoding $raw
  if($post.Count -gt 0){
    foreach($x in $post){ Write-Host ('        OJO: ' + $x) }
    throw 'El workflow quedo con encoding roto en el servidor. Hay que arreglar y volver a subir.'
  }
  # Red mas fina: comparar los no-ASCII uno por uno. Esto atrapa los emojis que
  # se convierten en "??", que no son mojibake y ningun patron puede detectar.
  #
  # OJO: hay que comparar contra los NODOS re-serializados, no contra el texto
  # crudo del GET. La respuesta de n8n trae los nodos DOS veces (en 'nodes' y otra
  # vez dentro de 'activeVersion'), ademas de campos extra (createdAt, tags...),
  # asi que comparar el crudo da el doble de caracteres y un falso positivo.
  $srv = $raw | ConvertFrom-Json
  $srvBody = [ordered]@{ name=$srv.name; nodes=$srv.nodes; connections=$srv.connections; settings=$srv.settings }
  $srvPayload = $srvBody | ConvertTo-Json -Depth 40 -Compress
  $difs = Compare-N8nNoAscii $payload $srvPayload
  if($difs.Count -gt 0){
    Write-Host '        Se perdieron o cambiaron caracteres entre lo enviado y el servidor:'
    foreach($d in $difs){ Write-Host ('          ' + $d) }
    throw 'ABORTADO: el servidor NO tiene los mismos caracteres que se enviaron.'
  }
  Write-Host ('        Encoding sano y los ' + ([regex]::Matches($payload, '[^\u0000-\u007F]')).Count + ' caracteres especiales llegaron intactos.')

  if($anclas){
    foreach($a in $anclas){
      $i = $raw.IndexOf($a, [System.StringComparison]::Ordinal)
      if($i -ge 0){ Write-Host ("        ancla OK: '" + $raw.Substring($i, [Math]::Min($a.Length + 4, $raw.Length - $i)) + "'") }
      else { Write-Host ("        ancla NO ENCONTRADA: '" + $a + "'") }
    }
  }
}
