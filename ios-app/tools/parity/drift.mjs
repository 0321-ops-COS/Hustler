// Cross-checks the native Swift tests against the captured web expectations.
//
// The oracle (--check) proves index.html still behaves like expectations.json.
// This script proves the scanning Swift test cases still assert those values,
// so a web change cannot leave a stale green native suite.
//
// Verified here:
//   - every VerdictCase row, field by field, plus the exact id set;
//   - every money format string in the oracle is asserted in MoneyTests;
//   - acceptance assertions are mapped back to the oracle fixture they came from.
// Not verified here: the hand-maintained fixture text in Fixtures.swift versus
// the copy inside oracle.mjs, and assertions this parser does not recognise.
// `swift test` remains the authority for value equality.

import fs from 'node:fs';

const EXPECTATIONS = 'ios-app/tools/parity/expectations.json';
const TESTS = 'ios-app/HustlerCore/Tests/HustlerCoreTests';
const VERDICT_TESTS = `${TESTS}/VerdictParityTests.swift`;
const MONEY_TESTS = `${TESTS}/MoneyTests.swift`;
const ACCEPTANCE_TESTS = `${TESTS}/AcceptanceLogicTests.swift`;

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
