import { useState, useEffect } from 'react'
import { sincronizarGoogleSheets } from './constants'
import Dashboard from './Dashboard'
import Cotizador from './Cotizador'
import ListaPaises from './ListaPaises'
import AdminPanel from './AdminPanel'
import LoginAdmin from './LoginAdmin'
import MisOperaciones from './MisOperaciones'
import Auth from './Auth'
import { supabase } from './lib/supabase'

const CLAVE_MAYOR = '1234jk'

function LoginMayor({ onLogin }) {
  const [clave, setClave] = useState('')
  const [error, setError] = useState('')

  const handleSubmit = (e) => {
    e.preventDefault()
    if (clave === CLAVE_MAYOR) {
      sessionStorage.setItem('jk_mayor_auth', 'true')
      onLogin()
    } else {
      setError('Clave incorrecta. Intente de nuevo.')
      setClave('')
    }
  }

  return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--bg-color)', padding: '2rem' }}>
      <div className="glass" style={{ maxWidth: '420px', width: '100%', padding: '3rem 2.5rem', textAlign: 'center' }}>
        <div style={{ width: '5rem', height: '5rem', margin: '0 auto 1.5rem', borderRadius: '1rem', display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden' }}>
          <img src="./logo-jk-transparente.png" alt="Logo JK" style={{ width: '130%', height: '130%', objectFit: 'contain' }} />
        </div>
        <h2 style={{ fontSize: '1.8rem', marginBottom: '0.5rem', color: 'white' }}>Grupo JK Mayor</h2>
        <p style={{ color: 'var(--text-low)', fontSize: '0.9rem', marginBottom: '2rem' }}>Acceso exclusivo para remesistas y cambistas</p>

        <form onSubmit={handleSubmit}>
          <input
            type="password"
            value={clave}
            onChange={e => { setClave(e.target.value); setError(''); }}
            placeholder="Ingrese la clave de acceso"
            className="input-field"
            style={{ marginBottom: '1rem', textAlign: 'center', fontSize: '1.1rem', letterSpacing: '0.15em' }}
            autoFocus
          />
          {error && (
            <p style={{ color: 'var(--error-color)', fontSize: '0.85rem', marginBottom: '1rem', fontWeight: 600 }}>
              ❌ {error}
            </p>
          )}
          <button
            type="submit"
            className="btn-primary"
            style={{ width: '100%', fontSize: '1.1rem', padding: '1.1rem' }}
          >
            🔓 Ingresar
          </button>
        </form>
      </div>
    </div>
  )
}

