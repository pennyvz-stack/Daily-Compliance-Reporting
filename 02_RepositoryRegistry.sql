USE DBA_Tools;
GO

-- Create the Repository Registry Table
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[RepositoryRegistry]') AND type in (N'U'))
BEGIN
    CREATE TABLE [dbo].[RepositoryRegistry](
        [RepositoryID] INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RepositoryRegistry PRIMARY KEY,
        [RepositoryName] VARCHAR(100) NOT NULL CONSTRAINT UQ_RepositoryName UNIQUE,
        [IsActive] BIT NOT NULL CONSTRAINT DF_RepositoryRegistry_IsActive DEFAULT (1),
        [CreatedDate] DATETIME NOT NULL CONSTRAINT DF_RepositoryRegistry_CreatedDate DEFAULT (GETDATE())
    );
    
    PRINT 'Table dbo.RepositoryRegistry created successfully.';
END
ELSE
BEGIN
    PRINT 'Table dbo.RepositoryRegistry already exists.';
END
GO
