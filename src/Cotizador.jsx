import { useState, useEffect, useRef } from 'react'
import { cargarPaises, calcularTasaPublica, calcularConversion, calcularConversionInversa, isCajaDolar, formatearMonto, calcularTasaEnvio, calcularTasaRecibo, getFlagUrl, isCustomFlag, isEfectivoVenSubEntry, agruparEfectivoVenezuela, getPaisesParaSelector, parsearMonto, formatearMontoInput } from './constants'

// Componente interno para selector de países con buscador responsivo
function PaisSelector({ label, paises, selected, onSelect, noBottomRadius = false, hideLabel = false }) {
  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState('')
  const [isMobile, setIsMobile] = useState(window.innerWidth <= 600)
  const [keyboardOffset, setKeyboardOffset] = useState(0)
  const [visibleHeight, setVisibleHeight] = useState(window.innerHeight)
  const containerRef = useRef(null)

  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth <= 600)
    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [])

  // Detectar teclado virtual y subir la bottom sheet para que el buscador siempre sea visible
  useEffect(() => {
    if (!open || !isMobile) return
    const vv = window.visualViewport
    if (!vv) return
    const handleVV = () => {
      const offset = window.innerHeight - vv.height - vv.offsetTop
      setKeyboardOffset(Math.max(0, offset))
      setVisibleHeight(vv.height)
    }
    vv.addEventListener('resize', handleVV)
    vv.addEventListener('scroll', handleVV)
    handleVV()
    return () => {
      vv.removeEventListener('resize', handleVV)
      vv.removeEventListener('scroll', handleVV)
      setKeyboardOffset(0)
      setVisibleHeight(window.innerHeight)
    }
  }, [open, isMobile])

  const normalize = str => str.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  const searchNorm = normalize(search);
  const filtered = paises.filter(p =>
    normalize(p.nombre).includes(searchNorm) ||
    (p.codigo || '').toLowerCase().includes(search.toLowerCase()) ||
    (p.iso2 || '').toLowerCase().includes(search.toLowerCase()) ||
    normalize(p.moneda || '').includes(searchNorm)
  )

  const renderList = () => (
    <div style={{ flex: 1, overflowY: 'auto', padding: '0.4rem' }} className="custom-scroll">
      {filtered.map(p => (
        <div 
          key={p.id}
          onClick={() => { onSelect(p.id); setOpen(false); setSearch(''); }}
          style={{
            padding: '1rem', cursor: 'pointer',
            display: 'flex', alignItems: 'center', gap: '0.8rem',
            borderRadius: '0.7rem',
            background: selected?.id === p.id ? 'rgba(16,185,129,0.15)' : 'transparent',
            transition: 'all 0.2s',
            marginBottom: '4px'
          }}
          className="selector-item"
        >
          <img 
            src={getFlagUrl(p)}
            alt={p.nombre}
            style={{ width: isCustomFlag(p) ? '2.5rem' : '1.8rem', height: isCustomFlag(p) ? '2.5rem' : '1.2rem', objectFit: 'contain', borderRadius: isCustomFlag(p) ? '0' : '3px' }}
          />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: '1rem', fontWeight: selected?.id === p.id ? 700 : 500, color: 'white' }}>{p.nombre}</div>
            <div style={{ fontSize: '0.75rem', color: 'var(--text-low)', textTransform: 'uppercase' }}>{p.moneda}</div>
          </div>
          <span style={{ fontSize: '0.75rem', fontWeight: 800, color: 'var(--primary-color)', background: 'rgba(16,185,129,0.1)', padding: '0.2rem 0.6rem', borderRadius: '0.4rem' }}>
            {p.codigo}
          </span>
        </div>
      ))}
      {filtered.length === 0 && (
        <div style={{ padding: '3rem 1rem', textAlign: 'center', color: 'var(--text-low)', fontSize: '0.9rem' }}>
          No encontramos "{search}" 🔍
        </div>
      )}
    </div>
  )

  return (
    <div style={{ position: 'relative', width: '100%' }}>
      {!hideLabel && (
        <label style={{ display: 'block', fontSize: '0.75rem', letterSpacing: '0.1em', color: 'var(--text-low)', marginBottom: '0.6rem', textTransform: 'uppercase', fontWeight: 700 }}>
          {label}
        </label>
      )}
      <div 
        onClick={() => setOpen(!open)}
        className="input-field"
        style={{ 
          cursor: 'pointer', 
          display: 'flex', 
          alignItems: 'center', 
          gap: '0.75rem',
          height: '3.8rem',
          padding: '0 1.25rem',
          borderBottomLeftRadius: noBottomRadius ? 0 : '1.5rem',
          borderBottomRightRadius: noBottomRadius ? 0 : '1.5rem',
          transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)'
        }}
      >
        {selected ? (
          <img 
            src={getFlagUrl(selected)}
            alt={selected.nombre}
            style={{ width: isCustomFlag(selected) ? '2.2rem' : '1.6rem', height: isCustomFlag(selected) ? '2.2rem' : '1.1rem', objectFit: 'contain', borderRadius: isCustomFlag(selected) ? '0' : '3px' }}
          />
        ) : <span style={{fontSize: '1.2rem'}}>🌐</span>}
        <span style={{ flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', fontWeight: 600, fontSize: '1.05rem' }}>
          {selected ? selected.nombre : 'Elije un país...'}
        </span>
        <span style={{ fontSize: '0.7rem', opacity: 0.6, transition: 'transform 0.4s', transform: open ? 'rotate(180deg)' : 'rotate(0)' }}>▼</span>
      </div>

      {open && (
        <>
          {/* Overlay para cerrar al hacer clic fuera (móvil y desktop) */}
          <div 
            className="mobile-overlay" 
            onClick={() => { setOpen(false); setSearch(''); }} 
            style={{ display: isMobile ? 'block' : 'block', position: 'fixed', inset: 0, zIndex: isMobile ? undefined : 999, background: isMobile ? undefined : 'transparent' }}
          />
          
          <div 
            className={isMobile ? 'bottom-sheet' : ''} 
            style={isMobile ? { 
              bottom: `${keyboardOffset}px`,
              maxHeight: `${Math.min(visibleHeight * 0.9, visibleHeight - 20)}px`
            } : {
              position: 'absolute', top: '105%', left: 0, right: 0, zIndex: 1000,
              background: 'var(--surface-high)', backdropFilter: 'blur(30px)',
              border: '1px solid var(--glass-border)', borderRadius: '1.25rem',
              overflow: 'hidden', boxShadow: '0 25px 60px rgba(0,0,0,0.6)',
              animation: 'fadeIn 0.2s ease-out'
            }}
          >
            {isMobile && <div className="bottom-sheet-header" />}
            
            <div style={{ padding: '1rem', borderBottom: '1px solid rgba(255,255,255,0.08)' }}>
              <div style={{ position: 'relative' }}>
                <input 
                  autoFocus
                  type="text"
                  placeholder="Escribe el nombre o código..."
                  value={search}
                  onChange={e => setSearch(e.target.value)}
                  onClick={e => e.stopPropagation()}
                  style={{
                    width: '100%', padding: '1rem 1rem 1rem 3rem', background: 'rgba(0,0,0,0.2)',
                    border: '1px solid rgba(255,255,255,0.1)', borderRadius: '1rem',
                    color: 'white', outline: 'none', fontSize: '1rem'
                  }}
                />
                <span style={{ position: 'absolute', left: '1.2rem', top: '50%', transform: 'translateY(-50%)', opacity: 0.5 }}>🔍</span>
              </div>
            </div>

            {renderList()}
            
            {isMobile && (
              <div style={{ padding: '1rem', borderTop: '1px solid rgba(255,255,255,0.05)', textAlign: 'center' }}>
                <button 
                  onClick={() => { setOpen(false); setSearch(''); }}
                  style={{ width: '100%', padding: '1rem', borderRadius: '1rem', border: 'none', background: 'var(--surface-high)', color: 'white', fontWeight: 600 }}
                >
                  Cerrar
                </button>
              </div>
            )}
          </div>
        </>
      )}
    </div>
  )
}

