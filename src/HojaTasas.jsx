import { getFlagUrl, obtenerTasasProcesadas, formatearMonto, isCajaDolar } from './constants'

export default function HojaTasas({ paisOrigen, paises, modo = 'detal', onBack }) {
  if (!paisOrigen) return null

  // Mostrar TODOS los países disponibles como destino (excepto el origen)
  const destinos = paises.filter(p => p.id !== paisOrigen.id)

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
      navigator.clipboard.writeText(url)
      alert('¡Enlace copiado al portapapeles!')
    }
  }

  return (
    <div className="premium-sheet" style={{ 
      padding: '1.5rem', 
      minHeight: '100vh', 
      color: 'white',
      position: 'relative',
      background: '#0a0f18',
      overflow: 'hidden'
    }}>
      
      {/* Marca de Agua (Logo) */}
      <div style={{
        position: 'absolute',
        top: '50%',
        left: '50%',
        transform: 'translate(-50%, -50%)',
        width: '80%',
        opacity: 0.04,
        zIndex: 0,
        pointerEvents: 'none'
      }}>
        <img src="./logo-jk-transparente.png" alt="Watermark" style={{ width: '100%', filter: 'grayscale(100%)' }} />
      </div>

      {/* Botón Volver (Solo visible en pantalla, no en captura idealmente) */}
      <button 
        onClick={onBack}
        className="no-print"
        style={{
          position: 'absolute',
          top: '1rem',
          left: '1rem',
          background: 'rgba(255,255,255,0.05)',
          border: '1px solid rgba(255,255,255,0.1)',
          color: 'white',
          padding: '0.4rem 0.8rem',
          borderRadius: '2rem',
          cursor: 'pointer',
          fontSize: '0.75rem',
          zIndex: 10
        }}
      >
        ← Volver
      </button>

      {/* Header Estilo Minimalista */}
      <div style={{ textAlign: 'center', marginBottom: '2.5rem', position: 'relative', zIndex: 1 }}>
        <h1 style={{ fontSize: '2.8rem', fontWeight: 900, marginBottom: '0.2rem', letterSpacing: '-0.04em' }}>
          Tasas de <span style={{ color: '#10b981' }}>Cambio</span>
        </h1>
        <p style={{ fontSize: '1rem', color: 'rgba(255,255,255,0.6)', fontWeight: 500 }}>
          Para envíos desde <span style={{ color: 'white', fontWeight: 700 }}>{paisOrigen.nombre} {paisOrigen.bandera}</span>
        </p>
      </div>

      <div style={{ 
        display: 'grid', 
        gridTemplateColumns: window.innerWidth > 800 ? '1fr 300px' : '1fr', 
        gap: '1.5rem',
        position: 'relative',
        zIndex: 1 
      }}>
        
        {/* Columna Izquierda: Listado de Tasas */}
        <div style={{ 
          background: 'rgba(255,255,255,0.02)', 
          borderRadius: '1.5rem',
          border: '1px solid rgba(255,255,255,0.05)',
          padding: '0.5rem',
          backdropFilter: 'blur(10px)'
        }}>
          <div style={{ padding: '1rem', borderBottom: '1px solid rgba(255,255,255,0.05)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <span style={{ color: '#10b981', fontSize: '1.2rem' }}>📈</span>
              <span style={{ fontSize: '0.7rem', fontWeight: 800, textTransform: 'uppercase', letterSpacing: '0.1em', opacity: 0.8 }}>Mejor tasa del mercado</span>
            </div>
            <span style={{ fontSize: '0.7rem', color: 'rgba(255,255,255,0.4)' }}>● +1000 clientes satisfechos</span>
          </div>
          
          <div style={{ padding: '0.5rem' }}>
            {destinos.map((destino) => {
              const { tasaDestinoDesdeDolares, tasaOrigenParaDolares } = obtenerTasasProcesadas(paisOrigen, destino, paises, modo)
              let tasaCruzada = (1 / tasaOrigenParaDolares) * tasaDestinoDesdeDolares
              let valorFinal = tasaCruzada
              let labelRelacion = `${destino.codigo} / ${paisOrigen.codigo}`
              let monedaFormato = destino.codigo

              if (isCajaDolar(destino) && !isCajaDolar(paisOrigen)) {
                valorFinal = 1 / tasaCruzada
                labelRelacion = `${paisOrigen.codigo} / ${destino.codigo}`
                monedaFormato = paisOrigen.codigo
              } 
              else if (tasaCruzada < 0.1 && !isCajaDolar(destino)) {
                valorFinal = tasaCruzada * 1000
                labelRelacion = `${destino.codigo} x 1.000 ${paisOrigen.codigo}`
              }

              return (
                <div key={destino.id} style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  padding: '0.8rem 1rem',
                  borderBottom: '1px solid rgba(255,255,255,0.03)',
                }}>
                  <div style={{ width: '2.2rem', height: '1.5rem', borderRadius: '0.3rem', overflow: 'hidden', flexShrink: 0, marginRight: '1rem' }}>
                    <img src={getFlagUrl(destino)} alt={destino.nombre} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                  </div>
                  <div style={{ flex: 1 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.4rem' }}>
                      <span style={{ fontWeight: 800, fontSize: '0.9rem', color: 'rgba(255,255,255,0.9)' }}>{destino.codigo}</span>
                      <span style={{ fontSize: '0.75rem', color: 'rgba(255,255,255,0.4)', fontWeight: 500 }}>{destino.moneda}</span>
                    </div>
                  </div>
                  <div style={{ textAlign: 'right', display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
                    <span style={{ color: '#10b981', fontWeight: 800 }}>{'>'}</span>
                    <span style={{ fontSize: '1.3rem', fontWeight: 900, color: '#10b981', fontFamily: 'monospace' }}>
                      {formatearMonto(valorFinal, '')}
                    </span>
                  </div>
                </div>
              )
            })}
          </div>

          {/* Logo Inferior Central */}
          <div style={{ textAlign: 'center', padding: '1.5rem' }}>
            <img src="./logo-jk-transparente.png" alt="JK Logo" style={{ width: '120px', opacity: 0.8 }} />
          </div>
        </div>

        {/* Columna Derecha: Sidebar */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
          
          {/* Contacto */}
          <div style={{ background: 'rgba(255,255,255,0.03)', borderRadius: '1.2rem', padding: '1.2rem', border: '1px solid rgba(255,255,255,0.05)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '0.5rem' }}>
              <span style={{ fontSize: '0.8rem', fontWeight: 700, opacity: 0.6 }}>Contáctanos</span>
              <span style={{ fontSize: '1.2rem' }}>🟢</span>
            </div>
            <p style={{ fontWeight: 800, fontSize: '1.2rem', color: '#10b981', margin: 0 }}>+57 323 394 7051</p>
            <div style={{ display: 'flex', alignItems: 'center', gap: '0.3rem', marginTop: '0.3rem' }}>
              <span style={{ color: '#10b981', fontSize: '0.8rem' }}>✔️</span>
              <span style={{ fontSize: '0.65rem', fontWeight: 600, opacity: 0.5 }}>Atención inmediata</span>
            </div>
          </div>

          {/* Horario */}
          <div style={{ background: 'rgba(255,255,255,0.03)', borderRadius: '1.2rem', padding: '1.2rem', border: '1px solid rgba(255,255,255,0.05)', textAlign: 'center' }}>
            <span style={{ fontSize: '1.2rem', display: 'block', marginBottom: '0.4rem' }}>🕒</span>
            <span style={{ fontSize: '0.8rem', fontWeight: 700, opacity: 0.6, display: 'block' }}>Horario</span>
            <p style={{ fontSize: '0.9rem', fontWeight: 800, margin: '0.2rem 0' }}>8:00AM - 8:00PM</p>
            <p style={{ fontSize: '0.7rem', opacity: 0.5, margin: 0 }}>Lunes a Sábado</p>
          </div>

          {/* Métodos de Pago */}
          <div style={{ background: 'rgba(255,255,255,0.03)', borderRadius: '1.2rem', padding: '1.2rem', border: '1px solid rgba(255,255,255,0.05)' }}>
            <div style={{ textAlign: 'center', marginBottom: '1rem' }}>
              <span style={{ fontSize: '1.2rem', display: 'block', marginBottom: '0.4rem' }}>💳</span>
              <span style={{ fontSize: '0.8rem', fontWeight: 700, opacity: 0.6 }}>Metodos de Pago</span>
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.8rem', alignItems: 'center' }}>
               <div style={{ fontSize: '0.75rem', fontWeight: 800, color: '#f3ba2f' }}>🔶 BINANCE</div>
               <div style={{ fontSize: '0.75rem', fontWeight: 800, color: '#6366f1' }}>💜 Zelle</div>
               <div style={{ fontSize: '0.75rem', fontWeight: 800, color: '#2563eb' }}>🔹 BCP</div>
               <div style={{ fontSize: '0.75rem', fontWeight: 800, color: '#d946ef' }}>💖 Zinli</div>
               <div style={{ fontSize: '0.75rem', fontWeight: 800, color: '#10b981' }}>🟢 USDT</div>
               <div style={{ fontSize: '0.75rem', fontWeight: 800, color: '#eab308' }}>🟡 Bancolombia</div>
               <div style={{ fontSize: '0.75rem', fontWeight: 800, color: '#ef4444' }}>🔴 Banesco</div>
               <div style={{ fontSize: '0.75rem', fontWeight: 800, color: '#3b82f6' }}>🌊 BBVA</div>
            </div>
          </div>

          {/* Botón Acción (No visible en captura ideally, pero útil para compartir) */}
          <button 
            onClick={handleShare}
            className="no-print"
            style={{
              background: '#10b981',
              border: 'none',
              padding: '1rem',
              borderRadius: '1rem',
              color: '#0a0f18',
              fontWeight: 900,
              cursor: 'pointer',
              fontSize: '0.9rem',
              marginTop: 'auto',
              boxShadow: '0 8px 20px rgba(16, 185, 129, 0.3)'
            }}
          >
            📤 COMPARTIR HOJA
          </button>
        </div>

      </div>

      {/* Footer Bar Estilo Unicambios */}
      <div style={{ 
        marginTop: '2.5rem', 
        background: 'linear-gradient(90deg, #10b981, #064e3b)', 
        padding: '0.8rem 1.5rem', 
        borderRadius: '0.5rem',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        position: 'relative',
        zIndex: 1
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <span style={{ fontSize: '1rem' }}>📞</span>
          <span style={{ fontSize: '0.8rem', fontWeight: 800 }}>+57 3233947051</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '0.3rem' }}>
             <span style={{ fontSize: '1rem' }}>📸</span>
             <span style={{ fontSize: '0.75rem', fontWeight: 800 }}>@grupojkconversor</span>
          </div>
          <span style={{ fontSize: '0.8rem' }}>✔️</span>
        </div>
      </div>

    </div>
  )
}
