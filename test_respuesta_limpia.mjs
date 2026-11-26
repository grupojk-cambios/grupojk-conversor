// Prueba de "Separar Respuesta" (workflow "Bot JK - Atencion al Cliente e IA"): la limpieza fija que se le hace a la
// respuesta de la IA antes de mandarla por WhatsApp, y las reglas del prompt sobre lo que esta fuera de tema.
//
// Lo que la destapo (revision diaria del 25/11): a un cliente que pregunto "De verdad ?" el bot le contesto
// "Solo remesas de JK. Si necesitas ayuda con transferencias o tasas, aquí estoy. 😊". Dos errores: "De verdad?" no
// era fuera de tema, y la regla dice "Solo remesas de JK." sin nada mas (y nunca 😊).
//
// Todos los datos son INVENTADOS (el repositorio es publico). Correr con:  node test_respuesta_limpia.mjs

import { readFileSync } from 'fs';

const wf = JSON.parse(readFileSync('workflow_ia_atencion.json', 'utf8').replace(/^﻿/, ''));
const nodo = n => wf.nodes.find(x => x.name === n);
const SALTO = String.fromCharCode(10);

let fallos = 0;
const chk = (ok, etiqueta, detalle) => { if (!ok) fallos++; console.log('  ' + (ok ? 'OK   ' : 'FALLO') + ' ' + etiqueta.padEnd(76) + ' ' + (detalle || '')); };

const separar = (output, extra) => new Function('$json', nodo('Separar Respuesta').parameters.jsCode)(Object.assign({ output, sessionId: 'chat' }, extra || {})).map(i => i.json);
const textos = r => r.map(x => x.output);

console.log('=== 1) "Solo remesas de JK." va SOLO ===');
{
  let r = separar('Solo remesas de JK. Si necesitas ayuda con transferencias o tasas, aquí estoy. 😊');
  chk(JSON.stringify(textos(r)) === '["Solo remesas de JK."]', 'se le quita el relleno y el 😊 que le pegaba el modelo', '-> ' + JSON.stringify(textos(r)));
  r = separar('Solo remesas de JK.');
  chk(JSON.stringify(textos(r)) === '["Solo remesas de JK."]', 'si ya venia bien, queda igual');
  r = separar('solo remesas de JK 🙏');
  chk(JSON.stringify(textos(r)) === '["Solo remesas de JK."]', 'aunque venga en minuscula o con otro emoji');
  r = separar('Te paso la cuenta. Solo remesas de JK, no cambio cheques.');
  chk(r.length === 1 && r[0].output === 'Te paso la cuenta. Solo remesas de JK, no cambio cheques.', 'si la frase NO empieza asi, no se toca');
  // la forma que salio en vivo el 25/11 a las 20:29 (a una imagen que no era comprobante)
  r = separar('Lo siento, solo manejo remesas de JK. Si necesitas ayuda con eso, aquí estoy. 😊');
  chk(JSON.stringify(textos(r)) === '["Solo remesas de JK."]', '"Lo siento, solo manejo remesas de JK. ..." -> "Solo remesas de JK."', '-> ' + JSON.stringify(textos(r)));
  r = separar('Disculpa, solo hacemos remesas 🙏');
  chk(JSON.stringify(textos(r)) === '["Solo remesas de JK."]', '"Disculpa, solo hacemos remesas" -> igual');
  for (const t of ['Solo te falta la cuenta para tu remesa 👍', 'Solo necesito la captura del depósito', 'Las remesas solo salen en horario de atención'])
    chk(separar(t)[0].output === t, 'no se confunde con: "' + t + '"');
}

console.log('=== 2) El 😊 no va nunca ===');
{
  let r = separar('Hola 👋 Dime, ¿qué necesitas? 😊');
  chk(r[0].output === 'Hola 👋 Dime, ¿qué necesitas?', 'al final de la frase', '-> ' + JSON.stringify(r[0].output));
  r = separar('Hola 😊 ¿qué necesitas?');
  chk(r[0].output === 'Hola ¿qué necesitas?', 'en el medio (sin dejar doble espacio)', '-> ' + JSON.stringify(r[0].output));
  r = separar('Listo, recibido! 😊' + SALTO + 'Procesamos tu remesa enseguida ✅');
  chk(r[0].output === 'Listo, recibido!' + SALTO + 'Procesamos tu remesa enseguida ✅', 'antes de un salto de linea (los saltos se conservan)', '-> ' + JSON.stringify(r[0].output));
  r = separar('😊');
  chk(r.length === 1 && r[0].output === '😊', 'si la respuesta era SOLO el 😊, no se manda un mensaje vacio');
}

console.log('=== 3) Lo de antes sigue igual ===');
{
  const cuenta = 'Te paso la cuenta de Ecuador 👇' + SALTO + SALTO + '*CUENTA AUTORIZADA USD*' + SALTO + '1) 2200000001' + SALTO + '*Pichincha ahorro*';
  let r = separar(cuenta);
  chk(r.length === 1 && r[0].output === cuenta, 'una respuesta normal (con renglones vacios) queda tal cual');
  r = separar('Enviando 100 USD desde Ecuador, el destinatario recibe 92.000,00 VES en Venezuela.' + SALTO + 'Tasa: 920.00 VES' + SALTO + '---' + SALTO
    + 'Enviando 100 USD desde Ecuador, el destinatario recibe 380.000,00 COP en Colombia. 😊' + SALTO + 'Tasa: 3800.00 COP');
  chk(r.length === 2 && /Tasa: 920\.00 VES$/.test(r[0].output) && /^Enviando 100 USD/.test(r[1].output) && /Tasa: 3800\.00 COP$/.test(r[1].output)
      && !r.some(x => /---|😊/.test(x.output)),
      'dos cotizaciones -> 2 mensajes aparte, sin el "---" del medio y sin 😊', '-> ' + JSON.stringify(textos(r)));
  r = separar('Solo remesas de JK.', { sessionId: 'chat-123', otro: 7 });
  chk(r[0].sessionId === 'chat-123' && r[0].otro === 7, 'los demas datos del item pasan sin tocarse');
  r = separar('');
  chk(r.length === 1 && r[0].output === '', 'una respuesta vacia pasa como venia');
}

console.log('=== 4) Lo que dice el prompt ===');
{
  const prompt = nodo('AI Agent').parameters.options.systemMessage;
  chk(/responde EXACTAMENTE "Solo remesas de JK\." y nada mas/.test(prompt), 'fuera de tema: "Solo remesas de JK." exacto, sin nada mas');
  chk(/LA CHARLA CORTA NO ES FUERA DE TEMA/.test(prompt) && /"De verdad\?"/.test(prompt), 'la charla corta ("De verdad?", "En serio?") no es fuera de tema');
  chk(/"De verdad\?" \/ "En serio\?".*-> "Sí, así es 👍"/.test(prompt), 'y trae el ejemplo de como contestarla');
  chk(/IMAGEN SIN DATOS:.*NO es fuera de tema: responde SOLO "Recibí la imagen 👍 Dime, ¿qué necesitas\?"/.test(prompt), 'una imagen que no es comprobante ni cuenta NO es fuera de tema');
  chk(!/recarga/i.test(prompt.split('LA CHARLA CORTA')[0].split('- Fuera de tema')[1] || ''), 'las recargas NO se ponen como fuera de tema (Kelvin puede venderlas)');
}

console.log('');
console.log(fallos ? ('FALLARON ' + fallos) : 'TODO OK');
process.exit(fallos ? 1 : 0);
