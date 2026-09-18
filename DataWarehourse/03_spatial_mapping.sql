/* =====================================================================
   BUOC 03 -- GAN SENSOR / LICENCE VE BLOCK GAN NHAT
   ---------------------------------------------------------------------
   VAN DE
     Du lieu nguoi di bo co lat/long nhung KHONG co Block ID.
     Du lieu CLUE co Block ID nhung khong co sensor.
     Giay phep ruou co lat/long nhung khong co Block ID.
     => Khong join truc tiep duoc. Phai tinh khoang cach dia ly.

   CACH LAM
     Dung kieu du lieu GEOGRAPHY co san trong SQL Server.
     Ham .STDistance() tra ve khoang cach theo MET tren mat cau,
     chinh xac hon Haversine tu viet va nhanh hon nhieu.
     SRID 4326 = he toa do WGS84 (chuan GPS).

   LUU Y PHUONG PHAP -- PHAI GHI TRONG BAO CAO
     Ta so voi TAM DIEM (centroid) cua block, khong phai RANH GIOI block.
     Mot sensor nam sat mep block A van co the gan tam block B hon.
     Day la sai so chap nhan duoc trong pham vi do an.
     Cach chinh xac hon: dung polygon o cot [Geo Shape] voi .STContains().
     Ta KHONG lam vi: (1) can parse GeoJSON thanh geography, (2) sensor
     nam tren duong -- tuc tren RANH GIOI giua hai block -- nen
     STContains() se tra ve 0 ket qua cho phan lon sensor.
     Muc 5 ben duoi dinh luong sai so nay de dua vao bao cao.

   VENUE KHONG CAN O DAY: file CLUE da co san [Block ID].

   Chay SAU 02_staging_load.sql
   ===================================================================== */

USE MelbourneFB_STG;
GO

/* =====================================================================
   1. CHUAN BI -- bang toa do tam block
      Cot [Geo Point] co dang "lat, long" -> phai tach bang CHARINDEX
   ===================================================================== */
PRINT '--- 1. Toa do tam block ---';

DROP TABLE IF EXISTS #BlockGeo;

SELECT
    TRY_CAST(b.block_id AS INT) AS BlockID,
    b.area_name,
    TRY_CAST(LTRIM(RTRIM(LEFT(b.[Geo Point],
        CHARINDEX(',', b.[Geo Point]) - 1))) AS FLOAT) AS Lat,
    TRY_CAST(LTRIM(RTRIM(SUBSTRING(b.[Geo Point],
        CHARINDEX(',', b.[Geo Point]) + 1, 100))) AS FLOAT) AS Lon
INTO #BlockGeo
FROM stg.Blocks b
WHERE b.[Geo Point] IS NOT NULL
  AND CHARINDEX(',', b.[Geo Point]) > 0
  AND TRY_CAST(b.block_id AS INT) IS NOT NULL;

ALTER TABLE #BlockGeo ADD Pt GEOGRAPHY;

UPDATE #BlockGeo
SET Pt = GEOGRAPHY::Point(Lat, Lon, 4326)
WHERE Lat IS NOT NULL AND Lon IS NOT NULL;

CREATE CLUSTERED INDEX CX_BlockGeo ON #BlockGeo(BlockID);

SELECT COUNT(*) AS SoBlockCoToaDo FROM #BlockGeo WHERE Pt IS NOT NULL;
-- ky vong 603. Neu it hon thi co block bi thieu [Geo Point].
GO


/* =====================================================================
   2. SENSOR -> BLOCK   (134 sensor)
   ===================================================================== */
PRINT '--- 2. Sensor -> block ---';

DELETE FROM stg.NearestBlockMap WHERE EntityType = 'SENSOR';

