import React, { useState } from "react";
import { SafeAreaView, Text, StyleSheet, TextInput, Button, ScrollView } from "react-native";

const BACKEND = "http://localhost:3000"; // device: "http://<YOUR_MAC_IP>:3000"

export default function App() {
  const [q, setQ] = useState("comment déboucher un évier");
  const [res, setRes] = useState(null);
  const [loading, setLoading] = useState(false);

  async function runSearch() {
    setLoading(true);
    try {
      const r = await fetch(`${BACKEND}/api/search`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: q })
      });
      const json = await r.json();
      setRes(json);
    } catch (e) {
      setRes({ error: String(e) });
    } finally {
      setLoading(false);
    }
  }

  return (
    <SafeAreaView style={styles.container}>
      <Text style={styles.title}>Hackit MVP — Test</Text>
      <TextInput style={styles.input} value={q} onChangeText={setQ} />
      <Button title={loading ? "Loading…" : "Lancer recherche"} onPress={runSearch} />
      <ScrollView style={styles.result}>
        <Text>{JSON.stringify(res, null, 2)}</Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, padding: 16 },
  title: { fontSize: 20, fontWeight: "700", marginBottom: 12 },
  input: { borderWidth: 1, borderColor: "#ccc", padding: 8, marginBottom: 8 },
  result: { marginTop: 12 }
});