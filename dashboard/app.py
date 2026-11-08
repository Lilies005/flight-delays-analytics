"""Entry point of the dashboard: streamlit run dashboard/app.py

Streamlit builds the sidebar menu from the files in dashboard/pages/.
Each person owns one page file and nobody edits another person's page.
"""
import streamlit as st

st.set_page_config(page_title="Flight delays", layout="wide")

st.title("Flight delays: where, when and why")
st.write(
    "This dashboard helps an airline operations team see where, when and why "
    "flights are delayed or cancelled, so it knows where to act first. "
    "Choose a theme in the sidebar."
)
st.caption(
    "Delayed = arrival delay of 15 minutes or more. Cancelled and diverted "
    "flights are excluded from delay analyses. Source: 50,000-flight sample."
)
