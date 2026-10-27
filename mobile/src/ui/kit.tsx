// Small UI kit: cards, stats, buttons, fields, tables, bars. Dark theme from the web app.

import React from "react";
import {
  View, Text, TextInput, Pressable, ScrollView, StyleSheet, KeyboardAvoidingView, Platform,
  type TextInputProps, type ViewStyle, type StyleProp,
} from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { C, R } from "../lib/theme";
import { useApp } from "../lib/store";

export function Screen({ children }: { children: React.ReactNode }) {
  const { toast } = useApp();
  return (
    <SafeAreaView style={s.screen} edges={["top"]}>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <ScrollView contentContainerStyle={s.scroll} keyboardShouldPersistTaps="handled">
          {children}
        </ScrollView>
      </KeyboardAvoidingView>
      {!!toast && (
        <View style={s.toast} pointerEvents="none"><Text style={s.toastTx}>{toast}</Text></View>
      )}
    </SafeAreaView>
  );
}

export const H2 = ({ children }: { children: React.ReactNode }) => <Text style={s.h2}>{children}</Text>;
export const Hint = ({ children, style }: { children: React.ReactNode; style?: StyleProp<any> }) => (
  <Text style={[s.hint, style]}>{children}</Text>
);

export function Card({ children, style }: { children: React.ReactNode; style?: StyleProp<ViewStyle> }) {
  return <View style={[s.card, style]}>{children}</View>;
}

export function Stat({ value, label, tone }: { value: string; label: string; tone?: "go" | "no" | "gold" }) {
  const col = tone === "go" ? C.go : tone === "no" ? C.no : tone === "gold" ? C.gold : C.tx;
  return (
    <View style={s.stat}>
      <Text style={[s.num, { color: col }]} numberOfLines={1} adjustsFontSizeToFit>{value}</Text>
      <Text style={s.statLbl}>{label}</Text>
    </View>
  );
}

export const Grid = ({ children }: { children: React.ReactNode }) => <View style={s.grid}>{children}</View>;

export function Btn({ label, onPress, kind = "primary", style, disabled }: {
  label: string; onPress: () => void; kind?: "primary" | "ghost" | "go"; style?: StyleProp<ViewStyle>; disabled?: boolean;
}) {
  const bg = kind === "primary" ? C.gold : kind === "go" ? C.go : "transparent";
  const fg = kind === "ghost" ? C.tx : C.ink;
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [s.btn, { backgroundColor: bg, borderColor: kind === "ghost" ? C.g2 : bg, opacity: pressed || disabled ? 0.6 : 1 }, style]}
    >
      <Text style={[s.btnTx, { color: fg }]}>{label}</Text>
    </Pressable>
  );
}

export const Row = ({ children, style }: { children: React.ReactNode; style?: StyleProp<ViewStyle> }) => (
  <View style={[s.row, style]}>{children}</View>
);

export function Field({ label, style, ...p }: TextInputProps & { label: string }) {
  return (
    <View style={[s.field, style]}>
      <Text style={s.fieldLbl}>{label}</Text>
      <TextInput
        placeholderTextColor={C.g3}
        keyboardAppearance="dark"
        style={[s.input, p.multiline && { minHeight: 110, textAlignVertical: "top" }]}
        {...p}
      />
    </View>
  );
}

export function Table({ head, rows, widths }: { head: string[]; rows: (string | number)[][]; widths?: number[] }) {
  const w = (i: number) => (widths ? { width: widths[i] } : { flex: 1 });
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false}>
      <View style={{ minWidth: "100%" }}>
        <View style={s.tr}>
          {head.map((h, i) => <Text key={i} style={[s.th, w(i)]}>{h}</Text>)}
        </View>
        {rows.map((r, j) => (
          <View key={j} style={s.tr}>
            {r.map((c, i) => <Text key={i} style={[s.td, w(i)]}>{String(c)}</Text>)}
          </View>
        ))}
      </View>
    </ScrollView>
  );
}

export function Bar({ v, max, color = C.go }: { v: number; max: number; color?: string }) {
  return (
    <View style={s.barBg}>
      <View style={{ height: "100%", width: `${max ? Math.min(100, (100 * v) / max) : 0}%`, backgroundColor: color, borderRadius: 5 }} />
    </View>
  );
}

