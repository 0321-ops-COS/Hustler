// Read-only parity oracle: executes index.html's own functions in a stubbed
// DOM so native expectations are observed behaviour, not transcription.
// Reads index.html and never writes it.
//
//   node oracle.mjs            --check (default): compare with expectations.json
//   node oracle.mjs --update   rewrite expectations.json (approved changes only)
//
// --check never writes, so expectations cannot be refreshed to make a failing
// test pass by accident.
//
// The Scoreboard, period tables and decline float are only reachable through
// rendering functions that read the wall clock and write HTML. Those are driven
// here with a fixed clock (Date is stubbed) and their rendered output is parsed,
// so the captured values are what the web app actually displays.

import fs from 'node:fs';
import vm from 'node:vm';

process.on('unhandledRejection', () => {});

const EXPECTATIONS = 'ios-app/tools/parity/expectations.json';
const MODE = process.argv.includes('--update') ? 'update' : 'check';

for (const flag of process.argv.slice(2)) {
  if (flag !== '--update' && flag !== '--check') {
    console.error(`unknown argument: ${flag}`);
    process.exit(2);
  }
}

// Thursday 29 Oct 2026, 18:00 UTC. Anchored well away from midnight so the
// device timezone cannot move the calendar date, and inside the week that the
// fixtures use (Monday 2026-10-26).
const FIXED_NOW = Date.parse('2026-10-29T18:00:00Z');

const html = fs.readFileSync('index.html', 'utf8');
const start = html.lastIndexOf('<script>');
const end = html.indexOf('</script>', start);
if (start < 0 || end < 0) throw new Error('could not locate the inline app script');
const appJs = html.slice(start + '<script>'.length, end);

const cache = new Map();
function node(sel) {
  return {
    _v: '',
    get value() { return this._v; },
    set value(v) { this._v = String(v); },
    textContent: '', innerHTML: '', checked: false, files: [], options: [], selectedIndex: 0,
    hidden: false, disabled: false, src: '', title: '', placeholder: '', type: '', id: sel,
    dataset: {}, style: { cssText: '' },
    classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } },
    addEventListener() {}, removeEventListener() {}, setAttribute() {}, getAttribute() { return null; },
    appendChild() {}, remove() {}, focus() {}, click() {}, closest() { return null; },
    querySelector() { return node('#child'); }, querySelectorAll() { return []; },
    getContext() { return {}; }
  };
}
const $ = (sel) => { if (!cache.has(sel)) cache.set(sel, node(sel)); return cache.get(sel); };

const sandbox = {
  $, console,
  document: {
    querySelector: $, querySelectorAll: () => [], addEventListener() {},
    createElement: () => node('#created'), body: { appendChild() {} }, visibilityState: 'visible'
  },
  window: { addEventListener() {} },
  navigator: {},
  location: { hash: '', pathname: '/', search: '', origin: 'http://localhost', href: '' },
  history: { replaceState() {}, pushState() {} },
  localStorage: { getItem: () => null, setItem() {}, removeItem() {}, clear() {} },
  setTimeout: () => 0, clearTimeout() {}, setInterval: () => 0,
  confirm: () => true, alert() {}, prompt: () => null
};

// Fixed clock: `renderGame`/`renderFloat` call `new Date()` for "now".
const RealDate = Date;
class StubDate extends RealDate {
  constructor(...args) {
    if (args.length === 0) super(FIXED_NOW); else super(...args);
  }
  static now() { return FIXED_NOW; }
}
sandbox.Date = StubDate;

vm.createContext(sandbox);
vm.runInContext(appJs, sandbox, { filename: 'index.html' });

const HDR = '| Date | Payout | Miles | Items | Per Mile | Net | Hourly | Verdict | Acceptance rate | Choice | Slack | Zone | Minutes | Source |\n' +
            '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|';
const A1 = '| 2026-10-25 18:00 | 7.00 | 5.0 | 2 | 1.40 | 5.10 | 20.40 |  |  | Accepted |  | Temecula | 30 | archive |';
const A2 = A1.replace('18:00', '19:30');

