// Times one procedural pass (apply) over a 5,000-element document with 200 filters.
// Runs in jsdom, so the numbers are an upper-bound smoke check, not a browser measurement.
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';

const SRC = readFileSync(new URL('../procedural.js', import.meta.url), 'utf8');
const ENTRIES = 2500; // each entry is a div and a span: 5,000 elements
const FILTERS = 200;
const RUNS = 20;

const parts = [];
for (let i = 0; i < ENTRIES; i++) {
  const cls = i % 50 === 0 ? 'ad-slot' : 'item';
  parts.push(`<div class="${cls} g${i % 20}" data-x="v${i % 7}" id="e${i}"><span>text ${i}</span></div>`);
}
const dom = new JSDOM(`<body>${parts.join('')}</body>`, { runScripts: 'outside-only' });
dom.window.eval(SRC);
const api = dom.window.wbeProcedural;

const op = (type, arg) => ({ type, arg });
const filters = [];
for (let i = 0; i < FILTERS; i++) {
  if (i < 100) filters.push({ selector: [op('css-selector', `.k${i}`)] });
  else if (i < 140) filters.push({ selector: [op('css-selector', `div.g${i % 20}`), op('has-text', `word${i}`)] });
  else if (i < 170) filters.push({ selector: [op('has-text', `nomatch${i}`)] });
  else if (i < 185) filters.push({ selector: [op('css-selector', 'div.item'), op('matches-attr', `data-x=v${i % 7}`)] });
  else filters.push({ selector: [op('css-selector', `div.g${i % 20}`), op('upward', 'body')], action: { type: 'remove-class', arg: `nope${i}` } });
}
const json = filters.map((f) => JSON.stringify(f));

api.apply(json);
const times = [];
for (let r = 0; r < RUNS; r++) {
  const t0 = performance.now();
  api.apply(json);
  times.push(performance.now() - t0);
}
times.sort((a, b) => a - b);
const median = times[Math.floor(times.length / 2)];
const mean = times.reduce((a, b) => a + b, 0) / times.length;
console.log(`elements=${dom.window.document.querySelectorAll('*').length} filters=${FILTERS} runs=${RUNS}`);
console.log(`pass median=${median.toFixed(1)} ms mean=${mean.toFixed(1)} ms min=${times[0].toFixed(1)} ms`);
