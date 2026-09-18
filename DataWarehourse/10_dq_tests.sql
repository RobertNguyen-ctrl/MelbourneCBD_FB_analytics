/* =====================================================================
   BUOC 10 -- BO TEST CHAT LUONG DU LIEU
   ---------------------------------------------------------------------
   Chay SAU khi da nap xong 3 fact. Moi test tra ve 1 dong:
     KetQua = 'PASS' hoac 'FAIL'
   Chay lai bo test nay TRUOC MOI LAN nop bai va truoc buoi bao ve.
   Anh chup ket qua PASS toan bo la bang chung tot nhat cho tieu chi 4.

   Ket qua cua file nay la muc "Kiem thu va chat luong du lieu" trong
   bao cao -- hoi dong thuong hoi "lam sao biet du lieu dung".
   ===================================================================== */
USE MelbourneFB_DW;
GO

DROP TABLE IF EXISTS #Results;
CREATE TABLE #Results (
    TestNo    INT,
    TestGroup NVARCHAR(30),
    TestName  NVARCHAR(200),
    Actual    NVARCHAR(50),
    Expected  NVARCHAR(50),
    KetQua    NVARCHAR(10)
);
GO

DECLARE @a BIGINT, @b BIGINT;

/* =====================================================================
   NHOM 1 -- SO DONG (grain dung hay khong)
   ===================================================================== */

-- T01: Fact 1
SELECT @a = COUNT(*) FROM dw.FactFootfallHourly;
INSERT INTO #Results VALUES (1, N'So dong',
    N'FactFootfallHourly = 1.613.524 dong', CAST(@a AS NVARCHAR), N'1613524',
    CASE WHEN @a = 1613524 THEN N'PASS' ELSE N'FAIL' END);

-- T02: Fact 2 -- khung census that, KHONG phai 603 x 23
SELECT @a = COUNT(*) FROM dw.FactBlockAnnual;
INSERT INTO #Results VALUES (2, N'So dong',
    N'FactBlockAnnual = 13.519 dong (khung census, khong phai 13.869)',
    CAST(@a AS NVARCHAR), N'13519',
    CASE WHEN @a = 13519 THEN N'PASS' ELSE N'FAIL' END);

-- T03: Fact 3
SELECT @a = COUNT(*) FROM dw.FactBlockIndustryAnnual;
INSERT INTO #Results VALUES (3, N'So dong',
    N'FactBlockIndustryAnnual = 270.380 dong (13.519 x 20 nganh)',
    CAST(@a AS NVARCHAR), N'270380',
    CASE WHEN @a = 270380 THEN N'PASS' ELSE N'FAIL' END);

-- T04: so bang trong schema dw
SELECT @a = COUNT(*) FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'dw' AND TABLE_TYPE = 'BASE TABLE';
INSERT INTO #Results VALUES (4, N'So dong',
    N'Schema dw co dung 10 bang (7 dim + 3 fact)', CAST(@a AS NVARCHAR), N'10',
    CASE WHEN @a = 10 THEN N'PASS' ELSE N'FAIL' END);

/* =====================================================================
   NHOM 2 -- TOAN VEN GRAIN (khong duoc trung dong)
   ===================================================================== */

-- T05: Fact 2 duy nhat theo (block, nam)
SELECT @a = COUNT(*) FROM (
    SELECT BlockKey, CensusYear FROM dw.FactBlockAnnual
    GROUP BY BlockKey, CensusYear HAVING COUNT(*) > 1) x;
INSERT INTO #Results VALUES (5, N'Grain',
    N'FactBlockAnnual: khong to hop (block, nam) nao bi trung',
    CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T06: Fact 3 duy nhat theo (block, nam, nganh)
SELECT @a = COUNT(*) FROM (
    SELECT BlockKey, CensusYear, IndustryKey FROM dw.FactBlockIndustryAnnual
    GROUP BY BlockKey, CensusYear, IndustryKey HAVING COUNT(*) > 1) x;
INSERT INTO #Results VALUES (6, N'Grain',
    N'FactBlockIndustryAnnual: khong to hop (block, nam, nganh) nao trung',
    CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T07: Fact 1 duy nhat theo (ngay, gio, sensor)
--      Loai sensor Unknown ra vi 3 sensor mo coi gop vao cung key -1
SELECT @a = COUNT(*) FROM (
    SELECT DateKey, TimeKey, SensorKey FROM dw.FactFootfallHourly
    WHERE SensorKey <> -1
    GROUP BY DateKey, TimeKey, SensorKey HAVING COUNT(*) > 1) x;
INSERT INTO #Results VALUES (7, N'Grain',
    N'FactFootfallHourly: khong to hop (ngay, gio, sensor) nao trung',
    CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);


/* =====================================================================
   NHOM 3 -- DOI CHIEU GIUA CAC FACT (quan trong nhat)
   ===================================================================== */

-- T08: SUM(Fact3.JobCount) = Fact2.TotalJobs cho tung block-nam
SELECT @a = COUNT(*) FROM (
    SELECT a.BlockKey, a.CensusYear
    FROM dw.FactBlockAnnual a
    JOIN dw.FactBlockIndustryAnnual i
         ON i.BlockKey = a.BlockKey AND i.CensusYear = a.CensusYear
    GROUP BY a.BlockKey, a.CensusYear, a.TotalJobs
    HAVING a.TotalJobs <> SUM(ISNULL(i.JobCount, 0))) x;
INSERT INTO #Results VALUES (8, N'Doi chieu',
    N'Fact2.TotalJobs = SUM(Fact3.JobCount) theo tung block-nam',
    CAST(@a AS NVARCHAR) + N' dong lech', N'0 dong lech',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T09: SUM(Fact3.EstablishmentCount) = Fact2.TotalEstablishments
SELECT @a = COUNT(*) FROM (
    SELECT a.BlockKey, a.CensusYear
    FROM dw.FactBlockAnnual a
    JOIN dw.FactBlockIndustryAnnual i
         ON i.BlockKey = a.BlockKey AND i.CensusYear = a.CensusYear
    GROUP BY a.BlockKey, a.CensusYear, a.TotalEstablishments
    HAVING a.TotalEstablishments <> SUM(ISNULL(i.EstablishmentCount, 0))) x;
