# %% [markdown]
# # Block Archetypes — k-Means clustering for BQ5
#
# Assigns each CBD block an archetype label so investors can reason about
# "blocks like this one" rather than one block at a time. Writes to
# `stg.BlockCluster`, which `06_load_dimensions.sql` already reads into
# `DimBlock.ClusterID` / `ClusterName`.
#
# **Design decision — cluster on SHAPE, not SIZE.** Every feature is a
# proportion or a log ratio. Raw pedestrian counts are deliberately excluded:
# with absolute volume in the feature set, k-means separates big blocks from
# small blocks and tells you nothing the footfall map does not already show.
# What matters for concept selection is the *rhythm* of a block — when its
# people arrive and who they are.
#
# **Scope.** Only the 76 blocks with `HasFootfallCoverage = 1`. The other 527
# have no hourly profile and cannot be typed. They stay NULL in DimBlock.
#
# Run after `09_load_fact_blockannual.sql`. Afterwards re-run
# `06_load_dimensions.sql` to push labels into DimBlock.
#
# Requires: `pip install pandas scikit-learn pyodbc ipykernel`
#
# Run each cell with **Shift+Enter**.

# %%
# --- CELL 1: imports and connection ---------------------------------
import warnings
warnings.filterwarnings("ignore", category=UserWarning)

import pandas as pd
import numpy as np
import pyodbc
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score, silhouette_samples

pd.set_option("display.width", 200)
pd.set_option("display.max_columns", 50)

CONN_STR = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    "SERVER=LAPTOP-DBD3DPCV;"
    "DATABASE=MelbourneFB_DW;"
    "Trusted_Connection=yes;"
)

conn = pyodbc.connect(CONN_STR)
print("Connected.")
print(pd.read_sql("SELECT COUNT(*) AS Blocks FROM dw.DimBlock", conn))

# %%
# --- CELL 2: daypart rhythm -----------------------------------------
# How each block's traffic spreads across the seven non-overlapping
# dayparts. This is the slowest query (scans 1.6M rows) — expect ~1 min.
sql_daypart = """
SELECT
    b.BlockID,
    t.Daypart,
    SUM(CAST(f.TotalPedestrians AS BIGINT)) AS Ped
FROM dw.FactFootfallHourly f
JOIN dw.DimBlock b ON b.BlockKey = f.BlockKey
JOIN dw.DimTime  t ON t.TimeKey  = f.TimeKey
WHERE b.HasFootfallCoverage = 1
  AND f.BlockKey <> -1
GROUP BY b.BlockID, t.Daypart
"""
daypart = pd.read_sql(sql_daypart, conn)
print(f"{daypart['BlockID'].nunique()} blocks, {len(daypart)} block-daypart rows")
daypart.head()

# %%
# --- CELL 3: pivot to shares ----------------------------------------
# Shares are what make a 50,000-pedestrian block comparable to a
# 3,000-pedestrian one.
dp = daypart.pivot(index="BlockID", columns="Daypart", values="Ped").fillna(0)
dp = dp.div(dp.sum(axis=1), axis=0)
dp.columns = [f"share_{c.lower().replace(' ', '_')}" for c in dp.columns]
print(dp.shape)
dp.head()

# %%
# --- CELL 4: weekend orientation ------------------------------------
sql_weekend = """
SELECT
    b.BlockID,
    SUM(CASE WHEN d.IsWeekend = 1
             THEN CAST(f.TotalPedestrians AS BIGINT) ELSE 0 END) AS WeekendPed,
    SUM(CAST(f.TotalPedestrians AS BIGINT))                      AS TotalPed,
    COUNT(DISTINCT f.DateKey)                                    AS Days
FROM dw.FactFootfallHourly f
JOIN dw.DimBlock b ON b.BlockKey = f.BlockKey
JOIN dw.DimDate  d ON d.DateKey  = f.DateKey
WHERE b.HasFootfallCoverage = 1
  AND f.BlockKey <> -1
GROUP BY b.BlockID
"""
wk = pd.read_sql(sql_weekend, conn).set_index("BlockID")
wk["weekend_share"] = wk["WeekendPed"] / wk["TotalPed"]
wk["avg_daily_ped"] = wk["TotalPed"] / wk["Days"]     # for naming only
wk = wk[["weekend_share", "avg_daily_ped"]]
wk.describe()

