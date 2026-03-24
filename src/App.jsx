import { useState, useEffect } from 'react'
import Dashboard from './Dashboard'
import Cotizador from './Cotizador'
import ListaPaises from './ListaPaises'
import AdminPanel from './AdminPanel'
import LoginAdmin from './LoginAdmin'

function App() {
  const [ruta, setRuta] = useState('inicio')
  const [auth, setAuth] = useState(false)

  // Autenticación inicial
  useEffect(() => {
    const isAuth = sessionStorage.getItem('jk_admin_auth')
    if (isAuth) setAuth(true)
  }, [])

  // Enrutamiento básico con hash
  useEffect(() => {
    const handleHashChange = () => {
      const hash = window.location.hash.replace('#/', '') || 'inicio'
      setRuta(hash)
    }
    
    window.addEventListener('hashchange', handleHashChange)
    handleHashChange()
    
    return () => window.removeEventListener('hashchange', handleHashChange)
  }, [])

  const navegar = (nueva) => {
    window.location.hash = `/${nueva}`
  }

  const handleLogin = () => {
    setAuth(true)
    navegar('admin')
  }

  const handleLogout = () => {
    sessionStorage.removeItem('jk_admin_auth')
    setAuth(false)
    navegar('inicio')
  }

  return (
    <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      
      {/* Navbar Público */}
      {(ruta !== 'admin-jk' && ruta !== 'admin') && (
        <nav style={{
          height: 'var(--header-height)',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          padding: '0 2rem',
          background: 'rgba(6, 25, 52, 0.8)',
          backdropFilter: 'blur(12px)',
          borderBottom: '1px solid var(--glass-border)',
          position: 'sticky',
          top: 0,
          zIndex: 1000
        }}>
          <div 
            style={{ fontSize: '1.5rem', fontWeight: 800, color: 'white', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '0.5rem' }}
            onClick={() => navegar('inicio')}
          >
            <div style={{ width: '2.6rem', height: '2.6rem', background: 'white', borderRadius: '0.4rem', display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden', padding: '0.15rem', boxShadow: '0 0 10px rgba(16,185,129,0.2)' }}>
              <img src="/logo_jk_final.png" alt="Logo" style={{ width: '100%', height: '100%', objectFit: 'contain' }} />
            </div>
            <span>GRUPO JK</span>
          </div>
          
          <div style={{ display: 'flex', gap: '2rem', alignItems: 'center' }}>
            <button onClick={() => navegar('inicio')} className={`nav-link ${ruta === 'inicio' ? 'active' : ''}`} style={{ background: 'none', border: 'none', fontSize: '1rem', cursor: 'pointer' }}>Inicio</button>
            <button onClick={() => navegar('cotizador')} className={`nav-link ${ruta === 'cotizador' ? 'active' : ''}`} style={{ background: 'none', border: 'none', fontSize: '1rem', cursor: 'pointer' }}>Cotizador</button>
            <button onClick={() => navegar('tasas')} className={`nav-link ${ruta === 'tasas' ? 'active' : ''}`} style={{ background: 'none', border: 'none', fontSize: '1rem', cursor: 'pointer' }}>Lista de Tasas</button>
          </div>
        </nav>
      )}

      {/* Main Content */}
      <main style={{ flex: 1 }}>
        {ruta === 'inicio' && <Dashboard onNavegar={navegar} />}
        {ruta === 'cotizador' && <Cotizador />}
        {ruta === 'tasas' && <ListaPaises />}
        
        {ruta === 'admin-jk' && (
          !auth ? <LoginAdmin onLogin={handleLogin} /> : <AdminPanel onLogout={handleLogout} />
        )}
        
        {ruta === 'admin' && (
          auth ? <AdminPanel onLogout={handleLogout} /> : <LoginAdmin onLogin={handleLogin} />
        )}
      </main>

      {/* Footer Público */}
      {(ruta !== 'admin-jk' && ruta !== 'admin') && (
        <footer style={{
          textAlign: 'center',
          padding: '2rem',
          borderTop: '1px solid var(--glass-border)',
          color: 'var(--text-low)',
          fontSize: '0.85rem'
        }}>
          <p>© {new Date().getFullYear()} GRUPO JK. Todos los derechos reservados.</p>
          <p style={{ marginTop: '0.5rem' }}>
            <span style={{ cursor: 'pointer', opacity: 0.3 }} onDoubleClick={() => navegar('admin-jk')}>⚡</span>
          </p>
        </footer>
      )}

    </div>
  )
}

export default App
