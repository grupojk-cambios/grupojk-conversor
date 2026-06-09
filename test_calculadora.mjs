// Test local del motor de cálculo portado desde la app JK Conversor.
// Descarga el CSV en vivo, construye los países y corre conversiones de prueba.
// Objetivo: confirmar que el bot dará los MISMOS números que la app.

const CSV_URL = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv";

// ---------- Parser + builder (idéntico al que irá en el bot) ----------
function parseCSV(text) {
  const lineas = text.split(/\r?\n/).filter((l) => l.trim().length > 0);
  const parseLine = (linea) => {
    const row = [];
    let inQ = false;
    let cur = "";
    for (const c of linea) {
      if (c === '"') inQ = !inQ;
      else if (c === "," && !inQ) { row.push(cur); cur = ""; }
      else cur += c;
    }
    row.push(cur);
    return row.map((s) => s.trim());
  };
  return lineas.map(parseLine);
}
function num(s) {
  if (s === undefined || s === null || s === "") return 0;
  let v = String(s).replace(/\s/g, "").replace(",", ".");
  const n = parseFloat(v);
  return isNaN(n) ? 0 : n;
}
function norm(s) {
  return (s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9 ]/g, "").trim();
}
function construirPaises(text) {
  const filas = parseCSV(text);
  if (!filas.length) return [];
  const head = filas[0].map((h) => h.toUpperCase());
  const idx = {
    factorEUR: head.findIndex((h) => h.includes("FACTOR EUR") || h.includes("VALOR EUR")),
    factorUSDT: head.findIndex((h) => h.includes("FACTOR USDT") || h.includes("VALOR USDT")),
    cod: head.findIndex((h) => h.includes("CÓDIGO") || h.includes("CODIGO") || h.includes("BANCO")),
    moneda: head.findIndex((h) => h.includes("NOMBRE") || h.includes("MONEDA")),
    mEMayor: head.findIndex((h) => h.includes("MARGEN ENVIO MAYOR") || h.includes("MARGEN ENVÍO MAYOR")),
    mRMayor: head.findIndex((h) => h.includes("MARGEN RECIBO MAYOR")),
  };
  const paises = [];
  for (let i = 1; i < filas.length; i++) {
    const row = filas[i];
    const nombre = (row[0] || "").trim();
    if (!nombre) continue;
    const tE = num(row[1]);
    const mE = row[2] !== undefined && row[2] !== "" ? num(row[2]) : 6;
    const tR = num(row[3]);
    const mR = row[4] !== undefined && row[4] !== "" ? num(row[4]) : 6;
    if (tE === 0 && tR === 0) continue;
    const codigo = idx.cod !== -1 && row[idx.cod] ? row[idx.cod].toUpperCase() : nombre.substring(0, 3).toUpperCase();
    paises.push({
      nombre,
      codigo,
      moneda: idx.moneda !== -1 && row[idx.moneda] ? row[idx.moneda] : "Divisa local",
      tasaProveedorEnvio: tE,
      margenEnvio: mE,
      tasaProveedorRecibo: tR,
      margenRecibo: mR,
      margenEnvioMayor: idx.mEMayor !== -1 ? num(row[idx.mEMayor]) : 0,
      margenReciboMayor: idx.mRMayor !== -1 ? num(row[idx.mRMayor]) : 0,
      factorEUR: idx.factorEUR !== -1 ? num(row[idx.factorEUR]) : 0,
      factorUSDT: idx.factorUSDT !== -1 ? num(row[idx.factorUSDT]) : 0,
    });
  }
  return paises;
}