INSERT INTO #Results VALUES (9, N'Doi chieu',
    N'Fact2.TotalEstablishments = SUM(Fact3.EstablishmentCount)',
    CAST(@a AS NVARCHAR) + N' dong lech', N'0 dong lech',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T10: TotalSeats = IndoorSeats + OutdoorSeats
--      Cot TotalSeats cong CA cac dong thieu [Seating type], nen phep
--      nay chi dung khi nguon khong co dong nao thieu seating type.
SELECT @a = COUNT(*) FROM dw.FactBlockAnnual
WHERE TotalSeats <> IndoorSeats + OutdoorSeats;
INSERT INTO #Results VALUES (10, N'Doi chieu',
    N'TotalSeats = IndoorSeats + OutdoorSeats',
    CAST(@a AS NVARCHAR) + N' dong lech', N'0 dong lech',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T11: TotalDwellings = tong 3 loai nha o
SELECT @a = COUNT(*) FROM dw.FactBlockAnnual
WHERE TotalDwellings <> ApartmentDwellings + StudentDwellings + HouseDwellings;
INSERT INTO #Results VALUES (11, N'Doi chieu',
    N'TotalDwellings = Apartment + Student + House',
    CAST(@a AS NVARCHAR) + N' dong lech', N'0 dong lech',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T12: doi chieu tong ghe nam moi nhat voi staging (ETL khong mat du lieu)
DECLARE @LatestYear NVARCHAR(10) =
    (SELECT CAST(MAX(CensusYear) AS NVARCHAR) FROM dw.FactBlockAnnual);
SELECT @a = SUM(TotalSeats) FROM dw.FactBlockAnnual WHERE IsLatestCensusYear = 1;
SELECT @b = SUM(ISNULL(TRY_CAST([Number of seats] AS INT), 0))
FROM MelbourneFB_STG.stg.CafeSeats
WHERE [Census year] = @LatestYear
  AND TRY_CAST([Block ID] AS INT) IS NOT NULL;
INSERT INTO #Results VALUES (12, N'Doi chieu',
    N'Tong ghe nam moi nhat: DW = staging (ETL khong mat du lieu)',
    CAST(@a AS NVARCHAR), CAST(@b AS NVARCHAR),
    CASE WHEN @a = @b THEN N'PASS' ELSE N'FAIL' END);


/* =====================================================================
   NHOM 4 -- DOUBLE COUNTING (rui ro lon nhat cua thiet ke gop fact)
   ===================================================================== */

-- T13: pipeline KHONG duoc nhan 23 lan
SELECT @a = SUM(PipelineResiDwellings) FROM dw.FactBlockAnnual;
INSERT INTO #Results VALUES (13, N'Double count',
    N'SUM(PipelineResiDwellings) = 37.128, KHONG phai 23 x 37.128',
    CAST(@a AS NVARCHAR), N'37128',
    CASE WHEN @a = 37128 THEN N'PASS' ELSE N'FAIL' END);

-- T14: pipeline chi ton tai o dong nam moi nhat
SELECT @a = COUNT(*) FROM dw.FactBlockAnnual
WHERE IsLatestCensusYear = 0 AND PipelineResiDwellings IS NOT NULL;
INSERT INTO #Results VALUES (14, N'Double count',
    N'Cot Pipeline* chi dien o dong IsLatestCensusYear = 1',
    CAST(@a AS NVARCHAR) + N' dong sai', N'0 dong sai',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T15: licence chi ton tai o dong nam moi nhat
SELECT @a = COUNT(*) FROM dw.FactBlockAnnual
WHERE IsLatestCensusYear = 0 AND LicenceCount IS NOT NULL;
INSERT INTO #Results VALUES (15, N'Double count',
    N'Cot Licence* chi dien o dong IsLatestCensusYear = 1',
    CAST(@a AS NVARCHAR) + N' dong sai', N'0 dong sai',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T16: dung 1 census year duoc danh dau la latest
SELECT @a = COUNT(DISTINCT CensusYear) FROM dw.FactBlockAnnual
WHERE IsLatestCensusYear = 1;
INSERT INTO #Results VALUES (16, N'Double count',
    N'Dung 1 census year duoc danh dau IsLatestCensusYear',
    CAST(@a AS NVARCHAR), N'1',
    CASE WHEN @a = 1 THEN N'PASS' ELSE N'FAIL' END);


/* =====================================================================
   NHOM 5 -- UNKNOWN MEMBER va toan ven tham chieu
   ===================================================================== */

-- T17: moi dimension co dung 1 Unknown Member
SELECT @a =
    (SELECT COUNT(*) FROM dw.DimBlock    WHERE BlockKey    = -1)
  + (SELECT COUNT(*) FROM dw.DimSensor   WHERE SensorKey   = -1)
  + (SELECT COUNT(*) FROM dw.DimWeather  WHERE WeatherKey  = -1)
  + (SELECT COUNT(*) FROM dw.DimIndustry WHERE IndustryKey = -1);
INSERT INTO #Results VALUES (17, N'Unknown member',
    N'4 dimension x 1 Unknown Member', CAST(@a AS NVARCHAR), N'4',
    CASE WHEN @a = 4 THEN N'PASS' ELSE N'FAIL' END);

-- T18: Fact 3 KHONG duoc dung Unknown Member
SELECT @a = COUNT(*) FROM dw.FactBlockIndustryAnnual
WHERE IndustryKey = -1 OR BlockKey = -1;
INSERT INTO #Results VALUES (18, N'Unknown member',
    N'Fact 3 khong dong nao dung Unknown Member',
    CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T19: Fact 1 -- Unknown sensor phai duoi 2% (3 sensor mo coi 28/65/78)
SELECT @a = CAST(100.0 * SUM(CASE WHEN SensorKey = -1 THEN 1 ELSE 0 END)
                 / COUNT(*) * 100 AS INT)     -- x100 de so nguyen
