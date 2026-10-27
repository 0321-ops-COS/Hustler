// Log parsing, verdict rule, analysis and what-if replay.
// Ported from the web app; behaviour is intentionally identical.

import type { Settings } from "./settings.ts";
import { num, money, hourLabel, sum } from "./util.ts";

export interface LogRow {
  date?: string;
  time?: string;
  zone?: string;
  payout?: string;
  miles?: string;
  items?: string;
  minutes?: string;
  verdict?: string;
  choice?: string;
  src?: string;
  // pipe-table (shortcut) extras
  permile?: string;
  net?: string;
  hourly?: string;
  rate?: string;
  slack?: string;
  [k: string]: string | undefined;
}

/** Header the shortcut's pipe-table rows use. */
export const PIPE_HEADER =
  "| Date | Payout | Miles | Items | Per Mile | Net | Hourly | Verdict | Acceptance rate | Choice | Slack |\n|---|---|---|---|---|---|---|---|---|---|---|";

export const CSV_HEADER = "date,time,zone,payout,miles,items,minutes,verdict,choice";
export const CSV_HEADER_ARCHIVE = CSV_HEADER + ",src";

/** A log is stored as text. It may hold a CSV block (header + rows) and/or shortcut pipe-table rows. */
export interface LogParts {
  /** shortcut pipe rows, without the header and divider lines */
  pipe: string[];
  /** CSV header line ("" when there is none) */
  header: string;
  /** CSV data rows */
  csv: string[];
}

const pipeCells = (l: string): string[] => l.split("|").slice(1, -1).map((x) => x.trim());
const isPipeData = (c: string[]): boolean =>
  !!c[0] && !/^[-: ]+$/.test(c[0]) && c[0].toLowerCase() !== "date" && c[0] !== "#";

export function splitLog(text: string): LogParts {
  const parts: LogParts = { pipe: [], header: "", csv: [] };
  for (const raw of (text || "").split(/\r?\n/)) {
    const l = raw.trim();
    if (!l) continue;
    if (l.startsWith("|")) {
      if (isPipeData(pipeCells(l))) parts.pipe.push(l);
    } else if (!parts.header) parts.header = l;
    else parts.csv.push(l);
  }
  return parts;
}

export function joinLog(p: LogParts): string {
  return [
    ...(p.pipe.length ? [PIPE_HEADER, ...p.pipe] : []),
    ...(p.header ? [p.header, ...p.csv] : []),
  ].join("\n");
}

function parsePipeRow(c: string[]): LogRow {
  if (/^\d+$/.test(c[0]) && /^\d{4}-\d\d-\d\d/.test(c[1] || "")) c = c.slice(1);
  const dt = c[0].split(/\s+/);
  const m = num(c[2]), it = num(c[3]), net = num(c[5]), hr = num(c[6]);
  return {
    date: dt[0],
    time: dt[1] || "",
    zone: "",
    payout: c[1],
    miles: c[2],
    items: c[3],
    permile: c[4],
    net: c[5],
    hourly: c[6],
    verdict: c[7],
    rate: c[8],
    choice: c[9] || "",
    slack: c[10] || "",
    minutes: String(hr > 0 && net > 0 ? +((net / hr) * 60).toFixed(1) : +(10 + m * 2.5 + it * 2).toFixed(1)),
  };
}

/** Parse a CSV log (first row is the header), the shortcut's pipe table, or both together. */
export function parseLog(text: string): LogRow[] {
  const { pipe, header, csv } = splitLog(text);
  const out: LogRow[] = [];
  if (header && csv.length) {
    const H = header.split(",").map((h) => h.trim().toLowerCase());
    for (const l of csv) {
      const c = l.split(","), o: LogRow = {};
      H.forEach((h, i) => (o[h] = (c[i] || "").trim()));
      out.push(o);
    }
  }
  for (const l of pipe) out.push(parsePipeRow(pipeCells(l)));
  return out;
}

export type IngestResult =
  | { kind: "handoff"; settings?: Record<string, unknown>; csv?: string }
  | { kind: "rows"; csv: string; added: number }
  | { kind: "bad" };

