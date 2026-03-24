import { useState, useEffect } from 'react'
import { cargarPaises, PAISES_DESTACADOS_IDS, calcularTasaPublica, formatearMonto } from './constants'

export default function Dashboard({ onNavegar }) {
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

  const tasaDisplay = (pais) => {
    const tp = calcularTasaPublica(pais)
    if (pais.codigo === 'USD') return '1.00'
    return formatearMonto(tp, pais.codigo)
  }

  return (
    <div style={{ maxWidth: '1200px', margin: '0 auto', padding: '2rem 1.5rem' }}>

      {/* Hero */}
      <div style={{
        textAlign: 'center',
        padding: '4rem 2rem 3rem',
        background: 'var(--glass-bg)',
        border: '1px solid var(--glass-border)',
        borderRadius: '2rem',
        marginBottom: '3rem',
        backdropFilter: 'blur(24px)',
        position: 'relative',
        overflow: 'hidden',
      }}>
        <div style={{
          position: 'absolute', inset: 0,
          background: 'radial-gradient(circle at 50% 0%, rgba(16,185,129,0.12) 0%, transparent 70%)',
          pointerEvents: 'none',
        }} />
        <div style={{ 
          width: '7.5rem', height: '7.5rem', margin: '0 auto 1.5rem', 
          background: 'white', borderRadius: '1.5rem', padding: '0.5rem', 
          boxShadow: '0 15px 40px rgba(0,0,0,0.5), 0 0 20px rgba(16,185,129,0.2)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          position: 'relative', zIndex: 1
        }}>
          <img src="/logo_jk_final.png" alt="Logo JK" style={{ width: '100%', height: '100%', objectFit: 'contain' }} />
        </div>
        <h1 style={{ fontSize: 'clamp(2rem, 5vw, 3.5rem)', marginBottom: '1rem', color: 'white' }}>
          GRUPO JK
        </h1>
        <p style={{ fontSize: '1.2rem', color: 'var(--text-low)', marginBottom: '0.5rem' }}>
          Cambio de Divisas — Tasas en Tiempo Real
        </p>
        <p style={{ color: 'var(--primary-color)', fontWeight: 600, marginBottom: '2.5rem' }}>
          ✅ Transferencias seguras · ⚡ 15-30 minutos · 💲 Sin comisión oculta
        </p>
        <div style={{ display: 'flex', gap: '1rem', justifyContent: 'center', flexWrap: 'wrap' }}>
          <button className="btn-primary" style={{ fontSize: '1.1rem', padding: '1rem 2.5rem' }}
            onClick={() => onNavegar('cotizador')}>
            💱 Hacer una Cotización
          </button>
          <button onClick={() => onNavegar('tasas')}
            style={{
              background: 'transparent',
              border: '1px solid var(--primary-color)',
              borderRadius: '2rem',
              padding: '1rem 2.5rem',
              color: 'var(--primary-color)',
              fontWeight: 700,
              cursor: 'pointer',
              fontSize: '1.1rem',
              transition: 'all 0.3s',
            }}
            onMouseEnter={e => e.target.style.background = 'rgba(16,185,129,0.1)'}
            onMouseLeave={e => e.target.style.background = 'transparent'}
          >
            📋 Ver Todas las Tasas
          </button>
        </div>
      </div>

      {/* Tasas Destacadas */}
      <div style={{ marginBottom: '2rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h2 style={{ fontSize: '1.8rem', marginBottom: '0.3rem' }}>Tasas del Día</h2>
          <p style={{ color: 'var(--text-low)', fontSize: '0.95rem' }}>
            1 USD equivale a — Actualizado por GRUPO JK
          </p>
        </div>
        <button onClick={() => onNavegar('tasas')}
          style={{ color: 'var(--primary-color)', background: 'none', border: 'none', cursor: 'pointer', fontWeight: 600, fontSize: '0.95rem' }}>
          Ver todas →
        </button>
      </div>

      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))',
        gap: '1.2rem',
        marginBottom: '3rem',
      }}>
        {destacados.map(pais => (
          <div key={pais.id}
            className="glass card"
            style={{ padding: '1.5rem', cursor: 'pointer', textAlign: 'center' }}
            onClick={() => onNavegar('cotizador')}
          >
            <div style={{ width: '4rem', height: '2.5rem', margin: '0 auto 1.2rem', overflow: 'hidden', borderRadius: '0.5rem', boxShadow: '0 4px 12px rgba(0,0,0,0.2)' }}>
              <img 
                src={`https://flagcdn.com/w80/${(pais.iso2 || pais.codigo.substring(0,2)).toLowerCase()}.png`}
                alt={pais.nombre}
                style={{ width: '100%', height: '100%', objectFit: 'cover' }}
              />
            </div>
            <p style={{ fontWeight: 700, color: 'white', fontSize: '1rem', marginBottom: '0.2rem' }}>
              {pais.nombre}
            </p>
            <p style={{ fontSize: '0.75rem', color: 'var(--text-low)', marginBottom: '0.8rem' }}>
              {pais.moneda}
            </p>
            <p style={{
              fontSize: '1.4rem', fontWeight: 800,
              color: 'var(--primary-color)',
              fontFamily: 'Manrope, sans-serif',
            }}>
              {tasaDisplay(pais)}
            </p>
            <p style={{ fontSize: '0.7rem', color: 'var(--text-low)', marginTop: '0.2rem' }}>
              {pais.codigo}
            </p>
          </div>
        ))}
      </div>

      {/* Info inferior */}
      <div style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))',
        gap: '1.5rem',
      }}>
        {[
          { icon: '⚡', titulo: 'Transferencia Rápida', desc: 'Tiempo estimado: 15 - 30 minutos una vez confirmado el pago' },
          { icon: '🔒', titulo: 'Operaciones Seguras', desc: 'Más de 5 años de experiencia en transferencias internacionales' },
          { icon: '💯', titulo: 'Sin Comisión Oculta', desc: 'La tasa que ves es exactamente lo que recibes, sin sorpresas' },
        ].map(item => (
          <div key={item.titulo} className="glass" style={{ padding: '1.5rem', display: 'flex', gap: '1rem', alignItems: 'flex-start' }}>
            <div style={{
              width: '2.5rem', height: '2.5rem', minWidth: '2.5rem',
              background: 'rgba(16,185,129,0.1)',
              border: '1px solid rgba(16,185,129,0.3)',
              borderRadius: '0.75rem',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: '1.2rem',
            }}>{item.icon}</div>
            <div>
              <p style={{ fontWeight: 700, color: 'white', marginBottom: '0.3rem' }}>{item.titulo}</p>
              <p style={{ fontSize: '0.85rem', color: 'var(--text-low)', lineHeight: 1.5 }}>{item.desc}</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
