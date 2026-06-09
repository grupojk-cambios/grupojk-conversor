// Compara el motor del BOT (ya arreglado) contra el motor EXACTO de la app (src/constants.js)
// sobre el CSV en vivo, para detectar CUALQUIER diferencia numerica.
const CSV_URL = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv";

// ---------- util comun ----------
function parseCSVrow(linea){ const row=[]; let inQ=false; let cur=''; for(const c of linea){ if(c==='"') inQ=!inQ; else if(c===','&&!inQ){ row.push(cur); cur=''; } else cur+=c; } row.push(cur); return row; }
function normName(str){ return (str||'').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,''); }

// ====================== MOTOR APP (port fiel de src/constants.js) ======================
const PAISES_INICIALES = [
 {id:1,nombre:'Argentina',codigo:'ARS',factorEUR:0,factorUSDT:0},{id:2,nombre:'Uruguay',codigo:'UYU',factorEUR:0,factorUSDT:0},
 {id:3,nombre:'Chile',codigo:'CLP',factorEUR:0,factorUSDT:0},{id:4,nombre:'Paraguay',codigo:'PYG',factorEUR:0,factorUSDT:0},
 {id:5,nombre:'Brasil',codigo:'BRL',factorEUR:0,factorUSDT:0},{id:6,nombre:'Bolivia',codigo:'BOB',factorEUR:0,factorUSDT:0},
 {id:7,nombre:'Perú',codigo:'PEN',factorEUR:0,factorUSDT:0},{id:8,nombre:'Colombia',codigo:'COP',factorEUR:0,factorUSDT:0},
 {id:9,nombre:'Ecuador',codigo:'USD',factorEUR:0,factorUSDT:0},{id:10,nombre:'Venezuela',codigo:'VES',factorEUR:1,factorUSDT:1},
 {id:11,nombre:'Panamá',codigo:'USD',factorEUR:0,factorUSDT:0},{id:12,nombre:'Costa Rica',codigo:'CRC',factorEUR:0,factorUSDT:0},
 {id:13,nombre:'Nicaragua',codigo:'NIO',factorEUR:0,factorUSDT:0},{id:14,nombre:'Honduras',codigo:'HNL',factorEUR:0,factorUSDT:0},
 {id:15,nombre:'Guatemala',codigo:'GTQ',factorEUR:0,factorUSDT:0},{id:16,nombre:'Cuba',codigo:'CUP',factorEUR:0,factorUSDT:0},
 {id:17,nombre:'México',codigo:'MXN',factorEUR:0,factorUSDT:0},{id:18,nombre:'EEUU',codigo:'USD',factorEUR:0,factorUSDT:0},
 {id:19,nombre:'Europa',codigo:'EUR',factorEUR:0,factorUSDT:0},
];
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
      margenEnvioMayor: idxMEM!==-1&&row.length>idxMEM?parseVal(row[idxMEM]):0, margenReciboMayor: idxMRM!==-1&&row.length>idxMRM?parseVal(row[idxMRM]):0 });
  }
  return out;
}
const A={};
A.isCajaDolar=(p)=>['USD','USDT','EC','US','PA'].includes(p.codigo)||[9,11,18].includes(p.id)||(p.nombre||'').toLowerCase().includes('usdt');
A.tEnv=(p,modo)=>{ const t=parseFloat(p.tasaProveedorEnvio)||0; if(t===0)return 0; let m=(modo==='mayor'&&parseFloat(p.margenEnvioMayor)>0)?p.margenEnvioMayor:p.margenEnvio; return t*(1-(parseFloat(m)||0)/100); };
A.tRec=(p,modo)=>{ const t=parseFloat(p.tasaProveedorRecibo)||0; if(t===0)return 0; let m=(modo==='mayor'&&parseFloat(p.margenReciboMayor)>0)?p.margenReciboMayor:p.margenRecibo; return t*(1+(parseFloat(m)||0)/100); };
A.obtener=(o,d,modo)=>{ let tO=A.tRec(o,modo), tD=A.tEnv(d,modo); const BASES=['EUR','USDT','GBP','EU'],FU=['EUR','GBP','EU']; let fa=false;
  if(BASES.includes(o.codigo)&&!A.isCajaDolar(d)&&!BASES.includes(d.codigo)){ const f=parseFloat(d['factor'+o.codigo]); if(f>0&&!isNaN(f)){ tO=1/f; fa=true; } }
  else if(!BASES.includes(o.codigo)&&!A.isCajaDolar(o)&&BASES.includes(d.codigo)){ const f=parseFloat(o['factor'+d.codigo]); if(f>0&&!isNaN(f)){ tD=1/f; fa=true; } }
  if(!fa){ const oF=FU.includes(o.codigo),dF=FU.includes(d.codigo),oD=A.isCajaDolar(o),dD=A.isCajaDolar(d);
    if(oF||dF){ if(oF&&!oD)tO=1/Math.max(tO,0.001); if(oF&&dD)tD=1; if(oD&&dF)tO=1; }
    else { if(oD&&!dD){ const mO=parseFloat(o.margenRecibo)||0,mD=parseFloat(d.margenEnvio)||0; tO=1; const tB=parseFloat(d.tasaProveedorEnvio)||0; tD=tB*(1-(mO+mD)/100); }
      else if(oD&&dD){ tO=1; const tB=parseFloat(d.tasaProveedorEnvio)||0; const mD=parseFloat(d.margenEnvio)||0; tD=tB*(1-mD/100); }
      else if(!oD&&dD){ const mO=parseFloat(o.margenRecibo)||0,mD=parseFloat(d.margenEnvio)||0; const tB=parseFloat(o.tasaProveedorRecibo)||0; tO=tB*(1+(mO+mD)/100); tD=1; } } }
  if(tO===0)tO=1; return {tO,tD}; };