export default function Cotizador({ modo = 'detal' }) {
  const [paises, setPaises] = useState([])
  const [paisesSelector, setPaisesSelector] = useState([])
  const [origen, setOrigen] = useState(null)
  const [destino, setDestino] = useState(null)
  const [monto, setMonto] = useState('')
  const [montoRecibir, setMontoRecibir] = useState('')
  const [tasaDisplay, setTasaDisplay] = useState({ base: '', valor: 0, unidad: '' })
  const [lastEdited, setLastEdited] = useState('enviar')
  const [isMobile, setIsMobile] = useState(window.innerWidth <= 600)
  const [errorDismissed, setErrorDismissed] = useState(false)
  const [efectivoVenNoticeDismissed, setEfectivoVenNoticeDismissed] = useState(false)
  // Sub-menú Efectivo Venezuela
  const [showEVMenu, setShowEVMenu] = useState(false)
  const [evGrupos, setEvGrupos] = useState([])
  const [evEstadoSeleccionado, setEvEstadoSeleccionado] = useState(null)
  const [evSelectTarget, setEvSelectTarget] = useState('destino') // 'origen' | 'destino'

  const esMayor = modo === 'mayor'
  const isEfectivoVen = (p) => p?.nombre?.toUpperCase().includes('EFECTIVO VENEZUELA') || p?.nombre?.toUpperCase().includes('EFECTIVO VEN');

  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth <= 600)
    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [])

  useEffect(() => {
    if (destino && isEfectivoVen(destino)) {
      setEfectivoVenNoticeDismissed(false);
    }
  }, [destino])

  useEffect(() => {
    const todos = cargarPaises()
    setPaises(todos)
    setPaisesSelector(getPaisesParaSelector(todos))
    setEvGrupos(agruparEfectivoVenezuela(todos))
    
    // Buscar en memoria, sino usar valores por defecto (Ecuador -> Colombia)
    const savedOrigenId = localStorage.getItem('jk_last_origen')
    const savedDestinoId = localStorage.getItem('jk_last_destino')

    let defaultOrigen = todos.find(p => p.id === 9)
    let defaultDestino = todos.find(p => p.id === 8)

    if (savedOrigenId) {
      const p = todos.find(x => x.id === parseInt(savedOrigenId))
      if (p) defaultOrigen = p
    }
    if (savedDestinoId) {
      const p = todos.find(x => x.id === parseInt(savedDestinoId))
      if (p) defaultDestino = p
    }

    setOrigen(defaultOrigen)
    setDestino(defaultDestino)
  }, [])

  useEffect(() => {
    if (origen && destino && paises.length > 0) {
      const tOrigenRecibo = calcularTasaRecibo(origen, modo)
      const tDestinoEnvio = calcularTasaEnvio(destino, modo)
      const isDisp = tOrigenRecibo > 0 && tDestinoEnvio > 0

      const numMonto = parsearMonto(monto)
      const numMontoRecibir = parsearMonto(montoRecibir)

      if (isDisp) {
        const tc = calcularConversion(origen, destino, 1, paises, modo)
        if (isCajaDolar(origen) && !isCajaDolar(destino)) {
          setTasaDisplay({ base: `1 ${origen.codigo}`, valor: tc, unidad: destino.codigo })
        } else if (!isCajaDolar(origen) && isCajaDolar(destino)) {
          const tcInverso = calcularConversionInversa(origen, destino, 1, paises, modo)
          setTasaDisplay({ base: `1 ${destino.codigo}`, valor: tcInverso, unidad: origen.codigo })
        } else {
          setTasaDisplay({ base: `1 ${origen.codigo}`, valor: tc, unidad: destino.codigo })
        }
      }

      if (lastEdited === 'enviar' && monto !== '') {
        if (isDisp && numMonto > 0) {
          const res = calcularConversion(origen, destino, numMonto, paises, modo)
          setMontoRecibir(formatearMontoInput(res.toFixed(2).replace('.', ',')))
        } else if (numMonto === 0) {
          setMontoRecibir('0')
        }
      } else if (lastEdited === 'recibir' && montoRecibir !== '') {
        if (isDisp && numMontoRecibir > 0) {
          const nuevoMonto = calcularConversionInversa(origen, destino, numMontoRecibir, paises, modo)
          setMonto(formatearMontoInput(nuevoMonto.toFixed(2).replace('.', ',')))
        } else {
          setMonto('0')
        }
      }
    }
  }, [origen, destino, paises, monto, montoRecibir, lastEdited, modo])


  const handleMontoEnviarChange = (valStr) => {
    setLastEdited('enviar')
    if (valStr === '') {
      setMonto('')
      setMontoRecibir('')
      return
    }
    // Permitir solo números y comas (una sola)
    let limpio = valStr.replace(/[^0-9,]/g, '')
    if ((limpio.match(/,/g) || []).length > 1) return
    
    setMonto(formatearMontoInput(limpio))
  }

  const handleMontoRecibirChange = (valStr) => {
    setLastEdited('recibir')
    if (valStr === '') {
      setMontoRecibir('')
      setMonto('')
      return
    }
    let limpio = valStr.replace(/[^0-9,]/g, '')
    if ((limpio.match(/,/g) || []).length > 1) return

    setMontoRecibir(formatearMontoInput(limpio))
  }

  const handleOrigen = (id) => {
    // Si es el placeholder de Efectivo Venezuela, abrir sub-menú para ORIGEN
    if (id === 'ev-placeholder') {
      setEvSelectTarget('origen')
      setShowEVMenu(true)
      setEvEstadoSeleccionado(null)
      return
    }
    const p = paises.find(p => p.id === parseInt(id)) || paisesSelector.find(p => p.id === id)
    if (!p) return
    setOrigen(p)
    localStorage.setItem('jk_last_origen', p.id)
    
    setErrorDismissed(false)

    // No permitir mismo país en ambos lados
    if (destino && destino.id === p.id) {
      setDestino(null)
      localStorage.removeItem('jk_last_destino')
    }
  }

  const handleDestino = (id) => {
    // Si es el placeholder de Efectivo Venezuela, abrir sub-menú
    if (id === 'ev-placeholder') {
      setEvSelectTarget('destino')
      setShowEVMenu(true)
      setEvEstadoSeleccionado(null)
      return
    }
    const p = paises.find(p => p.id === parseInt(id)) || paisesSelector.find(p => p.id === id)
    setDestino(p)
    if (p) localStorage.setItem('jk_last_destino', p.id)

    setErrorDismissed(false)

    if (origen && origen.id === p.id) {
      setOrigen(null)
      localStorage.removeItem('jk_last_origen')
    }
  }

  // Handler para selección final de Efectivo Venezuela
  const handleEVSelect = (paisEV) => {
    if (evSelectTarget === 'origen') {
      setOrigen(paisEV)
      localStorage.setItem('jk_last_origen', paisEV.id)
    } else {
      setDestino(paisEV)
      localStorage.setItem('jk_last_destino', paisEV.id)
    }
    setShowEVMenu(false)
    setEvEstadoSeleccionado(null)
    setErrorDismissed(false)
  }

  const intercambiar = () => {
    const tempO = origen
    const tempD = destino
    setOrigen(tempD)
    setDestino(tempO)

    setErrorDismissed(false)

    if (tempD) localStorage.setItem('jk_last_origen', tempD.id)
    else localStorage.removeItem('jk_last_origen')

    if (tempO) localStorage.setItem('jk_last_destino', tempO.id)
    else localStorage.removeItem('jk_last_destino')
  }

  const tasaPublicaOrigen = origen ? calcularTasaPublica(origen) : 0
  const tasaPublicaDestino = destino ? calcularTasaPublica(destino) : 0

  const tOrigenCheck = origen ? calcularTasaRecibo(origen) : 1;
  const tDestinoCheck = destino ? calcularTasaEnvio(destino) : 1;
  const isDisponible = origen && destino ? (tOrigenCheck > 0 && tDestinoCheck > 0) : true;

  const getMotivoNoDisponible = () => {
    if (!origen || !destino || isDisponible) return '';
    if (tOrigenCheck === 0 && tDestinoCheck === 0) {
      return `Por el momento no estamos recibiendo ${origen.moneda} (${origen.nombre}) ni enviando hacia ${destino.nombre}.`;
    } else if (tOrigenCheck === 0) {
      return `En el caso de ${origen.nombre}, es que no recibimos ${origen.moneda} por el momento.`;
    } else if (tDestinoCheck === 0) {
      return `En el caso de ${destino.nombre}, es que no tenemos envíos en ${destino.moneda} por el momento.`;
    }
    return `La tasa de cambio para ${origen.nombre} o ${destino.nombre} está en actualización.`;
  }

  // Texto explicativo
  const explicacion = () => {
    if (!origen || !destino || !monto) return ''
    const codOrigen = origen.codigo
    const codDestino = destino.codigo
    const numMonto = parsearMonto(monto)
    const numMontoRecibir = parsearMonto(montoRecibir)
    const resFormateado = formatearMonto(numMontoRecibir, codDestino)
    const montoEnvFormateado = formatearMonto(numMonto, codOrigen)
    
    return `Estás enviando ${montoEnvFormateado} ${codOrigen} (${origen.nombre}) → ${resFormateado} ${codDestino} (${destino.nombre})`
  }

  return (
    <div style={{ maxWidth: '900px', margin: '0 auto', padding: '2rem 1.5rem' }}>
      <div style={{ textAlign: 'center', marginBottom: '3rem' }}>
        <h2 style={{ fontSize: 'clamp(1.8rem, 4vw, 2.5rem)', marginBottom: '0.5rem' }}>
          💱 Cotizador de Divisas{esMayor ? ' Mayor' : ''}
        </h2>
        <p style={{ color: 'var(--text-low)' }}>
          Ingresa el monto y selecciona los países para calcular tu cambio al instante
        </p>
      </div>

      <div className="glass" style={{ padding: isMobile ? '1.5rem' : '2.5rem', marginBottom: '2rem' }}>

        {/* Origen + Swap + Destino Integrados */}
        <div style={{ 
          display: 'grid', 
          gridTemplateColumns: isMobile ? '1fr' : '1fr auto 1fr', 
          gap: isMobile ? '1.5rem' : '1rem', 
          alignItems: 'start', 
          marginBottom: '2.5rem' 
        }}>

          {/* Bloque Origen */}
          <div style={{ width: '100%' }}>
            <label style={{ display: 'block', fontSize: '0.75rem', letterSpacing: '0.1em', color: 'var(--text-low)', marginBottom: '0.6rem', textTransform: 'uppercase', fontWeight: 700 }}>
              País de Origen / Monto a Enviar
            </label>
            <PaisSelector 
              hideLabel={true}
              noBottomRadius={true}
              paises={paisesSelector}
              selected={origen}
              onSelect={handleOrigen}
            />
            <div style={{ 
              display: 'flex', 
              alignItems: 'center', 
              borderRadius: '1.5rem', 
              borderTopLeftRadius: 0,
              borderTopRightRadius: 0,
              overflow: 'hidden', 
              border: '1px solid var(--glass-border)', 
              background: 'rgba(255,255,255,0.04)', 
              opacity: (isDisponible && !isEfectivoVen(destino)) ? 1 : 0.5,
              position: 'relative',
              marginTop: '-1px'
            }}>
              {origen && (
                <span style={{ padding: '0 0.9rem', borderRight: '1px solid var(--glass-border)', color: 'var(--primary-color)', fontWeight: 800, fontSize: '0.8rem', whiteSpace: 'nowrap', flexShrink: 0 }}>
                  {origen.codigo}
                </span>
              )}
              <input
                type="text"
                value={monto || ''}
                disabled={!isDisponible || isEfectivoVen(destino)}
                onChange={e => handleMontoEnviarChange(e.target.value)}
                placeholder={isEfectivoVen(destino) ? "Bloqueado" : "0"}
                style={{ flex: 1, background: 'transparent', border: 'none', outline: 'none', padding: '1rem', fontSize: isMobile ? '1.3rem' : '1.5rem', fontWeight: 700, color: 'white', width: '100%' }}
              />
            </div>
          </div>

          {/* Botón intercambiar */}
          <div style={{ display: 'flex', justifyContent: 'center', paddingTop: isMobile ? '0' : '2.2rem' }}>
            <button
              onClick={intercambiar}
              style={{
                width: isMobile ? 'fit-content' : '3.5rem', 
                height: '3.5rem',
                padding: isMobile ? '0 2.5rem' : '0',
                background: 'rgba(16,185,129,0.08)',
                border: '1px solid rgba(16,185,129,0.2)',
                borderRadius: isMobile ? '1rem' : '50%',
                cursor: 'pointer',
                fontSize: '1.4rem',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                transition: 'all 0.3s',
                color: 'var(--primary-color)'
              }}
              className="swap-btn"
              title="Intercambiar países"
            >
              {isMobile ? '⇅ Cambiar Dirección' : '⇄'}
            </button>
          </div>

          {/* Bloque Destino */}
          <div style={{ width: '100%' }}>
            <label style={{ display: 'block', fontSize: '0.75rem', letterSpacing: '0.1em', color: 'var(--text-low)', marginBottom: '0.6rem', textTransform: 'uppercase', fontWeight: 700 }}>
              País de Destino / Recibirías
            </label>
            <PaisSelector 
              hideLabel={true}
              noBottomRadius={true}
              paises={paisesSelector}
              selected={destino}
              onSelect={handleDestino}
            />
            <div style={{ 
              display: 'flex', 
              alignItems: 'center', 
              borderRadius: '1.5rem', 
              borderTopLeftRadius: 0,
              borderTopRightRadius: 0,
              overflow: 'hidden', 
              border: isEfectivoVen(destino) ? '1px solid var(--primary-color)' : '1px solid var(--glass-border)', 
              background: 'rgba(255,255,255,0.04)', 
              opacity: isDisponible ? 1 : 0.5,
              marginTop: '-1px'
            }}>
              {destino && (
                <span style={{ padding: '0 0.9rem', borderRight: isEfectivoVen(destino) ? '1px solid var(--primary-color)' : '1px solid var(--glass-border)', color: isEfectivoVen(destino) ? 'var(--primary-color)' : 'var(--error-color)', fontWeight: 800, fontSize: '0.8rem', whiteSpace: 'nowrap', flexShrink: 0 }}>
                  {destino.codigo}
                </span>
              )}
              <input
                type="text"
                value={montoRecibir || ''}
                disabled={!isDisponible}
                onChange={e => handleMontoRecibirChange(e.target.value)}
                placeholder="0"
                style={{ flex: 1, background: 'transparent', border: 'none', outline: 'none', padding: '1rem', fontSize: isMobile ? '1.3rem' : '1.5rem', fontWeight: 700, color: 'white', width: '100%' }}
              />
            </div>
          </div>
        </div>

        {/* MENSAJE DE NO DISPONIBLE EN LÍNEA TIPO BANNER (por si cierran el modal) */}
        {origen && destino && !isDisponible && errorDismissed && (
          <div style={{
            background: 'rgba(239, 68, 68, 0.1)',
            border: '1px solid rgba(239, 68, 68, 0.3)',
            borderRadius: '1rem',
            padding: '1rem 1.5rem',
            marginBottom: '2rem',
            display: 'flex',
            alignItems: 'center',
            gap: '1rem',
            animation: 'fadeIn 0.3s'
          }}>
            <span style={{ fontSize: '1.5rem' }}>⚠️</span>
            <div>
              <p style={{ color: 'var(--error-color)', fontWeight: 700, fontSize: '0.9rem', marginBottom: '0.2rem' }}>Conversión no disponible</p>
              <p style={{ color: 'var(--text-low)', fontSize: '0.85rem' }}>{getMotivoNoDisponible()}</p>
            </div>
          </div>
        )}

        {/* MODAL DE NO DISPONIBLE */}
        {origen && destino && !isDisponible && !errorDismissed && (
          <div 
            style={{
              position: 'fixed',
              top: 0, left: 0, right: 0, bottom: 0,
              backgroundColor: 'rgba(0,0,0,0.7)',
              backdropFilter: 'blur(8px)',
              zIndex: 99999,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              padding: '1.5rem',
              animation: 'fadeIn 0.2s ease-out'
            }}
            onClick={() => setErrorDismissed(true)}
          >
            <div 
              style={{
                background: 'var(--surface-high)',
                border: '1px solid rgba(239, 68, 68, 0.3)',
                borderRadius: '1.5rem',
                padding: '2.5rem 2rem',
                maxWidth: '400px',
                width: '100%',
                textAlign: 'center',
                boxShadow: '0 25px 50px -12px rgba(0,0,0,0.5)',
                animation: 'slideUp 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275)'
              }}
              onClick={e => e.stopPropagation()}
            >
              <div style={{ 
                fontSize: '3.5rem', 
                marginBottom: '1rem',
                display: 'inline-block'
              }}>
                ⚠️
              </div>
              <h3 style={{
                fontSize: '1.4rem',
                fontWeight: 800,
                color: 'var(--error-color)',
                marginBottom: '1rem',
                lineHeight: 1.2
              }}>
                Conversión no disponible
              </h3>
              <p style={{ color: 'var(--text-mid)', fontSize: '1rem', lineHeight: 1.6, marginBottom: '2rem' }}>
                {getMotivoNoDisponible()}
              </p>
              
              <button 
                onClick={() => setErrorDismissed(true)}
                style={{
                  width: '100%',
                  padding: '1.2rem',
                  borderRadius: '1rem',
                  border: 'none',
                  background: 'rgba(239, 68, 68, 0.15)',
                  color: 'var(--error-color)',
                  fontWeight: 800,
                  fontSize: '1.1rem',
                  cursor: 'pointer',
                  transition: 'background 0.2s',
                  textTransform: 'uppercase',
                  letterSpacing: '0.05em'
                }}
                onMouseOver={e => e.currentTarget.style.background = 'rgba(239, 68, 68, 0.25)'}
                onMouseOut={e => e.currentTarget.style.background = 'rgba(239, 68, 68, 0.15)'}
              >
                Entendido
              </button>
            </div>
          </div>
        )}

        {/* MODAL DE AVISO EFECTIVO VENEZUELA */}
        {origen && destino && isEfectivoVen(destino) && !efectivoVenNoticeDismissed && (
          <div 
            style={{
              position: 'fixed',
              top: 0, left: 0, right: 0, bottom: 0,
              backgroundColor: 'rgba(0,0,0,0.7)',
              backdropFilter: 'blur(8px)',
              zIndex: 99999,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              padding: '1.5rem',
              animation: 'fadeIn 0.2s ease-out'
            }}
            onClick={() => setEfectivoVenNoticeDismissed(true)}
          >
            <div 
              style={{
                background: 'var(--surface-high)',
                border: '1px solid var(--primary-color)',
                borderRadius: '1.5rem',
                padding: '2.5rem 2rem',
                maxWidth: '430px',
                width: '100%',
                textAlign: 'center',
                boxShadow: '0 25px 50px -12px rgba(0,0,0,0.5)',
                animation: 'slideUp 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275)'
              }}
              onClick={e => e.stopPropagation()}
            >
              <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>💵</div>
              <h3 style={{ fontSize: '1.4rem', fontWeight: 800, color: 'var(--primary-color)', marginBottom: '1.5rem', lineHeight: 1.2 }}>
                Aviso: Efectivo Venezuela
              </h3>
              <p style={{ color: 'white', fontSize: '1rem', lineHeight: 1.6, marginBottom: '2rem' }}>
                Para <strong>Efectivo Venezuela</strong>, debes colocar el monto en <strong>Monto a recibir</strong> solo múltiplos de 10 (ej: 200, 210, 220...). El sistema calculará cuánto debes pagar automáticamente.
              </p>
              
              <button 
                onClick={() => setEfectivoVenNoticeDismissed(true)}
                style={{
                  width: '100%', padding: '1.2rem', borderRadius: '1rem', border: 'none', background: 'var(--primary-color)', color: 'var(--bg-main)', fontWeight: 800, fontSize: '1.1rem', cursor: 'pointer', transition: 'transform 0.2s'
                }}
                onMouseOver={e => e.currentTarget.style.transform = 'scale(1.02)'}
                onMouseOut={e => e.currentTarget.style.transform = 'scale(1)'}
              >
                ¡ENTENDIDO!
              </button>
            </div>
          </div>
        )}

        {/* Explicación dinámica */}
        {origen && destino && isDisponible && (
          <div style={{
            background: 'rgba(16,185,129,0.07)',
            border: '1px solid rgba(16,185,129,0.2)',
            borderRadius: '1rem',
            padding: '1rem 1.5rem',
            marginBottom: '2rem',
          }}>
            <p style={{ fontSize: '0.85rem', color: 'var(--text-low)', marginBottom: '0.2rem' }}>📋 Resumen de tu operación:</p>
            <p style={{ fontWeight: 600, color: 'var(--text-mid)', lineHeight: 1.6 }}>
              {explicacion()}
            </p>
          </div>
        )}

        {/* TASA APLICADA DESTACADA EN EL MEDIO */}
        {origen && destino && isDisponible && (
          <div style={{ textAlign: 'center', marginTop: '-1rem', marginBottom: '2.5rem' }}>
            <div style={{ 
              display: 'inline-flex',
              flexDirection: 'column', 
              alignItems: 'center',
              padding: '0.8rem 2.5rem',
              background: 'rgba(16,185,129,0.12)',
              border: '1px solid rgba(16,185,129,0.4)',
              borderRadius: '1.5rem',
              boxShadow: '0 8px 30px rgba(0,0,0,0.3)'
            }}>
              <span style={{ fontSize: '0.7rem', color: 'var(--text-low)', textTransform: 'uppercase', letterSpacing: '0.15rem', marginBottom: '0.2rem' }}>Tasa Aplicada</span>
              <div style={{ fontSize: 'clamp(1.4rem, 4vw, 2rem)', fontWeight: 900, color: 'var(--primary-color)', fontFamily: 'Manrope, sans-serif' }}>
                 {tasaDisplay.base} = {formatearMonto(tasaDisplay.valor, tasaDisplay.unidad)} <span style={{ fontSize: '0.6em', color: 'var(--secondary-color)' }}>{tasaDisplay.unidad}</span>
              </div>
            </div>
          </div>
        )}

        {/* BANNER ESPECÍFICO PARA EFECTIVO VENEZUELA */}
        {origen && destino && isDisponible && isEfectivoVen(destino) && (
          <div style={{
            background: 'rgba(16,185,129,0.1)',
            border: '1px solid var(--primary-color)',
            borderRadius: '1rem',
            padding: '1.2rem 1.5rem',
            marginBottom: '2rem',
            display: 'flex',
            alignItems: 'center',
            gap: '1rem',
            animation: 'fadeIn 0.4s'
          }}>
            <span style={{ fontSize: '1.5rem' }}>💡</span>
            <div>
              <p style={{ color: 'var(--primary-color)', fontWeight: 800, fontSize: '0.9rem', marginBottom: '0.2rem' }}>Instrucción de Entrega</p>
              <p style={{ color: 'var(--text-mid)', fontSize: '0.85rem' }}>
                Ingrese en <strong>Monto a recibir</strong> valores múltiplos de 10 (ej: 100, 110, 150...). El campo de envío está bloqueado para evitar errores.
              </p>
            </div>
          </div>
        )}

        {/* Resultado */}
        {parsearMonto(montoRecibir) > 0 && origen && destino && isDisponible && (
          <div style={{
            background: 'linear-gradient(135deg, rgba(16,185,129,0.12) 0%, rgba(6,183,127,0.06) 100%)',
            border: '1px solid rgba(16,185,129,0.3)',
            borderRadius: '1.5rem',
            padding: '2rem',
            textAlign: 'center',
            boxShadow: '0 15px 40px rgba(0,0,0,0.4)',
            marginBottom: '2.5rem',
            animation: 'slideUp 0.6s ease-out'
          }}>
            <p style={{
              fontSize: '0.8rem',
              color: 'var(--text-low)',
              textTransform: 'uppercase',
              letterSpacing: '0.2rem',
              marginBottom: '1rem',
              fontWeight: 700
            }}>
              {destino.codigo} RECIBIRÍAS EN {destino.nombre.toUpperCase()}
            </p>
            <p style={{
              fontSize: 'clamp(2rem, 8vw, 4.5rem)',
              fontWeight: 900,
              color: 'var(--primary-color)',
              fontFamily: 'Manrope, sans-serif',
              marginBottom: '0.5rem',
            }}>
              {formatearMonto(parsearMonto(montoRecibir), destino.codigo)} <span style={{ fontSize: '0.5em', color: 'var(--secondary-color)' }}>{destino.codigo}</span>
            </p>



            <div style={{
              marginTop: '1.5rem',
              padding: '0.75rem 1.5rem',
              background: 'rgba(0,0,0,0.2)',
              borderRadius: '2rem',
              display: 'inline-block',
            }}>
              <p style={{ fontSize: '0.85rem', color: 'var(--text-low)' }}>
                ⚡ Transferencia estimada: <strong style={{ color: 'white' }}>15 - 30 minutos</strong> · 💲 <strong style={{ color: 'white' }}>$0 comisión</strong>
              </p>
            </div>
          </div>
        )}

        {(!origen || !destino) && (
          <div style={{ textAlign: 'center', padding: '2rem', color: 'var(--text-low)' }}>
            <p style={{ fontSize: '2rem', marginBottom: '0.5rem' }}>👆</p>
            <p>Selecciona los países de origen y destino para ver la cotización</p>
          </div>
        )}
      </div>

      {/* Nota informativa */}
      <div className="glass" style={{ padding: '1.2rem 1.5rem', display: 'flex', gap: '0.75rem', alignItems: 'center' }}>
        {origen && (
          <>
            <img 
              src={getFlagUrl(origen)}
              alt={origen.nombre}
              style={{ width: isCustomFlag(origen) ? '2rem' : '1.2rem', height: isCustomFlag(origen) ? '2rem' : '0.9rem', objectFit: 'contain' }}
            />
            <span style={{ fontSize: '0.8rem', fontWeight: 800, color: 'var(--text-low)' }}>{origen.codigo}</span>
          </>
        )}
        <p style={{ fontSize: '0.85rem', color: 'var(--text-low)', lineHeight: 1.6 }}>
          Las tasas de cambio se actualizan en tiempo real para ofrecerte el mejor valor del mercado. {esMayor ? 'Grupo JK Mayor' : 'CAMBIOS JK'} garantiza la seguridad y rapidez en cada una de tus operaciones. Los montos calculados ya incluyen todos los diferenciales de cambio aplicables.
        </p>
      </div>

      {/* Modal sub-menú Efectivo Venezuela */}
      {showEVMenu && (
        <div style={{
          position: 'fixed', inset: 0,
          background: 'rgba(0,0,0,0.75)',
          backdropFilter: 'blur(8px)',
          zIndex: 5000,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          padding: '1rem',
        }} onClick={() => { setShowEVMenu(false); setEvEstadoSeleccionado(null); }}>
          <div 
            className="glass" 
            style={{ 
              maxWidth: '480px', width: '100%', padding: '2rem', 
              maxHeight: '80vh', overflowY: 'auto',
              animation: 'fadeIn 0.3s ease'
            }}
            onClick={e => e.stopPropagation()}
          >
            {/* Header */}
            <div style={{ textAlign: 'center', marginBottom: '1.5rem' }}>
              <p style={{ fontSize: '2.5rem', marginBottom: '0.5rem' }}>🇻🇪</p>
              <h3 style={{ fontSize: '1.3rem', color: 'white', marginBottom: '0.3rem' }}>
                {evEstadoSeleccionado ? `${evEstadoSeleccionado.estado}` : 'Efectivo Venezuela'}
              </h3>
              <p style={{ color: 'var(--text-low)', fontSize: '0.85rem' }}>
                {evEstadoSeleccionado ? 'Selecciona la ciudad' : 'Selecciona el estado donde recibes'}
              </p>
            </div>

            {/* Botón Volver (cuando hay estado seleccionado) */}
            {evEstadoSeleccionado && (
              <button
                onClick={() => setEvEstadoSeleccionado(null)}
                style={{
                  background: 'rgba(255,255,255,0.05)',
                  border: '1px solid var(--glass-border)',
                  borderRadius: '0.75rem',
                  color: 'var(--text-low)',
                  padding: '0.5rem 1rem',
                  cursor: 'pointer',
                  fontSize: '0.85rem',
                  marginBottom: '1rem',
                  display: 'flex', alignItems: 'center', gap: '0.3rem'
                }}
              >
                ← Volver a estados
              </button>
            )}

            {/* Lista de Estados */}
            {!evEstadoSeleccionado && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                {evGrupos.map(grupo => (
                  <button
                    key={grupo.estado}
                    onClick={() => {
                      // Si el estado tiene una sola entrada sin ciudad, seleccionar directo
                      if (grupo.entries.length === 1 && !grupo.entries[0].ciudad) {
                        handleEVSelect(grupo.entries[0].pais)
                      } else {
                        setEvEstadoSeleccionado(grupo)
                      }
                    }}
                    style={{
                      background: 'var(--surface-color)',
                      border: '1px solid var(--glass-border)',
                      borderRadius: '1rem',
                      padding: '1rem 1.2rem',
                      color: 'white',
                      cursor: 'pointer',
                      textAlign: 'left',
                      fontSize: '1rem',
                      fontWeight: 600,
                      transition: 'all 0.2s',
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center'
                    }}
                    onMouseEnter={e => {
                      e.target.style.borderColor = 'var(--primary-color)'
                      e.target.style.background = 'var(--surface-high)'
                    }}
                    onMouseLeave={e => {
                      e.target.style.borderColor = 'var(--glass-border)'
                      e.target.style.background = 'var(--surface-color)'
                    }}
                  >
                    <span>📍 {grupo.estado}</span>
                    {grupo.entries.length > 1 || grupo.entries[0].ciudad ? (
                      <span style={{ color: 'var(--text-low)', fontSize: '0.8rem' }}>
                        {grupo.entries.length} {grupo.entries.length === 1 ? 'ciudad' : 'ciudades'} →
                      </span>
                    ) : grupo.ciudadesTexto ? (
                      <span style={{ color: 'var(--text-low)', fontSize: '0.75rem', maxWidth: '50%', textAlign: 'right' }}>
                        {grupo.ciudadesTexto}
                      </span>
                    ) : null}
                  </button>
                ))}
              </div>
            )}

            {/* Lista de Ciudades del estado seleccionado */}
            {evEstadoSeleccionado && (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                {evEstadoSeleccionado.entries.map((entry, idx) => (
                  <button
                    key={idx}
                    onClick={() => handleEVSelect(entry.pais)}
                    style={{
                      background: 'var(--surface-color)',
                      border: '1px solid var(--glass-border)',
                      borderRadius: '1rem',
                      padding: '1rem 1.2rem',
                      color: 'white',
                      cursor: 'pointer',
                      textAlign: 'left',
                      fontSize: '1rem',
                      fontWeight: 600,
                      transition: 'all 0.2s',
                    }}
                    onMouseEnter={e => {
                      e.target.style.borderColor = 'var(--primary-color)'
                      e.target.style.background = 'var(--surface-high)'
                    }}
                    onMouseLeave={e => {
                      e.target.style.borderColor = 'var(--glass-border)'
                      e.target.style.background = 'var(--surface-color)'
                    }}
                  >
                    🏙️ {entry.ciudad || evEstadoSeleccionado.estado}
                    {entry.pais.ciudades && (
                      <span style={{ display: 'block', fontSize: '0.75rem', color: 'var(--text-low)', fontWeight: 400, marginTop: '0.2rem' }}>
                        Disponible en: {entry.pais.ciudades}
                      </span>
                    )}
                  </button>
                ))}
              </div>
            )}

            {/* Botón cerrar */}
            <button
              onClick={() => { setShowEVMenu(false); setEvEstadoSeleccionado(null); }}
              style={{
                marginTop: '1.5rem',
                width: '100%',
                padding: '0.8rem',
                background: 'rgba(255,255,255,0.05)',
                border: '1px solid var(--glass-border)',
                borderRadius: '1rem',
                color: 'var(--text-low)',
                cursor: 'pointer',
                fontSize: '0.9rem'
              }}
            >
              Cancelar
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
