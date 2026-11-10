# ✈️ Flight Delays Analysis — 2015

Interactive dashboard analyzing flight delays in the United States, built with **PostgreSQL**, **SQL** and **Streamlit**.

## Table of Contents

- [Project Overview](#project-overview)
- [Key Features](#key-features)
- [Dataset](#dataset)
- [Methodology](#methodology)
- [Technologies Used](#technologies-used)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Installation and Setup](#installation-and-setup)
- [Run the Dashboard](#run-the-dashboard)
- [Run the AI Comparison Dashboard](#run-the-ai-comparison-dashboard)
- [Database Objects](#database-objects)
- [Troubleshooting](#troubleshooting)
- [Git Workflow](#git-workflow)
- [Authors](#authors)

## Project Overview

This project analyzes flight delays in the United States using the **2015 Flight Delays and Cancellations** dataset.

The main objectives are to:

- Analyze flight delays across different airlines.
- Evaluate airline reliability and performance.
- Identify airports with significant delay patterns.
- Analyze the most delayed flight routes.

Data is stored and prepared in PostgreSQL (tables, analytical views, indexes), then served to an interactive multi-page Streamlit dashboard.

## Key Features

### Airlines Analysis

- Airline delay rates
- Average arrival delays
- Airline performance rankings
- Reliability analysis

### Airports & Routes Analysis

- KPI cards: most delayed airport, highest airport delay rate, most delayed route, highest route delay rate
- Interactive airport ranking by **delay volume** or **delay rate (%)**, with a selectable top 5 / 10 / 15
- Top 10 most delayed routes (origin → destination)
- Rich hover tooltips (city, state, eligible flights, delay rate, average arrival delay)
- Expandable detailed data tables

### Time Analysis
- Overall delay rate and 95% confidence interval
- Delay patterns by departure hour, weekday and month
- Interactive heatmap and filters
- Comparison of delay rates across periods of the day
- Identification of the most and least affected time periods

### Cancellations Analysis
- Overall cancellation rate and monthly trends
- Cancellation reasons and their monthly distribution
- Cancellation rates by airline
- Interactive airline and month filters
- Key cancellation indicators and impact on arrival-delay averages
- Recommendations based on the main cancellation patterns

## Dataset

**2015 Flight Delays and Cancellations** (US Department of Transportation data, distributed on Kaggle). It contains flights, airlines and airports information for 2015.

The dataset files are **not included** in the repository because of their size. Download them and place them at the paths expected by `sql/01_load_data.sql`.
Time Analysis

## Methodology

- A flight is considered **delayed** when `arrival_delay >= 15` minutes.
- **Cancelled** and **diverted** flights are excluded.
- Flights with a **missing arrival delay** are excluded.
- A minimum threshold of **30 eligible flights** is applied to airports and routes, to avoid misleading rates on small samples.
- Delay rate (%) = delayed flights / eligible flights × 100.

Time Analysis:

-A flight is considered delayed when its arrival delay is 15 minutes or more.
-Cancelled and diverted flights are excluded from delay calculations.
-Groups with fewer than 30 eligible flights are excluded from comparative delay-rate analysis.
-Wilson 95% confidence intervals are used to assess differences between groups.

Cancellations Analysis:

-Cancellation rate (%) = cancelled flights / all scheduled flights × 100.
-Cancellation reasons are grouped into Airline, Air system (NAS), Weather, Security and Unknown.
-A minimum threshold of 30 flights is applied to airline and monthly comparisons.
-Cancellation shares based on fewer than 30 cancelled flights are displayed with a warning.
-Cancelled and diverted flights are excluded from arrival-delay averages because their arrival-delay values are not representative of completed flights.

## Technologies Used

| Technology | Purpose |
|---|---|
| **Python** | Dashboard development and data processing |
| **PostgreSQL** | Database management |
| **SQL** | Data preparation, analysis, views and indexes |
| **Pandas** | Data manipulation |
| **Streamlit** | Interactive dashboard |
| **Plotly** | Data visualization |
| **SQLAlchemy** | Database connection |
| **psycopg2-binary** | PostgreSQL driver |
| **python-dotenv** | Environment variable management |

## Project Structure

```text
flight-delays/
│
├── dashboard/
│   ├── app.py                  # Streamlit entry point
│   ├── database.py             # PostgreSQL connection (SQLAlchemy engine)
│   └── pages/
│       ├── airlines.py         # Airlines analysis page
        ├── cancellations.py     # cancellations analysis page
        ├── airports_routes.py  # Airports & routes analysis page 
│       └── time_analysis.py  # Time analysis page
│
├── ai_comparison/
│   └── ai_dashboard.py         # AI model comparison dashboard
│
├── sql/
│   ├── 00_schema.sql           # Tables and structure
│   ├── 01_load_data.sql        # Dataset loading
│   ├── airlines.sql            # Airlines views and indexes
    ├── time.sql                # Time analysis views
    ├── cancellations.sql       # Cancellations views and indexes 
│   └── airports_routes.sql     # Airports & routes views and indexes

│
├── .env.example                # Environment variables template
├── .gitignore
├── requirements.txt
└── README.md
```

## Prerequisites

- Python 3.10 or later
- PostgreSQL
- Git

## Installation and Setup

### 1. Clone the Repository

```bash
git clone https://github.com/Lilies005/flight-delays-analytics.git
cd flight-delays-analytics
```

### 2. Create and Activate a Virtual Environment

```bash
python -m venv venv
```

On Windows (PowerShell):

```powershell
.\venv\Scripts\Activate
```

On macOS / Linux:

```bash
source venv/bin/activate
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

### 4. Create the PostgreSQL Database

```sql
CREATE DATABASE flights_db;
```

### 5. Configure Environment Variables

Copy `.env.example` to `.env` in the project root:

```powershell
copy .env.example .env
```

Then edit `.env` with your PostgreSQL credentials:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=flights_db
DB_USER=postgres
DB_PASSWORD=your_password
```

Replace `your_password` with your PostgreSQL password. **Never commit your `.env` file** (it is ignored by `.gitignore`).

### 6. Create the Database Schema

```powershell
psql -U postgres -d flights_db -f "sql/00_schema.sql"
```

### 7. Load the Dataset

```powershell
psql -U postgres -d flights_db -f "sql/01_load_data.sql"
```

> **Note:** make sure the dataset files are available at the paths expected by `01_load_data.sql` before executing it.

### 8. Execute the SQL Analysis Scripts

```powershell
psql -U postgres -d flights_db -f "sql/airlines.sql"
psql -U postgres -d flights_db -f "sql/airports_routes.sql"
psql -U postgres -d flights_db -f "sql/time.sql"
psql -U postgres -d flights_db -f "sql/delay_causes.sql"
psql -U postgres -d flights_db -f "sql/cancellations.sql"
```

These scripts create the analytical views and indexes required by the dashboard.

> **Important:** execute the scripts in the order shown above so that tables, data and views are available.

## Run the Dashboard

From the project root, with the virtual environment activated:

```powershell
streamlit run dashboard/app.py
```

The app opens in your browser. Use the sidebar to navigate between pages.

## Run the AI Comparison Dashboard

The project also includes an AI comparison dashboard for exploring and comparing flight delay prediction models.

From the project root, with the virtual environment activated, run the following commands on Windows (Command Prompt):

```cmd
set DB_USER=postgres
set DB_NAME=flights_db
set DB_PASSWORD=your_password
python -m streamlit run ai_comparison\ai_dashboard.py
```

Replace `your_password` with your PostgreSQL password.

The AI comparison dashboard will open in your browser.

> **Note:** These environment variables are set only for the current terminal session. Make sure PostgreSQL is running and the required database is available before launching the dashboard.

## Database Objects

Main views used by the Airports & Routes page:

| View | Description |
|---|---|
| `v_airports_routes_airport_delays` | Delay statistics per airport (eligible flights, delayed flights, delay rate, average arrival delay) |
| `v_airports_routes_top_routes` | Ranked routes with the most delayed flights (`route_rank`) |

Time Analysis
| View | Description |
v_time_cube|Aggregated flight statistics used for time-based analysis and filtering
v_time_overall|Overall delay statistics
v_time_by_hour|Delay statistics by scheduled departure hour
v_time_by_weekday|Delay statistics by day of the week
v_time_monthly_trend|Monthly flight delay trends
v_time_by_period|Delay statistics by period of the day

Cancellations Analysis

| View | Description |
v_cancel_airline_month|Flight and cancellation statistics by airline and month
v_cancel_airline_month_reason|Monthly cancellation statistics grouped by cancellation reason
v_cancel_by_airline|Cancellation performance and rankings by airline
v_cancel_delay_check|Comparison of arrival-delay averages using correct and incorrect treatment of NULL values
Query results are cached for 5 minutes in the dashboard (`st.cache_data(ttl=300)`).

## Troubleshooting

Before launching the dashboard, check that:

- PostgreSQL is running.
- The `flights_db` database exists.
- The schema has been created and the dataset loaded.
- All SQL analysis scripts have been executed.
- The `.env` file contains the correct credentials.

| Problem | Likely cause / fix |
|---|---|
| `Error loading PostgreSQL data` in the dashboard | A view is missing: re-run `airlines.sql` and `airports_routes.sql` |
| Connection refused / authentication failed | Check PostgreSQL is running and `.env` credentials |
| `ModuleNotFoundError` | Virtual environment not activated or dependencies not installed |

## Git Workflow

- `main` holds the stable version.
- Each feature is developed on its own branch (e.g. `airlines-dashboard`, `airports-routes-dashboard`) and merged through a pull request.
- Before opening a pull request, merge `main` into your branch to resolve conflicts locally:

```bash
git fetch origin
git merge origin/main
```

## Authors

Developed as part of a Database Systems and Analysis project (2CS, BDDA).
