import React, { useState, useEffect, useRef } from 'react'
import html2canvas from 'html2canvas'
import { cargarPaises, obtenerTasasProcesadas, getFlagUrl, formatearMonto } from './constants'
import './GeneradorEstados.css'

export default function GeneradorEstados() {
  const [todosPaises, setTodosPaises] = useState([])
  const [paisOrigen, setPaisOrigen] = useState(null)
  const [chunks, setChunks] = useState([])
  const cardRefs = useRef([])

  useEffect(() => {
    // Solo países con tasa > 0
    const paises = cargarPaises().filter(p => p.tasaProveedor > 0 || p.tasaProveedorEnvio > 0 || p.id === 9)
    setTodosPaises(paises)
  }, [])

  useEffect(() => {
    if (paisOrigen) {
      // Filtrar que no sea el Origen y que tenga tasa
      const paisesDestino = todosPaises.filter(p => p.id !== paisOrigen.id)

      // Calcular la tasa enviar para cada país desde el Origen
      const paisesConTasa = paisesDestino.map(pais => {
        const { tasaOrigenParaDolares, tasaDestinoDesdeDolares } = obtenerTasasProcesadas(paisOrigen, pais, todosPaises, 'detal')
        const tasaFinal = (1 / tasaOrigenParaDolares) * tasaDestinoDesdeDolares
        return {
          ...pais,
          tasaCalculada: tasaFinal
        }
      })

      // Agrupar en chunks de 10
      const size = 10
      const newChunks = []
      for (let i = 0; i < paisesConTasa.length; i += size) {
        newChunks.push(paisesConTasa.slice(i, i + size))
      }
      setChunks(newChunks)
    }
  }, [paisOrigen, todosPaises])

  const descargarImagen = async (index) => {
    const element = cardRefs.current[index]
    if (!element) return

    try {
      const canvas = await html2canvas(element, {
        scale: 2, // Alta calidad
        useCORS: true,
        backgroundColor: '#020813' // Color premium oscuro
      })
      
      const image = canvas.toDataURL('image/png')
      const link = document.createElement('a')
      link.href = image
      link.download = `JK_Estados_${paisOrigen.codigo}_Parte_${index + 1}.png`
      link.click()
    } catch (error) {
      console.error('Error al generar la imagen:', error)
      alert('Hubo un error al descargar la imagen.')
    }
  }

  // VISTA 1: SELECCIONAR PAIS DE ORIGEN
  if (!paisOrigen) {
    return (
      <div style={{ color: 'white' }}>
        <div style={{ textAlign: 'center', marginBottom: '2rem' }}>
          <h2 style={{ fontSize: '2rem', marginBottom: '0.5rem', color: 'var(--primary-color)' }}>
            📍 Selecciona el País Origen
          </h2>
          <p style={{ color: 'var(--text-low)' }}>
            Elige qué país estará en el centro del árbol como moneda base.
          </p>
        </div>

        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))',
          gap: '1rem',
          maxWidth: '900px',
          margin: '0 auto'
        }}>
          {todosPaises.map(pais => (
            <button
              key={pais.id}
              onClick={() => setPaisOrigen(pais)}
              style={{
                background: 'rgba(255,255,255,0.03)',
                border: '1px solid rgba(255,255,255,0.1)',
                borderRadius: '1rem',
                padding: '1rem',
                cursor: 'pointer',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: '0.5rem',
                transition: 'all 0.3s ease',
                color: 'white'
              }}
              onMouseEnter={e => {
                e.currentTarget.style.background = 'rgba(0,198,255,0.1)'
                e.currentTarget.style.borderColor = 'var(--primary-color)'
              }}
              onMouseLeave={e => {
                e.currentTarget.style.background = 'rgba(255,255,255,0.03)'
                e.currentTarget.style.borderColor = 'rgba(255,255,255,0.1)'
              }}
            >
              <img src={getFlagUrl(pais)} alt={pais.nombre} style={{ width: '2.5rem', height: '2.5rem', borderRadius: '50%', objectFit: 'cover' }} />
              <span style={{ fontWeight: 600, fontSize: '0.9rem' }}>{pais.nombre}</span>
              <span style={{ fontSize: '0.7rem', color: 'var(--text-low)' }}>{pais.codigo}</span>
            </button>
          ))}
        </div>
      </div>
    )
  }

  // VISTA 2: GENERADOR DE ESTADOS (ÁRBOL MINIMALISTA)
  return (
    <div style={{ color: 'white' }}>
      
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2rem', maxWidth: '800px', margin: '0 auto 2rem auto' }}>
        <button 
          onClick={() => setPaisOrigen(null)}
          style={{ background: 'none', border: '1px solid rgba(255,255,255,0.2)', color: 'white', padding: '0.5rem 1rem', borderRadius: '0.5rem', cursor: 'pointer' }}
        >
          ← Cambiar Origen
        </button>
        <div style={{ textAlign: 'right' }}>
          <span style={{ color: 'var(--text-low)', fontSize: '0.9rem' }}>Base Actual:</span>
          <div style={{ fontWeight: 'bold', color: 'var(--primary-color)' }}>{paisOrigen.nombre} ({paisOrigen.codigo})</div>
        </div>
      </div>

      <div className="generador-estados-container">
        {chunks.map((chunk, index) => {
          // Calculamos dinámicamente las posiciones Y para el SVG basándonos en la cantidad de elementos en este chunk
          const numItems = chunk.length;
          
          return (
          <div key={index} className="estado-card-wrapper">
            {/* Tarjeta a exportar */}
            <div 
              className="estado-card premium-tree" 
              ref={el => cardRefs.current[index] = el}
            >
              {/* Marca de Agua (Fondo muy visible) */}
              <div className="watermark-container">
                <img 
                  src="./logo-jk-transparente.png" 
                  alt="Watermark" 
                  className="estado-watermark" 
                  crossOrigin="anonymous"
                />
              </div>

              {/* Branding Header */}
              <div className="estado-header-minimal">
                <img 
                  src="./logo-jk-transparente.png" 
                  alt="Logo JK" 
                  className="header-logo" 
                  crossOrigin="anonymous"
                />
                <div className="header-text">
                  <h2 className="estado-title-minimal">GRUPO JK</h2>
                  <p className="estado-subtitle-minimal">TASAS DE HOY DESDE {paisOrigen.codigo}</p>
                </div>
              </div>

              {/* ÁRBOL LAYOUT */}
              <div className="tree-layout">
                {/* IZQUIERDA: ORIGEN */}
                <div className="tree-left">
                  <div className="tree-origin-box">
                    <span className="origin-name">{paisOrigen.nombre}</span>
                    <img 
                      src={getFlagUrl(paisOrigen)} 
                      alt={paisOrigen.nombre} 
                      className="origin-flag"
                      crossOrigin="anonymous" 
                    />
                    <span className="origin-currency">1 {paisOrigen.codigo}</span>
                  </div>
                </div>

                {/* CENTRO: LÍNEAS SVG */}
                <div className="tree-svg-container">
                  <svg preserveAspectRatio="none" viewBox="0 0 100 100" className="tree-svg">
                    {chunk.map((_, i) => {
                      // Calcular posición Y destino en porcentaje (100% dividido por numItems, centrado en cada bloque)
                      const step = 100 / numItems;
                      const yDest = (i * step) + (step / 2);
                      return (
                        <path 
                          key={i}
                          d={`M 0,50 C 50,50 50,${yDest} 100,${yDest}`} 
                          className="tree-path"
                        />
                      )
                    })}
                  </svg>
                </div>

                {/* DERECHA: DESTINOS */}
                <div className="tree-right">
                  {chunk.map(pais => (
                    <div key={pais.id} className="tree-dest-row">
                      <img 
                        src={getFlagUrl(pais)} 
                        alt={pais.nombre} 
                        className="dest-flag"
                        crossOrigin="anonymous" 
                      />
                      <div className="dest-info">
                        <div className="dest-rate">{formatearMonto(pais.tasaCalculada)}</div>
                        <div className="dest-name">{pais.codigo}</div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* FOOTER */}
              <div className="estado-footer-minimal">
                Tasas referenciales sujetas a cambio • Grupo JK
              </div>
            </div>

            {/* Botón Descargar */}
            <button 
              onClick={() => descargarImagen(index)}
              className="btn-primary"
              style={{ padding: '1rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.5rem', fontWeight: 'bold' }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                <polyline points="7 10 12 15 17 10"></polyline>
                <line x1="12" y1="15" x2="12" y2="3"></line>
              </svg>
              Descargar Parte {index + 1}
            </button>
          </div>
        )})}
      </div>
    </div>
  )
}
