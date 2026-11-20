// Genera Dockerfile.easypanel a partir de parche_evolution.cjs.
// El script va dentro del Dockerfile comprimido en base64, porque en Easypanel el Dockerfile se
// pega a mano en un cuadro de texto y no hay carpeta de donde copiar archivos.
//     node evolution_parche/generar_dockerfile.cjs
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const aqui = __dirname;
const fuente = fs.readFileSync(path.join(aqui, 'parche_evolution.cjs'), 'utf8');
// Sin las lineas de comentario (el original comentado queda en el repositorio).
const compacto = fuente.split(/\r?\n/).filter(l => !/^\s*\/\//.test(l)).join('\n');
const b64 = zlib.gzipSync(Buffer.from(compacto, 'utf8'), { level: 9 }).toString('base64');
const docker = [
  'FROM evoapicloud/evolution-api:latest',
  '# Parches de Cambios JK. El codigo legible esta en evolution_parche/parche_evolution.cjs',
  '#  1) Baileys: confirma las senales <status> (si no, la instancia queda sorda a las ~2 h)',
  '#  2) Baileys: un mensaje atrasado con error ya no tranca la cola de atrasados',
  '#  3) Evolution: los estados se publican en tandas una detras de otra, subiendo la foto 1 vez',
  '# Si algun parche no se puede aplicar, la construccion FALLA y queda corriendo la version anterior.',
  'RUN echo ' + b64 + ' | base64 -d | gunzip > /tmp/parche.cjs && node /tmp/parche.cjs && rm /tmp/parche.cjs',
  ''
].join('\n');
fs.writeFileSync(path.join(aqui, 'Dockerfile.easypanel'), docker);
console.log('Dockerfile.easypanel generado: ' + docker.length + ' caracteres.');
