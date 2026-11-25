# ============================================================================
#  WORKFLOW "Bot JK - Publicar y Registrar Operacion"  (Cambios JK - Fase 2)
# ============================================================================
#  Sub-workflow independiente para publicar aprobaciones, correcciones y
#  registrar operaciones (de dia y de noche) en Supabase.
#
#  Genera workflow_operacion_publicar.json.
#  Se sube con scripts\desplegar_operacion_publicar.ps1.
#  IMPORTANTE: guardar SIEMPRE con BOM UTF-8 (PowerShell 5.1 lo necesita).
# ============================================================================
$ErrorActionPreference = 'Stop'

$nodes = @(
  [ordered]@{
    parameters = [ordered]@{
      content = @'
## Bot JK - Publicar y Registrar Operacion

Ejecuta las publicaciones en el grupo de TRANSFERIR y registros en Supabase cuando lo llama el bot principal:
- **aprobar**: manda sticker Pedido Aprobado, re-descarga y publica la captura, separa y envía las cuentas, revisa montos y guarda cada cuenta en Supabase.
- **correccion**: publica los datos corregidos en TRANSFERIR y actualiza la fila en Supabase.
- **noche**: desempaca y guarda las filas nocturnas (`en_espera`) en Supabase.

Se mantiene inactivo hasta que Kelvin lo publique manualmente en n8n.
'@
      height = 320
      width = 520
      color = 4
    }
    id = 'pub22000-0000-4a00-9a00-pubnota00001'
    name = 'Nota'
    type = 'n8n-nodes-base.stickyNote'
    typeVersion = 1
    position = @(
      1900,
      -100
    )
  },
  [ordered]@{
    parameters = [ordered]@{
      inputSource = 'passthrough'
    }
    id = 'pub22000-0001-4a00-9a00-pubtrig00001'
    name = 'Cuando lo Llama el Bot'
    type = 'n8n-nodes-base.executeWorkflowTrigger'
    typeVersion = 1.1
    position = @(
      1900,
      300
    )
  },
  [ordered]@{
    parameters = [ordered]@{
      options = @{}
      rules = [ordered]@{
        values = @(
          [ordered]@{
            conditions = [ordered]@{
              options = [ordered]@{
                typeValidation = 'loose'
                leftValue = ''
                caseSensitive = $true
              }
              conditions = @(
                ,[ordered]@{
                  id = 'pub-aprobar'
                  leftValue = '={{ $json.modoPublicar }}'
                  rightValue = 'aprobar'
                  operator = [ordered]@{
                    operation = 'equals'
                    type = 'string'
                  }
                }
              )
              combinator = 'and'
            }
            renameOutput = $true
            outputKey = 'aprobar'
          },
          [ordered]@{
            conditions = [ordered]@{
              options = [ordered]@{
                typeValidation = 'loose'
                leftValue = ''
                caseSensitive = $true
              }
              conditions = @(
                ,[ordered]@{
                  id = 'pub-correccion'
                  leftValue = '={{ $json.modoPublicar }}'
                  rightValue = 'correccion'
                  operator = [ordered]@{
                    operation = 'equals'
                    type = 'string'
                  }
                }
              )
              combinator = 'and'
            }
            renameOutput = $true
            outputKey = 'correccion'
          },
          [ordered]@{
            conditions = [ordered]@{
              options = [ordered]@{
                typeValidation = 'loose'
                leftValue = ''
                caseSensitive = $true
              }
              conditions = @(
                ,[ordered]@{
                  id = 'pub-noche'
                  leftValue = '={{ $json.modoPublicar }}'
                  rightValue = 'noche'
                  operator = [ordered]@{
                    operation = 'equals'
                    type = 'string'
                  }
                }
              )
              combinator = 'and'
            }
            renameOutput = $true
            outputKey = 'noche'
          }
        )
      }
    }
    id = 'pub22000-0002-4a00-9a00-pubswitch001'
    name = 'Router Publicacion'
    type = 'n8n-nodes-base.switch'
    typeVersion = 3.2
    position = @(
      2120,
      300
    )
  },
  [ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Desempaca las filas nocturnas enviadas por "Armar Filas Noche" para guardarlas 1 a 1 en Supabase.
const filas = Array.isArray($json.filas) ? $json.filas : [];
return filas.map(row => ({ json: row }));
'@
    }
    id = 'pub22000-0003-4a00-9a00-pubnoche0001'
    name = 'Desempacar Filas Noche'
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      2360,
      740
    )
  },
  [ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Avisa en el grupo si los montos de las cuentas no suman lo que dice el comprobante.
// Solo avisa cuando esta SEGURO: si no se pudo leer el monto del comprobante, o si alguna
// cuenta no traia monto, se queda callado. Una falsa alarma cada dos por tres haria que
// nadie le haga caso.
let cuentas = [];
try { cuentas = $('Separar Cuentas').all().map(i => i.json); } catch(e){}
if (cuentas.length < 2) return [];                       // con una sola cuenta no hay nada que sumar

let total = null;
try { total = $('Cuando lo Llama el Bot').first().json.montoComprobante; } catch(e){}
if (total === null || total === undefined) return [];    // no se leyo el monto del comprobante

if (cuentas.some(c => c.monto === null || c.monto === undefined)) return [];  // falta algun monto

const suma = cuentas.reduce((a, c) => a + Number(c.monto), 0);
const dif = Math.round((Number(total) - suma) * 100) / 100;
if (Math.abs(dif) < 0.01) return [];                     // cuadra

const redondo = (n) => (Math.round(n * 100) / 100);
return [{ json: { aviso:
  'OJO: el comprobante dice $' + redondo(total) + ' y las ' + cuentas.length +
  ' cuentas suman $' + redondo(suma) + '. Diferencia: $' + redondo(Math.abs(dif)) } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      3460,
      400
    )
    id = 'd0e1f2a3-0000-4b00-9000-revisarmont01'
    name = 'Revisar Montos'
    executeOnce = $true
  },
  [ordered]@{
    parameters = [ordered]@{
      specifyBody = 'json'
      url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'
      options = @{}
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
      jsonBody = '={{ JSON.stringify({ number: "593961230380-1601657528@g.us", text: $json.aviso }) }}'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'd0e1f2a3-0000-4b00-9000-avisarmonto01'
    name = 'Avisar Montos'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      3640,
      400
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 2
    waitBetweenTries = 1000
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
      url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'
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
      jsonBody = '={{ JSON.stringify({ number: "593961230380-1601657528@g.us", text: $json.texto }) }}'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'c9d0e1f2-0002-4a00-9c00-correccion02'
    name = 'Publicar Correccion'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      2336,
      736
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 2
    waitBetweenTries = 1000
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
      value = '={{ JSON.stringify({ jid: $("Cuando lo Llama el Bot").first().json.jid, nombre: $("Cuando lo Llama el Bot").first().json.nombre, idCuenta: $("Cuando lo Llama el Bot").first().json.idCuenta, idCaptura: $("Cuando lo Llama el Bot").first().json.idCaptura, publicacion: $("Cuando lo Llama el Bot").first().json.publicacion }) }}'
      expire = $true
      ttl = 172800
      keyType = 'string'
      key = '={{ ''grupoMsg:'' + (($json.key && $json.key.id) || ($json.data && $json.data.key && $json.data.key.id) || ''nada'') }}'
      operation = 'set'
    }
    id = 'c9d0e1f2-0003-4a00-9c00-correccion03'
    name = 'Redis Guardar Publicacion Correccion'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      2512,
      736
    )
    onError = 'continueRegularOutput'
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  },
  [ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// La fila de esa cuenta en Supabase queda con los datos corregidos: asi, cuando la operadora devuelva la
// foto, la Fase B la compara con los datos BUENOS. Solo van las columnas que se cambian.
const v = $('Cuando lo Llama el Bot').first().json;
return [{ json: {
  cuentas: [{ id: v.idCuenta || '', texto: v.datos, monto: v.monto }],
  notas: 'Datos corregidos por el cliente (la operadora pidio: ' + (v.nota || 'verificar') + ')'
} }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      2688,
      736
    )
    id = 'c9d0e1f2-0004-4a00-9c00-correccion04'
    name = 'Datos Correccion Supabase'
  },
  [ordered]@{
    parameters = [ordered]@{
      inputsToIgnore = ''
      tableId = 'transacciones_detal_por_whatsapp'
      filterString = '={{ "id_msgs_grupo=cs." + JSON.stringify([ $("Cuando lo Llama el Bot").first().json.publicacion || "sin-dato" ]) + "&estado=in.(en_proceso,en_espera)" }}'
      resource = 'row'
      filterType = 'string'
      operation = 'update'
      dataToSend = 'autoMapInputData'
    }
    id = 'c9d0e1f2-0005-4a00-9c00-correccion05'
    name = 'Corregir Cuenta en Supabase'
    type = 'n8n-nodes-base.supabase'
    typeVersion = 1
    position = @(
      2864,
      736
    )
    onError = 'continueRegularOutput'
    credentials = [ordered]@{
      supabaseApi = [ordered]@{
        id = 'JCvvp9JkZ15OpA9E'
        name = 'Supabase Cambios JK'
      }
    }
  },
  [ordered]@{
    parameters = [ordered]@{
      operation = 'get'
      key = '={{ ''lastimg:'' + $(''Cuando lo Llama el Bot'').first().json.jid }}'
      keyType = 'string'
      propertyName = 'imgKeyId'
      options = @{}
    }
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      2380,
      220
    )
    id = 'bb22cc33-dd44-4271-9bbb-redisimg0001'
    name = 'Redis Leer ID Imagen'
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
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
      jsonBody = '={ "message": { "key": { "id": "{{ $("Cuando lo Llama el Bot").first().json.idImagen || $json.imgKeyId }}" } }, "convertToMp4": false }'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'cc33dd44-ee55-4282-9ccc-redownload001'
    name = 'Re-descargar Imagen'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      2560,
      220
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 2
    waitBetweenTries = 1000
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
      url = 'http://evolution-api:8080/message/sendMedia/BOT%20JK%20Kelvin'
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
      jsonBody = '={{ JSON.stringify({ number: "593961230380-1601657528@g.us", mediatype: "image", mimetype: ($json.mimetype || "image/jpeg"), media: $json.base64, caption: ("Cliente: " + $("Cuando lo Llama el Bot").first().json.nombreMostrar) }) }}'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'dd44ee55-ff66-4393-9ddd-sendimg0001'
    name = 'Enviar Imagen Grupo'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      2740,
      220
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 2
    waitBetweenTries = 1000
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
      url = 'http://evolution-api:8080/message/sendSticker/BOT%20JK%20Kelvin'
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
      jsonBody = '={ "number": "{{ $("Cuando lo Llama el Bot").first().json.jid }}", "sticker": "https://grupojk-cambios.github.io/grupojk-conversor/logos/sticker-pedido-aprobado.webp" }'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'ee55ff66-aa77-4404-9eee-sendsticker01'
    name = 'Enviar Sticker Cliente'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      2920,
      220
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 2
    waitBetweenTries = 1000
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
      value = '={{ JSON.stringify({ jid: $(''Cuando lo Llama el Bot'').first().json.jid, nombre: $(''Cuando lo Llama el Bot'').first().json.nombreMostrar, idCuenta: $(''Cuando lo Llama el Bot'').first().json.idCuenta, idCaptura: $(''Cuando lo Llama el Bot'').first().json.idImagen }) }}'
      expire = $true
      ttl = 172800
      keyType = 'string'
      key = '={{ ''grupoMsg:'' + (($json.key && $json.key.id) || ($json.data && $json.data.key && $json.data.key.id) || ''nada'') }}'
      operation = 'set'
    }
    id = 'd0e1f2a3-0000-4b00-9000-marcapubimg1'
    name = 'Marcar Publicacion Imagen'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      2740,
      60
    )
    onError = 'continueRegularOutput'
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  },
  [ordered]@{
    parameters = [ordered]@{
      value = '={{ JSON.stringify({ jid: $(''Cuando lo Llama el Bot'').first().json.jid, nombre: $(''Cuando lo Llama el Bot'').first().json.nombreMostrar, idCuenta: ($(''Separar Cuentas'').item.json.idCuenta || $(''Cuando lo Llama el Bot'').first().json.idCuenta), idCaptura: $(''Cuando lo Llama el Bot'').first().json.idImagen }) }}'
      expire = $true
      ttl = 172800
      keyType = 'string'
      key = '={{ ''grupoMsg:'' + (($json.key && $json.key.id) || ($json.data && $json.data.key && $json.data.key.id) || ''nada'') }}'
      operation = 'set'
    }
    id = 'd0e1f2a3-0000-4b00-9000-marcapubcta1'
    name = 'Marcar Publicacion Cuenta'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      3280,
      400
    )
    onError = 'continueRegularOutput'
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  },
  [ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// Una publicacion por cada cuenta que mando el cliente, con una cabecera que diga de quien
// es y por cuanto. Antes salia el bloque pelado y la operadora no sabia de quien era.
const ap = $('Cuando lo Llama el Bot').first().json || {};
const nombre = ap.nombreMostrar || ap.nombre || 'Cliente';

let lista = (ap.mensajesAprobar !== undefined) ? (ap.mensajesAprobar || []) : (ap.mensajes || []);
const ro = { registro: ap.registro || null };

// ===== CUENTAS DESTINO, UNA POR BLOQUE (lo usan "Separar Cuentas", "Armar Filas Noche" y "Revisar Operacion") =====
// Los nombres son propios (montoDelBloque, limpiarNotasBot...) para no chocar con los de "Revisar Operacion".
// Las notas que escribe el propio bot al leer una imagen no son cuentas del cliente.
function limpiarNotasBot(t){
  return String(t || '')
    .replace(/\[El cliente envio un COMPROBANTE[^\]]*\]/gi, '')
    .replace(/\[El cliente envio una imagen que no parece[^\]]*\]/gi, '')
    .replace(/\[El cliente envio una imagen con una CUENTA bancaria\.?\s*Datos:\s*([^\]]*)\]/gi, 'Cuenta (imagen): $1')
    .trim();
}

