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
  1. El bot le envía el sticker de confirmación: **"RST Recibido"** (alojado en `https://grupojk-cambios.github.io/grupojk-conversor/logos/sticker-rst-recibido.webp`).
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

---

## 7. Monitoreo de Vigencia y Alertas Preventivas de Vencimiento (RST)

Cada código de retiro (RST) tiene una vigencia establecida por la entidad bancaria. El bot debe registrar el momento exacto en que ingresa el código para supervisar su estado y avisar al cobrador antes de que expire.

### Tabla de Duración por Banco y Horarios de Alerta
| Banco | Duración del Código (RST) | Tiempo de Alerta Previa |
| :--- | :--- | :--- |
| **Banco Pichincha** | 4 horas | 1 hora antes de vencer (a las 3 hrs) |
| **Banco del Pacífico** | 4 horas | 1 hora antes de vencer (a las 3 hrs) |
| **Banco Guayaquil** | 24 horas | 1 hora antes de vencer (a las 23 hrs) |
| **Produbanco** | 24 horas | 1 hora antes de vencer (a las 23 hrs) |
| **Banco Bolivariano** | Hasta las 9:00 PM del mismo día | 1 hora antes (a las 8:00 PM) |
| **Cooperativa JEP** | 15 minutos | A los 5 a 7 minutos de recibido |

### Reglas de Detección de Cobro y Alerta
1. **Guardar Timestamp:** El bot almacena la fecha y hora exacta en que el RST fue recibido en el chat/grupo del cliente.
2. **Identificación de Estado por Reacción / Emojis:**
   - **Cobrado:** El mensaje del código en el grupo del banco cuenta con un emoji de reacción (cualquiera, por ejemplo: ✅, 👍, 💵, etc., **excepto** la `❌`).
   - **No cobrado / Pendiente / Dañado:** No tiene reacción, o tiene la `❌` (que indica que se dañó o requiere verificar).
3. **Disparo de la Alerta al Grupo del Banco:**
   - Cuando falta 1 hora para el vencimiento (o el tiempo proporcional en JEP) y el código **NO** tiene emoji de cobrado:
   - El bot cita el mensaje del RST en el grupo correspondiente (ej: Grupo Pichincha) y publica:
   > *"⚠️ ¡Pendiente! Este código está por vencerse, le queda poco tiempo. Favor proceder con el retiro en cajero."*
   - De esta manera el cobrador sabe que debe acudir de inmediato al cajero antes de que el código quede inútil.

### Cómo lo hace el bot (implementado)
- **Qué vigila:** todo RST que está en el grupo de su banco: tanto el que **publica el bot** como el que **alguien pega a mano**. Solo los bancos de la tabla de arriba (Pichincha, Pacífico, Guayaquil, Produbanco, Bolivariano y JEP). De Solidario, Austro e Internacional el manual no dice cuánto duran, así que **no se vigilan**. Los RCT (retiro con tarjeta) tampoco: no tienen código que se venza.
- **Cuándo cuenta el reloj:** desde que el cliente envió el código. Un RST de Guayaquil o Produbanco que esperó en COBRAR MAÑANA se vigila desde el momento en que el cliente lo mandó (no desde que se pasó a su banco).
- **Cobrado o no:** lo marca el cobrador con una **reacción** al mensaje (cualquier emoji menos la ❌ = cobrado; ❌ = no cobrado; quitar la reacción lo devuelve a pendiente). También se entiende un emoji (o la palabra "cobrado") escrito como respuesta que cita el RST.
- **Se anula la alerta** si el RST quedó cobrado, o si el banco citó el mensaje con "verificar / corregir" o "se dañó" (el cliente ya manda uno nuevo, no tiene sentido avisar de un código que se reemplaza).
- **❌ + "Verificar":** si el cobrador pone la ❌ **y** cita el mensaje con "Verificar" (en cualquier orden), manda el "Verificar": el bot le pide al cliente que corrija y envíe de nuevo (Caso A de la sección 3) y **no** avisa de vencimiento de ese código. Una ❌ sola, sin "Verificar" ni "se dañó", **sí** genera la alerta (no cobrado). Para escribirle al cliente, el bot tiene que haber publicado él mismo ese RST; si alguien lo pegó a mano en el grupo, el bot solo anula la alerta.
- **Solo en horario de atención** (lunes a sábado 9:00–18:00, domingo 10:00–14:00). Si la alerta toca de noche y el código sigue vivo cuando abrimos, se avisa al abrir; si ya se venció, no se avisa.
- **Bolivariano:** vence a las 9:00 pm del mismo día, así que avisa a las 8:00 pm. Si el código llegó cuando ya faltaba menos de 1 hora, avisa 10 minutos después.
- **JEP:** a los **5 minutos** de recibido (el bot revisa cada 2 minutos, así que el aviso llega entre los 5 y los 7).
- **Arranca en ensayo:** la alerta no se escribe en ningún banco; aparece como vista previa en el grupo de avisos ("🧪 ENSAYO — la alerta iría a PICHINCHA…"). Cuando Kelvin revise y dé su OK, se pasa a real.


---

