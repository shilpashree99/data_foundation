-- ============================================================
-- Metadata Schema & Tables DDL
-- Author : Shilpashree SR
-- Date   : 2025-09-21
-- Purpose: Metadata-driven architecture for Azure Data Platform
-- ============================================================

---------------------------------------------------------------
-- 1. Create metadata schema
-- All tables will be created inside this schema instead of dbo
---------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.schemas WHERE name = N'metadata'
)
BEGIN
    EXEC ('CREATE SCHEMA [metadata] AUTHORIZATION [dbo]');
END
GO

---------------------------------------------------------------
-- 2. BatchMaster
-- Purpose: Tracks every pipeline/batch execution at a high level
-- Each batch has one row, identified by BatchID
---------------------------------------------------------------
IF OBJECT_ID('metadata.BatchMaster', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.BatchMaster (
        BatchID NVARCHAR(100) NOT NULL PRIMARY KEY,   -- Unique batch identifier
        ApplicationName NVARCHAR(255) NOT NULL,       -- Which app triggered it (ADF, Databricks, etc.)
        SourceSystemName NVARCHAR(255) NOT NULL,      -- Source system (SAP, CRM, etc.)
        LoadGroupName NVARCHAR(255) NULL,             -- Logical grouping (e.g., Finance Loads)
        StageName NVARCHAR(200) NULL,                 -- Processing stage (Raw, Sanitized, etc.)
        LoadStartTime DATETIME2(3) NOT NULL,          -- Start time of batch
        LoadEndTime DATETIME2(3) NULL,                -- End time of batch
        LoadStatus NVARCHAR(50) NULL,                 -- Success, Failed, Running

        -- Audit trail
        RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME2(3) NULL,
        RecordUpdatedBy NVARCHAR(255) NULL
    );
END
GO

---------------------------------------------------------------
-- 3. BatchDetails
-- Purpose: Tracks detailed execution within a batch
-- Example: Each dataset/file processed under a batch
---------------------------------------------------------------
IF OBJECT_ID('metadata.BatchDetails', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.BatchDetails (
        BatchDetailID INT IDENTITY(1,1) PRIMARY KEY,  -- Surrogate key
        BatchID NVARCHAR(100) NOT NULL,               -- FK to BatchMaster
        SourceSystemName NVARCHAR(255) NOT NULL,      -- System that provided the data
        LoadGroupName NVARCHAR(255) NULL,             -- Group name for logical association
        StageName NVARCHAR(200) NULL,                 -- Raw/Transformed/Sanitized
        LoadStartTime DATETIME2(3) NOT NULL,
        LoadEndTime DATETIME2(3) NULL,
        LoadStatus NVARCHAR(50) NULL,                 -- Success/Failed/Running

        -- Audit trail
        RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME2(3) NULL,
        RecordUpdatedBy NVARCHAR(255) NULL
    );

    -- Relationship to BatchMaster
    ALTER TABLE metadata.BatchDetails
    ADD CONSTRAINT FK_BatchDetails_BatchMaster
        FOREIGN KEY (BatchID) REFERENCES metadata.BatchMaster(BatchID);

    -- Index for quick joins on BatchID + SourceSystem
    CREATE INDEX IX_BatchDetails_BatchID_SourceSystem
        ON metadata.BatchDetails (BatchID, SourceSystemName);
END
GO

---------------------------------------------------------------
-- 4. ConnectionDetails
-- Purpose: Stores connection-level metadata (non-secret)
-- Secrets are referenced from Key Vault
---------------------------------------------------------------
IF OBJECT_ID('metadata.ConnectionDetails', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.ConnectionDetails (
        ConnectionID INT IDENTITY(1,1) PRIMARY KEY,   -- Surrogate key
        SourceConnectionName NVARCHAR(255) NOT NULL,  -- Friendly name (e.g., HR_Blob, CRM_SQL)
        SourceType NVARCHAR(100) NOT NULL,            -- Blob, ADLS, SQL, API
        ConnectionDesc NVARCHAR(500) NULL,            -- Optional description
        IsActive BIT NOT NULL DEFAULT 1,              -- Enable/disable toggle

        -- Storage account/container details
        StorageAccountName NVARCHAR(255) NULL,
        StorageContainerName NVARCHAR(255) NULL,

        -- Authentication details (secrets in KV)
        ServicePrincipalId NVARCHAR(255) NULL,
        ServicePrincipalSecretKVName NVARCHAR(255) NULL,

        -- Audit trail
        RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME2(3) NULL,
        RecordUpdatedBy NVARCHAR(255) NULL
    );

    -- Prevent duplicate connection names
    CREATE UNIQUE INDEX UX_ConnectionDetails_SourceConnectionName
        ON metadata.ConnectionDetails (SourceConnectionName);
END
GO

---------------------------------------------------------------
-- 5. Path
-- Purpose: Stores ADLS/Blob paths for datasets across all zones
---------------------------------------------------------------
IF OBJECT_ID('metadata.Path', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.Path (
        PathID INT IDENTITY(1,1) PRIMARY KEY,
        SourceSystemName NVARCHAR(255) NOT NULL,  -- SAP, CRM, etc.
        DatasetName NVARCHAR(255) NOT NULL,       -- Sales, Customers, etc.

        -- Landing / Transformed paths
        RawPath NVARCHAR(1024) NOT NULL,
        RawTempPath NVARCHAR(1024) NOT NULL,
        RawErrorPath NVARCHAR(1024) NOT NULL,
        TransformedPath NVARCHAR(1024) NOT NULL,
        TransformedTempPath NVARCHAR(1024) NOT NULL,
        TransformedErrorPath NVARCHAR(1024) NOT NULL,

        -- Sanitized zone paths
        SanitizedPath NVARCHAR(1024) NOT NULL,
        SanitizedRejectedPath NVARCHAR(1024) NOT NULL,
        SanitizedRejectedSummaryPath NVARCHAR(1024) NOT NULL,

        -- Curated & Optimized zone paths
        CuratedPath NVARCHAR(1024) NOT NULL,
        CuratedRejectedPath NVARCHAR(1024) NOT NULL,
        OptimizedPath NVARCHAR(1024) NOT NULL,

        -- Audit trail
        RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME2(3) NULL,
        RecordUpdatedBy NVARCHAR(255) NULL
    );

    -- Ensure one row per dataset
    CREATE UNIQUE INDEX UX_Path_Source_Dataset
        ON metadata.Path (SourceSystemName, DatasetName);
END
GO

---------------------------------------------------------------
-- 6. SourceEntity
-- Purpose: Register datasets (at dataset-level granularity)
-- Includes format, load type, and schema reference
---------------------------------------------------------------
IF OBJECT_ID('metadata.SourceEntity', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.SourceEntity (
        SourceEntityID INT IDENTITY(1,1) PRIMARY KEY,
        ApplicationName NVARCHAR(255) NOT NULL,      -- App name (e.g., SAPLoader)
        SourceSystemName NVARCHAR(255) NOT NULL,     -- System (SAP, CRM)
        SourceDesc NVARCHAR(500) NULL,
        LoadGroupName NVARCHAR(255) NULL,            -- Group link

        DatasetName NVARCHAR(255) NOT NULL,          -- e.g., Sales
        DatasetDesc NVARCHAR(500) NULL,
        DatasetFilepath NVARCHAR(1024) NULL,
        DatasetFileFormat NVARCHAR(50) NULL,         -- csv, json, parquet
        DatasetFilePattern NVARCHAR(255) NULL,       -- file mask
        DatasetLoadType NVARCHAR(20) NULL,           -- FULL/INCREMENTAL
        DatasetConnectionName NVARCHAR(255) NULL,    -- Link to ConnectionDetails
        DatasetLastProcessed DATETIME2(3) NULL,      -- Last processed timestamp

        DatasetSchemaName NVARCHAR(255) NULL,        -- Schema reference
        DatasetTimestampColumnName NVARCHAR(255) NULL, -- For watermarking

        -- Audit trail
        RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME2(3) NULL,
        RecordUpdatedBy NVARCHAR(255) NULL
    );

    -- Enforce valid load type values
    ALTER TABLE metadata.SourceEntity
    DROP CONSTRAINT IF EXISTS CHK_SourceEntity_LoadType;

    ALTER TABLE metadata.SourceEntity
    ADD CONSTRAINT CHK_SourceEntity_LoadType
        CHECK (DatasetLoadType IS NULL OR DatasetLoadType IN (N'FULL', N'INCREMENTAL', N'NA'));

    -- Prevent duplicate dataset definitions
    CREATE UNIQUE INDEX UX_SourceEntity_App_Source_Dataset
        ON metadata.SourceEntity (ApplicationName, SourceSystemName, DatasetName);
END
GO

---------------------------------------------------------------
-- 7. SourceEntityDefinition
-- Purpose: Field-level definitions for each dataset
-- Works like a schema registry
---------------------------------------------------------------
IF OBJECT_ID('metadata.SourceEntityDefinition', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.SourceEntityDefinition (
        SourceEntityDefID INT IDENTITY(1,1) PRIMARY KEY,
        SourceSystemName NVARCHAR(255) NOT NULL,
        DatasetName NVARCHAR(255) NOT NULL,

        DatasetFieldName NVARCHAR(255) NOT NULL,    -- Column name
        DatasetFieldType NVARCHAR(100) NOT NULL,    -- Data type
        DatasetScale INT NULL,
        DatasetPrecision INT NULL,

        -- Flags for pipeline logic
        IsKey BIT NOT NULL DEFAULT 0,               -- Part of PK?
        IsOrderByColumn BIT NOT NULL DEFAULT 0,     -- Used in ordering?
        OrderByColumnSequence INT NULL,
        OrderingFactor NVARCHAR(10) NULL,           -- ASC/DESC
        IsSCDColumn BIT NOT NULL DEFAULT 0,         -- For Slowly Changing Dimensions
        IsCountryCode BIT NOT NULL DEFAULT 0,       -- Mark country columns

        -- Audit trail
        RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME2(3) NULL,
        RecordUpdatedBy NVARCHAR(255) NULL
    );

    -- Prevent duplicate field definitions
    CREATE UNIQUE INDEX UX_SourceEntityDef_System_Dataset_Field
        ON metadata.SourceEntityDefinition (SourceSystemName, DatasetName, DatasetFieldName);
END
GO

---------------------------------------------------------------
-- 8. LoadGroup
-- Purpose: Logical grouping of datasets for orchestration control
---------------------------------------------------------------
DROP TABLE IF EXISTS metadata.LoadGroup;
GO

CREATE TABLE metadata.LoadGroup (
    LoadGroupID INT IDENTITY(1,1) PRIMARY KEY,
    SourceSystemName NVARCHAR(255) NOT NULL,
    LoadGroupName NVARCHAR(255) NOT NULL,
    LoadGroupProceedFlag BIT NOT NULL DEFAULT 1,   -- 1=run, 0=skip
    UnityCatalogClusterId NVARCHAR(100) NULL,      -- Cluster link if UC
    NonUnityCatalogClusterId NVARCHAR(100) NULL,   -- Cluster link if non-UC

    -- Audit trail
    RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
    RecordCreatedBy NVARCHAR(255) NULL,
    RecordUpdatedTimestamp DATETIME2(3) NULL,
    RecordUpdatedBy NVARCHAR(255) NULL
);

-- Prevent duplicate group names per system
CREATE UNIQUE INDEX UX_LoadGroup_SourceSystem_Group
    ON metadata.LoadGroup (SourceSystemName, LoadGroupName);
GO

---------------------------------------------------------------
-- 9. UnityCatalogOwnerChanges
-- Purpose: Tracks ownership changes for UC objects (tables)
---------------------------------------------------------------
IF OBJECT_ID('metadata.UnityCatalogOwnerChanges', 'U') IS NULL
BEGIN
    CREATE TABLE metadata.UnityCatalogOwnerChanges (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        CatalogName NVARCHAR(255) NOT NULL,
        SchemaName NVARCHAR(255) NOT NULL,
        TableName NVARCHAR(255) NOT NULL,
        Owner NVARCHAR(255) NOT NULL,               -- User/group to assign ownership
        IsActive BIT NOT NULL DEFAULT 1,            -- 1=Active, 0=Inactive

        -- Audit trail
        RecordCreatedTimestamp DATETIME2(3) DEFAULT SYSUTCDATETIME(),
        RecordCreatedBy NVARCHAR(255) NULL,
        RecordUpdatedTimestamp DATETIME2(3) NULL,
        RecordUpdatedBy NVARCHAR(255) NULL
    );

    -- Avoid duplicate ownership assignments
    CREATE UNIQUE INDEX UX_UnityCatalogOwnerChanges_Object
        ON metadata.UnityCatalogOwnerChanges (CatalogName, SchemaName, TableName, Owner);
END
GO

/* =========================================================================
   View: vwIngestionConfig
   -------------------------------------------------------------------------
   Purpose:
     - Provides a single unified configuration view for ingestion pipelines.
     - Joins business metadata (SourceEntity) with technical storage paths (Path).
     - Normalizes file formats so pipelines don’t have to handle special cases.
     - Pipelines will query this view instead of joining multiple tables.

   Why this matters:
     - Keeps ADF/Databricks pipelines generic (they query the view, not raw tables).
     - Any future metadata changes are handled here without touching pipelines.
     - Ensures consistent ingestion logic across all datasets.

   Author : Shilpashree SR
   Date   : 2025-09-21
   ========================================================================= */
IF OBJECT_ID('metadata.vwIngestionConfig', 'V') IS NOT NULL
    DROP VIEW metadata.vwIngestionConfig;
GO

CREATE VIEW metadata.vwIngestionConfig
AS
SELECT
    -------------------------------------------------------------------------
    -- Business metadata (from SourceEntity)
    -------------------------------------------------------------------------
    se.ApplicationName,      -- Which application registered this dataset
    se.SourceSystemName,     -- Source system (e.g., SAP, CRM)
    se.DatasetName,          -- Dataset (e.g., Sales, Customers)
    se.LoadGroupName,        -- Group of datasets for orchestration

    -------------------------------------------------------------------------
    -- Normalized file format
    -- Ensures that special file types (XLS, ZIP, TABLE) are mapped to 
    -- standard formats (CSV, PARQUET) so ingestion logic is consistent.
    -------------------------------------------------------------------------
    CASE 
        WHEN se.DatasetFileFormat IN (N'XLS', N'XLSX', N'ZIP') THEN N'CSV'
        WHEN se.DatasetFileFormat = N'TABLE' THEN N'PARQUET'
        ELSE se.DatasetFileFormat
    END AS NormalizedFileFormat,

    -------------------------------------------------------------------------
    -- Technical storage paths (from Path)
    -- Defines where to pick files from, where to land them,
    -- and where to store processed outputs across all zones.
    -------------------------------------------------------------------------
    p.RawPath,                       -- Raw landing path
    p.RawTempPath,                   -- Temp path for raw files
    p.RawErrorPath,                  -- Error quarantine for raw
    p.TransformedPath,               -- Transformed landing path
    p.TransformedTempPath,           -- Temp path for transformed files
    p.TransformedErrorPath,          -- Error quarantine for transformed
    p.SanitizedPath,                 -- Sanitized zone path
    p.SanitizedRejectedPath,         -- Path for rejected records
    p.SanitizedRejectedSummaryPath,  -- Path for summary of rejects
    p.CuratedPath,                   -- Curated zone path (business-aligned tables)
    p.CuratedRejectedPath,           -- Path for rejected curated records
    p.OptimizedPath                  -- Optimized zone path (aggregates, marts)

FROM metadata.SourceEntity AS se
INNER JOIN metadata.Path AS p
    ON se.SourceSystemName = p.SourceSystemName
   AND se.DatasetName = p.DatasetName;
GO

/* =========================================================================
   View: vwSourceEntityDefinition
   -------------------------------------------------------------------------
   Purpose:
     - Exposes dataset field definitions (column-level metadata).
     - Allows ADF/Databricks pipelines to dynamically build schemas.
     - Enables schema validation, dynamic DataFrame creation,
       and metadata-driven transformations.

   Why this matters:
     - No need to hardcode schemas in pipelines.
     - Supports schema enforcement, evolution, and drift handling.
     - Enables one generic ingestion/processing pipeline to work 
       across multiple datasets.

   Author : Shilpashree SR
   Date   : 2025-09-21
   ========================================================================= */
IF OBJECT_ID('metadata.vwSourceEntityDefinition', 'V') IS NOT NULL
    DROP VIEW metadata.vwSourceEntityDefinition;
GO

CREATE VIEW metadata.vwSourceEntityDefinition
AS
SELECT
    -------------------------------------------------------------------------
    -- Identifiers
    -------------------------------------------------------------------------
    SourceSystemName,           -- System that dataset belongs to (SAP, CRM, etc.)
    DatasetName,                -- Dataset name (Sales, Customers, etc.)

    -------------------------------------------------------------------------
    -- Field definition
    -------------------------------------------------------------------------
    DatasetFieldName,           -- Column name
    DatasetFieldType,           -- Column data type (string, int, date, etc.)
    DatasetScale,               -- Scale (if numeric)
    DatasetPrecision,           -- Precision (if numeric)

    -------------------------------------------------------------------------
    -- Flags for ingestion/transform logic
    -------------------------------------------------------------------------
    IsKey,                      -- Flag: is this field part of PK?
    IsOrderByColumn,            -- Flag: should pipeline order by this field?
    OrderByColumnSequence,      -- Order sequence (if multiple ordering cols)
    OrderingFactor,             -- ASC/DESC indicator
    IsSCDColumn,                -- Flag: used in Slowly Changing Dimension logic?
    IsCountryCode               -- Flag: is this a country-code field?
FROM metadata.SourceEntityDefinition;
GO


/* ============================================================
   usp_StartBatch
   Purpose: Create a batch entry in metadata.BatchMaster and return BatchID.
   If @BatchID is NULL, the procedure generates a GUID-based ID.
   Caller: ADF orchestration or Databricks job at the start of a run.
   ============================================================ */
IF OBJECT_ID('metadata.usp_StartBatch', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_StartBatch;
GO

CREATE PROCEDURE metadata.usp_StartBatch
    @BatchID      NVARCHAR(100) = NULL,    -- Optional external BatchID; if NULL a NEWID() is created
    @ApplicationName NVARCHAR(255),        -- e.g., 'ADF_Ingest'
    @SourceSystemName NVARCHAR(255),       -- e.g., 'SAP'
    @LoadGroupName NVARCHAR(255) = NULL,
    @StageName NVARCHAR(200) = NULL,
    @CallerUser NVARCHAR(255) = NULL       -- Who triggered this (optional)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @BatchID IS NULL
            SET @BatchID = CONVERT(NVARCHAR(100), NEWID());

        INSERT INTO metadata.BatchMaster (
            BatchID, ApplicationName, SourceSystemName, LoadGroupName, StageName,
            LoadStartTime, LoadStatus, RecordCreatedTimestamp, RecordCreatedBy
        )
        VALUES (
            @BatchID, @ApplicationName, @SourceSystemName, @LoadGroupName, @StageName,
            SYSUTCDATETIME(), N'Running', SYSUTCDATETIME(), @CallerUser
        );

        -- Return the BatchID so caller can pass it to subsequent steps
        SELECT 0 AS ReturnCode, 'OK' AS ReturnMessage, @BatchID AS BatchID;
    END TRY
    BEGIN CATCH
        SELECT
            ERROR_NUMBER() AS ErrorNumber,
            ERROR_SEVERITY() AS ErrorSeverity,
            ERROR_STATE() AS ErrorState,
            ERROR_PROCEDURE() AS ErrorProcedure,
            ERROR_LINE() AS ErrorLine,
            ERROR_MESSAGE() AS ErrorMessage;
        RAISERROR('usp_StartBatch failed: %s', 16, 1, ERROR_MESSAGE());
    END CATCH
END
GO

/* ============================================================
   usp_EndBatch
   Purpose: Mark batch end, set status and optional error message.
   Caller: ADF OnSuccess/OnFailure step or Databricks finally block.
   ============================================================ */
IF OBJECT_ID('metadata.usp_EndBatch', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_EndBatch;
GO

CREATE PROCEDURE metadata.usp_EndBatch
    @BatchID NVARCHAR(100),
    @LoadStatus NVARCHAR(50),       -- 'Success' or 'Failed' or 'Cancelled'
    @RowsIn BIGINT = NULL,         -- optional metrics
    @RowsOut BIGINT = NULL,
    @ErrorMessage NVARCHAR(MAX) = NULL,
    @UpdatedBy NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        UPDATE metadata.BatchMaster
        SET LoadEndTime = SYSUTCDATETIME(),
            LoadStatus = @LoadStatus,
            RecordUpdatedTimestamp = SYSUTCDATETIME(),
            RecordUpdatedBy = @UpdatedBy
        WHERE BatchID = @BatchID;

        -- Optionally, return a row to indicate success
        SELECT 0 AS ReturnCode, 'OK' AS ReturnMessage, @BatchID AS BatchID, @LoadStatus AS LoadStatus;
    END TRY
    BEGIN CATCH
        SELECT
            ERROR_NUMBER() AS ErrorNumber,
            ERROR_MESSAGE() AS ErrorMessage;
        RAISERROR('usp_EndBatch failed: %s', 16, 1, ERROR_MESSAGE());
    END CATCH
END
GO


/* ============================================================
   usp_LogBatchDetail
   Purpose: Insert a BatchDetails record (per file/table processed).
   Caller: ADF ForEach after copy; Databricks per-file processing.
   ============================================================ */
IF OBJECT_ID('metadata.usp_LogBatchDetail', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_LogBatchDetail;
GO

CREATE PROCEDURE metadata.usp_LogBatchDetail
    @BatchID NVARCHAR(100),
    @SourceSystemName NVARCHAR(255),
    @LoadGroupName NVARCHAR(255) = NULL,
    @StageName NVARCHAR(200) = NULL,
    @LoadStartTime DATETIME2(3) = NULL,
    @LoadEndTime DATETIME2(3) = NULL,
    @LoadStatus NVARCHAR(50) = NULL,
    @RowsIn BIGINT = NULL,
    @RowsOut BIGINT = NULL,
    @FileName NVARCHAR(1024) = NULL,
    @CreatedBy NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @LoadStartTime IS NULL
            SET @LoadStartTime = SYSUTCDATETIME();

        INSERT INTO metadata.BatchDetails (
            BatchID, SourceSystemName, LoadGroupName, StageName,
            LoadStartTime, LoadEndTime, LoadStatus,
            RecordCreatedTimestamp, RecordCreatedBy
        )
        VALUES (
            @BatchID, @SourceSystemName, @LoadGroupName, @StageName,
            @LoadStartTime, @LoadEndTime, @LoadStatus,
            SYSUTCDATETIME(), @CreatedBy
        );

        -- Return the inserted BatchDetailID
        SELECT SCOPE_IDENTITY() AS BatchDetailID, 0 AS ReturnCode, 'OK' AS ReturnMessage;
    END TRY
    BEGIN CATCH
        SELECT
            ERROR_NUMBER() AS ErrorNumber,
            ERROR_MESSAGE() AS ErrorMessage;
        RAISERROR('usp_LogBatchDetail failed: %s', 16, 1, ERROR_MESSAGE());
    END CATCH
END
GO

/* ============================================================
   usp_GetIngestionConfig
   Purpose: Return ingestion config rows (wraps vwIngestionConfig).
   Caller: ADF Lookup activity or Databricks JDBC read to decide what to process.
   Parameters:
     - @SourceSystemName, @DatasetName are optional filters.
   ============================================================ */
IF OBJECT_ID('metadata.usp_GetIngestionConfig', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_GetIngestionConfig;
GO

CREATE PROCEDURE metadata.usp_GetIngestionConfig
    @SourceSystemName NVARCHAR(255) = NULL,
    @DatasetName NVARCHAR(255)     = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT *
        FROM metadata.vwIngestionConfig AS cfg
        WHERE (@SourceSystemName IS NULL OR cfg.SourceSystemName = @SourceSystemName)
          AND (@DatasetName IS NULL OR cfg.DatasetName = @DatasetName);
    END TRY
    BEGIN CATCH
        SELECT
            ERROR_NUMBER() AS ErrorNumber,
            ERROR_MESSAGE() AS ErrorMessage;
        RAISERROR('usp_GetIngestionConfig failed: %s', 16, 1, ERROR_MESSAGE());
    END CATCH
END
GO


/* ============================================================
   usp_GetIngestionConfig
   Purpose: Return ingestion config rows (wraps vwIngestionConfig).
   Caller: ADF Lookup activity or Databricks JDBC read to decide what to process.
   Parameters:
     - @SourceSystemName, @DatasetName are optional filters.
   ============================================================ */
IF OBJECT_ID('metadata.usp_GetIngestionConfig', 'P') IS NOT NULL
    DROP PROCEDURE metadata.usp_GetIngestionConfig;
GO

CREATE PROCEDURE metadata.usp_GetIngestionConfig
    @SourceSystemName NVARCHAR(255) = NULL,
    @DatasetName NVARCHAR(255)     = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SELECT *
        FROM metadata.vwIngestionConfig AS cfg
        WHERE (@SourceSystemName IS NULL OR cfg.SourceSystemName = @SourceSystemName)
          AND (@DatasetName IS NULL OR cfg.DatasetName = @DatasetName);
    END TRY
    BEGIN CATCH
        SELECT
            ERROR_NUMBER() AS ErrorNumber,
            ERROR_MESSAGE() AS ErrorMessage;
        RAISERROR('usp_GetIngestionConfig failed: %s', 16, 1, ERROR_MESSAGE());
    END CATCH
END
GO


