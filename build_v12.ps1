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
$MINUTOS_PAUSA = 60
$HORAS_PAUSA_MANUAL = 12
$GRUPO_AVISOS = '120363413942097019@g.us'   # grupo "Notificaciones Clientes"

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
    if (nombre) txt += ' Saludalo por su nombre con naturalidad.';
    if (recurrente) txt += ' Si pide cotizar, puedes sugerir su destino habitual.';
    txt += ' No menciones montos ni datos viejos salvo que el cliente pregunte.';
    clienteContexto = txt;
  }
} catch(e){}

return [{ json: { lista, modo, esMayorista, appUrl:APP_URL, hayEfectivoVe, evUbicaciones, totalPaises: paises.length, cuentas, hayCuentas: cuentas.length>0, diaIndex, diaSemanaEc, avisosCuentas, clienteContexto, error: paises.length? null : 'Lista vacia' } }];
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
=Eres asistente de *Cambios JK🚛* por WhatsApp. RESPONDE EN MAXIMO 2-3 LINEAS, directo y humano. 1-2 emojis maximo. NO repitas frases de cortesia.

El cliente puede enviarte VARIOS mensajes juntos (separados por saltos de linea). Leelos todos y responde UNA sola vez, corto.

Tarifa de este cliente: {{ $node["Code in JavaScript"].json.modo }} (detal=publico, mayor=mayorista). Nunca menciones lo mayorista a un cliente detal.
{{ $node["Code in JavaScript"].json.clienteContexto ? ('CONTEXTO DEL CLIENTE (usalo con naturalidad para atender mejor): ' + $node["Code in JavaScript"].json.clienteContexto) : '' }}

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
- COMPROBANTE DE PAGO: si ves "[El cliente envio un COMPROBANTE de pago...]", NUNCA digas "no tengo esa cuenta". Responde MUY corto, 1 sola linea. Si en el mensaje hay numeros de cuenta/cedula/banco/datos de una cuenta destino (aunque vengan reenviados o en numeros sueltos), confirma: "Listo, recibido! Procesamos tu remesa enseguida ✅" y NO preguntes nada mas. SOLO si NO hay ninguna cuenta en el mensaje, pide corto: "Recibi tu comprobante! 🙌 Pasame la cuenta destino (banco, numero y titular)". La cuenta destino es donde el destinatario RECIBE el dinero; el cliente puede dividir el monto en varias cuentas.
- IMAGEN DE CUENTA: si ves "[El cliente envio una imagen con una CUENTA bancaria...]", trata esos datos como la cuenta destino para su remesa.
- Fuera de tema: "Solo remesas de JK."
- Quejas o problema con un giro: "Un asesor te contacta enseguida."
- Nunca pidas claves, cuentas ni documentos. No des consejo financiero.
- Ver todas las tasas: {{ $node["Code in JavaScript"].json.appUrl }}
{{ $node["Code in JavaScript"].json.hayEfectivoVe ? '- Efectivo Venezuela (dolares en efectivo). El precio PUEDE variar por ciudad, asi que SIEMPRE pregunta el estado/ciudad y calcula con la herramienta usando ESA ubicacion exacta como pais_destino (ej "Efectivo Venezuela Maracaibo"). Ubicaciones disponibles: ' + ($node["Code in JavaScript"].json.evUbicaciones || []).map(u => u.estado + (u.ciudades && u.ciudades.length ? ' (' + u.ciudades.join(', ') + ')' : '')).join('; ') + '. Si la ciudad NO esta en la lista, ahi no hay entrega en efectivo por ahora.' : '' }}

PROHIBIDO repetir en cada mensaje cosas como "estoy aqui", "disponible", "para ayudarte", "cualquier consulta", "no dudes en". Responde lo justo y para. Suena como una persona, no como un bot.

MULTI-COTIZACION: si das varias cotizaciones (ej. desde Venezuela Y desde Ecuador), separa cada cotizacion con una linea que diga solamente "---" (tres guiones, sin nada mas, en una linea propia). Asi cada cotizacion sale como mensaje aparte en WhatsApp. Una sola cotizacion = sin "---".
'@

