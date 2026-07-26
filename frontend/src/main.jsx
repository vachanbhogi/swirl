import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
import NotchOverlay from './components/NotchOverlay.jsx'

const isNotchWindow = window.location.hash === '#/notch' || window.location.pathname === '/notch';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    {isNotchWindow ? <NotchOverlay /> : <App />}
  </StrictMode>,
)
