import { useState, useEffect } from 'react'
import { supabase } from './lib/supabase'

export default function AdminPanel({ onLogout }) {
  const [transacciones, setTransacciones] = useState([])
  const [busqueda, setBusqueda] = useState('')
  const [loading, setLoading] = useState(true)
  const [mensaje, setMensaje] = useState(null)

  const estadosDisponibles = ['Pendiente', 'Verificando', 'Completada', 'Cancelada']

  useEffect(() => {
    fetchTransacciones()
    
    const subscription = supabase
      .channel('transacciones_actualizaciones')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'transacciones' }, () => {
        fetchTransacciones()
      })
      .subscribe()

    return () => {
      supabase.removeChannel(subscription)
    }
  }, [])

  const fetchTransacciones = async () => {
    try {
      const { data, error } = await supabase
        .from('transacciones')
        .select('*')
        .order('fecha', { ascending: false })

      if (error) throw error
      setTransacciones(data || [])
    } catch (error) {
      console.error('Error al cargar transacciones:', error)
      mostrarMensaje('error', '❌ Error al conectar con la base de datos')
    } finally {
      setLoading(false)
    }
  }

  const actualizarEstado = async (id, nuevoEstado) => {
    try {
      const { error } = await supabase
        .from('transacciones')
        .update({ estado: nuevoEstado })
        .eq('id', id)

      if (error) throw error
      mostrarMensaje('success', `✅ Estado cambiado a ${nuevoEstado}`)
      
      // Actualización optimista
      setTransacciones(prev => prev.map(t => t.id === id ? { ...t, estado: nuevoEstado } : t))
    } catch (error) {
      console.error('Error updating:', error)
      mostrarMensaje('error', '❌ Error al actualizar el estado')
    }
  }

  const mostrarMensaje = (tipo, texto) => {
    setMensaje({ tipo, texto })
    setTimeout(() => setMensaje(null), 3000)
  }

  const formatearMonto = (monto) => Number(monto).toLocaleString('es-ES', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  
  const formatearFecha = (fechaUtc) => {
    const d = new Date(fechaUtc)
    return `${d.toLocaleDateString('es-ES')} - ${d.toLocaleTimeString('es-ES', {hour: '2-digit', minute:'2-digit'})}`
  }

  const getEstadoColor = (estado) => {
    switch(estado) {
      case 'Pendiente': return { bg: 'rgba(234, 179, 8, 0.1)', color: '#eab308' }
      case 'Verificando': return { bg: 'rgba(59, 130, 246, 0.1)', color: '#3b82f6' }
      case 'Completada': return { bg: 'rgba(16, 185, 129, 0.1)', color: '#10b981' }
      case 'Cancelada': return { bg: 'rgba(239, 68, 68, 0.1)', color: '#ef4444' }
      default: return { bg: 'rgba(255,255,255,0.1)', color: 'white' }
    }
  }

  const handleSubirComprobanteAdmin = async (id, codigo, file) => {
    if (!file) return
    
    try {
      // Subir imagen a Supabase Storage
      const fileExt = file.name.split('.').pop()
      const fileName = `admin-${codigo}-${Date.now()}.${fileExt}`
      const filePath = `admin/${fileName}`

      const { error: uploadError } = await supabase.storage
        .from('comprobantes')
        .upload(filePath, file)

      if (uploadError) throw uploadError

      const { data: { publicUrl: url } } = supabase.storage
        .from('comprobantes')
        .getPublicUrl(filePath)

      // Actualizar registro en la tabla y marcar como completada
      const { error: updateError } = await supabase
        .from('transacciones')
        .update({
          comprobante_admin: url,
          estado: 'Completada'
        })
        .eq('id', id)

      if (updateError) throw updateError

      mostrarMensaje('success', '✅ Comprobante enviado y transacción completada')
      fetchTransacciones()
    } catch (error) {
      console.error('Error al subir comprobante admin:', error)
      mostrarMensaje('error', '❌ Error al subir el comprobante')
    }
  }

  const transaccionesFiltradas = transacciones.filter(t => {
    const p = busqueda.toLowerCase()
    const nombreCompleto = `${t.nombre_cliente} ${t.apellido_cliente}`.toLowerCase()
    return (
      nombreCompleto.includes(p) ||
      (t.codigo && t.codigo.toLowerCase().includes(p)) ||
      (t.whatsapp_cliente && t.whatsapp_cliente.includes(p))
    )
  })

  // Estilos compartidos
  const tableHeaderStyle = {
    padding: '1rem',
    textAlign: 'left',
    fontSize: '0.8rem',
    color: 'var(--text-low)',
    textTransform: 'uppercase',
    letterSpacing: '0.05rem',
    borderBottom: '1px solid rgba(255,255,255,0.1)'
  }

  const tableCellStyle = {
    padding: '1rem',
    borderBottom: '1px solid rgba(255,255,255,0.05)',
    verticalAlign: 'middle'
  }

  return (
    <div style={{ maxWidth: '1400px', margin: '0 auto', padding: '2rem 1.5rem', paddingBottom: '6rem' }}>

      {mensaje && (
        <div style={{
          position: 'fixed', top: '2rem', right: '2rem', zIndex: 3000,
          background: mensaje.tipo === 'success' ? 'var(--primary-color)' : 'var(--error-color)',
          color: 'white', padding: '1rem 2rem', borderRadius: '1rem', fontWeight: 700,
          boxShadow: '0 10px 40px rgba(0,0,0,0.5)', animation: 'slideIn 0.3s ease-out'
        }}>
          {mensaje.texto}
        </div>
      )}

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2rem', flexWrap: 'wrap', gap: '1rem' }}>
        <div>
          <h2 style={{ fontSize: '2rem', marginBottom: '0.2rem' }}>
            <span style={{ color: 'var(--primary-color)' }}>📊</span> Control de Transacciones
          </h2>
          <p style={{ color: 'var(--text-low)' }}>
            Revisa y actualiza el estado de las operaciones de tus clientes en tiempo real.
          </p>
        </div>

        <div style={{ display: 'flex', gap: '0.8rem' }}>
          <button 
            onClick={() => window.location.hash = '#/inicio'} 
            style={{
              background: 'rgba(16, 185, 129, 0.1)', 
              border: '1px solid var(--primary-color)', 
              color: 'var(--primary-color)',
              padding: '0.6rem 1.2rem', 
              borderRadius: '0.8rem', 
              cursor: 'pointer', 
              fontWeight: 700,
              fontSize: '0.9rem', 
              transition: 'all 0.3s'
            }}
            onMouseEnter={e => e.currentTarget.style.background = 'rgba(16, 185, 129, 0.2)'}
            onMouseLeave={e => e.currentTarget.style.background = 'rgba(16, 185, 129, 0.1)'}
          >
            🏠 Ir a Inicio
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
            placeholder="Buscar por código, nombre o WhatsApp..."
            value={busqueda}
            onChange={e => setBusqueda(e.target.value)}
          />
        </div>
      </div>

      <div className="glass" style={{ overflowX: 'auto', borderRadius: '1.5rem', padding: '1rem' }}>
        {loading ? (
          <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--text-low)' }}>Cargando transacciones...</div>
        ) : transaccionesFiltradas.length === 0 ? (
          <div style={{ padding: '3rem', textAlign: 'center', color: 'var(--text-low)' }}>No se encontraron transacciones.</div>
        ) : (
          <table style={{ width: '100%', borderCollapse: 'collapse', minWidth: '900px' }}>
            <thead>
              <tr>
                <th style={tableHeaderStyle}>Código</th>
                <th style={tableHeaderStyle}>Fecha / Hora</th>
                <th style={tableHeaderStyle}>Cliente</th>
                <th style={tableHeaderStyle}>Origen (Envío)</th>
                <th style={tableHeaderStyle}>Destino (Recibo)</th>
                <th style={tableHeaderStyle}>P2P (Cliente)</th>
                <th style={tableHeaderStyle}>Estado / Acción</th>
              </tr>
            </thead>
            <tbody>
              {transaccionesFiltradas.map(t => {
                const statusColors = getEstadoColor(t.estado)
                return (
                  <tr key={t.id} style={{ transition: 'background 0.2s' }} onMouseEnter={e => e.currentTarget.style.background = 'rgba(255,255,255,0.02)'} onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
                    {/* Código */}
                    <td style={tableCellStyle}>
                      <span style={{ fontWeight: 700, color: 'var(--primary-color)', fontFamily: 'monospace' }}>{t.codigo}</span>
                      {t.tipo_cliente === 'Mayorista' && (
                        <div style={{ fontSize: '0.65rem', color: '#3b82f6', background: 'rgba(59,130,246,0.1)', padding: '0.1rem 0.4rem', borderRadius: '0.3rem', display: 'inline-block', marginTop: '0.3rem' }}>MAYORISTA</div>
                      )}
                    </td>
                    
                    {/* Fecha y Hora */}
                    <td style={tableCellStyle}>
                      <span style={{ fontSize: '0.85rem', color: 'var(--text-low)' }}>{formatearFecha(t.fecha)}</span>
                    </td>
                    
                    {/* Detalles del Cliente */}
                    <td style={tableCellStyle}>
                      <div style={{ fontWeight: 600 }}>{t.nombre_cliente} {t.apellido_cliente}</div>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem', marginTop: '0.4rem' }}>
                        <a 
                          href={`https://wa.me/${t.whatsapp_cliente.replace(/\+/g, '').replace(/ /g, '')}?text=Hola%20${t.nombre_cliente}%2C%20le%20saluda%20Kelvin%20de%20JK%20CONVERSOR%20sobre%20su%20operaci%C3%B3n%20%23${t.codigo}`} 
                          target="_blank" rel="noreferrer" 
                          style={{ textDecoration: 'none', color: 'white', background: '#25D366', padding: '0.3rem 0.6rem', borderRadius: '0.4rem', fontSize: '0.7rem', display: 'flex', alignItems: 'center', gap: '4px', fontWeight: 700, justifyContent: 'center' }}
                        >
                          🟢 Kelvin
                        </a>
                        <a 
                          href={`https://wa.me/${t.whatsapp_cliente.replace(/\+/g, '').replace(/ /g, '')}?text=Hola%20${t.nombre_cliente}%2C%20le%20saluda%20Dario%20de%20JK%20CONVERSOR%20sobre%20su%20operaci%C3%B3n%20%23${t.codigo}`} 
                          target="_blank" rel="noreferrer" 
                          style={{ textDecoration: 'none', color: 'white', background: '#25D366', padding: '0.3rem 0.6rem', borderRadius: '0.4rem', fontSize: '0.7rem', display: 'flex', alignItems: 'center', gap: '4px', fontWeight: 700, justifyContent: 'center' }}
                        >
                          🟢 Dario
                        </a>
                        <div style={{ fontSize: '0.65rem', color: 'var(--text-low)', textAlign: 'center', marginTop: '0.2rem' }}>
                          WhatsApp: {t.whatsapp_cliente}
                        </div>
                        <div style={{ fontSize: '0.75rem', color: 'white', textAlign: 'center', fontWeight: 700, marginTop: '0.1rem', textTransform: 'uppercase' }}>
                          {t.nombre_cliente} {t.apellido_cliente}
                        </div>
                      </div>
                    </td>

                    {/* Origen */}
                    <td style={tableCellStyle}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                        <div>
                          <p style={{ fontWeight: 700, fontSize: '0.95rem', margin: 0 }}>{formatearMonto(t.monto_enviado)} <span style={{fontSize: '0.8rem', color: 'var(--text-low)'}}>{t.moneda_origen}</span></p>
                          <p style={{ fontSize: '0.75rem', color: 'var(--text-low)', margin: 0, marginTop: '0.1rem' }}>{t.pais_origen}</p>
                        </div>
                      </div>
                    </td>

                    {/* Destino */}
                    <td style={tableCellStyle}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                        <div>
                          <p style={{ fontWeight: 700, fontSize: '0.95rem', margin: 0 }}>{formatearMonto(t.monto_recibir)} <span style={{fontSize: '0.8rem', color: 'var(--text-low)'}}>{t.moneda_destino}</span></p>
                          <p style={{ fontSize: '0.75rem', color: 'var(--text-low)', margin: 0, marginTop: '0.1rem' }}>{t.pais_destino}</p>
                        </div>
                      </div>
                    </td>

                    {/* P2P Cliente Data */}
                    <td style={tableCellStyle}>
                      {t.referencia_pago || t.comprobante_cliente ? (
                        <div style={{ fontSize: '0.8rem' }}>
                          {t.referencia_pago && <div style={{ fontWeight: 600, color: '#3b82f6' }}>Ref: {t.referencia_pago}</div>}
                          {t.comprobante_cliente && (
                            <a href={t.comprobante_cliente} target="_blank" rel="noreferrer" style={{ color: 'var(--primary-color)', textDecoration: 'underline', fontSize: '0.75rem' }}>Ver Imagen 🖼️</a>
                          )}
                        </div>
                      ) : (
                        <span style={{ color: 'var(--text-low)', fontSize: '0.75rem', fontStyle: 'italic' }}>Sin datos aún</span>
                      )}
                    </td>

                    {/* Estado con Selector y Carga de Comprobante Admin */}
                    <td style={tableCellStyle}>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
                        <select 
                          value={t.estado} 
                          onChange={(e) => actualizarEstado(t.id, e.target.value)}
                          style={{
                            backgroundColor: statusColors.bg,
                            color: statusColors.color,
                            border: `1px solid ${statusColors.color}`,
                            padding: '0.4rem 2rem 0.4rem 0.8rem',
                            borderRadius: '0.6rem',
                            fontWeight: 700,
                            fontSize: '0.75rem',
                            outline: 'none',
                            cursor: 'pointer',
                            appearance: 'none',
                            backgroundImage: `url("data:image/svg+xml;utf8,<svg fill='${statusColors.color.replace('#', '%23')}' height='20' viewBox='0 0 24 24' width='20' xmlns='http://www.w3.org/2000/svg'><path d='M7 10l5 5 5-5z'/></svg>")`,
                            backgroundRepeat: 'no-repeat',
                            backgroundPosition: 'calc(100% - 0.5rem) center',
                            backgroundSize: '1.2rem',
                            minWidth: '135px'
                          }}
                        >
                          {estadosDisponibles.map(est => (
                            <option key={est} value={est} style={{ background: '#0a192f', color: 'white' }}>{est}</option>
                          ))}
                        </select>

                        {t.estado === 'Verificando' && (
                          <div style={{ marginTop: '0.5rem' }}>
                            <label className="cta-button" style={{ 
                              padding: '0.4rem 0.8rem', fontSize: '0.7rem', display: 'inline-block',
                              background: 'var(--primary-color)', color: '#0a192f', borderRadius: '0.5rem',
                              cursor: 'pointer'
                            }}>
                              SUBIR RECIBO FINAL
                              <input 
                                type="file" 
                                hidden 
                                accept="image/*"
                                onChange={(e) => handleSubirComprobanteAdmin(t.id, t.codigo, e.target.files[0])}
                              />
                            </label>
                          </div>
                        )}

                        {t.comprobante_admin && (
                          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.3rem' }}>
                            <a href={t.comprobante_admin} target="_blank" rel="noreferrer" style={{ fontSize: '0.7rem', color: '#10b981', textAlign: 'center', textDecoration: 'none', fontWeight: 700 }}>
                              🖼️ Ver Recibo Enviado
                            </a>
                            <a 
                              href={`https://wa.me/${t.whatsapp_cliente.replace(/\+/g, '').replace(/ /g, '')}?text=%C2%A1Hola!%20Tu%20operaci%C3%B3n%20%23${t.codigo}%20en%20JK%20CONVERSOR%20ha%20sido%20COMPLETADA.%20Puedes%20ver%20tu%20recibo%20aqu%C3%AD:%20${t.comprobante_admin}`} 
                              target="_blank" rel="noreferrer"
                              style={{ 
                                background: '#25D366', color: 'white', padding: '0.3rem', 
                                borderRadius: '0.4rem', fontSize: '0.65rem', textAlign: 'center',
                                textDecoration: 'none', fontWeight: 800
                              }}
                            >
                              NOTIFICAR AL CLIENTE 💬
                            </a>
                          </div>
                        )}
                      </div>
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        ) }
      </div>
    </div>
  )
}
