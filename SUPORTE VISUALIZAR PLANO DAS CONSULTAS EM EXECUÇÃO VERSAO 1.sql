SELECT
    B.start_time,
    A.session_id,
    B.command,
    A.login_name,
    A.[host_name],
    A.[program_name],
    B.logical_reads,
    B.cpu_time,
    B.writes,
    B.blocking_session_id,
    C.query_plan
FROM
    sys.dm_exec_sessions AS A WITH (NOLOCK)
    LEFT JOIN sys.dm_exec_requests AS B WITH (NOLOCK) ON A.session_id = B.session_id
    OUTER APPLY sys.dm_exec_query_plan(B.[plan_handle]) AS C
WHERE
    A.session_id > 50
    AND A.session_id <> @@SPID
    AND (A.[status] <> 'sleeping' OR (A.[status] = 'sleeping' AND A.open_transaction_count > 0))
ORDER BY
    B.start_time