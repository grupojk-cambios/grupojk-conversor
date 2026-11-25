# ============================================================================
#  WORKFLOW "Bot JK - Grupos de Operadoras"  (Cambios JK - Fase 1)
# ============================================================================
#  Sub-workflow independiente para entregas de comprobantes, foto suelta y
#  "verificar datos" en el grupo de TRANSFERIR.
#
#  Genera workflow_operadoras.json. Se sube con scripts\desplegar_operadoras.ps1.
#  IMPORTANTE: guardar SIEMPRE con BOM UTF-8 (PowerShell 5.1 lo necesita).
# ============================================================================
$ErrorActionPreference = 'Stop'

$nodes = @(
  [ordered]@{
    parameters = [ordered]@{
      content = @'
## Bot JK - Grupos de Operadoras

Atiende las acciones del grupo de TRANSFERIR cuando lo llama el bot principal:
- **entregar**: entrega el comprobante citado al cliente (revisa si ya se entregó, valida con IA si cuadra el monto/cuenta y manda confirmación + sticker).
- **recordarFoto**: guarda en Redis la última foto suelta de la operadora por si luego cita con un punto.
- **verificar**: la operadora citó una cuenta para "verificar/corregir datos"; marca la operación y le pide los datos corregidos al cliente.

Se mantiene inactivo hasta que Kelvin lo publique manualmente en n8n.
'@
      height = 320
      width = 520
      color = 4
    }
    id = 'op110000-0000-4a00-9a00-opnota000001'
    name = 'Nota'
    type = 'n8n-nodes-base.stickyNote'
    typeVersion = 1
    position = @(
      -1500,
      -1100
    )
  },
  [ordered]@{
    parameters = [ordered]@{
      inputSource = 'passthrough'
    }
    id = 'op110000-0001-4a00-9a00-optrig000001'
    name = 'Cuando lo Llama el Bot'
    type = 'n8n-nodes-base.executeWorkflowTrigger'
    typeVersion = 1.1
    position = @(
      -1500,
      -700
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
                  id = 'op-entregar'
                  leftValue = '={{ $json.accionPausa }}'
                  rightValue = 'entregar'
                  operator = [ordered]@{
                    operation = 'equals'
                    type = 'string'
                  }
                }
              )
              combinator = 'and'
            }
            renameOutput = $true
            outputKey = 'entregar'
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
                  id = 'op-recfoto'
                  leftValue = '={{ $json.accionPausa }}'
                  rightValue = 'recordarFoto'
                  operator = [ordered]@{
                    operation = 'equals'
                    type = 'string'
                  }
                }
              )
              combinator = 'and'
            }
            renameOutput = $true
            outputKey = 'recordarFoto'
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
                  id = 'op-verificar'
                  leftValue = '={{ $json.accionPausa }}'
                  rightValue = 'verificar'
                  operator = [ordered]@{
                    operation = 'equals'
                    type = 'string'
                  }
                }
              )
              combinator = 'and'
            }
            renameOutput = $true
            outputKey = 'verificar'
          }
        )
      }
    }
    id = 'op110000-0002-4a00-9a00-opswitch0001'
    name = 'Router Operadoras'
    type = 'n8n-nodes-base.switch'
    typeVersion = 3.2
    position = @(
      -1300,
      -700
    )
  },
  [ordered]@{
    parameters = [ordered]@{
      value = '={{ $json.idFoto }}'
      expire = $true
      ttl = 600
      keyType = 'string'
      key = '={{ $json.claveFoto }}'
      operation = 'set'
    }
    id = 'd0e1f2a3-0000-4b00-9000-guardafoto001'
    name = 'Redis Guardar Ultima Foto'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      60,
      -660
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
      operation = 'get'
      key = '={{ $(''Cuando lo Llama el Bot'').first().json.claveFoto }}'
      propertyName = 'ultimaFoto'
      keyType = 'string'
      options = @{}
    }
    id = 'd0e1f2a3-0000-4b00-9000-leerfoto00001'
    name = 'Redis Leer Ultima Foto'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      300,
      -500
    )
    onError = 'continueRegularOutput'
    alwaysOutputData = $true
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  },
  [ordered]@{
    parameters = [ordered]@{
      conditions = [ordered]@{
        boolean = @(
          ,[ordered]@{
            value2 = '={{true}}'
            value1 = '={{ $json.accion === ''repetido'' }}'
          }
        )
      }
    }
    id = 'd0e1f2a3-0000-4b00-9000-esrepetido001'
    name = 'Ya Se Entrego?'
    type = 'n8n-nodes-base.if'
    typeVersion = 1
    position = @(
      460,
      -420
    )
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
      jsonBody = '={{ JSON.stringify({ number: $json.jidGrupo, text: ("OJO: " + $json.aviso), quoted: { key: { id: $json.stanzaId } } }) }}'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'd0e1f2a3-0000-4b00-9000-avisarepeti01'
    name = 'Avisar Repetido'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      620,
      -360
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
      conditions = [ordered]@{
        boolean = @(
          ,[ordered]@{
            value2 = '={{true}}'
            value1 = '={{ !!$json.error }}'
          }
        )
      }
    }
    id = 'd0e1f2a3-0000-4b00-9000-fallocita0001'
    name = 'Fallo la Cita?'
    type = 'n8n-nodes-base.if'
    typeVersion = 1
    position = @(
      860,
      -560
    )
  },
  [ordered]@{
    parameters = [ordered]@{
      specifyBody = 'json'
      url = 'http://evolution-api:8080/message/sendMedia/BOT%20JK%20Kelvin'
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
      jsonBody = '={{ JSON.stringify({ number: $("Revisar Pedido").first().json.jid, mediatype: "image", mimetype: ($("Bajar Foto Operadora").first().json.mimetype || "image/jpeg"), media: $("Bajar Foto Operadora").first().json.base64 }) }}'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'd0e1f2a3-0000-4b00-9000-envsincita001'
    name = 'Enviar Comprobante sin Cita'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      1020,
      -620
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 3
    waitBetweenTries = 1500
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
      conditions = [ordered]@{
        boolean = @(
          ,[ordered]@{
            value2 = '={{true}}'
            value1 = '={{ !!$json.error }}'
          }
        )
      }
    }
    id = 'd0e1f2a3-0000-4b00-9000-fallocitag001'
    name = 'Fallo la Cita del Grupo?'
    type = 'n8n-nodes-base.if'
    typeVersion = 1
    position = @(
      1340,
      -500
    )
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
      jsonBody = '={{ JSON.stringify({ number: $("Revisar Pedido").first().json.jidGrupo, text: ("Enviado a " + $("Revisar Pedido").first().json.nombre + " OK") }) }}'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'd0e1f2a3-0000-4b00-9000-confsincita01'
    name = 'Confirmar sin Cita'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      1500,
      -560
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
      operation = 'get'
      key = '={{ $json.claveGrupoMsg }}'
      propertyName = 'pedido'
      keyType = 'string'
      options = @{}
    }
    id = 'd0e1f2a3-0000-4b00-9000-leerpublic001'
    name = 'Redis Leer Publicacion'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      60,
      -500
    )
    onError = 'continueRegularOutput'
    alwaysOutputData = $true
    credentials = [ordered]@{
      redis = [ordered]@{
        id = 'SKkvpS5A65SOcmJs'
        name = 'Redis memoria para Cambios JK'
      }
    }
  },
  [ordered]@{
    parameters = [ordered]@{
      operation = 'get'
      key = '={{ $(''Cuando lo Llama el Bot'').first().json.claveEntregado }}'
      propertyName = 'entregado'
      keyType = 'string'
      options = @{}
    }
    id = 'd0e1f2a3-0000-4b00-9000-leerentreg001'
    name = 'Redis Leer Entregado'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      220,
      -500
    )
    onError = 'continueRegularOutput'
    alwaysOutputData = $true
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
// La operadora respondio una publicacion del grupo. Aqui se decide que hacer.
//
// Se entrega SOLO si el mensaje que cito es una publicacion que hizo el bot: esa es toda la
// autorizacion. Si cito cualquier otra cosa, no hay nada guardado y no pasa nada, en silencio.
const base = $('Cuando lo Llama el Bot').first().json;

