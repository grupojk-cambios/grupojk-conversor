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

# Registro en Supabase (tabla transacciones_por_whatsapp): cuantas operaciones del cliente se leen
# en cada mensaje, y hasta cuantos dias atras cuenta la ultima para contestar "¿ya llego?".
$OPERACIONES_A_LEER = 20
$DIAS_ULTIMA_OPERACION = 7

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
const csv = (httpItem && httpItem.json && httpItem.json.data) ? String(httpItem.json.data) : '';

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
  return [{ json: { lista:[], modo, esMayorista, appUrl:APP_URL, hayEfectivoVe:false, totalPaises:0, error:'No se recibieron datos de tasas' } }];
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

return [{ json: { lista, modo, esMayorista, appUrl:APP_URL, hayEfectivoVe, evUbicaciones, totalPaises: paises.length, cuentas, hayCuentas: cuentas.length>0, diaIndex, diaSemanaEc, avisosCuentas, clienteContexto, nombreCliente, paisPorPrefijo, sessionId, error: paises.length? null : 'Lista vacia' } }];
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
  const tasaMostrar = (Math.abs(cross) < 0.005) ? Number(cross.toFixed(6)) : Number(cross.toFixed(2));
  return JSON.stringify({ ok:true, modo:modoN, direccion, origen:o.nombre, monedaOrigen:o.moneda, codigoOrigen:o.codigo, destino:d.nombre, monedaDestino:d.moneda, codigoDestino:d.codigo, monto:montoN, resultado:Number(resultado.toFixed(2)), tasaCruzada:tasaMostrar, explicacion });
}

// 1) Camino rapido y seguro: datos ya cargados por el nodo principal (sincrono)
let _data = _safe(()=>{ if(typeof $getWorkflowStaticData==='function'){ const sd=$getWorkflowStaticData('global'); if(sd && Array.isArray(sd.paisesData) && sd.paisesData.length) return sd.paisesData; } return undefined; });
if(_data && _data.length) return compute(_data);

// 2) Respaldo: descargar el CSV (asincrono) solo si no hubo datos en memoria
if(typeof fetch !== 'function') return JSON.stringify({ ok:false, error:'No pude acceder a las tasas. Pide disculpas y di que un asesor ayudara.' });
const _url='https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv';
return (async () => { try { const res = await fetch(_url + '&nocache=' + Date.now()); const text = await res.text(); return compute(construirPaises(text)); } catch(e){ return JSON.stringify({ ok:false, error:'No pude descargar las tasas: '+e.message }); } })();
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
{{ $('Revisar Operacion').first().json.contextoOperaciones || '' }}

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
- DISPONIBILIDAD (NO te equivoques en esto): la lista de tasas de arriba es la VERDAD absoluta. ANTES de decir que NO manejas algo, BUSCALO en la lista por nombre de pais, por codigo de moneda o por nombre de moneda. Ejemplos de match: "pesos mexicanos"/"mexico"/"mxn" = Mexico; "pesos colombianos"/"cop" = Colombia; "soles" = Peru; "reales" = Brasil. Si el pais/moneda APARECE en la lista con una tasa de Envio o Recibo distinta de "N/D", entonces SI lo manejas en esa direccion: cotiza normal, NUNCA digas que no. Solo responde "Por ahora no manejamos ese servicio" cuando de verdad NO esta en la lista, o ambas tasas (Envio y Recibo) son "N/D". Nunca asumas ni adivines: revisa la lista primero.
- VENEZUELA: hay bolivares (VES, a cuenta/pago movil) y efectivo en dolares ("Efectivo Venezuela"). Regla para NO preguntar de mas: (a) si el cliente YA dijo "Bs"/"bolivares"/"pago movil" -> usa Venezuela (bolivares) y NO preguntes nada de eso. (b) si YA dijo "dolares"/"$"/"efectivo"/"cash" o una ciudad/estado venezolano (Caracas, Maracaibo, Valencia...) -> es Efectivo Venezuela (USD). (c) SOLO pregunta "Lo quieres en bolivares o en efectivo (dolares)?" cuando el cliente va a RECIBIR dinero EN Venezuela y NO dejo claro cual de los dos quiere. (d) si Venezuela es el ORIGEN (el cliente ENVIA Bs hacia otro pais), NUNCA preguntes eso: solo es bolivares. Para efectivo en dolares, pregunta en que ciudad lo retira.
- CUENTAS (REGLA ESTRICTA - UNA SOLA CUENTA POR PAIS POR DIA): en la lista CUENTAS DEL DIA hay EXACTAMENTE UNA cuenta por pais (la del dia de hoy, ya rotada). Cuando el cliente pida datos para pagar / donde deposito / a donde transfiero, busca la cuenta de ese pais en la lista y envia su campo "Datos" TAL CUAL, completo (con todas sus lineas: banco, numero, titular, cedula). NUNCA preguntes "cual banco prefieres", NUNCA ofrezcas alternativas, NUNCA enumeres bancos: solo manda la unica cuenta que hay para ese pais hoy. Si el cliente pide OTRA cuenta / OTRO banco / "una banesco" / "tienes de otro banco" / "mandame otra" (o cualquier variante) DESPUES de que ya le enviaste la del dia, responde EXACTAMENTE UNA linea corta: "Solo esa esta habilitada hoy, usamos una sola cuenta para recibir al dia por pais 🙏". No des explicaciones extra, no ofrezcas escalar, no repitas la cuenta. Solo si NO hay NINGUNA cuenta de ese pais en la lista: "Por ahora no tengo esa cuenta a la mano, un asesor te la pasa enseguida."
- OJO CON EL COMPROBANTE: los datos que vienen DENTRO del corchete "[El cliente envio un COMPROBANTE de pago. Datos leidos: ...]" son del comprobante que el cliente pago (banco de origen, monto, referencia). NO son la cuenta destino. NUNCA los cuentes como si el cliente te hubiera pasado una cuenta.
- ESTADO DE LA OPERACION: si al final del mensaje ves "[ESTADO DE LA OPERACION: ...]", esa nota la pone el sistema despues de revisar la captura y la cuenta de este cliente, y MANDA sobre las reglas de comprobante de abajo: responde exactamente lo que dice. Nunca menciones esa nota al cliente.
- COMPROBANTE DE PAGO: si ves "[El cliente envio un COMPROBANTE de pago...]", NUNCA digas "no tengo esa cuenta". Responde MUY corto, 1 sola linea. Si en el mensaje hay numeros de cuenta/cedula/banco/datos de una cuenta destino (aunque vengan reenviados o en numeros sueltos), confirma: "Listo, recibido! Procesamos tu remesa enseguida ✅" y NO preguntes nada mas. SOLO si NO hay ninguna cuenta en el mensaje, pide corto: "Recibi tu comprobante! 🙌 Pasame la cuenta destino (banco, numero y titular)". La cuenta destino es donde el destinatario RECIBE el dinero; el cliente puede dividir el monto en varias cuentas.
- IMAGEN DE CUENTA: si ves "[El cliente envio una imagen con una CUENTA bancaria...]", trata esos datos como la cuenta destino para su remesa.
- BENEFICIARIOS: nunca ofrezcas cuentas guardadas ni listas de beneficiarios. Si el cliente no manda los datos de la cuenta destino, pideselos simple: banco, numero de cuenta, titular y cedula (y el monto de cada una si son varias).
- YA LLEGO? / COMO VA MI ENVIO? / YA SALIO?: contesta corto con la ULTIMA OPERACION DEL CLIENTE de arriba. EN PROCESO -> "Ya está en proceso 👍 Apenas salga te paso el comprobante por aquí." ENVIADA -> "Sí, ya salió <cuando> ✅ Te pasé el comprobante por aquí." EN ESPERA -> "Se procesa a partir de las 9:00 am 👍". Si arriba NO hay ULTIMA OPERACION DEL CLIENTE -> "Déjame revisar con un asesor y te confirmo enseguida." NUNCA digas que ya llegó si no dice ENVIADA.
- Fuera de tema: "Solo remesas de JK."
- Quejas o problema con un giro: "Un asesor te contacta enseguida."
- Nunca pidas claves, cuentas ni documentos. No des consejo financiero.
- Ver todas las tasas: {{ $node["Code in JavaScript"].json.appUrl }}
{{ $node["Code in JavaScript"].json.hayEfectivoVe ? '- Efectivo Venezuela (dolares en efectivo). El precio PUEDE variar por ciudad, asi que SIEMPRE pregunta el estado/ciudad y calcula con la herramienta usando ESA ubicacion exacta como pais_destino (ej "Efectivo Venezuela Maracaibo"). Ubicaciones disponibles: ' + ($node["Code in JavaScript"].json.evUbicaciones || []).map(u => u.estado + (u.ciudades && u.ciudades.length ? ' (' + u.ciudades.join(', ') + ')' : '')).join('; ') + '. Si la ciudad NO esta en la lista, ahi no hay entrega en efectivo por ahora.' : '' }}

TONO (asi contesta Kelvin a sus clientes): corto, directo y cercano. Nunca uses 😊. PROHIBIDO usar frases de relleno como "aqui estoy", "estoy aqui", "disponible", "con gusto", "quedo atento", "para ayudarte", "cualquier consulta", "no dudes en". Responde lo justo y para. Suena como una persona, no como un bot.
Ejemplos (cliente -> tu):
- "Hola buen dia" -> "Hola, buen día 👋 Dime, ¿qué necesitas?"
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

return [{ json: { jid, texto: texto || '', miTs, esComprobante, espera, idMensaje,
                  keyBuf: 'buf:'+jid, keyTok: 'tok:'+jid } }];
'@

