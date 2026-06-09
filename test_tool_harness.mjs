// Extrae el jsCode REAL de la calculadora desde el workflow desplegado
// y lo ejecuta simulando cómo n8n/el agente lo invoca.
import { readFile } from "node:fs/promises";

const wf = JSON.parse((await readFile(new URL("./workflow_bot_whatsapp_v3.json", import.meta.url), "utf8")).replace(/^﻿/, ""));
const tool = wf.nodes.find((n) => n.name === "Calculadora de Conversion");
const code = tool.parameters.jsCode;

// Simula $getWorkflowStaticData VACÍO para forzar el camino de fetch (peor caso).
const fakeStaticEmpty = () => ({});

// Runner: el tool de n8n ejecuta el código con `query` y helpers en scope.
function runTool(code, query, getStatic) {
  const fn = new Function("query", "$getWorkflowStaticData", code);
  return fn(query, getStatic);
}

const casos = [
  { pais_origen: "Chile", pais_destino: "Colombia", monto: 100, direccion: "directa", modo: "detal" },
  { pais_origen: "Zelle", pais_destino: "Venezuela", monto: 100, direccion: "directa", modo: "detal" },
  { pais_origen: "Zelle", pais_destino: "Colombia", monto: 100, direccion: "directa", modo: "detal" },
  { pais_origen: "Europa", pais_destino: "Colombia", monto: 100, direccion: "directa", modo: "detal" },
  { pais_origen: "Zelle", pais_destino: "Venezuela", monto: 50, direccion: "inversa", modo: "detal" },
  { pais_origen: "Marte", pais_destino: "Colombia", monto: 100, direccion: "directa", modo: "detal" }, // país inexistente
];

console.log("=== Probando camino FETCH (static data vacío) ===");
for (const q of casos) {
  try {
    const out = await runTool(code, q, fakeStaticEmpty);
    console.log(`${q.pais_origen}->${q.pais_destino} ${q.monto} (${q.direccion}):`, out);
  } catch (e) {
    console.log(`${q.pais_origen}->${q.pais_destino}: ERROR ->`, e.message);
  }
}

// Ahora simula static data CON datos (camino normal en producción)
console.log("\n=== Probando camino STATIC DATA (con datos precargados) ===");
// Reusar el builder del otro test para poblar paisesData
const CSV_URL = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv";
const res = await fetch(CSV_URL + "&nocache=" + Date.now());
const text = await res.text();
// parseo mínimo idéntico
function parseCSV(t){const L=t.split(/\r?\n/).filter(l=>l.trim().length>0);const pl=(l)=>{const r=[];let q=false,c='';for(const ch of l){if(ch==='"')q=!q;else if(ch===','&&!q){r.push(c);c='';}else c+=ch;}r.push(c);return r.map(s=>s.trim());};return L.map(pl);}
function num(s){if(s==null||s==='')return 0;let v=String(s).replace(/\s/g,'').replace(',','.');const n=parseFloat(v);return isNaN(n)?0:n;}
const filas=parseCSV(text);const head=filas[0].map(h=>h.toUpperCase());
const idx={factorEUR:head.findIndex(h=>h.includes('FACTOR EUR')),factorUSDT:head.findIndex(h=>h.includes('FACTOR USDT')),cod:head.findIndex(h=>h.includes('CODIGO')||h.includes('BANCO')),moneda:head.findIndex(h=>h.includes('NOMBRE')||h.includes('MONEDA')),mEMayor:head.findIndex(h=>h.includes('MARGEN ENVIO MAYOR')),mRMayor:head.findIndex(h=>h.includes('MARGEN RECIBO MAYOR'))};
const paisesData=[];
for(let i=1;i<filas.length;i++){const row=filas[i];const nombre=(row[0]||'').trim();if(!nombre)continue;const tE=num(row[1]);const mE=row[2]!=null&&row[2]!==''?num(row[2]):6;const tR=num(row[3]);const mR=row[4]!=null&&row[4]!==''?num(row[4]):6;if(tE===0&&tR===0)continue;const codigo=idx.cod!==-1&&row[idx.cod]?row[idx.cod].toUpperCase():nombre.substring(0,3).toUpperCase();paisesData.push({nombre,codigo,moneda:idx.moneda!==-1&&row[idx.moneda]?row[idx.moneda]:'Divisa local',tasaProveedorEnvio:tE,margenEnvio:mE,tasaProveedorRecibo:tR,margenRecibo:mR,margenEnvioMayor:idx.mEMayor!==-1?num(row[idx.mEMayor]):0,margenReciboMayor:idx.mRMayor!==-1?num(row[idx.mRMayor]):0,factorEUR:idx.factorEUR!==-1?num(row[idx.factorEUR]):0,factorUSDT:idx.factorUSDT!==-1?num(row[idx.factorUSDT]):0});}
const fakeStaticFull = () => ({ paisesData });
for (const q of casos.slice(0, 4)) {
  const out = await runTool(code, q, fakeStaticFull);
  console.log(`${q.pais_origen}->${q.pais_destino} ${q.monto}:`, out);
}