let crudo = '';
try { crudo = $('Redis Leer Publicacion').first().json.pedido || ''; } catch(e){}
if (!crudo) return [];               // no es una publicacion del bot

let p = null;
try { p = (typeof crudo === 'string') ? JSON.parse(crudo) : crudo; } catch(e){}
if (!p || !p.jid) return [];

// Si citaron el AVISO de "este comprobante NO cuadra" (Fase B), ese aviso trae la publicacion original:
// la entrega, el "Enviado a ... OK" y la fila de Supabase son los de esa publicacion.
const publicacion = String(p.publicacion || base.stanzaId || '');
const comun = {
  jid: p.jid,
  nombre: p.nombre || 'el cliente',
  idCuenta: p.idCuenta || '',        // para citarle el mensaje donde dio sus datos bancarios
  idCaptura: p.idCaptura || '',      // la captura del deposito: con ella se buscan sus cuentas en Supabase
  stanzaId: publicacion,             // la publicacion citada, para citarla al confirmar
  claveEntregado: p.publicacion ? ('entregado:' + publicacion) : base.claveEntregado,
  jidGrupo: base.jidGrupo,
  // "forzar" solo vale respondiendo el aviso: ahi la operadora ya vio que no cuadraba.
  forzar: !!(base.forzar && p.publicacion)
};

