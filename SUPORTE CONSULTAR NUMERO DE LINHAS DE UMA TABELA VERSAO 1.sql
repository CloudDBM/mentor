SELECT COUNT(1) FROM aluno

-- very fast but not accurate

SELECT rows FROM sys.sysindexes WHERE id = OBJECT_ID ('aluno') AND indid < 2

-- The way the SSMS counts rows (look at table properties > storage > row count). 
-- Very fast, but still an approximate number of rows.

SELECT CAST (p.rows AS float)
FROM sys.tables AS tbl
INNER JOIN sys.indexes AS idx ON idx.object_id = tbl.object_id and idx.index_id < 2
INNER JOIN sys.partitions AS p ON p.object_id=CAST(tbl.object_id AS int)
AND p.index_id=idx.index_id
WHERE ((tbl.name=N'aluno'
AND SCHEMA_NAME(tbl.schema_id)='dbo'))

-- accurate but not so fast
SELECT SUM (row_count)
FROM sys.dm_db_partition_stats
WHERE object_id=OBJECT_ID('aluno')   
AND (index_id = 0 or index_id = 1);
