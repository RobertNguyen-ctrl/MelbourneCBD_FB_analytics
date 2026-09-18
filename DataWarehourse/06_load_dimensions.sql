/* =====================================================================
   BUOC 06 -- LOAD DimBlock, DimSensor, DimWeather
   ---------------------------------------------------------------------
   DimDate / DimTime da nap o buoc 05.
   DimIndustry da seed san trong 04_dw_ddl.sql (20 + 1 dong).

   Thu tu trong file: DimBlock -> DimSensor -> DimWeather
   (DimSensor can NearestBlockMap; DimBlock can BlockFootfallCoverage)

   DIEU KIEN TIEN QUYET
     - stg.* da load day du (buoc 02)
     - stg.NearestBlockMap va stg.BlockFootfallCoverage da tinh (buoc 03)
   ===================================================================== */
USE MelbourneFB_DW;
GO

/* Chan chay khi staging chua san sang -------------------------------- */
IF NOT EXISTS (SELECT 1 FROM MelbourneFB_STG.stg.NearestBlockMap
               WHERE EntityType = 'SENSOR')
BEGIN
    RAISERROR('stg.NearestBlockMap chua co du lieu SENSOR. Chay 03_spatial_mapping.sql truoc.', 16, 1);
    RETURN;
END
GO


/* =====================================================================
   1. DimBlock  --  603 block, SCD Type 1 (ghi de)
      Nguon chinh: stg.Blocks (toa do, ten khu)
      Bo sung:     stg.BlockFootfallCoverage (co sensor <=200m hay khong)
                   stg.JobsByBlock (CLUE small area -- phu DU 603 block)
                   stg.BlockCluster (ket qua k-Means, neu da co)

      LUU Y: KHONG lay CLUESmallArea tu stg.CafeSeats. File do chi phu
      cac block CO F&B (~329 block) -> 274 block se bi NULL.
      JobsByBlock phu toan bo khung census -> dung lam nguon chuan.
   ===================================================================== */
PRINT '--- 1. DimBlock ---';

MERGE dw.DimBlock AS tgt
USING (
    SELECT
        TRY_CAST(b.block_id AS INT)                              AS BlockID,
        MAX(b.region_name)                                       AS RegionName,
        MAX(b.area_name)                                         AS AreaName,
        MAX(TRY_CAST(LTRIM(RTRIM(LEFT(b.[Geo Point],
            CHARINDEX(',', b.[Geo Point]) - 1))) AS DECIMAL(10,7)))    AS Lat,
        MAX(TRY_CAST(LTRIM(RTRIM(SUBSTRING(b.[Geo Point],
            CHARINDEX(',', b.[Geo Point]) + 1, 100))) AS DECIMAL(10,7))) AS Lon,
        MAX(cov.KhoangCachSensorGanNhat)                         AS DistSensor,
        MAX(CAST(ISNULL(cov.CoDoPhuFootfall, 0) AS INT))         AS HasCoverage
    FROM MelbourneFB_STG.stg.Blocks b
    LEFT JOIN MelbourneFB_STG.stg.BlockFootfallCoverage cov
           ON cov.BlockID = TRY_CAST(b.block_id AS INT)
    WHERE TRY_CAST(b.block_id AS INT) IS NOT NULL
      AND CHARINDEX(',', b.[Geo Point]) > 0
    GROUP BY TRY_CAST(b.block_id AS INT)
) AS src
ON tgt.BlockID = src.BlockID
WHEN MATCHED THEN UPDATE SET
    tgt.RegionName          = src.RegionName,
    tgt.AreaName            = src.AreaName,
    tgt.CentroidLatitude    = src.Lat,
    tgt.CentroidLongitude   = src.Lon,
    tgt.DistanceToSensorM   = src.DistSensor,
    tgt.HasFootfallCoverage = CAST(src.HasCoverage AS BIT)
WHEN NOT MATCHED BY TARGET THEN INSERT
    (BlockID, RegionName, AreaName, CentroidLatitude, CentroidLongitude,
     DistanceToSensorM, HasFootfallCoverage)
VALUES
    (src.BlockID, src.RegionName, src.AreaName, src.Lat, src.Lon,
     src.DistSensor, CAST(src.HasCoverage AS BIT));
GO

