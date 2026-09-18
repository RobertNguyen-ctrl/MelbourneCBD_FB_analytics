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


USE MelbourneFB_DW;
SELECT b.BlockID, b.AreaName, SUM(f.JobCount) AS TongViecLam
FROM dw.FactBlockIndustryAnnual f
JOIN dw.DimBlock b ON b.BlockKey = f.BlockKey
WHERE f.CensusYear = 2024
GROUP BY b.BlockID, b.AreaName
HAVING SUM(f.JobCount) = 0
ORDER BY b.BlockID;



USE MelbourneFB_DW;
SELECT TOP 15
    b.BlockID,
    b.AreaName,
    a.TotalSeats,
    a.PipelineProjects,
    a.PipelineResiDwellings,
    a.PipelineStudentBeds,
    a.PipelineHotelRooms
FROM dw.FactBlockAnnual a
JOIN dw.DimBlock b ON b.BlockKey = a.BlockKey
WHERE a.IsLatestCensusYear = 1
  AND b.HasFootfallCoverage = 1
  AND a.PipelineProjects > 0
ORDER BY a.PipelineResiDwellings DESC;


--BQ3
USE MelbourneFB_DW;
SELECT COUNT(*) AS BlockCoLicenceDem,
       SUM(LateNightLicenceCount) AS TongLicenceDem,
       SUM(Licence24hCount)       AS Tong24h
FROM dw.FactBlockAnnual
WHERE IsLatestCensusYear = 1 AND LateNightLicenceCount > 0;