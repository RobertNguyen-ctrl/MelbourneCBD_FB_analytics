/* =====================================================================
   BUOC 06b -- dw.DimCensusYear   (conformed dimension, grain = NAM)
   ---------------------------------------------------------------------
   TAI SAO CAN BANG NAY

     Fact 1 (footfall) trai tu 2024-08-05 den 2026-08-04, grain NGAY x GIO.
     Fact 2 va Fact 3 co DateKey = 31/12 cua census year, grain NAM.
     Hai tap DateKey nay chi giao nhau DUNG MOT ngay: 20241231.

     Neu de DimDate dieu khien ca 3 fact trong Power BI:
       - chon thang 3/2025  -> moi so lieu ghe / viec lam = BLANK
       - chon ca nam 2024   -> footfall chi co 5 thang (tu 05/08) nhung
                               TotalSeats la snapshot ca nam
                               -> Seat Saturation sai khoang 2,4 lan
       - chon 2025 / 2026   -> footfall du, ghe blank (census dung o 2024)

     Bang nay tach truc thoi gian census ra khoi DimDate:
       DimDate       -> chi dieu khien Fact 1
       DimCensusYear -> dieu khien Fact 2 va Fact 3
     Hai truc doc lap, khong cai nao lam cai kia blank.

   VI TRI TRONG PIPELINE
     Chay SAU 06_load_dimensions.sql, TRUOC 07/08/09.
     Nguon lay tu STAGING (khong lay tu fact) de khi rebuild tu dau
     thi dimension da ton tai truoc khi fact tro FK vao.

   LUU Y
     DELETE chu khong TRUNCATE -- cung ly do voi DimDate/DimTime:
     ton tai FOREIGN KEY la SQL Server chan TRUNCATE (Msg 4712),
     ke ca khi bang fact dang rong.
   ===================================================================== */
USE MelbourneFB_DW;
GO

/* =====================================================================
   1. DDL  (idempotent -- chay lai khong loi)
   ===================================================================== */
IF OBJECT_ID('dw.DimCensusYear') IS NULL
BEGIN
    CREATE TABLE dw.DimCensusYear (
        CensusYear          SMALLINT     NOT NULL,  -- business key = surrogate
        CensusYearLabel     NVARCHAR(10) NOT NULL,  -- '2024'
        CensusDateKey       INT          NOT NULL,  -- 20241231, noi sang DimDate
        IsLatestCensusYear  BIT          NOT NULL DEFAULT 0,
        YearsFromLatest     SMALLINT     NOT NULL,  -- 0 = moi nhat
        IsInFootfallPeriod  BIT          NOT NULL DEFAULT 0,  -- co du lieu footfall?
        CONSTRAINT PK_DimCensusYear PRIMARY KEY CLUSTERED (CensusYear)
    );
    PRINT 'Da tao dw.DimCensusYear.';
END
ELSE
    PRINT 'dw.DimCensusYear da ton tai -- chi nap lai du lieu.';
GO


/* =====================================================================
   2. NAP -- lay tu STAGING, hop cua ca hai file census
      (JobsByBlock va EstabByBlock la nguon cua census spine trong 09)
   ===================================================================== */
DELETE FROM dw.DimCensusYear;
GO

;WITH Yrs AS (
    SELECT DISTINCT TRY_CAST([Census year] AS SMALLINT) AS CensusYear
    FROM MelbourneFB_STG.stg.JobsByBlock
    WHERE TRY_CAST([Census year] AS SMALLINT) IS NOT NULL
    UNION
    SELECT DISTINCT TRY_CAST([Census year] AS SMALLINT)
    FROM MelbourneFB_STG.stg.EstabByBlock
    WHERE TRY_CAST([Census year] AS SMALLINT) IS NOT NULL
),
MaxY AS (SELECT MAX(CensusYear) AS MaxYear FROM Yrs)
INSERT INTO dw.DimCensusYear
    (CensusYear, CensusYearLabel, CensusDateKey,
     IsLatestCensusYear, YearsFromLatest, IsInFootfallPeriod)
SELECT
    y.CensusYear,
    CAST(y.CensusYear AS NVARCHAR(10)),
    y.CensusYear * 10000 + 1231,
    CAST(CASE WHEN y.CensusYear = m.MaxYear THEN 1 ELSE 0 END AS BIT),
    m.MaxYear - y.CensusYear,
    /* Nam co giao voi dai footfall 2024-08-05 .. 2026-08-04.
       Dung de loc slicer, tranh bay so sanh cung-cau lech ky. */
    CAST(CASE WHEN y.CensusYear >= 2024 THEN 1 ELSE 0 END AS BIT)
FROM Yrs y
CROSS JOIN MaxY m;
GO


/* =====================================================================
   4. KIEM TRA
   ===================================================================== */
SELECT COUNT(*) AS SoNamCensus, 23 AS KyVong FROM dw.DimCensusYear;   -- 2002..2024

SELECT CensusYear, CensusYearLabel, CensusDateKey,
       IsLatestCensusYear, YearsFromLatest, IsInFootfallPeriod
FROM dw.DimCensusYear
ORDER BY CensusYear DESC;

-- IsLatestCensusYear o DimCensusYear PHAI khop voi co san trong FactBlockAnnual.
-- Neu lech thi hai noi dang tinh "nam moi nhat" tren hai tap khac nhau.
SELECT
    (SELECT MAX(CensusYear) FROM dw.DimCensusYear WHERE IsLatestCensusYear = 1) AS Dim_LatestYear,
    (SELECT MAX(CensusYear) FROM dw.FactBlockAnnual WHERE IsLatestCensusYear = 1) AS Fact_LatestYear;
-- HAI CON SO PHAI BANG NHAU.

-- Moi CensusDateKey phai ton tai trong DimDate (de noi sang DimDate neu can)
SELECT COUNT(*) AS CensusDateKeyThieuTrongDimDate
FROM dw.DimCensusYear c
LEFT JOIN dw.DimDate d ON d.DateKey = c.CensusDateKey
WHERE d.DateKey IS NULL;                                              -- ky vong 0
GO

PRINT 'DimCensusYear xong. DW gio co 10 bang: 3 fact + 7 dimension.';
GO

