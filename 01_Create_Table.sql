CREATE TABLE dbo.DeveloperRegistry (
    DeveloperEmail VARCHAR(100) NOT NULL PRIMARY KEY,
    DeveloperName  VARCHAR(100) NOT NULL,
    TimeZoneID     VARCHAR(50)  NOT NULL, -- Must match standard Windows TimeZone IDs
    IsActive       BIT          NOT NULL DEFAULT 1
);

-- Populate your initial team mapping
INSERT INTO dbo.DeveloperRegistry (DeveloperEmail, DeveloperName, TimeZoneID)
VALUES 
('bob@example.com', 'Bob Developer', 'Eastern Standard Time'),
('pennyvz@gmail.com', 'Penny Vanzandt', 'Central Standard Time'),
('carlos@example.com', 'Carlos Silva', 'Central Standard Time'),
('alice@example.com', 'Alice Smith', 'Mountain Standard Time'),
('dana@example.com', 'Dana Jones', 'Pacific Standard Time');
