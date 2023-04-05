-- Lista fragmentação das tabelas

SELECT a.index_id, name, avg_fragmentation_in_percent

FROM sys.dm_db_index_physical_stats (DB_ID(DB_NAME()),

OBJECT_ID(N'dbo.FLAN'), NULL, NULL, NULL) AS a

JOIN sys.indexes AS b ON a.object_id = b.object_id AND a.index_id =

b.index_id

--WHERE name LIKE ''

ORDER BY avg_fragmentation_in_percent DESC;