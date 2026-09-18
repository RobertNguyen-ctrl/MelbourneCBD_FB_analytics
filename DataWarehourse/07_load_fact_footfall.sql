/* =====================================================================
   BUOC 07 -- FACT 1: FactFootfallHourly   1.613.524 dong
   ---------------------------------------------------------------------
   GRAIN: 1 sensor x 1 ngay x 1 gio
   NGUON: stg.PedestrianHourly (1,6 tr dong) + stg.Weather (17.520 dong)
   PHUC VU: BQ1 (phia cau), BQ2, BQ3, BQ7

   HAI DIEM KY THUAT DANG NOI TRONG BAO CAO

   1) Weather duoc gan TRUC TIEP vao fact, khong tach fact rieng.
      Weather o grain ngay x gio -- THO HON grain cua fact nay
      (sensor x ngay x gio). Nen moi dong footfall anh xa vao DUNG MOT
      ban ghi weather. Day la phep gan hop le trong Kimball va no xoa
      bo rui ro fan-out khi so sanh footfall voi thoi tiet trong BI.
      Neu de weather thanh fact rieng, Power BI phai noi 2 fact qua
      DimDate + DimTime -> quan he many-to-many -> nhan doi luot di bo.

   2) 3 sensor mo coi (28, 65, 78) co trong file counts nhung KHONG co
      trong file sensor locations. Chung chiem ~1,58% so dong. Xu ly:
      tro ve Unknown Member (SensorKey = -1) chu KHONG xoa dong, va bao
      cao lai ty le nay. Xoa dong se lam sai tong luot nguoi.
   ===================================================================== */
USE MelbourneFB_DW;
GO

/* Dieu kien tien quyet ----------------------------------------------- */
IF (SELECT COUNT(*) FROM dw.DimSensor) < 100
BEGIN
    RAISERROR('DimSensor chua nap xong. Chay 06_load_dimensions.sql truoc.', 16, 1);
    RETURN;
END
IF (SELECT COUNT(*) FROM dw.DimWeather) <> 13
BEGIN
    RAISERROR('DimWeather phai co 13 dong (12 to hop + 1 Unknown).', 16, 1);
    RETURN;
END
GO


/* =====================================================================
   1. VAT CHAT HOA WEATHER VAO BANG TAM
   ---------------------------------------------------------------------
   Bat buoc phai materialize, KHONG dung CTE. Ly do: neu de weather
   trong CTE thi optimizer se tinh lai bieu thuc TRY_CAST cho tung
   trong 1,6 trieu dong ben ngoai. Voi bang tam + PK thi chi 17.520
   phep tinh, roi join bang index seek.

   Cot [time] o staging co dang 2024-08-05T00:00 (chuoi ISO).
   Tach: 10 ky tu dau = ngay, ky tu 12-13 = gio.
   ===================================================================== */
PRINT '--- 1. Chuan bi bang tam weather ---';

DROP TABLE IF EXISTS #Weather;
CREATE TABLE #Weather (
    DateKey         INT           NOT NULL,
    TimeKey         TINYINT       NOT NULL,
    TemperatureC    DECIMAL(5,2)  NULL,
    PrecipitationMM DECIMAL(6,2)  NULL,
    WeatherKey      INT           NOT NULL,
    PRIMARY KEY CLUSTERED (DateKey, TimeKey)
);

INSERT INTO #Weather (DateKey, TimeKey, TemperatureC, PrecipitationMM, WeatherKey)
SELECT
    YEAR(w.Dt)*10000 + MONTH(w.Dt)*100 + DAY(w.Dt),
    w.Hr,
    w.TempC,
    w.PrecipMM,
    ISNULL(dwx.WeatherKey, -1)
