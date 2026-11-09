"""Person 5 - Cancellations: when and why are flights cancelled?"""
import os

import pandas as pd
import plotly.express as px
import streamlit as st
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

load_dotenv()

st.set_page_config(page_title="Cancellations - Flight Delays", layout="wide")

st.title("Cancellations")
st.caption(
    "Cancellation rate = cancelled flights / all scheduled flights. "
    "Cancelled flights have no delay values, so they are never used in average-delay calculations."
)

# ---------- Connexion a PostgreSQL (variables du fichier .env) ----------
REQUIRED_ENV = ["DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD"]
missing = [k for k in REQUIRED_ENV if not os.getenv(k)]
if missing:
    st.error(
        f"Missing variables in .env: {', '.join(missing)}. "
        "Copy .env.example to .env and fill it in."
    )
    st.stop()


@st.cache_resource
def get_engine():
    url = URL.create(
        "postgresql+psycopg2",
        username=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        host=os.getenv("DB_HOST"),
        port=int(os.getenv("DB_PORT")),
        database=os.getenv("DB_NAME"),
    )
    return create_engine(url)


@st.cache_data(ttl=600)
def load_view(name: str) -> pd.DataFrame:
    with get_engine().connect() as conn:
        return pd.read_sql(text(f"SELECT * FROM {name}"), conn)


try:
    month = load_view("v_cancel_by_month").sort_values(["year", "month"])
    reasons = load_view("v_cancel_reasons").sort_values("nb_cancelled", ascending=False)
    airline = load_view("v_cancel_by_airline").sort_values("cancel_rate_pct", ascending=False)
    rm = load_view("v_cancel_reason_month")
except Exception as exc:
    st.error(f"Could not read the v_cancel_* views. Did you run sql/cancellations.sql? Details: {exc}")
    st.stop()

# ---------- KPIs ----------
total = int(month.nb_flights.sum())
canc = int(month.nb_cancelled.sum())
worst_m = month.sort_values("cancel_rate_pct", ascending=False).iloc[0]
top_reason = reasons.iloc[0]

k1, k2, k3 = st.columns(3)
k1.metric("Cancellation rate", f"{round(100 * canc / total, 2)} %", f"{canc:,} flights", delta_color="off")
k2.metric("Worst month", f"{int(worst_m.year)}-{int(worst_m.month):02d}", f"{worst_m.cancel_rate_pct} %", delta_color="inverse")
k3.metric("Main reason", top_reason.reason, f"{top_reason.share_pct} % of cancellations", delta_color="off")

# ---------- Monthly trend and reasons ----------
month["period"] = month.year.astype(str) + "-" + month.month.astype(str).str.zfill(2)
left, right = st.columns(2)
with left:
    fig = px.line(month, x="period", y="cancel_rate_pct", markers=True,
                  labels={"period": "Month", "cancel_rate_pct": "Cancellation rate (%)"},
                  title="Monthly cancellation rate")
    st.plotly_chart(fig, use_container_width=True)
with right:
    fig = px.bar(reasons, x="reason", y="nb_cancelled", text="share_pct",
                 labels={"reason": "Reason", "nb_cancelled": "Cancelled flights"},
                 title="Cancellation reasons")
    fig.update_traces(texttemplate="%{text} %")
    st.plotly_chart(fig, use_container_width=True)

# ---------- Reason x month ----------
fig = px.bar(rm, x="month", y="nb_cancelled", color="reason", barmode="stack",
             labels={"month": "Month", "nb_cancelled": "Cancelled flights"},
             title="Reasons by month")
st.plotly_chart(fig, use_container_width=True)

# ---------- Airlines ----------
st.subheader("Cancellation rate by airline")
fig = px.bar(airline.sort_values("cancel_rate_pct"), x="cancel_rate_pct", y="airline_name", orientation="h",
             labels={"cancel_rate_pct": "Cancellation rate (%)", "airline_name": ""})
st.plotly_chart(fig, use_container_width=True)
st.dataframe(airline[["worst_rank", "airline_name", "nb_flights", "nb_cancelled", "cancel_rate_pct", "vs_overall_pts"]],
             use_container_width=True, hide_index=True)