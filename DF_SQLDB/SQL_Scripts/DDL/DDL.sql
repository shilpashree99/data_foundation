-- create schema 'metadata' if not exists
IF NOT EXISTS (
    SELECT *
    FROM sys.schemas
    WHERE name = N'metadata')
    EXEC ('CREATE SCHEMA metadata AUTHORIZATION dbo');
GO

---------------------------------------------------------

-- Create table 'metadata.BatchMaster' if not exists
IF OBJECT_ID('metadata.BatchMaster', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.BatchMaster (
        BatchID VARCHAR(255) NOT NULL PRIMARY KEY,     -- unique batch identifier
        ApplicationName VARCHAR(255) NOT NULL,
        SourceSystemName VARCHAR(255) NOT NULL,
        LoadGroupName VARCHAR(255) NULL,
        StageName VARCHAR(200) NULL,
        LoadStartTime DATETIME NOT NULL,
        LoadEndTime DATETIME NULL,
        LoadStatus VARCHAR(255) NULL,

        -- audit fields
        RecordCreatedTimestamp DATETIME DEFAULT GETDATE(),
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME NULL,
        RecordUpdatedBy NVARCHAR(255) NULL
    );
END
GO

---------------------------------------------------------
SELECT *
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'metadata'
--AND TABLE_NAME = 'BatchMaster';

---------------------------------------------------------

-- Create table 'metadata.BatchDetails' if not exists
IF OBJECT_ID('metadata.BatchDetails', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.BatchDetails (
        BatchDetailID INT IDENTITY(1,1) PRIMARY KEY,   -- surrogate key
        BatchID VARCHAR(255) NOT NULL,                 -- FK to BatchMaster
        SourceSystemName VARCHAR(255) NOT NULL,
        LoadGroupName VARCHAR(255) NULL,
        StageName VARCHAR(200) NULL,
        LoadStartTime DATETIME NOT NULL,
        LoadEndTime DATETIME NULL,
        LoadStatus VARCHAR(255) NULL,

        -- audit columns
        RecordCreatedTimestamp DATETIME DEFAULT GETDATE(),
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME NULL,
        RecordUpdatedBy NVARCHAR(255) NULL
    );
END
GO

-------------------------------------------------

-- Create table 'metadata.ConnectionDetails' if not exists

IF OBJECT_ID('metadata.ConnectionDetails', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.ConnectionDetails (
        -- audit columns (track who/when created or updated)
        RecordCreatedTimestamp DATETIME DEFAULT GETDATE(),
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME NULL,
        RecordUpdatedBy NVARCHAR(255) NULL,

        -- connection metadata
        SourceConnectionName VARCHAR(500) NULL,       -- friendly name of the source connection
        SourceType VARCHAR(500) NULL,                 -- e.g., ADLS, Blob
        ConnectionDesc NVARCHAR(500) NULL,            -- optional description
        IsActive CHAR(1) NOT NULL,                    -- Y/N flag to enable/disable

        -- storage account details
        StorageAccountName VARCHAR(500) NULL,         -- ADLS/Blob account
        StorageContainerName NVARCHAR(500) NULL,      -- container/folder

        -- authentication (via Key Vault)
        ServicePrincipalId NVARCHAR(500) NULL,        -- SPN client ID
        ServicePrincipalSecretKVName NVARCHAR(500) NULL -- KV secret name for SPN secret
    );
END
GO

---------------------------------------------------------------

-- Create table 'metadata.Path' if not exists
IF OBJECT_ID('metadata.Path', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.Path (
        -- audit columns (track who/when created or updated)
        RecordCreatedTimestamp DATETIME DEFAULT GETDATE(),
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME NULL,
        RecordUpdatedBy NVARCHAR(255) NULL,

        -- identifiers
        SourceSystemName VARCHAR(255),    -- source system (e.g., CRM, ERP)
        DatasetName VARCHAR(255),         -- dataset name (e.g., Sales, Customer)

        -- raw layer paths
        RawPath VARCHAR(255) NOT NULL,                -- main raw data path
        RawTempPath VARCHAR(255) NOT NULL,            -- temporary staging in raw
        RawErrorPath VARCHAR(255) NOT NULL,           -- rejected/error files
        RawHistoryPath VARCHAR(255) NOT NULL,         -- historical loads
        RawArchivePath VARCHAR(255) NOT NULL,         -- archived source files
        RawPreTempPath VARCHAR(255) NOT NULL,         -- pre-processing temp
        RawFormatConfigPath VARCHAR(255) NOT NULL,    -- raw file format config

        -- sanitized layer paths
        SanitizedPath VARCHAR(255) NOT NULL,                 
        SanitizedRejectedPath VARCHAR(255) NOT NULL,
        SanitizedRejectedSummaryPath VARCHAR(255) NOT NULL,

        -- curated/optimized layer paths
        CuratedPath VARCHAR(255) NOT NULL,
        CuratedRejectedPath VARCHAR(255) NOT NULL,
        OptimizedPath VARCHAR(255) NOT NULL,

        -- data quality configs and logs
        DQConfigPath VARCHAR(255) NOT NULL,
        GlobalDQConfigPath VARCHAR(255) NOT NULL,
        DQLogDeltaTablePath VARCHAR(255) NOT NULL,

        -- reconciliation configs and logs
        ReconConfigPath VARCHAR(255) NOT NULL,
        ReconLogPath VARCHAR(255) NOT NULL,
        ReconSCDType2LogPath VARCHAR(255) NOT NULL,

        -- file validation
        FileValidationLogPath VARCHAR(255) NOT NULL,
        FVGlobalConfigPath VARCHAR(255) NOT NULL,
        EntityFVConfigPath VARCHAR(255) NOT NULL,
        SchemaValidationLogPath VARCHAR(255) NOT NULL,

        -- archival
        TempArchivePath VARCHAR(255) NOT NULL,
        ArchivalAtSourcePath VARCHAR(255) NOT NULL,
        PreTempArchiveLogPath VARCHAR(255) NOT NULL,

        -- preprocessing configs and logs
        PreProcessValidationLogPath VARCHAR(255) NOT NULL,
        GlobalPreProConfigPath VARCHAR(255) NOT NULL,
        EntityPreProConfigPath VARCHAR(255) NOT NULL
    );
END
GO

-------------------------------
-- Create table 'metadata.SourceEntity' if not exists

IF OBJECT_ID('metadata.SourceEntity') IS NULL
BEGIN
CREATE TABLE metadata.SourceEntity (
        -- Audit columns
        RecordCreatedTimestamp DATETIME NULL,
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME NULL,
        RecordUpdatedBy NVARCHAR(255) NULL,

        -- Application and source metadata
        ApplicationName VARCHAR(255),
        SourceSystemName VARCHAR(255),
        SourceDesc NVARCHAR(255),
        LoadGroupName VARCHAR(255),

        -- Dataset metadata
        DatasetName VARCHAR(255),
        DatasetDesc NVARCHAR(255),
        DatasetFilepath VARCHAR(255),
        DatasetFileFormat VARCHAR(255),
        DatasetFilePattern VARCHAR(255),
        DatasetLoadType VARCHAR(255),
        DatasetConnectionName VARCHAR(255),
        DatasetLastProcessed DATETIME,

        -- Schema & timestamp information
        DatasetSchemaName VARCHAR(255) NULL,
        DatasetTimestampColumnName VARCHAR(255) NULL,

        -- Flags for dataset activity
        IsActive VARCHAR(5) NOT NULL DEFAULT 'Y',
        ArchivalAtSourceType VARCHAR(255) NULL,
        FilterSheetName VARCHAR(255) NULL,
        PostLandingLoadType VARCHAR(255) NULL,

        -- Special Settings flags
        TechnicalDataValidationActiveFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        AllowRejectedRowsFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        AllowRejectedRowsSummaryFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        RawFileValidationActiveFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        BusinessValidationActiveFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        DataReconciliationActiveflag VARCHAR(5) NOT NULL DEFAULT 'Y',
        RemoveDuplicateflag VARCHAR(5) NOT NULL DEFAULT 'N',
        HandleDuplicateFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        IsArchivalAtSource VARCHAR(5) NOT NULL DEFAULT 'N',
        RawDataBackupFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        PreProcessingActiveFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        RawHistoryflag VARCHAR(5) NOT NULL DEFAULT 'Y',
        ProceedFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        SchemaValidationFlag VARCHAR(5) NOT NULL DEFAULT 'N',

        -- Inclusion / Exclusion columns
        ColumnInclusionType VARCHAR(10) NULL,
        IncludeColumns VARCHAR(255) NULL,
        ExcludeColumns VARCHAR(255) NULL,
        DatasetSelectQueryFlag VARCHAR(1) NOT NULL DEFAULT 'N',
        DatasetSelectQuery VARCHAR(MAX) NOT NULL,

        -- Full load start date related columns
        FullExtractFilterFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        FullExtractNoOfYear INT NULL,
        FullExtractStartDate DATETIME DEFAULT NULL,

        -- Deleted records indicator flags
        DeletedRecordColName VARCHAR(100) DEFAULT NULL,
        DeletedRecordColValue VARCHAR(100) DEFAULT NULL,

        -- Replace special characters from column names
        ReplaceSpecialCharsFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        TrimSpecialCharsFlag VARCHAR(5) NOT NULL DEFAULT 'N',
        ColumnNameCharsToReplace VARCHAR(50) NULL,
        ReplacementChar VARCHAR(10),

        -- Notification flag and email ID
        NotificationEmailld VARCHAR(255) NULL,
        DatasetNotifiedFlag VARCHAR(5) NOT NULL DEFAULT 'N',

        -- Catalog/schema for sanitized and rejected data
        SanitizedCatalogName VARCHAR(255) DEFAULT NULL,
        SanitizedSchemaName VARCHAR(255) DEFAULT NULL,
        RejectedCatalogName VARCHAR(255) DEFAULT NULL,
        RejectedSchemaName VARCHAR(255) DEFAULT NULL,

        -- API-related metadata
        ApiPath VARCHAR(250) NULL,
        ApiParams VARCHAR(max) NULL,
        ApiScenerio VARCHAR(255) NULL   -- ✅ no trailing comma
    )
END
GO

-------------------------------------------

-- Drop and Create constraint 'chkEntityLoadType'

ALTER TABLE metadata.SourceEntity DROP CONSTRAINT IF EXISTS chkEntityLoadType
GO

ALTER TABLE metadata.SourceEntity ADD CONSTRAINT chkEntityLoadType CHECK (DatasetLoadType in ('FULL', 'INCREMENTAL', 'NA'))
GO

-----------------------------------------------

-- Create table 'metadata.SourceEntityDefinition' if not exists
IF OBJECT_ID('metadata.SourceEntityDefinition', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.SourceEntityDefinition (
        -- Audit columns
        RecordCreatedTimestamp DATETIME NULL,
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME NULL,
        RecordUpdatedBy NVARCHAR(255) NULL,

        -- Source and dataset details
        SourceSystemName VARCHAR(255),             -- e.g., CRM, ERP
        DatasetName VARCHAR(255),                  -- dataset/table this column belongs to

        -- Field/column definition
        DatasetFieldName VARCHAR(255) NOT NULL,    -- column/field name
        DatasetFieldType VARCHAR(255) NOT NULL,    -- datatype (e.g., VARCHAR, INT, DATE)
        DatasetScale INT NULL,                     -- scale for decimals
        DatasetPrecision INT NULL,                 -- precision for decimals

        -- Column role flags
        IsKey VARCHAR(5) NOT NULL DEFAULT 'N',     -- is this a key column? Y/N
        IsOrderByColumn VARCHAR(5) NOT NULL DEFAULT 'N', -- is this used for ordering? Y/N
        OrderByColumnSequence INT NULL,            -- sequence for order by
        OrderingFactor VARCHAR(10) NULL,           -- ASC/DESC (ordering direction)

        IsSCDColumn VARCHAR(5) NOT NULL DEFAULT 'N', -- flag for Slowly Changing Dimension column
        IsCountryCode VARCHAR(5) NOT NULL DEFAULT 'N' -- flag for country code field

    );
END
GO

-----------------------------
-- Create table 'metadata.LoadGroup' if not exists
IF OBJECT_ID('metadata.LoadGroup', 'U') IS NOT NULL
BEGIN
    DROP TABLE IF EXISTS metadata.LoadGroup;
END
GO

CREATE TABLE metadata.LoadGroup (
    -- Audit columns
    RecordCreatedTimestamp DATETIME NULL,
    RecordCreatedBy NVARCHAR(255) NULL,
    RecordUpdatedTimestamp DATETIME NULL,
    RecordUpdatedBy NVARCHAR(255) NULL,

    -- Business metadata
    SourceSystemName VARCHAR(255),                   -- e.g., CRM, SAP, Salesforce
    LoadGroupName VARCHAR(255),                      -- logical group name for datasets
    LoadGroupProceedFlag VARCHAR(5) NOT NULL DEFAULT 'Y', -- flag to mark if load group can proceed
    UnityCatalogClusterId VARCHAR(30) NULL,          -- Databricks UC cluster reference
    NonUnityCatalogClusterId VARCHAR(30) NULL        -- Non-UC Databricks cluster reference
);
GO

------------------------------------------------------

-- Create table 'metadata.UnityCatalogOwnerChanges' if not exists
IF OBJECT_ID('metadata.UnityCatalogOwnerChanges', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.UnityCatalogOwnerChanges (
        Id INT PRIMARY KEY IDENTITY (1,1),     -- surrogate key
        CatalogName VARCHAR(50),               -- UC catalog
        SchemaName VARCHAR(50),                -- schema inside catalog
        TableName VARCHAR(50),                 -- table inside schema
        Owner VARCHAR(50),                     -- owner (user/service principal)
        IsActive CHAR(1)                       -- active flag (Y/N)
    );
END
GO