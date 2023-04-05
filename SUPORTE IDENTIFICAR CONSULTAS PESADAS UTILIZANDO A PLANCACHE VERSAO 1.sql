SELECT TOP(100)
    DB_NAME(C.[dbid]) as [database],
    B.[text],
    (SELECT CAST(SUBSTRING(B.[text], (A.statement_start_offset/2)+1,   
        (((CASE A.statement_end_offset  
            WHEN -1 THEN DATALENGTH(B.[text]) 
            ELSE A.statement_end_offset  
        END) - A.statement_start_offset)/2) + 1) AS NVARCHAR(MAX)) FOR XML PATH(''), TYPE) AS [TSQL],
    C.query_plan,

    A.last_execution_time,
    A.execution_count,
 
    A.total_elapsed_time / 1000 AS total_elapsed_time_ms,
    A.last_elapsed_time / 1000 AS last_elapsed_time_ms,
    A.min_elapsed_time / 1000 AS min_elapsed_time_ms,
    A.max_elapsed_time / 1000 AS max_elapsed_time_ms,
    ((A.total_elapsed_time / A.execution_count) / 1000) AS avg_elapsed_time_ms,
 
    A.total_worker_time / 1000 AS total_worker_time_ms,
    A.last_worker_time / 1000 AS last_worker_time_ms,
    A.min_worker_time / 1000 AS min_worker_time_ms,
    A.max_worker_time / 1000 AS max_worker_time_ms,
    ((A.total_worker_time / a.execution_count) / 1000) AS avg_worker_time_ms,
   
    A.total_physical_reads,
    A.last_physical_reads,
    A.min_physical_reads,
    A.max_physical_reads,
   
    A.total_logical_reads,
    A.last_logical_reads,
    A.min_logical_reads,
    A.max_logical_reads,
   
    A.total_logical_writes,
    A.last_logical_writes,
    A.min_logical_writes,
    A.max_logical_writes
FROM
    sys.dm_exec_query_stats A
    CROSS APPLY sys.dm_exec_sql_text(A.[sql_handle]) B
    OUTER APPLY sys.dm_exec_query_plan (A.plan_handle) AS C
ORDER BY
    A.total_elapsed_time DESC