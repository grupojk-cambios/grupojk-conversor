// ============================================================================
//  MOTOR DE CALCULO — FUENTE UNICA DE VERDAD
// ============================================================================
//  Este archivo es la UNICA copia de las matematicas de tasas y cruces.
//
//  Lo usan DOS consumidores:
//    1) La app (React).  src/constants.js lo re-exporta, asi que los demas
//       archivos lo siguen importando desde 'constants.js' como siempre.
//    2) El bot de WhatsApp (n8n).  build_v12.ps1 lee este archivo, le quita
//       los "export" e INYECTA el texto tal cual dentro de los nodos
//       "Code in JavaScript" y "Calculadora de Conversion".
//
//  POR ESO, REGLAS AL EDITAR ESTE ARCHIVO:
//    - JavaScript puro. NADA de import.meta, window, document, fetch ni React.
//    - Sin imports de otros archivos (se inyecta suelto, no habria de donde).
//    - Cada funcion declarada como "export function" en el margen izquierdo
//       (asi la encuentra el inyector del build).
//
//  Si lo cambias: corre "npm run verificar-motor" (compara app vs bot y
//  falla si se despegan) y vuelve a desplegar el bot para que lo reciba.
//
//  Historia: antes habia 3 copias de esto (app + 2 nodos del bot). Se
//  despegaron y el bot regalaba plata: daba 101 USD por 100 EUR a Zelle
//  cuando lo correcto eran 95.04, porque forzaba paridad 1:1 y se comia el
//  margen del destino. De ahi viene este archivo.
// ============================================================================

/**
 * Tasa de Envío (cuando el sistema vende USD y entrega esta moneda).
 * Se RESTA el margen al proveedor.
 */
