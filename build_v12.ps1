$ErrorActionPreference = "Stop"

# ============================================================================
#   DE QUE NUMERO DE WHATSAPP SALE EL BOT  (instancia de Evolution)
# ============================================================================
#  Hoy: "BOT JK Kelvin"  (593961230380, el numero de Kelvin)
#  Antes: "bot-JK-prueba-operador1"
#
#  Para moverlo a otra instancia hay que tocar TRES cosas juntas. Si se cambia
#  una sola, el bot recibe por un lado y responde por otro, o Evolution rechaza
#  todo con error de credencial:
#
#   1. Las 6 URLs http://evolution-api:8080/.../<INSTANCIA>
#      OJO: aca el nombre va CODIFICADO, los espacios como %20.
#   2. Los 2 nodos de Evolution (parametro instanceName), con el nombre normal.
#   3. La credencial httpHeaderAuth de esas 6 URLs: cada instancia tiene SU
#      propia apikey, la de otra instancia no sirve.
#      Hoy: 'Evolution apikey Kelvin 0380'
#
#  Y aparte, en el panel de Evolution, la instancia nueva necesita el webhook
#  prendido apuntando a:
#      https://cambios-jk-remesas-n8n.wh5rmr.easypanel.host/webhook/webhook-whatsapp
#  con el evento MESSAGES_UPSERT, y el de la instancia vieja apagado.
# ============================================================================

# ============================================================================
#   SOLO RESPONDERLE A ESTOS NUMEROS   (modo pruebas)
# ============================================================================
#  VACIA  -> el bot le responde A TODO EL MUNDO. Asi es como trabaja normalmente.
#  CON NUMEROS -> el bot SOLO le responde a esos. A los demas NO les contesta nada.
#
#  Sirve para probar el bot sin que le caiga encima a un cliente real.
#  Los numeros van con codigo de pais y solo digitos, entre comillas simples.
#
#  Ejemplo para probar con un solo telefono:
#      $SOLO_ESTOS = @('593961230380')
#  Ejemplo con dos:
#      $SOLO_ESTOS = @('593961230380', '584121234567')
#
#  OJO: mientras la lista tenga algo, los clientes de verdad quedan sin respuesta.
#  Al terminar de probar hay que dejarla vacia -> $SOLO_ESTOS = @()
#  y volver a desplegar:  powershell -File scripts\desplegar_bot.ps1
# ============================================================================
$SOLO_ESTOS = @()

$SOLO_ESTOS_JS = "[" + (($SOLO_ESTOS | ForEach-Object { "'" + $_ + "'" }) -join ",") + "]"

# ============================================================================
#   SOLO ATENDER A CLIENTES CARGADOS   (interruptor)
# ============================================================================
#  $false -> el bot le contesta a todo el mundo. Es como trabaja hoy.
#  $true  -> el bot SOLO le contesta a los numeros cargados en Supabase, en las
#            tablas clientes_bot_detal y clientes_bot_mayor.
#
#  Los numeros se agregan y se quitan DESDE SUPABASE, sin volver a desplegar.
#  Este interruptor solo decide si la lista se respeta o no, y se deja en $false
#  mientras se cargan los clientes, para no dejar a nadie sin atender a medio
#  camino. Cuando ya estan todos cargados, se pone en $true y se despliega.
#
#  RED DE SEGURIDAD: aun con $true, si las tablas estan VACIAS o Supabase falla,
#  el bot le contesta a TODOS igual. Un problema de base de datos no puede dejar
#  al negocio sin atender.
# ============================================================================
$MODO_SOLO_CLIENTES = $true

# ============================================================================
#   NO CONTESTAR MENSAJES VIEJOS
# ============================================================================
#  Cada vez que la instancia de Evolution se reconecta despues de estar caida,
#  manda DE GOLPE todo lo que quedo pendiente. El 18/11 pasaron dos rafagas, de
#  70 y de 200 mensajes, con cosas escritas hasta 2 dias antes. Sin esto el bot
#  se pone a contestar conversaciones viejas y el cliente recibe una respuesta
#  de la nada sobre algo que pregunto anteayer.
#
#  Un mensaje con mas de estos minutos se ignora. En 0 se apaga el control.
# ============================================================================
$MINUTOS_MENSAJE_VIEJO = 20

# ============================================================================
#   PAUSA CUANDO KELVIN ATIENDE EL CHAT
# ============================================================================
#  El numero del bot es tambien el numero personal de Kelvin. Cuando el escribe
#  en una conversacion, el bot se calla AHI durante estos minutos, contados
#  desde su ULTIMO mensaje: mientras siga conversando, el bot no se mete.
#
#  Si el cliente pregunta algo durante la pausa, el bot NO le contesta pero
#  avisa al grupo, para que nadie quede sin atencion.
#
#  En el chat, Kelvin puede escribir:
#     "bot on"   -> el bot vuelve a atender ese chat de inmediato
#     "bot off"  -> el bot se calla ahi 12 horas
# ============================================================================
# Cuanto espera el bot a que lleguen mas mensajes antes de contestar. Con una OPERACION espera
# mas: la gente manda la foto del pago y la cuenta destino una tras otra, en cualquier orden, y
# tardan (el 19/11 una clienta tardo 36 segundos; el 20/11 otra, 14 minutos). Se espera lo mismo
# cuando llega primero la captura (foto + cuenta) que cuando llega primero la cuenta (cuenta +
# foto). Un mensaje normal sigue en 30 s.
$SEGUNDOS_ESPERA = 30
$SEGUNDOS_ESPERA_OPERACION = 100

$MINUTOS_PAUSA = 60
$HORAS_PAUSA_MANUAL = 12
$GRUPO_AVISOS = '120363413942097019@g.us'   # grupo "Notificaciones Clientes"

# Grupo donde las operadoras reciben el comprobante y la cuenta del cliente, hacen la
# transferencia y responden con la foto del envio. Estaba escrito a mano en dos nodos.
$GRUPO_OPERACIONES = '593961230380-1601657528@g.us'

# Cuanto recuerda el bot a que cliente pertenece cada publicacion del grupo. Pasado ese
# tiempo, responder un pedido viejo con una foto ya no hace nada.
$HORAS_MEMORIA_OPERACION = 48
$SEG_MEMORIA_OPERACION = $HORAS_MEMORIA_OPERACION * 3600

# Si la operadora manda la foto SUELTA y despues cita con un punto, el bot recuerda su
# ultima foto durante estos minutos. Corto a proposito: si mando varias seguidas, se usa
# la ultima.
$MINUTOS_RECORDAR_FOTO = 10

# Cuanto recuerda el bot una CUENTA que llego sin captura, o una CAPTURA que llego sin cuenta,
# esperando lo que falta. El 20/11 una clienta mando la cuenta y 14 minutos despues las capturas:
# el bot solo miraba los ultimos 30 segundos, le dijo "Listo, recibido!" y no paso nada al grupo.
$MINUTOS_OPERACION_PENDIENTE = 120

# Dos capturas con el MISMO monto en estos minutos, si a una no se le leyo la referencia, se toman
# como el mismo deposito (ej. dos pantallas distintas del mismo Zelle).
$MINUTOS_MISMO_DEPOSITO = 15

# "gracias" -> sticker A SU ORDEN, sin pasar por la IA. Como mucho uno cada tantos minutos por
# cliente: si escribe "gracias" tres veces seguidas no le llegan tres stickers.
$MINUTOS_ENTRE_STICKERS_GRACIAS = 10

# El nombre del cliente se usa UNA sola vez cada tantas horas, al saludar. Repetirlo en cada
# mensaje suena a bot (revision de los chats, 20/11).
$HORAS_ENTRE_NOMBRES = 24

# Registro en Supabase (tabla transacciones_detal_por_whatsapp): cuantas operaciones del cliente se leen
# en cada mensaje, y hasta cuantos dias atras cuenta la ultima para contestar "¿ya llego?".
$OPERACIONES_A_LEER = 20
$DIAS_ULTIMA_OPERACION = 7

# MAYOR, Fase 1: el workflow "Mayor: escuchar y registrar" (scripts\desplegar_mayor.ps1). El bot le pasa
# cada mensaje de los grupos de clientes que estan en la tabla grupos_mayor y NADA MAS: el bot no
# responde ni publica nada en esos grupos.
$MAYOR_WORKFLOW_ID = 'HIERZLV4lwtuBRbZ'

# FASE 1 (Operadoras): el workflow "Bot JK - Grupos de Operadoras" (scripts\desplegar_operadoras.ps1).
# Atiende entregas de comprobante, foto suelta y "verificar datos" del grupo de TRANSFERIR.
$OPERADORAS_WORKFLOW_ID = 'gav5txTYWq3ARV8H'

# FASE 2 (Publicar y Registrar): el workflow "Bot JK - Publicar y Registrar Operacion" (scripts\desplegar_operacion_publicar.ps1).
# Atiende aprobaciones (TRANSFERIR + Supabase), correcciones y guardado nocturno.
$OPERACION_PUBLICAR_WORKFLOW_ID = 'EVe1KsFiKhZtv4zK'

# FASE 3 (Media): el workflow "Bot JK - Procesar Media" (scripts\desplegar_media.ps1).
# Procesa audio (Whisper), imagen/comprobante (Vision + Redis Guardar Imagen) y texto directo -> { texto }.
$MEDIA_WORKFLOW_ID = 'UMQqyE6H4HVrIDoy'

# FASE 4 (Atencion al Cliente e IA): el workflow "Bot JK - Atencion al Cliente e IA" (scripts\desplegar_ia_atencion.ps1).
# Atiende consultas de tasas/cuentas, deteccion de operaciones/aprobaciones y AI Agent con Calculadora.
$IA_WORKFLOW_ID = 'OjALXRrfveeGpdtd'

# FASE 5 (Debounce y Admin): el workflow "Bot JK - Debounce y Admin" (scripts\desplegar_debounce_admin.ps1).
# Procesa Media, acumula mensajes en Redis (Wait 30s/100s), atiende comandos admin y delega a Atencion e IA.
$DEBOUNCE_ADMIN_WORKFLOW_ID = 'lUfmCp6cNHVcaVrh'

# ¿EL DEPOSITO CUADRA CON LAS CUENTAS? (pedido de Kelvin, 23/11). La suma de las cuentas tiene que dar
# EXACTO lo que dice la captura, en la misma moneda (tolerancia 0: "que sea exacta"). Si no cuadra, NO
# se pasa a transferir: se le pide al cliente que confirme. El workflow "Avisar deposito que no cuadra"
# (scripts\desplegar_vigilar_monto.ps1) le recuerda a los 5 minutos y avisa al grupo de avisos a los 10.
$MARGEN_CUADRE_USD = 0

# VERIFICAR DATOS (pedido de Kelvin, 23/11): cuando la operadora cita una cuenta con "Verificar datos",
# el bot le pide al cliente que la corrija; lo que el cliente mande con datos de cuenta en estas horas
# se toma como la correccion y se vuelve a pasar a transferir.
$HORAS_CORREGIR_DATOS = 12

# GOOGLE SHEETS LENTO (23/11): el bot lee las tasas y las cuentas del dia de la hoja de Google, y ese dia
# Google tardo 4 minutos en contestar: una clienta recibio su respuesta 5 minutos tarde. Ahora cada
# lectura espera como mucho $SEGUNDOS_MAX_GOOGLE segundos (2 intentos = unos 20 s en total) y, si Google no
# contesta, se usa la ULTIMA COPIA BUENA que el bot guardo en su memoria. La copia solo vale unas horas:
# una tasa vieja no se usa (mejor avisar que no se pudo cargar), una cuenta si aguanta mas.
$SEGUNDOS_MAX_GOOGLE = 10
$HORAS_RESPALDO_TASAS = 3
$HORAS_RESPALDO_CUENTAS = 24
$VIGILAR_MONTO_WORKFLOW_ID = '5GUqzdpeeJBttqgd'

# Horario de atencion (hora de Ecuador). Igual que el workflow de apertura y cierre: lunes a sabado
# de 9:00 a 18:00 y domingo de 10:00 a 14:00. Fuera de horario el bot atiende igual, pero una
# operacion completa (captura + cuenta) NO se pasa a transferir: queda 'en_espera' en Supabase y la
# publica el workflow "Liberar operaciones de la noche" al abrir (9:05; el domingo 10:05).
$HORA_ABRE_SEMANA = 9
$HORA_CIERRA_SEMANA = 18
$HORA_ABRE_DOMINGO = 10
$HORA_CIERRA_DOMINGO = 14

# Codigo del horario, compartido por "Prep Debounce" y "Revisar Operacion".
$horarioJs = @'
// ===== HORARIO DE ATENCION (hora de Ecuador: UTC-5, sin horario de verano) =====
// Lunes a sabado y domingo, como el workflow de apertura y cierre. Se cambia en build_v12.ps1
// ($HORA_ABRE_SEMANA y compania), nunca aqui.
const HORARIO_JK = { semana: [__ABRE_SEMANA__, __CIERRA_SEMANA__], domingo: [__ABRE_DOMINGO__, __CIERRA_DOMINGO__] };
function horarioDe(ms){
  const ec = new Date(ms - 5 * 3600000);
  const dow = ec.getUTCDay();
  const horas = ec.getUTCHours() + ec.getUTCMinutes() / 60;
  const rango = (dow === 0) ? HORARIO_JK.domingo : HORARIO_JK.semana;
  const abierto = horas >= rango[0] && horas < rango[1];
  const medianoche = ms - (((ec.getUTCHours() * 60 + ec.getUTCMinutes()) * 60 + ec.getUTCSeconds()) * 1000 + ec.getUTCMilliseconds());
  const esHoy = horas < rango[0];                      // de madrugada abre hoy; si ya cerro, manana
  const dowAbre = esHoy ? dow : (dow + 1) % 7;
  const horaAbre = (dowAbre === 0) ? HORARIO_JK.domingo[0] : HORARIO_JK.semana[0];
  const proximaApertura = medianoche + (esHoy ? 0 : 86400000) + horaAbre * 3600000;
  const DIAS = ['domingo', 'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado'];
  const conDia = (dowAbre === 0 || (!esHoy && dowAbre === 1)) ? ' ' + DIAS[dowAbre] : '';
  const hora = (horaAbre % 12 || 12) + ':00 ' + (horaAbre >= 12 ? 'pm' : 'am');
  return { abierto, proximaApertura, cuandoAbre: (esHoy ? 'hoy' : 'mañana') + conDia + ' a partir de las ' + hora };
}
'@
$horarioJs = $horarioJs.Replace('__ABRE_SEMANA__', [string]$HORA_ABRE_SEMANA).Replace('__CIERRA_SEMANA__', [string]$HORA_CIERRA_SEMANA)
$horarioJs = $horarioJs.Replace('__ABRE_DOMINGO__', [string]$HORA_ABRE_DOMINGO).Replace('__CIERRA_DOMINGO__', [string]$HORA_CIERRA_DOMINGO)

# Cada cuantos minutos, como MUCHO, se avisa de un mismo chat en pausa. Sin esto, un cliente
# que escribe seis veces seguidas genera seis avisos y el grupo se vuelve ruido.
$MINUTOS_ENTRE_AVISOS = 15

# Solo se avisa si el mensaje del cliente menciona algo del negocio. Si esta conversando de
# cosas personales con Kelvin, no hace falta molestar al grupo.
# Se comparan sin mayusculas y sin acentos, y basta con que la palabra APAREZCA.
# Para agregar o quitar palabras se edita esta lista y se vuelve a desplegar.
$PALABRAS_AVISO = @(
  'tasa','tasas','cambio','cambiar','precio','cuanto','cuesta','vale',
  'cuenta','cuentas','banco','bancos','transferencia','deposito','pago','pagar','pague',
  'enviar','envio','mandar','mando','recibir','recibe','remesa','remesas','giro',
  'dolar','dolares','usdt','zelle','binance','bolivares','bolivar','pesos','soles','reales',
  'euro','euros','efectivo','comprobante','disponible','saldo'
)
$PALABRAS_AVISO_JS = '[' + (($PALABRAS_AVISO | ForEach-Object { "'" + $_ + "'" }) -join ',') + ']'

$MODO_SOLO_CLIENTES_JS = $(if ($MODO_SOLO_CLIENTES) { 'true' } else { 'false' })

# ===================== CODIGO NODO PRINCIPAL (Code in JavaScript) =====================
$mainCode = @'
// === JK Remesas - Procesamiento de tasas (espejo de la app JK Conversor) ===
function parseCSV(text){
  // Parser robusto: respeta comillas y celdas MULTI-LINEA (ej. cuentas con banco/numero/titular en renglones).
  const Q = '"';
  const rows=[]; let row=[]; let cur=''; let inQ=false;
  for (let i=0; i<text.length; i++){
    const c = text[i];
    if (inQ){ if (c===Q){ if (text[i+1]===Q){ cur+=Q; i++; } else inQ=false; } else cur+=c; }
    else { if (c===Q) inQ=true; else if (c===',') { row.push(cur); cur=''; } else if (c==='\r') { } else if (c==='\n') { row.push(cur); rows.push(row); row=[]; cur=''; } else cur+=c; }
  }
  if (cur.length>0 || row.length>0){ row.push(cur); rows.push(row); }
  return rows.map(r => r.map(s => s.trim())).filter(r => r.some(c => c.length>0));
}
function num(s){ if(s===undefined||s===null||s==='') return 0; let v=String(s).replace(/\s/g,'').replace(',', '.'); const n=parseFloat(v); return isNaN(n)?0:n; }
function numN(s){ if(s===undefined||s===null||String(s).trim()==='') return null; const n=parseFloat(String(s).replace(/\s/g,'').replace(',', '.')); return isNaN(n)?null:n; }

const httpItem = $('Consultar Tasas').first();
let csv = (httpItem && httpItem.json && httpItem.json.data) ? String(httpItem.json.data) : '';

// ===== GOOGLE SHEETS LENTO O CAIDO: SE USA LA ULTIMA COPIA BUENA =====
// El 23/11 Google tardo 4 minutos en dar las cuentas y una clienta recibio su respuesta 5 minutos tarde.
// Las dos consultas a la hoja ahora tienen tope de tiempo; si no contestan (o devuelven algo que no es la
// hoja), se usa la copia de la ultima lectura buena, que el bot guarda en su memoria. Una tasa vieja puede
// estar mal, asi que esa copia solo vale HORAS_RESPALDO_TASAS; la de las cuentas, mas.
const HORAS_RESPALDO_TASAS = __HORAS_RESPALDO_TASAS__;
const HORAS_RESPALDO_CUENTAS = __HORAS_RESPALDO_CUENTAS__;
let memoria = {};
try { if (typeof $getWorkflowStaticData === 'function') memoria = $getWorkflowStaticData('global') || {}; } catch(e){ memoria = {}; }
const respaldo = { tasas: false, cuentas: false };
const copiaVigente = (texto, ts, horas) => !!texto && typeof ts === 'number' && (Date.now() - ts) <= horas * 3600000;
const tasasBuenas = t => { try { return parseCSV(String(t || '')).slice(1).some(r => (r[0]||'').trim() && (num(r[1]) > 0 || num(r[3]) > 0)); } catch(e){ return false; } };
if (tasasBuenas(csv)){
  if (memoria.csvTasas !== csv) memoria.csvTasas = csv;
  if (!memoria.csvTasasTs || Date.now() - memoria.csvTasasTs > 60000) memoria.csvTasasTs = Date.now();   // como mucho 1 escritura por minuto
} else if (copiaVigente(memoria.csvTasas, memoria.csvTasasTs, HORAS_RESPALDO_TASAS) && tasasBuenas(memoria.csvTasas)){
  csv = String(memoria.csvTasas); respaldo.tasas = true;
}

const APP_URL = 'https://grupojk-cambios.github.io/grupojk-conversor/';

// ====== LISTA MANUAL DE MAYORISTAS (respaldo opcional, EDITAR AQUI) ======
// Numeros de WhatsApp mayoristas (solo digitos, con codigo de pais).
// Ejemplo: const MAYORISTAS = ['584121234567', '593961230380'];
const MAYORISTAS = [];
// ================================================

let jid = '';
try { jid = $('Webhook Evolution API').first().json.body.data.key.remoteJid || ''; } catch(e) { jid = ''; }
const senderDigits = String(jid).replace(/\D/g,'');
let esMayorista = MAYORISTAS.some(n => { const d=String(n).replace(/\D/g,''); return d && (senderDigits===d || senderDigits.endsWith(d)); });
// Supabase: si el numero esta registrado en la tabla perfiles_mayor (registro via app) -> mayorista.
// Si el nodo "Consultar Mayorista" falla o no tiene credencial, esto queda en false y se usa detal (seguro).
if (!esMayorista) {
  try {
    const filasMayor = $('Consultar Mayorista').all();
    esMayorista = filasMayor.some(it => it.json && (it.json.id || it.json.whatsapp));
  } catch(e) {}
}
// La tabla en la que Kelvin lo cargo MANDA sobre perfiles_mayor: clientes_bot_mayor da
// tarifa mayor y clientes_bot_detal da detal, asi las dos listas funcionan por separado.
// Si no esta en ninguna (filtro apagado, o Supabase caido) queda lo de arriba, como antes.
let tarifaCargada = '';
try { tarifaCargada = String($('Solo Estos Numeros').first().json.tarifaCargada || ''); } catch(e){}
if (tarifaCargada === 'mayor') esMayorista = true;
else if (tarifaCargada === 'detal') esMayorista = false;

// Admin (Supabase perfiles_detal role='admin'): puede fijar su propia tarifa con "modo mayor"/"modo detal"
// (ver nodo "Detectar Comando Admin"). Mientras no elija, ve tarifa detal por defecto.
let esAdminSender = false;
try { esAdminSender = !!$('Detectar Comando Admin').first().json.esAdmin; } catch(e){}
let modoAdminGuardado = '';
try { modoAdminGuardado = String($('Redis Leer Modo Admin').first().json.modoAdmin || '').toLowerCase().trim(); } catch(e){}
const modo = esAdminSender
  ? ((modoAdminGuardado === 'mayor' || modoAdminGuardado === 'detal') ? modoAdminGuardado : 'detal')
  : (esMayorista ? 'mayor' : 'detal');

if(!csv){
  return [{ json: { lista:[], modo, esMayorista, appUrl:APP_URL, hayEfectivoVe:false, totalPaises:0, respaldo, error:'No se recibieron datos de tasas' } }];
}

const filas = parseCSV(csv);
const head = (filas[0]||[]).map(h=>String(h||'').toUpperCase().normalize('NFD').replace(/[\u0300-\u036f]/g,''));
const idx = {
  factorEUR: head.findIndex(h=>h.includes('FACTOR EUR')||h.includes('VALOR EUR')),
  factorUSDT: head.findIndex(h=>h.includes('FACTOR USDT')||h.includes('VALOR USDT')),
  cod: head.findIndex(h=>h.includes('CODIGO')||h.includes('BANCO')),
  moneda: head.findIndex(h=>h.includes('NOMBRE')||h.includes('MONEDA')),
  mEMayor: head.findIndex(h=>h.includes('MARGEN ENVIO MAYOR')),
  mRMayor: head.findIndex(h=>h.includes('MARGEN RECIBO MAYOR')),
  ciudades: head.findIndex(h=>h.includes('CIUDADES')),
};
const paises=[];
for(let i=1;i<filas.length;i++){
  const row=filas[i]; const nombre=(row[0]||'').trim(); if(!nombre) continue;
  // Margen: celda VACIA = 0 (igual que la app: parseVal('')=0). Solo default 6 si la columna no existe.
  const tE=num(row[1]); const mE=(row[2]!==undefined)?num(row[2]):6;
  const tR=num(row[3]); const mR=(row[4]!==undefined)?num(row[4]):6;
  if(tE===0 && tR===0) continue;
  const codigo = idx.cod!==-1 && row[idx.cod] ? row[idx.cod].toUpperCase() : nombre.substring(0,3).toUpperCase();
  paises.push({ nombre, codigo, moneda: idx.moneda!==-1 && row[idx.moneda] ? row[idx.moneda] : 'Divisa local', tasaProveedorEnvio:tE, margenEnvio:mE, tasaProveedorRecibo:tR, margenRecibo:mR, margenEnvioMayor: idx.mEMayor!==-1?numN(row[idx.mEMayor]):null, margenReciboMayor: idx.mRMayor!==-1?numN(row[idx.mRMayor]):null, factorEUR: (idx.factorEUR!==-1?num(row[idx.factorEUR]):0), factorUSDT: (idx.factorUSDT!==-1?num(row[idx.factorUSDT]):0), ciudades: idx.ciudades!==-1 && row[idx.ciudades] ? String(row[idx.ciudades]).trim() : '' });
}

// Guardar datos crudos para la calculadora (mismo dato que el prompt)
try { const sd=$getWorkflowStaticData('global'); sd.paisesData = paises; } catch(e){}

// ---- MOTOR DE CALCULO: inyectado desde src/motor.js (fuente unica, compartida con la app) ----
__MOTOR_JK__
// Pais de referencia = Ecuador (la base USD del operador). Las tasas de la tabla se cruzan contra Ecuador,
// IGUAL que el Cotizador/Pizarra de la app (GeneradorEstados.jsx): suma de margenes, sin exceptuar ningun pais.
const ecuRef = paises.find(p => (p.nombre||'').toLowerCase()==='ecuador');
const lista = paises
  .filter(p => !/^efectivo venezuela/i.test(p.nombre))
  .map(p => {
    let envio, recibo;
    if (!ecuRef || (p.nombre||'').toLowerCase()==='ecuador') { envio = calcularTasaEnvio(p, modo); recibo = calcularTasaRecibo(p, modo); }
    else { envio = calcularConversion(ecuRef, p, 1, paises, modo); recibo = obtenerTasasProcesadas(p, ecuRef, paises, modo).tasaOrigenParaDolares; }
    return { Pais:p.nombre, Codigo:p.codigo, Moneda:p.moneda, Envio: envio? Number(envio.toFixed(2)):'N/D', Recibo: recibo? Number(recibo.toFixed(2)):'N/D', EsDolar: isCajaDolar(p) };
  });

