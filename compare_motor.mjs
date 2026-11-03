// Compara el motor del BOT (port) contra el motor REAL de la app (import directo de src/constants.js)
// sobre el CSV en vivo. Detecta CUALQUIER diferencia numerica en tasas y cruces (detal y mayor).
import { isCajaDolar as appIsCajaDolar, calcularTasaEnvio as appTEnv, calcularTasaRecibo as appTRec,
  calcularConversion as appConv, calcularConversionInversa as appConvInv, PAISES_INICIALES } from './src/constants.js';

const CSV_URL = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv";
function parseCSVrow(linea){ const row=[]; let inQ=false; let cur=''; for(const c of linea){ if(c==='"') inQ=!inQ; else if(c===','&&!inQ){ row.push(cur); cur=''; } else cur+=c; } row.push(cur); return row; }
function normName(str){ return (str||'').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,''); }

// ===== APP: replica EXACTA de sincronizarGoogleSheets (con parseValNullable para mayoristas) =====
function appParse(csv){
  const lineas = csv.split('\n').filter(l=>l.trim().length>0);
  const headRow = parseCSVrow(lineas[0].trim()).map(h=>h.toUpperCase());
  const idxEUR=headRow.findIndex(h=>h.includes('FACTOR EUR')||h.includes('VALOR EUR'));
  const idxUSDT=headRow.findIndex(h=>h.includes('FACTOR USDT')||h.includes('VALOR USDT'));
  const idxCod=headRow.findIndex(h=>h.includes('CÓDIGO')||h.includes('CODIGO')||h.includes('BANCO'));
  const idxMon=headRow.findIndex(h=>h.includes('NOMBRE')||h.includes('MONEDA'));
  const idxMEM=headRow.findIndex(h=>h.includes('MARGEN ENVIO MAYOR')||h.includes('MARGEN ENVÍO MAYOR'));
  const idxMRM=headRow.findIndex(h=>h.includes('MARGEN RECIBO MAYOR'));
  const parseVal=(str)=>{ if(!str) return 0; let s=str.replace(/\s/g,''); s=s.replace(',', '.'); const v=parseFloat(s); return isNaN(v)?0:v; };
  const parseValNullable=(str)=>{ if(str===undefined||str===null||str.trim()==='') return null; let s=str.replace(/\s/g,''); s=s.replace(',', '.'); const v=parseFloat(s); return isNaN(v)?null:v; };
  const out=[];
  for(let i=1;i<lineas.length;i++){ const row=parseCSVrow(lineas[i].trim()); if(!(row.length>=1&&row[0].trim()!=='')) continue;
    const nombreCol=row[0].trim();
    const tE=row.length>=2?parseVal(row[1]):0; const mE=row.length>=3?parseVal(row[2]):6;
    const tR=row.length>=4?parseVal(row[3]):0; const mR=row.length>=5?parseVal(row[4]):6;
    const base=PAISES_INICIALES.find(p=>normName(p.nombre)===normName(nombreCol));
    const codCustom=idxCod!==-1&&row.length>idxCod&&row[idxCod].trim()!==''?row[idxCod].trim().toUpperCase():null;
    const monCustom=idxMon!==-1&&row.length>idxMon&&row[idxMon].trim()!==''?row[idxMon].trim():null;
    const vEUR=idxEUR!==-1&&row.length>idxEUR?parseVal(row[idxEUR]):0;
    const vUSDT=idxUSDT!==-1&&row.length>idxUSDT?parseVal(row[idxUSDT]):0;
    out.push({ id: base?base.id:1000+i, nombre: base?base.nombre:nombreCol, codigo: codCustom||(base?base.codigo:nombreCol.substring(0,3).toUpperCase()),
      moneda: monCustom||'Divisa Local', tasaProveedorEnvio:tE, margenEnvio:mE, tasaProveedorRecibo:tR, margenRecibo:mR,
      factorEUR: vEUR||(base?base.factorEUR||0:0), factorUSDT: vUSDT||(base?base.factorUSDT||0:0),
      margenEnvioMayor: idxMEM!==-1&&row.length>idxMEM?parseValNullable(row[idxMEM]):null, margenReciboMayor: idxMRM!==-1&&row.length>idxMRM?parseValNullable(row[idxMRM]):null });
  }
  return out;
}

// ===== BOT: se extrae el CODIGO REAL del nodo del workflow (ya NO hay replica a mano) =====
// Antes esta seccion era una copia escrita a mano del nodo; podia quedar desfasada y hacer que
// la comparacion mintiera. Ahora se lee tal cual del JSON que se despliega.
import { readFileSync } from 'fs';
const WF = JSON.parse(readFileSync('workflow_bot_whatsapp_v12.json', 'utf8').replace(/^\uFEFF/, ''));
const NODO = WF.nodes.find(n => n.name === 'Calculadora de Conversion');
if (!NODO) throw new Error('No encontre el nodo "Calculadora de Conversion" en el workflow');
const CODIGO_NODO = NODO.parameters.jsCode || NODO.parameters.code || '';

// Saca el texto completo de "function <nombre>(...){ ... }" contando llaves.
// Si el conteo se rompiera, el eval de abajo falla con error claro (nunca da numeros silenciosamente malos).
function extraerFuncion(src, nombre) {
  const firma = 'function ' + nombre + '(';
  const pos = src.indexOf(firma);
  if (pos === -1) throw new Error('No encontre la funcion "' + nombre + '" en el nodo del bot');
  const ini = src.indexOf('{', pos);
  let nivel = 0;
  for (let j = ini; j < src.length; j++) {
    if (src[j] === '{') nivel++;
    else if (src[j] === '}') { nivel--; if (nivel === 0) return src.slice(pos, j + 1); }
  }
  throw new Error('Llaves sin cerrar en "' + nombre + '"');
}

