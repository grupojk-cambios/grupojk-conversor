// Prueba del motor de calculo del bot con datos reales del CSV.
// Replica EXACTA de las funciones del nodo "Calculadora de Conversion".

const CSV_URL = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv";

function parseCSV(text){
  const lineas = text.split(/\r?\n/).filter(l => l.trim().length>0);
  const parseLine = (linea)=>{ const row=[]; let inQ=false; let cur=''; for(const c of linea){ if(c==='"') inQ=!inQ; else if(c===',' && !inQ){ row.push(cur); cur=''; } else cur+=c; } row.push(cur); return row.map(s=>s.trim()); };
  return lineas.map(parseLine);
}
function num(s){ if(s===undefined||s===null||s==='') return 0; let v=String(s).replace(/\s/g,'').replace(',', '.'); const n=parseFloat(v); return isNaN(n)?0:n; }
function norm(s){ return (s||'').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^a-z0-9 ]/g,'').trim(); }
function construirPaises(text){
  const filas = parseCSV(text); if(!filas.length) return [];
  const head=(filas[0]||[]).map(h=>String(h||'').toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g,''));
  const idx={ factorEUR:head.findIndex(h=>h.includes('FACTOR EUR')||h.includes('VALOR EUR')), factorUSDT:head.findIndex(h=>h.includes('FACTOR USDT')||h.includes('VALOR USDT')), cod:head.findIndex(h=>h.includes('CODIGO')||h.includes('BANCO')), moneda:head.findIndex(h=>h.includes('NOMBRE')||h.includes('MONEDA')), mEMayor:head.findIndex(h=>h.includes('MARGEN ENVIO MAYOR')), mRMayor:head.findIndex(h=>h.includes('MARGEN RECIBO MAYOR')), ciudades:head.findIndex(h=>h.includes('CIUDADES')) };
  const paises=[];
  for(let i=1;i<filas.length;i++){ const row=filas[i]; const nombre=(row[0]||'').trim(); if(!nombre) continue; const tE=num(row[1]); const mE=(row[2]!==undefined&&row[2]!=='')?num(row[2]):6; const tR=num(row[3]); const mR=(row[4]!==undefined&&row[4]!=='')?num(row[4]):6; if(tE===0&&tR===0) continue; const codigo=idx.cod!==-1&&row[idx.cod]?row[idx.cod].toUpperCase():nombre.substring(0,3).toUpperCase(); paises.push({ nombre, codigo, moneda: idx.moneda!==-1&&row[idx.moneda]?row[idx.moneda]:'Divisa local', tasaProveedorEnvio:tE, margenEnvio:mE, tasaProveedorRecibo:tR, margenRecibo:mR, margenEnvioMayor: idx.mEMayor!==-1?num(row[idx.mEMayor]):0, margenReciboMayor: idx.mRMayor!==-1?num(row[idx.mRMayor]):0, factorEUR: idx.factorEUR!==-1?num(row[idx.factorEUR]):0, factorUSDT: idx.factorUSDT!==-1?num(row[idx.factorUSDT]):0, ciudades: idx.ciudades!==-1&&row[idx.ciudades]?String(row[idx.ciudades]).trim():'' }); }
  return paises;
}
function isCajaDolar(p){ const c=(p.codigo||'').toUpperCase(); const n=(p.nombre||'').toUpperCase(); return ['USD','USDT'].includes(c)||n.includes('USDT')||n.includes('ZELLE')||n.includes('EFECTIVO VEN'); }
function mEnv(p,modo){ return modo==='mayor'&&p.margenEnvioMayor>0?p.margenEnvioMayor:(p.margenEnvio||0); }
function mRec(p,modo){ return modo==='mayor'&&p.margenReciboMayor>0?p.margenReciboMayor:(p.margenRecibo||0); }
function tEnv(p,modo){ const t=p.tasaProveedorEnvio||0; return t? t*(1-mEnv(p,modo)/100):0; }
function tRec(p,modo){ const t=p.tasaProveedorRecibo||0; return t? t*(1+mRec(p,modo)/100):0; }
function obtenerTasasProcesadas(origen,destino,modo){
  let tasaOrigenParaDolares=tRec(origen,modo);
  let tasaDestinoDesdeDolares=tEnv(destino,modo);
  const BASES=['EUR','USDT','GBP','EU']; const FUERTES=['EUR','GBP','EU'];
  const oc=(origen.codigo||'').toUpperCase(); const dc=(destino.codigo||'').toUpperCase();
  let factorAplicado=false;
  if(BASES.includes(oc) && !isCajaDolar(destino) && !BASES.includes(dc)){ const f=parseFloat(destino['factor'+oc]); if(f>0&&!isNaN(f)){ tasaOrigenParaDolares=1/f; factorAplicado=true; } }
  else if(!BASES.includes(oc) && !isCajaDolar(origen) && BASES.includes(dc)){ const f=parseFloat(origen['factor'+dc]); if(f>0&&!isNaN(f)){ tasaDestinoDesdeDolares=1/f; factorAplicado=true; } }
  if(!factorAplicado){
    const oF=FUERTES.includes(oc), dF=FUERTES.includes(dc), oD=isCajaDolar(origen), dD=isCajaDolar(destino);
    if(oF||dF){
      if(oF && !oD) tasaOrigenParaDolares=1/Math.max(tasaOrigenParaDolares,0.001);
      if(oF && dD) tasaDestinoDesdeDolares=1;
      if(oD && dF) tasaOrigenParaDolares=1;
    } else {
      if(oD && !dD){ const mO=mRec(origen,modo), mD=mEnv(destino,modo); tasaOrigenParaDolares=1; const tBaseD=destino.tasaProveedorEnvio||0; tasaDestinoDesdeDolares=tBaseD*(1-(mO+mD)/100); }
      else if(oD && dD){ tasaOrigenParaDolares=1; const tBaseD=destino.tasaProveedorEnvio||0; const mD=mEnv(destino,modo); tasaDestinoDesdeDolares=tBaseD*(1-mD/100); }
      else if(!oD && dD){ const mO=mRec(origen,modo), mD=mEnv(destino,modo); const tBaseO=origen.tasaProveedorRecibo||0; tasaOrigenParaDolares=tBaseO*(1+(mO+mD)/100); tasaDestinoDesdeDolares=1; }
    }
  }
  if(tasaOrigenParaDolares===0) tasaOrigenParaDolares=1;
  return { tasaOrigenParaDolares, tasaDestinoDesdeDolares };
}
function calcularConversion(origen,destino,monto,modo){ const r=obtenerTasasProcesadas(origen,destino,modo); return (monto/r.tasaOrigenParaDolares)*r.tasaDestinoDesdeDolares; }
function calcularConversionInversa(origen,destino,montoRecibir,modo){ const r=obtenerTasasProcesadas(origen,destino,modo); if(r.tasaDestinoDesdeDolares===0) return 0; const tBaseD=destino.tasaProveedorEnvio||0; if(tBaseD>0 && r.tasaDestinoDesdeDolares<tBaseD){ const md=(tBaseD-r.tasaDestinoDesdeDolares)/tBaseD; return (montoRecibir/tBaseD)*(1+md)*r.tasaOrigenParaDolares; } return (montoRecibir/r.tasaDestinoDesdeDolares)*r.tasaOrigenParaDolares; }
function evMatch(evList, nq){
  for (const x of evList) { const e=norm(String(x.nombre).split('-')[1]||''); if (e && (nq===e || nq.indexOf(e)!==-1)) return x; }
  for (const x of evList) { const c=norm(String(x.ciudades||'')); if (!c) continue; const toks=c.split(/[ ,]+/).filter(t=>t.length>=4); if (toks.some(t => nq.indexOf(t)!==-1)) return x; }
  return null;
}
function findPais(paises,q){ const nq=norm(q); if(!nq) return null;
  const evList = paises.filter(x=>/efectivo venezuela/i.test(x.nombre));
  if (evList.length && nq.indexOf('efectivo')!==-1) { return evMatch(evList, nq) || evList[0]; }
  let p=paises.find(x=>norm(x.nombre)===nq); if(p) return p;
  if (evList.length) { const m=evMatch(evList, nq); if (m) return m; }
  const alias={ euros:'europa', eur:'europa', tether:'usdt' }; if(alias[nq]){ p=paises.find(x=>norm(x.nombre)===norm(alias[nq])); if(p) return p; } p=paises.find(x=>norm(x.nombre).includes(nq)||nq.includes(norm(x.nombre))); return p||null; }

