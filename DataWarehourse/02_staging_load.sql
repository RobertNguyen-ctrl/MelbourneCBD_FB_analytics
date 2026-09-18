/* =====================================================================
   BUOC 02 -- BULK LOAD 10 NGUON CSV VAO STAGING
   ---------------------------------------------------------------------
   Chay SAU 01_staging_ddl.sql

   THU TU: file nho truoc, file lon sau. Neu file nho loi thi dung ngay,
   khong mat thoi gian cho file 121 MB.

   DUONG DAN GIA DINH: C:\MelbourneFB\landing\
   Neu khac, Find & Replace duong dan trong file nay (Ctrl+H trong SSMS).

   MOI KHOI DEU: TRUNCATE -> BULK INSERT -> ghi ETL_RunLog -> kiem so dong.
   Nho TRUNCATE dau moi khoi, chay lai file nay bao nhieu lan cung ra
   dung so dong (idempotent). Day la bai hoc tu su co double-load.

   Nguon 11 (liquor licences) la .xlsx -> xem cuoi file.
   ===================================================================== */

USE MelbourneFB_STG;
GO

DECLARE @Batch BIGINT = CAST(FORMAT(SYSDATETIME(), 'yyMMddHHmm') AS BIGINT);
SELECT @Batch AS LoadBatchID_DangDung;
GO


/* =====================================================================
   1. SENSOR LOCATIONS -- 134 dong.  LOAD CAI NAY TRUOC TIEN.
      File nho nhat, dung de xac nhan duong dan va quyen doc file.
   ===================================================================== */
PRINT '--- 1/10 SensorLocations ---';
DECLARE @t DATETIME2 = SYSDATETIME(),
        @b BIGINT = CAST(FORMAT(SYSDATETIME(), 'yyMMddHHmm') AS BIGINT);

TRUNCATE TABLE stg.SensorLocations;

BULK INSERT stg.SensorLocations
FROM 'C:\MelbourneFB\landing\pedestrian-counting-system-sensor-locations.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"',
      CODEPAGE='65001', ROWTERMINATOR='0x0d0a', TABLOCK);

INSERT INTO stg.ETL_RunLog (LoadBatchID, StepName, TableName, RowsInserted,
                            RowsExpected, StartedAt, FinishedAt, Status)
SELECT @b, N'02_staging_load', N'stg.SensorLocations', COUNT(*), 134,
       @t, SYSDATETIME(),
       CASE WHEN COUNT(*) = 134 THEN N'SUCCESS' ELSE N'MISMATCH' END
FROM stg.SensorLocations;

SELECT location_type, COUNT(*) AS n FROM stg.SensorLocations
GROUP BY location_type;                      -- ky vong Outdoor 100, Indoor 34
GO


/* =====================================================================
   2. CLUE BLOCKS -- 603 dong
      Cot [Geo Shape] la GeoJSON co dau phay ben trong -> FIELDQUOTE
      bat buoc. Bang da khai du 5 cot nen KHONG can bang raw.
   ===================================================================== */
PRINT '--- 2/10 Blocks ---';
DECLARE @t DATETIME2 = SYSDATETIME(),
        @b BIGINT = CAST(FORMAT(SYSDATETIME(), 'yyMMddHHmm') AS BIGINT);

TRUNCATE TABLE stg.Blocks;

BULK INSERT stg.Blocks
FROM 'C:\MelbourneFB\landing\blocks-for-census-of-land-use-and-employment-clue.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"',
      CODEPAGE='65001', ROWTERMINATOR='0x0d0a', TABLOCK);

INSERT INTO stg.ETL_RunLog (LoadBatchID, StepName, TableName, RowsInserted,
                            RowsExpected, StartedAt, FinishedAt, Status)
SELECT @b, N'02_staging_load', N'stg.Blocks', COUNT(*), 603, @t, SYSDATETIME(),
       CASE WHEN COUNT(*) = 603 THEN N'SUCCESS' ELSE N'MISMATCH' END
FROM stg.Blocks;

-- [Geo Point] phai co dang "lat, long" -> phai chua dau phay
SELECT COUNT(*) AS BlockThieuToaDo FROM stg.Blocks
WHERE [Geo Point] IS NULL OR CHARINDEX(',', [Geo Point]) = 0;   -- ky vong 0
GO


