"""Person 5 - Cancellations: when and why are flights cancelled?

Logic lives in SQL (sql/cancellations.sql). Two fine-grain views feed the
sidebar filters; the analytic views are used for the airline ranking and the
open-issue panel.
"""
import numpy as np
import pandas as pd
import plotly.express as px
import streamlit as st

from database import get_engine

st.set_page_config(page_title="Cancellations - Flight Delays", layout="wide")

MONTHS = {1: "Jan", 2: "Feb", 3: "Mar", 4: "Apr", 5: "May", 6: "Jun",
          7: "Jul", 8: "Aug", 9: "Sep", 10: "Oct", 11: "Nov", 12: "Dec"}
REASON_COLORS = {  # same palette as the delay-causes page
    "Airline": "#00B894", "Air system (NAS)": "#0984E3", "Weather": "#FDCB6E",
    "Security": "#D63031", "Unknown": "#B2BEC3",
}
SIGNAL_COLORS = {"Above overall": "#D63031", "In line": "#B2BEC3", "Below overall": "#00B894"}
RECOMMENDATIONS = {
    "Airline": "Improve crew and aircraft planning, keep spare aircraft or crews at hubs, and strengthen preventive maintenance.",
    "Weather": "Decide earlier to cancel and rebook in advance, and keep extra capacity in the months when weather cancellations peak.",
    "Air system (NAS)": "Schedule less aggressively at congested airports and peak hours, and coordinate with air traffic management.",
    "Security": "Rare: no operational change needed beyond contingency rebooking.",
    "Unknown": "Record a cancellation reason for every cancelled flight so the cause can be analysed.",
}
MIN_FLIGHTS = 30       # team rule
MIN_CANCELLED = 30     # below this, shares are unreliable

