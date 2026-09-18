/* =====================================================================
   MELBOURNE F&B LOCATION INTELLIGENCE
   BUOC 01 -- STAGING DDL
   ---------------------------------------------------------------------
   NGUYEN TAC THIET KE STAGING

   1. MOI cot deu la NVARCHAR. Khong cast o buoc load.
      Ly do: file nguon co o rong, so co dau phay, ngay nhieu dinh dang.
      Cast som => package fail o dong thu 40.000. Cast o buoc DW.

   2. Bang staging khai DUNG SO COT nhu file nguon, khong hon khong kem,
      va giu NGUYEN ten cot nguon (co dau cach, co ngoac).
      LY DO QUAN TRONG: BULK INSERT map cot THEO VI TRI, khong theo ten.
      Neu bang co thua 2 cot audit o cuoi thi SQL Server bao
      Msg 7801 "Cannot obtain the required interface IID_IColumnsInfo".
      Vi vay o day KHONG co cot LoadBatchID / LoadedAt trong bang nguon.
      Audit duoc ghi o muc batch trong stg.ETL_RunLog.
      Nho quy uoc nay, ta khong can view trung gian va khong can bang raw.

   3. Truncate-and-load moi lan chay. Khong incremental o staging.
      Day la bai hoc tu su co may tu dong tat giua luc load, gay
      double-load bang LiquorLicences len 47.524 dong.

   4. 10 nguon duoc load. File
      business-establishments-with-address-and-industry-classification.csv
      (413.550 dong) KHONG dung: so co so theo block da co san o file
      business-establishments-per-block-by-clue-industry.csv, dung grain
      can thiet. Day la lua chon co y thuc de giam 80 MB va 1 bang.

   LUU Y KY THUAT KHI LOAD
     - File co UTF-8 BOM   -> CODEPAGE = 65001
     - Line ending CRLF    -> ROWTERMINATOR = 0x0d0a
     - Text qualifier "    -> FIELDQUOTE = '"'  (bat buoc: Geo Shape va
                              ten nganh "Electricity, Gas, ..." co phay)
     - Header nam dong 1   -> FIRSTROW = 2  (ke ca file open-meteo:
                              ban export nay KHONG co dong preamble)
   ===================================================================== */

IF DB_ID('MelbourneFB_STG') IS NULL CREATE DATABASE MelbourneFB_STG;
GO
USE MelbourneFB_STG;
GO
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');
GO

/* Don sach de chay lai duoc tu dau ------------------------------------ */
DROP TABLE IF EXISTS stg.PedestrianHourly;
DROP TABLE IF EXISTS stg.SensorLocations;
DROP TABLE IF EXISTS stg.Blocks;
DROP TABLE IF EXISTS stg.Weather;
DROP TABLE IF EXISTS stg.CafeSeats;
DROP TABLE IF EXISTS stg.BarPatrons;
DROP TABLE IF EXISTS stg.JobsByBlock;
DROP TABLE IF EXISTS stg.EstabByBlock;
DROP TABLE IF EXISTS stg.ResidentialDwellings;
DROP TABLE IF EXISTS stg.DevActivity;
DROP TABLE IF EXISTS stg.LiquorLicences;
DROP TABLE IF EXISTS stg.NearestBlockMap;
DROP TABLE IF EXISTS stg.BlockFootfallCoverage;
DROP TABLE IF EXISTS stg.BlockCluster;
DROP TABLE IF EXISTS stg.ETL_RunLog;
-- Bang cua ban cu, khong con dung
DROP TABLE IF EXISTS stg.Establishments;
DROP TABLE IF EXISTS stg.raw_Blocks;
DROP TABLE IF EXISTS stg.raw_DevActivity;
DROP TABLE IF EXISTS stg.ETL_Watermark;
DROP TABLE IF EXISTS stg.ETL_Rejects;
GO


/* =====================================================================
   NGUON 1 -- PEDESTRIAN COUNTS PER HOUR    1.613.524 dong, 121 MB
   9 cot. Bang lon nhat, load cuoi cung.
   ===================================================================== */
