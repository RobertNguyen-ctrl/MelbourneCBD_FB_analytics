/* =====================================================================
   BUOC 05 -- NAP DimDate va DimTime
   ---------------------------------------------------------------------
   Hai dimension nay KHONG lay tu file nguon -- sinh bang T-SQL.
   Chay SAU 04_dw_ddl.sql, TRUOC moi fact.
   ===================================================================== */
USE MelbourneFB_DW;
GO

/* =====================================================================
   1. DimTime -- 24 dong
   ---------------------------------------------------------------------
   Daypart chia theo logic nganh F&B, khong chia deu 6 tieng.
   Daypart KHONG chong lap -> dung lam slicer duoc.

   4 cot cua so gio CHONG LAP nhau -> phai la 4 cot BIT rieng.
     InCafeWindow    06:00-14:00  (gio 6..13)
     InLunchWindow   10:00-15:00  (gio 10..14)
     InAllDayWindow  07:00-19:00  (gio 7..18)
     InNightWindow   16:00-24:00  (gio 16..23)
   Gio 10-13 thuoc DONG THOI Cafe, Lunch va AllDay. Neu dung 1 cot
   CASE WHEN thi 3 cua so kia mat du lieu -- day la loi cua v1.

   KIEM LAI voi bang BQ2 trong bao cao: bang do ghi "6-14 / 7-15 /
   10-19 / 16-24". Dinh nghia duoi day theo NHAN ngu nghia
   (Cafe/Lunch/AllDay/Night). Neu bao cao muon dung so trong bang thi
   sua o day va sua ca bang -- KHONG de hai noi lech nhau.
   ===================================================================== */
/* DELETE chu khong TRUNCATE.
   Ly do: 04_dw_ddl.sql da tao FOREIGN KEY tu 3 fact vao DimTime.
   SQL Server chan TRUNCATE chi vi TON TAI constraint, ke ca khi bang
   fact dang rong -> Msg 4712. DELETE khong bi chan.
   DELETE chi thanh cong khi fact chua co dong nao tro vao -- dung voi
   thu tu chay 04 -> 05 -> 06 -> 07/08/09. Neu muon nap lai DimTime sau
   khi da co fact thi phai xoa fact truoc. */
DELETE FROM dw.DimTime;
GO

;WITH Hours AS (
    SELECT 0 AS h
    UNION ALL SELECT h + 1 FROM Hours WHERE h < 23
)
INSERT INTO dw.DimTime
    (TimeKey, HourLabel, HourLabel12h, Daypart, DaypartSortOrder,
     InCafeWindow, InLunchWindow, InAllDayWindow, InNightWindow,
     IsAfter22h, IsBusinessHour)
SELECT
    h,
    RIGHT('0' + CAST(h AS VARCHAR(2)), 2) + ':00',
    CASE WHEN h = 0  THEN '12 AM'
         WHEN h < 12 THEN CAST(h AS VARCHAR(2)) + ' AM'
         WHEN h = 12 THEN '12 PM'
         ELSE CAST(h - 12 AS VARCHAR(2)) + ' PM' END,
    CASE WHEN h BETWEEN 0  AND 4  THEN N'Late Night'
         WHEN h = 5                THEN N'Early Morning'
         WHEN h BETWEEN 6  AND 10  THEN N'Breakfast'
         WHEN h BETWEEN 11 AND 14  THEN N'Lunch'
         WHEN h BETWEEN 15 AND 17  THEN N'Afternoon'
         WHEN h BETWEEN 18 AND 20  THEN N'Dinner'
         ELSE N'Evening' END,
    CASE WHEN h BETWEEN 0  AND 4  THEN 7
         WHEN h = 5                THEN 1
         WHEN h BETWEEN 6  AND 10  THEN 2
         WHEN h BETWEEN 11 AND 14  THEN 3
         WHEN h BETWEEN 15 AND 17  THEN 4
         WHEN h BETWEEN 18 AND 20  THEN 5
         ELSE 6 END,
    CAST(CASE WHEN h BETWEEN 6  AND 13 THEN 1 ELSE 0 END AS BIT),   -- Cafe
    CAST(CASE WHEN h BETWEEN 10 AND 14 THEN 1 ELSE 0 END AS BIT),   -- Lunch
    CAST(CASE WHEN h BETWEEN 7  AND 18 THEN 1 ELSE 0 END AS BIT),   -- AllDay
    CAST(CASE WHEN h >= 16             THEN 1 ELSE 0 END AS BIT),   -- Night
    CAST(CASE WHEN h >= 22             THEN 1 ELSE 0 END AS BIT),   -- BQ3
    CAST(CASE WHEN h BETWEEN 9 AND 17  THEN 1 ELSE 0 END AS BIT)
FROM Hours
OPTION (MAXRECURSION 30);
GO

-- Bang chung cua viec chong lap: gio 10..13 phai thuoc 3 cua so
SELECT TimeKey, HourLabel, InCafeWindow, InLunchWindow,
       InAllDayWindow, InNightWindow,
       CAST(InCafeWindow AS INT) + CAST(InLunchWindow AS INT)
         + CAST(InAllDayWindow AS INT) + CAST(InNightWindow AS INT) AS SoCuaSo
FROM dw.DimTime
ORDER BY TimeKey;
-- gio 10,11,12,13 -> SoCuaSo = 3.  Neu tat ca deu = 1 la da lam sai.
GO