// Monto del bloque: "$30", "30$", "30 usd", "$30,50". Si no hay, null.
// Primero se busca "$30" y despues "30$" EN LA MISMA LINEA. Con el salto de linea permitido, una
// cedula con "$60" en la linea de abajo salia como monto ("Ci 11111111 / $60" -> $11111111).
function montoDelBloque(t){
  const s = String(t);
  const m = s.match(/\$[ \t]*([0-9]+(?:[.,][0-9]{1,2})?)/) || s.match(/([0-9]+(?:[.,][0-9]{1,2})?)[ \t]*(?:\$|usd|dolares|dolar)/i);
  if (!m) return null;
  const v = parseFloat(String(m[1]).replace(',', '.'));
  return isNaN(v) ? null : v;
}

const CLAVES_CUENTA = ['bancolombia','nequi','pago movil','banco','cuenta','titular','cedula','cc ',' ci ',
                'swift','interbank','binance','zelle','pichincha','guayaquil','produbanco','pacifico',
                'bancolombia','ahorro','corriente','banesco','mercantil','provincial','bdv','bicentenario',
                'bancamiga','davivienda','daviplata','plin','yape','paypal','usdt','wallet','billetera'];
// Un bloque tambien es una cuenta si trae un numero largo o un correo, aunque no diga "banco":
// asi no se pierde el caso del 20/11 (pais, cuenta de 20 digitos, titular, cedula, monto).
function esBloqueCuenta(bloque){
  const bajo = ' ' + bloque.toLowerCase() + ' ';
  if (CLAVES_CUENTA.some(k => bajo.indexOf(k) !== -1)) return true;
  if (/[0-9]{10,}/.test(bajo.replace(/([0-9])[ .-](?=[0-9])/g, '$1'))) return true;
  return /[^ @]+@[^ @]+\.[a-z]{2,}/.test(bajo);
}

