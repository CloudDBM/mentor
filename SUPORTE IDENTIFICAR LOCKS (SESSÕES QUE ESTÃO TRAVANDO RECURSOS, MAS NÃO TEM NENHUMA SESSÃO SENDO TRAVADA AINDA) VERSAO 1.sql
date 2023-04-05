SELECT
    A.request_session_id AS session_id,
    COALESCE(G.start_time, F.last_request_start_time) AS start_time,
    COALESCE(G.open_transaction_count, F.open_transaction_count) AS open_transaction_count,
    A.resource_database_id,
    DB_NAME(A.resource_database_id) AS dbname,
    (CASE WHEN A.resource_type = 'OBJECT' THEN D.[name] ELSE E.[name] END) AS ObjectName,
    (CASE WHEN A.resource_type = 'OBJECT' THEN D.is_ms_shipped ELSE E.is_ms_shipped END) AS is_ms_shipped,
    --B.index_id,
    --C.[name] AS index_name,
    --A.resource_type,
    --A.resource_description,
    --A.resource_associated_entity_id,
    A.request_mode,
    A.request_status,
    F.login_name,
    F.[program_name],
    F.[host_name],
    G.blocking_session_id
FROM
    sys.dm_tran_locks A WITH(NOLOCK)
    LEFT JOIN sys.partitions B WITH(NOLOCK) ON B.hobt_id = A.resource_associated_entity_id
    LEFT JOIN sys.indexes C WITH(NOLOCK) ON C.[object_id] = B.[object_id] AND C.index_id = B.index_id
    LEFT JOIN sys.objects D WITH(NOLOCK) ON A.resource_associated_entity_id = D.[object_id]
    LEFT JOIN sys.objects E WITH(NOLOCK) ON B.[object_id] = E.[object_id]
    LEFT JOIN sys.dm_exec_sessions F WITH(NOLOCK) ON A.request_session_id = F.session_id
    LEFT JOIN sys.dm_exec_requests G WITH(NOLOCK) ON A.request_session_id = G.session_id
WHERE
    A.resource_associated_entity_id > 0
    AND A.resource_database_id = DB_ID()
    AND A.resource_type = 'OBJECT'
    AND (CASE WHEN A.resource_type = 'OBJECT' THEN D.is_ms_shipped ELSE E.is_ms_shipped END) = 0
ORDER BY
    A.request_session_id,
    A.resource_associated_entity_id