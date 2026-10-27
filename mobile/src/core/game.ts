// Scoreboard extras: earnings by period, quests, California guarantee, decline float, start-here checklist.

import type { Settings } from "./settings.ts";
import type { AnRow } from "./log.ts";
import { num, money, iso, pad2 } from "./util.ts";

export type Period = "day" | "week" | "month" | "year";

/** Group key for a date string: the day, the Monday of its week, the month or the year. */
export function keyOf(s: string | undefined, p: Period): string {
  s = (s || "").slice(0, 10);
  if (p === "day") return s;
  if (p === "month") return s.slice(0, 7);
  if (p === "year") return s.slice(0, 4);
  const d = new Date(s + "T12:00:00");
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
  return iso(d);
}

interface Bucket { p: number; n: number; c: number; m: number }
const zero = (): Bucket => ({ p: 0, n: 0, c: 0, m: 0 });
const perHour = (g: Bucket) => (g.m ? money(g.n / (g.m / 60)) : "--");

export interface GameStats {
  label: string;
  big: { label: string; value: string; money?: boolean }[];
  table: { key: string; gross: string; net: string; taken: number; hourly: string }[];
  weekHeader: boolean;
  streak: { current: number; best: number };
  quests: { label: string; a: number; b: number; dollars: boolean }[];
  badges: { label: string; on: boolean }[];
}

export function gameStats(R: AnRow[], RL: AnRow[], PER: Period, now: Date): GameStats {
  const acc = R.filter((r) => r.t && /^\d{4}-\d\d-\d\d/.test(r.date || ""));
  const G: Record<string, Bucket> = {};
  acc.forEach((r) => {
    const k = keyOf(r.date, PER);
    const g = (G[k] = G[k] || zero());
    g.p += r.p; g.n += r.net; g.c++; g.m += r.min;
  });
  const today = iso(now);
  const cur0 = keyOf(today, PER);
  const ks = Object.keys(G).sort().reverse().slice(0, PER === "day" ? 10 : PER === "week" ? 8 : 12);
  if (!ks.includes(cur0)) ks.unshift(cur0);
  const cur = G[cur0] || zero();
  const label = { day: "Today", week: "This week", month: "This month", year: "This year" }[PER];

  const fol = RL.filter((r) => (r.date || "").slice(0, 10) === today && r.v === r.t).length;
  const dn: Record<string, number> = {};
  acc.forEach((r) => { const k = r.date.slice(0, 10); dn[k] = (dn[k] || 0) + r.net; });
  const past = Object.keys(dn).filter((k) => k !== today).map((k) => dn[k]);
  const avg = past.length ? past.reduce((a, b) => a + b, 0) / past.length : 50;
  const tn = dn[today] || 0;
  let st = 0, best = 0, run = 0;
  RL.forEach((r) => { if (r.v === r.t) { run++; best = Math.max(best, run); } else run = 0; });
  for (let i = RL.length - 1; i >= 0 && RL[i].v === RL[i].t; i--) st++;
  const fp = RL.length ? RL.filter((r) => r.v === r.t).length / RL.length : 0;
  const life = acc.reduce((a, r) => a + r.net, 0);

  return {
    label,
    big: [
      { label: label + " net", value: money(cur.n, 0), money: true },
      { label: "Gross", value: money(cur.p, 0) },
      { label: "Offers taken", value: String(cur.c) },
      { label: "Net $/hr", value: perHour(cur) },
    ],
    weekHeader: PER === "week",
    table: ks.map((k) => {
      const g = G[k] || zero();
      return { key: k, gross: money(g.p), net: money(g.n), taken: g.c, hourly: perHour(g) };
    }),
    streak: { current: st, best },
    quests: [
      { label: "Follow the call 5 times", a: fol, b: 5, dollars: false },
      { label: "Beat your average day", a: tn, b: Math.max(avg, 1), dollars: true },
      { label: "10 in a row", a: st, b: 10, dollars: false },
    ],
    badges: [
      { label: "25 offers", on: RL.length >= 25 },
      { label: "10 in a row", on: best >= 10 },
      { label: "85% follow rate", on: RL.length >= 20 && fp >= 0.85 },
      { label: "$1,000 net", on: life >= 1000 },
    ],
  };
}