/** Merge pasted or picked text into the saved log. New rows only; duplicates are skipped. */
export function ingestText(t: string, currentCsv: string): IngestResult {
  let j: any = null;
  try { j = JSON.parse(t); } catch { /* not JSON */ }
  if (j && typeof j === "object" && (j.settings || j.csv !== undefined)) {
    return { kind: "handoff", settings: j.settings, csv: j.csv };
  }
  const L = t.trim().split(/\r?\n/).filter(Boolean);
  if (L.length && /^\s*\d/.test(L[0])) L.unshift(CSV_HEADER);
  const incoming = splitLog(L.join("\n"));
  if (!incoming.csv.length && !incoming.pipe.length) return { kind: "bad" };
  const cur = splitLog(currentCsv);
  const haveCsv = new Set(cur.csv), havePipe = new Set(cur.pipe);
  const addCsv = incoming.csv.filter((x) => !haveCsv.has(x));
  const addPipe = incoming.pipe.filter((x) => !havePipe.has(x));
  const csvText = joinLog({
    pipe: [...cur.pipe, ...addPipe],
    header: cur.header || (incoming.csv.length ? incoming.header : ""),
    csv: [...cur.csv, ...addCsv],
  });
  return { kind: "rows", csv: csvText, added: addCsv.length + addPipe.length };
}

/** Add one shortcut row (already a pipe line). */
export function addPipeRow(
  line: string,
  currentCsv: string,
): { status: "added"; csv: string } | { status: "dup" | "bad" } {
  const l = line.trim();
  if (!l.startsWith("|") || !isPipeData(pipeCells(l))) return { status: "bad" };
  const cur = splitLog(currentCsv);
  if (cur.pipe.includes(l)) return { status: "dup" };
  return { status: "added", csv: joinLog({ ...cur, pipe: [...cur.pipe, l] }) };
}

export const yes = (v?: string): boolean =>
  /accept|take|yes|worth|good|go/i.test(v || "") && !/decline|pass|no\b/i.test(v || "");
export const took = (v?: string): boolean =>
  /accept/i.test(v || "") && !/declin/i.test(v || "");

/** Per-column sanity check shown under the log box. */
export interface ColumnCheck { column: string; type: string; check: string; ok: boolean }
export function checkColumns(d: LogRow[]): ColumnCheck[] {
  if (!d.length) return [];
  return (["payout", "miles", "items", "minutes"] as const).map((k) => {
    if (!(k in d[0])) return { column: k, type: "column missing", check: "", ok: false };
    let f = 0, w = 0;
    const bad: number[] = [];
    d.forEach((r, j) => {
      const v = String(r[k] || "").trim();
      if (/^\$?-?\d+\.\d+$/.test(v)) f++;
      else if (/^\$?-?\d+$/.test(v)) w++;
      else bad.push(j + 2);
    });
    const t = f && !w ? "float" : w && !f ? "whole numbers" : "mixed float and whole";
    return {
      column: k,
      type: f + w ? t : "no numbers",
      check: bad.length ? bad.length + " bad (rows " + bad.slice(0, 5).join(", ") + ")" : "all clean",
      ok: !bad.length,
    };
  });
}

/**
 * Archive rows carry estimated pay/miles. When a monthly statement total is known,
 * spread it over that month's archive rows by active minutes, to the cent.
 */
export function adjust(d: LogRow[], S: Settings): LogRow[] {
  const M = S.monthly || {};
  const sm: Record<string, number> = {};
  const ix: Record<string, number[]> = {};
  const pc: Record<number, number> = {};
  d.forEach((r, i) => {
    if (r.src === "archive") {
      const k = (r.date || "").slice(0, 7);
      sm[k] = (sm[k] || 0) + num(r.minutes);
      (ix[k] = ix[k] || []).push(i);
    }
  });
  Object.keys(ix).forEach((k) => {
    if (!M[k] || !sm[k]) return;
    const T = Math.round(M[k][0] * 100);
    const ex = ix[k].map((i) => (T * num(d[i].minutes)) / sm[k]);
    const fl = ex.map(Math.floor);
    const rem = T - fl.reduce((a, b) => a + b, 0);
    ex.map((v, j) => [v - fl[j], j] as [number, number])
      .sort((a, b) => b[0] - a[0])
      .slice(0, Math.max(0, rem))
      .forEach((x) => fl[x[1]]++);
    ix[k].forEach((i, j) => (pc[i] = fl[j] / 100));
  });
  return d.map((r, i) => {
    const k = (r.date || "").slice(0, 7);
    if (r.src !== "archive" || !M[k] || !sm[k] || pc[i] === undefined) return r;
    const f = num(r.minutes) / sm[k];
    const o: LogRow = { ...r };
    o.payout = pc[i].toFixed(2);
    if (M[k][1] > 0) o.miles = (M[k][1] * f).toFixed(1);
    return o;
  });
}

// ---------------------------------------------------------------- verdict

export const ramp = (P: Settings, rate: number): number =>
  Math.min(1, Math.max(0, (P.rampTop - rate) / (P.rampTop - P.rampLow)));

