import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DEF, defaultSettings, mergeStoredSettings, readSettingsForm, zoneGasText, monthlyText,
  num, money,
  parseLog, splitLog, joinLog, ingestText, addPipeRow, checkColumns, PIPE_HEADER, CSV_HEADER,
  adjust, verdict, ramp, analyze, replay,
  csvRows, parseDeliveries, archiveLogLines, mergeArchiveIntoLog, pacificStamp, archStats,
  parseStatement, earnStats, applyStatements,
  keyOf, gameStats, caWeek, caProject, floatInfo, startInfo,
} from "../src/core/index.ts";

const S = () => defaultSettings();
const close = (a: number, b: number, eps = 1e-9) => assert.ok(Math.abs(a - b) < eps, `${a} vs ${b}`);

test("num and money match the web helpers", () => {
  assert.equal(num("$1,234.50"), 1234.5);
  assert.equal(num("abc"), 0);
  assert.equal(num(undefined), 0);
  assert.equal(money(12.345), "$12.35");
  assert.equal(money(-3.2), "$-3.20");
  assert.equal(money(7, 0), "$7");
});

test("verdict: take a good offer, skip a bad one", () => {
  const good = verdict({ payout: "10.70", miles: "5.5", items: "1", minutes: "22" }, S(), 89);
  const per = 5.75 / 17.5 + 0.12;
  close(good.net, 10.7 - 5.5 * per);
  close(good.reqM, 1.5 - 0.2 * 0.75);
  close(good.reqH, 18 - 0.2 * 8);
  assert.equal(good.ok, true);
  const bad = verdict({ payout: "4", miles: "6", items: "1", minutes: "30" }, S(), 89);
  assert.equal(bad.ok, false);
});

test("verdict: emergency rate takes any profitable offer, big orders use big bars", () => {
  const cheap = { payout: "5", miles: "3", items: "1", minutes: "40" };
  assert.equal(verdict(cheap, S(), 89).ok, false);
  assert.equal(verdict(cheap, S(), 70).ok, true);
  const big = verdict({ payout: "12", miles: "5", items: "5", minutes: "30" }, S(), 95);
  close(big.reqM, 2); close(big.reqH, 20);
});

test("verdict: zone gas price changes net, minutes fall back to the shortcut formula", () => {
  const P = { ...S(), zoneGas: { Vista: 8 } };
  const a = verdict({ zone: "Vista", payout: "10", miles: "5", items: "2" }, P, 89);
  const b = verdict({ zone: "Other", payout: "10", miles: "5", items: "2" }, P, 89);
  assert.ok(a.net < b.net);
  close(a.mn, 10 + 5 * 2.5 + 2 * 2);
});

test("ramp clamps between 0 and 1", () => {
  assert.equal(ramp(S(), 95), 0);
  assert.equal(ramp(S(), 80), 1);
  close(ramp(S(), 87.5), 0.5);
});

test("parseLog: CSV with header", () => {
  const rows = parseLog(CSV_HEADER + "\n2026-10-24,12:40,Vista,10.70,5.5,1,22,Accept,Accepted\n");
  assert.equal(rows.length, 1);
  assert.equal(rows[0].zone, "Vista");
  assert.equal(rows[0].choice, "Accepted");
  assert.deepEqual(parseLog("only a header"), []);
  assert.deepEqual(parseLog(""), []);
});

test("parseLog: shortcut pipe rows, minutes derived from net / hourly", () => {
  const row = "| 2026-10-27 12:40 | 12.50 | 4.2 | 3 | 2.98 | 9.10 | 21.40 | TAKE IT | 89 | Accept | 25 |";
  const [r] = parseLog(PIPE_HEADER + "\n" + row);
  assert.equal(r.date, "2026-10-27");
  assert.equal(r.time, "12:40");
  assert.equal(r.verdict, "TAKE IT");
  assert.equal(r.rate, "89");
  assert.equal(r.minutes, String(+((9.1 / 21.4) * 60).toFixed(1)));
  // a leading row number column is dropped
  const [r2] = parseLog("| 7 | 2026-10-27 | 12.50 | 4.2 | 3 | 2.98 | 9.10 | 21.40 | TAKE IT | 89 | Accept |");
  assert.equal(r2.date, "2026-10-27");
  assert.equal(r2.payout, "12.50");
});

