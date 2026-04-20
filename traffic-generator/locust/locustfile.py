import os
import random
import time

import psycopg2
from faker import Faker
from locust import User, between, events, task

fake = Faker()

PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_DB = os.getenv("PG_DB", "appdb")
PG_USER = os.getenv("PG_USER", "postgres")
PG_PASSWORD = os.getenv("PG_PASSWORD", "postgres")
PG_SSLMODE = os.getenv("PG_SSLMODE", "disable")


def dsn() -> str:
    return (
        f"host={PG_HOST} port={PG_PORT} dbname={PG_DB} "
        f"user={PG_USER} password={PG_PASSWORD} sslmode={PG_SSLMODE}"
    )


class PostgresOrderUser(User):
    wait_time = between(0.01, 0.2)

    def on_start(self):
        self.conn = psycopg2.connect(dsn())
        self.conn.autocommit = True

    def on_stop(self):
        self.conn.close()

    def _fire_event(self, request_type, name, start_time, exception=None):
        response_time = (time.time() - start_time) * 1000
        if exception:
            events.request.fire(
                request_type=request_type,
                name=name,
                response_time=response_time,
                response_length=0,
                exception=exception,
            )
        else:
            events.request.fire(
                request_type=request_type,
                name=name,
                response_time=response_time,
                response_length=0,
            )

    @task(7)
    def create_order(self):
        amount = round(random.uniform(20, 2000), 2)
        status = random.choice(["NEW", "PAID", "SHIPPED"])
        customer = fake.uuid4()
        start_time = time.time()

        try:
            with self.conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO orders (customer_id, amount, status)
                    VALUES (%s, %s, %s)
                    """,
                    (customer, amount, status),
                )
            self._fire_event("SQL", "INSERT order", start_time)
        except Exception as e:
            self._fire_event("SQL", "INSERT order", start_time, exception=e)

    @task(3)
    def update_order(self):
        new_status = random.choice(["PAID", "SHIPPED", "CANCELLED"])
        start_time = time.time()

        try:
            with self.conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE orders
                    SET status = %s
                    WHERE id IN (
                      SELECT id FROM orders ORDER BY random() LIMIT 1
                    )
                    """,
                    (new_status,),
                )
            self._fire_event("SQL", "UPDATE order", start_time)
        except Exception as e:
            self._fire_event("SQL", "UPDATE order", start_time, exception=e)
