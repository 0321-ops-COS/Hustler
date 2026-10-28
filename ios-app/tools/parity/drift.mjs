// Cross-checks the native Swift tests against the captured web expectations.
//
// The oracle (--check) proves index.html still behaves like expectations.json.
// This script proves the scanning Swift test cases still assert those values,
// so a web change cannot leave a stale green native suite.
//
// Verified here:
//   - every VerdictCase row, field by field, plus the exact id set;
//   - every money format string in the oracle is asserted in MoneyTests;
//   - acceptance assertions are mapped back to the oracle fixture they came from;
//   - every PeriodCase, StatCase, PeriodTotalsCase and FloatCase in the M2 tests.
// Not verified here: the hand-maintained fixture text in Fixtures.swift versus
// the copy inside oracle.mjs, and assertions this parser does not recognise.
// `swift test` remains the authority for value equality.

import fs from 'node:fs';

const EXPECTATIONS = 'ios-app/tools/parity/expectations.json';
const TESTS = 'ios-app/HustlerCore/Tests/HustlerCoreTests';
const VERDICT_TESTS = `${TESTS}/VerdictParityTests.swift`;
const MONEY_TESTS = `${TESTS}/MoneyTests.swift`;
const ACCEPTANCE_TESTS = `${TESTS}/AcceptanceLogicTests.swift`;
const PERIOD_TESTS = `${TESTS}/PeriodGroupingTests.swift`;
const SCOREBOARD_TESTS = `${TESTS}/ScoreboardTests.swift`;
const FLOAT_TESTS = `${TESTS}/DeclineFloatTests.swift`;

// `renderGame` always inserts the current period even when it has no rows, so a
// placeholder bucket can appear with zero takings. Those have no native
// equivalent and are skipped below; a real bucket is only created by an
// accepted row, so `taken === 0` identifies a placeholder exactly.

const failures = [];
const notes = [];

function read(path) {
  if (!fs.existsSync(path)) {
    console.error(`missing ${path} (run this from the repository root)`);
    process.exit(2);
  }
  return fs.readFileSync(path, 'utf8');
}

const expectations = JSON.parse(read(EXPECTATIONS));
const verdictSource = read(VERDICT_TESTS);
const moneySource = read(MONEY_TESTS);
const acceptanceSource = read(ACCEPTANCE_TESTS);
const periodSource = read(PERIOD_TESTS);
const scoreboardSource = read(SCOREBOARD_TESTS);
const floatSource = read(FLOAT_TESTS);

// ---- 1. Verdict table: strict field comparison ------------------------------
const casePattern = new RegExp(
  'VerdictCase\\(\\s*id:\\s*"([^"]+)",\\s*' +
  'payout:\\s*(-?[\\d.]+),\\s*miles:\\s*(-?[\\d.]+),\\s*items:\\s*(-?[\\d.]+),\\s*' +
  'minutes:\\s*(-?[\\d.]+),\\s*zone:\\s*"([^"]*)",\\s*rate:\\s*(-?[\\d.]+),\\s*' +
  'zoneGas:\\s*\\[[^\\]]*\\],\\s*takeIt:\\s*(true|false),\\s*minutesOut:\\s*(-?[\\d.]+),\\s*' +
  'net:\\s*"([^"]+)",\\s*hourly:\\s*"([^"]+)",\\s*perMile:\\s*"([^"]+)",\\s*' +
  'requiredMile:\\s*"([^"]+)",\\s*requiredHour:\\s*"([^"]+)"\\s*\\)',
  'g'
);

const swiftCases = new Map();
for (const match of verdictSource.matchAll(casePattern)) {
  swiftCases.set(match[1], {
    takeIt: match[8] === 'true',
    minutesOut: Number(match[9]),
    net: match[10],
    hourly: match[11],
    perMile: match[12],
    requiredMile: match[13],
    requiredHour: match[14]
  });
}

const expectedCases = new Map(expectations.verdict.map((v) => [v.id, v]));

for (const id of expectedCases.keys()) {
  if (!swiftCases.has(id)) {
    failures.push(`verdict "${id}" is in expectations.json but no VerdictCase asserts it`);
  }
}
for (const id of swiftCases.keys()) {
  if (!expectedCases.has(id)) {
    failures.push(`verdict "${id}" is asserted in Swift but absent from expectations.json`);
  }
}

for (const [id, expected] of expectedCases) {
  const actual = swiftCases.get(id);
  if (!actual) continue;
  const pairs = [
    ['takeIt', actual.takeIt, expected.ok],
    ['minutesOut', actual.minutesOut, expected.mn],
    ['net', actual.net, expected.netF],
    ['hourly', actual.hourly, expected.hrF],
    ['perMile', actual.perMile, expected.pmF],
    ['requiredMile', actual.requiredMile, expected.reqMF],
    ['requiredHour', actual.requiredHour, expected.reqHF]
  ];
  for (const [field, asserted, oracle] of pairs) {
    if (asserted !== oracle) {
      failures.push(`verdict "${id}".${field}: Swift asserts ${JSON.stringify(asserted)}, oracle says ${JSON.stringify(oracle)}`);
    }
  }
}
notes.push(`verdict table: ${swiftCases.size} asserted cases vs ${expectedCases.size} oracle cases`);