# ===================== CODIGO: PREP DEBOUNCE =====================
$prepCode = @'
// Prepara los datos para el debounce con Redis. El texto ya viene unificado (de texto directo o de audio transcrito).
let jid='', texto='';
try { jid = $('Webhook Evolution API').first().json.body.data.key.remoteJid || ''; } catch(e){}
try { texto = $json.texto || ''; } catch(e){}
const miTs = String(Date.now()) + '-' + Math.random().toString(36).slice(2,8);
return [{ json: { jid, texto: texto || '', miTs, keyBuf: 'buf:'+jid, keyTok: 'tok:'+jid } }];
'@

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
let texto='';
if(tipo.indexOf('comprobante')>=0){ texto = '[El cliente envio un COMPROBANTE de pago. Datos leidos: ' + resumen + ']'; }
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
// Junta todos los mensajes leidos de Redis en un solo texto.
let arr = [];
try { arr = $('Redis Leer Mensajes').item.json.mensajes; } catch(e){}
if (!Array.isArray(arr)) arr = (arr === undefined || arr === null) ? [] : [arr];
const combinado = arr.join('\n\n').trim() || '(sin texto)';
return [{ json: { mensajeCombinado: combinado } }];
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
const original = String($('Combinar').item.json.mensajeCombinado || '');
const combinado = original.toLowerCase();
const tieneComprobante = combinado.includes('[el cliente envio un comprobante');
const cuentaPatterns = ['bancolombia', 'nequi', 'pago movil', 'banco', 'cuenta', 'numero de cuenta', 'titular', 'cedula', 'cc ', ' ci ', 'swift', 'interbank', 'binance', 'zelle'];
const tieneCuenta = cuentaPatterns.some(p => combinado.includes(p));
if (!tieneComprobante || !tieneCuenta) { return []; } // no hay ambos -> no aprobar
// Cuenta destino = lo que escribio el cliente, quitando las anotaciones internas del bot ([El cliente envio ...]).
let datosCuenta = original
  .replace(/\[El cliente envio un COMPROBANTE[^\]]*\]/gi, '')
  .replace(/\[El cliente envio una imagen que no parece[^\]]*\]/gi, '')
  .replace(/\[El cliente envio una imagen con una CUENTA bancaria\.?\s*Datos:\s*([^\]]*)\]/gi, 'Cuenta (imagen): $1')
  .replace(/\n{3,}/g, '\n\n')
  .trim();
if (!datosCuenta) datosCuenta = '(el cliente no escribio la cuenta en texto, revisar imagenes)';
let jid='', nombre='', numero='';
try { jid = $('Webhook Evolution API').first().json.body.data.key.remoteJid || ''; nombre = String($('Webhook Evolution API').first().json.body.data.pushName || 'Cliente').normalize('NFKC'); numero = String(jid).replace(/\D/g,''); } catch(e){}
return [{ json: { aprobado: true, jid, nombre, numero, datosCuenta, mensajeCombinado: combinado } }];
'@