FROM (
    SELECT
        TRY_CAST(LEFT(x.[time], 10) AS DATE)            AS Dt,
        TRY_CAST(SUBSTRING(x.[time], 12, 2) AS TINYINT) AS Hr,
        TRY_CAST(x.TemperatureC    AS DECIMAL(5,2))     AS TempC,
        TRY_CAST(x.PrecipitationMM AS DECIMAL(6,2))     AS PrecipMM
    FROM MelbourneFB_STG.stg.Weather x
) w
-- Phan dai roi tra ve WeatherKey. Nguong phai KHOP voi 12_load_dimensions
LEFT JOIN dw.DimWeather dwx
       ON dwx.TemperatureBand =
            CASE WHEN w.TempC <  10 THEN N'Cold'
                 WHEN w.TempC <  20 THEN N'Mild'
                 WHEN w.TempC <= 28 THEN N'Warm'
                 ELSE                     N'Hot' END
      AND dwx.PrecipitationBand =
            CASE WHEN w.PrecipMM IS NULL OR w.PrecipMM <= 0.1 THEN N'None'
                 WHEN w.PrecipMM <= 2.0                       THEN N'Light'
                 ELSE                                              N'Heavy' END
WHERE w.Dt IS NOT NULL AND w.Hr IS NOT NULL;

SELECT COUNT(*) AS Weather_Rows FROM #Weather;                     -- 17520
SELECT MIN(DateKey) AS TuNgay, MAX(DateKey) AS DenNgay FROM #Weather;
SELECT COUNT(*) AS WeatherKhongPhanDuocDai FROM #Weather WHERE WeatherKey = -1;
-- ky vong 0. Neu > 0 thi nguong o day va o DimWeather khong khop nhau.
GO


/* =====================================================================
   2. LOAD FACT
      Truncate-and-load (idempotent). Chay lai bao nhieu lan cung ra
      dung so dong -- bai hoc tu su co double-load o staging truoc day.
   ===================================================================== */
PRINT '--- 2. FactFootfallHourly ---';

TRUNCATE TABLE dw.FactFootfallHourly;
GO

DECLARE @t0 DATETIME2 = SYSDATETIME();

INSERT INTO dw.FactFootfallHourly
    (DateKey, TimeKey, SensorKey, BlockKey, WeatherKey, SourceRecordID,
     Direction1Count, Direction2Count, TotalPedestrians,
     TemperatureC, PrecipitationMM)
SELECT
    p.DateKey,
    p.Hr,
    ISNULL(s.SensorKey, -1),      -- 3 sensor mo coi -> Unknown Member
    ISNULL(b.BlockKey,  -1),
    ISNULL(w.WeatherKey, -1),     -- gio thieu weather -> Unknown Member
    p.SrcID,
    p.Dir1, p.Dir2, p.Total,
    w.TemperatureC, w.PrecipitationMM
FROM (
    SELECT
        YEAR(TRY_CAST(f.[Sensing_Date] AS DATE))*10000
          + MONTH(TRY_CAST(f.[Sensing_Date] AS DATE))*100
          + DAY(TRY_CAST(f.[Sensing_Date] AS DATE))  AS DateKey,
        TRY_CAST(f.[HourDay] AS TINYINT)             AS Hr,
        TRY_CAST(f.[Location_ID] AS INT)             AS LocationID,
        TRY_CAST(f.[ID] AS BIGINT)                   AS SrcID,
        TRY_CAST(f.[Direction_1] AS INT)             AS Dir1,
        TRY_CAST(f.[Direction_2] AS INT)             AS Dir2,
        TRY_CAST(f.[Total_of_Directions] AS INT)     AS Total
    FROM MelbourneFB_STG.stg.PedestrianHourly f
    WHERE TRY_CAST(f.[Sensing_Date] AS DATE) IS NOT NULL
      AND TRY_CAST(f.[HourDay] AS TINYINT) IS NOT NULL
      AND TRY_CAST(f.[Total_of_Directions] AS INT) IS NOT NULL
) p
LEFT JOIN dw.DimSensor s ON s.LocationID = p.LocationID AND s.IsCurrent = 1
LEFT JOIN dw.DimBlock   b ON b.BlockID   = s.BlockID
LEFT JOIN #Weather      w ON w.DateKey   = p.DateKey AND w.TimeKey = p.Hr;

