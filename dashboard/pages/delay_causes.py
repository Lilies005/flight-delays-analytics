"""Dashboard page: delay causes (Person 4).

The logic lives in SQL (sql/delay_causes.sql). This page reads two small
pre-aggregated views and only re-sums their rows for the filters chosen
in the sidebar:
  v_causes_airline_month   minutes and flights per airline, month and cause
  v_causes_delayed_counts  delayed flights and delay minutes per airline and month
"""
import pandas as pd
import plotly.express as px
import streamlit as st

from database import get_engine

MONTHS = {1: "Jan", 2: "Feb", 3: "Mar", 4: "Apr", 5: "May", 6: "Jun",
          7: "Jul", 8: "Aug", 9: "Sep", 10: "Oct", 11: "Nov", 12: "Dec"}

# One fixed color per cause, so a cause looks the same in every chart
CAUSE_COLORS = {
    "Late aircraft": "#6C5CE7",
    "Airline": "#00B894",
    "Air system (NAS)": "#0984E3",
    "Weather": "#FDCB6E",
    "Security": "#D63031",
}
MIN_FLIGHTS = 30  # team rule: do not trust shares computed on fewer flights


@st.cache_data
def run_query(sql: str) -> pd.DataFrame:
    return pd.read_sql(sql, get_engine())


causes = run_query("SELECT * FROM v_causes_airline_month")
counts = run_query("SELECT * FROM v_causes_delayed_counts")

# ---------------------------------------------------------------- header
st.title("Why are flights delayed?")
st.caption(
    "Delayed = arrival delay of 15 minutes or more. Cancelled and diverted "
    "flights are excluded. Source: 50,000-flight sample."
)

# ---------------------------------------------------------------- filters
st.sidebar.header("Delay causes: filters")
airline = st.sidebar.selectbox("Airline", ["All"] + sorted(counts["airline"].unique()))
month = st.sidebar.selectbox(
    "Month",
    ["All"] + sorted(counts["month"].unique()),
    format_func=lambda m: MONTHS.get(m, m),
)


def pick(df, by_airline=True, by_month=True):
    """Keep only the rows matching the filters chosen in the sidebar."""
    if by_airline and airline != "All":
        df = df[df["airline"] == airline]
    if by_month and month != "All":
        df = df[df["month"] == month]
    return df


sel_causes = pick(causes)
sel_counts = pick(counts)
delayed_flights = int(sel_counts["delayed_flights"].sum())
if delayed_flights == 0:
    st.warning("No delayed flights for this selection.")
    st.stop()
total_minutes = int(sel_counts["delay_minutes"].sum())

by_cause = (
    sel_causes.groupby("cause", as_index=False)
    .agg(total_minutes=("total_minutes", "sum"),
         flights_affected=("flights_affected", "sum"))
)
by_cause["avg_minutes"] = (by_cause["total_minutes"] / by_cause["flights_affected"]).round(1)
by_cause["pct"] = (100 * by_cause["total_minutes"] / by_cause["total_minutes"].sum()).round(1)
by_cause = by_cause.sort_values("total_minutes", ascending=False)
top = by_cause.iloc[0]

# ---------------------------------------------------------------- KPIs
k1, k2, k3, k4 = st.columns(4)
k1.metric("Delayed flights", f"{delayed_flights:,}")
k2.metric("Delay minutes", f"{total_minutes:,}")
k3.metric("Average per delayed flight", f"{total_minutes / delayed_flights:.0f} min")
k4.metric("Main cause", top["cause"], f"{top['pct']}% of minutes", delta_color="off")

if int(by_cause["total_minutes"].sum()) == total_minutes:
    st.caption("Check passed: the five causes add up exactly to the arrival delay minutes of this selection.")
else:
    st.warning("The causes do not add up to the arrival delay for this selection.")
if delayed_flights < MIN_FLIGHTS:
    st.warning(
        f"Only {delayed_flights} delayed flights in this selection "
        f"(team minimum is {MIN_FLIGHTS}): read the shares with caution."
    )

st.divider()

# ---------------------------------------------------------------- row 1
left, right = st.columns(2)

