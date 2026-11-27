const url = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRwirpun5iWeuc7fc0mvv-nXQl-2ZyJMkOOJbNGLoh9U5qb5Hy9SRKnldeifWHp8a10MC1UK_0DU8co/pub?output=csv';
fetch(url).then(r => r.text()).then(async t => {
  const { obtenerTasasProcesadas, calcularConversion, calcularConversionInversa } = await import('./src/motor.js');
  const rows = t.split('\n').map(l => l.split(','));
  const parseVal = (str) => {
    if (!str) return 0;
    let s = str.replace(/\s/g, '').replace(',', '.');
    const val = parseFloat(s);
    return isNaN(val) ? 0 : val;
  };
  const parseValNullable = (str) => {
    if (str === undefined || str === null || str.trim() === '') return null;
    let s = str.replace(/\s/g, '').replace(',', '.');
    const val = parseFloat(s);
    return isNaN(val) ? null : val;
  };
  
  const paises = rows.slice(1).map((r, i) => ({
    id: i + 1,
    nombre: r[0]?.trim(),
    codigo: r[7]?.trim() || r[0]?.trim().substring(0,3).toUpperCase(),
    tasaProveedorEnvio: parseVal(r[1]),
    margenEnvio: parseVal(r[2]),
    tasaProveedorRecibo: parseVal(r[3]),
    margenRecibo: parseVal(r[4]),
    factorEUR: parseVal(r[5]),
    margenEnvioMayor: parseValNullable(r[9]),
    margenReciboMayor: parseValNullable(r[10])
  })).filter(p => p.nombre);

  const ecuador = paises.find(p => p.nombre.toLowerCase() === 'ecuador');
  console.log('Ecuador en Sheets:', ecuador);

  const testList = ['Colombia', 'Venezuela', 'Zelle', 'USDT', 'Panamá', 'Europa', 'Chile', 'Perú'];
  for (const name of testList) {
    const p = paises.find(x => x.nombre.toLowerCase().includes(name.toLowerCase()));
    if (!p) continue;
    const c1 = calcularConversion(ecuador, p, 100, paises, 'detal');
    const c2 = calcularConversion(p, ecuador, 100, paises, 'detal');
    const t1 = obtenerTasasProcesadas(ecuador, p, paises, 'detal');
    const t2 = obtenerTasasProcesadas(p, ecuador, paises, 'detal');
    console.log(`\n--- Ecuador <-> ${p.nombre} ---`);
    console.log(`100 Ecuador -> ${p.nombre}: ${c1} ${p.codigo} (tOrig: ${t1.tasaOrigenParaDolares}, tDest: ${t1.tasaDestinoDesdeDolares})`);
    console.log(`100 ${p.nombre} -> Ecuador: ${c2} USD (tOrig: ${t2.tasaOrigenParaDolares}, tDest: ${t2.tasaDestinoDesdeDolares})`);
  }
});