CREATE TABLE stg.PedestrianHourly (
    [ID]                  NVARCHAR(50)  NULL,
    [Location_ID]         NVARCHAR(50)  NULL,
    [Sensing_Date]        NVARCHAR(50)  NULL,
    [HourDay]             NVARCHAR(10)  NULL,
    [Direction_1]         NVARCHAR(50)  NULL,
    [Direction_2]         NVARCHAR(50)  NULL,
    [Total_of_Directions] NVARCHAR(50)  NULL,
    [Sensor_Name]         NVARCHAR(200) NULL,
    [Location]            NVARCHAR(100) NULL
);
GO

/* =====================================================================
   NGUON 2 -- SENSOR LOCATIONS              134 dong
   12 cot. File duy nhat dung ten cot chu thuong va KHONG co BOM.
   ===================================================================== */
CREATE TABLE stg.SensorLocations (
    location_id        NVARCHAR(50)   NULL,
    sensor_description NVARCHAR(300)  NULL,
    sensor_name        NVARCHAR(200)  NULL,
    installation_date  NVARCHAR(50)   NULL,
    note               NVARCHAR(1000) NULL,
    location_type      NVARCHAR(50)   NULL,
    status             NVARCHAR(20)   NULL,
    direction_1        NVARCHAR(50)   NULL,
    direction_2        NVARCHAR(50)   NULL,
    latitude           NVARCHAR(50)   NULL,
    longitude          NVARCHAR(50)   NULL,
    [location]         NVARCHAR(100)  NULL
);
GO

/* =====================================================================
   NGUON 3 -- CLUE BLOCKS                   603 dong
   5 cot. [Geo Shape] la GeoJSON polygon dai, co dau phay VA dau ngoac
   kep ben trong -> bat buoc FIELDQUOTE='"'. Ta KHONG dung cot nay
   (chi dung [Geo Point] la tam block), nhung van khai de so cot khop
   file -- nho vay khong can bang raw trung gian.
   ===================================================================== */
CREATE TABLE stg.Blocks (
    [Geo Point] NVARCHAR(100) NULL,   -- dang "lat, long"
    [Geo Shape] NVARCHAR(MAX) NULL,   -- khai de khop cot, khong dung
    block_id    NVARCHAR(50)  NULL,
    region_name NVARCHAR(100) NULL,
    area_name   NVARCHAR(100) NULL
);
GO

/* =====================================================================
   NGUON 4 -- OPEN-METEO HOURLY WEATHER     17.520 dong
   3 cot. Ten cot goc: time / temperature_2m (C) / precipitation (mm)
   Doi ten ngay o staging vi ky tu do C gay loi mapping trong SSIS.
   Doi ten KHONG anh huong BULK INSERT vi map theo vi tri.
   ===================================================================== */
CREATE TABLE stg.Weather (
    [time]          NVARCHAR(50) NULL,   -- 2024-08-05T00:00
    TemperatureC    NVARCHAR(50) NULL,
    PrecipitationMM NVARCHAR(50) NULL
);
GO

/* =====================================================================
   NGUON 5 -- CAFES / RESTAURANTS WITH SEATING   66.356 dong
   15 cot. 1 dong = 1 dia diem x 1 nam x 1 loai cho ngoi.
   [Seating type]: 'Seats - Indoor' 43.420 / 'Seats - Outdoor' 22.936
   ===================================================================== */
CREATE TABLE stg.CafeSeats (
    [Census year]                    NVARCHAR(10)  NULL,
    [Block ID]                       NVARCHAR(50)  NULL,
    [Property ID]                    NVARCHAR(50)  NULL,
    [Base property ID]               NVARCHAR(50)  NULL,
    [Building address]               NVARCHAR(300) NULL,
    [CLUE small area]                NVARCHAR(100) NULL,
    [Trading name]                   NVARCHAR(300) NULL,
    [Business address]               NVARCHAR(300) NULL,
    [Industry (ANZSIC4) code]        NVARCHAR(20)  NULL,
    [Industry (ANZSIC4) description] NVARCHAR(200) NULL,
    [Seating type]                   NVARCHAR(50)  NULL,
    [Number of seats]                NVARCHAR(50)  NULL,
    [Longitude]                      NVARCHAR(50)  NULL,
    [Latitude]                       NVARCHAR(50)  NULL,
    [location]                       NVARCHAR(100) NULL
);
GO

