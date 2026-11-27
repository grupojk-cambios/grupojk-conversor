# Protocolo para Pedidos y Datos Bancarios por País — Grupo JK

Guía de entrenamiento y referencia para que el Bot de WhatsApp identifique, valide y formatee correctamente los pedidos de clientes antes de enviarlos a los grupos de operadoras de cada país.

> **Privacidad:** Las capturas reales de WhatsApp referenciadas en este documento se guardan en la carpeta local `privado/` (excluida en `.gitignore`, **no se sube a GitHub**). Todos los ejemplos de texto incluidos en este archivo están anonimizados.

---

## 1. Reglas Generales (APLICAN A TODOS LOS PAÍSES)

### 1.1. Campos estándar de un pedido bancario
En general, todo pedido bancario debe traer:
- **Cuenta / billetera / destino** (número de cuenta, CBU/CVU/Alias, Yape, Nequi, RUT, etc.)
- **Nombre y apellido** del titular (o razón social)
- **Cédula / documento de identidad** (C.I., DNI, RUT, CUIT/CUIL, Carnet de Extranjería, según país)
- **Monto en USD (`$`)**
- **Monto en moneda local** (Bs, Soles, ARS, CLP, COP, etc.)

> **Orden libre:** Los clientes envían los datos en el orden que prefieren (en 1, 2 o más mensajes). El bot debe extraer los campos sin exigir una plantilla fija.

### 1.2. Nombre del cliente siempre en la cabecera
Al pasar un pedido a los grupos de operadoras (tanto en **Detal** como en **Mayor**), **siempre debe ir el nombre del cliente en la cabecera del mensaje** (primera línea del pedido), seguido de la modalidad si aplica (`RST`, `EST`, etc.) y luego los datos bancarios.

Ejemplo de cabecera esperada:
```text
NOMBRE DEL CLIENTE
RST

[Datos bancarios del beneficiario]
[Monto $ y monto en moneda local]
```

### 1.3. Identificación y confirmación obligatoria del país
El bot puede inferir el país leyendo cualquiera de estas señales:
- **Nombre del país** (ej. Colombia, Perú, Chile, Argentina, Venezuela)
- **Nombre de la moneda** (ej. pesos colombianos, soles, bolívares, pesos chilenos, pesos argentinos)
- **Código ISO de moneda** (ej. `COP`, `PEN`, `VES`, `CLP`, `ARS`, `BRL`, `PYG`, `UYU`, `BOB`, `MXN`, `DOP`, `EUR`, `USD`, `USDT`)
- **Bandera del país** (`🇨🇴`, `🇵🇪`, `🇻🇪`, `🇨🇱`, `🇦🇷`, etc.)
- **Bancos más populares (top ~6 por país) o redes/billeteras reconocidas** (Yape, Plin, Pago Móvil, Zelle, Yappy, Nequi, Daviplata, Pix, SINPE Móvil, Mercado Pago, Brubank, Mach, CuentaRUT, etc.).

**Regla estricta — NO asumir sin confirmar:**
1. Si el cliente **no nombró explícitamente** el país y el bot lo deduce por el banco/red/moneda, **debe preguntar primero** antes de aprobar o cobrar:
   > *"¿Ese envío es para Colombia?"* (o el país deducido)
2. Esperar respuesta (**SÍ** o **NO**):
   - Si responde **SÍ**:
     - Si el pedido **ya está pago** → aprobar y enviar el **sticker de pedido aprobado**.
     - Si **aún no está pago** → proceder a pedir el pago.
   - Si responde **NO** (sin indicar el país correcto):
     - Volver a preguntar: *"¿Qué país es? Por favor nómbralo."*
     - Solo tras recibir y confirmar el país correcto, aprobar (si ya pagó) o pedir el pago (si falta el pago).