/* =====================================================================
   3. BARS / PUBS -- 5.304 dong
   ===================================================================== */
PRINT '--- 3/10 BarPatrons ---';
DECLARE @t DATETIME2 = SYSDATETIME(),
        @b BIGINT = CAST(FORMAT(SYSDATETIME(), 'yyMMddHHmm') AS BIGINT);

TRUNCATE TABLE stg.BarPatrons;

BULK INSERT stg.BarPatrons
FROM 'C:\MelbourneFB\landing\bars-and-pubs-with-patron-capacity.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"',
      CODEPAGE='65001', ROWTERMINATOR='0x0d0a', TABLOCK);

INSERT INTO stg.ETL_RunLog (LoadBatchID, StepName, TableName, RowsInserted,
                            RowsExpected, StartedAt, FinishedAt, Status)
SELECT @b, N'02_staging_load', N'stg.BarPatrons', COUNT(*), 5304, @t, SYSDATETIME(),
       CASE WHEN COUNT(*) = 5304 THEN N'SUCCESS' ELSE N'MISMATCH' END
FROM stg.BarPatrons;
GO


/* =====================================================================
   4. EMPLOYMENT BY BLOCK -- 13.519 dong, dang PIVOT
      Bang nay dinh nghia KHUNG CENSUS cho toan bo Fact 2 va Fact 3.
   ===================================================================== */
PRINT '--- 4/10 JobsByBlock ---';
DECLARE @t DATETIME2 = SYSDATETIME(),
        @b BIGINT = CAST(FORMAT(SYSDATETIME(), 'yyMMddHHmm') AS BIGINT);

TRUNCATE TABLE stg.JobsByBlock;

BULK INSERT stg.JobsByBlock
FROM 'C:\MelbourneFB\landing\employment-by-block-by-clue-industry.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"',
      CODEPAGE='65001', ROWTERMINATOR='0x0d0a', TABLOCK);

INSERT INTO stg.ETL_RunLog (LoadBatchID, StepName, TableName, RowsInserted,
                            RowsExpected, StartedAt, FinishedAt, Status)
SELECT @b, N'02_staging_load', N'stg.JobsByBlock', COUNT(*), 13519, @t, SYSDATETIME(),
       CASE WHEN COUNT(*) = 13519 THEN N'SUCCESS' ELSE N'MISMATCH' END
FROM stg.JobsByBlock;

-- Khung census: so block moi nam. Con so nay dung de doi chieu Fact 2.
SELECT [Census year], COUNT(*) AS SoBlock
FROM stg.JobsByBlock GROUP BY [Census year] ORDER BY [Census year];
-- ky vong: 2002-2006 = 543, 2007 = 555, 2017-2018 = 602, con lai = 603
GO


/* =====================================================================
   5. ESTABLISHMENTS PER BLOCK -- 13.519 dong, dang PIVOT
   ===================================================================== */
PRINT '--- 5/10 EstabByBlock ---';
DECLARE @t DATETIME2 = SYSDATETIME(),
        @b BIGINT = CAST(FORMAT(SYSDATETIME(), 'yyMMddHHmm') AS BIGINT);

TRUNCATE TABLE stg.EstabByBlock;

BULK INSERT stg.EstabByBlock
FROM 'C:\MelbourneFB\landing\business-establishments-per-block-by-clue-industry.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"',
      CODEPAGE='65001', ROWTERMINATOR='0x0d0a', TABLOCK);

INSERT INTO stg.ETL_RunLog (LoadBatchID, StepName, TableName, RowsInserted,
                            RowsExpected, StartedAt, FinishedAt, Status)
SELECT @b, N'02_staging_load', N'stg.EstabByBlock', COUNT(*), 13519, @t, SYSDATETIME(),
       CASE WHEN COUNT(*) = 13519 THEN N'SUCCESS' ELSE N'MISMATCH' END
FROM stg.EstabByBlock;

-- Hai file 4 va 5 PHAI co cung khung census, neu khong FULL OUTER JOIN
-- o buoc 08 se sinh dong la
SELECT COUNT(*) AS ToHopLechGiuaHaiFile FROM (
    SELECT [Census year], [Block ID] FROM stg.JobsByBlock
    EXCEPT
    SELECT [Census year], [Block ID] FROM stg.EstabByBlock) x;   -- ky vong 0
GO


/* =====================================================================
   6. DEVELOPMENT ACTIVITY -- 1.438 dong, 42 cot
   ===================================================================== */