/* =====================================================================
   NGUON 6 -- BARS / PUBS WITH PATRON CAPACITY   5.304 dong
   12 cot. Khac nguon 5: co [Number of patrons], KHONG co seating type.
   CHU Y: pub xuat hien trong CA nguon 5 va nguon 6 -> khi dem so dia
   diem phai khu trung (xu ly o buoc 09).
   ===================================================================== */
CREATE TABLE stg.BarPatrons (
    [Census year]       NVARCHAR(10)  NULL,
    [Block ID]          NVARCHAR(50)  NULL,
    [Property ID]       NVARCHAR(50)  NULL,
    [Base property ID]  NVARCHAR(50)  NULL,
    [Building address]  NVARCHAR(300) NULL,
    [CLUE small area]   NVARCHAR(100) NULL,
    [Trading name]      NVARCHAR(300) NULL,
    [Business address]  NVARCHAR(300) NULL,
    [Number of patrons] NVARCHAR(50)  NULL,
    [Longitude]         NVARCHAR(50)  NULL,
    [Latitude]          NVARCHAR(50)  NULL,
    [location]          NVARCHAR(100) NULL
);
GO

/* =====================================================================
   NGUON 7 -- EMPLOYMENT BY BLOCK BY INDUSTRY    13.519 dong
   24 cot, dang PIVOT: 20 nganh la 20 COT -> UNPIVOT o buoc 08.
   Bang nay dinh nghia KHUNG CENSUS: 1 dong = 1 block x 1 nam.
   Khung KHONG du 603 block moi nam:
     2002-2006: 543   2007: 555   2017-2018: 602   con lai: 603
   Ten cot "Electricity, Gas, Water and Waste Services" va
   "Transport, Postal and Storage" CO DAU PHAY trong file -> file boc
   chung trong dau ngoac kep, FIELDQUOTE se xu ly.
   ===================================================================== */
CREATE TABLE stg.JobsByBlock (
    [Census year]                                NVARCHAR(10)  NULL,
    [Block ID]                                   NVARCHAR(50)  NULL,
    [CLUE small area]                            NVARCHAR(100) NULL,
    [Accommodation]                              NVARCHAR(50)  NULL,
    [Admin and Support Services]                 NVARCHAR(50)  NULL,
    [Agriculture and Mining]                     NVARCHAR(50)  NULL,
    [Arts and Recreation Services]               NVARCHAR(50)  NULL,
    [Business Services]                          NVARCHAR(50)  NULL,
    [Construction]                               NVARCHAR(50)  NULL,
    [Education and Training]                     NVARCHAR(50)  NULL,
    [Electricity, Gas, Water and Waste Services] NVARCHAR(50)  NULL,
    [Finance and Insurance]                      NVARCHAR(50)  NULL,
    [Food and Beverage Services]                 NVARCHAR(50)  NULL,
    [Health Care and Social Assistance]          NVARCHAR(50)  NULL,
    [Information Media and Telecommunications]   NVARCHAR(50)  NULL,
    [Manufacturing]                              NVARCHAR(50)  NULL,
    [Other Services]                             NVARCHAR(50)  NULL,
    [Public Administration and Safety]           NVARCHAR(50)  NULL,
    [Real Estate Services]                       NVARCHAR(50)  NULL,
    [Rental and Hiring Services]                 NVARCHAR(50)  NULL,
    [Retail Trade]                               NVARCHAR(50)  NULL,
    [Transport, Postal and Storage]              NVARCHAR(50)  NULL,
    [Wholesale Trade]                            NVARCHAR(50)  NULL,
    [Total jobs in block]                        NVARCHAR(50)  NULL
);
GO