// ------------------------------------------------ California pay guarantee

export const CA_MAX_HOURS = 84;

export interface CaWeek {
  week: string;
  ok: boolean;
  n: number;
  hours: number;
  miles: number;
  pay: number;
  rate: number;
  guaranteed: number;
  adjustment: number;
  payPerHour: number;
  milesPerHour: number;
}

export function caWeek(R: AnRow[], S: Settings, now: Date): CaWeek {
  const wk = keyOf(iso(now), "week");
  const rs = R.filter((r) => r.t && keyOf(r.date, "week") === wk);
  const pay = rs.reduce((a, r) => a + r.p, 0), hours = rs.reduce((a, r) => a + r.min, 0) / 60;
  const miles = rs.reduce((a, r) => a + r.m, 0), n = rs.length;
  const rate = (S.caPct / 100) * S.caWage;
  const g = rate * hours + S.caMile * miles;
  return {
    week: wk, ok: n > 0 && hours > 0, n, hours, miles, pay, rate,
    guaranteed: g, adjustment: Math.max(0, g - pay),
    payPerHour: hours ? pay / hours : 0, milesPerHour: hours ? miles / hours : 0,
  };
}

/** "Next week guess" at a chosen number of hours, using this week's pace. */
export function caProject(w: CaWeek, S: Settings, h: number) {
  const pay = w.payPerHour * h, mi = w.milesPerHour * h;
  const g = w.rate * h + S.caMile * mi;
  const adj = Math.max(0, g - pay);
  return { pay, miles: mi, guaranteed: g, adjustment: adj, total: pay + adj };
}

export const hoursMinutes = (h: number): string =>
  Math.floor(h) + "h " + pad2(Math.round((h % 1) * 60)) + "m";

// ------------------------------------------------ decline float

export interface FloatInfo { target: number; declined: number; left: number; none: boolean; level: "good" | "low" | "none"; message: string }

export function floatInfo(S: Settings): FloatInfo {
  const T = num(S.target) || 85;
  const d = Math.max(0, Math.round(100 - num(S.accept)));
  const left = 100 - T - d, none = left <= 0;
  const message = none
    ? left < 0
      ? "NO FLOAT. You are " + -left + " decline" + (left === -1 ? "" : "s") + " past your " + T + "% target. Accept offers until old declines roll off the last 100."
      : `NO FLOAT. Your next decline drops you under ${T}%. Take what comes.`
    : left <= 3
      ? "LOW. " + left + " decline" + (left === 1 ? "" : "s") + " left before you drop under " + T + "%."
      : "OK. You can pass on " + left + " more before you drop under " + T + "%.";
  return { target: T, declined: d, left, none, level: none ? "none" : left <= 3 ? "low" : "good", message };
}

// ------------------------------------------------ start here

export interface StartInfo {
  hasArchive: boolean;
  hasStatements: boolean;
  hasRate: boolean;
  archiveCount: number;
  statementCount: number;
  exact: string[];
  estimated: string[];
  done: boolean;
}

export function startInfo(R: AnRow[], archCount: number, stmKeys: string[], S: Settings): StartInfo {
  const am: Record<string, 1> = {};
  R.filter((r) => r.src === "archive").forEach((r) => { const k = (r.date || "").slice(0, 7); if (k) am[k] = 1; });
  const ak = Object.keys(am).sort();
  const has = new Set(stmKeys);
  const ex = ak.filter((k) => has.has(k));
  const es = ak.filter((k) => !has.has(k) && (!ex.length || k >= ex[0]));
  const hasA = archCount > 0 || ak.length > 0, hasS = stmKeys.length > 0, hasR = !!S.accSet;
  return {
    hasArchive: hasA, hasStatements: hasS, hasRate: hasR,
    archiveCount: archCount, statementCount: stmKeys.length,
    exact: ex, estimated: es, done: hasA && hasS && hasR,
  };
}