FROM dw.FactFootfallHourly;
INSERT INTO #Results VALUES (19, N'Unknown member',
    N'Fact 1: ty le Unknown sensor duoi 2% (3 sensor mo coi)',
    CAST(@a / 100.0 AS NVARCHAR(20)) + N' %', N'< 2 %',
    CASE WHEN @a < 200 THEN N'PASS' ELSE N'FAIL' END);

-- T20: Fact 1 -- moi dong phai gan duoc thoi tiet
SELECT @a = COUNT(*) FROM dw.FactFootfallHourly WHERE WeatherKey = -1;
INSERT INTO #Results VALUES (20, N'Unknown member',
    N'Fact 1: moi dong gan duoc WeatherKey (khong dung Unknown)',
    CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);


/* =====================================================================
   NHOM 6 -- LOGIC NGHIEP VU
   ===================================================================== */

-- T21: 4 cua so gio phai CHONG LAP (tong > 100%)
SELECT @a = CAST(SUM(CAST(InCafeWindow AS INT) + InLunchWindow
                   + InAllDayWindow + InNightWindow) AS INT)
FROM dw.DimTime;
INSERT INTO #Results VALUES (21, N'Nghiep vu',
    N'DimTime: 4 cua so gio chong lap (tong co BIT > 24)',
    CAST(@a AS NVARCHAR), N'> 24',
    CASE WHEN @a > 24 THEN N'PASS' ELSE N'FAIL' END);

-- T22: khong duoc co measure am
SELECT @a = COUNT(*) FROM dw.FactBlockAnnual
WHERE TotalSeats < 0 OR TotalJobs < 0 OR TotalDwellings < 0;
INSERT INTO #Results VALUES (22, N'Nghiep vu',
    N'FactBlockAnnual: khong measure nao am',
    CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T23: chi 76 block co do phu footfall -- gioi han quan trong cua BQ1
SELECT @a = COUNT(*) FROM dw.DimBlock
WHERE HasFootfallCoverage = 1 AND BlockKey <> -1;
INSERT INTO #Results VALUES (23, N'Nghiep vu',
    N'DimBlock: 76 block co sensor trong 200m (gioi han cua BQ1)',
    CAST(@a AS NVARCHAR), N'76',
    CASE WHEN @a = 76 THEN N'PASS' ELSE N'FAIL' END);

-- T24: BQ1 tinh duoc tren it nhat 20 block (du de xep hang)
SELECT @a = COUNT(DISTINCT a.BlockKey)
FROM dw.FactBlockAnnual a
JOIN dw.DimBlock b ON b.BlockKey = a.BlockKey
WHERE a.IsLatestCensusYear = 1 AND b.HasFootfallCoverage = 1 AND a.TotalSeats > 0;
INSERT INTO #Results VALUES (24, N'Nghiep vu',
    N'BQ1: co it nhat 20 block vua co footfall vua co ghe',
    CAST(@a AS NVARCHAR), N'>= 20',
    CASE WHEN @a >= 20 THEN N'PASS' ELSE N'FAIL' END);


/* =====================================================================
   KET QUA
   ===================================================================== */
SELECT TestNo, TestGroup, TestName, Actual, Expected, KetQua
FROM #Results ORDER BY TestNo;

SELECT KetQua, COUNT(*) AS SoTest FROM #Results GROUP BY KetQua;

