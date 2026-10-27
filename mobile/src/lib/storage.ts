// Local storage (AsyncStorage, keys "hh_<name>" like the web app) with optional Supabase cloud mirror.
// Cloud table: hh_store(user_id, k, v, updated_at), same as the web app, so both apps share an account.

import AsyncStorage from "@react-native-async-storage/async-storage";
import { cloud } from "./cloud";

export const KEYS = ["settings", "log", "archive", "statements", "ca"] as const;
export type Key = (typeof KEYS)[number];

const tmo = <T,>(p: PromiseLike<T>, ms = 8000): Promise<T> =>
  Promise.race([p as Promise<T>, new Promise<T>((_, rej) => setTimeout(() => rej(new Error("timeout")), ms))]);

async function dirtyList(): Promise<string[]> {
  try { return JSON.parse((await AsyncStorage.getItem("hh_dirty")) || "[]"); } catch { return []; }
}
async function setDirty(k: string, on: boolean) {
  const d = new Set(await dirtyList());
  if (on) d.add(k); else d.delete(k);
  try { await AsyncStorage.setItem("hh_dirty", JSON.stringify([...d])); } catch { /* ignore */ }
}
export async function dirtyCount(): Promise<number> { return (await dirtyList()).length; }

export async function localGet<T = any>(k: string): Promise<T | null> {
  try {
    const v = await AsyncStorage.getItem("hh_" + k);
    return v ? (JSON.parse(v) as T) : null;
  } catch { return null; }
}

async function cloudPut(k: string, obj: unknown): Promise<boolean> {
  const c = cloud.client, u = cloud.user;
  if (!c || !u) return false;
  try {
    const r = await tmo(c.from("hh_store").upsert({ user_id: u.id, k, v: obj, updated_at: new Date().toISOString() }, { onConflict: "user_id,k" }));
    return !r.error;
  } catch { return false; }
}

/** undefined = could not reach the cloud, null = nothing stored there. */
async function cloudGet(k: string): Promise<any | null | undefined> {
  const c = cloud.client, u = cloud.user;
  if (!c || !u) return undefined;
  try {
    const r = await tmo(c.from("hh_store").select("v").eq("k", k).maybeSingle());
    if (r.error) return undefined;
    return r.data ? r.data.v : null;
  } catch { return undefined; }
}

/** Save to this phone, then to the account when signed in. Returns where it landed. */
export async function put(k: Key, obj: unknown): Promise<"account" | "phone" | null> {
  let where: "account" | "phone" | null = null;
  try { await AsyncStorage.setItem("hh_" + k, JSON.stringify(obj)); where = "phone"; } catch { /* ignore */ }
  if (cloud.user) {
    const ok = await cloudPut(k, obj);
    await setDirty(k, !ok);
    if (ok) where = "account";
  }
  return where;
}

export async function get<T = any>(k: Key): Promise<T | null> {
  if (cloud.user && !(await dirtyList()).includes(k)) {
    const c = await cloudGet(k);
    if (c !== undefined && c !== null) {
      try { await AsyncStorage.setItem("hh_" + k, JSON.stringify(c)); } catch { /* ignore */ }
      return c as T;
    }
  }
  return localGet<T>(k);
}

/** Push anything this phone has that the account lacks, or that failed to upload earlier. */
export async function syncNow(): Promise<number> {
  let n = 0;
  for (const k of KEYS) {
    const l = await localGet(k);
    if (!l) continue;
    const c = await cloudGet(k);
    if (c === undefined) continue;
    if (c === null || (await dirtyList()).includes(k)) {
      if (await cloudPut(k, l)) { await setDirty(k, false); n++; }
    }
  }
  return n;
}

export async function loadPins(): Promise<Record<string, boolean>> {
  try { return JSON.parse((await AsyncStorage.getItem("hh_pins")) || "{}"); } catch { return {}; }
}
export async function savePins(p: Record<string, boolean>) {
  try { await AsyncStorage.setItem("hh_pins", JSON.stringify(p)); } catch { /* ignore */ }
}