$prepCode = $prepCode.Replace('__ESPERA_OPERACION__', [string]$SEGUNDOS_ESPERA_OPERACION)
$prepCode = $prepCode.Replace('__ESPERA_NORMAL__', [string]$SEGUNDOS_ESPERA)

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
$leerImagenPrompt = 'Esta imagen la envio un cliente de una casa de cambio de remesas por WhatsApp. Clasificala y responde SOLO en JSON valido sin texto extra: {"tipo": "comprobante|cuenta|otra", "resumen": "datos clave en una sola linea"}. comprobante = recibo o captura de un pago/transferencia que el cliente hizo (extrae monto, banco, fecha, referencia). cuenta = datos de una cuenta bancaria (extrae banco, numero de cuenta, titular, cedula). otra = cualquier otra cosa.'

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
    const n = trozo[0].match(/monto[^0-9]{0,12}([0-9]+(?:[.,][0-9]{1,2})?)/i);
    if (n){ const v = parseFloat(n[1].replace(',', '.')); if (!isNaN(v)) montoComprobante = v; }
  }
} catch(e){}

// La foto que se publica en el grupo es la de la CAPTURA, aunque despues el cliente haya mandado
// otra imagen (ej. la foto de la cuenta).
const idImagen = desdeOperacion ? String(ro.idImagen || '') : '';

return [{ json: { aprobado: true, jid, nombre, nombreMostrar, numero, datosCuenta, idCuenta,
                  montoComprobante, idImagen, mensajeCombinado: combinado } }];
'@

# ===================== CODIGO: SEPARAR CUENTAS (1 mensaje por cuenta) =====================
$separarCuentasCode = @'
// Una publicacion por cada cuenta que mando el cliente, con una cabecera que diga de quien
// es y por cuanto. Antes salia el bloque pelado y la operadora no sabia de quien era.
//
// Se recorre mensaje por mensaje (no el texto junto) para que cada publicacion conserve el
// id del mensaje del que salio: asi, cuando la operadora devuelva el comprobante, se le cita
// al cliente el mensaje correcto aunque haya mandado las cuentas en varios mensajes.
const ap = $('Detectar Aprobación').item.json;
const nombre = ap.nombreMostrar || ap.nombre || 'Cliente';

let lista = [];
try {
  const ro = $('Revisar Operacion').first().json || {};
  lista = (ro.mensajesAprobar !== undefined) ? (ro.mensajesAprobar || []) : ($('Combinar').item.json.mensajes || []);
} catch(e){ try { lista = $('Combinar').item.json.mensajes || []; } catch(e2){} }

// Las notas que escribe el propio bot al leer una imagen no son cuentas del cliente.
function limpiar(t){
  return String(t || '')
    .replace(/\[El cliente envio un COMPROBANTE[^\]]*\]/gi, '')
    .replace(/\[El cliente envio una imagen que no parece[^\]]*\]/gi, '')
    .replace(/\[El cliente envio una imagen con una CUENTA bancaria\.?\s*Datos:\s*([^\]]*)\]/gi, 'Cuenta (imagen): $1')
    .trim();
}

// Monto del bloque: "$30", "30$", "30 usd", "$30,50". Si no hay, null.
// Primero se busca "$30" y despues "30$" EN LA MISMA LINEA. Con el salto de linea permitido, una
// cedula con "$60" en la linea de abajo salia como monto ("Ci 11111111 / $60" -> $11111111).
function montoDe(t){
  const s = String(t);
  const m = s.match(/\$[ 	]*([0-9]+(?:[.,][0-9]{1,2})?)/) || s.match(/([0-9]+(?:[.,][0-9]{1,2})?)[ 	]*(?:\$|usd|dolares|dolar)/i);
  if (!m) return null;
  const v = parseFloat(String(m[1]).replace(',', '.'));
  return isNaN(v) ? null : v;
}

const CLAVES = ['bancolombia','nequi','pago movil','banco','cuenta','titular','cedula','cc ',' ci ',
                'swift','interbank','binance','zelle','pichincha','guayaquil','produbanco','pacifico',
                'bancolombia','ahorro','corriente','banesco','mercantil','provincial','bdv','bicentenario',
                'bancamiga','davivienda','daviplata','plin','yape','paypal','usdt','wallet','billetera'];
// Un bloque tambien es una cuenta si trae un numero largo o un correo, aunque no diga "banco":
// asi no se pierde el caso del 20/11 (pais, cuenta de 20 digitos, titular, cedula, monto).
function esBloqueCuenta(bloque){
  const bajo = ' ' + bloque.toLowerCase() + ' ';
  if (CLAVES.some(k => bajo.indexOf(k) !== -1)) return true;
  if (/[0-9]{10,}/.test(bajo.replace(/([0-9])[ .-](?=[0-9])/g, '$1'))) return true;
  return /[^ @]+@[^ @]+\.[a-z]{2,}/.test(bajo);
}

const items = [];
for (const m of lista){
  const t = limpiar(m && m.texto);
  if (!t) continue;
  for (const trozo of t.split(/\n\s*\n+/)){
    const bloque = trozo.trim();
    if (!bloque) continue;
    const bajo = bloque.toLowerCase();
    if (!esBloqueCuenta(bloque)) continue;   // no parece una cuenta
    const monto = montoDe(bloque);
    const cabecera = nombre + (monto !== null ? ' - $' + monto : '');
    items.push({ json: { cuenta: cabecera + '\n\n' + bloque, idCuenta: (m && m.id) || '', monto } });
  }
}

// Si no se reconocio ningun bloque (el cliente lo escribio de una forma rara), se manda lo
// que haya tal cual, como se hacia antes: es preferible a dejar a la operadora sin la cuenta.
if (!items.length){
  const todo = String(ap.datosCuenta || '').trim();
  if (todo) items.push({ json: { cuenta: nombre + '\n\n' + todo, idCuenta: ap.idCuenta || '', monto: null } });
}
return items;
'@

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

