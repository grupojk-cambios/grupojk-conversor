// Datos de los 19 países — tasas expresadas como "unidades de moneda por 1 USD"
export const PAISES_INICIALES = [
  { id: 1, nombre: 'Argentina', iso2: 'ar', bandera: '🇦🇷', codigo: 'ARS', moneda: 'Peso Argentino', tasaProveedorEnvio: 1050, margenEnvio: 6, tasaProveedorRecibo: 1050, margenRecibo: 9, factorEUR: 0, factorUSDT: 0 },
  { id: 2, nombre: 'Uruguay', iso2: 'uy', bandera: '🇺🇾', codigo: 'UYU', moneda: 'Peso Uruguayo', tasaProveedorEnvio: 42, margenEnvio: 6, tasaProveedorRecibo: 42, margenRecibo: 6, factorEUR: 0, factorUSDT: 0 },
  { id: 3, nombre: 'Chile', iso2: 'cl', bandera: '🇨🇱', codigo: 'CLP', moneda: 'Peso Chileno', tasaProveedorEnvio: 950, margenEnvio: 6, tasaProveedorRecibo: 950, margenRecibo: 9, factorEUR: 0, factorUSDT: 0 },
  { id: 4, nombre: 'Paraguay', iso2: 'py', bandera: '🇵🇾', codigo: 'PYG', moneda: 'Guaraní Paraguayo', tasaProveedorEnvio: 7800, margenEnvio: 6, tasaProveedorRecibo: 7800, margenRecibo: 6, factorEUR: 0, factorUSDT: 0 },
  { id: 5, nombre: 'Brasil', iso2: 'br', bandera: '🇧🇷', codigo: 'BRL', moneda: 'Real Brasileño', tasaProveedorEnvio: 5.1, margenEnvio: 6, tasaProveedorRecibo: 5.83, margenRecibo: 6, factorEUR: 0, factorUSDT: 0 },
  { id: 6, nombre: 'Bolivia', iso2: 'bo', bandera: '🇧🇴', codigo: 'BOB', moneda: 'Boliviano', tasaProveedorEnvio: 6.9, margenEnvio: 6, tasaProveedorRecibo: 6.9, margenRecibo: 6, factorEUR: 0, factorUSDT: 0 },
  { id: 7, nombre: 'Perú', iso2: 'pe', bandera: '🇵🇪', codigo: 'PEN', moneda: 'Sol Peruano', tasaProveedorEnvio: 3.41, margenEnvio: 6, tasaProveedorRecibo: 3.6, margenRecibo: 9, factorEUR: 0, factorUSDT: 0 },
  { id: 8, nombre: 'Colombia', iso2: 'co', bandera: '🇨🇴', codigo: 'COP', moneda: 'Peso Colombiano', tasaProveedorEnvio: 3640, margenEnvio: 3.0219, tasaProveedorRecibo: 3640, margenRecibo: 4, factorEUR: 0, factorUSDT: 0 },
  { id: 9, nombre: 'Ecuador', iso2: 'ec', bandera: '🇪🇨', codigo: 'USD', moneda: 'Dólar Americano', tasaProveedorEnvio: 1, margenEnvio: 0, tasaProveedorRecibo: 1, margenRecibo: 0, factorEUR: 0, factorUSDT: 0 },
  { id: 10, nombre: 'Venezuela', iso2: 've', bandera: '🇻🇪', codigo: 'VES', moneda: 'Bolívar Digital', tasaProveedorEnvio: 645, margenEnvio: 3.411, tasaProveedorRecibo: 645, margenRecibo: 6, factorEUR: 1, factorUSDT: 1 },
  { id: 11, nombre: 'Panamá', iso2: 'pa', bandera: '🇵🇦', codigo: 'USD', moneda: 'Dólar Americano', tasaProveedorEnvio: 1, margenEnvio: 0, tasaProveedorRecibo: 1, margenRecibo: 0, factorEUR: 0, factorUSDT: 0 },
  { id: 12, nombre: 'Costa Rica', iso2: 'cr', bandera: '🇨🇷', codigo: 'CRC', moneda: 'Colón Costarricense', tasaProveedorEnvio: 520, margenEnvio: 6, tasaProveedorRecibo: 520, margenRecibo: 6, factorEUR: 0, factorUSDT: 0 },
  { id: 13, nombre: 'Nicaragua', iso2: 'ni', bandera: '🇳🇮', codigo: 'NIO', moneda: 'Córdoba Nicaragüense', tasaProveedorEnvio: 36.5, margenEnvio: 6, tasaProveedorRecibo: 36.5, margenRecibo: 6, factorEUR: 0, factorUSDT: 0 },
  { id: 14, nombre: 'Honduras', iso2: 'hn', bandera: '🇭🇳', codigo: 'HNL', moneda: 'Lempira Hondureño', tasaProveedorEnvio: 25, margenEnvio: 6, tasaProveedorRecibo: 25, margenRecibo: 6, factorEUR: 0, factorUSDT: 0 },
  { id: 15, nombre: 'Guatemala', iso2: 'gt', bandera: '🇬🇹', codigo: 'GTQ', moneda: 'Quetzal Guatemalteco', tasaProveedorEnvio: 7.7, margenEnvio: 6, tasaProveedorRecibo: 7.7, margenRecibo: 6, factorEUR: 0, factorUSDT: 0 },
  { id: 16, nombre: 'Cuba', iso2: 'cu', bandera: '🇨🇺', codigo: 'CUP', moneda: 'Peso Cubano', tasaProveedorEnvio: 350, margenEnvio: 6, tasaProveedorRecibo: 350, margenRecibo: 6, factorEUR: 0, factorUSDT: 0 },
  { id: 17, nombre: 'México', iso2: 'mx', bandera: '🇲🇽', codigo: 'MXN', moneda: 'Peso Mexicano', tasaProveedorEnvio: 20, margenEnvio: 6, tasaProveedorRecibo: 20, margenRecibo: 6, factorEUR: 0, factorUSDT: 0 },
  { id: 18, nombre: 'EEUU', iso2: 'us', bandera: '🇺🇸', codigo: 'USD', moneda: 'Dólar Americano', tasaProveedorEnvio: 1, margenEnvio: 0, tasaProveedorRecibo: 1, margenRecibo: 0, factorEUR: 0, factorUSDT: 0 },
  { id: 19, nombre: 'Europa', iso2: 'eu', bandera: '🇪🇺', codigo: 'EUR', moneda: 'Euro', tasaProveedorEnvio: 0.92, margenEnvio: 6, tasaProveedorRecibo: 0.92, margenRecibo: 6, factorEUR: 0, factorUSDT: 0 },
]

