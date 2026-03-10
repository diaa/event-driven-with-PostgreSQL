import os
import random
from datetime import datetime, timezone

import psycopg2
from faker import Faker
from locust import User, between, task

fake = Faker()

PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = int(os.getenv("PG_PORT", "5432"))
PG_DB = os.getenv("PG_DB", "appdb")
PG_USER = os.getenv("PG_USER", "postgres")
PG_PASSWORD = os.getenv("PG_PASSWORD", "postgres")


def dsn() -> str:
    return (
        f"host={PG_HOST} port={PG_PORT} dbname={PG_DB} "
        f"user={PG_USER} password={PG_PASSWORD}"
    )


class PostgresOrderUser(User):
    wait_time = between(0.01, 0.2)

    def on_start(self):
        self.conn = psycopg2.connect(dsn())
        self.conn.autocommit = True

    def on_stop(self):
        self.conn.close()

    @task(7)
    def create_order(self):
        amount = round(random.uniform(20, 2000), 2)
        status = random.choice(["NEW", "PAID", "SHIPPED"])
        customer = fake.uuid4()

        with self.conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO orders (customer_id, amount, status)
                VALUES (%s, %s, %s)
                """,
                (customer, amount, status),
            )

    @task(3)
    def update_order(self):
        new_status = random.choice(["PAID", "SHIPPED", "CANCELLED"])
        with self.conn.cursor() as cur:
            cur.execute(
                """
                UPDATE orders
                SET status = %s,
                    updated_at = %s
                WHERE id IN (
                  SELECT id FROM orders ORDER BY random() LIMIT 1
                )
                """,
                (new_status, datetime.now(timezone.utc)),
            )
