/* =====================================================================
   BUOC 08 -- FACT 3: FactBlockIndustryAnnual   270.380 dong
   ---------------------------------------------------------------------
   GRAIN: 1 block x 1 census year x 1 nganh
   NGUON: stg.JobsByBlock  + stg.EstabByBlock  (ca hai dang PIVOT)
   PHUC VU: BQ4 (drill 20 nganh), BQ5

   CHAY TRUOC FACT 2. Fact 2 lay cac cot TotalJobs / FoodBeverageJobs /
   OfficeTypeJobs / RetailJobs TU BANG NAY, khong doc lai file nguon.
   Nho vay dinh nghia "nganh nao la office" nam DUY NHAT o
   DimIndustry.IsOfficeWorker, va test doi chieu Fact2 = SUM(Fact3)
   dung theo thiet ke.

   BUOC BIEN DOI KHO NHAT CUA PIPELINE
     Nguon: 2 file, moi file 13.519 dong x 20 cot nganh
     Dich:  1 dong = 1 block x 1 nam x 1 nganh
     Ket qua: 13.519 x 20 = 270.380 dong -- fact DAY, khong sparse,
     vi nguon dien so 0 cho nganh khong co mat chu khong de o trong.
   ===================================================================== */
USE MelbourneFB_DW;
GO

IF (SELECT COUNT(*) FROM dw.DimIndustry) <> 21
BEGIN
    RAISERROR('DimIndustry phai co dung 21 dong (20 nganh + Unknown).', 16, 1);
    RETURN;
END
GO

TRUNCATE TABLE dw.FactBlockIndustryAnnual;
GO

;WITH JobsUnpivoted AS (
    SELECT CensusYear, BlockID, IndustryName, JobCount
    FROM (
        SELECT
            TRY_CAST([Census year] AS SMALLINT) AS CensusYear,
            TRY_CAST([Block ID] AS INT)         AS BlockID,
            TRY_CAST([Accommodation] AS INT)                              AS [Accommodation],
            TRY_CAST([Admin and Support Services] AS INT)                 AS [Admin and Support Services],
            TRY_CAST([Agriculture and Mining] AS INT)                     AS [Agriculture and Mining],
            TRY_CAST([Arts and Recreation Services] AS INT)               AS [Arts and Recreation Services],
            TRY_CAST([Business Services] AS INT)                          AS [Business Services],
            TRY_CAST([Construction] AS INT)                               AS [Construction],
            TRY_CAST([Education and Training] AS INT)                     AS [Education and Training],
            TRY_CAST([Electricity, Gas, Water and Waste Services] AS INT) AS [Electricity, Gas, Water and Waste Services],
            TRY_CAST([Finance and Insurance] AS INT)                      AS [Finance and Insurance],
            TRY_CAST([Food and Beverage Services] AS INT)                 AS [Food and Beverage Services],
            TRY_CAST([Health Care and Social Assistance] AS INT)          AS [Health Care and Social Assistance],
            TRY_CAST([Information Media and Telecommunications] AS INT)   AS [Information Media and Telecommunications],
            TRY_CAST([Manufacturing] AS INT)                              AS [Manufacturing],
            TRY_CAST([Other Services] AS INT)                             AS [Other Services],
            TRY_CAST([Public Administration and Safety] AS INT)           AS [Public Administration and Safety],
            TRY_CAST([Real Estate Services] AS INT)                       AS [Real Estate Services],
            TRY_CAST([Rental and Hiring Services] AS INT)                 AS [Rental and Hiring Services],
            TRY_CAST([Retail Trade] AS INT)                               AS [Retail Trade],
            TRY_CAST([Transport, Postal and Storage] AS INT)              AS [Transport, Postal and Storage],
            TRY_CAST([Wholesale Trade] AS INT)                            AS [Wholesale Trade]
        FROM MelbourneFB_STG.stg.JobsByBlock
    ) p
    UNPIVOT (JobCount FOR IndustryName IN (
        [Accommodation], [Admin and Support Services], [Agriculture and Mining],
        [Arts and Recreation Services], [Business Services], [Construction],
        [Education and Training], [Electricity, Gas, Water and Waste Services],
        [Finance and Insurance], [Food and Beverage Services],
        [Health Care and Social Assistance],
        [Information Media and Telecommunications], [Manufacturing],
        [Other Services], [Public Administration and Safety],
        [Real Estate Services], [Rental and Hiring Services], [Retail Trade],
        [Transport, Postal and Storage], [Wholesale Trade])) u
),
EstabUnpivoted AS (
    SELECT CensusYear, BlockID, IndustryName, EstabCount
    FROM (
        SELECT
            TRY_CAST([Census year] AS SMALLINT) AS CensusYear,
            TRY_CAST([Block ID] AS INT)         AS BlockID,
            TRY_CAST([Accommodation] AS INT)                              AS [Accommodation],
            TRY_CAST([Admin and Support Services] AS INT)                 AS [Admin and Support Services],
            TRY_CAST([Agriculture and Mining] AS INT)                     AS [Agriculture and Mining],
            TRY_CAST([Arts and Recreation Services] AS INT)               AS [Arts and Recreation Services],
            TRY_CAST([Business Services] AS INT)                          AS [Business Services],
            TRY_CAST([Construction] AS INT)                               AS [Construction],
            TRY_CAST([Education and Training] AS INT)                     AS [Education and Training],
            TRY_CAST([Electricity, Gas, Water and Waste Services] AS INT) AS [Electricity, Gas, Water and Waste Services],
            TRY_CAST([Finance and Insurance] AS INT)                      AS [Finance and Insurance],
            TRY_CAST([Food and Beverage Services] AS INT)                 AS [Food and Beverage Services],
            TRY_CAST([Health Care and Social Assistance] AS INT)          AS [Health Care and Social Assistance],
            TRY_CAST([Information Media and Telecommunications] AS INT)   AS [Information Media and Telecommunications],
            TRY_CAST([Manufacturing] AS INT)                              AS [Manufacturing],
            TRY_CAST([Other Services] AS INT)                             AS [Other Services],
            TRY_CAST([Public Administration and Safety] AS INT)           AS [Public Administration and Safety],
            TRY_CAST([Real Estate Services] AS INT)                       AS [Real Estate Services],
            TRY_CAST([Rental and Hiring Services] AS INT)                 AS [Rental and Hiring Services],
            TRY_CAST([Retail Trade] AS INT)                               AS [Retail Trade],
            TRY_CAST([Transport, Postal and Storage] AS INT)              AS [Transport, Postal and Storage],
            TRY_CAST([Wholesale Trade] AS INT)                            AS [Wholesale Trade]
        FROM MelbourneFB_STG.stg.EstabByBlock
    ) p
    UNPIVOT (EstabCount FOR IndustryName IN (
        [Accommodation], [Admin and Support Services], [Agriculture and Mining],
        [Arts and Recreation Services], [Business Services], [Construction],
        [Education and Training], [Electricity, Gas, Water and Waste Services],
        [Finance and Insurance], [Food and Beverage Services],
        [Health Care and Social Assistance],
        [Information Media and Telecommunications], [Manufacturing],
        [Other Services], [Public Administration and Safety],
        [Real Estate Services], [Rental and Hiring Services], [Retail Trade],
        [Transport, Postal and Storage], [Wholesale Trade])) u
)
INSERT INTO dw.FactBlockIndustryAnnual
    (DateKey, CensusYear, BlockKey, IndustryKey, JobCount, EstablishmentCount)
