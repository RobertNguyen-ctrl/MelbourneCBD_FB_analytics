/* =====================================================================
   BUOC 09 -- FACT 2: FactBlockAnnual   13.519 dong
   ---------------------------------------------------------------------
   GRAIN: 1 block x 1 census year
   PHUC VU: BQ1 (phia cung), BQ3, BQ4, BQ5, BQ6, BQ7

   CONSOLIDATED FACT TABLE -- gop 6 nguon cung grain:
     A. stg.CafeSeats             -> ghe indoor/outdoor
     B. stg.BarPatrons            -> suc chua patron
     C. (A + B)                   -> so dia diem theo loai hinh
     D. dw.FactBlockIndustryAnnual-> viec lam, so co so (dan so ban ngay)
     E. stg.ResidentialDwellings  -> so can ho (dan so ban dem)
     F. stg.LiquorLicences        -> giay phep dem muon   [CHI nam moi nhat]
     G. stg.DevActivity           -> pipeline              [CHI nam moi nhat]

   =====================================================================
   BA DIEM PHAI HIEU RO TRUOC KHI CHAY
   =====================================================================

   1) SPINE LAY TU KHUNG CENSUS, KHONG CROSS JOIN
      Khung CLUE KHONG du 603 block moi nam:
        2002-2006: 543 block   2007: 555   2017-2018: 602   con lai: 603
      Tong = 13.519 block-nam.
      Neu CROSS JOIN DimBlock x 23 nam se ra 13.869 dong, tuc tao ra
      350 dong block-nam CHUA TUNG duoc dieu tra. Nhung dong do se
      hien la 0 ghe / 0 viec lam va bi doc sai thanh "khu vuc trong".
      => Spine = DISTINCT (Block ID, Census year) tu stg.JobsByBlock.

   2) LEFT JOIN TU SPINE RA, KHONG BAO GIO INNER JOIN
      Block khong co cafe nao van PHAI co dong voi TotalSeats = 0.
      Do chinh la nhung block ma BQ1 dang di tim. INNER JOIN se lam
      chung bien mat khoi ket qua.

   3) NHOM COT Licence* VA Pipeline* CHI DIEN VAO NAM MOI NHAT
      Hai nhom nay KHONG phai du lieu census:
        Licence*  = snapshot 30/04/2026
        Pipeline* = Development Activity Monitor, khong co truc thoi gian
      Chung duoc dat vao dong IsLatestCensusYear = 1, cac nam khac NULL.
      Neu dien cho ca 23 nam thi SUM(PipelineResiDwellings) se ra
      854.000 can thay vi 37.128 -- sai 23 lan va trong van rat binh
      thuong. Day la rui ro double counting lon nhat cua thiet ke gop
      fact, phai ghi ro trong bao cao.
   ===================================================================== */
USE MelbourneFB_DW;
GO

/* Dieu kien tien quyet ----------------------------------------------- */
IF (SELECT COUNT(*) FROM dw.FactBlockIndustryAnnual) = 0
BEGIN
    RAISERROR('FactBlockIndustryAnnual con rong. Chay 08_load_fact_industry.sql truoc.', 16, 1);
    RETURN;
END
GO

TRUNCATE TABLE dw.FactBlockAnnual;
GO

DECLARE @LatestYear SMALLINT =
    (SELECT MAX(TRY_CAST([Census year] AS SMALLINT))
     FROM MelbourneFB_STG.stg.JobsByBlock);
PRINT 'Census year moi nhat = ' + CAST(@LatestYear AS VARCHAR(10));
GO


/* =====================================================================
   0. SPINE -- khung census that
   ===================================================================== */
PRINT '--- 0. Spine ---';

DROP TABLE IF EXISTS #Spine;
SELECT DISTINCT
    b.BlockKey,
    TRY_CAST(j.[Census year] AS SMALLINT) AS CensusYear,
    TRY_CAST(j.[Block ID] AS INT)         AS BlockID
INTO #Spine
FROM MelbourneFB_STG.stg.JobsByBlock j
JOIN dw.DimBlock b ON b.BlockID = TRY_CAST(j.[Block ID] AS INT)
WHERE TRY_CAST(j.[Census year] AS SMALLINT) IS NOT NULL;