/* =====================================================================
   NGUON 8 -- ESTABLISHMENTS PER BLOCK BY INDUSTRY   13.519 dong
   24 cot, cau truc y het nguon 7, chi khac cot tong cuoi.
   ===================================================================== */
CREATE TABLE stg.EstabByBlock (
    [Census year]                                NVARCHAR(10)  NULL,
    [Block ID]                                   NVARCHAR(50)  NULL,
    [CLUE small area]                            NVARCHAR(100) NULL,
    [Accommodation]                              NVARCHAR(50)  NULL,
    [Admin and Support Services]                 NVARCHAR(50)  NULL,
    [Agriculture and Mining]                     NVARCHAR(50)  NULL,
    [Arts and Recreation Services]               NVARCHAR(50)  NULL,
    [Business Services]                          NVARCHAR(50)  NULL,
    [Construction]                               NVARCHAR(50)  NULL,
    [Education and Training]                     NVARCHAR(50)  NULL,
    [Electricity, Gas, Water and Waste Services] NVARCHAR(50)  NULL,
    [Finance and Insurance]                      NVARCHAR(50)  NULL,
    [Food and Beverage Services]                 NVARCHAR(50)  NULL,
    [Health Care and Social Assistance]          NVARCHAR(50)  NULL,
    [Information Media and Telecommunications]   NVARCHAR(50)  NULL,
    [Manufacturing]                              NVARCHAR(50)  NULL,
    [Other Services]                             NVARCHAR(50)  NULL,
    [Public Administration and Safety]           NVARCHAR(50)  NULL,
    [Real Estate Services]                       NVARCHAR(50)  NULL,
    [Rental and Hiring Services]                 NVARCHAR(50)  NULL,
    [Retail Trade]                               NVARCHAR(50)  NULL,
    [Transport, Postal and Storage]              NVARCHAR(50)  NULL,
    [Wholesale Trade]                            NVARCHAR(50)  NULL,
    [Total establishments in block]              NVARCHAR(50)  NULL
);
GO

/* =====================================================================
   NGUON 9 -- RESIDENTIAL DWELLINGS         ~219.680 dong, 32 MB
   11 cot. DAN SO BAN DEM theo block -- bo sung cho nguon 7 (vốn chi la
   dan so ban ngay). Phuc vu BQ4.
   GRAIN: 1 toa nha x 1 nam x 1 loai nha o -- KHONG phai 1 block.
   [Dwelling number] la SO CAN trong toa nha do.
   3 loai: House/Townhouse 183.288 | Residential Apartments 35.330 |
           Student Apartments 1.062
   ===================================================================== */
CREATE TABLE stg.ResidentialDwellings (
    [Census year]      NVARCHAR(10)  NULL,
    [Block ID]         NVARCHAR(50)  NULL,
    [Property ID]      NVARCHAR(50)  NULL,
    [Base property ID] NVARCHAR(50)  NULL,
    [Building address] NVARCHAR(300) NULL,
    [CLUE small area]  NVARCHAR(100) NULL,
    [Dwelling type]    NVARCHAR(100) NULL,
    [Dwelling number]  NVARCHAR(50)  NULL,
    [Longitude]        NVARCHAR(50)  NULL,
    [Latitude]         NVARCHAR(50)  NULL,
    [location]         NVARCHAR(100) NULL
);
GO

/* =====================================================================
   NGUON 10 -- DEVELOPMENT ACTIVITY MONITOR   1.438 dong
   42 cot. Khai DU 42 cot de khong can bang raw; buoc 09 chi lay 8 cot.
   LUU Y: [year_completed] RONG hoan toan voi 317 du an chua xong ->
   KHONG the phan tich pipeline theo nam, chi tong theo block.
   Cot publicdispaly_flr la loi chinh ta CUA NGUON, giu nguyen.
   ===================================================================== */