// IDs de países destacados en el Dashboard (los más frecuentes)
export const PAISES_DESTACADOS_IDS = [8, 10, 17, 7, 3, 19] // Colombia, Venezuela, México, Perú, Chile, Europa

/**
 * Tasa de Envío (cuando el sistema vende USD y entrega esta moneda).
 * Se RESTA el margen al proveedor.
 */
export function calcularTasaEnvio(pais, modo = 'detal') {
  const rawProveedor = pais.tasaProveedorEnvio !== undefined ? pais.tasaProveedorEnvio : (pais.tasaProveedor || 0)
  const tProveedor = parseFloat(rawProveedor) || 0;

  if (tProveedor === 0) return 0
  if (pais.codigo === 'USD') return 1

  let rawMargen;
  if (modo === 'mayor' && pais.margenEnvioMayor !== undefined && parseFloat(pais.margenEnvioMayor) > 0) {
    rawMargen = pais.margenEnvioMayor;
  } else {
    rawMargen = pais.margenEnvio !== undefined ? pais.margenEnvio : (pais.margen || 0);
  }
  const margen = parseFloat(rawMargen) || 0;
  return tProveedor * (1 - margen / 100)
}

/**
 * Tasa de Recibo / Inversa (cuando el sistema recibe esta moneda y entrega USD).
 * Se SUMA el margen al proveedor.
 */