test("parseLog handles a CSV block and pipe rows in one log", () => {
  const text = [
    PIPE_HEADER,
    "| 2026-10-27 12:40 | 12.50 | 4.2 | 3 | 2.98 | 9.10 | 21.40 | TAKE IT | 89 | Accept | 25 |",
    "date,time,zone,payout,miles,items,minutes,verdict,choice,src",
    "2026-10-01,12:00,Temecula,7.00,3.0,1,10,,Accepted,archive",
  ].join("\n");
  const rows = parseLog(text);
  assert.equal(rows.length, 2);
  assert.equal(rows.filter((r) => r.src === "archive").length, 1);
  assert.equal(splitLog(text).pipe.length, 1);
  assert.equal(joinLog(splitLog(text)), text);
});

test("yes/took classification through analyze", () => {
  const a = analyze(parseLog(CSV_HEADER + "\n2026-10-24,12:40,,10,5,1,20,Accept,Accepted\n2026-10-24,13:40,,3,5,1,20,Decline,Declined\n2026-10-24,14:40,,9,5,1,20,Accept,Declined"), S());
  assert.equal(a.nl, 3);
  assert.equal(a.followPct, 67);
  assert.equal(a.matrix[0].count, 1);
  assert.equal(a.matrix[1].count, 1);
  assert.equal(a.matrix[3].count, 1);
});

test("analyze: empty log", () => {
  const a = analyze([], S());
  assert.equal(a.n, 0);
  assert.equal(a.followPct, null);
  assert.deepEqual(a.stats, []);
  assert.equal(a.level.name, "Rookie");
});

test("analyze: stats, tax, hours, months, zones", () => {
  const csv = [
    CSV_HEADER,
    "2026-10-24,12:40,Vista,10.00,5,1,30,Accept,Accepted",
    "2026-10-24,13:10,Vista,8.00,4,2,30,Accept,Accepted",
    "2026-09-02,18:00,Carlsbad,6.00,3,1,20,Accept,Declined",
  ].join("\n");
  const P = S();
  const a = analyze(parseLog(csv), P);
  const per = P.gas / P.mpg + P.wear;
  const net = 18 - 9 * per;
  assert.equal(a.stats[1].value, "$18");
  close(a.tax.miles, 9);
  close(a.tax.deduction, 9 * P.taxRate);
  assert.equal(a.stats[2].value, money(net, 0));
  assert.equal(a.stats[3].value, money(net / 1));
  assert.deepEqual(a.zones.map((z) => z.zone), ["Vista"]);
  assert.deepEqual(a.hours.map((h) => h.label), ["12pm", "1pm"]);
  assert.equal(a.months.length, 1);
  assert.equal(a.months[0].month, "2026-10");
  assert.equal(a.level.name, "Rookie");
});

test("analyze: pipe rows use the logged net instead of recomputing", () => {
  const a = analyze(parseLog(PIPE_HEADER + "\n| 2026-10-27 12:40 | 12.50 | 4.2 | 3 | 2.98 | 9.10 | 21.40 | TAKE IT | 89 | Accept | 25 |"), S());
  assert.equal(a.R[0].net, 9.1);
});

test("checkColumns reports missing and bad columns", () => {
  const rows = parseLog(CSV_HEADER + "\n2026-10-24,12:40,,10.5,5.5,1,x,Accept,Accepted");
  const c = checkColumns(rows);
  assert.equal(c.find((x) => x.column === "payout")!.type, "float");
  assert.equal(c.find((x) => x.column === "items")!.type, "whole numbers");
  assert.equal(c.find((x) => x.column === "minutes")!.ok, false);
  assert.equal(checkColumns(parseLog("a,b\n1,2"))[0].type, "column missing");
});

test("ingestText: adds new rows only, adds a header when missing", () => {
  const first = ingestText("2026-10-24,12:40,Vista,10.70,5.5,1,22,Accept,Accepted", "");
  assert.equal(first.kind, "rows");
  if (first.kind !== "rows") return;
  assert.equal(first.added, 1);
  assert.ok(first.csv.startsWith(CSV_HEADER));
  const again = ingestText("2026-10-24,12:40,Vista,10.70,5.5,1,22,Accept,Accepted\n2026-10-25,12:40,Vista,9,5,1,22,Accept,Accepted", first.csv);
  assert.equal(again.kind === "rows" && again.added, 1);
  assert.equal(ingestText("nothing useful", "").kind, "bad");
});