## 8. Fuera de horario: grupo COBRAR MAÑANA (regla de Kelvin, 24/11/2026)

El horario de atención es de **lunes a sábado de 9:00 a 18:00** y el **domingo de 10:00 a 14:00** (hora de Ecuador). Las duraciones de cada código están en la tabla de la sección 7; aquí se explica qué hace el bot con un RST que llega **fuera de horario**.

### En horario
El bot publica el RST/RCT **directo en el grupo del banco** correspondiente.

### Fuera de horario
El bot lo publica en el grupo **COBRAR MAÑANA**, con el mismo formato de siempre. Qué pasa después depende de cuánto dura el código del banco:

| Banco | Duración del código | Qué hace el bot de noche |
|---|---|---|
| **Pichincha, Pacífico** (4 h), **Bolivariano** (hasta las 9 pm) | Se vence **el mismo día** | Publica en COBRAR MAÑANA con el aviso **"⚠️ COBRAR HOY para que no se venza"**, para que el cobrador lo lea y lo cobre ese mismo día. **Se queda ahí** (no se pasa al banco al otro día). |
| **Solidario, Austro, Internacional** (y cualquier banco nuevo) | Se tratan como **el mismo día** por seguridad | Igual que los anteriores. |
| **JEP** (15 min) | Se vence en minutos: de noche el código no sirve | **No se publica ningún código.** El bot le dice al cliente cuándo abrimos y, al abrir, le pide al cobrador que vaya a un cajero (ver sección 10). |
| **Guayaquil, Produbanco** | Duran **24 horas** | Publica en COBRAR MAÑANA **sin** el aviso. Al abrir (lunes a sábado 9:05, domingo 10:05) el bot lo **pasa a su grupo del banco**. |

- Un RST de Guayaquil o Produbanco que lleve **más de 36 horas** esperando ya está vencido: el bot **no lo pasa** y avisa en el grupo de avisos para pedirle uno nuevo al cliente.
- Los **RCT** (retiro con tarjeta) siguen la misma regla por banco.
- Un banco que **no tiene grupo** (por ahora, 23 de Julio): el bot no publica nada y avisa en el grupo de avisos.

### Cómo arranca (modo ensayo)
Al principio el bot **no escribe a ningún banco ni cliente**: cada RST que entiende lo muestra como vista previa en el grupo de avisos ("🧪 ENSAYO — iría a PICHINCHA: …", con los códigos tapados). Cuando Kelvin revise las vistas previas y dé su OK, se enciende de verdad en un grupo de cliente primero.

---

## 9. Longitud Exacta de Códigos por Banco y Clave Temporal en Vivo (Solidario)

Para validar que los datos del retiro vengan completos y sin errores de tipeo, el bot debe verificar la cantidad exacta de dígitos según la entidad bancaria:

| Banco | Cantidad de Dígitos | Ejemplo | Notas Adicionales |
| :--- | :--- | :--- | :--- |
| **Banco Pichincha** | 4 dígitos | `2938` | — |
| **Produbanco** | 6 dígitos | `159753` | — |
| **Banco Guayaquil** | Dos códigos de 4 dígitos cada uno | `C1: 3467` / `C2: 4598` | Siempre deben venir ambos (C1 y C2) |
| **Banco del Pacífico** | 6 dígitos | `474927` | — |
| **Banco Solidario** | 6 dígitos + Clave Temporal en vivo | `874454` + `919180` | Ver flujo especial de cajero abajo |
| **Banco Bolivariano** | **6 dígitos** u **8 dígitos** (2 formas exactas) | `068521` / `57913864` | Solo 6 u 8 dígitos (no de 7) |
| **Cooperativa JEP** | Código: 6 dígitos + Clave: 4 dígitos | `OTP: 332625` / `Clave: 1964` | Ambos campos son obligatorios |

### Flujo Especial: Segundo Código / Clave Temporal en Vivo (Banco Solidario)
Cuando el cobrador está frente al cajero retirando un RST de **Banco Solidario**, al ingresar los datos iniciales el banco envía en ese instante una clave temporal por SMS al cliente:

1. **Aviso del Cobrador en Grupo Solidario:** El cobrador cita el RST en el grupo Solidario y escribe palabras clave como: `"temporal"`, `"código temporal"`, `"segundo código"` o similar.
2. **Solicitud Inmediata al Cliente:** El bot acude al grupo/chat del cliente, **cita el RST original** y le pide que envíe de inmediato el código temporal que le acaba de llegar en ese momento.
3. **Respuesta del Cliente:** El cliente reenvía el texto del banco o los dígitos (ejemplo real: *"B. Solidario te informa tu clave temporal para retiro de efectivo es 919180, recuerda que esta clave podra ser utilizada hasta 17:12"*).
4. **Confirmación y Entrega al Cajero:**
   - El bot le responde al cliente: **"Ok, recibido"**.
   - Acto seguido, el bot reenvía ese mismo texto/clave al **Grupo Solidario**, **citando el RST en cuestión**, para que el cobrador pueda ingresarlo de inmediato en el cajero antes de que expire.

