// Settings defaults and labels. Same keys, defaults and wording as the web app (index.html).

export interface Settings {
  accept: number;
  estPay: number;
  estMph: number;
  mpg: number;
  wear: number;
  gas: number;
  rampTop: number;
  rampLow: number;
  floorMile: number;
  floorHour: number;
  baseMile: number;
  baseHour: number;
  bigItems: number;
  bigMile: number;
  bigHour: number;
  emergency: number;
  taxRate: number;
  target: number;
  caWage: number;
  caPct: number;
  caMile: number;
  /** month "YYYY-MM" -> [statement total, miles] */
  monthly: Record<string, [number, number]>;
  /** zone name -> gas price for that zone */
  zoneGas: Record<string, number>;
  /** 1 once the user has saved their acceptance counts */
  accSet?: number;
  version?: number;
}

export type NumericKey = Exclude<
  keyof Settings,
  "monthly" | "zoneGas" | "accSet" | "version"
>;

export const DEF: Record<NumericKey, number> = {
  accept: 89,
  estPay: 7,
  estMph: 20,
  mpg: 17.5,
  wear: 0.12,
  gas: 5.75,
  rampTop: 90,
  rampLow: 85,
  floorMile: 0.75,
  floorHour: 10,
  baseMile: 1.5,
  baseHour: 18,
  bigItems: 3,
  bigMile: 2,
  bigHour: 20,
  emergency: 80,
  taxRate: 0.7,
  target: 85,
  caWage: 16.9,
  caPct: 120,
  caMile: 0.37,
};

export const LBL: Record<NumericKey, string> = {
  accept: "Acceptance rate (%)",
  estPay: "Archive est. pay per delivery ($)",
  estMph: "Archive est. avg speed (mph)",
  mpg: "MPG",
  wear: "Wear cost per mile ($)",
  gas: "Gas price ($/gal)",
  rampTop: "Ramp top (% acceptance)",
  rampLow: "Ramp low (% acceptance)",
  floorMile: "Floor $/mile",
  floorHour: "Floor $/hour",
  baseMile: "Base $/mile",
  baseHour: "Base $/hour",
  bigItems: "Big order: items over",
  bigMile: "Big order $/mile",
  bigHour: "Big order $/hour",
  emergency: "Emergency rate (%)",
  taxRate: "Mileage deduction rate ($/mi)",
  target: "Float target (% acceptance)",
  caWage: "CA minimum wage ($/hr)",
  caPct: "CA guarantee (% of min wage per active hour)",
  caMile: "CA guarantee per mile ($)",
};

import { num } from "./util.ts";

export const NUMERIC_KEYS = Object.keys(DEF) as NumericKey[];

export function defaultSettings(): Settings {
  return { ...DEF, monthly: {}, zoneGas: {} };
}

/** Rebuild settings from whatever was saved (local, cloud or a handoff file). */
export function mergeStoredSettings(s: any): Settings {
  const S = defaultSettings();
  if (!s || typeof s !== "object") return S;
  S.monthly = s.monthly || {};
  S.zoneGas = s.zoneGas || {};
  S.gas = num(s.gas) > 0 ? num(s.gas) : DEF.gas;
  NUMERIC_KEYS.forEach((k) => {
    if (k !== "gas" && s[k] !== undefined && s[k] !== null && Number.isFinite(Number(s[k]))) S[k] = num(s[k]);
  });
  if (s.accSet) S.accSet = 1;
  return S;
}

/** Editor text for per-zone gas: one "Zone=5.99" per line. */
export const zoneGasText = (S: Settings): string =>
  Object.entries(S.zoneGas || {}).map((e) => e.join("=")).join("\n");

/** Editor text for statement months: one "2026-10=1234.56,812" per line (total, optional miles). */
export const monthlyText = (S: Settings): string =>
  Object.entries(S.monthly || {})
    .map((e) => e[0] + "=" + e[1][0] + (e[1][1] ? "," + e[1][1] : ""))
    .join("\n");

/** Apply the editor's field values and the two text boxes onto a copy of the current settings. */
export function readSettingsForm(
  base: Settings,
  fields: Partial<Record<NumericKey, string>>,
  zoneText: string,
  monthlyTxt: string,
): Settings {
  const S: Settings = { ...base, monthly: {}, zoneGas: {} };
  NUMERIC_KEYS.forEach((k) => {
    if (fields[k] !== undefined) S[k] = num(fields[k]);
  });
  (zoneText || "").split(/\n/).forEach((l) => {
    const p = l.split("=");
    if (p[0] && num(p[1]) > 0) S.zoneGas[p[0].trim()] = num(p[1]);
  });
  (monthlyTxt || "").split(/\n/).forEach((l) => {
    const p = l.split("="), v = (p[1] || "").split(",");
    if (/^\d{4}-\d\d$/.test((p[0] || "").trim()) && num(v[0]) > 0) S.monthly[p[0].trim()] = [num(v[0]), num(v[1])];
  });
  S.version = 1;
  return S;
}
