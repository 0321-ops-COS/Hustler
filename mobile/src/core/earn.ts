// Monthly statements ("Earn" tab): parse statement text, combine with archive rows.

import type { AnRow } from "./log.ts";
import { num, money, pad2, MONTH_NAMES, DAY_SHORT } from "./util.ts";

export interface Statement { k: string; total: number; n: number }
export type Statements = Record<string, Statement>;

/** Read one statement's text: "<Month> <Year> Statement", "Total Payouts $x", "Payouts (n)". */
export function parseStatement(t: string): Statement | null {
  const m = t.match(/(January|February|March|April|May|June|July|August|September|October|November|December) (\d{4}) Statement/);
  const a = t.match(/Total Payouts\s*\$([\d,]+\.\d\d)/);
  const c = t.match(/Payouts \((\d+)\)/);
  return m && a ? { k: m[2] + "-" + pad2(MONTH_NAMES.indexOf(m[1]) + 1), total: num(a[1]), n: c ? +c[1] : 0 } : null;
}

export interface EarnStats {
  tiles: { label: string; value: string; money?: boolean }[];
  table: string[][];
  days: { label: string; deliveries: number; max: number }[];
  notes: string[];
}

export function earnStats(STM: Statements, rows: { date?: string; minutes?: string; src?: string }[] | AnRow[]): EarnStats | null {
  const ks = Object.keys(STM).sort();
  if (!ks.length) return null;
  const A = (rows as { date?: string; min?: number; minutes?: string; src?: string }[]).filter((r) => r.src === "archive");
  const mm: Record<string, { n: number; m: number }> = {};
  A.forEach((r) => {
    const k = (r.date || "").slice(0, 7);
    (mm[k] = mm[k] || { n: 0, m: 0 }).n++;
    mm[k].m += r.min !== undefined ? r.min : num(r.minutes);
  });
  let T = 0, P = 0, DN = 0, HR = 0;
  const table = ks.map((k) => {
    const s = STM[k], a = mm[k] || { n: 0, m: 0 }, h = a.m / 60;
    T += s.total; P += s.n; DN += a.n; HR += h;
    return [k, money(s.total), String(s.n), String(a.n), a.n ? money(s.total / a.n) : "--", h ? money(s.total / h) : "--"];
  });
  const wd = [0, 0, 0, 0, 0, 0, 0];
  A.forEach((r) => {
    const d = new Date((r.date || "") + "T12:00:00");
    if (!isNaN(+d) && STM[(r.date || "").slice(0, 7)]) wd[d.getDay()]++;
  });
  const pd = ks.filter((k) => (mm[k] || { n: 0 }).n >= 30).map((k): [string, number] => [k, STM[k].total / mm[k].n]).sort((a, b) => b[1] - a[1]);
  const wx = Math.max(...wd), hi = wd.indexOf(wx), lo = wd.indexOf(Math.min(...wd));
  const notes: string[] = [];
  if (pd.length > 1) notes.push(`Best pay per delivery: ${pd[0][0]} at ${money(pd[0][1])}. Lowest: ${pd[pd.length - 1][0]} at ${money(pd[pd.length - 1][1])}. The gap is what a better offer mix is worth.`);
  if (DN) notes.push(`${DAY_SHORT[hi]} is your busiest day with ${wd[hi]} deliveries, and ${DAY_SHORT[lo]} is your quietest with ${wd[lo]}.`);
  notes.push("Statements show total pay only. They don't split base pay, tips and peak pay, and they have no miles. Logging offers with the shortcut is what shows which zones and offer types pay.");
  return {
    tiles: [
      { label: `Earned, ${ks.length} months`, value: money(T, 0), money: true },
      { label: "Payouts", value: String(P) },
      { label: "Per delivery", value: DN ? money(T / DN) : "--", money: true },
      { label: "Per active hour", value: HR ? money(T / HR) : "--", money: true },
    ],
    table,
    days: wd.map((v, i) => ({ label: DAY_SHORT[i], deliveries: v, max: wx })),
    notes,
  };
}

/** Put every statement's total into settings.monthly, keeping any saved miles. */
export function applyStatements(monthly: Record<string, [number, number]>, STM: Statements): Record<string, [number, number]> {
  const out = { ...monthly };
  Object.values(STM).forEach((s) => { out[s.k] = [s.total, (out[s.k] || [])[1] || 0]; });
  return out;
}
