# React + Vite

This template provides a minimal setup to get React working in Vite with HMR and some ESLint rules.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Oxc](https://oxc.rs)
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/)

## React Compiler

The React Compiler is not enabled on this template because of its impact on dev & build performances. To add it, see [this documentation](https://react.dev/learn/react-compiler/installation).

## Expanding the ESLint configuration

If you are developing a production application, we recommend using TypeScript with type-aware lint rules enabled. Check out the [TS template](https://github.com/vitejs/vite/tree/main/packages/create-vite/template-react-ts) for information on how to integrate TypeScript and [`typescript-eslint`](https://typescript-eslint.io) in your project.

---

# Cambios JK — motor de cálculo y despliegue del bot

## El motor de tasas vive en UN solo archivo

Todas las matemáticas de tasas y cruces están **solo** en [`src/motor.js`](src/motor.js).

- La **app** lo usa porque `src/constants.js` lo re-exporta. Los demás archivos lo siguen
  importando desde `constants.js` igual que siempre.
- El **bot de WhatsApp** lo usa porque `build_v12.ps1` lee ese archivo y lo **inyecta** dentro de
  los dos nodos de n8n (`Code in JavaScript` y `Calculadora de Conversion`).

**Si hay que cambiar una fórmula, se toca únicamente `src/motor.js`.** No hagas una segunda copia:
antes había tres (app + 2 nodos), se despegaron y el bot llegó a dar **101 USD por 100 EUR a Zelle
cuando lo correcto eran 95,04** — eran 581 diferencias en producción y nadie se dio cuenta.

## El candado

```bash
npm run verificar-motor
```

Compara el motor de la app contra el **código real** que tiene el bot y **falla (exit 1)** si no dan
lo mismo. Está enganchado en dos sitios, así que corre solo:

- en `predeploy`, así que gatea `npm run deploy` de la app;
- en el paso 1 de `scripts/desplegar_bot.ps1`, así que gatea el despliegue del bot.

## Desplegar el bot

```bash
powershell -ExecutionPolicy Bypass -File scripts\desplegar_bot.ps1
```

Antes hay que generar el JSON:

```bash
powershell -ExecutionPolicy Bypass -File build_v12.ps1
```

El script de despliegue verifica el motor, revisa el encoding, conserva la posición de los nodos y
las credenciales del workflow vivo, sube con `WebClient` + UTF-8 y vuelve a bajar todo para
comprobar que no quedó nada corrupto. **No cambia el estado activo/inactivo** del workflow.

## Dos trampas de encoding (ya resueltas, no las reintroduzcas)

1. **Los `.ps1` con texto en español necesitan BOM UTF-8.** PowerShell 5.1 lee un `.ps1` sin BOM
   como Windows-1252 y rompe tildes y emojis *antes* de que salgan del script.
2. **Nunca uses `Invoke-RestMethod` / `Invoke-WebRequest`** para subir a n8n: destruyen los emojis
   en silencio. Solo `System.Net.WebClient` con `Encoding = UTF8`.
