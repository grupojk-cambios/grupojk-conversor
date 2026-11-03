// Prueba del BOT DE CUENTAS con el codigo REAL de los nodos del workflow.
//
// Vigila los errores que reporto Kelvin:
//   1. Salian cuadritos en vez de emojis (String.fromCharCode no sirve para
//      codigos mayores a 65535; hay que usar String.fromCodePoint).
//   2. La columna Datos llegaba resumida por la IA y separada por comas.
//   3. El mensaje de confirmacion iba en Markdown y los datos traen asteriscos.
//   4. Cada cuenta quedaba con el formato con que Kelvin la escribio ese dia.
//      Ahora el bot la REORDENA siempre al mismo formato, con el titulo
//      *CUENTA AUTORIZADA <MONEDA>* sacado del pais.
//
// Red de seguridad clave: la IA reescribe numeros de cuenta. Si al reordenar se
// pierde algun numero de 4+ digitos, se guarda el mensaje ORIGINAL y se avisa.
//
// Correr con:  node test_bot_cuentas.mjs
import { readFileSync } from 'fs';
const wf = JSON.parse(readFileSync('workflow_cuentas_v1.json','utf8').replace(/^\uFEFF/,''));
const code = n => wf.nodes.find(x=>x.name===n).parameters.jsCode;
const correr = (nombre, ctx) => new Function('$', code(nombre))(
  (n) => ({ first: () => ({ json: ctx[n] || {} }), all: () => [{ json: ctx[n] || {} }] })
);
function flujo(texto, ia){
  const det   = correr('Detectar Mensaje', { 'Telegram Trigger': { message: { text: texto, chat: { id: '1' } } } })[0].json;
  const inter = correr('Interpretar', { 'Detectar Mensaje': det, 'Redis Leer Pendiente': {} })[0].json;
  const llam  = correr('Preparar Llamada IA', { 'Interpretar': inter })[0].json;
  return correr('Preparar Fila', { 'Parsear con GPT-4o': { choices:[{message:{content:JSON.stringify(ia)}}] }, 'Preparar Llamada IA': llam })[0].json;
}

// Caso 1: tu mensaje de Ecuador, desordenado
const msg1 = '/mayor\n*cuentas autorizadas para hoy*\n\n\u{1F3E6}1)  2205061301\n *Pichincha ahorro*\n0963893565\n*Dario Araujo*\n\nMOTIVO DE PAGO ES:\n*Contactanos al 0961230380*';
const r1 = flujo(msg1, { pais:'Ecuador', metodo:'Pichincha Ahorro', notas:'Pichincha Dario',
  numeroCuenta:'2205061301', banco:'Pichincha ahorro', identificacion:'0963893565', titular:'Dario Araujo',
  extra:'MOTIVO DE PAGO ES:\n*Contactanos al 0961230380*' });

// Caso 2: Colombia escrito de otra forma
const msg2 = '/detal\nbancolombia de enrique\ncuenta 55458142571 ahorros\ncedula 8536509\nEnrique Rodriguez';
const r2 = flujo(msg2, { pais:'Colombia', metodo:'Bancolombia Ahorro', notas:'Bancolombia Enrique',
  numeroCuenta:'55458142571', banco:'Bancolombia ahorro', identificacion:'C.I: 8536509', titular:'Enrique Rodriguez', extra:'' });

// Caso 3: la IA PIERDE un numero -> debe guardar el original
const r3 = flujo(msg1, { pais:'Ecuador', metodo:'Pichincha Ahorro', notas:'Pichincha Dario',
  numeroCuenta:'220506130', banco:'Pichincha ahorro', identificacion:'0963893565', titular:'Dario Araujo', extra:'' });

console.log('========== CASO 1: Ecuador (mensaje desordenado) ==========');
console.log(r1.fila.Datos);
console.log('');
console.log('========== CASO 2: Colombia (escrito de otra forma) ==========');
console.log(r2.fila.Datos);
console.log('');
console.log('========== CASO 3: la IA se come un digito ==========');
console.log(r3.fila.Datos.split('\n').slice(0,3).join('\n') + '   <-- debe ser el ORIGINAL');
console.log('');
let f=0; const ok=(c,t,d='')=>{if(!c)f++;console.log('  '+(c?'OK   ':'FALLO')+' '+t.padEnd(50)+d);};
ok(r1.fila.Datos.startsWith('*CUENTA AUTORIZADA USD*'), 'Ecuador -> titulo con USD');
ok(r2.fila.Datos.startsWith('*CUENTA AUTORIZADA COP*'), 'Colombia -> titulo con COP');
ok(r1.reordenada === true, 'caso 1 se reordeno');
ok(r2.reordenada === true, 'caso 2 se reordeno');
ok(r1.fila.Datos.includes('2205061301') && r1.fila.Datos.includes('0963893565') && r1.fila.Datos.includes('0961230380'), 'caso 1 conserva los 3 numeros');
ok(r2.fila.Datos.includes('55458142571') && r2.fila.Datos.includes('8536509'), 'caso 2 conserva los numeros');
ok(r3.reordenada === false, 'caso 3 detecta el numero perdido');
ok(r3.fila.Datos === msg1.replace(/^\/mayor\s*/,''), 'caso 3 guarda el ORIGINAL tal cual');
ok(/No pude reordenarla/.test(r3.resumen), 'caso 3 te avisa');
const mismaForma = [r1,r2].every(r => {
  const l = r.fila.Datos.split('\n');
  return /^\*CUENTA AUTORIZADA \w+\*$/.test(l[0]) && l[1]==='' && /^\u{1F3E6}1\) /u.test(l[2]);
});
ok(mismaForma, 'las dos quedan con la MISMA estructura');
console.log('');
console.log(f ? ('FALLARON '+f) : 'TODO OK');

process.exit(f ? 1 : 0);
