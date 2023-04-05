USE [msdb]
GO

/****** Object:  Job [MANUTENCAO - ALERTA ESPACO EM DISCO]    Script Date: 07/11/2022 14:35:43 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 07/11/2022 14:35:43 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'MANUTENCAO - ALERTA ESPACO EM DISCO', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Nenhuma descrição disponível.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [1]    Script Date: 07/11/2022 14:35:44 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'1', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'SET NOCOUNT ON
IF OBJECT_ID(N''tempdb..#drives'') IS NOT NULL
DROP TABLE #drives
DECLARE @hr int
DECLARE @fso int
DECLARE @drive char(1)
DECLARE @odrive int
DECLARE @TotalSize varchar(20) 
DECLARE @MB Numeric 
SET @MB = 1048576
CREATE TABLE #drives 
    (drive char(1) PRIMARY KEY, 
     FreeSpace int NULL,
     TotalSize int NULL) 

INSERT #drives(drive,FreeSpace) 

EXEC master.dbo.xp_fixeddrives 

EXEC @hr=sp_OACreate ''Scripting.FileSystemObject'', @fso OUT 
IF @hr <> 0 
EXEC sp_OAGetErrorInfo @fso

DECLARE dcur CURSOR LOCAL FAST_FORWARD
FOR SELECT drive from #drives ORDER by drive

OPEN dcur FETCH NEXT FROM dcur INTO @drive
WHILE @@FETCH_STATUS=0
BEGIN
EXEC @hr = sp_OAMethod @fso,''GetDrive'', @odrive OUT, @drive

IF @hr <> 0 EXEC sp_OAGetErrorInfo @fso EXEC @hr =
sp_OAGetProperty
@odrive,''TotalSize'', 
@TotalSize OUT IF @hr <> 0 

EXEC sp_OAGetErrorInfo @odrive 

UPDATE #drives SET TotalSize=@TotalSize/@MB 
WHERE  drive=@drive 
FETCH NEXT FROM dcur INTO @drive
End
Close dcur
DEALLOCATE dcur
EXEC @hr=sp_OADestroy @fso IF @hr <> 0 EXEC sp_OAGetErrorInfo @fso

DECLARE @tableHTML NVARCHAR(MAX);

SET @tableHTML = N''<H1>ESPAÇO DOS DISCOS</H1>'' + N''<table border="1">'' + N''<tr>'' +
				N''<th>DRIVE</th>'' + 
				N''<th>TOTAL (MB)</th>'' + 
                N''<th>FREE (MB)</th>''  + 
				N''<th>FREE (%)</th>''  + 
				''</tr>'' + CAST((

SELECT
 td = drive , '''', 
 td = TotalSize, '''', 
 td = FreeSpace, '''', 
 td = cast((1 - (cast (FreeSpace as float))/(cast (TotalSize as float))) *100 as decimal(4,2))
FROM #drives
ORDER BY drive 
FOR XML PATH(''tr'')
                    ,TYPE
                ) AS NVARCHAR(MAX)) + N''</table>'';
DECLARE @tableHTMLCondicao NVARCHAR(MAX);
SET @tableHTMLCondicao = N''<H1>ESPAÇO DOS DISCOS</H1>'' + N''<table border="1">'' + N''<tr>'' +
				N''<th>DRIVE</th>'' + 
				N''<th>TOTAL (MB)</th>'' + 
                N''<th>FREE (MB)</th>''  + 
				N''<th>FREE (%)</th>''  + 
				''</tr>'' + CAST((

SELECT
 td = drive , '''', 
 td = TotalSize, '''', 
 td = FreeSpace, '''', 
 td = cast((1 - (cast (FreeSpace as float))/(cast (TotalSize as float))) as decimal(4,2))
FROM #drives
ORDER BY drive 
FOR XML PATH(''tr'')
                    ,TYPE
                ) AS NVARCHAR(MAX)) + N''</table>'';

DECLARE @assunto VARCHAR(100) = N''TECHSHOP - DISCOS NO SERVIDOR BAIXO: '' + @@SERVERNAME + '' '' + CAST (GETDATE() AS VARCHAR)

if CHARINDEX(''0.00'',@tableHTMLCondicao) > 0 -- se a porcentagem for menor que 10% envia email
BEGIN
EXEC msdb.dbo.sp_send_dbmail @body = @tableHTML
        ,@body_format = ''HTML''
        ,@profile_name = N''DBA''
        ,@recipients = N''monitoramento@clouddbm.com''
        ,@Subject = @assunto
END', 
		@database_name=N'master', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'5 EM 5 MINUTOS', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=5, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20221021, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'2eb74b4f-c9e8-4119-9e34-f96a88864aed'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


