// Prueba el SELLO DE FECHA que el bot de WhatsApp le pone a la cuenta del dia.
//
// La cuenta rota cada dia, asi que al cliente hay que decirle que la que recibe
// es la de HOY. La fecha NO se guarda en la hoja (quedaria congelada): se agrega
// al momento de enviarla, con la misma hora de Ecuador (UTC-5) que decide cual
// cuenta toca, para que la fecha y la rotacion nunca se contradigan.
//
// Correr con:  node test_cuenta_del_dia.mjs

import { readFileSync } from 'fs';
const wf = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json','utf8').replace(/^\uFEFF/,''));
const codigo = wf.nodes.find(n=>n.name==='Code in JavaScript').parameters.jsCode;
const CSV='https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv';
const tasas = await (await fetch(CSV+'&n='+Date.now())).text();

// Hoja de cuentas simulada: una con el formato NUEVO y otra con el VIEJO
const nueva = '*CUENTA AUTORIZADA USD*\n\n\u{1F3E6}1) 2205061301\n*Pichincha ahorro*\n0963893565\n*Dario Araujo*';
const vieja = '\u{1F3E6}1) 55458142571\n*Bancolombia ahorro*\nC.I: 8536509\n*Enrique Rodriguez*';
const esc = s => '"' + s.replace(/"/g,'""') + '"';
const cuentasCSV = [
  'Pais,Metodo,Disponible,Datos,Notas,Tipo',
  'Ecuador,Pichincha,si,' + esc(nueva) + ',,',
  'Colombia,Bancolombia,si,' + esc(vieja) + ',,'
].join('\n');

function correr(iso){
  const real = Date.now; Date.now = () => new Date(iso).getTime();
  try {
    const $ = (n) => { const uno = j => ({first:()=>({json:j}),all:()=>[{json:j}]});
      if(n==='Consultar Tasas') return uno({data:tasas});
      if(n==='Consultar Cuentas') return uno({data:cuentasCSV});
      if(n==='Webhook Evolution API') return uno({body:{data:{key:{remoteJid:'584121112233@s.whatsapp.net'}}}});
      return {first:()=>({json:{}}),all:()=>[]}; };
    return new Function('$',codigo)($)[0].json;
  } finally { Date.now = real; }
}

const r = correr('2026-11-03T17:00:00Z');   // martes
console.log('===== LO QUE LE LLEGA AL CLIENTE =====');
for (const c of r.cuentas) { console.log('--- ' + c.Pais + ' ---'); console.log(c.Datos); console.log(''); }

let f=0; const ok=(c,t,d='')=>{if(!c)f++;console.log('  '+(c?'OK   ':'FALLO')+' '+t.padEnd(52)+d);};
const ec = r.cuentas.find(c=>/ecuador/i.test(c.Pais));
const co = r.cuentas.find(c=>/colombia/i.test(c.Pais));
ok(ec.Datos.split('\n')[0]==='*CUENTA AUTORIZADA USD*', 'formato nuevo: conserva el titulo con la moneda');
ok(ec.Datos.split('\n')[1]==='_Válida solo hoy, martes 3 de noviembre_', 'formato nuevo: la fecha va debajo del titulo');
ok(co.Datos.startsWith('*CUENTA AUTORIZADA*\n_Válida solo hoy, martes 3 de noviembre_'), 'formato viejo: se le antepone el encabezado');
ok(co.Datos.includes('55458142571'), 'formato viejo: no se pierde nada');
ok((ec.Datos.match(/CUENTA AUTORIZADA/g)||[]).length===1, 'el titulo NO se duplica');

console.log('');
console.log('--- la fecha cambia sola cada dia ---');
for (const [iso,esp] of [['2026-11-03T17:00:00Z','martes 3 de noviembre'],['2026-11-04T17:00:00Z','miércoles 4 de noviembre'],['2026-11-07T17:00:00Z','sábado 7 de noviembre'],['2026-12-25T17:00:00Z','viernes 25 de diciembre']]){
  const x = correr(iso).cuentas.find(c=>/ecuador/i.test(c.Pais));
  const linea = x ? x.Datos.split('\n')[1] : '(sin cuenta)';
  ok(linea === '_Válida solo hoy, ' + esp + '_', iso.slice(0,10), '-> ' + linea);
}
// Antes de medianoche en Ecuador sigue siendo el dia anterior
const tarde = correr('2026-11-04T04:00:00Z').cuentas.find(c=>/ecuador/i.test(c.Pais));
ok(tarde.Datos.split('\n')[1].includes('martes 3'), 'a las 11pm de Ecuador todavia dice el dia de hoy', '-> ' + tarde.Datos.split('\n')[1]);
console.log('');
console.log(f ? ('FALLARON '+f) : 'TODO OK');

process.exit(f ? 1 : 0);