;WITH SensorGeo AS (
    SELECT
        s.location_id,
        GEOGRAPHY::Point(
            TRY_CAST(s.latitude  AS FLOAT),
            TRY_CAST(s.longitude AS FLOAT), 4326) AS Pt
    FROM stg.SensorLocations s
    WHERE TRY_CAST(s.latitude  AS FLOAT) IS NOT NULL
      AND TRY_CAST(s.longitude AS FLOAT) IS NOT NULL
)
INSERT INTO stg.NearestBlockMap (EntityType, EntityKey, BlockID, DistanceMetres)
SELECT 'SENSOR', sg.location_id, CAST(nb.BlockID AS NVARCHAR(50)),
       CAST(nb.DistM AS DECIMAL(10,2))
FROM SensorGeo sg
CROSS APPLY (
    SELECT TOP 1 bg.BlockID, sg.Pt.STDistance(bg.Pt) AS DistM
    FROM #BlockGeo bg
    WHERE bg.Pt IS NOT NULL
    ORDER BY sg.Pt.STDistance(bg.Pt)
) nb;

SELECT COUNT(*) AS SensorDaGan FROM stg.NearestBlockMap WHERE EntityType='SENSOR';
-- ky vong 134

-- Sensor bi thieu toa do (neu co) -> se roi vao Unknown Member sau nay
SELECT s.location_id, s.sensor_description
FROM stg.SensorLocations s
LEFT JOIN stg.NearestBlockMap m
       ON m.EntityType = 'SENSOR' AND m.EntityKey = s.location_id
WHERE m.EntityKey IS NULL;
GO


/* =====================================================================
   3. LIQUOR LICENCE -> BLOCK   (2.196 giay phep Melbourne City)
      Chi chay neu stg.LiquorLicences da co du lieu.
   ===================================================================== */
PRINT '--- 3. Licence -> block ---';

IF EXISTS (SELECT 1 FROM stg.LiquorLicences)
BEGIN
    DELETE FROM stg.NearestBlockMap WHERE EntityType = 'LICENCE';

    ;WITH LicGeo AS (
        SELECT
            l.[Licence Num],
            GEOGRAPHY::Point(
                TRY_CAST(l.[Latitude]  AS FLOAT),
                TRY_CAST(l.[Longitude] AS FLOAT), 4326) AS Pt
        FROM stg.LiquorLicences l
        WHERE l.[Council] LIKE '%MELBOURNE CITY%'
          AND TRY_CAST(l.[Latitude]  AS FLOAT) IS NOT NULL
          AND TRY_CAST(l.[Longitude] AS FLOAT) IS NOT NULL
    )
    INSERT INTO stg.NearestBlockMap (EntityType, EntityKey, BlockID, DistanceMetres)
    SELECT 'LICENCE', lg.[Licence Num], CAST(nb.BlockID AS NVARCHAR(50)),
           CAST(nb.DistM AS DECIMAL(10,2))
    FROM LicGeo lg
    CROSS APPLY (
        SELECT TOP 1 bg.BlockID, lg.Pt.STDistance(bg.Pt) AS DistM
        FROM #BlockGeo bg
        WHERE bg.Pt IS NOT NULL
        ORDER BY lg.Pt.STDistance(bg.Pt)
    ) nb;

    SELECT COUNT(*) AS LicenceDaGan
    FROM stg.NearestBlockMap WHERE EntityType='LICENCE';   -- ky vong ~2196
END
ELSE
    PRINT 'stg.LiquorLicences con rong -- bo qua muc 3. '
        + 'Load bang SSIS roi chay lai RIENG muc 3 nay.';
GO


/* =====================================================================
   4. DANH DAU BLOCK CO DO PHU FOOTFALL
      Chi block co sensor trong ban kinh 200m moi duoc coi la co du lieu
      cau dang tin cay. Nguong 200m chon vi: mot block CBD Melbourne dai
      khoang 100-200m, nen sensor cach tam <= 200m gan nhu chac chan nam
      tren mot mat cua block do.
   ===================================================================== */
PRINT '--- 4. Do phu footfall theo block ---';

TRUNCATE TABLE stg.BlockFootfallCoverage;

INSERT INTO stg.BlockFootfallCoverage
    (BlockID, KhoangCachSensorGanNhat, SoSensorTrongBlock, CoDoPhuFootfall)