# ===================== CODIGO: ARMAR FILA SUPABASE (registro de la operacion) =====================
$armarFilaCode = @'
// ===== LA FILA PARA SUPABASE (tabla transacciones_por_whatsapp) =====
// Una fila por cada operacion completa (captura + cuenta) que el bot pasa a transferir. Cuando la
// operadora devuelve la foto del envio, "Marcar Enviada en Supabase" la pasa a 'enviada'.
// Los campos se llaman EXACTAMENTE como las columnas de la tabla: el nodo siguiente los guarda tal cual.
const ap = $('Detectar Aprobación').first().json || {};
let ro = {};
try { ro = $('Revisar Operacion').first().json || {}; } catch(e){ ro = {}; }
const reg = ro.registro || {};
const capturas = Array.isArray(reg.capturas) ? reg.capturas : [];
const cuentas = Array.isArray(reg.cuentas) ? reg.cuentas : [];
function aNumero(s){ const v = parseFloat(String(s).replace(',', '.')); return isNaN(v) ? null : v; }
// El monto de cada cuenta, igual que "Separar Cuentas": primero "$60", si no "60$".
function montoDe(t){
  const s = String(t || '');
  const m = s.match(/\$[ \t]*([0-9]+(?:[.,][0-9]{1,2})?)/) || s.match(/([0-9]+(?:[.,][0-9]{1,2})?)[ \t]*(?:\$|usd|dolares|dolar)/i);
  return m ? aNumero(m[1]) : null;
}
const montos = capturas.map(c => c.monto).filter(m => typeof m === 'number' && !isNaN(m));
const unicos = a => a.filter((x, i) => x && a.indexOf(x) === i);
const fila = {
  whatsapp: String(ap.numero || ap.jid || '').replace(/\D/g, ''),
  nombre_cliente: ap.nombre || null,
  estado: 'en_proceso',
  monto_deposito: montos.length ? Math.round(montos.reduce((a, b) => a + b, 0) * 100) / 100 : null,
  ref_deposito: unicos(capturas.map(c => c.ref)).join(', ') || null,
  banco_origen: unicos(capturas.map(c => c.banco)).join(', ') || null,
  huella_foto: (capturas.find(c => c.huella) || {}).huella || null,
  id_msg_captura: ap.idImagen || (capturas[0] || {}).id || null,
  capturas,
  cuentas: cuentas.map(c => ({ id: c.id || '', texto: c.texto, monto: montoDe(c.texto) })),
  fuera_de_horario: false,
  publicado_en: new Date().toISOString()
};
return [{ json: fila }];
'@

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
if (esGrupo && !img && citado){
  // Cito con texto. Solo cuenta si es algo CORTO ("." , "ok", "listo"): asi, discutir sobre
  // un pedido citandolo no dispara una entrega por accidente. La foto sale de la recordada.
  if (texto.length <= 12){
    return [{ json: { accionPausa: 'entregar', stanzaId: citado,
                      claveGrupoMsg: 'grupoMsg:' + citado,
                      claveEntregado: 'entregado:' + citado,
                      claveFoto: claveFoto,
                      idFoto: '', jidGrupo: jid } }];
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

const comun = {
  jid: p.jid,
  nombre: p.nombre || 'el cliente',
  idCuenta: p.idCuenta || '',        // para citarle el mensaje donde dio sus datos bancarios
  idCaptura: p.idCaptura || '',      // la captura del deposito: asi se marca "enviada" en Supabase
  stanzaId: base.stanzaId,           // la publicacion citada, para citarla al confirmar
  claveEntregado: base.claveEntregado,
  jidGrupo: base.jidGrupo
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
const ahora = Date.now();

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
const vigente = x => !!x && typeof x.ts === 'number' && (ahora - x.ts) <= MINUTOS_PENDIENTE * 60000;
const cuentaGuardada = (op.cuenta && vigente(op.cuenta) && Array.isArray(op.cuenta.mensajes)) ? op.cuenta.mensajes : [];
const capturasGuardadas = Array.isArray(op.capturas) ? op.capturas.filter(vigente) : [];
const hechos = Array.isArray(op.hechos) ? op.hechos.filter(h => h && (ahora - (h.ts || 0)) <= HORAS_RECORDAR * 3600000) : [];

// ---------- las operaciones ya registradas en Supabase (tabla transacciones_por_whatsapp) ----------
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
  const m = sinHuella(t).match(/monto[^0-9]{0,15}([0-9][0-9.,]*)/i);
  if (!m) return null;
  const v = numero(m[1]);
  return isNaN(v) ? null : v;
}
function refDe(t){
  const m = sinHuella(t).match(/(referencia|ref\.?|transacci[oó]n|documento|confirmaci[oó]n|operaci[oó]n|n[uú]mero)[^0-9\]]{0,25}([0-9]{4,})/i);
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
const hayCaptura = capturas.length > 0 || capturasGuardadas.length > 0;
const cuentasAhora = [];
for (const m of mensajes){
  const resto = textoDelCliente(String((m && m.texto) || ''));
  if (!resto || esCuentaNuestra(resto)) continue;
  if (pideLaMisma(resto) && !datosFirmes(resto)) continue;      // "a la misma cuenta de siempre" no ES una cuenta
  const esCuenta = datosFirmes(resto) || (hayCaptura && resto.indexOf('?') === -1 && pareceCuenta(resto));
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
  const filaCuenta = historial.find(r => r.estado !== 'cancelada' && listaDe(r.cuentas).some(c => c && c.texto));
  const cs = filaCuenta ? listaDe(filaCuenta.cuentas).filter(c => c && c.texto) : [];
  if (cs.length === 1){                       // si la vez pasada fueron varias, se le piden los datos
    const texto = sinMontos(cs[0].texto);
    if (texto) propuestaNueva = { mensajes: [{ id: '', texto }], ts: ahora };
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
// Si la misma cuenta llega otra vez MAS COMPLETA (ej. ahora con el banco y el titular), se queda
// la version mas completa.
function unirCuentas(a, b){
  const out = [], donde = {};
  for (const m of a.concat(b)){
    const clave = datosDe(m.texto).sort().join('|') || String(m.texto).trim().toLowerCase();
    const nueva = { id: m.id || '', texto: m.texto };
    if (donde[clave] === undefined){ donde[clave] = out.length; out.push(nueva); continue; }
    if (String(m.texto).length > String(out[donde[clave]].texto).length) out[donde[clave]] = nueva;
  }
  return out;
}
const capturasOp = capturasGuardadas.concat(nuevas);
const cuentasOp = unirCuentas(cuentaGuardada, cuentasAhora);

let estado = 'nada';
if (todasRepetidas) estado = 'repetido';
else if (capturasOp.length && cuentasOp.length) estado = 'completo';
else if (capturasOp.length && propuestaNueva) estado = 'confirmar_cuenta';
else if (capturasOp.length) estado = 'falta_cuenta';
else if (cuentasAhora.length) estado = 'falta_captura';

const NOTA = {
  completo:      'ya tengo la captura del deposito y la cuenta destino de este cliente; se pasaron a operaciones. Responde SOLO: "Listo, recibido! Procesamos tu remesa enseguida ✅"',
  falta_cuenta:  'ya tengo la captura del deposito pero todavia NO tengo la cuenta destino. Responde SOLO: "Recibi tu comprobante! 🙌 Pasame la cuenta destino (banco, numero y titular)"',
  falta_captura: 'el cliente ya paso la cuenta destino pero todavia NO mando la captura del deposito. Si pregunto algo, respondelo; y pidele corto: "Recibi los datos de la cuenta 👍 Cuando hagas el deposito, enviame la captura"',
  repetido:      'esa captura es de un deposito que YA se habia recibido y pasado a operaciones: esta repetida. NO la proceses de nuevo. Responde SOLO: "Ese deposito ya lo recibi, esta repetido 👍 Si es un deposito distinto, avisame"'
};
if (propuestaNueva) NOTA.confirmar_cuenta = 'el cliente quiere usar la misma cuenta destino de la vez pasada. Responde SOLO esto, con la cuenta copiada tal cual: "¿Te lo envío a esta cuenta? 👇\n\n' + propuestaNueva.mensajes[0].texto + '\n\nResponde *sí* para confirmar"';
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
} else if (estado === 'falta_cuenta' || estado === 'confirmar_cuenta'){
  nueva.capturas = capturasOp.map(c => ({ id: c.id, texto: c.texto, ts: c.ts, ref: c.ref, monto: c.monto, huella: c.huella,
                                         banco: c.banco || '', destino: c.destino || '' }));
  if (propuestaNueva) nueva.cuentaPropuesta = propuestaNueva;
} else if (estado === 'falta_captura'){
  nueva.cuenta = { mensajes: cuentasOp, ts: ahora };
} else {
  // repetido o nada: lo que estaba pendiente sigue pendiente
  nueva.cuenta = cuentaGuardada.length ? { mensajes: cuentaGuardada, ts: op.cuenta.ts } : null;
  nueva.capturas = capturasGuardadas;
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
  const nCuentas = listaDe(ultima.cuentas).length;
  let txt = 'ULTIMA OPERACION DEL CLIENTE (usala solo si pregunta si ya llego o como va su envio): recibida ' + cuando(msUltima)
    + ((ultima.monto_deposito !== null && ultima.monto_deposito !== undefined) ? ', deposito de $' + Number(ultima.monto_deposito).toFixed(2) : '')
    + (nCuentas ? ', ' + nCuentas + (nCuentas === 1 ? ' cuenta destino' : ' cuentas destino') : '') + '. Estado: ';
  const msEnviada = Date.parse(ultima.enviada_en);
  if (ultima.estado === 'enviada') txt += 'ENVIADA' + (msEnviada ? ' ' + cuando(msEnviada) : '') + ' (ya se le reenvio el comprobante por este chat).';
  else if (ultima.estado === 'en_espera') txt += 'EN ESPERA (llego fuera de horario; se procesa al abrir).';
  else if (ultima.estado === 'en_proceso') txt += 'EN PROCESO (ya esta con la operadora; falta que mande el comprobante).';
  else txt += String(ultima.estado || '').toUpperCase() + '.';
  contextoOperaciones = txt;
}

return [{ json: Object.assign({}, base, {
  estadoOperacion: estado,
  contextoOperaciones,
  registro,
  accion,
  motivoAccion,
  reglaNombre,
  notaIA,
  textoAprobar,
  mensajesAprobar,
  idImagen,
  operacionNueva: JSON.stringify(nueva),
  capturasLeidas: capturas.map(c => ({ ref: c.ref, monto: c.monto, clase: c.clase }))
}), pairedItem: { item: 0 } }];
'@
$revisarOperacionCode = $revisarOperacionCode.Replace('__MINUTOS_PENDIENTE__', [string]$MINUTOS_OPERACION_PENDIENTE)
$revisarOperacionCode = $revisarOperacionCode.Replace('__MINUTOS_MISMO_DEPOSITO__', [string]$MINUTOS_MISMO_DEPOSITO)
$revisarOperacionCode = $revisarOperacionCode.Replace('__HORAS_RECORDAR__', [string]$HORAS_MEMORIA_OPERACION)
$revisarOperacionCode = $revisarOperacionCode.Replace('__MINUTOS_STICKER_GRACIAS__', [string]$MINUTOS_ENTRE_STICKERS_GRACIAS)
$revisarOperacionCode = $revisarOperacionCode.Replace('__HORAS_NOMBRE__', [string]$HORAS_ENTRE_NOMBRES)
$revisarOperacionCode = $revisarOperacionCode.Replace('__DIAS_ULTIMA_OPERACION__', [string]$DIAS_ULTIMA_OPERACION)

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
    # La operadora mando una foto SUELTA: se recuerda unos minutos por si despues cita con
    # un punto. La clave lleva quien la mando, para no mezclar operadoras.
    parameters = @{ operation = 'set'; key = '={{ $json.claveFoto }}'; value = '={{ $json.idFoto }}'; keyType = 'string'; expire = $true; ttl = $MINUTOS_RECORDAR_FOTO * 60 }
    id = 'd0e1f2a3-0000-4b00-9000-guardafoto001'; name = 'Redis Guardar Ultima Foto'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(60,-660)
    onError = 'continueRegularOutput'
    credentials = $redisCred
  },
  [ordered]@{
    # La ultima foto suelta de quien acaba de citar, por si cito con un punto.
    parameters = @{ operation = 'get'; key = "={{ `$('Solo Estos Numeros').first().json.claveFoto }}"; keyType = 'string'; propertyName = 'ultimaFoto'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-leerfoto00001'; name = 'Redis Leer Ultima Foto'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(300,-500)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = $redisCred
  },
  [ordered]@{
    # Entregar o avisar que ya se entrego?
    parameters = @{ conditions = @{ boolean = @( @{ value1 = '={{ $json.accion }}'; value2 = 'repetido'; operation = 'equals' } ) } }
    id = 'd0e1f2a3-0000-4b00-9000-esrepetido001'; name = 'Ya Se Entrego?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(460,-420)
  },
  [ordered]@{
    # Aviso de capture repetido, citando la misma publicacion.
    parameters = @{ method = 'POST'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'; jsonBody = '={{ JSON.stringify({ number: $json.jidGrupo, text: ("OJO: " + $json.aviso), quoted: { key: { id: $json.stanzaId } } }) }}'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-avisarepeti01'; name = 'Avisar Repetido'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(620,-360)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    # Si la cita no la soporta esta version de Evolution, el envio falla. Aqui se detecta
    # para reintentar sin cita: una cita que no funcione NUNCA puede dejar a un cliente sin
    # su comprobante.
    parameters = @{ conditions = @{ boolean = @( @{ value1 = '={{ !!$json.error }}'; value2 = '={{true}}' } ) } }
    id = 'd0e1f2a3-0000-4b00-9000-fallocita0001'; name = 'Fallo la Cita?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(860,-560)
  },
  [ordered]@{
    parameters = @{ method = 'POST'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; url = 'http://evolution-api:8080/message/sendMedia/BOT%20JK%20Kelvin'; jsonBody = '={{ JSON.stringify({ number: $("Revisar Pedido").first().json.jid, mediatype: "image", mimetype: ($("Bajar Foto Operadora").first().json.mimetype || "image/jpeg"), media: $("Bajar Foto Operadora").first().json.base64 }) }}'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-envsincita001'; name = 'Enviar Comprobante sin Cita'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1020,-620)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 1500; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    parameters = @{ conditions = @{ boolean = @( @{ value1 = '={{ !!$json.error }}'; value2 = '={{true}}' } ) } }
    id = 'd0e1f2a3-0000-4b00-9000-fallocitag001'; name = 'Fallo la Cita del Grupo?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(1340,-500)
  },
  [ordered]@{
    parameters = @{ method = 'POST'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'; jsonBody = '={{ JSON.stringify({ number: $("Revisar Pedido").first().json.jidGrupo, text: ("Enviado a " + $("Revisar Pedido").first().json.nombre + " OK") }) }}'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-confsincita01'; name = 'Confirmar sin Cita'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1500,-560)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $revisarMontosCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(3460,400); id = 'd0e1f2a3-0000-4b00-9000-revisarmont01'; name = 'Revisar Montos'
    executeOnce = $true
  },
  [ordered]@{
    parameters = @{ method = 'POST'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'; jsonBody = '={{ JSON.stringify({ number: "' + $GRUPO_OPERACIONES + '", text: $json.aviso }) }}'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-avisarmonto01'; name = 'Avisar Montos'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(3640,400)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    # Era una publicacion del bot el mensaje que cito la operadora?
    parameters = @{ operation = 'get'; key = '={{ $json.claveGrupoMsg }}'; keyType = 'string'; propertyName = 'pedido'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-leerpublic001'; name = 'Redis Leer Publicacion'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(60,-500)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = $redisCred
  },
  [ordered]@{
    # Ya se le mando el comprobante a ese cliente por esta misma publicacion?
    parameters = @{ operation = 'get'; key = "={{ `$('Solo Estos Numeros').first().json.claveEntregado }}"; keyType = 'string'; propertyName = 'entregado'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-leerentreg001'; name = 'Redis Leer Entregado'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(220,-500)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $revisarPedidoCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(380,-500); id = 'd0e1f2a3-0000-4b00-9000-revisarped001'; name = 'Revisar Pedido'
  },
  [ordered]@{
    # Se vuelve a bajar la foto de la operadora desde Evolution para poder reenviarla.
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/chat/getBase64FromMediaMessage/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "message": { "key": { "id": "{{ $json.idFoto }}" } }, "convertToMp4": false }'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-bajarfoto0001'; name = 'Bajar Foto Operadora'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(540,-500)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 1500; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    # La foto va al cliente CITANDO el mensaje donde el escribio sus datos bancarios, para que
    # quede claro a que cuenta corresponde ese pago. Si no se supo cual era, se manda sin citar.
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendMedia/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={{ JSON.stringify(Object.assign({ number: $("Revisar Pedido").first().json.jid, mediatype: "image", mimetype: ($json.mimetype || "image/jpeg"), media: $json.base64 }, $("Revisar Pedido").first().json.idCuenta ? { quoted: { key: { id: $("Revisar Pedido").first().json.idCuenta } } } : {})) }}'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-enviarcompr01'; name = 'Enviar Comprobante al Cliente'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(700,-500)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 1500; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendSticker/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "number": "{{ $("Revisar Pedido").first().json.jid }}", "sticker": "https://grupojk-cambios.github.io/grupojk-conversor/logos/sticker-pedido-pagado.webp" }'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-stickpagado01'; name = 'Sticker Pedido Pagado'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(860,-500)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    # Confirmacion en el grupo, citando la misma publicacion que respondio la operadora, para
    # que se vea de que pedido se trata y nadie lo mande dos veces.
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={{ JSON.stringify({ number: $("Revisar Pedido").first().json.jidGrupo, text: ("Enviado a " + $("Revisar Pedido").first().json.nombre + " OK"), quoted: { key: { id: $("Revisar Pedido").first().json.stanzaId } } }) }}'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-confirmgrup01'; name = 'Confirmar en el Grupo'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1020,-500)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = "={{ `$('Revisar Pedido').first().json.claveEntregado }}"; value = '1'; keyType = 'string'; expire = $true; ttl = $SEG_MEMORIA_OPERACION }
    id = 'd0e1f2a3-0000-4b00-9000-marcaentreg01'; name = 'Redis Marcar Entregado'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1180,-500)
    onError = 'continueRegularOutput'
    credentials = $redisCred
  },
  [ordered]@{
    # La operadora devolvio la foto y ya le llego al cliente: la operacion queda 'enviada'.
    # Se busca por la captura del deposito (viaja en grupoMsg). Solo si estaba en proceso.
    parameters = @{ resource = 'row'; operation = 'update'; tableId = 'transacciones_por_whatsapp'; filterType = 'string'; filterString = "={{ 'id_msg_captura=eq.' + (`$('Revisar Pedido').first().json.idCaptura || 'sin-dato') + '&estado=in.(en_proceso,en_espera)' }}"; dataToSend = 'defineBelow'; fieldsUi = @{ fieldValues = @( @{ fieldId = 'estado'; fieldValue = 'enviada' }, @{ fieldId = 'enviada_en'; fieldValue = '={{ $now.toISO() }}' } ) } }
    id = 'a1b2c3d4-0011-4e00-9a00-registro00011'; name = 'Marcar Enviada en Supabase'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(1408,-752)
    onError = 'continueRegularOutput'
    credentials = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
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
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'p-recfoto'; leftValue = '={{ $json.accionPausa }}'; rightValue = 'recordarFoto'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'recordarFoto' }
    ) } }
    id = 'd0e1f2a3-0000-4b00-9000-routerpausa01'; name = 'Router Pausa'; type = 'n8n-nodes-base.switch'; typeVersion = 3.2; position = @(-150,-20)
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
    # Llego un comprobante? Entonces se le manda el sticker de "verificando su deposito"
    # enseguida, sin esperar, para que el cliente sepa que se recibio.
    parameters = @{ conditions = @{ boolean = @( @{ value1 = '={{ $json.esComprobante }}'; value2 = '={{true}}' } ) } }
    id = 'd0e1f2a3-0000-4b00-9000-escomprob0001'; name = 'Llego un Comprobante?'; type = 'n8n-nodes-base.if'; typeVersion = 1; position = @(300,-120)
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendSticker/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "number": "{{ $("Prep Debounce").first().json.jid }}", "sticker": "https://grupojk-cambios.github.io/grupojk-conversor/logos/sticker-verificando-su-deposito.webp" }'; options = @{} }
    id = 'd0e1f2a3-0000-4b00-9000-stickerverif1'; name = 'Sticker Verificando'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(460,-120)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $prepCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(140,128); id = 'c1a2b3c4-1111-4a11-9111-prep00000001'; name = 'Prep Debounce'
  },
  [ordered]@{
    parameters = @{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'aud-cond-1'; leftValue = '={{ $json.body.data.messageType }}'; rightValue = 'audioMessage'; operator = @{ type = 'string'; operation = 'equals' } } ); combinator = 'and' } }
    id = 'd0a1b2c3-e4f5-4060-9788-esaudio00001'; name = 'Es Audio?'; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(-60,60)
  },
  [ordered]@{
    parameters = @{ jsCode = $textoDirectoCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(-60,220); id = 'e1f2a3b4-c5d6-4071-9899-txtdirecto01'; name = 'Texto Directo'
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/chat/getBase64FromMediaMessage/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "message": { "key": { "id": "{{ $json.body.data.key.id }}" } }, "convertToMp4": false }'; options = @{} }
    id = 'f2a3b4c5-d6e7-4082-9900-getbase64001'; name = 'Descargar Audio'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(120,-60)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 2000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $toBinarioCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(300,-60); id = 'a3b4c5d6-e7f8-4093-9a11-tobinario001'; name = 'Audio a Binario'
  },
  [ordered]@{
    parameters = @{ resource = 'audio'; operation = 'transcribe'; binaryPropertyName = 'data'; options = @{ language = 'es' } }
    id = 'b4c5d6e7-f8a9-4004-9b22-transcribe01'; name = 'Transcribir Audio'; type = '@n8n/n8n-nodes-langchain.openAi'; typeVersion = 1.8; position = @(480,-60)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 2000; alwaysOutputData = $true
    credentials = @{ openAiApi = @{ id = '44lRGIyEnSk1lMc5'; name = 'cambios jk para n8n' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $textoAudioCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(660,-60); id = 'c5d6e7f8-a9b0-4015-9c33-txtaudio0001'; name = 'Texto de Audio'
  },
  [ordered]@{
    parameters = @{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'img-cond-1'; leftValue = '={{ $json.body.data.messageType }}'; rightValue = 'imageMessage'; operator = @{ type = 'string'; operation = 'equals' } } ); combinator = 'and' } }
    id = 'd1e2f3a4-b5c6-4170-9080-esimagen0001'; name = 'Es Imagen?'; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(-60,380)
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/chat/getBase64FromMediaMessage/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "message": { "key": { "id": "{{ $json.body.data.key.id }}" } }, "convertToMp4": false }'; options = @{} }
    id = 'f3a4b5c6-d7e8-4181-9191-getimg000001'; name = 'Descargar Imagen'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(120,460)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 2000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $toBinarioImgCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(300,460); id = 'a4b5c6d7-e8f9-4192-9a22-tobinimg0001'; name = 'Imagen a Binario'
  },
  [ordered]@{
    parameters = @{ resource = 'image'; operation = 'analyze'; modelId = @{ __rl = $true; value = 'gpt-4o-mini'; mode = 'list'; cachedResultName = 'gpt-4o-mini' }; inputType = 'base64'; binaryPropertyName = 'data'; text = $leerImagenPrompt; options = @{} }
    id = 'b5c6d7e8-f9a0-4103-9b33-leerimg00001'; name = 'Leer Imagen'; type = '@n8n/n8n-nodes-langchain.openAi'; typeVersion = 1.8; position = @(480,460)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 2000; alwaysOutputData = $true
    credentials = @{ openAiApi = @{ id = '44lRGIyEnSk1lMc5'; name = 'cambios jk para n8n' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $textoImagenCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(660,460); id = 'c6d7e8f9-a0b1-4114-9c44-txtimg000001'; name = 'Texto de Imagen'
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = "={{ 'lastimg:' + `$('Webhook Evolution API').item.json.body.data.key.remoteJid }}"; value = "={{ `$json.imgKeyId }}"; keyType = 'string'; expire = $true; ttl = 86400 }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(840,460); id = 'd7e8f9a0-b1c2-4125-9d55-rsetimg00001'; name = 'Redis Guardar Imagen'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ operation = 'push'; list = "={{ `$('Prep Debounce').item.json.keyBuf }}"; messageData = "={{ JSON.stringify({ id: `$('Prep Debounce').item.json.idMensaje, texto: `$('Prep Debounce').item.json.texto }) }}"; tail = $true }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(160,128); id = 'c2a2b3c4-2222-4a22-9222-rpush0000001'; name = 'Redis Guardar Msg'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = "={{ `$('Prep Debounce').item.json.keyTok }}"; value = "={{ `$('Prep Debounce').item.json.miTs }}"; keyType = 'string'; expire = $true; ttl = 120 }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(340,128); id = 'c3a2b3c4-3333-4a33-9333-rset00000001'; name = 'Redis Marcar Token'; credentials = $redisCred
  },
  [ordered]@{
    # Los segundos los decide "Prep Debounce": mas si llego un comprobante.
    parameters = @{ amount = "={{ `$('Prep Debounce').first().json.espera }}"; unit = 'seconds' }
    type = 'n8n-nodes-base.wait'; typeVersion = 1.1; position = @(520,128); id = 'd2b3c4d5-4444-4a44-9444-wait00000001'; name = 'Esperar 30s'; webhookId = 'e7c1a2b3-5555-4a55-9555-waithook0001'
  },
  [ordered]@{
    parameters = @{ operation = 'get'; key = "={{ `$('Prep Debounce').item.json.keyTok }}"; propertyName = 'tokenActual'; keyType = 'string'; options = @{} }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(700,128); id = 'c4a2b3c4-6666-4a66-9666-rget00000001'; name = 'Redis Leer Token'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $filtrarCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(880,128); id = 'f3c4d5e6-7777-4a77-9777-filtrar00001'; name = 'Filtrar Ultimo'
  },
  [ordered]@{
    parameters = @{ operation = 'get'; key = "={{ `$('Prep Debounce').item.json.keyBuf }}"; propertyName = 'mensajes'; keyType = 'list'; options = @{} }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1060,128); id = 'c5a2b3c4-8888-4a88-9888-rgetlist0001'; name = 'Redis Leer Mensajes'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ operation = 'delete'; key = "={{ `$('Prep Debounce').item.json.keyBuf }}" }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1240,128); id = 'c6a2b3c4-9999-4a99-9999-rdel00000001'; name = 'Redis Borrar Buffer'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $combinarCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1420,128); id = 'a7b8c9d0-aaaa-4aaa-9aaa-combinar0001'; name = 'Combinar'
  },
  [ordered]@{
    # Trae TODOS los perfiles con role='admin' en perfiles_detal (Kelvin, Dario, quien se agregue despues).
    # Se usa para el comando "modo mayor"/"modo detal" (Detectar Comando Admin). Nunca afecta a clientes.
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'perfiles_detal'; returnAll = $false; limit = 20; filterType = 'string'; filterString = 'role=eq.admin' }
    id = 'f3a4b5c6-1234-4d99-9e11-supaadmin0001'; name = 'Consultar Admins'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(1420,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $detectarComandoAdminCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1490,300); id = 'f4a5b6c7-2345-4d10-9e22-detcomando01'; name = 'Detectar Comando Admin'
  },
  [ordered]@{
    parameters = @{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'admin-cond-1'; leftValue = '={{ $json.esComandoModo }}'; rightValue = $true; operator = @{ type = 'boolean'; operation = 'equals' } } ); combinator = 'and' } }
    id = 'f5a6b7c8-3456-4d21-9e33-escomando001'; name = '¿Es Comando Admin?'; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(1560,300)
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = "={{ 'modoAdmin:' + `$json.jid }}"; value = '={{ $json.modoElegido }}'; keyType = 'string'; expire = $true; ttl = 2592000 }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1630,220); id = 'f6a7b8c9-4567-4d32-9e44-rsetmodo0001'; name = 'Redis Guardar Modo Admin'; credentials = $redisCred
  },
  [ordered]@{
    # ¿El mensaje era SOLO el comando, o venia con una pregunta pegada?
    # Si venia algo mas, se sigue al flujo normal y se responde con la tarifa recien guardada
    # (el modo se lee mas adelante, en "Redis Leer Modo Admin", asi que ya toma el valor nuevo).
    parameters = @{ conditions = @{ options = @{ caseSensitive = $true; leftValue = ''; typeValidation = 'loose' }; conditions = @( [ordered]@{ id = 'solo-cmd-1'; leftValue = "={{ `$('Detectar Comando Admin').first().json.soloComando }}"; rightValue = $true; operator = @{ type = 'boolean'; operation = 'equals' } } ); combinator = 'and' } }
    id = 'f9a0b1c2-7890-4d65-9e77-solocomando1'; name = '¿Solo el Comando?'; type = 'n8n-nodes-base.if'; typeVersion = 2.2; position = @(1700,150)
  },
  [ordered]@{
    parameters = @{ jsCode = $confirmarModoAdminCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1700,220); id = 'f7a8b9c0-5678-4d43-9e55-confmodo0001'; name = 'Confirmar Modo Admin'
  },
  [ordered]@{
    parameters = @{ url = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv'; options = @{} }
    id = 'd117ce37-c8f2-4d1d-8c17-2e2ac16dcc5a'; name = 'Consultar Tasas'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1600,128)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 1500; alwaysOutputData = $true
  },
  [ordered]@{
    parameters = @{ url = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?gid=908170655&single=true&output=csv'; options = @{} }
    id = 'e2f3a4b5-c6d7-4e88-9f00-cuentas00001'; name = 'Consultar Cuentas'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(1690,300)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 3; waitBetweenTries = 1500; alwaysOutputData = $true
  },
  [ordered]@{
    # Busca el numero del cliente en la tabla perfiles_mayor de Supabase (registro de la app).
    # Filtro "like.*<digitos>" para que matchee con o sin "+" delante. Si falla o no hay credencial -> sigue (detal).
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'perfiles_mayor'; returnAll = $false; limit = 1; filterType = 'string'; filterString = "={{ 'whatsapp=like.*' + `$('Webhook Evolution API').first().json.body.data.key.remoteJid.split('@')[0].replace(/\D/g,'') }}" }
    id = 'ab12cd34-ef56-4789-9abc-supamayor001'; name = 'Consultar Mayorista'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(1780,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
  },
  [ordered]@{
    # Busca las operaciones previas del cliente en 'transacciones' (por su whatsapp) para personalizar la atencion.
    # Solo columnas necesarias. Si falla o no hay credencial -> sigue sin contexto (normal).
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'transacciones'; returnAll = $false; limit = 15; filterType = 'string'; filterString = "={{ 'whatsapp_cliente=like.*' + `$('Webhook Evolution API').first().json.body.data.key.remoteJid.split('@')[0].replace(/\D/g,'') }}" }
    id = 'cd34ef56-ab78-4890-9cde-supacliente1'; name = 'Consultar Cliente'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(1820,300)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
  },
  [ordered]@{
    # Lee la preferencia de tarifa guardada por un admin (comando "modo mayor"/"modo detal"). Vacio para clientes normales.
    parameters = @{ operation = 'get'; key = "={{ 'modoAdmin:' + `$('Webhook Evolution API').first().json.body.data.key.remoteJid }}"; propertyName = 'modoAdmin'; keyType = 'string'; options = @{} }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1840,300); id = 'f8a9b0c1-6789-4d54-9e66-rgetmodo0001'; name = 'Redis Leer Modo Admin'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $mainCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1860,128); id = '6ac06fc7-1afb-49ab-893c-e2f2b5f8b995'; name = 'Code in JavaScript'
  },
  [ordered]@{
    # Lo que el cliente tenia pendiente (cuenta sin captura, o captura sin cuenta) y las capturas
    # que ya se pasaron al grupo. Ver "Revisar Operacion".
    parameters = @{ operation = 'get'; key = "={{ 'op:' + `$('Prep Debounce').first().json.jid }}"; propertyName = 'operacion'; keyType = 'string'; options = @{} }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1280,48); id = 'a1b2c3d4-0001-4e00-9a00-operacion0001'; name = 'Redis Leer Operacion'; credentials = $redisCred
    onError = 'continueRegularOutput'; alwaysOutputData = $true
  },
  [ordered]@{
    # Si el ultimo mensaje del bot fue una pregunta ('1') o no ('0'). Con eso "Revisar Operacion"
    # decide si un "ok" suelto se contesta. Lo escribe "Redis Marcar Pregunta".
    parameters = @{ operation = 'get'; key = "={{ 'preg:' + `$('Prep Debounce').first().json.jid }}"; propertyName = 'pregunta'; keyType = 'string'; options = @{} }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1456,48); id = 'a1b2c3d4-0004-4e00-9a00-cierres00004'; name = 'Redis Leer Pregunta'; credentials = $redisCred
    onError = 'continueRegularOutput'; alwaysOutputData = $true
  },
  [ordered]@{
    # Las ultimas operaciones de este cliente en transacciones_por_whatsapp, la mas reciente primero
    # (ver "Revisar Operacion"). Si Supabase falla, el bot sigue sin eso.
    parameters = @{ resource = 'row'; operation = 'getAll'; tableId = 'transacciones_por_whatsapp'; returnAll = $false; limit = $OPERACIONES_A_LEER; filterType = 'string'; filterString = "={{ 'whatsapp=eq.' + `$('Prep Debounce').first().json.jid.split('@')[0].replace(/\D/g,'') + '&order=creado.desc' }}" }
    id = 'a1b2c3d4-0008-4e00-9a00-registro00008'; name = 'Consultar Operaciones WhatsApp'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(1632,48)
    onError = 'continueRegularOutput'; alwaysOutputData = $true
    credentials = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $revisarOperacionCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1456,48); id = 'a1b2c3d4-0002-4e00-9a00-operacion0002'; name = 'Revisar Operacion'
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = "={{ 'op:' + `$('Prep Debounce').first().json.jid }}"; value = '={{ $json.operacionNueva }}'; keyType = 'string'; expire = $true; ttl = $SEG_MEMORIA_OPERACION }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1632,48); id = 'a1b2c3d4-0003-4e00-9a00-operacion0003'; name = 'Redis Guardar Operacion'; credentials = $redisCred
    onError = 'continueRegularOutput'
  },
  [ordered]@{
    # Que se le contesta (lo decide "Revisar Operacion"):
    #   gracias -> sticker A SU ORDEN | callar -> nada | todo lo demas -> la IA
    # Lo que no calce en ninguna regla sale por la salida de respaldo, hacia la IA: si algo
    # falla, el bot contesta como antes en vez de quedarse callado.
    parameters = @{ options = @{ fallbackOutput = 'extra'; renameFallbackOutput = 'ia' }; rules = @{ values = @(
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'q-gracias'; leftValue = "={{ `$('Revisar Operacion').first().json.accion }}"; rightValue = 'gracias'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'gracias' },
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'q-callar'; leftValue = "={{ `$('Revisar Operacion').first().json.accion }}"; rightValue = 'callar'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'callar' }
    ) } }
    type = 'n8n-nodes-base.switch'; typeVersion = 3.2; position = @(1984,48); id = 'a1b2c3d4-0005-4e00-9a00-cierres00005'; name = '¿Qué Responder?'
  },
  [ordered]@{
    # "gracias" -> sticker A SU ORDEN, sin pasar por la IA.
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendSticker/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "number": "{{ $("Prep Debounce").first().json.jid }}", "sticker": "https://grupojk-cambios.github.io/grupojk-conversor/logos/sticker-a-su-orden.webp" }'; options = @{} }
    id = 'a1b2c3d4-0006-4e00-9a00-cierres00006'; name = 'Sticker A Su Orden'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(2160,208)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    # Anota si la respuesta de la IA fue una pregunta ('1') o no ('0'). Ver "Redis Leer Pregunta".
    parameters = @{ operation = 'set'; key = "={{ 'preg:' + `$('Prep Debounce').first().json.jid }}"; value = '={{ /[?¿]/.test(String($json.output || "")) ? "1" : "0" }}'; keyType = 'string'; expire = $true; ttl = $SEG_MEMORIA_OPERACION }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(1392,592); id = 'a1b2c3d4-0007-4e00-9a00-cierres00007'; name = 'Redis Marcar Pregunta'; credentials = $redisCred
    onError = 'continueRegularOutput'
  },
  [ordered]@{
    # Se usa el texto SIN la linea del comando ("modo mayor"/"modo detal"), para que el agente no
    # crea que el cliente le pregunto algo sobre tarifas. Si no hubo comando, es el mensaje tal cual.
    parameters = @{ promptType = 'define'; text = "={{ ((`$('Detectar Comando Admin').first().json.textoLimpio || `$('Combinar').item.json.mensajeCombinado) + (`$('Revisar Operacion').first().json.notaIA || '')).replace(/ Huella: [0-9a-f]+/gi, '') }}"; options = @{ systemMessage = $systemMsg } }
    type = '@n8n/n8n-nodes-langchain.agent'; typeVersion = 3.1; position = @(1960,128); id = '2ac354a3-fe77-4708-80c5-b238454cfdd6'; name = 'AI Agent'; executeOnce = $true
    retryOnFail = $true; maxTries = 3; waitBetweenTries = 3000
  },
  [ordered]@{
    parameters = @{ jsCode = $separarRespuestaCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2180,128); id = 'cc99dd00-ee11-4727-9ccc-separarresp1'; name = 'Separar Respuesta'
  },
  [ordered]@{
    parameters = @{ resource = 'messages-api'; instanceName = 'BOT JK Kelvin'; remoteJid = "={{ `$('Webhook Evolution API').item.json.body.data.key.remoteJid }}"; messageText = '={{ $json.output }}'; options_message = @{} }
    type = 'n8n-nodes-evolution-api.evolutionApi'; typeVersion = 1; position = @(2320,128); id = '02d01e05-a9f8-4caa-a02e-37a660aa662c'; name = 'Enviar texto a WhatsApp'
    retryOnFail = $true; maxTries = 4; waitBetweenTries = 5000
    credentials = @{ evolutionApi = @{ id = 'iUIvc9Sd8diFJaGU'; name = 'Evolution PARA n8n cambios JK' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $detectarCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2200,320); id = 'aa11bb22-cc33-4d44-9e55-detasesor001'; name = 'Detectar Asesor'
  },
  [ordered]@{
    # El aviso de "este cliente quiere un asesor" va al grupo "Notificaciones Clientes",
    # creado el 18/11 solo para esto. NO al grupo de operaciones, donde llegan comprobantes
    # y cuentas: Kelvin los quiere separados.
    # Para mandarlo a otro lado se cambia este remoteJid: otro grupo es otro id terminado
    # en @g.us, y una persona es <numero>@s.whatsapp.net.
    parameters = @{ resource = 'messages-api'; instanceName = 'BOT JK Kelvin'; remoteJid = '120363413942097019@g.us'; messageText = '={{ $json.alerta }}'; options_message = @{} }
    type = 'n8n-nodes-evolution-api.evolutionApi'; typeVersion = 1; position = @(2420,320); id = 'bb22cc33-dd44-4e55-9f66-notasesor001'; name = 'Notificar Asesor'
    retryOnFail = $true; maxTries = 4; waitBetweenTries = 5000
    credentials = @{ evolutionApi = @{ id = 'iUIvc9Sd8diFJaGU'; name = 'Evolution PARA n8n cambios JK' } }
  },
  [ordered]@{
    parameters = @{ model = 'gpt-4o'; options = @{ temperature = 0.2 } }
    id = '073e3eb0-3806-4654-8016-ed7207a45715'; name = 'OpenAI Model'; type = '@n8n/n8n-nodes-langchain.lmChatOpenAi'; typeVersion = 1; position = @(1820,400)
    credentials = @{ openAiApi = @{ id = '44lRGIyEnSk1lMc5'; name = 'cambios jk para n8n' } }
  },
  [ordered]@{
    parameters = @{ sessionIdType = 'customKey'; sessionKey = "={{ `$('Webhook Evolution API').item.json.body.data.key.remoteJid }}"; contextWindowLength = 15; sessionTTL = 259200 }
    id = 'bff6d1ec-1a12-45f2-a96a-327e1edd3f0e'; name = 'Memoria de Chat'; type = '@n8n/n8n-nodes-langchain.memoryRedisChat'; typeVersion = 1.6; position = @(2040,400)
    credentials = @{ redis = @{ id = 'SKkvpS5A65SOcmJs'; name = 'Redis memoria para Cambios JK' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $detectarAprobacionCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2200,220); id = 'aa11bb22-cc33-4170-9aaa-aprobacion001'; name = 'Detectar Aprobación'
  },
  [ordered]@{
    parameters = @{ operation = 'get'; key = "={{ 'lastimg:' + `$('Detectar Aprobación').item.json.jid }}"; propertyName = 'imgKeyId'; keyType = 'string'; options = @{} }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(2380,220); id = 'bb22cc33-dd44-4271-9bbb-redisimg0001'; name = 'Redis Leer ID Imagen'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/chat/getBase64FromMediaMessage/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "message": { "key": { "id": "{{ $("Detectar Aprobación").first().json.idImagen || $json.imgKeyId }}" } }, "convertToMp4": false }'; options = @{} }
    id = 'cc33dd44-ee55-4282-9ccc-redownload001'; name = 'Re-descargar Imagen'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(2560,220)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendMedia/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={{ JSON.stringify({ number: "' + $GRUPO_OPERACIONES + '", mediatype: "image", mimetype: ($json.mimetype || "image/jpeg"), media: $json.base64, caption: ("Cliente: " + $("Detectar Aprobación").item.json.nombreMostrar) }) }}'; options = @{} }
    id = 'dd44ee55-ff66-4393-9ddd-sendimg0001'; name = 'Enviar Imagen Grupo'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(2740,220)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendSticker/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "number": "{{ $("Detectar Aprobación").item.json.jid }}", "sticker": "https://grupojk-cambios.github.io/grupojk-conversor/logos/sticker-pedido-aprobado.webp" }'; options = @{} }
    id = 'ee55ff66-aa77-4404-9eee-sendsticker01'; name = 'Enviar Sticker Cliente'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(2920,220)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    # Se anota de quien es la publicacion que acaba de hacer el bot en el grupo. Cuando la
    # operadora RESPONDA ese mensaje con la foto del envio, asi se sabe a que cliente va.
    parameters = @{ operation = 'set'; key = "={{ 'grupoMsg:' + ((`$json.key && `$json.key.id) || (`$json.data && `$json.data.key && `$json.data.key.id) || 'nada') }}"; value = "={{ JSON.stringify({ jid: `$('Detectar Aprobación').first().json.jid, nombre: `$('Detectar Aprobación').first().json.nombreMostrar, idCuenta: `$('Detectar Aprobación').first().json.idCuenta, idCaptura: `$('Detectar Aprobación').first().json.idImagen }) }}"; keyType = 'string'; expire = $true; ttl = $SEG_MEMORIA_OPERACION }
    id = 'd0e1f2a3-0000-4b00-9000-marcapubimg1'; name = 'Marcar Publicacion Imagen'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(2740,60)
    onError = 'continueRegularOutput'
    credentials = $redisCred
  },
  [ordered]@{
    # Se anota de quien es la publicacion que acaba de hacer el bot en el grupo. Cuando la
    # operadora RESPONDA ese mensaje con la foto del envio, asi se sabe a que cliente va.
    parameters = @{ operation = 'set'; key = "={{ 'grupoMsg:' + ((`$json.key && `$json.key.id) || (`$json.data && `$json.data.key && `$json.data.key.id) || 'nada') }}"; value = "={{ JSON.stringify({ jid: `$('Detectar Aprobación').first().json.jid, nombre: `$('Detectar Aprobación').first().json.nombreMostrar, idCuenta: (`$('Separar Cuentas').item.json.idCuenta || `$('Detectar Aprobación').first().json.idCuenta), idCaptura: `$('Detectar Aprobación').first().json.idImagen }) }}"; keyType = 'string'; expire = $true; ttl = $SEG_MEMORIA_OPERACION }
    id = 'd0e1f2a3-0000-4b00-9000-marcapubcta1'; name = 'Marcar Publicacion Cuenta'; type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(3280,400)
    onError = 'continueRegularOutput'
    credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ jsCode = $separarCuentasCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2920,400); id = 'ff66aa77-bb88-4505-9fff-separarctas1'; name = 'Separar Cuentas'
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={{ JSON.stringify({ number: "' + $GRUPO_OPERACIONES + '", text: $json.cuenta }) }}'; options = @{} }
    id = 'aa77bb88-cc99-4616-9aaa-sendcuenta01'; name = 'Enviar Cuenta Grupo'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(3100,400)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    parameters = @{ jsCode = $registrarOperacionCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2380,340); id = 'bb88cc99-dd00-4727-9bbb-registrarop1'; name = 'Registrar Operación'
    onError = 'continueRegularOutput'; alwaysOutputData = $true
  },
  [ordered]@{
    parameters = @{ jsCode = $armarFilaCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(1808,768); id = 'a1b2c3d4-0009-4e00-9a00-registro00009'; name = 'Armar Fila Supabase'
    onError = 'continueRegularOutput'
  },
  [ordered]@{
    # Guarda la operacion en transacciones_por_whatsapp ('en_proceso'). Si falla, la operacion
    # igual se paso al grupo: solo queda sin registro.
    parameters = @{ resource = 'row'; operation = 'create'; tableId = 'transacciones_por_whatsapp'; dataToSend = 'autoMapInputData'; inputsToIgnore = '' }
    id = 'a1b2c3d4-0010-4e00-9a00-registro00010'; name = 'Guardar Operacion en Supabase'; type = 'n8n-nodes-base.supabase'; typeVersion = 1; position = @(1984,768)
    onError = 'continueRegularOutput'
    credentials = @{ supabaseApi = @{ id = 'JCvvp9JkZ15OpA9E'; name = 'Supabase Cambios JK' } }
  },
  [ordered]@{
    parameters = @{ name = 'calculadora_remesas'; description = 'Convierte montos de dinero entre paises/monedas con las tasas oficiales del dia de JK Remesas. Usala para cualquier conversion de monto, para cruces entre dos paises, o cuando intervengan dolares, USDT o euros. Devuelve el resultado exacto.'; language = 'javaScript'; jsCode = $toolCode; specifyInputSchema = $true; schemaType = 'manual'; inputSchema = $inputSchema }
    type = '@n8n/n8n-nodes-langchain.toolCode'; typeVersion = 1.1; position = @(2200,400); id = 'b1f2c3d4-0000-4a00-9000-aabbccddeeff'; name = 'Calculadora de Conversion'
  }
)