# ===================== CODIGO: SEPARAR CUENTAS (1 mensaje por cuenta) =====================
$separarCuentasCode = @'
// Separa la(s) cuenta(s) destino en items individuales (cada mensaje del cliente = un item) para enviar cada uno por separado al grupo.
const datos = String($('Detectar Aprobación').item.json.datosCuenta || '').trim();
if (!datos) return [];
const bloques = datos.split(/\n\s*\n+/).map(b => b.trim()).filter(b => b.length);
return bloques.map(b => ({ json: { cuenta: b } }));
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
      @{ conditions = @{ options = @{ typeValidation = 'loose'; leftValue = ''; caseSensitive = $true }; conditions = @( @{ id = 'p-avisar'; leftValue = '={{ $json.accionPausa }}'; rightValue = 'avisar'; operator = @{ operation = 'equals'; type = 'string' } } ); combinator = 'and' }; renameOutput = $true; outputKey = 'avisar' }
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
    parameters = @{ operation = 'push'; list = "={{ `$('Prep Debounce').item.json.keyBuf }}"; messageData = "={{ `$('Prep Debounce').item.json.texto }}"; tail = $true }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(160,128); id = 'c2a2b3c4-2222-4a22-9222-rpush0000001'; name = 'Redis Guardar Msg'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ operation = 'set'; key = "={{ `$('Prep Debounce').item.json.keyTok }}"; value = "={{ `$('Prep Debounce').item.json.miTs }}"; keyType = 'string'; expire = $true; ttl = 120 }
    type = 'n8n-nodes-base.redis'; typeVersion = 1; position = @(340,128); id = 'c3a2b3c4-3333-4a33-9333-rset00000001'; name = 'Redis Marcar Token'; credentials = $redisCred
  },
  [ordered]@{
    parameters = @{ amount = 30; unit = 'seconds' }
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
    # Se usa el texto SIN la linea del comando ("modo mayor"/"modo detal"), para que el agente no
    # crea que el cliente le pregunto algo sobre tarifas. Si no hubo comando, es el mensaje tal cual.
    parameters = @{ promptType = 'define'; text = "={{ `$('Detectar Comando Admin').first().json.textoLimpio || `$('Combinar').item.json.mensajeCombinado }}"; options = @{ systemMessage = $systemMsg } }
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
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/chat/getBase64FromMediaMessage/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={ "message": { "key": { "id": "{{ $json.imgKeyId }}" } }, "convertToMp4": false }'; options = @{} }
    id = 'cc33dd44-ee55-4282-9ccc-redownload001'; name = 'Re-descargar Imagen'; type = 'n8n-nodes-base.httpRequest'; typeVersion = 4; position = @(2560,220)
    onError = 'continueRegularOutput'; retryOnFail = $true; maxTries = 2; waitBetweenTries = 1000; alwaysOutputData = $true
    credentials = @{ httpHeaderAuth = @{ id = '70cMtifwmTdIqY1l'; name = 'Evolution apikey Kelvin 0380' } }
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendMedia/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={{ JSON.stringify({ number: "593961230380-1601657528@g.us", mediatype: "image", mimetype: ($json.mimetype || "image/jpeg"), media: $json.base64, caption: ("Cliente: " + $("Detectar Aprobación").item.json.nombre) }) }}'; options = @{} }
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
    parameters = @{ jsCode = $separarCuentasCode }
    type = 'n8n-nodes-base.code'; typeVersion = 2; position = @(2920,400); id = 'ff66aa77-bb88-4505-9fff-separarctas1'; name = 'Separar Cuentas'
  },
  [ordered]@{
    parameters = @{ method = 'POST'; url = 'http://evolution-api:8080/message/sendText/BOT%20JK%20Kelvin'; authentication = 'genericCredentialType'; genericAuthType = 'httpHeaderAuth'; sendHeaders = $true; headerParameters = @{ parameters = @( @{ name = 'Content-Type'; value = 'application/json' } ) }; sendBody = $true; specifyBody = 'json'; jsonBody = '={{ JSON.stringify({ number: "593961230380-1601657528@g.us", text: $json.cuenta }) }}'; options = @{} }
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
      @( ,@( @{ node='Avisar Pausa';          type='main'; index=0 } ) )
    ) }
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
  'Prep Debounce'          = @{ main = @( ,@( @{ node='Redis Guardar Msg'; type='main'; index=0 } ) ) }
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
  'Code in JavaScript'     = @{ main = @( ,@( @{ node='AI Agent'; type='main'; index=0 } ) ) }
  'OpenAI Model'           = @{ ai_languageModel = @( ,@( @{ node='AI Agent'; type='ai_languageModel'; index=0 } ) ) }
  'Memoria de Chat'        = @{ ai_memory = @( ,@( @{ node='AI Agent'; type='ai_memory'; index=0 } ) ) }
  'Calculadora de Conversion' = @{ ai_tool = @( ,@( @{ node='AI Agent'; type='ai_tool'; index=0 } ) ) }
  'AI Agent'               = @{ main = @( ,@( @{ node='Separar Respuesta'; type='main'; index=0 }, @{ node='Detectar Asesor'; type='main'; index=0 }, @{ node='Detectar Aprobación'; type='main'; index=0 } ) ) }
  'Separar Respuesta'      = @{ main = @( ,@( @{ node='Enviar texto a WhatsApp'; type='main'; index=0 } ) ) }
  'Detectar Asesor'        = @{ main = @( ,@( @{ node='Notificar Asesor'; type='main'; index=0 } ) ) }
  'Detectar Aprobación'    = @{ main = @( ,@( @{ node='Redis Leer ID Imagen'; type='main'; index=0 }, @{ node='Enviar Sticker Cliente'; type='main'; index=0 }, @{ node='Registrar Operación'; type='main'; index=0 } ) ) }
  'Redis Leer ID Imagen'   = @{ main = @( ,@( @{ node='Re-descargar Imagen'; type='main'; index=0 } ) ) }
  'Re-descargar Imagen'    = @{ main = @( ,@( @{ node='Enviar Imagen Grupo'; type='main'; index=0 } ) ) }
  'Enviar Imagen Grupo'    = @{ main = @( ,@( @{ node='Separar Cuentas'; type='main'; index=0 } ) ) }
  'Separar Cuentas'        = @{ main = @( ,@( @{ node='Enviar Cuenta Grupo'; type='main'; index=0 } ) ) }
}

$body = [ordered]@{ name = 'Bot WhatsApp CAMBIOS JK'; nodes = $nodes; connections = $connections; settings = @{ executionOrder = 'v1' } }

$json = $body | ConvertTo-Json -Depth 40
$json | Out-File -FilePath "C:\Users\USER\Documents\APP PARA CAMBIOS JK CONVERSOR\workflow_bot_whatsapp_v12.json" -Encoding utf8
Write-Output ("JSON v12 generado. Longitud: " + $json.Length + " chars. Nodos: " + $nodes.Count)