// Efectivo Venezuela = dolares en efectivo. El CSV trae varias filas "Efectivo Venezuela-Estado" con sus Ciudades.
// IMPORTANTE: el precio PUEDE variar por ciudad, asi que leemos CADA fila por separado con SU propia tasa (NO se colapsa).
// Es 100% dinamico: cualquier fila nueva (otro estado/ciudad, u otro pais) entra sola sin tocar el codigo.
const evEntries = paises.filter(p=>/^efectivo venezuela/i.test(p.nombre));
let evUbicaciones = [];
if (evEntries.length) {
  evUbicaciones = evEntries.map(p => {
    const estado = (String(p.nombre).split('-')[1]||'').trim();
    const ciudades = p.ciudades ? String(p.ciudades).split(',').map(c=>c.trim()).filter(Boolean) : [];
    return { estado, ciudades, envio: calcularTasaEnvio(p, modo)? Number(calcularTasaEnvio(p, modo).toFixed(2)) : 'N/D', recibo: calcularTasaRecibo(p, modo)? Number(calcularTasaRecibo(p, modo).toFixed(2)) : 'N/D' };
  });
}
const hayEfectivoVe = evEntries.length>0;

// ===== CUENTAS con ROTACION DIARIA (1 cuenta por pais por dia) =====
let cuentasCsv = '';
try { cuentasCsv = String($('Consultar Cuentas').first().json.data || ''); } catch(e){}
// Una hoja de cuentas buena tiene filas con pais y datos. Si Google no contesto (o devolvio una pagina de
// error), se usa la ultima copia buena: la fecha de hoy y la rotacion se calculan aqui con el dia de hoy,
// asi que una copia guardada nunca le da al cliente el dia equivocado.
const cuentasBuenas = t => { try { return parseCSV(String(t || '')).slice(1).some(r => (r[0]||'').trim() && (r[3]||'').trim()); } catch(e){ return false; } };
if (cuentasBuenas(cuentasCsv)){
  if (memoria.csvCuentas !== cuentasCsv) memoria.csvCuentas = cuentasCsv;
  if (!memoria.csvCuentasTs || Date.now() - memoria.csvCuentasTs > 60000) memoria.csvCuentasTs = Date.now();
} else if (copiaVigente(memoria.csvCuentas, memoria.csvCuentasTs, HORAS_RESPALDO_CUENTAS) && cuentasBuenas(memoria.csvCuentas)){
  cuentasCsv = String(memoria.csvCuentas); respaldo.cuentas = true;
}
const cuentasTodas = [];
if (cuentasCsv) {
  const filasC = parseCSV(cuentasCsv);
  // Encabezado: Pais, Metodo, Disponible, Datos, Notas [, Tipo]. El ORDEN de filas = orden de rotacion.
  const normH = s => String(s||'').toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g,'').trim();
  const headC = (filasC[0]||[]).map(normH);
  // Soporta 1 columna "Tipo" (DETAL / MAYOR / AMBOS) o 2 columnas "Detal" y "Mayor" (si/no).
  const iTipo = headC.findIndex(h => h.indexOf('TIPO') !== -1 || h.indexOf('TARIFA') !== -1);
  const iDetal = headC.findIndex(h => h === 'DETAL');
  const iMayor = headC.findIndex(h => h === 'MAYOR');
  for (let i=1; i<filasC.length; i++) {
    const row = filasC[i];
    const pais = (row[0]||'').trim();
    const datos = (row[3]||'').trim();
    if (!pais || !datos) continue;
    if (!/^s/i.test((row[2]||'').trim())) continue; // solo Disponible = Si
    // A que tarifa aplica esta cuenta. Por defecto (columna ausente o vacia) sirve para AMBAS.
    let esDetal = true, esMayor = true;
    if (iTipo !== -1) {
      const t = normH(row[iTipo]);
      if (t.indexOf('DETAL') !== -1 && t.indexOf('MAYOR') === -1) esMayor = false;
      else if (t.indexOf('MAYOR') !== -1 && t.indexOf('DETAL') === -1) esDetal = false;
    } else if (iDetal !== -1 || iMayor !== -1) {
      if (iDetal !== -1) esDetal = /^s/i.test(String(row[iDetal]||'').trim());
      if (iMayor !== -1) esMayor = /^s/i.test(String(row[iMayor]||'').trim());
      if (!esDetal && !esMayor) { esDetal = true; esMayor = true; } // fila sin marcar -> ambas
    }
    if (modo === 'mayor' ? !esMayor : !esDetal) continue; // no aplica a este cliente
    cuentasTodas.push({ Pais: pais, Metodo: (row[1]||'').trim(), Datos: datos });
  }
}
// Agrupar SOLO por PAIS (no por banco): UNA sola cuenta por pais por dia,
// sin importar cuantos bancos haya en la hoja para ese pais. Al dia siguiente
// rota a otra cuenta del mismo pais (puede ser de otro banco). Misma cuenta
// para TODOS los clientes de ese dia (el indice depende de la fecha, no del cliente).
const normTxt = s => String(s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').trim();
const porPais = {};
for (const c of cuentasTodas) {
  const k = normTxt(c.Pais);
  (porPais[k] = porPais[k] || []).push(c);
}
// Indice del dia segun hora de Ecuador (UTC-5): cambia a la medianoche de Ecuador
const diaIndex = Math.floor((Date.now() - 5*3600000) / 86400000);

// ===== REGLA DE FIN DE SEMANA PARA ECUADOR =====
// Viernes, sabado y domingo solo se entregan cuentas de Banco de Guayaquil o Banco Pichincha
// (son los que mueven el dinero el fin de semana). Ademas el DOMINGO se repite exactamente la
// misma cuenta que se dio el sabado, por eso usa el indice del dia anterior.
const BANCOS_FINDE_EC = ['guayaquil','pichincha'];
const diaSemanaEc = new Date(Date.now() - 5*3600000).getUTCDay();   // 0=domingo ... 5=viernes, 6=sabado
const esFindeEc = (diaSemanaEc === 5 || diaSemanaEc === 6 || diaSemanaEc === 0);

const cuentas = [];
const avisosCuentas = [];
for (const k in porPais) {
  let arr = porPais[k];
  let idxDia = diaIndex;

  if (k === 'ecuador' && esFindeEc) {
    arr = arr.filter(c => BANCOS_FINDE_EC.some(b => normTxt(c.Metodo).indexOf(b) !== -1));
    if (diaSemanaEc === 0) idxDia = diaIndex - 1;   // domingo = la misma del sabado
    if (!arr.length) {
      // Sin cuentas de esos bancos NO se entrega ninguna de Ecuador: dar una de otro banco en
      // fin de semana haria que el dinero no llegue. El bot responde que un asesor la pasa.
      avisosCuentas.push('Ecuador fin de semana: no hay ninguna cuenta de Guayaquil ni Pichincha marcada Disponible=si');
      continue;
    }
  }

  const idx = ((idxDia % arr.length) + arr.length) % arr.length; // ciclico 0,1,2,...
  cuentas.push(arr[idx]);
}

// ===== FECHA DE HOY EN LA CUENTA =====
// La cuenta cambia todos los dias, asi que al cliente hay que decirle que la que
// recibe es la de HOY. La fecha NO se guarda en la hoja (quedaria congelada y
// manana el cliente veria la de ayer): se agrega aqui, al momento de enviarla.
// Se usa la misma hora de Ecuador (UTC-5) que decide cual cuenta toca, para que
// la fecha y la rotacion nunca se contradigan.
const DIAS_SEM = ['domingo','lunes','martes','miércoles','jueves','viernes','sábado'];
const MESES_ES = ['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
const hoyEc = new Date(Date.now() - 5*3600000);
const fechaHoy = DIAS_SEM[hoyEc.getUTCDay()] + ' ' + hoyEc.getUTCDate() + ' de ' + MESES_ES[hoyEc.getUTCMonth()];
const selloFecha = '_Válida solo hoy, ' + fechaHoy + '_';

for (const c of cuentas) {
  const texto = String(c.Datos || '').trim();
  if (!texto) continue;
  const renglones = texto.split('\n');
  if (/^\*CUENTA AUTORIZADA/i.test(renglones[0].trim())) {
    // Formato nuevo (lo arma el bot de Cuentas): la fecha va debajo del titulo.
    renglones.splice(1, 0, selloFecha);
    c.Datos = renglones.join('\n');
  } else {
    // Filas viejas, guardadas con otro formato: se le antepone el encabezado.
    c.Datos = '*CUENTA AUTORIZADA*\n' + selloFecha + '\n\n' + texto;
  }
}

// ===== PERFIL DEL CLIENTE (historial de transacciones en Supabase) =====
// Lee las operaciones previas del cliente (nodo "Consultar Cliente") y arma un contexto corto
// para que el bot atienda mejor (saludar por nombre, saber a que pais suele enviar).
let clienteContexto = '';
let nombreCliente = '';
try {
  // 1) El nombre que Kelvin le cargo a mano en Supabase (clientes_bot_detal / _mayor).
  //    Le gana al del historial: ese lo escribio el, sabe como se llama el cliente.
  //    Viene pegado al mensaje por el nodo "Solo Estos Numeros".
  let nombre = '';
  try { nombre = String($('Solo Estos Numeros').first().json.nombreCargado || '').trim(); } catch(e){}

  // 2) El historial de operaciones. De aca sale el nombre si no estaba cargado, y
  //    ademas el pais al que suele enviar.
  const ops = $('Consultar Cliente').all().map(i => i.json).filter(o => o && (o.pais_destino || o.nombre_cliente));
  if (!nombre && ops.length) nombre = ((ops[0].nombre_cliente || '') + ' ' + (ops[0].apellido_cliente || '')).trim();
  nombreCliente = nombre;

  let recurrente = '';
  const partes = [];
  if (nombre) partes.push('se llama ' + nombre);
  if (ops.length) {
    const freq = {};
    ops.forEach(o => { const p = o.pais_destino; if (p) freq[p] = (freq[p] || 0) + 1; });
    recurrente = Object.keys(freq).sort((a,b) => freq[b] - freq[a])[0] || '';
    partes.push('ya es cliente (tiene operaciones previas con nosotros)');
    if (recurrente) partes.push('suele enviar a ' + recurrente);
  }
  if (partes.length) {
    let txt = 'Este cliente ' + partes.join(', ') + '.';
    // Aqui NO se le pide que lo salude por su nombre: eso lo decide "Revisar Operacion", que
    // deja usar el nombre una sola vez cada 24 h (repetirlo en cada mensaje suena a bot).
    if (recurrente) txt += ' Su destino habitual es solo contexto: no lo asumas; si no dice a donde envia, preguntale.';
    txt += ' No menciones montos ni datos viejos salvo que el cliente pregunte.';
    clienteContexto = txt;
  }
} catch(e){}

// ===== PAIS POR EL PREFIJO DEL NUMERO (solo como valor por defecto) =====
// 27 de 34 clientes son de Ecuador (+593). Si el cliente pide "la cuenta" sin decir desde donde
// deposita, se le da la del pais de su numero Y se le dice cual es, para que corrija si no es asi.
// Lo que diga el cliente manda: puede depositar otra persona desde otro pais. El DESTINO (a donde
// envia) nunca se saca del numero.
const PREFIJOS = [['593', 'Ecuador'], ['57', 'Colombia'], ['58', 'Venezuela'], ['51', 'Perú'], ['1', 'Estados Unidos (Zelle)']];
let paisPorPrefijo = '', prefijo = '';
if (/@s\.whatsapp\.net$/.test(String(jid))) {
  for (const par of PREFIJOS) {
    // +1 son 11 digitos (1 + 10). Asi un numero raro que empiece por 1 no se toma por EE.UU.
    if (senderDigits.indexOf(par[0]) === 0 && (par[0] !== '1' || senderDigits.length === 11)) { prefijo = par[0]; paisPorPrefijo = par[1]; break; }
  }
}
if (paisPorPrefijo) {
  clienteContexto = (clienteContexto ? clienteContexto + ' ' : '')
    + 'Su numero es de ' + paisPorPrefijo + ' (+' + prefijo + '). Si pide la cuenta para depositar y NO dijo desde que pais deposita, '
    + 'dale la de ' + paisPorPrefijo + ' y dilo claro en la misma respuesta (ej. "Te paso la cuenta de ' + paisPorPrefijo + ' 👇"), '
    + 'para que corrija si no es asi. Si dice que deposita desde otro pais, o que deposita otra persona desde otro pais, '
    + 'usa la cuenta de ESE pais. El pais DESTINO (a donde envia) NUNCA lo asumas por su numero.';
}

// RED DE SEGURIDAD de la memoria del chat. El nodo "Memoria de Chat" trae su propia llave
// configurada, pero n8n lo ha guardado VACIO dos veces (18/11 y 20/11): vuelve a su configuracion
// por defecto, que lee justo este campo (sessionId) de lo que le llega al agente. Sin el campo,
// el bot fallaba con "No session ID found" con TODOS los clientes y nadie se enteraba.
// Con el campo, si el nodo se vuelve a vaciar el bot sigue funcionando (con una memoria mas corta).
let sessionId = '';
try { sessionId = String($('Webhook Evolution API').first().json.body.data.key.remoteJid || ''); } catch(e){}

return [{ json: { lista, modo, esMayorista, appUrl:APP_URL, hayEfectivoVe, evUbicaciones, totalPaises: paises.length, cuentas, hayCuentas: cuentas.length>0, diaIndex, diaSemanaEc, avisosCuentas, clienteContexto, nombreCliente, paisPorPrefijo, sessionId, respaldo, error: paises.length? null : 'Lista vacia' } }];
'@

# ===================== CODIGO DE LA CALCULADORA (Code Tool) =====================
$toolCode = @'
// === Calculadora de remesas JK (motor identico a la app) ===
function _safe(fn){ try { return fn(); } catch(e){ return undefined; } }

let _a = {};
const _q = _safe(()=>query);
if (_q && typeof _q === 'object') _a = _q;
const inOrigen   = (_a.pais_origen  !== undefined) ? _a.pais_origen  : _safe(()=>pais_origen);
const inDestino  = (_a.pais_destino !== undefined) ? _a.pais_destino : _safe(()=>pais_destino);
const inMonto    = (_a.monto        !== undefined) ? _a.monto        : _safe(()=>monto);
const inDir      = (_a.direccion    !== undefined) ? _a.direccion    : _safe(()=>direccion);
const inModo     = (_a.modo         !== undefined) ? _a.modo         : _safe(()=>modo);

const origenQ  = String(inOrigen||'').trim();
const destinoQ = String(inDestino||'').trim();
const montoN   = Number(inMonto)||0;
const direccion= (String(inDir||'directa').toLowerCase()==='inversa')?'inversa':'directa';
const modoN    = (String(inModo||'detal').toLowerCase()==='mayor')?'mayor':'detal';

function parseCSV(text){
  // Parser robusto: respeta comillas y celdas MULTI-LINEA (ej. cuentas con banco/numero/titular en renglones).
  const Q = '"';
  const rows=[]; let row=[]; let cur=''; let inQ=false;
  for (let i=0; i<text.length; i++){
    const c = text[i];
    if (inQ){ if (c===Q){ if (text[i+1]===Q){ cur+=Q; i++; } else inQ=false; } else cur+=c; }
    else { if (c===Q) inQ=true; else if (c===',') { row.push(cur); cur=''; } else if (c==='\r') { } else if (c==='\n') { row.push(cur); rows.push(row); row=[]; cur=''; } else cur+=c; }
  }
  if (cur.length>0 || row.length>0){ row.push(cur); rows.push(row); }
  return rows.map(r => r.map(s => s.trim())).filter(r => r.some(c => c.length>0));
}
function num(s){ if(s===undefined||s===null||s==='') return 0; let v=String(s).replace(/\s/g,'').replace(',', '.'); const n=parseFloat(v); return isNaN(n)?0:n; }
function numN(s){ if(s===undefined||s===null||String(s).trim()==='') return null; const n=parseFloat(String(s).replace(/\s/g,'').replace(',', '.')); return isNaN(n)?null:n; }
function norm(s){ return (s||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9 ]/g,'').trim(); }
function construirPaises(text){
  const filas = parseCSV(text); if(!filas.length) return [];
  const head=(filas[0]||[]).map(h=>String(h||'').toUpperCase().normalize('NFD').replace(/[\u0300-\u036f]/g,''));
  const idx={ factorEUR:head.findIndex(h=>h.includes('FACTOR EUR')||h.includes('VALOR EUR')), factorUSDT:head.findIndex(h=>h.includes('FACTOR USDT')||h.includes('VALOR USDT')), cod:head.findIndex(h=>h.includes('CODIGO')||h.includes('BANCO')), moneda:head.findIndex(h=>h.includes('NOMBRE')||h.includes('MONEDA')), mEMayor:head.findIndex(h=>h.includes('MARGEN ENVIO MAYOR')), mRMayor:head.findIndex(h=>h.includes('MARGEN RECIBO MAYOR')) };
  const paises=[];
  for(let i=1;i<filas.length;i++){ const row=filas[i]; const nombre=(row[0]||'').trim(); if(!nombre) continue; const tE=num(row[1]); const mE=(row[2]!==undefined)?num(row[2]):6; const tR=num(row[3]); const mR=(row[4]!==undefined)?num(row[4]):6; if(tE===0&&tR===0) continue; const codigo=idx.cod!==-1&&row[idx.cod]?row[idx.cod].toUpperCase():nombre.substring(0,3).toUpperCase(); paises.push({ nombre, codigo, moneda: idx.moneda!==-1&&row[idx.moneda]?row[idx.moneda]:'Divisa local', tasaProveedorEnvio:tE, margenEnvio:mE, tasaProveedorRecibo:tR, margenRecibo:mR, margenEnvioMayor: idx.mEMayor!==-1?numN(row[idx.mEMayor]):null, margenReciboMayor: idx.mRMayor!==-1?numN(row[idx.mRMayor]):null, factorEUR: (idx.factorEUR!==-1?num(row[idx.factorEUR]):0), factorUSDT: (idx.factorUSDT!==-1?num(row[idx.factorUSDT]):0), ciudades: idx.ciudades!==-1&&row[idx.ciudades]?String(row[idx.ciudades]).trim():'' }); }
  return paises;
}
// ---- MOTOR DE CALCULO: inyectado desde src/motor.js (fuente unica, compartida con la app) ----
__MOTOR_JK__
function evMatch(evList, nq){
  // Casar por ESTADO (ej "zulia") o por CIUDAD del campo Ciudades (ej "maracaibo" -> Zulia).
  for (const x of evList) { const e=norm(String(x.nombre).split('-')[1]||''); if (e && (nq===e || nq.indexOf(e)!==-1)) return x; }
  for (const x of evList) { const c=norm(String(x.ciudades||'')); if (!c) continue; const toks=c.split(/[ ,]+/).filter(t=>t.length>=4); if (toks.some(t => nq.indexOf(t)!==-1)) return x; }
  return null;
}
function findPais(paises,q){ const nq=norm(q); if(!nq) return null;
  // Efectivo Venezuela (dolares en efectivo). El CSV trae varias "Efectivo Venezuela-Estado"; todas comparten tasa base en detal.
  const evList = paises.filter(x=>/efectivo venezuela/i.test(x.nombre));
  // Si menciona "efectivo" explicitamente: devolver la ubicacion que casa (estado/ciudad) o la primera.
  if (evList.length && nq.indexOf('efectivo')!==-1) { return evMatch(evList, nq) || evList[0]; }
  // Match exacto de pais (asi "venezuela" -> bolivares VES, NO efectivo).
  let p=paises.find(x=>norm(x.nombre)===nq); if(p) return p;
  // Estado/ciudad de efectivo mencionado solo (ej "caracas", "maracaibo", "barquisimeto").
  if (evList.length) { const m=evMatch(evList, nq); if (m) return m; }
  const alias={ euros:'europa', eur:'europa', tether:'usdt' }; if(alias[nq]){ p=paises.find(x=>norm(x.nombre)===norm(alias[nq])); if(p) return p; } p=paises.find(x=>norm(x.nombre).includes(nq)||nq.includes(norm(x.nombre))); return p||null; }

function compute(paises){
  if(!paises || !paises.length) return JSON.stringify({ ok:false, error:'No pude cargar las tasas en este momento. Pide disculpas y di que un asesor ayudara.' });
  const o = findPais(paises, origenQ); const d = findPais(paises, destinoQ);
  if(!o) return JSON.stringify({ ok:false, error:'No encontre el pais/moneda de ORIGEN: '+origenQ+'. Pide al cliente que lo aclare.' });
  if(!d) return JSON.stringify({ ok:false, error:'No encontre el pais/moneda de DESTINO: '+destinoQ+'. Pide al cliente que lo aclare.' });
  if(!(montoN>0)) return JSON.stringify({ ok:false, error:'Falta el monto a convertir o no es valido.' });
  const cross = calcularConversion(o,d,1,paises,modoN);
  let resultado, explicacion;
  if(direccion==='inversa'){
    resultado = calcularConversionInversa(o,d,montoN,paises,modoN);
    explicacion = 'Para que el destinatario reciba '+montoN+' '+d.codigo+' en '+d.nombre+', el cliente debe enviar aprox. '+resultado.toFixed(2)+' '+o.codigo+' desde '+o.nombre+'.';
  } else {
    resultado = calcularConversion(o,d,montoN,paises,modoN);
    explicacion = 'Enviando '+montoN+' '+o.codigo+' ('+o.nombre+') el destinatario recibe '+resultado.toFixed(2)+' '+d.codigo+' ('+d.nombre+').';
  }
  // La tasa se entrega con 2 decimales, IGUAL que la app y la pizarra, para que el cliente nunca
  // vea la misma tasa escrita de dos formas distintas. Antes iba con 6 decimales y la IA redondeaba
  // a su antojo (a veces daba 816,192 y otras 816,19).
  // Salvaguarda: un cruce con tasa diminuta (< 0,005) quedaria en 0,00, ahi se dejan mas decimales.
  // La tasa se MUESTRA como en la pizarra y en el cotizador de la app (misma regla que src/Cotizador.jsx):
  // si el cliente manda moneda local y recibe dolares (o euros), la tasa es cuanta moneda local hace
  // falta por 1 dolar ("1184.24 VES"), nunca el numerito al reves ("0,000844 VES" por cada Bs).
  let tasaValor = cross, unidadTasa = d.codigo, baseTasa = o.codigo;
  if (!isCajaDolar(o) && (isCajaDolar(d) || ['EUR', 'GBP', 'EU'].includes(d.codigo))){
    tasaValor = calcularConversionInversa(o,d,1,paises,modoN); unidadTasa = o.codigo; baseTasa = d.codigo;
  }
  const tasaMostrar = (Math.abs(tasaValor) < 0.005) ? Number(tasaValor.toFixed(6)) : Number(tasaValor.toFixed(2));
  return JSON.stringify({ ok:true, modo:modoN, direccion, origen:o.nombre, monedaOrigen:o.moneda, codigoOrigen:o.codigo, destino:d.nombre, monedaDestino:d.moneda, codigoDestino:d.codigo, monto:montoN, resultado:Number(resultado.toFixed(2)), tasaCruzada:tasaMostrar, unidadTasa, tasaTexto:'1 '+baseTasa+' = '+tasaMostrar+' '+unidadTasa, explicacion });
}

// 1) Camino rapido y seguro: datos ya cargados por el nodo principal (sincrono)
let _data = _safe(()=>{ if(typeof $getWorkflowStaticData==='function'){ const sd=$getWorkflowStaticData('global'); if(sd && Array.isArray(sd.paisesData) && sd.paisesData.length) return sd.paisesData; } return undefined; });
if(_data && _data.length) return compute(_data);

// 2) Respaldo: descargar el CSV (asincrono) solo si no hubo datos en memoria
if(typeof fetch !== 'function') return JSON.stringify({ ok:false, error:'No pude acceder a las tasas. Pide disculpas y di que un asesor ayudara.' });
const _url='https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv';
// Con tope de tiempo: si Google no contesta, la calculadora responde que no pudo cargar las tasas en vez de quedarse esperando.
const _tope = (typeof AbortSignal !== 'undefined' && AbortSignal.timeout) ? { signal: AbortSignal.timeout(15000) } : {};
return (async () => { try { const res = await fetch(_url + '&nocache=' + Date.now(), _tope); const text = await res.text(); return compute(construirPaises(text)); } catch(e){ return JSON.stringify({ ok:false, error:'No pude descargar las tasas: '+e.message }); } })();
'@

# ===================== INYECCION DEL MOTOR DE CALCULO =====================
# FUENTE UNICA: src/motor.js es el mismo archivo que usa la app (React).
# Aqui se lee, se le quitan los "export" y se mete tal cual donde dice __MOTOR_JK__.
# Asi no existe una segunda copia de las matematicas que se pueda despegar.
# Si esto falla, el build se detiene: mejor no desplegar que desplegar con el motor viejo.
$motorPath = Join-Path $PSScriptRoot 'src\motor.js'
if(-not (Test-Path $motorPath)){ throw "No encontre el motor en $motorPath. El bot NO se puede construir sin el." }
$motorJs = [System.IO.File]::ReadAllText($motorPath, [System.Text.Encoding]::UTF8)

# Quitar los "export " (en n8n las funciones van sueltas, no es un modulo).
$motorJs = $motorJs -replace '(?m)^export\s+function\s+', 'function '
if($motorJs -match '(?m)^\s*(export|import)\s'){ throw 'src/motor.js tiene import/export que no supe quitar. Revisalo antes de desplegar.' }

# Red de seguridad: el motor se inyecta en n8n, donde no existe el navegador.
foreach($prohibido in @('import.meta', 'window.', 'document.', 'localStorage')){
  # Se ignoran los comentarios (ahi se nombran a proposito en las reglas del archivo).
  $sinComentarios = ($motorJs -split "`n" | Where-Object { $_ -notmatch '^\s*(//|\*|/\*)' }) -join "`n"
  if($sinComentarios.Contains($prohibido)){ throw "src/motor.js usa '$prohibido', que no existe en n8n. El bot no puede recibirlo." }
}

$funcionesMotor = ([regex]::Matches($motorJs, '(?m)^function\s+(\w+)')) | ForEach-Object { $_.Groups[1].Value }
Write-Host ("Motor leido de src/motor.js: " + $funcionesMotor.Count + " funciones -> " + ($funcionesMotor -join ', '))
foreach($obligatoria in @('calcularTasaEnvio','calcularTasaRecibo','isCajaDolar','esEcuador','obtenerTasasProcesadas','calcularConversion','calcularConversionInversa')){
  if($funcionesMotor -notcontains $obligatoria){ throw "A src/motor.js le falta la funcion '$obligatoria'. El bot la necesita." }
}

# OJO: .Replace() literal, NO -replace. El motor trae template strings como
# `factor${origen.codigo}` y en el reemplazo de -replace (regex de .NET) ${...}
# se interpreta como referencia a un grupo con nombre y corrompe el codigo.
$mainCode = $mainCode.Replace('__MOTOR_JK__', $motorJs)
$mainCode = $mainCode.Replace('__HORAS_RESPALDO_TASAS__', [string]$HORAS_RESPALDO_TASAS).Replace('__HORAS_RESPALDO_CUENTAS__', [string]$HORAS_RESPALDO_CUENTAS)
$toolCode = $toolCode.Replace('__MOTOR_JK__', $motorJs)
if($mainCode.Contains('__MOTOR_JK__') -or $toolCode.Contains('__MOTOR_JK__')){ throw 'Quedo un __MOTOR_JK__ sin reemplazar.' }

# ===================== INPUT SCHEMA DE LA CALCULADORA =====================
$inputSchema = @'
{
  "type": "object",
  "properties": {
    "pais_origen": { "type": "string", "description": "Pais o moneda DESDE donde sale el dinero, tal como lo dijo el cliente (ej: Chile, Zelle, USDT, Europa, Colombia)." },
    "pais_destino": { "type": "string", "description": "Pais o moneda HACIA donde llega el dinero (ej: Colombia, Venezuela, Chile)." },
    "monto": { "type": "number", "description": "Cantidad numerica a convertir, en formato latino interpretado como ENTERO. El punto son miles: 710.000 = 710000, 1.000.000 = 1000000. La coma es decimal: 207,76 = 207.76. Envia el numero completo (710000, NO 710)." },
    "direccion": { "type": "string", "enum": ["directa", "inversa"], "description": "directa = el cliente ENVIA 'monto' en la moneda de origen y quiere saber cuanto llega. inversa = el cliente quiere que LLEGUEN 'monto' a destino y saber cuanto debe enviar." },
    "modo": { "type": "string", "enum": ["detal", "mayor"], "description": "Tipo de tarifa. Usa SIEMPRE el valor indicado en el system prompt para este cliente. Por defecto detal." }
  },
  "required": ["pais_origen", "pais_destino", "monto"]
}
'@

# ===================== SYSTEM MESSAGE DEL AGENTE =====================
$systemMsg = @'
=Eres asistente de *Cambios JK🚛* por WhatsApp. RESPONDE EN MAXIMO 2-3 LINEAS, directo y humano. 1 emoji maximo (nunca 😊). NO repitas frases de cortesia.

El cliente puede enviarte VARIOS mensajes juntos (separados por saltos de linea). Leelos todos y responde UNA sola vez, corto.

Tarifa de este cliente: {{ $node["Code in JavaScript"].json.modo }} (detal=publico, mayor=mayorista). Nunca menciones lo mayorista a un cliente detal.
{{ $node["Code in JavaScript"].json.clienteContexto ? ('CONTEXTO DEL CLIENTE (usalo con naturalidad para atender mejor): ' + $node["Code in JavaScript"].json.clienteContexto) : '' }}
{{ $('Revisar Operacion').first().json.reglaNombre || '' }}
{{ $('Revisar Operacion').first().json.reglaSaludo || '' }}
{{ $('Revisar Operacion').first().json.contextoOperaciones || '' }}
{{ $('Revisar Operacion').first().json.horarioTexto || '' }}

Tasas de hoy (Envio/Recibo ya con margen; "N/D" = no disponible):
{{ JSON.stringify($node["Code in JavaScript"].json.lista) }}

CUENTAS DEL DIA para pagar/depositar (UNA sola cuenta por pais por dia; usa el campo "Datos" tal cual):
{{ JSON.stringify($node["Code in JavaScript"].json.cuentas) }}

REGLAS:
- MONTO a convertir, cruce entre paises, o dolares/USDT/euros (EsDolar:true): USA la herramienta calculadora_remesas (pais_origen, pais_destino, monto, direccion "directa"/"inversa", modo "{{ $node["Code in JavaScript"].json.modo }}"). NUNCA calcules tu; da el numero que devuelve la herramienta.
- LLAMA LA HERRAMIENTA SIEMPRE (LA REGLA MAS IMPORTANTE DE TODAS): para dar CUALQUIER cifra (tasa, monto, "recibes X") DEBES llamar calculadora_remesas en ESTE MISMO turno. Si en este turno no llamaste la herramienta, NO puedes escribir ningun numero: en ese caso pregunta lo que falte en vez de inventar.
- LA CONVERSACION NO ES FUENTE DE TASAS: esta PROHIBIDO copiar, repetir o "acordarte" de una tasa o monto que aparezca mas arriba en el historial, aunque lo hayas dicho tu hace un minuto. Las tasas cambian durante el dia y la tarifa del cliente (detal/mayor) pudo haber cambiado entre mensajes: un numero viejo puede estar MAL aunque parezca correcto. Vuelve a llamar la herramienta SIEMPRE, incluso si la pregunta es identica a una anterior, si el cliente solo dice "dame la tasa" / "y ahora?" / "cuanto es?" / "si" / "ok", o si esta citando un mensaje tuyo. Repetir un numero sin recalcular es un ERROR GRAVE.
- La tarifa vigente AHORA es "{{ $node["Code in JavaScript"].json.modo }}" y ese es el valor exacto que debes pasar en el parametro modo. Ignora cualquier tarifa que se haya usado antes en la conversacion.
- DECIMALES AL RESPONDER: escribe SIEMPRE las tasas y los montos con 2 decimales, ni uno mas. Los numeros que devuelve la herramienta ya vienen redondeados a 2: copialos TAL CUAL, no les agregues decimales ni los recalcules. Ej: escribe "Tasa: 816.19 Bs", nunca "816.192". (Unica excepcion: si la herramienta te devuelve un numero con mas decimales porque es diminuto, ahi si lo copias completo.) Esto es para que la tasa se vea igual que en la pizarra y en la app.
- FORMATO DE NUMEROS (MUY IMPORTANTE): los montos vienen en formato latino. El PUNTO son MILES y la COMA son decimales. Ejemplos: "710.000" = 710000 (setecientos diez mil); "1.000.000" = 1000000; "1.500,50" = 1500.5; "207,76" = 207.76. NUNCA interpretes el punto como decimal en montos grandes. Pasa a la herramienta el numero entero correcto (ej 710000, no 710).
- IDENTIFICA bien ORIGEN y DESTINO antes de calcular. Mapeo moneda->lugar: COP/"pesos colombianos"=Colombia; USD/"dolares"/"$"=Ecuador, Zelle, Panama o EEUU (segun lo que diga); VES/"bolivares"/"Bs"=Venezuela; "efectivo en VE"=Efectivo Venezuela. "Cuanto recibo/me llega/me das" = el cliente da el monto de ORIGEN (direccion directa). "Cuanto debo enviar/pasar para que llegue X" = X es el DESTINO que debe llegar (direccion inversa). Si la frase es confusa, repregunta en pocas palabras antes de calcular.
- SANIDAD / NO TERQUEAR: si el cliente dice que el monto esta mal, o el resultado se ve descomunal (millones cuando deberian ser cientos, o viceversa), NUNCA insistas "el calculo es correcto". Asume que pudo haber error de direccion o de formato de numero: vuelve a llamar la herramienta revisando origen, destino, direccion y el monto, y corrige.
- TASA SOLA (cliente pide "tasa de X" o "que tasa hay para X" SIN dar monto ni el otro pais): NO sueltes los numeros de Envio/Recibo. Responde corto pidiendo el cruce: "Hola! Para cotizarte bien, dime desde donde envias y hacia donde recibe el destinatario (y el monto si lo tienes)". Cuando ya tengas origen + destino (con o sin monto), haz un EJEMPLO usa la herramienta calculadora_remesas con un monto de muestra (100 si no dieron monto), responde el resultado en 1-2 lineas, y al FINAL pon "Tasa: X.XX <codigo>". Ej: "Por 100 USD desde Ecuador recibes 341.440 COP en Colombia. Tasa: 3414.40 COP". Si el cliente da monto, usa ESE monto (no 100).
- LA LINEA "Tasa:" SE ESCRIBE COMO EN LA PIZARRA: siempre "Tasa: " + tasaCruzada + " " + unidadTasa, copiados TAL CUAL de la herramienta (es el numero grande por 1 dolar o 1 euro). Ej. de Venezuela a Ecuador: "Tasa: 1184.24 VES". NUNCA uses codigoDestino en esa linea, NUNCA escribas una tasa al reves como "0.000844" y NUNCA la inviertas tu.
- DISPONIBILIDAD (NO te equivoques en esto): la lista de tasas de arriba es la VERDAD absoluta. ANTES de decir que NO manejas algo, BUSCALO en la lista por nombre de pais, por codigo de moneda o por nombre de moneda. Ejemplos de match: "pesos mexicanos"/"mexico"/"mxn" = Mexico; "pesos colombianos"/"cop" = Colombia; "soles" = Peru; "reales" = Brasil. Si el pais/moneda APARECE en la lista con una tasa de Envio o Recibo distinta de "N/D", entonces SI lo manejas en esa direccion: cotiza normal, NUNCA digas que no. Solo responde "Por ahora no manejamos ese servicio" cuando de verdad NO esta en la lista, o ambas tasas (Envio y Recibo) son "N/D". Nunca asumas ni adivines: revisa la lista primero.
- VENEZUELA: hay bolivares (VES, a cuenta/pago movil) y efectivo en dolares ("Efectivo Venezuela"). Regla para NO preguntar de mas: (a) si el cliente YA dijo "Bs"/"bolivares"/"pago movil" -> usa Venezuela (bolivares) y NO preguntes nada de eso. (b) si YA dijo "dolares"/"$"/"efectivo"/"cash" o una ciudad/estado venezolano (Caracas, Maracaibo, Valencia...) -> es Efectivo Venezuela (USD). (c) SOLO pregunta "Lo quieres en bolivares o en efectivo (dolares)?" cuando el cliente va a RECIBIR dinero EN Venezuela y NO dejo claro cual de los dos quiere. (d) si Venezuela es el ORIGEN (el cliente ENVIA Bs hacia otro pais), NUNCA preguntes eso: solo es bolivares. Para efectivo en dolares, pregunta en que ciudad lo retira.
- CUENTAS (REGLA ESTRICTA - UNA SOLA CUENTA POR PAIS POR DIA): en la lista CUENTAS DEL DIA hay EXACTAMENTE UNA cuenta por pais (la del dia de hoy, ya rotada). Cuando el cliente pida datos para pagar / donde deposito / a donde transfiero, busca la cuenta de ese pais en la lista y envia su campo "Datos" TAL CUAL, completo (con todas sus lineas: banco, numero, titular, cedula). NUNCA preguntes "cual banco prefieres", NUNCA ofrezcas alternativas, NUNCA enumeres bancos: solo manda la unica cuenta que hay para ese pais hoy. Si el cliente pide OTRA cuenta / OTRO banco / "una banesco" / "tienes de otro banco" / "mandame otra" (o cualquier variante) DESPUES de que ya le enviaste la del dia, responde EXACTAMENTE UNA linea corta: "Solo esa esta habilitada hoy, usamos una sola cuenta para recibir al dia por pais 🙏". No des explicaciones extra, no ofrezcas escalar, no repitas la cuenta. Solo si NO hay NINGUNA cuenta de ese pais en la lista: "Por ahora no tengo esa cuenta a la mano, un asesor te la pasa enseguida."
- OJO CON EL COMPROBANTE: los datos que vienen DENTRO del corchete "[El cliente envio un COMPROBANTE de pago. Datos leidos: ...]" son del comprobante que el cliente pago (banco de origen, monto, referencia). NO son la cuenta destino. NUNCA los cuentes como si el cliente te hubiera pasado una cuenta.
- ESTADO DE LA OPERACION: si al final del mensaje ves "[ESTADO DE LA OPERACION: ...]", esa nota la pone el sistema despues de revisar la captura y la cuenta de este cliente, y MANDA sobre las reglas de comprobante de abajo: responde exactamente lo que dice. Nunca menciones esa nota al cliente.
- COMPROBANTE DE PAGO: si ves "[El cliente envio un COMPROBANTE de pago...]", NUNCA digas "no tengo esa cuenta". Responde MUY corto, 1 sola linea. Si en el mensaje hay numeros de cuenta/cedula/banco/datos de una cuenta destino (aunque vengan reenviados o en numeros sueltos), confirma: "Listo, recibido! Procesamos tu remesa enseguida ✅" y NO preguntes nada mas. SOLO si NO hay ninguna cuenta en el mensaje, pide corto: "Recibi tu comprobante! 🙌 Pasame la cuenta destino (banco, numero y titular)". La cuenta destino es donde el destinatario RECIBE el dinero; el cliente puede dividir el monto en varias cuentas.
- IMAGEN DE CUENTA: si ves "[El cliente envio una imagen con una CUENTA bancaria...]", trata esos datos como la cuenta destino para su remesa.
- BENEFICIARIOS: nunca ofrezcas cuentas guardadas ni listas de beneficiarios. Si el cliente no manda los datos de la cuenta destino, pideselos simple: banco, numero de cuenta, titular y cedula (y el monto de cada una si son varias).
- YA LLEGO? / COMO VA MI ENVIO? / YA SALIO?: contesta corto con la ULTIMA OPERACION DEL CLIENTE de arriba. EN PROCESO -> "Ya está en proceso 👍 Apenas salga te paso el comprobante por aquí." Si salio solo una parte (ej. "ya salio 1 de 2") -> "Ya salió 1 de 2 ✅ La otra está en proceso, apenas salga te paso el comprobante." ENVIADA -> "Sí, ya salió <cuando> ✅ Te pasé el comprobante por aquí." EN ESPERA -> "Se procesa a partir de las 9:00 am 👍". Si arriba NO hay ULTIMA OPERACION DEL CLIENTE -> "Déjame revisar con un asesor y te confirmo enseguida." NUNCA digas que ya llegó si no dice ENVIADA.
- Fuera de tema: "Solo remesas de JK."
- Quejas o problema con un giro: "Un asesor te contacta enseguida."
- Nunca pidas claves, cuentas ni documentos. No des consejo financiero.
- Ver todas las tasas: {{ $node["Code in JavaScript"].json.appUrl }}
{{ $node["Code in JavaScript"].json.hayEfectivoVe ? '- Efectivo Venezuela (dolares en efectivo). El precio PUEDE variar por ciudad, asi que SIEMPRE pregunta el estado/ciudad y calcula con la herramienta usando ESA ubicacion exacta como pais_destino (ej "Efectivo Venezuela Maracaibo"). Ubicaciones disponibles: ' + ($node["Code in JavaScript"].json.evUbicaciones || []).map(u => u.estado + (u.ciudades && u.ciudades.length ? ' (' + u.ciudades.join(', ') + ')' : '')).join('; ') + '. Si la ciudad NO esta en la lista, ahi no hay entrega en efectivo por ahora.' : '' }}

TONO (asi contesta Kelvin a sus clientes): corto, directo y cercano. Nunca uses 😊. PROHIBIDO usar frases de relleno como "aqui estoy", "estoy aqui", "disponible", "con gusto", "quedo atento", "para ayudarte", "cualquier consulta", "no dudes en". Responde lo justo y para. Suena como una persona, no como un bot.
Ejemplos (cliente -> tu):
- "Hola buen dia" -> "Hola, buen día 👋 Dime, ¿qué necesitas?"
- "Buenas tardes" -> "Buenas tardes 👋 Dime, ¿qué necesitas?"
- "Buenos dias, como estas?" -> "Buenos días, bien gracias 🙏 Dime, ¿qué necesitas?"
- "Hola, que tal" -> "Hola, todo bien 🙏 Dime, ¿qué necesitas?"
- "Buenos dias amigo, ayudame con ese envio" (con captura o cuenta, la nota del estado manda) -> "Buenos días 🙌 " + la frase de la nota
- "Buen provecho" -> "Igualmente 🙌"
- "Bendiciones" / "feliz dia" -> "Igualmente, bendiciones 🙏"
- "Buenas noches, disculpe la hora" -> "Buenas noches, tranquilo. Dime."
- "Hola, estan abiertos?" -> "Hola, sí 👋 Dime qué necesitas."
- "Que tasa hay hoy pa Colombia?" -> "¿Desde dónde envías y cuánto? Así te cotizo exacto."
- "Cuenta pa Ecuador" -> (solo la cuenta del dia, tal cual, sin nada mas)
- "Pasame la cuenta" (numero de Ecuador, no dijo el pais) -> "Te paso la cuenta de Ecuador 👇" y la cuenta del dia
- "Ya deposite" (sin captura) -> "Listo, pásame la captura porfa."
- "Puedo dividir en varias cuentas?" -> "Sí, claro. Pásame cada cuenta con el monto que va a cada una."
- "Disculpa la demora" -> "Tranquilo, sin problema."

MULTI-COTIZACION: si das varias cotizaciones (ej. desde Venezuela Y desde Ecuador), separa cada cotizacion con una linea que diga solamente "---" (tres guiones, sin nada mas, en una linea propia). Asi cada cotizacion sale como mensaje aparte en WhatsApp. Una sola cotizacion = sin "---".
'@

# ===================== CODIGO: PREP DEBOUNCE =====================
$prepCode = @'
// Prepara los datos para el debounce con Redis. El texto ya viene unificado (de texto directo o de audio transcrito).
let jid='', texto='';
try { jid = $('Webhook Evolution API').first().json.body.data.key.remoteJid || ''; } catch(e){}
try { texto = $json.texto || ''; } catch(e){}
const miTs = String(Date.now()) + '-' + Math.random().toString(36).slice(2,8);

// Si lo que llego es un COMPROBANTE, se espera mas antes de contestar. La gente manda
// primero la foto del pago y tarda en escribir la cuenta destino; si se contesta a los 30
// segundos, el comprobante y la cuenta caen en ejecuciones distintas y el bot nunca ve las
// dos cosas juntas. Paso el 19/11: la clienta tardo 36 segundos.
const esComprobante = texto.indexOf('COMPROBANTE de pago') !== -1;

// De noche (fuera de horario) NO se manda el sticker de "verificando su deposito": nadie lo esta
// verificando. Cuando tenga la captura y la cuenta, el bot le contesta "Recibido, se procesa...".
__HORARIO_JK__
const stickerVerificando = esComprobante && horarioDe(Date.now()).abierto;

// Los datos de una CUENTA destino tambien esperan lo mismo (cuenta + foto). Solo cuentan los datos
// FIRMES: un numero largo (cuenta o telefono de pago movil, aunque venga con espacios o guiones),
// un correo (Zelle, PayPal) o una direccion de billetera. Una pregunta como "me pasas la cuenta?"
// o "tienes cuenta en Banesco?" NO espera: se contesta en 30 s como siempre.
// Lo que el cliente cita se ignora (puede ser nuestra propia cuenta).
function datosFirmes(t){
  const sinCita = String(t || '').replace(/\[el cliente respondio citando[^\]]*\]/gi, '');
  const bajo = ' ' + sinCita.toLowerCase() + ' ';
  if (/[0-9]{10,}/.test(bajo.replace(/([0-9])[ .-](?=[0-9])/g, '$1'))) return true;
  if (/[^ @]+@[^ @]+\.[a-z]{2,}/.test(bajo)) return true;
  return /(^|\s)[A-Za-z0-9]{26,}(\s|$)/.test(sinCita);
}
const esperaLarga = esComprobante || datosFirmes(texto);
const espera = esperaLarga ? __ESPERA_OPERACION__ : __ESPERA_NORMAL__;

