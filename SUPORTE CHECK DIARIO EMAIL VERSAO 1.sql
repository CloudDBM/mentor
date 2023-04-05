-- habilita xp_cmdshell

-- To allow advanced options to be changed.  
EXECUTE sp_configure 'show advanced options', 1;  
GO  
-- To update the currently configured value for advanced options.  
RECONFIGURE;  
GO  
-- To enable the feature.  
EXECUTE sp_configure 'xp_cmdshell', 1;  
GO  
-- To update the currently configured value for this feature.  
RECONFIGURE;  
GO  

-- configura DBMail

-- Habilita o envio de emails
sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
sp_configure 'Database Mail XPs', 1;
GO
RECONFIGURE
GO

-- Cria o Profile
DECLARE @pid INT;
DECLARE @acctid INT;

EXEC msdb.dbo.sysmail_add_profile_sp
	@profile_name = 'DBA',
	@profile_id = @pid OUTPUT;

EXEC msdb.dbo.sysmail_add_account_sp 
	@account_name = 'CloudDB',
	@email_address = 'clouddb.email@gmail.com',
	@display_name = 'CloudDB Email',
	@replyto_address = '',
	@mailserver_name = 'smtp.gmail.com',
	@port = 587,
	@enable_ssl = 1,
	@username =  'clouddb.email@gmail.com', 
	@password = 'etenynwdxmtkutjm',
	@account_id = @acctid OUTPUT;

-- Add the account to the profile
EXEC msdb.dbo.sysmail_add_profileaccount_sp
	@profile_id = @pid,
	@account_id = @acctid, 
	@sequence_number = 1;
GO 

--  Adiciona o operator
USE [msdb]
GO
EXEC msdb.dbo.sp_add_operator 
	@name=N'DBA', 
	@enabled = 1, 
	@pager_days = 0, 
	@email_address = N'vpmaciel@gmail.com'
GO

-- Adiciona no SQL Server Agent o perfil

USE [msdb]
GO

EXEC msdb.dbo.sp_set_sqlagent_properties 
	@email_save_in_sent_folder = 1, 
	@databasemail_profile = N'DBA', 
	@use_databasemail = 1
GO

-- Define o tamanho máximo por anexo para 25 MB (O Padrão é 1 MB por arquivo)