const texts = {
  empty: '',
  header_only: HDR,
  two_rows: HDR + '\n' +
    '| 2026-10-27 14:46 | 26.50 | 9.1 | 6 | 2.91 | 22.42 | 30.06 | TAKE IT | 80.00 | Accept | 15.25 |\n' +
    '| 2026-10-27 15:10 | 4.25 | 6.2 | 2 | 0.69 | -0.31 | -1.20 | SKIP | 89.00 | Declined | 0 |',
  row_numbered: HDR + '\n| 1 | 2026-10-26 09:00 | 12.00 | 4.0 | 3 | 3.00 | 9.06 | 27.18 | TAKE IT | 89 | Accept | 20 |',
  duplicated_rows: HDR + '\n' +
    '| 2026-10-27 14:46 | 26.50 | 9.1 | 6 | 2.91 | 22.42 | 30.06 | TAKE IT | 80.00 | Accept | 15.25 |\n' +
    '| 2026-10-27 14:46 | 26.50 | 9.1 | 6 | 2.91 | 22.42 | 30.06 | TAKE IT | 80.00 | Accept | 15.25 |',
  archive_dupes: HDR + '\n' + A1 + '\n' + A1,
  archive_plus_shortcut: HDR + '\n' + A1 + '\n' +
    '| 2026-10-25 18:20 | 9.00 | 5.0 | 2 | 1.80 | 7.10 | 21.30 | TAKE IT | 89.00 | Accepted | 10 |',
  csv_rows: 'date,time,zone,payout,miles,items,minutes,verdict,choice\n' +
    '2026-10-24,12:10,Murrieta,8.50,3.2,2,18,Accept,Accepted\n' +
    '2026-10-24,12:40,Murrieta,4.00,5.1,1,22,Decline,Declined',
  money_cells: HDR + '\n| 2026-10-23 11:00 | $1,234.50 | 9.1 | 2 | 135.66 | 1,200.00 | 100.00 | TAKE IT | 89.00 | Accept | 5 |',
  malformed: HDR + '\n' +
    '| 2026-10-22 10:00 | n/a | 3 | 1 | 1 | 1 | 1 | TAKE IT | 89 | Accept | 0 |\n' +
    '| not-a-date | 5 | 3 | 1 | 1 | 1 | 1 | SKIP | 89 | Accept | 0 |',
  derived_minutes: HDR + '\n| 2026-10-21 12:00 | 10.00 | 4.0 | 2 | 2.50 | 7.66 | 23.00 | TAKE IT | 89 | Accept | 0 |',
  rate_older_and_newest: HDR + '\n' +
    '| 2026-10-20 10:00 | 10.00 | 4.0 | 2 | 2.50 | 7.66 | 23.00 | TAKE IT | 92.00 | Accept | 0 |\n' +
    '| 2026-10-27 10:00 | 10.00 | 4.0 | 2 | 2.50 | 7.66 | 23.00 | TAKE IT | 87.50 | Accept | 0 |',
  rate_blank_newest: HDR + '\n' +
    '| 2026-10-26 10:00 | 9.00 | 4.0 | 2 | 2.25 | 6.66 | 20.00 | TAKE IT | 91.00 | Accept | 0 |\n' +
    '| 2026-10-27 10:00 | 10.00 | 4.0 | 2 | 2.50 | 7.66 | 23.00 | TAKE IT |  | Accept | 0 |',
  rate_archive_newest: HDR + '\n' +
    '| 2026-10-26 10:00 | 9.00 | 4.0 | 2 | 2.25 | 6.66 | 20.00 | TAKE IT | 91.00 | Accept | 0 |\n' + A2
};

const settings = {
  accept: 89, estPay: 7, estMph: 20, mpg: 17.5, wear: 0.12, gas: 5.75,
  rampTop: 90, rampLow: 85, floorMile: 0.75, floorHour: 10, baseMile: 1.5, baseHour: 18,
  bigItems: 3, bigMile: 2, bigHour: 20, emergency: 80, taxRate: 0.7, target: 85,
  caWage: 16.9, caPct: 120, caMile: 0.37, zoneGas: {}
};