# %%
# --- CELL 5: employment mix -----------------------------------------
# IsOfficeWorker / IsRetail / IsFoodBeverage are the flags already defined
# in DimIndustry, so the definition lives in ONE place.
sql_industry = """
SELECT
    b.BlockID,
    SUM(CASE WHEN i.IsOfficeWorker = 1 THEN fi.JobCount ELSE 0 END) AS OfficeJobs,
    SUM(CASE WHEN i.IsRetail       = 1 THEN fi.JobCount ELSE 0 END) AS RetailJobs,
    SUM(CASE WHEN i.IsFoodBeverage = 1 THEN fi.JobCount ELSE 0 END) AS FBJobs,
    SUM(CASE WHEN i.IndustryName = 'Education and Training'
             THEN fi.JobCount ELSE 0 END)                           AS EduJobs,
    SUM(CASE WHEN i.IndustryName = 'Accommodation'
             THEN fi.JobCount ELSE 0 END)                           AS HotelJobs,
    SUM(fi.JobCount)                                                AS TotalJobs
FROM dw.FactBlockIndustryAnnual fi
JOIN dw.DimBlock    b ON b.BlockKey    = fi.BlockKey
JOIN dw.DimIndustry i ON i.IndustryKey = fi.IndustryKey
WHERE b.HasFootfallCoverage = 1
  AND fi.CensusYear = (SELECT MAX(CensusYear) FROM dw.FactBlockIndustryAnnual)
GROUP BY b.BlockID
"""
ind = pd.read_sql(sql_industry, conn).set_index("BlockID")

# Blocks with zero recorded jobs (car parks, parks) get 0 shares rather
# than NaN — they are a legitimate type, not missing data.
for col, new in [("OfficeJobs", "office_share"),
                 ("RetailJobs", "retail_share"),
                 ("FBJobs",     "fb_share"),
                 ("EduJobs",    "edu_share"),
                 ("HotelJobs",  "hotel_share")]:
    ind[new] = np.where(ind["TotalJobs"] > 0, ind[col] / ind["TotalJobs"], 0.0)

ind_feat = ind[["office_share", "retail_share", "fb_share",
                "edu_share", "hotel_share"]]
ind_feat.describe().round(3)

# %%
# --- CELL 6: current supply -----------------------------------------
sql_supply = """
SELECT b.BlockID, a.TotalSeats, a.TotalFBVenues
FROM dw.FactBlockAnnual a
JOIN dw.DimBlock b ON b.BlockKey = a.BlockKey
WHERE b.HasFootfallCoverage = 1
  AND a.IsLatestCensusYear = 1
"""
sup = pd.read_sql(sql_supply, conn).set_index("BlockID")
print(sup.shape)
sup.head()

# %%
# --- CELL 7: assemble feature matrix --------------------------------
df = dp.join(wk, how="inner").join(ind_feat, how="left").join(sup, how="left")
df = df.fillna(0)

# Saturation enters as a LOG because it spans roughly 8 to 900. On a raw
# scale a handful of Docklands blocks would dominate every distance
# calculation and the clustering would degenerate into
# "Docklands vs everything else".
df["seat_saturation"] = np.where(
    df["avg_daily_ped"] > 0,
    df["TotalSeats"] / (df["avg_daily_ped"] / 1000),
    0.0
)
df["log_saturation"] = np.log1p(df["seat_saturation"])

FEATURES = (
    [c for c in df.columns if c.startswith("share_")]
    + ["weekend_share", "office_share", "retail_share",
       "edu_share", "hotel_share", "log_saturation"]
)

X = df[FEATURES].values
scaler = StandardScaler()
Xs = scaler.fit_transform(X)

print(f"Feature matrix: {X.shape[0]} blocks x {X.shape[1]} features")
for f in FEATURES:
    print("  ", f)

# %%
# --- CELL 8: choose k -----------------------------------------------
# Silhouette rather than elbow: with n=76 the elbow plot is ambiguous and
# reading it is subjective. Silhouette gives a single number that can be
# defended in the viva and stored in stg.BlockCluster.
scores = {}
for k in range(2, 9):
    km_test = KMeans(n_clusters=k, n_init=25, random_state=42)
    labels = km_test.fit_predict(Xs)
    scores[k] = silhouette_score(Xs, labels)
    print(f"k={k}: silhouette = {scores[k]:.4f}")

best_k = max(scores, key=scores.get)
print(f"\nBest k = {best_k} (silhouette {scores[best_k]:.4f})")