// Ya se le mando? No se repite, pero ahora SI se avisa: antes se quedaba callado y la
// operadora no sabia si habia salido o no.
let yaSeEntrego = '';
try { yaSeEntrego = $('Redis Leer Entregado').first().json.entregado || ''; } catch(e){}
if (yaSeEntrego){
  return [{ json: Object.assign({}, comun, { accion: 'repetido',
    aviso: 'Este comprobante ya se le envio a ' + comun.nombre + '. No hace falta mandarlo de nuevo.' }) }];
}

// Que foto se manda: la del propio mensaje si la operadora cito CON la foto, o la ultima
// que mando suelta si cito con un punto.
let idFoto = String(base.idFoto || '');
if (!idFoto && p.idFotoOperadora) idFoto = String(p.idFotoOperadora);   // "forzar": la misma foto que no cuadraba
if (!idFoto){
  try { idFoto = String($('Redis Leer Ultima Foto').first().json.ultimaFoto || ''); } catch(e){}
}
if (!idFoto) return [];              // cito con texto pero no hay ninguna foto suya reciente

return [{ json: Object.assign({}, comun, { accion: 'entregar', idFoto }) }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      380,
      -500
    )
    id = 'd0e1f2a3-0000-4b00-9000-revisarped001'
    name = 'Revisar Pedido'
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
      jsonBody = '={ "message": { "key": { "id": "{{ $json.idFoto }}" } }, "convertToMp4": false }'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'd0e1f2a3-0000-4b00-9000-bajarfoto0001'
    name = 'Bajar Foto Operadora'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      540,
      -500
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 3
    waitBetweenTries = 1500
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
      592,
      -752
    )
    id = 'a1b2c3d4-0013-4e00-9a00-faseb0000013'
    name = 'Foto Operadora a Binario'
    onError = 'continueRegularOutput'
  },
  [ordered]@{
    parameters = [ordered]@{
      text = 'Esta imagen es el comprobante de una transferencia que hizo una casa de cambio HACIA un beneficiario (transferencia bancaria, pago movil, Zelle, Binance, Nequi, etc.). Lee SOLO los datos del DESTINO (quien RECIBE el dinero), nunca los de quien envia. Responde SOLO JSON valido, sin texto extra: {"es_comprobante": true|false, "cuenta_destino": "numero de cuenta o telefono del destino tal como aparece (con asteriscos si esta oculto)", "cedula_destino": "", "titular_destino": "nombre de quien recibe", "banco_destino": "", "correo_destino": "", "billetera_destino": "", "monto": "", "moneda": "", "referencia": ""}. Si un dato no aparece, dejalo vacio. No inventes nada. es_comprobante = false si no es un comprobante de pago (por ejemplo, una foto de dinero en efectivo o de una persona).'
      inputType = 'base64'
      modelId = [ordered]@{
        mode = 'list'
        __rl = $true
        cachedResultName = 'gpt-4o'
        value = 'gpt-4o'
      }
      resource = 'image'
      options = @{}
      operation = 'analyze'
      binaryPropertyName = 'data'
    }
    id = 'a1b2c3d4-0014-4e00-9a00-faseb0000014'
    name = 'Leer Comprobante Operadora'
    type = '@n8n/n8n-nodes-langchain.openAi'
    typeVersion = 1.8
    position = @(
      768,
      -752
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
      tableId = 'transacciones_detal_por_whatsapp'
      limit = 20
      filterString = '={{ ''id_msg_captura=eq.'' + ($(''Revisar Pedido'').first().json.idCaptura || ''sin-dato'') }}'
      resource = 'row'
      filterType = 'string'
      operation = 'getAll'
      returnAll = $false
    }
    id = 'a1b2c3d4-0015-4e00-9a00-faseb0000015'
    name = 'Leer Cuentas de la Operacion'
    type = 'n8n-nodes-base.supabase'
    typeVersion = 1
    position = @(
      944,
      -752
    )
    onError = 'continueRegularOutput'
    alwaysOutputData = $true
    credentials = [ordered]@{
      supabaseApi = [ordered]@{
        id = 'JCvvp9JkZ15OpA9E'
        name = 'Supabase Cambios JK'
      }
    }
  },
  [ordered]@{
    parameters = [ordered]@{
      jsCode = @'
// ===== FASE B: ¿EL COMPROBANTE DE LA OPERADORA CUADRA CON LA CUENTA DEL CLIENTE? =====
// Antes de mandarle al cliente la foto que devolvio la operadora, se lee (GPT-4o, "Leer Comprobante
// Operadora") y se compara con la cuenta destino de ESA publicacion: numero de cuenta o telefono,
// cedula, correo, billetera y titular. Lo que se quiere atrapar es el error grave: mandarle a un
// cliente el comprobante de otro, por citar la publicacion equivocada.
//   - algun dato coincide                  -> se entrega
//   - los datos se contradicen             -> NO se entrega y se avisa en el grupo
//   - no se pudo leer o no hay que comparar -> se entrega, como antes (una foto borrosa o una foto
//                                             de una entrega en efectivo no frena la entrega)
//   - la operadora respondio el aviso con "forzar" -> se entrega igual
// El monto NO se compara: la cuenta suele estar en dolares y el comprobante en bolivares o pesos.
const ped = $('Revisar Pedido').first().json || {};

let leido = {};
try {
  const r = $('Leer Comprobante Operadora').first().json || {};
  const t = String(r.content || r.text || '').replace(/```json/gi, '').replace(/```/g, '').trim();
  const a = t.indexOf('{'), z = t.lastIndexOf('}');
  if (a !== -1 && z > a) leido = JSON.parse(t.slice(a, z + 1)) || {};
} catch(e){ leido = {}; }
if (!leido || typeof leido !== 'object') leido = {};

let filas = [];
try { filas = $('Leer Cuentas de la Operacion').all().map(i => i.json).filter(r => r && r.id && !r.error); } catch(e){ filas = []; }
const listaDe = v => { if (Array.isArray(v)) return v; try { const x = JSON.parse(v); return Array.isArray(x) ? x : []; } catch(e){ return []; } };
const cuentaDe = r => (r ? (listaDe(r.cuentas)[0] || {}) : {});

// ---------- comparar ----------
const COMUNES = new Set(['banco', 'bank', 'cuenta', 'cta', 'ahorro', 'ahorros', 'corriente', 'cedula', 'titular', 'nombre', 'pago',
  'movil', 'telefono', 'numero', 'nro', 'monto', 'usd', 'dolares', 'dolar', 'bolivares', 'pesos', 'soles', 'transferencia', 'cliente',
  'venezuela', 'venezolano', 'colombia', 'ecuador', 'peru', 'panama', 'chile', 'mexico', 'zelle', 'binance', 'nequi', 'daviplata',
  'bancolombia', 'davivienda', 'pichincha', 'guayaquil', 'produbanco', 'pacifico', 'bolivariano', 'internacional', 'austro', 'machala',
  'banesco', 'mercantil', 'provincial', 'bdv', 'bicentenario', 'bancamiga', 'bnc', 'exterior', 'tesoro', 'sofitasa', 'plaza',
  'activo', 'banplus', 'caroni', 'banfanb', 'venezolana', 'interbank', 'bcp', 'scotiabank', 'yape', 'plin', 'nacional', 'credito',
  'universal', 'digital', 'coop', 'cooperativa', 'mutualista', 'jep', 'jardin', 'azuayo', 'julio', 'del', 'los', 'las', 'para',
  'con', 'por', 'que', 'una', 'uno', 'mas', 'favor', 'porfa', 'gracias', 'hola', 'buenas', 'enviar', 'envio', 'recibe']);
const norm = x => String(x || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const palabras = x => norm(x).replace(/[^a-z]+/g, ' ').split(' ').filter(w => w.length >= 3 && !COMUNES.has(w));
const juntar = x => String(x || '').replace(/([0-9])[ .\-]+(?=[0-9])/g, '$1');
const numerosCliente = t => (juntar(t).match(/[0-9]{6,}/g) || []);           // cuenta, telefono, cedula
const gruposComprobante = t => (juntar(t).match(/[0-9]{4,}/g) || []);         // lo que se ve (puede venir con ****)
function coinciden(visto, delCliente){
  const k = Math.min(6, visto.length, delCliente.length);
  return k >= 4 && visto.slice(-k) === delCliente.slice(-k);
}
// 'si' = coincide, 'no' = se contradice, 'nose' = no hay como comparar
function evaluar(fila){
  const texto = String(cuentaDe(fila).texto || '');
  const nums = numerosCliente(texto);
  const grupos = gruposComprobante(leido.cuenta_destino).concat(gruposComprobante(leido.cedula_destino));
  const numeros = (grupos.length && nums.length) ? (grupos.some(g => nums.some(n => coinciden(g, n))) ? 'si' : 'no') : 'nose';
  const correoVisto = (norm(leido.correo_destino).match(/[^\s@]+@[^\s@]+\.[a-z]{2,}/) || [])[0];
  const correos = norm(texto).match(/[^\s@]+@[^\s@]+\.[a-z]{2,}/g) || [];
  const correo = (correoVisto && correos.length) ? (correos.indexOf(correoVisto) !== -1 ? 'si' : 'no') : 'nose';
  const bill = String(leido.billetera_destino || '').replace(/\s+/g, '').toLowerCase();
  const tokens = (texto.match(/[A-Za-z0-9]{20,}/g) || []).map(x => x.toLowerCase());
  const billetera = (bill.length >= 20 && tokens.length) ? (tokens.some(x => x.slice(-6) === bill.slice(-6)) ? 'si' : 'no') : 'nose';
  const pv = palabras(leido.titular_destino), pc = palabras(texto);
  const nombre = (pv.length && pc.length) ? (pv.some(w => pc.indexOf(w) !== -1) ? 'si' : 'no') : 'nose';
  const datos = [numeros, correo, billetera];
  // Los numeros, el correo o la billetera mandan; el nombre solo decide si no hay ninguno que comparar.
  const resultado = datos.indexOf('si') !== -1 ? 'si' : (datos.indexOf('no') !== -1 ? 'no' : nombre);
  return { resultado, numeros, correo, billetera, nombre };
}

// ---------- con que cuenta se compara ----------
// La publicacion citada es una cuenta (primer id de su fila) o la foto de la captura (va con la primera
// cuenta). Si es la foto, o la foto de la operadora coincide con OTRA cuenta del mismo deposito, se
// usa esa: es el mismo cliente, y asi se marca enviada la cuenta correcta.
const citada = filas.find(r => listaDe(r.id_msgs_grupo)[0] === ped.stanzaId) || null;
const pendientes = filas.filter(r => r.estado !== 'enviada' && r.estado !== 'cancelada');
const orden = [];
for (const r of [].concat(citada ? [citada] : [], pendientes, filas)) if (orden.indexOf(r) === -1) orden.push(r);
const evals = new Map(orden.map(r => [r, evaluar(r)]));
const sePuedeLeer = leido.es_comprobante !== false && Object.keys(leido).length > 0;

let elegida = null, cuadra = true, verificado = false, motivo = '';
const coincide = sePuedeLeer ? orden.find(r => evals.get(r).resultado === 'si') : null;
if (ped.forzar){
  elegida = coincide || citada || pendientes[0] || null;
  motivo = 'forzado desde el grupo';
} else if (coincide){
  elegida = coincide; verificado = true;
  const e = evals.get(coincide);
  motivo = 'coincide: ' + ['numeros', 'correo', 'billetera', 'nombre'].filter(k => e[k] === 'si').join(', ');
} else {
  const base = citada || pendientes[0] || filas[0] || null;
  const contradice = sePuedeLeer && (citada ? evals.get(citada).resultado === 'no'
                                            : (orden.length > 0 && orden.every(r => evals.get(r).resultado === 'no')));
  elegida = base;
  if (contradice){ cuadra = false; motivo = 'los datos del comprobante no son los de la cuenta'; }
  else motivo = sePuedeLeer ? 'no hay datos para comparar' : 'no se pudo leer (o no es un comprobante)';
}

let aviso = '';
if (!cuadra){
  const vio = [leido.cuenta_destino && ('cuenta/tel ' + leido.cuenta_destino), leido.cedula_destino && ('cédula ' + leido.cedula_destino),
               leido.correo_destino, leido.billetera_destino, leido.titular_destino && ('titular ' + leido.titular_destino), leido.banco_destino]
              .filter(Boolean).join(' · ');
  const delCliente = String(cuentaDe(elegida).texto || '').split('\n').map(l => l.trim()).filter(Boolean).join(' · ');
  aviso = '⚠️ *Ojo: este comprobante NO cuadra con la cuenta de ' + (ped.nombre || 'el cliente') + '*\n\n'
    + 'El comprobante dice: ' + (vio || '(no se leyó bien)') + '\n'
    + 'La cuenta del cliente: ' + (delCliente || '(no la tengo)') + '\n\n'
    + 'NO se le mandó al cliente. Si te equivocaste de foto, responde la cuenta con la foto correcta. '
    + 'Si está bien así, responde a ESTE mensaje con la palabra *forzar* y se la mando.';
}

return [{ json: { cuadra, verificado, motivo, filaId: elegida ? elegida.id : null,
                  idCuenta: (elegida && cuentaDe(elegida).id) || ped.idCuenta || '', leido, aviso } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      1120,
      -752
    )
    id = 'a1b2c3d4-0016-4e00-9a00-faseb0000016'
    name = 'Revisar Comprobante'
    onError = 'continueRegularOutput'
  },
  [ordered]@{
    parameters = [ordered]@{
      conditions = [ordered]@{
        boolean = @(
          ,[ordered]@{
            value2 = '={{true}}'
            value1 = '={{ $json.cuadra !== false }}'
          }
        )
      }
    }
    id = 'a1b2c3d4-0017-4e00-9a00-faseb0000017'
    name = '¿Cuadra el Comprobante?'
    type = 'n8n-nodes-base.if'
    typeVersion = 1
    position = @(
      1296,
      -752
    )
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
      jsonBody = '={{ JSON.stringify({ number: $("Revisar Pedido").first().json.jidGrupo, text: $json.aviso, quoted: { key: { id: $("Revisar Pedido").first().json.idFoto } } }) }}'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'a1b2c3d4-0018-4e00-9a00-faseb0000018'
    name = 'Avisar Comprobante No Cuadra'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      1472,
      -592
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
      value = '={{ JSON.stringify({ jid: $(''Revisar Pedido'').first().json.jid, nombre: $(''Revisar Pedido'').first().json.nombre, idCuenta: $(''Revisar Pedido'').first().json.idCuenta, idCaptura: $(''Revisar Pedido'').first().json.idCaptura, publicacion: $(''Revisar Pedido'').first().json.stanzaId, idFotoOperadora: $(''Revisar Pedido'').first().json.idFoto }) }}'
      expire = $true
      ttl = 172800
      keyType = 'string'
      key = '={{ ''grupoMsg:'' + (($json.key && $json.key.id) || ($json.data && $json.data.key && $json.data.key.id) || ''nada'') }}'
      operation = 'set'
    }
    id = 'a1b2c3d4-0019-4e00-9a00-faseb0000019'
    name = 'Marcar Aviso No Cuadra'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      1648,
      -592
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
      jsonBody = '={{ JSON.stringify(Object.assign({ number: $("Revisar Pedido").first().json.jid, mediatype: "image", mimetype: ($("Bajar Foto Operadora").first().json.mimetype || "image/jpeg"), media: $("Bajar Foto Operadora").first().json.base64 }, $("Revisar Comprobante").first().json.idCuenta ? { quoted: { key: { id: $("Revisar Comprobante").first().json.idCuenta } } } : {})) }}'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'd0e1f2a3-0000-4b00-9000-enviarcompr01'
    name = 'Enviar Comprobante al Cliente'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      700,
      -500
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 3
    waitBetweenTries = 1500
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
      jsonBody = '={ "number": "{{ $("Revisar Pedido").first().json.jid }}", "sticker": "https://grupojk-cambios.github.io/grupojk-conversor/logos/sticker-pedido-pagado.webp" }'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'd0e1f2a3-0000-4b00-9000-stickpagado01'
    name = 'Sticker Pedido Pagado'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      860,
      -500
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
      jsonBody = '={{ JSON.stringify({ number: $("Revisar Pedido").first().json.jidGrupo, text: ("Enviado a " + $("Revisar Pedido").first().json.nombre + " OK"), quoted: { key: { id: $("Revisar Pedido").first().json.stanzaId } } }) }}'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'd0e1f2a3-0000-4b00-9000-confirmgrup01'
    name = 'Confirmar en el Grupo'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      1020,
      -500
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
      value = '1'
      expire = $true
      ttl = 172800
      keyType = 'string'
      key = '={{ $(''Revisar Pedido'').first().json.claveEntregado }}'
      operation = 'set'
    }
    id = 'd0e1f2a3-0000-4b00-9000-marcaentreg01'
    name = 'Redis Marcar Entregado'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      1180,
      -500
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
      tableId = 'transacciones_detal_por_whatsapp'
      fieldsUi = [ordered]@{
        fieldValues = @(
          [ordered]@{
            fieldId = 'estado'
            fieldValue = 'enviada'
          },
          [ordered]@{
            fieldId = 'enviada_en'
            fieldValue = '={{ $now.toISO() }}'
          }
        )
      }
      filterString = '={{ ($(''Revisar Comprobante'').first().json.filaId ? ''id=eq.'' + $(''Revisar Comprobante'').first().json.filaId : ''id_msgs_grupo=cs.'' + JSON.stringify([ $(''Revisar Pedido'').first().json.stanzaId || ''sin-dato'' ])) + ''&estado=in.(en_proceso,en_espera)'' }}'
      resource = 'row'
      filterType = 'string'
      operation = 'update'
      dataToSend = 'defineBelow'
    }
    id = 'a1b2c3d4-0011-4e00-9a00-registro00011'
    name = 'Marcar Enviada en Supabase'
    type = 'n8n-nodes-base.supabase'
    typeVersion = 1
    position = @(
      1408,
      -752
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
      key = '={{ $json.claveGrupoMsg }}'
      propertyName = 'pedido'
      keyType = 'string'
      options = @{}
    }
    id = 'c9d0e1f2-0011-4a00-9c00-verificar011'
    name = 'Redis Leer Publicacion Verificar'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      -1104,
      -1408
    )
    onError = 'continueRegularOutput'
    alwaysOutputData = $true
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
// La operadora cito la publicacion de una cuenta con "Verificar datos" (o "corregir dato"...). Si lo citado
// es una publicacion del bot (esta en Redis: esa es la autorizacion), se arma el mensaje para el cliente
// con los datos que hay que revisar. Si no, no pasa nada.
const base = $('Cuando lo Llama el Bot').first().json;
let p = null;
try {
  const crudo = $('Redis Leer Publicacion Verificar').first().json.pedido;
  if (crudo) p = (typeof crudo === 'string') ? JSON.parse(crudo) : crudo;
} catch(e){ p = null; }
if (!p || !p.jid) return [];
// Si citaron una correccion, la publicacion "de verdad" es la original (ahi esta la fila de Supabase).
const publicacion = String(p.publicacion || base.stanzaId || '');
// Lo publicado es "Nombre - $10" + renglon vacio + los datos (o "✏️ DATOS CORREGIDOS" + eso mismo).
const t = String(base.citadoTexto || '').replace(/^✏️ DATOS CORREGIDOS[^\n]*\n/, '');
const corte = t.indexOf('\n\n');
const cabecera = (corte === -1 ? '' : t.slice(0, corte)).trim();
const datos = (corte === -1 ? t : t.slice(corte + 2)).trim();
if (!datos) return [];
const nombre = String(p.nombre || 'el cliente');
const nota = String(base.nota || '').replace(/\s+/g, ' ').trim();
const mensaje = 'Disculpa 🙏 Nos indican: *' + nota + '*\n\n' + datos + '\n\nPor favor revisa estos datos, corrígelos y envíamelos de nuevo.';
return [{ json: { jid: String(p.jid), nombre, publicacion, idCaptura: String(p.idCaptura || ''), cabecera: cabecera || nombre,
                  datos, nota, mensaje, idNota: String(base.idNota || ''), jidGrupo: String(base.jidGrupo || ''),
                  confirmacion: 'Listo, le pedí a ' + nombre + ' que verifique y corrija los datos ✅' } }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      -928,
      -1408
    )
    id = 'c9d0e1f2-0012-4a00-9c00-verificar012'
    name = 'Preparar Corregir Datos'
  },
  [ordered]@{
    parameters = [ordered]@{
      operation = 'get'
      key = '={{ "op:" + $json.jid }}'
      propertyName = 'operacion'
      keyType = 'string'
      options = @{}
    }
    id = 'c9d0e1f2-0013-4a00-9c00-verificar013'
    name = 'Redis Leer Op Corregir'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      -752,
      -1408
    )
    onError = 'continueRegularOutput'
    alwaysOutputData = $true
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
// Se anota en la operacion del cliente (op:<chat>) que la operadora pidio corregir esa cuenta. Cuando el
// cliente mande los datos corregidos, "Revisar Operacion" los vuelve a pasar a transferir (ver "corregir").
const v = $('Preparar Corregir Datos').first().json;
let op = {};
try {
  const raw = $('Redis Leer Op Corregir').first().json.operacion;
  if (raw) op = (typeof raw === 'string') ? JSON.parse(raw) : raw;
} catch(e){ op = {}; }
if (!op || typeof op !== 'object' || Array.isArray(op)) op = {};
op.corregir = { ts: Date.now(), publicacion: v.publicacion, nombre: v.nombre, cabecera: v.cabecera, idCaptura: v.idCaptura,
                nota: v.nota, datos: String(v.datos || '').slice(0, 1500) };