const FUNCS = ['parseCSV', 'num', 'numN', 'norm', 'construirPaises',
  'calcularTasaEnvio', 'calcularTasaRecibo', 'esEcuador', 'isCajaDolar',
  'obtenerTasasProcesadas', 'calcularConversion', 'calcularConversionInversa'];
const fuenteBot = FUNCS.map(f => extraerFuncion(CODIGO_NODO, f)).join('\n');
const MB = new Function(fuenteBot + '\nreturn {' + FUNCS.join(',') + '};')();

// Lo que de verdad se compara ahora: el motor es el MISMO archivo en los dos lados
// (src/motor.js), asi que esta prueba vigila que la INYECCION del build no se rompa
// y, sobre todo, que el parser del bot (construirPaises, lee el CSV) arme los paises
// igual que el de la app (sincronizarGoogleSheets). Ese parser SI son dos
// implementaciones distintas, y es donde puede volver a aparecer una diferencia.
const botParse = (csv) => MB.construirPaises(csv);
let paisesBot = [];
const B = {
  isCajaDolar: MB.isCajaDolar,
  tEnv: MB.calcularTasaEnvio,
  tRec: MB.calcularTasaRecibo,
  obtener: (o, d, modo) => { const r = MB.obtenerTasasProcesadas(o, d, paisesBot, modo); return { tO: r.tasaOrigenParaDolares, tD: r.tasaDestinoDesdeDolares }; },
  conv: (o, d, m, modo) => MB.calcularConversion(o, d, m, paisesBot, modo),
  convInv: (o, d, m, modo) => MB.calcularConversionInversa(o, d, m, paisesBot, modo)
};

// ===== COMPARAR =====
const res = await fetch(CSV_URL+"&nocache="+Date.now());
const csv = await res.text();
const ap = appParse(csv);
const bp = botParse(csv);
paisesBot = bp;   // el motor necesita la lista completa (firma igual a la de la app)
const byNameA = {}; ap.forEach(p=>byNameA[normName(p.nombre)]=p);
const byNameB = {}; bp.forEach(p=>byNameB[normName(p.nombre)]=p);
const round=(x)=> (typeof x==='number'&&isFinite(x))? Math.round(x*100)/100 : x;
let diffsTasa=0, diffsCross=0;

console.log("===== 1) TASAS Envio/Recibo por pais (app REAL vs bot), detal y mayor =====");
for(const k of Object.keys(byNameA)){
  if(/^efectivo venezuela/.test(k)) continue;
  const a=byNameA[k], b=byNameB[k]; if(!b) continue;
  for(const modo of ['detal','mayor']){
    const aE=round(appTEnv(a,modo)), bE=round(B.tEnv(b,modo));
    const aR=round(appTRec(a,modo)), bR=round(B.tRec(b,modo));
    if(aE!==bE){ console.log(`  [DIFF Envio ${modo}] ${a.nombre}: app=${aE} bot=${bE}`); diffsTasa++; }
    if(aR!==bR){ console.log(`  [DIFF Recibo ${modo}] ${a.nombre}: app=${aR} bot=${bR}`); diffsTasa++; }
  }
}
console.log(diffsTasa? `  -> ${diffsTasa} diferencias de tasa` : "  -> 0 diferencias de tasa (IDENTICO a la app) ✅");

console.log("");
console.log("===== 2) CRUCES directa+inversa, detal+mayor, varios montos =====");
const rutas=['Argentina','Chile','Colombia','Ecuador','Venezuela','Peru','Mexico','Brasil','Zelle','USDT','Europa','Panama'];
const montos=[100, 1000, 250000];
for(const oN of rutas){ for(const dN of rutas){ if(oN===dN) continue;
  const oa=byNameA[normName(oN)], da=byNameA[normName(dN)], ob=byNameB[normName(oN)], db=byNameB[normName(dN)];
  if(!oa||!da||!ob||!db) continue;
  for(const modo of ['detal','mayor']){ for(const m of montos){ for(const dir of ['directa','inversa']){
    const av = round(dir==='inversa'?appConvInv(oa,da,m,ap,modo):appConv(oa,da,m,ap,modo));
    const bv = round(dir==='inversa'?B.convInv(ob,db,m,modo):B.conv(ob,db,m,modo));
    const rel = av!==0 ? Math.abs(av-bv)/Math.abs(av) : (bv===0?0:1);
    if(rel>0.001){ if(diffsCross<30) console.log(`  [DIFF] ${oN}->${dN} ${dir} ${modo} ${m}: app=${av} bot=${bv}`); diffsCross++; }
  }}}
}}
console.log(diffsCross? `  -> ${diffsCross} diferencias de cruce` : "  -> 0 diferencias de cruce (IDENTICO a la app) ✅");

// ===== CANDADO =====
// Sale con codigo de error si app y bot NO dan lo mismo, para que el deploy se
// detenga solo. Antes esto siempre salia con exito y una diferencia podia pasar
// desapercibida: asi llegamos a tener 581 diferencias en produccion sin notarlo.
const total = diffsTasa + diffsCross;
if (total > 0) {
  console.log("");
  console.log(`❌ El bot NO calcula igual que la app (${total} diferencias). NO despliegues asi.`);
  console.log("   Revisa src/motor.js y que build_v12.ps1 lo este inyectando bien.");
  process.exit(1);
}
console.log("");
console.log("✅ El bot calcula EXACTAMENTE igual que la app.");
