'use strict';
// =============================================================================================
// PARCHES DE CAMBIOS JK SOBRE EVOLUTION API 2.3.7 (Baileys 7.0.0-rc.9)
//
// Se ejecuta al CONSTRUIR la imagen (ver Dockerfile.easypanel). Si algun parche no se puede
// aplicar, sale con error y la construccion falla: Easypanel deja corriendo la version anterior
// y nunca queda una imagen a medio arreglar.
//
//  1) Baileys: confirmar (ack) las senales <status> de WhatsApp.
//     Sin esto la instancia queda "conectada" pero SORDA a las ~2 horas. (Evolution #2778)
//  2) Baileys: si un mensaje atrasado da error, la cola de atrasados sigue en vez de trancarse.
//  3) Evolution: publicar los estados en tandas UNA DETRAS DE OTRA, subiendo la foto UNA vez.
//     Evolution partia la lista en tandas de 10 y las mandaba TODAS a la vez (~580 juntas
//     con 5.800 contactos), y en cada tanda volvia a subir la imagen. Con texto a veces
//     aguantaba; con imagen se caia y el estado no le llegaba a casi nadie.
//
// Opciones (variables de entorno):
//   PARCHE_RAIZ=/evolution     donde esta instalado Evolution
//   PARCHE_SOLO_PROBAR=1       revisa todo y comprueba la sintaxis, pero NO escribe nada
// =============================================================================================

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const RAIZ = process.env.PARCHE_RAIZ || '/evolution';
const PROBAR = process.env.PARCHE_SOLO_PROBAR === '1';
const TANDA_ESTADOS = 50;         // contactos por tanda al publicar un estado
const PAUSA_ENTRE_TANDAS = 250;   // milisegundos entre tanda y tanda

function fallar(m) { console.error('[parche] ERROR: ' + m); process.exit(1); }
function decir(m) { console.log('[parche] ' + m); }

function revisarSintaxis(codigo, nombre) {
  const t = path.join(os.tmpdir(), 'parche_' + nombre.replace(/\W/g, '_') + '.js');
  fs.writeFileSync(t, codigo);
  try { execFileSync(process.execPath, ['--check', t], { stdio: 'pipe' }); }
  catch (e) { fallar('sintaxis invalida en ' + nombre + ': ' + String(e.stderr || e.message).slice(0, 300)); }
  finally { try { fs.unlinkSync(t); } catch (e) {} }
}

function guardar(archivo, codigo) {
  revisarSintaxis(codigo, archivo);
  if (PROBAR) { decir('(prueba) sintaxis OK, no se escribe ' + archivo); return; }
  fs.writeFileSync(archivo, codigo);
}

function recorrer(dir) {
  return fs.readdirSync(dir, { withFileTypes: true })
    .flatMap(e => e.isDirectory() ? recorrer(path.join(dir, e.name)) : [path.join(dir, e.name)]);
}

// ---------------------------------------------------------------------------------------------
// 1 y 2: Baileys
// ---------------------------------------------------------------------------------------------
const RECV = path.join(RAIZ, 'node_modules/baileys/lib/Socket/messages-recv.js');
if (!fs.existsSync(RECV)) fallar('no existe ' + RECV);
let recv = fs.readFileSync(RECV, 'utf8');

if (!recv.includes('CB:status')) {
  const m = recv.match(/ws\.on\(.CB:notification./);
  if (!m) fallar('no encontre CB:notification en messages-recv.js');
  recv = recv.slice(0, m.index) +
    "ws.on('CB:status', (node) => { sendMessageAck(node).catch(error => onUnexpectedError(error, 'acking status stanza')); });\n    " +
    recv.slice(m.index);
  decir('1 ack de status: aplicado');
} else decir('1 ack de status: ya estaba');

const PROC = 'await nodeProcessor(node);';
if (!recv.includes('try { ' + PROC)) {
  if (recv.split(PROC).length !== 2) fallar('"' + PROC + '" no aparece exactamente una vez');
  recv = recv.replace(PROC, 'try { ' + PROC + " } catch (error) { onUnexpectedError(error, 'processing offline node'); }");
  decir('2 cola de atrasados: aplicado');
} else decir('2 cola de atrasados: ya estaba');

guardar(RECV, recv);

// ---------------------------------------------------------------------------------------------
// 3: Evolution, publicar estados
// ---------------------------------------------------------------------------------------------

// El parche 3 manda las tandas 2 en adelante con relayMessage(..., { statusJidList }).
// Se comprueba que esta version de Baileys de verdad acepte esa opcion.
const SEND = path.join(RAIZ, 'node_modules/baileys/lib/Socket/messages-send.js');
const send = fs.existsSync(SEND) ? fs.readFileSync(SEND, 'utf8') : '';
if (!/const relayMessage = async \([^)]*\{[^}]*statusJidList[^}]*\}/.test(send)) {
  fallar('relayMessage de esta version de Baileys no recibe statusJidList; el parche 3 no es seguro');
}

