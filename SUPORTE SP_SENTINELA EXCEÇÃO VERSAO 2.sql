USE [master]
GO
/** Object:  StoredProcedure [dbo].[sp_SentinelaV2]    Script Date: 06/09/2022 09:51:08 **/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
create or alter PROCEDURE [dbo].[sp_Sentinela_Excecao] --with encryption
AS
BEGIN


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
and spid IN (SELECT blocked FROM master.dbo.sysprocesses where waittime > 0) -- 5 minutos = 300000
--and loginame not like 'vista\manutencao%'

-- FILTRA POR PROGRAMA
and program_name not like 'AzureWorkloadBackup% '
and program_name not like 'Microsoft SQL Server Management Studio% '

--You can see the kill Processes ID
IF(@SQL <> '')
BEGIN		
	IF OBJECT_ID(N'tempdb..##sp_who2') IS NOT NULL
	BEGIN
		DROP TABLE ##sp_who2
	END
	CREATE TABLE ##sp_who2 (
		SPID INT,Status VARCHAR(255),
		Login  VARCHAR(255),HostName  VARCHAR(255),
		BlkBy  VARCHAR(255),DBName  VARCHAR(255),
		Command VARCHAR(255),CPUTime INT,
		DiskIO INT,LastBatch VARCHAR(255),
		ProgramName VARCHAR(255),SPID2 INT,
		REQUESTID INT
	)
	INSERT INTO ##sp_who2 EXEC sp_who2

	SELECT      *
	FROM        ##sp_who2
	-- Add any filtering of the results here :
	WHERE       DBName <> 'master' AND BlkBy = @ID
	-- Add any sorting of the results here :
	ORDER BY    DBName ASC

	DECLARE @cat1 varchar(MAX)

	SELECT @cat1 = COALESCE(@cat1 + '', '')
	 + '<tr><td>'
                + CAST(ISNULL(SPID,'NULL') AS varchar) + '</td><td>'
                + CAST(ISNULL(Status,'NULL') AS varchar) + '</td><td>'
				+ CAST(ISNULL(Login,'NULL') AS varchar) + '</td><td>'
                + CAST(ISNULL(HostName,'NULL') AS varchar) + '</td><td>'
				+ CAST(ISNULL(BlkBy,'NULL') AS varchar) + '</td><td>'
				+ CAST(ISNULL(DBName,'NULL') AS varchar) + '</td><td>'		
				+ CAST(ISNULL(Command,'NULL') AS varchar) + '</td><td>'				
				+ CAST(ISNULL(CPUTime,'NULL') AS varchar) + '</td><td>'
				+ CAST(ISNULL(DiskIO,'NULL') AS varchar) + '</td><td>'
				+ CAST(ISNULL(LastBatch,'NULL') AS varchar) + '</td><td>'
				+ CAST(ISNULL(ProgramName,'NULL') AS varchar) + '</td><td>'
				+ CAST(ISNULL(SPID2,'NULL') AS varchar) + '</td><td>'
				+ CAST(ISNULL(REQUESTID,'NULL') AS varchar) + '</td><tr>'				
	FROM        ##sp_who2
	-- Add any filtering of the results here :
	WHERE       DBName <> 'master' AND BlkBy = @ID
	-- Add any sorting of the results here :
	ORDER BY    DBName ASC

	SET @cat1 = '
	<table border="1">
	<thead>
	<th>SPID</th>
	<th>Status</th>	
	<th>Login</th>
	<th>HostName</th>
	<th>BlkBy</th>
	<th>DBName</th>
	<th>Command</th>
	<th>CPUTime</th>
	<th>DiskIO</th>
	<th>LastBatch</th>
	<th>ProgramName</th>
	<th>SPID2</th>	
	<th>REQUESTID</th>	
	</thead>
	<tbody>

	 ' + @cat1 + '
	</tbody>
	</table>'
	
	IF OBJECT_ID(N'tempdb..##Inputbuffer') IS NOT NULL
	BEGIN
		DROP TABLE ##Inputbuffer
	END
	CREATE TABLE ##Inputbuffer(
		EventType NVARCHAR(30) NULL,
		Parameters INT NULL,
		EventInfo NVARCHAR(255) NULL
	)	
	INSERT ##Inputbuffer
	EXEC('DBCC INPUTBUFFER('+ @ID +')')

	
	--SELECT * FROM #sp_who2; SELECT * FROM #Inputbuffer;

	--SELECT * FROM #Inputbuffer

	-- DROP TABLE #Inputbuffer

	--SELECT @SQL

	
	EXEC(@SQL)--Kill the Processes

	DECLARE @MSG VARCHAR(255);
	SET @MSG = CONCAT('Teste exceção app ' + 'SERVER NAME: '+ @@SERVERNAME + ' ', @SQL)

	DECLARE @cat varchar(MAX)

	SELECT @cat = COALESCE(@cat + '', '')
	 + '<tr><td>'
                + CAST(ISNULL(EventType,'NULL') AS varchar) + '</td><td>'
                + CAST(ISNULL(Parameters,'NULL') AS varchar) + '</td><td>'
                + CAST(ISNULL(EventInfo,'NULL') AS varchar) + '</td><tr>'
	FROM ##Inputbuffer

	SET @cat = '
	<table border="1">
	<thead>
	<th>EventType</th>
	<th>Parameters</th>
	<th>EventInfo</th>
	</thead>
	<tbody>

	 ' + @cat + '
	</tbody>
	</table>'
	DECLARE @stmt VARCHAR(max)
	SET @stmt = @cat + '<br>' + @cat1

	EXEC msdb.dbo.sp_send_dbmail 		
	@profile_name = N'DBA',	
	@recipients = N'vpmaciel@gmail.com',
	--@recipients = N'monitoramento@clouddbm.com',
	@subject = @MSG,
	@body = @stmt,
    @body_format = 'HTML'
	
END
--@query = N'SELECT * FROM ##Inputbuffer;SELECT * FROM ##sp_who2;',
END