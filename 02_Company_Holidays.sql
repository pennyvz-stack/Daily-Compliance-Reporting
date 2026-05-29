USE [DBA_Tools];
GO

CREATE TABLE dbo.CompanyHolidays (
    HolidayDate DATE NOT NULL PRIMARY KEY,
    HolidayName VARCHAR(100) NOT NULL
);
GO

SET NOCOUNT ON;
DECLARE @Year INT = 2026;
WHILE @Year <= 2030
BEGIN
    DECLARE @Jan1 DATE = DATEFROMPARTS(@Year, 1, 1);
    DECLARE @Jul4 DATE = DATEFROMPARTS(@Year, 7, 4);
    DECLARE @Nov11 DATE = DATEFROMPARTS(@Year, 11, 11);
    DECLARE @Dec25 DATE = DATEFROMPARTS(@Year, 12, 25);
    
    INSERT INTO dbo.CompanyHolidays (HolidayDate, HolidayName)
    VALUES (CASE WHEN DATEPART(WEEKDAY, @Jan1) = 7 THEN DATEADD(DAY, -1, @Jan1) WHEN DATEPART(WEEKDAY, @Jan1) = 1 THEN DATEADD(DAY, 1, @Jan1) ELSE @Jan1 END, 'New Year''s Day');
    DECLARE @Jun19 DATE = DATEFROMPARTS(@Year, 6, 19);
    INSERT INTO dbo.CompanyHolidays (HolidayDate, HolidayName) VALUES (CASE WHEN DATEPART(WEEKDAY, @Jun19) = 7 THEN DATEADD(DAY, -1, @Jun19) WHEN DATEPART(WEEKDAY, @Jun19) = 1 THEN DATEADD(DAY, 1, @Jun19) ELSE @Jun19 END, 'Juneteenth National Independence Day');
    INSERT INTO dbo.CompanyHolidays (HolidayDate, HolidayName) VALUES (CASE WHEN DATEPART(WEEKDAY, @Jul4) = 7 THEN DATEADD(DAY, -1, @Jul4) WHEN DATEPART(WEEKDAY, @Jul4) = 1 THEN DATEADD(DAY, 1, @Jul4) ELSE @Jul4 END, 'Independence Day');
    INSERT INTO dbo.CompanyHolidays (HolidayDate, HolidayName) VALUES (CASE WHEN DATEPART(WEEKDAY, @Nov11) = 7 THEN DATEADD(DAY, -1, @Nov11) WHEN DATEPART(WEEKDAY, @Nov11) = 1 THEN DATEADD(DAY, 1, @Nov11) ELSE @Nov11 END, 'Veterans Day');
    INSERT INTO dbo.CompanyHolidays (HolidayDate, HolidayName) VALUES (CASE WHEN DATEPART(WEEKDAY, @Dec25) = 7 THEN DATEADD(DAY, -1, @Dec25) WHEN DATEPART(WEEKDAY, @Dec25) = 1 THEN DATEADD(DAY, 1, @Dec25) ELSE @Dec25 END, 'Christmas Day');
    DECLARE @Mlk DATE = DATEFROMPARTS(@Year, 1, 1); WHILE DATEPART(WEEKDAY, @Mlk) <> 2 SET @Mlk = DATEADD(DAY, 1, @Mlk); SET @Mlk = DATEADD(WEEK, 2, @Mlk); INSERT INTO dbo.CompanyHolidays (HolidayDate, HolidayName) VALUES (@Mlk, 'Martin Luther King Jr. Day');
    DECLARE @Pres DATE = DATEFROMPARTS(@Year, 2, 1); WHILE DATEPART(WEEKDAY, @Pres) <> 2 SET @Pres = DATEADD(DAY, 1, @Pres); SET @Pres = DATEADD(WEEK, 2, @Pres); INSERT INTO dbo.CompanyHolidays (HolidayDate, HolidayName) VALUES (@Pres, 'Washington''s Birthday');
    DECLARE @Mem DATE = DATEFROMPARTS(@Year, 5, 31); WHILE DATEPART(WEEKDAY, @Mem) <> 2 SET @Mem = DATEADD(DAY, -1, @Mem); INSERT INTO dbo.CompanyHolidays (HolidayDate, HolidayName) VALUES (@Mem, 'Memorial Day');
    DECLARE @Lab DATE = DATEFROMPARTS(@Year, 9, 1); WHILE DATEPART(WEEKDAY, @Lab) <> 2 SET @Lab = DATEADD(DAY, 1, @Lab); INSERT INTO dbo.CompanyHolidays (HolidayDate, HolidayName) VALUES (@Lab, 'Labor Day');
    DECLARE @Col DATE = DATEFROMPARTS(@Year, 10, 1); WHILE DATEPART(WEEKDAY, @Col) <> 2 SET @Col = DATEADD(DAY, 1, @Col); SET @Col = DATEADD(WEEK, 1, @Col); INSERT INTO dbo.CompanyHolidays (HolidayDate, HolidayName) VALUES (@Col, 'Columbus Day');
    DECLARE @Thxg DATE = DATEFROMPARTS(@Year, 11, 1); WHILE DATEPART(WEEKDAY, @Thxg) <> 5 SET @Thxg = DATEADD(DAY, 1, @Thxg); SET @Thxg = DATEADD(WEEK, 3, @Thxg); INSERT INTO dbo.CompanyHolidays (HolidayDate, HolidayName) VALUES (@Thxg, 'Thanksgiving Day');

    SET @Year = @Year + 1;
END;
GO