// ---------- cuantas cuentas trae un mensaje ----------
// Antes se partia el mensaje en cada renglon vacio. Pero muchos clientes escriben UNA cuenta con
// renglones vacios en el medio ("Banco / (vacio) / numero / (vacio) / titular y cedula / (vacio) / $60"),
// y al grupo iban 2 o 3 publicaciones sin monto (revision de los chats reales, 21/11). Ahora las cuentas
// se cuentan por lo que las identifica: un numero de cuenta o telefono, un correo o una billetera.
// La cedula NO cuenta: "C.I: 0900000001" tiene 10 digitos pero no es otra cuenta.
function tieneIdentificador(p){
  for (const l of String(p).split('\n')){
    // Tampoco un telefono de contacto ("Contactanos al 09...", "WhatsApp 09...").
    const sinCedula = l.replace(/(c\.?\s?i\b\.?|c\.?\s?c\b\.?|c[eé]d(ula)?\b\.?|rif\b|dni\b|pasaporte|\b[ve]-)\s*:?\s*[0-9][0-9 .\-]*/gi, ' ')
                       .replace(/(cont[aá]ct\w*|whats?app|wsp)\s*(al|:)?\s*\+?[0-9][0-9 .\-]*/gi, ' ');
    if (/[0-9]{10,}/.test(sinCedula.replace(/([0-9])[ .\-](?=[0-9])/g, '$1'))) return true;
    if (/[^\s@]+@[^\s@]+\.[a-z]{2,}/i.test(l)) return true;
    if (/(^|\s)[A-Za-z0-9]{26,}(\s|$)/.test(l)) return true;
  }
  return false;
}
// Con que suele empezar una cuenta (para saber donde empieza la siguiente).
const BANCOS_INICIO = /(banco|bank|bancolombia|nequi|daviplata|pago\s*m[oó]vil|zelle|binance|pichincha|guayaquil|produbanco|pac[ií]fico|banesco|mercantil|provincial|bdv|bicentenario|bancamiga|bnc|davivienda|interbank|bcp|scotiabank|yape|plin|paypal|usdt)/i;
// Un pedazo que es solo el monto ("$60", "40$", "Monto 25 usd").
const soloMonto = p => String(p).length <= 30 && montoDelBloque(p) !== null && !/[0-9]{6,}/.test(String(p).replace(/[ .,\-]/g, ''));
// Un pedazo que parece el nombre del titular (pocas palabras, solo letras). La charla no ("gracias amigo").
const CHARLA = /\b(hola|buen[oa]s?|d[ií]as|tardes|noches|gracias|porfa|favor|amig[oa]|herman[oa]|ok|listo|dale|saludos|bendiciones|av[ií]same|avisa|espero|cuando|llegue)\b/i;
const nombreProbable = p => /^[A-Za-zÁÉÍÓÚáéíóúÑñÜü .']{3,60}$/.test(String(p)) && String(p).trim().split(/\s+/).length <= 5 && !CHARLA.test(p);
function cuentasDelMensaje(t){
  const partes = String(t).split(/\n\s*\n+/).map(x => x.trim()).filter(Boolean);
  const sirve = p => esBloqueCuenta(p) || soloMonto(p) || nombreProbable(p);
  // De cada cuenta se quita lo que viene antes de sus datos (el saludo) y la charla.
  const armar = piezas => { const d = piezas.findIndex(p => esBloqueCuenta(p)); return d === -1 ? '' : piezas.slice(d).filter(sirve).join('\n'); };
  const conId = partes.filter(tieneIdentificador).length;
  if (conId <= 1) return [armar(partes)].filter(Boolean);          // UNA sola cuenta, aunque traiga renglones vacios
  // VARIAS cuentas: cada una empieza con su banco o su numero; el titular, la cedula y el monto que vienen
  // despues son de esa misma cuenta.
  const grupos = [];
  let actual = null;
  for (const p of partes){
    const id = tieneIdentificador(p);
    const otra = actual && actual.id && (id || (BANCOS_INICIO.test(p) && !soloMonto(p)));
    if (!actual || otra){ actual = { piezas: [], id: false }; grupos.push(actual); }
    actual.piezas.push(p);
    if (id) actual.id = true;
  }
  return grupos.map(g => armar(g.piezas)).filter(Boolean);
}

// Un bloque por cuenta, con la cabecera "nombre - $monto". Se recorre mensaje por mensaje para que
// cada bloque conserve el id del mensaje del que salio (para citarselo al cliente despues).
// Si no se reconoce ningun bloque (lo escribio de una forma rara), va todo junto, como antes: es
// preferible a dejar a la operadora sin la cuenta.
// El monto del deposito: la suma de las capturas, solo si se les leyo el monto a TODAS (si no, el de
// respaldo, o nada). Sirve para la cabecera cuando el cliente mando UNA sola cuenta sin monto.
function montoDelDeposito(ro, respaldo){
  const cs = ((ro && ro.registro) || {}).capturas || [];
  if (cs.length && cs.every(c => typeof c.monto === 'number' && !isNaN(c.monto))) return Math.round(cs.reduce((a, c) => a + c.monto, 0) * 100) / 100;
  return (typeof respaldo === 'number' && !isNaN(respaldo)) ? respaldo : null;
}

function bloquesDeCuentas(lista, nombre, todoSiNada, idTodo, montoDeposito){
  const out = [];
  for (const m of (lista || [])){
    const t = limpiarNotasBot(m && m.texto);
    if (!t) continue;
    for (const bloque of cuentasDelMensaje(t)){
      const monto = montoDelBloque(bloque);
      out.push({ cuenta: nombre + (monto !== null ? ' - $' + monto : '') + '\n\n' + bloque, idCuenta: (m && m.id) || '', monto, texto: bloque });
    }
  }
  if (!out.length){
    const todo = String(todoSiNada || '').trim();
    if (todo) out.push({ cuenta: nombre + '\n\n' + todo, idCuenta: idTodo || '', monto: null, texto: todo });
  }
  // UNA sola cuenta y sin monto: va con el monto del deposito (21/11: la clienta mando banco, cedula y
  // telefono, y en transferir la cuenta salio sin precio). Con varias cuentas no se reparte nada.
  if (out.length === 1 && out[0].monto === null && typeof montoDeposito === 'number' && !isNaN(montoDeposito)){
    out[0].monto = montoDeposito;
    out[0].cuenta = nombre + ' - $' + montoDeposito + '\n\n' + out[0].texto;
  }
  return out;
}
return bloquesDeCuentas(lista, nombre, ap.datosCuenta, ap.idCuenta, montoDelDeposito(ro, ap.montoComprobante)).map(b => ({ json: b }));
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      2920,
      400
    )
    id = 'ff66aa77-bb88-4505-9fff-separarctas1'
    name = 'Separar Cuentas'
  },
  [ordered]@{
    parameters = [ordered]@{
      url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'
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
      jsonBody = '={{ JSON.stringify({ number: "593961230380-1601657528@g.us", text: $json.cuenta }) }}'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'aa77bb88-cc99-4616-9aaa-sendcuenta01'
    name = 'Enviar Cuenta Grupo'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      3100,
      400
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 2
    waitBetweenTries = 1000
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
// Arma UNA fila de reporte por cada operacion aprobada (comprobante + cuenta destino).
// Orden de columnas (debe coincidir con la tabla de Excel): Fecha, Cliente, Numero, CuentaDestino, Comprobante, Tipo.
function p2(n){ return String(n).padStart(2,'0'); }
const d = new Date(Date.now() - 5*3600000); // hora Ecuador (UTC-5)
const fecha = d.getUTCFullYear()+'-'+p2(d.getUTCMonth()+1)+'-'+p2(d.getUTCDate())+' '+p2(d.getUTCHours())+':'+p2(d.getUTCMinutes());
let a = {};
try { a = $('Cuando lo Llama el Bot').first().json || {}; } catch(e){}
const cliente = a.nombre || 'Cliente';
const numero = a.numero ? ('+'+a.numero) : '';
const cuenta = String(a.datosCuenta || '').replace(/\n+/g,' | ').trim();
let comprobante = '';
const mc = String(a.mensajeCombinado || '');
const m = mc.match(/datos leidos:\s*([^\]]*)\]/i);
if (m) comprobante = m[1].trim(); else comprobante = '(ver comprobante en grupo)';
let tipo = 'detal';
tipo = a.modoTarifa || 'detal';
const fila = [fecha, cliente, numero, cuenta, comprobante, tipo];
return [{ json: { Fecha:fecha, Cliente:cliente, Numero:numero, CuentaDestino:cuenta, Comprobante:comprobante, Tipo:tipo, fila } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      2380,
      340
    )
    id = 'bb88cc99-dd00-4727-9bbb-registrarop1'
    name = 'Registrar Operación'
    onError = 'continueRegularOutput'
    alwaysOutputData = $true
  },
  [ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// ===== LAS FILAS PARA SUPABASE (tabla transacciones_detal_por_whatsapp), DE DIA =====
// UNA FILA POR CUENTA DESTINO: cada cuenta tiene su propio estado y pasa a 'enviada' cuando la
// operadora devuelve la foto de ESA cuenta (pedido de Kelvin, 20/11). Las cuentas de un mismo
// deposito comparten id_msg_captura. Corre DESPUES de publicar en el grupo, asi cada fila guarda el
// id de su publicacion (id_msgs_grupo): con eso "Marcar Enviada en Supabase" encuentra la fila.
// Los campos se llaman EXACTAMENTE como las columnas: el nodo siguiente los guarda tal cual.
// Lo comun a todas las cuentas de un deposito: quien, cuanto, referencia, banco y las capturas.
function filaBase(reg, numeroOJid, nombre, idImagen){
  reg = reg || {};
  const capturas = Array.isArray(reg.capturas) ? reg.capturas : [];
  const montos = capturas.map(c => c.monto).filter(m => typeof m === 'number' && !isNaN(m));
  const unicos = a => a.filter((x, i) => x && a.indexOf(x) === i);
  return {
    whatsapp: String(numeroOJid || '').split('@')[0].replace(/\D/g, ''),
    nombre_cliente: nombre || null,
    monto_deposito: montos.length ? Math.round(montos.reduce((a, b) => a + b, 0) * 100) / 100 : null,
    ref_deposito: unicos(capturas.map(c => c.ref)).join(', ') || null,
    banco_origen: unicos(capturas.map(c => c.banco)).join(', ') || null,
    huella_foto: (capturas.find(c => c.huella) || {}).huella || null,
    id_msg_captura: idImagen || (capturas[0] || {}).id || null,
    capturas
  };
}
const ap = $('Cuando lo Llama el Bot').first().json || {};
const reg = ap.registro || {};
const idDe = j => String((j && j.key && j.key.id) || (j && j.data && j.data.key && j.data.key.id) || '');
let separadas = [], enviadas = [], idFoto = '';
try { separadas = $('Separar Cuentas').all().map(i => i.json); } catch(e){}
try { enviadas = $('Enviar Cuenta Grupo').all().map(i => i.json); } catch(e){}
try { idFoto = idDe($('Enviar Imagen Grupo').first().json); } catch(e){}
const base = filaBase(reg, ap.numero || ap.jid, ap.nombreMostrar || ap.nombre, ap.idImagen);
const ahoraIso = new Date().toISOString();
return separadas.map((c, i) => ({ json: Object.assign({}, base, {
  estado: 'en_proceso',
  cuentas: [{ id: c.idCuenta || '', texto: c.texto || c.cuenta || '', monto: (c.monto === undefined ? null : c.monto) }],
  // La foto de la captura va con la primera cuenta: si la operadora responde a la foto, es esa.
  id_msgs_grupo: [idDe(enviadas[i]), i === 0 ? idFoto : ''].filter(Boolean),
  fuera_de_horario: false,
  publicado_en: ahoraIso,
  notas: separadas.length > 1 ? ('Cuenta ' + (i + 1) + ' de ' + separadas.length + ' del mismo deposito') : null
}) }));
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      3728,
      208
    )
    id = 'a1b2c3d4-0009-4e00-9a00-registro00009'
    name = 'Armar Fila Supabase'
    onError = 'continueRegularOutput'
  },
  [ordered]@{
    parameters = [ordered]@{
      tableId = 'transacciones_detal_por_whatsapp'
      operation = 'create'
      resource = 'row'
      inputsToIgnore = ''
      dataToSend = 'autoMapInputData'
    }
    id = 'a1b2c3d4-0010-4e00-9a00-registro00010'
    name = 'Guardar Operacion en Supabase'
    type = 'n8n-nodes-base.supabase'
    typeVersion = 1
    position = @(
      3904,
      208
    )
    onError = 'continueRegularOutput'
    credentials = [ordered]@{
      supabaseApi = [ordered]@{
        id = 'JCvvp9JkZ15OpA9E'
        name = 'Supabase Cambios JK'
      }
    }
  }
)

