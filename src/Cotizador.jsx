import { useState, useEffect } from 'react'
import { cargarPaises, calcularTasaPublica, calcularConversion, formatearMonto, calcularTasaEnvio, calcularTasaRecibo } from './constants'

// Componente interno para selector de países con buscador
function PaisSelector({ label, paises, selected, onSelect }) {
  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState('')

  const filtered = paises.filter(p =>
    p.nombre.toLowerCase().includes(search.toLowerCase()) ||
    p.codigo.toLowerCase().includes(search.toLowerCase())
  )

  // Cerrar al hacer clic fuera (simplificado con un backdrop invisible)
  return (
    <div style={{ position: 'relative', minWidth: '0' }}>
      <label style={{ display: 'block', fontSize: '0.8rem', letterSpacing: '0.1em', color: 'var(--text-low)', marginBottom: '0.5rem', textTransform: 'uppercase', fontWeight: 600 }}>
        {label}
      </label>
      <div 
        onClick={() => setOpen(!open)}
        className="input-field"
        style={{ 
          cursor: 'pointer', 
          display: 'flex', 
          alignItems: 'center', 
          gap: '0.5rem',
          height: '3.5rem',
          padding: '0 1rem',
          border: open ? '1px solid var(--primary-color)' : '1px solid var(--glass-border)',
          transition: 'all 0.3s'
        }}
      >
        {selected ? (
          <img 
            src={`https://flagcdn.com/w40/${(selected.iso2 || selected.codigo.substring(0,2)).toLowerCase()}.png`}
            alt={selected.nombre}
            style={{ width: '1.4rem', height: '1rem', objectFit: 'contain', borderRadius: '2px' }}
          />
        ) : '🌐'}
        <span style={{ flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', fontWeight: 500 }}>
          {selected ? `${selected.nombre} (${selected.codigo})` : 'Seleccionar...'}
        </span>
        <span style={{ fontSize: '0.8rem', opacity: 0.5, transition: 'transform 0.3s', transform: open ? 'rotate(180deg)' : 'rotate(0)' }}>▼</span>
      </div>

      {open && (
        <>
          <div onClick={() => setOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 90 }} />
          <div style={{
            position: 'absolute', top: '100%', left: 0, right: 0, zIndex: 100,
            background: 'var(--glass-bg)', backdropFilter: 'blur(20px)',
            border: '1px solid var(--glass-border)', borderRadius: '1rem',
            marginTop: '0.5rem', overflow: 'hidden',
            boxShadow: '0 20px 40px rgba(0,0,0,0.6)',
            animation: 'fadeIn 0.2s ease-out'
          }}>
            <div style={{ padding: '0.8rem', borderBottom: '1px solid rgba(255,255,255,0.08)', background: 'rgba(0,0,0,0.2)' }}>
              <input 
                autoFocus
                type="text"
                placeholder="🔍 Buscar país o ISO..."
                value={search}
                onChange={e => setSearch(e.target.value)}
                onClick={e => e.stopPropagation()}
                style={{
                  width: '100%', padding: '0.7rem 1rem', background: 'rgba(255,255,255,0.05)',
                  border: '1px solid rgba(255,255,255,0.15)', borderRadius: '0.75rem',
                  color: 'white', outline: 'none', fontSize: '0.9rem'
                }}
              />
            </div>
            <div style={{ maxHeight: '300px', overflowY: 'auto', padding: '0.4rem' }} className="custom-scroll">
              {filtered.map(p => (
                <div 
                  key={p.id}
                  onClick={() => { onSelect(p.id); setOpen(false); setSearch(''); }}
                  style={{
                    padding: '0.8rem 1rem', cursor: 'pointer',
                    display: 'flex', alignItems: 'center', gap: '0.8rem',
                    borderRadius: '0.7rem',
                    background: selected?.id === p.id ? 'rgba(16,185,129,0.15)' : 'transparent',
                    transition: 'all 0.2s',
                    marginBottom: '2px'
                  }}
                  onMouseEnter={e => e.currentTarget.style.background = 'rgba(255,255,255,0.08)'}
                  onMouseLeave={e => e.currentTarget.style.background = selected?.id === p.id ? 'rgba(16,185,129,0.15)' : 'transparent'}
                >
                  <img 
                    src={`https://flagcdn.com/w40/${(p.iso2 || p.codigo.substring(0,2)).toLowerCase()}.png`}
                    alt={p.nombre}
                    style={{ width: '1.4rem', height: '1rem', objectFit: 'contain', borderRadius: '2px' }}
                  />
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: '0.95rem', fontWeight: selected?.id === p.id ? 700 : 400 }}>{p.nombre}</div>
                    <div style={{ fontSize: '0.7rem', color: 'var(--text-low)', textTransform: 'uppercase' }}>{p.moneda}</div>
                  </div>
                  <span style={{ fontSize: '0.75rem', fontWeight: 800, color: 'var(--primary-color)', opacity: 0.8, background: 'rgba(16,185,129,0.1)', padding: '0.2rem 0.5rem', borderRadius: '0.4rem', fontFamily: 'monospace' }}>
                    {p.codigo}
                  </span>
                </div>
              ))}
              {filtered.length === 0 && (
                <div style={{ padding: '2rem 1rem', textAlign: 'center', color: 'var(--text-low)', fontSize: '0.85rem' }}>
                  No se encontró nada para "<strong>{search}</strong>"
                </div>
              )}
            </div>
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

  useEffect(() => {
    const todos = cargarPaises()
    setPaises(todos)
    // Por defecto: Ecuador (USD) → Colombia (COP)
    const ecuador = todos.find(p => p.id === 9)  // Ecuador USD
    const colombia = todos.find(p => p.id === 8)  // Colombia COP
    setOrigen(ecuador)
    setDestino(colombia)
  }, [])

  useEffect(() => {
    if (origen && destino && monto >= 0 && paises.length > 0) {
      const res = calcularConversion(origen, destino, monto, paises)
      const resRedondeado = Math.round((res + Number.EPSILON) * 100) / 100
      setMontoRecibir(resRedondeado)
      
      // Tasa cruzada: cuántas unidades de destino por 1 unidad de origen
      const tc = calcularConversion(origen, destino, 1, paises)
      
      // Personalizar display de tasa según USD
      if (origen.codigo === 'USD' && destino.codigo !== 'USD') {
        setTasaDisplay({ base: '1 USD', valor: calcularTasaEnvio(destino), unidad: destino.codigo })
      } else if (destino.codigo === 'USD' && origen.codigo !== 'USD') {
        setTasaDisplay({ base: '1 USD', valor: calcularTasaRecibo(origen), unidad: origen.codigo })
      } else {
        setTasaDisplay({ base: `1 ${origen.codigo}`, valor: tc, unidad: destino.codigo })
      }
    }
  }, [origen, destino, paises])

  const handleMontoEnviarChange = (valStr) => {
    const val = valStr === '' ? 0 : parseFloat(valStr)
    setMonto(val)
    if (origen && destino && paises.length > 0) {
      const res = calcularConversion(origen, destino, val, paises)
      const resRed = Math.round((res + Number.EPSILON) * 100) / 100
      setMontoRecibir(resRed)
    }
  }

  const handleMontoRecibirChange = (valStr) => {
    const val = valStr === '' ? 0 : parseFloat(valStr)
    setMontoRecibir(val)
    if (origen && destino && paises.length > 0) {
      const tOrigenRecibo = calcularTasaRecibo(origen)
      const tDestinoEnvio = calcularTasaEnvio(destino)
      if (tDestinoEnvio > 0) {
        const nuevoMontoEnviar = (val / tDestinoEnvio) * tOrigenRecibo
        const montoEnvRed = Math.round((nuevoMontoEnviar + Number.EPSILON) * 100) / 100
        setMonto(montoEnvRed)
      }
    }
  }

  const handleOrigen = (id) => {
    const p = paises.find(p => p.id === parseInt(id))
    setOrigen(p)
    // No permitir mismo país en ambos lados
    if (destino && destino.id === p.id) setDestino(null)
  }

  const handleDestino = (id) => {
    const p = paises.find(p => p.id === parseInt(id))
    setDestino(p)
    if (origen && origen.id === p.id) setOrigen(null)
  }

  const intercambiar = () => {
    const temp = origen
    setOrigen(destino)
    setDestino(temp)
  }

  const tasaPublicaOrigen = origen ? calcularTasaPublica(origen) : 0
  const tasaPublicaDestino = destino ? calcularTasaPublica(destino) : 0

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

      <div className="glass" style={{ padding: '2.5rem', marginBottom: '2rem' }}>

        {/* Montos */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '1.5rem', marginBottom: '2rem' }}>
          {/* Monto a Enviar */}
          <div style={{ minWidth: '0' }}>
            <label style={{ display: 'block', fontSize: '0.8rem', letterSpacing: '0.1em', color: 'var(--text-low)', marginBottom: '0.5rem', textTransform: 'uppercase', fontWeight: 600 }}>
              Monto a Enviar
            </label>
            <div style={{ position: 'relative' }}>
              <span style={{ position: 'absolute', left: '1.2rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--primary-color)', fontWeight: 800, fontSize: '1.3rem' }}>$</span>
              <input
                type="number"
                className="input-field"
                value={monto || ''}
                min="0"
                onChange={e => handleMontoEnviarChange(e.target.value)}
                style={{ paddingLeft: '2.5rem', fontSize: '1.5rem', fontWeight: 700, paddingRight: '3.5rem' }}
              />
              {origen && (
                <span style={{ position: 'absolute', right: '1rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-low)', fontSize: '0.7rem', fontWeight: 700 }}>
                  {origen.codigo}
                </span>
              )}
            </div>
          </div>

          {/* Monto a Recibir */}
          <div style={{ minWidth: '0' }}>
            <label style={{ display: 'block', fontSize: '0.8rem', letterSpacing: '0.1em', color: 'var(--text-low)', marginBottom: '0.5rem', textTransform: 'uppercase', fontWeight: 600 }}>
              Monto a Recibir
            </label>
            <div style={{ position: 'relative' }}>
              <span style={{ position: 'absolute', left: '1.2rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--error-color)', fontWeight: 800, fontSize: '1.3rem' }}>$</span>
              <input
                type="number"
                className="input-field"
                value={montoRecibir || ''}
                min="0"
                onChange={e => handleMontoRecibirChange(e.target.value)}
                style={{ paddingLeft: '2.5rem', fontSize: '1.5rem', fontWeight: 700, paddingRight: '3.5rem', border: '1px solid rgba(255, 113, 108, 0.3)' }}
              />
              {destino && (
                <span style={{ position: 'absolute', right: '1rem', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-low)', fontSize: '0.7rem', fontWeight: 700 }}>
                  {destino.codigo}
                </span>
              )}
            </div>
          </div>
        </div>

        {/* Origen + Swap + Destino */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr auto 1fr', gap: '1rem', alignItems: 'end', marginBottom: '2rem' }}>

          {/* Origen */}
          <PaisSelector 
            label="País de Origen"
            paises={paises}
            selected={origen}
            onSelect={handleOrigen}
          />

          {/* Botón intercambiar */}
          <button
            onClick={intercambiar}
            style={{
              width: '3rem', height: '3rem',
              background: 'rgba(16,185,129,0.1)',
              border: '1px solid rgba(16,185,129,0.3)',
              borderRadius: '50%',
              cursor: 'pointer',
              fontSize: '1.3rem',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              transition: 'all 0.3s',
              margin: 'auto 0',
            }}
            title="Intercambiar países"
            onMouseEnter={e => e.currentTarget.style.background = 'rgba(16,185,129,0.25)'}
            onMouseLeave={e => e.currentTarget.style.background = 'rgba(16,185,129,0.1)'}
          >
            ⇄
          </button>

          {/* Destino */}
          <PaisSelector 
            label="País de Destino"
            paises={paises}
            selected={destino}
            onSelect={handleDestino}
          />
        </div>

        {/* TASA APLICADA DESTACADA EN EL MEDIO */}
        {origen && destino && (
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
        {origen && destino && (
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
        {montoRecibir > 0 && origen && destino && (
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
              src={`https://flagcdn.com/w40/${(origen.iso2 || origen.codigo.substring(0,2)).toLowerCase()}.png`}
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