IF EXISTS (SELECT 1 FROM #Results WHERE KetQua = N'FAIL')
    PRINT '>>> CO TEST FAIL -- xem bang tren, sua truoc khi nop bai.';
ELSE
    PRINT '>>> TOAN BO TEST PASS. Data warehouse san sang cho Power BI.';
GO

DROP TABLE IF EXISTS #Results;
GO


/* =====================================================================
   BUOC 11 -- XUAT TOAN BO CAU TRUC DATABASE
   ---------------------------------------------------------------------
   File nay KHONG doi du lieu. Chi doc metadata va xuat ra 8 bang ket qua
   de copy vao bao cao (tieu chi 4 va tieu chi 8 cua rubric).

   CACH DUNG TRONG SSMS
     1. Query menu -> Results To -> Results To Grid
     2. Chay ca file (F5)
     3. Voi tung bang ket qua: phai chuot o goc trai bang ->
        "Select All" -> "Copy with Headers" -> dan vao Word/Excel
     Neu muon xuat mot lan ra file: Results To -> Results To File,
     hoac Results To Text roi Ctrl+A Ctrl+C.

   TAM BANG KET QUA
     1. Danh sach bang + so dong (ca 2 database)
     2. Data dictionary -- moi cot cua schema dw
     3. Primary key
     4. Foreign key -- ban do quan he giua cac bang
     5. Ma tran bus: fact x dimension
     6. Index
     7. Constraint khac (UNIQUE, DEFAULT, CHECK)
     8. Tong ket cho slide

   LUU Y VE SO DONG
     Dung sys.dm_db_partition_stats thay vi COUNT(*). Ly do: COUNT(*)
     tren FactFootfallHourly phai doc 1,6 trieu dong. Metadata cho ket
     qua tuc thi. Sai so co the xay ra neu dang co transaction mo,
     nhung o day khong co -- va con so nay chi dung de tai lieu hoa.
   ===================================================================== */


/* =====================================================================
   1. DANH SACH BANG + SO DONG  (ca 2 database)
   ===================================================================== */
PRINT '=== 1. DANH SACH BANG ===';

SELECT
    N'MelbourneFB_DW' AS Database_,
    s.name            AS Schema_,
    t.name            AS TableName,
    CASE WHEN t.name LIKE 'Fact%' THEN N'FACT'
         WHEN t.name LIKE 'Dim%'  THEN N'DIMENSION'
         ELSE N'KHAC' END AS Loai,
    SUM(p.row_count)  AS SoDong,
    (SELECT COUNT(*) FROM MelbourneFB_DW.sys.columns c
     WHERE c.object_id = t.object_id) AS SoCot
FROM MelbourneFB_DW.sys.tables t
JOIN MelbourneFB_DW.sys.schemas s ON s.schema_id = t.schema_id
JOIN MelbourneFB_DW.sys.dm_db_partition_stats p ON p.object_id = t.object_id
WHERE p.index_id IN (0, 1)          -- 0 = heap, 1 = clustered
GROUP BY s.name, t.name, t.object_id

UNION ALL

SELECT
    N'MelbourneFB_STG', s.name, t.name,
    CASE WHEN t.name LIKE 'ETL%' OR t.name LIKE 'Block%'
              OR t.name LIKE 'Nearest%' THEN N'PHU TRO'
         ELSE N'NGUON' END,
    SUM(p.row_count),
    (SELECT COUNT(*) FROM MelbourneFB_STG.sys.columns c
     WHERE c.object_id = t.object_id)
FROM MelbourneFB_STG.sys.tables t
JOIN MelbourneFB_STG.sys.schemas s ON s.schema_id = t.schema_id
JOIN MelbourneFB_STG.sys.dm_db_partition_stats p ON p.object_id = t.object_id
WHERE p.index_id IN (0, 1)
GROUP BY s.name, t.name, t.object_id
ORDER BY Database_ DESC, Loai, TableName;
GO


/* =====================================================================
   2. DATA DICTIONARY -- moi cot cua schema dw
   ---------------------------------------------------------------------
   Day la bang quan trong nhat cho bao cao. Cot VaiTro duoc suy ra tu
   ten cot va constraint, KHONG phai go tay -- nen luon dong bo voi DDL.
   Cot YNghia de trong: dien tay trong Word (khoang 90 dong).
   ===================================================================== */
PRINT '=== 2. DATA DICTIONARY ===';

USE MelbourneFB_DW;
GO

SELECT
    t.name                                          AS TableName,
    c.column_id                                     AS ThuTu,
    c.name                                          AS ColumnName,
    ty.name
      + CASE WHEN ty.name IN ('nvarchar','varchar','char','nchar','varbinary')
                  THEN '(' + CASE WHEN c.max_length = -1 THEN 'MAX'
                                  WHEN ty.name LIKE 'n%'
                                       THEN CAST(c.max_length/2 AS VARCHAR(10))
                                  ELSE CAST(c.max_length AS VARCHAR(10)) END + ')'
             WHEN ty.name IN ('decimal','numeric')
                  THEN '(' + CAST(c.precision AS VARCHAR(10)) + ','
                           + CAST(c.scale AS VARCHAR(10)) + ')'
             ELSE '' END                            AS KieuDuLieu,
    CASE WHEN c.is_nullable = 1 THEN N'NULL' ELSE N'NOT NULL' END AS ChoNull,
    CASE WHEN c.is_identity = 1 THEN N'IDENTITY' ELSE N'' END     AS Identity_,
    -- Vai tro suy ra tu constraint that
    CASE
      WHEN EXISTS (SELECT 1 FROM sys.index_columns ic
                   JOIN sys.indexes i ON i.object_id=ic.object_id
                                     AND i.index_id=ic.index_id
                   WHERE ic.object_id=c.object_id AND ic.column_id=c.column_id
                     AND i.is_primary_key=1)                     THEN N'PK'
      WHEN EXISTS (SELECT 1 FROM sys.foreign_key_columns fkc
                   WHERE fkc.parent_object_id=c.object_id
                     AND fkc.parent_column_id=c.column_id)        THEN N'FK'
      WHEN c.name LIKE '%Count' OR c.name LIKE '%Seats'
        OR c.name LIKE '%Jobs'  OR c.name LIKE '%Dwellings'
        OR c.name LIKE 'Pipeline%' OR c.name LIKE '%Capacity'
        OR c.name LIKE '%Venues'   OR c.name LIKE '%Sqm'
        OR c.name IN ('TotalPedestrians','TemperatureC','PrecipitationMM')
                                                                  THEN N'Measure'
      WHEN c.name LIKE 'Is%' OR c.name LIKE 'Has%' OR c.name LIKE 'In%'
                                                                  THEN N'Co (flag)'
      ELSE N'Thuoc tinh' END                        AS VaiTro,
    -- Bang nguon o staging, suy ra theo bang dich
    CASE t.name
      WHEN 'FactFootfallHourly'      THEN N'stg.PedestrianHourly + stg.Weather'
      WHEN 'FactBlockAnnual'         THEN N'6 nguon CLUE (xem file 09)'
      WHEN 'FactBlockIndustryAnnual' THEN N'stg.JobsByBlock + stg.EstabByBlock'
      WHEN 'DimBlock'                THEN N'stg.Blocks + stg.BlockFootfallCoverage'
      WHEN 'DimSensor'               THEN N'stg.SensorLocations + stg.NearestBlockMap'
      WHEN 'DimWeather'              THEN N'Sinh bang CROSS JOIN (junk dim)'
      WHEN 'DimIndustry'             THEN N'Seed tay trong 04_dw_ddl.sql'
      WHEN 'DimDate'                 THEN N'Sinh bang T-SQL recursive CTE'
      WHEN 'DimTime'                 THEN N'Sinh bang T-SQL recursive CTE'
      ELSE N'' END                                  AS NguonDuLieu,
    CAST(N'' AS NVARCHAR(200))                      AS YNghiaNghiepVu  -- dien tay
FROM sys.tables t
JOIN sys.columns c    ON c.object_id = t.object_id
JOIN sys.types   ty   ON ty.user_type_id = c.user_type_id
JOIN sys.schemas s    ON s.schema_id = t.schema_id
WHERE s.name = 'dw'
ORDER BY
    CASE WHEN t.name LIKE 'Fact%' THEN 1 ELSE 2 END,
    t.name, c.column_id;
GO


/* =====================================================================
   3. PRIMARY KEY
   ===================================================================== */
PRINT '=== 3. PRIMARY KEY ===';

SELECT
    t.name  AS TableName,
    i.name  AS TenConstraint,
    CASE WHEN i.type = 1 THEN N'CLUSTERED' ELSE N'NONCLUSTERED' END AS Loai,
    STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS CacCot
FROM sys.indexes i
JOIN sys.tables  t  ON t.object_id = i.object_id
JOIN sys.schemas s  ON s.schema_id = t.schema_id
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c  ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.is_primary_key = 1 AND s.name = 'dw'
GROUP BY t.name, i.name, i.type
ORDER BY t.name;
GO


/* =====================================================================
   4. FOREIGN KEY -- ban do quan he
   ---------------------------------------------------------------------
   Bang nay CHINH LA luoc do quan he ma tieu chi 4 va tieu chi 8 yeu cau
   "trinh bay duoc luoc do quan he cua cac bang trong Data warehouse".
   Ky vong 10 dong: Fact1 co 5 FK, Fact2 co 2, Fact3 co 3.
   ===================================================================== */
PRINT '=== 4. FOREIGN KEY (luoc do quan he) ===';

SELECT
    fk.name                        AS TenFK,
    tp.name                        AS BangCon_Fact,
    cp.name                        AS CotFK,
    N'-->'                         AS Toi,
    tr.name                        AS BangCha_Dimension,
    cr.name                        AS CotPK,
    CASE WHEN tr.name IN ('DimDate','DimBlock') THEN N'CONFORMED'
         ELSE N'PRIVATE' END       AS LoaiDimension
FROM sys.foreign_keys fk
JOIN sys.tables tp ON tp.object_id = fk.parent_object_id
JOIN sys.tables tr ON tr.object_id = fk.referenced_object_id
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns cp ON cp.object_id = fkc.parent_object_id
                   AND cp.column_id = fkc.parent_column_id
JOIN sys.columns cr ON cr.object_id = fkc.referenced_object_id
                   AND cr.column_id = fkc.referenced_column_id
ORDER BY tp.name, tr.name;
GO


/* =====================================================================
   5. MA TRAN BUS -- fact x dimension
   ---------------------------------------------------------------------
   Artifact dac trung cua phuong phap Kimball. Sinh tu FOREIGN KEY THAT
   trong database, khong go tay -- nen khong the lech voi thiet ke.
   Dau X = fact do noi vao dimension do.
   ===================================================================== */
PRINT '=== 5. MA TRAN BUS ===';

;WITH Rel AS (
    SELECT DISTINCT tp.name AS FactName, tr.name AS DimName
    FROM sys.foreign_keys fk
    JOIN sys.tables tp ON tp.object_id = fk.parent_object_id
    JOIN sys.tables tr ON tr.object_id = fk.referenced_object_id
)
SELECT
    f.name AS Fact,
    MAX(CASE WHEN r.DimName = 'DimDate'     THEN N'X' ELSE N'' END) AS DimDate,
    MAX(CASE WHEN r.DimName = 'DimBlock'    THEN N'X' ELSE N'' END) AS DimBlock,
    MAX(CASE WHEN r.DimName = 'DimTime'     THEN N'X' ELSE N'' END) AS DimTime,
    MAX(CASE WHEN r.DimName = 'DimSensor'   THEN N'X' ELSE N'' END) AS DimSensor,
    MAX(CASE WHEN r.DimName = 'DimWeather'  THEN N'X' ELSE N'' END) AS DimWeather,
    MAX(CASE WHEN r.DimName = 'DimIndustry' THEN N'X' ELSE N'' END) AS DimIndustry,
    COUNT(DISTINCT r.DimName)                                       AS SoDim
FROM sys.tables f
LEFT JOIN Rel r ON r.FactName = f.name
WHERE f.name LIKE 'Fact%'
GROUP BY f.name
ORDER BY f.name;
-- ky vong:
--   FactFootfallHourly      X X X X X .  -> 5 dim
--   FactBlockAnnual         X X . . . .  -> 2 dim
--   FactBlockIndustryAnnual X X . . . X  -> 3 dim
-- Cot DimDate va DimBlock co X o CA BA dong -> chung minh conformed.
GO


/* =====================================================================
   6. INDEX
   ===================================================================== */
PRINT '=== 6. INDEX ===';

SELECT
    t.name AS TableName,
    i.name AS TenIndex,
    CASE i.type WHEN 1 THEN N'CLUSTERED'
                WHEN 2 THEN N'NONCLUSTERED'
                ELSE CAST(i.type AS NVARCHAR(10)) END AS Loai,
    CASE WHEN i.is_unique = 1 THEN N'UNIQUE' ELSE N'' END AS Unique_,
    STRING_AGG(CASE WHEN ic.is_included_column = 0 THEN c.name END, ', ')
        WITHIN GROUP (ORDER BY ic.key_ordinal)          AS CotKhoa,
    STRING_AGG(CASE WHEN ic.is_included_column = 1 THEN c.name END, ', ')
                                                        AS CotInclude
FROM sys.indexes i
JOIN sys.tables  t ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE s.name = 'dw' AND i.type > 0 AND i.is_primary_key = 0
GROUP BY t.name, i.name, i.type, i.is_unique
ORDER BY t.name, i.name;
GO


/* =====================================================================
   7. CONSTRAINT KHAC -- UNIQUE va DEFAULT
   ===================================================================== */
PRINT '=== 7. CONSTRAINT KHAC ===';

SELECT t.name AS TableName, N'UNIQUE' AS LoaiConstraint, i.name AS TenConstraint,
       STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY ic.key_ordinal) AS ChiTiet