// ---- 2. Money: every oracle format string must be asserted ------------------
const moneyValues = expectations.f;
const missingMoney = moneyValues.filter((value) => !moneySource.includes(`"${value}"`));
for (const value of missingMoney) {
  failures.push(`money expectation ${JSON.stringify(value)} is not asserted in MoneyTests.swift`);
}
notes.push(`money: ${moneyValues.length - missingMoney.length}/${moneyValues.length} oracle strings asserted`);

// ---- 3. Acceptance: match assertions back to their oracle fixture -----------
const snake = (name) => name.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();

const variableToFixture = new Map();
for (const match of acceptanceSource.matchAll(/let\s+(\w+)\s*=\s*[^\n]*?Fixtures\.(\w+)/g)) {
  variableToFixture.set(match[1], snake(match[2]));
}

const acceptanceChecks = [];
for (const match of acceptanceSource.matchAll(
  /AcceptanceLogic\.(logRate|newestLoggedRate)\(\s*(\w+)\s*\)\s*,\s*([\d.]+)\s*\)/g
)) {
  const [, kind, variable, literal] = match;
  const fixture = variableToFixture.get(variable);
  if (!fixture) continue;
  acceptanceChecks.push({ kind, fixture, literal: Number(literal) });
}

for (const check of acceptanceChecks) {
  const record = expectations.accept[check.fixture];
  if (!record) {
    failures.push(`acceptance assertion uses fixture "${check.fixture}", which the oracle does not record`);
    continue;
  }
  const oracleValue = check.kind === 'logRate' ? record.LOGRATE : record.LOGACC;
  if (oracleValue === null || oracleValue === undefined) {
    failures.push(`acceptance "${check.fixture}".${check.kind} asserts ${check.literal} but the oracle recorded null`);
  } else if (Number(oracleValue) !== check.literal) {
    failures.push(`acceptance "${check.fixture}".${check.kind}: Swift asserts ${check.literal}, oracle says ${oracleValue}`);
  }
}
notes.push(`acceptance: ${acceptanceChecks.length} assertions resolved to oracle fixtures`);

// ---- 4. Period keys --------------------------------------------------------
const periodCases = new Map();
for (const match of periodSource.matchAll(
  /PeriodCase\(date: "([^"]*)", day: "([^"]*)", week: "([^"]*)", month: "([^"]*)", year: "([^"]*)"\)/g
)) {
  periodCases.set(match[1], { day: match[2], week: match[3], month: match[4], year: match[5] });
}

const expectedKeys = new Map(expectations.keyOf.map((k) => [k.date, k]));
for (const date of expectedKeys.keys()) {
  if (!periodCases.has(date)) failures.push(`period key "${date}" is in expectations.json but no PeriodCase asserts it`);
}
for (const date of periodCases.keys()) {
  if (!expectedKeys.has(date)) failures.push(`period key "${date}" is asserted in Swift but absent from expectations.json`);
}
for (const [date, expected] of expectedKeys) {
  const actual = periodCases.get(date);
  if (!actual) continue;
  for (const field of ['day', 'week', 'month', 'year']) {
    if (actual[field] !== expected[field]) {
      failures.push(`period "${date}".${field}: Swift asserts ${JSON.stringify(actual[field])}, oracle says ${JSON.stringify(expected[field])}`);
    }
  }
}
notes.push(`period keys: ${periodCases.size} asserted vs ${expectedKeys.size} oracle cases`);

// ---- 5. Scoreboard stat tiles ----------------------------------------------
const statCases = new Map();
for (const match of scoreboardSource.matchAll(
  /StatCase\(fixture: "(\w+)", label: "([^"]+)", value: "([^"]*)"\)/g
)) {
  if (!statCases.has(match[1])) statCases.set(match[1], new Map());
  statCases.get(match[1]).set(match[2], match[3]);
}

for (const [fixture, expected] of Object.entries(expectations.scoreboard)) {
  const actual = statCases.get(fixture);
  if (!actual) {
    failures.push(`scoreboard fixture "${fixture}" has oracle tiles but no StatCase asserts them`);
    continue;
  }
  for (const [label, value] of expected) {
    if (!actual.has(label)) {
      failures.push(`scoreboard "${fixture}" tile "${label}" (${value}) is not asserted`);
    } else if (actual.get(label) !== value) {
      failures.push(`scoreboard "${fixture}" tile "${label}": Swift asserts ${JSON.stringify(actual.get(label))}, oracle says ${JSON.stringify(value)}`);
    }
  }
  for (const label of actual.keys()) {
    if (!expected.some(([name]) => name === label)) {
      failures.push(`scoreboard "${fixture}" asserts tile "${label}", which the oracle does not produce`);
    }
  }
}
notes.push(`scoreboard: ${statCases.size} fixtures asserted`);

