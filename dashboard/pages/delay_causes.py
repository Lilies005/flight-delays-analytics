"""Dashboard page: delay causes (Person 4).

Reads only two SQL views, all the logic lives in sql/delay_causes.sql:
  v_causes_overall     minutes per cause
  v_causes_by_airline  cause mix per airline
"""
import pandas as pd
import plotly.express as px
import streamlit as st

from database import get_engine


@st.cache_data
def run_query(sql: str) -> pd.DataFrame:
    return pd.read_sql(sql, get_engine())


overall = run_query("SELECT * FROM v_causes_overall").sort_values(
    "total_minutes", ascending=False
)
by_airline = run_query("SELECT * FROM v_causes_by_airline")
delayed_flights = int(
    run_query("SELECT COUNT(*) AS n FROM v_causes_delayed_flights")["n"][0]
)

# ---------------------------------------------------------------- header
st.title("Why are flights delayed?")
st.caption(
    "Delayed = arrival delay of 15 minutes or more. Cancelled and diverted "
    "flights are excluded. Source: 50,000-flight sample."
)

# ---------------------------------------------------------------- KPIs
top = overall.iloc[0]
col1, col2, col3 = st.columns(3)
col1.metric("Delayed flights", f"{delayed_flights:,}")
col2.metric("Total delay minutes", f"{int(overall['total_minutes'].sum()):,}")
col3.metric("Main cause", top["cause"], f"{top['pct_of_total']}% of minutes")

# ---------------------------------------------------------------- chart 1
st.subheader("Delay minutes by cause")
fig1 = px.bar(
    overall,
    x="cause",
    y="total_minutes",
    text="pct_of_total",
    hover_data=["flights_affected", "avg_minutes"],
    labels={"cause": "", "total_minutes": "Delay minutes"},
)
fig1.update_traces(texttemplate="%{text}%", textposition="outside")
st.plotly_chart(fig1, use_container_width=True)
st.caption(
    "Weather is rare but the most severe when it happens: "
    f"{overall.loc[overall['cause'] == 'Weather', 'avg_minutes'].iloc[0]} "
    "minutes per affected flight on average."
)

# ---------------------------------------------------------------- chart 2
st.subheader("Cause mix by airline")
fig2 = px.bar(
    by_airline,
    x="pct_of_airline",
    y="airline",
    color="cause",
    orientation="h",
    category_orders={"cause": list(overall["cause"])},
    labels={"pct_of_airline": "% of the airline's delay minutes", "airline": ""},
)
st.plotly_chart(fig2, use_container_width=True)
st.caption(
    "Shares describe the composition of each airline's delays, "
    "not how punctual it is."
)

# ---------------------------------------------------------------- message
st.info(
    "**Finding:** late aircraft (39%) and airline-controlled causes (32%) "
    "produce about 71% of delay minutes.\n\n"
    "**Recommendation:** add buffer time to tight aircraft rotations, and use "
    "a different fix per airline profile (schedule slack for late-aircraft "
    "airlines, an operations review for airline-cause airlines)."
)