return [{ json: Object.assign({}, v, { operacionNueva: JSON.stringify(op) }) }];
'@
    }
    type = 'n8n-nodes-base.code'
    typeVersion = 2
    position = @(
      -576,
      -1408
    )
    id = 'c9d0e1f2-0014-4a00-9c00-verificar014'
    name = 'Marcar Corregir Datos'
  },
  [ordered]@{
    parameters = [ordered]@{
      value = '={{ $json.operacionNueva }}'
      expire = $true
      ttl = 172800
      keyType = 'string'
      key = '={{ "op:" + $json.jid }}'
      operation = 'set'
    }
    id = 'c9d0e1f2-0015-4a00-9c00-verificar015'
    name = 'Redis Guardar Op Corregir'
    type = 'n8n-nodes-base.redis'
    typeVersion = 1
    position = @(
      -400,
      -1408
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
      instanceName = 'BOT JK Kelvin'
      messageText = '={{ $("Preparar Corregir Datos").first().json.mensaje }}'
      options_message = @{}
      resource = 'messages-api'
      remoteJid = '={{ $("Preparar Corregir Datos").first().json.jid }}'
    }
    id = 'c9d0e1f2-0016-4a00-9c00-verificar016'
    name = 'Pedir Corregir al Cliente'
    type = 'n8n-nodes-evolution-api.evolutionApi'
    typeVersion = 1
    position = @(
      -224,
      -1408
    )
    retryOnFail = $true
    maxTries = 3
    waitBetweenTries = 3000
    onError = 'continueRegularOutput'
    credentials = [ordered]@{
      evolutionApi = [ordered]@{
        id = 'iUIvc9Sd8diFJaGU'
        name = 'Evolution PARA n8n cambios JK'
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
      jsonBody = '={{ JSON.stringify({ number: $("Preparar Corregir Datos").first().json.jidGrupo, text: $("Preparar Corregir Datos").first().json.confirmacion, quoted: { key: { id: $("Preparar Corregir Datos").first().json.idNota } } }) }}'
      genericAuthType = 'httpHeaderAuth'
      authentication = 'genericCredentialType'
    }
    id = 'c9d0e1f2-0017-4a00-9c00-verificar017'
    name = 'Confirmar Verificar en Grupo'
    type = 'n8n-nodes-base.httpRequest'
    typeVersion = 4
    position = @(
      -48,
      -1408
    )
    onError = 'continueRegularOutput'
    retryOnFail = $true
    maxTries = 2
    waitBetweenTries = 1000
    credentials = [ordered]@{
      httpHeaderAuth = [ordered]@{
        id = '70cMtifwmTdIqY1l'
        name = 'Evolution apikey Kelvin 0380'
      }
    }
  }
)

