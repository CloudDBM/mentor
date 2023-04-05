SELECT
    F.session_id,
    A.job_id,
    C.name AS job_name,
    F.login_name,
    F.[host_name],
    F.[program_name],
    A.start_execution_date,
    CONVERT(VARCHAR, CONVERT(VARCHAR, DATEADD(ms, ( DATEDIFF(SECOND, A.start_execution_date, GETDATE()) % 86400 ) * 1000, 0), 114)) AS time_elapsed,
    ISNULL(A.last_executed_step_id, 0) + 1 AS current_executed_step_id,
    D.step_name,
    H.[text]
FROM
    msdb.dbo.sysjobactivity                     A   WITH(NOLOCK)
    LEFT JOIN msdb.dbo.sysjobhistory            B   WITH(NOLOCK)    ON A.job_history_id = B.instance_id
    JOIN msdb.dbo.sysjobs                       C   WITH(NOLOCK)    ON A.job_id = C.job_id
    JOIN msdb.dbo.sysjobsteps                   D   WITH(NOLOCK)    ON A.job_id = D.job_id AND ISNULL(A.last_executed_step_id, 0) + 1 = D.step_id
    JOIN (
        SELECT CAST(CONVERT( BINARY(16), SUBSTRING([program_name], 30, 34), 1) AS UNIQUEIDENTIFIER) AS job_id, MAX(login_time) login_time
        FROM sys.dm_exec_sessions WITH(NOLOCK)
        WHERE [program_name] LIKE 'SQLAgent - TSQL JobStep (Job % : Step %)'
        GROUP BY CAST(CONVERT( BINARY(16), SUBSTRING([program_name], 30, 34), 1) AS UNIQUEIDENTIFIER)
    )                                           E                   ON C.job_id = E.job_id
    LEFT JOIN sys.dm_exec_sessions              F   WITH(NOLOCK)    ON E.job_id = (CASE WHEN BINARY_CHECKSUM(SUBSTRING(F.[program_name], 30, 34)) > 0 THEN CAST(TRY_CONVERT( BINARY(16), SUBSTRING(F.[program_name], 30, 34), 1) AS UNIQUEIDENTIFIER) ELSE NULL END) AND E.login_time = F.login_time
    LEFT JOIN sys.dm_exec_connections           G   WITH(NOLOCK)    ON F.session_id = G.session_id
    OUTER APPLY sys.dm_exec_sql_text(most_recent_sql_handle) H
WHERE
    A.session_id = ( SELECT TOP 1 session_id FROM msdb.dbo.syssessions	WITH(NOLOCK) ORDER BY agent_start_date DESC ) 
    AND A.start_execution_date IS NOT NULL 
    AND A.stop_execution_date IS NULL