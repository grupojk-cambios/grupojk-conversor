# La instancia de WhatsApp queda "conectada" pero sorda

## Qué pasa

WhatsApp manda unas señales llamadas `<status>` (las actualizaciones de estado de los
contactos). La versión de Baileys que trae Evolution 2.3.7 **no las confirma**. A los ~50
minutos WhatsApp corta la conexión por esa confirmación que falta; Evolution reconecta solo
en 1-2 segundos, vuelve a llegar la misma señal, tampoco la confirma, y la sesión queda:

- **enviando bien** (la apertura y el cierre salen, los envíos por API salen)
- **consultando bien** (responde consultas en vivo a WhatsApp en menos de 1 segundo)
- **sorda**: no recibe ni un mensaje más
- y el panel sigue mostrando **"Conectada"**

Por eso parecía que el bot estaba bien y los clientes se quedaban sin respuesta.

Bug reportado:
- evolution-foundation/evolution-api **#2778** (el análisis y el arreglo de 3 líneas)
- WhiskeySockets/Baileys **#2858**

## Lo que NO lo arregla

| Intento | Resultado |
|---|---|
| Botón "Restart" de la instancia | no lo arregla |
| Reiniciar el contenedor | no lo arregla |
| Borrar y recrear la instancia + QR | lo arregla **~2 horas** |
| Subir de versión | no existe versión con el arreglo (la última estable es la 2.3.7) |

Medido en esta instancia: creada 17:19, último mensaje recibido 19:03. **1 h 44 min de vida.**

## Lo que sí lo arregla

Agregar la confirmación que falta. Son 3 líneas, en
`node_modules/baileys/lib/Socket/messages-recv.js`:

```js
ws.on('CB:status', (node) => {
    sendMessageAck(node).catch(error => onUnexpectedError(error, 'acking status stanza'));
});
```

Evolution tiene `readStatus: false`, así que confirmar esas señales no cambia nada más: no
marca estados como vistos ni genera tráfico nuevo.

El script [`scripts/parche_status_evolution.cjs`](../scripts/parche_status_evolution.cjs) lo
aplica solo. Está probado y es seguro:

- si ya está parcheado, no hace nada
- comprueba que el resultado sea JavaScript válido **antes** de pisar el archivo
- guarda una copia del original en `messages-recv.js.original`
- sin `--estricto` **siempre sale con código 0**: nunca deja el servicio caído por su culpa
- con `--estricto` sale con error si no pudo parchear (para usarlo al construir la imagen)

## LO QUE ESTÁ APLICADO (20-nov-2026)

En Easypanel → proyecto `cambios-jk-remesas` → servicio `evolution-api` → **Fuente** →
pestaña **Dockerfile**, pegado el contenido de [`Dockerfile.easypanel`](Dockerfile.easypanel).
No necesita repositorio: Easypanel construye la imagen en el servidor.

`Dockerfile.easypanel` **se genera**, no se edita a mano:

```
node evolution_parche/generar_dockerfile.cjs
```

Lleva dentro, comprimido, el script [`parche_evolution.cjs`](parche_evolution.cjs) (el código
legible y comentado está en ese archivo). Aplica **tres** arreglos:

