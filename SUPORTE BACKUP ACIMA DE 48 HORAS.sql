IF OBJECT_ID(N'tempdb..##INFORMACOES_BACKUP') IS NOT NULL
	DROP TABLE ##INFORMACOES_BACKUP

CREATE TABLE ##INFORMACOES_BACKUP (
	servidor VARCHAR(256),
	banco VARCHAR(256),
	backup_date DATETIME,
	backup_horas INT
)
	
INSERT INTO ##INFORMACOES_BACKUP
SELECT 
   CONVERT(CHAR(100), SERVERPROPERTY('Servername')) AS Server, 
   msdb.dbo.backupset.database_name, 
   MAX(msdb.dbo.backupset.backup_finish_date) AS last_db_backup_date, 
   DATEDIFF(hh, MAX(msdb.dbo.backupset.backup_finish_date), GETDATE()) AS [Backup Age (Hours)] 
FROM 
   msdb.dbo.backupset 
WHERE 
   msdb.dbo.backupset.type = 'D'  
   AND msdb.dbo.backupset.backup_finish_date IS NOT NULL 
GROUP BY 
   msdb.dbo.backupset.database_name 
HAVING 
   (MAX(msdb.dbo.backupset.backup_finish_date) > DATEADD(hh, - 48, GETDATE()))  

UNION  
--Databases without any backup history 
SELECT      
   CONVERT(CHAR(100), SERVERPROPERTY('Servername')) AS Server,  
   master.sys.sysdatabases.NAME AS database_name,  
   NULL AS [Last Data Backup Date],  
   9999 AS [Backup Age (Hours)]  
FROM 
   master.sys.sysdatabases 
   LEFT JOIN msdb.dbo.backupset ON master.sys.sysdatabases.name = msdb.dbo.backupset.database_name 
WHERE 
   msdb.dbo.backupset.database_name IS NULL 
   AND master.sys.sysdatabases.name <> 'tempdb'
   AND msdb.dbo.backupset.backup_finish_date IS NOT NULL 
ORDER BY  
   msdb.dbo.backupset.database_name 

	
DECLARE	@servidor VARCHAR(256),
		@banco VARCHAR(256),
		@backup_date DATETIME,
		@backup_hora INT

	
DECLARE CURSOR_BACKUP CURSOR FOR
SELECT * from ##INFORMACOES_BACKUP
OPEN CURSOR_BACKUP

FETCH NEXT FROM CURSOR_BACKUP INTO @servidor, @banco, @backup_date, @backup_hora

WHILE @@fetch_status <> -1

BEGIN		
	PRINT @banco
		
	FETCH NEXT FROM CURSOR_BACKUP INTO @servidor, @banco, @backup_date, @backup_hora
END
CLOSE CURSOR_BACKUP	
DEALLOCATE CURSOR_BACKUP