export function calcularTasaRecibo(pais, modo = 'detal') {
  const rawProveedor = pais.tasaProveedorRecibo !== undefined ? pais.tasaProveedorRecibo : (pais.tasaProveedor || 0)
  const tProveedor = parseFloat(rawProveedor) || 0;

  if (tProveedor === 0) return 0
  if (pais.codigo === 'USD') return 1

  let rawMargen;
  if (modo === 'mayor' && pais.margenReciboMayor !== undefined && parseFloat(pais.margenReciboMayor) > 0) {
    rawMargen = pais.margenReciboMayor;
  } else {
    rawMargen = pais.margenRecibo !== undefined ? pais.margenRecibo : (pais.margen || 0);
  }
  const margen = parseFloat(rawMargen) || 0;
  return tProveedor * (1 + margen / 100)
}

/**
 * Calculo normal para mostrar la "Tasa Pública" general (que suele ser la de envío)
 */
export function calcularTasaPublica(pais, modo = 'detal') {
  return calcularTasaEnvio(pais, modo)
}

export function isCajaDolar(p) {
  if (!p) return false;
  return ['USD', 'USDT', 'EC', 'US', 'PA'].includes(p.codigo) || [9, 11, 18].includes(p.id) || p.nombre.toLowerCase().includes('usdt');
}

/**
 * Retorna la URL de la bandera o logo para el país/moneda.
 */
export function getFlagUrl(pais) {
  if (!pais) return '';
  const code = pais.codigo ? pais.codigo.toUpperCase() : '';
  const name = pais.nombre ? pais.nombre.toUpperCase() : '';
  const iso = pais.iso2 ? pais.iso2.toLowerCase() : code.substring(0, 2).toLowerCase();

  // Logos de Cripto
  if (code === 'USDT' || iso === 'usdt' || name.includes('USDT') || name.includes('TETHER')) {
    return 'https://assets.coingecko.com/coins/images/325/large/Tether.png';
  }

  // Si el usuario configuró Zelle pero olvidó la bandera US
  if (code === 'ZELLE' || name.includes('ZELLE')) {
    return 'https://flagcdn.com/w80/us.png';
  }

  // Efectivo Venezuela: imagen personalizada con mapa y billetes
  if (name.includes('EFECTIVO VENEZUELA') || name.includes('EFECTIVO VEN')) {
    return `${import.meta.env.BASE_URL}efectivo-venezuela.png`;
  }

  return `https://flagcdn.com/w80/${iso}.png`;
}

/**
 * Detecta si un país usa una imagen personalizada (más grande que una bandera normal).
 */
export function isCustomFlag(pais) {
  if (!pais) return false;
  const name = pais.nombre ? pais.nombre.toUpperCase() : '';
  return name.includes('EFECTIVO VENEZUELA') || name.includes('EFECTIVO VEN');
}

/**
 * Detecta si un país es una sub-entrada de Efectivo Venezuela (con estado/ciudad).
 */
export function isEfectivoVenSubEntry(pais) {
  if (!pais) return false;
  const name = pais.nombre ? pais.nombre.toUpperCase() : '';
  return (name.includes('EFECTIVO VENEZUELA-') || name.includes('EFECTIVO VENEZUELA -'));
}

/**
 * Agrupa las entradas de Efectivo Venezuela por estado y ciudad.
 * Retorna: [{ estado, ciudadesTexto, entries: [{ ciudad, pais }] }]
 */
export function agruparEfectivoVenezuela(paises) {
  const entradas = paises.filter(p => isEfectivoVenSubEntry(p));
  const grupos = {};

  entradas.forEach(p => {
    const name = p.nombre || '';
    // Formato: "Efectivo Venezuela-Estado" o "Efectivo Venezuela-Estado-Ciudad"
    const partes = name.split(/\s*-\s*/).map(s => s.trim());
    // partes[0] = "Efectivo Venezuela", [1] = Estado, [2] = Ciudad (opcional)
    const estado = partes[1] || 'Otro';
    const ciudad = partes[2] || null;

    if (!grupos[estado]) {
      grupos[estado] = { estado, ciudadesTexto: p.ciudades || '', entries: [] };
    }
    grupos[estado].entries.push({ ciudad, pais: p });
    if (p.ciudades && !grupos[estado].ciudadesTexto) {
      grupos[estado].ciudadesTexto = p.ciudades;
    }
  });

  return Object.values(grupos);
}

