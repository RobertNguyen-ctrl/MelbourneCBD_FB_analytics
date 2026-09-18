/* =====================================================================
   MELBOURNE F&B LOCATION INTELLIGENCE  --  DATA WAREHOUSE
   ---------------------------------------------------------------------
   Luoc do: 3 FACT + 6 DIMENSION = 9 bang  (rubric yeu cau toi thieu 5)

   BA GRAIN -> BA FACT
     Fact 1  FactFootfallHourly        sensor x ngay x gio    1.613.524
     Fact 2  FactBlockAnnual           block  x census year      13.519
     Fact 3  FactBlockIndustryAnnual   block  x nam x nganh     270.380

   TAI SAO KHONG PHAI 1 FACT
     Fact 1 o grain GIO, Fact 2 o grain NAM. Nhet chung se nhan ban
     du lieu nam len 1,6 trieu lan -> moi phep SUM sai. Hai grain khac
     nhau BAT BUOC hai bang.

   TAI SAO KHONG PHAI 6 FACT (mot fact cho moi file nguon)
     6 nguon CLUE (ghe cafe, patron bar, viec lam, so co so, nha o,
     giay phep + pipeline) deu o CUNG grain block x census year --
     kiem chung: employment-by-block dung 603 dong/nam. Kimball goi
     viec gop nay la CONSOLIDATED FACT TABLE, khong phai di tat.
     Thoi tiet o grain ngay x gio, THO HON Fact 1, nen gan truc tiep
     vao Fact 1 (moi dong footfall co dung 1 ban ghi thoi tiet) thay vi
     lam fact rieng -- tranh quan he many-to-many trong Power BI.

   CONFORMED DIMENSION (dung chung): DimDate, DimBlock
     DimBlock la truc cho phep so sanh CUNG (Fact 2) voi CAU (Fact 1)
     tren cung mot block -- dieu ma BQ1, BQ3, BQ7 bat buoc phai co.
     Neu 3 fact khong chia se dimension nao thi thanh stovepipe mart:
     khong the dat measure cua hai fact canh nhau trong mot visual.
   PRIVATE DIMENSION (rieng tung fact):
     DimTime, DimSensor, DimWeather -> Fact 1
     DimIndustry                    -> Fact 3
     Day la thiet ke DUNG: sensor khong co nghia voi du lieu census nam,
     nganh khong co nghia voi du lieu nguoi di bo theo gio.

   NGUYEN TAC THIET KE
     1. Surrogate key INT IDENTITY cho moi dimension, khong dung
        business key lam khoa chinh -- de xu ly SCD2 va orphan key.
     2. Unknown Member key = -1 o moi dimension. Ly do that: 3 sensor
        (28, 65, 78) co trong file counts nhung KHONG co trong file
        sensor locations. Tro chung ve -1 thay vi xoa dong hoac lam
        fail package.
     3. Fact khong chua cot text mo ta. Moi thuoc tinh o dimension.
     4. Fact theo nam tro vao DateKey = nam*10000 + 1231 (31/12).
     5. DimTime dung 4 cot BIT cho 4 cua so gio, KHONG dung 1 cot
        nhan chu -- vi 4 cua so cua BQ2 CHONG LAP nhau.

   CHAY SAU 03_spatial_mapping.sql. File nay DROP toan bo schema dw.
   ===================================================================== */

IF DB_ID('MelbourneFB_DW') IS NULL CREATE DATABASE MelbourneFB_DW;
GO
USE MelbourneFB_DW;
GO
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw');
GO

/* =====================================================================
   PHAN 0 -- DROP SACH SCHEMA dw
   Thu tu: FACT truoc, DIMENSION sau (nguoc lai se vuong FK).
   Liet ke ca cac ten bang cua thiet ke cu de file nay chay lai duoc
   tren mot database da co san bang -- khong loi neu bang khong ton tai.
   ===================================================================== */