FROM sys.indexes i
JOIN sys.tables  t ON t.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.index_columns ic ON ic.object_id=i.object_id AND ic.index_id=i.index_id
JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
WHERE i.is_unique_constraint = 1 AND s.name = 'dw'
GROUP BY t.name, i.name

UNION ALL

SELECT t.name, N'DEFAULT', dc.name, c.name + N' = ' + dc.definition
FROM sys.default_constraints dc
JOIN sys.tables  t ON t.object_id = dc.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.columns c ON c.object_id = dc.parent_object_id
                  AND c.column_id = dc.parent_column_id
WHERE s.name = 'dw'
ORDER BY TableName, LoaiConstraint;
GO


/* =====================================================================
   8. TONG KET -- so nay dua truc tiep len slide
   ===================================================================== */
PRINT '=== 8. TONG KET ===';

SELECT
    (SELECT COUNT(*) FROM sys.tables t JOIN sys.schemas s
        ON s.schema_id=t.schema_id WHERE s.name='dw')                AS SoBangDW,
    (SELECT COUNT(*) FROM sys.tables WHERE name LIKE 'Fact%')         AS SoFact,
    (SELECT COUNT(*) FROM sys.tables WHERE name LIKE 'Dim%')          AS SoDimension,
    (SELECT COUNT(*) FROM sys.foreign_keys)                           AS SoQuanHe,
    (SELECT COUNT(*) FROM sys.columns c JOIN sys.tables t
        ON t.object_id=c.object_id JOIN sys.schemas s
        ON s.schema_id=t.schema_id WHERE s.name='dw')                 AS TongSoCot,
    (SELECT COUNT(*) FROM MelbourneFB_STG.sys.tables t
     JOIN MelbourneFB_STG.sys.schemas s ON s.schema_id=t.schema_id
     WHERE s.name='stg')                                              AS SoBangStaging;