SELECT DATEDIFF(SECOND, @t0, SYSDATETIME()) AS GiaySuDung;
-- Ghi lai so nay cho muc "kho khan gap phai" trong bao cao
GO


/* =====================================================================
   3. KIEM TRA
   ===================================================================== */
SELECT COUNT(*) AS FactFootfall_Rows, 1613524 AS KyVong
FROM dw.FactFootfallHourly;

-- Ty le dung Unknown Member: bao cao con so nay, khong che di
SELECT
    SUM(CASE WHEN SensorKey  = -1 THEN 1 ELSE 0 END) AS DongUnknownSensor,
    CAST(100.0 * SUM(CASE WHEN SensorKey = -1 THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(6,3))                 AS PhanTramSensor,
    SUM(CASE WHEN BlockKey   = -1 THEN 1 ELSE 0 END) AS DongUnknownBlock,
    SUM(CASE WHEN WeatherKey = -1 THEN 1 ELSE 0 END) AS DongUnknownWeather
FROM dw.FactFootfallHourly;
-- ky vong: Sensor ~25.500 dong (~1,58%), Weather = 0

-- Do phu weather: bao nhieu % dong co gan duoc thoi tiet
SELECT CAST(100.0 * COUNT(TemperatureC) / COUNT(*) AS DECIMAL(6,2)) AS PhanTramCoWeather
FROM dw.FactFootfallHourly;

-- Khoang thoi gian
SELECT MIN(d.FullDate) AS TuNgay, MAX(d.FullDate) AS DenNgay
FROM dw.FactFootfallHourly f JOIN dw.DimDate d ON d.DateKey = f.DateKey;
-- ky vong 2024-08-05 -> 2026-08-04

-- Test BQ2 chay duoc: 4 cua so gio phai cho ra 4 con so KHAC NHAU
-- va tong cua chung LON HON 100% (vi cac cua so chong lap nhau)
SELECT
    CAST(100.0 * SUM(CASE WHEN t.InCafeWindow   = 1 THEN f.TotalPedestrians ELSE 0 END)
         / SUM(f.TotalPedestrians) AS DECIMAL(6,2)) AS PhanTram_Cafe,
    CAST(100.0 * SUM(CASE WHEN t.InLunchWindow  = 1 THEN f.TotalPedestrians ELSE 0 END)
         / SUM(f.TotalPedestrians) AS DECIMAL(6,2)) AS PhanTram_Lunch,
    CAST(100.0 * SUM(CASE WHEN t.InAllDayWindow = 1 THEN f.TotalPedestrians ELSE 0 END)
         / SUM(f.TotalPedestrians) AS DECIMAL(6,2)) AS PhanTram_AllDay,
    CAST(100.0 * SUM(CASE WHEN t.InNightWindow  = 1 THEN f.TotalPedestrians ELSE 0 END)
         / SUM(f.TotalPedestrians) AS DECIMAL(6,2)) AS PhanTram_Night
FROM dw.FactFootfallHourly f
JOIN dw.DimTime t ON t.TimeKey = f.TimeKey;
-- Tong 4 cot > 100 la DUNG. Neu = 100 thi 4 cot dang loai tru nhau,
-- tuc la da lam sai giong v1.

-- Test BQ7 chay duoc: footfall theo dieu kien thoi tiet
SELECT w.WeatherLabel,
       COUNT(*)                              AS SoGioQuanSat,
       AVG(CAST(f.TotalPedestrians AS FLOAT)) AS LuotTrungBinhMoiGio
FROM dw.FactFootfallHourly f
JOIN dw.DimWeather w ON w.WeatherKey = f.WeatherKey
WHERE f.SensorKey <> -1
GROUP BY w.WeatherLabel, w.TemperatureBandSort, w.PrecipitationBandSort
ORDER BY w.TemperatureBandSort, w.PrecipitationBandSort;
GO

DROP TABLE IF EXISTS #Weather;
GO

PRINT 'Chay tiep 08_load_fact_industry.sql';
GO
