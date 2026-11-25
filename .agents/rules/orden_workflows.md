---
trigger: always_on
---

# Regla Obligatoria: Estructura y Orden Visual de Nodos en Workflows (n8n / Automatizaciones)

Cada vez que se cree, modifique o reestructure un workflow o archivo JSON de automatización:

1. **Numeración Secuencial de Nodos (1 a Infinito):**
   - Todo nodo DEBE tener un prefijo numérico ordenado que indique su posición en el flujo:
     - `1. Webhook Entrada`
     - `2. Validar Datos`
     - `3. Consultar Redis`
     - `4. Enviar Mensaje`
   - Si hay ramas o condicionales (If / Switch), se numeran manteniendo la coherencia (ej: `5a. Opción Sí`, `5b. Opción No` o `5.1`, `5.2`).

2. **Orden Lógico y Dirección:**
   - El flujo debe avanzar siempre de izquierda a derecha de forma limpia y legible.
   - Nodos de soporte o herramientas (ej. Memory, Tools de IA) deben ubicarse alineados debajo de su nodo principal.

3. **Separación y Espaciado Fijo en Canvas (Coordenadas [X, Y]):**
   - Ningún nodo puede quedar superpuesto o pegado.
   - Mantener una distancia horizontal fija (mínimo 200 a 250 píxeles entre nodos en el eje X).
   - Mantener una distancia vertical clara (mínimo 120 a 160 píxeles en el eje Y) para ramas paralelas.
