// App state: settings, log, archive, statements. Loads from storage on launch, saves on every change.

import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import {
  type Settings, type ArchRec, type Statements, type LogRow, type Analysis,
  defaultSettings, mergeStoredSettings, parseLog, adjust, analyze, ingestText, addPipeRow,
  mergeArchiveIntoLog, parseDeliveries, applyStatements, parseStatement, num, PIPE_HEADER,
} from "../core/index.ts";
import { cloud } from "./cloud";
import { get, put, loadPins, savePins, syncNow } from "./storage";

export interface Ctx {
  ready: boolean;
  S: Settings;
  csv: string;
  isDemo: boolean;
  arch: ArchRec[];
  stm: Statements;
  ca: Record<string, unknown>;
  rows: LogRow[];
  an: Analysis;
  pins: Record<string, boolean>;
  user: string | null;
  toast: string;
  say: (t: string) => void;
  saveSettings: (S: Settings) => Promise<void>;
  setAccept: (n: number, fromCounts?: boolean) => Promise<void>;
  saveLog: (csv: string) => Promise<"account" | "phone" | null>;
  clearLog: () => Promise<void>;
  loadDemo: () => void;
  ingest: (text: string) => Promise<{ ok: boolean; msg: string }>;
  importDeliveryCsv: (text: string) => Promise<{ ok: boolean; msg: string }>;
  takeStatements: (texts: string[]) => Promise<number>;
  logPipeRow: (line: string) => Promise<"added" | "dup" | "bad">;
  replaceAll: (settings?: Record<string, unknown>, csv?: string) => Promise<void>;
  setPin: (k: string, on: boolean) => void;
  cloudSync: () => Promise<number>;
}

const X = createContext<Ctx | null>(null);
export const useApp = (): Ctx => {
  const c = useContext(X);
  if (!c) throw new Error("useApp outside provider");
  return c;
};

export function makeDemo(): string {
  const Z = ["Vista", "Oceanside", "Carlsbad", "San Marcos"];
  const o = ["date,time,zone,payout,miles,items,minutes,verdict,choice"];
  for (let i = 0; i < 40; i++) {
    const m = +(1.5 + Math.random() * 7).toFixed(1);
    const p = +(3 + m * (0.9 + Math.random() * 1.2)).toFixed(2);
    const v = p / m > 1.6 ? "Accept" : "Decline";
    const flip = Math.random() >= 0.85;
    const took = (v === "Accept") !== flip;
    o.push(`2026-10-${10 + (i % 14)},12:${10 + i},${Z[i % 4]},${p},${m},${1 + (i % 4)},${Math.round(10 + m * 3.2)},${v},${took ? "Accepted" : "Declined"}`);
  }
  return o.join("\n");
}