/* =====================================================================
   2. DimDate -- 2002-01-01 den 2026-12-31  (9.131 dong)
      Mua theo Nam ban cau (Melbourne): Summer = Dec, Jan, Feb
   ===================================================================== */
DELETE FROM dw.DimDate;   -- DELETE, khong TRUNCATE: xem ghi chu o DimTime
GO

;WITH Dates AS (
    SELECT CAST('2002-01-01' AS DATE) AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM Dates WHERE d < '2026-12-31'
)
INSERT INTO dw.DimDate
    (DateKey, FullDate, CalendarYear, CalendarQuarter, QuarterName,
     CalendarMonth, MonthName, MonthYearLabel, DayOfMonth,
     DayOfWeekNumber, DayName, IsWeekend, ISOWeek, DayOfYear,
     SeasonName, IsCurrentYear)
SELECT
    CONVERT(INT, FORMAT(d, 'yyyyMMdd')),
    d,
    YEAR(d),
    DATEPART(QUARTER, d),
    'Q' + CAST(DATEPART(QUARTER, d) AS VARCHAR(1)),
    MONTH(d),
    DATENAME(MONTH, d),
    FORMAT(d, 'MMM yyyy'),
    DAY(d),
    ((DATEPART(WEEKDAY, d) + @@DATEFIRST + 5) % 7) + 1,   -- 1 = Monday
    DATENAME(WEEKDAY, d),
    CASE WHEN ((DATEPART(WEEKDAY, d) + @@DATEFIRST + 5) % 7) + 1 >= 6
         THEN 1 ELSE 0 END,
    DATEPART(ISO_WEEK, d),
    DATEPART(DAYOFYEAR, d),
    CASE WHEN MONTH(d) IN (12, 1, 2) THEN N'Summer'
         WHEN MONTH(d) IN (3, 4, 5)  THEN N'Autumn'
         WHEN MONTH(d) IN (6, 7, 8)  THEN N'Winter'
         ELSE                              N'Spring' END,
    CASE WHEN YEAR(d) = YEAR(GETDATE()) THEN 1 ELSE 0 END
FROM Dates
OPTION (MAXRECURSION 10000);
GO

/* --- Ngay le Victoria -------------------------------------------------
   Nhom co dinh: ap cho moi nam.
   Nhom di dong (Easter, Melbourne Cup, AFL Grand Final): chi lam
   2024-2026 vi do la khoang co du lieu pedestrian. Day la lua chon
   co y thuc, khong phai bo sot -- ghi ro trong bao cao.
   --------------------------------------------------------------------- */
UPDATE dw.DimDate SET IsPublicHolidayVIC = 1, HolidayName = N'New Year''s Day'
    WHERE CalendarMonth = 1 AND DayOfMonth = 1;
UPDATE dw.DimDate SET IsPublicHolidayVIC = 1, HolidayName = N'Australia Day'
    WHERE CalendarMonth = 1 AND DayOfMonth = 26;
UPDATE dw.DimDate SET IsPublicHolidayVIC = 1, HolidayName = N'ANZAC Day'
    WHERE CalendarMonth = 4 AND DayOfMonth = 25;
UPDATE dw.DimDate SET IsPublicHolidayVIC = 1, HolidayName = N'Christmas Day'
    WHERE CalendarMonth = 12 AND DayOfMonth = 25;
UPDATE dw.DimDate SET IsPublicHolidayVIC = 1, HolidayName = N'Boxing Day'
    WHERE CalendarMonth = 12 AND DayOfMonth = 26;
GO

UPDATE dw.DimDate SET IsPublicHolidayVIC = 1, HolidayName = N'Labour Day'
    WHERE DateKey IN (20240311, 20250310, 20260309);
UPDATE dw.DimDate SET IsPublicHolidayVIC = 1, HolidayName = N'Good Friday'
    WHERE DateKey IN (20240329, 20250418, 20260403);
UPDATE dw.DimDate SET IsPublicHolidayVIC = 1, HolidayName = N'Easter Monday'
    WHERE DateKey IN (20240401, 20250421, 20260406);
UPDATE dw.DimDate SET IsPublicHolidayVIC = 1, HolidayName = N'King''s Birthday'
    WHERE DateKey IN (20240610, 20250609, 20260608);
UPDATE dw.DimDate SET IsPublicHolidayVIC = 1, HolidayName = N'AFL Grand Final Friday'
    WHERE DateKey IN (20240927, 20250926);
UPDATE dw.DimDate SET IsPublicHolidayVIC = 1, HolidayName = N'Melbourne Cup Day'
    WHERE DateKey IN (20241105, 20251104, 20261103);
GO

/* =====================================================================
   KIEM TRA
   ===================================================================== */
SELECT 'DimTime' AS Bang, COUNT(*) AS SoDong, 24 AS KyVong FROM dw.DimTime
UNION ALL SELECT 'DimDate', COUNT(*), 9131 FROM dw.DimDate
UNION ALL SELECT 'DimDate - ngay le VIC', COUNT(*), NULL
          FROM dw.DimDate WHERE IsPublicHolidayVIC = 1;

-- DateKey 31/12 cua moi census year PHAI ton tai (Fact 2 va 3 tro vao)
SELECT COUNT(*) AS SoNamCensusCoDateKey
FROM dw.DimDate
WHERE CalendarMonth = 12 AND DayOfMonth = 31
  AND CalendarYear BETWEEN 2002 AND 2024;    -- ky vong 23
GO

PRINT 'Chay tiep 06_load_dimensions.sql';
GO