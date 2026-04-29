import { useState } from 'react'
import { supabase } from './lib/supabase'

export default function Auth({ onLogin, tipo = 'detal' }) {
  const [loading, setLoading] = useState(false)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [nombre, setNombre] = useState('')
  const [whatsapp, setWhatsapp] = useState('')
  const [isRegister, setIsRegister] = useState(false)
  const [error, setError] = useState(null)

  const handleAuth = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    try {
      if (isRegister) {
        const { error } = await supabase.auth.signUp({
          email,
          password,
          options: {
            data: {
              nombre: nombre,
              whatsapp: whatsapp,
              tipo: tipo
            }
          }
        })
        if (error) throw error
        alert('📦 Registro exitoso. Por favor revisa tu correo para confirmar tu cuenta (si aplica).')
      } else {
        const { error } = await supabase.auth.signInWithPassword({
          email,
          password
        })
        if (error) throw error
        if (onLogin) onLogin()
      }
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const handleGoogleLogin = async () => {
    try {
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: window.location.origin + window.location.pathname
        }
      })
      if (error) throw error
    } catch (err) {
      setError(err.message)
    }
  }

  return (
    <div style={{ 
      minHeight: 'calc(100vh - var(--header-height))', 
      display: 'flex', 
      alignItems: 'center', 
      justifyContent: 'center', 
      padding: '2rem' 
    }}>
      <div className="glass" style={{ 
        maxWidth: '450px', 
        width: '100%', 
        padding: '3rem 2.5rem', 
        animation: 'fadeIn 0.5s ease-out' 
      }}>
        <div style={{ textAlign: 'center', marginBottom: '2.5rem' }}>
          <div style={{ 
            width: '4.5rem', 
            height: '4.5rem', 
            background: 'rgba(16,185,129,0.1)', 
            borderRadius: '1.2rem', 
            display: 'flex', 
            alignItems: 'center', 
            justifyContent: 'center', 
            margin: '0 auto 1.5rem',
            color: 'var(--primary-color)',
            border: '1px solid rgba(16,185,129,0.2)'
          }}>
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"></path>
              <circle cx="12" cy="7" r="4"></circle>
            </svg>
          </div>
          <h2 style={{ fontSize: '1.8rem', fontWeight: 800, marginBottom: '0.6rem' }}>
            {isRegister ? 'Crear Cuenta' : 'Bienvenido de nuevo'}
          </h2>
          <p style={{ color: 'var(--text-low)', fontSize: '0.95rem' }}>
            {isRegister ? 'Regístrate para gestionar tus cambios fácilmente' : 'Ingresa a tu cuenta para continuar'}
          </p>
        </div>

        <button
          onClick={handleGoogleLogin}
          style={{
            width: '100%',
            padding: '0.8rem',
            background: 'rgba(255,255,255,0.05)',
            border: '1px solid rgba(255,255,255,0.1)',
            borderRadius: '0.8rem',
            color: 'white',
            fontSize: '0.9rem',
            fontWeight: 600,
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '0.8rem',
            marginBottom: '1.5rem',
            transition: 'all 0.2s'
          }}
          onMouseOver={e => e.currentTarget.style.background = 'rgba(255,255,255,0.1)'}
          onMouseOut={e => e.currentTarget.style.background = 'rgba(255,255,255,0.05)'}
        >
          <svg width="18" height="18" viewBox="0 0 24 24">
            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
            <path fill="#FBBC05" d="M5.84 14.1c-.22-.66-.35-1.36-.35-2.1s.13-1.44.35-2.1V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l3.66-2.84z"/>
            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
          </svg>
          Continuar con Google
        </button>

        <div style={{ display: 'flex', alignItems: 'center', gap: '1rem', marginBottom: '1.5rem' }}>
          <div style={{ flex: 1, height: '1px', background: 'rgba(255,255,255,0.1)' }}></div>
          <span style={{ fontSize: '0.75rem', color: 'var(--text-low)', textTransform: 'uppercase', fontWeight: 700 }}>o vía email</span>
          <div style={{ flex: 1, height: '1px', background: 'rgba(255,255,255,0.1)' }}></div>
        </div>

        <form onSubmit={handleAuth} style={{ display: 'flex', flexDirection: 'column', gap: '1.2rem' }}>
          {isRegister && (
            <>
              <div className="input-group">
                <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 700, color: 'var(--text-low)', marginBottom: '0.5rem', textTransform: 'uppercase' }}>Nombre Completo</label>
                <input
                  required
                  type="text"
                  placeholder="Ej: Juan Pérez"
                  value={nombre}
                  onChange={e => setNombre(e.target.value)}
                  className="input-field"
                  style={{ width: '100%' }}
                />
              </div>
              <div className="input-group">
                <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 700, color: 'var(--text-low)', marginBottom: '0.5rem', textTransform: 'uppercase' }}>WhatsApp</label>
                <input
                  required
                  type="text"
                  placeholder="Ej: +593987654321"
                  value={whatsapp}
                  onChange={e => setWhatsapp(e.target.value)}
                  className="input-field"
                  style={{ width: '100%' }}
                />
              </div>
            </>
          )}

          <div className="input-group">
            <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 700, color: 'var(--text-low)', marginBottom: '0.5rem', textTransform: 'uppercase' }}>Correo Electrónico</label>
            <input
              required
              type="email"
              placeholder="tu@email.com"
              value={email}
              onChange={e => setEmail(e.target.value)}
              className="input-field"
              style={{ width: '100%' }}
            />
          </div>

          <div className="input-group">
            <label style={{ display: 'block', fontSize: '0.75rem', fontWeight: 700, color: 'var(--text-low)', marginBottom: '0.5rem', textTransform: 'uppercase' }}>Contraseña</label>
            <input
              required
              type="password"
              placeholder="••••••••"
              value={password}
              onChange={e => setPassword(e.target.value)}
              className="input-field"
              style={{ width: '100%' }}
            />
          </div>

          {error && (
            <div style={{ 
              padding: '0.8rem', 
              background: 'rgba(239, 68, 68, 0.1)', 
              border: '1px solid rgba(239, 68, 68, 0.2)', 
              borderRadius: '0.8rem', 
              color: '#ff4d4d', 
              fontSize: '0.85rem',
              fontWeight: 600
            }}>
              ⚠️ {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="btn-primary"
            style={{ 
              width: '100%', 
              padding: '1rem', 
              fontSize: '1rem', 
              marginTop: '0.5rem',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '0.8rem'
            }}
          >
            {loading ? (
              <span className="spinner" style={{ width: '20px', height: '20px', border: '3px solid rgba(0,0,0,0.1)', borderTopColor: 'black', borderRadius: '50%', animation: 'spin 1s linear infinite' }}></span>
            ) : null}
            {loading ? 'Procesando...' : (isRegister ? 'Registrarse Ahora' : 'Iniciar Sesión')}
          </button>
        </form>

        <div style={{ marginTop: '2rem', textAlign: 'center' }}>
          <p style={{ color: 'var(--text-low)', fontSize: '0.9rem' }}>
            {isRegister ? '¿Ya tienes una cuenta?' : '¿No tienes una cuenta aún?'}
            <button
              onClick={() => setIsRegister(!isRegister)}
              style={{ 
                background: 'none', 
                border: 'none', 
                color: 'var(--primary-color)', 
                fontWeight: 700, 
                cursor: 'pointer',
                marginLeft: '0.5rem',
                padding: '0.2rem 0.5rem'
              }}
            >
              {isRegister ? 'Inicia Sesión' : 'Regístrate aquí'}
            </button>
          </p>
        </div>
      </div>
      <style>{`
        @keyframes spin { to { transform: rotate(360deg); } }
      `}</style>
    </div>
  )
}