// ---------- Motor (portado de constants.js) ----------
function isCajaDolar(p) {
  if (!p) return false;
  const cod = (p.codigo || "").toUpperCase();
  const nom = (p.nombre || "").toUpperCase();
  return ["USD", "USDT"].includes(cod) || nom.includes("USDT") || nom.includes("ZELLE") || nom.includes("EFECTIVO VEN");
}
function margenEnvio(p, modo) {
  return modo === "mayor" && p.margenEnvioMayor > 0 ? p.margenEnvioMayor : p.margenEnvio || 0;
}
function margenRecibo(p, modo) {
  return modo === "mayor" && p.margenReciboMayor > 0 ? p.margenReciboMayor : p.margenRecibo || 0;
}
function calcularTasaEnvio(p, modo) {
  const t = p.tasaProveedorEnvio || 0;
  if (t === 0) return 0;
  return t * (1 - margenEnvio(p, modo) / 100);
}
function calcularTasaRecibo(p, modo) {
  const t = p.tasaProveedorRecibo || 0;
  if (t === 0) return 0;
  return t * (1 + margenRecibo(p, modo) / 100);
}
function obtenerTasasProcesadas(origen, destino, modo) {
  let tasaOrigenParaDolares = calcularTasaRecibo(origen, modo);
  let tasaDestinoDesdeDolares = calcularTasaEnvio(destino, modo);
  const BASES = ["EUR", "USDT", "GBP", "EU"];
  const FUERTES = ["EUR", "GBP", "EU"];
  const oc = (origen.codigo || "").toUpperCase();
  const dc = (destino.codigo || "").toUpperCase();
  let factorAplicado = false;
  if (BASES.includes(oc) && !isCajaDolar(destino) && !BASES.includes(dc)) {
    const f = parseFloat(destino["factor" + oc]);
    if (f > 0 && !isNaN(f)) { tasaOrigenParaDolares = 1 / f; factorAplicado = true; }
  } else if (!BASES.includes(oc) && !isCajaDolar(origen) && BASES.includes(dc)) {
    const f = parseFloat(origen["factor" + dc]);
    if (f > 0 && !isNaN(f)) { tasaDestinoDesdeDolares = 1 / f; factorAplicado = true; }
  }
  if (!factorAplicado) {
    const oF = FUERTES.includes(oc), dF = FUERTES.includes(dc);
    const oD = isCajaDolar(origen), dD = isCajaDolar(destino);
    if (oF || dF) {
      if (oF && !oD) tasaOrigenParaDolares = 1 / Math.max(tasaOrigenParaDolares, 0.001);
      if (oF && dD) tasaDestinoDesdeDolares = 1;
      if (oD && dF) tasaOrigenParaDolares = 1;
    } else {
      if (oD && !dD) {
        const mO = margenRecibo(origen, modo), mD = margenEnvio(destino, modo);
        tasaOrigenParaDolares = 1;
        const tBaseD = destino.tasaProveedorEnvio || 0;
        tasaDestinoDesdeDolares = tBaseD * (1 - (mO + mD) / 100);
      } else if (oD && dD) {
        tasaOrigenParaDolares = 1;
        const tBaseD = destino.tasaProveedorEnvio || 0;
        const mD = margenEnvio(destino, modo);
        tasaDestinoDesdeDolares = tBaseD * (1 - mD / 100);
      } else if (!oD && dD) {
        const mO = margenRecibo(origen, modo), mD = margenEnvio(destino, modo);
        const tBaseO = origen.tasaProveedorRecibo || 0;
        tasaOrigenParaDolares = tBaseO * (1 + (mO + mD) / 100);
        tasaDestinoDesdeDolares = 1;
      }
    }
  }
  if (tasaOrigenParaDolares === 0) tasaOrigenParaDolares = 1;
  return { tasaOrigenParaDolares, tasaDestinoDesdeDolares };
}
function calcularConversion(origen, destino, monto, modo) {
  const { tasaOrigenParaDolares, tasaDestinoDesdeDolares } = obtenerTasasProcesadas(origen, destino, modo);
  return (monto / tasaOrigenParaDolares) * tasaDestinoDesdeDolares;
}
function calcularConversionInversa(origen, destino, montoRecibir, modo) {
  const { tasaOrigenParaDolares, tasaDestinoDesdeDolares } = obtenerTasasProcesadas(origen, destino, modo);
  if (tasaDestinoDesdeDolares === 0) return 0;
  const tBaseD = destino.tasaProveedorEnvio || 0;
  if (tBaseD > 0 && tasaDestinoDesdeDolares < tBaseD) {
    const margenTotalDecimal = (tBaseD - tasaDestinoDesdeDolares) / tBaseD;
    return (montoRecibir / tBaseD) * (1 + margenTotalDecimal) * tasaOrigenParaDolares;
  }
  return (montoRecibir / tasaDestinoDesdeDolares) * tasaOrigenParaDolares;
}
function findPais(paises, q) {
  const nq = norm(q);
  if (!nq) return null;
  let p = paises.find((x) => norm(x.nombre) === nq);
  if (p) return p;
  const alias = { euros: "europa", eur: "europa", europa: "europa", tether: "usdt" };
  if (alias[nq]) { p = paises.find((x) => norm(x.nombre) === norm(alias[nq])); if (p) return p; }
  p = paises.find((x) => norm(x.nombre).includes(nq) || nq.includes(norm(x.nombre)));
  return p || null;
}

// ---------- Ejecución ----------
const res = await fetch(CSV_URL + "&nocache=" + Date.now());
const text = await res.text();
const paises = construirPaises(text);
console.log("Países cargados:", paises.length);
console.log("Lista:", paises.map((p) => `${p.nombre}(${p.codigo})`).join(", "));
console.log("\n--- Tasas por país (detal) ---");
for (const p of paises.slice(0, 25)) {
  const e = calcularTasaEnvio(p, "detal");
  const r = calcularTasaRecibo(p, "detal");
  console.log(`${p.nombre.padEnd(24)} Envío: ${e ? e.toFixed(2) : "N/D"}   Recibo: ${r ? r.toFixed(2) : "N/D"}`);
}

const casos = [
  ["Chile", "Colombia", 100, "directa"],
  ["Colombia", "Venezuela", 100000, "directa"],
  ["Zelle", "Venezuela", 100, "directa"],
  ["Zelle", "Colombia", 100, "directa"],
  ["USDT", "Colombia", 100, "directa"],
  ["Europa", "Colombia", 100, "directa"],
  ["Colombia", "Chile", 50000, "directa"],
  ["Zelle", "Venezuela", 50, "inversa"],
];
console.log("\n--- Conversiones de prueba (detal) ---");
for (const [o, d, m, dir] of casos) {
  const po = findPais(paises, o), pd = findPais(paises, d);
  if (!po || !pd) { console.log(`${o} -> ${d}: país no encontrado`); continue; }
  const cross = calcularConversion(po, pd, 1, "detal");
  const val = dir === "inversa" ? calcularConversionInversa(po, pd, m, "detal") : calcularConversion(po, pd, m, "detal");
  if (dir === "inversa") {
    console.log(`Para que lleguen ${m} ${pd.codigo} a ${pd.nombre}, enviar ~${val.toFixed(2)} ${po.codigo} (${po.nombre})`);
  } else {
    console.log(`${m} ${po.codigo} (${po.nombre}) -> ${val.toFixed(2)} ${pd.codigo} (${pd.nombre})   [1 ${po.codigo} = ${cross.toFixed(4)} ${pd.codigo}]`);
  }
}
