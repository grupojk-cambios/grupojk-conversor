import { useState, useEffect } from 'react'
import { cargarPaises, calcularTasaEnvio, calcularTasaRecibo, formatearMonto } from './constants'

export default function AdminPanel({ onLogout }) {
  const [paises, setPaises] = useState([])
  const [busqueda, setBusqueda] = useState('')
  const [cambiosSinGuardar, setCambiosSinGuardar] = useState(false)
  const [mensaje, setMensaje] = useState(null)
  const [margenGlobalEnvio, setMargenGlobalEnvio] = useState('')
  const [margenGlobalRecibo, setMargenGlobalRecibo] = useState('')

    const [newPais, setNewPais] = useState({
    nombre: '',
    codigo: '',
    moneda: '',
    iso2: '',
    tasaProveedorEnvio: 0,
    margenEnvio: 6,
    tasaProveedorRecibo: 0,
    margenRecibo: 6
  })
  const [showAddModal, setShowAddModal] = useState(false)
  const [showDeleteMode, setShowDeleteMode] = useState(false)

  useEffect(() => {
    setPaises(cargarPaises())
  }, [])

  const handleAgregarPais = () => {
    if (!newPais.nombre || !newPais.codigo) {
      setMensaje({ tipo: 'error', texto: '⚠️ Falta nombre o código ISO' })
      setTimeout(() => setMensaje(null), 3000)
      return
    }
    const nuevo = {
      ...newPais,
      id: Date.now(),
      codigo: newPais.codigo.toUpperCase(),
      iso2: (newPais.iso2 || newPais.codigo.substring(0,2)).toLowerCase(),
      tasaProveedorEnvio: parseFloat(newPais.tasaProveedorEnvio) || 0,
      tasaProveedorRecibo: parseFloat(newPais.tasaProveedorRecibo) || 0,
      margenEnvio: parseFloat(newPais.margenEnvio) || 6,
      margenRecibo: parseFloat(newPais.margenRecibo) || 6
    }
    const listaActualizada = [...paises, nuevo]
    setPaises(listaActualizada)
    localStorage.setItem('jk_paises', JSON.stringify(listaActualizada))
    setShowAddModal(false)
    setNewPais({ nombre: '', codigo: '', moneda: '', iso2: '', tasaProveedorEnvio: 0, margenEnvio: 6, tasaProveedorRecibo: 0, margenRecibo: 6 })
    setMensaje({ tipo: 'success', texto: `✅ ${nuevo.nombre} agregado correctamente` })
    setTimeout(() => setMensaje(null), 3000)
  }

  const handleEliminarPais = (id, nombre) => {
    if (window.confirm(`¿Seguro que quieres eliminar ${nombre}?`)) {
      const nuevos = paises.filter(p => p.id !== id)
      setPaises(nuevos)
      localStorage.setItem('jk_paises', JSON.stringify(nuevos))
      setMensaje({ tipo: 'info', texto: `🗑️ ${nombre} eliminado` })
      setTimeout(() => setMensaje(null), 3000)
    }
  }

  const handleMover = (idx, direccion) => {
    const nuevos = [...paises]
    const targetIdx = direccion === 'up' ? idx - 1 : idx + 1
    if (targetIdx < 0 || targetIdx >= nuevos.length) return

    // Intercambiar
    [nuevos[idx], nuevos[targetIdx]] = [nuevos[targetIdx], nuevos[idx]]
    setPaises(nuevos)
    localStorage.setItem('jk_paises', JSON.stringify(nuevos))
  }

  const handleChange = (id, campo, valor) => {
    const nuevos = paises.map(p => {
      if (p.id === id) {
        return { ...p, [campo]: valor }
      }
      return p
    })
    setPaises(nuevos)
    setCambiosSinGuardar(true)
  }

  const handleGuardar = () => {
    const paisesNumericos = paises.map(p => ({
      ...p,
      tasaProveedorEnvio: parseFloat(p.tasaProveedorEnvio) || 0,
      tasaProveedorRecibo: parseFloat(p.tasaProveedorRecibo) || 0,
      margenEnvio: parseFloat(p.margenEnvio) || 0,
      margenRecibo: parseFloat(p.margenRecibo) || 0
    }))

    localStorage.setItem('jk_paises', JSON.stringify(paisesNumericos))
    setPaises(paisesNumericos)
    setCambiosSinGuardar(false)
    setMensaje({ tipo: 'success', texto: '✅ Tasas publicadas correctamente' })
    setTimeout(() => setMensaje(null), 3000)
  }

  const aplicarMargenGlobal = () => {
    const nuevos = paises.map(p => ({
      ...p,
      ...(margenGlobalEnvio !== '' ? { margenEnvio: parseFloat(margenGlobalEnvio) || 0 } : {}),
      ...(margenGlobalRecibo !== '' ? { margenRecibo: parseFloat(margenGlobalRecibo) || 0 } : {}),
    }))
    setPaises(nuevos)
    setCambiosSinGuardar(true)
    setMensaje({ tipo: 'info', texto: `✅ Margen global aplicado a todos los países` })
    setTimeout(() => setMensaje(null), 3000)
  }

  const paisesFiltrados = paises.filter(p =>
    p.nombre.toLowerCase().includes(busqueda.toLowerCase()) ||
    p.codigo.toLowerCase().includes(busqueda.toLowerCase())
  )

  return (
    <div style={{ maxWidth: '1200px', margin: '0 auto', padding: '2rem 1.5rem', paddingBottom: '6rem' }}>

      {mensaje && (
        <div style={{
          position: 'fixed', top: '2rem', right: '2rem', zIndex: 3000,
          background: mensaje.tipo === 'success' ? 'var(--primary-color)' : (mensaje.tipo === 'error' ? 'var(--error-color)' : '#3b82f6'),
          color: 'white', padding: '1rem 2rem', borderRadius: '1rem', fontWeight: 700,
          boxShadow: '0 10px 40px rgba(0,0,0,0.5)', animation: 'slideIn 0.3s ease-out'
        }}>
          {mensaje.texto}
        </div>
      )}

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2rem', flexWrap: 'wrap', gap: '1rem' }}>
        <div>
          <h2 style={{ fontSize: '2rem', marginBottom: '0.2rem' }}>
            <span style={{ color: 'var(--primary-color)' }}>🔐</span> Panel de Control
          </h2>
          <p style={{ color: 'var(--text-low)' }}>
            Configura tasas de proveedor y márgenes independientes.
          </p>
        </div>

        <div style={{ display: 'flex', gap: '0.8rem', alignItems: 'center' }}>
          {/* Botón Eliminar (Rojo) */}
          <button 
            onClick={() => setShowDeleteMode(!showDeleteMode)} 
            style={{
              background: showDeleteMode ? 'var(--error-color)' : 'rgba(255,113,108,0.1)',
              border: `1px solid var(--error-color)`,
              color: showDeleteMode ? 'white' : 'var(--error-color)',
              padding: '0.6rem 1.2rem', borderRadius: '0.8rem', cursor: 'pointer', fontWeight: 700,
              fontSize: '0.9rem', transition: 'all 0.3s'
            }}
          >
            {showDeleteMode ? '✅ Listo' : '🗑️ Eliminar País'}
          </button>

          {/* Botón Agregar (Verde) - Cuadrito Verde solicitado */}
          <button 
            onClick={() => setShowAddModal(true)} 
            style={{
              background: 'rgba(16,185,129,0.1)',
              border: `1px solid var(--primary-color)`,
              color: 'var(--primary-color)',
              padding: '0.6rem 1.2rem', borderRadius: '0.8rem', cursor: 'pointer', fontWeight: 700,
              fontSize: '0.9rem', transition: 'all 0.3s'
            }}
            onMouseEnter={e => { e.currentTarget.style.background = 'var(--primary-color)'; e.currentTarget.style.color = 'white'; }}
            onMouseLeave={e => { e.currentTarget.style.background = 'rgba(16,185,129,0.1)'; e.currentTarget.style.color = 'var(--primary-color)'; }}
          >
            ➕ Agregar País
          </button>

          <button onClick={onLogout} style={{
            background: 'none', border: '1px solid rgba(255,255,255,0.2)', color: 'var(--text-low)',
            padding: '0.6rem 1.2rem', borderRadius: '0.8rem', cursor: 'pointer', fontWeight: 500,
            fontSize: '0.9rem', transition: 'all 0.3s'
          }}
          onMouseEnter={e => e.target.style.background = 'rgba(255,255,255,0.05)'}
          onMouseLeave={e => e.target.style.background = 'transparent'}
          >
            Cerrar Sesión
          </button>
        </div>
      </div>

      <div className="glass" style={{ padding: '1.5rem 2rem', marginBottom: '2rem', display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '1rem' }}>
        <div className="search-container" style={{ flex: '1', minWidth: '250px' }}>
          <span className="search-icon">🔍</span>
          <input
            type="text"
            className="search-input"
            placeholder="Buscar país o código..."
            value={busqueda}
            onChange={e => setBusqueda(e.target.value)}
          />
        </div>

        {/* Márgenes Globales */}
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.6rem', flexWrap: 'wrap' }}>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
            <label style={{ fontSize: '0.6rem', color: 'var(--primary-color)', textTransform: 'uppercase', fontWeight: 700, letterSpacing: '0.05rem', marginBottom: '0.25rem' }}>📤 Margen Envío %</label>
            <input
              type="number"
              step="0.1"
              placeholder="e.g. 6"
              value={margenGlobalEnvio}
              onChange={e => setMargenGlobalEnvio(e.target.value)}
              style={{
                width: '90px', padding: '0.55rem 0.7rem', borderRadius: '0.75rem',
                background: 'rgba(16,185,129,0.1)', border: '1px solid rgba(16,185,129,0.5)',
                color: 'var(--primary-color)', fontWeight: 700, fontSize: '0.9rem',
                outline: 'none', textAlign: 'center'
              }}
            />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
            <label style={{ fontSize: '0.6rem', color: '#3B82F6', textTransform: 'uppercase', fontWeight: 700, letterSpacing: '0.05rem', marginBottom: '0.25rem' }}>📥 Margen Recibo %</label>
            <input
              type="number"
              step="0.1"
              placeholder="e.g. 4"
              value={margenGlobalRecibo}
              onChange={e => setMargenGlobalRecibo(e.target.value)}
              style={{
                width: '90px', padding: '0.55rem 0.7rem', borderRadius: '0.75rem',
                background: 'rgba(59,130,246,0.1)', border: '1px solid rgba(59,130,246,0.5)',
                color: '#3B82F6', fontWeight: 700, fontSize: '0.9rem',
                outline: 'none', textAlign: 'center'
              }}
            />
          </div>
          <button
            onClick={aplicarMargenGlobal}
            disabled={margenGlobalEnvio === '' && margenGlobalRecibo === ''}
            style={{
              marginTop: '1.2rem',
              padding: '0.55rem 1rem', borderRadius: '0.75rem',
              background: margenGlobalEnvio !== '' || margenGlobalRecibo !== '' ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.03)',
              border: '1px solid rgba(255,255,255,0.2)', color: 'white',
              fontWeight: 700, fontSize: '0.8rem', cursor: 'pointer',
              whiteSpace: 'nowrap', opacity: margenGlobalEnvio === '' && margenGlobalRecibo === '' ? 0.4 : 1
            }}
          >
            ⚡ Aplicar a Todos
          </button>
        </div>

        <button
          className="btn-primary"
          onClick={handleGuardar}
          disabled={!cambiosSinGuardar}
          style={{
            opacity: cambiosSinGuardar ? 1 : 0.5,
            cursor: cambiosSinGuardar ? 'pointer' : 'not-allowed',
            padding: '1rem 2.5rem',
            display: 'flex', alignItems: 'center', gap: '0.5rem'
          }}
        >
          {cambiosSinGuardar ? '⚠️ GUARDAR Y PUBLICAR' : '🚀 TODO ACTUALIZADO'}
        </button>
      </div>

      {mensaje && (
        <div style={{
          padding: '1rem', marginBottom: '2rem', borderRadius: '1rem',
          background: mensaje.tipo === 'success' ? 'rgba(16,185,129,0.1)' : 'rgba(255,113,108,0.1)',
          border: `1px solid ${mensaje.tipo === 'success' ? 'var(--primary-color)' : 'var(--error-color)'}`,
          color: mensaje.tipo === 'success' ? 'var(--primary-color)' : 'var(--error-color)',
          fontWeight: 600, textAlign: 'center'
        }}>
          {mensaje.texto}
        </div>
      )}

      {/* Grid de edición */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(350px, 1fr))', gap: '2rem' }}>
        {paisesFiltrados.map(pais => {
          const tEnvio = calcularTasaEnvio(pais)
          const tRecibo = calcularTasaRecibo(pais)
          const esDolar = pais.codigo === 'USD'

          return (
            <div key={pais.id} className="glass" style={{
              padding: '1.5rem',
              border: '1px solid ' + (esDolar ? 'rgba(255,255,255,0.2)' : 'var(--glass-border)'),
              position: 'relative', overflow: 'hidden'
            }}>
              {/* Header card */}
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '1.5rem' }}>
                <div style={{ position: 'relative' }}>
                  <h3 style={{ fontSize: '1.1rem', marginBottom: '0.1rem' }}>{pais.nombre}</h3>
                  <p style={{ fontSize: '0.75rem', color: 'var(--text-low)', fontFamily: 'monospace' }}>{pais.codigo} · {pais.moneda}</p>
                  
                  {/* Botón de eliminar y mover en la tarjeta */}
                  {showDeleteMode && (
                    <div style={{
                      position: 'absolute', top: '-0.5rem', left: '-0.5rem',
                      display: 'flex', flexDirection: 'column', gap: '0.4rem', zIndex: 10
                    }}>
                      <button 
                         onClick={() => handleEliminarPais(pais.id, pais.nombre)}
                         style={{
                           background: 'var(--error-color)', border: 'none', color: 'white',
                           width: '2.4rem', height: '2.4rem', borderRadius: '50%', cursor: 'pointer',
                           fontSize: '1.2rem', boxShadow: '0 4px 15px rgba(255,113,108,0.4)',
                           display: 'flex', alignItems: 'center', justifyContent: 'center'
                         }}
                         title="Eliminar este país"
                      >
                        🗑️
                      </button>
                      
                      {/* Botones de mover */}
                      <button 
                         onClick={() => handleMover(paises.indexOf(pais), 'up')}
                         disabled={paises.indexOf(pais) === 0}
                         style={{
                           background: 'rgba(255,255,255,0.1)', border: '1px solid rgba(255,255,255,0.2)', color: 'white',
                           width: '2.4rem', height: '2.4rem', borderRadius: '50%', cursor: 'pointer',
                           fontSize: '1rem', backdropFilter: 'blur(5px)', opacity: paises.indexOf(pais) === 0 ? 0.3 : 1
                         }}
                      >
                        ↑
                      </button>
                      <button 
                         onClick={() => handleMover(paises.indexOf(pais), 'down')}
                         disabled={paises.indexOf(pais) === paises.length - 1}
                         style={{
                           background: 'rgba(255,255,255,0.1)', border: '1px solid rgba(255,255,255,0.2)', color: 'white',
                           width: '2.4rem', height: '2.4rem', borderRadius: '50%', cursor: 'pointer',
                           fontSize: '1rem', backdropFilter: 'blur(5px)', opacity: paises.indexOf(pais) === paises.length - 1 ? 0.3 : 1
                         }}
                      >
                        ↓
                      </button>
                    </div>
                  )}
                </div>
                <div style={{ 
                  width: '4rem', 
                  height: '4rem', 
                  display: 'flex', 
                  alignItems: 'center', 
                  justifyContent: 'center',
                  background: 'rgba(255,255,255,0.05)',
                  borderRadius: '1rem',
                  border: '1px solid rgba(255,255,255,0.1)',
                  overflow: 'hidden'
                }}>
                  <img 
                    src={`https://flagcdn.com/w80/${(pais.iso2 || pais.codigo.substring(0,2)).toLowerCase()}.png`}
                    alt={pais.nombre}
                    style={{ width: '70%', height: '70%', objectFit: 'contain' }}
                  />
                </div>
              </div>

              {/* Gestión de ENVÍO */}
              <div style={{ marginBottom: '1.5rem', padding: '1rem', background: 'rgba(255,255,255,0.03)', borderRadius: '1rem' }}>
                <p style={{ fontSize: '0.75rem', fontWeight: 700, color: 'var(--primary-color)', textTransform: 'uppercase', marginBottom: '0.8rem', borderLeft: '3px solid var(--primary-color)', paddingLeft: '0.5rem' }}>
                  📤 Gestión Envío (Venta)
                </p>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.8rem' }}>
                  <div>
                    <label style={{ display: 'block', fontSize: '0.65rem', color: 'var(--text-low)', marginBottom: '0.3rem' }}>PR. ENVÍO</label>
                    <input
                      type="number"
                      className="input-field"
                      style={{ padding: '0.6rem', background: 'rgba(0,0,0,0.3)', fontSize: '0.9rem' }}
                      value={pais.tasaProveedorEnvio ?? ''}
                      onChange={e => handleChange(pais.id, 'tasaProveedorEnvio', e.target.value)}
                    />
                  </div>
                  <div>
                    <label style={{ display: 'block', fontSize: '0.65rem', color: 'var(--text-low)', marginBottom: '0.3rem' }}>GANANCIA %</label>
                    <input
                      type="number"
                      className="input-field"
                      style={{ padding: '0.6rem', background: 'rgba(0,0,0,0.3)', fontSize: '0.9rem' }}
                      value={pais.margenEnvio ?? ''}
                      step="0.1"
                      onChange={e => handleChange(pais.id, 'margenEnvio', e.target.value)}
                    />
                  </div>
                </div>
                <div style={{ marginTop: '0.5rem', textAlign: 'right', fontSize: '0.8rem', color: 'rgba(255,255,255,0.5)' }}>
                  Pub Envío: <span style={{ color: 'var(--primary-color)', fontWeight: 700 }}>{formatearMonto(tEnvio, pais.codigo)}</span>
                </div>
              </div>

              {/* Gestión de RECIBO */}
              <div style={{ padding: '1rem', background: 'rgba(255,255,255,0.03)', borderRadius: '1rem' }}>
                <p style={{ fontSize: '0.75rem', fontWeight: 700, color: '#3B82F6', textTransform: 'uppercase', marginBottom: '0.8rem', borderLeft: '3px solid #3B82F6', paddingLeft: '0.5rem' }}>
                  📥 Gestión Recibo (Compra)
                </p>
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.8rem' }}>
                  <div>
                    <label style={{ display: 'block', fontSize: '0.65rem', color: 'var(--text-low)', marginBottom: '0.3rem' }}>PR. RECIBO</label>
                    <input
                      type="number"
                      className="input-field"
                      style={{ padding: '0.6rem', background: 'rgba(0,0,0,0.3)', fontSize: '0.9rem' }}
                      value={pais.tasaProveedorRecibo ?? ''}
                      onChange={e => handleChange(pais.id, 'tasaProveedorRecibo', e.target.value)}
                    />
                  </div>
                  <div>
                    <label style={{ display: 'block', fontSize: '0.65rem', color: 'var(--text-low)', marginBottom: '0.3rem' }}>GANANCIA %</label>
                    <input
                      type="number"
                      className="input-field"
                      style={{ padding: '0.6rem', background: 'rgba(0,0,0,0.3)', fontSize: '0.9rem' }}
                      value={pais.margenRecibo ?? ''}
                      step="0.1"
                      onChange={e => handleChange(pais.id, 'margenRecibo', e.target.value)}
                    />
                  </div>
                </div>
                <div style={{ marginTop: '0.5rem', textAlign: 'right', fontSize: '0.8rem', color: 'rgba(255,255,255,0.5)' }}>
                  Pub Recibo: <span style={{ color: '#3B82F6', fontWeight: 700 }}>{formatearMonto(tRecibo, pais.codigo)}</span>
                </div>
              </div>

            </div>
          )
        })}
      </div>

      {paisesFiltrados.length === 0 && (
        <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--text-low)' }}>
          No se encontraron coincidencias
        </div>
      )}

      {/* Floating Action Bar si hay cambios */}
      {cambiosSinGuardar && (
        <div style={{
          position: 'fixed', bottom: '2rem', left: '50%', transform: 'translateX(-50%)',
          background: 'rgba(6,25,52,0.9)', backdropFilter: 'blur(10px)',
          border: '1px solid var(--primary-color)', borderRadius: '3rem',
          padding: '1rem 2rem', display: 'flex', alignItems: 'center', gap: '2rem',
          boxShadow: '0 10px 30px rgba(0,0,0,0.5), 0 0 20px rgba(16,185,129,0.2)',
          zIndex: 100
        }}>
          <span style={{ color: 'white', fontWeight: 600 }}>⚠️ Tienes cambios sin publicar</span>
          <button className="btn-primary" onClick={handleGuardar} style={{ padding: '0.8rem 2rem' }}>
            Guardar y Publicar
          </button>
        </div>
      )}
      {/* MODAL PARA AGREGAR PAÍS */}
      {showAddModal && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.85)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 5000,
          backdropFilter: 'blur(10px)', padding: '1.5rem'
        }}>
          <div className="glass" style={{ 
            maxWidth: '500px', width: '100%', padding: '2.5rem', 
            borderRadius: '2rem', border: '1px solid rgba(16,185,129,0.3)',
            boxShadow: '0 25px 50px -12px rgba(0,0,0,0.5)'
          }}>
            <h3 style={{ fontSize: '1.8rem', marginBottom: '1.5rem', display: 'flex', alignItems: 'center', gap: '0.8rem' }}>
              <span style={{ fontSize: '2rem' }}>🌍</span> Nuevo País
            </h3>
            
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1.2rem', marginBottom: '1.5rem' }}>
              <div style={{ gridColumn: 'span 2' }}>
                <label style={{ display: 'block', fontSize: '0.75rem', color: 'var(--text-low)', marginBottom: '0.4rem' }}>Nombre del País (ej: Uruguay)</label>
                <input 
                  className="input-field"
                  value={newPais.nombre}
                  onChange={e => setNewPais({ ...newPais, nombre: e.target.value })}
                  placeholder="ej: Uruguay"
                />
              </div>
              <div>
                <label style={{ display: 'block', fontSize: '0.75rem', color: 'var(--text-low)', marginBottom: '0.4rem' }}>Código ISO (ej: UYU)</label>
                <input 
                  className="input-field"
                  value={newPais.codigo}
                  onChange={e => setNewPais({ ...newPais, codigo: e.target.value })}
                  placeholder="ej: UYU"
                />
              </div>
              <div>
                <label style={{ display: 'block', fontSize: '0.75rem', color: 'var(--text-low)', marginBottom: '0.4rem' }}>ISO2 Bandera (ej: uy)</label>
                <input 
                  className="input-field"
                  value={newPais.iso2}
                  onChange={e => setNewPais({ ...newPais, iso2: e.target.value })}
                  placeholder="ej: uy"
                />
              </div>
              <div style={{ gridColumn: 'span 2' }}>
                <label style={{ display: 'block', fontSize: '0.75rem', color: 'var(--text-low)', marginBottom: '0.4rem' }}>Nombre de Moneda (ej: Peso Uruguayo)</label>
                <input 
                  className="input-field"
                  value={newPais.moneda}
                  onChange={e => setNewPais({ ...newPais, moneda: e.target.value })}
                  placeholder="ej: Peso Uruguayo"
                />
              </div>
            </div>

            <div style={{ display: 'flex', gap: '1rem', marginTop: '2rem' }}>
              <button 
                onClick={() => setShowAddModal(false)}
                style={{ flex: 1, padding: '1rem', borderRadius: '1rem', background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)', color: 'white', fontWeight: 600, cursor: 'pointer' }}
              >
                Cancelar
              </button>
              <button 
                className="btn-primary"
                onClick={handleAgregarPais}
                style={{ flex: 2, padding: '1rem' }}
              >
                🚀 Crear País
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