$connections = [ordered]@{
  'Webhook Evolution API'  = @{ main = @( ,@( @{ node='Clientes Detal Permitidos'; type='main'; index=0 } ) ) }
  'Clientes Detal Permitidos' = @{ main = @( ,@( @{ node='Clientes Mayor Permitidos'; type='main'; index=0 } ) ) }
  'Clientes Mayor Permitidos' = @{ main = @( ,@( @{ node='Perfiles Detal App'; type='main'; index=0 } ) ) }
  'Perfiles Detal App'     = @{ main = @( ,@( @{ node='Perfiles Mayor App'; type='main'; index=0 } ) ) }
  'Perfiles Mayor App'     = @{ main = @( ,@( @{ node='Redis Leer Pausa'; type='main'; index=0 } ) ) }
  'Redis Leer Pausa'       = @{ main = @( ,@( @{ node='Redis Leer Aviso'; type='main'; index=0 } ) ) }
  'Redis Leer Aviso'       = @{ main = @( ,@( @{ node='Solo Estos Numeros'; type='main'; index=0 } ) ) }
  'Avisar Pausa'           = @{ main = @( ,@( @{ node='Redis Marcar Aviso'; type='main'; index=0 } ) ) }
  'Solo Estos Numeros'     = @{ main = @( ,@( @{ node='Router Pausa'; type='main'; index=0 } ) ) }
  'Router Pausa'           = @{ main = (
      @( ,@( @{ node='Es mensaje de cliente?'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Redis Guardar Pausa';   type='main'; index=0 } ) ) +
      @( ,@( @{ node='Redis Borrar Pausa';    type='main'; index=0 } ) ) +
      @( ,@( @{ node='Avisar Pausa';          type='main'; index=0 } ) ) +
      @( ,@( @{ node='Redis Leer Publicacion';     type='main'; index=0 } ) ) +
      @( ,@( @{ node='Redis Guardar Ultima Foto';  type='main'; index=0 } ) )
    ) }
  'Redis Leer Publicacion' = @{ main = @( ,@( @{ node='Redis Leer Entregado';   type='main'; index=0 } ) ) }
  'Redis Leer Entregado'   = @{ main = @( ,@( @{ node='Redis Leer Ultima Foto'; type='main'; index=0 } ) ) }
  'Redis Leer Ultima Foto' = @{ main = @( ,@( @{ node='Revisar Pedido';         type='main'; index=0 } ) ) }
  'Revisar Pedido'         = @{ main = @( ,@( @{ node='Ya Se Entrego?';         type='main'; index=0 } ) ) }
  'Ya Se Entrego?'         = @{ main = (
      @( ,@( @{ node='Avisar Repetido';      type='main'; index=0 } ) ) +
      @( ,@( @{ node='Bajar Foto Operadora'; type='main'; index=0 } ) )
    ) }
  'Bajar Foto Operadora'   = @{ main = @( ,@( @{ node='Enviar Comprobante al Cliente'; type='main'; index=0 } ) ) }
  'Enviar Comprobante al Cliente' = @{ main = @( ,@( @{ node='Fallo la Cita?'; type='main'; index=0 } ) ) }
  'Fallo la Cita?'         = @{ main = (
      @( ,@( @{ node='Enviar Comprobante sin Cita'; type='main'; index=0 } ) ) +
      @( ,@( @{ node='Sticker Pedido Pagado';       type='main'; index=0 } ) )
    ) }
  'Enviar Comprobante sin Cita' = @{ main = @( ,@( @{ node='Sticker Pedido Pagado'; type='main'; index=0 } ) ) }
  'Sticker Pedido Pagado'  = @{ main = @( ,@( @{ node='Confirmar en el Grupo'; type='main'; index=0 } ) ) }
  'Confirmar en el Grupo'  = @{ main = @( ,@( @{ node='Fallo la Cita del Grupo?'; type='main'; index=0 } ) ) }
  'Fallo la Cita del Grupo?' = @{ main = (
      @( ,@( @{ node='Confirmar sin Cita';     type='main'; index=0 } ) ) +
      @( ,@( @{ node='Redis Marcar Entregado'; type='main'; index=0 } ) )
    ) }
  'Confirmar sin Cita'     = @{ main = @( ,@( @{ node='Redis Marcar Entregado'; type='main'; index=0 } ) ) }
  'Es mensaje de cliente?' = @{ main = @( ,@( @{ node='Es Audio?'; type='main'; index=0 } ) ) }
  'Es Audio?'              = @{ main = (@( ,@( @{ node='Descargar Audio'; type='main'; index=0 } ) ) + @( ,@( @{ node='Es Imagen?'; type='main'; index=0 } ) )) }
  'Es Imagen?'             = @{ main = (@( ,@( @{ node='Descargar Imagen'; type='main'; index=0 } ) ) + @( ,@( @{ node='Texto Directo'; type='main'; index=0 } ) )) }
  'Descargar Imagen'       = @{ main = @( ,@( @{ node='Imagen a Binario'; type='main'; index=0 } ) ) }
  'Imagen a Binario'       = @{ main = @( ,@( @{ node='Leer Imagen'; type='main'; index=0 } ) ) }
  'Leer Imagen'            = @{ main = @( ,@( @{ node='Texto de Imagen'; type='main'; index=0 } ) ) }
  'Texto de Imagen'        = @{ main = @( ,@( @{ node='Redis Guardar Imagen'; type='main'; index=0 } ) ) }
  'Redis Guardar Imagen'   = @{ main = @( ,@( @{ node='Prep Debounce'; type='main'; index=0 } ) ) }
  'Descargar Audio'        = @{ main = @( ,@( @{ node='Audio a Binario'; type='main'; index=0 } ) ) }
  'Audio a Binario'        = @{ main = @( ,@( @{ node='Transcribir Audio'; type='main'; index=0 } ) ) }
  'Transcribir Audio'      = @{ main = @( ,@( @{ node='Texto de Audio'; type='main'; index=0 } ) ) }
  'Texto de Audio'         = @{ main = @( ,@( @{ node='Prep Debounce'; type='main'; index=0 } ) ) }
  'Texto Directo'          = @{ main = @( ,@( @{ node='Prep Debounce'; type='main'; index=0 } ) ) }
  'Prep Debounce'          = @{ main = @( ,@(
      @{ node='Redis Guardar Msg';      type='main'; index=0 },
      @{ node='Llego un Comprobante?';  type='main'; index=0 }
    ) ) }
  'Llego un Comprobante?'  = @{ main = @( ,@( @{ node='Sticker Verificando'; type='main'; index=0 } ) ) }
  'Redis Guardar Msg'      = @{ main = @( ,@( @{ node='Redis Marcar Token'; type='main'; index=0 } ) ) }
  'Redis Marcar Token'     = @{ main = @( ,@( @{ node='Esperar 30s'; type='main'; index=0 } ) ) }
  'Esperar 30s'            = @{ main = @( ,@( @{ node='Redis Leer Token'; type='main'; index=0 } ) ) }
  'Redis Leer Token'       = @{ main = @( ,@( @{ node='Filtrar Ultimo'; type='main'; index=0 } ) ) }
  'Filtrar Ultimo'         = @{ main = @( ,@( @{ node='Redis Leer Mensajes'; type='main'; index=0 } ) ) }
  'Redis Leer Mensajes'    = @{ main = @( ,@( @{ node='Redis Borrar Buffer'; type='main'; index=0 } ) ) }
  'Redis Borrar Buffer'    = @{ main = @( ,@( @{ node='Combinar'; type='main'; index=0 } ) ) }
  'Combinar'               = @{ main = @( ,@( @{ node='Consultar Admins'; type='main'; index=0 } ) ) }
  'Consultar Admins'       = @{ main = @( ,@( @{ node='Detectar Comando Admin'; type='main'; index=0 } ) ) }
  'Detectar Comando Admin' = @{ main = @( ,@( @{ node='¿Es Comando Admin?'; type='main'; index=0 } ) ) }
  '¿Es Comando Admin?'     = @{ main = (@( ,@( @{ node='Redis Guardar Modo Admin'; type='main'; index=0 } ) ) + @( ,@( @{ node='Consultar Tasas'; type='main'; index=0 } ) )) }
  'Redis Guardar Modo Admin' = @{ main = @( ,@( @{ node='¿Solo el Comando?'; type='main'; index=0 } ) ) }
  # true = solo el comando -> avisa y listo. false = venia una pregunta pegada -> sigue y la responde.
  '¿Solo el Comando?'      = @{ main = (@( ,@( @{ node='Confirmar Modo Admin'; type='main'; index=0 } ) ) + @( ,@( @{ node='Consultar Tasas'; type='main'; index=0 } ) )) }
  'Confirmar Modo Admin'   = @{ main = @( ,@( @{ node='Enviar texto a WhatsApp'; type='main'; index=0 } ) ) }
  'Consultar Tasas'        = @{ main = @( ,@( @{ node='Consultar Cuentas'; type='main'; index=0 } ) ) }
  'Consultar Cuentas'      = @{ main = @( ,@( @{ node='Consultar Mayorista'; type='main'; index=0 } ) ) }
  'Consultar Mayorista'    = @{ main = @( ,@( @{ node='Consultar Cliente'; type='main'; index=0 } ) ) }
  'Consultar Cliente'      = @{ main = @( ,@( @{ node='Redis Leer Modo Admin'; type='main'; index=0 } ) ) }
  'Redis Leer Modo Admin'  = @{ main = @( ,@( @{ node='Code in JavaScript'; type='main'; index=0 } ) ) }
  'Code in JavaScript'     = @{ main = @( ,@( @{ node='Redis Leer Operacion'; type='main'; index=0 } ) ) }
  'Redis Leer Operacion'   = @{ main = @( ,@( @{ node='Redis Leer Pregunta'; type='main'; index=0 } ) ) }
  'Redis Leer Pregunta'    = @{ main = @( ,@( @{ node='Consultar Operaciones WhatsApp'; type='main'; index=0 } ) ) }
  'Consultar Operaciones WhatsApp' = @{ main = @( ,@( @{ node='Revisar Operacion'; type='main'; index=0 } ) ) }
  'Revisar Operacion'      = @{ main = @( ,@( @{ node='Redis Guardar Operacion'; type='main'; index=0 } ) ) }
  'Redis Guardar Operacion' = @{ main = @( ,@( @{ node='¿Qué Responder?'; type='main'; index=0 } ) ) }
  '¿Qué Responder?'        = @{ main = (@( ,@( @{ node='Sticker A Su Orden'; type='main'; index=0 } ) ) + @( ,@() ) + @( ,@( @{ node='AI Agent'; type='main'; index=0 } ) )) }
  'OpenAI Model'           = @{ ai_languageModel = @( ,@( @{ node='AI Agent'; type='ai_languageModel'; index=0 } ) ) }
  'Memoria de Chat'        = @{ ai_memory = @( ,@( @{ node='AI Agent'; type='ai_memory'; index=0 } ) ) }
  'Calculadora de Conversion' = @{ ai_tool = @( ,@( @{ node='AI Agent'; type='ai_tool'; index=0 } ) ) }
  'AI Agent'               = @{ main = @( ,@( @{ node='Separar Respuesta'; type='main'; index=0 }, @{ node='Detectar Asesor'; type='main'; index=0 }, @{ node='Detectar Aprobación'; type='main'; index=0 }, @{ node='Redis Marcar Pregunta'; type='main'; index=0 } ) ) }
  'Separar Respuesta'      = @{ main = @( ,@( @{ node='Enviar texto a WhatsApp'; type='main'; index=0 } ) ) }
  'Detectar Asesor'        = @{ main = @( ,@( @{ node='Notificar Asesor'; type='main'; index=0 } ) ) }
  'Detectar Aprobación'    = @{ main = @( ,@( @{ node='Redis Leer ID Imagen'; type='main'; index=0 }, @{ node='Enviar Sticker Cliente'; type='main'; index=0 }, @{ node='Registrar Operación'; type='main'; index=0 }, @{ node='Armar Fila Supabase'; type='main'; index=0 } ) ) }
  'Armar Fila Supabase'    = @{ main = @( ,@( @{ node='Guardar Operacion en Supabase'; type='main'; index=0 } ) ) }
  'Redis Marcar Entregado' = @{ main = @( ,@( @{ node='Marcar Enviada en Supabase'; type='main'; index=0 } ) ) }
  'Redis Leer ID Imagen'   = @{ main = @( ,@( @{ node='Re-descargar Imagen'; type='main'; index=0 } ) ) }
  'Re-descargar Imagen'    = @{ main = @( ,@( @{ node='Enviar Imagen Grupo'; type='main'; index=0 } ) ) }
  'Enviar Imagen Grupo'    = @{ main = @( ,@(
      @{ node='Separar Cuentas';            type='main'; index=0 },
      @{ node='Marcar Publicacion Imagen';  type='main'; index=0 }
    ) ) }
  'Separar Cuentas'        = @{ main = @( ,@( @{ node='Enviar Cuenta Grupo'; type='main'; index=0 } ) ) }
  'Enviar Cuenta Grupo'    = @{ main = @( ,@( @{ node='Marcar Publicacion Cuenta'; type='main'; index=0 } ) ) }
  'Marcar Publicacion Cuenta' = @{ main = @( ,@( @{ node='Revisar Montos'; type='main'; index=0 } ) ) }
  'Revisar Montos'         = @{ main = @( ,@( @{ node='Avisar Montos';    type='main'; index=0 } ) ) }
}

$body = [ordered]@{ name = 'Bot WhatsApp CAMBIOS JK'; nodes = $nodes; connections = $connections; settings = @{ executionOrder = 'v1' } }

$json = $body | ConvertTo-Json -Depth 40
$json | Out-File -FilePath "C:\Users\USER\Documents\APP PARA CAMBIOS JK CONVERSOR\workflow_bot_whatsapp_v12.json" -Encoding utf8
Write-Output ("JSON v12 generado. Longitud: " + $json.Length + " chars. Nodos: " + $nodes.Count)