CREATE UNIQUE CLUSTERED INDEX CX_Spine ON #Spine(BlockKey, CensusYear);
SELECT COUNT(*) AS Spine_Rows, 13519 AS KyVong FROM #Spine;
GO


/* =====================================================================
   A. GHE  (stg.CafeSeats)
   ---------------------------------------------------------------------
   LUU Y VE DINH NGHIA: file "cafes-and-restaurants-with-seating-capacity"
   chua MOI co so co cho ngoi, ke ca Accommodation, Bakery, Supermarket.
   TotalSeats o day = toan bo ghe trong tap du lieu do, KHONG chi ghe
   cua 3 loai hinh F&B cot lo. Ghi ro dinh nghia nay trong bao cao.
   Ghe cua pub CO tinh vao TotalSeats (pub xuat hien trong ca 2 file).
   ===================================================================== */
PRINT '--- A. Ghe ---';

DROP TABLE IF EXISTS #Seats;
SELECT
    TRY_CAST(c.[Block ID] AS INT)         AS BlockID,
    TRY_CAST(c.[Census year] AS SMALLINT) AS CensusYear,
    SUM(CASE WHEN c.[Seating type] = N'Seats - Indoor'
             THEN TRY_CAST(c.[Number of seats] AS INT) ELSE 0 END) AS IndoorSeats,
    SUM(CASE WHEN c.[Seating type] = N'Seats - Outdoor'
             THEN TRY_CAST(c.[Number of seats] AS INT) ELSE 0 END) AS OutdoorSeats,
    SUM(ISNULL(TRY_CAST(c.[Number of seats] AS INT), 0))           AS TotalSeats
INTO #Seats
FROM MelbourneFB_STG.stg.CafeSeats c
WHERE TRY_CAST(c.[Block ID] AS INT) IS NOT NULL
  AND TRY_CAST(c.[Census year] AS SMALLINT) IS NOT NULL
GROUP BY TRY_CAST(c.[Block ID] AS INT), TRY_CAST(c.[Census year] AS SMALLINT);

CREATE UNIQUE CLUSTERED INDEX CX_Seats ON #Seats(BlockID, CensusYear);
GO


/* =====================================================================
   B. SUC CHUA PATRON  (stg.BarPatrons)
   ===================================================================== */
PRINT '--- B. Patron ---';

DROP TABLE IF EXISTS #Patrons;
SELECT
    TRY_CAST(p.[Block ID] AS INT)         AS BlockID,
    TRY_CAST(p.[Census year] AS SMALLINT) AS CensusYear,
    SUM(ISNULL(TRY_CAST(p.[Number of patrons] AS INT), 0)) AS BarPatronCapacity
INTO #Patrons
FROM MelbourneFB_STG.stg.BarPatrons p
WHERE TRY_CAST(p.[Block ID] AS INT) IS NOT NULL
  AND TRY_CAST(p.[Census year] AS SMALLINT) IS NOT NULL
GROUP BY TRY_CAST(p.[Block ID] AS INT), TRY_CAST(p.[Census year] AS SMALLINT);

CREATE UNIQUE CLUSTERED INDEX CX_Patrons ON #Patrons(BlockID, CensusYear);
GO


/* =====================================================================
   C. SO DIA DIEM THEO LOAI HINH  (thay cho DimVenue da bo)
   ---------------------------------------------------------------------
   Mot dia diem = 1 (Property ID + Trading name). Mot Property ID co the
   chua nhieu dia diem (food court, trung tam thuong mai).

   Pub xuat hien trong CA HAI file nguon -> phai UNION (khong UNION ALL)
   de khu trung, neu khong BarPubVenues se bi dem hai lan.
   ===================================================================== */
PRINT '--- C. So dia diem theo loai hinh ---';

