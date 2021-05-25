-- ############################## HEALTH CHECK ##############################

-- ### 1) NÓ ATIVO ATUAL | UPTIME | AGENT [Days:Hours:Minutes:Seconds] ----------------------------------------------------------------------------------------------------
SELECT
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
FROM master.sys.sysprocesses
WHERE spid = 1 
GO

-- ### 2) DATABASE STATUS -----------------------------------------------------------------------------------------------------------------------------------------
SELECT [name], [state_desc]
FROM master.sys.databases
WHERE [state_desc] <> 'ONLINE' 
GO

-- ### 3) ESPAÇO EM DISCO | Usa xp_cmdshell com powershell (habilita se necessrio e desliga ao final) -------------------------------------------------------------
DECLARE @critical_threshold DECIMAL(12,2) = 90 -- Ajustar "threshold" crítico
DECLARE @warning_threshold DECIMAL(12,2) = 80 -- Ajustar "threshold" warning
DECLARE @days_search_backup INTEGER = 30 -- Ajustar quantos dias vai verificar se discos tem backup

-- A) Cria tabela para registrar configurações previas de 'show advanced options' e 'xp_cmdshell'
IF OBJECT_ID('tempdb..#TEMP_Configure') IS NOT NULL DROP TABLE #TEMP_Configure
CREATE TABLE #TEMP_Configure ([Name] varchar(128), minimum int, maximum int, config_value int, run_value int)

-- B) Captura configurações 'show advanced options' e 'xp_cmdshell' e faz ajustes necessários
INSERT INTO #TEMP_Configure EXEC sp_configure 'show advanced options'
IF (SELECT run_value FROM #TEMP_Configure WHERE [Name] = 'show advanced options') = 0 -- ESTÁ DESLIGADO ANTES DA EXEC | precisa ligar pra exec
		BEGIN EXEC sp_configure 'show advanced options', 1; RECONFIGURE; END
INSERT INTO #TEMP_Configure EXEC sp_configure 'xp_cmdshell'; 
	IF (SELECT run_value FROM #TEMP_Configure WHERE [Name] = 'xp_cmdshell') = 0 -- ESTÁ DESLIGADO ANTES DA EXEC | precisa ligar pra exec
		BEGIN EXEC sp_configure 'xp_cmdshell', 1; RECONFIGURE; END;

-- C) EXECUTA POWERSHELL PELO XP_CMDSHELL
IF OBJECT_ID('tempdb..#TMPoutput') IS NOT NULL DROP TABLE #TMPoutput;
IF OBJECT_ID('tempdb..#TMPoutput_raw') IS NOT NULL DROP TABLE #TMPoutput_raw;
IF OBJECT_ID('tempdb..#Disk_Content') IS NOT NULL DROP TABLE #Disk_Content;
DECLARE @sql varchar(400) = 'powershell.exe -c "Get-WmiObject -Class Win32_Volume -Filter ''DriveType = 3'' | select name,capacity,freespace,filesystem | foreach{$.name+''|''+$.capacity/1048576+''%''+$.freespace/1048576+''*''+$.filesystem+''#''}"'
CREATE TABLE #TMPoutput_raw (line varchar(255)) -- Cria tabela temporária
INSERT #TMPoutput_raw EXEC xp_cmdshell @sql -- Executa powershell através de xp_cmdshell e guarda na temp table

-- D) CONVERTE OUTPUT DO POWERSHELL EM COLUNAS
SELECT [Volume]
     , [Total_MB]
     , CAST((([Total_MB]-[Free_MB])*100.00)/[Total_MB] AS DECIMAL(12,2)) [Used_PCT]
	 , CASE WHEN [FileSystem] = 'CSVFS' THEN 'CSV'
	        WHEN [FileSystem] = 'NTFS' AND LEN([Volume]) > 3 THEN 'MOUNT POINT'
			WHEN [FileSystem] = 'NTFS' AND LEN([Volume]) = 3 THEN 'DRIVE LETTER'
	   ELSE [FileSystem] END AS [Type]
