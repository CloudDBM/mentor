SELECT
    B.[name] AS table_name,
    idx.[name] AS clustered_index,
    nc.nonclusteredname AS best_non_clustered,
    c.user_seeks AS clustered_user_seeks,
    nc.user_seeks AS nonclustered_user_seeks,
    c.user_lookups AS clustered_user_lookups
FROM
    sys.indexes idx
    JOIN sys.objects B ON idx.[object_id] = B.[object_id]
    LEFT JOIN sys.dm_db_index_usage_stats c ON idx.[object_id] = c.[object_id] AND idx.index_id = c.index_id AND c.database_id = DB_ID()
    JOIN (
           SELECT
                idx.[object_id],
                idx.[name] AS nonclusteredname,
                ius.user_seeks
           FROM
                sys.indexes idx
                JOIN sys.dm_db_index_usage_stats ius ON idx.[object_id] = ius.[object_id] AND idx.index_id = ius.index_id
           WHERE
                idx.[type_desc] = 'nonclustered' 
                AND ius.user_seeks = ( SELECT MAX(user_seeks) FROM sys.dm_db_index_usage_stats WHERE [object_id] = ius.[object_id] AND [type_desc] = 'nonclustered' AND database_id = DB_ID() )
                AND ius.database_id = DB_ID()
           GROUP BY
                idx.[object_id],
                idx.[name],
                ius.user_seeks
         ) nc ON nc.[object_id] = idx.[object_id]
WHERE
    idx.[type_desc] IN ( 'clustered', 'heap' )
    AND nc.user_seeks > ( c.user_seeks * 1.50 ) -- 150%
    AND nc.user_seeks >= ( c.user_lookups * 0.75 ) -- 75%
ORDER BY
    nc.user_seeks DESC