$connections = [ordered]@{
  'Cuando lo Llama el Bot' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Router Operadoras'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Router Operadoras' = [ordered]@{
    main = @(
      @(
        ,[ordered]@{
          node = 'Redis Leer Publicacion'
          type = 'main'
          index = 0
        }
      ),
      @(
        ,[ordered]@{
          node = 'Redis Guardar Ultima Foto'
          type = 'main'
          index = 0
        }
      ),
      @(
        ,[ordered]@{
          node = 'Redis Leer Publicacion Verificar'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Leer Publicacion' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Leer Entregado'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Leer Entregado' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Leer Ultima Foto'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Leer Ultima Foto' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Revisar Pedido'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Revisar Pedido' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Ya Se Entrego?'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Ya Se Entrego?' = [ordered]@{
    main = @(
      @(
        ,[ordered]@{
          node = 'Avisar Repetido'
          type = 'main'
          index = 0
        }
      ),
      @(
        ,[ordered]@{
          node = 'Bajar Foto Operadora'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Bajar Foto Operadora' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Foto Operadora a Binario'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Foto Operadora a Binario' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Leer Comprobante Operadora'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Leer Comprobante Operadora' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Leer Cuentas de la Operacion'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Leer Cuentas de la Operacion' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Revisar Comprobante'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Revisar Comprobante' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = '¿Cuadra el Comprobante?'
          type = 'main'
          index = 0
        }
      )
    )
  }
  '¿Cuadra el Comprobante?' = [ordered]@{
    main = @(
      @(
        ,[ordered]@{
          node = 'Enviar Comprobante al Cliente'
          type = 'main'
          index = 0
        }
      ),
      @(
        ,[ordered]@{
          node = 'Avisar Comprobante No Cuadra'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Avisar Comprobante No Cuadra' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Marcar Aviso No Cuadra'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Enviar Comprobante al Cliente' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Fallo la Cita?'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Fallo la Cita?' = [ordered]@{
    main = @(
      @(
        ,[ordered]@{
          node = 'Enviar Comprobante sin Cita'
          type = 'main'
          index = 0
        }
      ),
      @(
        ,[ordered]@{
          node = 'Sticker Pedido Pagado'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Enviar Comprobante sin Cita' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Sticker Pedido Pagado'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Sticker Pedido Pagado' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Confirmar en el Grupo'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Confirmar en el Grupo' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Fallo la Cita del Grupo?'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Fallo la Cita del Grupo?' = [ordered]@{
    main = @(
      @(
        ,[ordered]@{
          node = 'Confirmar sin Cita'
          type = 'main'
          index = 0
        }
      ),
      @(
        ,[ordered]@{
          node = 'Redis Marcar Entregado'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Confirmar sin Cita' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Marcar Entregado'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Leer Publicacion Verificar' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Preparar Corregir Datos'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Preparar Corregir Datos' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Leer Op Corregir'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Leer Op Corregir' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Marcar Corregir Datos'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Marcar Corregir Datos' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Redis Guardar Op Corregir'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Guardar Op Corregir' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Pedir Corregir al Cliente'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Pedir Corregir al Cliente' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Confirmar Verificar en Grupo'
          type = 'main'
          index = 0
        }
      )
    )
  }
  'Redis Marcar Entregado' = [ordered]@{
    main = @(
      ,@(
        ,[ordered]@{
          node = 'Marcar Enviada en Supabase'
          type = 'main'
          index = 0
        }
      )
    )
  }
}

$wf = [ordered]@{
  name = 'Bot JK - Grupos de Operadoras'
  nodes = $nodes
  connections = $connections
  settings = [ordered]@{ executionOrder = 'v1'; timezone = 'America/Guayaquil' }
}
$salida = Join-Path $PSScriptRoot 'workflow_operadoras.json'
$json = $wf | ConvertTo-Json -Depth 40
[System.IO.File]::WriteAllText($salida, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('JSON generado: ' + $salida + ' | nodos: ' + $nodes.Count)
