// Busca credenciales antes de subir a GitHub. ESTE REPOSITORIO ES PUBLICO.
//
// Correr con:   npm run buscar-secretos
// Sale con codigo 1 si encuentra algo, para poder encadenarlo antes de un push.
//
// Revisa los archivos que git tiene en el "stage" (los que se van a subir).
// Si no hay nada en stage, revisa todos los archivos rastreados.
//
// NUNCA imprime el valor encontrado, solo el archivo y el tipo. La idea es
// avisar, no volver a exponer la credencial en la pantalla ni en los logs.
//
// Historia: en build_cuentas_v1.ps1 habia un token de bot de Telegram escrito en
// texto plano, y antes se filtro una apikey de Evolution en este mismo repo.

import { execSync } from 'child_process';
import { readFileSync, existsSync } from 'fs';

const REGLAS = [
  ['token de bot de Telegram', /\b\d{8,12}:[A-Za-z0-9_-]{30,}\b/g],
  ['clave privada',            /-----BEGIN [A-Z ]*PRIVATE KEY-----/g],
  ['JWT / token largo',        /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\./g],
  ['clave de Google (AIza)',   /\bAIza[0-9A-Za-z_-]{30,}\b/g],
  ['clave de OpenAI (sk-)',    /\bsk-[A-Za-z0-9]{20,}\b/g],
  ['clave de Supabase',        /\bsbp_[A-Za-z0-9]{20,}\b/g],
  ['apikey con valor escrito', /"(apikey|api_key|x-api-key|authorization|password|secret)"\s*:\s*"(?!=|\{\{)[^"]{12,}"/gi],
  ['UUID suelto (posible apikey)', /\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b/g]
];

// Los workflows de n8n estan LLENOS de UUID que son identificadores de nodo y de
// webhook, no credenciales. Se descartan para que la alerta de UUID sirva de algo.
function uuidsQueSonIds(texto) {
  const ids = new Set();
  const agrega = (re) => { let m; while ((m = re.exec(texto)) !== null) ids.add(m[1]); };
  agrega(/"id"\s*:\s*"([0-9A-Fa-f-]{36})"/g);
  agrega(/"webhookId"\s*:\s*"([0-9A-Fa-f-]{36})"/g);
  agrega(/\b(?:id|webhookId|instanceId)\s*=\s*'([0-9A-Fa-f-]{36})'/g);   // los build_*.ps1
  agrega(/"instanceId"\s*:\s*"([0-9A-Fa-f-]{36})"/g);
  return ids;
}

const enStage = execSync('git diff --cached --name-only', { encoding: 'utf8' }).split('\n').filter(Boolean);
const archivos = enStage.length
  ? enStage
  : execSync('git ls-files', { encoding: 'utf8' }).split('\n').filter(Boolean);

console.log(`Revisando ${archivos.length} archivo(s)${enStage.length ? ' en el stage' : ' rastreados'}...`);
console.log('');

let hallazgos = 0;
for (const f of archivos) {
  if (!existsSync(f)) continue;
  let s;
  try { s = readFileSync(f, 'utf8'); } catch { continue; }
  if (s.includes('\u0000')) continue;   // binario

  const ids = uuidsQueSonIds(s);
  for (const [nombre, re] of REGLAS) {
    let encontrados = s.match(re) || [];
    if (nombre.startsWith('UUID')) encontrados = encontrados.filter(u => !ids.has(u));
    if (encontrados.length) {
      hallazgos += encontrados.length;
      console.log(`  ALERTA  ${f}`);
      console.log(`          ${nombre} x${encontrados.length}  (el valor NO se muestra a proposito)`);
    }
  }
}

console.log('');
if (hallazgos === 0) {
  console.log('Sin credenciales. Seguro para subir.');
  process.exit(0);
}
console.log(`${hallazgos} posible(s) credencial(es). NO SUBAS hasta revisarlo.`);
console.log('Si es un falso positivo, ajusta las reglas de este archivo.');
process.exit(1);