EXEC msdb.dbo.sysmail_configure_sp 'MaxFileSize', '26214400';
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE sp_health_check --with encryption
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @@saida VARCHAR(MAX)

	-- ##########

	DECLARE @profile_nam VARCHAR(MAX) = 'DBA',
			@recipient NVARCHAR(MAX) = 'vpmaciel@gmail.com',	
			@subjec VARCHAR(MAX) = 'Health Check ' + CAST (GETDATE() AS VARCHAR),	
			@bod VARCHAR(MAX) = 'Health Check'

	-- ##########

	SET @subjec = 'Health Check ' + CAST (GETDATE() AS NVARCHAR(1000))

	SET @@saida = '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SET @@saida = @@saida + 'SERVER NAME:'+ @@SERVERNAME + CHAR(13) + CHAR(10)

	-- ########## INFORMAÇÕES DA VERSÃO DO SQL SERVER

	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SELECT @@saida = @@saida + @@VERSION

	-- ########## INFORMAÇÕES DO SERVIDOR

	IF OBJECT_ID(N'tempdb..##INFORMACOES_SERVER') IS NOT NULL
		DROP TABLE ##INFORMACOES_SERVER
	(SELECT
	CASE SERVERPROPERTY('IsClustered') WHEN 1 then 'CLUSTERED' ELSE 'STANDALONE' END AS [Instance_Type],
	CASE SERVERPROPERTY('IsClustered') WHEN 1 then SERVERPROPERTY('ComputerNamePhysicalNetBIOS') ELSE '-' END AS [Current_Node],
	CASE SERVERPROPERTY('IsClustered') WHEN 1 then (SELECT DISTINCT STUFF((SELECT ', ' + [NodeName] FROM sys.dm_os_cluster_nodes ORDER BY NodeName Asc FOR XML PATH(''),TYPE).value('(./text())[1]','VARCHAR(MAX)'),1,2,'') AS NameValues FROM sys.dm_os_cluster_nodes) ELSE '-' END [Cluster_Nodes],
	RTRIM(CONVERT(CHAR(3),DATEDIFF(second,login_time,getdate())/86400)) + ':' +
	RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400/3600)),2) + ':' +
	RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400%3600/60)),2) + ':' +
	RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400%3600%60)),2) AS [Uptime SQL SERVER: DD:HRS:MIN:SEC],
	(SELECT CASE WHEN AgentStatus = 0 AND IsExpress = 0 THEN 'OFFLINE' ELSE 'ONLINE' END 
		FROM (SELECT CASE WHEN REPLACE(CAST(SERVERPROPERTY('edition') AS VARCHAR), ' Edition', '') LIKE '%Express%' THEN 1 ELSE 0 END [IsExpress] , COUNT(1) AgentStatus 
			FROM master.sys.sysprocesses WHERE program_name = N'SQLAgent - Generic Refresher') TabAgent) AS [SQLAgentStatus]
	INTO ##INFORMACOES_SERVER
	FROM master.sys.sysprocesses
	WHERE spid = 1 
	)
	DECLARE	@Instance_Type VARCHAR(MAX), 
			@Current_Node	VARCHAR(MAX), 
			@Cluster_Nodes VARCHAR(MAX), 
			@Uptime VARCHAR(MAX), 
			@SQLAgentStatus VARCHAR(MAX)

	SELECT	@Instance_Type = CAST ([Instance_Type] AS VARCHAR(MAX)),
			@Current_Node = CAST ([Current_Node] AS VARCHAR(MAX)), 
			@Cluster_Nodes = CAST ([Cluster_Nodes] AS VARCHAR(MAX)), 
			@Uptime = CAST ([Uptime SQL SERVER: DD:HRS:MIN:SEC] AS VARCHAR(MAX)), 
			@SQLAgentStatus = CAST ([SQLAgentStatus] AS VARCHAR(MAX))
	FROM  ##INFORMACOES_SERVER

	SET @@saida = @@saida + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)

	SELECT @@saida = @@saida + 'INFORMAÇÕES DO SERVIDOR' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SELECT @@saida = @@saida + 'Instance_Type' + ': ' + @Instance_Type  + CHAR(13) + CHAR(10)
	SELECT @@saida = @@saida + 'Current_Node' + ': ' + @Current_Node  + CHAR(13) + CHAR(10)
	SELECT @@saida = @@saida + 'Cluster_Nodes' + ': ' + @Cluster_Nodes  + CHAR(13) + CHAR(10)
	SELECT @@saida = @@saida + 'Uptime SQL SERVER: DD:HRS:MIN:SEC' + ': ' + @Uptime  + CHAR(13) + CHAR(10)
	SELECT @@saida = @@saida + 'SQLAgentStatus' + ': ' + @SQLAgentStatus  + CHAR(13) + CHAR(10)

	-- ##########

	-- ULTIMO INICIO DO SQL SERVER
	IF OBJECT_ID(N'tempdb..##ULTIMO_INICIO_SQL_SERVER') IS NOT NULL
		DROP TABLE ##ULTIMO_INICIO_SQL_SERVER
	--Calculate SQLServer Uptime -Returns [Days:Hours:Minutes:Seconds]
	(
	select	RTRIM(CONVERT(CHAR(3),DATEDIFF(second,login_time,getdate())/86400)) + ':' +
			RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400/3600)),2) + ':' +
			RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400%3600/60)),2) + ':' +
			RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400%3600%60)),2) AS [Uptime SQL SERVER: DD:HRS:MIN:SEC]
	INTO ##ULTIMO_INICIO_SQL_SERVER
	from sys.sysprocesses  --sysprocesses for SQL versions <2000
	where spid = 1 
	)

	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SELECT @@saida = @@saida + 'ÚLTIMO INICIO DO SQL SERVER' + CHAR(13) + CHAR(10)
	DECLARE @msg VARCHAR(MAX)
	SELECT @msg = [Uptime SQL SERVER: DD:HRS:MIN:SEC] FROM ##ULTIMO_INICIO_SQL_SERVER
	SELECT @@saida = @@saida + CHAR(13) + CHAR(10) + 'Uptime SQL SERVER: DD:HRS:MIN:SEC' + ': ' + @msg + CHAR(13) + CHAR(10)

	-- ##########
	-- CHECK DE MALWARE
	DECLARE @TOTAL INT = 0
	IF OBJECT_ID(N'tempdb..##CHECK_MALWARE') IS NOT NULL
		DROP TABLE ##CHECK_MALWARE

	SELECT @TOTAL = count (1) FROM sys.server_principals WHERE [name] = 'Default'
	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)

	IF @TOTAL = 0 
	BEGIN
		SELECT @@saida = @@saida + 'SEM NENHUM MALVWARE' + CHAR(13) + CHAR(10)
	END
	ELSE
	BEGIN
		SELECT @@saida = @@saida + 'MALVWARE ENCONTRADO' + CHAR(13) + CHAR(10)
	END

	-- ##########

	IF OBJECT_ID(N'tempdb..##INFORMACOES_DISCO') IS NOT NULL
		DROP TABLE ##INFORMACOES_DISCO

	CREATE TABLE ##INFORMACOES_DISCO (
		drive VARCHAR(MAX),
		[MB livres] VARCHAR(MAX)
	)

	insert INTO ##INFORMACOES_DISCO EXEC xp_fixeddrives

	DECLARE	@drive VARCHAR(MAX),
			@MB_livres VARCHAR(MAX)

	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SELECT @@saida = @@saida + 'DISCOS' 
	
	DECLARE c2 CURSOR FOR
	SELECT drive, [MB livres] FROM ##INFORMACOES_DISCO
	OPEN c2

	FETCH NEXT FROM c2 INTO @drive, @MB_livres

	WHILE @@fetch_status <> -1

	BEGIN
		SET @@saida = @@saida + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10) + 'Drive: '+ @drive+ CHAR(13) + CHAR(10) + 'Espaço Livre: ' + @MB_livres + ' MB' + CHAR(13) + CHAR(10)
		FETCH NEXT FROM c2 INTO @drive, @MB_livres
	END

	CLOSE c2

	DEALLOCATE c2

	-- ##########

	IF OBJECT_ID(N'tempdb..##INFORMACOES_BACKUP') IS NOT NULL
		DROP TABLE ##INFORMACOES_BACKUP

	CREATE TABLE ##INFORMACOES_BACKUP (
		cod_servidor VARCHAR(64),
		name_banco VARCHAR(64),
		backup_date VARCHAR(64),
		tip_evento VARCHAR(64),
		dth_atualiza VARCHAR(64)
	)
	
	INSERT INTO ##INFORMACOES_BACKUP
	select @@servername cod_servidor, a.name,backup_date, 'FULL' tip_evento, GETDATE() dth_atualiza from master.dbo.sysdatabases  a (nolock)  

		left join 
			(select database_name,max(backup_finish_date) backup_date 
			from msdb.dbo.backupset (nolock) where type in ('D') 
			group by database_name)  b 
		on  a.name = b.database_name 
	where a.name not in ('tempdb','master','model','msdb')  and DATABASEPROPERTYEX(name, 'Status') = 'ONLINE'
	--and backup_date is null 
	AND backup_date <= getdate()-7 
	OR backup_date IS NULL 
	AND a.name not in ('tempdb','master','model','msdb') and DATABASEPROPERTYEX(name, 'Status') = 'ONLINE'
	UNION 
	select @@servername cod_servidor, a.name,backup_date, 'DIFF' tip_evento, GETDATE() dth_atualiza from master.dbo.sysdatabases  a (nolock)

		left join 
			(select database_name,max(backup_finish_date) backup_date 
			from msdb.dbo.backupset (nolock) where type in ('I') 
			group by database_name)  b 
		on  a.name = b.database_name 
	where rtrim (lower (a.name)) not in ('tempdb','master','model','msdb')  and DATABASEPROPERTYEX(name, 'Status') = 'ONLINE'
	--and backup_date is null 
	AND backup_date <= getdate()-1 
	OR backup_date IS NULL 
	AND name not in ('tempdb','master','model','msdb')  and DATABASEPROPERTYEX(name, 'Status') = 'ONLINE'
	UNION 
	select @@servername cod_servidor, a.name,backup_date, 'LOG' tip_evento, GETDATE() dth_atualiza from master.dbo.sysdatabases  a (nolock)

		left join 
			(select database_name,max(backup_finish_date) backup_date 
			from msdb.dbo.backupset (nolock) where type in ('L') 
			group by database_name)  b 
		on  a.name = b.database_name 
	where name not in ('tempdb','master','model','msdb') 
	AND  ((databasepropertyex(name, 'Recovery') = 'FULL') or
	databasepropertyex(name, 'Recovery') = 'BULK_LOGGED') and DATABASEPROPERTYEX(name, 'Status') = 'ONLINE' and databasepropertyex(name, 'Updateability') <> 'READ_ONLY' 
	--and backup_date is null 
	AND backup_date <= getdate()-1 
	OR backup_date IS NULL 
	AND name not in ('tempdb','master','model','msdb') 
	AND databasepropertyex(name, 'Recovery') = 'FULL' and DATABASEPROPERTYEX(name, 'Status') = 'ONLINE' and databasepropertyex(name, 'Updateability') <> 'READ_ONLY' 


	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SET @@saida = @@saida + 'FALTAS DE BACKUP SQL SERVER' 
	
	DECLARE	@cod_servidor VARCHAR(64),
			@name_banco VARCHAR(64),
			@backup_date VARCHAR(64),
			@tip_evento VARCHAR(64),
			@dth_atualiza VARCHAR(64)
	
	DECLARE c3 CURSOR FOR
	SELECT * from ##INFORMACOES_BACKUP
	OPEN c3

	FETCH NEXT FROM c3 INTO @cod_servidor, @name_banco, @backup_date, @tip_evento, @dth_atualiza

	WHILE @@fetch_status <> -1

	BEGIN		
		SET @@saida = @@saida+ CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10) + 
		'cod_servidor: ' + CAST(ISNULL(@cod_servidor,'NULL') AS VARCHAR(32)) + CHAR(13) + CHAR(10)+ 
		'name: ' + CAST(ISNULL(@name_banco,'NULL') AS VARCHAR(32)) + CHAR(13) + CHAR(10)+ 
		'backup_date: ' + CAST(ISNULL(@backup_date,'NULL') AS VARCHAR(32)) + CHAR(13) + CHAR(10)+
		'tip_evento: ' + CAST(ISNULL(@tip_evento,'NULL') AS VARCHAR(32)) + CHAR(13) + CHAR(10)+ 
		'dth_atualiza: ' + CAST(ISNULL(@dth_atualiza,'NULL') AS VARCHAR(32)) + ' MB'
		
		FETCH NEXT FROM c3 INTO @cod_servidor, @name_banco, @backup_date, @tip_evento, @dth_atualiza	
	END
	CLOSE c3	
	DEALLOCATE c3

	-- ##########

	SET @@saida = @@saida + CHAR(13) + CHAR(10)
	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SET @@saida = @@saida + 'BANCOS READ_ONLY OU COM STATUS RESTORING OU OFFLINE' + CHAR(13) + CHAR(10)
	
	IF OBJECT_ID(N'tempdb..##BANCOS_ESTADO') IS NOT NULL
		DROP TABLE ##BANCOS_ESTADO

	DECLARE @state_desc VARCHAR(64)

	select name,
		CASE databasepropertyex(name, 'Updateability')  WHEN 'READ_ONLY' then 'SIM' ELSE 'NÃO' END AS [READ_ONLY],
		CASE databasepropertyex(name, 'status') WHEN 'RESTORING' then 'SIM' ELSE 'NÃO' END AS [RESTORING],
		CASE databasepropertyex(name, 'status') WHEN 'OFFLINE' then 'SIM' ELSE 'NÃO' END AS [OFFLINE]
	INTO ##BANCOS_ESTADO
	from master..sysdatabases (nolock)

	where name not in ('master','model','tempdb') 
		and databasepropertyex(name, 'Updateability') = 'READ_ONLY' 
		OR databasepropertyex(name, 'status') = 'RESTORING' 
		OR DATABASEPROPERTYEX(name, 'status') = 'OFFLINE'
		and cmptlevel <> 65

	DECLARE	@banco varchar(64), 
			@read_only varchar(64), 
			@restoring varchar(64), 
			@offline varchar(64)

	DECLARE c10 CURSOR FOR

	SELECT * FROM ##BANCOS_ESTADO
	OPEN c10

	FETCH NEXT FROM c10 INTO @banco, @read_only, @restoring, @offline

	WHILE @@fetch_status <> -1

	BEGIN
		SET @@saida = @@saida  + CHAR(13) + CHAR(10) + 'Name: ' + @banco + CHAR(13) + CHAR(10) + 'READ_ONLY: ' + @read_only + CHAR(13) + CHAR(10) + 'RESTORING: ' + @restoring + CHAR(13) + CHAR(10) + 'OFFLINE: ' + @offline+ CHAR(13) + CHAR(10)
		FETCH NEXT FROM c10 INTO   @banco, @read_only, @restoring, @offline
	END

	CLOSE c10

	DEALLOCATE c10

	-- ##########


	SET @@saida = @@saida + CHAR(13) + CHAR(10)
	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SET @@saida = @@saida + 'RECOVERY MODEL DOS BANCOS' + CHAR(13) + CHAR(10)

	IF OBJECT_ID(N'tempdb..##INFORMACOES_RECOVERY_MODEL') IS NOT NULL
		DROP TABLE ##INFORMACOES_RECOVERY_MODEL

	CREATE TABLE ##INFORMACOES_RECOVERY_MODEL (
		Name VARCHAR(64),
		[Recovery Model] VARCHAR(64)
	)
	
	INSERT INTO ##INFORMACOES_RECOVERY_MODEL
	SELECT	Name
			,CAST( DATABASEPROPERTYEX(Name,'RECOVERY') AS VARCHAR(64)) AS [Recovery Model]
	FROM master.dbo.sysdatabases where name not in ('master','msdb','model','tempdb')
	order by 2,1 desc
	
	DECLARE	@nome_banco varchar(64),
			@recovery_model varchar(64)

	DECLARE c5 CURSOR FOR
	SELECT * FROM ##INFORMACOES_RECOVERY_MODEL
	OPEN c5

	FETCH NEXT FROM c5 INTO @nome_banco, @recovery_model

	WHILE @@fetch_status <> -1

	BEGIN
		SET @@saida = @@saida  + CHAR(13) + CHAR(10) + 'Name: ' + @nome_banco + CHAR(13) + CHAR(10) + 'Recovery Model: ' + @recovery_model+ CHAR(13) + CHAR(10)
		FETCH NEXT FROM c5 INTO  @nome_banco, @recovery_model
	END

	CLOSE c5

	DEALLOCATE c5

	-- ##########
	SET @@saida = @@saida + CHAR(13) + CHAR(10)
	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SET @@saida = @@saida + 'DATABASES COM STATUS DIFERENTE DE ONLINE' + CHAR(13) + CHAR(10)

	DECLARE @state_descricao VARCHAR(64)
	DECLARE c6 CURSOR FOR
	SELECT [name], [state_desc]
	FROM master.sys.databases
	where state_desc <> 'ONLINE'
	OPEN c6

	FETCH NEXT FROM c6 INTO @nome_banco, @state_descricao

	WHILE @@fetch_status <> -1

	BEGIN
		SET @@saida = @@saida  + CHAR(13) + CHAR(10) + 'Name: '+ @nome_banco + CHAR(13) + CHAR(10) + 'Recovery Model: ' + @state_descricao + CHAR(13) + CHAR(10)
		FETCH NEXT FROM c6 INTO  @nome_banco, @state_descricao
	END

	CLOSE c6

	DEALLOCATE c6


	-- ##########

	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SET @@saida = @@saida + 'CHECK DE PERFORMANCE' + CHAR(13) + CHAR(10)

	--PLE ao vivo
	DECLARE @valor int

	SELECT @valor = cntr_value
	FROM sys.dm_os_performance_counters
	WHERE counter_name = 'Page life expectancy'	AND object_name LIKE '%Buffer Manager%'
	
	SET @@saida = @@saida + CHAR(13) + CHAR(10)  + 'Page life expectancy: '+ CAST ( @valor AS VARCHAR(10))
                                                                                                           
	if @valor < 10
		SET @@saida = @@saida + CHAR(13) + CHAR(10) + 'Page life expectancy: excessivamente baixo, podENDo gerar erros, asserts e dumps' + CHAR(13) + CHAR(10)
	else if @valor < 300
		SET @@saida = @@saida + CHAR(13) + CHAR(10) + 'Page life expectancy: baixo' + CHAR(13) + CHAR(10)
	else if @valor < 1000
		SET @@saida = @@saida + CHAR(13) + CHAR(10) + 'Page life expectancy: razoável' + CHAR(13) + CHAR(10)
	else if @valor < 5000
		SET @@saida = @@saida + CHAR(13) + CHAR(10) + 'Page life expectancy: bom' + CHAR(13) + CHAR(10)
	else 
		SET @@saida = @@saida + CHAR(13) + CHAR(10) + 'Page life expectancy: excelente' + CHAR(13) + CHAR(10)


	-- ##########

	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SET @@saida = @@saida + 'JOBS COM PROBLEMAS' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)

	DECLARE @nome_job varchar(64)

	DECLARE c7 CURSOR FOR
	SELECT  DISTINCT(j.[name])          
	FROM    msdb.dbo.sysjobhistory h  
		INNER JOIN msdb.dbo.sysjobs j  
			ON h.job_id = j.job_id  
		INNER JOIN msdb.dbo.sysjobsteps s  
			ON j.job_id = s.job_id 
				AND h.step_id = s.step_id  
	WHERE    h.run_status = 0 AND h.run_date > CONVERT(int, CONVERT(varchar(10), DATEADD(DAY, -1, GETDATE()), 112))

	OPEN c7

	FETCH NEXT FROM c7 INTO @nome_job

	WHILE @@fetch_status <> -1

	BEGIN
		SET @@saida = @@saida + @nome_job + CHAR(13) + CHAR(10)
		FETCH NEXT FROM c7 INTO @nome_job
	END

	CLOSE c7

	DEALLOCATE c7

	-- ##########

	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SET @@saida = @@saida + 'INFORMAÇÕES DA CPU' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)


	IF OBJECT_ID(N'tempdb..##INFORMACAO_CPU') IS NOT NULL
		DROP TABLE ##INFORMACAO_CPU

	-- CPU Usage SQL Server 
	CREATE TABLE ##INFORMACAO_CPU(
		record_id VARCHAR(100),
		SQLServerProcessCPUUtilization VARCHAR(100),
		SystemIdleProcess VARCHAR(100),
		OtherProcessCPUUtilization VARCHAR(100),
		EventTime VARCHAR(100)
	)

	DECLARE @ts_now bigint = (SELECT cpu_ticks/(cpu_ticks/ms_ticks) FROM sys.dm_os_sys_info);  

	DECLARE	@record_id VARCHAR(100),
			@SQLServerProcessCPUUtilization VARCHAR(100),
			@SystemIdleProcess VARCHAR(100),
			@OtherProcessCPUUtilization VARCHAR(100),
			@EventTime VARCHAR(100)

	INSERT INTO ##INFORMACAO_CPU  
	SELECT	TOP(1)  
			[record_id], 
			SQLProcessUtilization AS [SQL Server Process CPU Utilization],  
			SystemIdle AS [System Idle Process],  
			100 - SystemIdle - SQLProcessUtilization AS [Other Process CPU Utilization],  
			DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) AS [Event Time]  
	FROM (  
			SELECT record.value('(./Record/@id)[1]', 'int') AS record_id,  
			record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS [SystemIdle],  
	record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]',  'int') AS [SQLProcessUtilization], [timestamp]  
	FROM (  
			SELECT [timestamp], CONVERT(xml, record) AS [record]  
			FROM sys.dm_os_ring_buffers  
			WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'  
			AND record LIKE '%<SystemHealth>%') AS x ) AS y  
	ORDER BY [Event Time] DESC;

	DECLARE c8 CURSOR FOR
	SELECT 
		record_id,
		SQLServerProcessCPUUtilization,
		SystemIdleProcess,
		OtherProcessCPUUtilization,
		EventTime
	FROM ##INFORMACAO_CPU
	
	OPEN c8

	FETCH NEXT FROM c8 INTO @record_id,@SQLServerProcessCPUUtilization,@SystemIdleProcess,@OtherProcessCPUUtilization,@EventTime

	WHILE @@fetch_status <> -1

	BEGIN
	SET @@saida = @@saida +'record_id: '+ @record_id + CHAR(13) + CHAR(10) +
							'SQL Server Process CPU Utilization: '+ @SQLServerProcessCPUUtilization + CHAR(13) + CHAR(10) +
							'System Idle Process: '+ @SystemIdleProcess + CHAR(13) + CHAR(10) +
							'Other Process CPU Utilization: '+ @OtherProcessCPUUtilization + CHAR(13) + CHAR(10) +
							'Event Time: '+ @EventTime + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	FETCH NEXT FROM c8 INTO @record_id,@SQLServerProcessCPUUtilization,@SystemIdleProcess,@OtherProcessCPUUtilization,@EventTime
	END

	CLOSE c8

	DEALLOCATE c8
	
	SET NOCOUNT ON;

	-- ##########

	SET @@saida = @@saida + CHAR(13) + CHAR(10) + '====================================================================================================' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)
	SET @@saida = @@saida + 'INFORMAÇÕES DA MEMÓRIA' + CHAR(13) + CHAR(10)+ CHAR(13) + CHAR(10)

	--Consultas de memória


	/*Esta consulta nos dá a memória do sistema operacional. 
	Em minha máquina, tenho muita memória física disponível, 
	então o resultado diz A memória física disponível está alta. 
	Isso é bom para o sistema e nada com que se preocupar.
	*/
	IF OBJECT_ID(N'tempdb..##INFORMACAO1_MEMORIA') IS NOT NULL
		DROP TABLE ##INFORMACAO1_MEMORIA

	CREATE TABLE ##INFORMACAO1_MEMORIA (
		[Total Physical Memory in MB] VARCHAR(100),
		[Physical Memory Available] VARCHAR(100),	
		[system_memory_state_desc] VARCHAR(100)
	)
	DECLARE	@TotalPhysicalMemoryinMB VARCHAR(100),
			@PhysicalMemoryAvailableinMB VARCHAR(100),
			@system_memory_state_desc VARCHAR(100)
		
	INSERT INTO ##INFORMACAO1_MEMORIA
	SELECT
		CAST(total_physical_memory_kb/1024 AS VARCHAR) [Total Physical Memory in MB],
		CAST(available_physical_memory_kb/1024 AS VARCHAR) [Physical Memory Available in MB],
		CAST(system_memory_state_desc AS VARCHAR)
	FROM sys.dm_os_sys_memory;


	DECLARE c9 CURSOR FOR
	SELECT 
		[Total Physical Memory in MB],
		[Physical Memory Available],	
		[system_memory_state_desc]
	FROM ##INFORMACAO1_MEMORIA
	OPEN c9

	FETCH NEXT FROM c9 INTO
		@TotalPhysicalMemoryinMB,
		@PhysicalMemoryAvailableinMB,
		@system_memory_state_desc

	WHILE @@fetch_status <> -1
	BEGIN
		SET @@saida = @@saida + 'Total Physical Memory in MB: ' + @TotalPhysicalMemoryinMB + CHAR(13) + CHAR(10) +
								'Physical Memory Available: ' + @PhysicalMemoryAvailableinMB + CHAR(13) + CHAR(10) +
								'system_memory_state_desc: ' + @system_memory_state_desc + CHAR(13) + CHAR(10)							
		FETCH NEXT FROM c9 INTO 
			@TotalPhysicalMemoryinMB,
			@PhysicalMemoryAvailableinMB,
			@system_memory_state_desc
	END

	CLOSE c9

	DEALLOCATE c9

	/*
	Essa consulta nos dá o resultado do processo do SQL Server em execução no 
	sistema operacional e também indica se há um problema de pouca memória ou não. 
	No nosso caso, ambos os valores são zero e isso é bom. 
	Se algum dos valores BAIXOS for 1, é uma questão de preocupação e 
	deve-se começar a investigar o problema de memória.
	*/

	IF OBJECT_ID(N'tempdb..##INFORMACAO2_MEMORIA') IS NOT NULL
		DROP TABLE ##INFORMACAO2_MEMORIA

	CREATE TABLE ##INFORMACAO2_MEMORIA (
		[Physical Memory Used in MB] VARCHAR(100),
		[Physical Memory Low] VARCHAR(100),	
		[Virtual Memory Low] VARCHAR(100)
	)
	DECLARE @PhysicalMemoryUsedinMB VARCHAR(100),
		@PhysicalMemoryLow VARCHAR(100),
		@VirtualMemoryLow VARCHAR(100)
		
	INSERT INTO ##INFORMACAO2_MEMORIA
	
	SELECT 
		physical_memory_in_use_kb/1024 [Physical Memory Used in MB],
		process_physical_memory_low [Physical Memory Low],
		process_virtual_memory_low [Virtual Memory Low]
	FROM sys.dm_os_process_memory;

	DECLARE c9 CURSOR FOR
	SELECT 
		[Physical Memory Used in MB],
		[Physical Memory Low],	
		[Virtual Memory Low]
	FROM ##INFORMACAO2_MEMORIA
	OPEN c9

	FETCH NEXT FROM c9 INTO 
		@PhysicalMemoryUsedinMB,
		@PhysicalMemoryLow,
		@VirtualMemoryLow

	WHILE @@fetch_status <> -1

	BEGIN
		SET @@saida = @@saida + CHAR(13) + CHAR(10) + 'Physical Memory Used in MB: ' + @PhysicalMemoryUsedinMB 
							  + CHAR(13) + CHAR(10) + 'Physical Memory Low: '+ @PhysicalMemoryLow 
							  + CHAR(13) + CHAR(10) + 'Virtual Memory Low: '+ @VirtualMemoryLow
							  + CHAR(13) + CHAR(10)							
		FETCH NEXT FROM c9 INTO
			@PhysicalMemoryUsedinMB,
			@PhysicalMemoryLow,
			@VirtualMemoryLow
	END

	CLOSE c9

	DEALLOCATE c9

	/*Essa consulta nos fornece quanta memória foi comprometida com o SQL Server 
	e qual é a projeção atual para o comprometimento de memória de destino do SQL Server. 
	Como a memória comprometida de destino é menor do que a memória disponível para nós, 
	também estamos bem nessa consulta.
	*/

	IF OBJECT_ID(N'tempdb..##INFORMACAO3_MEMORIA') IS NOT NULL
	DROP TABLE ##INFORMACAO3_MEMORIA

	CREATE TABLE ##INFORMACAO3_MEMORIA(
		[SQL Server Committed Memory in MB] VARCHAR(100),
		[SQL Server Target Committed Memory in MB] VARCHAR(100)
	)
	DECLARE	@SQLServerCommittedMemoryinMB VARCHAR(100),
			@SQLServerTargetCommittedMemoryinMB VARCHAR(100)		
		
	INSERT INTO ##INFORMACAO3_MEMORIA
	
	SELECT 
		committed_kb/1024 [SQL Server Committed Memory in MB],
		committed_target_kb/1024 [SQL Server Target Committed Memory in MB]
	FROM sys.dm_os_sys_info;

	DECLARE c9 CURSOR FOR
	SELECT 
		[SQL Server Committed Memory in MB],
		[SQL Server Target Committed Memory in MB]	
	FROM ##INFORMACAO3_MEMORIA
	OPEN c9

	FETCH NEXT FROM c9 INTO 
		@SQLServerCommittedMemoryinMB,
		@SQLServerTargetCommittedMemoryinMB						

	WHILE @@fetch_status <> -1
	BEGIN
		SET @@saida = @@saida + CHAR(13) + CHAR(10) + 'SQL Server Committed Memory in MB: ' + @SQLServerCommittedMemoryinMB 
							  + CHAR(13) + CHAR(10) + 'SQL Server Target Committed Memory in MB: ' + @SQLServerTargetCommittedMemoryinMB 
							  + CHAR(13) + CHAR(10) 							
	FETCH NEXT FROM c9 INTO 
		@SQLServerCommittedMemoryinMB,
		@SQLServerTargetCommittedMemoryinMB							
	END

	CLOSE c9

	DEALLOCATE c9

	IF OBJECT_ID(N'tempdb..##SAIDA') IS NOT NULL
		DROP TABLE ##SAIDA

	CREATE TABLE ##SAIDA(
		SAIDA VARCHAR(MAX)
	)
	
	INSERT INTO ##SAIDA VALUES(@@saida)

	DECLARE @query varchar(MAX) = N'select SAIDA from ##SAIDA;'; --Replace values as needed

	DECLARE @data VARCHAR(MAX)
	DECLARE @hora VARCHAR(MAX)
	DECLARE @minuto VARCHAR(MAX)

	SELECT @data = CAST(CONVERT(DATE, GETDATE()) AS VARCHAR)
	SELECT @hora = CAST(FORMAT(GETDATE(),'hh') AS VARCHAR)
	SELECT @minuto = CAST(FORMAT(GETDATE(),'mm') AS VARCHAR)	
	DECLARE @nome_arquivo VARCHAR(MAX) =  '[health check] [direcional] ['+ @data + '] [' + @hora + '_' + @minuto + '] ['+ @@SERVERNAME + '].txt';
	DECLARE @assunto VARCHAR(MAX) = '[health check] [direcional] ['+ @data + '] [' + @hora + '_' + @minuto + '] ['+ @@SERVERNAME + ']';

	EXEC msdb.dbo.sp_send_dbmail 
		@recipients='vpmaciel@gmail.com',
		@subject = @assunto,		
		@query = @query,
		@attach_query_result_as_file = 1, 
		@query_result_width = 20000,
		@query_attachment_filename = @nome_arquivo,
		@query_result_header = 1, 
		@query_no_truncate = 1,
		@query_result_no_padding = 0;
