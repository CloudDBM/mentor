print'===================================================================================================='
print @@VERSION
GO
print'===================================================================================================='
print'SERVER NAMER:'+ @@SERVERNAME
-- NÓ ATIVO ATUAL | UPTIME | AGENT [Days:Hours:Minutes:Seconds] ----------------------------------------------------------------------------------------------------
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
print''
print'===================================================================================================='
print'ULTIMO INICIO DO SQL SERVER'
print''
--Calculate SQLServer Uptime -Returns [Days:Hours:Minutes:Seconds]
select RTRIM(CONVERT(CHAR(3),DATEDIFF(second,login_time,getdate())/86400)) + ':' +
RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400/3600)),2) + ':' +
RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400%3600/60)),2) + ':' +
RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400%3600%60)),2) AS [Uptime SQL SERVER: DD:HRS:MIN:SEC]
from sys.sysprocesses  --sysprocesses for SQL versions <2000
where spid = 1 
go
print''
print'===================================================================================================='
print'CHECK DE MALWARE'
print''
SELECT [name], [type_desc], is_disabled, create_date, modify_date 
FROM sys.server_principals 
WHERE [name] = 'Default'
print''
print'===================================================================================================='
print'BLOQUEIOS SQL SERVER'
print''
go
sp_quem
go
print''
print'===================================================================================================='
print'ESPACO EM DISCO'
print''
EXEC master.dbo.xp_fixeddrives 
print'===================================================================================================='
print'FALTAS DE BACKUP SQL SERVER'
print''

select @@servername cod_servidor, a.name,backup_date, 'FULL' tip_evento, GETDATE() dth_atualiza from master.dbo.sysdatabases  a (nolock)  

      left join 
            (select database_name,max(backup_finish_date) backup_date 
            from msdb.dbo.backupset (nolock) where type in ('D') 
            group by database_name)  b 
      on  a.name = b.database_name 
where a.name not in ('tempdb','master','model','msdb') 
--and backup_date is null 
AND backup_date <= getdate()-7 
OR backup_date IS NULL 
AND a.name not in ('tempdb','master','model','msdb') 
UNION 
select @@servername cod_servidor, a.name,backup_date, 'DIFF' tip_evento, GETDATE() dth_atualiza from master.dbo.sysdatabases  a (nolock)

      left join 
            (select database_name,max(backup_finish_date) backup_date 
            from msdb.dbo.backupset (nolock) where type in ('I') 
            group by database_name)  b 
      on  a.name = b.database_name 
where rtrim (lower (a.name)) not in ('tempdb','master','model','msdb') 
--and backup_date is null 
AND backup_date <= getdate()-1 
OR backup_date IS NULL 
AND name not in ('tempdb','master','model','msdb') 
UNION 
select @@servername cod_servidor, a.name,backup_date, 'LOG' tip_evento, GETDATE() dth_atualiza from master.dbo.sysdatabases  a (nolock)

      left join 
            (select database_name,max(backup_finish_date) backup_date 
            from msdb.dbo.backupset (nolock) where type in ('L') 
            group by database_name)  b 
      on  a.name = b.database_name 
where name not in ('tempdb','master','model','msdb') 
AND  ((databasepropertyex(name, 'Recovery') = 'FULL') or
 databasepropertyex(name, 'Recovery') = 'BULK_LOGGED')
--and backup_date is null 
AND backup_date <= getdate()-1 
OR backup_date IS NULL 
AND name not in ('tempdb','master','model','msdb') 
AND databasepropertyex(name, 'Recovery') = 'FULL'

print'===================================================================================================='
print'RECOVERY MODEL DOS BANCOS'
print''

SELECT Name

, DATABASEPROPERTYEX(Name,'RECOVERY') AS [Recovery Model]

FROM master.dbo.sysdatabases where name not in ('master','msdb','model','tempdb')
order by 2,1 desc
print'===================================================================================================='
print'DATABASE STATUS'
print''
SELECT [name], [state_desc]
FROM master.sys.databases
where state_desc <> 'ONLINE'
GO
print''
print'===================================================================================================='
print'CHECK DE PERFORMANCE'
print''
--PLE ao vivo
DECLARE @valor int

SELECT @valor = cntr_value
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Page life expectancy'
AND object_name LIKE '%Buffer Manager%'

print 'Page life expectancy: '+ CAST ( @valor AS VARCHAR(10))
                                                                                                           
if @valor < 10
print 'Page life expectancy: excessivamente baixo, podendo gerar erros, asserts e dumps'
else if @valor < 300
print 'Page life expectancy: baixo'
else if @valor < 1000
print 'Page life expectancy: razoável'
else if @valor < 5000
print 'Page life expectancy: bom'
else 
print 'Page life expectancy: excelente'
print'' 
print'===================================================================================================='
print'JOBS COM PROBLEMAS'
print''
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
GO
print'' 
print'===================================================================================================='
print'SQLPERF(LOGSPACE)'
print''
DBCC SQLPERF(LOGSPACE)