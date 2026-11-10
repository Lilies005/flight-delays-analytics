"""Person 3 - Time Analysis: when do delays happen most often? """
import numpy as np
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

from database import get_engine

st.set_page_config(page_title="Time Analysis - Flight Delays", layout="wide")

MONTHS = {1: "Jan", 2: "Feb", 3: "Mar", 4: "Apr", 5: "May", 6: "Jun",
          7: "Jul", 8: "Aug", 9: "Sep", 10: "Oct", 11: "Nov", 12: "Dec"}
SIGNAL_COLORS = {"Above overall": "#D63031", "In line": "#B2BEC3", "Below overall": "#00B894"}
MIN_FLIGHTS = 30      # team rule
HEATMAP_MIN = 30    # same as v_time_hour_weekday

ALLOWED_VIEWS = {
    "v_time_cube", "v_time_overall", "v_time_by_hour", "v_time_by_weekday",
    "v_time_monthly_trend", "v_time_by_period", "v_time_quality",
}


@st.cache_data(ttl=600)
def load_view(name: str) -> pd.DataFrame:
    if name not in ALLOWED_VIEWS:
        raise ValueError(f"View not allowed: {name}")
    df = pd.read_sql(f"SELECT * FROM {name}", get_engine())
    for col in df.columns:  # PostgreSQL numeric -> Decimal -> float
        if df[col].dtype == object:
            try:
                df[col] = pd.to_numeric(df[col])
            except (ValueError, TypeError):
                pass
    return df


def wilson(x, n, z=1.96):
    """95% Wilson interval in %, same formula as rate_ci_low/high in SQL."""
    x = np.asarray(x, dtype=float)
    n = np.asarray(n, dtype=float)
    with np.errstate(divide="ignore", invalid="ignore"):
        p = x / n
        centre = p + z**2 / (2 * n)
        half = z * np.sqrt(p * (1 - p) / n + z**2 / (4 * n**2))
        d = 1 + z**2 / n
        return 100 * (centre - half) / d, 100 * (centre + half) / d


def summarise(df, by, overall_rate, min_flights=MIN_FLIGHTS):
    """Delay rate, interval, severity and signal per group; groups under the minimum are dropped."""
    g = df.groupby(by, as_index=False)[["nb_flights", "nb_delayed", "late_minutes"]].sum()
    g = g[g["nb_flights"] >= min_flights].copy()
    g["delay_rate_pct"] = 100 * g["nb_delayed"] / g["nb_flights"]
    g["ci_lo"], g["ci_hi"] = wilson(g["nb_delayed"], g["nb_flights"])
    g["avg_late_min"] = g["late_minutes"] / g["nb_delayed"].replace(0, np.nan)
    g["signal"] = np.where(g["ci_lo"] > overall_rate, "Above overall",
                           np.where(g["ci_hi"] < overall_rate, "Below overall", "In line"))
    return g


def same(a, b):
    return bool(np.array_equal(np.asarray(a, dtype=float), np.asarray(b, dtype=float)))


try:
    cube = load_view("v_time_cube")
    overall_v = load_view("v_time_overall").iloc[0]
    hour_v = load_view("v_time_by_hour").sort_values("hour_of_day")
    week_v = load_view("v_time_by_weekday").sort_values("day_of_week")
    month_v = load_view("v_time_monthly_trend")
    quality = load_view("v_time_quality").iloc[0]
except Exception as exc:
    st.error(f"Could not read the v_time_* views. Did you run sql/time.sql? Details: {exc}")
    st.stop()

# ---------------------------------------------------------------- header
st.title("When do delays happen?")
st.caption(
    "A flight is delayed when it arrives 15 minutes or more after schedule. Cancelled and diverted "
    "flights are excluded. Hours are scheduled departure hours."
)

# ---------------------------------------------------------------- filters
st.sidebar.header("Time analysis: filters")
airline = st.sidebar.selectbox("Airline", ["All"] + sorted(cube["airline_name"].unique()))
month = st.sidebar.selectbox(
    "Month", ["All"] + [int(m) for m in sorted(cube["month"].unique())],
    format_func=lambda m: MONTHS.get(m, m),
)


def pick(df, by_month=True):
    if airline != "All":
        df = df[df["airline_name"] == airline]
    if by_month and month != "All":
        df = df[df["month"] == month]
    return df


sel = pick(cube)
n_flights = int(sel["nb_flights"].sum())
if n_flights == 0:
    st.warning("No eligible flights for this selection.")
    st.stop()
n_delayed = int(sel["nb_delayed"].sum())
rate = 100 * n_delayed / n_flights
ci_lo, ci_hi = wilson(n_delayed, n_flights)

