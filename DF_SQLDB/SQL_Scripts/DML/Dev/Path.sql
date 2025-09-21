/* =========================================================================
   DML for metadata.Path
   Using temp table + MERGE pattern
   -------------------------------------------------------------------------
   Author : Shilpashree SR
   Purpose: Define storage paths for dataset ingestion (Raw → Optimized).
   ========================================================================= */

-- 1. Drop temp if exists
IF OBJECT_ID('tempdb..#udpPath') IS NOT NULL
    DROP TABLE #udpPath;

-- 2. Create temp staging table
CREATE TABLE #udpPath (
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
    OptimizedPath NVARCHAR(1024) NOT NULL
);

-- 3. Insert dataset path rows (add more with UNION ALL if needed)
INSERT INTO #udpPath
SELECT 
    N'Adverity', 
    N'customer',
    N'abfss://df-raw@datafoundationblob.dfs.core.windows.net/sap/sales/',               -- Raw
    N'abfss://df-raw-temp@datafoundationblob.dfs.core.windows.net/sap/sales/',          -- Raw Temp
    N'abfss://df-raw-error@datafoundationblob.dfs.core.windows.net/sap/sales/',         -- Raw Error
    N'abfss://df-transformed@datafoundationblob.dfs.core.windows.net/sap/sales/',       -- Transformed
    N'abfss://df-transformed-temp@datafoundationblob.dfs.core.windows.net/sap/sales/',  -- Transformed Temp
    N'abfss://df-transformed-error@datafoundationblob.dfs.core.windows.net/sap/sales/', -- Transformed Error
    N'abfss://df-sanitized@datafoundationblob.dfs.core.windows.net/sap/sales/',         -- Sanitized
    N'abfss://df-sanitized-rejected@datafoundationblob.dfs.core.windows.net/sap/sales/',-- Sanitized Rejected
    N'abfss://df-sanitized-rejected-summary@datafoundationblob.dfs.core.windows.net/sap/sales/', -- Sanitized Rejected Summary
    N'abfss://df-curated@datafoundationblob.dfs.core.windows.net/sap/sales/',           -- Curated
    N'abfss://df-curated-rejected@datafoundationblob.dfs.core.windows.net/sap/sales/',  -- Curated Rejected
    N'abfss://df-optimized@datafoundationblob.dfs.core.windows.net/sap/sales/';         -- Optimized

-- 4. MERGE into target table
MERGE metadata.Path AS tgt
USING #udpPath AS src
    ON tgt.SourceSystemName = src.SourceSystemName
   AND tgt.DatasetName = src.DatasetName
WHEN MATCHED THEN
    UPDATE SET
        RawPath = src.RawPath,
        RawTempPath = src.RawTempPath,
        RawErrorPath = src.RawErrorPath,
        TransformedPath = src.TransformedPath,
        TransformedTempPath = src.TransformedTempPath,
        TransformedErrorPath = src.TransformedErrorPath,
        SanitizedPath = src.SanitizedPath,
        SanitizedRejectedPath = src.SanitizedRejectedPath,
        SanitizedRejectedSummaryPath = src.SanitizedRejectedSummaryPath,
        CuratedPath = src.CuratedPath,
        CuratedRejectedPath = src.CuratedRejectedPath,
        OptimizedPath = src.OptimizedPath,
        RecordUpdatedTimestamp = SYSUTCDATETIME(),
        RecordUpdatedBy = N'Shilpashree SR'
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        SourceSystemName, DatasetName, RawPath, RawTempPath, RawErrorPath,
        TransformedPath, TransformedTempPath, TransformedErrorPath,
        SanitizedPath, SanitizedRejectedPath, SanitizedRejectedSummaryPath,
        CuratedPath, CuratedRejectedPath, OptimizedPath,
        RecordCreatedTimestamp, RecordCreatedBy
    )
    VALUES (
        src.SourceSystemName, src.DatasetName, src.RawPath, src.RawTempPath, src.RawErrorPath,
        src.TransformedPath, src.TransformedTempPath, src.TransformedErrorPath,
        src.SanitizedPath, src.SanitizedRejectedPath, src.SanitizedRejectedSummaryPath,
        src.CuratedPath, src.CuratedRejectedPath, src.OptimizedPath,
        SYSUTCDATETIME(), N'Shilpashree SR'
    )
OUTPUT $action, inserted.SourceSystemName, inserted.DatasetName;
GO

-- 5. Drop temp
DROP TABLE #udpPath;
GO
