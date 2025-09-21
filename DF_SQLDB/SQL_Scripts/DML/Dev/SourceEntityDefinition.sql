/* =========================================================================
   DML: metadata.SourceEntityDefinition (staging -> MERGE)
   Purpose: Insert field-level schema for Adverity.customer
   Pattern: temp staging table + MERGE into metadata.SourceEntityDefinition
   Author : Shilpashree SR
   Date   : 2025-09-21
   Notes:
     - Edit column types/flags to match your source schema if needed.
     - Safe to re-run (MERGE will update existing or insert new).
   ========================================================================= */

DECLARE @DeployedBy NVARCHAR(255) = N'Shilpashree SR';
DECLARE @Now DATETIME2(3) = SYSUTCDATETIME();

-- 1) Drop temp if exists
IF OBJECT_ID('tempdb..#stg_SourceEntityDef') IS NOT NULL
    DROP TABLE #stg_SourceEntityDef;

-- 2) Create temp staging table
CREATE TABLE #stg_SourceEntityDef (
    SourceSystemName NVARCHAR(255) NOT NULL,
    DatasetName NVARCHAR(255) NOT NULL,
    DatasetFieldName NVARCHAR(255) NOT NULL,
    DatasetFieldType NVARCHAR(100) NOT NULL,
    DatasetScale INT NULL,
    DatasetPrecision INT NULL,
    IsKey BIT NOT NULL,
    IsOrderByColumn BIT NOT NULL,
    OrderByColumnSequence INT NULL,
    OrderingFactor NVARCHAR(10) NULL,
    IsSCDColumn BIT NOT NULL,
    IsCountryCode BIT NOT NULL
);

-- 3) Stage field rows for Adverity.customer
-- Example columns: adjust types/flags for your real source
INSERT INTO #stg_SourceEntityDef
SELECT N'Adverity', N'customer', N'customer_id',    N'INT',      NULL, NULL, 1, 0, NULL, NULL, 0, 0 UNION ALL
SELECT N'Adverity', N'customer', N'customer_code',  N'NVARCHAR', NULL, NULL, 0, 0, NULL, NULL, 0, 0 UNION ALL
SELECT N'Adverity', N'customer', N'first_name',     N'NVARCHAR', NULL, NULL, 0, 0, NULL, NULL, 0, 0 UNION ALL
SELECT N'Adverity', N'customer', N'last_name',      N'NVARCHAR', NULL, NULL, 0, 0, NULL, NULL, 0, 0 UNION ALL
SELECT N'Adverity', N'customer', N'email',          N'NVARCHAR', NULL, NULL, 0, 0, NULL, NULL, 0, 0 UNION ALL
SELECT N'Adverity', N'customer', N'country_code',   N'NVARCHAR', NULL, NULL, 0, 0, NULL, NULL, 0, 1 UNION ALL
SELECT N'Adverity', N'customer', N'created_at',     N'DATETIME2',NULL, NULL, 0, 0, NULL, NULL, 0, 0 UNION ALL
SELECT N'Adverity', N'customer', N'updated_at',     N'DATETIME2',NULL, NULL, 0, 0, NULL, NULL, 0, 0 UNION ALL
SELECT N'Adverity', N'customer', N'is_active',      N'BIT',      NULL, NULL, 0, 0, NULL, NULL, 0, 0;

-- 4) MERGE staged rows into target table
MERGE INTO metadata.SourceEntityDefinition AS tgt
USING #stg_SourceEntityDef AS src
    ON tgt.SourceSystemName = src.SourceSystemName
   AND tgt.DatasetName = src.DatasetName
   AND tgt.DatasetFieldName = src.DatasetFieldName
WHEN MATCHED AND (
       ISNULL(tgt.DatasetFieldType,'')      <> ISNULL(src.DatasetFieldType,'')
    OR ISNULL(tgt.DatasetScale, -99999)     <> ISNULL(src.DatasetScale, -99999)
    OR ISNULL(tgt.DatasetPrecision, -99999) <> ISNULL(src.DatasetPrecision, -99999)
    OR ISNULL(tgt.IsKey,0)                  <> ISNULL(src.IsKey,0)
    OR ISNULL(tgt.IsOrderByColumn,0)        <> ISNULL(src.IsOrderByColumn,0)
    OR ISNULL(tgt.OrderByColumnSequence, -99999) <> ISNULL(src.OrderByColumnSequence, -99999)
    OR ISNULL(tgt.OrderingFactor,'')        <> ISNULL(src.OrderingFactor,'')
    OR ISNULL(tgt.IsSCDColumn,0)            <> ISNULL(src.IsSCDColumn,0)
    OR ISNULL(tgt.IsCountryCode,0)          <> ISNULL(src.IsCountryCode,0)
) THEN
    UPDATE SET
        DatasetFieldType = src.DatasetFieldType,
        DatasetScale = src.DatasetScale,
        DatasetPrecision = src.DatasetPrecision,
        IsKey = src.IsKey,
        IsOrderByColumn = src.IsOrderByColumn,
        OrderByColumnSequence = src.OrderByColumnSequence,
        OrderingFactor = src.OrderingFactor,
        IsSCDColumn = src.IsSCDColumn,
        IsCountryCode = src.IsCountryCode,
        RecordUpdatedTimestamp = @Now,
        RecordUpdatedBy = @DeployedBy
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        SourceSystemName, DatasetName, DatasetFieldName, DatasetFieldType,
        DatasetScale, DatasetPrecision, IsKey, IsOrderByColumn, OrderByColumnSequence,
        OrderingFactor, IsSCDColumn, IsCountryCode,
        RecordCreatedTimestamp, RecordCreatedBy
    )
    VALUES (
        src.SourceSystemName, src.DatasetName, src.DatasetFieldName, src.DatasetFieldType,
        src.DatasetScale, src.DatasetPrecision, src.IsKey, src.IsOrderByColumn, src.OrderByColumnSequence,
        src.OrderingFactor, src.IsSCDColumn, src.IsCountryCode,
        @Now, @DeployedBy
    )
OUTPUT $action, inserted.SourceSystemName, inserted.DatasetName, inserted.DatasetFieldName;
GO

-- 5) Cleanup
DROP TABLE IF EXISTS #stg_SourceEntityDef;
GO

-- 6) Quick verification (optional): show inserted rows
SELECT SourceSystemName, DatasetName, DatasetFieldName, DatasetFieldType, IsKey, IsCountryCode
FROM metadata.SourceEntityDefinition
WHERE SourceSystemName = N'Adverity' AND DatasetName = N'customer'
ORDER BY DatasetFieldName;
GO
