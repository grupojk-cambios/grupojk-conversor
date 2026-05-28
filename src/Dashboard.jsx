import { useState, useEffect } from 'react'
import { cargarPaises, PAISES_DESTACADOS_IDS, calcularTasaPublica, formatearMonto, getFlagUrl } from './constants'
import './Dashboard.css'

export default function Dashboard({ onNavegar, modo = 'detal' }) {
  const [paises, setPaises] = useState([])
  const [destacados, setDestacados] = useState([])

  useEffect(() => {
    const todos = cargarPaises()
    setPaises(todos)
    const dest = PAISES_DESTACADOS_IDS
      .map(id => todos.find(p => p.id === id))
      .filter(Boolean)
    setDestacados(dest)
  }, [])

  const esMayor = modo === 'mayor'

  const tasaDisplay = (pais) => {
    const tp = calcularTasaPublica(pais, modo)
    if (pais.codigo === 'USD') return '1.00'
    return formatearMonto(tp, pais.codigo)
  }

  return (
    <div className="dashboard-container">

      {/* Hero */}
      <div className="dashboard-hero">
        <div className="dashboard-hero-glow" />
        <div style={{ 
          width: '7.5rem', height: '7.5rem', margin: '0 auto 1.5rem', 
          borderRadius: '1.5rem', padding: '0.1rem', 
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          position: 'relative', zIndex: 1
        }}>
          <img src="./logo-jk-transparente.png" alt="Logo JK" style={{ width: '150%', height: '150%', objectFit: 'contain' }} />
        </div>
        <h1 style={{ fontSize: 'clamp(2rem, 5vw, 3.5rem)', marginBottom: '1rem', color: 'white', position: 'relative', zIndex: 1 }}>
          {esMayor ? 'Grupo JK Mayor' : 'CAMBIOS JK'}
        </h1>
        <p style={{ fontSize: '1.2rem', color: 'var(--text-low)', marginBottom: '0.5rem', position: 'relative', zIndex: 1 }}>
          Cambio de Divisas — Tasas en Tiempo Real
        </p>
        <p style={{ color: 'var(--primary-color)', fontWeight: 600, marginBottom: '2.5rem', position: 'relative', zIndex: 1, letterSpacing: '0.02em' }}>
          ✅ Transferencias seguras <span style={{opacity: 0.5}}>·</span> ⚡ 15-30 minutos <span style={{opacity: 0.5}}>·</span> 💲 Sin comisión oculta
        </p>
        <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center', flexWrap: 'wrap', position: 'relative', zIndex: 1 }}>
          <button className="btn-primary" style={{ fontSize: '1.1rem', padding: '1rem 2.5rem', boxShadow: '0 8px 25px rgba(16,185,129,0.3)' }}
            onClick={() => onNavegar(esMayor ? 'mayor-cotizador' : 'cotizador')}>
            💱 Hacer una Cotización
          </button>
          <button className="btn-premium-outline" onClick={() => onNavegar(esMayor ? 'mayor-tasas' : 'tasas')}>
            📋 Ver Todas las Tasas
          </button>
        </div>
      </div>

      {/* Tasas Destacadas */}
      <div style={{ marginBottom: '2rem', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
        <div>
          <h2 style={{ fontSize: '1.8rem', marginBottom: '0.3rem', color: 'white', letterSpacing: '-0.02em' }}>Tasas del Día</h2>
          <p style={{ color: 'var(--text-low)', fontSize: '0.95rem' }}>
            1 USD equivale a — Actualizado por <span style={{color: 'white', fontWeight: 600}}>{esMayor ? 'Grupo JK Mayor' : 'CAMBIOS JK'}</span>
          </p>
        </div>
        <button onClick={() => onNavegar(esMayor ? 'mayor-tasas' : 'tasas')}
          style={{ color: 'var(--primary-color)', background: 'none', border: 'none', cursor: 'pointer', fontWeight: 600, fontSize: '0.95rem', paddingBottom: '0.2rem' }}>
          Ver todas →
        </button>
      </div>

      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))',
        gap: '1.2rem',
        marginBottom: '4rem',
      }}>
        {destacados.map(pais => (
          <div key={pais.id}
            className="dashboard-card"
            onClick={() => onNavegar(esMayor ? 'mayor-cotizador' : 'cotizador')}
          >
            <div style={{ width: '4.5rem', height: '3rem', margin: '0 auto 1.2rem', overflow: 'hidden', borderRadius: '0.6rem', boxShadow: '0 4px 15px rgba(0,0,0,0.5)' }}>
              <img 
                src={getFlagUrl(pais)}
                alt={pais.nombre}
                style={{ width: '100%', height: '100%', objectFit: 'cover' }}
              />
            </div>
            <p style={{ fontWeight: 700, color: 'white', fontSize: '1.05rem', marginBottom: '0.2rem', letterSpacing: '0.02em' }}>
              {pais.nombre}
            </p>
            <p style={{ fontSize: '0.8rem', color: 'var(--text-low)', marginBottom: '1rem', textTransform: 'uppercase', letterSpacing: '0.05em' }}>
              {pais.moneda}
            </p>
            <p style={{
              fontSize: '1.6rem', fontWeight: 800,
              color: 'var(--primary-color)',
              fontFamily: 'Manrope, sans-serif',
              textShadow: '0 2px 10px rgba(16,185,129,0.2)'
            }}>
              {tasaDisplay(pais)}
            </p>
            <p style={{ fontSize: '0.75rem', color: 'rgba(255,255,255,0.4)', marginTop: '0.4rem', fontWeight: 600 }}>
              {pais.codigo}
            </p>
          </div>
        ))}
      </div>

      {/* Info inferior */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
        gap: '1.5rem',
      }}>
        {[
          { icon: '⚡', titulo: 'Transferencia Rápida', desc: 'Tiempo estimado: 15 - 30 minutos una vez confirmado el pago' },
          { icon: '🔒', titulo: 'Operaciones Seguras', desc: 'Más de 5 años de experiencia en transferencias internacionales' },
          { icon: '💯', titulo: 'Sin Comisión Oculta', desc: 'La tasa que ves es exactamente lo que recibes, sin sorpresas' },
        ].map(item => (
          <div key={item.titulo} className="dashboard-feature">
            <div style={{
              width: '3rem', height: '3rem', minWidth: '3rem',
              background: 'linear-gradient(135deg, rgba(16,185,129,0.15) 0%, rgba(16,185,129,0.05) 100%)',
              border: '1px solid rgba(16,185,129,0.3)',
              borderRadius: '0.8rem',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: '1.4rem',
              boxShadow: 'inset 0 2px 5px rgba(255,255,255,0.1)'
            }}>{item.icon}</div>
            <div>
              <p style={{ fontWeight: 700, color: 'white', marginBottom: '0.4rem', fontSize: '1.05rem' }}>{item.titulo}</p>
              <p style={{ fontSize: '0.9rem', color: 'var(--text-low)', lineHeight: 1.6 }}>{item.desc}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
