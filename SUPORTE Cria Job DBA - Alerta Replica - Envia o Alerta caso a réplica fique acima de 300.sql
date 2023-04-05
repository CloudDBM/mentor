USE [msdb]
GO

/****** Object:  Job [DBA - Alerta Replica]    Script Date: 21/01/2022 15:34:42 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 21/01/2022 15:34:42 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBA - Alerta Replica', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'DIRECIONALBH\tr0321', 
		@notify_email_operator_name=N'Monitoramento BD', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [alerta_replica]    Script Date: 21/01/2022 15:34:42 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'alerta_replica', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'Use UAU_DIRECIONAL
go
DECLARE @VALOR INT; -- variável que verifica o valor se está acima do definido

;WITH 
	AG_Stats AS 
			(
			SELECT AR.replica_server_name,
				   HARS.role_desc, 
				   Db_name(DRS.database_id) [DBName], 
				   DRS.last_commit_time
			FROM   sys.dm_hadr_database_replica_states DRS 
			INNER JOIN sys.availability_replicas AR ON DRS.replica_id = AR.replica_id 
			INNER JOIN sys.dm_hadr_availability_replica_states HARS ON AR.group_id = HARS.group_id 
				AND AR.replica_id = HARS.replica_id 
			),
	Pri_CommitTime AS 
			(
			SELECT	replica_server_name
					, DBName
					, last_commit_time
			FROM	AG_Stats
			WHERE	role_desc = ''PRIMARY''
			),
	Sec_CommitTime AS 
			(
			SELECT	replica_server_name
					, DBName
					, last_commit_time
			FROM	AG_Stats
			WHERE	role_desc = ''SECONDARY''
			)
SELECT @VALOR = DATEDIFF(ss,s.last_commit_time,p.last_commit_time)
FROM Pri_CommitTime p
LEFT JOIN Sec_CommitTime s ON [s].[DBName] = [p].[DBName]

IF @VALOR >= 300						-- SE O VALOR FOR MAIOR OU IGUAL A 0 ENVIA A MENSAGEM
BEGIN
	/*print @VALOR*/
	
	EXEC msdb.dbo.sp_send_dbmail @body = ''Contador maior que 300''
	,@body_format = ''HTML''
    ,@profile_name = N''InformacaoTI''				-- INSERE O PROFILE EXISTENTE DO E-MAIL
    ,@recipients = N''monitoramento@clouddbm.com;'' -- EMAIL DO DESTINATÁRIO
    ,@Subject = N''ALERTA: REPLICA ACIMA DE 300 - ISQL02 UAU DIRECIONAL'' 
	
END', 
		@database_name=N'UAU_DIRECIONAL', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'alerta replica recorrente', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=5, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20220106, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'00cc770e-b10d-42c9-a6f8-0bf7bc67018a'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


