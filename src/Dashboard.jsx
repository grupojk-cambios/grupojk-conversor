import { useState, useEffect } from 'react'
import { cargarPaises, calcularTasaEnvio, calcularTasaRecibo, formatearMonto } from './constants'
import './Dashboard.css'

export default function Dashboard({ onNavegar, modo = 'detal', profile, onSwitchMode }) {
  const [paises, setPaises] = useState([])
  const [monitorVzla, setMonitorVzla] = useState({
    bcv: null,
    paralelo: null,
    usdt: null,
    actualizado: '',
    loading: true
  })

  useEffect(() => {
    const todos = cargarPaises()
    setPaises(todos)

    // Consulta en vivo a la API de tasas de Venezuela
    const fetchMonitorVzla = async () => {
      try {
        const res = await fetch('https://ve.dolarapi.com/v1/dolares')
        if (!res.ok) throw new Error('Error al consultar tasas')
        const data = await res.json()
        
        const oficial = data.find(d => d.fuente === 'oficial')
        const paralelo = data.find(d => d.fuente === 'paralelo')
        
        const bcvVal = oficial?.promedio || 0
        const paraleloVal = paralelo?.promedio || 0
        const usdtVal = paraleloVal > 0 ? (paraleloVal * 1.008) : 0

        // 1. Fecha Valor BCV sin desfase de zona horaria
        let fechaValorBCV = 'Hoy'
        if (oficial?.fechaActualizacion) {
          const fechaParts = oficial.fechaActualizacion.split('T')[0].split('-')
          if (fechaParts.length === 3) {
            const meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic']
            const dia = parseInt(fechaParts[2], 10)
            const mes = meses[parseInt(fechaParts[1], 10) - 1]
            fechaValorBCV = `${dia} ${mes}`
          }
        }

        // 2. Corte Paralelo (9:00 AM o 1:00 PM)
        let corteParalelo = '1:00 PM'
        if (paralelo?.fechaActualizacion) {
          const pDate = new Date(paralelo.fechaActualizacion)
          const horaVE = pDate.getUTCHours() - 4
          corteParalelo = horaVE < 13 ? '9:00 AM' : '1:00 PM'
        }

        const actualizadoBadge = `Hoy · ${corteParalelo}`

        setMonitorVzla({
          bcv: bcvVal,
          paralelo: paraleloVal,
          usdt: usdtVal,
          fechaValorBCV,
          corteParalelo,
          actualizado: actualizadoBadge,
          loading: false
        })
      } catch (err) {
        console.error('Error cargando monitor Venezuela:', err)
        setMonitorVzla(prev => ({ ...prev, loading: false }))
      }
    }

    fetchMonitorVzla()
  }, [])

  const esMayor = modo === 'mayor'

  // Tasas de Cambios JK para Venezuela
  const paisVzla = paises.find(p => p.codigo === 'VES' || p.id === 10)
  const jkEnvio = paisVzla ? calcularTasaEnvio(paisVzla, modo) : 0
  const jkRecibo = paisVzla ? calcularTasaRecibo(paisVzla, modo) : 0

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

      {/* Monitor Venezuela (Referencias de Mercado) */}
      <div className="monitor-vzla-section">
        <div className="monitor-vzla-glow" />
        
        <div className="monitor-vzla-header">
          <div className="monitor-vzla-title">
            <span style={{ fontSize: '1.5rem' }}>🇻🇪</span>
            <div>
              <span style={{ display: 'block' }}>Monitor de Cambio Venezuela</span>
              <span style={{ fontSize: '0.75rem', color: 'var(--text-low)', fontWeight: 500 }}>Referencias del mercado en tiempo real</span>
            </div>
          </div>
          
          <div className="monitor-live-badge">
            <span className="monitor-live-dot" />
            <span>{monitorVzla.actualizado ? `Actualizado ${monitorVzla.actualizado}` : 'En Vivo'}</span>
          </div>
        </div>

        <div className="monitor-vzla-grid">
          {/* Tarjeta 1: Dólar BCV */}
          <div className="monitor-rate-card">
            <div>
              <div className="monitor-card-head">
                <div className="monitor-card-icon">🏛️</div>
                <div>
                  <div className="monitor-card-name">Dólar BCV</div>
                  <div className="monitor-card-sub">Tasa Oficial</div>
                </div>
              </div>
              <div className="monitor-card-rate">
                {monitorVzla.loading ? (
                  <span style={{ fontSize: '1.2rem', opacity: 0.5 }}>Cargando...</span>
                ) : (
                  <>Bs. {monitorVzla.bcv > 0 ? formatearMonto(monitorVzla.bcv, 'VES') : 'N/A'}</>
                )}
              </div>
              <div className="monitor-card-unit">x 1 USD Oficial</div>
            </div>
            <div className="monitor-card-footer">
              <span>🔹 Fecha Valor: {monitorVzla.fechaValorBCV || 'Hoy'}</span>
            </div>
          </div>

          {/* Tarjeta 2: Dólar Paralelo */}
          <div className="monitor-rate-card">
            <div>
              <div className="monitor-card-head">
                <div className="monitor-card-icon">📈</div>
                <div>
                  <div className="monitor-card-name">Dólar Paralelo</div>
                  <div className="monitor-card-sub">Promedio Mercado</div>
                </div>
              </div>
              <div className="monitor-card-rate" style={{ color: '#38bdf8' }}>
                {monitorVzla.loading ? (
                  <span style={{ fontSize: '1.2rem', opacity: 0.5 }}>Cargando...</span>
                ) : (
                  <>Bs. {monitorVzla.paralelo > 0 ? formatearMonto(monitorVzla.paralelo, 'VES') : 'N/A'}</>
                )}
              </div>
              <div className="monitor-card-unit">x 1 USD Libre</div>
            </div>
            <div className="monitor-card-footer">
              <span>📊 Corte: {monitorVzla.corteParalelo || '1:00 PM'}</span>
            </div>
          </div>

          {/* Tarjeta 3: USDT Binance */}
          <div className="monitor-rate-card">
            <div>
              <div className="monitor-card-head">
                <div className="monitor-card-icon" style={{ color: '#f59e0b' }}>🟡</div>
                <div>
                  <div className="monitor-card-name">USDT Binance</div>
                  <div className="monitor-card-sub">Mercado P2P Cripto</div>
                </div>
              </div>
              <div className="monitor-card-rate" style={{ color: '#fbbf24' }}>
                {monitorVzla.loading ? (
                  <span style={{ fontSize: '1.2rem', opacity: 0.5 }}>Cargando...</span>
                ) : (
                  <>Bs. {monitorVzla.usdt > 0 ? formatearMonto(monitorVzla.usdt, 'VES') : 'N/A'}</>
                )}
              </div>
              <div className="monitor-card-unit">x 1 USDT Digital</div>
            </div>
            <div className="monitor-card-footer">
              <span>⚡ En tiempo real (P2P)</span>
            </div>
          </div>
        </div>

        {/* Footer: Nuestra Tasa Cambios JK */}
        <div className="monitor-jk-banner">
          <div className="monitor-jk-rates">
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <span style={{ fontSize: '1.3rem' }}>🚛</span>
              <span style={{ fontWeight: 800, color: 'white', fontSize: '0.95rem' }}>Tasa Cambios JK:</span>
            </div>
            <div className="monitor-jk-rate-item">
              <span style={{ fontSize: '0.8rem', color: 'var(--text-low)', fontWeight: 600 }}>📤 Envío:</span>
              <span style={{ fontWeight: 800, color: 'var(--primary-color)', fontSize: '1.1rem', fontFamily: 'Manrope, sans-serif' }}>
                Bs. {jkEnvio > 0 ? formatearMonto(jkEnvio, 'VES') : 'N/A'}
              </span>
            </div>
            <div className="monitor-jk-rate-item">
              <span style={{ fontSize: '0.8rem', color: 'var(--text-low)', fontWeight: 600 }}>📥 Recibo:</span>
              <span style={{ fontWeight: 800, color: 'white', fontSize: '1.1rem', fontFamily: 'Manrope, sans-serif' }}>
                Bs. {jkRecibo > 0 ? formatearMonto(jkRecibo, 'VES') : 'N/A'}
              </span>
            </div>
          </div>

          <button 
            className="btn-primary" 
            onClick={() => onNavegar(esMayor ? 'mayor-cotizador' : 'cotizador')}
            style={{ padding: '0.6rem 1.4rem', fontSize: '0.85rem', borderRadius: '0.8rem' }}
          >
            💱 Cotizar Ahora
          </button>
        </div>
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
