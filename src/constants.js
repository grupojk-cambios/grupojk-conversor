// Datos de los 19 países — tasas expresadas como "unidades de moneda por 1 USD"
export const PAISES_INICIALES = [
  { id: 1,  nombre: 'Argentina',   iso2: 'ar', bandera: '🇦🇷', codigo: 'ARS', moneda: 'Peso Argentino',          tasaProveedorEnvio: 1050, margenEnvio: 6, tasaProveedorRecibo: 1050, margenRecibo: 9 },
  { id: 2,  nombre: 'Uruguay',     iso2: 'uy', bandera: '🇺🇾', codigo: 'UYU', moneda: 'Peso Uruguayo',           tasaProveedorEnvio: 42,   margenEnvio: 6, tasaProveedorRecibo: 42,   margenRecibo: 6 },
  { id: 3,  nombre: 'Chile',       iso2: 'cl', bandera: '🇨🇱', codigo: 'CLP', moneda: 'Peso Chileno',            tasaProveedorEnvio: 950,  margenEnvio: 6, tasaProveedorRecibo: 950,  margenRecibo: 9 },
  { id: 4,  nombre: 'Paraguay',    iso2: 'py', bandera: '🇵🇾', codigo: 'PYG', moneda: 'Guaraní Paraguayo',       tasaProveedorEnvio: 7800, margenEnvio: 6, tasaProveedorRecibo: 7800, margenRecibo: 6 },
  { id: 5,  nombre: 'Brasil',      iso2: 'br', bandera: '🇧🇷', codigo: 'BRL', moneda: 'Real Brasileño',          tasaProveedorEnvio: 5.1,  margenEnvio: 6, tasaProveedorRecibo: 5.83, margenRecibo: 6 },
  { id: 6,  nombre: 'Bolivia',     iso2: 'bo', bandera: '🇧🇴', codigo: 'BOB', moneda: 'Boliviano',               tasaProveedorEnvio: 6.9,  margenEnvio: 6, tasaProveedorRecibo: 6.9,  margenRecibo: 6 },
  { id: 7,  nombre: 'Perú',        iso2: 'pe', bandera: '🇵🇪', codigo: 'PEN', moneda: 'Sol Peruano',             tasaProveedorEnvio: 3.41, margenEnvio: 6, tasaProveedorRecibo: 3.6,  margenRecibo: 9 },
  { id: 8,  nombre: 'Colombia',    iso2: 'co', bandera: '🇨🇴', codigo: 'COP', moneda: 'Peso Colombiano',         tasaProveedorEnvio: 3640, margenEnvio: 3.0219, tasaProveedorRecibo: 3640, margenRecibo: 4 },
  { id: 9,  nombre: 'Ecuador',     iso2: 'ec', bandera: '🇪🇨', codigo: 'USD', moneda: 'Dólar Americano',         tasaProveedorEnvio: 1,    margenEnvio: 0, tasaProveedorRecibo: 1,    margenRecibo: 0 },
  { id: 10, nombre: 'Venezuela',   iso2: 've', bandera: '🇻🇪', codigo: 'VES', moneda: 'Bolívar Digital',         tasaProveedorEnvio: 645,  margenEnvio: 3.411, tasaProveedorRecibo: 645,  margenRecibo: 6 },
  { id: 11, nombre: 'Panamá',      iso2: 'pa', bandera: '🇵🇦', codigo: 'USD', moneda: 'Dólar Americano',         tasaProveedorEnvio: 1,    margenEnvio: 0, tasaProveedorRecibo: 1,    margenRecibo: 0 },
  { id: 12, nombre: 'Costa Rica',  iso2: 'cr', bandera: '🇨🇷', codigo: 'CRC', moneda: 'Colón Costarricense',     tasaProveedorEnvio: 520,  margenEnvio: 6, tasaProveedorRecibo: 520,  margenRecibo: 6 },
  { id: 13, nombre: 'Nicaragua',   iso2: 'ni', bandera: '🇳🇮', codigo: 'NIO', moneda: 'Córdoba Nicaragüense',    tasaProveedorEnvio: 36.5, margenEnvio: 6, tasaProveedorRecibo: 36.5, margenRecibo: 6 },
  { id: 14, nombre: 'Honduras',    iso2: 'hn', bandera: '🇭🇳', codigo: 'HNL', moneda: 'Lempira Hondureño',       tasaProveedorEnvio: 25,   margenEnvio: 6, tasaProveedorRecibo: 25,   margenRecibo: 6 },
  { id: 15, nombre: 'Guatemala',   iso2: 'gt', bandera: '🇬🇹', codigo: 'GTQ', moneda: 'Quetzal Guatemalteco',    tasaProveedorEnvio: 7.7,  margenEnvio: 6, tasaProveedorRecibo: 7.7,  margenRecibo: 6 },
  { id: 16, nombre: 'Cuba',        iso2: 'cu', bandera: '🇨🇺', codigo: 'CUP', moneda: 'Peso Cubano',             tasaProveedorEnvio: 350,  margenEnvio: 6, tasaProveedorRecibo: 350,  margenRecibo: 6 },
  { id: 17, nombre: 'México',      iso2: 'mx', bandera: '🇲🇽', codigo: 'MXN', moneda: 'Peso Mexicano',           tasaProveedorEnvio: 20,   margenEnvio: 6, tasaProveedorRecibo: 20,   margenRecibo: 6 },
  { id: 18, nombre: 'EEUU',        iso2: 'us', bandera: '🇺🇸', codigo: 'USD', moneda: 'Dólar Americano',         tasaProveedorEnvio: 1,    margenEnvio: 0, tasaProveedorRecibo: 1,    margenRecibo: 0 },
  { id: 19, nombre: 'Europa',      iso2: 'eu', bandera: '🇪🇺', codigo: 'EUR', moneda: 'Euro',                    tasaProveedorEnvio: 0.92, margenEnvio: 6, tasaProveedorRecibo: 0.92, margenRecibo: 6 },
]