// El id de ESTE mensaje viaja con el texto. Hace falta despues para poder CITAR el mensaje
// en el que el cliente escribio sus datos bancarios cuando se le mande el comprobante.
let idMensaje = '';
try { idMensaje = $('Webhook Evolution API').first().json.body.data.key.id || ''; } catch(e){}

return [{ json: { jid, texto: texto || '', miTs, esComprobante, stickerVerificando, espera, idMensaje,
                  keyBuf: 'buf:'+jid, keyTok: 'tok:'+jid } }];
'@

$prepCode = $prepCode.Replace('__ESPERA_OPERACION__', [string]$SEGUNDOS_ESPERA_OPERACION)
$prepCode = $prepCode.Replace('__ESPERA_NORMAL__', [string]$SEGUNDOS_ESPERA)
$prepCode = $prepCode.Replace('__HORARIO_JK__', $horarioJs)

# ===================== CODIGO: TEXTO DIRECTO (mensajes de texto) =====================
$textoDirectoCode = @'
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

# ===================== CODIGO: AUDIO A BINARIO =====================
$toBinarioCode = @'
// Convierte el base64 del audio (de Evolution) en un archivo binario para Whisper.
const b64 = $json.base64;
if(!b64) return [{ json: { texto: '' } }];
return [{ json: { mimetype: $json.mimetype || '' }, binary: { data: { data: b64, mimeType: 'audio/ogg', fileName: 'audio.ogg' } } }];
'@

# ===================== CODIGO: TEXTO DE AUDIO (transcripcion) =====================
$textoAudioCode = @'
// Toma la transcripcion de Whisper como texto del mensaje.
let t='';
try { t = $('Transcribir Audio').item.json.text || ''; } catch(e){}
t = String(t).trim();
if(!t) t = 'El cliente envio una nota de voz que no se pudo entender. Pidele amablemente que la repita o escriba.';
return [{ json: { texto: String(t || '').normalize('NFKC') } }];
'@

# ===================== CODIGO: IMAGEN A BINARIO =====================
$toBinarioImgCode = @'
// Convierte el base64 de la imagen (de Evolution) en binario para GPT-4o vision.
const b64 = $json.base64;
if(!b64) return [{ json: { sinImagen: true } }];
return [{ json: { mimetype: $json.mimetype || 'image/jpeg' }, binary: { data: { data: b64, mimeType: $json.mimetype || 'image/jpeg', fileName: 'img.jpg' } } }];
'@

# ===================== PROMPT: LEER IMAGEN (vision) =====================
# El resumen va SIEMPRE con el mismo formato ("Monto: ..., Banco: ..., Fecha: ..., Referencia: ..."): de ahi
# sacan el monto y la referencia "Revisar Operacion" (repetidas), "Detectar Aprobación" y la cabecera de la
# cuenta en transferir. El 21/11 la IA escribio "$30,00 Transferencia a ..." sin "Monto:" y la cuenta salio
# sin precio.
$leerImagenPrompt = 'Esta imagen la envio un cliente de una casa de cambio de remesas por WhatsApp. Clasificala y responde SOLO en JSON valido sin texto extra: {"tipo": "comprobante|cuenta|otra", "resumen": "..."}. comprobante = recibo o captura de un pago/transferencia que el cliente hizo; el resumen DEBE ir asi, en una sola linea: "Monto: <monto con su moneda, ej. $30,00>, Moneda: <codigo de la moneda del monto: USD, VES, COP, PEN, BRL, MXN, CLP, ARS, UYU, PYG, BOB, CRC, DOP, CUP, GTQ, HNL, NIO, EUR o USDT; ojo que Colombia, Mexico, Chile, Argentina, Uruguay, Republica Dominicana y Cuba tambien usan el simbolo $>, Banco: <banco desde donde pago>, Fecha: <fecha>, Referencia: <numero de referencia, de comprobante o de transaccion>". cuenta = datos de una cuenta bancaria; el resumen asi: "Banco: <banco>, Cuenta: <numero>, Titular: <nombre>, Cedula: <cedula>". Si un dato no se ve, escribe "no visible". otra = cualquier otra cosa (resumen corto).'