/**
 * Retorna los países filtrados para el selector (oculta sub-entradas de EV).
 */
export function getPaisesParaSelector(paises) {
  const tieneSubEntradas = paises.some(p => isEfectivoVenSubEntry(p));
  if (!tieneSubEntradas) return paises;

  // Filtrar sub-entradas de EV
  const sinEV = paises.filter(p => !isEfectivoVenSubEntry(p));
  // Solo agregar placeholder si no existe uno genérico
  const yaExisteEV = sinEV.some(p => {
    const n = (p.nombre || '').toUpperCase();
    return n === 'EFECTIVO VENEZUELA';
  });

  if (!yaExisteEV) {
    sinEV.push({
      id: 'ev-placeholder',
      nombre: 'Efectivo Venezuela',
      iso2: 've',
      bandera: '🇻🇪',
      codigo: 'USD',
      moneda: 'Dólar - Efectivo',
      _isEVPlaceholder: true
    });
  } else {
    // Marcar el existente como placeholder
    const ev = sinEV.find(p => (p.nombre || '').toUpperCase() === 'EFECTIVO VENEZUELA');
    if (ev) ev._isEVPlaceholder = true;
  }

  return sinEV;
}

/**
 * Cerebro maestro de Tasas para cruces limpios y factores dinámicos.
 */