test("ingestText: handoff JSON, and pasted pipe rows work with no header", () => {
  const h = ingestText(JSON.stringify({ app: "Hustle HQ", settings: { gas: 6 }, csv: "x" }), "");
  assert.equal(h.kind, "handoff");
  const p = ingestText("| 2026-10-27 12:40 | 12.50 | 4.2 | 3 | 2.98 | 9.10 | 21.40 | TAKE IT | 89 | Accept | 25 |", "");
  assert.equal(p.kind === "rows" && p.added, 1);
  assert.equal(parseLog(p.kind === "rows" ? p.csv : "").length, 1);
});

test("addPipeRow: adds, then reports duplicates", () => {
  const row = "| 2026-10-27 12:40 | 12.50 | 4.2 | 3 | 2.98 | 9.10 | 21.40 | TAKE IT | 89 | Accept | 25 |";
  const r1 = addPipeRow(row, "");
  assert.equal(r1.status, "added");
  if (r1.status !== "added") return;
  assert.equal(addPipeRow(row, r1.csv).status, "dup");
  assert.equal(addPipeRow("not a row", "").status, "bad");
});

test("adjust spreads a statement total across archive rows to the cent", () => {
  const P = { ...S(), monthly: { "2026-10": [100.01, 30] as [number, number] } };
  const rows = parseLog([
    CSV_HEADER + ",src",
    "2026-10-01,12:00,,7.00,3.0,1,10,,Accepted,archive",
    "2026-10-02,12:00,,7.00,3.0,1,20,,Accepted,archive",
    "2026-10-03,12:00,,7.00,3.0,1,33,,Accepted,archive",
    "2026-11-03,12:00,,7.00,3.0,1,33,,Accepted,archive",
  ].join("\n"));
  const out = adjust(rows, P);
  const oct = out.filter((r) => (r.date || "").startsWith("2026-10"));
  const total = oct.reduce((a, r) => a + Math.round(num(r.payout) * 100), 0);
  assert.equal(total, 10001);
  close(oct.reduce((a, r) => a + num(r.miles), 0), 30, 0.2);
  assert.equal(out[3].payout, "7.00"); // no statement for November: left as estimate
});

test("replay: a looser bar flips verdicts and reports the net change", () => {
  const rows = parseLog(CSV_HEADER + "\n2026-10-24,12:40,,6,5,1,30,Decline,Declined\n2026-10-24,13:40,,15,5,1,20,Accept,Accepted");
  const D = { ...S(), baseMile: 1, baseHour: 8, floorMile: 0.5, floorHour: 5 };
  const r = replay(rows, S(), D);
  assert.equal(r.flippedCount, 1);
  assert.equal(r.flipped[0].then, true);
  assert.equal(r.change.n, r.current.n + 1);
  assert.ok(r.delta > 0);
});

test("csvRows: quotes, doubled quotes, CRLF", () => {
  assert.deepEqual(csvRows('a,"b,c","d ""x"""\r\n1,2,3\r\n'), [["a", "b,c", 'd "x"'], ["1", "2", "3"]]);
});

test("pacificStamp matches Intl across DST edges for several years", () => {
  const F = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Los_Angeles", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
  let checked = 0;
  for (let y = 2022; y <= 2030; y++) {
    for (const [m, d] of [[3, 1], [3, 8], [3, 15], [10, 25], [11, 1], [11, 8], [1, 1], [7, 4], [12, 31]]) {
      for (let h = 0; h < 24; h += 1) {
        for (const mi of [0, 30]) {
          const ms = Date.UTC(y, m - 1, d, h, mi);
          const q: Record<string, string> = {};
          F.formatToParts(new Date(ms)).forEach((x) => (q[x.type] = x.value));
          const want = { date: q.year + "-" + q.month + "-" + q.day, time: q.hour + ":" + q.minute };
          assert.deepEqual(pacificStamp(ms), want, new Date(ms).toISOString());
          checked++;
        }
      }
    }
  }
  assert.ok(checked > 3000);
});

