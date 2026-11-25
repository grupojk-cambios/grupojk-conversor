# ============================================================================
#  WORKFLOW "Bot JK - Procesar Media"  (Cambios JK - Fase 3)
# ============================================================================
#  Sub-workflow independiente y sincrono (sin Wait) para procesar audio,
#  imagen/comprobante y texto directo de clientes.
#
#  Genera workflow_media.json. Se sube con scripts\desplegar_media.ps1.
#  IMPORTANTE: guardar SIEMPRE con BOM UTF-8 (PowerShell 5.1 lo necesita).
# ============================================================================
$ErrorActionPreference = 'Stop'

$nodes = @(
  [ordered]@{
    parameters = [ordered]@{
      content = @'
## Bot JK - Procesar Media

Convierte cualquier mensaje de cliente (audio con Whisper, imagen/comprobante con GPT-4o Vision o texto directo)
en `{ texto }` unificado y guarda el `imgKeyId` en Redis cuando llega una imagen.

Sin nodos Wait: ejecución síncrona rápida y segura.
Se mantiene inactivo hasta que Kelvin lo publique manualmente en n8n.
'@
      height = 240
      width = 520
      color = 4
    }
    id = 'med33000-0000-4a00-9a00-mednota00001'
    name = 'Nota'
    type = 'n8n-nodes-base.stickyNote'
    typeVersion = 1
    position = @(
      -300,
      -260
    )
  },
  [ordered]@{
    parameters = [ordered]@{
      inputSource = 'passthrough'
    }
    id = 'med33000-0001-4a00-9a00-medtrig00001'
    name = 'Cuando lo Llama el Bot'
    type = 'n8n-nodes-base.executeWorkflowTrigger'
    typeVersion = 1.1
    position = @(
      -300,
      60
    )
  },
  [ordered]@{
    parameters = [ordered]@{
      conditions = [ordered]@{
        options = [ordered]@{
          typeValidation = 'loose'
          leftValue = ''
          caseSensitive = $true
        }
        conditions = @(
          ,[ordered]@{
            id = 'aud-cond-1'
            leftValue = '={{ $json.body.data.messageType }}'
            rightValue = 'audioMessage'
            operator = [ordered]@{
              operation = 'equals'
              type = 'string'
            }
          }
        )
        combinator = 'and'
      }
    }
    id = 'd0a1b2c3-e4f5-4060-9788-esaudio00001'
    name = 'Es Audio?'
    type = 'n8n-nodes-base.if'
    typeVersion = 2.2
    position = @(
      -60,
      60
    )
  },
  [ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Extrae el texto del mensaje. Cubre: texto simple, extendedTextMessage (incluye cita),
// pie de imagen/video/documento, y respuestas a botones/listas. Si el cliente CITO un
// mensaje, agregamos el texto citado como CONTEXTO para que el bot sepa a que se refiere.
let t = '';
let citado = '';
try {
  const m = $json.body.data.message || {};
  t = m.conversation
    || (m.extendedTextMessage && m.extendedTextMessage.text)
    || (m.imageMessage && m.imageMessage.caption)
    || (m.videoMessage && m.videoMessage.caption)
    || (m.documentMessage && m.documentMessage.caption)
    || (m.buttonsResponseMessage && m.buttonsResponseMessage.selectedDisplayText)
    || (m.listResponseMessage && m.listResponseMessage.title)
    || (m.templateButtonReplyMessage && m.templateButtonReplyMessage.selectedDisplayText)
    || '';
  // Contexto de cita (extendedText, imageMessage o data.contextInfo directamente)
  const ctx = (m.extendedTextMessage && m.extendedTextMessage.contextInfo)
    || (m.imageMessage && m.imageMessage.contextInfo)
    || (m.videoMessage && m.videoMessage.contextInfo)
    || $json.body.data.contextInfo
    || null;
  if (ctx && ctx.quotedMessage) {
    const q = ctx.quotedMessage;
    citado = q.conversation
      || (q.extendedTextMessage && q.extendedTextMessage.text)
      || (q.imageMessage && q.imageMessage.caption)
      || (q.videoMessage && q.videoMessage.caption)
      || '';
  }
} catch(e){}
let texto = String(t || '').normalize('NFKC').trim();
if (citado) {
  citado = String(citado).normalize('NFKC').trim();
  if (citado.length > 200) citado = citado.substring(0,200) + '...';
  texto = '[el cliente respondio citando esto que tu/asesor le dijiste antes: "' + citado + '"]\n' + texto;
}
return [{ json: { texto } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      -60,
      220
    )
    id = 'e1f2a3b4-c5d6-4071-9899-txtdirecto01'
    name = 'Texto Directo'
  },
  [ordered]@{
    parameters = [ordered]@{
      url = 'http://evolution-api:8080/chat/getBase64FromMediaMessage/BOT%20JK%20Kelvin'
      options = @{}
      specifyBody = 'json'
      method = 'POST'
      headerParameters = [ordered]@{
        parameters = @(
          ,[ordered]@{
            value = 'application/json'
            name = 'Content-Type'
          }
        )
      }
      sendBody = $true
      sendHeaders = $true
      jsonBody = '={ "message": { "key": { "id": "{{ $json.body.data.key.id }}" } }, "convertToMp4": false }'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'f2a3b4c5-d6e7-4082-9900-getbase64001'
    name = 'Descargar Audio'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      120,
      -60
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 3
    waitBetweenTries = 2000
    alwaysOutputData = $true
    credentials = [ordered]@{
      httpHeaderAuth = [ordered]@{
        id = '70cMtifwmTdIqY1l'
        name = 'Evolution apikey Kelvin 0380'
      }
    }
  },
  [ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Convierte el base64 del audio (de Evolution) en un archivo binario para Whisper.
const b64 = $json.base64;
if(!b64) return [{ json: { texto: '' } }];
return [{ json: { mimetype: $json.mimetype || '' }, binary: { data: { data: b64, mimeType: 'audio/ogg', fileName: 'audio.ogg' } } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      300,
      -60
    )
    id = 'a3b4c5d6-e7f8-4093-9a11-tobinario001'
    name = 'Audio a Binario'
  },
  [ordered]@{
    parameters = [ordered]@{
      binaryPropertyName = 'data'
      operation = 'transcribe'
      resource = 'audio'
      options = [ordered]@{
        language = 'es'
      }
    }
    id = 'b4c5d6e7-f8a9-4004-9b22-transcribe01'
    name = 'Transcribir Audio'
    type = '@n8n/n8n-nodes-langchain.openAi'
    typeVersion = 1.8
    position = @(
      480,
      -60
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 2
    waitBetweenTries = 2000
    alwaysOutputData = $true
    credentials = [ordered]@{
      openAiApi = [ordered]@{
        id = '44lRGIyEnSk1lMc5'
        name = 'cambios jk para n8n'
      }
    }
  },
  [ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Toma la transcripcion de Whisper como texto del mensaje.
let t='';
try { t = $('Transcribir Audio').item.json.text || ''; } catch(e){}
t = String(t).trim();
if(!t) t = 'El cliente envio una nota de voz que no se pudo entender. Pidele amablemente que la repita o escriba.';
return [{ json: { texto: String(t || '').normalize('NFKC') } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      660,
      -60
    )
    id = 'c5d6e7f8-a9b0-4015-9c33-txtaudio0001'
    name = 'Texto de Audio'
  },
  [ordered]@{
    parameters = [ordered]@{
      conditions = [ordered]@{
        options = [ordered]@{
          typeValidation = 'loose'
          leftValue = ''
          caseSensitive = $true
        }
        conditions = @(
          ,[ordered]@{
            id = 'img-cond-1'
            leftValue = '={{ $json.body.data.messageType }}'
            rightValue = 'imageMessage'
            operator = [ordered]@{
              operation = 'equals'
              type = 'string'
            }
          }
        )
        combinator = 'and'
      }
    }
    id = 'd1e2f3a4-b5c6-4170-9080-esimagen0001'
    name = 'Es Imagen?'
    type = 'n8n-nodes-base.if'
    typeVersion = 2.2
    position = @(
      -60,
      380
    )
  },
  [ordered]@{
    parameters = [ordered]@{
      url = 'http://evolution-api:8080/chat/getBase64FromMediaMessage/BOT%20JK%20Kelvin'
      options = @{}
      specifyBody = 'json'
      method = 'POST'
      headerParameters = [ordered]@{
        parameters = @(
          ,[ordered]@{
            value = 'application/json'
            name = 'Content-Type'
          }
        )
      }
      sendBody = $true
      sendHeaders = $true
      jsonBody = '={ "message": { "key": { "id": "{{ $json.body.data.key.id }}" } }, "convertToMp4": false }'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'f3a4b5c6-d7e8-4181-9191-getimg000001'
    name = 'Descargar Imagen'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      120,
      460
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 3
    waitBetweenTries = 2000
    alwaysOutputData = $true
    credentials = [ordered]@{
      httpHeaderAuth = [ordered]@{
        id = '70cMtifwmTdIqY1l'
        name = 'Evolution apikey Kelvin 0380'
      }
    }
  },
  [ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Convierte el base64 de la imagen (de Evolution) en binario para GPT-4o vision.
const b64 = $json.base64;
if(!b64) return [{ json: { sinImagen: true } }];
return [{ json: { mimetype: $json.mimetype || 'image/jpeg' }, binary: { data: { data: b64, mimeType: $json.mimetype || 'image/jpeg', fileName: 'img.jpg' } } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      300,
      460
    )
    id = 'a4b5c6d7-e8f9-4192-9a22-tobinimg0001'
    name = 'Imagen a Binario'
  },
  [ordered]@{
    parameters = [ordered]@{
      text = 'Esta imagen la envio un cliente de una casa de cambio de remesas por WhatsApp. Clasificala y responde SOLO en JSON valido sin texto extra: {"tipo": "comprobante|cuenta|otra", "resumen": "..."}. comprobante = recibo o captura de un pago/transferencia que el cliente hizo; el resumen DEBE ir asi, en una sola linea: "Monto: <monto con su moneda, ej. $30,00>, Moneda: <codigo de la moneda del monto: USD, VES, COP, PEN, BRL, MXN, CLP, ARS, UYU, PYG, BOB, CRC, DOP, CUP, GTQ, HNL, NIO, EUR o USDT; ojo que Colombia, Mexico, Chile, Argentina, Uruguay, Republica Dominicana y Cuba tambien usan el simbolo $>, Banco: <banco desde donde pago>, Fecha: <fecha>, Referencia: <numero de referencia, de comprobante o de transaccion>". cuenta = datos de una cuenta bancaria; el resumen asi: "Banco: <banco>, Cuenta: <numero>, Titular: <nombre>, Cedula: <cedula>". Si un dato no se ve, escribe "no visible". otra = cualquier otra cosa (resumen corto).'
      inputType = 'base64'
      modelId = [ordered]@{
        mode = 'list'
        __rl = $true
        cachedResultName = 'gpt-4o-mini'
        value = 'gpt-4o-mini'
      }
      resource = 'image'
      options = @{}
      operation = 'analyze'
      binaryPropertyName = 'data'
    }
    id = 'b5c6d7e8-f9a0-4103-9b33-leerimg00001'
    name = 'Leer Imagen'
    type = '@n8n/n8n-nodes-langchain.openAi'
    typeVersion = 1.8
    position = @(
      480,
      460
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 2
    waitBetweenTries = 2000
    alwaysOutputData = $true
    credentials = [ordered]@{
      openAiApi = [ordered]@{
        id = '44lRGIyEnSk1lMc5'
        name = 'cambios jk para n8n'
      }
    }
  },
  [ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Toma lo que GPT-4o leyo de la imagen y arma el texto para el flujo + guarda metadatos.
let raw='';
try { raw = $('Leer Imagen').item.json.content || $('Leer Imagen').item.json.text || ''; } catch(e){}
let tipo='otra', resumen='';
try {
  let limpio = String(raw).replace(/```json/gi,'').replace(/```/g,'').trim();
  const obj = JSON.parse(limpio);
  tipo = (obj.tipo||'otra').toLowerCase();
  resumen = obj.resumen||'';
} catch(e){ resumen = String(raw).slice(0,200); }
let keyId='';
try { keyId = $('Cuando lo Llama el Bot').first().json.body.data.key.id || ''; } catch(e){}
// Huella de la foto (el sha256 que manda WhatsApp). Si el cliente reenvia la MISMA foto, la huella
// es la misma: asi "Revisar Operacion" reconoce el deposito repetido aunque no se lea la referencia.
let huella='';
try {
  const im = $('Cuando lo Llama el Bot').first().json.body.data.message.imageMessage || {};
  const f = im.fileSha256;
  let bytes = [];
  if (typeof f === 'string') bytes = Array.from(Buffer.from(f, 'base64'));
  else if (f && typeof f === 'object') bytes = Object.keys(f).sort((a, b) => Number(a) - Number(b)).map(k => f[k]);
  huella = bytes.slice(0, 8).map(x => ('0' + (Number(x) & 255).toString(16)).slice(-2)).join('');
} catch(e){ huella=''; }
let texto='';
if(tipo.indexOf('comprobante')>=0){ texto = '[El cliente envio un COMPROBANTE de pago. Datos leidos: ' + resumen + (huella ? ' Huella: ' + huella : '') + ']'; }
else if(tipo.indexOf('cuenta')>=0){ texto = '[El cliente envio una imagen con una CUENTA bancaria. Datos: ' + resumen + ']'; }
else { texto = '[El cliente envio una imagen que no parece comprobante ni cuenta de banco]'; }
// EL PIE DE FOTO es del cliente: muchos mandan la captura y escriben la cuenta destino en el pie de la
// misma foto ("Tipo de cuenta: VES / 0102... / cedula / 200$", un cliente, 24/11). Antes se
// descartaba y el bot contestaba "Pasame la cuenta destino" teniendo la cuenta ahi. Va DESPUES de la
// nota de la imagen, como si lo hubiera escrito aparte: "Revisar Operacion" la toma como la cuenta.
let pie = '';
try { pie = String($('Cuando lo Llama el Bot').first().json.body.data.message.imageMessage.caption || '').trim(); } catch(e){ pie = ''; }
if (pie) texto += '\n' + pie;
return [{ json: { texto, tipoImagen: tipo, resumenImagen: resumen, imgKeyId: keyId } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      660,
      460
    )
    id = 'c6d7e8f9-a0b1-4114-9c44-txtimg000001'
    name = 'Texto de Imagen'
  },
  [ordered]@{
    parameters = [ordered]@{
      value = '={{ $json.imgKeyId }}'
      expire = $true
      ttl = 86400
      keyType = 'string'
      key = '={{ ''lastimg:'' + $(''Cuando lo Llama el Bot'').first().json.body.data.key.remoteJid }}'
      operation = 'set'
    }
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      840,
      460
    )
    id = 'd7e8f9a0-b1c2-4125-9d55-rsetimg00001'
    name = 'Redis Guardar Imagen'
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  }
)

$connections = [ordered]@{
  'Cuando lo Llama el Bot' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Es Audio?'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Es Audio?' = [ordered]@{
    main = @(
      @(
        ,[ordered]@{
          node = 'Descargar Audio'
          type = 'main'
          index = 0
        }
      ),
      @(
        ,[ordered]@{
          node = 'Es Imagen?'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Es Imagen?' = [ordered]@{
    main = @(
      @(
        ,[ordered]@{
          node = 'Descargar Imagen'
          type = 'main'
          index = 0
        }
      ),
      @(
        ,[ordered]@{
          node = 'Texto Directo'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Descargar Imagen' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Imagen a Binario'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Imagen a Binario' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Leer Imagen'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Leer Imagen' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Texto de Imagen'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Texto de Imagen' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Guardar Imagen'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Descargar Audio' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Audio a Binario'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Audio a Binario' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Transcribir Audio'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Transcribir Audio' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Texto de Audio'
          type = 'main'
          index = 0
        }
      )
    )
  }
}

$wf = [ordered]@{
  name = 'Bot JK - Procesar Media'
  nodes = $nodes
  connections = $connections
  settings = [ordered]@{ executionOrder = 'v1'; timezone = 'America/Guayaquil' }
}
$salida = Join-Path $PSScriptRoot 'workflow_media.json'
$json = $wf | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($salida, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('JSON generado: ' + $salida + ' | nodos: ' + $nodes.Count)
