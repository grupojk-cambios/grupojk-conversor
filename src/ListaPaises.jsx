import { useState, useEffect } from 'react'
import { cargarPaises, calcularTasaPublica, formatearMonto } from './constants'

// Gráfica SVG simple de barras — normalizadas al máximo
function GraficaBarras({ paises }) {
  // Seleccionar 8 países con tasas interesantes (excluir USD=1)
  const seleccionados = paises
    .filter(p => p.codigo !== 'USD')
    .slice(0, 8)

  if (!seleccionados.length) return null

  const tasas = seleccionados.map(p => calcularTasaPublica(p))
  const maxTasa = Math.max(...tasas)

  const WIDTH = 600
  const HEIGHT = 220
  const PADDING = { top: 20, right: 10, bottom: 70, left: 10 }
  const barW = Math.floor((WIDTH - PADDING.left - PADDING.right) / seleccionados.length)
  const gap = Math.floor(barW * 0.25)
  const barWidth = barW - gap

  return (
    <div style={{ width: '100%', overflowX: 'auto' }}>
      <svg
        viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
        style={{ width: '100%', maxWidth: WIDTH, display: 'block', margin: '0 auto' }}
      >
        {/* Líneas guía horizontales */}
        {[0.25, 0.5, 0.75, 1].map(frac => {
          const y = PADDING.top + (HEIGHT - PADDING.top - PADDING.bottom) * (1 - frac)
          return (
            <line key={frac} x1={PADDING.left} x2={WIDTH - PADDING.right} y1={y} y2={y}
              stroke="rgba(158,171,200,0.12)" strokeWidth="1" />
          )
        })}

        {/* Barras */}
        {seleccionados.map((pais, i) => {
          const tasa = calcularTasaPublica(pais)
          const normalized = tasa / maxTasa
          const barH = (HEIGHT - PADDING.top - PADDING.bottom) * normalized
          const x = PADDING.left + i * barW + gap / 2
          const y = HEIGHT - PADDING.bottom - barH

          // Formato corto para la etiqueta
          let label = tasa >= 1000
            ? (tasa / 1000).toFixed(1) + 'K'
            : tasa >= 1
              ? tasa.toFixed(0)
              : tasa.toFixed(3)

          return (
            <g key={pais.id}>
              {/* Barra con gradiente */}
              <defs>
                <linearGradient id={`grad-${pais.id}`} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#69F6B8" stopOpacity="0.9" />
                  <stop offset="100%" stopColor="#10B981" stopOpacity="0.6" />
                </linearGradient>
              </defs>
              <rect
                x={x} y={y}
                width={barWidth} height={barH}
                rx="4" ry="4"
                fill={`url(#grad-${pais.id})`}
              />
              {/* Valor arriba de la barra */}
              <text
                x={x + barWidth / 2} y={y - 4}
                textAnchor="middle"
                fill="#69F6B8"
                fontSize="9"
                fontFamily="Manrope, sans-serif"
                fontWeight="700"
              >
                {label}
              </text>
              {/* Bandera del país */}
              <image
                x={x + barWidth / 2 - 10} y={HEIGHT - PADDING.bottom + 4}
                width="20" height="15"
                href={`https://flagcdn.com/w40/${(pais.iso2 || pais.codigo.substring(0,2)).toLowerCase()}.png`}
              />
              {/* Código */}
              <text
                x={x + barWidth / 2} y={HEIGHT - PADDING.bottom + 34}
                textAnchor="middle"
                fill="#9EABC8"
                fontSize="8"
                fontFamily="Inter, sans-serif"
              >
                {pais.codigo}
              </text>
            </g>
          )
        })}
      </svg>
      <p style={{ textAlign: 'center', fontSize: '0.75rem', color: 'var(--text-low)', marginTop: '0.5rem' }}>
        Unidades de moneda local por 1 USD · Tasas GRUPO JK
      </p>
    </div>
  )
}