A.conv=(o,d,m,modo)=>{ const r=A.obtener(o,d,modo); return (m/r.tO)*r.tD; };
A.convInv=(o,d,m,modo)=>{ const r=A.obtener(o,d,modo); if(r.tD===0)return 0; const tB=parseFloat(d.tasaProveedorEnvio)||0; if(tB>0&&r.tD<tB){ const md=(tB-r.tD)/tB; return (m/tB)*(1+md)*r.tO; } return (m/r.tD)*r.tO; };

// ====================== MOTOR BOT (port del nodo, YA arreglado margen vacio=0) ======================
function num(s){ if(s===undefined||s===null||s==='')return 0; let v=String(s).replace(/\s/g,'').replace(',', '.'); const n=parseFloat(v); return isNaN(n)?0:n; }
function botParse(csv){
  const filas=csv.split(/\r?\n/).filter(l=>l.trim().length>0).map(parseCSVrow).map(r=>r.map(s=>s.trim()));
  const head=(filas[0]||[]).map(h=>String(h||'').toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g,''));
  const idx={ factorEUR:head.findIndex(h=>h.includes('FACTOR EUR')||h.includes('VALOR EUR')), factorUSDT:head.findIndex(h=>h.includes('FACTOR USDT')||h.includes('VALOR USDT')), cod:head.findIndex(h=>h.includes('CODIGO')||h.includes('BANCO')), moneda:head.findIndex(h=>h.includes('NOMBRE')||h.includes('MONEDA')), mEMayor:head.findIndex(h=>h.includes('MARGEN ENVIO MAYOR')), mRMayor:head.findIndex(h=>h.includes('MARGEN RECIBO MAYOR')) };
  const paises=[];
  for(let i=1;i<filas.length;i++){ const row=filas[i]; const nombre=(row[0]||'').trim(); if(!nombre)continue;
    const tE=num(row[1]); const mE=(row[2]!==undefined)?num(row[2]):6; const tR=num(row[3]); const mR=(row[4]!==undefined)?num(row[4]):6;
    if(tE===0&&tR===0)continue; const codigo=idx.cod!==-1&&row[idx.cod]?row[idx.cod].toUpperCase():nombre.substring(0,3).toUpperCase();
    paises.push({ nombre, codigo, tasaProveedorEnvio:tE, margenEnvio:mE, tasaProveedorRecibo:tR, margenRecibo:mR, margenEnvioMayor: idx.mEMayor!==-1?num(row[idx.mEMayor]):0, margenReciboMayor: idx.mRMayor!==-1?num(row[idx.mRMayor]):0, factorEUR: (idx.factorEUR!==-1?num(row[idx.factorEUR]):0)||(nombre.toLowerCase()==='venezuela'?1:0), factorUSDT: (idx.factorUSDT!==-1?num(row[idx.factorUSDT]):0)||(nombre.toLowerCase()==='venezuela'?1:0) }); }
  return paises;
}
const B={};
B.isCajaDolar=(p)=>{ const c=(p.codigo||'').toUpperCase(); const n=(p.nombre||'').toUpperCase(); return ['USD','USDT'].includes(c)||n.includes('USDT')||n.includes('ZELLE')||n.includes('EFECTIVO VEN'); };
B.tEnv=(p,modo)=>{ const t=p.tasaProveedorEnvio||0; const m=modo==='mayor'&&p.margenEnvioMayor>0?p.margenEnvioMayor:(p.margenEnvio||0); return t?t*(1-m/100):0; };
B.tRec=(p,modo)=>{ const t=p.tasaProveedorRecibo||0; const m=modo==='mayor'&&p.margenReciboMayor>0?p.margenReciboMayor:(p.margenRecibo||0); return t?t*(1+m/100):0; };
B.obtener=(o,d,modo)=>{ let tO=B.tRec(o,modo),tD=B.tEnv(d,modo); const BASES=['EUR','USDT','GBP','EU'],FU=['EUR','GBP','EU']; const oc=(o.codigo||'').toUpperCase(),dc=(d.codigo||'').toUpperCase(); let fa=false;
  if(BASES.includes(oc)&&!B.isCajaDolar(d)&&!BASES.includes(dc)){ const f=parseFloat(d['factor'+oc]); if(f>0&&!isNaN(f)){ tO=1/f; fa=true; } }
  else if(!BASES.includes(oc)&&!B.isCajaDolar(o)&&BASES.includes(dc)){ const f=parseFloat(o['factor'+dc]); if(f>0&&!isNaN(f)){ tD=1/f; fa=true; } }
  if(!fa){ const oF=FU.includes(oc),dF=FU.includes(dc),oD=B.isCajaDolar(o),dD=B.isCajaDolar(d);
    if(oF||dF){ if(oF&&!oD)tO=1/Math.max(tO,0.001); if(oF&&dD)tD=1; if(oD&&dF)tO=1; }
    else { if(oD&&!dD){ const mO=o.margenRecibo||0,mD=d.margenEnvio||0; tO=1; const tB=d.tasaProveedorEnvio||0; tD=tB*(1-(mO+mD)/100); }
      else if(oD&&dD){ tO=1; const tB=d.tasaProveedorEnvio||0; const mD=d.margenEnvio||0; tD=tB*(1-mD/100); }
      else if(!oD&&dD){ const mO=o.margenRecibo||0,mD=d.margenEnvio||0; const tB=o.tasaProveedorRecibo||0; tO=tB*(1+(mO+mD)/100); tD=1; } } }
  if(tO===0)tO=1; return {tO,tD}; };