CREATE TABLE stg.DevActivity (
    data_format                 NVARCHAR(50)  NULL,
    development_key             NVARCHAR(50)  NULL,
    status                      NVARCHAR(50)  NULL,
    year_completed              NVARCHAR(10)  NULL,
    clue_small_area             NVARCHAR(100) NULL,
    clue_block                  NVARCHAR(50)  NULL,
    street_address              NVARCHAR(300) NULL,
    property_id                 NVARCHAR(50)  NULL,
    property_id_2               NVARCHAR(50)  NULL,
    property_id_3               NVARCHAR(50)  NULL,
    property_id_4               NVARCHAR(50)  NULL,
    property_id_5               NVARCHAR(50)  NULL,
    floors_above                NVARCHAR(20)  NULL,
    resi_dwellings              NVARCHAR(20)  NULL,
    studio_dwe                  NVARCHAR(20)  NULL,
    one_bdrm_dwe                NVARCHAR(20)  NULL,
    two_bdrm_dwe                NVARCHAR(20)  NULL,
    three_bdrm_dwe              NVARCHAR(20)  NULL,
    student_apartments          NVARCHAR(20)  NULL,
    student_beds                NVARCHAR(20)  NULL,
    student_accommodation_units NVARCHAR(20)  NULL,
    institutional_accom_beds    NVARCHAR(20)  NULL,
    hotel_rooms                 NVARCHAR(20)  NULL,
    serviced_apartments         NVARCHAR(20)  NULL,
    hotels_serviced_apartments  NVARCHAR(20)  NULL,
    hostel_beds                 NVARCHAR(20)  NULL,
    childcare_places            NVARCHAR(20)  NULL,
    office_flr                  NVARCHAR(20)  NULL,
    retail_flr                  NVARCHAR(20)  NULL,
    industrial_flr              NVARCHAR(20)  NULL,
    storage_flr                 NVARCHAR(20)  NULL,
    education_flr               NVARCHAR(20)  NULL,
    hospital_flr                NVARCHAR(20)  NULL,
    recreation_flr              NVARCHAR(20)  NULL,
    publicdispaly_flr           NVARCHAR(20)  NULL,   -- typo cua nguon
    community_flr               NVARCHAR(20)  NULL,
    car_spaces                  NVARCHAR(20)  NULL,
    bike_spaces                 NVARCHAR(20)  NULL,
    town_planning_application   NVARCHAR(200) NULL,
    longitude                   NVARCHAR(50)  NULL,
    latitude                    NVARCHAR(50)  NULL,
    geopoint                    NVARCHAR(100) NULL
);
GO

/* =====================================================================
   NGUON 11 -- VICTORIAN LIQUOR LICENCES    23.762 dong toan VIC
                                             2.196 dong Melbourne City
   File .xlsx -> BULK INSERT KHONG doc duoc. Load bang SSIS Excel Source
   hoac Import Flat File sau khi Save As CSV.
   Header nam o DONG 5 (4 dong dau la logo/tieu de).
   SSIS Excel Source: Sheet = 'Current_Victorian_Licences_By_L$A5:W'
   [Trading Hours] CHI la nhan chu ve gio DONG cua, vi du 'Trading to 3am'
   ===================================================================== */
CREATE TABLE stg.LiquorLicences (
    [Licence Num]      NVARCHAR(50)  NULL,
    [Licensee]         NVARCHAR(300) NULL,
    [Trading As]       NVARCHAR(300) NULL,
    [Category]         NVARCHAR(100) NULL,
    [Trading Hours]    NVARCHAR(100) NULL,
    [After 11 pm]      NVARCHAR(20)  NULL,
    [Maximum Capacity] NVARCHAR(20)  NULL,   -- rong o 439/2196 dong
    [Address]          NVARCHAR(300) NULL,
    [Suburb]           NVARCHAR(100) NULL,
    [Postcode]         NVARCHAR(20)  NULL,
    [Latitude]         NVARCHAR(50)  NULL,
    [Longitude]        NVARCHAR(50)  NULL,
    [Council]          NVARCHAR(150) NULL,
    [Region]           NVARCHAR(100) NULL,
    [Metro/Regional]   NVARCHAR(50)  NULL
);
GO


