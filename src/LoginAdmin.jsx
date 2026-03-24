import React, { useState } from 'react'
import './index.css'

const ADMIN_PASSWORD = 'jkadmin2026'

export default function LoginAdmin({ onLogin }) {
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = (e) => {
    e.preventDefault()
    setLoading(true)
    setTimeout(() => {
      if (password === ADMIN_PASSWORD) {
        sessionStorage.setItem('jk_admin_auth', 'true')
        onLogin()
      } else {
        setError('Contraseña incorrecta. Inténtalo de nuevo.')
        setPassword('')
      }
      setLoading(false)
    }, 600)
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
              Contraseña de Administrador
            </label>
            <input
              type="password"
              className="input-field"
              placeholder="Ingresa la contraseña..."
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