export function obtenerTasasProcesadas(paisOrigen, paisDestino, paises, modo = 'detal') {
  const origen = paises.find(p => p.id === paisOrigen.id) || paisOrigen
  const destino = paises.find(p => p.id === paisDestino.id) || paisDestino

  let tasaOrigenParaDolares = calcularTasaRecibo(origen, modo)
  let tasaDestinoDesdeDolares = calcularTasaEnvio(destino, modo)

  // LOGICA DE FACTORES ESPECIALES POR PAÍS (Factores base dinámicos aparte de USD)
  const BASES_ESPECIALES = ['EUR', 'USDT', 'GBP', 'EU']
  // MONEDAS_FUERTES: el usuario las configura como "USD por 1 EUR" (ej: 1.09 = 1 EUR vale 1.09 USD)
  // La matemática debe MULTIPLICAR, no dividir. Se logra invirtiendo la tasa.
  const MONEDAS_FUERTES = ['EUR', 'GBP', 'EU']
  let factorAplicado = false;

  // Factor especial por país (Factor EUR / Factor USDT configurado en Google Sheets)
  // Solo aplica para EUR/GBP → monedas locales (no Caja Dólar) donde el usuario configuró un factor
  if (BASES_ESPECIALES.includes(origen.codigo) && !isCajaDolar(destino) && !BASES_ESPECIALES.includes(destino.codigo)) {
    const factorClave = `factor${origen.codigo}`;
    const factorValor = parseFloat(destino[factorClave]);
    if (factorValor > 0 && !isNaN(factorValor)) {
      tasaOrigenParaDolares = 1 / factorValor;
      factorAplicado = true;
    }
  }
  else if (!BASES_ESPECIALES.includes(origen.codigo) && !isCajaDolar(origen) && BASES_ESPECIALES.includes(destino.codigo)) {
    const factorClave = `factor${destino.codigo}`;
    const factorValor = parseFloat(origen[factorClave]);
    if (factorValor > 0 && !isNaN(factorValor)) {
      tasaDestinoDesdeDolares = 1 / factorValor;
      factorAplicado = true;
    }
  }

  if (!factorAplicado) {
    const origFuerte = MONEDAS_FUERTES.includes(origen.codigo)
    const destFuerte = MONEDAS_FUERTES.includes(destino.codigo)
    const origDolar = isCajaDolar(origen)
    const destDolar = isCajaDolar(destino)

    if (origFuerte || destFuerte) {
      // CORRECCIÓN MATEMÁTICA MONEDAS FUERTES (EUR, GBP, EU)
      // Estas monedas se cotizan "USD por unidad" (Ej: 1 EUR = 1.16 USD).
      // El sistema por defecto divide; para convertirlo a multiplicador, simplemente invertimos la base de recibo.

      if (origFuerte && !origDolar) {
        // Al invertirla, monto / (1 / 1.16) = monto * 1.16
        tasaOrigenParaDolares = 1 / Math.max(tasaOrigenParaDolares, 0.001)
      }

      // Para el destino (Envío), la matemática estándar ya funciona correctamente como multiplicador directo.
      // E.g., tasa = 0.81 -> montoUSD * 0.81 = montoEUR.

      // Mantenemos las limpiezas de Cajas Dólar
      if (origFuerte && destDolar) tasaDestinoDesdeDolares = 1
      if (origDolar && destFuerte) tasaOrigenParaDolares = 1

    } else {
      // LOGICA DE MARGENES PARA USD (Zelle, Ecuador, etc)
      if (origDolar && !destDolar) {
        // ESCENARIO A: USD -> Moneda Local (Zelle -> Colombia)
        // Sumamos el margen de recibo del origen al margen de envío del destino
        const mO = (modo === 'mayor' && parseFloat(origen.margenReciboMayor) > 0) ? parseFloat(origen.margenReciboMayor) : (parseFloat(origen.margenRecibo) || 0);
        const mD = (modo === 'mayor' && parseFloat(destino.margenEnvioMayor) > 0) ? parseFloat(destino.margenEnvioMayor) : (parseFloat(destino.margenEnvio) || 0);
        tasaOrigenParaDolares = 1;
        const tBaseD = parseFloat(destino.tasaProveedorEnvio !== undefined ? destino.tasaProveedorEnvio : (destino.tasaProveedor || 0));
        tasaDestinoDesdeDolares = tBaseD * (1 - (mO + mD) / 100);
      } else if (origDolar && destDolar) {
        // ESCENARIO B: USD -> USD (E.g. Zelle -> Panamá, Ecuador -> Efectivo Venezuela)
        // Solo cuenta la tasa/margen envío del país destino
        tasaOrigenParaDolares = 1;
        const tBaseD = parseFloat(destino.tasaProveedorEnvio !== undefined ? destino.tasaProveedorEnvio : (destino.tasaProveedor || 0));
        const mD = (modo === 'mayor' && parseFloat(destino.margenEnvioMayor) > 0) ? parseFloat(destino.margenEnvioMayor) : (parseFloat(destino.margenEnvio) || 0);
        tasaDestinoDesdeDolares = tBaseD * (1 - mD / 100);
      } else if (!origDolar && destDolar) {
        // Caso inverso (Local -> USD)
        tasaDestinoDesdeDolares = 1;
      }
    }
  }

  if (tasaOrigenParaDolares === 0) tasaOrigenParaDolares = 1; // Seguridad matemática

  return { tasaOrigenParaDolares, tasaDestinoDesdeDolares, origen, destino }
}

/**
 * Calcula la conversión IDEAL hacia delante.
 */
export function calcularConversion(paisOrigen, paisDestino, monto, paises, modo = 'detal') {
  const { tasaOrigenParaDolares, tasaDestinoDesdeDolares } = obtenerTasasProcesadas(paisOrigen, paisDestino, paises, modo)
  const montoEnDolares = monto / tasaOrigenParaDolares
  return montoEnDolares * tasaDestinoDesdeDolares
}

/**
 * Calcula la conversión a la INVERSA (Cuanto necesito origen para que llegue exacto a destino)
 */