B.conv=(o,d,m,modo)=>{ const r=B.obtener(o,d,modo); return (m/r.tO)*r.tD; };
B.convInv=(o,d,m,modo)=>{ const r=B.obtener(o,d,modo); if(r.tD===0)return 0; const tB=d.tasaProveedorEnvio||0; if(tB>0&&r.tD<tB){ const md=(tB-r.tD)/tB; return (m/tB)*(1+md)*r.tO; } return (m/r.tD)*r.tO; };

// ====================== COMPARAR ======================
const res = await fetch(CSV_URL+"&nocache="+Date.now());
const csv = await res.text();
const ap = appParse(csv);
const bp = botParse(csv);
const byNameA = {}; ap.forEach(p=>byNameA[normName(p.nombre)]=p);
const byNameB = {}; bp.forEach(p=>byNameB[normName(p.nombre)]=p);

const round=(x)=> (typeof x==='number'&&isFinite(x))? Math.round(x*100)/100 : x;
let diffsTasa=0, diffsCross=0;

console.log("===== 1) Comparar TASAS Envio/Recibo por pais (app vs bot) =====");
for(const k of Object.keys(byNameA)){
  if(/^efectivo venezuela/.test(k)) continue; // se evaluan aparte
  const a=byNameA[k], b=byNameB[k]; if(!b) continue;
  for(const modo of ['detal','mayor']){
    const aE=round(A.tEnv(a,modo)), bE=round(B.tEnv(b,modo));
    const aR=round(A.tRec(a,modo)), bR=round(B.tRec(b,modo));
    if(aE!==bE){ console.log(`  [DIFF Envio ${modo}] ${a.nombre}: app=${aE} bot=${bE}`); diffsTasa++; }
    if(aR!==bR){ console.log(`  [DIFF Recibo ${modo}] ${a.nombre}: app=${aR} bot=${bR}`); diffsTasa++; }
  }
}
console.log(diffsTasa? `  -> ${diffsTasa} diferencias de tasa` : "  -> 0 diferencias de tasa (IDENTICO a la app) ✅");

