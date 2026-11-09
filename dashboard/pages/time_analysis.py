"""Person 3 - Time Analysis: when do delays happen most often?"""
import plotly.express as px
import streamlit as st
from db import run_query

st.set_page_config(page_title="Time Analysis", page_icon="🕒", layout="wide")
st.title("🕒 Time Analysis: when do delays happen?")

hour = run_query("SELECT * FROM v_time_by_hour ORDER BY hour_of_day")
week = run_query("SELECT * FROM v_time_by_weekday ORDER BY day_of_week")
heat = run_query("SELECT * FROM v_time_hour_weekday")
month = run_query("SELECT * FROM v_time_monthly_trend ORDER BY year, month")
period = run_query("SELECT * FROM v_time_by_period ORDER BY period")

# ---- KPIs ----
worst_h = hour.sort_values("delay_rate_pct", ascending=False).iloc[0]
worst_d = week.sort_values("delay_rate_pct", ascending=False).iloc[0]
overall = round(100 * hour.nb_delayed.sum() / hour.nb_flights.sum(), 2)
k1, k2, k3 = st.columns(3)
k1.metric("Overall delay rate", f"{overall} %")
k2.metric("Worst hour", f"{int(worst_h.hour_of_day):02d}:00", f"{worst_h.delay_rate_pct} %", delta_color="inverse")
k3.metric("Worst weekday", worst_d.day_name, f"{worst_d.delay_rate_pct} %", delta_color="inverse")

# ---- Hour and weekday ----
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

# ---- Heatmap ----
names = {1: "Mon", 2: "Tue", 3: "Wed", 4: "Thu", 5: "Fri", 6: "Sat", 7: "Sun"}
pivot = heat.pivot(index="day_of_week", columns="hour_of_day", values="delay_rate_pct").sort_index()
pivot.index = [names[i] for i in pivot.index]
fig = px.imshow(pivot, aspect="auto", color_continuous_scale="Reds",
                labels={"x": "Hour", "y": "Day", "color": "Delay rate (%)"},
                title="Delay rate by hour and weekday (cells with fewer than 30 flights are blank)")
st.plotly_chart(fig, use_container_width=True)

# ---- Monthly trend ----
month["period"] = month.year.astype(str) + "-" + month.month.astype(str).str.zfill(2)
fig = px.line(month, x="period", y="delay_rate_pct", markers=True,
              labels={"period": "Month", "delay_rate_pct": "Delay rate (%)"},
              title="Monthly delay rate")
st.plotly_chart(fig, use_container_width=True)
st.caption("Change versus the previous month (computed with LAG):")
st.dataframe(month[["period", "nb_flights", "delay_rate_pct", "prev_month_rate_pct", "change_pts"]],
             use_container_width=True, hide_index=True)

# ---- Time-of-day buckets ----
st.subheader("Time-of-day summary")
st.dataframe(period, use_container_width=True, hide_index=True)