-- CLUE small area tu JobsByBlock (nguon phu du 603 block)
UPDATE b
SET b.CLUESmallArea = x.SmallArea
FROM dw.DimBlock b
JOIN (
    SELECT TRY_CAST([Block ID] AS INT) AS BlockID,
           MAX([CLUE small area])      AS SmallArea
    FROM MelbourneFB_STG.stg.JobsByBlock
    WHERE TRY_CAST([Block ID] AS INT) IS NOT NULL
      AND NULLIF([CLUE small area], '') IS NOT NULL
    GROUP BY TRY_CAST([Block ID] AS INT)
) x ON x.BlockID = b.BlockID;
GO

-- Sensor gan nhat cua tung block (de tra loi "block nay lay so tu dau")
UPDATE b
SET b.NearestSensorID = x.LocationID
FROM dw.DimBlock b
JOIN (
    SELECT m.BlockID,
           TRY_CAST(m.EntityKey AS INT) AS LocationID,
           ROW_NUMBER() OVER (PARTITION BY m.BlockID
                              ORDER BY m.DistanceMetres) AS rn
    FROM MelbourneFB_STG.stg.NearestBlockMap m
    WHERE m.EntityType = 'SENSOR'
) x ON x.BlockID = b.BlockID AND x.rn = 1;
GO

-- Phan nhom dan so ban ngay theo census year moi nhat (dung cho BQ4)
DECLARE @LatestYear NVARCHAR(10) =
    (SELECT MAX([Census year]) FROM MelbourneFB_STG.stg.JobsByBlock);

UPDATE b
SET b.DaytimePopulationBand =
    CASE WHEN j.TotalJobs >= 10000 THEN N'Very High'
         WHEN j.TotalJobs >=  3000 THEN N'High'
         WHEN j.TotalJobs >=   500 THEN N'Medium'
         WHEN j.TotalJobs >      0 THEN N'Low'
         ELSE                            N'None' END
FROM dw.DimBlock b
JOIN (
    SELECT TRY_CAST([Block ID] AS INT)            AS BlockID,
           TRY_CAST([Total jobs in block] AS INT) AS TotalJobs
    FROM MelbourneFB_STG.stg.JobsByBlock
    WHERE [Census year] = @LatestYear
) j ON j.BlockID = b.BlockID;
GO

-- k-Means (chi chay neu da co ket qua tu Python; khong co thi bo qua)
IF EXISTS (SELECT 1 FROM MelbourneFB_STG.stg.BlockCluster)
BEGIN
    UPDATE b
    SET b.ClusterID   = c.ClusterID,
        b.ClusterName = c.ClusterName
    FROM dw.DimBlock b
    JOIN MelbourneFB_STG.stg.BlockCluster c
      ON TRY_CAST(c.BlockID AS INT) = b.BlockID;
    PRINT 'Da gan ket qua k-Means vao DimBlock.';
END
ELSE
    PRINT 'stg.BlockCluster con rong -- ClusterName de NULL, chay lai sau khi co k-Means.';
GO

SELECT COUNT(*) AS DimBlock_Rows FROM dw.DimBlock;                -- 603 + 1
SELECT HasFootfallCoverage, COUNT(*) AS n FROM dw.DimBlock
WHERE BlockKey <> -1 GROUP BY HasFootfallCoverage;                -- 0:527, 1:76
SELECT COUNT(*) AS BlockThieuSmallArea FROM dw.DimBlock
WHERE CLUESmallArea IS NULL AND BlockKey <> -1;                   -- ky vong 0
GO


/* =====================================================================
   2. DimSensor  --  134 sensor, SCD Type 2
      Lan chay dau : insert het, ValidFrom = hom nay, IsCurrent = 1
      Lan chay sau : so RowHash (MD5). Khac -> dong dong cu
                     (IsCurrent = 0, ValidTo = hom qua) roi insert dong moi.
   ===================================================================== */
PRINT '--- 2. DimSensor (SCD2) ---';

DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);