-- ky vong: 9 bang DW / 3 fact / 6 dimension / 10 quan he / ~15 bang staging

-- Tong so dong toan warehouse
SELECT SUM(p.row_count) AS TongSoDongDW
FROM sys.tables t
JOIN sys.dm_db_partition_stats p ON p.object_id = t.object_id
WHERE p.index_id IN (0, 1);
-- ky vong khoang 1.907.000 dong
GO

PRINT 'Xuat cau truc hoan tat.';
GO


SELECT name, state_desc, create_date
FROM sys.databases
ORDER BY database_id;

USE MelbourneFB_DW;

SELECT 
    s.name AS SchemaName,
    t.name AS TableName,
    SUM(p.rows) AS [RowCount]
FROM sys.tables t
JOIN sys.schemas s ON t.schema_id = s.schema_id
LEFT JOIN sys.partitions p 
    ON t.object_id = p.object_id AND p.index_id IN (0, 1)
GROUP BY s.name, t.name
ORDER BY t.name;


SELECT c.column_id, c.name AS ColumnName, ty.name AS DataType, c.is_nullable
FROM sys.columns c
JOIN sys.types ty ON c.user_type_id = ty.user_type_id
WHERE c.object_id = OBJECT_ID('dw.FactFootfallHourly')
ORDER BY c.column_id;

    /* =====================================================================
   BUOC 11 -- KIEM TRA TOAN VEN THAM CHIEU va DO SAN SANG CHO POWER BI
   ---------------------------------------------------------------------
   File nay BO SUNG cho 10_dq_tests.sql, khong thay the.
     10_dq_tests.sql  -> grain, doi chieu so lieu, double-count, unknown
     11 (file nay)    -> LIEN KET giua cac bang, va nhung dieu kien ma
                         Power BI bat buoc phai co de dung quan he 1:*

   TAI SAO CAN RIENG PHAN NAY
     Power BI khong doc FOREIGN KEY cua SQL Server. No tu do quan he
     bang cach nhin DU LIEU. Neu mot cot khoa cua dimension bi TRUNG,
     Power BI se im lang ha quan he xuong many-to-many, va moi measure
     tong hop se bi nhan len ma KHONG bao loi. Do la loi nguy hiem nhat
     trong toan bo khau bao cao -- so van hien ra, chi la sai.

   Chay SAU 06b_load_dim_censusyear.sql.
   ===================================================================== */
USE MelbourneFB_DW;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS #R;
CREATE TABLE #R (
    TestID   INT,
    Nhom     NVARCHAR(30),
    NoiDung  NVARCHAR(200),
    ThucTe   NVARCHAR(50),
    KyVong   NVARCHAR(50),
    KetQua   NVARCHAR(10)
);

DECLARE @a INT, @b INT;


/* =====================================================================
   NHOM A -- DANH SACH FOREIGN KEY
   ---------------------------------------------------------------------
   is_not_trusted = 1 nghia la FK duoc them bang WITH NOCHECK: SQL Server
   chan du lieu MOI nhung KHONG bao dam du lieu CU hop le. Voi mot DW
   dung de bao cao thi day la trang thai khong chap nhan duoc.
   ===================================================================== */
PRINT '--- A. Danh sach Foreign Key trong schema dw ---';

SELECT
    fk.name                                     AS TenFK,
    OBJECT_NAME(fk.parent_object_id)            AS BangCon,
    COL_NAME(fkc.parent_object_id,
             fkc.parent_column_id)              AS CotKhoa,
    OBJECT_NAME(fk.referenced_object_id)        AS BangCha,
    fk.is_disabled                              AS BiTatCC,
    fk.is_not_trusted                           AS KhongDuocTinCay
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
WHERE fk.schema_id = SCHEMA_ID('dw')
ORDER BY BangCon, BangCha;

-- T25: du 12 FK  (Fact1: 5, Fact2: 3, Fact3: 4)
SELECT @a = COUNT(*) FROM sys.foreign_keys WHERE schema_id = SCHEMA_ID('dw');
INSERT INTO #R VALUES (25, N'Foreign key',
    N'Schema dw co du 12 FOREIGN KEY', CAST(@a AS NVARCHAR), N'12',
    CASE WHEN @a = 12 THEN N'PASS' ELSE N'FAIL' END);

-- T26: khong FK nao bi tat hoac khong duoc tin cay
SELECT @a = COUNT(*) FROM sys.foreign_keys
WHERE schema_id = SCHEMA_ID('dw') AND (is_disabled = 1 OR is_not_trusted = 1);
INSERT INTO #R VALUES (26, N'Foreign key',
    N'Khong FK nao bi disable hoac not-trusted', CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);


/* =====================================================================
   NHOM B -- KHOA DIMENSION PHAI DUY NHAT
   ---------------------------------------------------------------------
   Day la dieu kien SONG CON cho Power BI. Moi cot duoi day se nam o
   phia "1" cua quan he 1:*. Trung mot dong la fan-out toan bo measure.
   ===================================================================== */

