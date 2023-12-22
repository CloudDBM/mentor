/*
ALERTA DE NUMERO DE CONEXOES,
INCLUI CRIACAO DO BANCO E TABELA PARA ARMAZENAR OS DADOS CASO ATINJA UM LIMITE DEFINIDO.
DA PROCEDURE, TABELA E DO JOB COM O ENVIO DE EMAIL SE LIMITE FOR ATINGIDO


-- Cria o banco DBManager caso não exista

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DBManager')
BEGIN
    CREATE DATABASE DBManager;
END

-- Cria a tabela ConnectionMonitor caso não exista

USE DBManager;
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'ConnectionMonitor')
BEGIN
    CREATE TABLE dbo.ConnectionMonitor (
        [ID] INT IDENTITY(1,1) PRIMARY KEY,
        [CaptureTime] DATETIME NOT NULL,
        [NumConnections] INT NOT NULL
    );
END
-- Cria a procedure spu_ConnectionMonitor caso não exista

USE DBManager;
GO

CREATE OR ALTER PROCEDURE dbo.spu_ConnectionMonitor	 -- Se ao executar a procedure não informar o valor do parâmetro, ela vai usar esse abaixo
    @ThresholdSave INT = 5000, -- Valor padrão para salvar na tabela os dados de registro 
    @ThresholdAlert INT = 7000 -- Valor padrão para enviar email de alerta
AS
BEGIN
    DECLARE @NumConnections INT;
    SELECT @NumConnections = COUNT(session_id)
    FROM sys.dm_exec_connections;

    IF @NumConnections > @ThresholdSave
    BEGIN
        INSERT INTO dbo.ConnectionMonitor (CaptureTime, NumConnections)
        VALUES (GETDATE(), @NumConnections);
    END

    IF @NumConnections > @ThresholdAlert
    BEGIN
        DECLARE @InstanceName NVARCHAR(100);
        SET @InstanceName = CAST(SERVERPROPERTY('MachineName') AS NVARCHAR(100));

        DECLARE @EmailSubject NVARCHAR(200);
        SET @EmailSubject = N'Alerta de Conexões - SQL Server (' + @InstanceName + N')';

        DECLARE @EmailBody NVARCHAR(MAX);
        SET @EmailBody = N'O número total de conexões na instância ' + @InstanceName + N'. Atualmente, existem ' + CAST(@NumConnections AS NVARCHAR(10)) + N' conexões.';

        EXEC msdb.dbo.sp_send_dbmail
            @profile_name = 'DBA',
            @recipients = 'seuemail@cloudb.com.br',
            @subject = @EmailSubject,
            @body = @EmailBody;
    END
END;
GO

--Cria o Job DBA - Monitora Numero Conexoes

USE [msdb]
GO

/****** Object:  Job [DBA - Monitora Numero Conexoes]    Script Date: 12/12/2023 17:03:25 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [[Uncategorized (Local)]]    Script Date: 12/12/2023 17:03:25 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBA - Monitora Numero Conexoes', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [.]    Script Date: 12/12/2023 17:03:25 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'.', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'USE DBManager
EXEC dbo.spu_ConnectionMonitor @ThresholdSave = 6000, @ThresholdAlert = 8000;', 
		@database_name=N'master', 
		--@output_file_name=N'C:\Temp\DBA - Monitora Numero de Conexoes.log', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Recorrente', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=3, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20231212, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'7d6be58d-b7c6-4051-8540-380ea0bf2cb5'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO



