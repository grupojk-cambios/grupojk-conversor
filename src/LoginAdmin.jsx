import { useState } from 'react'
import { supabase } from './lib/supabase'
import './index.css'

export default function LoginAdmin({ onLogin }) {
  const [email, setEmail] = useState('kelvin.17krak@gmail.com')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError('')
    
    try {
      // 1. Intentar iniciar sesión con Supabase Auth
      const { data, error: authError } = await supabase.auth.signInWithPassword({
        email: email,
        password: password
      })

      if (authError) throw authError

      // 2. Verificar que el usuario tenga el rol de 'admin' en perfiles_detal
      const { data: profile, error: profileError } = await supabase
        .from('perfiles_detal')
        .select('role')
        .eq('id', data.user.id)
        .single()

      if (profileError || !profile || profile.role !== 'admin') {
        // Si no es admin, cerramos la sesión inmediatamente por seguridad
        await supabase.auth.signOut()
        throw new Error('No tienes permisos de administrador.')
      }

      // 3. Si todo está bien, guardar sesión y entrar
      sessionStorage.setItem('jk_admin_auth', 'true')
      if (onLogin) onLogin()
      
    } catch (err) {
      console.error('DEBUG - Error completo:', err)
      let msg = 'Error de acceso'
      
      if (err.message === 'Invalid login credentials') {
        msg = 'Email o contraseña incorrectos. Verifica que el correo sea kelvin.17krak@gmail.com'
      } else if (err.message === 'No tienes permisos de administrador.') {
        msg = 'Acceso denegado: Tu usuario no tiene el rol de administrador.'
      } else {
        msg = `Error: ${err.message}`
      }
      
      setError(msg)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center p-6">
      {/* Elementos decorativos de fondo */}
      <div className="fixed top-0 right-0 w-[400px] h-[400px] bg-primary opacity-5 blur-[150px] -z-10"></div>
      <div className="fixed bottom-0 left-0 w-[300px] h-[300px] bg-secondary opacity-5 blur-[120px] -z-10"></div>

      <div className="card glass p-10 w-full max-w-md">
        {/* Logo */}
        <div className="text-center mb-10">
          <div className="w-16 h-16 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4 border border-primary/20">
            <span className="text-3xl">🔐</span>
          </div>
          <h1 className="text-3xl font-extrabold text-white mb-1">Acceso Administrativo</h1>
          <p className="text-low text-sm">GRUPO JK — Área Restringida</p>
        </div>

        <form onSubmit={handleSubmit} className="flex flex-col gap-5">
          <div>
            <label className="text-xs font-bold uppercase tracking-widest text-low block mb-2 opacity-70">
              Email Administrador
            </label>
            <input
              type="email"
              className="input-field"
              style={{ width: '100%' }}
              placeholder="admin@ejemplo.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoFocus
            />
          </div>

          <div>
            <label className="text-xs font-bold uppercase tracking-widest text-low block mb-2 opacity-70">
              Contraseña
            </label>
            <div style={{ position: 'relative' }}>
              <input
                type={showPassword ? 'text' : 'password'}
                className="input-field"
                style={{ width: '100%', paddingRight: '3.5rem' }}
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                style={{
                  position: 'absolute',
                  right: '1rem',
                  top: '50%',
                  transform: 'translateY(-50%)',
                  background: 'none',
                  border: 'none',
                  color: 'var(--text-low)',
                  cursor: 'pointer',
                  padding: '0.5rem',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  opacity: 0.6,
                  transition: 'opacity 0.2s'
                }}
                onMouseEnter={(e) => e.currentTarget.style.opacity = '1'}
                onMouseLeave={(e) => e.currentTarget.style.opacity = '0.6'}
              >
                {showPassword ? (
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"></path>
                    <line x1="1" y1="1" x2="23" y2="23"></line>
                  </svg>
                ) : (
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path>
                    <circle cx="12" cy="12" r="3"></circle>
                  </svg>
                )}
              </button>
            </div>
          </div>

          {error && (
            <div className="p-3 rounded-xl bg-red-500/10 border border-red-500/20 text-sm text-center" style={{ color: 'var(--error-color)' }}>
              {error}
            </div>
          )}

          <button
            type="submit"
            className="btn-primary w-full mt-2"
            disabled={loading}
          >
            {loading ? 'Verificando...' : 'Ingresar al Panel'}
          </button>

          <button
            type="button"
            onClick={() => window.location.hash = '#/inicio'}
            style={{
              background: 'none',
              border: 'none',
              color: 'var(--text-low)',
              fontSize: '0.8rem',
              marginTop: '1rem',
              cursor: 'pointer',
              textDecoration: 'underline',
              opacity: 0.6
            }}
          >
            Volver al Inicio
          </button>
        </form>

        <p className="text-center text-xs text-low mt-8 opacity-40">
          Acceso exclusivo para personal autorizado.
        </p>
      </div>
    </div>
  )
}