with left:
    st.subheader("Where the delay minutes come from")
    fig = px.bar(
        by_cause, x="total_minutes", y="cause", orientation="h",
        color="cause", color_discrete_map=CAUSE_COLORS, text="pct",
        category_orders={"cause": list(by_cause["cause"])},
        labels={"total_minutes": "Delay minutes", "cause": ""},
    )
    fig.update_traces(texttemplate="%{text}%", textposition="outside")
    fig.update_yaxes(autorange="reversed")
    fig.update_layout(showlegend=False, height=380, margin=dict(t=10))
    st.plotly_chart(fig, use_container_width=True)

with right:
    st.subheader("Frequent or severe?")
    fig = px.scatter(
        by_cause, x="flights_affected", y="avg_minutes", size="total_minutes",
        color="cause", color_discrete_map=CAUSE_COLORS, size_max=55, text="cause",
        labels={"flights_affected": "Flights affected",
                "avg_minutes": "Average minutes when it happens"},
    )
    fig.update_traces(textposition="top center")
    fig.update_yaxes(rangemode="tozero")
    fig.update_layout(showlegend=False, height=380, margin=dict(t=10))
    st.plotly_chart(fig, use_container_width=True)
    st.caption("Bubble size = total delay minutes. High and to the left = rare but severe.")

# ---------------------------------------------------------------- row 2
title = "Cause mix by airline"
if month != "All":
    title += f" ({MONTHS[month]})"
st.subheader(title)
mix = pick(causes, by_airline=False).groupby(["airline", "cause"], as_index=False)["total_minutes"].sum()
mix["pct"] = (100 * mix["total_minutes"] / mix.groupby("airline")["total_minutes"].transform("sum")).round(1)
airline_order = list(mix.groupby("airline")["total_minutes"].sum().sort_values().index)
fig = px.bar(
    mix, x="pct", y="airline", color="cause", orientation="h",
    color_discrete_map=CAUSE_COLORS,
    category_orders={"airline": airline_order, "cause": list(CAUSE_COLORS)},
    labels={"pct": "% of the airline's delay minutes", "airline": "", "cause": ""},
)
fig.update_layout(height=520, legend=dict(orientation="h", y=-0.15))
st.plotly_chart(fig, use_container_width=True)
st.caption(
    "Airlines are sorted by total delay minutes (largest at the top). "
    "Shares describe the composition of delays, not how punctual an airline is."
)

# ---------------------------------------------------------------- row 3
title = "Delay minutes by month"
if airline != "All":
    title += f" ({airline})"
st.subheader(title)
trend = pick(causes, by_month=False).groupby(["month", "cause"], as_index=False)["total_minutes"].sum()
trend["month_name"] = trend["month"].map(MONTHS)
fig = px.bar(
    trend, x="month_name", y="total_minutes", color="cause",
    color_discrete_map=CAUSE_COLORS,
    category_orders={"month_name": [MONTHS[m] for m in sorted(trend["month"].unique())],
                     "cause": list(CAUSE_COLORS)},
    labels={"month_name": "", "total_minutes": "Delay minutes", "cause": ""},
)
fig.update_layout(height=380, legend=dict(orientation="h", y=-0.2))
st.plotly_chart(fig, use_container_width=True)
st.caption("Each month holds a few thousand sampled flights, so read small differences with caution.")

# ---------------------------------------------------------------- message
severe = by_cause.sort_values("avg_minutes", ascending=False).iloc[0]
top2 = by_cause.head(2)
st.info(
    f"**Finding for this selection:** {' and '.join(top2['cause'])} produce "
    f"{top2['pct'].sum():.0f}% of the delay minutes. {severe['cause']} is the most "
    f"severe when it happens ({severe['avg_minutes']:.0f} minutes per affected flight, "
    f"{int(severe['flights_affected']):,} flights)."
)
st.success(
    "**Recommendation (all airlines, whole sample):** most delay comes from late "
    "aircraft and airline-controlled causes, so add buffer time to tight aircraft "
    "rotations and use a different fix per airline profile (schedule slack for "
    "late-aircraft airlines, an operations review for airline-cause airlines)."
)