# k=2 often wins mathematically but only splits the CBD into "busy" and
# "quiet", which is not an actionable typology. Fall back to 3..6.
if best_k == 2:
    best_k = max({k: v for k, v in scores.items() if 3 <= k <= 8},
                 key=lambda k: scores[k])
    print(f"k=2 rejected as non-actionable. Using k={best_k} "
          f"(silhouette {scores[best_k]:.4f}).")

# %%
# --- CELL 9: fit final model ----------------------------------------
km = KMeans(n_clusters=best_k, n_init=50, random_state=42)
df["ClusterID"] = km.fit_predict(Xs)
df["SilhouetteScore"] = silhouette_samples(Xs, df["ClusterID"])

profile = df.groupby("ClusterID")[
    FEATURES + ["avg_daily_ped", "seat_saturation", "TotalFBVenues"]
].mean()
profile["n_blocks"] = df.groupby("ClusterID").size()

print("--- Cluster profiles (means) ---")
profile.round(3).T

# %%
# --- CELL 10: name the clusters -------------------------------------
# Names come from explicit rules on the centroids, not from eyeballing.
# An unexplained label like "Cluster 3" is worthless to a reader, and a
# hand-picked one is not reproducible.
def name_cluster(row, med):
    # Infrastructure first: no jobs and effectively no venues
    if row["log_saturation"] < 2.0 and row["TotalFBVenues"] < 2:
        return "Thoroughfare (no F&B)"
    if row["edu_share"] > 0.40:
        return "Education Precinct"
    if row["retail_share"] > 0.35:
        return "Retail Strip"
    if row["office_share"] > 0.50:
        return "Office Core"
    if row["hotel_share"] > 0.10:
        return "Visitor & Weekend"
    if row["avg_daily_ped"] < 5000 and row["seat_saturation"] > 300: 
        return "Low-traffic Oversupplied"
    return "Mixed Commercial"

med = profile[FEATURES].median()
names = {cid: name_cluster(profile.loc[cid], med) for cid in profile.index}

# Two clusters with the same label would be indistinguishable in a slicer.
seen = {}
for cid in sorted(names):
    base = names[cid]
    if base in seen:
        seen[base] += 1
        names[cid] = f"{base} {seen[base]}"
    else:
        seen[base] = 1

df["ClusterName"] = df["ClusterID"].map(names)

print("--- Assigned archetypes ---")
for cid in sorted(names):
    print(f"  Cluster {cid}: {names[cid]:<24} "
          f"n={int(profile.loc[cid,'n_blocks']):>3}  "
          f"mean saturation={profile.loc[cid,'seat_saturation']:>7.1f}  "
          f"mean daily ped={profile.loc[cid,'avg_daily_ped']:>9.0f}")

print("\n--- Blocks per archetype ---")
for cid in sorted(names):
    members = sorted(df.index[df["ClusterID"] == cid].astype(int))
    print(f"  {names[cid]}: {members}")

# %%
# --- CELL 11: write back to stg.BlockCluster ------------------------
# Truncate-and-load, matching the idempotency rule used throughout the
# pipeline: running this twice must not double the rows.
out = df.reset_index()[["BlockID", "ClusterID", "ClusterName", "SilhouetteScore"]]
out["BlockID"] = out["BlockID"].astype(str)
out["ClusterID"] = out["ClusterID"].astype(int)
out["SilhouetteScore"] = out["SilhouetteScore"].round(4)

cur = conn.cursor()
cur.execute("USE MelbourneFB_STG; TRUNCATE TABLE stg.BlockCluster;")
cur.fast_executemany = True
cur.executemany(
    """INSERT INTO MelbourneFB_STG.stg.BlockCluster
       (BlockID, ClusterID, ClusterName, SilhouetteScore)
       VALUES (?, ?, ?, ?)""",
    out.values.tolist()
)
conn.commit()
print(f"Wrote {len(out)} rows to stg.BlockCluster.")

# %%
# --- CELL 12: verify -------------------------------------------------
check = pd.read_sql(
    """SELECT ClusterName, COUNT(*) AS Blocks,
              CAST(AVG(SilhouetteScore) AS DECIMAL(6,4)) AS AvgSilhouette
       FROM MelbourneFB_STG.stg.BlockCluster
       GROUP BY ClusterName
       ORDER BY COUNT(*) DESC""",
    conn
)
print(check.to_string(index=False))

conn.close()
print("\nDone. Now re-run 06_load_dimensions.sql to populate DimBlock,")
print("then Refresh in Power BI. ClusterName becomes available as a slicer.")




# %%