-- 3 fact cua thiet ke nay
DROP TABLE IF EXISTS dw.FactFootfallHourly;
DROP TABLE IF EXISTS dw.FactBlockAnnual;
DROP TABLE IF EXISTS dw.FactBlockIndustryAnnual;
-- Fact cua thiet ke cu (bo)
DROP TABLE IF EXISTS dw.FactPedestrianHourly;
DROP TABLE IF EXISTS dw.FactWeatherHourly;
DROP TABLE IF EXISTS dw.FactVenueCapacity;
DROP TABLE IF EXISTS dw.FactBlockIndustryYear;
DROP TABLE IF EXISTS dw.FactBlockPipeline;
DROP TABLE IF EXISTS dw.FactLiquorLicence;
DROP TABLE IF EXISTS dw.FactBlockDwellings;
DROP TABLE IF EXISTS dw.FactBlockDemandSupply;
GO
-- 6 dimension cua thiet ke nay
DROP TABLE IF EXISTS dw.DimWeather;
DROP TABLE IF EXISTS dw.DimIndustry;
DROP TABLE IF EXISTS dw.DimSensor;
DROP TABLE IF EXISTS dw.DimBlock;
DROP TABLE IF EXISTS dw.DimTime;
DROP TABLE IF EXISTS dw.DimDate;
-- Dimension cua thiet ke cu (bo)
DROP TABLE IF EXISTS dw.DimVenue;
DROP TABLE IF EXISTS dw.DimLicenceCategory;
DROP TABLE IF EXISTS dw.DimDwellingType;
GO
PRINT 'Da drop toan bo schema dw.';
GO


/* =====================================================================
   PHAN 1 -- DIMENSION
   ===================================================================== */

/* ---------------------------------------------------------------------
   1.1  DimDate   -- 9.131 dong  (2002-01-01 .. 2026-12-31)
        Phu ca CLUE (2002-2024) va pedestrian (08/2024-08/2026).
        CONFORMED: dung cho ca 3 fact.
   --------------------------------------------------------------------- */
CREATE TABLE dw.DimDate (
    DateKey             INT           NOT NULL,   -- yyyymmdd (smart key)
    FullDate            DATE          NOT NULL,
    CalendarYear        SMALLINT      NOT NULL,
    CalendarQuarter     TINYINT       NOT NULL,
    QuarterName         NVARCHAR(10)  NOT NULL,
    CalendarMonth       TINYINT       NOT NULL,
    MonthName           NVARCHAR(20)  NOT NULL,
    MonthYearLabel      NVARCHAR(20)  NOT NULL,
    DayOfMonth          TINYINT       NOT NULL,
    DayOfWeekNumber     TINYINT       NOT NULL,   -- 1 = Monday
    DayName             NVARCHAR(20)  NOT NULL,
    IsWeekend           BIT           NOT NULL,
    ISOWeek             TINYINT       NOT NULL,
    DayOfYear           SMALLINT      NOT NULL,
    SeasonName          NVARCHAR(10)  NOT NULL,   -- Nam ban cau
    IsPublicHolidayVIC  BIT           NOT NULL DEFAULT 0,
    HolidayName         NVARCHAR(60)  NULL,
    IsCurrentYear       BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_DimDate PRIMARY KEY CLUSTERED (DateKey)
);
CREATE UNIQUE INDEX UX_DimDate_FullDate ON dw.DimDate(FullDate);
GO

/* ---------------------------------------------------------------------
   1.2  DimTime   -- 24 dong
        BQ2 co 4 cua so gio CHONG LAP nhau (gio 10-13 thuoc ca
        Cafe 06-14 va Lunch 10-15). Mot cot CASE WHEN chi gan duoc
        gio do vao nhanh DAU TIEN khop -> mat du lieu.
        => Dung 4 cot BIT doc lap. Day la sua loi so v1.
   --------------------------------------------------------------------- */