PRINT '--- 6/10 DevActivity ---';
DECLARE @t DATETIME2 = SYSDATETIME(),
        @b BIGINT = CAST(FORMAT(SYSDATETIME(), 'yyMMddHHmm') AS BIGINT);

TRUNCATE TABLE stg.DevActivity;

BULK INSERT stg.DevActivity
FROM 'C:\MelbourneFB\landing\development-activity-monitor.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"',
      CODEPAGE='65001', ROWTERMINATOR='0x0d0a', TABLOCK);

INSERT INTO stg.ETL_RunLog (LoadBatchID, StepName, TableName, RowsInserted,
                            RowsExpected, StartedAt, FinishedAt, Status)
SELECT @b, N'02_staging_load', N'stg.DevActivity', COUNT(*), 1438, @t, SYSDATETIME(),
       CASE WHEN COUNT(*) = 1438 THEN N'SUCCESS' ELSE N'MISMATCH' END
FROM stg.DevActivity;

SELECT status, COUNT(*) AS n FROM stg.DevActivity GROUP BY status;
-- ky vong: COMPLETED 1121, APPROVED 214, UNDER CONSTRUCTION 58, APPLIED 45
--          -> 317 du an chua hoan thanh = pipeline

-- Bang chung cho han che phai ghi trong bao cao:
SELECT COUNT(*) AS DuAnChuaXongNhungThieuNamHoanThanh
FROM stg.DevActivity
WHERE UPPER(LTRIM(RTRIM(status))) <> 'COMPLETED'
  AND NULLIF(LTRIM(RTRIM(year_completed)), '') IS NULL;          -- ky vong 317
GO


/* =====================================================================
   7. WEATHER -- 17.520 dong
      Ban export nay co header o DONG 1 (KHONG co dong preamble) nen
      FIRSTROW=2. Neu tai lai tu Open-Meteo va thay 3 dong preamble thi
      doi thanh FIRSTROW=4.
   ===================================================================== */
PRINT '--- 7/10 Weather ---';
DECLARE @t DATETIME2 = SYSDATETIME(),
        @b BIGINT = CAST(FORMAT(SYSDATETIME(), 'yyMMddHHmm') AS BIGINT);

TRUNCATE TABLE stg.Weather;

BULK INSERT stg.Weather
FROM 'C:\MelbourneFB\landing\open-meteo-37.79S144.94E19m.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"',
      CODEPAGE='65001', ROWTERMINATOR='0x0d0a', TABLOCK);

INSERT INTO stg.ETL_RunLog (LoadBatchID, StepName, TableName, RowsInserted,
                            RowsExpected, StartedAt, FinishedAt, Status)
SELECT @b, N'02_staging_load', N'stg.Weather', COUNT(*), 17520, @t, SYSDATETIME(),
       CASE WHEN COUNT(*) = 17520 THEN N'SUCCESS' ELSE N'MISMATCH' END
FROM stg.Weather;

SELECT MIN([time]) AS TuGio, MAX([time]) AS DenGio FROM stg.Weather;
-- ky vong 2024-08-05T00:00 -> 2026-08-04T23:00 (khop khoang pedestrian)

-- Bien do nhiet do that, dung de dat nguong dai o DimWeather
SELECT CAST(MIN(TRY_CAST(TemperatureC AS DECIMAL(5,2))) AS DECIMAL(5,1)) AS ThapNhat,
       CAST(MAX(TRY_CAST(TemperatureC AS DECIMAL(5,2))) AS DECIMAL(5,1)) AS CaoNhat
FROM stg.Weather;                                    -- ky vong 1,8 -> 43,4
GO


/* =====================================================================
   8. CAFES / RESTAURANTS -- 66.356 dong
   ===================================================================== */
PRINT '--- 8/10 CafeSeats ---';
DECLARE @t DATETIME2 = SYSDATETIME(),
        @b BIGINT = CAST(FORMAT(SYSDATETIME(), 'yyMMddHHmm') AS BIGINT);

TRUNCATE TABLE stg.CafeSeats;

BULK INSERT stg.CafeSeats
FROM 'C:\MelbourneFB\landing\cafes-and-restaurants-with-seating-capacity.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"',
      CODEPAGE='65001', ROWTERMINATOR='0x0d0a', TABLOCK,
      BATCHSIZE=20000);