export function calcularConversionInversa(paisOrigen, paisDestino, montoRecibir, paises, modo = 'detal') {
  const { tasaOrigenParaDolares, tasaDestinoDesdeDolares } = obtenerTasasProcesadas(paisOrigen, paisDestino, paises, modo)
  if (tasaDestinoDesdeDolares === 0) return 0;
  const montoEnDolares = montoRecibir / tasaDestinoDesdeDolares
  return montoEnDolares * tasaOrigenParaDolares
}

/**
 * Formatea un número según la moneda destino.
 * Usa 2 decimales por defecto, más para tasas menores a 10.
 */
export function formatearMonto(valor, codigo, maxDigits) {
  if (!valor || isNaN(valor)) return '0.00'

  // Si nos piden decimales específicos (como en la tabla), los respetamos
  if (maxDigits !== undefined) {
    return valor.toLocaleString('es-CO', {
      minimumFractionDigits: 2,
      maximumFractionDigits: maxDigits,
    })
  }

  // Lógica inteligente: Si el valor es muy pequeño (menor a 1), necesitamos al menos 4 decimales
  const decimales = valor < 1 ? 4 : (valor < 100 ? 3 : 2)

  return valor.toLocaleString('es-CO', {
    minimumFractionDigits: 2,
    maximumFractionDigits: decimales,
  })
}

/**
 * Carga los países desde localStorage o usa los valores por defecto.
 */
export function cargarPaises() {
  try {
    const guardados = localStorage.getItem('jk_paises')
    if (guardados) {
      const parsed = JSON.parse(guardados)
      // Fusionamos con los datos iniciales para asegurar que tengamos iso2 y banderas nuevas
      return parsed.map(p => {
        const inicial = PAISES_INICIALES.find(ini => ini.id === p.id)
        if (inicial) {
          return { ...p, iso2: inicial.iso2, bandera: inicial.bandera }
        }
        return p
      })
    }
  } catch (e) { }
  return PAISES_INICIALES
}