const row = (o) => Object.assign({ date: '', time: '', zone: '', payout: '0', miles: '0', items: '0', minutes: '' }, o);
const verdicts = [
  { id: 'base_rate89', rate: 89, r: row({ payout: '12.50', miles: '4.2', items: '3', minutes: '25' }) },
  { id: 'rate90_base_bars', rate: 90, r: row({ payout: '12.50', miles: '4.2', items: '3', minutes: '25' }) },
  { id: 'rate85_floor_bars', rate: 85, r: row({ payout: '12.50', miles: '4.2', items: '3', minutes: '25' }) },
  { id: 'rate87_5_mid_ramp', rate: 87.5, r: row({ payout: '12.50', miles: '4.2', items: '3', minutes: '25' }) },
  { id: 'rate95_clamped', rate: 95, r: row({ payout: '12.50', miles: '4.2', items: '3', minutes: '25' }) },
  { id: 'rate80_clamped', rate: 80, r: row({ payout: '12.50', miles: '4.2', items: '3', minutes: '25' }) },
  { id: 'emergency_79_positive', rate: 79, r: row({ payout: '2.00', miles: '8.0', items: '1', minutes: '20' }) },
  { id: 'emergency_79_negative', rate: 79, r: row({ payout: '1.00', miles: '9.0', items: '1', minutes: '20' }) },
  { id: 'big_order_items4', rate: 87, r: row({ payout: '12.50', miles: '4.2', items: '4', minutes: '25' }) },
  { id: 'base_order_items3', rate: 87, r: row({ payout: '12.50', miles: '4.2', items: '3', minutes: '25' }) },
  { id: 'zero_miles', rate: 89, r: row({ payout: '6.00', miles: '0', items: '1', minutes: '12' }) },
  { id: 'blank_minutes', rate: 89, r: row({ payout: '9.00', miles: '3.0', items: '2', minutes: '' }) },
  { id: 'negative_minutes', rate: 89, r: row({ payout: '9.00', miles: '3.0', items: '2', minutes: '-5' }) },
  { id: 'zone_gas', rate: 89, r: row({ payout: '12.50', miles: '4.2', items: '3', minutes: '25', zone: 'Temecula' }), settings: { zoneGas: { Temecula: 6.5 } } },
  { id: 'exact_base_bar', rate: 90, r: row({ payout: '6.30', miles: '4.2', items: '1', minutes: '15' }) },
  { id: 'rate_zero', rate: 0, r: row({ payout: '12.50', miles: '4.2', items: '3', minutes: '25' }) }
];

const payload = { texts, settings, verdicts, words: ['Accepted', 'Declined', 'Accept', 'Decline', 'YES', 'no', 'No tip', 'TAKE IT', 'SKIP', '', 'good', 'pass', 'no way'],
  nums: ['12.5', '$1,234.5', '', 'abc', '12.5abc', '.5', '-3', '$', '1e3'],
  fs: [1.5, 0, -2.5, 1234.5, 0.125, 1.005, 2.675, 0.005, 1.335],
  lines: ['2026-10-27,14:46,Murrieta,26.50,9.1,6,30,TAKE IT,Accept',
          '2026-10-27,14:46,Murrieta,26.50,9.1,6,30,TAKE IT,Accept,shortcut,2.91,22.42,30.06,x,15.25',
          'not,a,valid,row', A1],
  ramps: [90, 89, 87.5, 85, 80, 95, 0] };

sandbox.__payload = payload;
const result = vm.runInContext(`(() => {
  const p = __payload, S0 = p.settings, out = {};
  out.header = HDRM;
  out.num = p.nums.map(num);
  out.f = p.fs.map(v => $f(v));
  out.yes = p.words.map(yes);
  out.took = p.words.map(took);
  out.ramp = p.ramps.map(r => ramp(S0, r));
  out.verdict = p.verdicts.map(c => {
    const P = Object.assign({}, S0, c.settings || {});
    const v = verdict(c.r, P, c.rate);
    return { id: c.id, ok: v.ok, mn: v.mn, h: v.h, netF: $f(v.net), hrF: $f(v.hr), pmF: $f(v.pm),
             reqMF: $f(v.reqM), reqHF: $f(v.reqH), net: v.net, hr: v.hr, pm: v.pm, reqM: v.reqM, reqH: v.reqH };
  });
  out.master = {}; out.rows = {}; out.parsed = {};
  for (const k of Object.keys(p.texts)) {
    const t = p.texts[k];
    out.master[k] = masterLog(t);
    out.rows[k] = logRows(masterLog(t));
    out.parsed[k] = parse(t).map(r => ({ date: r.date, time: r.time, zone: r.zone, payout: r.payout,
      miles: r.miles, items: r.items, minutes: r.minutes, net: r.net, hourly: r.hourly,
      verdict: r.verdict, rate: r.rate, choice: r.choice, src: r.src, slack: r.slack }));
  }
  out.pipe = p.lines.map(l => csvToPipe(l));
  out.arch = p.lines.map(isArchLine);
  out.merged = {
    archive_twice: mergeLog(p.texts.archive_dupes, p.texts.archive_dupes),
    header_plus_rows: mergeLog(p.texts.header_only, p.texts.two_rows),
    rows_twice: mergeLog(p.texts.two_rows, p.texts.two_rows)
  };
  out.accept = {};
  for (const k of ['two_rows', 'row_numbered', 'archive_dupes', 'rate_older_and_newest', 'rate_blank_newest', 'rate_archive_newest']) {
    analyze(parse(p.texts[k]));
    out.accept[k] = { LOGACC: LOGACC, LOGRATE: LOGRATE, settingsAccept: S.accept, rowCount: rows.length,
                      dedupedArchive: rows.filter(r => r.src === 'archive').length };
  }
  out.defaults = DEF;
  return out;
})()`, sandbox);