export function AppProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false);
  const [S, setS] = useState<Settings>(defaultSettings());
  const [csv, setCsvState] = useState("");
  const [isDemo, setDemo] = useState(false);
  const [arch, setArch] = useState<ArchRec[]>([]);
  const [stm, setStm] = useState<Statements>({});
  const [ca, setCa] = useState<Record<string, unknown>>({});
  const [pins, setPins] = useState<Record<string, boolean>>({});
  const [user, setUser] = useState<string | null>(null);
  const [toast, setToast] = useState("");
  const tt = useRef<ReturnType<typeof setTimeout> | null>(null);

  const say = useCallback((t: string) => {
    setToast(t);
    if (tt.current) clearTimeout(tt.current);
    tt.current = setTimeout(() => setToast(""), 2200);
  }, []);

  const loadAll = useCallback(async () => {
    const s = await get("settings");
    if (s) setS(mergeStoredSettings(s));
    const sm = await get("statements");
    if (sm && sm.s) setStm(sm.s);
    const c0 = await get("ca");
    if (c0 && c0.w) setCa(c0.w);
    const ar = await get("archive");
    if (ar && ar.r) setArch(ar.r);
    const l = await get("log");
    if (l && typeof l.csv === "string") setCsvState(l.csv);
  }, []);

  useEffect(() => {
    (async () => {
      await cloud.init();
      setUser(cloud.user?.email ?? cloud.user?.id ?? null);
      cloud.subscribe(() => setUser(cloud.user?.email ?? cloud.user?.id ?? null));
      setPins(await loadPins());
      await loadAll();
      setReady(true);
    })();
  }, [loadAll]);

  const rows = useMemo(() => adjust(parseLog(csv), S), [csv, S]);
  const an = useMemo(() => analyze(rows, S), [rows, S]);

  const saveSettings = useCallback(async (next: Settings) => {
    setS(next);
    const w = await put("settings", next);
    say(w ? "Settings saved" : "Could not save");
  }, [say]);

  const setAccept = useCallback(async (n: number, fromCounts = false) => {
    const next = { ...S, accept: n, ...(fromCounts ? { accSet: 1 } : {}) };
    setS(next);
    await put("settings", next);
    say("Acceptance rate set to " + n + "%");
  }, [S, say]);

  const saveLog = useCallback(async (next: string) => {
    setCsvState(next);
    setDemo(false);
    return put("log", { csv: next, v: 1 });
  }, []);

  const clearLog = useCallback(async () => {
    setCsvState("");
    setDemo(false);
    await put("log", { csv: "", v: 1 });
    say("Cleared");
  }, [say]);

  const loadDemo = useCallback(() => {
    setCsvState(makeDemo());
    setDemo(true);
    say("Demo data, not saved");
  }, [say]);

  const ingest = useCallback(async (text: string) => {
    const r = ingestText(text, isDemo ? "" : csv);
    if (r.kind === "bad") return { ok: false, msg: "Could not read that file" };
    if (r.kind === "handoff") {
      if (r.settings) {
        const ns = mergeStoredSettings(r.settings);
        setS(ns);
        await put("settings", ns);
      }
      if (r.csv !== undefined) { setCsvState(r.csv); setDemo(false); await put("log", { csv: r.csv, v: 1 }); }
      return { ok: true, msg: "Handoff imported" };
    }
    await saveLog(r.csv);
    return { ok: true, msg: r.added + " new rows added" };
  }, [csv, isDemo, saveLog]);

  const importDeliveryCsv = useCallback(async (text: string) => {
    const d = parseDeliveries(text);
    if (!d.ok) return { ok: false, msg: "Not a DoorDash delivery file" };
    setArch(d.arch);
    await put("archive", { v: 1, r: d.arch });
    await saveLog(mergeArchiveIntoLog(d.arch, S, isDemo ? "" : csv));
    return { ok: true, msg: d.arch.length + " deliveries added to your log" };
  }, [S, csv, isDemo, saveLog]);

  const takeStatements = useCallback(async (texts: string[]) => {
    const next: Statements = { ...stm };
    let got = 0;
    for (const t of texts) {
      const s = parseStatement(t);
      if (s) { next[s.k] = s; got++; }
    }
    if (!got) return 0;
    setStm(next);
    const ns = { ...S, monthly: applyStatements(S.monthly || {}, next) };
    setS(ns);
    await put("statements", { v: 1, s: next });
    await put("settings", ns);
    return got;
  }, [stm, S]);

  const logPipeRow = useCallback(async (line: string) => {
    const r = addPipeRow(line, isDemo ? "" : csv);
    if (r.status !== "added") return r.status;
    await saveLog(r.csv);
    return "added" as const;
  }, [csv, isDemo, saveLog]);

  const replaceAll = useCallback(async (settings?: Record<string, unknown>, c?: string) => {
    if (settings) { const ns = mergeStoredSettings(settings); setS(ns); await put("settings", ns); }
    if (c !== undefined) await saveLog(c);
  }, [saveLog]);

  const setPin = useCallback((k: string, on: boolean) => {
    setPins((p) => { const n = { ...p, [k]: on }; savePins(n); return n; });
  }, []);

  const cloudSync = useCallback(async () => {
    const n = await syncNow();
    await loadAll();
    return n;
  }, [loadAll]);

  const value: Ctx = {
    ready, S, csv, isDemo, arch, stm, ca, rows, an, pins, user, toast, say,
    saveSettings, setAccept, saveLog, clearLog, loadDemo, ingest, importDeliveryCsv,
    takeStatements, logPipeRow, replaceAll, setPin, cloudSync,
  };
  return <X.Provider value={value}>{children}</X.Provider>;
}

export { num, PIPE_HEADER };