CREATE TABLE dw.DimTime (
    TimeKey             TINYINT       NOT NULL,   -- 0..23
    HourLabel           NVARCHAR(10)  NOT NULL,   -- '13:00'
    HourLabel12h        NVARCHAR(10)  NOT NULL,   -- '1 PM'
    Daypart             NVARCHAR(20)  NOT NULL,   -- KHONG chong lap
    DaypartSortOrder    TINYINT       NOT NULL,
    InCafeWindow        BIT           NOT NULL,   -- 06:00-14:00
    InLunchWindow       BIT           NOT NULL,   -- 10:00-15:00
    InAllDayWindow      BIT           NOT NULL,   -- 07:00-19:00
    InNightWindow       BIT           NOT NULL,   -- 16:00-24:00
    IsAfter22h          BIT           NOT NULL,   -- BQ3 kinh te dem
    IsBusinessHour      BIT           NOT NULL,   -- 09:00-18:00
    CONSTRAINT PK_DimTime PRIMARY KEY CLUSTERED (TimeKey)
);
GO

/* ---------------------------------------------------------------------
   1.3  DimBlock   -- 603 + 1 Unknown
        CONFORMED DIMENSION TRUNG TAM. Ca 3 fact noi vao day.
        Day la bang cho phep so sanh CUNG (Fact 2) voi CAU (Fact 1)
        tren cung mot block -- dieu ma BQ1, BQ3, BQ7 bat buoc phai co.
   --------------------------------------------------------------------- */
CREATE TABLE dw.DimBlock (
    BlockKey              INT IDENTITY(1,1) NOT NULL,
    BlockID               INT           NOT NULL,   -- business key
    CLUESmallArea         NVARCHAR(100) NULL,
    RegionName            NVARCHAR(100) NULL,
    AreaName              NVARCHAR(100) NULL,
    CentroidLatitude      DECIMAL(10,7) NULL,
    CentroidLongitude     DECIMAL(10,7) NULL,
    NearestSensorID       INT           NULL,
    DistanceToSensorM     DECIMAL(10,2) NULL,
    HasFootfallCoverage   BIT           NOT NULL DEFAULT 0,  -- sensor <=200m
    ClusterID             INT           NULL,       -- k-Means (Python)
    ClusterName           NVARCHAR(100) NULL,       -- BQ5 archetype
    DaytimePopulationBand NVARCHAR(20)  NULL,
    CONSTRAINT PK_DimBlock PRIMARY KEY (BlockKey)
);
CREATE UNIQUE INDEX UX_DimBlock_BlockID ON dw.DimBlock(BlockID);
GO
SET IDENTITY_INSERT dw.DimBlock ON;
INSERT INTO dw.DimBlock (BlockKey, BlockID, CLUESmallArea, HasFootfallCoverage)
VALUES (-1, -1, N'Unknown', 0);
SET IDENTITY_INSERT dw.DimBlock OFF;
GO

/* ---------------------------------------------------------------------
   1.4  DimSensor   -- 134 + 1 Unknown, SCD Type 2
        PRIVATE cho Fact 1. Du lieu census khong co khai niem sensor.
        SCD2 vi sensor co the doi status (Active/Inactive/Removed) va
        doi vi tri mo ta -- can giu lich su de khong lam sai so lieu cu.
   --------------------------------------------------------------------- */