export default function ListaPaises() {
  const [paises, setPaises] = useState([])
  const [busqueda, setBusqueda] = useState('')

  useEffect(() => {
    setPaises(cargarPaises())
  }, [])

  const paisesFiltrados = paises.filter(p =>
    p.nombre.toLowerCase().includes(busqueda.toLowerCase()) ||
    p.codigo.toLowerCase().includes(busqueda.toLowerCase()) ||
    p.moneda.toLowerCase().includes(busqueda.toLowerCase())
  )

  return (
    <div style={{ maxWidth: '1100px', margin: '0 auto', padding: '2rem 1.5rem' }}>

      <div style={{ textAlign: 'center', marginBottom: '3rem' }}>
        <h2 style={{ fontSize: 'clamp(1.8rem, 4vw, 2.5rem)', marginBottom: '0.5rem' }}>
          🌎 Tasas de Cambio
        </h2>
        <p style={{ color: 'var(--text-low)' }}>
          {paises.length} países disponibles · Tasa base: 1 USD
        </p>
      </div>

      {/* Grática de barras */}
      <div className="glass" style={{ padding: '2rem', marginBottom: '2.5rem' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.5rem', flexWrap: 'wrap', gap: '0.5rem' }}>
          <div>
            <h3 style={{ fontSize: '1.2rem', marginBottom: '0.2rem' }}>📊 Tasas Actuales vs USD</h3>
            <p style={{ fontSize: '0.8rem', color: 'var(--text-low)' }}>
              Comparativa de las monedas más usadas · Actualizadas por el administrador
            </p>
          </div>
          <span className="badge badge-success">En vivo</span>
        </div>
        <GraficaBarras paises={paises} />
      </div>

      {/* Buscador */}
      <div style={{ marginBottom: '1.5rem' }}>
        <div className="search-container" style={{ maxWidth: '100%' }}>
          <span className="search-icon">🔍</span>
          <input
            type="text"
            className="search-input"
            placeholder="Buscar país, moneda o código ISO..."
            value={busqueda}
            onChange={e => setBusqueda(e.target.value)}
            style={{ width: '100%', fontSize: '1rem' }}
          />
        </div>
      </div>

      {/* Tabla */}
      <div className="glass" style={{ padding: '0', overflow: 'hidden' }}>
        {/* Header */}
        <div style={{
          display: 'grid',
          gridTemplateColumns: '2.5rem 1fr 1fr 1fr 1fr',
          gap: '1rem',
          padding: '1rem 1.5rem',
          background: 'rgba(0,0,0,0.2)',
          borderBottom: '1px solid var(--glass-border)',
        }}>
          {['', 'País', 'Moneda', 'Código ISO', 'Tasa por USD'].map((h, i) => (
            <div key={i} style={{
              fontSize: '0.7rem',
              color: 'var(--text-low)',
              textTransform: 'uppercase',
              letterSpacing: '0.1em',
              fontWeight: 700,
              textAlign: i === 4 ? 'right' : 'left',
            }}>
              {h}
            </div>
          ))}
        </div>

        {/* Filas */}
        {paisesFiltrados.map((pais, idx) => {
          const tp = calcularTasaPublica(pais)
          const esUSD = pais.codigo === 'USD'
          return (
            <div
              key={pais.id}
              style={{
                display: 'grid',
                gridTemplateColumns: '2.5rem 1fr 1fr 1fr 1fr',
                gap: '1rem',
                padding: '1rem 1.5rem',
                borderBottom: idx < paisesFiltrados.length - 1 ? '1px solid var(--glass-border)' : 'none',
                transition: 'background 0.2s',
                alignItems: 'center',
              }}
              onMouseEnter={e => e.currentTarget.style.background = 'rgba(255,255,255,0.03)'}
              onMouseLeave={e => e.currentTarget.style.background = 'transparent'}
            >
              <div style={{ width: '2.5rem', height: '1.6rem', borderRadius: '0.3rem', overflow: 'hidden', boxShadow: '0 2px 6px rgba(0,0,0,0.2)' }}>
                <img 
                  src={`https://flagcdn.com/w80/${(pais.iso2 || pais.codigo.substring(0,2)).toLowerCase()}.png`}
                  alt={pais.nombre}
                  style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                />
              </div>
              <div>
                <p style={{ fontWeight: 700, color: 'white', fontSize: '0.95rem' }}>{pais.nombre}</p>
              </div>
              <div style={{ color: 'var(--text-low)', fontSize: '0.875rem' }}>{pais.moneda}</div>
              <div>
                <span className="badge badge-success" style={{ fontFamily: 'monospace' }}>
                  {pais.codigo}
                </span>
              </div>
              <div style={{ textAlign: 'right' }}>
                <p style={{
                  fontWeight: 800,
                  color: esUSD ? 'var(--text-mid)' : 'var(--primary-color)',
                  fontSize: '1.1rem',
                  fontFamily: 'Manrope, sans-serif',
                }}>
                  {esUSD ? '1.0000' : formatearMonto(tp, pais.codigo)}
                </p>
                <p style={{ fontSize: '0.7rem', color: 'var(--text-low)' }}>{pais.codigo}/USD</p>
              </div>
            </div>
          )
        })}

        {paisesFiltrados.length === 0 && (
          <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--text-low)' }}>
            No se encontraron países con "{busqueda}"
          </div>
        )}
      </div>

      <p style={{ textAlign: 'center', fontSize: '0.8rem', color: 'var(--text-low)', marginTop: '1.5rem' }}>
        Todas las tasas incluyen el diferencial de cambio de GRUPO JK · Basadas en USD como moneda de referencia
      </p>
    </div>
  )
}
