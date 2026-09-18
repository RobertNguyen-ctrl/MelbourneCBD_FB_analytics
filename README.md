# Melbourne CBD F&B Investment Analytics

**Where should an investor open a new food & beverage venue in Melbourne CBD — and what should it sell, and when should it open?**

An end-to-end data warehouse and BI system that answers those questions from five open datasets (~2.37 million rows), built with SQL Server, SSIS, Power BI, Python and R.

---

## Recommendation

**Open on Block 51 (CBD West) — a café and after-work drinks concept, trading 08:00–20:00, Monday to Friday.**

| Evidence | Figure |
|---|---|
| Undersupply | 32,883 pedestrians/day but only 832 F&B seats — a gap of 2,291 seats |
| Low competition | 13 venues, of which only 2 are drinks-led |
| Customer base | Office workers 56.8% of daytime population; Real Estate occupies 40.4% of ground-floor industry mix |
| Demand shape | Café window 40.4% of footfall vs lunch window 30% — people drink more than they eat here |
| Future demand | 607 residential dwellings under construction: 5th highest of 56 blocks, 18× the median |

Block 35 (Retail Strip) and Block 15 (Mixed Commercial) have larger absolute seat gaps but are already crowded — 21 and 37 venues respectively. Block 51 pairs a real shortage with a thin competitive field.

---

## The metric this project is built on

**Seat Saturation** = F&B seats per 1,000 daily pedestrians on a block.
Low saturation means demand is not being served — that is the opportunity.

**Seat Gap** = the additional seats a block would need to reach the CBD median of **94.98 seats per 1,000 pedestrians/day**.

Saturation across the analysed blocks ranges from **15.9 to 606.6** — a near 40× spread. **28 of 56 blocks** sit below the median.

### A dead end worth recording

The original plan was to measure venue survival — which locations keep businesses alive longest. CLUE records 8,112 trading names across 1,920 addresses (2002–2024), but roughly **76% of apparent closures are rebrands or ownership changes**, and no field distinguishes the two. The approach was abandoned in favour of measuring supply–demand imbalance directly, which does not depend on an outcome variable the data cannot support.

---

## Scope

The city has 603 blocks. Only 56 are analysable, and the binding constraint is the sensor network:

| Filter | Blocks remaining |
|---|---|
| All City of Melbourne blocks | 603 |
| Pedestrian sensor within 200 m | 76 |
| Has F&B seating | 68 |
| Footfall ≥ 2,000/day | **56** |

Those 56 blocks nevertheless hold **44% of all CBD venues and 39% of all seats**. The warehouse stores all 603 blocks, so no schema change is needed when the city expands its sensor network.

---

## Data sources

All open data, CC BY 4.0.

| Source | Content | Rows |
|---|---|---|
| Pedestrian Counting System | Hourly counts, 134 sensors | 1,613,524 |
| CLUE Census 2002–2024 | F&B seats, employment, dwellings | ~600,000 |
| Development Activity Monitor | Projects under construction | snapshot |
| Victorian Liquor Licences | Licence type, trading hours | 47,524 |
| Open-Meteo API | Hourly temperature and rainfall | ~17,500 |

---

## Architecture

```
5 open sources  →  MelbourneFB_STG  →  MelbourneFB_DW  →  Power BI  →  Recommendation
   CSV/XLSX/API     BULK INSERT          Galaxy schema      5 pages
                    truncate-and-load    3 fact · 7 dim
                                         ~1.97M fact rows
                                              ↓
                                     Python (k-means) · R (hypothesis tests)
```

**Warehouse** — galaxy schema, 3 fact tables and 7 dimensions. SCD Type 2 on `DimBlock` and `DimSensor` using MD5 hash comparison. Blocks are joined to sensors by a 200 m spatial mapping.

**ETL** — three SSIS packages (`00_Master` orchestrates `01_Load_Staging` and `02_Load_DW`) driving 12 numbered SQL scripts in sequence. The pipeline is idempotent: a machine shutdown mid-load once duplicated the entire LiquorLicences table (47,524 rows), after which every load was rebuilt on a truncate-and-load pattern.

**A modelling problem worth noting** — `FactFootfallHourly` has a grain of block × day × hour across ~730 days, while the two census fact tables carry exactly one `DateKey` per year (31 December). Joined through a shared `DimDate`, the two groups intersect on a single day and every census measure returned BLANK. Resolved by introducing `DimCensusYear` at year grain and marking the `DimDate` relationship to the census facts inactive.

