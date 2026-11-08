
import streamlit as st
from sqlalchemy import create_engine, URL

@st.cache_resource
def get_engine():

    connection_url = URL.create(
        drivername="postgresql+psycopg2",
        username=st.secrets["postgres"]["username"],
        password=st.secrets["postgres"]["password"],
        host=st.secrets["postgres"]["host"],
        port=st.secrets["postgres"]["port"],
        database=st.secrets["postgres"]["database"]
    )

    engine = create_engine(
        connection_url,
        pool_pre_ping=True
    )

    return engine