END
GO

-- cria o job

USE [msdb]
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT

SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
	EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END

DECLARE @jobId BINARY(16)

EXEC @ReturnCode =  msdb.dbo.sp_add_job 
	@job_name=N'DBA - Health_Check', 
	@enabled=1, 
	@notify_level_eventlog=0, 
	@notify_level_email=2, 
	@notify_level_netsEND=0, 
	@notify_level_page=0, 
	@delete_level=0, 
	@description=N'No description available.', 
	@category_name=N'[Uncategorized (Local)]', 
	@owner_login_name=N'sa', 
	@notify_email_operator_name=N'DBA', @job_id = @jobId OUTPUT

IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep 
	@job_id=@jobId, 
	@step_name=N'Health Check', 
	@step_id=1, 
	@cmdexec_success_code=0, 
	@on_success_action=1, 
	@on_success_step_id=0, 
	@on_fail_action=2, 
	@on_fail_step_id=0, 
	@retry_attempts=0, 
	@retry_interval=0, 
	@os_run_priority=0, @subsystem=N'TSQL', 
	@command=N'exec sp_health_check', 
	@database_name=N'msdb', 
	@output_file_name=N'D:\Temp\DBA - Health_Check.log', 
	@flags=0

IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1

IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule 
	@job_id=@jobId, @name=N'manha', 
	@enabled=1, 
	@freq_type=4, 
	@freq_interval=1, 
	@freq_subday_type=1, 
	@freq_subday_interval=0, 
	@freq_relative_interval=0, 
	@freq_recurrence_factor=0, 
	@active_start_date=20220524, 
	@active_END_date=99991231, 
	@active_start_time=80000, 
	@active_END_time=235959, 
	@schedule_uid=N'8e32dbfd-21f7-450a-a3fd-bbc45cb3800a'

IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule
	@job_id=@jobId, @name=N'tarde', 
	@enabled=1, 
	@freq_type=4, 
	@freq_interval=1, 
	@freq_subday_type=1, 
	@freq_subday_interval=0, 
	@freq_relative_interval=0, 
	@freq_recurrence_factor=0, 
	@active_start_date=20220524, 
	@active_END_date=99991231, 
	@active_start_time=130000, 
	@active_END_time=235959, 
	@schedule_uid=N'd563f067-eb08-4bdd-9042-a55db99dea77'

IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'

IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO ENDSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
ENDSave:
GO