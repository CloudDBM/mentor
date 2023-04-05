/*
Listando queries mais consumidoras que geram grande consumo de cpu, memória e disco, 
estas que ocasionam possíveis problemas de performance, que uma vez identificadas deve-se realizar o tunning ou 
avaliar uma melhora no hardware
*/


USE MASTER
SELECT TOP 10 DATABASENAME       = DB_NAME(QP.DBID),
       SUBSTRING(QT.TEXT, (QS.STATEMENT_START_OFFSET/2)+1,
                    ((CASE QS.STATEMENT_END_OFFSET
                        WHEN -1 THEN DATALENGTH(QT.TEXT)
                        ELSE QS.STATEMENT_END_OFFSET
                       END - QS.STATEMENT_START_OFFSET
                      )/2
                    )+1
                ) SENTENCA,
       QS.EXECUTION_COUNT,
       QS.TOTAL_LOGICAL_READS, QS.LAST_LOGICAL_READS,
       QS.TOTAL_LOGICAL_WRITES, QS.LAST_LOGICAL_WRITES,
       QS.TOTAL_WORKER_TIME,
       QS.LAST_WORKER_TIME,
       QS.TOTAL_ELAPSED_TIME/1000000 TOTAL_ELAPSED_TIME_IN_S,
       QS.LAST_ELAPSED_TIME/1000000 LAST_ELAPSED_TIME_IN_S,
       QS.LAST_EXECUTION_TIME/*,
       QP.QUERY_PLAN,
       QS.sql_handle,QS.statement_start_offset,QS.statement_end_offset,QS.plan_generation_num,QS.plan_handle,QS.creation_time,QS.last_execution_time,QS.execution_count,QS.total_worker_time,QS.last_worker_time,QS.min_worker_time,QS.max_worker_time,
       QS.total_physical_reads,QS.last_physical_reads,QS.min_physical_reads,QS.max_physical_reads,QS.total_logical_writes,QS.last_logical_writes,QS.min_logical_writes,QS.max_logical_writes,QS.total_logical_reads,QS.last_logical_reads,QS.min_logical_reads,
       QS.max_logical_reads,QS.total_clr_time,QS.last_clr_time,QS.min_clr_time,QS.max_clr_time,QS.total_elapsed_time,QS.last_elapsed_time,QS.min_elapsed_time,QS.max_elapsed_time,QS.query_hash,QS.query_plan_hash,QS.total_rows,QS.last_rows,QS.min_rows,QS.max_rows,
       QS.statement_sql_handle,QS.statement_context_id,QS.total_dop,QS.last_dop,QS.min_dop,QS.max_dop,QS.total_grant_kb,QS.last_grant_kb,QS.min_grant_kb,QS.max_grant_kb,QS.total_used_grant_kb,QS.last_used_grant_kb,QS.min_used_grant_kb,QS.max_used_grant_kb,
       QS.total_ideal_grant_kb,QS.last_ideal_grant_kb,QS.min_ideal_grant_kb,QS.max_ideal_grant_kb,QS.total_reserved_threads,QS.last_reserved_threads,QS.min_reserved_threads,QS.max_reserved_threads,QS.total_used_threads,QS.last_used_threads,QS.min_used_threads,
       QS.max_used_threads,QS.total_columnstore_segment_reads,QS.last_columnstore_segment_reads,QS.min_columnstore_segment_reads,QS.max_columnstore_segment_reads,QS.total_columnstore_segment_skips,QS.last_columnstore_segment_skips,QS.min_columnstore_segment_skips,
       QS.max_columnstore_segment_skips,QS.total_spills,QS.last_spills,QS.min_spills,QS.max_spills,QS.total_num_physical_reads,QS.last_num_physical_reads,QS.min_num_physical_reads,QS.max_num_physical_reads,QS.total_page_server_reads,QS.last_page_server_reads,
       QS.min_page_server_reads,QS.max_page_server_reads,QS.total_num_page_server_reads,QS.last_num_page_server_reads,QS.min_num_page_server_reads,QS.max_num_page_server_reads
       */
FROM SYS.DM_EXEC_QUERY_STATS QS
     CROSS APPLY SYS.DM_EXEC_SQL_TEXT(QS.SQL_HANDLE) QT
     CROSS APPLY SYS.DM_EXEC_QUERY_PLAN(QS.PLAN_HANDLE) QP
ORDER BY QS.TOTAL_WORKER_TIME DESC