function App() {
  const [ruta, setRuta] = useState('inicio')
  const [user, setUser] = useState(null)
  const [auth, setAuth] = useState(false)
  const [mayorAuth, setMayorAuth] = useState(false)
  const [sheetsReady, setSheetsReady] = useState(false)
  const [isMobile, setIsMobile] = useState(window.innerWidth <= 600)
  const [profile, setProfile] = useState(null)
  const [showWhatsAppModal, setShowWhatsAppModal] = useState(false)
  const [newWhatsApp, setNewWhatsApp] = useState('')
  const [savingWhatsApp, setSavingWhatsApp] = useState(false)

  // Detectar modo a partir de la ruta
  const modoMayor = ruta.startsWith('mayor')

  useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth <= 600)
    window.addEventListener('resize', handleResize)
    return () => window.removeEventListener('resize', handleResize)
  }, [])

  // Autenticación inicial y Sincronización
  useEffect(() => {
    // Escuchar cambios en la sesión de Supabase
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null)
    })

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null)
    })

    const isAuth = sessionStorage.getItem('jk_admin_auth')
    if (isAuth) setAuth(true)

    const isMayorAuth = sessionStorage.getItem('jk_mayor_auth')
    if (isMayorAuth) setMayorAuth(true)

    sincronizarGoogleSheets().finally(() => {
        setSheetsReady(true)
    })

    return () => subscription.unsubscribe()
  }, [])

  // Verificar perfil y WhatsApp
  useEffect(() => {
    if (user) {
      const fetchProfile = async () => {
        const { data, error } = await supabase
          .from('perfiles')
          .select('*')
          .eq('id', user.id)
          .single()
        
        if (data) {
          setProfile(data)
          // Si no tiene WhatsApp y no estamos en la página de login, preguntar
          if (!data.whatsapp && ruta !== 'login') {
            setShowWhatsAppModal(true)
          }
        }
      }
      fetchProfile()
    } else {
      setProfile(null)
      setShowWhatsAppModal(false)
    }
  }, [user, ruta])

  const handleSaveWhatsApp = async (e) => {
    e.preventDefault()
    if (!newWhatsApp || newWhatsApp.length < 8) return
    
    setSavingWhatsApp(true)
    const { error } = await supabase
      .from('perfiles')
      .update({ whatsapp: newWhatsApp })
      .eq('id', user.id)
    
    if (!error) {
      setProfile({ ...profile, whatsapp: newWhatsApp })
      setShowWhatsAppModal(false)
    } else {
      alert('Error al guardar: ' + error.message)
    }
    setSavingWhatsApp(false)
  }

  // Redirección forzada si no hay usuario (Capa de Seguridad)
  useEffect(() => {
    if (sheetsReady && !user && ruta !== 'login') {
      navegar('login')
    }
    // Si ya hay usuario y está en login, mandarlo al inicio
    if (sheetsReady && user && ruta === 'login') {
      navegar('inicio')
    }
  }, [user, ruta, sheetsReady])

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

  const handleLogout = async () => {
    await supabase.auth.signOut()
    sessionStorage.removeItem('jk_admin_auth')
    setAuth(false)
    navegar('inicio')
  }

  const handleMayorLogin = () => {
    setMayorAuth(true)
    navegar('mayor-inicio')
  }

  const handleMayorLogout = async () => {
    await supabase.auth.signOut()
    sessionStorage.removeItem('jk_mayor_auth')
    setMayorAuth(false)
    navegar('inicio')
  }

  // Branding dinámico
  const brandName = modoMayor ? 'Grupo JK Mayor' : 'CAMBIOS JK'

  if (!sheetsReady) {
    return (
      <div style={{ height: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'var(--bg-main)', color: 'white', flexDirection: 'column', gap: '1rem' }}>
        <div style={{ fontSize: '3.5rem', animation: 'spin 2s linear infinite', display: 'inline-block' }}>🚛</div>
        <p style={{ fontWeight: 700, fontSize: '1.1rem', letterSpacing: '0.05em' }}>Cargando el Camión...</p>
        <p style={{ fontSize: '0.8rem', color: 'var(--text-low)', marginTop: '-0.5rem' }}>GRUPO JK · Tasas en Tiempo Real</p>
        <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
      </div>
    )
  }

  // Si intenta acceder a rutas mayor sin estar autenticado → login
  if (modoMayor && !mayorAuth && ruta !== 'mayor') {
    // Redirigir a login mayor
    window.location.hash = '#/mayor'
    return <LoginMayor onLogin={handleMayorLogin} />
  }

  // Ruta exacta "mayor" = login
  if (ruta === 'mayor' && !mayorAuth) {
    return <LoginMayor onLogin={handleMayorLogin} />
  }
  if (ruta === 'mayor' && mayorAuth) {
    navegar('mayor-inicio')
  }

  // Determinar si mostrar navbar público
  const isAdminRoute = ruta === 'admin-jk' || ruta === 'admin'

  return (
    <div style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      
      {/* Navbar */}
      {!isAdminRoute && (
        <nav style={{
          height: 'var(--header-height)',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          padding: isMobile ? '0 1rem' : '0 2rem',
          background: 'rgba(6, 25, 52, 0.8)',
          backdropFilter: 'blur(12px)',
          borderBottom: '1px solid var(--glass-border)',
          position: 'sticky',
          top: 0,
          zIndex: 1000
        }}>
          <div 
            style={{ fontSize: isMobile ? '1.1rem' : '1.5rem', fontWeight: 800, color: 'white', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '0.4rem' }}
            onClick={() => navegar(modoMayor ? 'mayor-inicio' : 'inicio')}
          >
            <div style={{ width: isMobile ? '2rem' : '2.6rem', height: isMobile ? '2rem' : '2.6rem', borderRadius: '0.4rem', display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden', padding: '0.15rem' }}>
              <img src="./logo-jk-transparente.png" alt="Logo" style={{ width: '100%', height: '100%', objectFit: 'contain' }} />
            </div>
            <span>{brandName}</span>
          </div>
          
          <div style={{ display: 'flex', gap: isMobile ? '0.6rem' : '2rem', alignItems: 'center' }}>
            {modoMayor ? (
              <>
                <button onClick={() => navegar('mayor-inicio')} className={`nav-link ${ruta === 'mayor-inicio' ? 'active' : ''}`} style={{ background: 'none', border: 'none', fontSize: isMobile ? '0.8rem' : '1rem', cursor: 'pointer', padding: isMobile ? '0.3rem 0.5rem' : undefined }}>Inicio</button>
                <button onClick={() => navegar('mayor-cotizador')} className={`nav-link ${ruta === 'mayor-cotizador' ? 'active' : ''}`} style={{ background: 'none', border: 'none', fontSize: isMobile ? '0.8rem' : '1rem', cursor: 'pointer', padding: isMobile ? '0.3rem 0.5rem' : undefined }}>Cotizador</button>
                <button onClick={() => navegar('mayor-tasas')} className={`nav-link ${ruta === 'mayor-tasas' ? 'active' : ''}`} style={{ background: 'none', border: 'none', fontSize: isMobile ? '0.8rem' : '1rem', cursor: 'pointer', padding: isMobile ? '0.3rem 0.5rem' : undefined }}>{isMobile ? 'Tasas' : 'Lista de Tasas'}</button>
                <button onClick={handleMayorLogout} style={{ background: 'none', border: '1px solid var(--error-color)', borderRadius: '0.6rem', color: 'var(--error-color)', fontSize: '0.75rem', padding: '0.3rem 0.6rem', cursor: 'pointer', fontWeight: 700 }}>Salir</button>
              </>
            ) : (
              <>
                <button onClick={() => navegar('inicio')} className={`nav-link ${ruta === 'inicio' ? 'active' : ''}`} style={{ background: 'none', border: 'none', fontSize: isMobile ? '0.8rem' : '1rem', cursor: 'pointer', padding: isMobile ? '0.3rem 0.5rem' : undefined }}>Inicio</button>
                <button onClick={() => navegar('cotizador')} className={`nav-link ${ruta === 'cotizador' ? 'active' : ''}`} style={{ background: 'none', border: 'none', fontSize: isMobile ? '0.8rem' : '1rem', cursor: 'pointer', padding: isMobile ? '0.3rem 0.5rem' : undefined }}>Cotizador</button>
                <button onClick={() => navegar('mis-operaciones')} className={`nav-link ${ruta === 'mis-operaciones' ? 'active' : ''}`} style={{ background: 'none', border: 'none', fontSize: isMobile ? '0.8rem' : '1rem', cursor: 'pointer', padding: isMobile ? '0.3rem 0.5rem' : undefined }}>{isMobile ? 'Mis Cambios' : 'Mis Cambios'}</button>
                
                {user ? (
                   <button 
                    onClick={handleLogout}
                    style={{ 
                      background: 'rgba(239, 68, 68, 0.1)', 
                      border: '1px solid rgba(239, 68, 68, 0.2)', 
                      borderRadius: '0.6rem', 
                      color: '#ff4d4d', 
                      fontSize: '0.75rem', 
                      padding: '0.4rem 0.8rem', 
                      cursor: 'pointer', 
                      fontWeight: 700,
                      display: 'flex',
                      alignItems: 'center',
                      gap: '0.4rem'
                    }}
                  >
                     <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
                     Salir
                  </button>
                ) : (
                  <button 
                    onClick={() => navegar('login')}
                    className="btn-primary"
                    style={{ fontSize: '0.8rem', padding: '0.5rem 1rem', borderRadius: '0.7rem' }}
                  >
                    Ingresar
                  </button>
                )}
              </>
            )}
          </div>
        </nav>
      )}

      {/* Modal Inteligente de WhatsApp */}
      {showWhatsAppModal && (
        <div style={{
          position: 'fixed',
          top: 0, left: 0, right: 0, bottom: 0,
          background: 'rgba(0,0,0,0.85)',
          backdropFilter: 'blur(8px)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          zIndex: 9999, padding: '2rem'
        }}>
          <div className="glass" style={{ maxWidth: '400px', width: '100%', padding: '2.5rem', textAlign: 'center' }}>
            <div style={{ fontSize: '3.5rem', marginBottom: '1rem' }}>📱</div>
            <h3 style={{ fontSize: '1.5rem', marginBottom: '0.8rem', color: 'white' }}>¡Solo un paso más!</h3>
            <p style={{ color: 'var(--text-low)', fontSize: '0.9rem', marginBottom: '1.5rem' }}>
              Para procesar tus cambios necesitamos tu número de WhatsApp. Solo lo usaremos para notificarte sobre tus envíos.
            </p>
            <form onSubmit={handleSaveWhatsApp}>
              <input
                type="text"
                required
                placeholder="Ej: +593 987 654 321"
                className="input-field"
                value={newWhatsApp}
                onChange={e => setNewWhatsApp(e.target.value)}
                style={{ marginBottom: '1.5rem', textAlign: 'center', fontSize: '1.1rem' }}
                autoFocus
              />
              <button
                type="submit"
                disabled={savingWhatsApp}
                className="btn-primary"
                style={{ width: '100%', padding: '1rem', fontSize: '1rem' }}
              >
                {savingWhatsApp ? 'Guardando...' : '💰 Completar Registro'}
              </button>
            </form>
          </div>
        </div>
      )}

      {/* Main Content */}
      <main style={{ flex: 1 }}>
        {/* DETAL */}
        {ruta === 'inicio' && <Dashboard onNavegar={navegar} modo="detal" />}
        {ruta === 'cotizador' && <Cotizador modo="detal" />}
        {ruta === 'tasas' && <ListaPaises modo="detal" />}
        {ruta === 'mis-operaciones' && <MisOperaciones />}
        {ruta === 'login' && <Auth onLogin={() => navegar('inicio')} />}
        
        {/* MAYOR */}
        {ruta === 'mayor-inicio' && mayorAuth && <Dashboard onNavegar={navegar} modo="mayor" />}
        {ruta === 'mayor-cotizador' && mayorAuth && <Cotizador modo="mayor" />}
        {ruta === 'mayor-tasas' && mayorAuth && <ListaPaises modo="mayor" />}

        {/* ADMIN */}
        {ruta === 'admin-jk' && (
          !auth ? <LoginAdmin onLogin={handleLogin} /> : <AdminPanel onLogout={handleLogout} />
        )}
        
        {ruta === 'admin' && (
          auth ? <AdminPanel onLogout={handleLogout} /> : <LoginAdmin onLogin={handleLogin} />
        )}
      </main>

      {/* Footer */}
      {!isAdminRoute && (
        <footer style={{
          textAlign: 'center',
          padding: '2rem',
          borderTop: '1px solid var(--glass-border)',
          color: 'var(--text-low)',
          fontSize: '0.85rem',
          background: 'rgba(0,0,0,0.2)'
        }}>
          <div style={{ marginBottom: '1.5rem' }}>
            <p style={{ marginBottom: '0.8rem', fontSize: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.1rem' }}>Atención al Cliente:</p>
            <div style={{ display: 'flex', justifyContent: 'center', gap: '1rem', flexWrap: 'wrap' }}>
              <a 
                href="https://wa.me/593961230380" 
                target="_blank" 
                rel="noreferrer" 
                style={{ 
                  background: '#25D366', color: 'white', padding: '0.5rem 1rem', 
                  borderRadius: '0.6rem', fontSize: '0.75rem', textDecoration: 'none', 
                  fontWeight: 700, display: 'flex', alignItems: 'center', gap: '0.4rem' 
                }}
              >
                🟢 Kelvin
              </a>
              <a 
                href="https://wa.me/593998053300" 
                target="_blank" 
                rel="noreferrer" 
                style={{ 
                  background: '#25D366', color: 'white', padding: '0.5rem 1rem', 
                  borderRadius: '0.6rem', fontSize: '0.75rem', textDecoration: 'none', 
                  fontWeight: 700, display: 'flex', alignItems: 'center', gap: '0.4rem' 
                }}
              >
                🟢 Dario
              </a>
            </div>
          </div>
          <p>© {new Date().getFullYear()} {brandName}. Todos los derechos reservados.</p>
          <p style={{ marginTop: '0.5rem' }}>
            <span style={{ cursor: 'pointer', opacity: 0.3 }} onDoubleClick={() => navegar('admin-jk')}>⚡</span>
          </p>
        </footer>
      )}

    </div>
  )
}

export default App
