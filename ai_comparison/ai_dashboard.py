import os
import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go
from sqlalchemy import create_engine, text

# -----------------------------------------------------------------------------
# 1. PAGE CONFIGURATION & THEME
# -----------------------------------------------------------------------------
st.set_page_config(
    page_title="Airline Operational Decision Support",
    page_icon="✈️",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS for executive layout
st.markdown("""
<style>
    .metric-card {
        background-color: #f8f9fa;
        border-radius: 8px;
        padding: 15px;
        border-left: 5px solid #1E88E5;
        box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }
    .stApp {
        background-color: #FAFAFA;
    }
</style>
""", unsafe_allow_html=True)

# -----------------------------------------------------------------------------
# 2. DATABASE CONNECTION & DATA LOADING
# -----------------------------------------------------------------------------
@st.cache_resource
def get_db_engine():
    """Initializes database connection via SQLAlchemy."""
    # Pull credentials from environment variables or Streamlit secrets
    user = os.getenv("DB_USER", "postgres")
    password = os.getenv("DB_PASSWORD", "postgres")
    host = os.getenv("DB_HOST", "localhost")
    port = os.getenv("DB_PORT", "5432")
    dbname = os.getenv("DB_NAME", "airline_db")
    
    connection_url = f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{dbname}"
    return create_engine(connection_url, pool_pre_ping=True)

@st.cache_data(ttl=3600)
def load_filter_options():
    """Loads lightweight categorical data for filter dropdowns."""
    engine = get_db_engine()
    with engine.connect() as conn:
        airlines = pd.read_sql("SELECT iata_code, airline FROM airlines ORDER BY airline", conn)
        airports = pd.read_sql("SELECT iata_code, airport, city FROM airports ORDER BY city", conn)
    return airlines, airports

@st.cache_data(ttl=600)
def load_flight_data(selected_airline, selected_month):
    """
    Executes an optimized, analytical query joining flights with origin/destination airports.
    """
    engine = get_db_engine()
    
    query = """
    SELECT 
        f.flight_id,
        f.flight_date,
        f.year,
        f.month,
        f.day_of_week,
        f.airline AS airline_code,
        a.airline AS airline_name,
        f.flight_number,
        f.origin_airport AS origin_code,
        orig.city AS origin_city,
        orig.latitude AS origin_lat,
        orig.longitude AS origin_lon,
        f.destination_airport AS dest_code,
        dest.city AS dest_city,
        dest.latitude AS dest_lat,
        dest.longitude AS dest_lon,
        f.scheduled_hour,
        f.departure_delay,
        f.arrival_delay,
        f.cancelled,
        f.diverted,
        cr.reason AS cancellation_reason,
        COALESCE(f.air_system_delay, 0) AS air_system_delay,
        COALESCE(f.security_delay, 0) AS security_delay,
        COALESCE(f.airline_delay, 0) AS airline_delay,
        COALESCE(f.late_aircraft_delay, 0) AS late_aircraft_delay,
        COALESCE(f.weather_delay, 0) AS weather_delay
    FROM flights f
    LEFT JOIN airlines a ON f.airline = a.iata_code
    LEFT JOIN airports orig ON f.origin_airport = orig.iata_code
    LEFT JOIN airports dest ON f.destination_airport = dest.iata_code
    LEFT JOIN cancellation_reasons cr ON f.cancellation_reason = cr.code
    WHERE 1=1
    """
    params = {}
    
    if selected_airline != "All":
        query += " AND f.airline = :airline"
        params["airline"] = selected_airline
        
    if selected_month != "All":
        query += " AND f.month = :month"
        params["month"] = selected_month

    with engine.connect() as conn:
        df = pd.read_sql(text(query), conn, params=params)
        
    return df

# -----------------------------------------------------------------------------
# 3. SIDEBAR FILTERS
# -----------------------------------------------------------------------------
st.sidebar.title("✈️ Operations Control")
st.sidebar.markdown("Filter parameters to isolate operational bottlenecks.")

try:
    airlines_df, airports_df = load_filter_options()
    
    airline_options = ["All"] + list(airlines_df['iata_code'])
    selected_airline = st.sidebar.selectbox("Airline Carrier", airline_options)
    
    month_options = ["All"] + list(range(1, 13))
    selected_month = st.sidebar.selectbox("Month", month_options)
    
    df = load_flight_data(selected_airline, selected_month)

except Exception as e:
    st.error(f"Failed to connect to PostgreSQL database: {e}")
    st.info("Check your database connection string and psycopg2 setup.")
    st.stop()

# -----------------------------------------------------------------------------
# 4. EXECUTIVE DASHBOARD HEADER & KPIS
# -----------------------------------------------------------------------------
st.title("Airline Operations Decision-Support Dashboard")
st.markdown("Directing interventions toward high-impact delays, systemic root causes, and cancelled routes.")

# Compute High-Level Metrics
total_flights = len(df)
cancelled_flights = df['cancelled'].sum()
cancellation_rate = (cancelled_flights / total_flights * 100) if total_flights > 0 else 0

# On-Time Performance (Arrival Delay <= 15 min and not cancelled)
on_time_flights = len(df[(df['arrival_delay'] <= 15) & (df['cancelled'] == 0)])
otp_rate = (on_time_flights / total_flights * 100) if total_flights > 0 else 0

total_delay_min = df[df['arrival_delay'] > 0]['arrival_delay'].sum()
# Industry benchmark (~$74/minute operational delay cost)
est_financial_cost = total_delay_min * 74 

# Display Metric Cards
col1, col2, col3, col4 = st.columns(4)

with col1:
    st.metric("On-Time Performance (OTP)", f"{otp_rate:.1f}%", delta=f"{otp_rate - 80:.1f}% vs 80% Target")
with col2:
    st.metric("Cancellation Rate", f"{cancellation_rate:.2f}%", delta=f"-{cancellation_rate:.2f}%", delta_color="inverse")
with col3:
    st.metric("Total Delay Time", f"{total_delay_min:,.0f} min", f"~${est_financial_cost/1e6:.2f}M Impact")
with col4:
    # Identify top delay cause
    delay_sums = {
        'Carrier/Airline': df['airline_delay'].sum(),
        'Late Aircraft': df['late_aircraft_delay'].sum(),
        'NAS/Air System': df['air_system_delay'].sum(),
        'Weather': df['weather_delay'].sum(),
        'Security': df['security_delay'].sum()
    }
    top_cause = max(delay_sums, key=delay_sums.get)
    st.metric("Primary Bottleneck", top_cause, f"{delay_sums[top_cause]:,.0f} mins total")

st.divider()

# -----------------------------------------------------------------------------
# 5. TABBED ANALYTICAL VIEWS
# -----------------------------------------------------------------------------
tab_why, tab_where, tab_when = st.tabs([
    "🔍 WHY: Root Causes & Disruption Types",
    "📍 WHERE: Geographic Bottlenecks & Routes",
    "⏰ WHEN: Temporal & Hourly Patterns"
])

# -----------------------------------------------------------------------------
# TAB 1: WHY (Root Cause Analysis)
# -----------------------------------------------------------------------------
with tab_why:
    col_a, col_b = st.columns(2)
    
    with col_a:
        st.subheader("Breakdown of Delay Causes (Minutes)")
        cause_df = pd.DataFrame(list(delay_sums.items()), columns=['Cause', 'Minutes']).sort_values('Minutes', ascending=False)
        
        fig_causes = px.bar(
            cause_df, 
            x='Minutes', 
            y='Cause', 
            orientation='h',
            color='Cause',
            color_discrete_sequence=px.colors.qualitative.Bold,
            text_auto=',.0f'
        )
        fig_causes.update_layout(showlegend=False, yaxis={'categoryorder':'total ascending'})
        st.plotly_chart(fig_causes, use_container_width=True)
        st.caption("Actionable Takeaway: Focus IT/Operations resources on the top bucket. 'Carrier' delays point to crew/maintenance, while 'Late Aircraft' indicates downstream propagation.")

    with col_b:
        st.subheader("Cancellation Reasons")
        cancellations = df[df['cancelled'] == 1]['cancellation_reason'].value_counts().reset_index()
        cancellations.columns = ['Reason', 'Count']
        
        if not cancellations.empty:
            fig_canc = px.pie(
                cancellations, 
                values='Count', 
                names='Reason', 
                hole=0.4,
                color_discrete_sequence=px.colors.sequential.RdBu
            )
            st.plotly_chart(fig_canc, use_container_width=True)
        else:
            st.info("No cancellations recorded for the selected filter criteria.")

# -----------------------------------------------------------------------------
# TAB 2: WHERE (Geographic & Route Analysis)
# -----------------------------------------------------------------------------
with tab_where:
    col_map, col_routes = st.columns([1.2, 0.8])
    
    with col_map:
        st.subheader("Worst Origin Airports by Average Delay")
        
        # Aggregate by Origin Airport
        airport_stats = df.groupby(['origin_code', 'origin_city', 'origin_lat', 'origin_lon']).agg(
            avg_delay=('arrival_delay', 'mean'),
            flight_count=('flight_id', 'count')
        ).reset_index()
        
        # Filter out low-volume airports to reduce noise
        airport_stats = airport_stats[airport_stats['flight_count'] >= 50]
        
        fig_map = px.scatter_geo(
            airport_stats,
            lat='origin_lat',
            lon='origin_lon',
            color='avg_delay',
            size='flight_count',
            hover_name='origin_city',
            hover_data=['origin_code', 'avg_delay', 'flight_count'],
            projection="albers usa",
            color_continuous_scale="Reds",
            title="Airports Sized by Volume, Colored by Avg Delay (Min)"
        )
        st.plotly_chart(fig_map, use_container_width=True)
        
    with col_routes:
        st.subheader("Top 10 Most Delayed Route Pairs")
        
        df['route'] = df['origin_code'] + " ➔ " + df['dest_code']
        route_stats = df.groupby('route').agg(
            total_delay=('arrival_delay', 'sum'),
            avg_delay=('arrival_delay', 'mean'),
            flights=('flight_id', 'count')
        ).reset_index().sort_values(by='avg_delay', ascending=False).head(10)
        
        st.dataframe(
            route_stats.style.format({
                'total_delay': '{:,.0f}',
                'avg_delay': '{:.1f}',
                'flights': '{:,}'
            }),
            use_container_width=True,
            hide_index=True
        )

# -----------------------------------------------------------------------------
# TAB 3: WHEN (Temporal Analysis)
# -----------------------------------------------------------------------------
with tab_when:
    col_t1, col_t2 = st.columns(2)
    
    with col_t1:
        st.subheader("Delay Accumulation by Scheduled Departure Hour")
        hourly_stats = df.groupby('scheduled_hour').agg(
            avg_dep_delay=('departure_delay', 'mean'),
            avg_arr_delay=('arrival_delay', 'mean')
        ).reset_index()
        
        fig_hourly = go.Figure()
        fig_hourly.add_trace(go.Scatter(x=hourly_stats['scheduled_hour'], y=hourly_stats['avg_dep_delay'], mode='lines+markers', name='Departure Delay'))
        fig_hourly.add_trace(go.Scatter(x=hourly_stats['scheduled_hour'], y=hourly_stats['avg_arr_delay'], mode='lines+markers', name='Arrival Delay'))
        fig_hourly.update_layout(xaxis_title="Hour of Day (24h)", yaxis_title="Average Delay (Minutes)")
        
        st.plotly_chart(fig_hourly, use_container_width=True)
        st.caption("Key Decision Pattern: Delays typically cascade and compound throughout the afternoon and evening hours.")
        
    with col_t2:
        st.subheader("Day-of-Week Operational Heatmap")
        
        heatmap_data = df.pivot_table(
            index='day_of_week', 
            columns='scheduled_hour', 
            values='arrival_delay', 
            aggfunc='mean'
        )
        
        fig_heat = px.imshow(
            heatmap_data,
            labels=dict(x="Scheduled Hour", y="Day of Week (1=Mon, 7=Sun)", color="Avg Delay"),
            color_continuous_scale="YlOrRd"
        )
        st.plotly_chart(fig_heat, use_container_width=True)