CREATE TABLE dw.DimSensor (
    SensorKey           INT IDENTITY(1,1) NOT NULL,
    LocationID          INT           NOT NULL,   -- business key
    SensorName          NVARCHAR(200) NULL,
    SensorDescription   NVARCHAR(300) NULL,
    LocationType        NVARCHAR(50)  NULL,       -- Outdoor 100 / Indoor 34
    SensorStatus        NVARCHAR(20)  NULL,
    Direction1Name      NVARCHAR(50)  NULL,
    Direction2Name      NVARCHAR(50)  NULL,
    Latitude            DECIMAL(10,7) NULL,
    Longitude           DECIMAL(10,7) NULL,
    BlockID             INT           NULL,       -- tu NearestBlockMap
    DistanceToBlockM    DECIMAL(10,2) NULL,
    InstallationDate    DATE          NULL,
    HasDirectionalData  BIT           NOT NULL DEFAULT 0,
    IsInStablePanel     BIT           NOT NULL DEFAULT 0,  -- >=95% do phu gio
    RowHash             VARBINARY(32) NULL,       -- MD5 de so sanh SCD2
    ValidFrom           DATE          NOT NULL DEFAULT '1900-01-01',
    ValidTo             DATE          NOT NULL DEFAULT '9999-12-31',
    IsCurrent           BIT           NOT NULL DEFAULT 1,
    CONSTRAINT PK_DimSensor PRIMARY KEY (SensorKey)
);
CREATE INDEX IX_DimSensor_Lookup ON dw.DimSensor(LocationID, IsCurrent);
GO
SET IDENTITY_INSERT dw.DimSensor ON;
INSERT INTO dw.DimSensor (SensorKey, LocationID, SensorDescription, IsCurrent)
VALUES (-1, -1, N'Unknown sensor (orphan key trong file counts)', 1);
SET IDENTITY_INSERT dw.DimSensor OFF;
GO

/* ---------------------------------------------------------------------
   1.5  DimWeather   -- 12 + 1 Unknown  (JUNK DIMENSION)
        PRIVATE cho Fact 1.
        Ly do khong lam fact weather rieng: weather o
        grain ngay x gio, THO HON grain cua Fact 1, nen moi dong
        footfall anh xa vao DUNG 1 to hop thoi tiet -> khong the fan-out.
        4 dai nhiet do x 3 dai mua = 12 to hop.
   --------------------------------------------------------------------- */
CREATE TABLE dw.DimWeather (
    WeatherKey            INT IDENTITY(1,1) NOT NULL,
    TemperatureBand       NVARCHAR(20)  NOT NULL,  -- Cold/Mild/Warm/Hot
    TemperatureBandSort   TINYINT       NOT NULL,
    PrecipitationBand     NVARCHAR(20)  NOT NULL,  -- None/Light/Heavy
    PrecipitationBandSort TINYINT       NOT NULL,
    IsRaining             BIT           NOT NULL,  -- precipitation > 0.1mm
    IsGoodForOutdoor      BIT           NOT NULL,  -- BQ7: khong mua + Mild/Warm
    WeatherLabel          NVARCHAR(50)  NOT NULL,  -- 'Warm, no rain'
    CONSTRAINT PK_DimWeather PRIMARY KEY (WeatherKey)
);
CREATE UNIQUE INDEX UX_DimWeather_Bands
    ON dw.DimWeather(TemperatureBand, PrecipitationBand);
GO
SET IDENTITY_INSERT dw.DimWeather ON;
INSERT INTO dw.DimWeather
    (WeatherKey, TemperatureBand, TemperatureBandSort, PrecipitationBand,
     PrecipitationBandSort, IsRaining, IsGoodForOutdoor, WeatherLabel)
VALUES (-1, N'Unknown', 9, N'Unknown', 9, 0, 0, N'Unknown');
SET IDENTITY_INSERT dw.DimWeather OFF;
GO

/* ---------------------------------------------------------------------
   1.6  DimIndustry   -- 20 + 1 Unknown
        PRIVATE cho Fact 3.
        CAC CO BIT LA DINH NGHIA DUY NHAT. Fact 2 tinh cot
        OfficeTypeJobs / FoodBeverageJobs / RetailJobs BANG CACH doc
        co o day, KHONG hard-code ten nganh lan thu hai. Neu hard-code
        2 noi, som muon 2 con so se lech va khong biet ben nao dung.
   --------------------------------------------------------------------- */
