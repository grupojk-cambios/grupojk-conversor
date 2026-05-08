import { getFlagUrl, obtenerTasasProcesadas, formatearMonto } from './constants'

export default function HojaTasas({ paisOrigen, paises, modo = 'detal', onBack }) {
  if (!paisOrigen) return null

  // Destinos destacados para la hoja (puedes ajustar esta lista)
  const destinos = paises.filter(p => 
    p.id !== paisOrigen.id && 
    ['VE', 'CO', 'PE', 'CL', 'AR', 'US', 'USDT'].includes(p.iso2?.toUpperCase())
  )

  const handleShare = async () => {
    const url = window.location.href
    if (navigator.share) {
      try {
        await navigator.share({
          title: `Tasas desde ${paisOrigen.nombre} - JK Conversor`,
          text: `Mira las tasas de cambio actualizadas desde ${paisOrigen.nombre} en JK Conversor.`,
          url: url
        })
      } catch (err) {
        console.log('Error sharing:', err)
      }
    } else {
      // Fallback: copiar al portapapeles
      navigator.clipboard.writeText(url)
      alert('¡Enlace copiado al portapapeles!')
    }
  }

  return (
    <div className="premium-sheet" style={{ padding: '2rem', minHeight: '80vh', color: 'white' }}>
      
      {/* Botón Volver */}
      <button 
        onClick={onBack}
        style={{
          position: 'absolute',
          top: '1.5rem',
          left: '1.5rem',
          background: 'rgba(255,255,255,0.1)',
          border: 'none',
          color: 'white',
          padding: '0.5rem 1rem',
          borderRadius: '2rem',
          cursor: 'pointer',
          fontSize: '0.8rem',
          fontWeight: 600,
          zIndex: 10
        }}
      >
        ← Volver
      </button>

      {/* Header */}
      <div style={{ textAlign: 'center', marginBottom: '3rem', marginTop: '2rem' }}>
        <h1 style={{ fontSize: '2.5rem', fontWeight: 800, marginBottom: '0.5rem', letterSpacing: '-0.02em' }}>
          Tasas de <span style={{ color: 'var(--primary-color)' }}>Cambio</span>
        </h1>
        <p style={{ fontSize: '1.1rem', color: 'var(--text-low)', fontWeight: 500 }}>
          Para envíos desde <span style={{ color: 'white', fontWeight: 700 }}>{paisOrigen.nombre} {paisOrigen.bandera}</span>
        </p>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: window.innerWidth > 900 ? '1fr 320px' : '1fr', gap: '2rem' }}>
        
        {/* Columna Izquierda: Listado de Tasas */}
        <div className="glass-card" style={{ padding: '0.5rem' }}>
          <div style={{ padding: '1.2rem', borderBottom: '1px solid rgba(255,255,255,0.05)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--primary-color)', textTransform: 'uppercase', letterSpacing: '0.1em' }}>
              Destinos Principales
            </span>
            <span style={{ fontSize: '0.75rem', color: 'var(--text-low)' }}>
              Actualizado hoy
            </span>
          </div>
          
          {destinos.map((destino) => {
            const { tasaDestinoDesdeDolares, tasaOrigenParaDolares } = obtenerTasasProcesadas(paisOrigen, destino, paises, modo)
            // Tasa cruzada: 1 unidad de Origen -> X unidades de Destino
            const tasaCruzada = (1 / tasaOrigenParaDolares) * tasaDestinoDesdeDolares

            return (
              <div key={destino.id} className="rate-row-premium">
                <div style={{ width: '3rem', height: '2rem', borderRadius: '0.4rem', overflow: 'hidden', flexShrink: 0, boxShadow: '0 4px 10px rgba(0,0,0,0.3)' }}>
                  <img src={getFlagUrl(destino)} alt={destino.nombre} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                </div>
                <div style={{ flex: 1 }}>
                  <p style={{ fontWeight: 700, fontSize: '1rem', color: 'white' }}>{destino.nombre}</p>
                  <p style={{ fontSize: '0.75rem', color: 'var(--text-low)' }}>{destino.moneda}</p>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <span className="rate-value-premium">
                    {formatearMonto(tasaCruzada, destino.codigo)}
                  </span>
                  <p style={{ fontSize: '0.65rem', color: 'var(--text-low)', marginTop: '2px' }}>
                    {destino.codigo} / {paisOrigen.codigo}
                  </p>
                </div>
              </div>
            )
          })}
        </div>

        {/* Columna Derecha: Sidebar */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>
          
          {/* Contacto */}
          <div className="glass-card" style={{ padding: '1.5rem' }}>
            <span className="sidebar-label">Contáctanos</span>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.8rem', marginBottom: '1rem' }}>
              <div style={{ background: '#10b981', width: '40px', height: '40px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifySelf: 'center', justifyContent: 'center', fontSize: '1.2rem' }}>💬</div>
              <div>
                <p style={{ fontWeight: 700, fontSize: '1rem' }}>+57 323 394 7051</p>
                <p style={{ fontSize: '0.7rem', color: '#10b981', fontWeight: 600 }}>Atención inmediata</p>
              </div>
            </div>
            
            <span className="sidebar-label" style={{ marginTop: '1.5rem' }}>Horario</span>
            <p style={{ fontSize: '0.9rem', fontWeight: 500 }}>Lunes a Sábado</p>
            <p style={{ fontSize: '0.8rem', color: 'var(--text-low)' }}>8:00 AM - 8:00 PM</p>
          </div>

          {/* Métodos de Pago */}
          <div className="glass-card" style={{ padding: '1.5rem' }}>
            <span className="sidebar-label">Métodos de Pago</span>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '1rem', alignItems: 'center', marginTop: '0.5rem' }}>
              {/* Estos son placeholders de logos, en una app real usarías imágenes */}
              <div style={{ textAlign: 'center', fontSize: '0.6rem', opacity: 0.8 }}>Zelle</div>
              <div style={{ textAlign: 'center', fontSize: '0.6rem', opacity: 0.8 }}>Binance</div>
              <div style={{ textAlign: 'center', fontSize: '0.6rem', opacity: 0.8 }}>Banesco</div>
              <div style={{ textAlign: 'center', fontSize: '0.6rem', opacity: 0.8 }}>Zinli</div>
              <div style={{ textAlign: 'center', fontSize: '0.6rem', opacity: 0.8 }}>BCP</div>
              <div style={{ textAlign: 'center', fontSize: '0.6rem', opacity: 0.8 }}>Bancolombia</div>
            </div>
          </div>

          {/* Botón Acción Compartir */}
          <button 
            onClick={handleShare}
            style={{
              background: 'var(--premium-gradient)',
              border: 'none',
              padding: '1.2rem',
              borderRadius: '1.25rem',
              color: 'var(--bg-color)',
              fontWeight: 800,
              cursor: 'pointer',
              fontSize: '1rem',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '0.8rem',
              boxShadow: '0 10px 25px rgba(16, 185, 129, 0.4)',
              transition: 'transform 0.2s'
            }}
            onMouseDown={e => e.currentTarget.style.transform = 'scale(0.98)'}
            onMouseUp={e => e.currentTarget.style.transform = 'scale(1)'}
          >
            📤 COMPARTIR HOJA
          </button>
        </div>

      </div>

      {/* Footer */}
      <div style={{ marginTop: '4rem', textAlign: 'center', padding: '1rem', borderTop: '1px solid rgba(255,255,255,0.05)' }}>
        <p style={{ fontSize: '0.8rem', color: 'var(--text-low)', letterSpacing: '0.05em' }}>
          UN CAMBIO SEGURO Y PROFESIONAL · <span style={{ color: 'white', fontWeight: 600 }}>@GRUPOJKCONVERSOR</span>
        </p>
      </div>

    </div>
  )
}