// ---- 6. Period totals ------------------------------------------------------
const totalCases = new Map();
for (const match of scoreboardSource.matchAll(
  /PeriodTotalsCase\(fixture: "(\w+)", period: "(\w+)", key: "([^"]*)", gross: "([^"]*)", net: "([^"]*)", taken: (\d+), netPerHour: "([^"]*)"\)/g
)) {
  const [, fixture, period, key, gross, net, taken, netPerHour] = match;
  if (!totalCases.has(fixture)) totalCases.set(fixture, new Map());
  if (!totalCases.get(fixture).has(period)) totalCases.get(fixture).set(period, new Map());
  totalCases.get(fixture).get(period).set(key, { gross, net, taken: Number(taken), netPerHour });
}

for (const [fixture, periods] of Object.entries(expectations.periods)) {
  for (const [period, rows] of Object.entries(periods)) {
    const asserted = (totalCases.get(fixture) || new Map()).get(period) || new Map();
    const expectedRows = rows.filter((row) => row[3] > 0);
    for (const [key, gross, net, taken, netPerHour] of expectedRows) {
      const actual = asserted.get(key);
      if (!actual) {
        failures.push(`period totals "${fixture}/${period}/${key}" is in expectations.json but not asserted`);
        continue;
      }
      if (actual.gross !== gross) failures.push(`period totals "${fixture}/${period}/${key}".gross: Swift ${JSON.stringify(actual.gross)}, oracle ${JSON.stringify(gross)}`);
      if (actual.net !== net) failures.push(`period totals "${fixture}/${period}/${key}".net: Swift ${JSON.stringify(actual.net)}, oracle ${JSON.stringify(net)}`);
      if (actual.taken !== taken) failures.push(`period totals "${fixture}/${period}/${key}".taken: Swift ${actual.taken}, oracle ${taken}`);
      if (actual.netPerHour !== netPerHour) failures.push(`period totals "${fixture}/${period}/${key}".netPerHour: Swift ${JSON.stringify(actual.netPerHour)}, oracle ${JSON.stringify(netPerHour)}`);
    }
    for (const key of asserted.keys()) {
      if (!expectedRows.some(([name]) => name === key)) {
        failures.push(`period totals "${fixture}/${period}" asserts key "${key}", which the oracle does not produce`);
      }
    }
  }
}
notes.push(`period totals: ${[...totalCases.values()].reduce((sum, m) => sum + [...m.values()].reduce((n, k) => n + k.size, 0), 0)} buckets asserted`);

// ---- 7. Decline float ------------------------------------------------------
const floatCases = new Map();
for (const match of floatSource.matchAll(
  /FloatCase\(rate: (nil|[\d.]+), target: ([\d.]+), declined: (\d+), left: (-?[\d.]+), state: "(\w+)", message: "([^"]*)"\)/g
)) {
  const [, rate, target, declined, left, state, message] = match;
  floatCases.set(`${rate}|${target}`, {
    declined: Number(declined), left: Number(left), state, message
  });
}

const expectedFloat = new Map(expectations.float.map((f) => [`${f.rate === null ? 'nil' : f.rate}|${f.target}`, f]));
for (const key of expectedFloat.keys()) {
  if (!floatCases.has(key)) failures.push(`float case rate|target "${key}" is in expectations.json but no FloatCase asserts it`);
}
for (const key of floatCases.keys()) {
  if (!expectedFloat.has(key)) failures.push(`float case "${key}" is asserted in Swift but absent from expectations.json`);
}
for (const [key, expected] of expectedFloat) {
  const actual = floatCases.get(key);
  if (!actual) continue;
  if (actual.declined !== expected.declined) failures.push(`float "${key}".declined: Swift ${actual.declined}, oracle ${expected.declined}`);
  if (actual.left !== expected.left) failures.push(`float "${key}".left: Swift ${actual.left}, oracle ${expected.left}`);
  if (actual.state !== expected.state) failures.push(`float "${key}".state: Swift ${JSON.stringify(actual.state)}, oracle ${JSON.stringify(expected.state)}`);
  if (actual.message !== expected.message) failures.push(`float "${key}".message: Swift ${JSON.stringify(actual.message)}, oracle ${JSON.stringify(expected.message)}`);
}
notes.push(`decline float: ${floatCases.size} cases asserted vs ${expectedFloat.size} oracle cases`);

// ---- Report ----------------------------------------------------------------
for (const note of notes) console.log(`  ok: ${note}`);

if (failures.length > 0) {
  console.error('\nnative tests drifted from the captured web expectations:');
  for (const failure of failures) console.error(`  - ${failure}`);
  console.error('\nFix the port, or — only for an approved behaviour change — update the oracle and the tests together.');
  process.exit(1);
}

console.log('native tests: in sync with expectations.json');
console.log('not covered here (proved by `swift test`): fixture text parity between oracle.mjs and Fixtures.swift');
