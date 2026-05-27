import React, { useState, useEffect, useRef } from 'react'
import html2canvas from 'html2canvas'
import { cargarPaises, obtenerTasasProcesadas, getFlagUrl, formatearMonto } from './constants'
import './GeneradorEstados.css'

export default function GeneradorEstados() {
  const [chunks, setChunks] = useState([])
  const [baseUSD, setBaseUSD] = useState(null)
  const cardRefs = useRef([])

  useEffect(() => {
    const todosPaises = cargarPaises()
    // Base Ecuador (id=9)
    const ecuador = todosPaises.find(p => p.id === 9)
    setBaseUSD(ecuador)

    if (ecuador) {
      // Filtrar que no sea Ecuador y que tenga tasa configurada
      const paisesDestino = todosPaises.filter(p => p.id !== 9 && p.tasaProveedor > 0)

      // Calcular la tasa enviar para cada país desde USD
      const paisesConTasa = paisesDestino.map(pais => {
        const { tasaOrigenParaDolares, tasaDestinoDesdeDolares } = obtenerTasasProcesadas(ecuador, pais, todosPaises, 'detal')
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
  }, [])

  const descargarImagen = async (index) => {
    const element = cardRefs.current[index]
    if (!element) return

    try {
      const canvas = await html2canvas(element, {
        scale: 2, // Alta calidad
        useCORS: true,
        backgroundColor: '#020813'
      })
      
      const image = canvas.toDataURL('image/png')
      const link = document.createElement('a')
      link.href = image
      link.download = `JK_Estados_Parte_${index + 1}.png`
      link.click()
    } catch (error) {
      console.error('Error al generar la imagen:', error)
      alert('Hubo un error al descargar la imagen.')
    }
  }

  if (!baseUSD) return <div style={{ color: 'white', textAlign: 'center' }}>Cargando datos...</div>

  return (
    <div style={{ color: 'white' }}>
      <p style={{ textAlign: 'center', color: 'var(--text-low)', marginBottom: '2rem' }}>
        Genera imágenes optimizadas para tus estados de WhatsApp. Los países se dividen en grupos de 10 automáticamente.
      </p>
      
      <div className="generador-estados-container">
        {chunks.map((chunk, index) => (
          <div key={index} className="estado-card-wrapper">
            {/* Tarjeta a exportar */}
            <div 
              className="estado-card" 
              ref={el => cardRefs.current[index] = el}
            >
              {/* Marca de Agua */}
              <img 
                src="./logo-jk-transparente.png" 
                alt="Watermark" 
                className="estado-watermark" 
                crossOrigin="anonymous"
              />

              <div className="estado-content">
                <div className="estado-header">
                  <h2 className="estado-title">GRUPO JK</h2>
                  <p className="estado-subtitle">TASAS DE HOY DESDE USD</p>
                </div>

                <div className="estado-list">
                  {chunk.map(pais => (
                    <div key={pais.id} className="estado-row">
                      <div className="estado-country-info">
                        <img 
                          src={getFlagUrl(pais.codigo)} 
                          alt={pais.nombre} 
                          className="estado-flag"
                          crossOrigin="anonymous" 
                        />
                        <span className="estado-country-name">{pais.nombre}</span>
                      </div>
                      <div className="estado-rate-info">
                        <div className="estado-rate">
                          {formatearMonto(pais.tasaCalculada)}
                        </div>
                        <div className="estado-currency">
                          {pais.codigo} / USD
                        </div>
                      </div>
                    </div>
                  ))}
                </div>

                <div className="estado-footer">
                  Tasa referencial sujeta a cambios • Grupo JK
                </div>
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
        ))}
      </div>
    </div>
  )
}