DROP TABLE IF EXISTS #SrcSensor;
SELECT
    TRY_CAST(s.location_id AS INT)              AS LocationID,
    s.sensor_name                               AS SensorName,
    s.sensor_description                        AS SensorDescription,
    s.location_type                             AS LocationType,
    s.status                                    AS SensorStatus,
    NULLIF(s.direction_1, '')                   AS Direction1Name,
    NULLIF(s.direction_2, '')                   AS Direction2Name,
    TRY_CAST(s.latitude  AS DECIMAL(10,7))      AS Latitude,
    TRY_CAST(s.longitude AS DECIMAL(10,7))      AS Longitude,
    TRY_CAST(m.BlockID AS INT)                  AS BlockID,
    m.DistanceMetres                            AS DistanceToBlockM,
    TRY_CAST(s.installation_date AS DATE)       AS InstallationDate,
    CAST(CASE WHEN NULLIF(s.direction_1,'') IS NOT NULL
              THEN 1 ELSE 0 END AS BIT)         AS HasDirectionalData,
    HASHBYTES('MD5', CONCAT(
        ISNULL(s.sensor_name,''),        '|', ISNULL(s.sensor_description,''), '|',
        ISNULL(s.location_type,''),      '|', ISNULL(s.status,''),             '|',
        ISNULL(s.direction_1,''),        '|', ISNULL(s.direction_2,''),        '|',
        ISNULL(s.latitude,''),           '|', ISNULL(s.longitude,''),          '|',
        ISNULL(CAST(m.BlockID AS NVARCHAR(20)),''))) AS RowHash
INTO #SrcSensor
FROM MelbourneFB_STG.stg.SensorLocations s
LEFT JOIN MelbourneFB_STG.stg.NearestBlockMap m
       ON m.EntityType = 'SENSOR' AND m.EntityKey = s.location_id
WHERE TRY_CAST(s.location_id AS INT) IS NOT NULL;

-- SCD2 buoc 1: dong dong cu neu thuoc tinh doi
UPDATE d
SET d.IsCurrent = 0,
    d.ValidTo   = DATEADD(DAY, -1, @Today)
FROM dw.DimSensor d
JOIN #SrcSensor s ON s.LocationID = d.LocationID
WHERE d.IsCurrent = 1
  AND d.SensorKey <> -1
  AND (d.RowHash IS NULL OR d.RowHash <> s.RowHash);

-- SCD2 buoc 2: insert dong moi
INSERT INTO dw.DimSensor
    (LocationID, SensorName, SensorDescription, LocationType, SensorStatus,
     Direction1Name, Direction2Name, Latitude, Longitude,
     BlockID, DistanceToBlockM, InstallationDate, HasDirectionalData,
     RowHash, ValidFrom, ValidTo, IsCurrent)
SELECT
    s.LocationID, s.SensorName, s.SensorDescription, s.LocationType,
    s.SensorStatus, s.Direction1Name, s.Direction2Name,
    s.Latitude, s.Longitude, s.BlockID, s.DistanceToBlockM,
    s.InstallationDate, s.HasDirectionalData,
    s.RowHash, @Today, '9999-12-31', 1
FROM #SrcSensor s
WHERE NOT EXISTS (
    SELECT 1 FROM dw.DimSensor d
    WHERE d.LocationID = s.LocationID AND d.IsCurrent = 1);
GO

-- Stable panel: sensor co >= 95% do phu gio trong ky du lieu
;WITH Cov AS (
    SELECT TRY_CAST([Location_ID] AS INT) AS LocationID, COUNT(*) AS SoDong
    FROM MelbourneFB_STG.stg.PedestrianHourly
    GROUP BY TRY_CAST([Location_ID] AS INT)
), Ky AS (
    SELECT DATEDIFF(DAY,
             MIN(TRY_CAST([Sensing_Date] AS DATE)),
             MAX(TRY_CAST([Sensing_Date] AS DATE))) + 1 AS SoNgay
    FROM MelbourneFB_STG.stg.PedestrianHourly
)
UPDATE d
SET d.IsInStablePanel =
    CASE WHEN c.SoDong >= 0.95 * (SELECT SoNgay FROM Ky) * 24 THEN 1 ELSE 0 END
FROM dw.DimSensor d
JOIN Cov c ON c.LocationID = d.LocationID
WHERE d.IsCurrent = 1;
GO

