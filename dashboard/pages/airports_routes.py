
import streamlit as st
import pandas as pd
import plotly.express as px
from sqlalchemy import text
from database import get_engine


# ============================================================
# PAGE CONFIGURATION
# ============================================================

st.set_page_config(
    page_title="Airports & Routes",
    layout="wide"
)

st.title("Airports & Routes Analysis")
st.caption("Flight Delays Analysis | 2015")

engine = get_engine()


# ============================================================
# LOAD DATA FROM POSTGRESQL
# ============================================================

@st.cache_data(ttl=300)
def load_airports():
    with engine.connect() as connection:
        return pd.read_sql(
            text("""
                SELECT *
                FROM v_airports_routes_airport_delays
            """),
            connection
        )


@st.cache_data(ttl=300)
def load_routes():
    with engine.connect() as connection:
        return pd.read_sql(
            text("""
                SELECT *
                FROM v_airports_routes_top_routes
                WHERE route_rank <= 10
                ORDER BY route_rank
            """),
            connection
        )


try:
    airports = load_airports()
    routes = load_routes()

except Exception as e:
    st.error(f"Error loading PostgreSQL data: {e}")
    st.stop()


# ============================================================
# PREPARE DATA
# ============================================================

# Convert numerical columns to numeric types
airport_numeric_cols = [
    "eligible_flights",
    "delayed_flights",
    "delay_rate_pct",
    "avg_arrival_delay"
]

route_numeric_cols = [
    "eligible_flights",
    "delayed_flights",
    "delay_rate_pct",
    "avg_arrival_delay"
]

for col in airport_numeric_cols:
    airports[col] = pd.to_numeric(airports[col])

for col in route_numeric_cols:
    routes[col] = pd.to_numeric(routes[col])


# ============================================================
# KPI CARDS
# ============================================================

st.header("Key Performance Indicators")

# Highest delay volume airport
highest_volume_airport = airports.loc[
    airports["delayed_flights"].idxmax()
]

# Highest delay rate airport
highest_rate_airport = airports.loc[
    airports["delay_rate_pct"].idxmax()
]

# Most delayed route
most_delayed_route = routes.loc[
    routes["delayed_flights"].idxmax()
]

# Highest delay rate among the displayed top 10 routes
highest_route_rate = routes.loc[
    routes["delay_rate_pct"].idxmax()
]


col1, col2, col3, col4 = st.columns(4)

col1.metric(
    "Most Delayed Airport",
    highest_volume_airport["airport_code"],
    f'{int(highest_volume_airport["delayed_flights"])} delayed flights'
)

col2.metric(
    "Highest Airport Delay Rate",
    f'{highest_rate_airport["delay_rate_pct"]:.2f}%',
    highest_rate_airport["airport_code"]
)

col3.metric(
    "Most Delayed Route",
    f'{most_delayed_route["origin_code"]} → '
    f'{most_delayed_route["destination_code"]}',
    f'{int(most_delayed_route["delayed_flights"])} delayed flights'
)

col4.metric(
    "Highest Route Delay Rate (Top 10)",
    f'{highest_route_rate["delay_rate_pct"]:.2f}%',
    f'{highest_route_rate["origin_code"]} → '
    f'{highest_route_rate["destination_code"]}'
)


st.divider()


# ============================================================
# SECTION 1: AIRPORT ANALYSIS
# ============================================================

st.header("01. Airport Delay Analysis")

st.markdown(
    "Explore airports with the highest number and percentage "
    "of delayed flights."
)

# Controls
col1, col2 = st.columns(2)

with col1:
    airport_metric = st.selectbox(
        "Rank airports by",
        ["Delayed Flights", "Delay Rate (%)"]
    )

with col2:
    airport_limit = st.selectbox(
        "Number of airports",
        [5, 10, 15],
        index=1
    )


# Select ranking
if airport_metric == "Delayed Flights":
    airport_display = airports.sort_values(
        "delayed_flights",
        ascending=False
    ).head(airport_limit)

    x_column = "delayed_flights"
    chart_title = "Airports with the Highest Delay Volume"
    x_label = "Number of Delayed Flights"

else:
    airport_display = airports.sort_values(
        "delay_rate_pct",
        ascending=False
    ).head(airport_limit)

    x_column = "delay_rate_pct"
    chart_title = "Airports with the Highest Delay Rate"
    x_label = "Delay Rate (%)"


# Create readable labels
airport_display = airport_display.copy()

airport_display["airport_label"] = (
    airport_display["airport_code"]
    + " · "
    + airport_display["airport_name"]
)


