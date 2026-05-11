import React, { useState } from 'react'
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

              if (isCajaDolar(destino) && !isCajaDolar(paisOrigen)) {
                valorFinal = 1 / tasaCruzada
              } 
              else if (tasaCruzada < 0.1 && !isCajaDolar(destino)) {
                valorFinal = tasaCruzada * 1000
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
          
          {/* Contactos */}
          <div style={{ background: 'rgba(255,255,255,0.03)', borderRadius: '1.2rem', padding: '1.2rem', border: '1px solid rgba(255,255,255,0.05)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '0.8rem' }}>
              <span style={{ fontSize: '0.8rem', fontWeight: 700, opacity: 0.6 }}>Contáctanos</span>
              <span style={{ fontSize: '1.2rem' }}>🟢</span>
            </div>
            
            <div style={{ marginBottom: '1rem' }}>
              <p style={{ fontSize: '0.7rem', color: 'rgba(255,255,255,0.5)', fontWeight: 700, textTransform: 'uppercase', marginBottom: '0.2rem' }}>Atención Kelvin</p>
              <ContactItem number="593961230380" label="+593 96 123 0380" />
            </div>

            <div>
              <p style={{ fontSize: '0.7rem', color: 'rgba(255,255,255,0.5)', fontWeight: 700, textTransform: 'uppercase', marginBottom: '0.2rem' }}>Atención Dario</p>
              <ContactItem number="593998053300" label="+593 99 805 3300" />
            </div>
          </div>

          {/* Horario */}
          <div style={{ background: 'rgba(255,255,255,0.03)', borderRadius: '1.2rem', padding: '1.2rem', border: '1px solid rgba(255,255,255,0.05)', textAlign: 'center' }}>
            <span style={{ fontSize: '1.2rem', display: 'block', marginBottom: '0.4rem' }}>🕒</span>
            <span style={{ fontSize: '0.8rem', fontWeight: 700, opacity: 0.6, display: 'block' }}>Horario</span>
            <p style={{ fontSize: '0.9rem', fontWeight: 800, margin: '0.2rem 0' }}>8:00AM - 8:00PM</p>
            <p style={{ fontSize: '0.7rem', opacity: 0.5, margin: 0 }}>Lunes a Sábado</p>
          </div>

          {/* Métodos de Pago - Dinámicos por País Origen */}
          <div style={{ background: 'rgba(255,255,255,0.03)', borderRadius: '1.2rem', padding: '1.2rem', border: '1px solid rgba(255,255,255,0.05)' }}>
            <div style={{ textAlign: 'center', marginBottom: '1.2rem' }}>
              <span style={{ fontSize: '1.2rem', display: 'block', marginBottom: '0.4rem' }}>💳</span>
              <span style={{ fontSize: '0.8rem', fontWeight: 700, opacity: 0.6 }}>Métodos de Pago</span>
            </div>
            
            <div style={{ 
              display: 'grid', 
              gridTemplateColumns: 'repeat(2, 1fr)', 
              gap: '0.6rem',
              alignItems: 'center'
            }}>
               {paisOrigen.id === 8 || paisOrigen.nombre.toUpperCase().includes('VENEZUELA') ? (
                 <>
                   <BankItem name="B. VENEZUELA" logo="https://upload.wikimedia.org/wikipedia/commons/thumb/a/a2/Banco_de_Venezuela_logo.svg/512px-Banco_de_Venezuela_logo.svg.png" />
                   <BankItem name="BANESCO" logo="https://upload.wikimedia.org/wikipedia/commons/thumb/4/4c/Banesco_Logo.svg/512px-Banesco_Logo.svg.png" />
                   <BankItem name="MERCANTIL" logo="https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/Mercantil_Banco_logo.svg/512px-Mercantil_Banco_logo.svg.png" />
                   <BankItem name="PROVINCIAL" logo="https://upload.wikimedia.org/wikipedia/commons/thumb/f/f2/BBVA_2019.svg/512px-BBVA_2019.svg.png" />
                   <BankItem name="BICENTENARIO" logo="https://www.bancobicentenario.com.ve/favicon.ico" />
                   <BankItem name="BNC" logo="https://www.bncenlinea.com/favicon.ico" />
                   <BankItem name="BINANCE" logo="https://upload.wikimedia.org/wikipedia/commons/thumb/e/e8/Binance_Logo.svg/512px-Binance_Logo.svg.png" />
                   <BankItem name="ZELLE" logo="https://img.icons8.com/color/96/zelle.png" />
                   <BankItem name="ZINLI" logo="https://www.google.com/s2/favicons?domain=zinli.com&sz=128" />
                   <BankItem name="USDT" logo="https://img.icons8.com/color/96/tether.png" />
                 </>
               ) : (
                 <div style={{ gridColumn: 'span 2', textAlign: 'center' }}>
                   <p style={{ fontSize: '0.7rem', opacity: 0.5, margin: 0 }}>Consulta bancos disponibles para {paisOrigen.nombre} vía WhatsApp</p>
                 </div>
               )}
            </div>
          </div>

          {/* Botón Acción */}
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

      {/* Marca de Agua Inferior Estilizada */}
      <div style={{ 
        marginTop: '3rem', 
        textAlign: 'center',
        opacity: 0.3
      }}>
        <p style={{ fontSize: '0.7rem', fontWeight: 800, letterSpacing: '0.3em', textTransform: 'uppercase' }}>
          JK CONVERSOR • SEGURIDAD Y CONFIANZA
        </p>
      </div>

    </div>
  )
}

function BankItem({ name, logo }) {
  const [imgError, setImgError] = useState(false);

  return (
    <div style={{ 
      display: 'flex', 
      alignItems: 'center', 
      gap: '0.6rem',
      background: 'rgba(255,255,255,0.06)',
      padding: '0.4rem 0.8rem',
      borderRadius: '0.8rem',
      border: '1px solid rgba(255,255,255,0.08)',
      height: '2.5rem'
    }}>
      <div style={{ 
        width: '1.4rem', 
        height: '1.4rem', 
        display: 'flex', 
        alignItems: 'center', 
        justifyContent: 'center', 
        overflow: 'hidden',
        background: 'rgba(255,255,255,0.9)',
        borderRadius: '0.2rem',
        padding: '2px'
      }}>
        {!imgError ? (
          <img 
            src={logo} 
            alt={name} 
            onError={() => setImgError(true)}
            style={{ maxWidth: '100%', maxHeight: '100%', objectFit: 'contain' }} 
          />
        ) : (
          <span style={{ fontSize: '0.8rem' }}>🏦</span>
        )}
      </div>
      <span style={{ 
        fontSize: '0.6rem', 
        fontWeight: 800, 
        color: 'rgba(255,255,255,0.9)',
        whiteSpace: 'nowrap',
        overflow: 'hidden',
        textOverflow: 'ellipsis',
        letterSpacing: '0.02em'
      }}>{name}</span>
    </div>
  )
}

function ContactItem({ number, label }) {
  const copyToClipboard = (e) => {
    e.stopPropagation();
    navigator.clipboard.writeText(number);
    alert('Número copiado: ' + number);
  };

  return (
    <div 
      onClick={() => window.open(`https://wa.me/${number}`, '_blank')}
      style={{ 
        display: 'flex', 
        alignItems: 'center', 
        justifyContent: 'space-between',
        cursor: 'pointer',
        background: 'rgba(16,185,129,0.05)',
        padding: '0.4rem 0.8rem',
        borderRadius: '0.8rem',
        border: '1px solid rgba(16,185,129,0.1)',
        transition: 'all 0.2s'
      }}
      onMouseOver={e => e.currentTarget.style.background = 'rgba(16,185,129,0.1)'}
      onMouseOut={e => e.currentTarget.style.background = 'rgba(16,185,129,0.05)'}
    >
      <span style={{ fontWeight: 800, fontSize: '1rem', color: '#10b981' }}>{label}</span>
      <button 
        onClick={copyToClipboard}
        style={{
          background: 'none',
          border: 'none',
          color: 'rgba(255,255,255,0.4)',
          cursor: 'pointer',
          padding: '4px',
          display: 'flex',
          alignItems: 'center'
        }}
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
          <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
        </svg>
      </button>
    </div>
  );
}
