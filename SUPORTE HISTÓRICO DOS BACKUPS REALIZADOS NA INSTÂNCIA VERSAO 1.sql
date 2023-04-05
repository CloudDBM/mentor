SELECT
    B.[database_name],
    (CASE B.[type]
        WHEN 'D' THEN 'Full Backup'
        WHEN 'I' THEN 'Differential Backup'
        WHEN 'L' THEN 'TLog Backup'
        WHEN 'F' THEN 'File or filegroup'
        WHEN 'G' THEN 'Differential file'
        WHEN 'P' THEN 'Partial'
        WHEN 'Q' THEN 'Differential Partial'
    END) AS BackupType,
    B.recovery_model AS RecoveryModel,
    B.backup_start_date,
    B.backup_finish_date,
    CAST(DATEDIFF(SECOND,B.backup_start_date, B.backup_finish_date) AS VARCHAR(4)) + ' ' + 'Seconds' AS TotalTimeTaken,
    B.expiration_date,
    B.[user_name],
    B.machine_name,
    B.is_password_protected,
    B.collation_name,
    B.is_copy_only,
    CONVERT(NUMERIC(20, 2), B.backup_size / 1048576) AS BackupSizeMB,
    A.logical_device_name,
    A.physical_device_name,
    B.[name] AS backupset_name,
    B.[description],
    B.has_backup_checksums,
    B.is_damaged,
    B.has_incomplete_metadata
FROM
    sys.databases X
    JOIN msdb.dbo.backupset B ON X.[name] = B.[database_name]
    JOIN msdb.dbo.backupmediafamily A ON A.media_set_id = B.media_set_id
WHERE
    B.backup_start_date >= CONVERT(DATE, DATEADD(DAY, -7, GETDATE()))