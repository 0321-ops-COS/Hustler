// DoorDash data_archive.zip import: delivery_information.csv -> archive records -> log rows.

import type { Settings } from "./settings.ts";
import { CSV_HEADER_ARCHIVE, splitLog, joinLog } from "./log.ts";
import { num, pad2, hourLabel, DAY_SHORT, commas } from "./util.ts";

/** [orderCreated, pickup, delivery, store, itemCount], times as "YYYY-MM-DDTHH:MM" (UTC, as DoorDash exports them) */
export type ArchRec = [string, string, string, string, number];

export const CITIES = [
  "Murrieta", "Temecula", "Lake Elsinore", "Menifee", "Corona", "Wildomar", "Perris", "Winchester",
  "Sun City", "Canyon Lake", "Fontana", "Riverside", "Hemet", "Norco", "Eastvale", "Moreno Valley",
];

/** Minimal CSV reader that handles quoted fields, doubled quotes and CRLF. */
export function csvRows(t: string): string[][] {
  const o: string[][] = [];
  let r: string[] = [], c = "", q = false;
  for (let i = 0; i < t.length; i++) {
    const ch = t[i];
    if (q) {
      if (ch === '"') { if (t[i + 1] === '"') { c += '"'; i++; } else q = false; }
      else c += ch;
    } else if (ch === '"') q = true;
    else if (ch === ",") { r.push(c); c = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && t[i + 1] === "\n") i++;
      r.push(c); c = "";
      if (r.length > 1 || r[0]) o.push(r);
      r = [];
    } else c += ch;
  }
  if (c || r.length) { r.push(c); o.push(r); }
  return o;
}

/** True when the text looks like DoorDash's delivery file. */
export const looksLikeDeliveryCsv = (t: string): boolean => /ORDER_CREATED_TIME/i.test(t.slice(0, 300));

export type DeliveryParse = { ok: true; arch: ArchRec[] } | { ok: false };

export function parseDeliveries(t: string): DeliveryParse {
  const R = csvRows(t);
  const H = (R[0] || []).map((h) => h.toLowerCase());
  const ix = (k: string) => H.indexOf(k);
  const a = ix("order_created_time"), b = ix("actual_pickup_time"), c = ix("actual_delivery_time");
  const s = ix("store_name"), n = ix("total_item_count"), st = ix("order_status");
  if (a < 0 || c < 0) return { ok: false };
  const T = (v?: string) => (v || "").slice(0, 16).replace(" ", "T");
  const arch = R.slice(1)
    .filter((r) => !/cancel/i.test(r[st] || "") && r[c])
    .map((r): ArchRec => [T(r[a]), T(r[b]), T(r[c]), (r[s] || "").slice(0, 90), num(r[n])]);
  return { ok: true, arch };
}

// ------------------------------------------------ US Pacific time without Intl

function nthSunday(year: number, month: number, n: number): number {
  const dow = new Date(Date.UTC(year, month, 1)).getUTCDay();
  return 1 + ((7 - dow) % 7) + 7 * (n - 1);
}

/** US Pacific daylight time: 2nd Sunday of March 02:00 PST -> 1st Sunday of November 02:00 PDT. */
export function isPacificDST(utcMs: number): boolean {
  const y = new Date(utcMs).getUTCFullYear();
  const start = Date.UTC(y, 2, nthSunday(y, 2, 2), 10);
  const end = Date.UTC(y, 10, nthSunday(y, 10, 1), 9);
  return utcMs >= start && utcMs < end;
}

export function pacificStamp(utcMs: number): { date: string; time: string } {
  const d = new Date(utcMs + (isPacificDST(utcMs) ? -7 : -8) * 3600000);
  return {
    date: d.getUTCFullYear() + "-" + pad2(d.getUTCMonth() + 1) + "-" + pad2(d.getUTCDate()),
    time: pad2(d.getUTCHours()) + ":" + pad2(d.getUTCMinutes()),
  };
}

// ------------------------------------------------ archive -> log rows

/**
 * Each delivery gets an active window from 8 minutes before pickup to drop-off.
 * Overlapping windows (stacked orders) share their combined time equally.
 */