-- T27: DimBlock.BlockKey duy nhat
SELECT @a = COUNT(*) FROM (
    SELECT BlockKey FROM dw.DimBlock GROUP BY BlockKey HAVING COUNT(*) > 1) x;
INSERT INTO #R VALUES (27, N'Khoa duy nhat',
    N'DimBlock.BlockKey khong trung', CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T28: DimSensor -- moi LocationID chi duoc co DUNG 1 dong IsCurrent = 1
--      SCD Type 2 sai o buoc dong dong cu se tao 2 dong current
--      -> load fact lan sau nhan doi luot nguoi di bo.
SELECT @a = COUNT(*) FROM (
    SELECT LocationID FROM dw.DimSensor
    WHERE IsCurrent = 1 AND SensorKey <> -1
    GROUP BY LocationID HAVING COUNT(*) > 1) x;
INSERT INTO #R VALUES (28, N'Khoa duy nhat',
    N'DimSensor: moi LocationID chi 1 dong IsCurrent=1',
    CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T29: DimCensusYear.CensusYear duy nhat
SELECT @a = COUNT(*) FROM (
    SELECT CensusYear FROM dw.DimCensusYear
    GROUP BY CensusYear HAVING COUNT(*) > 1) x;
INSERT INTO #R VALUES (29, N'Khoa duy nhat',
    N'DimCensusYear.CensusYear khong trung', CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T30: DimDate.DateKey va DimTime.TimeKey duy nhat
SELECT @a = (SELECT COUNT(*) FROM (SELECT DateKey FROM dw.DimDate
                GROUP BY DateKey HAVING COUNT(*) > 1) x)
          + (SELECT COUNT(*) FROM (SELECT TimeKey FROM dw.DimTime
                GROUP BY TimeKey HAVING COUNT(*) > 1) y);
INSERT INTO #R VALUES (30, N'Khoa duy nhat',
    N'DimDate.DateKey va DimTime.TimeKey khong trung',
    CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);


/* =====================================================================
   NHOM C -- KHONG CO KHOA MO COI (orphan)
   ---------------------------------------------------------------------
   Ve ly thuyet FK da chan. Nhung neu FK bi not-trusted (T26) thi phan
   nay moi la bang chung that. Chay ca hai de chac chan.
   ===================================================================== */

-- T31: Fact 1 -- ca 5 duong noi
SELECT @a =
    (SELECT COUNT(*) FROM dw.FactFootfallHourly f
     LEFT JOIN dw.DimDate d ON d.DateKey = f.DateKey WHERE d.DateKey IS NULL)
  + (SELECT COUNT(*) FROM dw.FactFootfallHourly f
     LEFT JOIN dw.DimTime t ON t.TimeKey = f.TimeKey WHERE t.TimeKey IS NULL)
  + (SELECT COUNT(*) FROM dw.FactFootfallHourly f
     LEFT JOIN dw.DimSensor s ON s.SensorKey = f.SensorKey WHERE s.SensorKey IS NULL)
  + (SELECT COUNT(*) FROM dw.FactFootfallHourly f
     LEFT JOIN dw.DimBlock b ON b.BlockKey = f.BlockKey WHERE b.BlockKey IS NULL)
  + (SELECT COUNT(*) FROM dw.FactFootfallHourly f
     LEFT JOIN dw.DimWeather w ON w.WeatherKey = f.WeatherKey WHERE w.WeatherKey IS NULL);
INSERT INTO #R VALUES (31, N'Orphan',
    N'Fact 1: khong dong nao mo coi tren 5 dim', CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T32: Fact 2 -- Block, Date, CensusYear
SELECT @a =
    (SELECT COUNT(*) FROM dw.FactBlockAnnual f
     LEFT JOIN dw.DimBlock b ON b.BlockKey = f.BlockKey WHERE b.BlockKey IS NULL)
  + (SELECT COUNT(*) FROM dw.FactBlockAnnual f
     LEFT JOIN dw.DimDate d ON d.DateKey = f.DateKey WHERE d.DateKey IS NULL)
  + (SELECT COUNT(*) FROM dw.FactBlockAnnual f
     LEFT JOIN dw.DimCensusYear c ON c.CensusYear = f.CensusYear WHERE c.CensusYear IS NULL);
INSERT INTO #R VALUES (32, N'Orphan',
    N'Fact 2: khong dong nao mo coi tren 3 dim', CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T33: Fact 3 -- Block, Date, Industry, CensusYear
SELECT @a =
    (SELECT COUNT(*) FROM dw.FactBlockIndustryAnnual f
     LEFT JOIN dw.DimBlock b ON b.BlockKey = f.BlockKey WHERE b.BlockKey IS NULL)
  + (SELECT COUNT(*) FROM dw.FactBlockIndustryAnnual f
     LEFT JOIN dw.DimDate d ON d.DateKey = f.DateKey WHERE d.DateKey IS NULL)
  + (SELECT COUNT(*) FROM dw.FactBlockIndustryAnnual f
     LEFT JOIN dw.DimIndustry i ON i.IndustryKey = f.IndustryKey WHERE i.IndustryKey IS NULL)
  + (SELECT COUNT(*) FROM dw.FactBlockIndustryAnnual f
     LEFT JOIN dw.DimCensusYear c ON c.CensusYear = f.CensusYear WHERE c.CensusYear IS NULL);
INSERT INTO #R VALUES (33, N'Orphan',
    N'Fact 3: khong dong nao mo coi tren 4 dim', CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);


/* =====================================================================
   NHOM D -- DIEU KIEN RIENG CUA MO HINH POWER BI
   ===================================================================== */

-- T34: Fact 1 va Fact 2/3 KHONG duoc dung chung truc DimDate
--      Day chinh la ly do phai co DimCensusYear. Test nay ghi lai
--      con so de dua vao muc "kho khan gap phai" trong bao cao.
SELECT @a = COUNT(DISTINCT f.DateKey)
FROM dw.FactBlockAnnual f
WHERE EXISTS (SELECT 1 FROM dw.FactFootfallHourly g WHERE g.DateKey = f.DateKey);
INSERT INTO #R VALUES (34, N'Model Power BI',
    N'So DateKey chung giua Fact 1 va Fact 2 (chi 31/12/2024)',
    CAST(@a AS NVARCHAR), N'1',
    CASE WHEN @a = 1 THEN N'PASS' ELSE N'CHECK' END);

