FROM locustio/locust:2.29.1
COPY requirements.txt /mnt/locust/requirements.txt
RUN pip install --no-cache-dir -r /mnt/locust/requirements.txt
COPY locustfile.py /mnt/locust/locustfile.py