export function calcularTasaEnvio(pais, modo = 'detal') {
  const rawProveedor = pais.tasaProveedorEnvio !== undefined ? pais.tasaProveedorEnvio : (pais.tasaProveedor || 0)
  const tProveedor = parseFloat(rawProveedor) || 0;

  if (tProveedor === 0) return 0
  // Eliminamos el retorno forzado de 1 para USD para permitir ver la "Tasa Real" con margen

  let rawMargen;
  if (modo === 'mayor' && pais.margenEnvioMayor !== undefined && pais.margenEnvioMayor !== null && !isNaN(parseFloat(pais.margenEnvioMayor))) {
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
  // Eliminamos el retorno forzado de 1 para USD para permitir ver la "Tasa Real" con margen

  let rawMargen;
  if (modo === 'mayor' && pais.margenReciboMayor !== undefined && pais.margenReciboMayor !== null && !isNaN(parseFloat(pais.margenReciboMayor))) {
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

/**
 * Ecuador es la base USD de referencia del operador: nunca lleva margen.
 * Se reconoce por id (como lo arma la app) O por nombre (como lo arma el bot,
 * que lee el CSV y no maneja ids).
 */
export function esEcuador(p) {
  if (!p) return false;
  return p.id === 9 || (p.nombre || '').toLowerCase() === 'ecuador';
}

export function isCajaDolar(p) {
  if (!p) return false;
  const nom = (p.nombre || '').toLowerCase();
  return ['USD', 'USDT', 'EC', 'US', 'PA'].includes(p.codigo) || [9, 11, 18].includes(p.id) || nom.includes('usdt') || nom.includes('zelle') || nom.includes('efectivo ven');
}

/**
 * Cerebro maestro de Tasas para cruces limpios y factores dinámicos.
 */
export function obtenerTasasProcesadas(paisOrigen, paisDestino, paises, modo = 'detal') {
  // El bot de n8n arma sus paises desde el CSV y NO les pone id. Sin el guard de
  // "p.id !== undefined", find() casaria undefined===undefined y devolveria SIEMPRE
  // el primer pais de la lista. Con el guard, el bot cae limpio al pais que le pasaron.
  const lista = paises || []
  const origen = lista.find(p => p.id !== undefined && p.id === paisOrigen.id) || paisOrigen
  const destino = lista.find(p => p.id !== undefined && p.id === paisDestino.id) || paisDestino

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
    // (No hace falta un "destFuerte": ver el comentario de abajo — para entregar
    //  Euros, calcularTasaEnvio ya hizo tBase * (1 - mD/100) y no se invierte.)
    const origDolar = isCajaDolar(origen)
    const destDolar = isCajaDolar(destino)

    if (origFuerte) {
      // Para Monedas Fuertes (EUR, GBP) como origen:
      // Al recibir Euros, el margen descuenta al cliente: montoEUR * tBase * (1 - mO / 100)
      let mO = (modo === 'mayor' && origen.margenReciboMayor !== undefined && origen.margenReciboMayor !== null && !isNaN(parseFloat(origen.margenReciboMayor)))
        ? parseFloat(origen.margenReciboMayor)
        : (parseFloat(origen.margenRecibo) || 0);
      const rawBaseO = origen.tasaProveedorRecibo !== undefined ? origen.tasaProveedorRecibo : (origen.tasaProveedor || 1);
      const tBaseO = parseFloat(rawBaseO) || 1;
      const factorEurNeto = Math.max(tBaseO * (1 - mO / 100), 0.00001);
      tasaOrigenParaDolares = 1 / factorEurNeto;
    }
    // Para destFuerte (entregar Euros), calcularTasaEnvio ya calcula tBase * (1 - mD / 100).
    // Con base 1 y margen 20%, da 0.80 directo (500 USD * 0.80 = 400 EUR). NO SE INVIERTE.

    if (origDolar && destDolar) {
      // CAJA DÓLAR A CAJA DÓLAR ($ a $) (USDT, Zelle, Efectivo Venezuela, Ecuador, Panamá):
      // Suma directa de márgenes: margenRecibo(origen) + margenEnvio(destino).
      // Se suman directamente los porcentajes (ej: Zelle 5% + Ecuador 1% = 6%; Zelle 5% + USDT 5% = 10%).
      // Ecuador sí suma su comisión cuando se envía o recibe entre cajas dólar.
      let mO = (modo === 'mayor' && origen.margenReciboMayor !== undefined && origen.margenReciboMayor !== null && !isNaN(parseFloat(origen.margenReciboMayor)))
        ? parseFloat(origen.margenReciboMayor)
        : (parseFloat(origen.margenRecibo) || 0);
      let mD = (modo === 'mayor' && destino.margenEnvioMayor !== undefined && destino.margenEnvioMayor !== null && !isNaN(parseFloat(destino.margenEnvioMayor)))
        ? parseFloat(destino.margenEnvioMayor)
        : (parseFloat(destino.margenEnvio) || 0);

      const mTotal = mO + mD;
      tasaOrigenParaDolares = 1;
      tasaDestinoDesdeDolares = Math.max(1 * (1 - mTotal / 100), 0.00001);
    } else {
      if (origDolar) {
        // CAJA DÓLAR ORIGEN (USDT, Zelle, Efectivo Venezuela, Ecuador) -> Moneda Local:
        // El margen de recibo (mO) se calcula sobre base 1 fija e independiente.
        // Así puedes anotar tu costo real (ej. 1.01) en Excel para tu sistema contable,
        // y la app descontará el margen limpio sobre 100 (ej: 8% -> 92.00 USD exactos).
        let mO = (modo === 'mayor' && origen.margenReciboMayor !== undefined && origen.margenReciboMayor !== null && !isNaN(parseFloat(origen.margenReciboMayor)))
          ? parseFloat(origen.margenReciboMayor)
          : (parseFloat(origen.margenRecibo) || 0);
        // Si Ecuador es la base de referencia hacia moneda local, se mantiene neutro (base limpia para la pizarra)
        if (esEcuador(origen)) mO = 0;

        // Base 1 fija para el cálculo público del margen
        const factorDolarNeto = Math.max(1 * (1 - mO / 100), 0.00001);
        tasaOrigenParaDolares = 1 / factorDolarNeto;
      }

      if (destDolar) {
        // Moneda Local -> CAJA DÓLAR DESTINO (USDT, Zelle, Efectivo Venezuela, Ecuador):
        // Al entregar, el margen de envío (mD) se calcula sobre base 1 fija:
        // Si el margen es 7%, entrega 93.00 USDT exactos (100 * 0.93 = 93.00).
        let mD = (modo === 'mayor' && destino.margenEnvioMayor !== undefined && destino.margenEnvioMayor !== null && !isNaN(parseFloat(destino.margenEnvioMayor)))
          ? parseFloat(destino.margenEnvioMayor)
          : (parseFloat(destino.margenEnvio) || 0);

        tasaDestinoDesdeDolares = 1 * (1 - mD / 100);
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

  // Tasa base del proveedor para el destino
  const tBaseD = parseFloat(paisDestino.tasaProveedorEnvio !== undefined ? paisDestino.tasaProveedorEnvio : (paisDestino.tasaProveedor || 0));

  // Matemática Aditiva para el reverso (ej: 100 de 102)
  // Si la tasa procesada es menor a la del proveedor, significa que se restó un margen (ej. 1 -> 0.98)
  // En el reverso, el usuario prefiere sumar ese mismo % (matemática aditiva) para resultados más "redondos".
  if (tBaseD > 0 && tasaDestinoDesdeDolares < tBaseD) {
    const margenTotalDecimal = (tBaseD - tasaDestinoDesdeDolares) / tBaseD;
    // (Monto / TasaBase) * (1 + Margen%) * TasaOrigen
    const res = (montoRecibir / tBaseD) * (1 + margenTotalDecimal) * tasaOrigenParaDolares;
    return res;
  }

  const montoEnDolares = montoRecibir / tasaDestinoDesdeDolares
  return montoEnDolares * tasaOrigenParaDolares
}
