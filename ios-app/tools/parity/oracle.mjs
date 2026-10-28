// Read-only parity oracle: executes index.html's own functions in a stubbed
// DOM so native expectations are observed behaviour, not transcription.
// Reads index.html, writes nothing to it.
import fs from 'node:fs';
import vm from 'node:vm';

process.on('unhandledRejection', () => {});

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

fs.writeFileSync('ios-app/tools/parity/expectations.json', JSON.stringify(result, null, 2));
console.log(JSON.stringify({
  header: result.header,
  num: result.num, f: result.f,
  yes: Object.fromEntries(payload.words.map((w, i) => [w, result.yes[i]])),
  took: Object.fromEntries(payload.words.map((w, i) => [w, result.took[i]])),
  ramp: result.ramp,
  verdict: result.verdict.map(v => ({ id: v.id, ok: v.ok, mn: v.mn, netF: v.netF, hrF: v.hrF, pmF: v.pmF, reqMF: v.reqMF, reqHF: v.reqHF })),
  rows: result.rows,
  parsed: Object.fromEntries(Object.entries(result.parsed).map(([k, v]) => [k, v.map(r => [r.date, r.time, r.minutes, r.src, r.zone])])),
  pipe: result.pipe,
  arch: result.arch,
  accept: result.accept,
  mergedRows: Object.fromEntries(Object.entries(result.merged).map(([k, v]) => [k, Math.max(0, v.split('\n').length - 2)]))
}, null, 2));