DROP TABLE IF EXISTS #VenueList;
SELECT DISTINCT
    TRY_CAST(c.[Block ID] AS INT)         AS BlockID,
    TRY_CAST(c.[Census year] AS SMALLINT) AS CensusYear,
    c.[Property ID] + N'|' + ISNULL(c.[Trading name], N'') AS VenueID,
    CASE
        WHEN c.[Industry (ANZSIC4) description] LIKE N'%Takeaway%'   THEN N'Takeaway'
        WHEN c.[Industry (ANZSIC4) description] LIKE N'%Pubs%'
          OR c.[Industry (ANZSIC4) description] LIKE N'%Bar%'
          OR c.[Industry (ANZSIC4) description] LIKE N'%Clubs (Hospitality)%'
                                                                     THEN N'Bar/Pub'
        WHEN c.[Industry (ANZSIC4) description] LIKE N'%Cafes%'
          OR c.[Industry (ANZSIC4) description] LIKE N'%Restaurant%' THEN N'Cafe/Restaurant'
        ELSE N'Other'
    END AS VenueConcept
INTO #VenueList
FROM MelbourneFB_STG.stg.CafeSeats c
WHERE TRY_CAST(c.[Block ID] AS INT) IS NOT NULL
  AND TRY_CAST(c.[Census year] AS SMALLINT) IS NOT NULL
  AND c.[Property ID] IS NOT NULL;

-- Bo sung cac pub CHI co trong file bars (khong co trong file cafes)
INSERT INTO #VenueList (BlockID, CensusYear, VenueID, VenueConcept)
SELECT DISTINCT
    TRY_CAST(p.[Block ID] AS INT),
    TRY_CAST(p.[Census year] AS SMALLINT),
    p.[Property ID] + N'|' + ISNULL(p.[Trading name], N''),
    N'Bar/Pub'
FROM MelbourneFB_STG.stg.BarPatrons p
WHERE TRY_CAST(p.[Block ID] AS INT) IS NOT NULL
  AND TRY_CAST(p.[Census year] AS SMALLINT) IS NOT NULL
  AND p.[Property ID] IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM #VenueList v
      WHERE v.VenueID = p.[Property ID] + N'|' + ISNULL(p.[Trading name], N'')
        AND v.CensusYear = TRY_CAST(p.[Census year] AS SMALLINT));

DROP TABLE IF EXISTS #VenueCounts;
SELECT
    BlockID, CensusYear,
    COUNT(DISTINCT CASE WHEN VenueConcept = N'Cafe/Restaurant' THEN VenueID END) AS CafeRestaurantVenues,
    COUNT(DISTINCT CASE WHEN VenueConcept = N'Bar/Pub'         THEN VenueID END) AS BarPubVenues,
    COUNT(DISTINCT CASE WHEN VenueConcept = N'Takeaway'        THEN VenueID END) AS TakeawayVenues
INTO #VenueCounts
FROM #VenueList
GROUP BY BlockID, CensusYear;

CREATE UNIQUE CLUSTERED INDEX CX_VenueCounts ON #VenueCounts(BlockID, CensusYear);
GO


/* =====================================================================
   D. DAN SO BAN NGAY  (tu FACT 3, khong doc lai file nguon)
   ---------------------------------------------------------------------
   Cac co IsOfficeWorker / IsFoodBeverage / IsRetail nam DUY NHAT o
   DimIndustry. Nho vay test "SUM(Fact3) = Fact2.TotalJobs" dung theo
   thiet ke, va khi doi dinh nghia "nganh nao la office" thi chi sua
   MOT cho.
   ===================================================================== */
PRINT '--- D. Dan so ban ngay (tu Fact 3) ---';

DROP TABLE IF EXISTS #Jobs;
SELECT
    f.BlockKey,
    f.CensusYear,
    SUM(ISNULL(f.JobCount, 0))                                   AS TotalJobs,
    SUM(CASE WHEN i.IsFoodBeverage = 1 THEN ISNULL(f.JobCount,0) ELSE 0 END) AS FoodBeverageJobs,
    SUM(CASE WHEN i.IsOfficeWorker = 1 THEN ISNULL(f.JobCount,0) ELSE 0 END) AS OfficeTypeJobs,
    SUM(CASE WHEN i.IsRetail       = 1 THEN ISNULL(f.JobCount,0) ELSE 0 END) AS RetailJobs,
    SUM(ISNULL(f.EstablishmentCount, 0))                         AS TotalEstablishments,
    SUM(CASE WHEN i.IsFoodBeverage = 1
             THEN ISNULL(f.EstablishmentCount,0) ELSE 0 END)     AS FoodBeverageEstabs
