import os

import pandas as pd
import plotly.express as px
import streamlit as st
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

load_dotenv()  # lit le fichier .env (cherche en remontant les dossiers jusqu'a la racine du projet)

st.set_page_config(page_title="Airlines - Flight Delays", layout="wide")

st.title("Airlines")
st.caption(
    "A flight is delayed when it arrives 15 minutes or more after schedule. "
    "Cancelled and diverted flights are excluded."
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
    # URL.create echappe correctement les caracteres speciaux du mot de passe
    url = URL.create(
        "postgresql+psycopg2",
        username=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        host=os.getenv("DB_HOST"),
        port=int(os.getenv("DB_PORT")),
        database=os.getenv("DB_NAME"),
    )
    return create_engine(url)


engine = get_engine()

# Seules les vues de cette page peuvent etre lues (le nom est insere dans la requete)
ALLOWED_VIEWS = {
    "v_airlines_delay_rate",
    "v_airlines_ranking",
    "v_airlines_reliability",
}


@st.cache_data(ttl=300)
def load_view(view_name: str) -> pd.DataFrame:
    """Lit une vue SQL entiere et la renvoie en DataFrame."""
    if view_name not in ALLOWED_VIEWS:
        raise ValueError(f"Vue non autorisee : {view_name}")
    with engine.connect() as connection:
        df = pd.read_sql(text(f"SELECT * FROM {view_name}"), connection)
    # PostgreSQL renvoie du numeric (Decimal) : on convertit en float pour les graphiques
    for col in df.columns:
        if df[col].dtype == "object":
            try:
                df[col] = df[col].astype(float)
            except (ValueError, TypeError):
                pass
    return df


# ---------- Visualization 1 : delay rate by airline (with details on hover / click) ----------
st.subheader("Delay rate by airline")

df_rate = load_view("v_airlines_delay_rate")
df_rank = load_view("v_airlines_ranking")

# On ajoute la moyenne sur tous les vols (elle vient de v_airlines_ranking)
df = df_rate.merge(
    df_rank[["iata_code", "avg_arrival_delay_min"]], on="iata_code"
).sort_values("delay_rate_pct", ascending=False).reset_index(drop=True)

fig = px.bar(
    df,
    x="airline",
    y="delay_rate_pct",
    text="delay_rate_pct",
    custom_data=[
        "total_flights",
        "delayed_flights",
        "avg_arrival_delay_min",
        "avg_delay_when_late_min",
    ],
    labels={"airline": "Airline", "delay_rate_pct": "Delayed flights (%)"},
)
fig.update_traces(
    texttemplate="%{text:.1f}%",
    textposition="outside",
    hovertemplate=(
        "<b>%{x}</b><br>"
        "Delay rate: %{y:.1f}%<br>"
        "Flights analysed: %{customdata[0]:,}<br>"
        "Delayed flights: %{customdata[1]:,}<br>"
        "Avg arrival delay (all flights): %{customdata[2]:.1f} min<br>"
        "Avg delay when late: %{customdata[3]:.1f} min"
        "<extra></extra>"
    ),
)
fig.update_layout(
    xaxis={"categoryorder": "array", "categoryarray": df["airline"].tolist()},
    yaxis={"ticksuffix": "%"},
    xaxis_tickangle=-45,
    margin={"t": 30},
)

event = st.plotly_chart(
    fig, on_select="rerun", selection_mode="points", key="airline_chart"
)

points = event.selection.points
if points:
    row = df[df["airline"] == points[0]["x"]].iloc[0]
    st.markdown(f"**{row['airline']}**")
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Delay rate", f"{row['delay_rate_pct']:.1f}%")
    c2.metric("Avg arrival delay (all flights)", f"{row['avg_arrival_delay_min']:.1f} min")
    c3.metric("Avg delay when late", f"{row['avg_delay_when_late_min']:.1f} min")
    c4.metric("Flights analysed", f"{int(row['total_flights']):,}")
else:
    st.info("Click a bar to see the average delay for that airline.")


# ---------- Visualization 2 : average delay by airline (table) ----------
st.subheader("Average delay by airline")

table = df_rank.sort_values("airline_rank")[
    ["airline", "avg_arrival_delay_min", "avg_delay_when_late_min"]
].rename(
    columns={
        "airline": "Airline",
        "avg_arrival_delay_min": "Avg arrival delay",
        "avg_delay_when_late_min": "Avg delay when late",
    }
)

st.dataframe(
    table,
    hide_index=True,
    column_config={
        "Avg arrival delay": st.column_config.NumberColumn(format="%.1f min"),
        "Avg delay when late": st.column_config.NumberColumn(format="%.1f min"),
    },
)
st.caption(
    "Avg arrival delay: mean over all eligible flights (early flights count as negative). "
    "Avg delay when late: mean over delayed flights only (15 minutes or more)."
)


# ---------- Open issue : reliability of the rates ----------
st.header("Open issue: how reliable are these rates?")

df_rel = load_view("v_airlines_reliability").sort_values(
    "delay_rate_pct", ascending=False
)
n_total = len(df_rel)
n_reliable = int(df_rel["reliable"].sum())
low = df_rel[~df_rel["reliable"]]
widest = df_rel.loc[df_rel["margin_pts"].idxmax()]
narrowest = df_rel.loc[df_rel["margin_pts"].idxmin()]

st.markdown(
    "**Problem.** A delay rate is an estimate built from the flights we observed. "
    "The fewer flights an airline has in our sample, the less precise its rate is, "
    "so a ranking can look more certain than it really is.\n\n"
    "**Impact.** Two airlines with close rates may not really differ, and a small "
    "airline can look better or worse than it is."
)

c1, c2, c3 = st.columns(3)
c1.metric("Airlines with 1,000+ flights", f"{n_reliable} / {n_total}")
c2.metric(
    "Widest margin of error",
    f"±{widest['margin_pts']:.1f} pts",
    help=widest["airline"],
)
c3.metric(
    "Narrowest margin of error",
    f"±{narrowest['margin_pts']:.1f} pts",
    help=narrowest["airline"],
)

if len(low) > 0:
    st.warning(
        "Below 1,000 flights: " + ", ".join(low["airline"].tolist()) + "."
    )

# Chart : delay rate with its margin of error (95 % interval)
df_chart = df_rel.copy()
df_chart["Status"] = df_chart["reliable"].map(
    {True: "1,000+ flights", False: "Fewer than 1,000 flights"}
)
fig_rel = px.bar(
    df_chart,
    x="airline",
    y="delay_rate_pct",
    error_y="margin_pts",
    color="Status",
    color_discrete_map={
        "1,000+ flights": "#0068C9",
        "Fewer than 1,000 flights": "#F5A623",
    },
    labels={"airline": "Airline", "delay_rate_pct": "Delayed flights (%)"},
)
fig_rel.update_layout(
    xaxis={"categoryorder": "array", "categoryarray": df_chart["airline"].tolist()},
    yaxis={"ticksuffix": "%"},
    xaxis_tickangle=-45,
    margin={"t": 30},
)
st.plotly_chart(fig_rel)

# Table : margin of error and reliability flag
table_rel = df_rel[
    ["airline", "total_flights", "delay_rate_pct", "margin_pts", "reliable"]
].rename(
    columns={
        "airline": "Airline",
        "total_flights": "Flights analysed",
        "delay_rate_pct": "Delay rate",
        "margin_pts": "Margin of error",
        "reliable": "Reliable",
    }
)
table_rel["Reliable"] = table_rel["Reliable"].map({True: "Yes", False: "No"})
st.dataframe(
    table_rel.sort_values("Margin of error", ascending=False),
    hide_index=True,
    column_config={
        "Flights analysed": st.column_config.NumberColumn(format="%d"),
        "Delay rate": st.column_config.NumberColumn(format="%.1f%%"),
        "Margin of error": st.column_config.NumberColumn(format="±%.1f pts"),
    },
)