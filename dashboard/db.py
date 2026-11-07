import os
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine

load_dotenv()

def get_engine():
    url = (
        f"postgresql+psycopg2://{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}"
        f"@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}"
    )
    return create_engine(url)

def load_view(view_name: str) -> pd.DataFrame:
    """Lit une vue SQL entière et la renvoie en DataFrame."""
    df = pd.read_sql(f"SELECT * FROM {view_name}", get_engine())
    # PostgreSQL renvoie du numeric (Decimal) : on convertit en float pour les graphiques
    for col in df.columns:
        if df[col].dtype == "object":
            try:
                df[col] = df[col].astype(float)
            except (ValueError, TypeError):
                pass
    return df