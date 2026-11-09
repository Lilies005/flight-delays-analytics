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

## Dataset

**2015 Flight Delays and Cancellations** (US Department of Transportation data, distributed on Kaggle). It contains flights, airlines and airports information for 2015.

The dataset files are **not included** in the repository because of their size. Download them and place them at the paths expected by `sql/01_load_data.sql`.

## Methodology

- A flight is considered **delayed** when `arrival_delay >= 15` minutes.
- **Cancelled** and **diverted** flights are excluded.
- Flights with a **missing arrival delay** are excluded.
- A minimum threshold of **30 eligible flights** is applied to airports and routes, to avoid misleading rates on small samples.
- Delay rate (%) = delayed flights / eligible flights × 100.

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
│       └── airports_routes.py  # Airports & routes analysis page
│
├── sql/
│   ├── 00_schema.sql           # Tables and structure
│   ├── 01_load_data.sql        # Dataset loading
│   ├── airlines.sql            # Airlines views and indexes
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
```

These scripts create the analytical views and indexes required by the dashboard.

> **Important:** execute the scripts in the order shown above so that tables, data and views are available.

## Run the Dashboard

From the project root, with the virtual environment activated:

```powershell
streamlit run dashboard/app.py
```

The app opens in your browser. Use the sidebar to navigate between pages.

## Database Objects

Main views used by the Airports & Routes page:

| View | Description |
|---|---|
| `v_airports_routes_airport_delays` | Delay statistics per airport (eligible flights, delayed flights, delay rate, average arrival delay) |
| `v_airports_routes_top_routes` | Ranked routes with the most delayed flights (`route_rank`) |

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
