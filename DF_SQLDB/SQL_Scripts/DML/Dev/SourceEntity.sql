/* =========================================================================
   DML: metadata.SourceEntity (staging -> MERGE)
   Purpose: Register dataset-level metadata for Adverity.customer
   Pattern: temp staging table + MERGE into metadata.SourceEntity
   Author : Shilpashree SR
   Date   : 2025-09-21
   ========================================================================= */

-- deployer info (change if running from CI)
DECLARE @DeployedBy NVARCHAR(255) = N'Shilpashree SR';
DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();

-- 1) Clean up existing temp staging table if present
IF OBJECT_ID('tempdb..#stg_SourceEntity') IS NOT NULL
    DROP TABLE #stg_SourceEntity;

-- 2) Create temp staging table
CREATE TABLE #stg_SourceEntity (
    ApplicationName NVARCHAR(255) NOT NULL,
    SourceSystemName NVARCHAR(255) NOT NULL,
    SourceDesc NVARCHAR(500) NULL,
    LoadGroupName NVARCHAR(255) NULL,
    DatasetName NVARCHAR(255) NOT NULL,
    DatasetDesc NVARCHAR(500) NULL,
    DatasetFilepath NVARCHAR(1024) NULL,
    DatasetFileFormat NVARCHAR(50) NULL,
    DatasetFilePattern NVARCHAR(255) NULL,
    DatasetLoadType NVARCHAR(20) NULL,
    DatasetConnectionName NVARCHAR(255) NULL,
    DatasetLastProcessed DATETIME2(3) NULL,
    DatasetSchemaName NVARCHAR(255) NULL,
    DatasetTimestampColumnName NVARCHAR(255) NULL
);

-- 3) Stage the Adverity.customer metadata row(s)
INSERT INTO #stg_SourceEntity
SELECT
    N'ADF_Ingest',                -- ApplicationName
    N'Adverity',                  -- SourceSystemName (as confirmed)
    N'Adverity source for customer dataset', -- SourceDesc
    N'Adverity_Ingest',           -- LoadGroupName
    N'customer',                  -- DatasetName (as confirmed)
    N'Customer master data from Adverity', -- DatasetDesc
    N'abfss://df-raw@datafoundationblob.dfs.core.windows.net/adverity/customer/', -- DatasetFilepath (logical)
    N'CSV',                       -- DatasetFileFormat
    N'customer_*.csv',            -- DatasetFilePattern (file mask)
    N'INCREMENTAL',               -- DatasetLoadType (assume incremental)
    N'azure_blob',                -- DatasetConnectionName (matches your connection)
    NULL,                         -- DatasetLastProcessed (NULL initially)
    N'raw',                       -- DatasetSchemaName (logical schema reference)
    N'ingest_time';               -- DatasetTimestampColumnName (watermark column)

-- 4) MERGE from staging into metadata.SourceEntity
MERGE INTO metadata.SourceEntity AS tgt
USING #stg_SourceEntity AS src
    ON tgt.ApplicationName = src.ApplicationName
   AND tgt.SourceSystemName = src.SourceSystemName
   AND tgt.DatasetName = src.DatasetName
WHEN MATCHED AND (
       ISNULL(tgt.SourceDesc,'')                 <> ISNULL(src.SourceDesc,'')
    OR ISNULL(tgt.LoadGroupName,'')              <> ISNULL(src.LoadGroupName,'')
    OR ISNULL(tgt.DatasetDesc,'')                <> ISNULL(src.DatasetDesc,'')
    OR ISNULL(tgt.DatasetFilepath,'')             <> ISNULL(src.DatasetFilepath,'')
    OR ISNULL(tgt.DatasetFileFormat,'')           <> ISNULL(src.DatasetFileFormat,'')
    OR ISNULL(tgt.DatasetFilePattern,'')          <> ISNULL(src.DatasetFilePattern,'')
    OR ISNULL(tgt.DatasetLoadType,'')             <> ISNULL(src.DatasetLoadType,'')
    OR ISNULL(tgt.DatasetConnectionName,'')       <> ISNULL(src.DatasetConnectionName,'')
    OR ISNULL(tgt.DatasetSchemaName,'')           <> ISNULL(src.DatasetSchemaName,'')
    OR ISNULL(tgt.DatasetTimestampColumnName,'')  <> ISNULL(src.DatasetTimestampColumnName,'')
) THEN
    UPDATE SET
        SourceDesc = src.SourceDesc,
        LoadGroupName = src.LoadGroupName,
        DatasetDesc = src.DatasetDesc,
        DatasetFilepath = src.DatasetFilepath,
        DatasetFileFormat = src.DatasetFileFormat,
        DatasetFilePattern = src.DatasetFilePattern,
        DatasetLoadType = src.DatasetLoadType,
        DatasetConnectionName = src.DatasetConnectionName,
        DatasetSchemaName = src.DatasetSchemaName,
        DatasetTimestampColumnName = src.DatasetTimestampColumnName,
        RecordUpdatedTimestamp = @Now,
        RecordUpdatedBy = @DeployedBy
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        ApplicationName, SourceSystemName, SourceDesc, LoadGroupName,
        DatasetName, DatasetDesc, DatasetFilepath, DatasetFileFormat, DatasetFilePattern,
        DatasetLoadType, DatasetConnectionName, DatasetLastProcessed,
        DatasetSchemaName, DatasetTimestampColumnName,
        RecordCreatedTimestamp, RecordCreatedBy
    )
    VALUES (
        src.ApplicationName, src.SourceSystemName, src.SourceDesc, src.LoadGroupName,
        src.DatasetName, src.DatasetDesc, src.DatasetFilepath, src.DatasetFileFormat, src.DatasetFilePattern,
        src.DatasetLoadType, src.DatasetConnectionName, src.DatasetLastProcessed,
        src.DatasetSchemaName, src.DatasetTimestampColumnName,
        @Now, @DeployedBy
    )
OUTPUT $action, inserted.ApplicationName, inserted.SourceSystemName, inserted.DatasetName;
GO

-- 5) Cleanup
DROP TABLE IF EXISTS #stg_SourceEntity;
GO