export function archiveLogLines(arch: ArchRec[], S: Settings): string[] {
  const O = arch
    .map((r) => {
      const b = +new Date(r[2] + ":00Z"), p = +new Date((r[1] || r[2]) + ":00Z");
      return { p, a: p - 480000, b, s: r[3], i: r[4], m: 0 };
    })
    .filter((o) => o.b > o.a)
    .sort((x, y) => x.a - y.a);
  let i = 0;
  while (i < O.length) {
    let j = i, end = O[i].b;
    while (j + 1 < O.length && O[j + 1].a < end) { j++; end = Math.max(end, O[j].b); }
    const share = (end - O[i].a) / (j - i + 1) / 60000;
    for (let k = i; k <= j; k++) O[k].m = share;
    i = j + 1;
  }
  return O.map((o) => {
    const q = pacificStamp(o.p);
    const z = CITIES.find((c) => o.s.toLowerCase().includes(c.toLowerCase())) || "";
    return [q.date, q.time, z, num(S.estPay).toFixed(2), ((o.m / 60) * num(S.estMph)).toFixed(1), o.i || 1, Math.round(o.m), "", "Accepted", "archive"].join(",");
  });
}

/** Rebuild the saved log text: keep real rows, replace any earlier archive rows. */
export function mergeArchiveIntoLog(arch: ArchRec[], S: Settings, currentCsv: string): string {
  const lines = archiveLogLines(arch, S);
  const cur = splitLog(currentCsv);
  const old = cur.csv.filter((l) => !/,archive$/.test(l));
  const have = new Set(old);
  return joinLog({
    pipe: cur.pipe,
    header: CSV_HEADER_ARCHIVE,
    csv: [...old, ...lines.filter((l) => !have.has(l))],
  });
}

// ------------------------------------------------ lifetime history stats

const D3 = (a: string) => new Date(a + ":00Z");

export interface ArchStats {
  tiles: { value: string; label: string }[];
  months: { month: string; deliveries: number; avg: string }[];
  hours: { label: string; deliveries: number; max: number }[];
  days: { label: string; deliveries: number; max: number }[];
  stores: { store: string; deliveries: number }[];
  total: number;
}

const MON3 = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

export function archStats(ARCH: ArchRec[]): ArchStats | null {
  if (!ARCH.length) return null;
  const R = ARCH.map((r) => {
    const d = D3(r[2]), dur = r[1] ? (+d - +D3(r[1])) / 60000 : 0;
    return { d, dur: dur > 0 && dur < 180 ? dur : 0, s: r[3], o: D3(r[0]) };
  });
  const n = R.length;
  const mo: Record<string, typeof R> = {};
  const hr: number[] = Array(24).fill(0), wd: number[] = Array(7).fill(0);
  const st: Record<string, number> = {};
  R.forEach((r) => {
    const k = r.d.getFullYear() + "-" + pad2(r.d.getMonth() + 1);
    (mo[k] = mo[k] || []).push(r);
    hr[r.d.getHours()]++;
    wd[r.d.getDay()]++;
    const s = r.s.replace(/\s*[\(#-].*$/, "").trim() || r.s;
    st[s] = (st[s] || 0) + 1;
  });
  const dd = R.filter((r) => r.dur);
  const avg = dd.length ? dd.reduce((a, r) => a + r.dur, 0) / dd.length : 0;
  const first = R.map((r) => r.o).sort((a, b) => +a - +b)[0];
  const bh = hr.indexOf(Math.max(...hr));
  const mx = Math.max(...hr), wx = Math.max(...wd);
  return {
    total: n,
    tiles: [
      { value: commas(n), label: "Lifetime deliveries" },
      { value: MON3[first.getMonth()] + " " + first.getFullYear(), label: "First order" },
      { value: avg ? avg.toFixed(0) + " min" : "--", label: "Avg pickup to drop" },
      { value: hourLabel(bh), label: "Busiest hour" },
    ],
    months: Object.keys(mo).sort().reverse().map((k) => {
      const a = mo[k], d2 = a.filter((r) => r.dur);
      const v = d2.length ? d2.reduce((x, r) => x + r.dur, 0) / d2.length : 0;
      return { month: k, deliveries: a.length, avg: v ? v.toFixed(0) + " min" : "--" };
    }),
    hours: hr.map((v, h) => (v ? { label: hourLabel(h), deliveries: v, max: mx } : null)).filter((x): x is { label: string; deliveries: number; max: number } => !!x),
    days: wd.map((v, i) => ({ label: DAY_SHORT[i], deliveries: v, max: wx })),
    stores: Object.keys(st).sort((a, b) => st[b] - st[a]).slice(0, 10).map((k) => ({ store: k, deliveries: st[k] })),
  };
}
