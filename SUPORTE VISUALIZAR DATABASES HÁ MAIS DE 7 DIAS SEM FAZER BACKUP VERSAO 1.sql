SELECT
    A.[name] AS [database_name],
    A.recovery_model_desc,
    (SELECT SUM(CAST(size / 128 / 1024.0 AS NUMERIC(18, 2))) FROM sys.master_files WHERE A.[name] = [name]) AS size_GB,
    MAX(B.backup_start_date) AS last_backup_date
FROM
    sys.databases A
    LEFT JOIN msdb.dbo.backupset B ON A.[name] = B.[database_name]
WHERE
    (B.backup_set_id IS NULL OR DATEDIFF(DAY, B.backup_start_date, GETDATE()) > 7)
    AND A.[name] NOT IN ('tempdb', 'model')
GROUP BY
    A.[name],
    A.recovery_model_desc