SELECT COUNT(*) AS DimSensor_Rows FROM dw.DimSensor;              -- 134 + 1
SELECT LocationType, COUNT(*) AS n FROM dw.DimSensor
WHERE IsCurrent = 1 AND SensorKey <> -1 GROUP BY LocationType;    -- Outdoor 100, Indoor 34
SELECT IsInStablePanel, COUNT(*) AS n FROM dw.DimSensor
WHERE IsCurrent = 1 AND SensorKey <> -1 GROUP BY IsInStablePanel; -- 1: ~62
GO


/* =====================================================================
   3. DimWeather  --  JUNK DIMENSION, 12 + 1 dong
   ---------------------------------------------------------------------
   Thay cho viec lam mot fact weather rieng.
   4 dai nhiet do x 3 dai mua = 12 to hop, sinh bang CROSS JOIN.
   Sinh TAT CA to hop chu khong chi to hop xuat hien trong du lieu --
   nhu vay slicer trong Power BI on dinh, khong doi khi refresh.

   Nguong nhiet do chon theo bien do that cua du lieu: 1,8 -> 43,4 C
   Nguong mua: 0,1mm la gioi han duoi cua "co mua" theo Open-Meteo.
   ===================================================================== */
PRINT '--- 3. DimWeather (junk dimension) ---';

DELETE FROM dw.DimWeather WHERE WeatherKey <> -1;
GO

INSERT INTO dw.DimWeather
    (TemperatureBand, TemperatureBandSort, PrecipitationBand,
     PrecipitationBandSort, IsRaining, IsGoodForOutdoor, WeatherLabel)
SELECT
    t.Band, t.Srt, p.Band, p.Srt,
    CAST(CASE WHEN p.Band <> N'None' THEN 1 ELSE 0 END AS BIT),
    -- BQ7: dieu kien ly tuong cho ghe ngoai troi
    CAST(CASE WHEN p.Band = N'None' AND t.Band IN (N'Mild', N'Warm')
              THEN 1 ELSE 0 END AS BIT),
    t.Band + N', ' +
    CASE WHEN p.Band = N'None'  THEN N'no rain'
         WHEN p.Band = N'Light' THEN N'light rain'
         ELSE                        N'heavy rain' END
FROM (VALUES (N'Cold',1), (N'Mild',2), (N'Warm',3), (N'Hot',4)) AS t(Band, Srt)
CROSS JOIN (VALUES (N'None',1), (N'Light',2), (N'Heavy',3)) AS p(Band, Srt);
GO

SELECT COUNT(*) AS DimWeather_Rows FROM dw.DimWeather;             -- 12 + 1
SELECT WeatherKey, WeatherLabel, IsRaining, IsGoodForOutdoor
FROM dw.DimWeather ORDER BY TemperatureBandSort, PrecipitationBandSort;
GO


/* =====================================================================
   KIEM TRA TONG THE -- moi dimension phai co DUNG 1 Unknown Member
   ===================================================================== */
SELECT 'DimDate'     AS Bang, COUNT(*) AS SoDong FROM dw.DimDate
UNION ALL SELECT 'DimTime',     COUNT(*) FROM dw.DimTime
UNION ALL SELECT 'DimBlock',    COUNT(*) FROM dw.DimBlock
UNION ALL SELECT 'DimSensor',   COUNT(*) FROM dw.DimSensor
UNION ALL SELECT 'DimWeather',  COUNT(*) FROM dw.DimWeather
UNION ALL SELECT 'DimIndustry', COUNT(*) FROM dw.DimIndustry;

SELECT 'DimBlock' AS Bang, COUNT(*) AS UnknownMembers
FROM dw.DimBlock WHERE BlockKey = -1
UNION ALL SELECT 'DimSensor',   COUNT(*) FROM dw.DimSensor   WHERE SensorKey   = -1
UNION ALL SELECT 'DimWeather',  COUNT(*) FROM dw.DimWeather  WHERE WeatherKey  = -1
UNION ALL SELECT 'DimIndustry', COUNT(*) FROM dw.DimIndustry WHERE IndustryKey = -1;
-- ca 4 dong PHAI = 1
GO

PRINT 'Chay tiep 07_load_fact_footfall.sql';
GO

SELECT ClusterName, COUNT(*) AS Blocks
FROM dw.DimBlock 
WHERE ClusterName IS NOT NULL 
GROUP BY ClusterName 
ORDER BY COUNT(*) DESC;

