# Benchmark Dashboard

Streamlit dashboard that visualizes event latency, throughput, and payload size per CDC approach.

## Run

```bash
pip install -r requirements.txt
streamlit run app.py
```

Open `http://localhost:8501`.

## Data Source

Reads from PostgreSQL table `benchmark_events`.
