USE [msdb]
GO

/****** Object:  StoredProcedure [dbo].[spu_alerta_bloqueio]    Script Date: 18/09/2020 11:09:46 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE proc [dbo].[spu_alerta_bloqueio] as

 SET NOCOUNT ON

SELECT s.session_id
    ,r.STATUS
    ,r.blocking_session_id
    ,r.wait_type
    ,wait_resource
    ,r.wait_time / (1000.0) 'WaitSec'
    ,r.cpu_time
    ,r.logical_reads
    ,r.reads
    ,r.writes
    ,r.total_elapsed_time / (1000.0) 'ElapsSec'
    ,Substring(st.TEXT, (r.statement_start_offset / 2) + 1, (
            (
                CASE r.statement_end_offset
                    WHEN - 1
                        THEN Datalength(st.TEXT)
                    ELSE r.statement_end_offset
                    END - r.statement_start_offset
                ) / 2
            ) + 1) AS statement_text
    ,Coalesce(Quotename(Db_name(st.dbid)) + N'.' + Quotename(Object_schema_name(st.objectid, st.dbid)) + N'.' + Quotename(Object_name(st.objectid, st.dbid)), '') AS command_text
    ,r.command
    ,s.login_name
    ,s.host_name
    ,s.program_name
    ,s.host_process_id
    ,s.last_request_end_time
    ,s.login_time
    ,r.open_transaction_count
INTO #temp_requests
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
WHERE r.session_id != @@SPID
and r.wait_time / (1000.0) > 60
ORDER BY r.cpu_time DESC
    ,r.STATUS
    ,r.blocking_session_id
    ,s.session_id

IF (
        SELECT count(*)
        FROM #temp_requests
        WHERE blocking_session_id > 50
        ) <> 0
BEGIN
    -- blocking found, sent email. 
    DECLARE @tableHTML NVARCHAR(MAX);

    SET @tableHTML = N'<H1>Atenção - Bloqueios a mais de 1 minuto no Banco de Dados</H1>' + N'<table border="1">' + N'<tr>' + N'<th>session_id</th>' + N'<th>Status</th>' + 
                     N'<th>blocking_session_id</th><th>wait_type</th><th>wait_resource</th>' + 
                     N'<th>WaitSec</th>' + N'<th>cpu_time</th>' + 
                     N'<th>logical_reads</th>' + N'<th>reads</th>' +
                     N'<th>writes</th>' + N'<th>ElapsSec</th>' + N'<th>statement_text</th>' + N'<th>command_text</th>' + 
                     N'<th>command</th>' + N'<th>login_name</th>' + N'<th>host_name</th>' + N'<th>program_name</th>' + 
                     N'<th>host_process_id</th>' + N'<th>last_request_end_time</th>' + N'<th>login_time</th>' + 
                     N'<th>open_transaction_count</th>' + '</tr>' + CAST((
                SELECT td = s.session_id
                    ,''
                    ,td = r.STATUS
                    ,''
                    ,td = r.blocking_session_id
                    ,''
                    ,td = r.wait_type
                    ,''
                    ,td = wait_resource
                    ,''
                    ,td = r.wait_time / (1000.0)
                    ,''
                    ,td = r.cpu_time
                    ,''
                    ,td = r.logical_reads
                    ,''
                    ,td = r.reads
                    ,''
                    ,td = r.writes
                    ,''
                    ,td = r.total_elapsed_time / (1000.0)
                    ,''
                    ,td = Substring(st.TEXT, (r.statement_start_offset / 2) + 1, (
                            (
                                CASE r.statement_end_offset
                                    WHEN - 1
                                        THEN Datalength(st.TEXT)
                                    ELSE r.statement_end_offset
                                    END - r.statement_start_offset
                                ) / 2
                            ) + 1)
                    ,''
                    ,td = Coalesce(Quotename(Db_name(st.dbid)) + N'.' + Quotename(Object_schema_name(st.objectid, st.dbid)) +
                        N'.' + Quotename(Object_name(st.objectid, st.dbid)), '')
                    ,''
                    ,td = r.command
                    ,''
                    ,td = s.login_name
                    ,''
                    ,td = s.host_name
                    ,''
                    ,td = s.program_name
                    ,''
                    ,td = s.host_process_id
                    ,''
                    ,td = s.last_request_end_time
                    ,''
                    ,td = s.login_time
                    ,''
                    ,td = r.open_transaction_count
                FROM sys.dm_exec_sessions AS s
                INNER JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
                CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
                WHERE r.session_id != @@SPID
                    AND blocking_session_id > 0
                ORDER BY r.cpu_time DESC
                    ,r.STATUS
                    ,r.blocking_session_id
                    ,s.session_id
                FOR XML PATH('tr')
                    ,TYPE
                ) AS NVARCHAR(MAX)) + N'</table>';

    EXEC msdb.dbo.sp_send_dbmail @body = @tableHTML
        ,@body_format = 'HTML'
        ,@profile_name = N'E-MAIL 1'
        ,@recipients = N'monitoramento@clouddbm.com'
        ,@Subject = N'Bloqueio detectado - SERVIDOR BANCO DE DADOS' 
END

DROP TABLE #temp_requests
GO


USE [msdb]
GO

/****** Object:  StoredProcedure [dbo].[spu_checkblocking]    Script Date: 18/09/2020 11:10:47 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO



create procedure [dbo].[spu_checkblocking]
as
	
	declare @spid int,@blocked int,@waittime int,@dbccstmt varchar(100)
	declare @eventtype1 varchar(300),@eventtype2 varchar(300), @hostname varchar(20), @program_name varchar(30), @program_name2 varchar(30), @host_blocking varchar(20)
	declare cur_sp cursor for select spid,blocked,waittime,hostname,program_name from master.dbo.sysprocesses (nolock) where blocked > 1

	create table #dbcc_output (
	eventtype varchar(30),
	parameters varchar(30),
	eventinfo varchar(300)
	)
   	open cur_sp
        fetch next from cur_sp into @spid,@blocked,@waittime,@hostname,@program_name
	while (@@fetch_status = 0)
	begin
                select @program_name2 = program_name from master.dbo.sysprocesses (nolock) where spid=@blocked		
                select @host_blocking = hostname from master.dbo.sysprocesses (nolock) where spid=@blocked

		set @dbccstmt = 'dbcc inputbuffer ('+convert(char(3),@spid)+')'
		print @dbccstmt
		insert  into #dbcc_output  exec (@dbccstmt)
		select @eventtype1 = eventinfo from #dbcc_output
		truncate table #dbcc_output
		set @dbccstmt = 'dbcc inputbuffer ('+convert(char(3),@blocked)+')'
		insert  into #dbcc_output  exec (@dbccstmt)
		select @eventtype2 = eventinfo from #dbcc_output
		truncate table #dbcc_output

		if @spid <> @blocked 
			insert into blocktable values (@spid,@blocked,@eventtype1,@eventtype2,@waittime,@hostname,getdate(),@program_name, @program_name2,@host_blocking)
                
/*
                if @waittime > 90000 exec master.dbo.xp_cmdshell 'net send "E0404019" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 2 MINUTOS - VERIFIQUE NO PROCESS INFO"'
                if @waittime > 90000 exec master.dbo.xp_cmdshell 'net send "E0404009" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 2 MINUTOS - VERIFIQUE NO PROCESS INFO"'
                if @waittime > 90000 exec master.dbo.xp_cmdshell 'net send "M2216" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 2 MINUTOS - VERIFIQUE NO PROCESS INFO"'
                if @waittime > 90000 exec master.dbo.xp_cmdshell 'net send "console" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 2 MINUTOS - VERIFIQUE NO PROCESS INFO"'
                if @waittime > 90000 exec master.dbo.xp_cmdshell 'net send "m2953" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 2 MINUTOS - VERIFIQUE NO PROCESS INFO"'
                if @waittime > 90000 exec master.dbo.xp_cmdshell 'net send "m2954" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 2 MINUTOS - VERIFIQUE NO PROCESS INFO"'
                if @waittime > 90000 exec master.dbo.xp_cmdshell 'net send "GILBERTR" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 2 MINUTOS - VERIFIQUE NO PROCESS INFO"'
                if @waittime > 600000 exec master.dbo.xp_cmdshell 'net send "uf104730" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 10 MINUTOS - UTILIZE A SP_QUEM"'
                if @waittime > 600000 exec master.dbo.xp_cmdshell 'net send "uf025055" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 10 MINUTOS - UTILIZE A SP_QUEM"'
                if @waittime > 600000 exec master.dbo.xp_cmdshell 'net send "uf015930" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 10 MINUTOS - UTILIZE A SP_QUEM"'
                if @waittime > 600000 exec master.dbo.xp_cmdshell 'net send "uf100160" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 10 MINUTOS - UTILIZE A SP_QUEM"'
                if @waittime > 600000 exec master.dbo.xp_cmdshell 'net send "uf100445" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 10 MINUTOS - UTILIZE A SP_QUEM"'
                if @waittime > 600000 exec master.dbo.xp_cmdshell 'net send "m2953" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 10 MINUTOS - VERIFIQUE NO PROCESS INFO"'
                if @waittime > 90000 exec master.dbo.xp_cmdshell 'net send "m2954" "ACIARIA - PROCESSO BLOQUEADO A MAIS DE 2 MINUTOS - VERIFIQUE NO PROCESS INFO"'
*/

		fetch next from cur_sp into @spid,@blocked,@waittime,@hostname,@program_name
	end
	close cur_sp
	deallocate cur_sp
	drop table #dbcc_output


