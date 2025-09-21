/* =========================================================================
   DML for ConnectionDetails
   Using temp table + MERGE pattern
   ========================================================================= */

-- Drop temp if exists
IF OBJECT_ID('tempdb..#udpConnectionDetails') IS NOT NULL
    DROP TABLE #udpConnectionDetails;

-- Create temp staging table
CREATE TABLE #udpConnectionDetails (
    SourceConnectionName NVARCHAR(255) NOT NULL,
    SourceType NVARCHAR(100) NOT NULL,
    ConnectionDesc NVARCHAR(500) NULL,
    IsActive BIT NOT NULL,
    StorageAccountName NVARCHAR(255) NULL,
    StorageContainerName NVARCHAR(255) NULL,
    ServicePrincipalId NVARCHAR(255) NULL,
    ServicePrincipalSecretKVName NVARCHAR(255) NULL
);

-- Insert connection metadata rows
INSERT INTO #udpConnectionDetails
SELECT 
    N'azure_blob',                -- SourceConnectionName
    N'Blob',                      -- SourceType
    N'to extract data from azure blob to azure adls gen 2', -- ConnectionDesc
    1,                            -- IsActive (1 = yes, 0 = no)
    N'datafoundationblob',        -- StorageAccountName
    N'adverity-data',             -- StorageContainerName
    N'30f404d0-9d3b-4cf3-93f7-c0aae7f42ff1',        -- ServicePrincipalId
    N'datafoundation-blob-access-secret'       -- Secret in Key Vault
;

-- MERGE into real table
MERGE metadata.ConnectionDetails AS tgt
USING #udpConnectionDetails AS src
    ON tgt.SourceConnectionName = src.SourceConnectionName
WHEN MATCHED THEN
    UPDATE SET
        SourceType = src.SourceType,
        ConnectionDesc = src.ConnectionDesc,
        IsActive = src.IsActive,
        StorageAccountName = src.StorageAccountName,
        StorageContainerName = src.StorageContainerName,
        ServicePrincipalId = src.ServicePrincipalId,
        ServicePrincipalSecretKVName = src.ServicePrincipalSecretKVName,
        RecordUpdatedTimestamp = SYSUTCDATETIME(),
        RecordUpdatedBy = N'Shilpashree SR'
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        SourceConnectionName, SourceType, ConnectionDesc, IsActive,
        StorageAccountName, StorageContainerName, ServicePrincipalId, ServicePrincipalSecretKVName,
        RecordCreatedTimestamp, RecordCreatedBy
    )
    VALUES (
        src.SourceConnectionName, src.SourceType, src.ConnectionDesc, src.IsActive,
        src.StorageAccountName, src.StorageContainerName, src.ServicePrincipalId, src.ServicePrincipalSecretKVName,
        SYSUTCDATETIME(), N'Shilpashree SR'
    )
OUTPUT $action, inserted.SourceConnectionName;
GO

-- Drop temp table
DROP TABLE #udpConnectionDetails;
GO