### Cómo lo hace el bot (implementado)
**Largo de los códigos**
- Si el cliente manda un código con un largo distinto al de la tabla, el bot **no lo publica**: le responde citando su mensaje, por ejemplo *"Revisa tu RST de Pichincha: el código debe tener 4 dígitos. Corrígelo y envíalo de nuevo con todos los datos en un solo texto, por favor."* (Bolivariano: *"debe tener 6 u 8 dígitos"*; Guayaquil revisa el código 1 y el 2 por separado; JEP revisa el código y la clave de la tarjeta).
- Si además falta algún dato, lo dice todo en el mismo mensaje.
- Solo se revisan los bancos de la tabla. Austro e Internacional no tienen regla de largo y se publican como siempre. El RCT no tiene código, no se revisa.

**Clave temporal de Solidario**
- Para que funcione, **el RST tiene que haberlo publicado el bot** en el grupo Solidario (así sabe de qué cliente es). Si alguien lo pegó a mano, el bot no puede saber a quién pedirle la clave.
- El cobrador cita el RST y escribe `"temporal"`, `"código temporal"`, `"segundo código"` o `"segunda clave"`. El bot responde en el grupo *"ok, se lo pido al cliente"* y le escribe al cliente (citando su RST): *"Por favor envíame de inmediato el código temporal que te acaba de llegar."*
- Desde ese momento el bot espera esa clave **15 minutos**. Cuando el cliente manda **un solo número de 6 dígitos** (solo los dígitos, o el mensaje completo del banco), el bot reenvía **ese mismo texto** al grupo Solidario **citando el RST** y le dice al cliente *"Ok, recibido"*.
- Si el cliente manda en cambio un **RST nuevo y completo**, se trata como RST, no como clave temporal. Si manda dos números de 6 dígitos distintos, no adivina cuál es: no hace nada. La clave se entrega **una sola vez**.

---

## 10. Cooperativa JEP: el cliente genera el RST cuando el cobrador ya está en el cajero (regla de Kelvin, 24/11/2026)

El código de JEP dura solo **15 minutos**. Por eso el cliente **no debe generarlo antes de tiempo**: el bot espera a que el cobrador esté parado frente al cajero.

### Flujo paso a paso
1. **El cliente quiere hacer (o manda) un RST de JEP** (con datos o solo diciendo "quiero retirar por JEP"). Aunque ya traiga el código, **el bot NO lo publica**.
2. **El bot le responde al cliente**, citando su mensaje:
   > *"Te avisamos cuando el cobrador esté en el cajero, para que realices el RST."*
3. **El bot le pide al cobrador, en el grupo de JEP** (COOP JEP), que vaya a un cajero y avise:
   ```text
   🏧 Cobrador: ir a un cajero y avisar aquí, citando este mensaje, cuando estés para indicarle al cliente que haga el RST.

   Cliente: Nombre del Cliente
   Monto: 300$
   ```
4. **El cobrador va al cajero**, **cita ese mensaje del bot** y escribe que ya llegó: `"listo, ya estoy acá"`, `"llegué"`, `"pide el RST"`, etc.
5. **El bot confirma en el grupo** (*"ok, ya le aviso al cliente"*) y **le avisa al cliente**, citando su mensaje:
   > *"El cobrador ya está en el cajero. Realiza tu RST ahora y envíame todos los datos en un solo texto."*
6. **El cliente genera el RST y manda todos los datos** (banco, monto, OTP, cédula, clave de la tarjeta). El bot lo publica **de inmediato** en el grupo COOP JEP (con el formato de siempre) y le manda el sticker "RST Recibido". En ese momento empieza a correr la alerta de vencimiento de JEP (a los 5 minutos si nadie lo marcó como cobrado, sección 7).

### Detalles
- El permiso del cobrador dura **30 minutos**; sirve para **un solo** RST (el siguiente pedido repite el proceso).
- Si el cliente vuelve a escribir mientras espera, el bot le dice: *"Ya avisamos al cobrador. Te escribimos apenas esté en el cajero."* y **no** vuelve a molestar al cobrador.
- Si el cobrador responde algo que no es "ya llegué" ("no hay cajero", "todavía no"), el bot no le avisa al cliente.
- **Si el cobrador no contesta en 30 minutos**, el bot avisa en el grupo de **avisos** ("⚠️ JEP: el cobrador todavía no avisa que llegó al cajero. Lleva 30 minutos esperando: …") para que alguien de la oficina lo llame. Cuenta desde que el pedido sale al grupo de JEP (de noche, desde que abre). Si el cobrador contesta "listo" citando el pedido, o reacciona a ese mensaje, queda atendido y no se avisa.
- Si el cliente manda los datos incompletos después del aviso del cobrador, el bot le pide lo que falta (no vuelve a llamar al cobrador).
- **Fuera de horario:** el bot le dice al cliente cuándo abrimos (*"Te avisamos cuando el cobrador esté en el cajero, mañana a partir de las 9:00 am, para que realices el RST."*) y, al abrir, publica el pedido al cobrador en el grupo de JEP (workflow de la mañana).
- El **RCT** de JEP (retiro con tarjeta) **no** pasa por este proceso: va directo al grupo como los demás bancos.

