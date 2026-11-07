from db import load_view

for view in ["v_airlines_delay_rate", "v_airlines_ranking", "v_airlines_reliability"]:
    df = load_view(view)
    print(f"{view}: {len(df)} lignes")
    print(df.head(3), "\n")