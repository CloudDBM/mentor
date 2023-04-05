/********************************************************************************************* 
Find Key Lookups in Cached Plans v1.00 (2010-07-27) 
(C) 2010, Kendal Van Dyke

Feedback: mailto:kendal.vandyke@gmail.com

License: 
   This query is free to download and use for personal, educational, and internal 
   corporate purposes, provided that this header is preserved. Redistribution or sale 
   of this query, in whole or in part, is prohibited without the author's express 
   written consent. 
   
Note: 
   Exercise caution when running this in production!

   The function sys.dm_exec_query_plan() is resource intensive and can put strain 
   on a server when used to retrieve all cached query plans.

   Consider using TOP in the initial select statement (insert into @plans) 
   to limit the impact of running this query or run during non-peak hours 
*********************************************************************************************/
DECLARE @plans TABLE
(
    query_text NVARCHAR(MAX),
    o_name sysname,
    execution_plan XML,
    last_execution_time DATETIME,
    execution_count BIGINT,
    total_worker_time BIGINT,
    total_physical_reads BIGINT,
    total_logical_reads BIGINT
);

DECLARE @lookups TABLE
(
    table_name sysname,
    index_name sysname,
    index_cols NVARCHAR(MAX)
);

WITH query_stats
AS ( 
    SELECT
         [sql_handle],
         [plan_handle],
         MAX(last_execution_time) AS last_execution_time,
         SUM(execution_count) AS execution_count,
         SUM(total_worker_time) AS total_worker_time,
         SUM(total_physical_reads) AS total_physical_reads,
         SUM(total_logical_reads) AS total_logical_reads
     FROM
         sys.dm_exec_query_stats
     GROUP BY
         [sql_handle],
         [plan_handle] 
)
INSERT INTO @plans
(
    query_text,
    o_name,
    execution_plan,
    last_execution_time,
    execution_count,
    total_worker_time,
    total_physical_reads,
    total_logical_reads
)
SELECT /*TOP 50*/
    sql_text.[text],
    CASE
        WHEN sql_text.objectid IS NOT NULL THEN ISNULL(OBJECT_NAME(sql_text.objectid, sql_text.[dbid]), 'Unresolved')
        ELSE CAST('Ad-hoc\Prepared' AS sysname)
    END,
    query_plan.query_plan,
    query_stats.last_execution_time,
    query_stats.execution_count,
    query_stats.total_worker_time,
    query_stats.total_physical_reads,
    query_stats.total_logical_reads
FROM
    query_stats
    CROSS APPLY sys.dm_exec_sql_text(query_stats.sql_handle) AS [sql_text]
    CROSS APPLY sys.dm_exec_query_plan(query_stats.plan_handle) AS [query_plan]
WHERE
    query_plan.query_plan IS NOT NULL;

;WITH XMLNAMESPACES
 (
     DEFAULT 'http://schemas.microsoft.com/sqlserver/2004/07/showplan'
 )
, lookups
AS ( SELECT
         DB_ID(REPLACE(REPLACE(keylookups.keylookup.value('(Object/@Database)[1]', 'sysname'), '[', ''), ']', '')) AS [database_id],
         OBJECT_ID(keylookups.keylookup.value('(Object/@Database)[1]', 'sysname') + '.' + keylookups.keylookup.value('(Object/@Schema)[1]', 'sysname') + '.' + keylookups.keylookup.value('(Object/@Table)[1]', 'sysname')) AS [object_id],
         keylookups.keylookup.value('(Object/@Database)[1]', 'sysname') AS [database],
         keylookups.keylookup.value('(Object/@Schema)[1]', 'sysname') AS [schema],
         keylookups.keylookup.value('(Object/@Table)[1]', 'sysname') AS [table],
         keylookups.keylookup.value('(Object/@Index)[1]', 'sysname') AS [index],
         REPLACE(keylookups.keylookup.query(' 
for $column in DefinedValues/DefinedValue/ColumnReference 
return string($column/@Column) 
').value('.', 'varchar(max)'), ' ', ', ') AS [columns],
         plans.query_text,
         plans.o_name,
         plans.execution_plan,
         plans.last_execution_time,
         plans.execution_count,
         plans.total_worker_time,
         plans.total_physical_reads,
         plans.total_logical_reads
     FROM
         @plans AS [plans]
         CROSS APPLY execution_plan.nodes('//RelOp/IndexScan[@Lookup="1"]') AS keylookups(keylookup) )
SELECT
    lookups.[database],
    lookups.[schema],
    lookups.[table],
    lookups.[index],
    lookups.[columns],
    index_stats.user_lookups,
    index_stats.last_user_lookup,
    lookups.execution_count,
    lookups.total_worker_time,
    lookups.total_physical_reads,
    lookups.total_logical_reads,
    lookups.last_execution_time,
    lookups.o_name AS [object_name],
    lookups.query_text,
    lookups.execution_plan
FROM
    lookups
    INNER JOIN sys.dm_db_index_usage_stats AS [index_stats] ON lookups.database_id = index_stats.database_id
                                                               AND lookups.[object_id] = index_stats.[object_id]
WHERE
    index_stats.user_lookups > 0
    AND lookups.[database] NOT IN ( '[master]', '[model]', '[msdb]', '[tempdb]' )
ORDER BY
    index_stats.user_lookups DESC,
    lookups.total_physical_reads DESC,
    lookups.total_logical_reads DESC