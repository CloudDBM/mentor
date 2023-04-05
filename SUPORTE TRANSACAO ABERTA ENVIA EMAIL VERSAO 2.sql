DROP TABLE IF EXISTS #TRANSACAO_ABERTA_V2

CREATE TABLE #TRANSACAO_ABERTA_V2(
	session_id INT,
	login_time DATETIME,
	host_name VARCHAR(MAX),
	program_name VARCHAR(MAX),
	login_name VARCHAR(MAX),
	status VARCHAR(MAX),
	cpu_time INT,
	memory_usage INT,
	last_request_start_time DATETIME,
	last_request_end_time DATETIME,
	duration DATETIME,
	transaction_isolation_level INT,
	lock_timeout INT,
	deadlock_priority INT,
	row_count BIGINT,
	text VARCHAR(MAX)
)

INSERT INTO #TRANSACAO_ABERTA_V2
SELECT
	A.session_id,
	A.login_time,
	A.host_name,
	A.program_name,
	A.login_name,
	A.status,
	A.cpu_time,
	A.memory_usage,
	A.last_request_start_time,
	A.last_request_end_time,
	DATEDIFF(SECOND, A.last_request_end_time, A.last_request_start_time) AS duration,
	A.transaction_isolation_level,
	A.lock_timeout,
	A.deadlock_priority,
	A.row_count,
	C.text
FROM 
	sys.dm_exec_sessions										A	WITH(NOLOCK)
	JOIN sys.dm_exec_connections								B	WITH(NOLOCK) ON	A.session_id = B.session_id
	CROSS APPLY sys.dm_exec_sql_text(most_recent_sql_handle)	C
WHERE 
	EXISTS (SELECT * FROM sys.dm_tran_session_transactions AS t WITH(NOLOCK) WHERE t.session_id = A.session_id)
	AND NOT EXISTS (SELECT * FROM sys.dm_exec_requests AS r WITH(NOLOCK) WHERE r.session_id = A.session_id)
ORDER BY 
	last_request_start_time 



 -- CONFERE 
 -- select * from #TRANSACAO_ABERTA_V2

DECLARE @cat varchar(MAX)

SELECT
	@cat = COALESCE(@cat + '', '')
	+ '<tr><td>'
    + CAST(ISNULL(session_id,'NULL') AS varchar) + '</td><td>'
    + CAST(ISNULL(login_time,'NULL') AS varchar) + '</td><td>'
    + CAST(ISNULL(host_name,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(program_name,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(login_name,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(cpu_time,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(memory_usage,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(last_request_start_time,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(last_request_end_time,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(duration,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(transaction_isolation_level,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(lock_timeout,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(deadlock_priority,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(row_count,'NULL') AS varchar) + '</td><tr>'
	+ CAST(ISNULL(text,'NULL') AS varchar) + '</td><tr>'				 
FROM #TRANSACAO_ABERTA_V2

SET @cat = '
<table border="1">
<thead>
<th>EventType</th>
<th>Parameters</th>
<th>EventInfo</th>
</thead>
<tbody>

	' + @cat + '
</tbody>
</table>'

EXEC msdb.dbo.sp_send_dbmail 
	@body_format = 'TEXT'
	,@body = @cat
    ,@profile_name = N'DBA' 
    ,@recipients = N'monitoramento@clouddbm.com'
    ,@Subject = N'KILL @ID_TRANSACAO ABERTA EM @HORA_TRANSACAO_ABERTA - AFYA' 
END

--EXECUTE msdb.dbo.sysmail_help_profile_sp;