CREATE TABLE dw.DimIndustry (
    IndustryKey       INT IDENTITY(1,1) NOT NULL,
    IndustryName      NVARCHAR(100) NOT NULL,
    IndustryGroup     NVARCHAR(50)  NULL,
    IsFoodBeverage    BIT           NOT NULL DEFAULT 0,
    IsOfficeWorker    BIT           NOT NULL DEFAULT 0,  -- driver cau an trua
    IsRetail          BIT           NOT NULL DEFAULT 0,
    SortOrder         TINYINT       NULL,
    CONSTRAINT PK_DimIndustry PRIMARY KEY (IndustryKey)
);
CREATE UNIQUE INDEX UX_DimIndustry_Name ON dw.DimIndustry(IndustryName);
GO
SET IDENTITY_INSERT dw.DimIndustry ON;
INSERT INTO dw.DimIndustry (IndustryKey, IndustryName) VALUES (-1, N'Unknown');
SET IDENTITY_INSERT dw.DimIndustry OFF;
GO
INSERT INTO dw.DimIndustry
    (IndustryName, IndustryGroup, IsFoodBeverage, IsOfficeWorker, IsRetail, SortOrder)
VALUES
 (N'Accommodation',                              N'Retail & Hospitality', 0,0,0, 1),
 (N'Admin and Support Services',                 N'Office',               0,1,0, 2),
 (N'Agriculture and Mining',                     N'Industrial',           0,0,0, 3),
 (N'Arts and Recreation Services',               N'Retail & Hospitality', 0,0,0, 4),
 (N'Business Services',                          N'Office',               0,1,0, 5),
 (N'Construction',                               N'Industrial',           0,0,0, 6),
 (N'Education and Training',                     N'Public & Community',   0,0,0, 7),
 (N'Electricity, Gas, Water and Waste Services', N'Industrial',           0,0,0, 8),
 (N'Finance and Insurance',                      N'Office',               0,1,0, 9),
 (N'Food and Beverage Services',                 N'Retail & Hospitality', 1,0,0,10),
 (N'Health Care and Social Assistance',          N'Public & Community',   0,0,0,11),
 (N'Information Media and Telecommunications',   N'Office',               0,1,0,12),
 (N'Manufacturing',                              N'Industrial',           0,0,0,13),
 (N'Other Services',                             N'Retail & Hospitality', 0,0,0,14),
 (N'Public Administration and Safety',           N'Public & Community',   0,1,0,15),
 (N'Real Estate Services',                       N'Office',               0,1,0,16),
 (N'Rental and Hiring Services',                 N'Office',               0,0,0,17),
 (N'Retail Trade',                               N'Retail & Hospitality', 0,0,1,18),
 (N'Transport, Postal and Storage',              N'Industrial',           0,0,0,19),
 (N'Wholesale Trade',                            N'Industrial',           0,0,0,20);
GO


/* =====================================================================
   PHAN 2 -- FACT
   ===================================================================== */

/* ---------------------------------------------------------------------
   2.1  FACT 1 -- FactFootfallHourly   1.613.524 dong
        GRAIN: 1 sensor x 1 ngay x 1 gio
        Phuc vu BQ1 (phia cau), BQ2, BQ3, BQ7

        TemperatureC / PrecipitationMM la measure KHONG CONG DUOC.
        Chi dung AVG / MIN / MAX. Trong Power BI phai an SUM cua 2 cot
        nay di (Summarize by = Do not summarize) neu khong nguoi dung
        se cong nhiet do lai voi nhau.
   --------------------------------------------------------------------- */
