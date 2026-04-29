import { useState } from 'react'
import { supabase } from './lib/supabase'
import './index.css'

const ADMIN_EMAIL = 'multimarcasjk2018@gmail.com'

export default function LoginAdmin({ onLogin }) {
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError('')
    
    try {
      const { data, error: authError } = await supabase.auth.signInWithPassword({
        email: ADMIN_EMAIL,
        password: password
      })

      if (authError) throw authError

      // Verificar que el correo coincida (por seguridad extra)
      if (data.user?.email === ADMIN_EMAIL) {
        sessionStorage.setItem('jk_admin_auth', 'true')
        if (onLogin) onLogin()
      } else {
        throw new Error('Acceso no autorizado para este usuario.')
      }
    } catch (err) {
      console.error('Error login admin:', err)
      setError('Error de acceso: ' + (err.message === 'Invalid login credentials' ? 'Contraseña incorrecta' : err.message))
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
          <div style={{ marginBottom: '1.5rem' }}>
            <label className="text-xs font-bold uppercase tracking-widest text-low block mb-2 opacity-70">
              Usuario Administrador
            </label>
            <div style={{ 
              padding: '1rem', 
              background: 'rgba(255,255,255,0.05)', 
              borderRadius: '1rem', 
              border: '1px solid rgba(255,255,255,0.1)',
              color: 'var(--primary-color)',
              fontSize: '0.9rem',
              fontWeight: 600
            }}>
              {ADMIN_EMAIL}
            </div>
          </div>

          <div>
            <label className="text-xs font-bold uppercase tracking-widest text-low block mb-2 opacity-70">
              Contraseña de Acceso
            </label>
            <input
              type="password"
              className="input-field"
              placeholder="••••••••"
              value={password}
              onChange={(e) => {
                setPassword(e.target.value)
                setError('')
              }}
              autoFocus
              required
            />
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
        </form>

        <p className="text-center text-xs text-low mt-8 opacity-40">
          Esta página no es accesible desde el sitio público.
        </p>
      </div>
    </div>
  )
}
