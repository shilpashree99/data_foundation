/* ============================================================
   Metadata Framework - Full DDL + Views + Stored Procedures
   Author : Shilpashree SR
   Date   : 2025-09-21
   Purpose: Create metadata schema, tables, views and procs
   Notes  : Idempotent for Dev: drops conflicting objects first.
   ============================================================ */

-- If you want to lock to a specific DB, uncomment and set:
-- USE [df_metadata_dev];
-- GO

/****************************************************************************
 1) DROP stored procedures and views (so they don't block table drops)
****************************************************************************/
IF OBJECT_ID('metadata.usp_GetIngestionConfig', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_GetIngestionConfig;
GO
IF OBJECT_ID('metadata.usp_LogBatchDetail', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_LogBatchDetail;
GO
IF OBJECT_ID('metadata.usp_EndBatch', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_EndBatch;
GO
IF OBJECT_ID('metadata.usp_StartBatch', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_StartBatch;
GO

IF OBJECT_ID('metadata.vwIngestionConfig', 'V') IS NOT NULL
    DROP VIEW metadata.vwIngestionConfig;
GO
IF OBJECT_ID('metadata.vwSourceEntityDefinition', 'V') IS NOT NULL
    DROP VIEW metadata.vwSourceEntityDefinition;
GO

/****************************************************************************
 2) Drop any foreign key constraints that reference metadata tables.
****************************************************************************/
DECLARE @fkname SYSNAME, @parent_table SYSNAME, @schema_name SYSNAME, @sql NVARCHAR(MAX);

DECLARE fk_cursor CURSOR FOR
SELECT fk.name, OBJECT_NAME(fk.parent_object_id) AS parent_table,
       SCHEMA_NAME(OBJECTPROPERTY(fk.parent_object_id, 'SchemaId')) AS schema_name
FROM sys.foreign_keys fk
WHERE OBJECT_SCHEMA_NAME(fk.referenced_object_id) = 'metadata';

OPEN fk_cursor;
FETCH NEXT FROM fk_cursor INTO @fkname, @parent_table, @schema_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'ALTER TABLE ' + QUOTENAME(@schema_name) + N'.' + QUOTENAME(@parent_table) +
               N' DROP CONSTRAINT ' + QUOTENAME(@fkname) + N';';
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        PRINT 'Warning dropping FK ' + ISNULL(@fkname,'<null>') + ': ' + ERROR_MESSAGE();
    END CATCH;

    FETCH NEXT FROM fk_cursor INTO @fkname, @parent_table, @schema_name;
END

CLOSE fk_cursor;
DEALLOCATE fk_cursor;
GO


/****************************************************************************
 3) Drop metadata tables (children first to avoid FK issues)
****************************************************************************/
DROP TABLE IF EXISTS metadata.BatchDetails;
DROP TABLE IF EXISTS metadata.UnityCatalogOwnerChanges;
DROP TABLE IF EXISTS metadata.LoadGroup;
DROP TABLE IF EXISTS metadata.SourceEntityDefinition;
DROP TABLE IF EXISTS metadata.SourceEntity;
DROP TABLE IF EXISTS metadata.Path;
DROP TABLE IF EXISTS metadata.ConnectionDetails;
DROP TABLE IF EXISTS metadata.BatchMaster;
GO

/****************************************************************************
 4) Create schema if not exists
****************************************************************************/
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'metadata')
    EXEC ('CREATE SCHEMA [metadata] AUTHORIZATION [dbo]');
GO

/****************************************************************************
 5) Create tables (clean definitions with comments)
****************************************************************************/

-- BatchMaster: high-level batch runs
CREATE TABLE metadata.BatchMaster (
    BatchID NVARCHAR(100) NOT NULL PRIMARY KEY,    -- Unique batch identifier
    ApplicationName NVARCHAR(255) NOT NULL,       -- e.g., ADF, Databricks
    SourceSystemName NVARCHAR(255) NOT NULL,      -- e.g., Adverity
    LoadGroupName NVARCHAR(255) NULL,             -- logical grouping
    StageName NVARCHAR(200) NULL,                 -- Raw/Sanitized/Curated/etc.
    LoadStartTime DATETIME2(3) NOT NULL,
    LoadEndTime DATETIME2(3) NULL,
    LoadStatus NVARCHAR(50) NULL,                 -- Running/Success/Failed

    -- audit columns
    RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
    RecordCreatedBy NVARCHAR(255) NULL,
    RecordUpdatedTimestamp DATETIME2(3) NULL,
    RecordUpdatedBy NVARCHAR(255) NULL
);
GO

-- BatchDetails: detailed per-file / per-dataset logs within Batch
CREATE TABLE metadata.BatchDetails (
    BatchDetailID INT IDENTITY(1,1) PRIMARY KEY,
    BatchID NVARCHAR(100) NOT NULL,               -- FK to BatchMaster
    SourceSystemName NVARCHAR(255) NOT NULL,
    LoadGroupName NVARCHAR(255) NULL,
    StageName NVARCHAR(200) NULL,
    LoadStartTime DATETIME2(3) NOT NULL,
    LoadEndTime DATETIME2(3) NULL,
    LoadStatus NVARCHAR(50) NULL,

    RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
    RecordCreatedBy NVARCHAR(255) NULL,
    RecordUpdatedTimestamp DATETIME2(3) NULL,
    RecordUpdatedBy NVARCHAR(255) NULL
);
GO

-- Add FK BatchDetails -> BatchMaster (after both tables exist)
ALTER TABLE metadata.BatchDetails
ADD CONSTRAINT FK_BatchDetails_BatchMaster FOREIGN KEY (BatchID)
    REFERENCES metadata.BatchMaster(BatchID);
GO

-- ConnectionDetails: connection-level metadata (non-secret)
CREATE TABLE metadata.ConnectionDetails (
    ConnectionID INT IDENTITY(1,1) PRIMARY KEY,
    SourceConnectionName NVARCHAR(255) NOT NULL,   -- friendly name
    SourceType NVARCHAR(100) NOT NULL,             -- Blob/ADLS/SQL/API
    ConnectionDesc NVARCHAR(500) NULL,
    IsActive BIT NOT NULL DEFAULT 1,
    StorageAccountName NVARCHAR(255) NULL,
    StorageContainerName NVARCHAR(255) NULL,
    ServicePrincipalId NVARCHAR(255) NULL,
    ServicePrincipalSecretKVName NVARCHAR(255) NULL,
    RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
    RecordCreatedBy NVARCHAR(255) NULL,
    RecordUpdatedTimestamp DATETIME2(3) NULL,
    RecordUpdatedBy NVARCHAR(255) NULL
);
-- unique friendly name
CREATE UNIQUE INDEX UX_ConnectionDetails_SourceConnectionName ON metadata.ConnectionDetails (SourceConnectionName);
GO

-- Path: storage paths for each dataset (landing -> sanitized -> curated -> optimized)
CREATE TABLE metadata.Path (
    PathID INT IDENTITY(1,1) PRIMARY KEY,
    SourceSystemName NVARCHAR(255) NOT NULL,
    DatasetName NVARCHAR(255) NOT NULL,
    RawPath NVARCHAR(1024) NOT NULL,
    RawTempPath NVARCHAR(1024) NOT NULL,
    RawErrorPath NVARCHAR(1024) NOT NULL,
    TransformedPath NVARCHAR(1024) NOT NULL,
    TransformedTempPath NVARCHAR(1024) NOT NULL,
    TransformedErrorPath NVARCHAR(1024) NOT NULL,
    SanitizedPath NVARCHAR(1024) NOT NULL,
    SanitizedRejectedPath NVARCHAR(1024) NOT NULL,
    SanitizedRejectedSummaryPath NVARCHAR(1024) NOT NULL,
    CuratedPath NVARCHAR(1024) NOT NULL,
    CuratedRejectedPath NVARCHAR(1024) NOT NULL,
    OptimizedPath NVARCHAR(1024) NOT NULL,
    RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
    RecordCreatedBy NVARCHAR(255) NULL,
    RecordUpdatedTimestamp DATETIME2(3) NULL,
    RecordUpdatedBy NVARCHAR(255) NULL
);
CREATE UNIQUE INDEX UX_Path_Source_Dataset ON metadata.Path (SourceSystemName, DatasetName);
GO

-- SourceEntity: dataset-level registration
CREATE TABLE metadata.SourceEntity (
    SourceEntityID INT IDENTITY(1,1) PRIMARY KEY,
    ApplicationName NVARCHAR(255) NOT NULL,
    SourceSystemName NVARCHAR(255) NOT NULL,
    SourceDesc NVARCHAR(500) NULL,
    LoadGroupName NVARCHAR(255) NULL,
    DatasetName NVARCHAR(255) NOT NULL,
    DatasetDesc NVARCHAR(500) NULL,
    DatasetFilepath NVARCHAR(1024) NULL,
    DatasetFileFormat NVARCHAR(50) NULL,
    DatasetFilePattern NVARCHAR(255) NULL,
    DatasetLoadType NVARCHAR(20) NULL,  -- FULL/INCREMENTAL/NA
    DatasetConnectionName NVARCHAR(255) NULL,
    DatasetLastProcessed DATETIME2(3) NULL,
    DatasetSchemaName NVARCHAR(255) NULL,
    DatasetTimestampColumnName NVARCHAR(255) NULL,
    RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
    RecordCreatedBy NVARCHAR(255) NULL,
    RecordUpdatedTimestamp DATETIME2(3) NULL,
    RecordUpdatedBy NVARCHAR(255) NULL
);
-- Enforce allowed load types
ALTER TABLE metadata.SourceEntity
ADD CONSTRAINT CHK_SourceEntity_LoadType CHECK (DatasetLoadType IS NULL OR DatasetLoadType IN (N'FULL', N'INCREMENTAL', N'NA'));
CREATE UNIQUE INDEX UX_SourceEntity_App_Source_Dataset ON metadata.SourceEntity (ApplicationName, SourceSystemName, DatasetName);
GO

-- SourceEntityDefinition: column-level schema registry
CREATE TABLE metadata.SourceEntityDefinition (
    SourceEntityDefID INT IDENTITY(1,1) PRIMARY KEY,
    SourceSystemName NVARCHAR(255) NOT NULL,
    DatasetName NVARCHAR(255) NOT NULL,
    DatasetFieldName NVARCHAR(255) NOT NULL,
    DatasetFieldType NVARCHAR(100) NOT NULL,
    DatasetScale INT NULL,
    DatasetPrecision INT NULL,
    IsKey BIT NOT NULL DEFAULT 0,
    IsOrderByColumn BIT NOT NULL DEFAULT 0,
    OrderByColumnSequence INT NULL,
    OrderingFactor NVARCHAR(10) NULL,
    IsSCDColumn BIT NOT NULL DEFAULT 0,
    IsCountryCode BIT NOT NULL DEFAULT 0,
    RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
    RecordCreatedBy NVARCHAR(255) NULL,
    RecordUpdatedTimestamp DATETIME2(3) NULL,
    RecordUpdatedBy NVARCHAR(255) NULL
);
CREATE UNIQUE INDEX UX_SourceEntityDef_System_Dataset_Field ON metadata.SourceEntityDefinition (SourceSystemName, DatasetName, DatasetFieldName);
GO

-- LoadGroup: grouping for orchestration
CREATE TABLE metadata.LoadGroup (
    LoadGroupID INT IDENTITY(1,1) PRIMARY KEY,
    SourceSystemName NVARCHAR(255) NOT NULL,
    LoadGroupName NVARCHAR(255) NOT NULL,
    LoadGroupProceedFlag BIT NOT NULL DEFAULT 1,
    UnityCatalogClusterId NVARCHAR(100) NULL,
    NonUnityCatalogClusterId NVARCHAR(100) NULL,
    RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
    RecordCreatedBy NVARCHAR(255) NULL,
    RecordUpdatedTimestamp DATETIME2(3) NULL,
    RecordUpdatedBy NVARCHAR(255) NULL
);
CREATE UNIQUE INDEX UX_LoadGroup_SourceSystem_Group ON metadata.LoadGroup (SourceSystemName, LoadGroupName);
GO

-- UnityCatalogOwnerChanges: UC ownership governance
CREATE TABLE metadata.UnityCatalogOwnerChanges (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    CatalogName NVARCHAR(255) NOT NULL,
    SchemaName NVARCHAR(255) NOT NULL,
    TableName NVARCHAR(255) NOT NULL,
    Owner NVARCHAR(255) NOT NULL,
    IsActive BIT NOT NULL DEFAULT 1,
    RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
    RecordCreatedBy NVARCHAR(255) NULL,
    RecordUpdatedTimestamp DATETIME2(3) NULL,
    RecordUpdatedBy NVARCHAR(255) NULL
);
CREATE UNIQUE INDEX UX_UnityCatalogOwnerChanges_Object ON metadata.UnityCatalogOwnerChanges (CatalogName, SchemaName, TableName, Owner);
GO

/****************************************************************************
 6) Create Views (vwIngestionConfig, vwSourceEntityDefinition)
****************************************************************************/

IF OBJECT_ID('metadata.vwIngestionConfig', 'V') IS NOT NULL
    DROP VIEW metadata.vwIngestionConfig;
GO

CREATE VIEW metadata.vwIngestionConfig
AS
SELECT
    se.ApplicationName,
    se.SourceSystemName,
    se.DatasetName,
    se.LoadGroupName,
    CASE 
        WHEN se.DatasetFileFormat IN (N'XLS', N'XLSX', N'ZIP') THEN N'CSV'
        WHEN se.DatasetFileFormat = N'TABLE' THEN N'PARQUET'
        ELSE se.DatasetFileFormat
    END AS NormalizedFileFormat,
    p.RawPath,
    p.RawTempPath,
    p.RawErrorPath,
    p.TransformedPath,
    p.TransformedTempPath,
    p.TransformedErrorPath,
    p.SanitizedPath,
    p.SanitizedRejectedPath,
    p.SanitizedRejectedSummaryPath,
    p.CuratedPath,
    p.CuratedRejectedPath,
    p.OptimizedPath
FROM metadata.SourceEntity AS se
INNER JOIN metadata.Path AS p
    ON se.SourceSystemName = p.SourceSystemName
   AND se.DatasetName = p.DatasetName;
GO

IF OBJECT_ID('metadata.vwSourceEntityDefinition', 'V') IS NOT NULL
    DROP VIEW metadata.vwSourceEntityDefinition;
GO

CREATE VIEW metadata.vwSourceEntityDefinition
AS
SELECT
    SourceSystemName,
    DatasetName,
    DatasetFieldName,
    DatasetFieldType,
    DatasetScale,
    DatasetPrecision,
    IsKey,
    IsOrderByColumn,
    OrderByColumnSequence,
    OrderingFactor,
    IsSCDColumn,
    IsCountryCode
FROM metadata.SourceEntityDefinition;
GO

/****************************************************************************
 7) Stored Procedures (Start/Log/End/GetIngestionConfig)
    Simplified versions (no TRY/CATCH) for stable POC usage.
****************************************************************************/

-- usp_StartBatch
IF OBJECT_ID('metadata.usp_StartBatch', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_StartBatch;
GO
CREATE PROCEDURE metadata.usp_StartBatch
    @ApplicationName NVARCHAR(255),
    @SourceSystemName NVARCHAR(255),
    @LoadGroupName NVARCHAR(255) = NULL,
    @StageName NVARCHAR(200) = NULL,
    @BatchID NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    -- BatchID format: SourceSystem_yyyyMMddHHmmss
    SET @BatchID = CONCAT(@SourceSystemName, '_', FORMAT(GETDATE(), 'yyyyMMddHHmmss'));
    INSERT INTO metadata.BatchMaster (
        BatchID, ApplicationName, SourceSystemName, LoadGroupName, StageName,
        LoadStartTime, LoadStatus, RecordCreatedTimestamp, RecordCreatedBy
    ) VALUES (
        @BatchID, @ApplicationName, @SourceSystemName, @LoadGroupName, @StageName,
        GETDATE(), 'Running', GETDATE(), SUSER_SNAME()
    );
    SELECT @BatchID AS BatchID;
END
GO

-- usp_EndBatch
IF OBJECT_ID('metadata.usp_EndBatch', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_EndBatch;
GO
CREATE PROCEDURE metadata.usp_EndBatch
    @BatchID NVARCHAR(255),
    @LoadStatus NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE metadata.BatchMaster
    SET LoadEndTime = GETDATE(),
        LoadStatus = @LoadStatus,
        RecordUpdatedTimestamp = GETDATE(),
        RecordUpdatedBy = SUSER_SNAME()
    WHERE BatchID = @BatchID;
END
GO

-- usp_LogBatchDetail
IF OBJECT_ID('metadata.usp_LogBatchDetail', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_LogBatchDetail;
GO
CREATE PROCEDURE metadata.usp_LogBatchDetail
    @BatchID NVARCHAR(255),
    @SourceSystemName NVARCHAR(255),
    @LoadGroupName NVARCHAR(255) = NULL,
    @StageName NVARCHAR(200) = NULL,
    @LoadStatus NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO metadata.BatchDetails (
        BatchID, SourceSystemName, LoadGroupName, StageName,
        LoadStartTime, LoadEndTime, LoadStatus, RecordCreatedTimestamp, RecordCreatedBy
    ) VALUES (
        @BatchID, @SourceSystemName, @LoadGroupName, @StageName,
        GETDATE(), GETDATE(), @LoadStatus, GETDATE(), SUSER_SNAME()
    );
END
GO

-- usp_GetIngestionConfig
IF OBJECT_ID('metadata.usp_GetIngestionConfig', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_GetIngestionConfig;
GO
CREATE PROCEDURE metadata.usp_GetIngestionConfig
    @SourceSystemName NVARCHAR(255),
    @DatasetName NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT *
    FROM metadata.vwIngestionConfig
    WHERE SourceSystemName = @SourceSystemName
      AND DatasetName = @DatasetName;
END
GO

/****************************************************************************
 8) Quick Validation Queries (run after script completes)
****************************************************************************/
PRINT 'Script completed. Run the following checks manually to validate:';
PRINT '1) List tables: SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = ''metadata'';';
PRINT '2) List procedures: SELECT name FROM sys.procedures WHERE schema_id = SCHEMA_ID(''metadata'');';
PRINT '3) Test start proc: DECLARE @b NVARCHAR(255); EXEC metadata.usp_StartBatch @ApplicationName=''POC'', @SourceSystemName=''Adverity'', @BatchID=@b OUTPUT; SELECT @b;';
PRINT '4) Test view: SELECT TOP 5 * FROM metadata.vwIngestionConfig;';
GO