### 1.4. Formato estándar de 2do mensaje para Cajas Dólar / Divisas
Para los grupos de **Binance (USDT)**, **Zelle**, **Euros**, **Money Venezuela** y **Ecuador**, el resumen se envía como **2do mensaje** con la misma estructura:
```text
[Monto cobrado en USD con % aplicado]
[NOMBRE DEL CLIENTE]
[Ciudad/Estado si es Money Venezuela]
[Monto final a entregar]
```
La operadora responde **citando ese 2do mensaje** (donde aparece el nombre del cliente) con la foto del comprobante, y el bot reenvía el comprobante al cliente correspondiente.

---

## 2. Venezuela (`VES`)

### Reglas específicas
- **Validación obligatoria de cuenta:** Todas las cuentas bancarias en Venezuela tienen exactamente **20 dígitos** (pueden llegar pegados o con espacios/guiones; al limpiar separadores deben ser 20 dígitos).
- **Clientes del MAYOR:** Solo se aceptan **cuentas bancarias completas de 20 dígitos**. **NO se aceptan Pago Móviles.**
- **Enrutamiento a grupos de operadoras:**
  - **Grupo `BANESCO`** → únicamente cuentas Banesco (prefijo `0134...`).
  - **Grupo `VENEZUELA`** → cuentas Banco de Venezuela (prefijo `0102...`), **todas las interbancarias** de otros bancos (ej. Bicentenario `0175...`, Provincial `0108...`, Mercantil `0105...`, BNC `0191...`, Bancamiga `0172...`, etc.) y Pago Móvil (cuando aplique en Detal).

### Ejemplos de formato (anonimizados)

**Banco de Venezuela (`0102...`) → Grupo `VENEZUELA`:**
```text
CLIENTE EJEMPLO
RST

Banco Venezuela
Tipo de cuenta: VES
01020000000000000000
V12345678
Nombre Apellido
$800
794.880 bs
```

**Banesco (`0134...`) → Grupo `BANESCO`:**
```text
CLIENTE EJEMPLO
RST

01340000000000000000
BANESCO
NOMBRE APELLIDO
C.I. 12345678
bs 103.400
$100
```

**Interbancaria (ej. Bicentenario `0175...`) → Grupo `VENEZUELA`:**
```text
CLIENTE EJEMPLO
RST

01750000000000000000
Bicentenario
Nombre Apellido
Cédula 12345678
Bs 218.400
$226.26 (tomar en cuenta la comisión)
```

### Capturas reales de referencia (locales en `privado/venezuela/`)
- [Banco de Venezuela — Ejemplo 1](privado/venezuela/bdv_1.jpg)
- [Banco de Venezuela — Ejemplo 2 (cuenta con espacios)](privado/venezuela/bdv_2.jpg)
- [Banesco — Ejemplo 1](privado/venezuela/banesco_1.jpg)
- [Banesco — Ejemplo 2](privado/venezuela/banesco_2.jpg)
- [Interbancaria Bicentenario en grupo Venezuela](privado/venezuela/interbancaria_bicentenario.jpg)
- [Pago Móvil (referencia Detal — NO aceptado en Mayor)](privado/venezuela/pagomovil_ejemplo.jpg)

---

## 3. Entregas de Cash en Venezuela (`MONEY Venezuela`)

### Reglas específicas
- El destino/grupo se llama **`MONEY Venezuela`**.
- No importa el orden o formato exacto en que lleguen los datos, **lo obligatorio es que traiga los 5 datos**:
  1. **Monto a entregar en `$`**
  2. **Foto del documento de identidad** de quien recibe (sirve cualquiera: cédula, DNI, pasaporte, licencia o carnet)
  3. **Número de teléfono** de quien recibe
  4. **Ciudad / estado** de entrega
  5. **Nombre de quien envía**

### Plantilla de solicitud al cliente
```text
🇻🇪 REQUISITOS ENTREGA 🇻🇪
DOLARES EN VENEZUELA

1. Envío monto: 200 $
2. FOTO CEDULA: (📷 dni, carnet, cedula, pasaporte)
3. Número de quien recibe: 04240000000
4. Ciudad: Puerto La Cruz
5. Quien envía: Nombre Apellido

Rellenar este SMS ⚠️
```

