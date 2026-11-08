
import os
from pathlib import Path

from dotenv import load_dotenv
from sqlalchemy import create_engine, URL

# Charger le fichier .env situé à la racine du projet
BASE_DIR = Path(__file__).resolve().parents[1]
load_dotenv(BASE_DIR / ".env")


def get_engine():
    connection_url = URL.create(
        drivername="postgresql+psycopg2",
        username=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        database=os.getenv("DB_NAME")
    )

    return create_engine(connection_url, pool_pre_ping=True)