const DELIV = [
  "ORDER_CREATED_TIME,ACTUAL_PICKUP_TIME,ACTUAL_DELIVERY_TIME,STORE_NAME,TOTAL_ITEM_COUNT,ORDER_STATUS",
  '2026-10-02 19:00:00,2026-10-02 19:10:00,2026-10-02 19:30:00,"Chipotle (Temecula, CA)",3,DELIVERED',
  "2026-10-02 19:12:00,2026-10-02 19:20:00,2026-10-02 19:40:00,McDonalds Murrieta,2,DELIVERED",
  "2026-10-03 02:00:00,2026-10-03 02:10:00,2026-10-03 02:25:00,Corona Sushi,1,CANCELLED",
  "2026-10-05 03:00:00,2026-10-05 03:15:00,2026-10-05 03:35:00,Somewhere Else,0,DELIVERED",
].join("\n");

test("parseDeliveries drops cancelled orders and rejects other CSVs", () => {
  const r = parseDeliveries(DELIV);
  assert.ok(r.ok);
  if (!r.ok) return;
  assert.equal(r.arch.length, 3);
  assert.deepEqual(r.arch[0], ["2026-10-02T19:00", "2026-10-02T19:10", "2026-10-02T19:30", "Chipotle (Temecula, CA)", 3]);
  assert.equal(parseDeliveries("a,b\n1,2").ok, false);
});

test("archive -> log lines: Pacific time, zone from store, stacked orders share time", () => {
  const r = parseDeliveries(DELIV);
  if (!r.ok) throw new Error("parse");
  const lines = archiveLogLines(r.arch, S());
  assert.equal(lines.length, 3);
  // 19:10 UTC on Oct 2 is 12:10 PDT
  assert.ok(lines[0].startsWith("2026-10-02,12:10,Temecula,7.00,"));
  assert.ok(lines[1].startsWith("2026-10-02,12:20,Murrieta,"));
  // first window 19:02-19:30, second 19:12-19:40 overlap: combined 19:02-19:40 = 38 min, shared 19 each
  assert.equal(lines[0].split(",")[6], "19");
  assert.equal(lines[1].split(",")[6], "19");
  // 03:15 UTC on Oct 5 is 20:15 PDT on Oct 4
  assert.ok(lines[2].startsWith("2026-10-04,20:15,,"));
  assert.equal(lines[2].split(",")[5], "1"); // zero items falls back to 1
  assert.ok(lines.every((l) => l.endsWith(",Accepted,archive")));
});

test("mergeArchiveIntoLog keeps real rows, replaces old archive rows, keeps pipe rows", () => {
  const r = parseDeliveries(DELIV);
  if (!r.ok) throw new Error("parse");
  const pipe = "| 2026-10-27 12:40 | 12.50 | 4.2 | 3 | 2.98 | 9.10 | 21.40 | TAKE IT | 89 | Accept | 25 |";
  const base = [PIPE_HEADER, pipe, CSV_HEADER, "2026-10-24,12:40,Vista,10.70,5.5,1,22,Accept,Accepted", "2020-01-01,10:00,,7.00,3.0,1,10,,Accepted,archive"].join("\n");
  const out = mergeArchiveIntoLog(r.arch, S(), base);
  const parts = splitLog(out);
  assert.equal(parts.pipe.length, 1);
  assert.equal(parts.csv.filter((l) => l.endsWith(",archive")).length, 3);
  assert.ok(!out.includes("2020-01-01"));
  assert.ok(out.includes("Vista"));
  // running it twice changes nothing
  assert.equal(mergeArchiveIntoLog(r.arch, S(), out), out);
  assert.equal(parseLog(out).length, 1 + 1 + 3);
});

test("archStats: totals and tiles", () => {
  const r = parseDeliveries(DELIV);
  if (!r.ok) throw new Error("parse");
  const s = archStats(r.arch)!;
  assert.equal(s.total, 3);
  assert.equal(s.tiles[0].value, "3");
  assert.equal(s.stores[0].store.length > 0, true);
  assert.equal(archStats([]), null);
});

test("parseStatement and earnStats", () => {
  const t = "DoorDash October 2026 Statement ... Total Payouts $1,234.56 ... Payouts (14)";
  assert.deepEqual(parseStatement(t), { k: "2026-10", total: 1234.56, n: 14 });
  assert.equal(parseStatement("nothing here"), null);
  const rows = parseLog([CSV_HEADER + ",src", ...Array.from({ length: 31 }, (_, i) => `2026-10-${String((i % 28) + 1).padStart(2, "0")},12:00,,7.00,3.0,1,10,,Accepted,archive`)].join("\n"));
  const e = earnStats({ "2026-10": { k: "2026-10", total: 1234.56, n: 14 } }, rows)!;
  assert.equal(e.tiles[0].value, "$1235");
  assert.equal(e.table[0][3], "31");
  assert.equal(earnStats({}, rows), null);
  assert.deepEqual(applyStatements({ "2026-10": [1, 55] }, { "2026-10": { k: "2026-10", total: 9, n: 1 } }), { "2026-10": [9, 55] });
});