/** Label + bar rows for "by day / by hour" charts. */
export function BarRows({ items }: { items: { label: string; v: number; max: number }[] }) {
  return (
    <View>
      {items.map((x, i) => (
        <View key={i} style={s.barRow}>
          <Text style={s.barLbl}>{x.label}</Text>
          <View style={{ flex: 1 }}><Bar v={x.v} max={x.max} /></View>
          <Text style={s.barVal}>{x.v}</Text>
        </View>
      ))}
    </View>
  );
}

export function Chip({ label, on }: { label: string; on?: boolean }) {
  return (
    <View style={[s.chip, on && { borderColor: C.go, backgroundColor: "rgba(43,255,136,.12)" }]}>
      <Text style={[s.chipTx, on && { color: C.go }]}>{label}</Text>
    </View>
  );
}

export function Seg<T extends string>({ value, options, onChange }: {
  value: T; options: { k: T; label: string }[]; onChange: (k: T) => void;
}) {
  return (
    <View style={s.seg}>
      {options.map((o) => (
        <Pressable key={o.k} onPress={() => onChange(o.k)} style={[s.segBtn, value === o.k && { backgroundColor: C.gold }]}>
          <Text style={[s.segTx, value === o.k && { color: C.ink, fontWeight: "700" }]}>{o.label}</Text>
        </Pressable>
      ))}
    </View>
  );
}

export const Divider = () => <View style={{ height: 1, backgroundColor: C.line, marginVertical: 16 }} />;

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: C.bg },
  scroll: { padding: 16, paddingBottom: 48 },
  h2: { color: C.tx, fontSize: 17, fontWeight: "700" },
  hint: { color: C.mut, fontSize: 13, lineHeight: 19, marginTop: 6 },
  card: { backgroundColor: C.panel, borderRadius: R.card, borderWidth: 1, borderColor: C.line, padding: 16, marginBottom: 14 },
  grid: { flexDirection: "row", flexWrap: "wrap", gap: 10, marginTop: 12 },
  stat: { flexBasis: "47%", flexGrow: 1, backgroundColor: C.g1, borderRadius: 12, padding: 12, borderWidth: 1, borderColor: C.line },
  num: { fontSize: 24, fontWeight: "800" },
  statLbl: { color: C.mut, fontSize: 12, marginTop: 2 },
  btn: { paddingVertical: 11, paddingHorizontal: 16, borderRadius: R.btn, borderWidth: 1, alignItems: "center" },
  btnTx: { fontWeight: "700", fontSize: 15 },
  row: { flexDirection: "row", flexWrap: "wrap", gap: 10, marginTop: 12 },
  field: { flexBasis: "47%", flexGrow: 1, marginTop: 10 },
  fieldLbl: { color: C.mut, fontSize: 12, marginBottom: 4 },
  input: { backgroundColor: C.g1, borderWidth: 1, borderColor: C.g2, borderRadius: R.input, color: C.tx, paddingHorizontal: 12, paddingVertical: 10, fontSize: 16 },
  tr: { flexDirection: "row", borderBottomWidth: 1, borderBottomColor: C.line, paddingVertical: 8, gap: 8 },
  th: { color: C.mut, fontSize: 12, fontWeight: "600", minWidth: 64 },
  td: { color: C.tx, fontSize: 14, minWidth: 64 },
  barBg: { height: 8, backgroundColor: C.g2, borderRadius: 5, overflow: "hidden" },
  barRow: { flexDirection: "row", alignItems: "center", gap: 10, paddingVertical: 6 },
  barLbl: { color: C.tx, width: 52, fontSize: 13 },
  barVal: { color: C.mut, width: 34, textAlign: "right", fontSize: 13 },
  chip: { borderWidth: 1, borderColor: C.g2, borderRadius: 20, paddingVertical: 5, paddingHorizontal: 12 },
  chipTx: { color: C.mut, fontSize: 13 },
  seg: { flexDirection: "row", backgroundColor: C.g1, borderRadius: 12, padding: 3, borderWidth: 1, borderColor: C.line },
  segBtn: { flex: 1, paddingVertical: 8, borderRadius: 9, alignItems: "center" },
  segTx: { color: C.mut, fontSize: 14 },
  toast: { position: "absolute", bottom: 90, alignSelf: "center", backgroundColor: C.g2, borderRadius: 20, paddingVertical: 10, paddingHorizontal: 18 },
  toastTx: { color: C.tx, fontSize: 14 },
});