# ===================== CODIGO: TEXTO DE IMAGEN =====================
$textoImagenCode = @'
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
try { keyId = $('Webhook Evolution API').first().json.body.data.key.id || ''; } catch(e){}
// Huella de la foto (el sha256 que manda WhatsApp). Si el cliente reenvia la MISMA foto, la huella
// es la misma: asi "Revisar Operacion" reconoce el deposito repetido aunque no se lea la referencia.
let huella='';
try {
  const im = $('Webhook Evolution API').first().json.body.data.message.imageMessage || {};
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
try { pie = String($('Webhook Evolution API').first().json.body.data.message.imageMessage.caption || '').trim(); } catch(e){ pie = ''; }
if (pie) texto += '\n' + pie;
return [{ json: { texto, tipoImagen: tipo, resumenImagen: resumen, imgKeyId: keyId } }];
'@

# ===================== CODIGO: FILTRAR ULTIMO =====================
$filtrarCode = @'
// Tras esperar 30s: solo continua si mi token sigue siendo el ultimo en Redis.
const miTs = $('Prep Debounce').item.json.miTs;
let actual = $json.tokenActual;
if (actual === undefined || actual === null) { try { actual = $('Redis Leer Token').item.json.tokenActual; } catch(e){} }
if (String(actual) !== String(miTs)) {
  return []; // llego un mensaje mas nuevo: esta ejecucion NO responde
}
return [{ json: { jid: $('Prep Debounce').item.json.jid } }];
'@

# ===================== CODIGO: COMBINAR MENSAJES =====================
$combinarCode = @'
// Junta todos los mensajes leidos de Redis en un solo texto, y conserva el id de cada uno.
// Los ids hacen falta para citar despues el mensaje donde el cliente puso su cuenta.
let arr = [];
try { arr = $('Redis Leer Mensajes').item.json.mensajes; } catch(e){}
if (!Array.isArray(arr)) arr = (arr === undefined || arr === null) ? [] : [arr];

// Cada entrada es {"id":"...","texto":"..."}. Se acepta tambien el formato VIEJO (texto
// pelado): al desplegar puede haber mensajes guardados antes del cambio y no se pueden
// perder.
const mensajes = [];
for (const x of arr){
  if (x === undefined || x === null) continue;
  if (typeof x === 'object'){ mensajes.push({ id: x.id || '', texto: String(x.texto || '') }); continue; }
  const cruda = String(x);
  let obj = null;
  try { obj = JSON.parse(cruda); } catch(e){}
  if (obj && typeof obj === 'object' && obj.texto !== undefined) mensajes.push({ id: obj.id || '', texto: String(obj.texto) });
  else mensajes.push({ id: '', texto: cruda });
}

const combinado = mensajes.map(m => m.texto).join('\n\n').trim() || '(sin texto)';
return [{ json: { mensajeCombinado: combinado, mensajes } }];
'@

# ===================== CODIGO: DETECTAR COMANDO ADMIN (modo mayor/detal) =====================
$detectarComandoAdminCode = @'
// Detecta si el remitente es ADMIN (Supabase perfiles_detal role=admin, nodo "Consultar Admins")
// y si escribio un comando de modo ("modo mayor" / "modo detal"). Un cliente normal JAMAS activa esto.
let jid = '';
try { jid = $('Webhook Evolution API').first().json.body.data.key.remoteJid || ''; } catch(e){}
const senderDigits = String(jid).replace(/\D/g,'');
// SOLO los numeros con role='admin' en Supabase pueden cambiar la tarifa. Si Supabase falla o no
// devuelve nada, esto queda en false y el comando NO se activa (falla del lado seguro).
// El match por "termina en" es para aguantar que el numero este guardado con o sin codigo de pais,
// pero se exigen al menos 8 digitos: si un admin tuviera el whatsapp mal cargado (ej. "0380"),
// sin ese minimo CUALQUIER cliente cuyo numero termine en 0380 pasaria por admin.
let esAdmin = false;
try {
  const admins = $('Consultar Admins').all().map(i => i.json).filter(a => a && a.whatsapp);
  esAdmin = admins.some(a => {
    const d = String(a.whatsapp||'').replace(/\D/g,'');
    if (!d || !senderDigits) return false;
    if (senderDigits === d) return true;
    if (d.length < 8 || senderDigits.length < 8) return false;
    return senderDigits.endsWith(d) || d.endsWith(senderDigits);
  });
} catch(e){}
let texto = '';
try { texto = String($('Combinar').item.json.mensajeCombinado || '').trim(); } catch(e){}

// Acepta: "mayor", "detal", "al mayor", "al detal", "modo mayor", "tarifa al detalle", etc.
// Se revisa LINEA POR LINEA (no el mensaje entero): por el debounce de 30s, si el admin manda
// "Modo detal" justo despues de otros mensajes, todo llega junto en un solo texto. Antes se exigia
// que el mensaje COMPLETO fuera el comando y por eso no lo reconocia.
// La linea tiene que ser SOLO el comando, para no secuestrar frases como "cuanto es al mayor para 5000".
const RX_COMANDO = /^\s*(?:modo\s+|tarifa\s+|precio\s+|pasame\s+|ponme\s+|dame\s+)?(?:al\s+|a\s+|en\s+)?(mayor|mayorista|detal|detalle)\s*[.!?]*\s*$/i;

// OJO: solo se toca el texto si el remitente ES admin. Un cliente puede responder "mayor" a una
// pregunta del bot, y si se le quitara esa linea el agente se quedaria sin saber que contesto.
const lineas = texto.split('\n');
const quedan = [];
let modoElegido = '';
for (const ln of lineas){
  const m = esAdmin ? ln.match(RX_COMANDO) : null;
  if (m){ modoElegido = /^may/i.test(m[1]) ? 'mayor' : 'detal'; continue; }  // se saca del texto
  quedan.push(ln);
}
const esComandoModo = !!(esAdmin && modoElegido);

// Lo que queda del mensaje despues de quitar el comando. Si sobra algo (una pregunta, un monto),
// el flujo sigue normal y se responde YA con la tarifa nueva, en vez de perder ese mensaje.
const textoLimpio = quedan.join('\n').replace(/\n{3,}/g, '\n\n').trim();
const soloComando = textoLimpio.length < 2;

return [{ json: { esAdmin, esComandoModo, modoElegido, soloComando, textoLimpio, jid } }];
'@

# ===================== CODIGO: CONFIRMAR MODO ADMIN (texto de respuesta) =====================
$confirmarModoAdminCode = @'
// Arma el mensaje corto de confirmacion tras guardar la preferencia de tarifa del admin.
const modo = String($('Detectar Comando Admin').item.json.modoElegido || '').toLowerCase();
const texto = modo === 'mayor' ? 'Listo, ahora te muestro tarifa MAYOR 👍' : 'Listo, ahora te muestro tarifa DETAL 👍';
return [{ json: { output: texto } }];
'@

# ===================== CODIGO: DETECTAR APROBACION (comprobante + cuenta) =====================
$detectarAprobacionCode = @'
// Detecta si hay comprobante + cuenta destino para APROBAR la operación y reenviar al grupo.
// De donde sale el texto: de "Revisar Operacion", que ya junto la captura y la cuenta aunque hayan
// llegado con minutos de diferencia (y que deja afuera las capturas repetidas). Si ese nodo no
// esta, del mensaje tal cual.
let ro = {};
try { ro = $('Revisar Operacion').first().json || {}; } catch(e){ ro = {}; }
const desdeOperacion = (ro.textoAprobar !== undefined);
// Fuera de horario la operacion NO se aprueba ni se pasa a transferir: queda 'en_espera' en Supabase
// ("Armar Filas Noche") y la publica al abrir el workflow "Liberar operaciones de la noche".
if (ro.enEspera) return [];
const original = desdeOperacion ? String(ro.textoAprobar || '') : String($('Combinar').item.json.mensajeCombinado || '');
const combinado = original.toLowerCase();
const tieneComprobante = combinado.includes('[el cliente envio un comprobante');
// Cuenta destino = lo que escribio el cliente, quitando las anotaciones internas del bot
// ([El cliente envio ...]). Esto va ANTES de buscar la cuenta, y es importante: la anotacion
// del comprobante dice "Banco: Banco Guayaquil", y como "banco" esta en la lista, el bot
// creia que el cliente habia mandado la cuenta cuando solo habia mandado la foto del pago.
// Paso el 19/11: aprobo la operacion y le mando al grupo "(el cliente no escribio la cuenta)".
let datosCuenta = original
  .replace(/\[El cliente envio un COMPROBANTE[^\]]*\]/gi, '')
  .replace(/\[El cliente envio una imagen que no parece[^\]]*\]/gi, '')
  .replace(/\[El cliente envio una imagen con una CUENTA bancaria\.?\s*Datos:\s*([^\]]*)\]/gi, 'Cuenta (imagen): $1')
  .replace(/\n{3,}/g, '\n\n')
  .trim();
// Como se reconoce que un texto trae los datos de una cuenta. Antes solo se buscaban palabras
// ("banco", "cuenta", "cedula"...) y el 20/11 un cliente mando "Venezuela / <cuenta de 20 digitos> /
// <titular> / <cedula> / 35$": ninguna de esas palabras, asi que el bot le contesto al cliente
// "Listo, recibido!" y NO paso nada al grupo. Ahora tambien cuenta:
//   - un numero largo (cuenta o telefono de pago movil), aunque venga con espacios o guiones
//   - un correo (Zelle, PayPal, Binance)
//   - el nombre de un banco o billetera conocidos
// Esto se aplica SOLO al texto que escribio el cliente: las anotaciones del bot ya se quitaron
// arriba, asi que "Banco: Banco Guayaquil" del comprobante no cuenta (el error del 19/11).
const cuentaPatterns = ['bancolombia', 'nequi', 'pago movil', 'banco', 'cuenta', 'numero de cuenta', 'titular', 'cedula', 'cc ', ' ci ', 'swift', 'interbank', 'binance', 'zelle'];
const NOMBRES_CUENTA = ['banesco', 'mercantil', 'provincial', 'bdv', 'bicentenario', 'bancamiga', 'bnc', 'exterior',
                        'pichincha', 'guayaquil', 'produbanco', 'pacifico', 'bolivariano', 'davivienda', 'daviplata',
                        'plin', 'yape', 'paypal', 'usdt', 'trc20', 'erc20', 'bep20', 'wallet', 'billetera', 'iban'];
function pareceCuenta(texto){
  const bajo = ' ' + String(texto || '').toLowerCase() + ' ';
  if (cuentaPatterns.some(p => bajo.indexOf(p) !== -1)) return true;
  // palabra entera, para que "plin" no salte con "complicado"
  if (NOMBRES_CUENTA.some(p => new RegExp('(^|[^a-z0-9])' + p + '([^a-z0-9]|$)').test(bajo))) return true;
  // 10 digitos seguidos o mas (se juntan los grupos: "0102 0000 0000 0001 2345")
  if (/[0-9]{10,}/.test(bajo.replace(/([0-9])[ .-](?=[0-9])/g, '$1'))) return true;
  // correo
  if (/[^ @]+@[^ @]+\.[a-z]{2,}/.test(bajo)) return true;
  return false;
}
const tieneCuenta = pareceCuenta(datosCuenta);
if (!tieneComprobante || !tieneCuenta) { return []; } // no hay ambos -> no aprobar
let jid='', nombre='', numero='';
try { jid = $('Webhook Evolution API').first().json.body.data.key.remoteJid || ''; nombre = String($('Webhook Evolution API').first().json.body.data.pushName || 'Cliente').normalize('NFKC'); numero = String(jid).replace(/\D/g,''); } catch(e){}

// Cual de los mensajes del cliente traia la cuenta. Sirve para que, cuando la operadora
// mande el comprobante del envio, el bot se lo pase al cliente CITANDO ese mensaje suyo y
// quede claro a que cuenta corresponde. Si no se encuentra, va vacio y no se cita nada.
let idCuenta = '';
try {
  const lista = desdeOperacion ? (ro.mensajesAprobar || []) : ($('Combinar').item.json.mensajes || []);
  for (const m of lista){
    const t = String((m && m.texto) || '').toLowerCase();
    if (t.indexOf('[el cliente envio') === 0) continue;   // es una nota del bot, no del cliente
    if (pareceCuenta(t)) idCuenta = m.id || idCuenta;
  }
} catch(e){}

// El nombre que se muestra en el grupo: primero el que Kelvin cargo en Supabase (es el que
// el reconoce), y si no hay, el que tenga puesto el cliente en WhatsApp.
let nombreMostrar = '';
try { nombreMostrar = String($('Solo Estos Numeros').first().json.nombreCargado || '').trim(); } catch(e){}
if (!nombreMostrar) nombreMostrar = nombre;

// Monto que la IA leyo en el comprobante del cliente. Sirve para avisar si las cuentas que
// mando no suman lo que deposito. Si no se pudo leer, queda en null y no se avisa nada.
let montoComprobante = null;
try {
  const trozo = original.match(/\[El cliente envio un COMPROBANTE[^\]]*\]/i);
  if (trozo){
    // Con la etiqueta "Monto:"; si la IA no la puso, el primer monto con "$" ("$30,00", caso del 21/11).
    const sinH = trozo[0].replace(/huella:\s*[0-9a-f]+/gi, '');
    const n = sinH.match(/monto[^0-9]{0,12}([0-9]+(?:[.,][0-9]{1,2})?)(?![0-9])/i)
           || sinH.match(/(?:\$|usd|us\$)[ \t]*([0-9]+(?:[.,][0-9]{1,2})?)(?![0-9])/i);
    if (n){ const v = parseFloat(n[1].replace(',', '.')); if (!isNaN(v)) montoComprobante = v; }
  }
} catch(e){}

// La foto que se publica en el grupo es la de la CAPTURA, aunque despues el cliente haya mandado
// otra imagen (ej. la foto de la cuenta).
const idImagen = desdeOperacion ? String(ro.idImagen || '') : '';

let modoTarifa = 'detal';
try { modoTarifa = $('Code in JavaScript').first().json.modo || 'detal'; } catch(e){}
let mensajesCombinar = [];
try { mensajesCombinar = $('Combinar').item.json.mensajes || []; } catch(e){}

return [{ json: { modoPublicar: 'aprobar', aprobado: true, jid, nombre, nombreMostrar, numero, datosCuenta, idCuenta,
                  montoComprobante, idImagen, mensajeCombinado: combinado,
                  mensajesAprobar: desdeOperacion ? (ro.mensajesAprobar || []) : undefined,
                  mensajes: mensajesCombinar, modoTarifa,
                  registro: desdeOperacion ? (ro.registro || null) : null } }];
'@

# ===================== CODIGO: CUENTAS POR BLOQUE (compartido) =====================
$bloquesCuentasJs = @'
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
'@

# ===================== CODIGO: SEPARAR CUENTAS (1 mensaje por cuenta) =====================
$separarCuentasCode = @'
// Una publicacion por cada cuenta que mando el cliente, con una cabecera que diga de quien
// es y por cuanto. Antes salia el bloque pelado y la operadora no sabia de quien era.
const ap = $('Detectar Aprobación').item.json;
const nombre = ap.nombreMostrar || ap.nombre || 'Cliente';

let lista = [], ro = {};
try {
  ro = $('Revisar Operacion').first().json || {};
  lista = (ro.mensajesAprobar !== undefined) ? (ro.mensajesAprobar || []) : ($('Combinar').item.json.mensajes || []);
} catch(e){ try { lista = $('Combinar').item.json.mensajes || []; } catch(e2){} }

__BLOQUES_CUENTAS__
return bloquesDeCuentas(lista, nombre, ap.datosCuenta, ap.idCuenta, montoDelDeposito(ro, ap.montoComprobante)).map(b => ({ json: b }));
'@
$separarCuentasCode = $separarCuentasCode.Replace('__BLOQUES_CUENTAS__', $bloquesCuentasJs)

# ===================== CODIGO: SEPARAR RESPUESTA (1 mensaje por cotizacion) =====================
$separarRespuestaCode = @'
// Separa la respuesta en mensajes: cada COTIZACION (lineas que terminan en "Tasa: X") = 1 mensaje aparte.
// Si la respuesta no tiene cotizaciones (no aparece "Tasa:"), va como un solo mensaje.
// Esto cumple lo que pidio el usuario: 1 cotizacion = 1 mensaje, sin depender del modelo.
const out = String($json.output || '').trim();
if (!out) return [{ json: $json }];
if (!/tasa\s*:/i.test(out)) return [{ json: $json }];
const lineas = out.split(/\n/).map(l => l.trim()).filter(l => l.length);
const mensajes = [];
let buf = [];
for (const l of lineas) {
  buf.push(l);
  if (/tasa\s*:/i.test(l)) { mensajes.push(buf.join('\n')); buf = []; }
}
if (buf.length) mensajes.push(buf.join('\n')); // cola sin "Tasa:" (preguntas/cierre)
if (mensajes.length <= 1) return [{ json: $json }];
return mensajes.map(m => ({ json: { ...$json, output: m } }));
'@

# ===================== CODIGO: REGISTRAR OPERACION (fila para Excel) =====================
$registrarOperacionCode = @'
// Arma UNA fila de reporte por cada operacion aprobada (comprobante + cuenta destino).
// Orden de columnas (debe coincidir con la tabla de Excel): Fecha, Cliente, Numero, CuentaDestino, Comprobante, Tipo.
function p2(n){ return String(n).padStart(2,'0'); }
const d = new Date(Date.now() - 5*3600000); // hora Ecuador (UTC-5)
const fecha = d.getUTCFullYear()+'-'+p2(d.getUTCMonth()+1)+'-'+p2(d.getUTCDate())+' '+p2(d.getUTCHours())+':'+p2(d.getUTCMinutes());
let a = {};
try { a = $('Detectar Aprobación').item.json || {}; } catch(e){}
const cliente = a.nombre || 'Cliente';
const numero = a.numero ? ('+'+a.numero) : '';
const cuenta = String(a.datosCuenta || '').replace(/\n+/g,' | ').trim();
let comprobante = '';
const mc = String(a.mensajeCombinado || '');
const m = mc.match(/datos leidos:\s*([^\]]*)\]/i);
if (m) comprobante = m[1].trim(); else comprobante = '(ver comprobante en grupo)';
let tipo = 'detal';
try { tipo = $('Code in JavaScript').first().json.modo || 'detal'; } catch(e){}
const fila = [fecha, cliente, numero, cuenta, comprobante, tipo];
return [{ json: { Fecha:fecha, Cliente:cliente, Numero:numero, CuentaDestino:cuenta, Comprobante:comprobante, Tipo:tipo, fila } }];
'@

# ===================== CODIGO: FILA DE UNA OPERACION (compartido) =====================
$filaJs = @'
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
'@

# ===================== CODIGO: ARMAR FILA SUPABASE (registro de la operacion) =====================
$armarFilaCode = @'
// ===== LAS FILAS PARA SUPABASE (tabla transacciones_detal_por_whatsapp), DE DIA =====
// UNA FILA POR CUENTA DESTINO: cada cuenta tiene su propio estado y pasa a 'enviada' cuando la
// operadora devuelve la foto de ESA cuenta (pedido de Kelvin, 20/11). Las cuentas de un mismo
// deposito comparten id_msg_captura. Corre DESPUES de publicar en el grupo, asi cada fila guarda el
// id de su publicacion (id_msgs_grupo): con eso "Marcar Enviada en Supabase" encuentra la fila.
// Los campos se llaman EXACTAMENTE como las columnas: el nodo siguiente los guarda tal cual.
__FILA_OPERACION__
const ap = $('Detectar Aprobación').first().json || {};
let ro = {};
try { ro = $('Revisar Operacion').first().json || {}; } catch(e){ ro = {}; }
const idDe = j => String((j && j.key && j.key.id) || (j && j.data && j.data.key && j.data.key.id) || '');
let separadas = [], enviadas = [], idFoto = '';
try { separadas = $('Separar Cuentas').all().map(i => i.json); } catch(e){}
try { enviadas = $('Enviar Cuenta Grupo').all().map(i => i.json); } catch(e){}
try { idFoto = idDe($('Enviar Imagen Grupo').first().json); } catch(e){}
const base = filaBase(ro.registro, ap.numero || ap.jid, ap.nombreMostrar || ap.nombre, ap.idImagen);
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
$armarFilaCode = $armarFilaCode.Replace('__FILA_OPERACION__', $filaJs)

# ===================== CODIGO: ARMAR FILAS NOCHE (operacion completa fuera de horario) =====================
$armarFilasNocheCode = @'
// ===== OPERACION COMPLETA FUERA DE HORARIO -> 'en_espera' =====
// De noche (o un domingo despues de las 2 pm) la operacion NO se pasa a transferir: se guarda aqui,
// una fila por cuenta destino, y el workflow "Liberar operaciones de la noche" la publica al abrir
// (9:05; el domingo 10:05), le manda al cliente el sticker de PEDIDO APROBADO y la pasa a
// 'en_proceso'. Pedido de Kelvin (20/11): "para no enredarnos en nuestra contabilidad y revisiones
// de la noche".
let ro = {};
try { ro = $('Revisar Operacion').first().json || {}; } catch(e){ ro = {}; }
if (!ro.enEspera) return [];
__BLOQUES_CUENTAS__
__FILA_OPERACION__
let jid = '', pushName = '', nombreCargado = '';
try { const d = $('Webhook Evolution API').first().json.body.data; jid = String(d.key.remoteJid || ''); pushName = String(d.pushName || '').trim(); } catch(e){}
try { nombreCargado = String($('Solo Estos Numeros').first().json.nombreCargado || '').trim(); } catch(e){}
const nombre = nombreCargado || pushName || 'Cliente';
const cuentasTexto = ((ro.registro || {}).cuentas || []).map(c => c.texto).join('\n\n');
const bloques = bloquesDeCuentas(ro.mensajesAprobar || [], nombre, cuentasTexto, '', montoDelDeposito(ro, null));
const base = filaBase(ro.registro, jid, nombre, ro.idImagen);
return bloques.map((b, i) => ({ json: Object.assign({}, base, {
  estado: 'en_espera',
  cuentas: [{ id: b.idCuenta || '', texto: b.texto, monto: b.monto }],
  id_msgs_grupo: [],
  fuera_de_horario: true,
  publicado_en: null,
  notas: bloques.length > 1 ? ('Cuenta ' + (i + 1) + ' de ' + bloques.length + ' del mismo deposito') : null
}) }));
'@
$armarFilasNocheCode = $armarFilasNocheCode.Replace('__BLOQUES_CUENTAS__', $bloquesCuentasJs).Replace('__FILA_OPERACION__', $filaJs)

# ===================== CODIGO: DETECTAR ASESOR (alerta) =====================
$detectarCode = @'
// Si la respuesta del bot indica que se necesita un asesor, arma la alerta. Si no, no hace nada.
const out = String($json.output || '');
if (!/asesor/i.test(out)) { return []; } // no es escalamiento -> no notificar
let jid = '';
try { jid = $('Webhook Evolution API').first().json.body.data.key.remoteJid || ''; } catch(e){}
const numero = String(jid).replace(/\D/g,'');
let msg = '';
try { msg = $('Combinar').item.json.mensajeCombinado || ''; } catch(e){}
const texto = '*Cliente necesita atencion*\n\nNumero: +' + numero + '\nhttps://wa.me/' + numero + '\n\nCliente escribio:\n' + msg + '\n\nBot respondio:\n' + out;
return [{ json: { alerta: texto, numeroCliente: numero } }];
'@

# ===================== CODIGO: SOLO ESTOS NUMEROS (filtro de pruebas) =====================
$soloEstosCode = @'
// ===== A QUIEN LE CONTESTA EL BOT, Y CUANDO =====
// Este nodo es lo PRIMERO despues del webhook y decide cuatro cosas:
//   1. Descartar mensajes viejos (Evolution los reenvia en rafaga al reconectarse).
//   2. Si escribio Kelvin, poner el chat en pausa (o leer sus comandos "bot on"/"bot off").
//   3. Si el chat esta en pausa, no contestar y avisar al grupo.
//   4. Si no, dejar pasar solo a los clientes autorizados.
//
// Todo lo que se descarta se descarta AQUI, antes de transcribir audios o leer imagenes
// con la IA, que es lo que cuesta plata.
//
// La salida lleva siempre un campo accionPausa, que el nodo "Router Pausa" usa para
// mandar el item por donde toca: seguir | pausar | reanudar | avisar.
const SOLO_ESTOS = __SOLO_ESTOS__;
const MODO_SOLO_CLIENTES = __MODO_SOLO_CLIENTES__;
const MINUTOS_VIEJO = __MINUTOS_VIEJO__;
const MINUTOS_PAUSA = __MINUTOS_PAUSA__;
const HORAS_PAUSA_MANUAL = __HORAS_PAUSA_MANUAL__;
const MINUTOS_ENTRE_AVISOS = __MINUTOS_ENTRE_AVISOS__;
const PALABRAS_AVISO = __PALABRAS_AVISO__;

// OJO: el mensaje NO viene en $input. Antes de este nodo hay varias consultas a Supabase y
// a Redis, y esos nodos devuelven SUS filas: eso es lo que trae $input aca. El mensaje de
// WhatsApp hay que ir a buscarlo al webhook.
let entran = [];
try { entran = $('Webhook Evolution API').all(); } catch(e){ entran = $input.all(); }

// ===== 1) MENSAJES VIEJOS =====
// Cuando Evolution se reconecta despues de estar caido manda de golpe todo lo que quedo
// pendiente, incluso de hace dias. Sin esto el bot contesta conversaciones viejas.
// Un mensaje sin fecha NO se descarta: ante la duda es mejor contestar de mas.
if (MINUTOS_VIEJO > 0){
  const ahora = Date.now() / 1000;
  entran = entran.filter(it => {
    let ts = 0;
    try { ts = Number(it.json.body.data.messageTimestamp) || 0; } catch(e){}
    if (!ts) return true;
    return ((ahora - ts) / 60) <= MINUTOS_VIEJO;
  });
}
if (!entran.length) return [];

// ===== 2) QUIEN ESCRIBIO =====
const dat  = (((entran[0] || {}).json || {}).body || {}).data || {};
const llave = dat.key || {};
const jid  = String(llave.remoteJid || '');
const esGrupo = jid.indexOf('@g.us') !== -1;
const clave = 'pausaBot:' + jid;

let texto = '';
try {
  const m = dat.message || {};
  texto = String(m.conversation || (m.extendedTextMessage || {}).text || '').trim();
} catch(e){}
const cmd = texto.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^a-z]/g,'');

// Como se sabe que escribio KELVIN y no el propio bot: los dos llegan con fromMe=true, pero
// el id es distinto. Los que manda el bot (libreria Baileys) empiezan por "3EB0"; los que
// se escriben desde el telefono o WhatsApp Web son mas largos y empiezan por otra cosa.
// Si algun dia Baileys cambia eso, el bot se pausaria solo al responder: se destraba
// escribiendo "bot on" en ese chat.
const loEscribioElBot = String(llave.id || '').indexOf('3EB0') === 0;

// ===== MAYOR (FASE 1): GRUPOS DE CLIENTES QUE EL BOT SOLO ESCUCHA =====
// Si el chat es un grupo de la tabla grupos_mayor, el mensaje (de quien sea: el cliente, su operador,
// Kelvin o la operadora) se le pasa al workflow "Mayor: escuchar y registrar" y ahi termina: NO se
// contesta, NO se pausa, NO se publica nada. Va ANTES del bloque de fromMe y de la entrega del
// comprobante, que tratan los grupos del detal (esos siguen exactamente igual). Si la tabla no se pudo
// leer, el grupo se ignora como siempre.
// El grupo donde se publican los pedidos del DETAL (transferir) y el de avisos NUNCA se enrutan al mayor,
// aunque alguien los cargue por error en grupos_mayor: la entrega del comprobante del detal depende de ellos.
const GRUPOS_DEL_DETAL = __GRUPOS_DEL_DETAL__;
if (esGrupo && GRUPOS_DEL_DETAL.indexOf(jid) === -1){
  let grupoMayor = null;
  try { grupoMayor = $('Grupos Mayor').all().map(i => i.json).find(g => g && g.grupo_jid === jid && g.activo !== false) || null; } catch(e){}
  if (grupoMayor) return [{ json: { accionPausa: 'mayor', grupo: grupoMayor, data: dat } }];
}

// ===== LA OPERADORA DEVUELVE EL COMPROBANTE DEL ENVIO =====
// En el grupo de operaciones, cuando alguien RESPONDE (cita) una publicacion del bot con una
// foto, esa foto es el comprobante de la transferencia y hay que hacersela llegar al cliente.
//
// Quien autoriza es el propio Redis: mas adelante se busca el mensaje citado en la lista de
// publicaciones del bot, y si no esta, no pasa nada. Por eso aqui no hace falta comprobar de
// que grupo viene ni quien escribio: citar cualquier otra cosa no dispara nada.
//
// Esto va ANTES del bloque de fromMe a proposito: la foto la puede mandar una operadora
// (fromMe false) o el propio Kelvin (fromMe true), y mas abajo todo lo de grupos se descarta.
const msg = dat.message || {};
const img = msg.imageMessage || null;
let citado = '';
try {
  const ctx = dat.contextInfo || (img && img.contextInfo) || null;
  citado = String((ctx && ctx.stanzaId) || '');
} catch(e){}