### Formato de anotación en el grupo `MONEY Venezuela` (2do mensaje)
```text
107
Nombre Apellido (Cliente)
Mérida
100
```
*(Línea 1: dólares cobrados con % | Línea 2: nombre del cliente | Línea 3: ciudad y estado | Línea 4: dólares entregados en efectivo en Venezuela).*

### Capturas reales de referencia (locales en `privado/money_venezuela/`)
- [Money Venezuela — Ejemplo 1](privado/money_venezuela/money_ve_1.jpg)
- [Money Venezuela — Ejemplo 2](privado/money_venezuela/money_ve_2.jpg)
- [Money Venezuela — Ejemplo 3 (plantilla requisitos)](privado/money_venezuela/money_ve_3.jpg)
- [Money Venezuela — Ejemplo 4](privado/money_venezuela/money_ve_4.jpg)

---

## 4. Perú (`PEN`)

### Reglas específicas
- Grupo: **`PERÚ 🇵🇪`**.
- **Nombre del cliente siempre en la cabecera** del pedido (como en la foto 3).
- Bancos y billeteras principales: **Yape** (9 dígitos), **Plin**, **BCP** (cuenta soles y CCI interbancaria), **Interbank**, **BBVA Perú**, **Scotiabank**.

### Ejemplos de formato (anonimizados)
```text
NOMBRE DEL CLIENTE

Yape 900000000
Nombre Apellido
Monto 102 soles
```
```text
NOMBRE DEL CLIENTE

900 000 000 Nombre Apellido
Carnet de extranjería: 000000000
Yape
Perú 🇵🇪
75$
Tasa 3.32
249 soles
```

### Capturas reales de referencia (locales en `privado/peru/`)
- [Perú — Ejemplo 1 (Yape + comprobante BCP)](privado/peru/peru_1.jpg)
- [Perú — Ejemplo 2 (Yape + cuenta BCP Soles/CCI)](privado/peru/peru_2.jpg)
- [Perú — Ejemplo 3 (referencia de nombre en cabecera)](privado/peru/peru_3_cabecera.jpg)
- [Perú — Ejemplo 4 (Yape con Carnet de Extranjería)](privado/peru/peru_4.jpg)
- [Perú — Ejemplo 5 (Cuenta BCP Soles + CCI + comprobante)](privado/peru/peru_5_bcp.jpg)

---

## 5. Argentina (`ARS`)

### Reglas específicas
- Grupo: **`Argentina 🇦🇷`**.
- **Nombre del cliente siempre en la cabecera** del pedido.
- Datos habituales: Titular, **CUIT/CUIL**, **Alias** (ej. `nombre.bru.1234`, `12345678.PREX`), **CBU / CVU** (22 dígitos), número de cuenta, banco/billetera (**Brubank**, **Mercado Pago**, **Galicia**, **Banco Nación / BNA**, **PREX**, **Ualá**, **Santander**), monto en `$` y monto en **ARS / Pesos Argentinos**.

### Ejemplo de formato (anonimizado)
```text
NOMBRE DEL CLIENTE

Titular: Nombre Apellido
CUIT/CUIL: 27-00000000-4
Alias: nombre.bru.0000
CBU: 1430001713000000000000
Número de cuenta: 1300000000000
29.200 Pesos Argentinos
```

### Capturas reales de referencia (locales en `privado/argentina/`)
- [Argentina — Ejemplo 1 (Brubank + comprobante Galicia)](privado/argentina/argentina_1.jpg)
- [Argentina — Ejemplo 2 (BNA con CUIL, Alias y CBU)](privado/argentina/argentina_2.jpg)
- [Argentina — Ejemplo 3 (Brubank con CBU)](privado/argentina/argentina_3.jpg)
- [Argentina — Ejemplo 4 (Alias directo)](privado/argentina/argentina_4.jpg)
- [Argentina — Ejemplo 5 (PREX con CVU y Alias)](privado/argentina/argentina_5.jpg)

---

## 6. Chile (`CLP`)

