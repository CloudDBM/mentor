USE [master]
GO

/****** Object:  StoredProcedure [dbo].[sp_sentinela_excecao]    Script Date: 07/03/2022 15:52:55 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO





ALTER procedure [dbo].[sp_sentinela_excecao] as 


DECLARE @ID INT;


SELECT @ID = session_id
FROM sys.dm_exec_sessions WHERE PROGRAM_NAME like '%Management%' 
and session_id <> @@SPID
    or (program_name like '%qlik%' and session_id <> @@SPID )
--	or 	(program_name like '%prouau%' and session_id <> @@SPID)
	or (program_name like '%visual%' and session_id <> @@SPID)
    --or (program_name like '%tunning%' and session_id <> @@SPID)



and host_name NOT LIKE 'DRCBHZ006'

--kill all the Blocked Processes of a Database

DECLARE @DatabaseName nvarchar(50)
--Set the Database Name
--SET @DatabaseName = N'Datbase_Name'
--Select the current Daatbase

SET @DatabaseName = DB_NAME()
DECLARE @SQL varchar(max)
SET @SQL = ''
SELECT top 1 @SQL = @SQL + 'Kill ' + Convert(varchar, SPId) + ';'
FROM MASTER..SysProcesses WHERE SPId <> @@SPId    and SPId > 50
and spid IN (SELECT blocked FROM master.dbo.sysprocesses where waittime > 3000)
and loginame not like '%srvmgpuau01%'
and loginame not like '%srvmgtshmg01%'
AND  SPId NOT IN (@ID) 
order by last_batch asc

--You can see the kill Processes ID

SELECT @SQL

--Kill the Processes
EXEC(@SQL)

--You can see the kill Processes ID
IF(@SQL <> '')
BEGIN
EXEC msdb.dbo.sp_send_dbmail @body = @SQL
,@body_format = 'DBA'
,@profile_name = N'InformacaoTI'  --INSERIR O PROFILE EXISTENTE
,@recipients = N'monitoramento@clouddbm.com'
,@Subject = N'Matou processo no ISQL02'
END

GO


