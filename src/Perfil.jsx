import { useState, useEffect } from 'react'
import { supabase } from './lib/supabase'

export default function Perfil({ profile, onUpdate, modo = 'detal', onLogout, onSwitchMode }) {
  const [formData, setFormData] = useState({
    full_name: profile?.full_name || '',
    whatsapp: profile?.whatsapp || '',
    email: profile?.email || ''
  })
  const [loading, setLoading] = useState(false)
  const [mensaje, setMensaje] = useState(null)

  useEffect(() => {
    if (profile) {
      setFormData({
        full_name: profile.full_name || '',
        whatsapp: profile.whatsapp || '',
        email: profile.email || ''
      })
    }
  }, [profile])

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    setMensaje(null)

    // Limpiar WhatsApp de espacios
    const whatsappLimpio = formData.whatsapp.replace(/\s+/g, '')

    // Validación básica
    if (whatsappLimpio && !whatsappLimpio.startsWith('+')) {
      setMensaje({ tipo: 'error', texto: '⚠️ El WhatsApp debe incluir el "+" y código de país.' })
      setLoading(false)
      return
    }

    try {
      const tabla = modo === 'mayor' ? 'perfiles_mayor' : 'perfiles_detal'
      const { error } = await supabase
        .from(tabla)
        .update({
          full_name: formData.full_name,
          whatsapp: whatsappLimpio
        })
        .eq('id', profile.id)

      if (error) throw error

      setMensaje({ tipo: 'success', texto: '✅ Perfil actualizado correctamente' })
      if (onUpdate) onUpdate({ ...profile, full_name: formData.full_name, whatsapp: whatsappLimpio })
    } catch (error) {
      console.error('Error al actualizar perfil:', error)
      setMensaje({ tipo: 'error', texto: '❌ Error al guardar los cambios' })
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{ maxWidth: '600px', margin: '2rem auto', padding: '0 1.5rem', paddingBottom: '6rem' }}>
      <div className="glass" style={{ padding: '3rem 2rem', textAlign: 'center' }}>
        
        {/* Avatar/Icono */}
        <div style={{ 
          width: '6rem', height: '6rem', borderRadius: '50%', background: 'var(--primary-color)', 
          margin: '0 auto 1.5rem', display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: '2.5rem', boxShadow: '0 0 20px rgba(16, 185, 129, 0.3)'
        }}>
          👤
        </div>

        <h2 style={{ fontSize: '1.8rem', marginBottom: '0.5rem', color: 'white' }}>Mi Perfil</h2>
        <p style={{ color: 'var(--text-low)', fontSize: '0.9rem', marginBottom: '2.5rem' }}>
          Gestiona tu información personal en {modo === 'mayor' ? 'Grupo JK Mayor' : 'JK Conversor'}
        </p>

        {mensaje && (
          <div style={{
            padding: '1rem', borderRadius: '0.8rem', marginBottom: '1.5rem', fontSize: '0.9rem',
            background: mensaje.tipo === 'success' ? 'rgba(16, 185, 129, 0.1)' : 'rgba(239, 68, 68, 0.1)',
            color: mensaje.tipo === 'success' ? '#10b981' : '#ef4444',
            border: `1px solid ${mensaje.tipo === 'success' ? '#10b981' : '#ef4444'}`,
            fontWeight: 600
          }}>
            {mensaje.texto}
          </div>
        )}

        <form onSubmit={handleSubmit} style={{ textAlign: 'left' }}>
          <div style={{ marginBottom: '1.5rem' }}>
            <label style={{ display: 'block', color: 'var(--text-low)', fontSize: '0.8rem', marginBottom: '0.5rem', textTransform: 'uppercase', letterSpacing: '0.05rem' }}>
              Correo Electrónico (No editable)
            </label>
            <input
              type="email"
              value={formData.email}
              disabled
              className="input-field"
              style={{ width: '100%', opacity: 0.6, cursor: 'not-allowed' }}
            />
          </div>

          <div style={{ marginBottom: '1.5rem' }}>
            <label style={{ display: 'block', color: 'white', fontSize: '0.8rem', marginBottom: '0.5rem', textTransform: 'uppercase', letterSpacing: '0.05rem', fontWeight: 600 }}>
              Nombre Completo
            </label>
            <input
              type="text"
              required
              value={formData.full_name}
              onChange={e => setFormData({ ...formData, full_name: e.target.value })}
              placeholder="Tu nombre completo"
              className="input-field"
              style={{ width: '100%' }}
            />
          </div>

          <div style={{ marginBottom: '2.5rem' }}>
            <label style={{ display: 'block', color: 'white', fontSize: '0.8rem', marginBottom: '0.5rem', textTransform: 'uppercase', letterSpacing: '0.05rem', fontWeight: 600 }}>
              WhatsApp (Con código de país)
            </label>
            <input
              type="text"
              required
              value={formData.whatsapp}
              onChange={e => setFormData({ ...formData, whatsapp: e.target.value })}
              placeholder="Ej: +593987654321"
              className="input-field"
              style={{ width: '100%' }}
            />
            <p style={{ fontSize: '0.75rem', color: 'var(--text-low)', marginTop: '0.5rem' }}>
              ℹ️ Usamos este número para enviarte los comprobantes de tus operaciones.
            </p>
          </div>

          <button
            type="submit"
            disabled={loading}
            className="btn-primary"
            style={{ width: '100%', padding: '1.1rem', fontSize: '1rem', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '0.5rem' }}
          >
            {loading ? 'Guardando...' : (
              <>
                <span>💾</span> Guardar Cambios
              </>
            )}
          </button>
        </form>

        {/* Selector de Modo (Solo para Admins) */}
        {profile?.role === 'admin' && (
          <div style={{ marginTop: '2.5rem', paddingTop: '1.5rem', borderTop: '1px solid rgba(255,255,255,0.1)', textAlign: 'left' }}>
            <label style={{ display: 'block', color: 'white', fontSize: '0.8rem', marginBottom: '1rem', textTransform: 'uppercase', letterSpacing: '0.05rem', fontWeight: 600 }}>
              Configuración de Interfaz (Admin)
            </label>
            
            <div style={{ background: 'rgba(255,255,255,0.05)', borderRadius: '1rem', padding: '1rem', display: 'flex', flexDirection: 'column', gap: '0.8rem' }}>
              <p style={{ fontSize: '0.85rem', color: 'var(--text-low)', marginBottom: '0.5rem' }}>
                Como administrador, puedes alternar entre la vista de Detal y Mayorista para revisar las tasas.
              </p>
              
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem' }}>
                <button 
                  onClick={() => onSwitchMode && onSwitchMode('detal')}
                  style={{
                    padding: '0.8rem',
                    borderRadius: '0.6rem',
                    border: '1px solid ' + (modo === 'detal' ? 'var(--primary-color)' : 'rgba(255,255,255,0.1)'),
                    background: modo === 'detal' ? 'rgba(16, 185, 129, 0.1)' : 'transparent',
                    color: modo === 'detal' ? 'var(--primary-color)' : 'white',
                    fontWeight: 700,
                    cursor: 'pointer',
                    transition: 'all 0.2s'
                  }}
                >
                  🏠 MODO DETAL
                </button>
                
                <button 
                  onClick={() => onSwitchMode && onSwitchMode('mayor')}
                  style={{
                    padding: '0.8rem',
                    borderRadius: '0.6rem',
                    border: '1px solid ' + (modo === 'mayor' ? 'var(--primary-color)' : 'rgba(255,255,255,0.1)'),
                    background: modo === 'mayor' ? 'rgba(16, 185, 129, 0.1)' : 'transparent',
                    color: modo === 'mayor' ? 'var(--primary-color)' : 'white',
                    fontWeight: 700,
                    cursor: 'pointer',
                    transition: 'all 0.2s'
                  }}
                >
                  💼 MODO MAYOR
                </button>
              </div>
            </div>
          </div>
        )}

        <div style={{ marginTop: '2rem', paddingTop: '1.5rem', borderTop: '1px solid rgba(255,255,255,0.1)', display: 'flex', flexDirection: 'column', gap: '1rem' }}>
          <button 
            onClick={() => onLogout && onLogout()}
            style={{ 
              background: 'rgba(239, 68, 68, 0.1)', 
              border: '1px solid rgba(239, 68, 68, 0.2)', 
              borderRadius: '0.8rem', 
              color: '#ff4d4d', 
              padding: '1rem', 
              cursor: 'pointer', 
              fontWeight: 700,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '0.6rem',
              fontSize: '1rem',
              width: '100%',
              transition: 'all 0.2s'
            }}
            onMouseOver={e => e.currentTarget.style.background = 'rgba(239, 68, 68, 0.2)'}
            onMouseOut={e => e.currentTarget.style.background = 'rgba(239, 68, 68, 0.1)'}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
            CERRAR SESIÓN
          </button>

          <button 
            onClick={() => window.location.hash = modo === 'mayor' ? '#/mayor-inicio' : '#/inicio'}
            style={{ background: 'none', border: 'none', color: 'var(--text-low)', cursor: 'pointer', fontSize: '0.9rem', textDecoration: 'underline' }}
          >
            Volver al Inicio
          </button>
        </div>

      </div>
    </div>
  )
}