/* =====================================================================
   BANG PHU TRO
   ===================================================================== */

/* Ket qua tinh khoang cach dia ly (buoc 03).
   Moi entity -> 1 block gan nhat + khoang cach theo met. */
CREATE TABLE stg.NearestBlockMap (
    EntityType     NVARCHAR(20)  NOT NULL,   -- 'SENSOR' | 'LICENCE'
    EntityKey      NVARCHAR(100) NOT NULL,   -- location_id | Licence Num
    BlockID        NVARCHAR(50)  NULL,
    DistanceMetres DECIMAL(10,2) NULL,
    CalculatedAt   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_NearestBlockMap PRIMARY KEY (EntityType, EntityKey)
);
GO

/* Block nao co du lieu footfall dang tin cay (buoc 03).
   Chi block co sensor trong ban kinh 200m moi tinh duoc Seat Saturation. */
CREATE TABLE stg.BlockFootfallCoverage (
    BlockID                  INT           NOT NULL PRIMARY KEY,
    KhoangCachSensorGanNhat  DECIMAL(10,2) NULL,
    SoSensorTrongBlock       INT           NULL,
    CoDoPhuFootfall          BIT           NOT NULL DEFAULT 0
);
GO

/* Ket qua k-Means (chay bang Python/sklearn ngoai pipeline SQL).
   Bang nay co the RONG -- buoc 06 se bo qua va de ClusterName NULL. */
CREATE TABLE stg.BlockCluster (
    BlockID         NVARCHAR(50)  NOT NULL PRIMARY KEY,
    ClusterID       INT           NULL,
    ClusterName     NVARCHAR(100) NULL,
    SilhouetteScore DECIMAL(6,4)  NULL,
    LoadedAt        DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);
GO

/* Log moi lan chay ETL. Bat buoc co de tra loi cau hoi cua hoi dong
   ve error handling va auditing. Ghi o muc BATCH, khong o muc dong --
   day la ly do bang nguon khong co cot LoadBatchID. */
CREATE TABLE stg.ETL_RunLog (
    RunLogID     INT IDENTITY(1,1) PRIMARY KEY,
    LoadBatchID  BIGINT        NOT NULL,   -- BIGINT, khong INT: yyMMddHHmm cho ra so 10 chu so
    StepName     NVARCHAR(200) NOT NULL,   -- '02_staging_load' ...
    TableName    NVARCHAR(200) NULL,
    RowsInserted BIGINT        NULL,
    RowsExpected BIGINT        NULL,
    StartedAt    DATETIME2(0)  NULL,
    FinishedAt   DATETIME2(0)  NULL,
    Status       NVARCHAR(20)  NULL,       -- SUCCESS | MISMATCH | FAILED
    Notes        NVARCHAR(MAX) NULL
);
GO


/* =====================================================================
   KIEM TRA
   ===================================================================== */
SELECT TABLE_NAME,
       (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS c
        WHERE c.TABLE_NAME = t.TABLE_NAME AND c.TABLE_SCHEMA = 'stg') AS SoCot
FROM INFORMATION_SCHEMA.TABLES t
WHERE TABLE_SCHEMA = 'stg' ORDER BY TABLE_NAME;

/* So cot PHAI khop file nguon:
     PedestrianHourly      9      SensorLocations      12
     Blocks                5      Weather               3
     CafeSeats            15      BarPatrons           12
     JobsByBlock          24      EstabByBlock         24
     ResidentialDwellings 11      DevActivity          42
     LiquorLicences       15 (load bang SSIS, khong BULK INSERT)
   Neu lech mot cot thi buoc 02 se bao Msg 7801. */

PRINT 'Staging DDL hoan tat: 11 bang nguon + 4 bang phu tro.';
PRINT 'Chay tiep 02_staging_load.sql';
GO