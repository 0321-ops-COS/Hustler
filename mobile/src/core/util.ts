// Small shared helpers, ported 1:1 from the web app.

/** Parse a number out of text like "$1,234.50". Anything unreadable is 0. */
export const num = (v: unknown): number => {
  const n = parseFloat(String(v).replace(/[$,]/g, ""));
  return isNaN(n) ? 0 : n;
};

/** "$12.34". Negative numbers print as "$-3.20", exactly like the web app. */
export const money = (n: number, d = 2): string => "$" + n.toFixed(d);

export const pad2 = (n: number | string): string => String(n).padStart(2, "0");

/** Local-date key "YYYY-MM-DD". */
export const iso = (d: Date): string =>
  d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());

export const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];
export const DAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

export const hourLabel = (h: number): string => (h % 12 || 12) + (h < 12 ? "am" : "pm");

export const sum = <T,>(a: T[], f: (x: T) => number): number =>
  a.reduce((s, x) => s + f(x), 0);

/** 12345 -> "12,345" (avoids depending on Intl being present). */
export const commas = (n: number): string => String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