INSERT INTO stg.ETL_RunLog (LoadBatchID, StepName, TableName, RowsInserted,
                            RowsExpected, StartedAt, FinishedAt, Status)
SELECT @b, N'02_staging_load', N'stg.CafeSeats', COUNT(*), 66356, @t, SYSDATETIME(),
       CASE WHEN COUNT(*) = 66356 THEN N'SUCCESS' ELSE N'MISMATCH' END
FROM stg.CafeSeats;

SELECT [Seating type], COUNT(*) AS n FROM stg.CafeSeats GROUP BY [Seating type];
-- ky vong: Seats - Indoor 43420, Seats - Outdoor 22936

-- Kiem BOM: neu con BOM thi ky tu dau tien co ma > 127
SELECT TOP 1 [Census year] AS GiaTri, UNICODE(LEFT([Census year], 1)) AS MaKyTuDau
FROM stg.CafeSeats;                                  -- ky vong 50 (chu so '2')
GO


/* =====================================================================
   9. RESIDENTIAL DWELLINGS -- ~219.680 dong, 32 MB
   ===================================================================== */
PRINT '--- 9/10 ResidentialDwellings ---';
DECLARE @t DATETIME2 = SYSDATETIME(),
        @b BIGINT = CAST(FORMAT(SYSDATETIME(), 'yyMMddHHmm') AS BIGINT);

TRUNCATE TABLE stg.ResidentialDwellings;

BULK INSERT stg.ResidentialDwellings
FROM 'C:\MelbourneFB\landing\residential-dwellings.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"',
      CODEPAGE='65001', ROWTERMINATOR='0x0d0a', TABLOCK,
      BATCHSIZE=50000);

INSERT INTO stg.ETL_RunLog (LoadBatchID, StepName, TableName, RowsInserted,
                            StartedAt, FinishedAt, Status)
SELECT @b, N'02_staging_load', N'stg.ResidentialDwellings', COUNT(*),
       @t, SYSDATETIME(), N'SUCCESS'
FROM stg.ResidentialDwellings;

SELECT [Dwelling type], COUNT(*) AS SoToaNha,
       SUM(TRY_CAST([Dwelling number] AS INT)) AS TongSoCan
FROM stg.ResidentialDwellings GROUP BY [Dwelling type] ORDER BY TongSoCan DESC;
-- ky vong 3 loai: House/Townhouse, Residential Apartments, Student Apartments
GO


/* =====================================================================
   10. PEDESTRIAN HOURLY -- 1.613.524 dong, 121 MB.  LOAD CUOI CUNG.
       Mat khoang 20-90 giay tuy o dia. Ghi lai so giay cho bao cao.
   ===================================================================== */
PRINT '--- 10/10 PedestrianHourly (file lon nhat) ---';
DECLARE @t DATETIME2 = SYSDATETIME(),
        @b BIGINT = CAST(FORMAT(SYSDATETIME(), 'yyMMddHHmm') AS BIGINT);

TRUNCATE TABLE stg.PedestrianHourly;

BULK INSERT stg.PedestrianHourly
FROM 'C:\MelbourneFB\landing\pedestrian-counting-system-monthly-counts-per-hour.csv'
WITH (FORMAT='CSV', FIRSTROW=2, FIELDQUOTE='"',
      CODEPAGE='65001', ROWTERMINATOR='0x0d0a', TABLOCK,
      BATCHSIZE=200000);

INSERT INTO stg.ETL_RunLog (LoadBatchID, StepName, TableName, RowsInserted,
                            RowsExpected, StartedAt, FinishedAt, Status, Notes)
SELECT @b, N'02_staging_load', N'stg.PedestrianHourly', COUNT(*), 1613524,
       @t, SYSDATETIME(),
       CASE WHEN COUNT(*) = 1613524 THEN N'SUCCESS' ELSE N'MISMATCH' END,
       N'Thoi gian load: ' + CAST(DATEDIFF(SECOND, @t, SYSDATETIME()) AS NVARCHAR) + N' giay'
FROM stg.PedestrianHourly;

SELECT MIN([Sensing_Date]) AS TuNgay, MAX([Sensing_Date]) AS DenNgay,
       COUNT(DISTINCT [Location_ID]) AS SoSensorCoSoLieu
FROM stg.PedestrianHourly;             -- 2024-08-05 -> 2026-08-04, 103 sensor