-- T35: DimBlock phai phu HET block xuat hien trong ca 3 fact
SELECT @a = COUNT(*) FROM (
    SELECT BlockKey FROM dw.FactFootfallHourly
    UNION SELECT BlockKey FROM dw.FactBlockAnnual
    UNION SELECT BlockKey FROM dw.FactBlockIndustryAnnual
) x
WHERE NOT EXISTS (SELECT 1 FROM dw.DimBlock d WHERE d.BlockKey = x.BlockKey);
INSERT INTO #R VALUES (35, N'Model Power BI',
    N'DimBlock phu het BlockKey cua ca 3 fact', CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);

-- T36: block co du CA footfall LAN ghe -> tap hop tinh duoc Seat Saturation
SELECT @a = COUNT(DISTINCT a.BlockKey)
FROM dw.FactBlockAnnual a
WHERE a.IsLatestCensusYear = 1
  AND ISNULL(a.TotalSeats, 0) > 0
  AND EXISTS (SELECT 1 FROM dw.FactFootfallHourly f
              WHERE f.BlockKey = a.BlockKey AND f.BlockKey <> -1);
INSERT INTO #R VALUES (36, N'Model Power BI',
    N'So block tinh duoc Seat Saturation (BQ1)', CAST(@a AS NVARCHAR), N'>= 20',
    CASE WHEN @a >= 20 THEN N'PASS' ELSE N'FAIL' END);

-- T37: cot khong cong duoc (non-additive) phai duoc nhan dien
--      Power BI se SUM chung neu khong doi Summarize By = None.
--      Test nay chi in ra bien do de doi chieu voi cai nhin thay trong PBI.
SELECT
    CAST(MIN(TemperatureC) AS DECIMAL(5,1))  AS NhietDoThapNhat,
    CAST(MAX(TemperatureC) AS DECIMAL(5,1))  AS NhietDoCaoNhat,
    CAST(AVG(TemperatureC) AS DECIMAL(5,1))  AS NhietDoTrungBinh,
    CAST(MAX(PrecipitationMM) AS DECIMAL(6,1)) AS MuaLonNhat_mm
FROM dw.FactFootfallHourly;
-- Trong Power BI, card nhiet do PHAI ra so trong khoang nay.
-- Neu ra hang chuc nghin do la quen doi Summarize By.

-- T38: khong co measure am o ca 3 fact
SELECT @a =
    (SELECT COUNT(*) FROM dw.FactFootfallHourly WHERE TotalPedestrians < 0)
  + (SELECT COUNT(*) FROM dw.FactBlockAnnual
     WHERE TotalSeats < 0 OR TotalFBVenues < 0 OR TotalJobs < 0)
  + (SELECT COUNT(*) FROM dw.FactBlockIndustryAnnual
     WHERE JobCount < 0 OR EstablishmentCount < 0);
INSERT INTO #R VALUES (38, N'Model Power BI',
    N'Khong co measure am o ca 3 fact', CAST(@a AS NVARCHAR), N'0',
    CASE WHEN @a = 0 THEN N'PASS' ELSE N'FAIL' END);


/* =====================================================================
   TONG KET
   ===================================================================== */
SELECT * FROM #R ORDER BY TestID;

SELECT KetQua, COUNT(*) AS SoTest
FROM #R GROUP BY KetQua ORDER BY KetQua;

IF EXISTS (SELECT 1 FROM #R WHERE KetQua = 'FAIL')
BEGIN
    PRINT '';
    PRINT '*** CO TEST FAIL -- SUA TRUOC KHI MO POWER BI ***';
    SELECT TestID, Nhom, NoiDung, ThucTe, KyVong FROM #R WHERE KetQua = 'FAIL';
END
ELSE
    PRINT 'Toan bo lien ket hop le. San sang nap vao Power BI va dong goi SSIS.';
GO


/* =====================================================================
   PHU LUC -- BANG THONG KE DUA THANG VAO BAO CAO (tieu chi 4 va 8)
   ===================================================================== */
PRINT '--- Ban do lien ket: fact nao noi vao dim nao ---';

SELECT
    OBJECT_NAME(fk.parent_object_id)                          AS Fact,
    OBJECT_NAME(fk.referenced_object_id)                      AS Dimension,
    COL_NAME(fkc.parent_object_id, fkc.parent_column_id)      AS KhoaNgoai,
    (SELECT SUM(p.rows) FROM sys.partitions p
     WHERE p.object_id = fk.parent_object_id AND p.index_id IN (0,1)) AS SoDongFact,
    (SELECT SUM(p.rows) FROM sys.partitions p
     WHERE p.object_id = fk.referenced_object_id AND p.index_id IN (0,1)) AS SoDongDim
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
WHERE fk.schema_id = SCHEMA_ID('dw')
ORDER BY Fact, Dimension;

-- Dimension nao duoc chia se giua nhieu fact -> chung minh galaxy schema
SELECT
    OBJECT_NAME(fk.referenced_object_id) AS Dimension,
    COUNT(DISTINCT fk.parent_object_id)  AS SoFactSuDung,
    CASE WHEN COUNT(DISTINCT fk.parent_object_id) > 1
         THEN N'Conformed' ELSE N'Private' END AS LoaiDimension
FROM sys.foreign_keys fk
WHERE fk.schema_id = SCHEMA_ID('dw')
GROUP BY OBJECT_NAME(fk.referenced_object_id)
ORDER BY SoFactSuDung DESC, Dimension;
-- Ky vong: DimBlock 3 fact, DimDate 3 fact, DimCensusYear 2 fact -> Conformed
--          DimTime/DimSensor/DimWeather 1 fact, DimIndustry 1 fact -> Private
--          (mentor da duyet: private dimension per fact la hop le trong Kimball)
GO

DROP TABLE IF EXISTS #R;
GO