GO

USE [msdb]
GO

/****** Object:  Job [DBA - Alerta - Monitora Processos Bloqueados]    Script Date: 18/09/2020 11:06:13 ******/
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
/****** Object:  JobCategory [REPL-Checkup]    Script Date: 18/09/2020 11:06:13 ******/
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'REPL-Checkup' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'REPL-Checkup'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBA - Alerta - Monitora Processos Bloqueados', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Esse Job executa a stored procedure spu_checkblocking, que foi avaliada durante 30 dias. Como os resultados foram satisfatórios, foi implementada a funcionalidade de envio de mensagem para a Operação intervir em processos bloqueados a mais de 2 minutos.', 
		@category_name=N'REPL-Checkup', 
		@owner_login_name=N'sa', 
		@notify_email_operator_name=N'CloudDB', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
/****** Object:  Step [spu_alerta_bloqueio e spu_checkblocking]    Script Date: 18/09/2020 11:06:14 ******/
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'spu_alerta_bloqueio e spu_checkblocking', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=10, 
		@retry_interval=1, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'SET DEADLOCK_PRIORITY LOW 
exec spu_alerta_bloqueio
go
--exec spu_checkblocking', 
		@database_name=N'msdb', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'schedule 2', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=1, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20030429, 
		@active_end_date=99991231, 
		@active_start_time=30, 
		@active_end_time=235959, 
		@schedule_uid=N'edcbf2b4-61fa-4b8d-8cf1-97880d613bde'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO


