USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_sentinela_teste]    Script Date: 6/10/2022 2:40:54 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER procedure [dbo].[sp_sentinela_teste] as 

--kill all the Blocked Processes of a Database

DECLARE @DatabaseName nvarchar(50) = ''
--Set the Database Name
--SET @DatabaseName = N'Datbase_Name'
--Select the current Database

SET @DatabaseName = (select name from sysdatabases where name not in ('TOTVS') for xml path(''))
DECLARE @SQL varchar(max)
SET @SQL = ''
DECLARE @ID varchar(max)
SELECT @SQL = @SQL + 'Kill ' + Convert(varchar, SPId) + ';', @ID = Convert(varchar, SPId)
FROM MASTER..SysProcesses
WHERE SPId <> @@SPId
and spid IN (SELECT blocked FROM master.dbo.sysprocesses where waittime > 300000)
and loginame not like 'vista\manutencao%'

--You can see the kill Processes ID
IF(@SQL <> '')
BEGIN	
	IF OBJECT_ID(N'tempdb..#sp_who2') IS NOT NULL
	BEGIN
		DROP TABLE #sp_who2
	END
	
	CREATE TABLE #sp_who2 (
		SPID INT,Status VARCHAR(255),
		Login  VARCHAR(255),HostName  VARCHAR(255),
		BlkBy  VARCHAR(255),DBName  VARCHAR(255),
		Command VARCHAR(255),CPUTime INT,
		DiskIO INT,LastBatch VARCHAR(255),
		ProgramName VARCHAR(255),SPID2 INT,
		REQUESTID INT
	)
	INSERT INTO #sp_who2 EXEC sp_who2
	SELECT      *
	FROM        #sp_who2
	-- Add any filtering of the results here :
	WHERE       DBName <> 'master' AND BlkBy = @ID
	-- Add any sorting of the results here :
	ORDER BY    DBName ASC
 
	DROP TABLE #sp_who2

	IF OBJECT_ID(N'tempdb..#Inputbuffer') IS NOT NULL
	BEGIN
		DROP TABLE #Inputbuffer
	END

	CREATE TABLE #Inputbuffer(
		EventType NVARCHAR(30) NULL,
		Parameters INT NULL,
		EventInfo NVARCHAR(255) NULL
	)
	GO
	
	INSERT #Inputbuffer
	EXEC('DBCC INPUTBUFFER('+ @ID +')')
	GO

	SELECT * FROM #Inputbuffer

	DROP TABLE #Inputbuffer
	EXEC msdb.dbo.sp_send_dbmail @body = '@SQL'
		,@body_format = 'TEXT'
		,@profile_name = N'EMAIL 1'
		,@query = 'EXEC sp_who2'
		,@recipients = N'monitoramento@clouddbm.com'
		,@Subject = N'Solucionare - Teste' 

	SELECT @SQL

	--Kill the Processes
	EXEC(@SQL)
END

--O exemplo a seguir mostra a lista de todos os perfis na instância.

--EXECUTE msdb.dbo.sysmail_help_profile_sp;