export async function sincronizarGoogleSheets() {
  try {
    const url = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv";
    const res = await fetch(url + "&nocache=" + new Date().getTime());
    if (!res.ok) throw new Error("No se pudo descargar el CSV");
    const csv = await res.text();

    // Parseo de CSV robusto (para ignorar comillas o comas raras)
    const lineas = csv.split('\n').filter(l => l.trim().length > 0);
    const datosNuevos = [];

    // Auto-detectar columnas de factor en la cabecera (Fila 0)
    let headRow = [];
    let inQHead = false;
    let currH = '';
    for (let c of lineas[0].trim()) {
      if (c === '"') inQHead = !inQHead;
      else if (c === ',' && !inQHead) { headRow.push(currH.toUpperCase()); currH = ''; }
      else currH += c;
    }
    headRow.push(currH.toUpperCase());

    const idxEUR = headRow.findIndex(h => h.includes('FACTOR EUR') || h.includes('VALOR EUR'));
    const idxUSDT = headRow.findIndex(h => h.includes('FACTOR USDT') || h.includes('VALOR USDT'));
    const idxISO = headRow.findIndex(h => h.includes('ISO') || h.includes('BANDERA'));
    const idxCod = headRow.findIndex(h => h.includes('CÓDIGO') || h.includes('CODIGO') || h.includes('BANCO'));
    const idxMargenEnvioMayor = headRow.findIndex(h => h.includes('MARGEN ENVIO MAYOR') || h.includes('MARGEN ENVÍO MAYOR'));
    const idxMargenReciboMayor = headRow.findIndex(h => h.includes('MARGEN RECIBO MAYOR'));
    const idxCiudades = headRow.findIndex(h => h.includes('CIUDADES'));
    const idxMon = headRow.findIndex(h => h.includes('NOMBRE') || h.includes('MONEDA'));

    // Empezamos desde la línea 1 (omitiendo cabeceras País, Tasa Envio, etc)
    for (let i = 1; i < lineas.length; i++) {
      let row = [];
      let inQuotes = false;
      let current = '';
      for (let c of lineas[i].trim()) {
        if (c === '"') inQuotes = !inQuotes;
        else if (c === ',' && !inQuotes) { row.push(current); current = ''; }
        else current += c;
      }
      row.push(current);


      // Columna 0 = País, Columna 1 = Envio, 2 = MargenE, 3 = Recibo, 4 = MargenR
      if (row.length >= 1 && row[0].trim() !== '') {
        const nombreCol = row[0].trim();

        const parseVal = (str) => {
          if (!str) return 0;
          let s = str.replace(/\s/g, ''); // quitar espacios
          s = s.replace(',', '.'); // reemplazar posible uso europeo a estándar
          const val = parseFloat(s);
          return isNaN(val) ? 0 : val;
        };

        const tE = row.length >= 2 ? parseVal(row[1]) : 0;
        const mE = row.length >= 3 ? parseVal(row[2]) : 6;
        const tR = row.length >= 4 ? parseVal(row[3]) : 0;
        const mR = row.length >= 5 ? parseVal(row[4]) : 6;

        if (tE === 0 && tR === 0 && mE === 0 && mR === 0 && typeof row[1] === 'string' && row[1].includes('Tasa')) {
          // Posible cabecera repetida o basura
          continue;
        }

        // Buscar si es un país conocido para heredar bandera e ISO
        const normalize = str => str.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
        const base = PAISES_INICIALES.find(p => normalize(p.nombre) === normalize(nombreCol));

        // Evaluamos metadata de columnas buscando por su índice
        const isoCustom = idxISO !== -1 && row.length > idxISO && row[idxISO].trim() !== '' ? row[idxISO].trim().toLowerCase() : null;
        const codCustom = idxCod !== -1 && row.length > idxCod && row[idxCod].trim() !== '' ? row[idxCod].trim().toUpperCase() : null;
        const monCustom = idxMon !== -1 && row.length > idxMon && row[idxMon].trim() !== '' ? row[idxMon].trim() : null;

        // Evaluamos factores dinámicamente según cabecera
        const valFactorEUR = idxEUR !== -1 && row.length > idxEUR ? parseVal(row[idxEUR]) : 0;
        const valFactorUSDT = idxUSDT !== -1 && row.length > idxUSDT ? parseVal(row[idxUSDT]) : 0;

        datosNuevos.push({
          id: base ? base.id : Date.now() + i, // Generar ID único si es nuevo
          nombre: base ? base.nombre : nombreCol, // Respetar nombre capitalizado de base
          iso2: isoCustom || (base ? base.iso2 : 'un'), // Prioridad al Custom ISO, luego al base, luego genérico
          bandera: base ? base.bandera : '🌐',
          codigo: codCustom || (base ? base.codigo : nombreCol.substring(0, 3).toUpperCase()),
          moneda: monCustom || (base ? base.moneda : 'Divisa Local'),
          tasaProveedorEnvio: tE,
          margenEnvio: mE,
          tasaProveedorRecibo: tR,
          margenRecibo: mR,
          factorEUR: valFactorEUR || (base ? base.factorEUR || 0 : 0),
          factorUSDT: valFactorUSDT || (base ? base.factorUSDT || 0 : 0),
          margenEnvioMayor: idxMargenEnvioMayor !== -1 && row.length > idxMargenEnvioMayor ? parseVal(row[idxMargenEnvioMayor]) : 0,
          margenReciboMayor: idxMargenReciboMayor !== -1 && row.length > idxMargenReciboMayor ? parseVal(row[idxMargenReciboMayor]) : 0,
          ciudades: idxCiudades !== -1 && row.length > idxCiudades && row[idxCiudades].trim() !== '' ? row[idxCiudades].trim() : ''
        });
      }
    }

    // Solo guardamos si el Sheets realmente tenía la data de países
    if (datosNuevos.length > 0) {
      localStorage.setItem('jk_paises', JSON.stringify(datosNuevos));
      return true;
    }
    return false;
  } catch (e) {
    console.error('Error sincronizando Google Sheets:', e);
    return false;
  }
}
