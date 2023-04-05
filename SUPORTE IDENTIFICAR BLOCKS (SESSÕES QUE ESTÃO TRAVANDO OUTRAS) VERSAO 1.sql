DECLARE @Monitoramento_Locks TABLE
(
    [nested_level] INT,
    [session_id] SMALLINT,
    [wait_info] NVARCHAR(4000),
    [wait_time_ms] BIGINT,
    [blocking_session_id] SMALLINT,
    [blocked_session_count] INT,
    [open_transaction_count] INT,
    [sql_text] XML,
    [sql_command] XML,
    [total_elapsed_time] INT,
    [deadlock_priority] INT,
    [transaction_isolation_level] VARCHAR(50),
    [last_request_start_time] DATETIME,
    [login_name] NVARCHAR(128),
    [nt_user_name] NVARCHAR(128),
    [original_login_name] NVARCHAR(128),
    [host_name] NVARCHAR(128),
    [program_name] NVARCHAR(128)
)

INSERT INTO @Monitoramento_Locks
SELECT
    NULL AS nested_level,
    A.session_id AS session_id,
    '(' + CAST(COALESCE(E.wait_duration_ms, B.wait_time) AS VARCHAR(20)) + 'ms)' + COALESCE(E.wait_type, B.wait_type) + COALESCE((CASE 
        WHEN COALESCE(E.wait_type, B.wait_type) LIKE 'PAGE%LATCH%' THEN ':' + DB_NAME(LEFT(E.resource_description, CHARINDEX(':', E.resource_description) - 1)) + ':' + SUBSTRING(E.resource_description, CHARINDEX(':', E.resource_description) + 1, 999)
        WHEN COALESCE(E.wait_type, B.wait_type) = 'OLEDB' THEN '[' + REPLACE(REPLACE(E.resource_description, ' (SPID=', ':'), ')', '') + ']'
        ELSE ''
    END), '') AS wait_info,
    COALESCE(E.wait_duration_ms, B.wait_time) AS wait_time_ms,
    NULLIF(B.blocking_session_id, 0) AS blocking_session_id,
    COALESCE(F.blocked_session_count, 0) AS blocked_session_count,
    A.open_transaction_count,
    CAST('<?query --' + CHAR(10) + (
    SELECT TOP 1 SUBSTRING(X.[text], B.statement_start_offset / 2 + 1, ((CASE
                                                                        WHEN B.statement_end_offset = -1 THEN (LEN(CONVERT(NVARCHAR(MAX), X.[text])) * 2)
                                                                        ELSE B.statement_end_offset
                                                                    END
                                                                    ) - B.statement_start_offset
                                                                ) / 2 + 1
                    )
    ) + CHAR(10) + '--?>' AS XML) AS sql_text,
    CAST('<?query --' + CHAR(10) + X.[text] + CHAR(10) + '--?>' AS XML) AS sql_command,
    A.total_elapsed_time,
    A.[deadlock_priority],
    (CASE B.transaction_isolation_level
        WHEN 0 THEN 'Unspecified' 
        WHEN 1 THEN 'ReadUncommitted' 
        WHEN 2 THEN 'ReadCommitted' 
        WHEN 3 THEN 'Repeatable' 
        WHEN 4 THEN 'Serializable' 
        WHEN 5 THEN 'Snapshot'
    END) AS transaction_isolation_level,
    A.last_request_start_time,
    A.login_name,
    A.nt_user_name,
    A.original_login_name,
    A.[host_name],
    (CASE WHEN D.name IS NOT NULL THEN 'SQLAgent - TSQL Job (' + D.[name] + ' - ' + SUBSTRING(A.[program_name], 67, LEN(A.[program_name]) - 67) +  ')' ELSE A.[program_name] END) AS [program_name]
FROM
    sys.dm_exec_sessions AS A WITH (NOLOCK)
    LEFT JOIN sys.dm_exec_requests AS B WITH (NOLOCK) ON A.session_id = B.session_id
    LEFT JOIN msdb.dbo.sysjobs AS D ON RIGHT(D.job_id, 10) = RIGHT(SUBSTRING(A.[program_name], 30, 34), 10)
    LEFT JOIN (
        SELECT
            session_id, 
            wait_type,
            wait_duration_ms,
            resource_description,
            ROW_NUMBER() OVER(PARTITION BY session_id ORDER BY (CASE WHEN wait_type LIKE 'PAGE%LATCH%' THEN 0 ELSE 1 END), wait_duration_ms) AS Ranking
        FROM 
            sys.dm_os_waiting_tasks
    ) E ON A.session_id = E.session_id AND E.Ranking = 1
    LEFT JOIN (
        SELECT
            blocking_session_id,
            COUNT(*) AS blocked_session_count
        FROM
            sys.dm_exec_requests
        WHERE
            blocking_session_id <> 0
        GROUP BY
            blocking_session_id
    ) F ON A.session_id = F.blocking_session_id
    LEFT JOIN sys.sysprocesses AS G WITH(NOLOCK) ON A.session_id = G.spid
    OUTER APPLY sys.dm_exec_sql_text(COALESCE(B.[sql_handle], G.[sql_handle])) AS X
WHERE
    A.session_id > 50
    AND A.session_id <> @@SPID
    AND (
        (NULLIF(B.blocking_session_id, 0) IS NOT NULL OR COALESCE(F.blocked_session_count, 0) > 0)
        OR (A.session_id IN (SELECT NULLIF(blocking_session_id, 0) FROM sys.dm_exec_requests))
    )


------------------------------------------------
-- Gera o nível dos locks
------------------------------------------------

UPDATE @Monitoramento_Locks
SET nested_level = 1
WHERE blocking_session_id IS NULL


DECLARE @Contador INT = 2

WHILE(EXISTS(SELECT NULL FROM @Monitoramento_Locks WHERE nested_level IS NULL) AND @Contador < 50)
BEGIN
        

    UPDATE A
    SET 
        A.nested_level = @Contador
    FROM 
        @Monitoramento_Locks A
        JOIN @Monitoramento_Locks B ON A.blocking_session_id = B.session_id
    WHERE 
        A.nested_level IS NULL
        AND B.nested_level = (@Contador - 1)


    SET @Contador += 1


END


UPDATE @Monitoramento_Locks
SET nested_level = @Contador
WHERE nested_level IS NULL


SELECT * 
FROM @Monitoramento_Locks
ORDER BY nested_level, blocked_session_count DESC, blocking_session_id, wait_time_ms DESC