-- Kiem CRLF: neu sai ROWTERMINATOR, cot cuoi con dinh ky tu CR (ma 13)
SELECT TOP 1 UNICODE(RIGHT([Location], 1)) AS MaKyTuCuoi
FROM stg.PedestrianHourly WHERE [Location] IS NOT NULL;   -- KHONG duoc = 13

-- Toan ven tham chieu: sensor co trong counts nhung khong co trong locations
SELECT DISTINCT f.[Location_ID] AS OrphanSensorID
FROM stg.PedestrianHourly f
LEFT JOIN stg.SensorLocations d ON f.[Location_ID] = d.location_id
WHERE d.location_id IS NULL;
-- ky vong 3 dong: 28, 65, 78
-- Day la ly do can Unknown Member (SensorKey = -1) trong DimSensor.
-- KHONG xoa cac dong nay: xoa se lam sai tong luot nguoi.
GO


/* =====================================================================
   11. LIQUOR LICENCES -- file .xlsx, BULK INSERT KHONG doc duoc
   ---------------------------------------------------------------------
   Ba cach, chon 1:
   (a) Mo file trong Excel -> Save As CSV UTF-8 -> BULK INSERT
       LUU Y header nam o DONG 5 => FIRSTROW=6
   (b) SSMS -> phai chuot database -> Tasks -> Import Flat File
   (c) SSIS Excel Source (cach se dung khi nop bai)
       Excel Sheet = 'Current_Victorian_Licences_By_L$A5:W'

   NEU CHUA LOAD: buoc 03 va 09 van chay duoc, chi la nhom cot Licence*
   trong FactBlockAnnual se de NULL va BQ3 chua tra loi duoc.
   Load xong thi chay lai muc 3 cua 03_spatial_mapping.sql roi chay lai 09.
   ===================================================================== */
IF NOT EXISTS (SELECT 1 FROM stg.LiquorLicences)
    PRINT 'CHU Y: stg.LiquorLicences con rong. Load bang SSIS/Import Flat File.';
ELSE
BEGIN
    SELECT COUNT(*) AS TongVIC FROM stg.LiquorLicences;                 -- 23762
    SELECT COUNT(*) AS MelbourneCity FROM stg.LiquorLicences
    WHERE [Council] LIKE '%MELBOURNE CITY%';                            -- 2196
    SELECT [Trading Hours], COUNT(*) AS n FROM stg.LiquorLicences
    WHERE [Council] LIKE '%MELBOURNE CITY%'
    GROUP BY [Trading Hours] ORDER BY 2 DESC;
END
GO


/* =====================================================================
   KIEM TRA TONG THE
   ===================================================================== */
SELECT 'SensorLocations' AS Bang, COUNT(*) AS SoDong, 134 AS KyVong
FROM stg.SensorLocations
UNION ALL SELECT 'Blocks',              COUNT(*), 603     FROM stg.Blocks
UNION ALL SELECT 'BarPatrons',          COUNT(*), 5304    FROM stg.BarPatrons
UNION ALL SELECT 'JobsByBlock',         COUNT(*), 13519   FROM stg.JobsByBlock
UNION ALL SELECT 'EstabByBlock',        COUNT(*), 13519   FROM stg.EstabByBlock
UNION ALL SELECT 'DevActivity',         COUNT(*), 1438    FROM stg.DevActivity
UNION ALL SELECT 'Weather',             COUNT(*), 17520   FROM stg.Weather
UNION ALL SELECT 'CafeSeats',           COUNT(*), 66356   FROM stg.CafeSeats
UNION ALL SELECT 'ResidentialDwellings',COUNT(*), NULL    FROM stg.ResidentialDwellings
UNION ALL SELECT 'PedestrianHourly',    COUNT(*), 1613524 FROM stg.PedestrianHourly
UNION ALL SELECT 'LiquorLicences',      COUNT(*), 23762   FROM stg.LiquorLicences;

-- Log: moi dong phai la SUCCESS
SELECT TableName, RowsInserted, RowsExpected, Status,
       DATEDIFF(SECOND, StartedAt, FinishedAt) AS Giay
FROM stg.ETL_RunLog
WHERE StepName = N'02_staging_load'
ORDER BY RunLogID;
GO

PRINT 'Chay tiep 03_spatial_mapping.sql';
GO