SELECT
    bg.BlockID,
    MIN(m.DistanceMetres),
    COUNT(m.EntityKey),
    CAST(CASE WHEN MIN(m.DistanceMetres) <= 200 THEN 1 ELSE 0 END AS BIT)
FROM #BlockGeo bg
LEFT JOIN stg.NearestBlockMap m
       ON m.EntityType = 'SENSOR'
      AND TRY_CAST(m.BlockID AS INT) = bg.BlockID
GROUP BY bg.BlockID;

SELECT CoDoPhuFootfall, COUNT(*) AS SoBlock
FROM stg.BlockFootfallCoverage GROUP BY CoDoPhuFootfall;
-- ky vong 1: 76 block, 0: 527 block
-- CON SO 76 RAT QUAN TRONG: chi 76/603 block tinh duoc Seat Saturation.
-- Day la gioi han lon nhat cua toan bo do an, phai neu ngay trong slide.
GO


/* =====================================================================
   5. DINH LUONG SAI SO -- phan nay danh cho muc "Han che" trong bao cao
   ===================================================================== */
PRINT '--- 5. Danh gia chat luong mapping ---';

-- 5a. Phan bo khoang cach tu sensor toi tam block gan nhat
SELECT
    COUNT(*)                         AS SoSensor,
    CAST(MIN(DistanceMetres) AS INT) AS GanNhat_m,
    CAST(AVG(DistanceMetres) AS INT) AS TrungBinh_m,
    CAST(MAX(DistanceMetres) AS INT) AS XaNhat_m
FROM stg.NearestBlockMap WHERE EntityType = 'SENSOR';

-- 5b. Phan nhom theo do tin cay -- bang nay dua truc tiep vao slide
SELECT
    CASE WHEN DistanceMetres <= 100 THEN N'1. <=100m   rat tin cay'
         WHEN DistanceMetres <= 200 THEN N'2. 100-200m tin cay'
         WHEN DistanceMetres <= 400 THEN N'3. 200-400m can luu y'
         ELSE                            N'4. >400m    khong dung'
    END AS MucDoTinCay,
    COUNT(*) AS SoSensor
FROM stg.NearestBlockMap
WHERE EntityType = 'SENSOR'
GROUP BY CASE WHEN DistanceMetres <= 100 THEN N'1. <=100m   rat tin cay'
              WHEN DistanceMetres <= 200 THEN N'2. 100-200m tin cay'
              WHEN DistanceMetres <= 400 THEN N'3. 200-400m can luu y'
              ELSE                            N'4. >400m    khong dung' END
ORDER BY 1;

-- 5c. Block nao co nhieu sensor nhat (nhieu sensor = so lieu on dinh hon)
SELECT TOP 10 m.BlockID, b.area_name, COUNT(*) AS SoSensor
FROM stg.NearestBlockMap m
LEFT JOIN stg.Blocks b ON b.block_id = m.BlockID
WHERE m.EntityType = 'SENSOR'
GROUP BY m.BlockID, b.area_name
ORDER BY COUNT(*) DESC;

-- 5d. 76 block co do phu nam o dau -> chung minh tap trung o CBD core
SELECT b.area_name, COUNT(*) AS SoBlock
FROM stg.BlockFootfallCoverage c
JOIN stg.Blocks b ON TRY_CAST(b.block_id AS INT) = c.BlockID
WHERE c.CoDoPhuFootfall = 1
GROUP BY b.area_name
ORDER BY COUNT(*) DESC;

-- 5e. Khoang cach mapping cua giay phep (neu da load)
IF EXISTS (SELECT 1 FROM stg.NearestBlockMap WHERE EntityType = 'LICENCE')
    SELECT COUNT(*)                         AS SoGiayPhep,
           CAST(AVG(DistanceMetres) AS INT) AS TrungBinh_m,
           CAST(MAX(DistanceMetres) AS INT) AS XaNhat_m
    FROM stg.NearestBlockMap WHERE EntityType = 'LICENCE';
GO

DROP TABLE IF EXISTS #BlockGeo;
GO

PRINT 'Staging hoan tat. Chay tiep 04_dw_ddl.sql';
GO
