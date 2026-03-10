import os

import pandas as pd
import plotly.express as px
import psycopg2
import streamlit as st

st.set_page_config(page_title="CDC Benchmark Dashboard", layout="wide")
st.title("PostgreSQL CDC Benchmark Dashboard")
st.caption("Compare wal2json custom consumer, Debezium+Kafka, and Drasi side-by-side.")

PG_HOST = os.getenv("PG_HOST", "postgres")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_USER = os.getenv("PG_USER", "postgres")
PG_PASSWORD = os.getenv("PG_PASSWORD", "postgres")
PG_DB = os.getenv("PG_DB", "appdb")

LOC_TABLE = {
    "wal2json": "cdc/wal2json-consumer",
    "debezium": "cdc/debezium-kafka",
    "drasi": "cdc/drasi",
}


@st.cache_data(ttl=5)
def load_data() -> pd.DataFrame:
    conn = psycopg2.connect(
        host=PG_HOST,
        port=PG_PORT,
        user=PG_USER,
        password=PG_PASSWORD,
        dbname=PG_DB,
    )
    sql = """
      SELECT approach, source_event_id, source_commit_ts, observed_at,
             latency_ms, payload_bytes, operation
      FROM benchmark_events
      WHERE observed_at > now() - interval '1 day'
      ORDER BY observed_at DESC
      LIMIT 200000
    """
    df = pd.read_sql(sql, conn)
    conn.close()
    if not df.empty:
        df["observed_at"] = pd.to_datetime(df["observed_at"])
    return df


def complexity_df() -> pd.DataFrame:
    rows = []
    for name, path in LOC_TABLE.items():
        loc = 0
        for root, _, files in os.walk(path):
            for file in files:
                if file.endswith(".py") or file.endswith(".sql") or file.endswith(".md"):
                    file_path = os.path.join(root, file)
                    with open(file_path, "r", encoding="utf-8") as f:
                        loc += sum(1 for _ in f)
        rows.append({"approach": name, "approx_loc": loc})
    return pd.DataFrame(rows)


try:
    df = load_data()
except Exception as exc:
    st.error(f"Could not query benchmark data: {exc}")
    st.stop()

if df.empty:
    st.warning("No benchmark data found yet. Start traffic generation and consumers first.")
    st.stop()

approaches = sorted(df["approach"].dropna().unique().tolist())
selected = st.multiselect("Approaches", approaches, default=approaches)
filtered = df[df["approach"].isin(selected)]

c1, c2, c3 = st.columns(3)
with c1:
    st.metric("Events observed", f"{len(filtered):,}")
with c2:
    st.metric("Median latency (ms)", f"{filtered['latency_ms'].median():.2f}")
with c3:
    st.metric("P95 latency (ms)", f"{filtered['latency_ms'].quantile(0.95):.2f}")

lat = (
    filtered.dropna(subset=["latency_ms"])
    .groupby([pd.Grouper(key="observed_at", freq="5s"), "approach"], as_index=False)["latency_ms"]
    .median()
)
fig_latency = px.line(
    lat,
    x="observed_at",
    y="latency_ms",
    color="approach",
    title="Median Latency Over Time (5s buckets)",
)
st.plotly_chart(fig_latency, use_container_width=True)

th = (
    filtered.groupby([pd.Grouper(key="observed_at", freq="5s"), "approach"], as_index=False)
    .size()
    .rename(columns={"size": "events"})
)
fig_throughput = px.line(
    th,
    x="observed_at",
    y="events",
    color="approach",
    title="Observed Throughput Over Time (events per 5s)",
)
st.plotly_chart(fig_throughput, use_container_width=True)

payload = (
    filtered.dropna(subset=["payload_bytes"])
    .groupby("approach", as_index=False)["payload_bytes"]
    .mean()
)
fig_payload = px.bar(payload, x="approach", y="payload_bytes", title="Average Payload Size (bytes)")
st.plotly_chart(fig_payload, use_container_width=True)

st.subheader("Implementation Complexity (Approximate LOC)")
st.dataframe(complexity_df(), use_container_width=True)

st.subheader("Raw Event Samples")
st.dataframe(filtered.head(200), use_container_width=True)