// Quien lo mando dentro del grupo. Sirve para recordarle SU ultima foto y no confundirla
// con la de otra operadora.
const quien = String(llave.participant || llave.participantAlt || (llave.fromMe ? 'yo' : '')) || 'alguien';
const claveFoto = 'ultimaFoto:' + jid + ':' + quien;

if (esGrupo && img && citado){
  // Caso normal: la foto va citando la publicacion del bot.
  return [{ json: { accionPausa: 'entregar', stanzaId: citado,
                    claveGrupoMsg: 'grupoMsg:' + citado,
                    claveEntregado: 'entregado:' + citado,
                    claveFoto: claveFoto,
                    idFoto: String(llave.id || ''), jidGrupo: jid } }];
}
if (esGrupo && img && !citado){
  // Foto suelta: se guarda por si despues cita con un punto.
  return [{ json: { accionPausa: 'recordarFoto', claveFoto: claveFoto,
                    idFoto: String(llave.id || ''), jidGrupo: jid } }];
}
// ===== LA OPERADORA PIDE VERIFICAR LOS DATOS DE UNA CUENTA (pedido de Kelvin, 23/11) =====
// Citando la publicacion de una cuenta con "Verificar datos", "corregir dato", "datos malos"... el bot le
// pide al cliente que revise y corrija esos datos, y cuando los manda corregidos se los vuelve a pasar a
// transferir. Va ANTES de la entrega con texto corto: un "Verificar" (9 letras) se tomaba como "entregar
// la foto". Solo cuenta si lo citado es TEXTO (la publicacion de una cuenta, no la foto de la captura);
// que sea una publicacion del bot lo autoriza Redis, igual que la entrega.
const RX_VERIFICAR = /verific|correg|corrig|dato.{0,12}(mal|errad|incorrect)|(mal|errad|incorrect).{0,12}dato|no coincide|rebot/i;
if (esGrupo && !img && citado && RX_VERIFICAR.test(texto)){
  let citadoTexto = '';
  try {
    const ctx = dat.contextInfo || (msg.extendedTextMessage && msg.extendedTextMessage.contextInfo) || {};
    const q = ctx.quotedMessage || {};
    citadoTexto = String(q.conversation || (q.extendedTextMessage || {}).text || '');
  } catch(e){}
  if (citadoTexto.trim()){
    return [{ json: { accionPausa: 'verificar', stanzaId: citado, claveGrupoMsg: 'grupoMsg:' + citado,
                      nota: texto.slice(0, 200), citadoTexto: citadoTexto.slice(0, 2000),
                      idNota: String(llave.id || ''), jidGrupo: jid } }];
  }
  return [];      // "verificar" citando la foto de la captura: NUNCA es "entregar la foto" (eso lo ve Kelvin)
}
if (esGrupo && !img && citado){
  // Cito con texto. Solo cuenta si es algo CORTO ("." , "ok", "listo"): asi, discutir sobre
  // un pedido citandolo no dispara una entrega por accidente. La foto sale de la recordada.
  if (texto.length <= 12){
    // "forzar" (Fase B): respondiendo el aviso de "este comprobante NO cuadra", se manda igual.
    return [{ json: { accionPausa: 'entregar', stanzaId: citado,
                      claveGrupoMsg: 'grupoMsg:' + citado,
                      claveEntregado: 'entregado:' + citado,
                      claveFoto: claveFoto,
                      idFoto: '', jidGrupo: jid, forzar: /forzar/i.test(texto) } }];
  }
}

if (llave.fromMe === true){
  // En los grupos no hay nada que pausar: el bot no contesta en grupos.
  if (esGrupo) return [];
  if (cmd === 'boton')  return [{ json: { accionPausa: 'reanudar', clave: clave, jid: jid } }];
  if (cmd === 'botoff') return [{ json: { accionPausa: 'pausar', clave: clave, jid: jid,
                                          segundos: HORAS_PAUSA_MANUAL * 3600, motivo: 'manual' } }];
  if (loEscribioElBot) return [];   // fue el propio bot: no se pausa a si mismo
  // Escribio Kelvin a mano -> se pausa el chat. El TTL se renueva con cada mensaje suyo,
  // asi que la hora cuenta desde el ULTIMO, no desde el primero.
  return [{ json: { accionPausa: 'pausar', clave: clave, jid: jid,
                    segundos: MINUTOS_PAUSA * 60, motivo: 'auto' } }];
}

// ===== 2b) REACCIONES =====
// Cuando un cliente reacciona con un emoji a un mensaje, WhatsApp lo manda como un mensaje mas
// pero SIN texto. El bot lo trataba como un mensaje vacio y contestaba "Hola, en que puedo
// ayudarte hoy?" (paso el 20/11 con un cliente, justo despues de mandar su comprobante). Una
// reaccion no es una pregunta, asi que se descarta aqui. Las que hace Kelvin no llegan hasta
// este punto: se tratan arriba, en el bloque de fromMe.
if (msg.reactionMessage) return [];

// ===== 2c) STICKERS, UBICACIONES Y MENSAJES BORRADOS =====
// Tampoco traen texto. La revision de los chats (20/11) encontro 102 stickers y 16 ubicaciones de
// clientes: el bot los tomaba por mensajes vacios y contestaba "Hola, en que puedo ayudarte?".
// Los de Kelvin no llegan hasta aqui (bloque de fromMe).
if (msg.stickerMessage || msg.locationMessage || msg.liveLocationMessage || msg.protocolMessage) return [];

// ===== 3) A QUIEN SE LE CONTESTA =====
function mismoNumero(a, b){
  const x = String(a || '').replace(/\D/g, '');
  const y = String(b || '').replace(/\D/g, '');
  if (!x || !y) return false;
  if (x === y) return true;
  if (x.length < 8 || y.length < 8) return false;
  return x.endsWith(y) || y.endsWith(x);
}

// Saca los numeros de una tabla. null = NO se pudo leer (nodo caido, credencial mala),
// que es distinto de que la tabla este vacia.
function numerosDe(nodo){
  let items;
  try { items = $(nodo).all(); } catch(e){ return null; }
  if (items.some(it => it && it.json && it.json.error !== undefined)) return null;
  return items
    .filter(it => it && it.json && it.json.whatsapp && it.json.activo !== false)
    .map(it => String(it.json.whatsapp));
}

// El nombre que Kelvin le puso al cliente en Supabase, para que el agente lo salude por su
// nombre. Se busca aunque el filtro este apagado: no tiene que ver con dejar pasar o no.
function nombreCargado(j){
  for (const nodo of ['Clientes Detal Permitidos', 'Clientes Mayor Permitidos']){
    let items;
    try { items = $(nodo).all(); } catch(e){ continue; }
    for (const it of items){
      const f = (it && it.json) || {};
      if (f.whatsapp && f.nombre && mismoNumero(j, f.whatsapp)) return String(f.nombre).trim();
    }
  }
  return '';
}

// De que tabla salio el cliente: eso decide su tarifa.
//   clientes_bot_mayor -> mayor   |   clientes_bot_detal -> detal
// Si por error esta cargado en LAS DOS, gana DETAL. Darle tarifa de mayorista a un cliente
// de detal es plata perdida; al reves solo es un cliente que reclama y se corrige.
function tarifaCargada(j){
  let enDetal = false, enMayor = false;
  for (const par of [['Clientes Detal Permitidos','detal'], ['Clientes Mayor Permitidos','mayor']]){
    let items;
    try { items = $(par[0]).all(); } catch(e){ continue; }
    for (const it of items){
      const f = (it && it.json) || {};
      if (f.whatsapp && f.activo !== false && mismoNumero(j, f.whatsapp)){
        if (par[1] === 'detal') enDetal = true; else enMayor = true;
      }
    }
  }
  if (enDetal) return 'detal';
  if (enMayor) return 'mayor';
  return '';
}

function marcar(it){
  let j = '';
  try { j = String(it.json.body.data.key.remoteJid || ''); } catch(e){ return it; }
  const n = nombreCargado(j);
  if (n) it.json.nombreCargado = n;
  const t = tarifaCargada(j);
  if (t) it.json.tarifaCargada = t;
  it.json.accionPausa = 'seguir';
  return it;
}

// null = no hay ningun filtro prendido -> pasa todo.
// [] = el filtro SI esta prendido pero no hay nadie cargado -> no pasa nadie.
let permitidos = null;
if (SOLO_ESTOS.length){
  permitidos = SOLO_ESTOS;                       // modo prueba: manda el codigo
} else if (MODO_SOLO_CLIENTES){
  const detal = numerosDe('Clientes Detal Permitidos');
  const mayor = numerosDe('Clientes Mayor Permitidos');
  const appDetal = numerosDe('Perfiles Detal App');
  const appMayor = numerosDe('Perfiles Mayor App');
  // Si CUALQUIERA de las cuatro no se pudo leer, se le contesta a todos: no sabemos quien
  // esta autorizado, y dejar gente afuera en silencio es peor que contestar de mas.
  if (detal === null || mayor === null || appDetal === null || appMayor === null){
    return entran.map(marcar);
  }
  permitidos = detal.concat(mayor, appDetal, appMayor);
}

let pasan;
if (permitidos === null){
  pasan = entran.slice();                        // ningun filtro prendido
} else {
  pasan = [];
  for (const it of entran){
    let j = '';
    try { j = String(it.json.body.data.key.remoteJid || ''); } catch(e){}
    if (j.indexOf('@g.us') !== -1) continue;     // un grupo no es un numero de persona
    if (permitidos.some(n => mismoNumero(j, n))) pasan.push(it);
  }
}
if (!pasan.length) return [];

// ===== 4) LA PAUSA =====
// Llego hasta aca: el bot le habria contestado. Si Kelvin esta atendiendo ese chat, no lo
// hace, pero avisa al grupo para que el cliente no quede en el aire.
let enPausa = false;
try { enPausa = !!$('Redis Leer Pausa').first().json.pausaBot; } catch(e){}
if (enPausa && !esGrupo){
  // No se avisa de TODO lo que escriba. Si esta conversando de cosas personales con Kelvin,
  // el grupo no tiene por que enterarse. Solo si menciona algo del negocio.
  const limpio = texto.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');
  const esDelNegocio = PALABRAS_AVISO.some(w => limpio.indexOf(w) !== -1);
  if (!esDelNegocio) return [];

  // Y aunque lo sea, se avisa UNA sola vez por rato. Sin esto, un cliente que escribe seis
  // veces seguidas genera seis avisos.
  let yaSeAviso = false;
  try { yaSeAviso = !!$('Redis Leer Aviso').first().json.avisoPausa; } catch(e){}
  if (yaSeAviso) return [];

  const quien = String(dat.pushName || '').trim() || jid.split('@')[0];
  const recorte = texto.length > 200 ? (texto.slice(0, 200) + '...') : texto;
  const aviso = 'El bot NO le contesto a ' + quien + ' (+' + jid.split('@')[0] + ')'
    + ' porque estas atendiendo ese chat.\n\nEscribio:\n"' + (recorte || '(sin texto)') + '"'
    + '\n\nSi quieres que el bot siga atendiendolo, escribe "bot on" en ese chat.';
  return [{ json: { accionPausa: 'avisar', jid: jid, aviso: aviso,
                    claveAviso: 'avisoPausa:' + jid, segundosAviso: MINUTOS_ENTRE_AVISOS * 60 } }];
}

return pasan.map(marcar);
'@
# .Replace() literal, NO -replace: el codigo de arriba trae $ y llaves que -replace
# interpretaria como grupos con nombre.
$soloEstosCode = $soloEstosCode.Replace('__MODO_SOLO_CLIENTES__', $MODO_SOLO_CLIENTES_JS)
$soloEstosCode = $soloEstosCode.Replace('__MINUTOS_VIEJO__', [string]$MINUTOS_MENSAJE_VIEJO)
$soloEstosCode = $soloEstosCode.Replace('__MINUTOS_PAUSA__', [string]$MINUTOS_PAUSA)
$soloEstosCode = $soloEstosCode.Replace('__HORAS_PAUSA_MANUAL__', [string]$HORAS_PAUSA_MANUAL)
$soloEstosCode = $soloEstosCode.Replace('__MINUTOS_ENTRE_AVISOS__', [string]$MINUTOS_ENTRE_AVISOS)
$soloEstosCode = $soloEstosCode.Replace('__PALABRAS_AVISO__', $PALABRAS_AVISO_JS)
$GRUPOS_DEL_DETAL_JS = '[' + ((@($GRUPO_OPERACIONES, $GRUPO_AVISOS) | ForEach-Object { "'" + $_ + "'" }) -join ',') + ']'
$soloEstosCode = $soloEstosCode.Replace('__GRUPOS_DEL_DETAL__', $GRUPOS_DEL_DETAL_JS)
# .Replace() literal, NO -replace: el codigo de arriba trae $ y llaves que -replace
# interpretaria como grupos con nombre.
$soloEstosCode = $soloEstosCode.Replace('__MODO_SOLO_CLIENTES__', $MODO_SOLO_CLIENTES_JS)
$soloEstosCode = $soloEstosCode.Replace('__MINUTOS_VIEJO__', [string]$MINUTOS_MENSAJE_VIEJO)
$soloEstosCode = $soloEstosCode.Replace('__SOLO_ESTOS__', $SOLO_ESTOS_JS)

# ===================== CODIGO: REVISAR PEDIDO (entrega del comprobante) =====================
$revisarPedidoCode = @'
// La operadora respondio una publicacion del grupo. Aqui se decide que hacer.
//
// Se entrega SOLO si el mensaje que cito es una publicacion que hizo el bot: esa es toda la
// autorizacion. Si cito cualquier otra cosa, no hay nada guardado y no pasa nada, en silencio.
const base = $('Solo Estos Numeros').first().json;

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

# ===================== CODIGO: REVISAR MONTOS (cuentas vs comprobante) =====================
$revisarMontosCode = @'
// Avisa en el grupo si los montos de las cuentas no suman lo que dice el comprobante.
// Solo avisa cuando esta SEGURO: si no se pudo leer el monto del comprobante, o si alguna
// cuenta no traia monto, se queda callado. Una falsa alarma cada dos por tres haria que
// nadie le haga caso.
let cuentas = [];
try { cuentas = $('Separar Cuentas').all().map(i => i.json); } catch(e){}
if (cuentas.length < 2) return [];                       // con una sola cuenta no hay nada que sumar

let total = null;
try { total = $('Detectar Aprobación').first().json.montoComprobante; } catch(e){}
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

# ===================== CODIGO: REVISAR OPERACION (captura + cuenta en cualquier orden) =====================
$revisarOperacionCode = @'
// ===== LA OPERACION DEL CLIENTE: CAPTURA + CUENTA, EN EL ORDEN EN QUE LLEGUEN =====
// Antes el bot solo juntaba lo que llegaba dentro de su espera (30 s, o 60 s si llegaba una
// captura). El 20/11 una clienta mando la cuenta y 14 minutos despues dos capturas del mismo
// Zelle: el bot le contesto dos veces "Listo, recibido!" y NO paso nada al grupo.
//
// Ahora el bot RECUERDA, por cliente, lo que le falta (en Redis, clave 'op:<chat>'):
//   - llega la cuenta sola       -> la guarda y le pide la captura
//   - llega la captura sola      -> la guarda y le pide la cuenta
//   - llega lo que faltaba       -> junta las dos y "Detectar Aprobacion" las pasa al grupo
//   - llega una captura repetida -> NO la vuelve a pasar y le avisa al cliente
//
// Este nodo no manda nada: decide. Al agente le deja una nota con lo que tiene que contestar
// (asi lo que se le dice al cliente y lo que se pasa al grupo no se pueden contradecir), y a
// "Detectar Aprobacion" el texto con la captura y la cuenta ya juntas.
const MINUTOS_PENDIENTE = __MINUTOS_PENDIENTE__;
const MINUTOS_MISMO_DEPOSITO = __MINUTOS_MISMO_DEPOSITO__;
const HORAS_RECORDAR = __HORAS_RECORDAR__;
const MINUTOS_ENTRE_STICKERS = __MINUTOS_STICKER_GRACIAS__;
const HORAS_ENTRE_NOMBRES = __HORAS_NOMBRE__;
const DIAS_ULTIMA_OPERACION = __DIAS_ULTIMA_OPERACION__;
const MARGEN_CUADRE = __MARGEN_CUADRE__;
const HORAS_CORREGIR = __HORAS_CORREGIR__;
const ahora = Date.now();
__HORARIO_JK__
const hor = horarioDe(ahora);

let base = {};
try { base = $('Code in JavaScript').first().json || {}; } catch(e){}
let mensajes = [];
try { mensajes = $('Combinar').first().json.mensajes || []; } catch(e){}
if (!Array.isArray(mensajes)) mensajes = [];

// Lo que ya se sabia de este cliente.
let op = {};
try {
  const raw = $('Redis Leer Operacion').first().json.operacion;
  if (raw) op = (typeof raw === 'string') ? JSON.parse(raw) : raw;
} catch(e){ op = {}; }
if (!op || typeof op !== 'object') op = {};
// Lo pendiente vale MINUTOS_PENDIENTE. Si llego fuera de horario, vale hasta MINUTOS_PENDIENTE
// despues de abrir (una captura de las 11 pm espera la cuenta hasta las 11 am). Se guarda en 'hasta'.
const vigente = x => !!x && typeof x.ts === 'number'
  && ((typeof x.hasta === 'number') ? ahora <= x.hasta : (ahora - x.ts) <= MINUTOS_PENDIENTE * 60000);
function venceEn(ts){
  const h = horarioDe(ts), base = ts + MINUTOS_PENDIENTE * 60000;
  return h.abierto ? base : Math.max(base, h.proximaApertura + MINUTOS_PENDIENTE * 60000);
}
const cuentaGuardada = (op.cuenta && vigente(op.cuenta) && Array.isArray(op.cuenta.mensajes)) ? op.cuenta.mensajes : [];
const capturasGuardadas = Array.isArray(op.capturas) ? op.capturas.filter(vigente) : [];
const hechos = Array.isArray(op.hechos) ? op.hechos.filter(h => h && (ahora - (h.ts || 0)) <= HORAS_RECORDAR * 3600000) : [];

// ---------- las operaciones ya registradas en Supabase (tabla transacciones_detal_por_whatsapp) ----------
// Las ultimas de este cliente, la mas reciente primero. Sirven para reconocer una captura repetida
// aunque sea de hace semanas (Redis solo recuerda 48 h), para "la misma cuenta de siempre" y para
// contestar "¿ya llego?". Si Supabase no responde, todo sigue como antes.
let historial = [];
try { historial = $('Consultar Operaciones WhatsApp').all().map(i => i.json).filter(r => r && r.id && !r.error); } catch(e){ historial = []; }
historial.sort((a, b) => (Date.parse(b.creado) || 0) - (Date.parse(a.creado) || 0));
const listaDe = v => { if (Array.isArray(v)) return v; try { const x = JSON.parse(v); return Array.isArray(x) ? x : []; } catch(e){ return []; } };

// ---------- que es una cuenta (lo mismo que usa "Detectar Aprobacion") ----------
const cuentaPatterns = ['bancolombia', 'nequi', 'pago movil', 'banco', 'cuenta', 'numero de cuenta', 'titular', 'cedula', 'cc ', ' ci ', 'swift', 'interbank', 'binance', 'zelle'];
const NOMBRES_CUENTA = ['banesco', 'mercantil', 'provincial', 'bdv', 'bicentenario', 'bancamiga', 'bnc', 'exterior',
                        'pichincha', 'guayaquil', 'produbanco', 'pacifico', 'bolivariano', 'davivienda', 'daviplata',
                        'plin', 'yape', 'paypal', 'usdt', 'trc20', 'erc20', 'bep20', 'wallet', 'billetera', 'iban'];
function pareceCuenta(texto){
  const bajo = ' ' + String(texto || '').toLowerCase() + ' ';
  if (cuentaPatterns.some(p => bajo.indexOf(p) !== -1)) return true;
  if (NOMBRES_CUENTA.some(p => new RegExp('(^|[^a-z0-9])' + p + '([^a-z0-9]|$)').test(bajo))) return true;
  if (/[0-9]{10,}/.test(bajo.replace(/([0-9])[ .-](?=[0-9])/g, '$1'))) return true;
  if (/[^ @]+@[^ @]+\.[a-z]{2,}/.test(bajo)) return true;
  return false;
}

// DATOS FIRMES: un numero largo, un correo o una direccion de billetera. Es lo unico que basta,
// SIN captura de por medio, para tomar un texto como la cuenta destino del cliente. Las palabras
// ("banco", "cuenta", "cedula") no alcanzan solas: "me pasas la cuenta para depositar?" es una
// pregunta, no una cuenta, y no puede dispararle al agente una nota falsa de "ya paso su cuenta".
function datosFirmes(texto){
  const t = String(texto || '');
  const bajo = ' ' + t.toLowerCase() + ' ';
  if (/[0-9]{10,}/.test(bajo.replace(/([0-9])[ .-](?=[0-9])/g, '$1'))) return true;
  if (/[^ @]+@[^ @]+\.[a-z]{2,}/.test(bajo)) return true;
  return /(^|\s)[A-Za-z0-9]{26,}(\s|$)/.test(t);
}

// Las notas que escribe el bot no son del cliente. Con las citas hay que fijarse: si el cliente
// cita el mensaje donde el bot le mando NUESTRA cuenta del dia (o cualquier mensaje sin datos),
// eso no es su cuenta destino y se quita. Pero si cita SU PROPIO mensaje con sus datos y agrega
// lo que faltaba (paso el 20/11: cito "cedula / telefono / 0102 / 10$" y escribio "Banco
// Venezuela / Titular ..."), lo citado SI es parte de su cuenta y se conserva.
function textoDelCliente(t){
  return String(t || '')
    .replace(/\[El cliente envio un COMPROBANTE[^\]]*\]/gi, '')
    .replace(/\[El cliente envio una imagen que no parece[^\]]*\]/gi, '')
    .replace(/\[el cliente respondio citando[^"\]]*"([^\]]*)"\]/gi, (todo, citado) => {
      const d = datosDe(citado);
      return (d.length && !d.every(x => NUESTROS.has(x))) ? citado : '';
    })
    .replace(/\[el cliente respondio citando[^\]]*\]/gi, '')
    .trim();
}

// Si lo que escribio son NUESTRAS cuentas (las del dia, donde el cliente paga), no es su cuenta
// destino. Pasa cuando el cliente escribe "ya deposite en la 2205061301".
function datosDe(t){
  const s = String(t || '').toLowerCase();
  const nums = s.replace(/([0-9])[ .-](?=[0-9])/g, '$1').match(/[0-9]{8,}/g) || [];
  const correos = s.match(/[^ @\n]+@[^ @\n]+\.[a-z]{2,}/g) || [];
  return nums.concat(correos);
}
const NUESTROS = new Set(datosDe((Array.isArray(base.cuentas) ? base.cuentas : []).map(c => (c && c.Datos) || '').join('\n')));
function esCuentaNuestra(t){
  const d = datosDe(t);
  return d.length > 0 && d.every(x => NUESTROS.has(x));
}

// ---------- capturas: monto, referencia y huella, para reconocer las repetidas ----------
// La huella es hexadecimal y trae numeros: hay que quitarla antes de buscar el monto o la
// referencia, o "Referencia: no visible Huella: aaaa1111..." se leia como referencia 1111.
function sinHuella(t){ return String(t || '').replace(/huella:\s*[0-9a-f]+/gi, ''); }
function numero(s){
  s = String(s || '').replace(/[.,]+$/, '');
  const ult = Math.max(s.lastIndexOf('.'), s.lastIndexOf(','));
  if (ult === -1) return parseFloat(s);
  const dec = s.slice(ult + 1);
  if (dec.length === 3) return parseFloat(s.replace(/[.,]/g, ''));   // 1.500 = mil quinientos
  return parseFloat(s.slice(0, ult).replace(/[.,]/g, '') + '.' + dec);
}
function montoDe(t){
  // Con la etiqueta "Monto:"; si la IA no la puso, el primer monto con "$" o "USD" ("$30,00", caso del 21/11).
  const x = sinHuella(t);
  const m = x.match(/monto[^0-9]{0,15}([0-9][0-9.,]*)/i)
         || x.match(/(?:\$|usd|us\$)[ \t]*([0-9][0-9.,]*)/i)
         || x.match(/([0-9][0-9.,]*)[ \t]*(?:\$|usd|d[oó]lares)/i);
  if (!m) return null;
  const v = numero(m[1]);
  return isNaN(v) ? null : v;
}
function refDe(t){
  const m = sinHuella(t).match(/(referencia|ref\.?|transacci[oó]n|documento|comprobante|confirmaci[oó]n|operaci[oó]n|n[uú]mero|nro\.?)[^0-9\]]{0,25}([0-9]{4,})/i);
  return m ? m[2] : '';
}
function huellaDe(t){
  const m = String(t).match(/huella:\s*([0-9a-f]{8,})/i);
  return m ? m[1].toLowerCase() : '';
}
// Un dato de lo que leyo la IA: "Banco: Banesco, ..." -> 'Banesco'.
function campoDe(t, claves){
  const m = sinHuella(t).match(new RegExp('(?:' + claves + ')\\s*:\\s*([^,\\]]+)', 'i'));
  return m ? m[1].trim() : '';
}
function normal(x){
  return String(x || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, ' ').trim();
}
// Palabras demasiado comunes para decir que dos bancos o dos nombres son el mismo.
const PALABRAS_COMUNES = ['banco', 'bank', 'banking', 'universal', 'nacional', 'credito', 'cuenta', 'ahorro', 'ahorros',
                          'corriente', 'digital', 'secure', 'transfer', 'pago', 'movil', 'de', 'del', 'la', 'los', 'las', 'the'];