// El bloque original, ya compilado y minificado. Los nombres de las variables cambian de un
// archivo a otro, por eso se capturan: \1 tamano, \2 tandas, \3 LISTA, \6 id, \7 resultado,
// \8 primera tanda, \9 JID (status@broadcast), \10 MENSAJE, \11 tanda.
const BLOQUE = /let (\w+)=10,(\w+)=Array\.from\(\{length:Math\.ceil\((\w+)\.length\/\1\)\},\((\w+),(\w+)\)=>\3\.slice\(\5\*\1,\5\*\1\+\1\)\),(\w+)=null,(\w+),(\w+)=\2\.shift\(\);return \8&&\(\7=await this\.client\.sendMessage\((\w+),(\w+)\.status\.content,\{backgroundColor:\10\.status\.option\.backgroundColor,font:\10\.status\.option\.font,statusJidList:\8\}\),\6=\7\.key\.id\),\2\.length===0\|\|await Promise\.allSettled\(\2\.map\(async (\w+)=>await this\.client\.sendMessage\(\9,\10\.status\.content,\{backgroundColor:\10\.status\.option\.backgroundColor,font:\10\.status\.option\.font,statusJidList:\11,messageId:\6\}\)\)\),\7\}/;
const CRUDO = /Promise\.allSettled\(\w+\.map\(async \w+=>await this\.client\.sendMessage\(\w+,\w+\.status\.content/g;
const MARCA = '[parche-estados]';

function bloqueNuevo(LISTA, JID, MSG) {
  return '' +
    // Solo personas: fuera grupos, canales, bots. Tu propio numero primero, sin repetidos.
    'let __pjL=(Array.isArray(' + LISTA + ')?' + LISTA + ':[]).filter(j=>typeof j=="string"&&(j.endsWith("@s.whatsapp.net")||j.endsWith("@lid")));' +
    'const __pjYo=this.instance&&this.instance.wuid;if(__pjYo&&!__pjL.includes(__pjYo))__pjL.unshift(__pjYo);__pjL=[...new Set(__pjL)];' +
    'const __pjT=' + TANDA_ESTADOS + ',__pjD=Array.from({length:Math.ceil(__pjL.length/__pjT)},(a,i)=>__pjL.slice(i*__pjT,i*__pjT+__pjT));' +
    'let __pjH=null,__pjG,__pjOk=0,__pjMal=0;' +
    // Una tanda detras de otra. La primera crea el estado (y sube la foto UNA vez); las demas
    // reenvian ESE mismo mensaje con el mismo id, sin volver a subir nada.
    'for(const __pjS of __pjD){' +
      'try{' +
        'if(!__pjG){__pjG=await this.client.sendMessage(' + JID + ',' + MSG + '.status.content,{backgroundColor:' + MSG + '.status.option.backgroundColor,font:' + MSG + '.status.option.font,statusJidList:__pjS});__pjH=__pjG.key.id}' +
        'else{await this.client.relayMessage(' + JID + ',__pjG.message,{messageId:__pjH,statusJidList:__pjS})}' +
        '__pjOk++' +
      '}catch(__pjE){__pjMal++;console.log("' + MARCA + ' tanda fallida: "+(__pjE&&__pjE.message))}' +
      'await new Promise(r=>setTimeout(r,' + PAUSA_ENTRE_TANDAS + '))' +
    '}' +
    'console.log("' + MARCA + ' "+__pjL.length+" contactos, "+__pjD.length+" tandas, "+__pjOk+" bien, "+__pjMal+" fallidas");' +
    'if(!__pjG)throw new Error("No se pudo publicar el estado en ninguna tanda");' +
    'return __pjG}';
}

const DIST = path.join(RAIZ, 'dist');
if (!fs.existsSync(DIST)) fallar('no existe ' + DIST);
let parcheados = 0, yaEstaban = 0, principal = false;
for (const f of recorrer(DIST).filter(f => f.endsWith('.js'))) {
  let s = fs.readFileSync(f, 'utf8');
  const crudos = (s.match(CRUDO) || []).length;
  if (s.includes(MARCA)) { yaEstaban++; if (f.endsWith(path.sep + 'main.js')) principal = true; continue; }
  if (crudos === 0) continue;
  if (crudos !== 1) fallar(f + ': el bloque de estados aparece ' + crudos + ' veces (se esperaba 1)');
  const m = s.match(BLOQUE);
  if (!m) fallar(f + ': el bloque de estados no tiene la forma esperada');
  s = s.slice(0, m.index) + bloqueNuevo(m[3], m[9], m[10]) + s.slice(m.index + m[0].length);
  guardar(f, s);
  parcheados++;
  if (f.endsWith(path.sep + 'main.js')) principal = true;
}
if (!principal) fallar('dist/main.js (el que corre) no quedo parcheado');
decir('3 estados en tandas: ' + parcheados + ' archivos parcheados, ' + yaEstaban + ' ya estaban');

decir(PROBAR ? 'PRUEBA TERMINADA: todo aplicaria bien.' : 'TODOS LOS PARCHES APLICADOS.');