1. **Baileys: confirmar las señales `<status>`** (el bug #2778). Sin esto, la instancia queda
   "conectada" pero sorda a las ~2 horas.
2. **Baileys: la cola de mensajes atrasados ya no se tranca.** Sin el `try/catch`, si UN mensaje
   atrasado daba error, `isProcessing` quedaba en `true` para siempre.
3. **Evolution: publicar los estados en tandas, una detrás de otra.** Evolution partía la lista
   en tandas de 10 y las mandaba **todas a la vez** (~580 juntas con 5.800 contactos), y en cada
   tanda **volvía a subir la imagen**. Con texto a veces aguantaba (la apertura del 20-nov la
   vieron 61); con imagen se caía y el estado no le llegaba a casi nadie (el cierre del 19-nov
   no apareció). Ahora:
   - solo personas (`@s.whatsapp.net` y `@lid`): fuera grupos, canales y bots
   - tu propio número primero, sin repetidos
   - tandas de 50, **una detrás de otra**, con 250 ms entre tandas
   - la primera tanda crea el estado (y sube la foto **una vez**); las demás reenvían **ese mismo
     mensaje** con el mismo id usando `relayMessage`, sin volver a subir nada
   - si una tanda falla, las demás siguen; si falla la primera, la siguiente crea el estado

Si algún parche no se puede aplicar, **la construcción falla** y Easypanel deja corriendo la
versión anterior.

### Historial

| Fecha (UTC) | Qué | Resultado |
|---|---|---|
| 20-nov 17:36 | parches 1 y 2 | Success, sesión conservada sin QR |
| 20-nov 18:31 | desvincular + QR nuevo | el atraso de 17 h se drenaba al ritmo del reloj y nunca alcanzaba; con QR nuevo quedó al día al instante |
| 20-nov 20:01 | parches 1, 2 y 3 | Success, sesión conservada sin QR. Estado de imagen de prueba en 2,8 s |

### Probado

- Local: 16 comprobaciones de comportamiento sobre un Evolution falso con la forma exacta del
  código real (una sola subida, mismo id, tandas de 50, filtros, fallos).
- Servidor: prueba en seco (`PARCHE_SOLO_PROBAR=1`) contra los 75 archivos reales: todo
  aplicaba y la sintaxis era válida, sin escribir nada.
- Después de desplegar, en el contenedor: `CB:status` 1, `try { await nodeProcessor` 1,
  `parche-estados` 1, bloque viejo en paralelo 0.

**Para deshacerlo:** Fuente → pestaña **Imagen Docker** → `evoapicloud/evolution-api:latest`
→ Guardar → Implementar.

### Ojo con los estados de prueba

Un estado mandado solo a 1 o 2 números **no aparece en "Mis estados" de tu teléfono**, aunque
incluya tu propio número. El que sí aparece es el de la apertura/cierre, que va a todos. Para
probar, mirarlo desde el teléfono del destinatario.

### Reconectar después de muchas horas sorda

WhatsApp entrega TODO el atraso antes de lo nuevo, en tandas cada ~60 s. Con 17 horas de atraso
avanzaba al mismo ritmo que el reloj y nunca alcanzaba. La salida fue desvincular y escanear un
QR nuevo: se bota la fila vieja y queda al día al instante. Lo viejo igual está en el teléfono.

## Otras formas de aplicarlo (no usadas)

Dato confirmado de la imagen `evoapicloud/evolution-api:v2.3.7`:

```
WORKDIR    /evolution
ENTRYPOINT ["/bin/bash","-c",". ./Docker/scripts/deploy_database.sh && npm run start:prod"]
CMD        (ninguno)
USER       root
```

**Ojo:** como la imagen usa `ENTRYPOINT` y no `CMD`, poner algo en un campo "Command" de
Easypanel probablemente **no se ejecute** (acabaría como `$0` de ese `bash -c` y se
descartaría). Por eso la vía recomendada es construir la imagen, que no toca el arranque.

### Vía A (recomendada): construir la imagen con el parche

Usar [`Dockerfile`](Dockerfile) de esta carpeta. En el servicio de Evolution en Easypanel se
cambia el origen de "imagen de Docker" a "repositorio Git + Dockerfile", con:

- Dockerfile: `evolution_parche/Dockerfile`
- contexto de construcción: la raíz del repositorio

No se toca nada más: variables de entorno, dominios, volúmenes y la base de datos se quedan
como están, porque en Easypanel son secciones aparte del origen.

Es reversible: si algo sale mal, se vuelve a poner la imagen `evoapicloud/evolution-api:v2.3.7`
y queda como antes.

### Vía B: ejecutar el parche en cada arranque

Si el panel permite sustituir el **entrypoint** (no el "command"), el valor sería:

```
/bin/bash -c ". ./Docker/scripts/deploy_database.sh && node /parche_status_evolution.cjs && npm run start:prod"
```

con el script montado en `/parche_status_evolution.cjs` como archivo.

Esta vía se deja documentada, pero **la A es más segura**: si el entrypoint se escribe mal,
Evolution no arranca.

## Después de aplicarlo

1. Reiniciar el contenedor. Según los reportes del issue, con el parche puesto **ya no hace
   falta volver a escanear el QR**.
2. Al reconectar llega de golpe todo lo retenido. Si hay horas de atraso, el bot recibiría
   mensajes viejos; el filtro de mensajes viejos del bot (20 minutos) los descarta, pero vale
   estar pendiente la primera vez.
3. Confirmar que quedó arreglado: pasadas 3-4 horas, comprobar que siguen entrando mensajes.
   El estado "Conectada" **no sirve** para esto; hay que mirar la fecha del último mensaje
   recibido de verdad.

## Cómo comprobar el diagnóstico en los registros

En los registros del contenedor de Evolution debe aparecer, cada ~50 minutos:

```
stream errored out   ...   "class":"status"
```

Esa línea es la firma del bug.