### Reglas específicas
- Grupo: **`CHILE 🇨🇱`**.
- **Nombre del cliente siempre en la cabecera** del pedido.
- Datos habituales: Nombre completo, **RUT** (ej. `27.000.000-8` o `24.000.000-K`), banco (**Banco Estado / CuentaRUT**, **Mach - BCI**, **Banco de Chile**, **Santander**, **Banco Falabella**, **Scotiabank**), tipo de cuenta (Cuenta Corriente, Vista, CuentaRUT), número de cuenta, correo electrónico (frecuente en Chile), monto en `$` y monto en **CLP / pesos chilenos**.

### Ejemplo de formato (anonimizado)
```text
NOMBRE DEL CLIENTE

NOMBRE APELLIDO
27.000.000-8
Mach - BCI
Cuenta Corriente
777900000000
correo@ejemplo.com
18.240 clp
```

### Capturas reales de referencia (locales en `privado/chile/`)
- [Chile — Ejemplo 1 (Banco Estado CuentaRUT y BCI Mach)](privado/chile/chile_1.jpg)
- [Chile — Ejemplo 2 (Mach-BCI + comprobante)](privado/chile/chile_2.jpg)
- [Chile — Ejemplo 3 (Banco Estado Cuenta RUT/Vista)](privado/chile/chile_3.jpg)
- [Chile — Ejemplo 4 (Banco Estado CuentaRUT)](privado/chile/chile_4.jpg)

---

## 7. Colombia (`COP`)

### Reglas específicas
- Grupo: **`COLOMBIA 🇨🇴`**.
- **Nombre del cliente siempre en la cabecera** del pedido.
- Bancos y billeteras principales: **Nequi** (celular de 10 dígitos), **Bancolombia** (Ahorros/Corriente), **Daviplata**, **Davivienda**, **BBVA Colombia**, **Banco de Bogotá**.

### Ejemplos de formato (anonimizados)
```text
NOMBRE DEL CLIENTE

Nequi
3000000000
Nombre Apellido
100$
323.369 pesos
```
```text
NOMBRE DEL CLIENTE

Nombre Apellido
Cédula: 1000000000
Bancolombia Ahorros
00000000000
Enviar: 1.000.000 cop
```

### Capturas reales de referencia (locales en `privado/colombia/`)
- [Colombia — Ejemplo 1 (Nequi + comprobante recarga)](privado/colombia/colombia_1.jpg)
- [Colombia — Ejemplo 2 (Nequi + Bancolombia Ahorros)](privado/colombia/colombia_2.jpg)
- [Colombia — Ejemplo 3 (Ahorro Bancolombia + comprobante)](privado/colombia/colombia_3.jpg)
- [Colombia — Ejemplo 4 (Nequi + comprobante)](privado/colombia/colombia_4.jpg)
- [Colombia — Ejemplo 5 (Nequi con C.I.)](privado/colombia/colombia_5.jpg)
- [Colombia — Ejemplo 6 (Nequi varios formatos)](privado/colombia/colombia_6.jpg)

---

## 8. Binance (`USDT`)

### Reglas específicas
- Grupo: **`BINANCE 🪙`**.
- El bot debe reconocer los 5 tipos de destino Binance:
  1. **BEP20** (dirección `0x...`, 42 caracteres)
  2. **TRC20** (dirección `T...`, 34 caracteres)
  3. **Correo electrónico** (Binance Pay)
  4. **Teléfono** (Binance Pay)
  5. **ID Binance** (numérico o usuario)

### Regla de prioridad estricta (pegar SOLO UNA)
Si el cliente envía más de una opción (en 1, 2 o más mensajes), el bot selecciona y pega en el grupo Binance **únicamente la que esté primero en este orden**:

> **1. BEP20  >  2. TRC20  >  3. Correo  >  4. Teléfono  >  5. ID Binance**

- Si trae `BEP20` y `TRC20` → gana **BEP20** (e indicar explícitamente a la operadora que es red **`BEP20`**, como en la foto 7).
- Si trae `TRC20` y correo → gana **TRC20**.