CREATE TABLE dw.FactFootfallHourly (
    FootfallFactID      BIGINT IDENTITY(1,1) NOT NULL,
    DateKey             INT           NOT NULL,
    TimeKey             TINYINT       NOT NULL,
    SensorKey           INT           NOT NULL,
    BlockKey            INT           NOT NULL,
    WeatherKey          INT           NOT NULL,
    SourceRecordID      BIGINT        NULL,      -- degenerate, de truy vet
    Direction1Count     INT           NULL,
    Direction2Count     INT           NULL,
    TotalPedestrians    INT           NOT NULL,  -- additive
    TemperatureC        DECIMAL(5,2)  NULL,      -- KHONG additive
    PrecipitationMM     DECIMAL(6,2)  NULL,      -- KHONG additive
    LoadBatchID         INT           NULL,
    CONSTRAINT PK_FactFootfallHourly PRIMARY KEY NONCLUSTERED (FootfallFactID),
    CONSTRAINT FK_FFH_Date    FOREIGN KEY (DateKey)    REFERENCES dw.DimDate(DateKey),
    CONSTRAINT FK_FFH_Time    FOREIGN KEY (TimeKey)    REFERENCES dw.DimTime(TimeKey),
    CONSTRAINT FK_FFH_Sensor  FOREIGN KEY (SensorKey)  REFERENCES dw.DimSensor(SensorKey),
    CONSTRAINT FK_FFH_Block   FOREIGN KEY (BlockKey)   REFERENCES dw.DimBlock(BlockKey),
    CONSTRAINT FK_FFH_Weather FOREIGN KEY (WeatherKey) REFERENCES dw.DimWeather(WeatherKey)
);
CREATE CLUSTERED INDEX CX_FFH_Date_Sensor
    ON dw.FactFootfallHourly(DateKey, SensorKey, TimeKey);
CREATE NONCLUSTERED INDEX IX_FFH_Block
    ON dw.FactFootfallHourly(BlockKey) INCLUDE (TotalPedestrians);
CREATE NONCLUSTERED INDEX IX_FFH_Time
    ON dw.FactFootfallHourly(TimeKey) INCLUDE (BlockKey, TotalPedestrians);
GO

/* ---------------------------------------------------------------------
   2.2  FACT 3 -- FactBlockIndustryAnnual   270.380 dong
        GRAIN: 1 block x 1 census year x 1 nganh
        Phuc vu BQ4 (drill), BQ5
        Tao TRUOC Fact 2 vi Fact 2 lay so tong hop tu bang nay.
   --------------------------------------------------------------------- */
CREATE TABLE dw.FactBlockIndustryAnnual (
    BlockIndustryID     BIGINT IDENTITY(1,1) NOT NULL,
    DateKey             INT       NOT NULL,   -- 31/12 census year
    CensusYear          SMALLINT  NOT NULL,   -- degenerate, loc nhanh
    BlockKey            INT       NOT NULL,
    IndustryKey         INT       NOT NULL,
    JobCount            INT       NULL,
    EstablishmentCount  INT       NULL,
    LoadBatchID         INT       NULL,
    CONSTRAINT PK_FactBlockIndustryAnnual PRIMARY KEY NONCLUSTERED (BlockIndustryID),
    CONSTRAINT FK_FBIA_Date     FOREIGN KEY (DateKey)     REFERENCES dw.DimDate(DateKey),
    CONSTRAINT FK_FBIA_Block    FOREIGN KEY (BlockKey)    REFERENCES dw.DimBlock(BlockKey),
    CONSTRAINT FK_FBIA_Industry FOREIGN KEY (IndustryKey) REFERENCES dw.DimIndustry(IndustryKey)
);
CREATE CLUSTERED INDEX CX_FBIA_Year_Block
    ON dw.FactBlockIndustryAnnual(CensusYear, BlockKey, IndustryKey);
GO

/* ---------------------------------------------------------------------
   2.3  FACT 2 -- FactBlockAnnual   13.519 dong
        GRAIN: 1 block x 1 census year
        Phuc vu BQ1 (phia cung), BQ3, BQ4, BQ5, BQ6, BQ7

        CONSOLIDATED FACT TABLE -- gop 6 nguon CLUE cung grain:
          cafes-and-restaurants-with-seating-capacity
          bars-and-pubs-with-patron-capacity
          employment-by-block-by-clue-industry     (qua Fact 3)
          business-establishments-per-block         (qua Fact 3)
          residential-dwellings
          Current_Victorian_Licences + development-activity-monitor

        !!! CANH BAO DOUBLE COUNTING !!!
        Nhom cot Licence* va Pipeline* KHONG phai du lieu census.
          Licence*  = snapshot 30/04/2026
          Pipeline* = Development Activity Monitor (khong co nam)
        Chung CHI duoc dien vao dong IsLatestCensusYear = 1, cac nam
        khac de NULL. Neu dien cho ca 23 nam thi SUM se ra sai 23 lan.
        Trong Power BI moi measure tren nhom cot nay PHAI boc trong
        CALCULATE(..., FactBlockAnnual[IsLatestCensusYear] = 1).
   --------------------------------------------------------------------- */
