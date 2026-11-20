// ===========================================================================================
// PARCHE: la instancia dice "conectada" pero deja de RECIBIR mensajes.
//
// EL PROBLEMA
// WhatsApp manda unas senales llamadas <status> (las actualizaciones de estado de tus
// contactos). Esta version de Evolution (2.3.7, con Baileys 7.0.0-rc.9) NO las confirma.
// A los ~50 minutos WhatsApp corta la conexion por esa confirmacion que falta. Evolution
// reconecta solo en 1-2 segundos, vuelve a llegar la misma senal, tampoco la confirma, y la
// sesion queda ENVIANDO bien pero SORDA: no recibe ni un mensaje mas, y el panel sigue
// mostrando "Conectada".
//
// Reiniciar la instancia NO lo arregla. Reiniciar el contenedor tampoco. Solo volver a
// escanear el QR, y aguanta un par de horas.
//
// EL ARREGLO
// Agregar la confirmacion que falta. Son 3 lineas. Evolution tiene readStatus=false, asi
// que confirmar esas senales no cambia nada mas.
//
// Reportado en: evolution-foundation/evolution-api issue #2778
//               WhiskeySockets/Baileys issue #2858
//
// COMO SE USA
// Se ejecuta ANTES de arrancar Evolution, cada vez que el contenedor arranca:
//     node /parche_status_evolution.cjs && npm run start:prod
//
// Es seguro: si ya esta parcheado no hace nada, y si algo no cuadra avisa y deja arrancar
// Evolution igual (nunca te deja el servicio caido por culpa del parche).
// ===========================================================================================

'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ETIQUETA = '[parche-status]';
const avisar = (m) => console.log(ETIQUETA + ' ' + m);

// Modo estricto (--estricto): si NO se pudo parchear, sale con error.
// Se usa al construir la imagen, para que una construccion nunca termine en una imagen que
// parece arreglada y no lo esta. Sin esta opcion siempre sale con 0, que es lo que se quiere
// al arrancar el contenedor: mejor Evolution arrancando sin parche que no arrancando.
const ESTRICTO = process.argv.includes('--estricto');
function rendirse(motivo) {
  avisar(motivo);
  if (ESTRICTO) { avisar('modo estricto: corto aqui.'); process.exit(1); }
  avisar('dejo arrancar Evolution igual.');
  process.exit(0);
}

// --- 1) Encontrar el archivo de Baileys -----------------------------------------------------
function buscarArchivo() {
  const relativo = 'baileys/lib/Socket/messages-recv.js';
  const relativoScoped = '@whiskeysockets/baileys/lib/Socket/messages-recv.js';
  const raices = ['/evolution/node_modules', '/usr/src/app/node_modules', '/app/node_modules',
                  path.join(process.cwd(), 'node_modules')];
  for (const raiz of raices) {
    for (const rel of [relativo, relativoScoped]) {
      const p = path.join(raiz, rel);
      if (fs.existsSync(p)) return p;
    }
  }
  return null;
}

const archivo = buscarArchivo();
if (!archivo) rendirse('NO encontre node_modules/baileys.');
avisar('archivo: ' + archivo);

// --- 2) Decir que version de Baileys es (informativo) ---------------------------------------
try {
  const pkg = path.join(archivo.split(path.sep + 'lib' + path.sep)[0], 'package.json');
  avisar('version de Baileys: ' + JSON.parse(fs.readFileSync(pkg, 'utf8')).version);
} catch (e) { avisar('no pude leer la version de Baileys (no importa).'); }

// --- 3) Parchear ----------------------------------------------------------------------------
let codigo;
try { codigo = fs.readFileSync(archivo, 'utf8'); }
catch (e) { rendirse('no pude leer el archivo: ' + e.message); }

if (/CB:status/.test(codigo)) {
  avisar('YA estaba parcheado. Nada que hacer.');
  process.exit(0);
}

// Se engancha justo antes del manejador de CB:notification: ahi ya existen en memoria las
// dos funciones que necesitamos (sendMessageAck y onUnexpectedError), y el orden en que se
// registran los manejadores no importa.
const ancla = /ws\.on\((['"])CB:notification\1/;
const donde = codigo.match(ancla);
if (!donde) rendirse('NO encontre donde engancharlo: el archivo cambio en esta version de Baileys.');

const inyeccion =
  "ws.on('CB:status', (node) => {\n" +
  "        sendMessageAck(node).catch(error => onUnexpectedError(error, 'acking status stanza'));\n" +
  "    });\n" +
  "    ";

const nuevo = codigo.slice(0, donde.index) + inyeccion + codigo.slice(donde.index);

// --- 4) Comprobar que el resultado es JavaScript valido ANTES de pisar el original ----------
const prueba = path.join(require('os').tmpdir(), 'parche_status_prueba.js');
try {
  fs.writeFileSync(prueba, nuevo, 'utf8');
  execFileSync(process.execPath, ['--check', prueba], { stdio: 'pipe' });
} catch (e) {
  rendirse('el resultado NO era JavaScript valido, no toco nada.');
}
try { fs.unlinkSync(prueba); } catch (e) {}

// --- 5) Guardar copia del original y escribir -----------------------------------------------
try {
  if (!fs.existsSync(archivo + '.original')) fs.copyFileSync(archivo, archivo + '.original');
  fs.writeFileSync(archivo, nuevo, 'utf8');
  avisar('PARCHE APLICADO. La instancia ya deberia seguir recibiendo mensajes sin quedarse sorda.');
} catch (e) {
  rendirse('no pude escribir el archivo: ' + e.message);
}
process.exit(0);