const res = await fetch(CSV_URL + "&nocache=" + Date.now());
const text = await res.text();
const paises = construirPaises(text);

console.log("Total paises parseados:", paises.length);
console.log("");

function test(label, origenQ, destinoQ, monto, direccion, modo='detal'){
  const o = findPais(paises, origenQ);
  const d = findPais(paises, destinoQ);
  if(!o){ console.log(`[${label}] NO encontro origen: ${origenQ}`); return; }
  if(!d){ console.log(`[${label}] NO encontro destino: ${destinoQ}`); return; }
  let r;
  if(direccion==='inversa') r = calcularConversionInversa(o,d,monto,modo);
  else r = calcularConversion(o,d,monto,modo);
  console.log(`[${label}]`);
  console.log(`  origen=${o.nombre} (${o.codigo})  destino=${d.nombre} (${d.codigo})`);
  console.log(`  ${direccion} monto=${monto} -> RESULTADO = ${r.toFixed(2)}`);
  console.log("");
}

console.log("===== CASO QUE FALLO: '1500$ en Caracas, pagar desde Ecuador' =====");
test("Efectivo VE Caracas (inversa)", "Ecuador", "Efectivo Venezuela", 1500, "inversa");
test("Caracas directo (inversa)", "Ecuador", "caracas", 1500, "inversa");
console.log("===== COMPARACION: lo que el bot hizo MAL (bolivares) =====");
test("Venezuela bolivares (inversa)", "Ecuador", "Venezuela", 1500, "inversa");
console.log("===== Otros chequeos =====");
test("Efectivo VE directa", "Ecuador", "Efectivo Venezuela", 100, "directa");
test("Colombia desde Ecuador", "Ecuador", "Colombia", 100, "directa");
console.log("===== Que 'Venezuela' (bolivares) SIGA funcionando bien =====");
test("Venezuela VES directa", "Ecuador", "Venezuela", 100, "directa");
test("Efectivo desde Colombia (inversa)", "Colombia", "Efectivo Venezuela", 500, "inversa");