hours = summarise(sel, ["hour_of_day"], rate)
days = summarise(sel, ["day_of_week", "day_name"], rate).sort_values("day_of_week")
periods = summarise(sel, ["period_order", "period"], rate).sort_values("period_order")
pc = pick(cube, by_month=False)
trend = summarise(pc, ["year", "month"], 100 * pc["nb_delayed"].sum() / max(pc["nb_flights"].sum(), 1))
trend = trend.sort_values(["year", "month"])
multi_year = trend["year"].nunique() > 1
trend["label"] = [f"{int(y)}-{int(m):02d}" if multi_year else MONTHS[int(m)]
                  for y, m in zip(trend["year"], trend["month"])]
trend["change_pts"] = trend["delay_rate_pct"].diff()

# ---------------------------------------------------------------- KPIs
k1, k2, k3, k4 = st.columns(4)
k1.metric("Delay rate", f"{rate:.2f} %", f"{n_delayed:,} of {n_flights:,} flights", delta_color="off")
k1.caption(f"95% interval: {ci_lo:.2f}% to {ci_hi:.2f}%")
if len(hours):
    wh = hours.loc[hours["delay_rate_pct"].idxmax()]
    k2.metric("Worst hour", f"{int(wh['hour_of_day']):02d}:00", f"{wh['delay_rate_pct']:.2f} %", delta_color="inverse")
if len(days):
    wd = days.loc[days["delay_rate_pct"].idxmax()]
    k3.metric("Worst weekday", wd["day_name"], f"{wd['delay_rate_pct']:.2f} %", delta_color="inverse")
if len(periods):
    wp = periods.loc[periods["delay_rate_pct"].idxmax()]
    name, hours_txt = wp["period"].split(" (")
    k4.markdown(
        '<div style="line-height:1.25">'
        '<div style="font-size:0.875rem;opacity:0.7">Worst period</div>'
        f'<div style="font-size:1.6rem;font-weight:600">{name}<br>'
        f'<span style="font-size:1rem;font-weight:400;opacity:0.7">({hours_txt}</span></div>'
        f'<div style="font-size:0.875rem;color:#D63031">&#9650; {wp["delay_rate_pct"]:.2f} %</div>'
        '</div>',
        unsafe_allow_html=True,
    )

if n_flights < 1000:
    st.warning(f"Only {n_flights:,} eligible flights in this selection: read small differences with caution.")
st.caption("Monthly trend shows all months; the month filter applies to everything else. "
           "Red bars: the 95% interval (shown on hover) is entirely above the selection's rate.")
st.divider()

# ---------------------------------------------------------------- hour and weekday
left, right = st.columns(2)
with left:
    st.subheader("By hour of day")
    fig = px.bar(hours, x="hour_of_day", y="delay_rate_pct", color="signal",
                 color_discrete_map=SIGNAL_COLORS,
                 category_orders={"signal": list(SIGNAL_COLORS)},
                 custom_data=["nb_flights", "avg_late_min", "ci_lo", "ci_hi"],
                 labels={"hour_of_day": "Scheduled departure hour", "delay_rate_pct": "Delay rate (%)", "signal": ""})
    fig.update_traces(hovertemplate="%{x}:00<br>Delay rate: %{y:.1f}%<br>Flights: %{customdata[0]:,}"
                                    "<br>Avg delay when late: %{customdata[1]:.0f} min"
                                    "<br>95% interval: %{customdata[2]:.1f}% to %{customdata[3]:.1f}%<extra></extra>")
    fig.add_hline(y=rate, line_dash="dash", annotation_text=f"Selection {rate:.1f} %")
    fig.update_layout(height=380, margin=dict(t=10), legend=dict(orientation="h", y=-0.2))
    st.plotly_chart(fig, use_container_width=True)
with right:
    st.subheader("By day of week")
    fig = px.bar(days, x="day_name", y="delay_rate_pct", color="signal",
                 color_discrete_map=SIGNAL_COLORS,
                 category_orders={"signal": list(SIGNAL_COLORS), "day_name": list(days["day_name"])},
                 custom_data=["nb_flights", "avg_late_min", "ci_lo", "ci_hi"],
                 labels={"day_name": "", "delay_rate_pct": "Delay rate (%)", "signal": ""})
    fig.update_traces(hovertemplate="%{x}<br>Delay rate: %{y:.1f}%<br>Flights: %{customdata[0]:,}"
                                    "<br>Avg delay when late: %{customdata[1]:.0f} min"
                                    "<br>95% interval: %{customdata[2]:.1f}% to %{customdata[3]:.1f}%<extra></extra>")
    fig.add_hline(y=rate, line_dash="dash")
    fig.update_layout(height=380, margin=dict(t=10), legend=dict(orientation="h", y=-0.2))
    st.plotly_chart(fig, use_container_width=True)