// true = hablan de lo mismo, false = se contradicen, null = falta alguno de los dos y no se puede comparar.
function parecidos(x, y){
  x = normal(x); y = normal(y);
  if (!x || !y) return null;
  if (x === y || x.indexOf(y) !== -1 || y.indexOf(x) !== -1) return true;
  const ys = y.split(' ');
  return x.split(' ').some(w => w.length >= 4 && PALABRAS_COMUNES.indexOf(w) === -1 && ys.indexOf(w) !== -1);
}
// La MONEDA del deposito: 'USD', 'VES', 'COP', 'PEN', 'BRL', 'MXN', 'CLP', 'ARS', 'UYU', 'PYG', 'BOB', 'CRC', 'DOP',
// 'CUP', 'GTQ', 'HNL', 'NIO', 'EUR', 'USDT' (las de la hoja de tasas), o '' si no se sabe. La IA la escribe en
// "Moneda: USD" (desde el 23/11); en las capturas leidas antes se deduce del monto. El "$" solo no basta:
// Colombia, Mexico, Chile, Argentina, Uruguay, Dominicana y Cuba tambien lo usan, asi que un banco de esos
// paises manda sobre el "$". Ante la duda, '' (y entonces no se compara con las cuentas).
const MONEDA_DEL_BANCO = [
  ['COP', /bancolombia|nequi|daviplata|davivienda|bogota/i],
  ['BOB', /mercantil santa cruz|banco uni[oó]n|bancosol/i],
  ['VES', /banesco|mercantil|provincial|venezuela|\bbdv\b|bicentenario|bancamiga|\bbnc\b|tesoro|banplus|bancaribe|exterior/i],
  ['PEN', /\bbcp\b|interbank|yape|plin/i],
  ['BRL', /nubank|itau|bradesco|\bpix\b/i],
  ['CLP', /bancoestado|banco estado/i],
  ['ARS', /mercado ?pago/i],
  ['MXN', /banorte|azteca/i],
  ['UYU', /\bbrou\b/i],
  ['PYG', /\bueno\b|banco continental|visi[oó]n banco/i],
  ['CRC', /\bbcr\b|banco nacional de costa rica|credomatic/i],
  ['DOP', /banreservas|\bbhd\b|popular dominicano/i],
  ['CUP', /bandec|metropolitano|\bbpa\b/i],
  ['GTQ', /banrural|banco industrial/i],
  ['HNL', /atl[aá]ntida|ficohsa/i],
  ['NIO', /lafise|banpro/i]];
const MONEDA_DE_PALABRA = [
  ['USDT', /usdt|tether/], ['BRL', /r\$|\bbrl\b|reais|reales/], ['DOP', /\bdop\b|rd\$|dominican/], ['NIO', /\bnio\b|c[oó]rdoba|c\$/],
  ['UYU', /\buyu\b|uruguay|\$u\b/], ['BOB', /\bbob\b|bolivian/], ['VES', /\bves\b|\bbs\b|bol[ií]var/], ['COP', /\bcop\b|colombian/],
  ['PEN', /\bpen\b|s\/|\bsoles?\b/], ['MXN', /\bmxn\b|mexican/], ['CLP', /\bclp\b|chilen/], ['ARS', /\bars\b|argentin/],
  ['PYG', /\bpyg\b|guaran|₲|\bgs\b/], ['CRC', /\bcrc\b|col[oó]n|₡/], ['CUP', /\bcup\b|cuban/], ['GTQ', /\bgtq\b|quetzal/],
  ['HNL', /\bhnl\b|lempira/], ['EUR', /\beur\b|€|euros?\b/], ['USD', /\busd\b|\bus\b|d[oó]lar/]];
function monedaDeCaptura(t){
  const x = sinHuella(t);
  const banco = campoDe(x, 'banco|entidad');
  const delBanco = (MONEDA_DEL_BANCO.find(([m, rx]) => rx.test(banco)) || [''])[0];
  const dicha = String(campoDe(x, 'moneda') || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
  if (dicha && dicha !== 'no visible'){
    const m = (MONEDA_DE_PALABRA.find(([c, rx]) => rx.test(dicha)) || [''])[0];
    if (m === 'USD' && delBanco) return delBanco;          // "$" de un banco colombiano son pesos
    return m;
  }
  const seg = String((x.match(/monto\s*:?\s*([^,\]]*(?:,[0-9]{1,2})?)/i) || [])[1] || '').toLowerCase();
  const m = (MONEDA_DE_PALABRA.find(([c, rx]) => c !== 'USD' && rx.test(seg)) || [''])[0];
  if (m) return m;
  if (/\$|\busd\b|d[oó]lar/.test(seg)) return delBanco || 'USD';
  return '';
}
// El monto de una cuenta EN UNA MONEDA: "$10" / "10$" / "10 usd" (dolares), "Bs 12.000" / "12.000 bs",
// "100.000 COP" / "$100.000" (pesos), "S/ 50", "R$ 50", "50 €"... Solo un numero pegado a su moneda, en
// la misma linea (una cedula o un telefono no tienen moneda). null si no hay.
// (Se escriben como /.../.source para no tener que duplicar las barras invertidas.)
const NUM = /([0-9][0-9.,]*[0-9]|[0-9])/.source, ESP = /[ \t]*/.source;
const MARCAS_MONEDA = {
  USD:  [/(?:us\$|(?<![a-z])\$|\busd\b)/.source,  /(?:(?<![a-z])\$|\busd\b|d[oó]lares?\b)/.source],
  USDT: [/(?:\busdt\b)/.source,                   /(?:\busdt\b)/.source],
  VES:  [/(?:\bbs\b\.?|\bves\b)/.source,           /(?:\bbs\b\.?|bol[ií]vares?\b|\bves\b)/.source],
  COP:  [/(?:\bcop\b|(?<![a-z])\$)/.source,        /(?:\bcop\b|\bpesos?\b|(?<![a-z])\$)/.source],
  MXN:  [/(?:\bmxn\b|(?<![a-z])\$)/.source,        /(?:\bmxn\b|\bpesos?\b|(?<![a-z])\$)/.source],
  CLP:  [/(?:\bclp\b|(?<![a-z])\$)/.source,        /(?:\bclp\b|\bpesos?\b|(?<![a-z])\$)/.source],
  ARS:  [/(?:\bars\b|(?<![a-z])\$)/.source,        /(?:\bars\b|\bpesos?\b|(?<![a-z])\$)/.source],
  PEN:  [/(?:s\/\.?|\bpen\b)/.source,              /(?:\bsoles?\b|\bpen\b)/.source],
  BRL:  [/(?:r\$|\bbrl\b)/.source,                 /(?:\breais\b|\breales\b|\bbrl\b)/.source],
  EUR:  [/(?:€|\beur\b)/.source,                   /(?:€|\beur\b|\beuros?\b)/.source],
  BOB:  [/(?:\bbob\b|\bbs\b\.?)/.source,           /(?:\bbob\b|\bbs\b\.?|bolivianos?\b)/.source],
  UYU:  [/(?:\buyu\b|\$u\b|(?<![a-z])\$)/.source,  /(?:\buyu\b|\bpesos?\b|(?<![a-z])\$)/.source],
  PYG:  [/(?:\bpyg\b|\bgs\b\.?|₲)/.source,         /(?:\bpyg\b|\bgs\b\.?|guaran[ií]es\b|₲)/.source],
  CRC:  [/(?:\bcrc\b|₡)/.source,                   /(?:\bcrc\b|colones\b|₡)/.source],
  DOP:  [/(?:\bdop\b|rd\$|(?<![a-z])\$)/.source,   /(?:\bdop\b|\bpesos?\b|(?<![a-z])\$)/.source],
  CUP:  [/(?:\bcup\b|(?<![a-z])\$)/.source,        /(?:\bcup\b|\bpesos?\b|(?<![a-z])\$)/.source],
  GTQ:  [/(?:\bgtq\b|\bq\b\.?)/.source,            /(?:\bgtq\b|quetzales?\b)/.source],
  HNL:  [/(?:\bhnl\b|\bl\b\.?)/.source,            /(?:\bhnl\b|lempiras?\b)/.source],
  NIO:  [/(?:\bnio\b|c\$)/.source,                 /(?:\bnio\b|c[oó]rdobas?\b)/.source]};
function montoEn(t, moneda){
  const mk = MARCAS_MONEDA[moneda];
  if (!mk) return null;
  const antes = new RegExp(mk[0] + ESP + NUM, 'i'), despues = new RegExp(NUM + ESP + mk[1], 'i');
  for (const linea of String(t || '').split('\n')){
    const m = linea.match(antes) || linea.match(despues);
    if (m){ const v = numero(m[1]); if (!isNaN(v)) return v; }
  }
  return null;
}
// Como se escribe un monto en esa moneda: "$10", "$10.50", "12.000 Bs", "100.000 COP".
function montoTexto(n, moneda){
  if (typeof n !== 'number' || isNaN(n)) return '?';
  const dec = Math.round(n * 100) % 100 !== 0;
  if (!moneda || moneda === 'USD') return '$' + (dec ? n.toFixed(2) : String(Math.round(n)));
  const partes = (dec ? n.toFixed(2) : String(Math.round(n))).split('.');
  const miles = partes[0].replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return miles + (partes[1] ? ',' + partes[1] : '') + ' ' + (moneda === 'VES' ? 'Bs' : moneda);
}
// Todo lo que se puede comparar de una captura: monto, referencia, banco, destinatario y huella.
function datosDeCaptura(texto, id){
  return { id: id || '', texto, ts: ahora,
           monto: montoDe(texto), ref: refDe(texto), huella: huellaDe(texto),
           banco: campoDe(texto, 'banco|entidad'),
           destino: campoDe(texto, 'destinatario|beneficiario|titular|nombre|enviad[oa] a') };
}
// El MISMO deposito se decide con el monto, la referencia y los datos bancarios (banco y
// destinatario), nunca con uno solo:
//   - la misma foto (huella)                                   -> repetido
//   - cualquier dato que se CONTRADIGA (otro monto, otra referencia, otro banco o destinatario)
//                                                              -> es otro deposito
//   - misma referencia                                         -> repetido
//   - sin referencia: mismo monto Y mismo banco o destinatario -> repetido (aunque pase tiempo)
//   - sin referencia ni banco que comparar: solo el monto y unos pocos minutos (dos pantallas
//     del mismo pago, ej. un Zelle)                            -> repetido
// Si a las dos les falta el monto no se afirma nada: mejor pasar de mas que tragarse un deposito.
function mismoDeposito(a, b){
  if (!a || !b) return false;
  if (a.huella && b.huella && a.huella === b.huella) return true;
  const ma = (a.monto === undefined) ? null : a.monto, mb = (b.monto === undefined) ? null : b.monto;
  if (ma !== null && mb !== null && Math.abs(ma - mb) >= 0.01) return false;
  if (a.ref && b.ref && a.ref !== b.ref) return false;
  const banco = parecidos(a.banco, b.banco), destino = parecidos(a.destino, b.destino);
  if (banco === false || destino === false) return false;
  if (a.ref && b.ref) return true;
  if (ma === null || mb === null) return false;
  if (banco === true || destino === true) return true;
  return Math.abs((a.ts || 0) - (b.ts || 0)) <= MINUTOS_MISMO_DEPOSITO * 60000;
}

// ---------- palabras de cierre ("gracias", "ok") y de confirmacion ("si, esa") ----------
// Palabras que pueden acompanar un "gracias" o un "ok" sin cambiar lo que significa.
// "no" NO esta a proposito: "no gracias" es otra cosa.
const RELLENO = ['ok','oki','okey','okay','okis','oks','okok','okidoki','listo','perfecto','vale','dale','bueno','buena',
  'bien','esta','muy','mucho','muchas','muchisimas','muchisimo','mil','de','verdad','todo','todos','por','su','tu','la','el',
  'lo','le','te','a','al','y','e','que','mi','mis','amigo','amiga','hermano','hermana','mano','pana','bro','parcero','parce',
  'rey','reina','amor','mija','mijo','sr','sra','senor','senora','don','dona','jefe','jefa','veci','vecino','vecina',
  'kelvin','jk','cambios','equipo','ustedes','usted','ud','uds','dios','bendiga','bendiciones','bendicion','saludos',
  'abrazo','abrazos','feliz','buen','buenas','buenos','dia','dias','tarde','tardes','noche','noches','fin','semana',
  'hasta','manana','luego','pronto','chao','chau','bye','igualmente','excelente','genial','chevere','super','fino',
  'recibido','recibida','recibi','llego','llegaron','ya','me','si','ah','aja','oh','eh','uy','hagale','entendido',
  'acuerdo','copiado','enterado','entiendo','va'];
// Lo que lo vuelve un agradecimiento.
const GRACIAS = ['gracias','gracia','grasias','grax','agradezco','agradecido','agradecida','agradecidos','agradecemos',
  'amable','thanks','thank','thx'];
// Lo que lo vuelve un "ok" suelto.
const ACUSE = ['ok','oki','okey','okay','okis','oks','okok','okidoki','listo','perfecto','vale','dale','bien','bueno',
  'entendido','acuerdo','copiado','enterado','entiendo','hagale'];
// Lo que confirma una cuenta propuesta ("¿te lo envio a esta cuenta?" -> "si, esa").
const AFIRMA = ['si','sip','esa','ese','esas','esos','eso','misma','mismo','correcto','correcta','exacto','exacta','confirmo',
  'confirmado','confirmada','afirmativo','claro','asi','es','ok','oki','okey','okis','okok','dale','listo','perfecto','vale','va'];

// "Graciaaaas" = "gracias", "okk" = "ok": las letras repetidas se juntan (en las listas tambien).
const simple = w => w.replace(/(.)\1+/g, '$1');
const S_RELLENO = new Set(RELLENO.map(simple)), S_GRACIAS = new Set(GRACIAS.map(simple)), S_ACUSE = new Set(ACUSE.map(simple));
const S_AFIRMA = new Set(AFIRMA.map(simple));
const esRisa = w => /^(ja|je|ji|ha)+j?$/.test(w);
const EMOJIS_OK = /👍|👌|✅|🫡|🤝|❤|🧡|💛|💚|💙|💜|🖤|🤍|😂|🤣|😅|😁|😀|😃|😄|😊|🙂|😉|😎|🥳|🎉|💪|🙌|👏|🫶|😘|🥰|😍|🔥/gu;
function palabrasDe(t){
  return String(t || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
    .replace(/🙏/g, ' gracias ').replace(/👍|👌|✅|🫡/g, ' ok ')
    .replace(/[^a-z0-9]+/g, ' ').trim().split(' ').filter(Boolean).map(simple);
}
// 'vacio' | 'gracias' | 'acuse' | '' (cualquier otra cosa: la IA)
function tipoDeCierre(textos){
  // Lo citado no cuenta: solo lo que escribio ahora.
  const crudo = textos.map(t => String(t || '').replace(/\[el cliente respondio citando[^\]]*\]/gi, ' ')).join('\n').trim();
  if (!crudo) return 'vacio';
  if (/[?¿]/.test(crudo)) return '';                       // una pregunta nunca es un cierre
  const w = palabrasDe(crudo);
  if (!w.length){
    // Solo emojis. Los de "ok", risa o carino (👍 😂 ❤️) son como un "ok". Los de preocupacion o
    // duda (😔 🤔 🚨 🤷) NO: ahi conviene que la IA pregunte que pasa. Un "." tambien va a la IA.
    const resto = crudo.replace(EMOJIS_OK, '').replace(/[\u{1F3FB}-\u{1F3FF}\uFE0F\u200D]/gu, '').replace(/[\s.,!¡]+/g, '');
    return (/\p{Extended_Pictographic}/u.test(crudo) && !resto) ? 'acuse' : '';
  }
  const frase = w.join(' ');
  if (/(^| )gracias a dios( |$)/.test(frase)) return '';      // "bien, gracias a Dios" contesta un "como estas?"
  if (/(^| )y (tu|usted|ustedes|ud|uds|vos)( |$)/.test(frase)) return '';   // "bien y tu" pregunta de vuelta
  const sobra = (x, propias) => !(propias.has(x) || S_RELLENO.has(x) || esRisa(x));
  if (w.some(x => S_GRACIAS.has(x)) && !w.some(x => sobra(x, S_GRACIAS))) return 'gracias';
  if (w.some(x => S_ACUSE.has(x)) && !w.some(x => sobra(x, S_ACUSE))) return 'acuse';
  return '';
}
// Si el ultimo mensaje del bot fue una pregunta (lo anota "Redis Marcar Pregunta" cada vez que la
// IA contesta). true / false / null = no se sabe (Redis caido): ante la duda contesta la IA.
function ultimoFuePregunta(){
  let j;
  try { j = $('Redis Leer Pregunta').first().json || {}; } catch(e){ return null; }
  if (j.error) return null;
  return String(j.pregunta || '') === '1';
}

// ---------- depositos ya registrados en Supabase ----------
// Pueden ser de hace semanas, asi que solo se toman como EL MISMO deposito con la misma foto o la
// misma referencia (larga). "Mismo monto y mismo banco" es normal en un cliente que deposita lo
// mismo cada semana. Las operaciones canceladas no cuentan.
const hechosTabla = [];
for (const r of historial){
  if (r.estado === 'cancelada') continue;
  const cs = listaDe(r.capturas);
  if (cs.length) cs.forEach(c => hechosTabla.push({ ref: String((c && c.ref) || ''), monto: (c && typeof c.monto === 'number') ? c.monto : null, huella: String((c && c.huella) || '') }));
  else hechosTabla.push({ ref: String(r.ref_deposito || ''), monto: (r.monto_deposito === null || r.monto_deposito === undefined) ? null : Number(r.monto_deposito), huella: String(r.huella_foto || '') });
}
function mismoDepositoViejo(a, b){
  if (a.huella && b.huella && a.huella === b.huella) return true;
  if (!a.ref || !b.ref || a.ref !== b.ref || a.ref.length < 6) return false;
  if (a.monto !== null && a.monto !== undefined && b.monto !== null && Math.abs(a.monto - b.monto) >= 0.01) return false;
  return true;
}

// ---------- "la misma cuenta de siempre" ----------
// El bot NO ofrece listas de beneficiarios (a algunos clientes los enreda). Solo si el cliente lo
// pide ("a la misma de siempre", "igual que la otra vez") y ya mando la captura, se le muestra la
// ultima cuenta que uso y se le pide un "si". Sin captura, "la misma cuenta" casi siempre habla de
// NUESTRA cuenta (donde deposita): eso lo contesta el agente como siempre.
function pideLaMisma(t){
  t = String(t || '');
  if (/[?¿]/.test(t)) return false;
  const x = ' ' + t.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, ' ').trim() + ' ';
  return / mism[ao]s? (cuenta|cuentas|datos|persona|beneficiari[ao]|destinatari[ao]) /.test(x)
      || / (la|el|los|las) mism[ao]s? (de|que) (siempre|antes|la otra vez|la vez pasada|la ultima vez|ayer|la anterior) /.test(x)
      || / (la|el) de siempre /.test(x)
      || / igual que (la otra vez|antes|siempre|la vez pasada|ayer|la anterior) /.test(x);
}
function esAfirmacion(t){
  t = String(t || '');
  if (/[?¿]/.test(t)) return false;
  const w = palabrasDe(t);
  if (!w.length || w.indexOf('no') !== -1) return false;
  return w.some(x => S_AFIRMA.has(x) && x !== 'es' && x !== 'asi') && w.every(x => S_AFIRMA.has(x) || S_RELLENO.has(x) || esRisa(x));
}
// La cuenta de la vez pasada se muestra SIN su monto: el de hoy puede ser otro, y el grupo vería
// un monto viejo en la cabecera.
function sinMontos(t){
  return String(t || '').split('\n').map(l => l
      .replace(/monto\s*:?\s*\$?\s*[0-9][0-9.,]*\s*(\$|usd|dolares|dolar)?/gi, '')
      .replace(/\$\s*[0-9][0-9.,]*/g, '')
      .replace(/[0-9][0-9.,]*\s*(\$|usd\b|dolares|dolar)/gi, '')
      .trim())
    .filter(l => l.length).join('\n');
}

__BLOQUES_CUENTAS__

// ---------- lo que llego ahora ----------
const RX_CAPTURA = /\[El cliente envio un COMPROBANTE[^\]]*\]/i;
const capturas = [];
for (const m of mensajes){
  const t = String((m && m.texto) || '');
  const c = t.match(RX_CAPTURA);
  if (c) capturas.push(datosDeCaptura(c[0], (m && m.id) || ''));
}

// Una cuenta: SIN captura de por medio, solo con datos firmes. CON una captura (en este envio o
// esperando guardada), tambien un texto con palabras de cuenta o banco, pero nunca una pregunta.
// La operadora pidio VERIFICAR los datos de una cuenta de este cliente (nodo "Marcar Corregir Datos"):
// lo que mande ahora con datos de cuenta es la correccion, aunque no traiga captura (ver 'correccion').
const corregir = (op.corregir && typeof op.corregir.ts === 'number' && (ahora - op.corregir.ts) <= HORAS_CORREGIR * 3600000) ? op.corregir : null;
const hayCaptura = capturas.length > 0 || capturasGuardadas.length > 0;
const cuentasAhora = [];
for (const m of mensajes){
  const resto = textoDelCliente(String((m && m.texto) || ''));
  if (!resto || esCuentaNuestra(resto)) continue;
  if (pideLaMisma(resto) && !datosFirmes(resto)) continue;      // "a la misma cuenta de siempre" no ES una cuenta
  // El PIE DE FOTO de una captura solo cuenta como cuenta si TRAE datos de cuenta: un numero largo, un correo,
  // una billetera, o palabras de cuenta con un numero de 6 digitos o mas. "Buenos dias", "aqui mi pago" o
  // "para la cuenta de mi mama" son charla, no la cuenta (pedido de Kelvin, 24/11).
  const esPie = RX_CAPTURA.test(String((m && m.texto) || ''));
  const pieConDatos = datosFirmes(resto) || (pareceCuenta(resto) && /[0-9]{6,}/.test(resto.replace(/([0-9])[ .-](?=[0-9])/g, '$1')));
  const esCuenta = esPie ? pieConDatos : (datosFirmes(resto) || ((hayCaptura || corregir) && resto.indexOf('?') === -1 && pareceCuenta(resto)));
  if (esCuenta) cuentasAhora.push({ id: (m && m.id) || '', texto: resto });
}

// "La misma de siempre": si el turno pasado se le propuso una cuenta y ahora dice "si", es esa.
// Si dice otra cosa, la propuesta se olvida (y se le vuelve a pedir la cuenta).
const textoAhora = mensajes.map(m => textoDelCliente(String((m && m.texto) || ''))).filter(Boolean).join('\n');
const propuestaVieja = (op.cuentaPropuesta && vigente(op.cuentaPropuesta) && Array.isArray(op.cuentaPropuesta.mensajes)) ? op.cuentaPropuesta.mensajes : [];
let pideMisma = false, propuestaNueva = null;
if (!cuentasAhora.length && propuestaVieja.length && esAfirmacion(textoAhora)){
  propuestaVieja.forEach(m => cuentasAhora.push({ id: m.id || '', texto: m.texto }));
} else if (!cuentasAhora.length && hayCaptura && pideLaMisma(textoAhora)){
  pideMisma = true;
  // Hay una fila por cuenta: las de la ultima operacion comparten el id de la captura.
  const filaCuenta = historial.find(r => r.estado !== 'cancelada' && listaDe(r.cuentas).some(c => c && c.texto));
  const filasOp = !filaCuenta ? [] : historial.filter(r => r.estado !== 'cancelada'
    && (filaCuenta.id_msg_captura ? r.id_msg_captura === filaCuenta.id_msg_captura : r.id === filaCuenta.id));
  const cs = [].concat.apply([], filasOp.map(r => listaDe(r.cuentas))).filter(c => c && c.texto);
  if (cs.length === 1){                       // si la vez pasada fueron varias, se le piden los datos
    const texto = sinMontos(cs[0].texto);
    if (texto) propuestaNueva = { mensajes: [{ id: '', texto }], ts: ahora, hasta: venceEn(ahora) };
  }
}

const nuevas = [];
for (let i = 0; i < capturas.length; i++){
  const c = capturas[i];
  const antes = capturas.slice(0, i).find(x => mismoDeposito(c, x));
  if (antes){ c.clase = antes.clase; continue; }             // otra pantalla del mismo pago, en el mismo envio
  if (hechos.some(h => mismoDeposito(c, h)) || hechosTabla.some(h => mismoDepositoViejo(c, h))){ c.clase = 'repetida'; continue; }
  const g = capturasGuardadas.find(x => mismoDeposito(c, x));
  if (g){                                                    // la volvio a mandar mientras falta la cuenta
    c.clase = 'guardada';
    if (!g.ref && c.ref) g.ref = c.ref;
    if (!g.huella && c.huella) g.huella = c.huella;
    if (!g.banco && c.banco) g.banco = c.banco;
    if (!g.destino && c.destino) g.destino = c.destino;
    continue;
  }
  c.clase = 'nueva';
  nuevas.push(c);
}
const todasRepetidas = capturas.length > 0 && capturas.every(c => c.clase === 'repetida');

// Varias cuentas (en un mensaje o en varios) se juntan; la misma cuenta escrita dos veces, no.
// Por cada cuenta se queda la version CON monto (21/11: si la mando sin monto, se le pide y la vuelve a
// mandar con monto); si las dos tienen o no tienen monto, la mas completa (ej. ahora con el banco y el
// titular). Los mensajes viejos que ya no aportan ninguna cuenta se descartan: asi al grupo no van repetidas.
// Si las dos traen monto y es DISTINTO, gana la mas nueva: es una correccion (23/11: "tu deposito es de
// $10 pero la cuenta dice $15" -> la manda de nuevo con $10).
// Cada cuenta lleva dos montos: 'monto' (el que tenga: "$10", o en la moneda del deposito) para saber
// si trae monto, y 'enMoneda' (solo en la moneda del deposito) para sumarla y compararla con el deposito.
function depurarCuentas(msgs){
  const gana = {};
  msgs.forEach((m, i) => {
    let bl = bloquesDeCuentas([m], '', '', '', null).map(b => b.texto);
    if (!bl.length) bl = [String((m && m.texto) || '')];
    for (const texto of bl){
      const enMoneda = monedaDep ? montoEn(texto, monedaDep) : null;
      const monto = (monedaDep && monedaDep !== 'USD' && enMoneda !== null) ? enMoneda : (montoDelBloque(texto) !== null ? montoDelBloque(texto) : enMoneda);
      const clave = datosDe(texto).sort().join('|') || normal(texto);
      const g = gana[clave], con = monto !== null;
      const corrige = g && con && g.con && Math.abs(monto - g.monto) >= 0.01;
      if (!g || (con && !g.con) || corrige || (con === g.con && texto.length >= g.largo)) gana[clave] = { i, con, largo: texto.length, monto, enMoneda };
    }
  });
  const cuentas = Object.keys(gana).map(k => gana[k]);
  return { mensajes: msgs.filter((m, i) => cuentas.some(c => c.i === i)).map(m => ({ id: m.id || '', texto: m.texto })), cuentas };
}
const capturasOp = capturasGuardadas.concat(nuevas);
const montosCap = capturasOp.map(c => c.monto);
const montoDeposito = (capturasOp.length && montosCap.every(m => typeof m === 'number' && !isNaN(m))) ? montosCap.reduce((a, b) => a + b, 0) : null;
// La moneda del deposito: la de TODAS sus capturas (si son de monedas distintas o no se sabe, '').
const monedasCap = capturasOp.map(c => monedaDeCaptura(c.texto));
const monedaDep = (monedasCap.length && monedasCap.every(m => m && m === monedasCap[0])) ? monedasCap[0] : '';