// ---- Scoreboard, period grouping and decline float -------------------------
// Rendered output of the web app, with a fixed clock so the result does not
// depend on the day the oracle runs.
const sbTexts = {
  mixed: HDR + '\n' +
    '| 2026-10-27 14:46 | 26.50 | 9.1 | 6 | 2.91 | 22.42 | 30.06 | TAKE IT | 80.00 | Accept | 15.25 |\n' +
    '| 2026-10-27 15:10 | 4.25 | 6.2 | 2 | 0.69 | -0.31 | -1.20 | SKIP | 89.00 | Declined | 0 |\n' +
    '| 2026-10-26 09:00 | 12.00 | 4.0 | 3 | 3.00 | 9.06 | 27.18 | TAKE IT | 91.00 | Accept | 10 |\n' +
    '| 2026-09-30 12:00 | 10.00 | 4.0 | 1 | 2.50 | 7.66 | 30.64 | TAKE IT | 88.00 | Accept | 5 |\n' +
    // Archive rows written the way `toLog` writes them: no net, no hourly.
    '| 2026-10-25 18:00 | 7.00 | 5.0 | 2 | 1.40 |  |  |  |  | Accepted |  | Temecula | 30 | archive |\n' +
    '| 2026-10-24 12:10 | 9.00 | 6.0 | 2 | 1.50 | 5.10 | 11.84 |  |  | Accepted |  |  | 25 | archive |',
  archive_only: HDR + '\n' +
    '| 2026-10-25 18:00 | 7.00 | 5.0 | 2 | 1.40 |  |  |  |  | Accepted |  | Temecula | 30 | archive |\n' +
    '| 2026-10-24 12:10 | 9.00 | 6.0 | 2 | 1.50 | 5.10 | 11.84 |  |  | Accepted |  |  | 25 | archive |'
};

const sbDates = [
  '2026-10-27', '2026-10-25', '2026-10-26', '2026-03-01', '2026-01-01',
  '2026-12-31', '2026-11-01', '2026-02-28', '2026-10-31', '2026-10-01'
];

const floatCases = [];
for (const rate of [null, 100, 95, 90, 89, 87.5, 85, 80, 70]) {
  for (const target of [85, 90, 0]) floatCases.push({ rate, target });
}

sandbox.__sb = { texts: sbTexts, dates: sbDates, floats: floatCases };

const rendered = vm.runInContext(`(() => {
  const out = { keyOf: [], stats: {}, periods: {}, float: [] };
  for (const d of __sb.dates) {
    out.keyOf.push({ date: d, day: keyOf(d, 'day'), week: keyOf(d, 'week'),
                     month: keyOf(d, 'month'), year: keyOf(d, 'year') });
  }
  for (const name of Object.keys(__sb.texts)) {
    analyze(parse(__sb.texts[name]));
    out.stats[name] = ($('#stats') || {}).innerHTML || '';
    out.periods[name] = {};
    for (const p of ['day', 'week', 'month', 'year']) {
      PER = p;
      renderGame(LG[0], LG[1]);
      out.periods[name][p] = ($('#earnTbl') || {}).innerHTML || '';
    }
  }
  PER = 'day';
  for (const c of __sb.floats) {
    LOGACC = c.rate;
    S.target = c.target;
    renderFloat();
    out.float.push({ rate: c.rate ?? null, target: c.target, html: ($('#float') || {}).innerHTML || '' });
  }
  LOGACC = null;
  S.target = 85;
  return out;
})()`, sandbox);

function parseStats(html) {
  const out = [];
  const re = /<div class="num[^"]*">([^<]*)<\/div><span>([^<]*)<\/span>/g;
  let match;
  while ((match = re.exec(html)) !== null) out.push([match[2], match[1]]);
  return out;
}

