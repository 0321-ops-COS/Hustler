// Supabase client. Same project and publishable key as the web app, so one account works in both.
// The key is a publishable (anon) key, safe to ship. Override with EXPO_PUBLIC_SUPABASE_* env vars.

import "react-native-url-polyfill/auto";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";

const URL = process.env.EXPO_PUBLIC_SUPABASE_URL || "https://xpcglmabtsceyzfrdiky.supabase.co";
const KEY = process.env.EXPO_PUBLIC_SUPABASE_KEY || "sb_publishable_-_9Q2cS-64BaU5-uQJDVlQ_c1k_IpeO";

class Cloud {
  client: SupabaseClient | null = null;
  user: User | null = null;
  private subs = new Set<() => void>();

  async init() {
    try {
      this.client = createClient(URL, KEY, {
        auth: { storage: AsyncStorage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: false },
      });
      const r = await Promise.race([
        this.client.auth.getSession(),
        new Promise<never>((_, rej) => setTimeout(() => rej(new Error("timeout")), 8000)),
      ]);
      this.user = r?.data?.session?.user ?? null;
      this.client.auth.onAuthStateChange((_e, s) => { this.user = s?.user ?? null; this.subs.forEach((f) => f()); });
    } catch {
      // offline: keep the client (so it can retry later) but no user
      this.user = this.user ?? null;
    }
  }

  subscribe(f: () => void) { this.subs.add(f); return () => { this.subs.delete(f); }; }
}

export const cloud = new Cloud();
