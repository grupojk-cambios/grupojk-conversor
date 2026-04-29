import React, { useState, useEffect } from 'react'
import { supabase } from './lib/supabase'

export default function MisOperaciones({ modo = 'detal' }) {
  const [transacciones, setTransacciones] = useState([])
  const [loading, setLoading] = useState(true)
  const [user, setUser] = useState(null)
  const [isMobile, setIsMobile] = useState(window.innerWidth <= 600)

  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth <= 600)
    window.addEventListener('resize', handleResize)
    
    // Verificar sesión inicial
    supabase.auth.getUser().then(({ data: { user } }) => {
      setUser(user)
      if (user) fetchMisTransacciones(user.id)
      else setLoading(false)
    })

    // Suscribirse a cambios en tiempo real
    const channel = supabase
      .channel('mis-cambios-realtime')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'transacciones' }, () => {
        supabase.auth.getUser().then(({ data: { user } }) => {
          if (user) fetchMisTransacciones(user.id)
        })
      })
      .subscribe()

    return () => {
      window.removeEventListener('resize', handleResize)
      supabase.removeChannel(channel)
    }
  }, [modo])

  async function fetchMisTransacciones(userId) {
    try {
      const tipo = modo === 'mayor' ? 'Mayorista' : 'Estándar'
      const { data, error } = await supabase
        .from('transacciones')
        .select('*')
        .eq('user_id', userId)
        .eq('tipo_cliente', tipo)
        .order('fecha', { ascending: false })

      if (error) throw error
      setTransacciones(data || [])
    } catch (err) {
      console.error('Error fetching transactions:', err)
    } finally {
      setLoading(false)
    }
  }

  async function handleSubirPago(id, codigo) {
    const refInput = document.getElementById(`ref-${id}`)
    const fileInput = document.getElementById(`file-${id}`)
    const referencia = refInput?.value || ''
    const file = fileInput?.files[0]

    if (!referencia && !file) {
      alert('Por favor ingressa al menos el número de referencia o sube una foto.')
      return
    }

    try {
      let publicUrl = null

      if (file) {
        // Subir imagen a Supabase Storage
        const fileExt = file.name.split('.').pop()
        const fileName = `${codigo}-${Date.now()}.${fileExt}`
        const filePath = `clientes/${fileName}`

        const { error: uploadError } = await supabase.storage
          .from('comprobantes')
          .upload(filePath, file)

        if (uploadError) throw uploadError

        const { data: { publicUrl: url } } = supabase.storage
          .from('comprobantes')
          .getPublicUrl(filePath)
        
        publicUrl = url
      }

      // Actualizar registro en la tabla
      const { error: updateError } = await supabase
        .from('transacciones')
        .update({
          referencia_pago: referencia,
          comprobante_cliente: publicUrl,
          estado: 'Verificando'
        })
        .eq('id', id)

      if (updateError) throw updateError

      alert('¡Datos de pago enviados correctamente! Estamos verificando tu operación.')
      fetchMisTransacciones()
    } catch (err) {
      console.error('Error al subir pago:', err)
      alert('Hubo un error al subir los datos. Asegúrate de que el archivo sea una imagen.')
    }
  }

  const getStatusColor = (estado) => {
    switch (estado) {
      case 'Completada': return '#10b981';
      case 'Verificando': return '#f59e0b';
      case 'Cancelada': return '#ef4444';
      default: return '#3b82f6';
    }
  }

  const getStatusIcon = (estado) => {
    switch (estado) {
      case 'Completada': return '✅';
      case 'Verificando': return '🔍';
      case 'Cancelada': return '❌';
      default: return '🕒';
    }
  }

  if (loading) {
    return (
      <div style={{ padding: '4rem 2rem', textAlign: 'center', color: 'white' }}>
        <p>Buscando tus transacciones...</p>
      </div>
    )
  }

  return (
    <div style={{ maxWidth: '800px', margin: '0 auto', padding: isMobile ? '1.5rem' : '3rem 2rem' }}>
      <header style={{ marginBottom: '2.5rem', textAlign: 'center' }}>
        <h1 style={{ fontSize: isMobile ? '1.8rem' : '2.5rem', fontWeight: 800, color: 'white', marginBottom: '0.8rem' }}>
          Mis Operaciones
        </h1>
        <p style={{ color: 'var(--text-low)', fontSize: '0.95rem' }}>
          Consulta el estado de tus envíos en tiempo real
        </p>
      </header>

      {!user ? (
        <div className="glass" style={{ padding: '4rem 2rem', textAlign: 'center' }}>
          <div style={{ fontSize: '3rem', marginBottom: '1.5rem' }}>🔐</div>
          <h3 style={{ color: 'white', marginBottom: '1rem' }}>Inicia sesión para ver tus cambios</h3>
          <p style={{ color: 'var(--text-low)', marginBottom: '2rem', maxWidth: '400px', margin: '0 auto 2rem' }}>
            Necesitas estar dentro de tu cuenta para poder rastrear tus operaciones de forma segura.
          </p>
          <button 
            onClick={() => window.location.hash = '#/login'}
            className="btn-primary"
            style={{ padding: '0.8rem 2rem' }}
          >
            Iniciar Sesión
          </button>
        </div>
      ) : transacciones.length === 0 ? (
        <div className="glass" style={{ padding: '4rem 2rem', textAlign: 'center' }}>
          <div style={{ fontSize: '3rem', marginBottom: '1.5rem' }}>📋</div>
          <h3 style={{ color: 'white', marginBottom: '1rem' }}>No tienes transacciones registradas</h3>
          <p style={{ color: 'var(--text-low)', marginBottom: '2rem', maxWidth: '400px', margin: '0 auto 2rem' }}>
            Aún no has realizado ninguna cotización con esta cuenta.
          </p>
          <button 
            onClick={() => window.location.hash = '#/cotizador'}
            className="btn-primary"
            style={{ padding: '0.8rem 2rem' }}
          >
            Ir al Cotizador
          </button>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1.2rem' }}>
          {transacciones.map(tr => (
            <div key={tr.id} className="glass" style={{ 
              padding: '1.5rem', 
              borderLeft: `4px solid ${getStatusColor(tr.estado)}`,
              animation: 'fadeIn 0.4s'
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '1.2rem' }}>
                <div>
                  <span style={{ 
                    fontSize: '0.7rem', 
                    fontWeight: 800, 
                    background: 'rgba(255,255,255,0.05)', 
                    padding: '0.2rem 0.6rem', 
                    borderRadius: '0.4rem',
                    color: 'var(--text-low)',
                    letterSpacing: '0.05em'
                  }}>
                    #{tr.codigo}
                  </span>
                  <p style={{ fontSize: '0.75rem', color: 'var(--text-low)', marginTop: '0.4rem' }}>
                    {new Date(tr.fecha).toLocaleString('es-ES', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })}
                  </p>
                </div>
                
                <div style={{ 
                  display: 'flex', 
                  alignItems: 'center', 
                  gap: '0.5rem', 
                  background: `${getStatusColor(tr.estado)}20`, 
                  padding: '0.4rem 0.8rem', 
                  borderRadius: '2rem',
                  border: `1px solid ${getStatusColor(tr.estado)}40`
                }}>
                  <span style={{ fontSize: '0.9rem' }}>{getStatusIcon(tr.estado)}</span>
                  <span style={{ fontSize: '0.75rem', fontWeight: 700, color: getStatusColor(tr.estado), textTransform: 'uppercase' }}>
                    {tr.estado}
                  </span>
                </div>
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: isMobile ? '1fr' : '1fr auto 1fr', gap: '1rem', alignItems: 'center', background: 'rgba(0,0,0,0.2)', padding: '1rem', borderRadius: '0.8rem' }}>
                <div style={{ textAlign: isMobile ? 'left' : 'right' }}>
                  <p style={{ fontSize: '0.7rem', color: 'var(--text-low)', textTransform: 'uppercase', marginBottom: '0.2rem' }}>Envías ({tr.pais_origen})</p>
                  <p style={{ fontSize: '1.1rem', fontWeight: 700, color: 'white' }}>{new Intl.NumberFormat('es-ES').format(tr.monto_enviado)} {tr.moneda_origen}</p>
                </div>
                
                <div style={{ textAlign: 'center', color: 'var(--primary-color)', fontSize: '1.2rem', opacity: 0.5 }}>
                  {isMobile ? '↓' : '→'}
                </div>

                <div>
                  <p style={{ fontSize: '0.7rem', color: 'var(--text-low)', textTransform: 'uppercase', marginBottom: '0.2rem' }}>Recibes ({tr.pais_destino})</p>
                  <p style={{ fontSize: '1.1rem', fontWeight: 700, color: 'var(--primary-color)' }}>{new Intl.NumberFormat('es-ES').format(tr.monto_recibir)} {tr.moneda_destino}</p>
                </div>
              </div>

              {tr.estado === 'Pendiente' && (
                <div style={{ marginTop: '1.2rem', padding: '1.2rem', background: 'rgba(59, 130, 246, 0.05)', borderRadius: '1rem', border: '1px solid rgba(59, 130, 246, 0.2)' }}>
                  <p style={{ fontSize: '0.8rem', fontWeight: 700, color: '#93c5fd', marginBottom: '1rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                    <span>📤</span> REGISTRAR TU PAGO (P2P)
                  </p>
                  
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '0.8rem' }}>
                    <div>
                      <label style={{ fontSize: '0.7rem', color: 'var(--text-low)', display: 'block', marginBottom: '0.4rem' }}>Número de Referencia / ID de Transacción</label>
                      <input 
                        type="text" 
                        placeholder="Ej: 123456789"
                        id={`ref-${tr.id}`}
                        style={{ width: '100%', padding: '0.7rem', background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.1)', borderRadius: '0.6rem', color: 'white', fontSize: '0.85rem', outline: 'none' }}
                      />
                    </div>
                    
                    <div>
                      <label style={{ fontSize: '0.7rem', color: 'var(--text-low)', display: 'block', marginBottom: '0.4rem' }}>Foto del Comprobante (Opcional)</label>
                      <input 
                        type="file" 
                        id={`file-${tr.id}`}
                        accept="image/*"
                        style={{ fontSize: '0.75rem', color: 'var(--text-low)' }}
                      />
                    </div>

                    <button 
                      onClick={() => handleSubirPago(tr.id, tr.codigo)}
                      style={{ 
                        marginTop: '0.5rem',
                        padding: '0.8rem',
                        background: '#3b82f6',
                        color: 'white',
                        border: 'none',
                        borderRadius: '0.8rem',
                        fontWeight: 700,
                        fontSize: '0.8rem',
                        cursor: 'pointer',
                        transition: 'all 0.2s'
                      }}
                    >
                      Enviar Datos de Pago
                    </button>
                  </div>
                </div>
              )}

              {(tr.referencia_pago || tr.comprobante_cliente) && tr.estado !== 'Pendiente' && (
                <div style={{ marginTop: '1.2rem', padding: '1rem', background: 'rgba(255,255,255,0.03)', borderRadius: '0.8rem', border: '1px solid rgba(255,255,255,0.05)' }}>
                  <p style={{ fontSize: '0.7rem', color: 'var(--text-low)', textTransform: 'uppercase', marginBottom: '0.6rem', fontWeight: 700 }}>Mi Comprobante Enviado:</p>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <span style={{ fontSize: '0.8rem', color: 'white' }}>Ref: {tr.referencia_pago || 'N/A'}</span>
                    {tr.comprobante_cliente && (
                      <a href={tr.comprobante_cliente} target="_blank" rel="noreferrer" style={{ fontSize: '0.75rem', color: 'var(--primary-color)', textDecoration: 'none', fontWeight: 600 }}>Ver Imagen</a>
                    )}
                  </div>
                </div>
              )}

              {tr.comprobante_admin && (
                <div style={{ marginTop: '1.2rem', padding: '1.2rem', background: 'rgba(16, 185, 129, 0.1)', borderRadius: '1rem', border: '2px solid var(--primary-color)' }}>
                  <p style={{ fontSize: '0.85rem', fontWeight: 800, color: 'var(--primary-color)', marginBottom: '0.8rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                    <span>📥</span> COMPROBANTE DE JK CONVERSOR
                  </p>
                  <p style={{ fontSize: '0.75rem', color: 'white', marginBottom: '1rem' }}>Tu pago ha sido procesado con éxito. Aquí tienes tu comprobante:</p>
                  <a 
                    href={tr.comprobante_admin} 
                    target="_blank" 
                    rel="noreferrer" 
                    style={{ 
                      display: 'block',
                      width: '100%',
                      padding: '0.8rem',
                      background: 'var(--primary-color)',
                      color: 'var(--bg-color)',
                      textAlign: 'center',
                      borderRadius: '0.8rem',
                      fontWeight: 800,
                      textDecoration: 'none',
                      fontSize: '0.85rem'
                    }}
                  >
                    DESCARGAR COMPROBANTE FINAL
                  </a>
                </div>
              )}

              {tr.estado === 'Verificando' && !tr.comprobante_admin && (
                <div style={{ marginTop: '1.2rem', padding: '0.8rem', background: 'rgba(245, 158, 11, 0.1)', borderRadius: '0.6rem', border: '1px solid rgba(245, 158, 11, 0.2)', display: 'flex', gap: '0.8rem', alignItems: 'center' }}>
                  <span style={{ fontSize: '1.2rem' }}>🔎</span>
                  <p style={{ fontSize: '0.75rem', color: '#fcd34d', margin: 0, lineHeight: 1.4 }}>
                    Estamos validando tu comprobante de pago. En breve procesaremos tu envío.
                  </p>
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      <div style={{ marginTop: '3rem', textAlign: 'center' }}>
        <p style={{ color: 'var(--text-low)', fontSize: '0.85rem', marginBottom: '1rem' }}>
          ¿Necesitas ayuda con una operación? <br/>
          Contacta con nosotros:
        </p>
        <div style={{ display: 'flex', justifyContent: 'center', gap: '1rem', flexWrap: 'wrap' }}>
          <a 
            href="https://wa.me/593961230380" 
            target="_blank" 
            rel="noreferrer" 
            style={{ 
              background: '#25D366', color: 'white', padding: '0.6rem 1.2rem', 
              borderRadius: '0.8rem', fontSize: '0.8rem', textDecoration: 'none', 
              fontWeight: 700, display: 'flex', alignItems: 'center', gap: '0.5rem' 
            }}
          >
            🟢 Soporte Kelvin
          </a>
          <a 
            href="https://wa.me/593998053300" 
            target="_blank" 
            rel="noreferrer" 
            style={{ 
              background: '#25D366', color: 'white', padding: '0.6rem 1.2rem', 
              borderRadius: '0.8rem', fontSize: '0.8rem', textDecoration: 'none', 
              fontWeight: 700, display: 'flex', alignItems: 'center', gap: '0.5rem' 
            }}
          >
            🟢 Soporte Dario
          </a>
        </div>
      </div>
    </div>
  )
}
