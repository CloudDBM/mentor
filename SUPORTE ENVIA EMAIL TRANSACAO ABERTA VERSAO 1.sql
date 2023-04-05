DROP TABLE IF EXISTS #TEMPORARIA

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
A.transaction_isolation_level,
A.lock_timeout,
A.deadlock_priority,
A.row_count,
C.text
INTO #TEMPORARIA
FROM 
sys.dm_exec_sessions			A	WITH(NOLOCK)
JOIN sys.dm_exec_connections		B	WITH(NOLOCK)	ON	A.session_id = B.session_id
CROSS APPLY sys.dm_exec_sql_text(most_recent_sql_handle)	C
WHERE 
EXISTS (SELECT * FROM sys.dm_tran_session_transactions AS t WITH(NOLOCK) WHERE t.session_id = A.session_id)
AND NOT EXISTS (SELECT * FROM sys.dm_exec_requests AS r WITH(NOLOCK) WHERE r.session_id = A.session_id)
ORDER BY last_request_start_time 
OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY  

DECLARE @HORA_TRANSACAO_ABERTA DATETIME

DECLARE @TEMPO_TRANSACAO_ABERTA_SEGUNDOS INT, @ID_TRANSACAO VARCHAR(10);

DECLARE @SQL NVARCHAR(1000)

SELECT @HORA_TRANSACAO_ABERTA = last_request_start_time FROM #TEMPORARIA

SELECT @ID_TRANSACAO = session_id FROM #TEMPORARIA

SELECT @TEMPO_TRANSACAO_ABERTA_SEGUNDOS = DATEDIFF(SECOND, @HORA_TRANSACAO_ABERTA, GETDATE())

IF @TEMPO_TRANSACAO_ABERTA_SEGUNDOS >= 0 -- COLOCAR TEMPO MÍNIMO EM SEGUNDOS PARA ENVIAR E-MAIL DA TRANSAÇÃO ABERTA
BEGIN

SET @SQL = 'KILL ' + CAST(@ID_TRANSACAO as varchar(4))

EXEC (@SQL)

EXEC msdb.dbo.sp_send_dbmail @body = N'KILL @ID_TRANSACAO ABERTA EM @HORA_TRANSACAO_ABERTA - AFYA'
        ,@body_format = 'TEXT'
        ,@profile_name = N'monitorclouddb@gmail.com' 
        ,@recipients = N'monitoramento@clouddbm.com'
        ,@Subject = N'KILL @ID_TRANSACAO ABERTA EM @HORA_TRANSACAO_ABERTA - AFYA' 

END

--EXECUTE msdb.dbo.sysmail_help_profile_sp;