INTO #Jobs
FROM dw.FactBlockIndustryAnnual f
JOIN dw.DimIndustry i ON i.IndustryKey = f.IndustryKey
GROUP BY f.BlockKey, f.CensusYear;

CREATE UNIQUE CLUSTERED INDEX CX_Jobs ON #Jobs(BlockKey, CensusYear);
GO


/* =====================================================================
   E. DAN SO BAN DEM  (stg.ResidentialDwellings)
   ---------------------------------------------------------------------
   GRAIN CUA FILE: 1 toa nha x 1 nam x 1 loai nha o -- KHONG phai block.
   Phai GROUP BY truoc khi join. Cot [Dwelling number] la SO CAN trong
   toa nha do, khong phai so toa nha.
   Ba loai: House/Townhouse (183.288 dong), Residential Apartments
   (35.330), Student Apartments (1.062).
   ===================================================================== */
PRINT '--- E. Dan so ban dem ---';

DROP TABLE IF EXISTS #Dwellings;
SELECT
    TRY_CAST(r.[Block ID] AS INT)         AS BlockID,
    TRY_CAST(r.[Census year] AS SMALLINT) AS CensusYear,
    SUM(ISNULL(TRY_CAST(r.[Dwelling number] AS INT), 0))          AS TotalDwellings,
    SUM(CASE WHEN r.[Dwelling type] = N'Residential Apartments'
             THEN ISNULL(TRY_CAST(r.[Dwelling number] AS INT),0) ELSE 0 END) AS ApartmentDwellings,
    SUM(CASE WHEN r.[Dwelling type] = N'Student Apartments'
             THEN ISNULL(TRY_CAST(r.[Dwelling number] AS INT),0) ELSE 0 END) AS StudentDwellings,
    SUM(CASE WHEN r.[Dwelling type] = N'House/Townhouse'
             THEN ISNULL(TRY_CAST(r.[Dwelling number] AS INT),0) ELSE 0 END) AS HouseDwellings
INTO #Dwellings
FROM MelbourneFB_STG.stg.ResidentialDwellings r
WHERE TRY_CAST(r.[Block ID] AS INT) IS NOT NULL
  AND TRY_CAST(r.[Census year] AS SMALLINT) IS NOT NULL
GROUP BY TRY_CAST(r.[Block ID] AS INT), TRY_CAST(r.[Census year] AS SMALLINT);

CREATE UNIQUE CLUSTERED INDEX CX_Dwellings ON #Dwellings(BlockID, CensusYear);
GO


/* =====================================================================
   F. GIAY PHEP RUOU  (snapshot 30/04/2026)  --  KHONG co truc census
   ---------------------------------------------------------------------
   Bien nhan chu [Trading Hours] thanh so gio dong cua dung duoc.
   Day la gia tri gia tang cua ETL: nguon chi co chuoi 'Trading to 3am',
   DW cho ra IsLateNight = 1.
   Giay phep KHONG co Block ID -> lay tu stg.NearestBlockMap (buoc 03).
   ===================================================================== */
PRINT '--- F. Giay phep ruou ---';

DROP TABLE IF EXISTS #Licences;
CREATE TABLE #Licences (
    BlockKey              INT PRIMARY KEY,
    LicenceCount          INT NULL,
    LateNightLicenceCount INT NULL,
    Licence24hCount       INT NULL,
    LicensedCapacity      INT NULL
);