console.log("===== CASO BUG: '710.000 cop a $ Ecuador' (capturas) =====");
test("CORRECTO: 710000 COP -> USD (directa Col->Ecu)", "Colombia", "Ecuador", 710000, "directa");
test("CORRECTO: recibir 710000 COP (inversa Ecu->Col)", "Ecuador", "Colombia", 710000, "inversa");
test("BUG reproducido: inversa Col->Ecu con 710 (parse 710.000 como 710)", "Colombia", "Ecuador", 710, "inversa");
test("OK previo: 207.76 USD Ecu->Col directa", "Ecuador", "Colombia", 207.76, "directa");
console.log("");

console.log("===== Reconocer CIUDADES por separado (como la app) =====");
for (const ciudad of ["Maracaibo","Barquisimeto","Valencia","Caracas","Margarita","Punto Fijo","Ejido","El Vigia"]) {
  const d = findPais(paises, ciudad);
  console.log(`  "${ciudad}" -> ${d ? d.nombre : 'NO ENCONTRADO'}`);
}

console.log("");
console.log("===== Ubicaciones de Efectivo Venezuela leidas POR SEPARADO (cada una con SU tasa) =====");
const evEntries = paises.filter(p=>/^efectivo venezuela/i.test(p.nombre));
evEntries.forEach(p => {
  const est=(String(p.nombre).split('-')[1]||'').trim();
  const ciu = p.ciudades || '(estado)';
  console.log(`  ${est} [${ciu}] -> Envio ${tEnv(p,'detal').toFixed(2)} | margenE ${p.margenEnvio} | mayorE ${p.margenEnvioMayor}`);
});

console.log("");
console.log("===== PRUEBA: si una ciudad tiene precio distinto, el calculo lo refleja =====");
// Clonamos y le subimos el margen de envio SOLO a Zulia (Maracaibo) a 15% para simular precio distinto
const paises2 = paises.map(p => ({...p}));
const zulia = paises2.find(p=>/zulia/i.test(p.nombre));
if (zulia) zulia.margenEnvio = 15;
function calc2(origenQ, destinoQ, monto, direccion){
  const o=findPais(paises2,origenQ), d=findPais(paises2,destinoQ);
  const r = direccion==='inversa' ? calcularConversionInversa(o,d,monto,'detal') : calcularConversion(o,d,monto,'detal');
  console.log(`  ${destinoQ}: recibir ${monto} -> enviar ${r.toFixed(2)} (destino=${d.nombre})`);
}
calc2("Ecuador","Maracaibo",1000,"inversa");  // Zulia con 15% (simulado) -> deberia ser MAS caro
calc2("Ecuador","Caracas",1000,"inversa");    // Caracas con 7% -> mas barato
console.log("  (Maracaibo debe salir mas caro que Caracas, demostrando precio por ciudad)");
