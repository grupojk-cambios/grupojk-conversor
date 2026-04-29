import { useState, useEffect } from 'react'
import { cargarPaises, calcularTasaEnvio, calcularTasaRecibo, formatearMonto, getFlagUrl } from './constants'


export default function ListaPaises({ modo = 'detal' }) {
  const [paises, setPaises] = useState([])
  const [busqueda, setBusqueda] = useState('')
  const [listaActiva, setListaActiva] = useState('enviar')
  const [isMobile, setIsMobile] = useState(window.innerWidth <= 768)
  const esMayor = modo === 'mayor'

  useEffect(() => {
    setPaises(cargarPaises())
  }, [])

  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth <= 768)
    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [])

  const paisesFiltrados = paises.filter(p =>
    p.nombre.toLowerCase().includes(busqueda.toLowerCase()) ||
    p.codigo.toLowerCase().includes(busqueda.toLowerCase()) ||
    p.moneda.toLowerCase().includes(busqueda.toLowerCase())
  )

  const getTasa = (pais) => {
    if (listaActiva === 'enviar') return calcularTasaEnvio(pais, modo)
    return calcularTasaRecibo(pais, modo)
  }

  const labelColumna = listaActiva === 'enviar' ? 'Tasa Enviar / USD' : 'Tasa Recibir / USD'

  return (
    <div style={{ maxWidth: '1100px', margin: '0 auto', padding: isMobile ? '1.5rem 1rem' : '2rem 1.5rem' }}>

      <div style={{ textAlign: 'center', marginBottom: '2rem' }}>
        <h2 style={{ fontSize: 'clamp(1.8rem, 4vw, 2.5rem)', marginBottom: '0.5rem' }}>
          🌎 Tasas de Cambio{esMayor ? ' Mayor' : ''}
        </h2>
        <p style={{ color: 'var(--text-low)' }}>
          {paises.length} países disponibles · Tasa base: 1 USD
        </p>
      </div>

      {/* ── TABS TOGGLE ── */}
      <div style={{
        display: 'flex',
        justifyContent: 'center',
        marginBottom: '2rem',
      }}>
        <div style={{
          display: 'flex',
          background: 'var(--surface-color)',
          border: '1px solid var(--glass-border)',
          borderRadius: '1rem',
          padding: '0.3rem',
          gap: '0.3rem',
        }}>
          {[
            { key: 'enviar', label: '📤 Tasa Enviar', desc: 'Cuánta moneda entrega JK' },
            { key: 'recibir', label: '📥 Tasa Recibir', desc: 'Cuánta moneda recibe JK' },
          ].map(tab => {
            const activo = listaActiva === tab.key
            return (
              <button
                key={tab.key}
                onClick={() => setListaActiva(tab.key)}
                title={tab.desc}
                style={{
                  padding: isMobile ? '0.6rem 1.2rem' : '0.7rem 2rem',
                  borderRadius: '0.75rem',
                  border: 'none',
                  cursor: 'pointer',
                  fontFamily: 'Manrope, sans-serif',
                  fontWeight: 700,
                  fontSize: isMobile ? '0.85rem' : '0.95rem',
                  transition: 'all 0.25s ease',
                  background: activo
                    ? 'var(--primary-color)'
                    : 'transparent',
                  color: activo ? 'var(--bg-color)' : 'var(--text-low)',
                  boxShadow: activo ? '0 0 18px rgba(16,185,129,0.35)' : 'none',
                }}
              >
                {tab.label}
              </button>
            )
          })}
        </div>
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

      {/* Tabla / Tarjetas */}
      <div className="glass" style={{ padding: '0', overflow: 'hidden' }}>
        {isMobile ? (
          // Vista de tarjetas para móvil y tablet
          <div>
            {/* Cabecera de la lista activa */}
            <div style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              padding: '0.75rem 1rem',
              background: 'rgba(16,185,129,0.08)',
              borderBottom: '1px solid var(--glass-border)',
            }}>
              <span style={{ fontSize: '0.7rem', fontWeight: 700, color: 'var(--primary-color)', textTransform: 'uppercase', letterSpacing: '0.08em' }}>
                {listaActiva === 'enviar' ? '📤 Tasa Enviar' : '📥 Tasa Recibir'}
              </span>
              <span style={{ fontSize: '0.7rem', color: 'var(--text-low)' }}>
                {listaActiva === 'enviar' ? 'JK entrega esta moneda' : 'JK recibe esta moneda'}
              </span>
            </div>
            {paisesFiltrados.map((pais, idx) => {
              const tp = getTasa(pais)
              const esUSD = pais.codigo === 'USD'
              return (
                <div
                  key={pais.id}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: '0.75rem',
                    padding: '0.9rem 1rem',
                    borderBottom: idx < paisesFiltrados.length - 1 ? '1px solid var(--glass-border)' : 'none',
                  }}
                >
                  {/* Bandera */}
                  <div style={{ width: '2.8rem', height: '1.9rem', borderRadius: '0.3rem', overflow: 'hidden', flexShrink: 0, boxShadow: '0 2px 6px rgba(0,0,0,0.2)' }}>
                    <img src={getFlagUrl(pais)} alt={pais.nombre} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  </div>
                  {/* Nombre + moneda */}
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <p style={{ fontWeight: 700, color: 'white', fontSize: '0.95rem', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{pais.nombre}</p>
                    <p style={{ fontSize: '0.72rem', color: 'var(--text-low)', marginTop: '1px' }}>{pais.moneda}</p>
                  </div>
                  {/* Código + tasa */}
                  <div style={{ textAlign: 'right', flexShrink: 0 }}>
                    <span className="badge badge-success" style={{ fontFamily: 'monospace', fontSize: '0.72rem', marginBottom: '0.3rem', display: 'inline-block' }}>{pais.codigo}</span>
                    <p style={{ fontWeight: 800, color: 'var(--primary-color)', fontSize: '1rem', fontFamily: 'Manrope, sans-serif' }}>
                      {formatearMonto(tp, pais.codigo)}
                    </p>
                    <p style={{ fontSize: '0.65rem', color: 'var(--text-low)' }}>{pais.codigo}/USD</p>
                  </div>
                </div>
              )
            })}
          </div>
        ) : (
          // Vista de tabla para desktop
          <div>
            {/* Header */}
            <div style={{
              display: 'grid',
              gridTemplateColumns: '2.5rem 1fr 1fr 1fr 1fr',
              gap: '1rem',
              padding: '1rem 1.5rem',
              background: 'rgba(16,185,129,0.08)',
              borderBottom: '1px solid var(--glass-border)',
            }}>
              {['', 'País', 'Moneda', 'Código ISO', labelColumna].map((h, i) => (
                <div key={i} style={{
                  fontSize: '0.7rem',
                  color: i === 4 ? 'var(--primary-color)' : 'var(--text-low)',
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
              const tp = getTasa(pais)
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
                    <img src={getFlagUrl(pais)} alt={pais.nombre} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  </div>
                  <div>
                    <p style={{ fontWeight: 700, color: 'white', fontSize: '0.95rem' }}>{pais.nombre}</p>
                  </div>
                  <div style={{ color: 'var(--text-low)', fontSize: '0.875rem' }}>{pais.moneda}</div>
                  <div>
                    <span className="badge badge-success" style={{ fontFamily: 'monospace' }}>{pais.codigo}</span>
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <p style={{ fontWeight: 800, color: 'var(--primary-color)', fontSize: '1.1rem', fontFamily: 'Manrope, sans-serif' }}>
                      {formatearMonto(tp, pais.codigo)}
                    </p>
                    <p style={{ fontSize: '0.7rem', color: 'var(--text-low)' }}>{pais.codigo}/USD</p>
                  </div>
                </div>
              )
            })}
          </div>
        )}

        {paisesFiltrados.length === 0 && (
          <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--text-low)' }}>
            No se encontraron países con "{busqueda}"
          </div>
        )}
      </div>

      <p style={{ textAlign: 'center', fontSize: '0.8rem', color: 'var(--text-low)', marginTop: '1.5rem' }}>
        {listaActiva === 'enviar'
          ? '📤 Tasa Enviar — Moneda local que recibe el destinatario por cada 1 USD enviado con GRUPO JK'
          : '📥 Tasa Recibir — Moneda local que debes entregar a JK para obtener 1 USD'}
      </p>
    </div>
  )
}