INTO #TMPoutput
FROM (SELECT rtrim(ltrim(SUBSTRING(line,1,CHARINDEX('|',line) -1))) as [Volume]
	        ,round(cast(rtrim(ltrim(SUBSTRING(line,CHARINDEX('|',line)+1, (CHARINDEX('%',line) -1)-CHARINDEX('|',line)) )) as Float),0) AS [Total_MB]
	        ,round(cast(rtrim(ltrim(SUBSTRING(line,CHARINDEX('%',line)+1, (CHARINDEX('*',line) -1)-CHARINDEX('%',line)) )) as Float),0) AS [Free_MB]
	        ,rtrim(ltrim(SUBSTRING(line,CHARINDEX('',line)+1, (CHARINDEX('#',line) -1)-CHARINDEX('',line)) )) AS [FileSystem]
      FROM #TMPoutput_raw
      WHERE line like '[A-Z][:]%') TabConv

-- E) VERIFICA CONTEÚDO DOS DISCOS
SELECT [Volume]
     , LTRIM(RTRIM(CASE WHEN SUM(CASE WHEN [db_name] IN ('tempdb') THEN 1 ELSE 0 END) > 0 THEN '[Tempdb]' ELSE '' END + ' ' +
	        CASE WHEN SUM(CASE WHEN [db_name] IN ('master', 'model', 'msdb') THEN 1 ELSE 0 END) > 0 THEN '[SystemDatabases]' ELSE '' END + ' ' +
	        CASE WHEN SUM(CASE WHEN [db_name] NOT IN ('tempdb', 'master', 'model', 'msdb') AND [type_desc] = 'ROWS' THEN 1 ELSE 0 END) > 0 THEN '[Datafiles]' ELSE '' END + ' ' +
	        CASE WHEN SUM(CASE WHEN [db_name] NOT IN ('tempdb', 'master', 'model', 'msdb') AND [type_desc] = 'LOG' THEN 1 ELSE 0 END) > 0 THEN '[Logfiles]' ELSE '' END + ' ' +
			CASE WHEN SUM(CASE WHEN [type_desc] = 'BACKUP' THEN 1 ELSE 0 END) > 0 THEN '[Backup]' ELSE '' END)) AS [Volume_Content]
