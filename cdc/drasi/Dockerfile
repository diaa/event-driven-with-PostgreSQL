FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY sink_recorder.py .

EXPOSE 8090
CMD ["uvicorn", "sink_recorder:app", "--host", "0.0.0.0", "--port", "8090"]