export interface Verdict {
  ok: boolean;
  net: number;
  h: number;
  mn: number;
  reqM: number;
  reqH: number;
  pm: number;
  hr: number;
}

export interface OfferInput {
  zone?: string;
  payout?: string | number;
  miles?: string | number;
  items?: string | number;
  minutes?: string | number;
}

export function verdict(r: OfferInput, P: Settings, rate: number): Verdict {
  const per = ((P.zoneGas && r.zone && P.zoneGas[r.zone]) || P.gas) / P.mpg + P.wear;
  const p = num(r.payout), m = num(r.miles), it = num(r.items);
  const mn = num(r.minutes) > 0 ? num(r.minutes) : 10 + m * 2.5 + it * 2;
  const h = mn / 60, net = p - m * per;
  const T = ramp(P, rate), big = it > P.bigItems;
  const mb = big ? P.bigMile : P.baseMile, hb = big ? P.bigHour : P.baseHour;
  const reqM = mb - T * (mb - P.floorMile), reqH = hb - T * (hb - P.floorHour);
  const pm = m ? p / m : p, hr = net / h;
  return {
    ok: (pm > reqM && hr > reqH) || (rate < P.emergency && net > 0),
    net, h, mn, reqM, reqH, pm, hr,
  };
}

// ---------------------------------------------------------------- analysis

export interface AnRow {
  date: string;
  time: string;
  zone: string;
  src: string;
  rate: string;
  p: number;
  m: number;
  min: number;
  net: number;
  /** the verdict said yes */
  v: boolean;
  /** the driver took it */
  t: boolean;
}

export interface Analysis {
  n: number;
  nl: number;
  R: AnRow[];
  RL: AnRow[];
  followPct: number | null;
  followText: string;
  estNote: string;
  stats: { label: string; value: string; money?: boolean }[];
  matrix: { label: string; good: boolean; count: number; hourly: string }[];
  zones: { zone: string; orders: number; hourly: string; perMile: string }[];
  hours: { label: string; orders: number; hourly: string }[];
  months: { month: string; orders: number; gross: number; miles: number; net: number; deduction: number }[];
  tax: { gross: number; miles: number; deduction: number; taxable: number };
  level: { name: string; offers: number; pct: number };
  logRate: number | null;
}

const LEVELS: [string, number][] = [["Rookie", 0], ["Grinder", 25], ["Operator", 100], ["Hustler", 300], ["Legend", 800]];