ALLOWED_VIEWS = {
    "v_cancel_airline_month", "v_cancel_airline_month_reason",
    "v_cancel_by_airline", "v_cancel_delay_check", "v_cancel_quality",
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


try:
    am = load_view("v_cancel_airline_month")
    amr = load_view("v_cancel_airline_month_reason")
    by_airline = load_view("v_cancel_by_airline")
    delay_check = load_view("v_cancel_delay_check")
    quality = load_view("v_cancel_quality").iloc[0]
except Exception as exc:
    st.error(f"Could not read the v_cancel_* views. Did you run sql/cancellations.sql? Details: {exc}")
    st.stop()

# ---------------------------------------------------------------- header
st.title("When and why are flights cancelled?")
st.caption(
    "Cancellation rate = cancelled flights / all scheduled flights. Cancelled flights have no "
    "delay values, so they are never used in delay averages."
)

# ---------------------------------------------------------------- filters
st.sidebar.header("Cancellations: filters")
airline = st.sidebar.selectbox("Airline", ["All"] + sorted(am["airline_name"].unique()))
month = st.sidebar.selectbox(
    "Month", ["All"] + [int(m) for m in sorted(am["month"].unique())],
    format_func=lambda m: MONTHS.get(m, m),
)


def pick(df, by_airline=True, by_month=True):
    if by_airline and airline != "All":
        df = df[df["airline_name"] == airline]
    if by_month and month != "All":
        df = df[df["month"] == month]
    return df


sel = pick(am)
n_flights = int(sel["nb_flights"].sum())
n_canc = int(sel["nb_cancelled"].sum())
if n_flights == 0:
    st.warning("No flights for this selection.")
    st.stop()
rate = 100 * n_canc / n_flights
ci_lo, ci_hi = wilson(n_canc, n_flights)

reasons = (pick(amr).groupby(["reason_code", "reason"], as_index=False)["nb_cancelled"].sum()
           .sort_values("nb_cancelled", ascending=False))
reasons["share_pct"] = (100 * reasons["nb_cancelled"] / max(n_canc, 1)).round(1)

# monthly trend: airline filter only, all months, team minimum applied
trend = (pick(am, by_month=False).groupby(["year", "month"], as_index=False)[["nb_flights", "nb_cancelled"]].sum())
trend = trend[trend["nb_flights"] >= MIN_FLIGHTS].copy()
trend["cancel_rate_pct"] = 100 * trend["nb_cancelled"] / trend["nb_flights"]
multi_year = trend["year"].nunique() > 1
trend["label"] = [f"{int(y)}-{int(m):02d}" if multi_year else MONTHS[int(m)]
                  for y, m in zip(trend["year"], trend["month"])]
trend_rate = 100 * trend["nb_cancelled"].sum() / trend["nb_flights"].sum() if len(trend) else float("nan")

# ---------------------------------------------------------------- KPIs
k1, k2, k3, k4 = st.columns(4)
k1.metric("Cancellation rate", f"{rate:.2f} %", f"{n_canc:,} of {n_flights:,} flights", delta_color="off")
k1.caption(f"95% interval: {ci_lo:.2f}% to {ci_hi:.2f}%")
if len(trend):
    worst = trend.loc[trend["cancel_rate_pct"].idxmax()]
    k2.metric("Worst month", worst["label"], f"{worst['cancel_rate_pct']:.2f} %", delta_color="inverse")
if len(reasons) and n_canc:
    top = reasons.iloc[0]
    k3.metric("Main reason", top["reason"], f"{top['share_pct']} % of cancellations", delta_color="off")
    air_share = reasons.loc[reasons["reason_code"] == "A", "share_pct"].sum()
    k4.metric("Airline-caused", f"{air_share:.1f} %", "of cancellations", delta_color="off")

if n_canc < MIN_CANCELLED:
    st.warning(f"Only {n_canc} cancelled flights in this selection (minimum {MIN_CANCELLED}): "
               "read shares and rates with caution.")
st.caption("Trend and monthly reasons show all months; the month filter applies to the KPIs, "
           "the reasons chart and the airline ranking.")
st.divider()

# ---------------------------------------------------------------- trend and reasons
left, right = st.columns(2)
with left:
    st.subheader("Monthly cancellation rate")
    if len(trend):
        fig = px.line(trend, x="label", y="cancel_rate_pct", markers=True,
                      labels={"label": "", "cancel_rate_pct": "Cancellation rate (%)"})
        fig.add_hline(y=trend_rate, line_dash="dash", annotation_text=f"Period average {trend_rate:.2f} %")
        fig.update_yaxes(rangemode="tozero")
        fig.update_layout(height=380, margin=dict(t=10))
        st.plotly_chart(fig, use_container_width=True)
    else:
        st.info("No month reaches the minimum number of flights for this airline.")
with right:
    st.subheader("Cancellation reasons")
    if n_canc:
        fig = px.bar(reasons, x="nb_cancelled", y="reason", orientation="h",
                     color="reason", color_discrete_map=REASON_COLORS,
                     text=reasons.apply(lambda r: f"{int(r.nb_cancelled):,} ({r.share_pct}%)", axis=1),
                     category_orders={"reason": list(reasons["reason"])},
                     labels={"nb_cancelled": "Cancelled flights", "reason": ""})
        fig.update_traces(textposition="outside")
        fig.update_yaxes(autorange="reversed")
        fig.update_layout(showlegend=False, height=380, margin=dict(t=10))
        st.plotly_chart(fig, use_container_width=True)
        if int(reasons["nb_cancelled"].sum()) == n_canc:
            st.caption("Check passed: the reasons add up exactly to the cancelled flights of this selection.")
        else:
            st.warning("The reasons do not add up to the cancelled flights of this selection.")
    else:
        st.info("No cancelled flights in this selection.")

# ---------------------------------------------------------------- reasons by month
st.subheader("Reasons by month")
metric = st.radio("Show", ["Per 1,000 flights", "Cancelled flights", "Share of the month's cancellations"],
                  horizontal=True)
rm = pick(amr, by_month=False).groupby(["year", "month", "reason"], as_index=False)["nb_cancelled"].sum()
present = [r for r in REASON_COLORS if r in set(amr["reason"])]
grid = trend[["year", "month", "label", "nb_flights", "nb_cancelled"]].rename(
    columns={"nb_cancelled": "month_total"}).merge(pd.DataFrame({"reason": present}), how="cross")
grid = grid.merge(rm, on=["year", "month", "reason"], how="left").fillna({"nb_cancelled": 0})
grid["per_1000"] = 1000 * grid["nb_cancelled"] / grid["nb_flights"]
grid["share"] = np.where(grid["month_total"] > 0, 100 * grid["nb_cancelled"] / grid["month_total"].replace(0, np.nan), 0)
col, label = {"Per 1,000 flights": ("per_1000", "Cancellations per 1,000 flights"),
              "Cancelled flights": ("nb_cancelled", "Cancelled flights"),
              "Share of the month's cancellations": ("share", "% of the month's cancellations")}[metric]
if len(grid):
    fig = px.bar(grid, x="label", y=col, color="reason", barmode="stack",
                 color_discrete_map=REASON_COLORS, category_orders={"reason": present},
                 labels={"label": "", col: label, "reason": ""})
    fig.update_layout(height=400, legend=dict(orientation="h", y=-0.15))
    st.plotly_chart(fig, use_container_width=True)
    st.caption("Per 1,000 flights removes the effect of flight volume; counts mostly follow how many flights run.")

# ---------------------------------------------------------------- airlines
st.subheader("Cancellation rate by airline")
air = pick(am, by_airline=False).groupby(["airline_code", "airline_name"], as_index=False)[["nb_flights", "nb_cancelled"]].sum()
air = air[air["nb_flights"] >= MIN_FLIGHTS].copy()
sel_rate = 100 * air["nb_cancelled"].sum() / air["nb_flights"].sum() if len(air) else float("nan")
air["cancel_rate_pct"] = 100 * air["nb_cancelled"] / air["nb_flights"]
air["ci_lo"], air["ci_hi"] = wilson(air["nb_cancelled"], air["nb_flights"])
air["signal"] = np.where(air["ci_lo"] > sel_rate, "Above overall",
                         np.where(air["ci_hi"] < sel_rate, "Below overall", "In line"))
air = air.sort_values("cancel_rate_pct")
fig = px.bar(air, x="cancel_rate_pct", y="airline_name", orientation="h", color="signal",
             color_discrete_map=SIGNAL_COLORS,
             category_orders={"signal": list(SIGNAL_COLORS)},
             labels={"cancel_rate_pct": "Cancellation rate (%)", "airline_name": "", "signal": "Versus overall"})
fig.add_vline(x=sel_rate, line_dash="dash", annotation_text=f"Overall {sel_rate:.2f} %")
fig.update_layout(height=max(380, 28 * len(air) + 120), margin=dict(t=10))
st.plotly_chart(fig, use_container_width=True)
st.caption("Red: the 95% interval is entirely above the overall rate. Grey: not clearly different.")
st.dataframe(
    by_airline.sort_values("worst_rank")[["worst_rank", "airline_name", "nb_flights", "nb_cancelled",
                                          "cancel_rate_pct", "vs_overall_pts", "signal", "airline_caused_pct"]],
    use_container_width=True, hide_index=True,
    column_config={"cancel_rate_pct": st.column_config.NumberColumn("Rate (%)", format="%.2f"),
                   "vs_overall_pts": st.column_config.NumberColumn("Vs overall (pts)", format="%+.2f"),
                   "airline_caused_pct": st.column_config.NumberColumn("Airline-caused (%)", format="%.1f")})
st.caption("Table: all months, all airlines (from v_cancel_by_airline).")

# ---------------------------------------------------------------- open issue
st.divider()
st.subheader("Open issue: cancelled flights and delay averages")
q1, q2, q3, q4 = st.columns(4)
q1.metric("Cancelled flights", f"{int(quality['cancelled_flights']):,}")
q2.metric("With NULL arrival delay", f"{int(quality['cancelled_null_arrival_delay']):,}")
q3.metric("With delay = 0", f"{int(quality['cancelled_with_zero_delay']):,}")
q4.metric("Unknown reason", f"{int(quality['cancelled_unknown_reason']):,}")
dc = delay_check.sort_values("bias_min").melt(
    id_vars="airline_name", value_vars=["avg_delay_correct_min", "avg_delay_wrong_min"],
    var_name="method", value_name="avg_delay")
dc["method"] = dc["method"].map({"avg_delay_correct_min": "Completed flights only (used)",
                                 "avg_delay_wrong_min": "NULL replaced by 0 (wrong)"})
fig = px.bar(dc, x="avg_delay", y="airline_name", color="method", barmode="group", orientation="h",
             color_discrete_sequence=["#0984E3", "#D63031"],
             labels={"avg_delay": "Average arrival delay (min)", "airline_name": "", "method": ""})
fig.update_layout(height=max(380, 34 * delay_check.shape[0] + 120), legend=dict(orientation="h", y=-0.1))
st.plotly_chart(fig, use_container_width=True)
st.caption("Replacing NULL by 0 turns cancelled and diverted flights into on-time flights and pulls the average "
           "toward zero. Delay averages in this project use completed flights only.")

# ---------------------------------------------------------------- findings
st.divider()
parts = []
if len(trend):
    top3 = trend.nlargest(3, "nb_cancelled")["nb_cancelled"].sum()
    parts.append(f"Cancellations peak in {worst['label']} ({worst['cancel_rate_pct']:.2f}% against a period "
                 f"average of {trend_rate:.2f}%); the three busiest months hold "
                 f"{100 * top3 / max(trend['nb_cancelled'].sum(), 1):.0f}% of all cancellations.")
if n_canc:
    parts.append(f"{top['reason']} is the main reason ({top['share_pct']}%); airline-caused cancellations are "
                 f"{air_share:.0f}%, the part the airline can control.")
if airline == "All":
    flagged = air[air["signal"] == "Above overall"].sort_values("cancel_rate_pct", ascending=False)["airline_name"].tolist()
    parts.append("Airlines clearly above the overall rate: " + (", ".join(flagged[:3]) if flagged else "none") + ".")
if parts:
    st.info("**Finding for this selection:** " + " ".join(parts))
if n_canc:
    recs = [RECOMMENDATIONS[r] for r in reasons["reason"].head(2)]
    st.success("**Recommendation:** " + " ".join(recs))