INTO #Disk_Content
FROM( SELECT X.[db_name], X.[type_desc], X.[physical_name], COALESCE(X.[Volume], P.[Volume]) [Volume]
	  FROM ( SELECT M.[db_name], M.[type_desc], M.physical_name, T.Volume 
	  	     FROM (SELECT db_name(M.database_id) [db_name], M.[type_desc], M.physical_name FROM master.sys.master_files M 
			       UNION
                   SELECT S.[database_name], 'BACKUP', M.physical_device_name
                   FROM msdb..backupset S with (nolock) JOIN msdb..backupmediafamily M with (nolock) ON M.media_set_id = S.media_set_id
                   WHERE S.backup_start_date BETWEEN DATEADD(d, -1*(@days_search_backup), getdate()) AND GETDATE() AND M.device_type in (2,102)  ) M 
	  	   LEFT OUTER JOIN (SELECT * FROM #TMPoutput WHERE [Type] IN ('CSV', 'MOUNT POINT')) T ON M.physical_name LIKE T.[Volume] + '%' ) X
	  LEFT OUTER JOIN (SELECT * FROM #TMPoutput WHERE [Type] IN ('DRIVE LETTER')) P ON LEFT(X.physical_name,3) = P.[Volume] ) Y
GROUP BY [Volume]

-- F) SELECT OUTPUT
SELECT T.[Volume], 
       T.[Total_MB], 
	   T.[Used_PCT],
	   COALESCE(D.[Volume_Content], '-') [Volume_Content],
	   CASE WHEN T.[Used_PCT] >= @warning_threshold AND T.[Used_PCT] < @critical_threshold THEN 'WARNING'
	        WHEN T.[Used_PCT] >= @critical_threshold THEN 'CRITICAL'
	   ELSE '-' END [Situation]
FROM #TMPoutput T LEFT OUTER JOIN #Disk_Content D ON T.[Volume] = D.[Volume]
WHERE T.[Used_PCT] >= @warning_threshold

-- F) Verifica se é necessário retornar configurações anteriores para 'show advanced options' e 'xp_cmdshell'
IF (SELECT run_value FROM #TEMP_Configure WHERE [Name] = 'xp_cmdshell') = 0 -- ESTAVA DESLIGADO ANTES DA EXEC | precisa desligar novamente
	BEGIN EXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE; END;
IF (SELECT run_value FROM #TEMP_Configure WHERE [Name] = 'show advanced options') = 0 -- ESTAVA DESLIGADO ANTES DA EXEC | precisa desligar novamente
	BEGIN EXEC sp_configure 'show advanced options', 0; RECONFIGURE; END

-- ### 4) BACKUP PROBLEMS -----------------------------------------------------------------------------------------------------------------------------------------
DECLARE @dtfull datetime = DATEADD(DAY, -7, GETDATE()) -- Ajustar "Threshold" para Backup FULL
DECLARE @dtlog datetime = DATEADD(DAY, -1, GETDATE()) -- Ajustar "Threshold" para Backup LOG
SELECT D.[name] [database_name],
	   D.[recovery_model_desc] [recovery_model],
       F.[backup_date] [Last_Backup_FULL], 
	   L.[backup_date] [Last_Backup_Log],
	   CASE WHEN (F.[backup_date] IS NULL OR F.[backup_date] <= @dtfull) AND (L.[backup_date] IS NULL OR L.[backup_date] <= @dtlog) THEN 'Check Backup FULL and LOG'
	        WHEN (F.[backup_date] IS NULL OR F.[backup_date] <= @dtfull) AND (L.[backup_date] > @dtlog) THEN 'Check Backup FULL'
			WHEN (L.[backup_date] IS NULL OR L.[backup_date] <= @dtlog)  AND (F.[backup_date] > @dtfull) THEN 'Check Backup LOG'
	   ELSE 'OK' END AS [Action]
FROM master.sys.databases D (nolock)  
	 LEFT OUTER JOIN (SELECT [database_name], max([backup_finish_date]) backup_date 
	 				FROM msdb.dbo.backupset (nolock) where type in ('D') 
	 				GROUP BY [database_name] ) F
	 ON D.[name] = F.[database_name]
	 LEFT OUTER JOIN (SELECT [database_name], max([backup_finish_date]) backup_date 
	 				FROM msdb.dbo.backupset (nolock) where type in ('L') 
	 				GROUP BY [database_name] ) L
	 ON D.[name] = L.[database_name]
WHERE F.[backup_date] IS NULL
   OR L.[backup_date] IS NULL
   OR F.[backup_date] <= @dtfull
   OR L.[backup_date] <= @dtlog
 
-- ### 5) VERIFICAÇÃO DE JOBS ------------------------------------------------------------------------------------------------------------------------

DECLARE @failed_period TINYINT = 1 -- Ajustar quantos dias para trás serão buscados
                                                                                                                                                                                            
SELECT J.name                                                                                                                                                                                         
	, CASE J.[enabled] WHEN 1 THEN 'yes' WHEN 0 THEN 'no' END AS [Enabled]                                                                                                                                  
	, COALESCE(JE.[Status], 'idle') [Status]                                                                                                                                                                                            
	, CASE WHEN JS.[NextRunDateTime] IS NULL THEN 'no' ELSE 'yes' END AS [Scheduled]                                                                                                                        
	, CASE                                                                                                                                                                                                  
		WHEN [ST].[last_run_outcome] = 0 THEN 'Failed'                                                                                                                                                      
		WHEN [ST].[last_run_outcome] = 1 THEN 'Succeeded'                                                                                                                                                   
		WHEN [ST].[last_run_outcome] = 2 THEN 'Retry'                                                                                                                                                       
		WHEN [ST].[last_run_outcome] = 3 THEN 'Canceled'                                                                                                                                                    
		WHEN [ST].[last_run_outcome] = 4 THEN 'In Progress'                                                                                                                                                 
		WHEN [ST].[last_run_outcome] = 5 THEN 'Unknown'
	  END AS [LastRunStatus]                                                                                                                                                                              
	, [ST].[LastRunDateTime]                                                                                                                                                                            
	, [ST].[LastRunDuration]                                                                                                                                                                                
	, JS.[NextRunDateTime]                                                                                                                                                                              
FROM msdb..sysjobs J
	 LEFT OUTER JOIN (SELECT job_id, MIN(CASE JS.[next_run_date] WHEN 0 THEN NULL                                                                                                                        
	 				  ELSE CAST( CAST(JS.[next_run_date] AS CHAR(8)) + ' ' + STUFF(STUFF(RIGHT('000000' + CAST(JS.[next_run_time]                                                                         
	 				  AS VARCHAR(6)),  6), 3, 0, ':'), 6, 0, ':')	AS DATETIME) END) AS [NextRunDateTime]                                                                                                  
	 				  FROM msdb..sysjobschedules JS GROUP BY job_id) JS ON J.job_id = JS.job_id                                                                                                           
	 LEFT OUTER JOIN (SELECT job_id, run_status last_run_outcome, 
	                  STUFF( STUFF(RIGHT('000000' + CAST([run_duration] AS VARCHAR(6)),  6) , 3, 0, ':') , 6, 0, ':') [LastRunDuration],
	                  CASE [run_date] WHEN 0 THEN NULL                                                                                                                                                                                    
	                  ELSE CAST( CAST([run_date] AS CHAR(8)) + ' ' + STUFF( STUFF(RIGHT('000000' + CAST([run_time] AS VARCHAR(6)),  6), 3, 0, ':'), 6, 0, ':') AS DATETIME) END AS [LastRunDateTime]  
	 				  FROM msdb..sysjobhistory WHERE instance_id IN (select max(instance_id) max_inst_id from msdb..sysjobhistory where step_id = 0 group by job_id)) ST ON J.job_id = ST.job_id          
	 LEFT OUTER JOIN (SELECT job_id, 'Executing (Step: ' + cast(step_id as varchar) + ')' [Status] 
	                  FROM msdb..sysjobhistory WHERE instance_id IN (select max(instance_id) max_instance_id from msdb..sysjobhistory GROUP BY job_id) AND step_id <> 0) JE ON J.job_id = JE.job_id
WHERE [ST].[last_run_outcome] = 0 -- Filtro | Apenas Jobs com status de Falha
  AND [ST].[LastRunDateTime] IS NOT NULL -- Filtro | Exclui Jobs que não tem data da última execução
  AND [ST].[LastRunDateTime] >= DATEADD(DAY, -1*(@failed_period), GETDATE()) -- Filtro | Considera apenas Jobs com execução nos últimos "X" dias

-- ### 6) VERIFICA ERRORLOG ### -----------------------------------------------------------------------------------------------------------------------------------
IF OBJECT_ID('tempdb..#TmpErrorlog') IS NOT NULL DROP TABLE #TmpErrorlog;
IF OBJECT_ID('tempdb..#TmpErrorlog_Errors') IS NOT NULL DROP TABLE #TmpErrorlog_Errors;
IF OBJECT_ID('tempdb..#TmpErrorlog_Msgs') IS NOT NULL DROP TABLE #TmpErrorlog_Msgs;

-- A) JOGA ERRORLOG ATUAL PARA DENTRO DE UMA TABELA TEMPORARIA
CREATE TABLE #TmpErrorlog (ctrl integer identity(1,1), LogDate datetime, ProcessInfo varchar(128), Text varchar(512));
INSERT INTO #TmpErrorlog (LogDate, ProcessInfo, Text) EXEC sp_readerrorlog 0, 1;

-- B) VALIDAÇÃO DE ERROS | Concatenando as 2 linhas referentes ao mesmo erro (Codigo + Mensagem) | Filtrar Codigos de Erro que não devem ser apresentados
WITH E AS ( SELECT ctrl, LogDate, ProcessInfo, [Text], ctrl+1 as ctrl_aux, 
            substring( [text], charindex('Error: ', [Text],  1) + 7, (charindex(',', [Text], charindex('Error: ', [Text],  1) + 7)) - (charindex('Error: ', [Text],  1) + 7) )  ErrorCode
		    FROM #TmpErrorlog E 
			WHERE charindex('Error: ', [Text],  1) > 0 and charindex('Severity: ', [Text],  1) > 0)


SELECT T.LogDate, T.ProcessInfo, E.[Text] AS ErrorCode, T.[Text] AS Msg
INTO #TmpErrorlog_Errors
FROM #TmpErrorlog T INNER JOIN E ON T.ctrl = E.ctrl_aux
WHERE ErrorCode <> '18456' -- Login Failed

-- C) VALIDAÇÃO DE MENSAGENS IMPORTANTES | Adicionar as mensagens que devem ser apresentadas
SELECT LogDate, ProcessInfo, '-' AS ErrorCode, [text] AS Msg
INTO #TmpErrorlog_Msgs
FROM #TmpErrorlog 
WHERE Text LIKE '%A significant part of sql server process memory has been paged out%'
   OR Text LIKE '%SQL Server has encountered % occurrence(s) of I/O requests taking longer than 15 seconds to complete on file%'

-- D) SELECT OUTPUT
SELECT * FROM #TmpErrorlog_Errors UNION SELECT * FROM #TmpErrorlog_Msgs ORDER BY LogDate ASC