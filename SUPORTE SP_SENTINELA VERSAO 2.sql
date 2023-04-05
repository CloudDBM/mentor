USE [master]
GO
/****** Object:  StoredProcedure [dbo].[sp_SentinelaV2]    Script Date: 6/29/2022 9:53:56 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[sp_SentinelaV2] --with encryption
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
and spid IN (SELECT blocked FROM master.dbo.sysprocesses where waittime > 0000) -- seleciona processos bloqueados com mais de 30 segundos de espera
--and loginame not like 'vista\manutencao%'

--You can see the kill Processes ID
IF(@SQL <> '')
BEGIN			
	CREATE TABLE ##sp_who2 (
		SPID VARCHAR(255),Status VARCHAR(255),
		Login  VARCHAR(255),HostName  VARCHAR(255),
		BlkBy  VARCHAR(255),DBName  VARCHAR(255),
		Command VARCHAR(255),CPUTime VARCHAR(255),
		DiskIO VARCHAR(255),LastBatch VARCHAR(255),
		ProgramName VARCHAR(255),SPID2 VARCHAR(255),
		REQUESTID VARCHAR(255)
	)

	INSERT INTO ##sp_who2 EXEC sp_who2
	
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
	WHERE       DBName <> 'master' AND BlkBy <> '  .'
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
	
	CREATE TABLE ##Inputbuffer(
		EventType NVARCHAR(30) NULL,
		Parameters NVARCHAR(30) NULL,
		EventInfo NVARCHAR(255) NULL
	)	
	INSERT ##Inputbuffer
	EXEC('DBCC INPUTBUFFER('+ @ID +')')

	
	--SELECT * FROM #sp_who2; SELECT * FROM #Inputbuffer;

	--SELECT * FROM #Inputbuffer

	-- DROP TABLE #Inputbuffer

	--SELECT @SQL

	
	EXEC(@SQL)--Kill the Processes

	DECLARE @MSG VARCHAR(MAX);
	SET @MSG = CONCAT('Solucionare ' + 'SERVER NAME: '+ @@SERVERNAME + ' ', @SQL)

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
	DECLARE @total_linhas INT
	SET @stmt = @cat + '<br>' + @cat1
	SET @total_linhas = (SELECT count(1) FROM ##sp_who2 WHERE BlkBy <> '  .')    
	IF (@total_linhas > 0)
	BEGIN
	EXEC msdb.dbo.sp_send_dbmail 		
	@profile_name = N'EMAIL 1',	
	@recipients = N'monitoramento@clouddbm.com',	
	@subject = @MSG,
	@body = @stmt,
    @body_format = 'HTML'	
	IF OBJECT_ID(N'tempdb..##sp_who2') IS NOT NULL
	BEGIN
		DROP TABLE ##sp_who2
	END
	IF OBJECT_ID(N'tempdb..##Inputbuffer') IS NOT NULL
	BEGIN
		DROP TABLE ##Inputbuffer
	END
	END
END
--@query = N'SELECT * FROM ##Inputbuffer;SELECT * FROM ##sp_who2;',
END