function parsePeriodTable(html) {
  const out = [];
  const re = /<tr><td>([^<]*)<\/td><td>([^<]*)<\/td><td>([^<]*)<\/td><td>([^<]*)<\/td><td>([^<]*)<\/td><\/tr>/g;
  let match;
  while ((match = re.exec(html)) !== null) {
    out.push([match[1], match[2], match[3], Number(match[4]), match[5]]);
  }
  return out;
}

function parseFloatPanel(html) {
  const pick = (label) => {
    const re = new RegExp(`<div class="num[^"]*">([^<]*)<\\/div><span>${label}</span>`);
    const match = re.exec(html);
    return match ? match[1] : null;
  };
  const msg = /<p class="hint" style="font-size:14px;color:var\(--tx\)">([^<]*)<\/p>/.exec(html);
  const message = msg ? msg[1] : '';
  const left = Number(pick('Declines left'));
  const state = message.startsWith('NO FLOAT')
    ? (left < 0 ? 'past' : 'none')
    : message.startsWith('LOW.') ? 'low' : 'ok';
  return {
    declined: Number(pick('Declined, last 100')),
    left,
    // The tile shows the target after the `|| 85` fallback, so it is recorded
    // separately from the target that was passed in.
    targetUsed: Number(String(pick('Target')).replace('%', '')),
    state,
    message
  };
}

result.keyOf = rendered.keyOf;
result.scoreboard = {};
for (const name of Object.keys(rendered.stats)) result.scoreboard[name] = parseStats(rendered.stats[name]);
result.periods = {};
for (const name of Object.keys(rendered.periods)) {
  result.periods[name] = {};
  for (const period of Object.keys(rendered.periods[name])) {
    result.periods[name][period] = parsePeriodTable(rendered.periods[name][period]);
  }
}
result.float = rendered.float.map((c) => Object.assign({ rate: c.rate, target: c.target }, parseFloatPanel(c.html)));

function diff(expected, actual, path = '', out = []) {
  if (out.length >= 60) return out;
  const bothArrays = Array.isArray(expected) && Array.isArray(actual);
  const bothObjects = expected !== null && actual !== null &&
                      typeof expected === 'object' && typeof actual === 'object';
  if (bothArrays) {
    if (expected.length !== actual.length) {
      out.push({ path, note: `array length ${expected.length} -> ${actual.length}` });
    }
    for (let i = 0; i < Math.min(expected.length, actual.length); i += 1) {
      diff(expected[i], actual[i], `${path}[${i}]`, out);
    }
  } else if (bothObjects && !bothArrays) {
    for (const key of new Set([...Object.keys(expected), ...Object.keys(actual)])) {
      diff(expected[key], actual[key], path ? `${path}.${key}` : key, out);
    }
  } else if (!Object.is(expected, actual)) {
    out.push({ path, note: `${JSON.stringify(expected)} -> ${JSON.stringify(actual)}` });
  }
  return out;
}

if (MODE === 'update') {
  fs.writeFileSync(EXPECTATIONS, JSON.stringify(result, null, 2));
  console.log(`updated ${EXPECTATIONS}`);
  console.log(`  verdict cases: ${result.verdict.length}, fixtures: ${Object.keys(result.master).length}`);
  console.log(`  scoreboard: ${Object.keys(result.scoreboard).length}, float cases: ${result.float.length}`);
  process.exit(0);
}

if (!fs.existsSync(EXPECTATIONS)) {
  console.error(`missing ${EXPECTATIONS}; run with --update once and review the diff`);
  process.exit(1);
}

const captured = JSON.parse(fs.readFileSync(EXPECTATIONS, 'utf8'));
const differences = diff(captured, result);

if (differences.length === 0) {
  console.log('oracle: no drift against the captured web expectations');
  console.log(`  verdict cases: ${result.verdict.length}, fixtures: ${Object.keys(result.master).length}`);
  process.exit(0);
}

console.error(`oracle: WEB BEHAVIOUR DRIFTED from ${EXPECTATIONS}`);
for (const d of differences.slice(0, 20)) {
  console.error(`  ${d.path}: ${d.note}`);
}
if (differences.length > 20) console.error(`  ... ${differences.length - 20} more difference(s)`);
console.error('For an approved change, run --update and review the expectations diff with the native tests.');
process.exit(1);
