const SHEET = "https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?gid=908170655&single=true&output=csv";
const Q = '"';
function parseCSV(text){
  const rows=[]; let row=[]; let cur=''; let inQ=false;
  for (let i=0; i<text.length; i++){
    const c = text[i];
    if (inQ){ if (c===Q){ if (text[i+1]===Q){ cur+=Q; i++; } else inQ=false; } else cur+=c; }
    else { if (c===Q) inQ=true; else if (c===',') { row.push(cur); cur=''; } else if (c==='\r') {} else if (c==='\n') { row.push(cur); rows.push(row); row=[]; cur=''; } else cur+=c; }
  }
  if (cur.length>0 || row.length>0){ row.push(cur); rows.push(row); }
  return rows.map(r => r.map(s => s.trim())).filter(r => r.some(c => c.length>0));
}
const normH = s => String(s||'').toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g,'').trim();

// Replica EXACTA de la logica del bot
function cuentasDelDia(filasC, modo, diaIndex){
  const headC = (filasC[0]||[]).map(normH);
  const iTipo = headC.findIndex(h => h.indexOf('TIPO') !== -1 || h.indexOf('TARIFA') !== -1);
  const iDetal = headC.findIndex(h => h === 'DETAL');
  const iMayor = headC.findIndex(h => h === 'MAYOR');
  const todas = [];
  for (let i=1; i<filasC.length; i++){
    const row = filasC[i];
    const pais=(row[0]||'').trim(); const datos=(row[3]||'').trim();
    if (!pais || !datos) continue;
    if (!/^s/i.test((row[2]||'').trim())) continue;
    let esDetal = true, esMayor = true;
    if (iTipo !== -1){
      const t = normH(row[iTipo]);
      if (t.indexOf('DETAL') !== -1 && t.indexOf('MAYOR') === -1) esMayor = false;
      else if (t.indexOf('MAYOR') !== -1 && t.indexOf('DETAL') === -1) esDetal = false;
    } else if (iDetal !== -1 || iMayor !== -1){
      if (iDetal !== -1) esDetal = /^s/i.test(String(row[iDetal]||'').trim());
      if (iMayor !== -1) esMayor = /^s/i.test(String(row[iMayor]||'').trim());
      if (!esDetal && !esMayor){ esDetal = true; esMayor = true; }
    }
    if (modo === 'mayor' ? !esMayor : !esDetal) continue;
    todas.push({ Pais:pais, Metodo:(row[1]||'').trim(), Datos:datos });
  }
  const porPais = {};
  for (const c of todas){ const k = normH(c.Pais); (porPais[k]=porPais[k]||[]).push(c); }
  const out = [];
  for (const k in porPais){ const arr=porPais[k]; const idx=((diaIndex%arr.length)+arr.length)%arr.length; out.push(arr[idx]); }
  return out;
}

const csv = await (await fetch(SHEET + "&n=" + Date.now())).text();
const filasC = parseCSV(csv);
const hoy = Math.floor((Date.now()-5*3600000)/86400000);

console.log("=== 1) MISMA cuenta para TODOS los clientes el mismo dia ===");
const clientes = ["+593961230380","+584121112233","+573001234567"];
for (const cli of clientes){
  const c = cuentasDelDia(filasC,'detal',hoy).find(x => normH(x.Pais)==='VENEZUELA' && normH(x.Metodo)==='BANESCO');
  console.log("  cliente " + cli + " -> " + (c ? c.Datos.split('\n').filter(Boolean)[0] : '(sin cuenta)'));
}
console.log("  (el indice del dia NO depende del cliente -> todos reciben la misma)");

console.log("");
console.log("=== 2) Rotacion dia a dia (Banesco Venezuela) ===");
for (let d=0; d<4; d++){
  const c = cuentasDelDia(filasC,'detal',hoy+d).find(x => normH(x.Pais)==='VENEZUELA' && normH(x.Metodo)==='BANESCO');
  console.log("  dia +" + d + " -> " + (c ? c.Datos.split('\n').filter(Boolean)[0] : '(sin cuenta)'));
}

console.log("");
console.log("=== 3) Filtro DETAL vs MAYOR (hoja actual, sin columna Tipo todavia) ===");
for (const modo of ['detal','mayor']){
  const cs = cuentasDelDia(filasC, modo, hoy);
  console.log("  modo " + modo + " -> " + cs.length + " cuentas: " + cs.map(c=>c.Pais+"/"+c.Metodo).join(", "));
}
console.log("  (sin columna Tipo: todas sirven para ambos = compatible con tu hoja actual)");