// ---------- ¿el deposito cuadra con las cuentas? (pedido de Kelvin, 23/11) ----------
// En la MISMA moneda: si deposito en dolares, las cuentas en dolares ("$10"); si deposito en pesos,
// bolivares o soles, las cuentas en esa moneda ("100.000 COP", "Bs 12.000"). La suma tiene que dar
// EXACTO lo que dice la captura. Solo se compara cuando se sabe la moneda del deposito, se leyo su
// monto y TODAS las cuentas traen su monto en esa moneda. Si difieren en mas de 20 veces, es otra
// moneda leida mal: no se compara. null = no se puede comparar (y la operacion sigue como siempre).
function cuadreDe(cuentas){
  if (!monedaDep || montoDeposito === null || !cuentas.length || cuentas.some(c => c.enMoneda === null)) return null;
  const suma = Math.round(cuentas.reduce((a, c) => a + c.enMoneda, 0) * 100) / 100;
  const deposito = Math.round(montoDeposito * 100) / 100;
  if (suma <= 0 || deposito <= 0 || Math.max(suma, deposito) / Math.min(suma, deposito) > 20) return null;
  return { suma, deposito, moneda: monedaDep, cuadra: Math.abs(suma - deposito) <= MARGEN_CUADRE + 0.001, montos: cuentas.map(c => c.enMoneda) };
}
let depuradas = depurarCuentas(cuentaGuardada.concat(cuentasAhora));
let cuadre = cuadreDe(depuradas.cuentas);
// Ya se le dijo que no cuadraba y ahora manda las cuentas de nuevo: si las que manda AHORA, solas,
// dan lo mismo que el deposito, son las buenas y reemplazan a las de antes (ej. tenia dos cuentas
// de $10 y $5 con un deposito de $10, y ahora manda solo la de $10).
if (cuadre && !cuadre.cuadra && op.noCuadra && cuentasAhora.length){
  const soloNuevas = depurarCuentas(cuentasAhora);
  const c2 = cuadreDe(soloNuevas.cuentas);
  if (c2 && c2.cuadra){ depuradas = soloNuevas; cuadre = c2; }
}
const cuentasOp = depuradas.mensajes;

// ---------- ¿las cuentas traen el monto? (pedido de Kelvin, 21/11) ----------
// Con VARIAS cuentas, cada una tiene que decir cuanto va: si a alguna le falta, NO se pasa a transferir y
// se le pide al cliente que se lo coloque y las vuelva a mandar. Con UNA sola cuenta sin monto se usa el
// del deposito (va en la cabecera); solo si tampoco se pudo leer el de la captura, se le pide.
const cuentasDep = depuradas.cuentas;
const sinMonto = cuentasDep.filter(c => c.monto === null).length;
const faltaMonto = cuentasDep.length > 1 ? sinMonto > 0 : (cuentasDep.length === 1 && sinMonto === 1 && montoDeposito === null);

let estado = 'nada';
if (todasRepetidas) estado = 'repetido';
// Los datos corregidos que pidio la operadora: sin captura de por medio (si manda otra captura, es otra operacion).
else if (corregir && cuentasAhora.length && !capturasOp.length) estado = 'correccion';
else if (capturasOp.length && cuentasOp.length) estado = faltaMonto ? 'falta_monto' : ((cuadre && !cuadre.cuadra) ? 'no_cuadra' : 'completo');
else if (capturasOp.length && propuestaNueva) estado = 'confirmar_cuenta';
else if (capturasOp.length) estado = 'falta_cuenta';
else if (cuentasAhora.length) estado = 'falta_captura';

const NOTA = {
  completo:      'ya tengo la captura del deposito y la cuenta destino de este cliente; se pasaron a operaciones. Responde SOLO: "Listo, recibido! Procesamos tu remesa enseguida ✅"',
  falta_cuenta:  'ya tengo la captura del deposito pero todavia NO tengo la cuenta destino. Responde SOLO: "Recibi tu comprobante! 🙌 Pasame la cuenta destino (banco, numero y titular)"',
  falta_captura: 'el cliente ya paso la cuenta destino pero todavia NO mando la captura del deposito. Si pregunto algo, respondelo; y pidele corto: "Recibi los datos de la cuenta 👍 Cuando hagas el deposito, enviame la captura"',
  repetido:      'esa captura es de un deposito que YA se habia recibido y pasado a operaciones: esta repetida. NO la proceses de nuevo. Responde SOLO: "Ese deposito ya lo recibi, esta repetido 👍 Si es un deposito distinto, avisame"'
};
// Los datos corregidos de la cuenta que la operadora pidio verificar: van a transferir (ver "Preparar Correccion").
NOTA.correccion = 'el cliente mando los datos corregidos de la cuenta que la operadora pidio verificar; ya se le pasaron a la operadora. '
  + 'Responde SOLO: "Listo, recibido ✅ Ya se lo pasé a la operadora con los datos corregidos."';
// Todavia no los corrige: si pregunta, que sepa que hay que revisar.
if (corregir) NOTA.nada = 'la operadora pidio verificar los datos de una cuenta de este cliente (indico: "' + String(corregir.nota || 'verificar datos') + '") '
  + 'y todavia no los manda corregidos. Si pregunta que esta mal o que tiene que hacer, dile corto que revise bien los datos de esa cuenta '
  + '(banco, numero de cuenta o telefono, titular y cedula) y te los mande corregidos. Si escribe otra cosa, respondele normal.';
if (propuestaNueva) NOTA.confirmar_cuenta = 'el cliente quiere usar la misma cuenta destino de la vez pasada. Responde SOLO esto, con la cuenta copiada tal cual: "¿Te lo envío a esta cuenta? 👇\n\n' + propuestaNueva.mensajes[0].texto + '\n\nResponde *sí* para confirmar"';
if (estado === 'falta_monto'){
  const varias = cuentasDep.length > 1;
  NOTA.falta_monto = cuentasAhora.length
    ? ('ya tengo la captura y ' + (varias ? ('las cuentas, pero ' + (sinMonto === 1 ? 'a una de las cuentas le falta el monto' : 'a ' + sinMonto + ' cuentas les falta el monto') + ' (cuanto va a cada una)')
                                          : 'la cuenta, pero no trae el monto y no pude leer el monto de la captura')
       + '. NO se procesa todavia. Responde SOLO: "' + (varias ? 'Disculpa, veo que tus datos no traen el monto de cada cuenta 🙏 Colócale a cada una cuánto va y envíamelas de nuevo, por favor'
                                                            : 'Disculpa, veo que tus datos no traen el monto 🙏 Colócale el monto y envíamelos de nuevo, por favor') + '"')
    : ('todavia falta el monto de ' + (varias ? 'cada cuenta' : 'la cuenta') + ' para procesar su remesa. Si pregunto otra cosa, respondelo; y recuerdale corto que le coloque el monto '
       + (varias ? 'a cada cuenta' : 'a la cuenta') + ' y la vuelva a mandar.');
}
// ===== EL DEPOSITO NO CUADRA CON LAS CUENTAS (pedido de Kelvin, 23/11) =====
// No se procesa: se le dice cuanto deposito y cuanto suman las cuentas, y se le pide que confirme.
//   - corrige (las cuentas con el monto bueno, solo las que van, o la otra captura) -> se procesa sola
//   - dice "si" y deposito de MENOS -> se le pide la captura del otro deposito
//   - dice "si" y deposito de MAS (o ya se le pidio la otra captura) -> un asesor lo revisa, y se deja
//     un aviso en el grupo de transferir (NO se transfiere)
// Por su cuenta, el workflow "Avisar deposito que no cuadra" le recuerda al cliente a los 5 minutos y
// avisa al grupo de avisos a los 10 (si no lo arreglo ni se paso a un asesor). La marca 'paso' dice en
// que va: preguntado | pidio_captura | escalado.
const noCuadraViejo = (op.noCuadra && typeof op.noCuadra.ts === 'number') ? op.noCuadra : null;
function confirmaMontos(t){
  t = String(t || '');
  if (!t.trim() || /[?¿]/.test(t)) return false;
  const w = palabrasDe(t);
  if (!w.length || w.indexOf('no') !== -1) return false;
  if (esAfirmacion(t)) return true;
  if (['si','sip','correcto','correcta','exacto','exacta','confirmo','confirmado','confirmada','afirmativo','claro'].indexOf(w[0]) !== -1) return true;
  return /(^| )(esta bien|estan bien|asi esta bien|asi es|es asi|son correctos|es correcto|esta correcto|estan correctos|todo bien|son esos|ese es|esos son)( |$)/.test(w.join(' '));
}
let pasoNoCuadra = '', escalarAhora = false;
if (estado === 'no_cuadra'){
  const mon = cuadre.moneda;
  const dep = montoTexto(cuadre.deposito, mon), suma = montoTexto(cuadre.suma, mon);
  const varias = cuentasDep.length > 1;
  const dicen = varias ? ('las cuentas suman ' + suma) : ('la cuenta dice ' + suma);
  const lasCuentas = varias ? 'las cuentas' : 'la cuenta';
  const faltaPlata = cuadre.deposito < cuadre.suma;
  const antes = noCuadraViejo ? (noCuadraViejo.paso || 'preguntado') : '';
  if (nuevas.length || cuentasAhora.length){
    pasoNoCuadra = (antes === 'escalado') ? 'escalado' : 'preguntado';
    NOTA.no_cuadra = 'el deposito es de ' + dep + ' pero ' + dicen + ': NO cuadra y NO se procesa todavia. Responde SOLO: "Disculpa, tu depósito es de '
      + dep + ' pero ' + dicen + ' 🙏 ¿Me confirmas los montos? Si alguno está mal, envíame ' + lasCuentas + ' con el monto correcto."';
  } else if (antes !== 'escalado' && confirmaMontos(textoAhora)){
    if (faltaPlata && antes !== 'pidio_captura'){
      pasoNoCuadra = 'pidio_captura';
      NOTA.no_cuadra = 'el cliente confirmo que ' + lasCuentas + ' estan bien (' + suma + '), pero el deposito es de ' + dep + ': falta otro deposito. NO se procesa todavia. '
        + 'Responde SOLO: "Perfecto 👍 Entonces envíame la captura del otro depósito para poder procesar tu operación."';
    } else {
      pasoNoCuadra = 'escalado'; escalarAhora = true;
      NOTA.no_cuadra = 'el cliente dice que esta bien asi aunque el deposito (' + dep + ') no cuadra con ' + lasCuentas + ' (' + suma + '). NO se procesa: lo revisa un asesor. '
        + 'Responde SOLO: "Listo 👍 Un asesor lo revisa y te escribe en unos minutos."';
    }
  } else if (antes === 'escalado'){
    pasoNoCuadra = 'escalado';
    NOTA.no_cuadra = 'esta operacion la esta revisando un asesor: el deposito (' + dep + ') no cuadra con ' + lasCuentas + ' (' + suma + ') y NO se procesa. '
      + 'Si pregunto otra cosa, respondelo; si pregunta por su operacion, dile corto que un asesor la esta revisando y le escribe pronto.';
  } else if (antes === 'pidio_captura'){
    pasoNoCuadra = 'pidio_captura';
    NOTA.no_cuadra = 'todavia falta la captura del otro deposito (el deposito es de ' + dep + ' y ' + dicen + '); NO se procesa todavia. '
      + 'Si pregunto otra cosa, respondelo; y recuerdale corto que envie la captura del otro deposito para poder procesar.';
  } else {
    pasoNoCuadra = 'preguntado';
    NOTA.no_cuadra = 'todavia NO cuadra: el deposito es de ' + dep + ' y ' + dicen + ', y NO se procesa hasta que cuadre. Si pregunto otra cosa, respondelo; '
      + 'y recuerdale corto que confirme los montos de ' + lasCuentas + ' o le mande ' + lasCuentas + ' con el monto correcto.';
  }
}
// Fuera de horario la operacion completa NO se pasa a transferir: queda 'en_espera' (ver "Armar
// Filas Noche") y se publica al abrir. Al cliente solo se le dice que se recibio y cuando se procesa.
const enEspera = (estado === 'completo') && !hor.abierto;
if (enEspera) NOTA.completo = 'ya tengo la captura del deposito y la cuenta destino de este cliente, pero estamos CERRADOS: la operacion queda guardada y se pasa a operaciones al abrir. Responde SOLO: "Recibido ✅ Se procesa ' + hor.cuandoAbre + '"';
if (pideMisma && !propuestaNueva) NOTA.falta_cuenta = 'el cliente pidio usar la misma cuenta de la vez pasada, pero no la tengo registrada (o la vez pasada fueron varias cuentas). Responde SOLO: "Recibí tu comprobante! 🙌 Pásame los datos de la cuenta destino porfa (banco, número, titular y cédula)"';
const notaIA = NOTA[estado] ? '\n\n[ESTADO DE LA OPERACION: ' + NOTA[estado] + ']' : '';

const huellaDeposito = c => ({ ref: c.ref || '', monto: (c.monto === undefined ? null : c.monto), huella: c.huella || '',
                                banco: c.banco || '', destino: c.destino || '', ts: ahora });
const nueva = { cuenta: null, capturas: [], hechos };
let textoAprobar = '', mensajesAprobar = [], idImagen = '', registro = null;
if (estado === 'completo'){
  textoAprobar = capturasOp.map(c => c.texto).join('\n') + '\n\n' + cuentasOp.map(m => m.texto).join('\n\n');
  mensajesAprobar = capturasOp.map(c => ({ id: c.id, texto: c.texto })).concat(cuentasOp);
  idImagen = (capturasOp[0] && capturasOp[0].id) || '';
  // Lo que se guarda en Supabase (ver "Armar Fila Supabase").
  registro = {
    capturas: capturasOp.map(c => ({ id: c.id || '', monto: (c.monto === undefined ? null : c.monto), ref: c.ref || '', banco: c.banco || '',
                                     destino: c.destino || '', huella: c.huella || '', texto: String(c.texto || '') })),
    cuentas: cuentasOp.map(m => ({ id: m.id || '', texto: m.texto }))
  };
  // Se recuerdan TODAS las capturas de este deposito (tambien la segunda pantalla), para
  // reconocerlas si las vuelve a mandar.
  const recordar = capturasGuardadas.concat(capturas.filter(c => c.clase !== 'repetida'));
  nueva.hechos = hechos.concat(recordar.map(huellaDeposito));
} else if (estado === 'falta_cuenta' || estado === 'confirmar_cuenta' || estado === 'falta_monto' || estado === 'no_cuadra'){
  nueva.capturas = capturasOp.map(c => ({ id: c.id, texto: c.texto, ts: c.ts, ref: c.ref, monto: c.monto, huella: c.huella,
                                         banco: c.banco || '', destino: c.destino || '',
                                         hasta: (typeof c.hasta === 'number') ? c.hasta : venceEn(c.ts || ahora) }));
  if (propuestaNueva) nueva.cuentaPropuesta = propuestaNueva;
  // Falta el monto, o no cuadra: las cuentas quedan guardadas; cuando las corrija, reemplazan a estas.
  if (estado === 'falta_monto' || estado === 'no_cuadra') nueva.cuenta = { mensajes: cuentasOp, ts: ahora, hasta: venceEn(ahora) };
} else if (estado === 'falta_captura'){
  nueva.cuenta = { mensajes: cuentasOp, ts: ahora, hasta: venceEn(ahora) };
} else if (estado === 'correccion'){
  // nada queda pendiente: la correccion ya se pasa a transferir
} else {
  // repetido o nada: lo que estaba pendiente sigue pendiente
  nueva.cuenta = cuentaGuardada.length ? { mensajes: cuentaGuardada, ts: op.cuenta.ts, hasta: op.cuenta.hasta } : null;
  nueva.capturas = capturasGuardadas;
}
// "No cuadra": la marca dice DESDE CUANDO (ts) y en que paso va. Sigue siendo la misma mientras no lo
// arregle, aunque escriba otra cosa o corrija solo una parte; se borra sola cuando la operacion se
// procesa. El workflow "Avisar deposito que no cuadra" solo actua si la marca sigue con el mismo ts.
// La PRIMERA vez se le pide vigilarla ('vigilar'); cuando pasa a un asesor, el aviso a transferir ('escalar').
let vigilarMonto = null;
if (estado === 'no_cuadra'){
  nueva.noCuadra = { ts: noCuadraViejo ? noCuadraViejo.ts : ahora, deposito: cuadre.deposito, suma: cuadre.suma, montos: cuadre.montos,
                     moneda: cuadre.moneda, paso: pasoNoCuadra };
  const datos = { token: nueva.noCuadra.ts, deposito: cuadre.deposito, suma: cuadre.suma, montos: cuadre.montos, moneda: cuadre.moneda };
  if (!noCuadraViejo) vigilarMonto = Object.assign({ modo: 'vigilar' }, datos);
  else if (escalarAhora) vigilarMonto = Object.assign({ modo: 'escalar' }, datos);
} else if (noCuadraViejo && estado !== 'completo' && nueva.capturas.length && nueva.cuenta){
  nueva.noCuadra = noCuadraViejo;      // todavia no lo arreglo (ej. le falta el monto a una, o mando una captura repetida)
}
// "Verificar datos": cuando llegan los datos corregidos se arma la correccion ("Preparar Correccion" la
// publica en transferir) y la marca se borra. Mientras no lleguen, la marca sigue (hasta HORAS_CORREGIR);
// si en el medio se procesa otra operacion completa, tambien se borra.
let correccion = null;
if (estado === 'correccion'){
  correccion = { publicacion: corregir.publicacion || '', nombre: corregir.nombre || '', cabecera: corregir.cabecera || '', idCaptura: corregir.idCaptura || '',
                 nota: corregir.nota || '', idCuenta: (cuentasAhora[0] && cuentasAhora[0].id) || '', texto: cuentasAhora.map(m => m.texto).join('\n\n') };
} else if (corregir && estado !== 'completo'){
  nueva.corregir = corregir;
}

// ===== CIERRES: "GRACIAS", "OK" SUELTOS Y MENSAJES SIN TEXTO =====
// Revision de los chats (20/11): el 20% de lo que escriben los clientes es "gracias" u "ok". Todo
// pasaba por la IA, que contestaba con relleno ("Aqui estoy para lo que necesites 😊").
//   - solo un agradecimiento -> sticker A SU ORDEN, sin IA, como mucho 1 cada MINUTOS_ENTRE_STICKERS
//   - solo un "ok" o "listo" -> nada, salvo que el ultimo mensaje del bot haya sido una pregunta
//   - sin texto              -> nada
// Solo cuando el mensaje es SOLO eso: "gracias, y la tasa?" u "ok, pasame la cuenta" van a la IA.
// El nodo "¿Qué Responder?" usa esta decision. Lo inesperado va siempre a la IA, como antes.

let accion = 'ia', motivoAccion = '';
if (estado === 'nada'){
  const cierre = tipoDeCierre(mensajes.map(m => (m && m.texto) || ''));
  if (cierre === 'vacio'){ accion = 'callar'; motivoAccion = 'mensaje sin texto'; }
  else if (cierre === 'gracias'){
    const reciente = typeof op.ultimoGracias === 'number' && (ahora - op.ultimoGracias) < MINUTOS_ENTRE_STICKERS * 60000;
    accion = reciente ? 'callar' : 'gracias';
    motivoAccion = reciente ? 'agradecimiento (ya tiene su sticker de hace poco)' : 'agradecimiento';
  } else if (cierre === 'acuse'){
    const p = ultimoFuePregunta();
    accion = (p === false) ? 'callar' : 'ia';
    motivoAccion = (p === false) ? 'ok suelto (el bot no habia preguntado nada)' : (p ? 'ok a una pregunta del bot' : 'ok suelto (no se sabe si el bot pregunto)');
  }
}
if (typeof op.ultimoGracias === 'number') nueva.ultimoGracias = op.ultimoGracias;
if (accion === 'gracias') nueva.ultimoGracias = ahora;

// ===== EL NOMBRE DEL CLIENTE: UNA SOLA VEZ CADA 24 H =====
// Antes el agente lo saludaba por su nombre en CADA mensaje. Ahora puede usarlo una vez (al
// saludar) y despues no, hasta que pasen HORAS_ENTRE_NOMBRES. Un sticker no gasta el saludo.
const nombreCliente = String(base.nombreCliente || '').trim();
const tocaNombre = !!nombreCliente && !(typeof op.ultimoSaludo === 'number' && (ahora - op.ultimoSaludo) < HORAS_ENTRE_NOMBRES * 3600000);
const reglaNombre = !nombreCliente ? '' : (tocaNombre
  ? 'NOMBRE DEL CLIENTE: si lo saludas, puedes saludarlo por su nombre (' + nombreCliente + ') UNA sola vez en esta respuesta. No lo repitas despues.'
  : 'NOMBRE DEL CLIENTE: NO escribas el nombre del cliente en esta respuesta (ya lo saludaste por su nombre hace poco). Contesta directo.');
if (typeof op.ultimoSaludo === 'number') nueva.ultimoSaludo = op.ultimoSaludo;
if (accion === 'ia' && tocaNombre) nueva.ultimoSaludo = ahora;

// ===== SALUDOS: BUENOS DIAS, BUENAS TARDES, BUENAS NOCHES (pedido de Kelvin, 24/11) =====
// Si el cliente saluda, el bot saluda de vuelta, tambien cuando su respuesta es una de las fijas ("Recibi tu
// comprobante...", "Listo, recibido!"): antes un "Buenos dias amigo, ayudame con ese envio" se contestaba
// sin saludar. Si el cliente dijo "buenos dias"/"buenas tardes"/"buenas noches", se le responde igual (puede
// escribir desde otro pais, con otra hora); si solo dijo "hola" o "buenas", el saludo es el de la hora de
// Ecuador. Lo ve la IA en su prompt (reglaSaludo).
function saludoDe(textos){
  const w = palabrasDe(textos.join(' '));
  for (let i = 0; i < w.length - 1; i++){
    if (!/^buen/.test(w[i])) continue;
    if (/^(dia|dias|dis|diad)$/.test(w[i + 1])) return 'dias';
    if (/^(tarde|tardes)$/.test(w[i + 1])) return 'tardes';
    if (/^(noche|noches)$/.test(w[i + 1])) return 'noches';
  }
  if (w.some(x => /^(hola|holi|ola|hey|buenas|saludos|epa|epale|bendiciones)$/.test(x))) return 'hola';
  return '';
}
function saludoDeLaHora(ms){
  const h = new Date(ms - 5 * 3600000).getUTCHours();          // hora de Ecuador
  return h < 5 ? 'noches' : (h < 12 ? 'dias' : (h < 19 ? 'tardes' : 'noches'));      // de madrugada (0 a 5 am) todavia es "buenas noches"
}
const SALUDOS = { dias: 'Buenos días', tardes: 'Buenas tardes', noches: 'Buenas noches' };
const clienteSaludo = saludoDe(mensajes.map(m => textoDelCliente(String((m && m.texto) || ''))).filter(Boolean));
const saludoHoy = SALUDOS[clienteSaludo && clienteSaludo !== 'hola' ? clienteSaludo : saludoDeLaHora(ahora)];
const reglaSaludo = (accion !== 'ia' || !clienteSaludo) ? '' :
  'SALUDO: el cliente te saludo. Empieza tu respuesta con "' + saludoHoy + '"'
  + (clienteSaludo === 'hola' ? ' (si solo dijo "hola", puedes empezar con "Hola" o con ese saludo)' : '') + ' y sigue con lo que toque. '
  + 'Si tu respuesta es una de las notas del [ESTADO DE LA OPERACION] ("Responde SOLO..."), el saludo es la UNICA excepcion: ponlo antes, con un emoji de la nota si cabe, y luego la frase de la nota tal cual. '
  + 'Si SOLO te saludo (sin pedir nada), contesta el saludo y preguntale que necesita: "' + saludoHoy + ' 👋 Dime, ¿qué necesitas?". '
  + 'Si ademas pregunta como estas, contesta "Bien, gracias 🙏" y sigue.';