IF EXISTS (SELECT 1 FROM MelbourneFB_STG.stg.NearestBlockMap WHERE EntityType = 'LICENCE')
BEGIN
    INSERT INTO #Licences
        (BlockKey, LicenceCount, LateNightLicenceCount, Licence24hCount, LicensedCapacity)
    SELECT
        b.BlockKey,
        COUNT(*),
        SUM(CASE WHEN l.[Trading Hours] LIKE N'%to 3am%'
                   OR l.[Trading Hours] LIKE N'%to 4am%'
                   OR l.[Trading Hours] LIKE N'%to 5am%'
                   OR l.[Trading Hours] LIKE N'%to 6am%'
                   OR l.[Trading Hours] LIKE N'%to 7am%'
                   OR l.[Trading Hours] LIKE N'%24 hour%'
                 THEN 1 ELSE 0 END),
        SUM(CASE WHEN l.[Trading Hours] LIKE N'%24 hour%' THEN 1 ELSE 0 END),
        SUM(TRY_CAST(l.[Maximum Capacity] AS INT))   -- SUM bo qua NULL (439/2196)
    FROM MelbourneFB_STG.stg.LiquorLicences l
    JOIN MelbourneFB_STG.stg.NearestBlockMap m
         ON m.EntityType = 'LICENCE' AND m.EntityKey = l.[Licence Num]
    JOIN dw.DimBlock b ON b.BlockID = TRY_CAST(m.BlockID AS INT)
    WHERE l.[Council] LIKE N'%MELBOURNE CITY%'
    GROUP BY b.BlockKey;

    SELECT COUNT(*) AS SoBlockCoGiayPhep, SUM(LicenceCount) AS TongGiayPhep
    FROM #Licences;   -- ky vong tong = 2196
END
ELSE
    PRINT 'CANH BAO: chua co mapping LICENCE trong stg.NearestBlockMap. '
        + 'Cac cot Licence* se de NULL. Chay muc 4 cua 03_spatial_mapping.sql roi chay lai file nay.';
GO


/* =====================================================================
   G. PIPELINE  (Development Activity Monitor)  --  KHONG co truc census
   ---------------------------------------------------------------------
   Chi lay du an CHUA hoan thanh (status <> COMPLETED). Cot
   year_completed rong hoan toan voi nhom nay nen khong the phan tich
   theo nam -- chi tong theo block.
   ===================================================================== */
PRINT '--- G. Pipeline ---';

DROP TABLE IF EXISTS #Pipeline;
SELECT
    b.BlockKey,
    COUNT(*)                                              AS PipelineProjects,
    SUM(ISNULL(TRY_CAST(d.resi_dwellings AS INT), 0))      AS PipelineResiDwellings,
    SUM(ISNULL(TRY_CAST(d.student_beds   AS INT), 0))      AS PipelineStudentBeds,
    SUM(ISNULL(TRY_CAST(d.hotel_rooms    AS INT), 0))      AS PipelineHotelRooms,
    SUM(ISNULL(TRY_CAST(d.office_flr AS DECIMAL(14,2)), 0)) AS PipelineOfficeSqm,
    SUM(ISNULL(TRY_CAST(d.retail_flr AS DECIMAL(14,2)), 0)) AS PipelineRetailSqm
INTO #Pipeline
FROM MelbourneFB_STG.stg.DevActivity d
JOIN dw.DimBlock b ON b.BlockID = TRY_CAST(d.clue_block AS INT)
WHERE UPPER(LTRIM(RTRIM(d.status))) <> N'COMPLETED'
GROUP BY b.BlockKey;

CREATE UNIQUE CLUSTERED INDEX CX_Pipeline ON #Pipeline(BlockKey);

SELECT COUNT(*)                     AS SoBlockCoPipeline,   -- ky vong 170
       SUM(PipelineResiDwellings)   AS TongCanHo,           -- ky vong 37.128
       SUM(PipelineOfficeSqm)       AS TongSanVanPhong,     -- ky vong 1.302.004
       SUM(PipelineRetailSqm)       AS TongSanBanLe         -- ky vong 188.121
FROM #Pipeline;
GO


/* =====================================================================
   INSERT CUOI CUNG -- spine LEFT JOIN tat ca
   ===================================================================== */
PRINT '--- INSERT FactBlockAnnual ---';

