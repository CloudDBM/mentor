SELECT
    A.[name] AS [database_name],
    A.recovery_model_desc,
    (SELECT SUM(CAST(size AS NUMERIC(18, 2))) FROM sys.master_files WHERE A.[name] = [name]) AS size_bytes,
    MAX(B.backup_start_date) AS last_backup_date
FROM
    sys.databases A
    LEFT JOIN msdb.dbo.backupset B ON A.[name] = B.[database_name]
WHERE
    (B.backup_set_id IS NULL OR DATEDIFF(DAY, B.backup_start_date, GETDATE()) >= 0)
    AND A.[name] NOT IN ('tempdb', 'model')
GROUP BY
    A.[name],
    A.recovery_model_desc
ORDER BY
	last_backup_date