$connections = [ordered]@{
  'Cuando lo Llama el Bot' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Router Publicacion'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Router Publicacion' = [ordered]@{
    main = @(
      @(
        [ordered]@{
          node = 'Redis Leer ID Imagen'
          type = 'main'
          index = 0
        },
        [ordered]@{
          node = 'Enviar Sticker Cliente'
          type = 'main'
          index = 0
        },
        [ordered]@{
          node = 'Registrar Operación'
          type = 'main'
          index = 0
        }
      ),
      @(
        ,[ordered]@{
          node = 'Publicar Correccion'
          type = 'main'
          index = 0
        }
      ),
      @(
        ,[ordered]@{
          node = 'Desempacar Filas Noche'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Desempacar Filas Noche' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Guardar Operacion en Supabase'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Publicar Correccion' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Guardar Publicacion Correccion'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Guardar Publicacion Correccion' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Datos Correccion Supabase'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Datos Correccion Supabase' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Corregir Cuenta en Supabase'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Armar Fila Supabase' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Guardar Operacion en Supabase'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Leer ID Imagen' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Re-descargar Imagen'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Re-descargar Imagen' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Enviar Imagen Grupo'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Enviar Imagen Grupo' = [ordered]@{
    main = @(
      ,@(
        [ordered]@{
          node = 'Separar Cuentas'
          type = 'main'
          index = 0
        },
        [ordered]@{
          node = 'Marcar Publicacion Imagen'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Separar Cuentas' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Enviar Cuenta Grupo'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Enviar Cuenta Grupo' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Marcar Publicacion Cuenta'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Marcar Publicacion Cuenta' = [ordered]@{
    main = @(
      ,@(
        [ordered]@{
          node = 'Revisar Montos'
          type = 'main'
          index = 0
        },
        [ordered]@{
          node = 'Armar Fila Supabase'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Revisar Montos' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Avisar Montos'
          type = 'main'
          index = 0
        }
      )
    )
  }
}

$wf = [ordered]@{
  name = 'Bot JK - Publicar y Registrar Operacion'
  nodes = $nodes
  connections = $connections
  settings = [ordered]@{ executionOrder = 'v1'; timezone = 'America/Guayaquil' }
}
$salida = Join-Path $PSScriptRoot 'workflow_operacion_publicar.json'
$json = $wf | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($salida, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('JSON generado: ' + $salida + ' | nodos: ' + $nodes.Count)