SELECT
    ISNULL(j.CensusYear, e.CensusYear) * 10000 + 1231,   -- 31/12 census year
    ISNULL(j.CensusYear, e.CensusYear),
    ISNULL(b.BlockKey,    -1),
    ISNULL(i.IndustryKey, -1),
    j.JobCount,
    e.EstabCount
FROM JobsUnpivoted j
-- FULL OUTER JOIN: giu dong co o file nay ma thieu o file kia
FULL OUTER JOIN EstabUnpivoted e
     ON  e.CensusYear   = j.CensusYear
     AND e.BlockID      = j.BlockID
     AND e.IndustryName = j.IndustryName
LEFT JOIN dw.DimBlock    b ON b.BlockID      = ISNULL(j.BlockID, e.BlockID)
LEFT JOIN dw.DimIndustry i ON i.IndustryName = ISNULL(j.IndustryName, e.IndustryName)
WHERE ISNULL(j.CensusYear, e.CensusYear) IS NOT NULL;
GO


/* =====================================================================
   KIEM TRA
   ===================================================================== */
SELECT COUNT(*) AS FactIndustry_Rows, 270380 AS KyVong
FROM dw.FactBlockIndustryAnnual;

-- Khong dong nao duoc dung Unknown Member o day (khac voi Fact 1)
SELECT SUM(CASE WHEN IndustryKey = -1 THEN 1 ELSE 0 END) AS NganhKhongKhop,
       SUM(CASE WHEN BlockKey    = -1 THEN 1 ELSE 0 END) AS BlockKhongKhop
FROM dw.FactBlockIndustryAnnual;
-- CA HAI PHAI = 0. Neu NganhKhongKhop > 0 thi ten nganh trong
-- DimIndustry khong khop chinh xac voi ten cot trong file nguon.

-- Grain phai duy nhat: khong duoc co (block, nam, nganh) trung
SELECT COUNT(*) AS SoToHopBiTrung
FROM (
    SELECT BlockKey, CensusYear, IndustryKey
    FROM dw.FactBlockIndustryAnnual
    GROUP BY BlockKey, CensusYear, IndustryKey
    HAVING COUNT(*) > 1
) x;                                                    -- ky vong 0

-- Khung census: so dong moi nam / 20 phai ra so block cua nam do
SELECT CensusYear,
       COUNT(*)                        AS SoDong,
       COUNT(*) / 20                   AS SoBlock,
       SUM(JobCount)                   AS TongViecLam
FROM dw.FactBlockIndustryAnnual
GROUP BY CensusYear ORDER BY CensusYear;
-- ky vong: 2002-2006 = 543 block, 2007 = 555, 2017-2018 = 602,
--          cac nam con lai = 603.  Tong 13.519 block-nam.

-- BQ4 chay duoc: co cau nganh cua block dong nhat nam moi nhat
SELECT TOP 10 i.IndustryName, i.IndustryGroup,
       SUM(f.JobCount) AS ViecLam
FROM dw.FactBlockIndustryAnnual f
JOIN dw.DimIndustry i ON i.IndustryKey = f.IndustryKey
WHERE f.CensusYear = (SELECT MAX(CensusYear) FROM dw.FactBlockIndustryAnnual)
GROUP BY i.IndustryName, i.IndustryGroup
ORDER BY SUM(f.JobCount) DESC;
GO

PRINT 'Chay tiep 09_load_fact_blockannual.sql';
GO