### Cálculo y formato en el grupo `BINANCE 🪙` (2 mensajes)
El cliente indica el monto en `$ Ecuador`; se aplica el `%` configurado en Google Sheets (ej. `-3%` a favor de JK: `$1500 - 3% = 1,455 USDT`).

- **1er mensaje** (solo el destino ganador para copiar rápido; si es BEP20, agregar indicación `BEP20`):
  ```text
  TXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  ```
- **2do mensaje:**
  ```text
  1500
  NOMBRE DEL CLIENTE
  1455
  ```
- Luego esperar el comprobante de la operadora citando el 2do mensaje y enviárselo al cliente correspondiente.

### Capturas reales de referencia (locales en `privado/binance/`)
- [Binance — Ejemplo 1 (correo, TRC20 e ID)](privado/binance/binance_1.jpg)
- [Binance — Ejemplo 2 (TRC20 1500 → 1455 USDT + comprobante)](privado/binance/binance_2.jpg)
- [Binance — Ejemplo 3 (TRC20 y correo)](privado/binance/binance_3.jpg)
- [Binance — Ejemplo 4 (correo + comprobante Binance Pay)](privado/binance/binance_4.jpg)
- [Binance — Ejemplo 5 (TRC20 + retiro en proceso)](privado/binance/binance_5.jpg)
- [Binance — Ejemplo 6 (correos + pago exitoso)](privado/binance/binance_6.jpg)
- [Binance — Ejemplo 7 (BEP20 con indicación de red a la operadora)](privado/binance/binance_7_bep20.jpg)

---

## 9. Zelle (`USD`)

### Reglas específicas
- Grupo: **`ZELLE`**.
- El cliente debe enviar **correo electrónico o teléfono** (ambos sirven), **nombre y apellido** (o empresa) y **monto en `$`**.
- **Atención a detalles en mensajes de clientes:**
  - El monto puede venir con emojis numéricos (ej. `1️⃣4️⃣8️⃣💰` = `$148`).
  - Algunos clientes piden colocar una **descripción / memo obligatorio** (ej. `Descripción: PAGO FACTURA`) — el bot debe conservarlo íntegro en el 1er mensaje.
- **Cálculo y formato en 2 mensajes** (misma lógica del 2do mensaje que Binance, Euros, Money Venezuela y Ecuador):
  - Se aplica el `%` vigente de Google Sheets sobre el monto Zelle (ej. `$240 + 3% = $247.20`).
  - **1er mensaje:** datos Zelle del destinatario (correo/teléfono, titular, monto, descripción si existe).
  - **2do mensaje:**
    ```text
    247.20
    NOMBRE DEL CLIENTE
    240
    ```

### Capturas reales de referencia (locales en `privado/zelle/`)
- [Zelle — Ejemplo 1 (correo + comprobante)](privado/zelle/zelle_1.jpg)
- [Zelle — Ejemplo 2 (teléfono +1)](privado/zelle/zelle_2.jpg)
- [Zelle — Ejemplo 3 (empresa/correo y montos con emojis)](privado/zelle/zelle_3.jpg)
- [Zelle — Ejemplo 4 (con descripción obligatoria PAGO FACTURA)](privado/zelle/zelle_4.jpg)
- [Zelle — Ejemplo 5 (correo + comprobante)](privado/zelle/zelle_5.jpg)
- [Zelle — Ejemplo 6 (teléfono +1 + pago por retiro)](privado/zelle/zelle_6.jpg)

---

## 10. Demás países (Referencia general)

Para el resto de países activos (Brasil/Pix, Panamá/Yappy, Uruguay, Paraguay, Bolivia, México/CLABE, República Dominicana, Costa Rica/SINPE Móvil, Ecuador, Europa/IBAN-Bizum, etc.):
- Aplicar todas las **Reglas Generales (Sección 1)**: campos estándar en cualquier orden, **nombre del cliente en cabecera**, reconocimiento por nombre/moneda/código/bandera y top ~6 bancos o redes populares del país, y **confirmación obligatoria del país** cuando no fue indicado explícitamente.
- Ir anexando aquí los ejemplos y capturas específicas conforme se agreguen.