// IDs de países destacados en el Dashboard (los más frecuentes)
export const PAISES_DESTACADOS_IDS = [8, 10, 17, 7, 3, 19] // Colombia, Venezuela, México, Perú, Chile, Europa

/**
 * Tasa de Envío (cuando el sistema vende USD y entrega esta moneda).
 * Se RESTA el margen al proveedor.
 */
export function calcularTasaEnvio(pais) {
  if (pais.codigo === 'USD' || pais.margenEnvio === 0) return 1
  const tProveedor = pais.tasaProveedorEnvio || pais.tasaProveedor || 0
  const margen = pais.margenEnvio !== undefined ? pais.margenEnvio : (pais.margen || 0)
  return tProveedor * (1 - margen / 100)
}

/**
 * Tasa de Recibo / Inversa (cuando el sistema recibe esta moneda y entrega USD).
 * Se SUMA el margen al proveedor.
 */
export function calcularTasaRecibo(pais) {
  if (pais.codigo === 'USD' || pais.margenRecibo === 0) return 1
  const tProveedor = pais.tasaProveedorRecibo || pais.tasaProveedor || 0
  const margen = pais.margenRecibo !== undefined ? pais.margenRecibo : (pais.margen || 0)
  return tProveedor * (1 + margen / 100)
}

/**
 * Calculo normal para mostrar la "Tasa Pública" general (que suele ser la de envío)
 */
export function calcularTasaPublica(pais) {
  return calcularTasaEnvio(pais)
}

/**
 * Calcula la conversión entre dos países usando USD como pivote.
 */
export function calcularConversion(paisOrigen, paisDestino, monto, paises) {
  const origen = paises.find(p => p.id === paisOrigen.id) || paisOrigen
  const destino = paises.find(p => p.id === paisDestino.id) || paisDestino

  const tasaOrigenParaDolares = calcularTasaRecibo(origen)
  const tasaDestinoDesdeDolares = calcularTasaEnvio(destino)

  const montoEnDolares = monto / tasaOrigenParaDolares
  return montoEnDolares * tasaDestinoDesdeDolares
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
  } catch (e) {}
  return PAISES_INICIALES
}
