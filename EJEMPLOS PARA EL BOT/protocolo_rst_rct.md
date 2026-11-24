# PROTOCOLO Y EJEMPLOS DE RETIROS (RST Y RCT) PARA EL BOT DE WHATSAPP

Este documento recopila las reglas operativas, flujos de atención, formatos de mensaje, manejo de incidencias y ejemplos prácticos para el procesamiento de retiros sin tarjeta (RST) y retiros con tarjeta (RCT) en Grupo JK.

---

## 1. Terminología y Nombres Clave

- **RST:** Retiro Sin Tarjeta.
- **RCT:** Retiro Con Tarjeta.
- **Sinónimos comunes:** Códigos, Retiros, RST, RCT.

---

## 2. Flujo Operativo y Protocolo de Mensajería

### Paso 1: Recepción del Código del Cliente
- Cuando el cliente envía los datos del retiro / código:
  1. El bot le envía el sticker de confirmación: **"RST Recibido"**.
  2. Inmediatamente el bot procede a redirigir los datos al **grupo del banco correspondiente** (Pichincha, Guayaquil, Produbanco, Pacífico, etc.).

### Paso 2: Formato de Envío al Grupo del Banco
Los datos se envían en un solo bloque estructurado con el nombre del cliente en la cabecera:

```text
(Nombre del Cliente
BANCO
Monto: XXX$
Código: XXXXXX
Cedula: XXXXXXXXXX
Teléfono: XXXXXXXXXX)
```

**Ejemplo real enviado al grupo:**
```text
(Julio E
PACÍFICO
Monto: 100$
Código: 474927
Cedula: 0966218349
Teléfono: 0983305361)
```

---

## 3. Manejo de Errores, Daños y Excepciones

### Caso A: Mensaje de "Verificar" o "Corregir" en el Grupo del Banco
Ocurre cuando el cajero falla, hay un error de tipeo del cliente o la entidad rechaza los datos:
1. El operador en el grupo del banco cita el RST y escribe: `"Verificar"`, `"Corregir"` o similar.
2. **Respuesta del Bot en el Grupo del Banco:**
   > *"ok, procedo a mandar a verificar y corregir"*
3. **Acción del Bot hacia el Cliente:**
   - El bot cita el mensaje original del RST del cliente y le responde:
   > *"Por favor verifique, corrija y envíe nuevamente todos los datos en un solo texto."*
   *(Se procesa como un RST nuevo una vez que el cliente responda).*

### Caso B: Códigos Dañados o Expirados ("Se dañó o salió dañado")
1. El operador en el grupo del banco cita el RST e indica: `"Se dañó"` o `"Salió dañado"`.
2. **Acción del Bot hacia el Cliente:**
   - El bot cita el código del cliente y le notifica que el retiro no pudo ser cobrado porque se dañó/venció, solicitando que genere uno nuevo:
   > *"Estimado cliente, su código se dañó / no pudo ser cobrado. Por favor genere un nuevo código de retiro para poder saldar el saldo pendiente."*

### Caso C: Control de Estados Visuales (Cobrados y No Cobrados)
- **Cobrados:** Se marcan con emojis variados de éxito/aprobado.
- **No cobrados:** Se marcan con el emoji `❌️`.
- **Regla obligatoria:** Toda actualización debe ir citando el mensaje original para garantizar el rastreo en caso de que no se puedan leer los emojis.

---

## 4. Reglas Críticas de Entrada y Reconocimiento de Datos

1. **Orden Indiferente:** Los datos pueden venir en cualquier orden (ejemplo: primero monto, luego código, luego cédula, etc.).
2. **Abreviaturas y Variantes Permitidas:**
   - **Banco:** Debe indicar el banco claramente (Pichincha, Guayaquil, Produbanco, Pacífico, JEP, Bolivariano, Solidario, Austro, etc.).
   - **Teléfono:** `tlf`, `tele`, `número`, `whatsapp`, `telef`, `tel`, `celular`, `cel`.
   - **Código:** `código`, `codigo`, `cod`, `c`, `c1`, `c2`, `otp`.
   - **Monto:** `monto`, `dolar`, `dólar`, `$`, `cantidad`, `cantida`.
   - **Cédula:** `cédula`, `cedula`, `ced`, `cedu`, `ci`, `c.i`.
   - **Clave tarjeta:** `clave tarjeta`, `clave`, `tarjeta`.
3. **Formato Simple sin Etiquetas (Solo Valores):**
   El bot debe poder inferir los campos aun cuando vengan sin etiquetas descriptivas.
   *Ejemplo Guayaquil posicional:*
   ```text
   Guayaquil 
   0961230380
   2345
   6543
   0963893557
   500
   ```
4. **PROHIBIDO FOTOS EN RST:**
   - Si el cliente envía una captura de pantalla o foto del retiro, el bot **no debe procesarla por imagen**.
   - Mensaje del bot al cliente:
   > *"Por favor envíe todos los datos en texto escrito para poder procesar su retiro."*

---

## 5. Catálogo de Bancos y Campos Requeridos

### 1. PRODUBANCO (RST)
**Campos requeridos:** Banco, Cédula, Código, Monto.
```text
Banco: PRODUBANCO
C.I: 1760471688
Código: 175588
Monto: 130$
```

### 2. BANCO DEL PACÍFICO (RST)
**Campos requeridos:** Banco, Cédula, Código, Teléfono, Monto.
```text
PACÍFICO
Monto: 100$
Código: 474927
Cedula: 0966218349
Teléfono: 0983305361
```

### 3. BANCO PICHINCHA (RST)
**Campos requeridos:** Banco, Teléfono, Código, Monto.
```text
Pichincha
Código: 5478
Teléfono: 0963192843
Monto: $200
```

### 4. BANCO GUAYAQUIL (RST)
**Campos requeridos:** Banco, Teléfono, Código 1 (C1), Código 2 (C2), Monto.
```text
Banco: Guayaquil 
C1: 2403 
C2: 2790
Teléfono: +593 98 769 6470
Monto: 500
```

### 5. COOPERATIVA JEP (RST)
**Campos requeridos:** Banco, Cédula, Código/OTP, Monto, Clave tarjeta.
```text
BANCO: Jep
Monto: $300
OTP: 796988
CI: 2100501937
Clave: 1111
```

### 6. BANCO SOLIDARIO (RST)
**Campos requeridos:** Banco, Cédula, Teléfono, Código, Monto.
```text
Banco: solidario
Monto: 100
Tlf: 0999703523
Cedula: 1759977968
Codigo: 874454
```

### 7. BANCO BOLIVARIANO / QUICKPAY (RST)
**Campos requeridos:** Banco, Cédula, Celular/Teléfono, Código, Monto.
```text
Banco Bolivariano
QuickPay
Monto: 380
Código: 068521
Celular: 0979460155
Cédula: 0953489960
```

---

## 6. Retiros Con Tarjeta (RCT)

Para los retiros con tarjeta (RCT) de cualquier banco, únicamente se necesita el **Banco** y el **Monto**, señalando expresamente que es con tarjeta:

### Ejemplo AUSTRO (RCT):
```text
Austro
*Retira con tarjeta*
Monto 500$
```

### Ejemplo PICHINCHA (RCT con Operadora Asignada):
```text
⚠️⚠️ *PICHINCHA* ⚠️⚠️
       👩🏻🦱Miser👩🏻🦱

*Retira con tarjeta*
Monto 500$
```
