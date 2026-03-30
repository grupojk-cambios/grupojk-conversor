import { useState, useEffect } from 'react'
import { cargarPaises, calcularTasaPublica, calcularConversion, calcularConversionInversa, isCajaDolar, formatearMonto, calcularTasaEnvio, calcularTasaRecibo, getFlagUrl } from './constants'

// Componente interno para selector de países con buscador responsivo
function PaisSelector({ label, paises, selected, onSelect }) {
  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState('')
  const [isMobile, setIsMobile] = useState(window.innerWidth <= 600)

  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth <= 600)
    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [])

  const filtered = paises.filter(p =>
    p.nombre.toLowerCase().includes(search.toLowerCase()) ||
    p.codigo.toLowerCase().includes(search.toLowerCase())
  )

  const renderList = () => (
    <div style={{ maxHeight: isMobile ? '70vh' : '300px', overflowY: 'auto', padding: '0.4rem' }} className="custom-scroll">
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
            style={{ width: '1.8rem', height: '1.2rem', objectFit: 'contain', borderRadius: '3px' }}
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
      <label style={{ display: 'block', fontSize: '0.75rem', letterSpacing: '0.1em', color: 'var(--text-low)', marginBottom: '0.6rem', textTransform: 'uppercase', fontWeight: 700 }}>
        {label}
      </label>
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
          border: open ? '1px solid var(--primary-color)' : '1px solid var(--glass-border)',
          background: 'rgba(255,255,255,0.03)',
          transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)'
        }}
      >
        {selected ? (
          <img 
            src={getFlagUrl(selected)}
            alt={selected.nombre}
            style={{ width: '1.6rem', height: '1.1rem', objectFit: 'contain', borderRadius: '3px' }}
          />
        ) : <span style={{fontSize: '1.2rem'}}>🌐</span>}
        <span style={{ flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', fontWeight: 600, fontSize: '1.05rem' }}>
          {selected ? selected.nombre : 'Elije un país...'}
        </span>
        <span style={{ fontSize: '0.7rem', opacity: 0.6, transition: 'transform 0.4s', transform: open ? 'rotate(180deg)' : 'rotate(0)' }}>▼</span>
      </div>

      {open && (
        <>
          <div 
            className="mobile-overlay" 
            onClick={() => { setOpen(false); setSearch(''); }} 
            style={{ display: isMobile ? 'block' : 'none' }}
          />
          
          <div 
            className={isMobile ? 'bottom-sheet' : ''} 
            style={isMobile ? {} : {
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

export default function Cotizador() {
  const [paises, setPaises] = useState([])
  const [origen, setOrigen] = useState(null)
  const [destino, setDestino] = useState(null)
  const [monto, setMonto] = useState(100)
  const [montoRecibir, setMontoRecibir] = useState(0)
  const [tasaDisplay, setTasaDisplay] = useState({ base: '', valor: 0, unidad: '' })
  const [lastEdited, setLastEdited] = useState('enviar') // 'enviar' | 'recibir'
  const [isMobile, setIsMobile] = useState(window.innerWidth <= 600)

  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth <= 600)
    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [])

  useEffect(() => {
    const todos = cargarPaises()
    setPaises(todos)
    
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
      const tOrigenRecibo = calcularTasaRecibo(origen)
      const tDestinoEnvio = calcularTasaEnvio(destino)
      const isDisp = tOrigenRecibo > 0 && tDestinoEnvio > 0

      // Actualizar tasa display (siempre)
      if (isDisp) {
        const tc = calcularConversion(origen, destino, 1, paises)
        if (isCajaDolar(origen) && !isCajaDolar(destino)) {
          setTasaDisplay({ base: `1 ${origen.codigo}`, valor: tc, unidad: destino.codigo })
        } else if (!isCajaDolar(origen) && isCajaDolar(destino)) {
          const tcInverso = calcularConversionInversa(origen, destino, 1, paises)
          setTasaDisplay({ base: `1 ${destino.codigo}`, valor: tcInverso, unidad: origen.codigo })
        } else {
          setTasaDisplay({ base: `1 ${origen.codigo}`, valor: tc, unidad: destino.codigo })
        }
      }

      // Solo recalcular el campo CONTRARIO al que editó el usuario
      if (lastEdited === 'enviar' && monto >= 0) {
        if (isDisp) {
          const res = calcularConversion(origen, destino, monto, paises)
          setMontoRecibir(Math.round((res + Number.EPSILON) * 100) / 100)
        } else {
          setMontoRecibir(0)
        }
      } else if (lastEdited === 'recibir' && montoRecibir > 0) {
        if (isDisp) {
          const nuevoMonto = calcularConversionInversa(origen, destino, montoRecibir, paises)
          const esCruceDolar = isCajaDolar(origen) && isCajaDolar(destino)
          setMonto(esCruceDolar ? Math.ceil(nuevoMonto) : Math.round((nuevoMonto + Number.EPSILON) * 100) / 100)
        } else {
          setMonto(0)
        }
      }
    }
  }, [origen, destino, paises, monto, montoRecibir, lastEdited])

  const handleMontoEnviarChange = (valStr) => {
    const val = valStr === '' ? 0 : parseFloat(valStr)
    setLastEdited('enviar')
    setMonto(val)
  }

  const handleMontoRecibirChange = (valStr) => {
    const val = valStr === '' ? 0 : parseFloat(valStr)
    setLastEdited('recibir')
    setMontoRecibir(val)
  }

  const handleOrigen = (id) => {
    const p = paises.find(p => p.id === parseInt(id))
    setOrigen(p)
    if (p) localStorage.setItem('jk_last_origen', p.id)
    
    // No permitir mismo país en ambos lados
    if (destino && destino.id === p.id) {
      setDestino(null)
      localStorage.removeItem('jk_last_destino')
    }
  }

  const handleDestino = (id) => {
    const p = paises.find(p => p.id === parseInt(id))
    setDestino(p)
    if (p) localStorage.setItem('jk_last_destino', p.id)

    if (origen && origen.id === p.id) {
      setOrigen(null)
      localStorage.removeItem('jk_last_origen')
    }
  }

  const intercambiar = () => {
    const tempO = origen
    const tempD = destino
    setOrigen(tempD)
    setDestino(tempO)

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
    const resFormateado = formatearMonto(montoRecibir, codDestino)
    const montoEnvFormateado = formatearMonto(monto, codOrigen)
    
    return `Estás enviando ${montoEnvFormateado} ${codOrigen} (${origen.nombre}) → ${resFormateado} ${codDestino} (${destino.nombre})`
  }

  return (
    <div style={{ maxWidth: '900px', margin: '0 auto', padding: '2rem 1.5rem' }}>
      <div style={{ textAlign: 'center', marginBottom: '3rem' }}>
        <h2 style={{ fontSize: 'clamp(1.8rem, 4vw, 2.5rem)', marginBottom: '0.5rem' }}>
          💱 Cotizador de Divisas
        </h2>
        <p style={{ color: 'var(--text-low)' }}>
          Ingresa el monto y selecciona los países para calcular tu cambio al instante
        </p>
      </div>

      <div className="glass" style={{ padding: isMobile ? '1.5rem' : '2.5rem', marginBottom: '2rem' }}>

        {/* Montos */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 280px), 1fr))', gap: '1.25rem', marginBottom: '2rem' }}>
          {/* Monto a Enviar */}
          <div style={{ minWidth: '0' }}>
            <label style={{ display: 'block', fontSize: '0.75rem', letterSpacing: '0.1em', color: 'var(--text-low)', marginBottom: '0.5rem', textTransform: 'uppercase', fontWeight: 700 }}>
              Monto a Enviar
            </label>
            <div style={{ position: 'relative' }}>
              {origen && (
                <span style={{ position: 'absolute', left: '1rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--primary-color)', fontWeight: 800, fontSize: '0.85rem' }}>
                  {origen.codigo}
                </span>
              )}
              <input
                type="number"
                className="input-field"
                value={monto || ''}
                min="0"
                disabled={!isDisponible}
                onChange={e => handleMontoEnviarChange(e.target.value)}
                style={{ paddingLeft: '3.5rem', fontSize: isMobile ? '1.3rem' : '1.5rem', fontWeight: 700, paddingRight: '1rem', opacity: isDisponible ? 1 : 0.5 }}
              />
            </div>
          </div>

          {/* Monto a Recibir */}
          <div style={{ minWidth: '0' }}>
            <label style={{ display: 'block', fontSize: '0.75rem', letterSpacing: '0.1em', color: 'var(--text-low)', marginBottom: '0.5rem', textTransform: 'uppercase', fontWeight: 700 }}>
              Monto a Recibir
            </label>
            <div style={{ position: 'relative' }}>
              {destino && (
                <span style={{ position: 'absolute', left: '1rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--error-color)', fontWeight: 800, fontSize: '0.85rem' }}>
                  {destino.codigo}
                </span>
              )}
              <input
                type="number"
                className="input-field"
                value={montoRecibir || ''}
                min="0"
                disabled={!isDisponible}
                onChange={e => handleMontoRecibirChange(e.target.value)}
                style={{ paddingLeft: '3.5rem', fontSize: isMobile ? '1.3rem' : '1.5rem', fontWeight: 700, paddingRight: '1rem', border: '1px solid rgba(255, 113, 108, 0.3)', opacity: isDisponible ? 1 : 0.5 }}
              />
            </div>
          </div>
        </div>

        {/* Origen + Swap + Destino */}
        <div style={{ 
          display: 'grid', 
          gridTemplateColumns: isMobile ? '1fr' : '1fr auto 1fr', 
          gap: isMobile ? '0.75rem' : '1rem', 
          alignItems: 'end', 
          marginBottom: '2.5rem' 
        }}>

          {/* Origen */}
          <PaisSelector 
            label="País de Origen"
            paises={paises}
            selected={origen}
            onSelect={handleOrigen}
          />

          {/* Botón intercambiar */}
          <div style={{ display: 'flex', justifyContent: 'center', padding: isMobile ? '0.5rem 0' : '0' }}>
            <button
              onClick={intercambiar}
              style={{
                width: isMobile ? '100%' : '3.5rem', 
                height: '3.5rem',
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

          {/* Destino */}
          <PaisSelector 
            label="País de Destino"
            paises={paises}
            selected={destino}
            onSelect={handleDestino}
          />
        </div>

        {/* MENSAJE DE NO DISPONIBLE */}
        {origen && destino && !isDisponible && (
          <div style={{
            background: 'rgba(239, 68, 68, 0.1)',
            border: '1px solid rgba(239, 68, 68, 0.3)',
            borderRadius: '1.5rem',
            padding: '2rem',
            textAlign: 'center',
            marginBottom: '2.5rem',
            animation: 'slideUp 0.6s ease-out'
          }}>
            <p style={{
              fontSize: '1.3rem',
              fontWeight: 700,
              color: 'var(--error-color)',
              marginBottom: '0.5rem',
            }}>
              ⚠️ Conversión no disponible por el momento
            </p>
            <p style={{ color: 'var(--text-low)', fontSize: '0.95rem', lineHeight: 1.6 }}>
              {getMotivoNoDisponible()}<br/>
              <span style={{opacity: 0.6, fontSize: '0.8rem', display: 'inline-block', marginTop: '0.5rem'}}>
                Por favor, intenta más tarde o contacta a nuestros asesores.
              </span>
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

        {/* Resultado */}
        {montoRecibir > 0 && origen && destino && isDisponible && (
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
              {formatearMonto(montoRecibir, destino.codigo)} <span style={{ fontSize: '0.5em', color: 'var(--secondary-color)' }}>{destino.codigo}</span>
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
              style={{ width: '1.2rem', height: '0.9rem', objectFit: 'contain' }}
            />
            <span style={{ fontSize: '0.8rem', fontWeight: 800, color: 'var(--text-low)' }}>{origen.codigo}</span>
          </>
        )}
        <p style={{ fontSize: '0.85rem', color: 'var(--text-low)', lineHeight: 1.6 }}>
          Las tasas de cambio se actualizan en tiempo real para ofrecerte el mejor valor del mercado. GRUPO JK garantiza la seguridad y rapidez en cada una de tus operaciones. Los montos calculados ya incluyen todos los diferenciales de cambio aplicables.
        </p>
      </div>
    </div>
  )
}
