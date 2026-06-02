import React, { useState, useEffect, useRef } from 'react'
import html2canvas from 'html2canvas'
import { cargarPaises, obtenerTasasProcesadas, getFlagUrl, formatearMonto, sincronizarGoogleSheets, isCajaDolar, calcularConversionInversa, calcularTasaEnvio, calcularTasaRecibo } from './constants'
import './GeneradorEstados.css'

export default function GeneradorEstados() {
  const [todosPaises, setTodosPaises] = useState([])
  const [paisOrigen, setPaisOrigen] = useState(null)
  const [modoGlobal, setModoGlobal] = useState(false)
  const [formatoGlobal, setFormatoGlobal] = useState('story') // 'story' o 'square'
  const [chunks, setChunks] = useState([])
  const [expandido, setExpandido] = useState(null)
  const cardRefs = useRef([])

  useEffect(() => {
    const loadData = async () => {
      // Cargar local primero
      const paisesLocales = cargarPaises().filter(p => p.tasaProveedor > 0 || p.tasaProveedorEnvio > 0 || p.id === 9)
      setTodosPaises(paisesLocales)
      
      // Sincronizar en background con Sheets para tener las tasas frescas
      await sincronizarGoogleSheets()
      const paisesActualizados = cargarPaises().filter(p => p.tasaProveedor > 0 || p.tasaProveedorEnvio > 0 || p.id === 9)
      setTodosPaises(paisesActualizados)
    }
    loadData()
  }, [])

  // Manejar botón atrás del teléfono/mouse para cerrar el modal
  useEffect(() => {
    const handlePopState = () => {
      if (expandido !== null) {
        setExpandido(null)
      }
    }
    window.addEventListener('popstate', handlePopState)
    return () => window.removeEventListener('popstate', handlePopState)
  }, [expandido])

  const toggleExpandido = (index) => {
    if (index !== null) {
      window.history.pushState({ modalAbierto: true }, '')
      setExpandido(index)
    } else {
      if (expandido !== null) {
        window.history.back() // Esto disparará el popstate y cerrará el modal
      }
    }
  }

  useEffect(() => {
    if (paisOrigen) {
      // Filtrar que no sea el Origen y que tenga tasa
      const paisesDestino = todosPaises.filter(p => p.id !== paisOrigen.id)

      // Calcular la tasa enviar para cada país desde el Origen
      const paisesConTasa = paisesDestino.map(pais => {
        const { tasaOrigenParaDolares, tasaDestinoDesdeDolares } = obtenerTasasProcesadas(paisOrigen, pais, todosPaises, 'detal')
        const tc = (1 / tasaOrigenParaDolares) * tasaDestinoDesdeDolares
        
        let displayRate = tc;
        let displayUnit = pais.codigo;
        let isInverse = false;

        // Si el origen NO es dólar y el destino SÍ es dólar, aplicamos la lógica inversa del Cotizador
        if (!isCajaDolar(paisOrigen) && isCajaDolar(pais)) {
          const tcInverso = calcularConversionInversa(paisOrigen, pais, 1, todosPaises, 'detal')
          displayRate = tcInverso;
          displayUnit = paisOrigen.codigo;
          isInverse = true;
        }

        return {
          ...pais,
          tasaCalculada: tc,
          displayRate,
          displayUnit,
          isInverse
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

  useEffect(() => {
    if (modoGlobal) {
      const paisesLocales = todosPaises.filter(p => !isCajaDolar(p))
      const size = 9
      const newChunks = []
      for (let i = 0; i < paisesLocales.length; i += size) {
        newChunks.push(paisesLocales.slice(i, i + size))
      }
      setChunks(newChunks)
    }
  }, [modoGlobal, todosPaises])

  const descargarImagen = async (index) => {
    // Si no está expandido, lo expandimos para asegurar máxima calidad de renderizado
    if (expandido !== index) {
      setExpandido(index)
      // Esperar un poco para que el DOM se actualice antes de capturar
      await new Promise(r => setTimeout(r, 300))
    }

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
      link.download = `JK_Estados_${paisOrigen.codigo}_Parte_${index + 1}_${Date.now()}.png`
      link.click()
      
      // Cerrar modal automáticamente después de descargar si lo abrimos solo para esto
      toggleExpandido(null)
    } catch (error) {
      console.error('Error al generar la imagen:', error)
      alert('Hubo un error al descargar la imagen.')
    }
  }

  const descargarPizarraImagen = async (index) => {
    // Si no está expandido, lo expandimos para asegurar máxima calidad de renderizado
    if (expandido !== index) {
      setExpandido(index)
      // Esperar un poco para que el DOM se actualice antes de capturar
      await new Promise(r => setTimeout(r, 300))
    }

    const element = cardRefs.current[index]
    if (!element) return

    try {
      const isSquare = formatoGlobal === 'square'
      const canvas = await html2canvas(element, {
        scale: 2, // Alta calidad
        useCORS: true,
        backgroundColor: '#020813' // Color premium oscuro
      })
      
      const image = canvas.toDataURL('image/png')
      const link = document.createElement('a')
      link.href = image
      link.download = `JK_Pizarra_Global_${isSquare ? 'Cuadrado' : 'Historia'}_Parte_${index + 1}_${Date.now()}.png`
      link.click()
      
      // Cerrar modal automáticamente después de descargar si lo abrimos solo para esto
      toggleExpandido(null)
    } catch (error) {
      console.error('Error al generar la imagen:', error)
      alert('Hubo un error al descargar la imagen.')
    }
  }

  // VISTA 1: SELECCIONAR PAIS DE ORIGEN
  if (!paisOrigen && !modoGlobal) {
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
          {/* Opción Pizarra Global de Primera */}
          <button
            onClick={() => {
              setModoGlobal(true)
              const paisesLocales = todosPaises.filter(p => !isCajaDolar(p))
              const size = 9
              const newChunks = []
              for (let i = 0; i < paisesLocales.length; i += size) {
                newChunks.push(paisesLocales.slice(i, i + size))
              }
              setChunks(newChunks)
            }}
            style={{
              background: 'linear-gradient(135deg, rgba(0, 198, 255, 0.1) 0%, rgba(0, 114, 255, 0.05) 100%)',
              border: '2px dashed var(--primary-color)',
              borderRadius: '1rem',
              padding: '1.2rem',
              cursor: 'pointer',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '0.5rem',
              transition: 'all 0.3s ease',
              color: 'white',
              gridColumn: '1 / -1',
              boxShadow: '0 0 15px rgba(0, 198, 255, 0.1)'
            }}
            onMouseEnter={e => {
              e.currentTarget.style.background = 'linear-gradient(135deg, rgba(0, 198, 255, 0.18) 0%, rgba(0, 114, 255, 0.12) 100%)'
              e.currentTarget.style.borderColor = '#00e5ff'
              e.currentTarget.style.boxShadow = '0 0 25px rgba(0, 198, 255, 0.3)'
            }}
            onMouseLeave={e => {
              e.currentTarget.style.background = 'linear-gradient(135deg, rgba(0, 198, 255, 0.1) 0%, rgba(0, 114, 255, 0.05) 100%)'
              e.currentTarget.style.borderColor = 'var(--primary-color)'
              e.currentTarget.style.boxShadow = '0 0 15px rgba(0, 198, 255, 0.1)'
            }}
          >
            <span style={{ fontSize: '2.5rem', lineHeight: 1 }}>📊</span>
            <span style={{ fontWeight: 900, fontSize: '1.3rem', letterSpacing: '0.08em', color: 'var(--primary-color)' }}>
              PIZARRA GLOBAL
            </span>
            <span style={{ fontSize: '0.8rem', color: 'rgba(255,255,255,0.6)' }}>
              Tasas de Envío y Recibo Consolidadas (Base USD/USDT)
            </span>
          </button>

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

  // Función para renderizar el contenido exacto de la tarjeta
  const renderCard = (chunk, isCaptureTarget, index) => (
    <div 
      className="estado-card premium-tree" 
      ref={isCaptureTarget ? (el => cardRefs.current[index] = el) : null}
    >
      {/* Marca de Agua (Fondo muy visible) */}
      <div className="watermark-container">
        <img 
          src="./logo-jk-transparente.png" 
          alt="Watermark 1" 
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
              src={`${getFlagUrl(paisOrigen)}?v=canvas`} 
              alt={paisOrigen.nombre} 
              className="origin-flag"
              crossOrigin="anonymous" 
              onError={(e) => { e.target.src = 'https://cdn-icons-png.flaticon.com/512/350/350965.png' }}
            />
            <span className="origin-currency">1 {paisOrigen.codigo}</span>
          </div>
        </div>

        {/* CENTRO: LÍNEAS SVG */}
        <div className="tree-svg-container">
          <svg preserveAspectRatio="none" viewBox="0 0 100 100" className="tree-svg">
            {chunk.map((_, i) => {
              const step = 100 / chunk.length;
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
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0.2em', width: '55px', flexShrink: 0 }}>
                <div style={{ fontSize: '0.55em', fontWeight: 'bold', color: 'rgba(255,255,255,0.9)', textTransform: 'uppercase', textAlign: 'center', lineHeight: '1' }}>
                  {pais.nombre}
                </div>
                <img 
                  src={`${getFlagUrl(pais)}?v=canvas`} 
                  alt={pais.nombre} 
                  className="dest-flag"
                  crossOrigin="anonymous" 
                  onError={(e) => { e.target.src = 'https://cdn-icons-png.flaticon.com/512/350/350965.png' }}
                />
              </div>
              <div className="dest-info">
                <div className="dest-rate">{formatearMonto(pais.displayRate)}</div>
                <div className="dest-name">{pais.isInverse ? `x 1 ${pais.codigo}` : pais.displayUnit}</div>
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
  );

  // VISTA DE LA PIZARRA GLOBAL CARD (HISTORIA O CUADRADO)
  const renderPizarraGlobalCard = (chunk, isCaptureTarget, index) => {
    const isSquare = formatoGlobal === 'square';
    const cardClass = isSquare ? 'premium-pizarra-square' : 'premium-pizarra-story';
    const fechaHoy = new Date().toLocaleDateString('es-ES', { day: '2-digit', month: '2-digit', year: 'numeric' });

    return (
      <div 
        className={`estado-card ${cardClass}`} 
        ref={isCaptureTarget ? (el => cardRefs.current[index] = el) : null}
        style={{
          width: isSquare ? '600px' : '450px',
          height: isSquare ? '600px' : '800px',
          flexShrink: 0,
          background: 'linear-gradient(135deg, #020b18 0%, #01040a 100%)',
          position: 'relative',
          overflow: 'hidden',
          padding: isSquare ? '2em 1.5em' : '2.5em 1.5em',
          display: 'flex',
          flexDirection: 'column',
          border: '1px solid rgba(255, 255, 255, 0.05)',
          borderRadius: '1.5em',
          color: 'white',
          boxShadow: '0 20px 50px rgba(0, 0, 0, 0.5)',
          fontSize: isSquare ? '14px' : '16px',
          transition: 'none'
        }}
      >
        {/* Marca de Agua (Fondo muy visible) */}
        <div className="watermark-container">
          <img 
            src="./logo-jk-transparente.png" 
            alt="Watermark 1" 
            className="estado-watermark" 
            crossOrigin="anonymous"
          />
        </div>

        {/* Branding Header */}
        <div className="estado-header-minimal" style={{ marginBottom: isSquare ? '0.5em' : '1.2em', paddingBottom: isSquare ? '0.6em' : '1em' }}>
          <img 
            src="./logo-jk-transparente.png" 
            alt="Logo JK" 
            className="header-logo" 
            crossOrigin="anonymous"
            style={{ width: isSquare ? '3em' : '3.5em', height: isSquare ? '3em' : '3.5em' }}
          />
          <div className="header-text">
            <h2 className="estado-title-minimal" style={{ fontSize: isSquare ? '1.6em' : '1.8em', lineHeight: 1 }}>GRUPO JK</h2>
            <p className="estado-subtitle-minimal" style={{ fontSize: isSquare ? '0.8em' : '0.85em', color: 'var(--primary-color)' }}>
              PIZARRA GLOBAL • {fechaHoy}
            </p>
          </div>
        </div>

        {/* SUB-HEADER / INDICACIÓN DE BASE */}
        <div style={{
          textAlign: 'center',
          background: 'rgba(0, 198, 255, 0.06)',
          border: '1px solid rgba(0, 198, 255, 0.15)',
          padding: '0.4em 1em',
          borderRadius: '0.6em',
          fontSize: '0.85em',
          fontWeight: 'bold',
          color: 'var(--primary-color)',
          marginBottom: isSquare ? '0.8em' : '1.2em',
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          gap: '0.5em',
          letterSpacing: '0.05em'
        }}>
          💵 BASE USD / USDT
        </div>

        {/* LISTA DE PAÍSES */}
        <div style={{
          display: 'flex',
          flexDirection: 'column',
          gap: isSquare ? '0.4em' : '0.6em',
          flex: 1,
          justifyContent: 'center'
        }}>
          {/* Cabecera de la tabla */}
          <div style={{
            display: 'grid',
            gridTemplateColumns: '1.8fr 1fr 1fr',
            padding: '0 0.8em',
            fontSize: '0.7em',
            fontWeight: 800,
            color: 'rgba(255,255,255,0.4)',
            textTransform: 'uppercase',
            letterSpacing: '0.08em',
            borderBottom: '1px solid rgba(255,255,255,0.05)',
            paddingBottom: '0.3em',
            marginBottom: '0.2em'
          }}>
            <div>País / Moneda</div>
            <div style={{ textAlign: 'right' }}>📤 Envío</div>
            <div style={{ textAlign: 'right' }}>📥 Recibo</div>
          </div>

          {chunk.map(pais => {
            const tasaEnvio = calcularTasaEnvio(pais, 'detal');
            const tasaRecibo = calcularTasaRecibo(pais, 'detal');
            
            return (
              <div 
                key={pais.id} 
                style={{
                  display: 'grid',
                  gridTemplateColumns: '1.8fr 1fr 1fr',
                  alignItems: 'center',
                  background: 'rgba(2, 11, 24, 0.7)',
                  padding: isSquare ? '0.4em 0.8em' : '0.5em 0.8em',
                  borderRadius: '0.8em',
                  border: '1px solid rgba(255, 255, 255, 0.08)',
                  boxShadow: '0 2px 5px rgba(0,0,0,0.15)'
                }}
              >
                {/* País info */}
                <div style={{ display: 'flex', alignItems: 'center', gap: '0.6em' }}>
                  <img 
                    src={`${getFlagUrl(pais)}?v=canvas`} 
                    alt={pais.nombre} 
                    style={{
                      width: '1.8em',
                      height: '1.8em',
                      borderRadius: '50%',
                      objectFit: 'cover',
                      border: '1px solid rgba(255, 255, 255, 0.1)',
                      boxShadow: '0 2px 5px rgba(0,0,0,0.2)'
                    }}
                    crossOrigin="anonymous" 
                    onError={(e) => { e.target.src = 'https://cdn-icons-png.flaticon.com/512/350/350965.png' }}
                  />
                  <div style={{ display: 'flex', flexDirection: 'column', lineHeight: 1.1 }}>
                    <span style={{ fontSize: '0.85em', fontWeight: 700, color: 'rgba(255,255,255,0.95)', textShadow: '0 1px 2px rgba(0,0,0,0.9)' }}>{pais.nombre}</span>
                    <span style={{ fontSize: '0.65em', fontWeight: 600, color: 'rgba(255,255,255,0.4)', textTransform: 'uppercase', textShadow: '0 1px 1px rgba(0,0,0,0.5)' }}>{pais.codigo}</span>
                  </div>
                </div>

                {/* Tasa Envío */}
                <div style={{ textAlign: 'right' }}>
                  <div style={{ fontSize: '0.95em', fontWeight: 800, color: '#10b981', textShadow: '0 1px 2px rgba(0,0,0,0.9)' }}>
                    {formatearMonto(tasaEnvio)}
                  </div>
                  <div style={{ fontSize: '0.55em', fontWeight: 600, color: 'rgba(255,255,255,0.4)', textShadow: '0 1px 1px rgba(0,0,0,0.5)' }}>
                    x 1 USD
                  </div>
                </div>

                {/* Tasa Recibo */}
                <div style={{ textAlign: 'right' }}>
                  <div style={{ fontSize: '0.95em', fontWeight: 800, color: 'var(--primary-color)', textShadow: '0 1px 2px rgba(0,0,0,0.9)' }}>
                    {formatearMonto(tasaRecibo)}
                  </div>
                  <div style={{ fontSize: '0.55em', fontWeight: 600, color: 'rgba(255,255,255,0.4)', textShadow: '0 1px 1px rgba(0,0,0,0.5)' }}>
                    x 1 USD
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        {/* FOOTER */}
        <div className="estado-footer-minimal" style={{
          marginTop: isSquare ? '0.6em' : '1.5em',
          paddingTop: isSquare ? '0.6em' : '1.2em',
          borderTop: '1px solid rgba(255, 255, 255, 0.05)',
          fontSize: '0.7em',
          color: 'rgba(255, 255, 255, 0.4)',
          textAlign: 'center',
          fontWeight: 'bold',
          letterSpacing: '0.05em'
        }}>
          <div>Todos monto mínimo de $20</div>
          <div style={{ fontSize: '0.8em', color: 'rgba(255,255,255,0.25)', marginTop: '0.2em', fontWeight: 500 }}>
            Tasas referenciales sujetas a cambio • Grupo JK
          </div>
        </div>
      </div>
    );
  };

  // VISTA 3: PIZARRA GLOBAL
  if (modoGlobal) {
    return (
      <div style={{ color: 'white' }}>
        
        <div style={{ 
          display: 'flex', 
          justifyContent: 'space-between', 
          alignItems: 'center', 
          marginBottom: '2rem', 
          maxWidth: '800px', 
          margin: '0 auto 2rem auto',
          flexWrap: 'wrap',
          gap: '1rem'
        }}>
          <button 
            onClick={() => {
              setModoGlobal(false)
              setChunks([])
            }}
            style={{ 
              background: 'none', 
              border: '1px solid rgba(255,255,255,0.2)', 
              color: 'white', 
              padding: '0.5rem 1rem', 
              borderRadius: '0.5rem', 
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              fontWeight: 600
            }}
          >
            ← Volver al Inicio
          </button>

          {/* Pill Switcher para Formatos */}
          <div style={{
            display: 'flex',
            background: 'rgba(255, 255, 255, 0.03)',
            border: '1px solid rgba(255, 255, 255, 0.08)',
            borderRadius: '100px',
            padding: '4px',
            gap: '4px'
          }}>
            <button 
              onClick={() => setFormatoGlobal('story')}
              style={{
                background: formatoGlobal === 'story' ? 'var(--primary-color)' : 'none',
                border: 'none',
                color: formatoGlobal === 'story' ? '#000' : '#fff',
                padding: '0.5rem 1.2rem',
                borderRadius: '100px',
                cursor: 'pointer',
                fontWeight: 'bold',
                fontSize: '0.85rem',
                transition: 'all 0.3s ease',
                display: 'flex',
                alignItems: 'center',
                gap: '0.3rem'
              }}
            >
              📱 Historia
            </button>
            <button 
              onClick={() => setFormatoGlobal('square')}
              style={{
                background: formatoGlobal === 'square' ? 'var(--primary-color)' : 'none',
                border: 'none',
                color: formatoGlobal === 'square' ? '#000' : '#fff',
                padding: '0.5rem 1.2rem',
                borderRadius: '100px',
                cursor: 'pointer',
                fontWeight: 'bold',
                fontSize: '0.85rem',
                transition: 'all 0.3s ease',
                display: 'flex',
                alignItems: 'center',
                gap: '0.3rem'
              }}
            >
              🟩 Cuadrado
            </button>
          </div>
        </div>

        <div className="generador-estados-container">
          {chunks.map((chunk, index) => {
            const isExpanded = expandido === index;
            const isSquare = formatoGlobal === 'square';
            const cardH = isSquare ? 225 : 400; // Alto visual en miniatura
            const scaleFactor = isSquare ? 0.375 : 0.5; // Escala para ajustar a 225px de ancho visual

            return (
              <div key={index} className="estado-card-wrapper" style={{ alignItems: 'center' }}>
                <p style={{ color: 'var(--text-low)', fontSize: '0.8rem', marginBottom: '-0.5rem' }}>
                  Haz clic en la imagen para verla en tamaño completo
                </p>
                
                {/* Contenedor del Preview (Miniatura) */}
                <div 
                  style={{
                    width: '225px',
                    height: `${cardH}px`,
                    position: 'relative',
                    overflow: 'hidden',
                    borderRadius: '1.5rem',
                    cursor: 'zoom-in',
                    border: '1px solid rgba(255,255,255,0.2)',
                    boxShadow: '0 10px 30px rgba(0,0,0,0.5)'
                  }}
                  onClick={() => toggleExpandido(index)}
                >
                  <div style={{
                    transform: `scale(${scaleFactor})`,
                    transformOrigin: 'top left',
                    width: isSquare ? '600px' : '450px',
                    height: isSquare ? '600px' : '800px'
                  }}>
                    {renderPizarraGlobalCard(chunk, !isExpanded, index)}
                  </div>
                </div>

                {/* Botón Descargar */}
                <button 
                  onClick={() => descargarPizarraImagen(index)}
                  className="btn-primary"
                  style={{ padding: '1rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.5rem', fontWeight: 'bold', width: '225px' }}
                >
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                    <polyline points="7 10 12 15 17 10"></polyline>
                    <line x1="12" y1="15" x2="12" y2="3"></line>
                  </svg>
                  Descargar Parte {index + 1}
                </button>

                {/* Modal Full Screen (Visible cuando el usuario hace clic en el preview) */}
                {isExpanded && (
                  <div className="modal-overlay" onClick={() => toggleExpandido(null)}>
                    <div 
                      className="modal-content" 
                      onClick={e => e.stopPropagation()} 
                      style={{
                        transform: isSquare ? 'scale(0.85)' : 'scale(0.85)',
                        transformOrigin: 'center center'
                      }}
                    >
                      {renderPizarraGlobalCard(chunk, isExpanded, index)}
                    </div>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      </div>
    );
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
          const isExpanded = expandido === index;
          
          return (
          <div key={index} className="estado-card-wrapper" style={{ alignItems: 'center' }}>
            <p style={{ color: 'var(--text-low)', fontSize: '0.8rem', marginBottom: '-0.5rem' }}>
              Haz clic en la imagen para verla en tamaño completo
            </p>
            
            {/* Contenedor del Preview (Miniatura) */}
            <div 
              style={{
                width: '225px',
                height: '400px',
                position: 'relative',
                overflow: 'hidden',
                borderRadius: '1.5rem',
                cursor: 'zoom-in',
                border: '1px solid rgba(255,255,255,0.2)',
                boxShadow: '0 10px 30px rgba(0,0,0,0.5)'
              }}
              onClick={() => toggleExpandido(index)}
            >
              {/* Contenedor que escala la tarjeta original 450x800 a 50% usando transform CSS puro */}
              <div style={{
                transform: 'scale(0.5)',
                transformOrigin: 'top left',
                width: '450px',
                height: '800px'
              }}>
                {renderCard(chunk, !isExpanded, index)}
              </div>
            </div>
            {/* Botón Descargar */}
            <button 
              onClick={() => descargarImagen(index)}
              className="btn-primary"
              style={{ padding: '1rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.5rem', fontWeight: 'bold', width: '225px' }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
                <polyline points="7 10 12 15 17 10"></polyline>
                <line x1="12" y1="15" x2="12" y2="3"></line>
              </svg>
              Descargar Parte {index + 1}
            </button>

            {/* Modal Full Screen (Visible cuando el usuario hace clic en el preview) */}
            {isExpanded && (
              <div className="modal-overlay" onClick={() => toggleExpandido(null)}>
                <div 
                  className="modal-content" 
                  onClick={e => e.stopPropagation()} 
                  style={{
                    /* En móviles muy pequeños, reducimos un poco el scale visual del modal, pero el DOM sigue siendo 450x800 para html2canvas */
                    transform: 'scale(0.85)',
                    transformOrigin: 'center center'
                  }}
                >
                  {renderCard(chunk, isExpanded, index)}
                </div>
              </div>
            )}
          </div>
        )})}
      </div>
    </div>
  )
}