// ===== "¿YA LLEGO?": EL ESTADO DE LA ULTIMA OPERACION, PARA EL AGENTE =====
// Se le pasa siempre (si es de los ultimos DIAS_ULTIMA_OPERACION dias); el prompt le dice que la
// use solo si el cliente pregunta como va su envio. Las horas, en hora de Ecuador.
function horaEc(ms){ const d = new Date(ms - 5 * 3600000); let h = d.getUTCHours(); const m = h >= 12 ? 'pm' : 'am'; h = h % 12 || 12; return h + ':' + String(d.getUTCMinutes()).padStart(2, '0') + ' ' + m; }
function diaEc(ms){
  const dia = x => Math.floor((x - 5 * 3600000) / 86400000);
  const n = dia(ahora) - dia(ms);
  if (n === 0) return 'hoy';
  if (n === 1) return 'ayer';
  const d = new Date(ms - 5 * 3600000);
  return 'el ' + d.getUTCDate() + '/' + (d.getUTCMonth() + 1);
}
const cuando = ms => diaEc(ms) + ' a las ' + horaEc(ms);
let contextoOperaciones = '';
const ultima = historial.find(r => r.estado !== 'cancelada' && r.estado !== 'repetida');
const msUltima = ultima ? Date.parse(ultima.creado) : NaN;
if (ultima && msUltima && (ahora - msUltima) <= DIAS_ULTIMA_OPERACION * 86400000){
  // Una fila por cuenta destino: las de la misma operacion comparten el id de la captura.
  const delMismo = historial.filter(r => r.estado !== 'cancelada' && r.estado !== 'repetida'
    && (ultima.id_msg_captura ? r.id_msg_captura === ultima.id_msg_captura : r.id === ultima.id));
  const n = delMismo.length;
  const enviadas = delMismo.filter(r => r.estado === 'enviada');
  const msEnviada = Math.max.apply(null, [0].concat(enviadas.map(r => Date.parse(r.enviada_en) || 0)));
  let txt = 'ULTIMA OPERACION DEL CLIENTE (usala solo si pregunta si ya llego o como va su envio): recibida ' + cuando(msUltima)
    + ((ultima.monto_deposito !== null && ultima.monto_deposito !== undefined) ? ', deposito de $' + Number(ultima.monto_deposito).toFixed(2) : '')
    + ', ' + n + (n === 1 ? ' cuenta destino' : ' cuentas destino') + '. Estado: ';
  if (n && enviadas.length === n){
    txt += 'ENVIADA' + (msEnviada ? ' ' + cuando(msEnviada) : '') + (n > 1 ? ' (las ' + n + ' cuentas)' : '') + ' (ya se le reenvio el comprobante por este chat).';
  } else if (enviadas.length){
    const faltan = n - enviadas.length;
    txt += 'EN PROCESO: ya salio ' + enviadas.length + ' de ' + n + (msEnviada ? ' (la ultima ' + cuando(msEnviada) + ')' : '')
      + '; falta el comprobante de ' + (faltan === 1 ? 'la otra cuenta' : 'las otras ' + faltan) + '.';
  } else if (delMismo.some(r => r.estado === 'en_espera')){
    txt += 'EN ESPERA (llego fuera de horario; se procesa ' + (hor.abierto ? 'en unos minutos' : hor.cuandoAbre) + ').';
  } else {
    txt += 'EN PROCESO (ya esta con la operadora; falta que mande el comprobante).';
  }
  contextoOperaciones = txt;
}

// ===== FUERA DE HORARIO: LO QUE EL AGENTE TIENE QUE SABER =====
const horarioTexto = hor.abierto ? '' : ('HORARIO: ahora estamos CERRADOS (abrimos ' + hor.cuandoAbre + '). Atiende igual, pero esto MANDA sobre las otras reglas: '
  + 'si pide una cotizacion, COTIZALE NORMAL (con la herramienta, como siempre) y al final agrega una linea aparte: "Estamos cerrados, abrimos ' + hor.cuandoAbre + ' 🕘"; '
  + 'si pide la cuenta para depositar, dasela igual (la del dia) y agrega "El depósito se procesa ' + hor.cuandoAbre + ' 👍"; '
  + 'si es una queja o necesita un asesor: "Un asesor te contacta ' + hor.cuandoAbre + '".');

return [{ json: Object.assign({}, base, {
  estadoOperacion: estado,
  contextoOperaciones,
  registro,
  enEspera,
  abierto: hor.abierto,
  cuandoAbre: hor.cuandoAbre,
  horarioTexto,
  accion,
  motivoAccion,
  reglaNombre,
  reglaSaludo,
  notaIA,
  textoAprobar,
  mensajesAprobar,
  idImagen,
  operacionNueva: JSON.stringify(nueva),
  vigilarMonto,
  correccion,
  capturasLeidas: capturas.map(c => ({ ref: c.ref, monto: c.monto, clase: c.clase }))
}), pairedItem: { item: 0 } }];
'@
$revisarOperacionCode = $revisarOperacionCode.Replace('__MINUTOS_PENDIENTE__', [string]$MINUTOS_OPERACION_PENDIENTE)
$revisarOperacionCode = $revisarOperacionCode.Replace('__MINUTOS_MISMO_DEPOSITO__', [string]$MINUTOS_MISMO_DEPOSITO)
$revisarOperacionCode = $revisarOperacionCode.Replace('__HORAS_RECORDAR__', [string]$HORAS_MEMORIA_OPERACION)
$revisarOperacionCode = $revisarOperacionCode.Replace('__MINUTOS_STICKER_GRACIAS__', [string]$MINUTOS_ENTRE_STICKERS_GRACIAS)
$revisarOperacionCode = $revisarOperacionCode.Replace('__HORAS_NOMBRE__', [string]$HORAS_ENTRE_NOMBRES)
$revisarOperacionCode = $revisarOperacionCode.Replace('__DIAS_ULTIMA_OPERACION__', [string]$DIAS_ULTIMA_OPERACION)
$revisarOperacionCode = $revisarOperacionCode.Replace('__MARGEN_CUADRE__', ([string]$MARGEN_CUADRE_USD).Replace(',', '.'))
$revisarOperacionCode = $revisarOperacionCode.Replace('__HORAS_CORREGIR__', [string]$HORAS_CORREGIR_DATOS)
$revisarOperacionCode = $revisarOperacionCode.Replace('__HORARIO_JK__', $horarioJs)
$revisarOperacionCode = $revisarOperacionCode.Replace('__BLOQUES_CUENTAS__', $bloquesCuentasJs)

# ===================== CODIGO: PREPARAR VIGILANCIA MONTO (deposito que no cuadra) =====================
$prepararVigilanciaCode = @'
// Lo que "Revisar Operacion" pide hacer con un deposito que NO cuadra con las cuentas, en el workflow
// "Avisar deposito que no cuadra":
//   modo 'vigilar' (la PRIMERA vez): a los 5 minutos le recuerda al cliente y a los 10 avisa al grupo de
//                                     avisos, si no lo arreglo;
//   modo 'escalar' (el cliente dice que esta bien asi): deja un aviso en el grupo de transferir.
// Si no hay nada que hacer, aqui termina (y no se llama a nadie).
let ro = {};
try { ro = $('Revisar Operacion').first().json || {}; } catch(e){ ro = {}; }
const v = ro.vigilarMonto;
if (!v || !v.token) return [];
let jid = '', pushName = '', nombreCargado = '';
try { jid = String($('Prep Debounce').first().json.jid || ''); } catch(e){}
try { pushName = String($('Webhook Evolution API').first().json.body.data.pushName || '').trim(); } catch(e){}
try { nombreCargado = String($('Solo Estos Numeros').first().json.nombreCargado || '').trim(); } catch(e){}
if (!jid) return [];
return [{ json: { modo: v.modo === 'escalar' ? 'escalar' : 'vigilar', jid, token: v.token, nombre: nombreCargado || pushName || 'Cliente',
                  numero: jid.split('@')[0], deposito: v.deposito, suma: v.suma, montos: v.montos || [], moneda: v.moneda || 'USD' } }];
'@

# ===================== CODIGO: VERIFICAR DATOS (la operadora pide corregir una cuenta, 23/11) =====================
$prepararCorregirCode = @'
// La operadora cito la publicacion de una cuenta con "Verificar datos" (o "corregir dato"...). Si lo citado
// es una publicacion del bot (esta en Redis: esa es la autorizacion), se arma el mensaje para el cliente
// con los datos que hay que revisar. Si no, no pasa nada.
const base = $('Solo Estos Numeros').first().json;
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

$marcarCorregirCode = @'
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

$prepararCorreccionCode = @'
// El cliente mando los datos corregidos de la cuenta que la operadora pidio verificar ("Revisar Operacion"
// lo decide). Se arma la publicacion para transferir: marcada como CORREGIDA, con el nombre y el monto.
let ro = {};
try { ro = $('Revisar Operacion').first().json || {}; } catch(e){ ro = {}; }
const c = ro.correccion;
if (!c || !c.texto || !c.publicacion) return [];
let jid = '';
try { jid = String($('Prep Debounce').first().json.jid || ''); } catch(e){}
if (!jid) return [];
// La cabecera: la de la publicacion original ("Nombre - $10"); si los datos nuevos traen otro monto, ese.
const montoNuevo = (String(c.texto).match(/\$[ \t]*([0-9]+(?:[.,][0-9]{1,2})?)/) || String(c.texto).match(/([0-9]+(?:[.,][0-9]{1,2})?)[ \t]*(?:\$|usd)/i) || [])[1] || '';
const montoViejo = (String(c.cabecera || '').match(/ - \$([0-9]+(?:[.,][0-9]{1,2})?)/) || [])[1] || '';
const monto = montoNuevo || montoViejo;
const nombre = String(c.nombre || 'Cliente');
const cabecera = montoNuevo ? (nombre + ' - $' + montoNuevo) : (c.cabecera || nombre);
const texto = '✏️ DATOS CORREGIDOS (la operadora pidió: ' + String(c.nota || 'verificar') + ')\n' + cabecera + '\n\n' + String(c.texto).trim();
return [{ json: { modoPublicar: 'correccion', jid, nombre, publicacion: c.publicacion, idCaptura: c.idCaptura || '', idCuenta: c.idCuenta || '', nota: c.nota || '',
                  datos: String(c.texto).trim(), monto: monto ? parseFloat(monto.replace(',', '.')) : null, texto } }];
'@

$datosCorreccionCode = @'
// La fila de esa cuenta en Supabase queda con los datos corregidos: asi, cuando la operadora devuelva la
// foto, la Fase B la compara con los datos BUENOS. Solo van las columnas que se cambian.
const v = $('Preparar Correccion').first().json;
return [{ json: {
  cuentas: [{ id: v.idCuenta || '', texto: v.datos, monto: v.monto }],
  notas: 'Datos corregidos por el cliente (la operadora pidio: ' + (v.nota || 'verificar') + ')'
} }];
'@

# ===================== PROMPT: LEER COMPROBANTE DE LA OPERADORA (Fase B) =====================
$leerComprobanteOperadoraPrompt = 'Esta imagen es el comprobante de una transferencia que hizo una casa de cambio HACIA un beneficiario (transferencia bancaria, pago movil, Zelle, Binance, Nequi, etc.). Lee SOLO los datos del DESTINO (quien RECIBE el dinero), nunca los de quien envia. Responde SOLO JSON valido, sin texto extra: {"es_comprobante": true|false, "cuenta_destino": "numero de cuenta o telefono del destino tal como aparece (con asteriscos si esta oculto)", "cedula_destino": "", "titular_destino": "nombre de quien recibe", "banco_destino": "", "correo_destino": "", "billetera_destino": "", "monto": "", "moneda": "", "referencia": ""}. Si un dato no aparece, dejalo vacio. No inventes nada. es_comprobante = false si no es un comprobante de pago (por ejemplo, una foto de dinero en efectivo o de una persona).'

# ===================== CODIGO: REVISAR COMPROBANTE (Fase B) =====================
$revisarComprobanteCode = @'
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

$prepararContextoIaCode = @'
// Empaqueta todo el contexto necesario para "Bot JK - Atencion al Cliente e IA" (Fase 4).
const wh = $('Webhook Evolution API').first().json || {};
const solo = $('Solo Estos Numeros').first().json || {};
const prep = $('Prep Debounce').first().json || {};
const comb = $('Combinar').first().json || {};
const adm = $('Detectar Comando Admin').first().json || {};
return [{
  json: {
    body: wh.body || {},
    jid: prep.jid || '',
    nombreCargado: solo.nombreCargado || '',
    tarifaCargada: solo.tarifaCargada || '',
    esAdmin: !!adm.esAdmin,
    textoLimpio: adm.textoLimpio || '',
    mensajeCombinado: comb.mensajeCombinado || '',
    mensajes: Array.isArray(comb.mensajes) ? comb.mensajes : []
  }
}];
'@

# ===================== CONSTRUCCION DEL WORKFLOW =====================
$redisCred = @{ redis = @{ id = 'SKkvpS5A65SOcmJs'; name = 'Redis memoria para Cambios JK' } }
$nodes = @(
  [ordered]@{
    parameters = @{ httpMethod = 'POST'; path = 'webhook-whatsapp'; options = @{} }
    id = '75799f35-f979-4b45-9dab-861127bd5f9d'; name = 'Webhook Evolution API'; type = 'n8n-nodes-base.webhook'; typeVersion = 1; position = @(-380,128); webhookId = 'a9ba9382-d166-495a-8309-e13a9d839b06'
  },
  [ordered]@{
    # Numeros de clientes DETAL autorizados. Se leen enteros y se comparan por digitos en el
    # nodo "Solo Estos Numeros", asi el numero se puede cargar con +, con espacios o sin
    # codigo de pais sin que deje de reconocerse.
    # Si falla, el nodo siguiente lo detecta y le contesta a todos (nunca deja al bot mudo).
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'clientes_bot_detal'; returnAll = $true }
    executeOnce = $true
    id = 'd0e1f2a3-0000-4b00-9000-cliesdetal001'; name = 'Clientes Detal Permitidos'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(-520,-160)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
  },
  [ordered]@{
    # Lo mismo para los clientes MAYOR. Por ahora solo decide a quien le contesta el bot:
    # NO cambia la tarifa. La tarifa mayor la sigue dando perfiles_mayor, como siempre.
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'clientes_bot_mayor'; returnAll = $true }
    executeOnce = $true
    id = 'd0e1f2a3-0000-4b00-9000-cliesmayor001'; name = 'Clientes Mayor Permitidos'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(-380,-160)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
  },
  [ordered]@{
    # Clientes que YA se registraron en la app (tabla perfiles_detal). Tambien les abre la
    # puerta, para no tener que cargarlos a mano. NO decide tarifa: eso lo sigue haciendo
    # "Consultar Mayorista" mas adelante.
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'perfiles_detal'; returnAll = $false; limit = 5; filterType = 'string'; filterString = "={{ 'whatsapp=like.*' + `$('Webhook Evolution API').first().json.body.data.key.remoteJid.split('@')[0].replace(/\D/g,'').slice(-9) }}" }
    executeOnce = $true
    id = 'd0e1f2a3-0000-4b00-9000-perfdetalapp1'; name = 'Perfiles Detal App'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(-520,-300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
  },
  [ordered]@{
    # Lo mismo con los mayoristas registrados en la app (tabla perfiles_mayor).
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'perfiles_mayor'; returnAll = $false; limit = 5; filterType = 'string'; filterString = "={{ 'whatsapp=like.*' + `$('Webhook Evolution API').first().json.body.data.key.remoteJid.split('@')[0].replace(/\D/g,'').slice(-9) }}" }
    executeOnce = $true
    id = 'd0e1f2a3-0000-4b00-9000-perfmayorapp1'; name = 'Perfiles Mayor App'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(-380,-300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
  },
  [ordered]@{
    # Hay una pausa puesta en este chat? La clave la escribe "Redis Guardar Pausa" y se
    # borra sola cuando se vence, asi que si existe es que Kelvin esta atendiendo ahi.
    parameters = @{ operation = 'get'; key = "={{ 'pausaBot:' + `$('Webhook Evolution API').first().json.body.data.key.remoteJid }}"; keyType = 'string'; propertyName = 'pausaBot'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-leerpausa0001'; name = 'Redis Leer Pausa'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(-250,-300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; executeOnce = $true
    credentials = $redisCred
  },
  [ordered]@{
    # Ya se aviso de este chat hace poco? Evita seis avisos cuando el cliente manda seis
    # mensajes seguidos. La clave se borra sola a los $MINUTOS_ENTRE_AVISOS.
    parameters = @{ operation = 'get'; key = "={{ 'avisoPausa:' + `$('Webhook Evolution API').first().json.body.data.key.remoteJid }}"; keyType = 'string'; propertyName = 'avisoPausa'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-leeraviso0001'; name = 'Redis Leer Aviso'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(-250,-420)
    onError = 'continueRegularOutput'; alwaysOutputData = $true; executeOnce = $true
    credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $soloEstosCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(-290,-20); id = 'd0e1f2a3-0000-4b00-9000-soloestos0001'; name = 'Solo Estos Numeros'
  },
  [ordered]@{
    # Por donde sigue cada mensaje, segun lo que decidio el nodo anterior.
    parameters = @{ options = @{}; rules = @{ values = @(
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'p-seguir'; leftValue = '={{ $json.accionPausa }}'; rightValue = 'seguir'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'seguir' },
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'p-pausar'; leftValue = '={{ $json.accionPausa }}'; rightValue = 'pausar'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'pausar' },
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'p-reanudar'; leftValue = '={{ $json.accionPausa }}'; rightValue = 'reanudar'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'reanudar' },
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'p-avisar'; leftValue = '={{ $json.accionPausa }}'; rightValue = 'avisar'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'avisar' },
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'p-entregar'; leftValue = '={{ $json.accionPausa }}'; rightValue = 'entregar'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'entregar' },
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'p-recfoto'; leftValue = '={{ $json.accionPausa }}'; rightValue = 'recordarFoto'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'recordarFoto' },
      # SIEMPRE la ultima: los indices de las salidas de arriba no pueden cambiar.
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'p-mayor'; leftValue = '={{ $json.accionPausa }}'; rightValue = 'mayor'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'mayor' },
      # La operadora pidio verificar los datos de una cuenta (23/11). Despues de 'mayor', por lo mismo.
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'p-verificar'; leftValue = '={{ $json.accionPausa }}'; rightValue = 'verificar'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'verificar' }
    ) } }
    id = 'd0e1f2a3-0000-4b00-9000-routerpausa01'; name = 'Router Pausa'; type = 'n8n-nodes-base.switch'; typeVersion = 3.2; position = @(-150,-20)
  },
  [ordered]@{
    # MAYOR, Fase 1: los grupos de clientes mayoristas que el bot escucha. Un grupo que no este aqui
    # se ignora como siempre. Si Supabase falla o la tabla no existe, el nodo sigue sin filas.
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'grupos_mayor'; returnAll = $true }
    executeOnce = $true
    id = 'e1f2a3b4-0000-4c00-9c00-gruposmayor01'; name = 'Grupos Mayor'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(-816,-880)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
  },
  [ordered]@{
    # MAYOR, Fase 1: le pasa el mensaje al workflow "Mayor: escuchar y registrar" y TERMINA ahi (no sigue
    # a ningun nodo). No espera su respuesta: el bot del detal no se frena por el mayor.
    parameters = @{ source = 'database'; workflowId = @{ __rl = $true; value = $MAYOR_WORKFLOW_ID; mode = 'id' }
                    workflowInputs = @{ mappingMode = 'defineBelow'; value = @{}; matchingColumns = @(); schema = @(); attemptToConvertTypes = $false; convertFieldsToString = $true }
                    mode = 'once'; options = @{ waitForSubWorkflow = $false } }
    id = 'e1f2a3b4-0001-4c00-9c00-mayorescucha01'; name = 'Mayor Escuchar'; type = 'n8n-nodes-base.executeWorkflow'; typeVersion = 1.3; position = @(-1280,-352)
    onError = 'continueRegularOutput'
  },
  [ordered]@{
    # FASE 1 (Operadoras): le pasa entregar / recordarFoto / verificar al workflow "Bot JK - Grupos de Operadoras" sin esperarlo.
    parameters = @{ source = 'database'; workflowId = @{ __rl = $true; value = $OPERADORAS_WORKFLOW_ID; mode = 'id' }
                    workflowInputs = @{ mappingMode = 'defineBelow'; value = @{}; matchingColumns = @(); schema = @(); attemptToConvertTypes = $false; convertFieldsToString = $true }
                    mode = 'once'; options = @{ waitForSubWorkflow = $false } }
    id = 'e1f2a3b4-0002-4c00-9c00-operadoras001'; name = 'Ejecutar Operadoras'; type = 'n8n-nodes-base.executeWorkflow'; typeVersion = 1.3; position = @(60,-500)
    onError = 'continueRegularOutput'
  },
  [ordered]@{
    # Pone la pausa. El TTL se renueva con CADA mensaje de Kelvin, asi que la hora cuenta
    # desde el ultimo que escribio, no desde el primero.
    parameters = @{ operation = 'set'; key = '={{ $json.clave }}'; value = '={{ $json.motivo }}'; keyType = 'string'; expire = $true; ttl = '={{ $json.segundos }}' }
    id = 'd0e1f2a3-0000-4b00-9000-ponerpausa001'; name = 'Redis Guardar Pausa'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(60,-180)
    onError = 'continueRegularOutput'
    credentials = $redisCred
  },
  [ordered]@{
    # "bot on": quita la pausa y el bot vuelve a atender ese chat de inmediato.
    parameters = @{ operation = 'delete'; key = '={{ $json.clave }}' }
    id = 'd0e1f2a3-0000-4b00-9000-quitarpausa01'; name = 'Redis Borrar Pausa'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(60,-300)
    onError = 'continueRegularOutput'
    credentials = $redisCred
  },
  [ordered]@{
    # Un cliente escribio mientras el chat estaba en pausa. No se le contesta, pero se avisa
    # al grupo para que no quede en el aire.
    parameters = @{ resource = 'messages-api'; instanceName = 'BOT JK Kelvin'; remoteJid = $GRUPO_AVISOS; messageText = '={{ $json.aviso }}'; options_message = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-avisarpausa01'; name = 'Avisar Pausa'; type = 'n8n-nodes-evolution-api.evolutionApi'; typeVersion = 1; position = @(60,-60)
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 3000
    onError = 'continueRegularOutput'
    credentials = @{ evolutionApi = @{ id = 'iUIvc9Sd8diFJaGU'; name = 'Evolution PARA n8n cambios JK' } }
  },
  [ordered]@{
    # Deja constancia de que ya se aviso de este chat, para no repetirlo con cada mensaje.
    # Los datos se leen del nodo del filtro, NO de $json: "Avisar Pausa" devuelve la respuesta
    # de Evolution y pisa el item.
    parameters = @{ operation = 'set'; key = "={{ `$('Solo Estos Numeros').first().json.claveAviso }}"; value = '1'; keyType = 'string'; expire = $true; ttl = "={{ `$('Solo Estos Numeros').first().json.segundosAviso }}" }
    id = 'd0e1f2a3-0000-4b00-9000-marcaraviso01'; name = 'Redis Marcar Aviso'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(260,-60)
    onError = 'continueRegularOutput'
    credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ conditions = @{ boolean = @( @{ value1 = '={{ $json.body.data.key.fromMe }}'; value2 = '={{false}}' } ) } }
    id = '4c9f6989-54ed-4990-89d5-283dd59b7ce2'; name = 'Es mensaje de cliente?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(-200,128)
  },
  [ordered]@{
    # FASE 5 (Debounce y Admin): delega el mensaje del cliente al workflow "Bot JK - Debounce y Admin" sin esperarlo.
    # Recibe el item completo de "Es mensaje de cliente?" ({ body, accionPausa, nombreCargado, tarifaCargada }).
    parameters = @{ source = 'database'; workflowId = @{ __rl = $true; value = $DEBOUNCE_ADMIN_WORKFLOW_ID; mode = 'id' }
                    workflowInputs = @{ mappingMode = 'defineBelow'; value = @{}; matchingColumns = @(); schema = @(); attemptToConvertTypes = $false; convertFieldsToString = $true }
                    mode = 'once'; options = @{ waitForSubWorkflow = $false } }
    id = 'e1f2a3b4-0007-4c00-9c00-debadmin0001'; name = 'Ejecutar Debounce'; type = 'n8n-nodes-base.executeWorkflow'; typeVersion = 1.3; position = @(-20,128)
    onError = 'continueRegularOutput'
  }
)

$connections = [ordered]@{
  'Webhook Evolution API'  = @{ main = @( ,@( @{ node='Clientes Detal Permitidos'; type='main'; index=0 } ) ) }
  'Clientes Detal Permitidos' = @{ main = @( ,@( @{ node='Clientes Mayor Permitidos'; type='main'; index=0 } ) ) }
  'Clientes Mayor Permitidos' = @{ main = @( ,@( @{ node='Perfiles Detal App'; type='main'; index=0 } ) ) }
  'Perfiles Detal App'     = @{ main = @( ,@( @{ node='Perfiles Mayor App'; type='main'; index=0 } ) ) }
  'Perfiles Mayor App'     = @{ main = @( ,@( @{ node='Grupos Mayor'; type='main'; index=0 } ) ) }
  'Grupos Mayor'           = @{ main = @( ,@( @{ node='Redis Leer Pausa'; type='main'; index=0 } ) ) }
  'Redis Leer Pausa'       = @{ main = @( ,@( @{ node='Redis Leer Aviso'; type='main'; index=0 } ) ) }
  'Redis Leer Aviso'       = @{ main = @( ,@( @{ node='Solo Estos Numeros'; type='main'; index=0 } ) ) }
  'Avisar Pausa'           = @{ main = @( ,@( @{ node='Redis Marcar Aviso'; type='main'; index=0 } ) ) }
  'Solo Estos Numeros'     = @{ main = @( ,@( @{ node='Router Pausa'; type='main'; index=0 } ) ) }
  'Router Pausa'           = @{ main = (
      @( ,@( @{ node='Es mensaje de cliente?'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Redis Guardar Pausa';   type='main'; index=0 } ) ) +
      @( ,@( @{ node='Redis Borrar Pausa';    type='main'; index=0 } ) ) +
      @( ,@( @{ node='Avisar Pausa';          type='main'; index=0 } ) ) +
      @( ,@( @{ node='Ejecutar Operadoras';   type='main'; index=0 } ) ) +
      @( ,@( @{ node='Ejecutar Operadoras';   type='main'; index=0 } ) ) +
      @( ,@( @{ node='Mayor Escuchar';        type='main'; index=0 } ) ) +
      @( ,@( @{ node='Ejecutar Operadoras';   type='main'; index=0 } ) )
    ) }
  'Es mensaje de cliente?' = @{ main = @( ,@( @{ node='Ejecutar Debounce'; type='main'; index=0 } ) ) }
}

$body = [ordered]@{ name = 'Bot WhatsApp CAMBIOS JK'; nodes = $nodes; connections = $connections; settings = @{ executionOrder = 'v1' } }

$json = $body | ConvertTo-Json -Depth 40
$json | Out-File -FilePath "C:\Users\USER\Documents\APP PARA CAMBIOS JK CONVERSOR\workflow_bot_whatsapp_v12.json" -Encoding utf8
Write-Output ("JSON v12 generado. Longitud: " + $json.Length + " chars. Nodos: " + $nodes.Count)