test("keyOf: week starts Monday", () => {
  assert.equal(keyOf("2026-10-25", "week"), "2026-10-19"); // Sunday
  assert.equal(keyOf("2026-10-26", "week"), "2026-10-26"); // Monday
  assert.equal(keyOf("2026-10-27", "month"), "2026-10");
  assert.equal(keyOf("2026-10-27", "year"), "2026");
});

test("gameStats, caWeek and caProject on a small week", () => {
  const csv = [
    CSV_HEADER,
    "2026-10-26,12:00,,10,4,1,30,Accept,Accepted",
    "2026-10-26,13:00,,12,5,1,30,Accept,Accepted",
    "2026-10-27,12:00,,3,6,1,30,Accept,Declined",
  ].join("\n");
  const P = S();
  const a = analyze(parseLog(csv), P);
  const now = new Date("2026-10-27T15:00:00");
  const g = gameStats(a.R, a.RL, "week", now);
  assert.equal(g.label, "This week");
  assert.equal(g.big[2].value, "2");
  assert.equal(g.streak.current, 0); // last offer went against the verdict
  assert.equal(g.streak.best, 2);
  const ca = caWeek(a.R, P, now);
  assert.ok(ca.ok);
  close(ca.hours, 1);
  close(ca.miles, 9);
  close(ca.guaranteed, 1.2 * 16.9 * 1 + 0.37 * 9);
  close(ca.adjustment, Math.max(0, ca.guaranteed - 22));
  const proj = caProject(ca, P, 10);
  close(proj.pay, 220);
  assert.equal(caWeek([], P, now).ok, false);
});

test("floatInfo wording and thresholds", () => {
  assert.equal(floatInfo({ ...S(), accept: 89 }).left, 4);
  assert.equal(floatInfo({ ...S(), accept: 89 }).level, "good");
  assert.equal(floatInfo({ ...S(), accept: 87 }).level, "low");
  assert.match(floatInfo({ ...S(), accept: 85 }).message, /^NO FLOAT. Your next decline/);
  assert.match(floatInfo({ ...S(), accept: 80 }).message, /5 declines past your 85% target/);
});

test("startInfo reports exact vs estimated months", () => {
  const a = analyze(parseLog([CSV_HEADER + ",src", "2026-08-01,12:00,,7,3,1,10,,Accepted,archive", "2026-09-01,12:00,,7,3,1,10,,Accepted,archive", "2026-10-01,12:00,,7,3,1,10,,Accepted,archive"].join("\n")), S());
  const s = startInfo(a.R, 3, ["2026-09"], S());
  assert.deepEqual(s.exact, ["2026-09"]);
  assert.deepEqual(s.estimated, ["2026-10"]);
  assert.equal(s.done, false);
});

test("settings: merge, form round-trip", () => {
  const m = mergeStoredSettings({ gas: "6.25", mpg: 20, accSet: 1, bogus: 1, wear: null, monthly: { "2026-10": [100, 20] }, zoneGas: { Vista: 6 } });
  assert.equal(m.gas, 6.25);
  assert.equal(m.mpg, 20);
  assert.equal(m.wear, DEF.wear);
  assert.equal(m.accSet, 1);
  assert.deepEqual(mergeStoredSettings(null).monthly, {});
  assert.equal(mergeStoredSettings({ gas: 0 }).gas, DEF.gas);
  const f = readSettingsForm(m, { mpg: "21", gas: "$6.00" }, zoneGasText(m) + "\nCarlsbad=5.5\nbad=0", monthlyText(m) + "\n2026-11=50\nbad=3");
  assert.equal(f.mpg, 21);
  assert.equal(f.gas, 6);
  assert.deepEqual(f.zoneGas, { Vista: 6, Carlsbad: 5.5 });
  assert.deepEqual(f.monthly, { "2026-10": [100, 20], "2026-11": [50, 0] });
  assert.equal(f.accSet, 1);
});
