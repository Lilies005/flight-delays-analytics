"""Person 3 - Time Analysis: when do delays happen most often?"""
import os

import pandas as pd
import plotly.express as px
import streamlit as st
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

load_dotenv()

st.set_page_config(page_title="Time Analysis - Flight Delays", layout="wide")

st.title("Time Analysis")
st.caption(
    "A flight is delayed when it arrives 15 minutes or more after schedule. "
    "Cancelled and diverted flights are excluded. Hours are scheduled departure hours."
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
    hour = load_view("v_time_by_hour").sort_values("hour_of_day")
    week = load_view("v_time_by_weekday").sort_values("day_of_week")
    heat = load_view("v_time_hour_weekday")
    month = load_view("v_time_monthly_trend").sort_values(["year", "month"])
    period = load_view("v_time_by_period").sort_values("period")
except Exception as exc:
    st.error(f"Could not read the v_time_* views. Did you run sql/time.sql? Details: {exc}")
    st.stop()

# ---------- KPIs ----------
worst_h = hour.sort_values("delay_rate_pct", ascending=False).iloc[0]
worst_d = week.sort_values("delay_rate_pct", ascending=False).iloc[0]
overall = round(100 * hour.nb_delayed.sum() / hour.nb_flights.sum(), 2)

k1, k2, k3 = st.columns(3)
k1.metric("Overall delay rate", f"{overall} %")
k2.metric("Worst hour", f"{int(worst_h.hour_of_day):02d}:00", f"{worst_h.delay_rate_pct} %", delta_color="inverse")
k3.metric("Worst weekday", worst_d.day_name, f"{worst_d.delay_rate_pct} %", delta_color="inverse")

# ---------- Hour and weekday ----------
left, right = st.columns(2)
with left:
    fig = px.bar(hour, x="hour_of_day", y="delay_rate_pct",
                 labels={"hour_of_day": "Scheduled departure hour", "delay_rate_pct": "Delay rate (%)"},
                 title="Delay rate by hour of day")
    fig.add_hline(y=overall, line_dash="dash", annotation_text=f"Overall {overall} %")
    st.plotly_chart(fig, use_container_width=True)
with right:
    fig = px.bar(week, x="day_name", y="delay_rate_pct",
                 labels={"day_name": "Day of week", "delay_rate_pct": "Delay rate (%)"},
                 title="Delay rate by day of week")
    fig.add_hline(y=overall, line_dash="dash")
    st.plotly_chart(fig, use_container_width=True)

# ---------- Heatmap ----------
names = {1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"}
pivot = heat.pivot(index="day_of_week", columns="hour_of_day", values="delay_rate_pct").sort_index()
pivot.index = [names[i] for i in pivot.index]
fig = px.imshow(pivot, aspect="auto", color_continuous_scale="Reds",
                labels={"x": "Hour", "y": "Day", "color": "Delay rate (%)"},
                title="Delay rate by hour and weekday (blank = fewer than 30 flights)")
st.plotly_chart(fig, use_container_width=True)

# ---------- Monthly trend ----------
month["period"] = month.year.astype(str) + "-" + month.month.astype(str).str.zfill(2)
fig = px.line(month, x="period", y="delay_rate_pct", markers=True,
              labels={"period": "Month", "delay_rate_pct": "Delay rate (%)"},
              title="Monthly delay rate")
st.plotly_chart(fig, use_container_width=True)
st.caption("Change versus the previous month (computed with LAG):")
st.dataframe(month[["period", "nb_flights", "delay_rate_pct", "prev_month_rate_pct", "change_pts"]],
             use_container_width=True, hide_index=True)

# ---------- Time-of-day buckets ----------
st.subheader("Time-of-day summay")
st.dataframe(period, use_container_width=True, hide_index=True)