console.log("");
console.log("===== 2) Comparar CRUCES (directa e inversa) en matriz =====");
const rutas=['Argentina','Chile','Colombia','Ecuador','Venezuela','Peru','Mexico','Brasil','Zelle','USDT','Europa'];
const montos=[100, 1000, 250000];
for(const oN of rutas){ for(const dN of rutas){ if(oN===dN) continue;
  const oa=byNameA[normName(oN)], da=byNameA[normName(dN)], ob=byNameB[normName(oN)], db=byNameB[normName(dN)];
  if(!oa||!da||!ob||!db) continue;
  for(const modo of ['detal','mayor']){ for(const m of montos){ for(const dir of ['directa','inversa']){
    const av = round(dir==='inversa'?A.convInv(oa,da,m,modo):A.conv(oa,da,m,modo));
    const bv = round(dir==='inversa'?B.convInv(ob,db,m,modo):B.conv(ob,db,m,modo));
    const rel = av!==0 ? Math.abs(av-bv)/Math.abs(av) : (bv===0?0:1);
    if(rel>0.001){ if(diffsCross<25) console.log(`  [DIFF] ${oN}->${dN} ${dir} ${modo} ${m}: app=${av} bot=${bv}`); diffsCross++; }
  }}}
}}
console.log(diffsCross? `  -> ${diffsCross} diferencias de cruce` : "  -> 0 diferencias de cruce (IDENTICO a la app) ✅");

console.log("");
console.log("===== 3) Caso del cliente: tasa y montos Ecuador<->Colombia =====");
const ecu=byNameB[normName('Ecuador')], col=byNameB[normName('Colombia')];
console.log(`  Tasa Ecuador->Colombia (envio, 1 USD): ${round(B.conv(ecu,col,1,'detal'))} COP  (cliente esperaba ~3414)`);
console.log(`  710000 COP que deben LLEGAR -> enviar (inversa): ${round(B.convInv(ecu,col,710000,'detal'))} USD`);
console.log(`  207.76 USD enviados -> llegan (directa): ${round(B.conv(ecu,col,207.76,'detal'))} COP`);
