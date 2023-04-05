SELECT
    D.[name] + '.' + C.[name] AS ObjectName,
    A.[name] AS IndexName,
    (CASE WHEN A.is_unique = 1 THEN 'UNIQUE ' ELSE '' END) + A.[type_desc] AS IndexType,
    MAX(B.last_user_seek) AS last_user_seek,
    MAX(COALESCE(B.last_user_seek, B.last_user_scan)) AS last_read,
    SUM(B.user_seeks) AS User_Seeks,
    SUM(B.user_scans) AS User_Scans,
    SUM(B.user_seeks) + SUM(B.user_scans) AS User_Reads,
    SUM(B.user_lookups) AS User_Lookups,
    SUM(B.user_updates) AS User_Updates,
    SUM(E.[rows]) AS [row_count],
    CAST(ROUND(((SUM(F.total_pages) * 8) / 1024.00), 2) AS NUMERIC(36, 2)) AS [size_mb],
    CAST(ROUND(((SUM(F.used_pages) * 8) / 1024.00), 2) AS NUMERIC(36, 2)) AS [used_mb], 
    CAST(ROUND(((SUM(F.total_pages) - SUM(F.used_pages)) * 8) / 1024.00, 2) AS NUMERIC(36, 2)) AS [unused_mb]
FROM
    sys.indexes A
    LEFT JOIN sys.dm_db_index_usage_stats B ON A.[object_id] = B.[object_id] AND A.index_id = B.index_id AND B.database_id = DB_ID()
    JOIN sys.objects C ON A.[object_id] = C.[object_id]
    JOIN sys.schemas D ON C.[schema_id] = D.[schema_id]
    JOIN sys.partitions E ON A.[object_id] = E.[object_id] AND A.index_id = E.index_id
    JOIN sys.allocation_units F ON E.[partition_id] = F.container_id
WHERE
    C.is_ms_shipped = 0
GROUP BY
    D.[name] + '.' + C.[name],
    A.[name],
    (CASE WHEN A.is_unique = 1 THEN 'UNIQUE ' ELSE '' END) + A.[type_desc]
ORDER BY
    1, 2