---

## Findings

**Trading hours.** 16:00–18:00 carries 23.9% of daily footfall, against 13.7% for the lunch window and 11.0% for the morning. The absolute peak is 17:00 on Thursday. 07:00 accounts for only 3.4% — opening at 7am runs ahead of demand, so the recommendation opens at 8am. Sunday is the weakest day at 11.6%.

**Night trade is not worth it.** Hours after 22:00 account for 4.93% of weekly footfall, while 267 late-night liquor licences already exist across 89 blocks. Only 31 of those 267 (12%) are 24-hour licences — even venues permitted to trade late mostly choose not to. Thin demand, thick supply.

**Block archetypes.** k-means groups 71 blocks into 7 archetypes (silhouette 0.19 — the blocks sit on a continuum rather than in discrete clusters, so the labels are interpretive, not a hard classification). Ranked by aggregate seat gap: Thoroughfare +11.3K, Retail Strip +5.1K, Education Precinct +1.6K, Office Core −2.7K, Visitor & Weekend −3.1K, Low-traffic −4.4K, Mixed Commercial −6.9K. Thoroughfare tops the list but is public infrastructure — Princes Bridge, Federation Square, the RMIT campus — with enormous footfall and no leasable frontage. Excluded.

**Outdoor seating pays.** 80% of observed hours are suitable for outdoor seating and rain falls in only 8.67% of hours. A paired regression — comparing like hours, like weekdays and like temperature bands, differing only in rain — puts the effect of rain at **−15.7%** of footfall (95% CI −17.4% to −13.9%, p = 2.8e-60). Light rain costs roughly 4,300 pedestrians/hour, heavy rain roughly 9,200. A naive comparison of wet and dry hours shows only −6%, because Melbourne rain tends to fall at night and in winter when streets are already empty. Customers respond to the volume of rain, not merely its presence — which is what makes an awning worth the capital.

**Statistical tests (R).**

| Test | Result | Reading |
|---|---|---|
| Spearman — footfall vs seats | rho = 0.45, p < 0.001, n = 56 | The market does allocate seats toward footfall, but loosely. The residual is the opportunity. |
| Kruskal-Wallis — saturation across 7 CLUE areas | chi² = 0.94, df = 6, p = 0.988 | Saturation does not differ between precincts. Variation is within them — which is why site selection must be done block by block, not suburb by suburb. |

---

## Repository layout

```
DataWarehouse/        12 numbered SQL scripts (DDL, staging load, spatial mapping,
                      dimensions, facts, DQ tests) + galaxy schema diagram (.drawio)
ETL/ssis/             3 SSIS packages and the Visual Studio project
Analysis-and-Insights/  Power BI dashboard (.pbix), k-means script (Python),
                      hypothesis tests (Quarto/R)
Documents/            Project report and dashboard screenshots
```

## Stack

SQL Server · SSIS (Visual Studio 2026) · Power BI Desktop · Python (scikit-learn) · R / Quarto · draw.io

## Reproducing

1. Create `MelbourneFB_STG` and `MelbourneFB_DW` on a SQL Server instance.
2. Download the five source datasets (links above) into a landing folder.
3. Run `DataWarehouse/` scripts 01–10 in numbered order, or execute `ETL/ssis/00_Master.dtsx`.
4. Run the Python clustering script; results are written back to `stg.BlockCluster`.
5. Open the `.pbix` and point it at `MelbourneFB_DW`.

Connections use Windows Authentication against `localhost`.

---

## Limitations

- **Coverage.** 56 of 603 blocks, limited by the city's 134-sensor network — not by the architecture, which already holds all 603.
- **Time mismatch.** Seat counts come from CLUE 2024; footfall runs to 2026. Gap estimates skew optimistic if venues have opened since.
- **The median is not an optimum.** 94.98 seats per 1,000 pedestrians is what the market currently does, not what is economically ideal. Establishing the latter needs revenue data, which is not open.
- **Sensors count passers-by.** They cannot distinguish someone stopping to buy from someone walking through.

---

## Author

Nguyen Phan Quang Bao — FUNiX DAP305x capstone, September 2026.

Licensed under MIT. Source data remains CC BY 4.0, City of Melbourne and Open-Meteo.
