SELECT
    A.[restore_history_id],
    A.[restore_date],
    A.[destination_database_name],
    C.physical_device_name,
    A.[user_name],
    A.[backup_set_id],
    CASE A.[restore_type]
        WHEN 'D' THEN 'Database'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        WHEN 'F' THEN 'File'
        WHEN 'G' THEN 'Filegroup'
        WHEN 'V' THEN 'Verifyonlyl'
    END AS RestoreType,
    A.[replace],
    A.[recovery],
    A.[restart],
    A.[stop_at],
    A.[device_count],
    A.[stop_at_mark_name],
    A.[stop_before]
FROM
    [msdb].[dbo].[restorehistory] A
    JOIN [msdb].[dbo].[backupset] B ON A.backup_set_id = B.backup_set_id
    JOIN msdb.dbo.backupmediafamily C ON B.media_set_id = C.media_set_id
WHERE
    A.restore_date >= CONVERT(DATE, DATEADD(DAY, -7, GETDATE()))