DECLARE @LatestYear SMALLINT =
    (SELECT MAX(CensusYear) FROM #Spine);

INSERT INTO dw.FactBlockAnnual
    (BlockKey, DateKey, CensusYear, IsLatestCensusYear,
     IndoorSeats, OutdoorSeats, TotalSeats, BarPatronCapacity,
     CafeRestaurantVenues, BarPubVenues, TakeawayVenues, TotalFBVenues,
     TotalJobs, FoodBeverageJobs, OfficeTypeJobs, RetailJobs,
     TotalEstablishments, FoodBeverageEstabs,
     TotalDwellings, ApartmentDwellings, StudentDwellings, HouseDwellings,
     LicenceCount, LateNightLicenceCount, Licence24hCount, LicensedCapacity,
     PipelineProjects, PipelineResiDwellings, PipelineStudentBeds,
     PipelineHotelRooms, PipelineOfficeSqm, PipelineRetailSqm)
SELECT
    sp.BlockKey,
    sp.CensusYear * 10000 + 1231,                    -- 31/12 census year
    sp.CensusYear,
    CAST(CASE WHEN sp.CensusYear = @LatestYear THEN 1 ELSE 0 END AS BIT),

    /* --- A: ghe --- 0 la gia tri THAT (block khong co cafe) --- */
    ISNULL(se.IndoorSeats,  0),
    ISNULL(se.OutdoorSeats, 0),
    ISNULL(se.TotalSeats,   0),
    ISNULL(pa.BarPatronCapacity, 0),

    /* --- C: so dia diem --- */
    ISNULL(vc.CafeRestaurantVenues, 0),
    ISNULL(vc.BarPubVenues,         0),
    ISNULL(vc.TakeawayVenues,       0),
    ISNULL(vc.CafeRestaurantVenues, 0) + ISNULL(vc.BarPubVenues, 0)
        + ISNULL(vc.TakeawayVenues, 0),

    /* --- D: dan so ban ngay --- */
    ISNULL(jb.TotalJobs,            0),
    ISNULL(jb.FoodBeverageJobs,     0),
    ISNULL(jb.OfficeTypeJobs,       0),
    ISNULL(jb.RetailJobs,           0),
    ISNULL(jb.TotalEstablishments,  0),
    ISNULL(jb.FoodBeverageEstabs,   0),

    /* --- E: dan so ban dem --- */
    ISNULL(dw2.TotalDwellings,      0),
    ISNULL(dw2.ApartmentDwellings,  0),
    ISNULL(dw2.StudentDwellings,    0),
    ISNULL(dw2.HouseDwellings,      0),

    /* --- F: licence -- CHI nam moi nhat, cac nam khac NULL --- */
    CASE WHEN sp.CensusYear = @LatestYear THEN ISNULL(li.LicenceCount, 0) END,
    CASE WHEN sp.CensusYear = @LatestYear THEN ISNULL(li.LateNightLicenceCount, 0) END,
    CASE WHEN sp.CensusYear = @LatestYear THEN ISNULL(li.Licence24hCount, 0) END,
    CASE WHEN sp.CensusYear = @LatestYear THEN li.LicensedCapacity END,

    /* --- G: pipeline -- CHI nam moi nhat, cac nam khac NULL --- */
    CASE WHEN sp.CensusYear = @LatestYear THEN ISNULL(pl.PipelineProjects, 0) END,
    CASE WHEN sp.CensusYear = @LatestYear THEN ISNULL(pl.PipelineResiDwellings, 0) END,
    CASE WHEN sp.CensusYear = @LatestYear THEN ISNULL(pl.PipelineStudentBeds, 0) END,
    CASE WHEN sp.CensusYear = @LatestYear THEN ISNULL(pl.PipelineHotelRooms, 0) END,
    CASE WHEN sp.CensusYear = @LatestYear THEN ISNULL(pl.PipelineOfficeSqm, 0) END,
    CASE WHEN sp.CensusYear = @LatestYear THEN ISNULL(pl.PipelineRetailSqm, 0) END

FROM #Spine sp
LEFT JOIN #Seats        se  ON se.BlockID  = sp.BlockID  AND se.CensusYear = sp.CensusYear
LEFT JOIN #Patrons      pa  ON pa.BlockID  = sp.BlockID  AND pa.CensusYear = sp.CensusYear
LEFT JOIN #VenueCounts  vc  ON vc.BlockID  = sp.BlockID  AND vc.CensusYear = sp.CensusYear
LEFT JOIN #Jobs         jb  ON jb.BlockKey = sp.BlockKey AND jb.CensusYear = sp.CensusYear
LEFT JOIN #Dwellings    dw2 ON dw2.BlockID = sp.BlockID  AND dw2.CensusYear = sp.CensusYear
LEFT JOIN #Licences     li  ON li.BlockKey = sp.BlockKey
LEFT JOIN #Pipeline     pl  ON pl.BlockKey = sp.BlockKey;
GO


/* =====================================================================
   KIEM TRA
   ===================================================================== */
SELECT COUNT(*) AS FactBlockAnnual_Rows, 13519 AS KyVong FROM dw.FactBlockAnnual;

-- Grain duy nhat (UQ constraint da bao ve, kiem lai cho chac)
SELECT COUNT(*) AS SoToHopTrung FROM (
    SELECT BlockKey, CensusYear FROM dw.FactBlockAnnual
    GROUP BY BlockKey, CensusYear HAVING COUNT(*) > 1) x;      -- ky vong 0

-- Pipeline: PHAI ra 37.128, KHONG duoc ra 23 x 37.128
SELECT SUM(PipelineResiDwellings) AS TongCanHoPipeline,
       COUNT(PipelineResiDwellings) AS SoDongCoPipeline
FROM dw.FactBlockAnnual;
-- ky vong 37.128 va so dong = 13.519 chia cho 23 nam -> chi nam moi nhat

-- Licence: PHAI ra 2.196
SELECT SUM(LicenceCount) AS TongGiayPhep FROM dw.FactBlockAnnual;

-- Doi chieu Fact 2 vs Fact 3: PHAI ra 0 dong lech
SELECT COUNT(*) AS SoDongLechViecLam FROM (
    SELECT a.BlockKey, a.CensusYear, a.TotalJobs, SUM(ISNULL(i.JobCount,0)) AS TongFact3
    FROM dw.FactBlockAnnual a
    JOIN dw.FactBlockIndustryAnnual i
         ON i.BlockKey = a.BlockKey AND i.CensusYear = a.CensusYear
    GROUP BY a.BlockKey, a.CensusYear, a.TotalJobs
    HAVING a.TotalJobs <> SUM(ISNULL(i.JobCount,0))) x;        -- ky vong 0

-- BQ1 chay duoc: cung va cau tren cung mot block (nam moi nhat)
;WITH Cau AS (
    SELECT f.BlockKey,
           SUM(CAST(f.TotalPedestrians AS BIGINT)) * 1.0
               / COUNT(DISTINCT f.DateKey) AS LuotMoiNgay
    FROM dw.FactFootfallHourly f
    WHERE f.SensorKey <> -1
    GROUP BY f.BlockKey
)
SELECT TOP 20
    b.BlockID, b.CLUESmallArea,
    CAST(c.LuotMoiNgay AS INT)                          AS LuotNguoiMoiNgay,
    a.TotalSeats, a.OutdoorSeats, a.TotalFBVenues,
    CAST(a.TotalSeats * 1000.0 / NULLIF(c.LuotMoiNgay, 0) AS DECIMAL(8,2))
                                                        AS GheTren1000Luot
FROM dw.FactBlockAnnual a
JOIN dw.DimBlock b ON b.BlockKey = a.BlockKey
JOIN Cau        c ON c.BlockKey = a.BlockKey
WHERE a.IsLatestCensusYear = 1
  AND b.HasFootfallCoverage = 1
  AND a.TotalSeats > 0
ORDER BY GheTren1000Luot ASC;
-- Thap nhat = nhieu nguoi, it ghe = khoang trong cung-cau
GO

DROP TABLE IF EXISTS #Spine;
DROP TABLE IF EXISTS #Seats;
DROP TABLE IF EXISTS #Patrons;
DROP TABLE IF EXISTS #VenueList;
DROP TABLE IF EXISTS #VenueCounts;
DROP TABLE IF EXISTS #Jobs;
DROP TABLE IF EXISTS #Dwellings;
DROP TABLE IF EXISTS #Licences;
DROP TABLE IF EXISTS #Pipeline;
GO

PRINT 'Chay tiep 10_dq_tests.sql';
GO