export function analyze(data: LogRow[], S: Settings): Analysis {
  const n = data.length;
  const gasOf = (r: LogRow) => (S.zoneGas && r.zone && S.zoneGas[r.zone]) || S.gas;
  const R: AnRow[] = data.map((r) => {
    const p = num(r.payout), m = num(r.miles), min = num(r.minutes);
    const net = "net" in r && r.net !== "" && r.net !== undefined ? num(r.net) : p - m * (gasOf(r) / S.mpg + S.wear);
    return {
      date: r.date || "", time: r.time || "", zone: r.zone || "", src: r.src || "", rate: r.rate || "",
      p, m, min, net, v: yes(r.verdict), t: took(r.choice),
    };
  });
  const RL = R.filter((r) => r.src !== "archive");
  const nl = RL.length;
  const acc = R.filter((r) => r.t);
  const hrs = sum(acc, (r) => r.min) / 60;
  const pay = sum(acc, (r) => r.p), mi = sum(acc, (r) => r.m), net = sum(acc, (r) => r.net);
  const accL = RL.filter((r) => r.t).length;
  const followed = RL.filter((r) => r.v === r.t).length;
  const fp = nl ? Math.round((100 * followed) / nl) : 0;

  const hr = (arr: AnRow[]) => {
    const h = sum(arr, (r) => r.min) / 60;
    return h ? money(sum(arr, (r) => r.net) / h) : "--";
  };
  const cell = (v: boolean, t: boolean) => RL.filter((r) => r.v === v && r.t === t);

  const Z: Record<string, AnRow[]> = {};
  acc.forEach((r) => { if (!r.zone) return; (Z[r.zone] = Z[r.zone] || []).push(r); });
  const zrate = (z: string) => sum(Z[z], (r) => r.net) / Math.max(1, sum(Z[z], (r) => r.min));
  const zk = Object.keys(Z).sort((a, b) => zrate(b) - zrate(a));

  const HB: Record<number, AnRow[]> = {};
  acc.forEach((r) => {
    const h = parseInt((r.time || "").split(":")[0]);
    if (isNaN(h)) return;
    (HB[h] = HB[h] || []).push(r);
  });
  const hk = Object.keys(HB).map(Number).sort((a, b) => a - b);

  const M: Record<string, AnRow[]> = {};
  acc.forEach((r) => {
    const k = (r.date || "").slice(0, 7);
    if (!/^\d{4}-\d\d$/.test(k)) return;
    (M[k] = M[k] || []).push(r);
  });

  let li = 0;
  LEVELS.forEach((l, j) => { if (n >= l[1]) li = j; });
  const nx = LEVELS[li + 1];

  const ded = mi * S.taxRate;
  return {
    n, nl, R, RL,
    followPct: n ? fp : null,
    followText: nl
      ? followed + " of " + nl + " logged offers matched the verdict. " + (fp >= 85 ? "Locked in." : "Room to tighten up.")
      : "Archive rows have no verdicts. Log offers with the shortcut to see this.",
    estNote: n > nl ? n - nl + " deliveries come from your DoorDash archive, with estimated pay and miles." : "",
    stats: !n ? [] : [
      { label: "Acceptance", value: nl ? Math.round((100 * accL) / nl) + "%" : "--" },
      { label: "Gross", value: money(pay, 0), money: true },
      { label: "Net after car", value: money(net, 0), money: true },
      { label: "Net $/hr", value: hrs ? money(net / hrs) : "--", money: true },
      { label: "Net $/mile", value: mi ? money(net / mi) : "--", money: true },
      { label: "Offers", value: String(n) },
      { label: "Miles driven", value: mi.toFixed(0) },
      { label: "Hours", value: hrs.toFixed(1) },
    ],
    matrix: ([
      [true, true, "Said yes, you accepted", true],
      [true, false, "Said yes, you declined", false],
      [false, true, "Said no, you accepted", false],
      [false, false, "Said no, you declined", true],
    ] as [boolean, boolean, string, boolean][]).map(([v, t, label, good]) => ({
      label, good, count: cell(v, t).length, hourly: hr(cell(v, t)),
    })),
    zones: zk.map((z) => {
      const a = Z[z], m = sum(a, (r) => r.m), nt = sum(a, (r) => r.net);
      return { zone: z, orders: a.length, hourly: hr(a), perMile: m ? money(nt / m) : "--" };
    }),
    hours: hk.map((h) => {
      const a = HB[h], t = sum(a, (r) => r.min) / 60, n2 = sum(a, (r) => r.net);
      return { label: hourLabel(h), orders: a.length, hourly: t ? money(n2 / t) : "--" };
    }),
    months: Object.keys(M).sort().reverse().map((k) => {
      const a = M[k], m = sum(a, (r) => r.m);
      return { month: k, orders: a.length, gross: sum(a, (r) => r.p), miles: m, net: sum(a, (r) => r.net), deduction: m * S.taxRate };
    }),
    tax: { gross: pay, miles: mi, deduction: ded, taxable: pay - ded },
    level: { name: LEVELS[li][0], offers: n, pct: nx ? (100 * (n - LEVELS[li][1])) / (nx[1] - LEVELS[li][1]) : 100 },
    logRate: nl ? Math.round((100 * accL) / nl) : null,
  };
}

// ---------------------------------------------------------------- what-if

export interface ReplayResult {
  current: { n: number; net: number; hr: number };
  change: { n: number; net: number; hr: number };
  flipped: { date: string; zone: string; payout: number; miles: number; now: boolean; then: boolean }[];
  flippedCount: number;
  delta: number;
  rateNow: number;
  rateChange: number;
}

export function replay(rows: LogRow[], S: Settings, D: Settings): ReplayResult {
  const A = rows.map((r) => ({
    r,
    a: verdict(r, S, num(r.rate) || S.accept),
    b: verdict(r, D, num(r.rate) || D.accept),
  }));
  const tot = (k: "a" | "b") => {
    const y = A.filter((x) => x[k].ok);
    const net = sum(y, (x) => x[k].net), h = sum(y, (x) => x[k].h);
    return { n: y.length, net, hr: h ? net / h : 0 };
  };
  const a = tot("a"), b = tot("b");
  const fl = A.filter((x) => x.a.ok !== x.b.ok);
  return {
    current: a, change: b,
    flipped: fl.slice(0, 12).map((x) => ({
      date: x.r.date || "", zone: x.r.zone || "",
      payout: x.a.net + num(x.r.miles) * (S.gas / S.mpg + S.wear),
      miles: num(x.r.miles), now: x.a.ok, then: x.b.ok,
    })),
    flippedCount: fl.length,
    delta: b.net - a.net,
    rateNow: num(S.accept),
    rateChange: num(D.accept),
  };
}