# Interactive bar chart
fig_airports = px.bar(
    airport_display.sort_values(x_column),
    x=x_column,
    y="airport_label",
    orientation="h",
    title=chart_title,
    labels={
        x_column: x_label,
        "airport_label": "Airport"
    },
    custom_data=[
        "airport_code",
        "airport_name",
        "city",
        "state",
        "eligible_flights",
        "delayed_flights",
        "delay_rate_pct",
        "avg_arrival_delay"
    ],
    color=x_column,
    color_continuous_scale="Blues"
)

fig_airports.update_traces(
    hovertemplate=
    "<b>%{customdata[0]} · %{customdata[1]}</b><br>"
    "City: %{customdata[2]}<br>"
    "State: %{customdata[3]}<br>"
    "Eligible flights: %{customdata[4]:,}<br>"
    "Delayed flights: %{customdata[5]:,}<br>"
    "Delay rate: %{customdata[6]:.2f}%<br>"
    "Average arrival delay: %{customdata[7]:.2f} min"
    "<extra></extra>"
)

fig_airports.update_layout(
    height=520,
    coloraxis_showscale=False,
    xaxis_title=x_label,
    yaxis_title="",
    margin=dict(l=10, r=20, t=60, b=30)
)

st.plotly_chart(
    fig_airports,
    use_container_width=True
)


# ============================================================
# SECTION 2: ROUTE ANALYSIS
# ============================================================

st.divider()

st.header("02. Top 10 Most Delayed Routes")

st.markdown(
    "Discover the flight routes with the highest number "
    "of delayed flights."
)

routes_display = routes.copy()

# Origin -> Destination label
routes_display["route_label"] = (
    routes_display["origin_code"]
    + " → "
    + routes_display["destination_code"]
)


# Interactive route chart
fig_routes = px.bar(
    routes_display.sort_values("delayed_flights"),
    x="delayed_flights",
    y="route_label",
    orientation="h",
    title="Top 10 Routes with the Most Delayed Flights",
    labels={
        "delayed_flights": "Number of Delayed Flights",
        "route_label": "Flight Route"
    },
    custom_data=[
        "origin_code",
        "origin_name",
        "origin_city",
        "destination_code",
        "destination_name",
        "destination_city",
        "eligible_flights",
        "delay_rate_pct",
        "avg_arrival_delay"
    ],
    color="delayed_flights",
    color_continuous_scale="Oranges"
)

fig_routes.update_traces(
    hovertemplate=
    "<b>%{customdata[0]} → %{customdata[3]}</b><br>"
    "<br>"
    "<b>Origin</b><br>"
    "%{customdata[1]} (%{customdata[2]})<br>"
    "<b>Destination</b><br>"
    "%{customdata[4]} (%{customdata[5]})<br>"
    "<br>"
    "Delayed flights: %{x}<br>"
    "Eligible flights: %{customdata[6]:,}<br>"
    "Delay rate: %{customdata[7]:.2f}%<br>"
    "Average arrival delay: %{customdata[8]:.2f} min"
    "<extra></extra>"
)

fig_routes.update_layout(
    height=550,
    coloraxis_showscale=False,
    xaxis_title="Number of Delayed Flights",
    yaxis_title="Origin → Destination",
    margin=dict(l=10, r=20, t=60, b=30)
)

st.plotly_chart(
    fig_routes,
    use_container_width=True
)


# ============================================================
# SECTION 3: DETAILS ON DEMAND
# ============================================================

st.divider()

with st.expander("View detailed airport data"):
    st.dataframe(
        airports[
            [
                "airport_code",
                "airport_name",
                "city",
                "eligible_flights",
                "delayed_flights",
                "delay_rate_pct",
                "avg_arrival_delay"
            ]
        ].sort_values(
            "delayed_flights",
            ascending=False
        ),
        use_container_width=True,
        hide_index=True
    )



with st.expander("View detailed route data"):
    st.dataframe(
        routes[
            [
                "route_rank",
                "origin_code",
                "origin_city",
                "destination_code",
                "destination_city",
                "eligible_flights",
                "delayed_flights",
                "delay_rate_pct",
                "avg_arrival_delay"
            ]
        ].sort_values(
            "route_rank"
        ),
        use_container_width=True,
        hide_index=True
    )



# ============================================================
# FOOTER
# ============================================================

st.caption(
    "Methodology: A flight is considered delayed when "
    "arrival_delay >= 15 minutes. Cancelled and diverted "
    "flights, as well as flights with missing arrival delay, "
    "are excluded. Minimum threshold: 30 eligible flights."
)