# ---------------------------------------------------------------- heatmap
st.subheader("Hour and weekday")
hm = sel.groupby(["day_of_week", "day_name", "hour_of_day"], as_index=False)[["nb_flights", "nb_delayed"]].sum()
hm = hm[hm["nb_flights"] >= HEATMAP_MIN]
if len(hm):
    day_order = (cube[["day_of_week", "day_name"]].drop_duplicates().sort_values("day_of_week")["day_name"].tolist())
    hm["rate"] = 100 * hm["nb_delayed"] / hm["nb_flights"]
    z = hm.pivot(index="day_name", columns="hour_of_day", values="rate").reindex(index=day_order, columns=range(24))
    f = hm.pivot(index="day_name", columns="hour_of_day", values="nb_flights").reindex(index=day_order, columns=range(24))
    fig = go.Figure(go.Heatmap(
        z=z.values, x=[f"{h:02d}" for h in range(24)], y=day_order, customdata=f.values,
        colorscale="Reds", colorbar=dict(title="%"), hoverongaps=False,
        hovertemplate="%{y} %{x}:00<br>Delay rate: %{z:.1f}%<br>Flights: %{customdata:,}<extra></extra>"))
    fig.update_yaxes(autorange="reversed")
    fig.update_layout(height=360, margin=dict(t=10), xaxis_title="Scheduled departure hour")
    st.plotly_chart(fig, use_container_width=True)
    st.caption(f"Blank = fewer than {HEATMAP_MIN} flights.")
else:
    st.info(f"No hour and weekday combination reaches {HEATMAP_MIN} flights for this selection.")

# ---------------------------------------------------------------- trend and periods
left, right = st.columns(2)
with left:
    st.subheader("Monthly delay rate")
    if len(trend):
        fig = px.line(trend, x="label", y="delay_rate_pct", markers=True,
                      labels={"label": "", "delay_rate_pct": "Delay rate (%)"})
        fig.update_yaxes(rangemode="tozero")
        fig.update_layout(height=380, margin=dict(t=10))
        st.plotly_chart(fig, use_container_width=True)
        st.dataframe(trend[["label", "nb_flights", "delay_rate_pct", "change_pts"]]
                     .rename(columns={"label": "Month", "nb_flights": "Flights", "delay_rate_pct": "Delay rate (%)",
                                      "change_pts": "Change vs previous month (pts)"}),
                     use_container_width=True, hide_index=True,
                     column_config={"Delay rate (%)": st.column_config.NumberColumn(format="%.2f"),
                                    "Change vs previous month (pts)": st.column_config.NumberColumn(format="%+.2f")})
with right:
    st.subheader("Time of day")
    if len(periods):
        fig = px.bar(periods, x="period", y="delay_rate_pct", color="signal",
                     color_discrete_map=SIGNAL_COLORS,
                     category_orders={"signal": list(SIGNAL_COLORS), "period": list(periods["period"])},
                     text=periods["delay_rate_pct"].round(1).astype(str) + "%",
                     labels={"period": "", "delay_rate_pct": "Delay rate (%)", "signal": ""})
        fig.update_layout(height=380, margin=dict(t=10), legend=dict(orientation="h", y=-0.2))
        st.plotly_chart(fig, use_container_width=True)

# ---------------------------------------------------------------- findings
st.divider()
if len(hours) and len(days) and len(periods):
    best_p = periods.loc[periods["delay_rate_pct"].idxmin()]
    best_h = hours.loc[hours["delay_rate_pct"].idxmin()]
    above = hours[hours["signal"] == "Above overall"]["hour_of_day"].astype(int).tolist()
    st.info(
        f"**Finding for this selection:** delays peak at {int(wh['hour_of_day']):02d}:00 "
        f"({wh['delay_rate_pct']:.1f}% against {rate:.1f}% overall) and are lowest at "
        f"{int(best_h['hour_of_day']):02d}:00 ({best_h['delay_rate_pct']:.1f}%). "
        f"The {wp['period']} period is the worst ({wp['delay_rate_pct']:.1f}%) and {best_p['period']} the best "
        f"({best_p['delay_rate_pct']:.1f}%). {wd['day_name']} is the worst weekday ({wd['delay_rate_pct']:.1f}%)."
        + (f" Hours clearly above the overall rate: {', '.join(f'{h:02d}h' for h in above)}." if above else "")
    )
    st.success(
        f"**Recommendation:** add schedule buffer and spare capacity around {int(wh['hour_of_day']):02d}:00 and in the "
        f"{wp['period']} period; suggest {best_p['period']} departures to passengers with tight connections; "
        f"check on {wd['day_name']}s whether the extra delay comes from volume or from specific airlines."
    )