CREATE TABLE dw.FactBlockAnnual (
    BlockAnnualID           INT IDENTITY(1,1) NOT NULL,
    BlockKey                INT           NOT NULL,
    DateKey                 INT           NOT NULL,   -- 31/12 census year
    CensusYear              SMALLINT      NOT NULL,
    IsLatestCensusYear      BIT           NOT NULL DEFAULT 0,

    /* --- CUNG F&B: ghe va suc chua --- */
    IndoorSeats             INT           NULL,       -- BQ1
    OutdoorSeats            INT           NULL,       -- BQ7
    TotalSeats              INT           NULL,       -- BQ1
    BarPatronCapacity       INT           NULL,       -- BQ1

    /* --- CUNG F&B: so dia diem theo loai hinh --- */
    CafeRestaurantVenues    INT           NULL,       -- BQ5
    BarPubVenues            INT           NULL,       -- BQ5
    TakeawayVenues          INT           NULL,       -- BQ5
    TotalFBVenues           INT           NULL,

    /* --- DAN SO BAN NGAY (tu Fact 3) --- */
    TotalJobs               INT           NULL,       -- BQ4
    FoodBeverageJobs        INT           NULL,       -- BQ4
    OfficeTypeJobs          INT           NULL,       -- BQ4
    RetailJobs              INT           NULL,       -- BQ4
    TotalEstablishments     INT           NULL,
    FoodBeverageEstabs      INT           NULL,

    /* --- DAN SO BAN DEM --- */
    TotalDwellings          INT           NULL,       -- BQ4
    ApartmentDwellings      INT           NULL,       -- BQ4
    StudentDwellings        INT           NULL,       -- BQ4
    HouseDwellings          INT           NULL,       -- BQ4

    /* --- LICENCE snapshot 30/04/2026 -- CHI dong latest --- */
    LicenceCount            INT           NULL,       -- BQ3
    LateNightLicenceCount   INT           NULL,       -- BQ3
    Licence24hCount         INT           NULL,       -- BQ3
    LicensedCapacity        INT           NULL,

    /* --- PIPELINE snapshot (DAM) -- CHI dong latest --- */
    PipelineProjects        INT           NULL,       -- BQ6
    PipelineResiDwellings   INT           NULL,       -- BQ6
    PipelineStudentBeds     INT           NULL,       -- BQ6
    PipelineHotelRooms      INT           NULL,       -- BQ6
    PipelineOfficeSqm       DECIMAL(14,2) NULL,       -- BQ6
    PipelineRetailSqm       DECIMAL(14,2) NULL,       -- BQ6

    LoadBatchID             INT           NULL,
    CONSTRAINT PK_FactBlockAnnual PRIMARY KEY NONCLUSTERED (BlockAnnualID),
    CONSTRAINT UQ_FactBlockAnnual UNIQUE (BlockKey, CensusYear),   -- bao ve grain
    CONSTRAINT FK_FBA_Block FOREIGN KEY (BlockKey) REFERENCES dw.DimBlock(BlockKey),
    CONSTRAINT FK_FBA_Date  FOREIGN KEY (DateKey)  REFERENCES dw.DimDate(DateKey)
);
CREATE CLUSTERED INDEX CX_FBA_Year_Block ON dw.FactBlockAnnual(CensusYear, BlockKey);
GO

/* =====================================================================
   KIEM TRA
   ===================================================================== */
SELECT TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'dw' ORDER BY TABLE_NAME;
-- ky vong 9 bang

PRINT 'DW DDL hoan tat: 6 dimension + 3 fact = 9 bang.';
PRINT 'Chay tiep 05_load_dim_date_time.sql';
GO
