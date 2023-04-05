USE [master]
GO

/****** Object:  StoredProcedure [dbo].[process_extended_events]    Script Date: 05/12/2022 10:20:28 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[process_extended_events]
	@extended_events_session_name VARCHAR(MAX),
	@extended_events_file_path VARCHAR(MAX),
	@stop_and_drop_all_extended_events_sessions_and_files BIT
AS
BEGIN
	SET NOCOUNT ON;
	-- Add a trailing forward slash to the path name, if needed.
	IF RIGHT(@extended_events_file_path, 1) <> '\'
	BEGIN
		SELECT @extended_events_file_path = @extended_events_file_path + '\';
	END
	-- Variables to hold info about the Extended Events session
	DECLARE @current_extended_events_session_name VARCHAR(MAX);
	DECLARE @does_event_session_exist BIT = 0;
	DECLARE @is_event_session_started BIT = 0;

	IF EXISTS (SELECT * FROM sys.dm_xe_sessions WHERE dm_xe_sessions.name LIKE @extended_events_session_name + '%')
	BEGIN
		SELECT @does_event_session_exist = 1;
		SELECT @is_event_session_started = 1;
		SELECT
			@current_extended_events_session_name = dm_xe_sessions.name
		FROM sys.dm_xe_sessions WHERE dm_xe_sessions.name LIKE @extended_events_session_name + '%';
	END
	ELSE
	IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE server_event_sessions.name LIKE @extended_events_session_name + '%')
	BEGIN
		SELECT @does_event_session_exist = 1;
		SELECT
			@current_extended_events_session_name = server_event_sessions.name
		FROM sys.server_event_sessions WHERE server_event_sessions.name LIKE @extended_events_session_name + '%';
	END

	DECLARE @session_number_previous INT;
	DECLARE @session_number_next INT;

	IF @does_event_session_exist = 1
	BEGIN
		SELECT @session_number_previous =
			CASE
				WHEN ISNUMERIC(RIGHT(@current_extended_events_session_name, 1)) = 1
				AND LEN(@current_extended_events_session_name) <> LEN(@extended_events_session_name)
					THEN SUBSTRING(@current_extended_events_session_name, LEN(@extended_events_session_name) + 1, LEN(@current_extended_events_session_name) - LEN('query_metrics'))
				ELSE 0
			END
	END
	SELECT @session_number_next = @session_number_previous + 1;
	
	DECLARE @next_extended_events_session_name VARCHAR(MAX)  = @extended_events_session_name + CAST(@session_number_next AS VARCHAR(MAX));

	-- Create Extended Events commands for use later on.
	DECLARE @extended_events_session_create_command NVARCHAR(MAX);
	SELECT @extended_events_session_create_command = '
		CREATE EVENT SESSION ' + @next_extended_events_session_name + ' ON SERVER
		ADD EVENT sqlserver.rpc_completed (
			ACTION (
				sqlserver.client_app_name,
				sqlserver.client_hostname,
				sqlserver.database_name,
				sqlserver.session_id,
				sqlserver.username)
			WHERE (sqlserver.client_app_name NOT LIKE ''SQLAgent%'')),
		ADD EVENT sqlserver.sql_batch_completed (
			ACTION (
				sqlserver.client_app_name,
				sqlserver.client_hostname,
				sqlserver.database_name,
				sqlserver.session_id,
				sqlserver.username)
			WHERE (sqlserver.client_app_name NOT LIKE ''SQLAgent%''))
			ADD TARGET package0.event_file
				(SET FILENAME = ''' + @extended_events_file_path + @next_extended_events_session_name + '.xel'',
					MAX_FILE_SIZE = 1000, -- 1000MB
					MAX_ROLLOVER_FILES = 3)
			WITH (	EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
					MAX_DISPATCH_LATENCY = 15 SECONDS,
					MAX_MEMORY = 1024MB,
					STARTUP_STATE = OFF);';
	-- Command to start the new Extended Events session
	DECLARE @extended_events_session_start_command NVARCHAR(MAX);
	SELECT @extended_events_session_start_command = '
		ALTER EVENT SESSION ' + @next_extended_events_session_name + ' ON SERVER
		STATE = START;';
	-- Command to stop the previous Extended Events session
	DECLARE @extended_events_session_stop_command NVARCHAR(MAX);
	SELECT @extended_events_session_stop_command = '
		ALTER EVENT SESSION ' + @current_extended_events_session_name + ' ON SERVER
		STATE = STOP;';
	-- Command to delete *.xel files from the previous event session
	DECLARE @extended_events_session_file_delete_command NVARCHAR(MAX);
	SELECT @extended_events_session_file_delete_command = 'EXEC xp_cmdshell ''DEL ' + @extended_events_file_path + @current_extended_events_session_name + '*.xel /q'',no_output;';
	-- Command to delete *.xel files from any previous event sessions
	DECLARE @extended_events_session_file_delete_all_command NVARCHAR(MAX);
	SELECT @extended_events_session_file_delete_all_command = 'EXEC xp_cmdshell ''DEL ' + @extended_events_file_path + @extended_events_session_name + '*.xel /q'',no_output;';
	-- Command to drop an Extended Events session
	DECLARE @extended_events_session_drop_command NVARCHAR(MAX);
	SELECT @extended_events_session_drop_command = '
		DROP EVENT SESSION ' + @current_extended_events_session_name + ' ON SERVER;';
	-- Command to read Extended Events XML into a table
	DECLARE @extended_events_read_data_command NVARCHAR(MAX);
	SELECT
		@extended_events_read_data_command = '
		INSERT INTO dbo.extended_events_xml
			(sample_time_utc, event_data_xml)
		SELECT
			timestamp_utc AS sample_time_utc,
			CAST(event_data AS VARCHAR(MAX)) AS event_data_xml
		FROM sys.fn_xe_file_target_read_file(''' + @extended_events_file_path + @current_extended_events_session_name + '*.xel'', NULL, NULL, NULL);';

	-- With these commands created, execute Extended Events logic accordingly:
	IF @stop_and_drop_all_extended_events_sessions_and_files = 1
	BEGIN -- Stop and drop Extended Events session and delete files, regardless of status
		IF @is_event_session_started = 1
		BEGIN
			EXEC sp_executesql @extended_events_session_stop_command;
		END
		IF @does_event_session_exist = 1
		BEGIN
			EXEC sp_executesql @extended_events_session_drop_command;
		END

		EXEC sp_executesql @extended_events_session_file_delete_all_command;
	END
	ELSE
	IF @does_event_session_exist = 0
	BEGIN -- If Extended Events session doesn't exist, then delete any files, and then create/start the new session
		EXEC sp_executesql @extended_events_session_file_delete_all_command;
		
		EXEC sp_executesql @extended_events_session_create_command;
		EXEC sp_executesql @extended_events_session_start_command;
	END
	ELSE
	BEGIN
		IF @is_event_session_started = 1 -- If the previous session is started, then stop it
		BEGIN
			EXEC sp_executesql @extended_events_session_stop_command;
		END
		-- Create a new session and start it
		EXEC sp_executesql @extended_events_session_create_command;
		EXEC sp_executesql @extended_events_session_start_command;
		-- Now that the new session is collecting events, process the data from the previous session
		EXEC sp_executesql @extended_events_read_data_command;
		
		EXEC sp_executesql @extended_events_session_drop_command;
		EXEC sp_executesql @extended_events_session_file_delete_command;
	END
	-- Crunch the XML into query details
	IF EXISTS (SELECT * FROM dbo.extended_events_xml)
	BEGIN
		INSERT INTO dbo.extended_events_data
			(sample_time_utc, database_name, event_name, session_id, cpu_time, duration, physical_reads,
			 logical_reads, writes, row_count, client_app_name, client_host_name, username)
		SELECT
			sample_time_utc,
			event_data_xml.value('(event/action[@name="database_name"]/value)[1]', 'SYSNAME') AS database_name,
			event_data_xml.value('(event/@name)[1]', 'VARCHAR(50)') As event_name,
			event_data_xml.value('(event/action[@name="session_id"]/value)[1]', 'SMALLINT') AS session_id,
			event_data_xml.value('(event/data[@name="cpu_time"]/value)[1]', 'BIGINT') AS cpu_time,
			event_data_xml.value('(event/data[@name="duration"]/value)[1]', 'BIGINT') AS duration,
			event_data_xml.value('(event/data[@name="physical_reads"]/value)[1]', 'BIGINT') AS physical_reads,
			event_data_xml.value('(event/data[@name="logical_reads"]/value)[1]', 'BIGINT') AS logical_reads,
			event_data_xml.value('(event/data[@name="writes"]/value)[1]', 'BIGINT') AS writes,
			event_data_xml.value('(event/data[@name="row_count"]/value)[1]', 'BIGINT') AS row_count,
			event_data_xml.value('(event/action[@name="client_app_name"]/value)[1]', 'VARCHAR(128)') AS client_app_name,
			event_data_xml.value('(event/action[@name="client_hostname"]/value)[1]', 'VARCHAR(128)') AS client_host_name,
			event_data_xml.value('(event/action[@name="username"]/value)[1]', 'SYSNAME') AS username
		FROM dbo.extended_events_xml;
		
		TRUNCATE TABLE dbo.extended_events_xml;
	END
END
GO

/****** Object:  StoredProcedure [dbo].[sp_acerta_logins]    Script Date: 05/12/2022 10:20:28 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO




create procedure [dbo].[sp_acerta_logins]
as  

-- Apos um restore utilize essa stored procedure para acertas os logins orfaos, dentro do banco de dados
-- De www.clouddbm.com Opensource Copywrited by Gilberto Rosa (gilberto.rosa@clouddbm.com)
-- Script executado em mais de 10 mil Bancos de Dados, valide seu ambiente e tenha backup

  
declare @cmd varchar(1000)  
declare cmd cursor  
   for  select 'exec sp_change_users_login ''update_one'', '''+name+''','+ ''''+name+''''   
 from sysusers u   
 where issqlrole <> 1   
 and hasdbaccess <> 0   
 and uid > 4   
 and uid < 16384   
 and exists (select 1 from master..syslogins l where u.name = l.name)  
open cmd   
fetch next from cmd into @cmd  
  
while @@fetch_status = 0  
   begin  
 exec(@cmd)  
 print @cmd     
 fetch next from cmd into @cmd  
   end  
close cmd  
deallocate cmd  

GO

/****** Object:  StoredProcedure [dbo].[sp_CompareDB]    Script Date: 05/12/2022 10:20:28 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO





-- sp_CompareDB  
--   
-- The SP compares structures and data in 2 databases.  
-- 1. Compares if all tables in one database have analog (by name) in second database  
-- Tables not existing in one of databases won't be used for data comparing  
-- 2. Compares if structures for tables with the same names are the same. Shows structural  
-- differences like:  
-- authors  
-- Column Phone: in db1 - char(12), in db2 - char(14)  
-- sales  
-- Column Location not in db2  
-- Tables, having different structures, won't be used for data comparing. However if the tables  
-- contain columns of the same type and different length (like Phone in the example above) or  
-- tables have compatible data types (have the same type in syscolumns - char and nchar,   
-- varchar and nvarchar etc) they will be allowed for data comparing.  
-- 3. Data comparison itself.   
-- 3.1 Get information about unique keys in the tables. If there are unique keys then one of them  
-- (PK is a highest priority candidate for this role) will be used to specify rows with  
-- different data.  
-- 3.2 Get information about all data columns in the table and form predicates that will be   
-- used to compare data.  
-- 3.3 Compare data with the criteria:  
-- a. if some unique keys from the table from first database do not exist in second db (only  
-- for tables with a unique key)  
-- b. if some unique keys from the table from second database do not exist in first db (only  
-- for tables with a unique key)  
-- c. if there are rows with the same values of unique keys and different data in other  
-- columns (only for tables with a unique key)  
-- d. if there are rows in the table from first database that don't have a twin in the   
-- table from second db  
-- e. if there are rows in the table from second database that don't have a twin in the   
-- table from first db  
--------------------------------------------------------------------------------------------  
-- Parameters:  
-- 1. @db1 - name of first database to compare  
-- 2. @db2 - name of second database to compare  
-- 3. @TabList - list of tables to compare. if empty - all tables in the databases should be  
-- compared  
-- 4. @NumbToShow - number of rows with differences to show. Default - 10.  
-- 5. @OnlyStructure - flag, if set to 1, allows to avoid data comparing. Only structures should  
-- be compared. Default - 0  
-- 6. @NoTimestamp - flag, if set to 1, allows to avoid comparing of columns of timestamp  
-- data type. Default - 0  
-- 7. @VerboseLevel - if set to 1 allows to print querues used for data comparison  
--------------------------------------------------------------------------------------------  
-- Created by Viktor Gorodnichenko (c)  
-- Created on: July 5, 2001  
--------------------------------------------------------------------------------------------  
CREATE PROC [dbo].[sp_CompareDB]  
@db1 varchar(128),  
@db2 varchar(128),  
@OnlyStructure bit = 0,  
@TabList varchar(8000) = '',  
@NumbToShow int = 10,  
@NoTimestamp bit = 0,  
@VerboseLevel tinyint = 0  
AS  
if @OnlyStructure <> 0  
set @OnlyStructure = 1  
if @NoTimestamp <> 0  
set @NoTimestamp = 1  
if @VerboseLevel <> 0  
set @VerboseLevel = 1  
  
SET NOCOUNT ON  
SET ANSI_WARNINGS ON  
SET ANSI_NULLS ON  
declare @sqlStr varchar(8000)  
set nocount on  
-- Checking if there are specified databases  
declare @SrvName sysname  
declare @DBName sysname  
set @db1 = RTRIM(LTRIM(@db1))  
set @db2 = RTRIM(LTRIM(@db2))  
set @SrvName = @@SERVERNAME  
if CHARINDEX('.',@db1) > 0  
begin  
set @SrvName = LEFT(@db1,CHARINDEX('.',@db1)-1)  
if not exists (select * from master.dbo.sysservers where srvname = @SrvName)  
begin  
print 'There is no linked server named '+@SrvName+'. End of work.'  
return   
end  
set @DBName = RIGHT(@db1,LEN(@db1)-CHARINDEX('.',@db1))  
end  
else  
set @DBName = @db1  
exec ('declare @Name sysname select @Name=name from ['+@SrvName+'].master.dbo.sysdatabases where name = '''+@DBName+'''')  
if @@rowcount = 0  
begin  
print 'There is no database named '+@db1+'. End of work.'  
return   end  
set @SrvName = @@SERVERNAME  
if CHARINDEX('.',@db2) > 0  
begin  
set @SrvName = LEFT(@db2,CHARINDEX('.',@db2)-1)  
if not exists (select * from master.dbo.sysservers where srvname = @SrvName)  
begin  
print 'There is no linked server named '+@SrvName+'. End of work.'  
return   
end  
set @DBName = RIGHT(@db2,LEN(@db2)-CHARINDEX('.',@db2))  
end  
else  
set @DBName = @db2  
exec ('declare @Name sysname select @Name=name from ['+@SrvName+'].master.dbo.sysdatabases where name = '''+@DBName+'''')  
if @@rowcount = 0  
begin  
print 'There is no database named '+@db2+'. End of work.'  
return   
end  
  
print Replicate('-',LEN(@db1)+LEN(@db2)+25)  
print 'Comparing databases '+@db1+' and '+@db2  
print Replicate('-',LEN(@db1)+LEN(@db2)+25)  
print 'Options specified:'  
print ' Compare only structures: '+CASE WHEN @OnlyStructure = 0 THEN 'No' ELSE 'Yes' END  
print ' List of tables to compare: '+CASE WHEN LEN(@TabList) = 0 THEN ' All tables' ELSE @TabList END  
print ' Max number of different rows in each table to show: '+LTRIM(STR(@NumbToShow))  
print ' Compare timestamp columns: '+CASE WHEN @NoTimestamp = 0 THEN 'No' ELSE 'Yes' END  
print ' Verbose level: '+CASE WHEN @VerboseLevel = 0 THEN 'Low' ELSE 'High' END  
  
-----------------------------------------------------------------------------------------  
-- Comparing structures  
-----------------------------------------------------------------------------------------  
print CHAR(10)+Replicate('-',36)  
print 'Comparing structure of the databases'  
print Replicate('-',36)  
if exists (select * from tempdb.dbo.sysobjects where name like '#TabToCheck%')  
drop table #TabToCheck  
create table #TabToCheck (name sysname)  
declare @NextCommaPos int  
if len(@TabList) > 0   
begin  
while 1=1  
begin  
set @NextCommaPos = CHARINDEX(',',@TabList)  
if @NextCommaPos = 0  
begin  
set @sqlStr = 'insert into #TabToCheck values('''+@TabList+''')'  
exec (@sqlStr)  
break  
end  
set @sqlStr = 'insert into #TabToCheck values('''+LEFT(@TabList,@NextCommaPos-1)+''')'  
exec (@sqlStr)  
set @TabList = RIGHT(@TabList,LEN(@TabList)-@NextCommaPos)  
end  
end  
else -- then will check all tables  
begin  
exec ('insert into #TabToCheck select name from '+@db1+'.dbo.sysobjects where type = ''U''')  
exec ('insert into #TabToCheck select name from '+@db2+'.dbo.sysobjects where type = ''U''')  
end  
-- First check if at least one table specified in @TabList exists in db1  
exec ('declare @Name sysname select @Name=name from '+@db1+'.dbo.sysobjects where name in (select * from #TabToCheck)')  
if @@rowcount = 0  
begin  
print 'No tables in '+@db1+' to check. End of work.'  
return  
end  
-- Check if tables existing in db1 are in db2 (all tables or specified in @TabList)  
if exists (select * from tempdb.dbo.sysobjects where name like '#TabNotInDB2%')  
drop table #TabNotInDB2  
create table #TabNotInDB2 (name sysname)  
insert into #TabNotInDB2   
exec ('select name from '+@db1+'.dbo.sysobjects d1o '+  
'where name in (select * from #TabToCheck) and '+  
' d1o.type = ''U'' and not exists '+  
'(select * from '+@db2+'.dbo.sysobjects d2o'+  
' where d2o.type = ''U'' and d2o.name = d1o.name)')  
if @@rowcount > 0  
begin  
print CHAR(10)+'The table(s) exist in '+@db1+', but do not exist in '+@db2+':'  
select * from #TabNotInDB2   
end  
delete from #TabToCheck where name in (select * from #TabNotInDB2)  
drop table #TabNotInDB2  
  
if exists (select * from tempdb.dbo.sysobjects where name like '#TabNotInDB1%')  
drop table #TabNotInDB1  
create table #TabNotInDB1 (name sysname)  
insert into #TabNotInDB1   
exec ('select name from '+@db2+'.dbo.sysobjects d1o '+  
'where name in (select * from #TabToCheck) and '+  
' d1o.type = ''U'' and not exists '+  
'(select * from '+@db1+'.dbo.sysobjects d2o'+  
' where d2o.type = ''U'' and d2o.name = d1o.name)')  
if @@rowcount > 0  
begin  
print CHAR(10)+'The table(s) exist in '+@db2+', but do not exist in '+@db1+':'  
select * from #TabNotInDB1   
end  
delete from #TabToCheck where name in (select * from #TabNotInDB1)  
drop table #TabNotInDB1  
-- Comparing structures of tables existing in both dbs  
print CHAR(10)+'Checking if there are tables existing in both databases having structural differences ...'+CHAR(10)  
if exists (select * from tempdb.dbo.sysobjects where name like '#DiffStructure%')  
drop table #DiffStructure  
create table #DiffStructure (name sysname)  
set @sqlStr='  
declare @TName1 sysname, @TName2 sysname, @CName1 sysname, @CName2 sysname,  
@TypeName1 sysname, @TypeName2 sysname,  
@CLen1 smallint, @CLen2 smallint, @Type1 sysname, @Type2 sysname, @PrevTName sysname  
declare @DiffStructure bit  
declare Diff cursor fast_forward for  
select d1o.name, d2o.name, d1c.name, d2c.name, d1t.name, d2t.name,  
d1c.length, d2c.length, d1c.type, d2c.type  
from ('+@db1+'.dbo.sysobjects d1o   
JOIN '+@db2+'.dbo.sysobjects d2o2 ON d1o.name = d2o2.name and d1o.type = ''U'' --only tables in both dbs  
and d1o.name in (select * from #TabToCheck)  
JOIN '+@db1+'.dbo.syscolumns d1c ON d1o.id = d1c.id  
JOIN '+@db1+'.dbo.systypes d1t ON d1c.xusertype = d1t.xusertype)  
FULL JOIN ('+@db2+'.dbo.sysobjects d2o   
JOIN '+@db1+'.dbo.sysobjects d1o2 ON d1o2.name = d2o.name and d2o.type = ''U'' --only tables in both dbs  
and d2o.name in (select * from #TabToCheck)  
JOIN '+@db2+'.dbo.syscolumns d2c ON d2c.id = d2o.id  
JOIN '+@db2+'.dbo.systypes d2t ON d2c.xusertype = d2t.xusertype)  
ON d1o.name = d2o.name and d1c.name = d2c.name  
WHERE (not exists   
(select * from '+@db2+'.dbo.sysobjects d2o2  
JOIN '+@db2+'.dbo.syscolumns d2c2 ON d2o2.id = d2c2.id  
JOIN '+@db2+'.dbo.systypes d2t2 ON d2c2.xusertype = d2t2.xusertype  
where d2o2.type = ''U''  
and d2o2.name = d1o.name   
and d2c2.name = d1c.name   
and d2t2.name = d1t.name  
and d2c2.length = d1c.length)  
OR not exists   
(select * from '+@db1+'.dbo.sysobjects d1o2  
JOIN '+@db1+'.dbo.syscolumns d1c2 ON d1o2.id = d1c2.id  
JOIN '+@db1+'.dbo.systypes d1t2 ON d1c2.xusertype = d1t2.xusertype  
where d1o2.type = ''U''  
and d1o2.name = d2o.name   
and d1c2.name = d2c.name   
and d1t2.name = d2t.name  
and d1c2.length = d2c.length))  
order by coalesce(d1o.name,d2o.name), d1c.name  
open Diff  
fetch next from Diff into @TName1, @TName2, @CName1, @CName2, @TypeName1, @TypeName2,  
@CLen1, @CLen2, @Type1, @Type2  
set @PrevTName = ''''  
set @DiffStructure = 0  
while @@fetch_status = 0  
begin  
if Coalesce(@TName1,@TName2) <> @PrevTName  
begin  
if @PrevTName <> '''' and @DiffStructure = 1  
begin  
insert into #DiffStructure values (@PrevTName)  
set @DiffStructure = 0  
end  
set @PrevTName = Coalesce(@TName1,@TName2)  
print @PrevTName  
end  
if @CName2 is null  
print '' Colimn ''+RTRIM(@CName1)+'' not in '+@db2+'''  
else  
if @CName1 is null  
print '' Colimn ''+RTRIM(@CName2)+'' not in '+@db1+'''  
else  
if @TypeName1 <> @TypeName2  
print '' Colimn ''+RTRIM(@CName1)+'': in '+@db1+' - ''+RTRIM(@TypeName1)+'', in '+@db2+' - ''+RTRIM(@TypeName2)  
else --the columns are not null(are in both dbs) and types are equal,then length are diff  
print '' Colimn ''+RTRIM(@CName1)+'': in '+@db1+' - ''+RTRIM(@TypeName1)+''(''+  
LTRIM(STR(CASE when @TypeName1=''nChar'' or @TypeName1 = ''nVarChar'' then @CLen1/2 else @CLen1 end))+  
''), in '+@db2+' - ''+RTRIM(@TypeName2)+''(''+  
LTRIM(STR(CASE when @TypeName1=''nChar'' or @TypeName1 = ''nVarChar'' then @CLen2/2 else @CLen2 end))+'')''  
if @Type1 = @Type2  
set @DiffStructure=@DiffStructure -- Do nothing. Cannot invert predicate  
else  
set @DiffStructure = 1  
fetch next from Diff into @TName1, @TName2, @CName1, @CName2, @TypeName1, @TypeName2,  
@CLen1, @CLen2, @Type1, @Type2  
end  
deallocate Diff  
if @DiffStructure = 1  
insert into #DiffStructure values (@PrevTName)  
'  
exec (@sqlStr)  
if (select count(*) from #DiffStructure) > 0  
begin  
print CHAR(10)+'The table(s) have the same name and different structure in the databases:'  
select distinct * from #DiffStructure   
delete from #TabToCheck where name in (select * from #DiffStructure)  
end  
else  
print CHAR(10)+'There are no tables with the same name and structural differences in the databases'+CHAR(10)+CHAR(10)  
if @OnlyStructure = 1  
begin  
print 'The option ''Only compare structures'' was specified. End of work.'  
return  
end  
exec ('declare @Name sysname select @Name=d1o.name  
from '+@db1+'.dbo.sysobjects d1o, '+@db2+'.dbo.sysobjects d2o   
where d1o.name = d2o.name and d1o.type = ''U'' and d2o.type = ''U''  
and d1o.name not in (''dtproperties'')   
and d1o.name in (select * from #TabToCheck)')  
if @@rowcount = 0  
begin  
print 'There are no tables with the same name and structure in the databases to compare. End of work.'  
return  
end  
  
  
-----------------------------------------------------------------------------------------  
-- Comparing data   
-----------------------------------------------------------------------------------------  
-- ##CompareStr - will be used to pass comparing strings into dynamic script  
-- to execute the string  
if exists (select * from tempdb.dbo.sysobjects where name like '##CompareStr%')  
drop table ##CompareStr  
create table ##CompareStr (Ind int, CompareStr varchar(8000))  
  
if exists (select * from tempdb.dbo.sysobjects where name like '#DiffTables%')  
drop table #DiffTables  
create table #DiffTables (Name sysname)  
if exists (select * from tempdb.dbo.sysobjects where name like '#IdenticalTables%')  
drop table #IdenticalTables  
create table #IdenticalTables (Name sysname)  
if exists (select * from tempdb.dbo.sysobjects where name like '#EmptyTables%')  
drop table #EmptyTables  
create table #EmptyTables (Name sysname)  
if exists (select * from tempdb.dbo.sysobjects where name like '#NoPKTables%')  
drop table #NoPKTables  
create table #NoPKTables (Name sysname)  
  
if exists (select * from tempdb.dbo.sysobjects where name like '#IndList1%')  
truncate table #IndList1  
else   
create table #IndList1 (IndId int, IndStatus int,  
KeyAndStr varchar(7000), KeyCommaStr varchar(1000))  
if exists (select * from tempdb.dbo.sysobjects where name like '#IndList2%')  
truncate table #IndList2  
else  
create table #IndList2 (IndId smallint, IndStatus int,  
KeyAndStr varchar(7000), KeyCommaStr varchar(1000))  
  
print Replicate('-',51)  
print 'Comparing data in tables with indentical structure:'  
print Replicate('-',51)  
--------------------------------------------------------------------------------------------  
-- Cursor for all tables in dbs (or for all specified tables if parameter @TabList is passed)  
--------------------------------------------------------------------------------------------  
declare @SqlStrGetListOfKeys1 varchar(8000)  
declare @SqlStrGetListOfKeys2 varchar(8000)  
declare @SqlStrGetListOfColumns varchar(8000)  
declare @SqlStrCompareUKeyTables varchar(8000)  
declare @SqlStrCompareNonUKeyTables varchar(8000)  
set @SqlStrGetListOfKeys1 = '  
declare @sqlStr varchar(8000)  
declare @ExecSqlStr varchar(8000)  
declare @PrintSqlStr varchar(8000)  
declare @Tab varchar(128)  
declare @d1User varchar(128)  
declare @d2User varchar(128)  
declare @KeyAndStr varchar(8000)   
declare @KeyCommaStr varchar(8000)   
declare @AndStr varchar(8000)   
declare @Eq varchar(8000)   
declare @IndId int  
declare @IndStatus int  
declare @CurrIndId smallint  
declare @CurrStatus int  
declare @UKey sysname   
declare @Col varchar(128)  
declare @LastUsedCol varchar(128)  
declare @xType int  
declare @Len int  
declare @SelectStr varchar(8000)   
declare @ExecSql nvarchar(1000)   
declare @NotInDB1 bit   
declare @NotInDB2 bit   
declare @NotEq bit   
declare @Numb int  
declare @Cnt1 int  
declare @Cnt2 int  
set @Numb = 0  
  
declare @StrInd int  
declare @i int  
declare @PrintStr varchar(8000)  
declare @ExecStr varchar(8000)  
declare TabCur cursor for   
  
select d1o.name, d1u.name, d2u.name from '+@db1+'.dbo.sysobjects d1o, '+@db2+'.dbo.sysobjects d2o,  
'+@db1+'.dbo.sysusers d1u, '+@db2+'.dbo.sysusers d2u   
where d1o.name = d2o.name and d1o.type = ''U'' and d2o.type = ''U''  
and d1o.uid = d1u.uid and d2o.uid = d2u.uid   
and d1o.name not in (''dtproperties'')   
and d1o.name in (select * from #TabToCheck)  
order by 1  
  
open TabCur   
fetch next from TabCur into @Tab, @d1User, @d2User   
while @@fetch_status = 0   
begin   
set @Numb = @Numb + 1  
print Char(13)+Char(10)+LTRIM(STR(@Numb))+''. TABLE: [''+@Tab+''] ''  
  
set @ExecSql = ''SELECT @Cnt = count(*) FROM '+@db1+'.[''+@d1User+''].[''+@Tab+'']''  
exec sp_executesql @ExecSql, N''@Cnt int output'', @Cnt = @Cnt1 output  
print CHAR(10)+STR(@Cnt1)+'' rows in '+@db1+'''  
set @ExecSql = ''SELECT @Cnt = count(*) FROM '+@db2+'.[''+@d2User+''].[''+@Tab+'']''  
exec sp_executesql @ExecSql, N''@Cnt int output'', @Cnt = @Cnt2 output  
print STR(@Cnt2)+'' rows in '+@db2+'''  
if @Cnt1 = 0 and @Cnt2 = 0  
begin  
exec ('' insert into #EmptyTables values(''''[''+@Tab+'']'''')'')   
goto NextTab  
end  
set @KeyAndStr = ''''   
set @KeyCommaStr = ''''   
set @NotInDB1 = 0  
set @NotInDB2 = 0   
set @NotEq = 0  
set @KeyAndStr = ''''   
set @KeyCommaStr = ''''   
truncate table #IndList1  
declare UKeys cursor fast_forward for   
select i.indid, i.status, c.name, c.xType from '+@db1+'.dbo.sysobjects o, '+@db1+'.dbo.sysindexes i, '+@db1+'.dbo.sysindexkeys k, '+@db1+'.dbo.syscolumns c   
where i.id = o.id and o.name = @Tab  
and (i.status & 2)<>0   
and k.id = o.id and k.indid = i.indid   
and c.id = o.id and c.colid = k.colid   
order by i.indid, c.name  
open UKeys   
fetch next from UKeys into @IndId, @IndStatus, @UKey, @xType  
set @CurrIndId = @IndId  
set @CurrStatus = @IndStatus  
while @@fetch_status = 0   
begin   
if @KeyAndStr <> ''''  
begin   
set @KeyAndStr = @KeyAndStr + '' and '' + CHAR(10)   
set @KeyCommaStr = @KeyCommaStr + '', ''   
end   
if @xType = 175 or @xType = 167 or @xType = 239 or @xType = 231 -- char, varchar, nchar, nvarchar  
begin  
set @KeyAndStr = @KeyAndStr + '' ISNULL(d1.[''+@UKey+''],''''!#null$'''')=ISNULL(d2.[''+@UKey+''],''''!#null$'''') ''  
end  
if @xType = 173 or @xType = 165 -- binary, varbinary  
begin  
set @KeyAndStr = @KeyAndStr +  
'' CASE WHEN d1.[''+@UKey+''] is null THEN 0x4D4FFB23A49411D5BDDB00A0C906B7B4 ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN 0x4D4FFB23A49411D5BDDB00A0C906B7B4 ELSE d2.[''+@UKey+''] END ''  
end  
else if @xType = 56 or @xType = 127 or @xType = 60 or @xType = 122 -- int, 127 - bigint,60 - money, 122 - smallmoney  
begin  
set @KeyAndStr = @KeyAndStr +   
'' CASE WHEN d1.[''+@UKey+''] is null THEN 971428763405345098745 ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN 971428763405345098745 ELSE d2.[''+@UKey+''] END ''  
end  
else if @xType = 106 or @xType = 108 -- int, decimal, numeric  
begin  
set @KeyAndStr = @KeyAndStr +   
'' CASE WHEN d1.[''+@UKey+''] is null THEN 71428763405345098745098.8723 ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN 71428763405345098745098.8723 ELSE d2.[''+@UKey+''] END ''  
end  
else if @xType = 62 or @xType = 59 -- 62 - float, 59 - real  
begin   
set @KeyAndStr = @KeyAndStr +   
'' CASE WHEN d1.[''+@UKey+''] is null THEN 8764589764.22708E237 ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN 8764589764.22708E237 ELSE d2.[''+@UKey+''] END ''  
end  
else if @xType = 52 or @xType = 48 or @xType = 104 -- smallint, tinyint, bit  
begin  
set @KeyAndStr = @KeyAndStr + '' CASE WHEN d1.[''+@UKey+''] is null THEN 99999 ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN 99999 ELSE d2.[''+@UKey+''] END ''  
end  
else if @xType = 36 -- 36 - id   
begin  
set @KeyAndStr = @KeyAndStr +  
'' CASE WHEN d1.[''+@UKey+''] is null''+  
'' THEN CONVERT(uniqueidentifier,''''1CD827A0-744A-4866-8401-B9902CF2D4FB'''')''+  
'' ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null''+  
'' THEN CONVERT(uniqueidentifier,''''1CD827A0-744A-4866-8401-B9902CF2D4FB'''')''+  
'' ELSE d2.[''+@UKey+''] END''  
end  
else if @xType = 61 or @xType = 58 -- datetime, smalldatetime  
begin  
set @KeyAndStr = @KeyAndStr +  
'' CASE WHEN d1.[''+@UKey+''] is null THEN ''''!#null$'''' ELSE CONVERT(varchar(40),d1.[''+@UKey+''],109) END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN ''''!#null$'''' ELSE CONVERT(varchar(40),d2.[''+@UKey+''],109) END ''  
end  
else if @xType = 189 -- timestamp (189)   
begin  
set @KeyAndStr = @KeyAndStr + '' d1.[''+@UKey+'']=d2.[''+@UKey+''] ''  
end  
else if @xType = 98 -- SQL_variant  
begin  
set @KeyAndStr = @KeyAndStr + '' ISNULL(d1.[''+@UKey+''],''''!#null$'''')=ISNULL(d2.[''+@UKey+''],''''!#null$'''') ''  
end  
set @KeyCommaStr = @KeyCommaStr + '' d1.''+@UKey   
fetch next from UKeys into @IndId, @IndStatus, @UKey, @xType  
if @IndId <> @CurrIndId  
begin  
insert into #IndList1 values (@CurrIndId, @CurrStatus, @KeyAndStr, @KeyCommaStr)  
set @CurrIndId = @IndId  
set @CurrStatus = @IndStatus  
set @KeyAndStr = ''''  
set @KeyCommaStr = ''''   
end  
end   
deallocate UKeys   
insert into #IndList1 values (@CurrIndId, @CurrStatus, @KeyAndStr, @KeyCommaStr)'  
set @SqlStrGetListOfKeys2 = '  
set @KeyAndStr = ''''   
set @KeyCommaStr = ''''   
truncate table #IndList2  
declare UKeys cursor fast_forward for   
select i.indid, i.status, c.name, c.xType from '+@db2+'.dbo.sysobjects o, '+@db2+'.dbo.sysindexes i, '+@db2+'.dbo.sysindexkeys k, '+@db2+'.dbo.syscolumns c   
where i.id = o.id and o.name = @Tab  
and (i.status & 2)<>0   
and k.id = o.id and k.indid = i.indid   
and c.id = o.id and c.colid = k.colid   
order by i.indid, c.name  
open UKeys   
fetch next from UKeys into @IndId, @IndStatus, @UKey, @xType  
set @CurrIndId = @IndId  
set @CurrStatus = @IndStatus  
while @@fetch_status = 0   
begin   
if @KeyAndStr <> ''''  
begin   
set @KeyAndStr = @KeyAndStr + '' and '' + CHAR(10)   
set @KeyCommaStr = @KeyCommaStr + '', ''   
end   
if @xType = 175 or @xType = 167 or @xType = 239 or @xType = 231 -- char, varchar, nchar, nvarchar  
begin  
set @KeyAndStr = @KeyAndStr + '' ISNULL(d1.[''+@UKey+''],''''!#null$'''')=ISNULL(d2.[''+@UKey+''],''''!#null$'''') ''  
end  
if @xType = 173 or @xType = 165 -- binary, varbinary  
begin  
set @KeyAndStr = @KeyAndStr +  
'' CASE WHEN d1.[''+@UKey+''] is null THEN 0x4D4FFB23A49411D5BDDB00A0C906B7B4 ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN 0x4D4FFB23A49411D5BDDB00A0C906B7B4 ELSE d2.[''+@UKey+''] END ''  
end  
else if @xType = 56 or @xType = 127 or @xType = 60 or @xType = 122 -- int, 127 - bigint,60 - money, 122 - smallmoney  
begin  
set @KeyAndStr = @KeyAndStr +   
'' CASE WHEN d1.[''+@UKey+''] is null THEN 971428763405345098745 ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN 971428763405345098745 ELSE d2.[''+@UKey+''] END ''  
end  
else if @xType = 106 or @xType = 108 -- int, decimal, numeric  
begin  
set @KeyAndStr = @KeyAndStr +   
'' CASE WHEN d1.[''+@UKey+''] is null THEN 71428763405345098745098.8723 ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN 71428763405345098745098.8723 ELSE d2.[''+@UKey+''] END ''  
end  
else if @xType = 62 or @xType = 59 -- 62 - float, 59 - real  
begin   
set @KeyAndStr = @KeyAndStr +   
'' CASE WHEN d1.[''+@UKey+''] is null THEN 8764589764.22708E237 ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN 8764589764.22708E237 ELSE d2.[''+@UKey+''] END ''  
end  
else if @xType = 52 or @xType = 48 or @xType = 104 -- smallint, tinyint, bit  
begin  
set @KeyAndStr = @KeyAndStr + '' CASE WHEN d1.[''+@UKey+''] is null THEN 99999 ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN 99999 ELSE d2.[''+@UKey+''] END ''  
end  
else if @xType = 36 -- 36 - id   
begin  
set @KeyAndStr = @KeyAndStr +  
'' CASE WHEN d1.[''+@UKey+''] is null''+  
'' THEN CONVERT(uniqueidentifier,''''1CD827A0-744A-4866-8401-B9902CF2D4FB'''')''+  
'' ELSE d1.[''+@UKey+''] END=''+  
''CASE WHEN d2.[''+@UKey+''] is null''+  
'' THEN CONVERT(uniqueidentifier,''''1CD827A0-744A-4866-8401-B9902CF2D4FB'''')''+  
'' ELSE d2.[''+@UKey+''] END''  
end  
else if @xType = 61 or @xType = 58 -- datetime, smalldatetime  
begin  
set @KeyAndStr = @KeyAndStr +  
'' CASE WHEN d1.[''+@UKey+''] is null THEN ''''!#null$'''' ELSE CONVERT(varchar(40),d1.[''+@UKey+''],109) END=''+  
''CASE WHEN d2.[''+@UKey+''] is null THEN ''''!#null$'''' ELSE CONVERT(varchar(40),d2.[''+@UKey+''],109) END ''  
end  
else if @xType = 189 -- timestamp (189)   
begin  
set @KeyAndStr = @KeyAndStr + '' d1.[''+@UKey+'']=d2.[''+@UKey+''] ''  
end  
else if @xType = 98 -- SQL_variant  
begin  
set @KeyAndStr = @KeyAndStr + '' ISNULL(d1.[''+@UKey+''],''''!#null$'''')=ISNULL(d2.[''+@UKey+''],''''!#null$'''') ''  
end  
set @KeyCommaStr = @KeyCommaStr + '' d1.''+@UKey   
fetch next from UKeys into @IndId, @IndStatus, @UKey, @xType  
if @IndId <> @CurrIndId  
begin  
insert into #IndList2 values (@CurrIndId, @CurrStatus, @KeyAndStr, @KeyCommaStr)  
set @CurrIndId = @IndId  
set @CurrStatus = @IndStatus  
set @KeyAndStr = ''''  
set @KeyCommaStr = ''''   
end  
end   
deallocate UKeys   
insert into #IndList2 values (@CurrIndId, @CurrStatus, @KeyAndStr, @KeyCommaStr)  
set @KeyCommaStr = null  
  
select @KeyCommaStr=i1.KeyCommaStr from #IndList1 i1  
join #IndList2 i2 on i1.KeyCommaStr = i2.KeyCommaStr  
where (i1.IndStatus & 2048)<> 0 and (i2.IndStatus & 2048)<>0  
  
if @KeyCommaStr is null   
set @KeyCommaStr = (select top 1 i1.KeyCommaStr from #IndList1 i1  
join #IndList2 i2 on i1.KeyCommaStr = i2.KeyCommaStr)  
set @KeyAndStr = (select TOP 1 KeyAndStr from #IndList1 where KeyCommaStr = @KeyCommaStr)  
if @KeyCommaStr is null  
set @KeyCommaStr = ''''  
if @KeyAndStr is null  
set @KeyAndStr = '''''  
set @SqlStrGetListOfColumns = '  
set @AndStr = ''''  
set @StrInd = 1  
declare Cols cursor local fast_forward for   
select c.name, c.xtype, c.length from '+@db1+'.dbo.sysobjects o, '+@db1+'.dbo.syscolumns c  
where o.id = c.id and o.name = @Tab   
and CHARINDEX(c.name, @KeyCommaStr) = 0  
open Cols   
fetch next from Cols into @Col, @xType, @len  
while @@fetch_status = 0   
begin   
if @xType = 175 or @xType = 167 or @xType = 239 or @xType = 231 -- char, varchar, nchar, nvarchar  
begin  
set @Eq = ''ISNULL(d1.[''+@Col+''],''''!#null$'''')=ISNULL(d2.[''+@Col+''],''''!#null$'''') ''  
end  
if @xType = 173 or @xType = 165 -- binary, varbinary  
begin  
set @Eq = ''CASE WHEN d1.[''+@Col+''] is null THEN 0x4D4FFB23A49411D5BDDB00A0C906B7B4 ELSE d1.[''+@Col+''] END=''+  
''CASE WHEN d2.[''+@Col+''] is null THEN 0x4D4FFB23A49411D5BDDB00A0C906B7B4 ELSE d2.[''+@Col+''] END ''  
end  
else if @xType = 56 or @xType = 127 or @xType = 60 or @xType = 122 -- int, 127 - bigint,60 - money, 122 - smallmoney  
begin  
set @Eq = ''CASE WHEN d1.[''+@Col+''] is null THEN 971428763405345098745 ELSE d1.[''+@Col+''] END=''+  
''CASE WHEN d2.[''+@Col+''] is null THEN 971428763405345098745 ELSE d2.[''+@Col+''] END ''  
end  
else if @xType = 106 or @xType = 108 -- int, decimal, numeric  
begin  
set @Eq = ''CASE WHEN d1.[''+@Col+''] is null THEN 71428763405345098745098.8723 ELSE d1.[''+@Col+''] END=''+  
''CASE WHEN d2.[''+@Col+''] is null THEN 71428763405345098745098.8723 ELSE d2.[''+@Col+''] END ''  
end  
else if @xType = 62 or @xType = 59 -- 62 - float, 59 - real  
begin   
set @Eq = ''CASE WHEN d1.[''+@Col+''] is null THEN 8764589764.22708E237 ELSE d1.[''+@Col+''] END=''+  
''CASE WHEN d2.[''+@Col+''] is null THEN 8764589764.22708E237 ELSE d2.[''+@Col+''] END ''  
end  
else if @xType = 52 or @xType = 48 or @xType = 104 -- smallint, tinyint, bit  
begin  
set @Eq = ''CASE WHEN d1.[''+@Col+''] is null THEN 99999 ELSE d1.[''+@Col+''] END=''+  
''CASE WHEN d2.[''+@Col+''] is null THEN 99999 ELSE d2.[''+@Col+''] END ''  
end  
else if @xType = 36 -- 36 - id   
begin  
set @Eq = ''CASE WHEN d1.[''+@Col+''] is null''+  
'' THEN CONVERT(uniqueidentifier,''''1CD827A0-744A-4866-8401-B9902CF2D4FB'''')''+  
'' ELSE d1.[''+@Col+''] END=''+  
''CASE WHEN d2.[''+@Col+''] is null''+  
'' THEN CONVERT(uniqueidentifier,''''1CD827A0-744A-4866-8401-B9902CF2D4FB'''')''+  
'' ELSE d2.[''+@Col+''] END''  
end  
else if @xType = 61 or @xType = 58 -- datetime, smalldatetime  
begin  
set @Eq =  
''CASE WHEN d1.[''+@Col+''] is null THEN ''''!#null$'''' ELSE CONVERT(varchar(40),d1.[''+@Col+''],109) END=''+  
''CASE WHEN d2.[''+@Col+''] is null THEN ''''!#null$'''' ELSE CONVERT(varchar(40),d2.[''+@Col+''],109) END ''  
end  
else if @xType = 34  
begin  
set @Eq = ''ISNULL(DATALENGTH(d1.[''+@Col+'']),0)=ISNULL(DATALENGTH(d2.[''+@Col+'']),0) ''   
end  
else if @xType = 35 or @xType = 99 -- text (35),ntext (99)   
begin  
set @Eq = ''ISNULL(SUBSTRING(d1.[''+@Col+''],1,DATALENGTH(d1.[''+@Col+  
''])),''''!#null$'''')=ISNULL(SUBSTRING(d2.[''+@Col+''],1,DATALENGTH(d2.[''+@Col+''])),''''!#null$'''') ''  
end  
else if @xType = 189   
begin  
if '+STR(@NoTimestamp)+' = 0   
set @Eq = ''d1.[''+@Col+'']=d2.[''+@Col+''] ''  
else  
set @Eq = ''1=1''  
end  
else if @xType = 98 -- SQL_variant  
begin  
set @Eq = ''ISNULL(d1.[''+@Col+''],''''!#null$'''')=ISNULL(d2.[''+@Col+''],''''!#null$'''') ''  
end  
if @AndStr = ''''  
set @AndStr = @AndStr + CHAR(10) + '' '' + @Eq   
else  
if len(@AndStr) + len('' and '' + @Eq)<8000  
set @AndStr = @AndStr + '' and '' + CHAR(10) + '' '' + @Eq   
else  
begin  
set @StrInd = @StrInd + 1  
Insert into ##CompareStr values(@StrInd,@AndStr)  
set @AndStr = '' and '' + @Eq   
end  
fetch next from Cols into @Col, @xType, @len   
end   
deallocate Cols '  
set @SqlStrCompareUKeyTables = '  
if @KeyAndStr <> ''''  
begin  
set @SelectStr = ''SELECT ''+ @KeyCommaStr+'' INTO ##NotInDb2 FROM '+@db1+'.[''+@d1User+''].[''+@Tab+''] d1 ''+   
'' WHERE not exists''+CHAR(10)+'' (SELECT * FROM '+@db2+'.[''+@d2User+''].[''+@Tab+''] d2 ''+   
'' WHERE ''+CHAR(10)+@KeyAndStr+'')''  
if '+STR(@VerboseLevel)+' = 1  
print CHAR(10)+''To find rows that are in '+@db1+', but are not in db2:''+CHAR(10)+  
REPLACE (@SelectStr, ''into ##NotInDB2'','''')  
exec (@SelectStr)   
if @@rowcount > 0   
set @NotInDB2 = 1   
set @SelectStr = ''SELECT ''+@KeyCommaStr+'' INTO ##NotInDB1 FROM '+@db2+'.[''+@d2User+''].[''+@Tab+''] d1 ''+   
'' WHERE not exists''+CHAR(10)+'' (SELECT * FROM '+@db1+'.[''+@d1User+''].[''+@Tab+''] d2 ''+   
'' WHERE ''+CHAR(10)+@KeyAndStr+'')''   
if '+STR(@VerboseLevel)+' = 1  
print CHAR(10)+''To find rows that are in '+@db2+', but are not in '+@db1+':''+CHAR(10)+  
REPLACE (@SelectStr, ''into ##NotInDB1'','''')  
exec (@SelectStr)   
if @@rowcount > 0   
set @NotInDB1 = 1   
-- if there are non-key columns  
if @AndStr <> ''''   
begin  
set @PrintStr = '' Print ''  
set @ExecStr = '' exec (''  
set @sqlStr = ''''  
Insert into ##CompareStr values(1,  
''SELECT ''+ @KeyCommaStr+'' INTO ##NotEq FROM '+@db2+'.[''+@d2User+''].[''+@Tab+''] d1 ''+   
'' INNER JOIN '+@db1+'.[''+@d1User+''].[''+@Tab+''] d2 ON ''+CHAR(10)+@KeyAndStr+CHAR(10)+''WHERE not('')   
-- Adding last string in temp table containing a comparing string to execute  
set @StrInd = @StrInd + 1  
Insert into ##CompareStr values(@StrInd,@AndStr+'')'')  
set @i = 1  
while @i <= @StrInd  
begin  
set @sqlStr = @sqlStr + '' declare @Str''+LTRIM(STR(@i))+'' varchar(8000) ''+  
''select @Str''+LTRIM(STR(@i))+''=CompareStr FROM ##CompareStr WHERE ind = ''+STR(@i)  
if @ExecStr <> '' exec (''  
set @ExecStr = @ExecStr + ''+''  
if @PrintStr <> '' Print ''  
set @PrintStr = @PrintStr + ''+''  
set @ExecStr = @ExecStr + ''@Str''+LTRIM(STR(@i))  
set @PrintStr = @PrintStr + '' REPLACE(@Str''+LTRIM(STR(@i))+'','''' into ##NotEq'''','''''''') ''  
set @i = @i + 1  
end  
set @ExecStr = @ExecStr + '') ''  
set @ExecSqlStr = @sqlStr + @ExecStr   
set @PrintSqlStr = @sqlStr +   
'' Print CHAR(10)+''''To find rows that are different in non-key columns:'''' ''+  
@PrintStr   
if '+STR(@VerboseLevel)+' = 1  
exec (@PrintSqlStr)  
exec (@ExecSqlStr)  
  
if @@rowcount > 0   
set @NotEq = 1   
end  
else  
if '+STR(@VerboseLevel)+' = 1  
print CHAR(10)+''There are no non-key columns in the table''  
truncate table ##CompareStr  
if @NotInDB1 = 1 or @NotInDB2 = 1 or @NotEq = 1  
begin   
print CHAR(10)+''Data are different''  
if @NotInDB2 = 1 and '+STR(@NumbToShow)+' > 0  
begin  
print ''These key values exist in '+@db1+', but do not exist in '+@db2+': ''  
set @SelectStr = ''select top ''+STR('+STR(@NumbToShow)+')+'' * from ##NotInDB2''  
exec (@SelectStr)  
end  
if @NotInDB1 = 1 and '+STR(@NumbToShow)+' > 0  
begin  
print ''These key values exist in '+@db2+', but do not exist in '+@db1+': ''  
set @SelectStr = ''select top ''+STR('+STR(@NumbToShow)+')+'' * from ##NotInDB1''  
exec (@SelectStr)  
end  
if @NotEq = 1 and '+STR(@NumbToShow)+' > 0  
begin  
print ''Row(s) with these key values contain differences in non-key columns: ''  
set @SelectStr = ''select top ''+STR('+STR(@NumbToShow)+')+'' * from ##NotEq''  
exec (@SelectStr)   
end  
exec (''insert into #DiffTables values(''''[''+@Tab+'']'''')'')   
end   
else  
begin  
print CHAR(10)+''Data are identical''  
exec ('' insert into #IdenticalTables values(''''[''+@Tab+'']'''')'')   
end  
if exists (select * from tempdb.dbo.sysobjects where name like ''##NotEq%'')  
drop table ##NotEq  
end   
else '  
set @SqlStrCompareNonUKeyTables = '  
begin  
exec (''insert into #NoPKTables values(''''[''+@Tab+'']'''')'')  
set @PrintStr = '' Print ''  
set @ExecStr = '' exec (''  
set @sqlStr = ''''  
Insert into ##CompareStr values(1,  
''SELECT ''+  
'' * INTO ##NotInDB2 FROM '+@db1+'.[''+@d1User+''].[''+@Tab+''] d1 WHERE not exists ''+CHAR(10)+  
'' (SELECT * FROM '+@db2+'.[''+@d2User+''].[''+@Tab+''] d2 WHERE '')  
set @StrInd = @StrInd + 1  
Insert into ##CompareStr values(@StrInd,@AndStr+'')'')  
set @i = 1  
while @i <= @StrInd  
begin  
set @sqlStr = @sqlStr + '' declare @Str''+LTRIM(STR(@i))+'' varchar(8000) ''+  
''select @Str''+LTRIM(STR(@i))+''=CompareStr FROM ##CompareStr WHERE ind = ''+STR(@i)  
if @ExecStr <> '' exec (''  
set @ExecStr = @ExecStr + ''+''  
if @PrintStr <> '' Print ''  
set @PrintStr = @PrintStr + ''+''  
set @ExecStr = @ExecStr + ''@Str''+LTRIM(STR(@i))  
set @PrintStr = @PrintStr + '' REPLACE(@Str''+LTRIM(STR(@i))+'','''' into ##NotInDB2'''','''''''') ''  
set @i = @i + 1  
end  
set @ExecStr = @ExecStr + '') ''  
set @ExecSqlStr = @sqlStr + @ExecStr   
set @PrintSqlStr = @sqlStr +  
'' Print CHAR(10)+''''To find rows that are in '+@db1+', but are not in '+@db2+':'''' ''+  
@PrintStr   
if '+STR(@VerboseLevel)+' = 1  
exec (@PrintSqlStr)  
exec (@ExecSqlStr)  
  
if @@rowcount > 0   
set @NotInDB2 = 1   
delete from ##CompareStr where ind = 1  
set @PrintStr = '' Print ''  
set @ExecStr = '' exec (''  
set @sqlStr = ''''  
Insert into ##CompareStr values(1,  
''SELECT ''+  
'' * INTO ##NotInDB1 FROM '+@db2+'.[''+@d2User+''].[''+@Tab+''] d1 WHERE not exists ''+CHAR(10)+  
'' (SELECT * FROM '+@db1+'.[''+@d1User+''].[''+@Tab+''] d2 WHERE '')  
set @i = 1  
while @i <= @StrInd  
begin  
set @sqlStr = @sqlStr + '' declare @Str''+LTRIM(STR(@i))+'' varchar(8000) ''+  
''select @Str''+LTRIM(STR(@i))+''=CompareStr FROM ##CompareStr WHERE ind = ''+STR(@i)  
if @ExecStr <> '' exec (''  
set @ExecStr = @ExecStr + ''+''  
if @PrintStr <> '' Print ''  
set @PrintStr = @PrintStr + ''+''  
set @ExecStr = @ExecStr + ''@Str''+LTRIM(STR(@i))  
set @PrintStr = @PrintStr + '' REPLACE(@Str''+LTRIM(STR(@i))+'','''' into ##NotInDB1'''','''''''') ''  
set @i = @i + 1  
end  
set @ExecStr = @ExecStr + '') ''  
set @ExecSqlStr = @sqlStr + @ExecStr   
set @PrintSqlStr = @sqlStr +  
'' Print CHAR(10)+''''To find rows that are in '+@db2+', but are not in '+@db1+':'''' ''+  
@PrintStr   
if '+STR(@VerboseLevel)+' = 1  
exec (@PrintSqlStr)  
exec (@ExecSqlStr)  
  
if @@rowcount > 0   
set @NotInDB1 = 1   
truncate table ##CompareStr  
if @NotInDB1 = 1 or @NotInDB2 = 1  
begin   
print CHAR(10)+''Data are different''  
if @NotInDB2 = 1 and '+STR(@NumbToShow)+' > 0  
begin  
print ''The row(s) exist in '+@db1+', but do not exist in '+@db2+': ''  
set @SelectStr = ''select top ''+STR('+STR(@NumbToShow)+')+'' * from ##NotInDB2''  
exec (@SelectStr)  
end  
if @NotInDB1 = 1 and '+STR(@NumbToShow)+' > 0  
begin  
print ''The row(s) exist in '+@db2+', but do not exist in '+@db1+': ''  
set @SelectStr = ''select top ''+STR('+STR(@NumbToShow)+')+'' * from ##NotInDB1''  
exec (@SelectStr)  
end  
exec (''insert into #DiffTables values(''''[''+@Tab+'']'''')'')   
end   
else  
begin  
print CHAR(10)+''Data are identical''  
exec ('' insert into #IdenticalTables values(''''[''+@Tab+'']'''')'')   
end  
end  
if exists (select * from tempdb.dbo.sysobjects where name like ''##NotInDB1%'')  
drop table ##NotInDB1  
if exists (select * from tempdb.dbo.sysobjects where name like ''##NotInDB2%'')  
drop table ##NotInDB2  
NextTab:  
fetch next from TabCur into @Tab, @d1User, @d2User   
end   
deallocate TabCur   
'  
exec (@SqlStrGetListOfKeys1+@SqlStrGetListOfKeys2+@SqlStrGetListOfColumns+  
@SqlStrCompareUKeyTables+@SqlStrCompareNonUKeyTables)  
print ' '  
SET NOCOUNT OFF  
if (select count(*) from #NoPKTables) > 0  
begin  
select name as 'Table(s) without Unique key:' from #NoPKTables   
end  
if (select count(*) from #DiffTables) > 0  
begin  
select name as 'Table(s) with the same name & structure, but different data:' from #DiffTables   
end  
else  
print CHAR(10)+'No tables with the same name & structure, but different data'+CHAR(10)  
if (select count(*) from #IdenticalTables) > 0  
begin  
select name as 'Table(s) with the same name & structure and identical data:' from #IdenticalTables   
end  
if (select count(*) from #EmptyTables) > 0  
begin  
select name as 'Table(s) with the same name & structure and empty in the both databases:' from #EmptyTables   
end  
drop table #TabToCheck  
drop table ##CompareStr  
drop table #DiffTables  
drop table #IdenticalTables  
drop table #EmptyTables  
drop table #NoPKTables  
drop table #IndList1  
drop table #IndList2  
return  
  


  -------------------------------

GO

/****** Object:  StoredProcedure [dbo].[sp_executando]    Script Date: 05/12/2022 10:20:28 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO



 create procedure [dbo].[sp_executando] as   
set nocount on

-- Existe todos os processos em execu��o na instancia sql server
-- De www.clouddbm.com Opensource Copywrited by Gilberto Rosa (gilberto.rosa@clouddbm.com)
-- Script executado em mais de 10 mil Bancos de Dados, valide seu ambiente e tenha backup

  
declare @QualID varchar(5)  
print '....................................................................................................................................'  
print 'Processos com status RUNNABLE !'  
print ''  
create table #tmpProc (spid         varchar(5),  
                       dbname       varchar(15),  
                       hostname     varchar(15),  
                       cpu          integer,  
                       program_name varchar(35),  
                       nt_username  varchar(15),  
                       mem_usage    integer,  
                       cmd          varchar(30),  
                       LoginName    varchar(15),  
                       hostprocess  integer )  
  
insert into #tmpProc  
select convert(varchar(5),spid), convert(varchar(15),db_name(dbid)) Database_Name,    
       convert(varchar(15),hostname) Hostname, cpu,  
       convert(varchar(35),program_name) Program_Name,   
       convert(varchar(15),nt_username) NT_Username, memusage, cmd, convert(varchar(15),loginame) LoginName,hostprocess  
from master.dbo.sysprocesses (nolock)  
where status like "RUNN%" order by cpu DESC  
select * from #tmpProc  
set RowCount 1  
select @QualID = spid from #tmpProc  
While @@RowCount <> 0  
  Begin  
   Print ""  
   Print "                                       ��� Comando executado pelo processo " + @QualID + " ���"  
   execute ( "dbcc inputbuffer ( " + @QualID + " )" )  
   delete from #tmpProc  
   select @QualID = spid from #tmpProc  
  End  
drop table #tmpProc  
set rowcount 0  
  
  
----------------------------
GO

/****** Object:  StoredProcedure [dbo].[sp_findText]    Script Date: 05/12/2022 10:20:28 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO




-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------  
--  
-- Procedure :  spu_findText  
--  
-- Description : Search every stored procedure for any references to a specified string of text.  
--  
-- Development : Microsoft SQL Server V7.0 / SQL Server 2000.  
-- Patches : SP3 - SQL v7.0 / SP1 - SQL 2000.  
--   
-- Platfrom : Windows 2000 Server.  
-- Patches : SP1.  
--  
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------  
--   
-- History.  
--  
-- Date.  Version. Programmer. Details.  
--  
-- 30/09/2000 1.0.0.  Paul Hobbs Written.  
--  
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------  
  
CREATE PROCEDURE [dbo].[sp_findText] (  
  
    @text            VARCHAR(50)  
  
) AS  
  
    -- Adjust search text to find all contains.  
    SET @text = '%' + @text + '%'  
  
    --  Declare general purpose variables.  
    DECLARE @line    VARCHAR(300)  
    DECLARE @char    CHAR  
    DECLARE @lineNo  INTEGER  
    DECLARE @counter INTEGER  
  
    -- Declare cursor structure.  
    DECLARE @proc    VARCHAR(100),  
            @usage   VARCHAR(4000)  
  
    --  Declare cursor of stored procedures.  
    DECLARE codeCursor CURSOR  
    FOR  
        SELECT SUBSTRING(OBJECT_NAME(id),1, 100) AS sproc,  
               text  
        FROM   syscomments  
        WHERE  text LIKE @text  
  
    --  Open cursor and fetch first row.   
    OPEN codeCursor  
    FETCH NEXT FROM codeCursor  
        INTO @proc,@usage  
  
    --  Check if any stored procedures were found.  
    IF @@FETCH_STATUS <> 0 BEGIN   
        PRINT 'Text ''' + SUBSTRING(@text,2,LEN(@text)-2) + ''' not found in stored procedures on database ' + @@SERVERNAME + '.' + DB_NAME()  
  
        -- Close and release code cursor.  
        CLOSE codeCursor  
        DEALLOCATE codeCursor  
        RETURN  
    END  
  
    --  Display column titles.  
    PRINT 'Procedure' + CHAR(9) + 'Line' + CHAR(9) + 'Reference ' + CHAR(13) + CHAR(13)  
  
    --  Search each stored procedure within code cursor.  
    WHILE @@FETCH_STATUS = 0 BEGIN  
        SET @lineNo  = 0  
        SET @counter = 1  
  
        -- Process each line.  
        WHILE (@counter <> LEN(@usage)) BEGIN  
            SET @char = SUBSTRING(@usage,@counter,1)  
  
            -- Check for line breaks.  
            IF (@char = CHAR(13)) BEGIN  
                SET @lineNo = @lineNo + 1  
  
                -- Check if we found the specified text.  
                IF (PATINDEX(@text,@line) <> 0)   
                    PRINT @proc + CHAR(9) + STR(@lineNo) + CHAR(9) + LTRIM(@line)      
              
                SET @line = ''  
     END ELSE  
         IF (@char <> CHAR(10))  
      SET @line = @line + @char  
  
                SET @counter = @counter + 1  
             
        END  
     
        FETCH NEXT FROM codeCursor  
            INTO @proc,@usage  
    END  
  
    --  Close and release cursor.  
    CLOSE codeCursor  
    DEALLOCATE codeCursor  
  
    RETURN  
  
  
  ----------------------

GO

/****** Object:  StoredProcedure [dbo].[sp_generate_inserts]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO




CREATE PROC [dbo].[sp_generate_inserts]  
(  
 @table_name varchar(776),    -- The table/view for which the INSERT statements will be generated using the existing data  
 @target_table varchar(776) = NULL,  -- Use this parameter to specify a different table name into which the data will be inserted  
 @include_column_list bit = 1,  -- Use this parameter to include/ommit column list in the generated INSERT statement  
 @from varchar(800) = NULL,   -- Use this parameter to filter the rows based on a filter condition (using WHERE)  
 @include_timestamp bit = 0,   -- Specify 1 for this parameter, if you want to include the TIMESTAMP/ROWVERSION column's data in the INSERT statement  
 @debug_mode bit = 0,   -- If @debug_mode is set to 1, the SQL statements constructed by this procedure will be printed for later examination  
 @owner varchar(64) = NULL,  -- Use this parameter if you are not the owner of the table  
 @ommit_images bit = 0,   -- Use this parameter to generate INSERT statements by omitting the 'image' columns  
 @ommit_identity bit = 0,  -- Use this parameter to ommit the identity columns  
 @top int = NULL,   -- Use this parameter to generate INSERT statements only for the TOP n rows  
 @cols_to_include varchar(8000) = NULL, -- List of columns to be included in the INSERT statement  
 @cols_to_exclude varchar(8000) = NULL, -- List of columns to be excluded from the INSERT statement  
 @disable_constraints bit = 0,  -- When 1, disables foreign key constraints and enables them after the INSERT statements  
 @ommit_computed_cols bit = 0  -- When 1, computed columns will not be included in the INSERT statement  
   
)  
AS  
BEGIN  
  
/***********************************************************************************************************  
Procedure: sp_generate_inserts  (Build 22)   
  (Copyright � 2002 Narayana Vyas Kondreddi. All rights reserved.)  
                                            
Purpose: To generate INSERT statements from existing data.   
  These INSERTS can be executed to regenerate the data at some other location.  
  This procedure is also useful to create a database setup, where in you can   
  script your data along with your table definitions.  
  
Written by: Narayana Vyas Kondreddi  
         http://vyaskn.tripod.com  
  
Acknowledgements:  
  Divya Kalra -- For beta testing  
  Mark Charsley -- For reporting a problem with scripting uniqueidentifier columns with NULL values  
  Artur Zeygman -- For helping me simplify a bit of code for handling non-dbo owned tables  
  Joris Laperre   -- For reporting a regression bug in handling text/ntext columns  
  
Tested on:  SQL Server 7.0 and SQL Server 2000  
  
Date created: January 17th 2001 21:52 GMT  
  
Date modified: May 1st 2002 19:50 GMT  
  
Email:   vyaskn@hotmail.com  
  
NOTE:  This procedure may not work with tables with too many columns.  
  Results can be unpredictable with huge text columns or SQL Server 2000's sql_variant data types  
  Whenever possible, Use @include_column_list parameter to ommit column list in the INSERT statement, for better results  
  IMPORTANT: This procedure is not tested with internation data (Extended characters or Unicode). If needed  
  you might want to convert the datatypes of character variables in this procedure to their respective unicode counterparts  
  like nchar and nvarchar  
    
  
Example 1: To generate INSERT statements for table 'titles':  
    
  EXEC sp_generate_inserts 'titles'  
  
Example 2:  To ommit the column list in the INSERT statement: (Column list is included by default)  
  IMPORTANT: If you have too many columns, you are advised to ommit column list, as shown below,  
  to avoid erroneous results  
    
  EXEC sp_generate_inserts 'titles', @include_column_list = 0  
  
Example 3: To generate INSERT statements for 'titlesCopy' table from 'titles' table:  
  
  EXEC sp_generate_inserts 'titles', 'titlesCopy'  
  
Example 4: To generate INSERT statements for 'titles' table for only those titles   
  which contain the word 'Computer' in them:  
  NOTE: Do not complicate the FROM or WHERE clause here. It's assumed that you are good with T-SQL if you are using this parameter  
  
  EXEC sp_generate_inserts 'titles', @from = "from titles where title like '%Computer%'"  
  
Example 5:  To specify that you want to include TIMESTAMP column's data as well in the INSERT statement:  
  (By default TIMESTAMP column's data is not scripted)  
  
  EXEC sp_generate_inserts 'titles', @include_timestamp = 1  
  
Example 6: To print the debug information:  
    
  EXEC sp_generate_inserts 'titles', @debug_mode = 1  
  
Example 7:  If you are not the owner of the table, use @owner parameter to specify the owner name  
  To use this option, you must have SELECT permissions on that table  
  
  EXEC sp_generate_inserts Nickstable, @owner = 'Nick'  
  
Example 8:  To generate INSERT statements for the rest of the columns excluding images  
  When using this otion, DO NOT set @include_column_list parameter to 0.  
  
  EXEC sp_generate_inserts imgtable, @ommit_images = 1  
  
Example 9:  To generate INSERT statements excluding (ommiting) IDENTITY columns:  
  (By default IDENTITY columns are included in the INSERT statement)  
  
  EXEC sp_generate_inserts mytable, @ommit_identity = 1  
  
Example 10:  To generate INSERT statements for the TOP 10 rows in the table:  
    
  EXEC sp_generate_inserts mytable, @top = 10  
  
Example 11:  To generate INSERT statements with only those columns you want:  
    
  EXEC sp_generate_inserts titles, @cols_to_include = "'title','title_id','au_id'"  
  
Example 12:  To generate INSERT statements by omitting certain columns:  
    
  EXEC sp_generate_inserts titles, @cols_to_exclude = "'title','title_id','au_id'"  
  
Example 13: To avoid checking the foreign key constraints while loading data with INSERT statements:  
    
  EXEC sp_generate_inserts titles, @disable_constraints = 1  
  
Example 14:  To exclude computed columns from the INSERT statement:  
  EXEC sp_generate_inserts MyTable, @ommit_computed_cols = 1  
***********************************************************************************************************/  
  
SET NOCOUNT ON  
  
--Making sure user only uses either @cols_to_include or @cols_to_exclude  
IF ((@cols_to_include IS NOT NULL) AND (@cols_to_exclude IS NOT NULL))  
 BEGIN  
  RAISERROR('Use either @cols_to_include or @cols_to_exclude. Do not use both the parameters at once',16,1)  
  RETURN -1 --Failure. Reason: Both @cols_to_include and @cols_to_exclude parameters are specified  
 END  
  
--Making sure the @cols_to_include and @cols_to_exclude parameters are receiving values in proper format  
IF ((@cols_to_include IS NOT NULL) AND (PATINDEX('''%''',@cols_to_include) = 0))  
 BEGIN  
  RAISERROR('Invalid use of @cols_to_include property',16,1)  
  PRINT 'Specify column names surrounded by single quotes and separated by commas'  
  PRINT 'Eg: EXEC sp_generate_inserts titles, @cols_to_include = "''title_id'',''title''"'  
  RETURN -1 --Failure. Reason: Invalid use of @cols_to_include property  
 END  
  
IF ((@cols_to_exclude IS NOT NULL) AND (PATINDEX('''%''',@cols_to_exclude) = 0))  
 BEGIN  
  RAISERROR('Invalid use of @cols_to_exclude property',16,1)  
  PRINT 'Specify column names surrounded by single quotes and separated by commas'  
  PRINT 'Eg: EXEC sp_generate_inserts titles, @cols_to_exclude = "''title_id'',''title''"'  
  RETURN -1 --Failure. Reason: Invalid use of @cols_to_exclude property  
 END  
  
  
--Checking to see if the database name is specified along wih the table name  
--Your database context should be local to the table for which you want to generate INSERT statements  
--specifying the database name is not allowed  
IF (PARSENAME(@table_name,3)) IS NOT NULL  
 BEGIN  
  RAISERROR('Do not specify the database name. Be in the required database and just specify the table name.',16,1)  
  RETURN -1 --Failure. Reason: Database name is specified along with the table name, which is not allowed  
 END  
  
--Checking for the existence of 'user table' or 'view'  
--This procedure is not written to work on system tables  
--To script the data in system tables, just create a view on the system tables and script the view instead  
  
IF @owner IS NULL  
 BEGIN  
  IF ((OBJECT_ID(@table_name,'U') IS NULL) AND (OBJECT_ID(@table_name,'V') IS NULL))   
   BEGIN  
    RAISERROR('User table or view not found.',16,1)  
    PRINT 'You may see this error, if you are not the owner of this table or view. In that case use @owner parameter to specify the owner name.'  
    PRINT 'Make sure you have SELECT permission on that table or view.'  
    RETURN -1 --Failure. Reason: There is no user table or view with this name  
   END  
 END  
ELSE  
 BEGIN  
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = @table_name AND (TABLE_TYPE = 'BASE TABLE' OR TABLE_TYPE = 'VIEW') AND TABLE_SCHEMA = @owner)  
   BEGIN  
    RAISERROR('User table or view not found.',16,1)  
    PRINT 'You may see this error, if you are not the owner of this table. In that case use @owner parameter to specify the owner name.'  
    PRINT 'Make sure you have SELECT permission on that table or view.'  
    RETURN -1 --Failure. Reason: There is no user table or view with this name    
   END  
 END  
  
--Variable declarations  
DECLARE  @Column_ID int,     
  @Column_List varchar(8000),   
  @Column_Name varchar(128),   
  @Start_Insert varchar(786),   
  @Data_Type varchar(128),   
  @Actual_Values varchar(8000), --This is the string that will be finally executed to generate INSERT statements  
  @IDN varchar(128)  --Will contain the IDENTITY column's name in the table  
  
--Variable Initialization  
SET @IDN = ''  
SET @Column_ID = 0  
SET @Column_Name = ''  
SET @Column_List = ''  
SET @Actual_Values = ''  
  
IF @owner IS NULL   
 BEGIN  
  SET @Start_Insert = 'INSERT INTO ' + '[' + RTRIM(COALESCE(@target_table,@table_name)) + ']'   
 END  
ELSE  
 BEGIN  
  SET @Start_Insert = 'INSERT ' + '[' + LTRIM(RTRIM(@owner)) + '].' + '[' + RTRIM(COALESCE(@target_table,@table_name)) + ']'     
 END  
  
  
--To get the first column's ID  
  
SELECT @Column_ID = MIN(ORDINAL_POSITION)    
FROM INFORMATION_SCHEMA.COLUMNS (NOLOCK)   
WHERE  TABLE_NAME = @table_name AND  
(@owner IS NULL OR TABLE_SCHEMA = @owner)  
  
   
  
--Loop through all the columns of the table, to get the column names and their data types  
WHILE @Column_ID IS NOT NULL  
 BEGIN  
  SELECT  @Column_Name = QUOTENAME(COLUMN_NAME),   
  @Data_Type = DATA_TYPE   
  FROM  INFORMATION_SCHEMA.COLUMNS (NOLOCK)   
  WHERE  ORDINAL_POSITION = @Column_ID AND   
  TABLE_NAME = @table_name AND  
  (@owner IS NULL OR TABLE_SCHEMA = @owner)  
  
   
  
  IF @cols_to_include IS NOT NULL --Selecting only user specified columns  
  BEGIN  
   IF CHARINDEX( '''' + SUBSTRING(@Column_Name,2,LEN(@Column_Name)-2) + '''',@cols_to_include) = 0   
   BEGIN  
    GOTO SKIP_LOOP  
   END  
  END  
  
  IF @cols_to_exclude IS NOT NULL --Selecting only user specified columns  
  BEGIN  
   IF CHARINDEX( '''' + SUBSTRING(@Column_Name,2,LEN(@Column_Name)-2) + '''',@cols_to_exclude) <> 0   
   BEGIN  
    GOTO SKIP_LOOP  
   END  
  END  
  
  --Making sure to output SET IDENTITY_INSERT ON/OFF in case the table has an IDENTITY column  
  IF (SELECT COLUMNPROPERTY( OBJECT_ID(QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + @table_name),SUBSTRING(@Column_Name,2,LEN(@Column_Name) - 2),'IsIdentity')) = 1   
  BEGIN  
   IF @ommit_identity = 0 --Determing whether to include or exclude the IDENTITY column  
    SET @IDN = @Column_Name  
   ELSE  
    GOTO SKIP_LOOP     
  END  
    
  --Making sure whether to output computed columns or not  
  IF @ommit_computed_cols = 1  
  BEGIN  
   IF (SELECT COLUMNPROPERTY( OBJECT_ID(QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + @table_name),SUBSTRING(@Column_Name,2,LEN(@Column_Name) - 2),'IsComputed')) = 1   
   BEGIN  
    GOTO SKIP_LOOP       
   END  
  END  
    
  --Tables with columns of IMAGE data type are not supported for obvious reasons  
  IF(@Data_Type in ('image'))  
   BEGIN  
    IF (@ommit_images = 0)  
     BEGIN  
      RAISERROR('Tables with image columns are not supported.',16,1)  
      PRINT 'Use @ommit_images = 1 parameter to generate INSERTs for the rest of the columns.'  
      PRINT 'DO NOT ommit Column List in the INSERT statements. If you ommit column list using @include_column_list=0, the generated INSERTs will fail.'  
      RETURN -1 --Failure. Reason: There is a column with image data type  
     END  
    ELSE  
     BEGIN  
     GOTO SKIP_LOOP  
     END  
   END  
  
  --Determining the data type of the column and depending on the data type, the VALUES part of  
  --the INSERT statement is generated. Care is taken to handle columns with NULL values. Also  
  --making sure, not to lose any data from flot, real, money, smallmomey, datetime columns  
  SET @Actual_Values = @Actual_Values  +  
  CASE   
   WHEN @Data_Type IN ('char','varchar','nchar','nvarchar')   
    THEN   
     'COALESCE('''''''' + REPLACE(RTRIM(' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')'  
   WHEN @Data_Type IN ('datetime','smalldatetime')   
    THEN   
     'COALESCE('''''''' + RTRIM(CONVERT(char,' + @Column_Name + ',109))+'''''''',''NULL'')'  
   WHEN @Data_Type IN ('uniqueidentifier')   
    THEN    
     'COALESCE('''''''' + REPLACE(CONVERT(char(255),RTRIM(' + @Column_Name + ')),'''''''','''''''''''')+'''''''',''NULL'')'  
   WHEN @Data_Type IN ('text','ntext')   
    THEN    
     'COALESCE('''''''' + REPLACE(CONVERT(char(8000),' + @Column_Name + '),'''''''','''''''''''')+'''''''',''NULL'')'       
   WHEN @Data_Type IN ('binary','varbinary')   
    THEN    
     'COALESCE(RTRIM(CONVERT(char,' + 'CONVERT(int,' + @Column_Name + '))),''NULL'')'    
   WHEN @Data_Type IN ('timestamp','rowversion')   
    THEN    
     CASE   
      WHEN @include_timestamp = 0   
       THEN   
        '''DEFAULT'''   
       ELSE   
        'COALESCE(RTRIM(CONVERT(char,' + 'CONVERT(int,' + @Column_Name + '))),''NULL'')'    
     END  
   WHEN @Data_Type IN ('float','real','money','smallmoney')  
    THEN  
     'COALESCE(LTRIM(RTRIM(' + 'CONVERT(char, ' +  @Column_Name  + ',2)' + ')),''NULL'')'   
   ELSE   
    'COALESCE(LTRIM(RTRIM(' + 'CONVERT(char, ' +  @Column_Name  + ')' + ')),''NULL'')'   
  END   + '+' +  ''',''' + ' + '  
    
  --Generating the column list for the INSERT statement  
  SET @Column_List = @Column_List +  @Column_Name + ','   
  
  SKIP_LOOP: --The label used in GOTO  
  
  SELECT  @Column_ID = MIN(ORDINAL_POSITION)   
  FROM  INFORMATION_SCHEMA.COLUMNS (NOLOCK)   
  WHERE  TABLE_NAME = @table_name AND   
  ORDINAL_POSITION > @Column_ID AND  
  (@owner IS NULL OR TABLE_SCHEMA = @owner)  
  
  
 --Loop ends here!  
 END  
  
--To get rid of the extra characters that got concatenated during the last run through the loop  
SET @Column_List = LEFT(@Column_List,len(@Column_List) - 1)  
SET @Actual_Values = LEFT(@Actual_Values,len(@Actual_Values) - 6)  
  
IF LTRIM(@Column_List) = ''   
 BEGIN  
  RAISERROR('No columns to select. There should at least be one column to generate the output',16,1)  
  RETURN -1 --Failure. Reason: Looks like all the columns are ommitted using the @cols_to_exclude parameter  
 END  
  
--Forming the final string that will be executed, to output the INSERT statements  
IF (@include_column_list <> 0)  
 BEGIN  
  SET @Actual_Values =   
   'SELECT ' +    
   CASE WHEN @top IS NULL OR @top < 0 THEN '' ELSE ' TOP ' + LTRIM(STR(@top)) + ' ' END +   
   '''' + RTRIM(@Start_Insert) +   
   ' ''+' + '''(' + RTRIM(@Column_List) +  '''+' + ''')''' +   
   ' +''VALUES(''+ ' +  @Actual_Values  + '+'')''' + ' ' +   
   COALESCE(@from,' FROM ' + CASE WHEN @owner IS NULL THEN '' ELSE '[' + LTRIM(RTRIM(@owner)) + '].' END + '[' + rtrim(@table_name) + ']' + '(NOLOCK)')  
 END  
ELSE IF (@include_column_list = 0)  
 BEGIN  
  SET @Actual_Values =   
   'SELECT ' +   
   CASE WHEN @top IS NULL OR @top < 0 THEN '' ELSE ' TOP ' + LTRIM(STR(@top)) + ' ' END +   
   '''' + RTRIM(@Start_Insert) +   
   ' '' +''VALUES(''+ ' +  @Actual_Values + '+'')''' + ' ' +   
   COALESCE(@from,' FROM ' + CASE WHEN @owner IS NULL THEN '' ELSE '[' + LTRIM(RTRIM(@owner)) + '].' END + '[' + rtrim(@table_name) + ']' + '(NOLOCK)')  
 END   
  
--Determining whether to ouput any debug information  
IF @debug_mode =1  
 BEGIN  
  PRINT '/*****START OF DEBUG INFORMATION*****'  
  PRINT 'Beginning of the INSERT statement:'  
  PRINT @Start_Insert  
  PRINT ''  
  PRINT 'The column list:'  
  PRINT @Column_List  
  PRINT ''  
  PRINT 'The SELECT statement executed to generate the INSERTs'  
  PRINT @Actual_Values  
  PRINT ''  
  PRINT '*****END OF DEBUG INFORMATION*****/'  
  PRINT ''  
 END  
    
PRINT '--INSERTs generated by ''sp_generate_inserts'' stored procedure written by Vyas'  
PRINT '--Build number: 22'  
PRINT '--Problems/Suggestions? Contact Vyas @ vyaskn@hotmail.com'  
PRINT '--http://vyaskn.tripod.com'  
PRINT ''  
PRINT 'SET NOCOUNT ON'  
PRINT ''  
  
  
--Determining whether to print IDENTITY_INSERT or not  
IF (@IDN <> '')  
 BEGIN  
  PRINT 'SET IDENTITY_INSERT ' + QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + QUOTENAME(@table_name) + ' ON'  
  PRINT 'GO'  
  PRINT ''  
 END  
  
  
IF @disable_constraints = 1 AND (OBJECT_ID(QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + @table_name, 'U') IS NOT NULL)  
 BEGIN  
  IF @owner IS NULL  
   BEGIN  
    SELECT  'ALTER TABLE ' + QUOTENAME(COALESCE(@target_table, @table_name)) + ' NOCHECK CONSTRAINT ALL' AS '--Code to disable constraints temporarily'  
   END  
  ELSE  
   BEGIN  
    SELECT  'ALTER TABLE ' + QUOTENAME(@owner) + '.' + QUOTENAME(COALESCE(@target_table, @table_name)) + ' NOCHECK CONSTRAINT ALL' AS '--Code to disable constraints temporarily'  
   END  
  
  PRINT 'GO'  
 END  
  
PRINT ''  
PRINT 'PRINT ''Inserting values into ' + '[' + RTRIM(COALESCE(@target_table,@table_name)) + ']' + ''''  
  
  
--All the hard work pays off here!!! You'll get your INSERT statements, when the next line executes!  
EXEC (@Actual_Values)  
  
PRINT 'PRINT ''Done'''  
PRINT ''  
  
  
IF @disable_constraints = 1 AND (OBJECT_ID(QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + @table_name, 'U') IS NOT NULL)  
 BEGIN  
  IF @owner IS NULL  
   BEGIN  
    SELECT  'ALTER TABLE ' + QUOTENAME(COALESCE(@target_table, @table_name)) + ' CHECK CONSTRAINT ALL'  AS '--Code to enable the previously disabled constraints'  
   END  
  ELSE  
   BEGIN  
    SELECT  'ALTER TABLE ' + QUOTENAME(@owner) + '.' + QUOTENAME(COALESCE(@target_table, @table_name)) + ' CHECK CONSTRAINT ALL' AS '--Code to enable the previously disabled constraints'  
   END  
  
  PRINT 'GO'  
 END  
  
PRINT ''  
IF (@IDN <> '')  
 BEGIN  
  PRINT 'SET IDENTITY_INSERT ' + QUOTENAME(COALESCE(@owner,USER_NAME())) + '.' + QUOTENAME(@table_name) + ' OFF'  
  PRINT 'GO'  
 END  
  
PRINT 'SET NOCOUNT OFF'  
  
  
SET NOCOUNT OFF  
RETURN 0 --Success. We are done!  
END  
  
  
  
  
  
  
  
  -----------------------


GO

/****** Object:  StoredProcedure [dbo].[sp_help_revlogin]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[sp_help_revlogin] @login_name sysname = NULL AS  
DECLARE @name    sysname  
DECLARE @xstatus int  
DECLARE @binpwd  varbinary (256)  
DECLARE @txtpwd  sysname  
DECLARE @tmpstr  varchar (256)  
DECLARE @SID_varbinary varbinary(85)  
DECLARE @SID_string varchar(256)  
  
IF (@login_name IS NULL)  
  DECLARE login_curs CURSOR FOR   
    SELECT sid, name, xstatus, password FROM master..sysxlogins   
    WHERE srvid IS NULL AND name <> 'sa'  
ELSE  
  DECLARE login_curs CURSOR FOR   
    SELECT sid, name, xstatus, password FROM master..sysxlogins   
    WHERE srvid IS NULL AND name = @login_name  
OPEN login_curs   
FETCH NEXT FROM login_curs INTO @SID_varbinary, @name, @xstatus, @binpwd  
IF (@@fetch_status = -1)  
BEGIN  
  PRINT 'No login(s) found.'  
  CLOSE login_curs   
  DEALLOCATE login_curs   
  RETURN -1  
END  
SET @tmpstr = '/* sp_help_revlogin script '   
PRINT @tmpstr  
SET @tmpstr = '** Generated '   
  + CONVERT (varchar, GETDATE()) + ' on ' + @@SERVERNAME + ' */'  
PRINT @tmpstr  
PRINT ''  
PRINT 'DECLARE @pwd sysname'  
WHILE (@@fetch_status <> -1)  
BEGIN  
  IF (@@fetch_status <> -2)  
  BEGIN  
    PRINT ''  
    SET @tmpstr = '-- Login: ' + @name  
    PRINT @tmpstr   
    IF (@xstatus & 4) = 4  
    BEGIN -- NT authenticated account/group  
      IF (@xstatus & 1) = 1  
      BEGIN -- NT login is denied access  
        SET @tmpstr = 'EXEC master..sp_denylogin ''' + @name + ''''  
        PRINT @tmpstr   
      END  
      ELSE BEGIN -- NT login has access  
        SET @tmpstr = 'EXEC master..sp_grantlogin ''' + @name + ''''  
        PRINT @tmpstr   
      END  
    END  
    ELSE BEGIN -- SQL Server authentication  
      IF (@binpwd IS NOT NULL)  
      BEGIN -- Non-null password  
        EXEC sp_hexadecimal @binpwd, @txtpwd OUT  
        IF (@xstatus & 2048) = 2048  
          SET @tmpstr = 'SET @pwd = CONVERT (varchar(256), ' + @txtpwd + ')'  
        ELSE  
          SET @tmpstr = 'SET @pwd = CONVERT (varbinary(256), ' + @txtpwd + ')'  
        PRINT @tmpstr  
 EXEC sp_hexadecimal @SID_varbinary,@SID_string OUT  
        SET @tmpstr = 'EXEC master..sp_addlogin ''' + @name   
          + ''', @pwd, @sid = ' + @SID_string + ', @encryptopt = '  
      END  
      ELSE BEGIN   
        -- Null password  
 EXEC sp_hexadecimal @SID_varbinary,@SID_string OUT  
        SET @tmpstr = 'EXEC master..sp_addlogin ''' + @name   
          + ''', NULL, @sid = ' + @SID_string + ', @encryptopt = '  
      END  
      IF (@xstatus & 2048) = 2048  
        -- login upgraded from 6.5  
        SET @tmpstr = @tmpstr + '''skip_encryption_old'''   
      ELSE   
        SET @tmpstr = @tmpstr + '''skip_encryption'''  
      PRINT @tmpstr   
    END  
  END  
  FETCH NEXT FROM login_curs INTO @SID_varbinary, @name, @xstatus, @binpwd  
  END  
CLOSE login_curs   
DEALLOCATE login_curs   
RETURN 0  
  
GO

/****** Object:  StoredProcedure [dbo].[sp_hexadecimal]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[sp_hexadecimal]

    @binvalue varbinary(256),

    @hexvalue varchar (514) OUTPUT

AS

DECLARE @charvalue varchar (514)

DECLARE @i int

DECLARE @length int

DECLARE @hexstring char(16)

SELECT @charvalue = '0x'

SELECT @i = 1

SELECT @length = DATALENGTH (@binvalue)

SELECT @hexstring = '0123456789ABCDEF'

WHILE (@i <= @length)

BEGIN

  DECLARE @tempint int

  DECLARE @firstint int

  DECLARE @secondint int

  SELECT @tempint = CONVERT(int, SUBSTRING(@binvalue,@i,1))

  SELECT @firstint = FLOOR(@tempint/16)

  SELECT @secondint = @tempint - (@firstint*16)

  SELECT @charvalue = @charvalue +

    SUBSTRING(@hexstring, @firstint+1, 1) +

    SUBSTRING(@hexstring, @secondint+1, 1)

  SELECT @i = @i + 1

END

SELECT @hexvalue = @charvalue



GO

/****** Object:  StoredProcedure [dbo].[sp_MonitoramentoLocks]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[sp_MonitoramentoLocks]
as

DECLARE @tempo INT = 1000 --miliseg
declare @idlog varchar(128) = newid() 
declare @tab  table  (
	[session_id] [smallint] NOT NULL,
	[blocked_by] [smallint] NOT NULL,
	[login] [nchar](128) NOT NULL,
	[host_name] [nchar](128) NOT NULL,
	[program_name] [nchar](128) NOT NULL,
	[Query] [nvarchar](max) NULL,
	[Command] [nchar](16) NOT NULL,
	[database] [sysname] NOT NULL,
	[last_wait_type] [nchar](32) NOT NULL,
	[wait_time_sec] [bigint] NULL,
	[last_batch] [datetime] NOT NULL,
	[login_time] [datetime] NOT NULL,
	[status] [nchar](30) NOT NULL,
	[cpu] [int] NULL,
	[capture_time] [datetime] NOT NULL,
	[ID_log] [uniqueidentifier] NULL)

insert into @tab 

Select  
	 SPRO.spid										AS [session_id]
	,SPRO.blocked									AS [blocked_by] 
	,SPRO.loginame									AS [login] 
	,SPRO.hostname									AS [host_name]
	--,SPRO.program_name								AS [program_name1]
	,CASE WHEN LTRIM(RTRIM(SPRO.[Program_name])) LIKE '%TSQL Job%' THEN B.NAME 
				ELSE LTRIM(RTRIM(SPRO.[Program_name])) END AS [Program_name]
	,CASE WHEN Text LIKE 'FETCH API_CURSOR%'
			THEN (SELECT TOP 1 c.properties +' | '+ t.text
					FROM sys.dm_exec_cursors (SPRO.spid) c
					CROSS APPLY sys.dm_exec_sql_text (c.sql_handle) t     )    
			ELSE Text END							AS [Query]
	--,Text											AS [Query]
	,SPRO.cmd										AS [Command]  
	,DTBS.name										AS [database] 
	,SPRO.lastwaittype								AS [last_wait_type]  
	,SPRO.waittime/1000								AS [wait_time]  
	,SPRO.last_batch								AS [last_batch]  
	,SPRO.login_time								AS [login_time]  
	,SPRO.status									AS [status]  
	,(SPRO.cpu/1000)								AS [cpu]  
	,getdate()										AS [capture_time]
	,@idlog											AS [ID_log]


FROM sys.sysprocesses AS SPRO
	CROSS APPLY sys.dm_exec_sql_text(sql_handle)
	OUTER APPLY (SELECT NAME FROM MSDB..SYSJOBS (NOLOCK) 
						WHERE '0x'+CONVERT(char(32),CAST(job_id AS binary(16)),2) = SUBSTRING(SPRO.[Program_name],30,34)) B

    INNER JOIN sys.databases AS DTBS
		ON SPRO.dbid = DTBS.database_id

		where	lastwaittype <> 'miscellaneous' 
				and SPRO.spid >0 
				and SPRO.blocked <> 0
				and SPRO.waittime >@tempo




/****** INSERE OS DADOS NA TABELA LOG_LOCKS ******/

INSERT INTO [DBMANAGER].[dbo].[log_locks]




	select * from @tab	

	union


Select  
	 SPRO.spid										AS [session_id]
	,SPRO.blocked									AS [blocked_by] 
	,SPRO.loginame									AS [login] 
	,SPRO.hostname									AS [host_name]
	--,SPRO.program_name								AS [program_name]
	,CASE WHEN LTRIM(RTRIM(SPRO.[Program_name])) LIKE '%TSQL Job%' THEN B.NAME 
				ELSE LTRIM(RTRIM(SPRO.[Program_name])) END AS [Program_name]
	,CASE WHEN Text LIKE 'FETCH API_CURSOR%'
			THEN (SELECT TOP 1 c.properties +' | '+ t.text
					FROM sys.dm_exec_cursors (SPRO.spid) c
					CROSS APPLY sys.dm_exec_sql_text (c.sql_handle) t     )    
			ELSE Text END							AS [Query]
	--,Text											AS [Query]
	,SPRO.cmd										AS [Command]  
	,DTBS.name										AS [database] 
	,SPRO.lastwaittype								AS [last_wait_type]  
	,SPRO.waittime/1000								AS [wait_time]  
	,SPRO.last_batch								AS [last_batch]  
	,SPRO.login_time								AS [login_time]  
	,SPRO.status									AS [status]  
	,(SPRO.cpu/1000)								AS [cpu] 
	,getdate()										AS [capture_time] 
	,@idlog											AS [ID_log]



FROM sys.sysprocesses AS SPRO
	CROSS APPLY sys.dm_exec_sql_text(sql_handle)
	OUTER APPLY (SELECT NAME FROM MSDB..SYSJOBS (NOLOCK) 
						WHERE '0x'+CONVERT(char(32),CAST(job_id AS binary(16)),2) = SUBSTRING(SPRO.[Program_name],30,34)) B

    INNER JOIN sys.databases AS DTBS
		ON SPRO.dbid = DTBS.database_id

		where SPRO.spid in (select blocked_by from @tab)


GO

/****** Object:  StoredProcedure [dbo].[sp_operador]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO


  CREATE PROCEDURE [dbo].[sp_operador]  
AS  

-- Exibe a causa raiz dos bloqueios que devem ser finalizados com cuidado e sob an�lise da causa raiz
-- De www.clouddbm.com Opensource Copywrited by Gilberto Rosa (gilberto.rosa@clouddbm.com)
-- Script executado em mais de 10 mil Bancos de Dados, valide seu ambiente e tenha backup


IF EXISTS  
    (SELECT * FROM master.dbo.sysprocesses (nolock)  
    WHERE spid IN (SELECT blocked FROM master.dbo.sysprocesses (nolock)))  
    SELECT   
        spid, status, loginame=substring(loginame, 1, 12),  
        hostname=substring(hostname, 1, 12),  
            blk=CONVERT(char(3), blocked),  
            open_tran,  
        dbname=substring(db_name(dbid),1,10),cmd,   
            waittype, waittime, last_batch  
        FROM master.dbo.sysprocesses (nolock)  
        WHERE spid IN (SELECT blocked FROM master.dbo.sysprocesses (nolock))  
            AND blocked=0  
ELSE  
SELECT "sem processos bloqueados !"  
  
GO

/****** Object:  StoredProcedure [dbo].[sp_Quem]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO


CREATE PROCEDURE [dbo].[sp_Quem]  
    @loginame     sysname = NULL  
as  

-- Exibe todos os bloqueios da instancia
-- De www.clouddbm.com Opensource Copywrited by Gilberto Rosa (gilberto.rosa@clouddbm.com)
-- Script executado em mais de 10 mil Bancos de Dados, valide seu ambiente e tenha backup

  
set nocount on  
  
declare  
    @retcode         int  
  
declare  
    @sidlow         varbinary(85)  
   ,@sidhigh        varbinary(85)  
   ,@sid1           varbinary(85)  
   ,@spidlow         int  
   ,@spidhigh        int  
  
declare  
    @charMaxLenLoginName      varchar(6)  
   ,@charMaxLenDBName         varchar(6)  
   ,@charMaxLenCPUTime        varchar(10)  
   ,@charMaxLenDiskIO         varchar(10)  
   ,@charMaxLenHostName       varchar(10)  
   ,@charMaxLenProgramName    varchar(10)  
   ,@charMaxLenLastBatch      varchar(10)  
   ,@charMaxLenCommand        varchar(10)  
  
declare  
    @charsidlow              varchar(85)  
   ,@charsidhigh             varchar(85)  
   ,@charspidlow              varchar(11)  
   ,@charspidhigh             varchar(11)  
  
--------  
  
select  
    @retcode         = 0      -- 0=good ,1=bad.  
  
--------defaults  
select @sidlow = convert(varbinary(85), (replicate(char(0), 85)))  
select @sidhigh = convert(varbinary(85), (replicate(char(1), 85)))  
  
select  
    @spidlow         = 0  
   ,@spidhigh        = 32767  
  
--------------------------------------------------------------  
IF (@loginame IS     NULL)  --Simple default to all LoginNames.  
      GOTO LABEL_17PARM1EDITED  
  
--------  
  
-- select @sid1 = suser_sid(@loginame)  
select @sid1 = null  
if exists(select * from master.dbo.syslogins where loginname = @loginame)  
 select @sid1 = sid from master.dbo.syslogins where loginname = @loginame  
  
IF (@sid1 IS NOT NULL)  --Parm is a recognized login name.  
   begin  
   select @sidlow  = suser_sid(@loginame)  
         ,@sidhigh = suser_sid(@loginame)  
   GOTO LABEL_17PARM1EDITED  
   end  
  
--------  
  
IF (lower(@loginame) IN ('active'))  --Special action, not sleeping.  
   begin  
   select @loginame = lower(@loginame)  
   GOTO LABEL_17PARM1EDITED  
   end  
  
--------  
  
IF (patindex ('%[^0-9]%' , isnull(@loginame,'z')) = 0)  --Is a number.  
   begin  
   select  
             @spidlow   = convert(int, @loginame)  
            ,@spidhigh  = convert(int, @loginame)  
   GOTO LABEL_17PARM1EDITED  
   end  
  
--------  
  
RaisError(15007,-1,-1,@loginame)  
select @retcode = 1  
GOTO LABEL_86RETURN  
  
  
LABEL_17PARM1EDITED:  
  
  
--------------------  Capture consistent sysprocesses.  -------------------  
  
SELECT  
  
  spid  
 ,status  
 ,sid  
 ,hostname  
 ,program_name  
 ,cmd  
 ,cpu  
 ,physical_io  
 ,blocked  
 ,dbid  
 ,convert(sysname, rtrim(loginame))  
        as loginname  
 ,spid as 'spid_sort'  
  
 ,  substring( convert(varchar,last_batch,111) ,6  ,5 ) + ' '  
  + substring( convert(varchar,last_batch,113) ,13 ,8 )  
       as 'last_batch_char'  
  
      INTO    #tb1_sysprocesses  
      from master.dbo.sysprocesses   (nolock)  
      where blocked <> 0  
  
--------Screen out any rows?  
  
IF (@loginame IN ('active'))  
   DELETE #tb1_sysprocesses  
         where   lower(status)  = 'sleeping'  
         and     upper(cmd)    IN (  
                     'AWAITING COMMAND'  
                    ,'MIRROR HANDLER'  
                    ,'LAZY WRITER'  
                    ,'CHECKPOINT SLEEP'  
                    ,'RA MANAGER'  
                                  )  
  
         and     blocked       = 0  
  
  
  
--------Prepare to dynamically optimize column widths.  
  
  
Select  
    @charsidlow     = convert(varchar(85),@sidlow)  
   ,@charsidhigh    = convert(varchar(85),@sidhigh)  
   ,@charspidlow     = convert(varchar,@spidlow)  
   ,@charspidhigh    = convert(varchar,@spidhigh)  
  
  
  
SELECT  
             @charMaxLenLoginName =  
                  convert( varchar  
                          ,isnull( max( datalength(loginname)) ,5)  
                         )  
  
            ,@charMaxLenDBName    =  
                  convert( varchar  
                          ,isnull( max( datalength( convert(varchar,db_name(dbid)))) ,6)  
                         )  
  
            ,@charMaxLenCPUTime   =  
                  convert( varchar  
                          ,isnull( max( datalength( convert(varchar,cpu))) ,7)  
                         )  
  
            ,@charMaxLenDiskIO    =  
                  convert( varchar  
                          ,isnull( max( datalength( convert(varchar,physical_io))) ,6)  
                         )  
  
            ,@charMaxLenCommand  =  
                  convert( varchar  
                          ,isnull( max( datalength( convert(varchar,cmd))) ,7)  
                         )  
  
            ,@charMaxLenHostName  =  
                  convert( varchar  
                          ,isnull( max( datalength( convert(varchar,hostname))) ,8)  
                         )  
  
            ,@charMaxLenProgramName =  
                  convert( varchar  
                          ,isnull( max( datalength( convert(varchar,program_name))) ,11)  
                         )  
  
            ,@charMaxLenLastBatch =  
                  convert( varchar  
                          ,isnull( max( datalength( convert(varchar,last_batch_char))) ,9)  
                         )  
      from  
             #tb1_sysprocesses  
      where  
--             sid >= @sidlow  
--      and    sid <= @sidhigh  
--      and  
             spid >= @spidlow  
      and    spid <= @spidhigh  
  
  
  
--------Output the report.  
  
  
EXECUTE(  
'  
SET nocount off  
  
SELECT  
             SPID          = convert(char(5),spid)  
  
            ,Status        =  
                  CASE lower(status)  
                     When ''sleeping'' Then convert(varchar(12),lower(status))  
                     Else                   convert(varchar(12),upper(status))  
                  END  
  
            ,Login         = convert(varchar(12),loginname)  
  
            ,HostName      =  
                  CASE hostname  
                     When Null  Then ''  .''  
                     When '' '' Then ''  .''  
                     Else    convert(varchar(12),hostname)  
                  END  
  
            ,BlkBy         =  
                  CASE               isnull(convert(char(5),blocked),''0'')  
                     When ''0'' Then ''  .''  
                     Else            isnull(convert(char(5),blocked),''0'')  
                  END  
  
            ,DBName        = convert(varchar(12),db_name(dbid))  
            ,Command       = cmd  
  
            ,ProgramName   = substring(program_name,1,' + @charMaxLenProgramName + ')  
      from  
             #tb1_sysprocesses  --Usually DB qualification is needed in exec().  
      where  
             spid >= ' + @charspidlow  + '  
      and    spid <= ' + @charspidhigh + '  
  
      -- (Seems always auto sorted.)   order by spid_sort  
  
'  
)  
/*****AKUNDONE: removed from where-clause in above EXEC sqlstr  
             sid >= ' + @charsidlow  + '  
      and    sid <= ' + @charsidhigh + '  
      and  
**************/  
  
  
LABEL_86RETURN:  
  
SET     ROWCOUNT     1  
  
DECLARE @DBCCcmd     varchar(250)  
DECLARE @QualSPID    varchar(5)  
DECLARE @QualBlkBy   varchar(5)  
  
SELECT  @QualSPID  = convert(varchar(5),SPID ),  
        @QualBlkBy = convert(varchar(5),Blocked)  
        FROM #tb1_sysprocesses  
  
WHILE @@ROWCOUNT <> 0  
  BEGIN  
   SET     @DBCCcmd = "............................. Comando executado pelo processo BLOQUEADO: " + @QualSPID  
   PRINT   @DBCCcmd  
   EXECUTE ( "dbcc inputbuffer ( " + @QualSPID + " )" )  
   SET     @DBCCcmd = "............................. Comando executado pelo processo BLOQUEANDO: " + @QualBlkBy  
   PRINT   @DBCCcmd  
   EXECUTE ( "dbcc inputbuffer ( " + @QualBlkBy + " )" )  
   DELETE  FROM #tb1_sysprocesses  
   SELECT  @QualSPID= convert(varchar(5),SPID ),  
           @QualBlkBy = convert(varchar(5),Blocked)  
           FROM #tb1_sysprocesses  
  END  
  
SET ROWCOUNT 0  
  
IF (object_id('tempdb..#tb1_sysprocesses') is not null)  
    drop table #tb1_sysprocesses  
  
SET NOCOUNT OFF  
  
return @retcode -- sp_quem  
  
  
GO

/****** Object:  StoredProcedure [dbo].[sp_SDS]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO




CREATE PROCEDURE [dbo].[sp_SDS]   
  @TargetDatabase sysname = NULL,     --  NULL: all dbs  
  @Level varchar(10) = 'Database',    --  or "File"  
  @UpdateUsage bit = 0,               --  default no update  
  @Unit char(2) = 'MB'                --  Megabytes, Kilobytes or Gigabytes  
AS  
  
/**************************************************************************************************  
**  
**  author: Richard Ding  
**  date:   4/8/2008  
**  usage:  list db size AND path w/o SUMmary  
**  test code: sp_SDS   --  default behavior  
**             sp_SDS 'maAster'  
**             sp_SDS NULL, NULL, 0  
**             sp_SDS NULL, 'file', 1, 'GB'  
**             sp_SDS 'Test_snapshot', 'Database', 1  
**             sp_SDS 'Test', 'File', 0, 'kb'  
**             sp_SDS 'pfaids', 'Database', 0, 'gb'  
**             sp_SDS 'tempdb', NULL, 1, 'kb'  
**     
**************************************************************************************************/  
  
SET NOCOUNT ON;  
  
IF @TargetDatabase IS NOT NULL AND DB_ID(@TargetDatabase) IS NULL  
  BEGIN  
    RAISERROR(15010, -1, -1, @TargetDatabase);  
    RETURN (-1)  
  END  
  
IF OBJECT_ID('tempdb.dbo.##Tbl_CombinedInfo', 'U') IS NOT NULL  
  DROP TABLE dbo.##Tbl_CombinedInfo;  
    
IF OBJECT_ID('tempdb.dbo.##Tbl_DbFileStats', 'U') IS NOT NULL  
  DROP TABLE dbo.##Tbl_DbFileStats;  
    
IF OBJECT_ID('tempdb.dbo.##Tbl_ValidDbs', 'U') IS NOT NULL  
  DROP TABLE dbo.##Tbl_ValidDbs;  
    
IF OBJECT_ID('tempdb.dbo.##Tbl_Logs', 'U') IS NOT NULL  
  DROP TABLE dbo.##Tbl_Logs;  
    
CREATE TABLE dbo.##Tbl_CombinedInfo (  
  DatabaseName sysname NULL,   
  [type] VARCHAR(10) NULL,   
  LogicalName sysname NULL,  
  T dec(10, 2) NULL,  
  U dec(10, 2) NULL,  
  [U(%)] dec(5, 2) NULL,  
  F dec(10, 2) NULL,  
  [F(%)] dec(5, 2) NULL,  
  PhysicalName sysname NULL );  
  
CREATE TABLE dbo.##Tbl_DbFileStats (  
  Id int identity,   
  DatabaseName sysname NULL,   
  FileId int NULL,   
  FileGroup int NULL,   
  TotalExtents bigint NULL,   
  UsedExtents bigint NULL,   
  Name sysname NULL,   
  FileName varchar(255) NULL );  
    
CREATE TABLE dbo.##Tbl_ValidDbs (  
  Id int identity,   
  Dbname sysname NULL );  
    
CREATE TABLE dbo.##Tbl_Logs (  
  DatabaseName sysname NULL,   
  LogSize dec (10, 2) NULL,   
  LogSpaceUsedPercent dec (5, 2) NULL,  
  Status int NULL );  
  
DECLARE @Ver varchar(10),   
        @DatabaseName sysname,   
        @Ident_last int,   
        @String varchar(2000),  
        @BaseString varchar(2000);  
          
SELECT @DatabaseName = '',   
       @Ident_last = 0,   
       @String = '',   
       @Ver = CASE WHEN @@VERSION LIKE '%9.0%' THEN 'SQL 2005'   
                   WHEN @@VERSION LIKE '%8.0%' THEN 'SQL 2000'   
                   WHEN @@VERSION LIKE '%10.0%' THEN 'SQL 2008'   
              END;  
                
SELECT @BaseString =   
' SELECT DB_NAME(), ' +   
CASE WHEN @Ver = 'SQL 2000' THEN 'CASE WHEN status & 0x40 = 0x40 THEN ''Log''  ELSE ''Data'' END'   
  ELSE ' CASE type WHEN 0 THEN ''Data'' WHEN 1 THEN ''Log'' WHEN 4 THEN ''Full-text'' ELSE ''reserved'' END' END +   
', name, ' +   
CASE WHEN @Ver = 'SQL 2000' THEN 'filename' ELSE 'physical_name' END +   
', size*8.0/1024.0 FROM ' +   
CASE WHEN @Ver = 'SQL 2000' THEN 'sysfiles' ELSE 'sys.database_files' END +   
' WHERE '  
+ CASE WHEN @Ver = 'SQL 2000' THEN ' HAS_DBACCESS(DB_NAME()) = 1' ELSE 'state_desc = ''ONLINE''' END + '';  
  
SELECT @String = 'INSERT INTO dbo.##Tbl_ValidDbs SELECT name FROM ' +   
                 CASE WHEN @Ver = 'SQL 2000' THEN 'master.dbo.sysdatabases'   
                      WHEN @Ver IN ('SQL 2005', 'SQL 2008') THEN 'master.sys.databases'   
                 END + ' WHERE HAS_DBACCESS(name) = 1 ORDER BY name ASC';  
EXEC (@String);  
  
INSERT INTO dbo.##Tbl_Logs EXEC ('DBCC SQLPERF (LOGSPACE) WITH NO_INFOMSGS');  
  
--  For data part  
IF @TargetDatabase IS NOT NULL  
  BEGIN  
    SELECT @DatabaseName = @TargetDatabase;  
    IF @UpdateUsage <> 0 AND DATABASEPROPERTYEX (@DatabaseName,'Status') = 'ONLINE'   
          AND DATABASEPROPERTYEX (@DatabaseName, 'Updateability') <> 'READ_ONLY'  
      BEGIN  
        SELECT @String = 'USE [' + @DatabaseName + '] DBCC UPDATEUSAGE (0)';  
        PRINT '*** ' + @String + ' *** ';  
        EXEC (@String);  
        PRINT '';  
      END  
        
    SELECT @String = 'INSERT INTO dbo.##Tbl_CombinedInfo (DatabaseName, type, LogicalName, PhysicalName, T) ' + @BaseString;   
  
    INSERT INTO dbo.##Tbl_DbFileStats (FileId, FileGroup, TotalExtents, UsedExtents, Name, FileName)  
          EXEC ('USE [' + @DatabaseName + '] DBCC SHOWFILESTATS WITH NO_INFOMSGS');  
    EXEC ('USE [' + @DatabaseName + '] ' + @String);  
          
    UPDATE dbo.##Tbl_DbFileStats SET DatabaseName = @DatabaseName;   
  END  
ELSE  
  BEGIN  
    WHILE 1 = 1  
      BEGIN  
        SELECT TOP 1 @DatabaseName = Dbname FROM dbo.##Tbl_ValidDbs WHERE Dbname > @DatabaseName ORDER BY Dbname ASC;  
        IF @@ROWCOUNT = 0  
          BREAK;  
        IF @UpdateUsage <> 0 AND DATABASEPROPERTYEX (@DatabaseName, 'Status') = 'ONLINE'   
              AND DATABASEPROPERTYEX (@DatabaseName, 'Updateability') <> 'READ_ONLY'  
          BEGIN  
            SELECT @String = 'DBCC UPDATEUSAGE (''' + @DatabaseName + ''') ';  
            PRINT '*** ' + @String + '*** ';  
            EXEC (@String);  
            PRINT '';  
          END  
      
        SELECT @Ident_last = ISNULL(MAX(Id), 0) FROM dbo.##Tbl_DbFileStats;  
  
        SELECT @String = 'INSERT INTO dbo.##Tbl_CombinedInfo (DatabaseName, type, LogicalName, PhysicalName, T) ' + @BaseString;   
  
        EXEC ('USE [' + @DatabaseName + '] ' + @String);  
        
        INSERT INTO dbo.##Tbl_DbFileStats (FileId, FileGroup, TotalExtents, UsedExtents, Name, FileName)  
          EXEC ('USE [' + @DatabaseName + '] DBCC SHOWFILESTATS WITH NO_INFOMSGS');  
  
        UPDATE dbo.##Tbl_DbFileStats SET DatabaseName = @DatabaseName WHERE Id BETWEEN @Ident_last + 1 AND @@IDENTITY;  
      END  
  END  
  
--  set used size for data files, do not change total obtained from sys.database_files as it has for log files  
UPDATE dbo.##Tbl_CombinedInfo   
SET U = s.UsedExtents*8*8/1024.0   
FROM dbo.##Tbl_CombinedInfo t JOIN dbo.##Tbl_DbFileStats s   
ON t.LogicalName = s.Name AND s.DatabaseName = t.DatabaseName;  
  
--  set used size and % values for log files:  
UPDATE dbo.##Tbl_CombinedInfo   
SET [U(%)] = LogSpaceUsedPercent,   
U = T * LogSpaceUsedPercent/100.0  
FROM dbo.##Tbl_CombinedInfo t JOIN dbo.##Tbl_Logs l   
ON l.DatabaseName = t.DatabaseName   
WHERE t.type = 'Log';  
  
UPDATE dbo.##Tbl_CombinedInfo SET F = T - U, [U(%)] = U*100.0/T;  
  
UPDATE dbo.##Tbl_CombinedInfo SET [F(%)] = F*100.0/T;  
  
IF UPPER(ISNULL(@Level, 'DATABASE')) = 'FILE'  
  BEGIN  
    IF @Unit = 'KB'  
      UPDATE dbo.##Tbl_CombinedInfo  
      SET T = T * 1024, U = U * 1024, F = F * 1024;  
        
    IF @Unit = 'GB'  
      UPDATE dbo.##Tbl_CombinedInfo  
      SET T = T / 1024, U = U / 1024, F = F / 1024;  
        
    SELECT DatabaseName AS 'Database',  
      type AS 'Type',  
      LogicalName,  
      T AS 'Total',  
      U AS 'Used',  
      [U(%)] AS 'Used (%)',  
      F AS 'Free',  
      [F(%)] AS 'Free (%)',  
      PhysicalName  
      FROM dbo.##Tbl_CombinedInfo   
      WHERE DatabaseName LIKE ISNULL(@TargetDatabase, '%')   
      ORDER BY DatabaseName ASC, type ASC;  
  
    SELECT CASE WHEN @Unit = 'GB' THEN 'GB' WHEN @Unit = 'KB' THEN 'KB' ELSE 'MB' END AS 'SUM',  
        SUM (T) AS 'TOTAL', SUM (U) AS 'USED', SUM (F) AS 'FREE' FROM dbo.##Tbl_CombinedInfo;  
  END  
  
IF UPPER(ISNULL(@Level, 'DATABASE')) = 'DATABASE'  
  BEGIN  
    DECLARE @Tbl_Final TABLE (  
      DatabaseName sysname NULL,  
      TOTAL dec (10, 2),  
      [=] char(1),  
      used dec (10, 2),  
      [used (%)] dec (5, 2),  
      [+] char(1),  
      free dec (10, 2),  
      [free (%)] dec (5, 2),  
      [==] char(2),  
      Data dec (10, 2),  
      Data_Used dec (10, 2),  
      [Data_Used (%)] dec (5, 2),  
      Data_Free dec (10, 2),  
      [Data_Free (%)] dec (5, 2),  
      [++] char(2),  
      Log dec (10, 2),  
      Log_Used dec (10, 2),  
      [Log_Used (%)] dec (5, 2),  
      Log_Free dec (10, 2),  
      [Log_Free (%)] dec (5, 2) );  
  
    INSERT INTO @Tbl_Final  
      SELECT x.DatabaseName,   
           x.Data + y.Log AS 'TOTAL',   
           '=' AS '=',   
           x.Data_Used + y.Log_Used AS 'U',  
           (x.Data_Used + y.Log_Used)*100.0 / (x.Data + y.Log)  AS 'U(%)',  
           '+' AS '+',  
           x.Data_Free + y.Log_Free AS 'F',  
           (x.Data_Free + y.Log_Free)*100.0 / (x.Data + y.Log)  AS 'F(%)',  
           '==' AS '==',  
           x.Data,   
           x.Data_Used,   
           x.Data_Used*100/x.Data AS 'D_U(%)',  
           x.Data_Free,   
           x.Data_Free*100/x.Data AS 'D_F(%)',  
           '++' AS '++',   
           y.Log,   
           y.Log_Used,   
           y.Log_Used*100/y.Log AS 'L_U(%)',  
           y.Log_Free,   
           y.Log_Free*100/y.Log AS 'L_F(%)'  
      FROM   
      ( SELECT d.DatabaseName,   
               SUM(d.T) AS 'Data',   
               SUM(d.U) AS 'Data_Used',   
               SUM(d.F) AS 'Data_Free'   
          FROM dbo.##Tbl_CombinedInfo d WHERE d.type = 'Data' GROUP BY d.DatabaseName ) AS x  
      JOIN   
      ( SELECT l.DatabaseName,   
               SUM(l.T) AS 'Log',   
               SUM(l.U) AS 'Log_Used',   
               SUM(l.F) AS 'Log_Free'   
          FROM dbo.##Tbl_CombinedInfo l WHERE l.type = 'Log' GROUP BY l.DatabaseName ) AS y  
      ON x.DatabaseName = y.DatabaseName;  
      
    IF @Unit = 'KB'  
      UPDATE @Tbl_Final SET TOTAL = TOTAL * 1024,  
      used = used * 1024,  
      free = free * 1024,  
      Data = Data * 1024,  
      Data_Used = Data_Used * 1024,  
      Data_Free = Data_Free * 1024,  
      Log = Log * 1024,  
      Log_Used = Log_Used * 1024,  
      Log_Free = Log_Free * 1024;  
        
     IF @Unit = 'GB'  
      UPDATE @Tbl_Final SET TOTAL = TOTAL / 1024,  
      used = used / 1024,  
      free = free / 1024,  
      Data = Data / 1024,  
      Data_Used = Data_Used / 1024,  
      Data_Free = Data_Free / 1024,  
      Log = Log / 1024,  
      Log_Used = Log_Used / 1024,  
      Log_Free = Log_Free / 1024;  
        
      DECLARE @GrantTotal dec(11, 2);  
      SELECT @GrantTotal = SUM(TOTAL) FROM @Tbl_Final;  
  
      SELECT   
      CONVERT(dec(10, 2), TOTAL*100.0/@GrantTotal) AS 'WEIGHT (%)',   
      DatabaseName AS 'DATABASE',  
      CONVERT(VARCHAR(12), used) + '  (' + CONVERT(VARCHAR(12), [used (%)]) + ' %)' AS 'USED  (%)',  
      [+],  
      CONVERT(VARCHAR(12), free) + '  (' + CONVERT(VARCHAR(12), [free (%)]) + ' %)' AS 'FREE  (%)',  
      [=],  
      TOTAL,   
      [=],  
      CONVERT(VARCHAR(12), Data) + '  (' + CONVERT(VARCHAR(12), Data_Used) + ',  ' +   
      CONVERT(VARCHAR(12), [Data_Used (%)]) + '%)' AS 'DATA  (used,  %)',  
      [+],  
      CONVERT(VARCHAR(12), Log) + '  (' + CONVERT(VARCHAR(12), Log_Used) + ',  ' +   
      CONVERT(VARCHAR(12), [Log_Used (%)]) + '%)' AS 'LOG  (used,  %)'  
        FROM @Tbl_Final   
        WHERE DatabaseName LIKE ISNULL(@TargetDatabase, '%')  
        ORDER BY DatabaseName ASC;  
          
    IF @TargetDatabase IS NULL  
      SELECT CASE WHEN @Unit = 'GB' THEN 'GB' WHEN @Unit = 'KB' THEN 'KB' ELSE 'MB' END AS 'SUM',   
      SUM (used) AS 'USED',   
      SUM (free) AS 'FREE',   
      SUM (TOTAL) AS 'TOTAL',   
      SUM (Data) AS 'DATA',   
      SUM (Log) AS 'LOG'   
      FROM @Tbl_Final;  
  END  
    
RETURN (0)  
  --------------------
GO

/****** Object:  StoredProcedure [dbo].[sp_Sentinela_Excecao]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO






CREATE procedure [dbo].[sp_Sentinela_Excecao] as 


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

/****** Object:  StoredProcedure [dbo].[sp_sentinela_teste]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

create   procedure [dbo].[sp_sentinela_teste] as 

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
and spid IN (SELECT blocked FROM master.dbo.sysprocesses where waittime > 3)
and loginame not like 'vista\manutencao%'
and program_name not like 'AzureWorkloadBackup% '
and program_name not like 'Microsoft SQL Server Management Studio1% '

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
	
	
	INSERT #Inputbuffer
	EXEC('DBCC INPUTBUFFER('+ @ID +')')
	

	SELECT * FROM #Inputbuffer

	DROP TABLE #Inputbuffer
	EXEC msdb.dbo.sp_send_dbmail @body = '@SQL'
		,@body_format = 'TEXT'
		,@profile_name = N'DBA'
		,@query = 'EXEC sp_who2'
		,@recipients = N'monitoramento@clouddbm.com'
		,@Subject = N'Solucionare - Teste' 

	SELECT @SQL

	--Kill the Processes
	EXEC(@SQL)
END

--O exemplo a seguir mostra a lista de todos os perfis na instância.

--EXECUTE msdb.dbo.sysmail_help_profile_sp;
GO

/****** Object:  StoredProcedure [dbo].[spu_alerta_bloqueio]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO




CREATE   proc [dbo].[spu_alerta_bloqueio] as

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

/*
_______________________________________________________________________
--CASO SEJA NECESSÁRIO, ALTERAR NA LINHA ABAIXO OS MINUTOS (60 PADRÃO)
_______________________________________________________________________

*/

and r.wait_time / (1000.0) > 1 -- 5 minutos
and
(
'SELECT * FROM [DB_TESTE].[dbo].[ALUNO]1' = st.TEXT
or
'SELECT * FROM [DB_TESTE].[dbo].[ALUNO]' = st.TEXT
)
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
	
/*
_______________________________________________________________________
--SE ALTERAR OS MINUTOS, ALTERAR TAMBÉM A LINHA ABAIXO
--ONDE TEM A MENSAGEM DE ATENÇÃO E O TEMPO DE BLOQUEIO
_______________________________________________________________________

*/
	
    SET @tableHTML = N'<H1> ELEVA - Cygnus - Atenção - Bloqueios a mais de 5 minutos no Banco de Dados</H1>' + N'<table border="1">' + N'<tr>' + N'<th>session_id</th>' + N'<th>database_name</th>' + N'<th>Status</th>' + 
                     N'<th>blocking_session_id</th><th>wait_type</th><th>wait_resource</th>' + 
                     N'<th>WaitSec</th>' + N'<th>cpu_time</th>' + 
                     N'<th>logical_reads</th>' + N'<th>reads</th>' +
                     N'<th>writes</th>' + N'<th>ElapsSec</th>' + N'<th>statement_text</th>' + N'<th>command_text</th>' + 
                     N'<th>command</th>' + N'<th>login_name</th>' + N'<th>host_name</th>' + N'<th>program_name</th>' + 
                     N'<th>host_process_id</th>' + N'<th>last_request_end_time</th>' + N'<th>login_time</th>' + 
                     N'<th>open_transaction_count</th>' + '</tr>' + CAST((
                SELECT td = s.session_id
                    ,''
                    ,td = (SELECT name FROM sys.databases where database_id= r.database_id)
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




/*
_______________________________________________________________________

NECESSÁRIO EDITAR O PROFILE NAME E O SUBJECT
_______________________________________________________________________

*/

    EXEC msdb.dbo.sp_send_dbmail @body = @tableHTML
        ,@body_format = 'HTML'
        ,@profile_name = N'DBA'   -- INSERIR O PROFILE EXISTENTE
        ,@recipients = N'vpmaciel@gmail.com'
        ,@Subject = N'Bloqueio detectado' 
/*
EXEC msdb.dbo.sp_send_dbmail
	@body_format = 'HTML',
	@profile_name = 'DBA',
	@recipients = 'monitoramento@clouddbm.com',
	@subject = '@subjec',
	@body = @tableHTML 
*/
END

DROP TABLE #temp_requests
GO

/****** Object:  StoredProcedure [dbo].[spu_alerta_bloqueio2]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO




CREATE   proc [dbo].[spu_alerta_bloqueio2] as

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

/*
_______________________________________________________________________
--CASO SEJA NECESSÁRIO, ALTERAR NA LINHA ABAIXO OS MINUTOS (60 PADRÃO)
_______________________________________________________________________

*/

and r.wait_time / (1000.0) > 30 -- 5 minutos
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
	
/*
_______________________________________________________________________
--SE ALTERAR OS MINUTOS, ALTERAR TAMBÉM A LINHA ABAIXO
--ONDE TEM A MENSAGEM DE ATENÇÃO E O TEMPO DE BLOQUEIO
_______________________________________________________________________

*/
	
    SET @tableHTML = N'<H1> ELEVA - Cygnus - Atenção - Bloqueios a mais de 5 minutos no Banco de Dados</H1>' + N'<table border="1">' + N'<tr>' + N'<th>session_id</th>' + N'<th>database_name</th>' + N'<th>Status</th>' + 
                     N'<th>blocking_session_id</th><th>wait_type</th><th>wait_resource</th>' + 
                     N'<th>WaitSec</th>' + N'<th>cpu_time</th>' + 
                     N'<th>logical_reads</th>' + N'<th>reads</th>' +
                     N'<th>writes</th>' + N'<th>ElapsSec</th>' + N'<th>statement_text</th>' + N'<th>command_text</th>' + 
                     N'<th>command</th>' + N'<th>login_name</th>' + N'<th>host_name</th>' + N'<th>program_name</th>' + 
                     N'<th>host_process_id</th>' + N'<th>last_request_end_time</th>' + N'<th>login_time</th>' + 
                     N'<th>open_transaction_count</th>' + '</tr>' + CAST((
                SELECT td = s.session_id
                    ,''
                    ,td = (SELECT name FROM sys.databases where database_id= r.database_id)
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




/*
_______________________________________________________________________

NECESSÁRIO EDITAR O PROFILE NAME E O SUBJECT
_______________________________________________________________________

*/
/*
    EXEC msdb.dbo.sp_send_dbmail @body = @tableHTML
        ,@body_format = 'HTML'
        ,@profile_name = N'SendMail'   -- INSERIR O PROFILE EXISTENTE
        ,@recipients = N'monitoramento@clouddbm.com; alertas-lock-cygnus-aaaahtuhe2agoi2nrk4amg44vm@slack-elevaeducacao.slack.com'
        ,@Subject = N'Bloqueio detectado' 
*/
EXEC msdb.dbo.sp_send_dbmail
	@body_format = 'HTML',
	@profile_name = 'DBA',
	@recipients = 'monitoramento@clouddbm.com',
	@subject = '@subjec',
	@body = @tableHTML 
END

DROP TABLE #temp_requests
GO

/****** Object:  StoredProcedure [dbo].[spu_backup_diff]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


create procedure [dbo].[spu_backup_diff]  
  @database nvarchar(500)= null  
as  
declare @device  nvarchar(2000)          
declare @pathbackup nvarchar(2000)          
declare @cmdcrtdev nvarchar(2000)          
declare @cmddrpdev nvarchar(2000)          
declare @cmdbkp  nvarchar(2000)              
declare @table table (database_name varchar(500))   
declare @excecao table (database_name varchar(500))  

--determina path do diret?rio para backup          

set @pathbackup = 'D:\BackupFiles\' --Caso esta linha for alterada dever? alterar a abaixo seguindo o padr?o          

-- determina os bancos de excecao  
insert into @excecao  
select name from sysdatabases where name in ('tempdb', 'master', 'msdb', 'model', 'pubs','Northwind') 
or (databasepropertyex(name, 'STATUS') =  'RESTORING') 
or (DATABASEPROPERTYEX(name, 'IsInStandBy') = 1) 

-- verifica se o parametro banco foi informado, se nao executa para todos os bancos    
if @database is not null    
 begin     
  insert into @table    
  select name from sysdatabases where name = @database    
 end    
else    
 begin     
  insert into @table    
  select name from sysdatabases where name not in (select database_name from @excecao)                    
 end        

--------------------------------  

declare devices cursor for          
select name from sysdevices        
open devices          
fetch next from devices into @device          
while @@fetch_status = 0          
 begin            
  --apaga device nao necessarios          
  select @cmddrpdev = 'sp_dropdevice '''+name+''', delfile;'          
  from sysdevices where name not like 'BkpLG%'          
  and name not in (select 'Bkp'+name from sysdatabases)           
  and name not in (select 'Bkp'+name+'Diff' from sysdatabases)
	--and name not in ('master','mastlog','modeldev','modellog','tempdev','templog')           
  and name not in ('master','mastlog','modeldev','modellog','tempdev','templog','R3DUMP0','R3DUMP1','R3DUMP2') 
  and name = @device            
  exec(@cmddrpdev)          
  fetch next from devices into @device          
 end          
close devices          
deallocate devices     
----  

declare databases cursor for                  
select database_name from @table         
open databases        
fetch next from databases          
into @database                  
while @@fetch_status = 0          
 begin            
  --cria device de backup diferencial para database se nao existe          
  select @cmdcrtdev = 'if not exists (select 1 from sysdevices where name = ''Bkp'+name+'Diff'')'+char(13)+'exec sp_addumpdevice ''disk'', ''Bkp'+name+'Diff'', '''+@pathbackup+'Bkp'+name+'Diff.bak'''+';',          
  @cmdbkp  = 'backup database ['+name+'] to [Bkp'+name+'Diff] with differential, format, stats=1;'        
  from sysdatabases where name = @database          
  exec(@cmdcrtdev)          
  print 'Inicio do Backup do Database: '+@database+ ' - ' +cast(getdate() as varchar)          
  exec(@cmdbkp)   
  print 'Fim do Backup do Database: '+@database+ ' - ' +cast(getdate() as varchar)          
  print ''          
  fetch next from databases          
  into @database          
 end          
close databases          
deallocate databases
GO

/****** Object:  StoredProcedure [dbo].[spu_backup_full]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE procedure [dbo].[spu_backup_full]                       
 @database nvarchar(500) = null                                        
as                      

declare @device  nvarchar(2000)                                
declare @pathbackup nvarchar(2000)                                
declare @cmdcrtdev nvarchar(2000)                                
declare @cmddrpdev nvarchar(2000)                                
declare @cmdbkp  nvarchar(2000)                                            
declare @table table (database_name varchar(500))                   
declare @excecao table (database_name varchar(500))                  

--determina path do diretorio para backup                                
set @pathbackup = 'D:\BackupFiles\'      --Caso esta linha for alterada devera alterar a abaixo seguindo o padrao                                

-- determina os bancos de excecao                  
insert into @excecao                  
select name from sysdatabases where name in ('tempdb','Northwind','pubs')  
or (databasepropertyex(name, 'STATUS') =  'RESTORING') 
or (DATABASEPROPERTYEX(name, 'IsInStandBy') = 1)                



-- verifica se o parametro banco foi informado, se nao executa para todos os bancos                      
if @database is not null                      
 begin                       
  insert into @table                      
  select name from sysdatabases where name = @database                      
 end                      
else                      
 begin                       
  insert into @table                      
  select name from sysdatabases where name not in (select database_name from @excecao)                  
 end                      

------------                                
declare devices cursor for                                
select name from sysdevices                              
open devices                                
fetch next from devices into @device                                
while @@fetch_status = 0                                
 begin                                  
  --apaga device nao necessarios                                
  select @cmddrpdev = 'sp_dropdevice '''+name+''', delfile;'                                
  from sysdevices where name not like 'BkpLG%'                                
  and name not in (select 'Bkp'+name from sysdatabases)                                 
  and name not in (select 'Bkp'+name+'Diff' from sysdatabases)
  and name not in ('master','mastlog','modeldev','modellog','tempdev','templog','R3DUMP0','R3DUMP1','R3DUMP2')                               
  and name = @device                                  
  print @cmddrpdev                      
  exec(@cmddrpdev)                                
  fetch next from devices into @device                                
 end                                
close devices                                
deallocate devices                                   
-----------------------                    

declare databases cursor for                                    
select database_name from @table                           
open databases                                        
fetch next from databases                                
into @database                                
while @@fetch_status = 0                                
 begin                                
  --cria device de backup full para database se nao existe                                
  select @cmdcrtdev = 'if not exists (select 1 from sysdevices where name = ''Bkp'+name+''')'+char(13)+'exec sp_addumpdevice ''disk'', ''Bkp'+name+''', '''+@pathbackup+'Bkp'+name+'.bak'''+';',                                
  @cmdbkp  = 'backup database ['+name+'] to [Bkp'+name+'] with format,stats=1;'                              


  from sysdatabases where name = @database

  exec(@cmdcrtdev)                                
  print 'Inicio do Backup do Database: '+@database+ ' - ' +cast(getdate() as varchar)                       
  print @cmdbkp                            
  exec(@cmdbkp)                        
  print 'Fim do Backup do Database: '+@database+ ' - ' +cast(getdate() as varchar)                                
  print ''                                
  fetch next from databases into @database                                
 end                                
close databases                                
deallocate databases 
GO

/****** Object:  StoredProcedure [dbo].[spu_backup_log_init]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


create proc [dbo].[spu_backup_log_init]
 @Database varchar(500)= null        
as          

-- declarando var?aveis          
declare @Name varchar(500)          
declare @Device  varchar(2000)          
declare @QualDevice  varchar(2000)          
declare @CreateDevice varchar(2000)          
declare @ComandoBkp  varchar(2000)          
declare @ComandoDrop varchar(2000)          
declare @ComandoDrop2 varchar(2000)          
declare @ComandoDrop3 varchar(2000)          
declare @ComandoDrop4 varchar(2000)          
declare @ComandoDrop5 varchar(2000)          
declare @QualDisco   varchar(99)          
declare @QualDia     integer          
declare @table table (database_name varchar(500), recoverymode varchar(20))      
declare @excecao table (database_name varchar(500))  

-- define o local de cria??o dos Devices          

set @QualDisco = 'D:\BackupFiles\'

-- determina os bancos de excecao  
insert into @excecao  
select name from sysdatabases where name in ('master','msdb','model','tempdb','Northwind') 
or (databasepropertyex(name, 'STATUS') =  'RESTORING') 
or (DATABASEPROPERTYEX(name, 'IsInStandBy') = 1) 


-- verifica se o parametro banco foi informado, se nao executa para todos os bancos      
if @Database is not null      
 begin       
  insert into @table      
  select name, cast (databasepropertyex(name, 'Recovery')as varchar) as RecoveryMode       
  from sysdatabases where name = @Database      
  and databasepropertyex(name, 'Recovery') <> 'SIMPLE'        
 end      
else      
 begin       
  insert into @table      
  select name, cast (databasepropertyex(name, 'Recovery')as varchar) as RecoveryMode       
  from sysdatabases where name not in (select database_name from @excecao)          
  and databasepropertyex(name, 'Recovery') <> 'SIMPLE'        
 end      

-- listando os bancos de usu?rio que est?o no recovery mode full e s?o bancos de usu?rio        
declare databases cursor for                    
select database_name from @table           
open databases                    
fetch next from databases into @Database                    
while @@fetch_status = 0                    
 begin                      
  if LEFT(@Database,3) = 'BD_'          
   select @Name = substring(@Database,4,LEN(@Database))           
  else          
   set @Name = @Database          
  set @Device = 'BkpLG_'+ @Name          
-- set @Device = "BkpLG_"+ @Name          
-- removendo os devices anteriores a 2 dias        
  if exists (select name from sysdevices where name like '' + @Device + '' + left( datename(weekday,getdate()-6),3))           
   begin          


	select @ComandoDrop = 'sp_dropdevice @logicalname = ''' + @Device + left( datename(weekday,getdate()-6),3) 
    select @ComandoDrop = @ComandoDrop +  + ''', @delfile = ''delfile'''

	--  select @ComandoDrop = "sp_dropdevice @logicalname = '" + @Device + left( datename(weekday,getdate()-6),3)              
	--  select @ComandoDrop = @ComandoDrop + "', @delfile = 'delfile'"          
    EXECUTE  (@ComandoDrop)          
    print @ComandoDrop        
   End          
  if exists (select name from sysdevices where name like '' + @Device + '' + left( datename(weekday,getdate()-5),3))           
   begin          
	select @ComandoDrop2 = 'sp_dropdevice @logicalname = ''' + @Device + left( datename(weekday,getdate()-5),3) 
    select @ComandoDrop2 = @ComandoDrop2 +  + ''', @delfile = ''delfile'''

--    select @ComandoDrop2 = "sp_dropdevice @logicalname = '" + @Device + left( datename(weekday,getdate()-5),3)              
  --  select @ComandoDrop2 = @ComandoDrop2 + "', @delfile = 'delfile'"          
    EXECUTE  (@ComandoDrop2)          
    print @ComandoDrop2        
   end          
  if exists (select name from sysdevices where name like '' + @Device + '' + left( datename(weekday,getdate()-4),3))           
   begin
	select @ComandoDrop3 = 'sp_dropdevice @logicalname = ''' + @Device + left( datename(weekday,getdate()-4),3) 
    select @ComandoDrop3 = @ComandoDrop3 +  + ''', @delfile = ''delfile'''
    --select @ComandoDrop3 = "sp_dropdevice @logicalname = '" + @Device + left( datename(weekday,getdate()-4),3)              
    --select @ComandoDrop3 = @ComandoDrop3 + "', @delfile = 'delfile'"          
    EXECUTE  (@ComandoDrop3)          
    print @ComandoDrop3        
   end          
  if exists (select name from sysdevices where name like '' + @Device + ''  + left( datename(weekday,getdate()-3),3))           
   begin          


	select @ComandoDrop4 = 'sp_dropdevice @logicalname = ''' + @Device + left( datename(weekday,getdate()-3),3) 
    select @ComandoDrop4 = @ComandoDrop4 +  + ''', @delfile = ''delfile'''

    --select @ComandoDrop4 = "sp_dropdevice @logicalname = '" + @Device + left( datename(weekday,getdate()-3),3)              
    --select @ComandoDrop4 = @ComandoDrop4 + "', @delfile = 'delfile'"          
    EXECUTE  (@ComandoDrop4)          
    print @ComandoDrop4        
     end          
  if exists (select name from sysdevices where name like '' + @Device + '' + left( datename(weekday,getdate()-2),3))           
   begin          

	select @ComandoDrop5 = 'sp_dropdevice @logicalname = ''' + @Device + left( datename(weekday,getdate()-2),3) 
    select @ComandoDrop5 = @ComandoDrop5 +  + ''', @delfile = ''delfile'''

--select @ComandoDrop5 = "sp_dropdevice @logicalname = '" + @Device + left( datename(weekday,getdate()-2),3)              
  --  select @ComandoDrop5 = @ComandoDrop5 + "', @delfile = 'delfile'"
    EXECUTE  (@ComandoDrop5)          
    print @ComandoDrop5        
   end          

-- criando o device do dia        
  set @QualDevice = @Device + left( datename(weekday,getdate()),3)      
  if not exists (select name from sysdevices where name like '' + @Device + '' + left( datename(weekday,getdate()),3))      
 begin      
  set @CreateDevice = 'sp_addumpdevice ''disk'',''' + @QualDevice + ''','''           
  set @CreateDevice = @CreateDevice + @QualDisco + @QualDevice + '.bak'''          

  --set @CreateDevice = "sp_addumpdevice " + "'disk,'" + @QualDevice + "', '"           
  --set @CreateDevice = @CreateDevice + @QualDisco + @QualDevice + ".bak'"          
  print @CreateDevice          
  EXECUTE  (@CreateDevice)          
 end      

-- executando o backup de log           
 --set @ComandoBkp = "backup transaction " + @Database + " to " + @QualDevice + " with"          
 --select @ComandoBkp = @ComandoBkp + " init, nounload, noskip, stats=1"          

 set @ComandoBkp = 'backup log [' + @Database + '] to [' + @QualDevice + '] with'          
 select @ComandoBkp = @ComandoBkp + ' format, nounload, stats=1'          


 print @ComandoBkp        
 EXECUTE  (@ComandoBkp)          

 fetch next from databases into @Database                  
end                    
close databases                    
deallocate databases 

GO

/****** Object:  StoredProcedure [dbo].[spu_backup_log_noinit]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


create proc [dbo].[spu_backup_log_noinit]
 @Database varchar(500)= null      
as        

-- declarando var?aveis        
declare @Name varchar(500)        
declare @Device  varchar(2000)        
declare @QualDevice  varchar(2000)        
declare @CreateDevice varchar(2000)        
declare @ComandoBkp  varchar(2000)        
declare @QualDisco   varchar(99)        
declare @QualDia     integer        
declare @table table (database_name varchar(500), recoverymode varchar(25))    
declare @excecao table (database_name varchar(500))  

-- define o local de cria??o dos Devices        

set @QualDisco = 'D:\BackupFiles\'     

-- determina os bancos de excecao  
insert into @excecao  
select name from sysdatabases where name in ('master','msdb','model','tempdb','pubs','Northwind') 
or (databasepropertyex(name, 'STATUS') =  'RESTORING') 
or (DATABASEPROPERTYEX(name, 'IsInStandBy') = 1) 


-- verifica se o parametro banco foi informado, se nao executa para todos os bancos    
if @Database is not null    
 begin     
  insert into @table    
  select name, cast (databasepropertyex(name, 'Recovery')as varchar) as RecoveryMode     
  from sysdatabases where name = @Database    
  and databasepropertyex(name, 'Recovery') <> 'SIMPLE'      
 end    
else    
 begin     
  insert into @table    
  select name, cast (databasepropertyex(name, 'Recovery')as varchar) as RecoveryMode     
  from sysdatabases where name not in (select database_name from @excecao)         
  and databasepropertyex(name, 'Recovery') <> 'SIMPLE'      
 end    

-- listando os bancos de usu?rio que est?o no recovery mode full e s?o bancos de usu?rio      
declare databases cursor for                  
select database_name from @table         
open databases                         
fetch next from databases into @Database                  
while @@fetch_status = 0                  
 begin                    
  if LEFT(@Database,3) = 'BD_'        
   select @Name = substring(@Database,4,LEN(@Database))         
  else        
   set @Name = @Database        
   set @Device = 'BkpLG_'+ @Name        
   set @QualDevice = @Device + left( datename(weekday,getdate()),3)        
   set @ComandoBkp = 'backup log [' + @Database + '] to [' + @QualDevice + '] with'        
   select @ComandoBkp = @ComandoBkp + ' noinit, nounload, stats=1'        
-- executando o backup de log          
 print @ComandoBkp    
 EXECUTE  (@ComandoBkp)        
 fetch next from databases into @Database                
end                  
close databases                  
deallocate databases
GO

/****** Object:  StoredProcedure [dbo].[spu_checkblocking]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO




create   procedure [dbo].[spu_checkblocking]
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

/****** Object:  StoredProcedure [dbo].[spu_create_otimizacao_necessaria_todos_bancos]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


 
create procedure [dbo].[spu_create_otimizacao_necessaria_todos_bancos]  
as  
  
declare @proc_text varchar(8000)  
  
set @proc_text = ('CREATE procedure [dbo].[spu_otimizacao_necessaria] as    
print char(13)+''''OTIMIZANDO O BANCO ''''+db_name()+'''' ''''+char(13)+char(13)    
set nocount on    
declare @tablename varchar (128)    
declare @TABLE_SCHEMA varchar (128)   
declare @execstr   varchar (255)    
declare @ObjectId  int    
declare @indexid   int    
declare @frag      decimal    
declare @maxfrag   decimal    
declare @mindens  decimal    
declare @dens   decimal    
declare @nome_indice varchar(3000)  
select @maxfrag = 10    
select @mindens = 70    
  
declare tables cursor for    
   select TABLE_NAME,TABLE_SCHEMA  from INFORMATION_SCHEMA.TABLES (nolock)  where TABLE_TYPE = ''''BASE TABLE'''' order by TABLE_NAME    
create table #tabela_framentacao_acima_10_densidade_abaixo_70 (    
   ObjectName CHAR (255),    
   ObjectId INT,    
   IndexName CHAR (255),    
   IndexId INT,    
   Lvl INT,    
   CountPages INT,    
   CountRows INT,    
   MinRecSize INT,    
   MaxRecSize INT,    
   AvgRecSize INT,    
   ForRecCount INT,    
   Extents INT,    
   ExtentSwitches INT,    
   AvgFreeBytes INT,    
   AvgPageDensity INT,    
   ScanDensity DECIMAL,    
   BestCount INT,    
   ActualCount INT,    
   LogicalFrag DECIMAL,    
   ExtentFrag DECIMAL)    
create table #resultado_frag_lista_de_comandos_para_otimizacao (des_comando varchar(8000))    
open tables    
fetch next from tables into @tablename,@TABLE_SCHEMA    
while @@fetch_status = 0    
begin    
   insert into #tabela_framentacao_acima_10_densidade_abaixo_70 exec (''''dbcc showcontig ('''''''''''' + @TABLE_SCHEMA + ''''.'''' + @tablename + '''''''''''')  with fast, tableresults, all_indexes, no_infomsgs'''')    
   fetch next from tables into @tablename,@TABLE_SCHEMA    
end  
close tables    
deallocate tables  
declare indexes cursor for    
   select ObjectName,table_schema, ObjectId, IndexId, LogicalFrag, ScanDensity from #tabela_framentacao_acima_10_densidade_abaixo_70 tbl_frg, INFORMATION_SCHEMA.TABLES tbl (nolock)    
   where (LogicalFrag >= @maxfrag or ScanDensity < @mindens)  and indexproperty (ObjectId, IndexName, ''''INDEXDEPTH'''') > 0 and tbl_frg.ObjectName COLLATE DATABASE_DEFAULT = tbl.table_name COLLATE DATABASE_DEFAULT and tbl.TABLE_TYPE = ''''BASE TABLE''''
 COLLATE DATABASE_DEFAULT   
open indexes    
fetch next from indexes into @tablename, @TABLE_SCHEMA,@ObjectId, @indexid, @frag, @dens    
while @@fetch_status = 0    
begin    
 select @nome_indice = (select name from sysindexes (nolock) where id=@ObjectId and indid = @indexid)    
insert into #resultado_frag_lista_de_comandos_para_otimizacao   select ''''dbcc dbreindex ([''''+@TABLE_SCHEMA + ''''.''''+rtrim(@tablename) + ''''],['''' + rtrim(@nome_indice) + ''''])  -- fragmentation currently ''''       + rtrim(convert(varchar(15),@frag)) + ''''%'''' + ''''    -- density ''''+ rtrim(convert(varchar(15),@dens))+''''%'''' + char(13) +  ''''dbcc updateusage ([''''+db_name()+''''],''''+ ''''[''''+ @TABLE_SCHEMA + ''''.'''' + rtrim(@tablename) + ''''],['''' + rtrim(@nome_indice) + ''''])'''' + char(13) + ''''update statistics ['''' + @TABLE_SCHEMA + ''''].'''' + ''''[''''+ rtrim(@tablename) + ''''] ['''' + rtrim(@nome_indice) + ''''] with fullscan'''' + char(13)+ '''';''''  
   fetch next from indexes into @tablename, @TABLE_SCHEMA,@ObjectId, @indexid, @frag, @dens    
end    
close indexes    
deallocate indexes  
insert into #resultado_frag_lista_de_comandos_para_otimizacao     
select distinct ''''exec sp_recompile ['''' + TABLE_SCHEMA COLLATE DATABASE_DEFAULT + ''''.'''' + rtrim (ObjectName) COLLATE DATABASE_DEFAULT + '''']'''' resultado_frag from #tabela_framentacao_acima_10_densidade_abaixo_70  tbl_frg, INFORMATION_SCHEMA.TABLES tbl (nolock) where (LogicalFrag >= @maxfrag or ScanDensity < @mindens)  and indexproperty (ObjectId, IndexName, ''''indexdepth'''') > 0 and tbl_frg.ObjectName COLLATE DATABASE_DEFAULT = tbl.table_name COLLATE DATABASE_DEFAULT and tbl.TABLE_TYPE = ''''BASE TABLE''''  COLLATE DATABASE_DEFAULT  
DECLARE @comando varchar(8000)    
DECLARE @comando_header varchar(8000)    
DECLARE tnames_cursor CURSOR FOR     
select ltrim (des_comando) resultado_frag from #resultado_frag_lista_de_comandos_para_otimizacao order by des_comando    
OPEN tnames_cursor    
FETCH NEXT FROM tnames_cursor INTO @comando    
WHILE (@@fetch_status <> -1)    
BEGIN    
 IF (@@fetch_status <> -2)    
 BEGIN  SET @comando_header = RTRIM(UPPER(@comando))    
  PRINT @comando_header    
         EXEC (@comando)    
 END    
 FETCH NEXT FROM tnames_cursor INTO @comando    
END    
SELECT @comando_header = ''''*NO MORE TABLES'''' + ''''  *''''  
PRINT @comando_header    
PRINT ''''Statistics have been updated for all tables.''''+char(13)    
DEALLOCATE tnames_cursor  
drop table #tabela_framentacao_acima_10_densidade_abaixo_70    
drop table #resultado_frag_lista_de_comandos_para_otimizacao')  
  
--select len (@proc_text)  
  
IF OBJECT_ID('tempdb..#database') IS NOT NULL   
drop table #database  
  
select name into #database from master..sysdatabases where name not in ('model','master','tempdb') and databasepropertyex(name, 'Updateability') <> 'READ_ONLY' and cmptlevel <> 65
  
--select name into #database from sysdatabases where name  in ('bd_xss')  
  
select * from #database  
  
declare @dbname varchar(200)  
  
while (select count(*) from #database) <> 0  
  
begin  
  
select top 1 @dbname = name from #database  
  
print @dbname  
  
IF OBJECT_ID('tempdb..#sysobjects') IS NOT NULL   
drop table #sysobjects  
--drop table #sysobjects  
  
SELECT TOP 0 name INTO #sysobjects FROM [sysobjects]  
  
INSERT INTO #sysobjects  
  EXEC('USE [' + @dbname + '] SELECT name FROM [sysobjects] where type = ''P''')  
  
  --select * from  #sysobjects  
  
  IF NOT EXISTS(SELECT * FROM #sysobjects WHERE [name] = N'spu_otimizacao_necessaria')  
        BEGIN  
  
   DECLARE @sql varchar(8000)  
   SET @sql = 'USE [' + @dbname + ']; EXEC ('' ' + @proc_text + ''');'  
  
   --print @sql 
   PRINT 'Procedure created in database: ' + @DBName + ''''   
      
   --EXEC sp_Executesql   
   exec(@sql)  
      
   END  
  ELSE  
   PRINT 'Procedure already exists in database: ' + @DBName + ''''  
  
   delete from #database where name = @dbname  
  end  
  
print @dbname  

GO

/****** Object:  StoredProcedure [dbo].[spu_export_table_html_output]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[spu_export_table_html_output] 
    @Ds_Tabela [varchar](max),
    @Fl_Aplica_Estilo_Padrao BIT = 1,
    @Ds_Alinhamento VARCHAR(10) = 'left',
    @Ds_OrderBy VARCHAR(MAX) = '',
    @Ds_Saida VARCHAR(MAX) OUTPUT

	--with encryption

AS
BEGIN   
    
    SET NOCOUNT ON    
    
    DECLARE
        @query NVARCHAR(MAX),
        @Database sysname,
        @Nome_Tabela sysname		   
    
    IF (LEFT(@Ds_Tabela, 1) = '#')
    BEGIN
        SET @Database = 'tempdb.'
        SET @Nome_Tabela = @Ds_Tabela
    END
    ELSE BEGIN
        SET @Database = LEFT(@Ds_Tabela, CHARINDEX('.', @Ds_Tabela))
        SET @Nome_Tabela = SUBSTRING(@Ds_Tabela, LEN(@Ds_Tabela) - CHARINDEX('.', REVERSE(@Ds_Tabela)) + 2, LEN(@Ds_Tabela))
    END
    
    SET @query = '
    SELECT ORDINAL_POSITION, COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, NUMERIC_PRECISION, NUMERIC_SCALE
    FROM ' + @Database + 'INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = ''' + @Nome_Tabela + '''
    ORDER BY ORDINAL_POSITION'    
    
    IF (OBJECT_ID('tempdb..#Colunas') IS NOT NULL) DROP TABLE #Colunas
    CREATE TABLE #Colunas (
        ORDINAL_POSITION int, 
        COLUMN_NAME sysname, 
        DATA_TYPE nvarchar(128), 
        CHARACTER_MAXIMUM_LENGTH int,
        NUMERIC_PRECISION tinyint, 
        NUMERIC_SCALE int
    )

    INSERT INTO #Colunas
    EXEC(@query)    
    
    IF (@Fl_Aplica_Estilo_Padrao = 1)
    BEGIN    
    SET @Ds_Saida = '<html>
<head>
    <title>Titulo</title>
    <style type="text/css">
        table { padding:0; border-spacing: 0; border-collapse: collapse; }
        thead { background: #3299bb; border: 1px solid #ddd; }
        th { padding: 10px; font-weight: bold; border: 1px solid #000; color: #fff; }
        tr { padding: 0; }
        td { padding: 5px; border: 1px solid #cacaca; margin:0; text-align:' + @Ds_Alinhamento + '; }
    </style>
</head>'    
    END      
    
    SET @Ds_Saida = ISNULL(@Ds_Saida, '') + '
<table>
    <thead>
        <tr>'
    -- Cabeçalho da tabela
    DECLARE 
        @contadorColuna INT = 1, 
        @totalColunas INT = (SELECT COUNT(*) FROM #Colunas), 
        @nomeColuna sysname,
        @tipoColuna sysname    

    WHILE(@contadorColuna <= @totalColunas)
    BEGIN

        SELECT @nomeColuna = COLUMN_NAME
        FROM #Colunas
        WHERE ORDINAL_POSITION = @contadorColuna

        SET @Ds_Saida = ISNULL(@Ds_Saida, '') + '
            <th>' + @nomeColuna + '</th>'

        SET @contadorColuna = @contadorColuna + 1
    END

    SET @Ds_Saida = ISNULL(@Ds_Saida, '') + '
        </tr>
    </thead>
    <tbody>'
    
    -- Conteúdo da tabela

    DECLARE @saida VARCHAR(MAX)

    SET @query = '
SELECT @saida = (
    SELECT '

    SET @contadorColuna = 1

    WHILE(@contadorColuna <= @totalColunas)
    BEGIN

        SELECT 
            @nomeColuna = COLUMN_NAME,
            @tipoColuna = DATA_TYPE
        FROM 
            #Colunas
        WHERE 
            ORDINAL_POSITION = @contadorColuna

        IF (@tipoColuna IN ('int', 'bigint', 'float', 'numeric', 'decimal', 'bit', 'tinyint', 'smallint', 'integer'))
        BEGIN
        
            SET @query = @query + '
    ISNULL(CAST([' + @nomeColuna + '] AS VARCHAR(MAX)), '''') AS [td]'
    
        END
        ELSE BEGIN
        
            SET @query = @query + '
    ISNULL([' + @nomeColuna + '], '''') AS [td]'
    
        END    
        
        IF (@contadorColuna < @totalColunas)
            SET @query = @query + ','
        
        SET @contadorColuna = @contadorColuna + 1

    END
	
    SET @query = @query + '
FROM ' + @Ds_Tabela + (CASE WHEN ISNULL(@Ds_OrderBy, '') = '' THEN '' ELSE ' 
ORDER BY ' END) + @Ds_OrderBy + '
FOR XML RAW(''tr''), Elements
)'
        
    EXEC tempdb.sys.sp_executesql
        @query,
        N'@saida NVARCHAR(MAX) OUTPUT',
        @saida OUTPUT

    -- Identação
    SET @saida = REPLACE(@saida, '<tr>', '
        <tr>')

    SET @saida = REPLACE(@saida, '<td>', '
            <td>')

    SET @saida = REPLACE(@saida, '</tr>', '
        </tr>')

    SET @Ds_Saida = ISNULL(@Ds_Saida, '') + @saida
	       
    SET @Ds_Saida = ISNULL(@Ds_Saida, '') + '
    </tbody>
</table>'    
            
END

GO

/****** Object:  StoredProcedure [dbo].[spu_finaliza_otimizacao_necessaria]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE proc [dbo].[spu_finaliza_otimizacao_necessaria] as 
declare
       @isql varchar(MAX),
       @dbname varchar(MAX),
       @logfile varchar(MAX)
       
       declare c1 cursor for 
       SELECT  d.name from  sys.databases d
       where recovery_model_desc <> 'SIMPLE'   
       open c1
       fetch next from c1 into @dbname
       While @@fetch_status <> -1
             begin
             select @isql = 'ALTER DATABASE [' + @dbname + '] SET RECOVERY FULL'
             print @isql
             exec(@isql)
             --select @isql='USE ' + @dbname + ' checkpoint'
             --print @isql
             --exec(@isql)
             --select @isql='USE ' + @dbname + ' DBCC SHRINKFILE (' + @logfile + ', 1)'
             --print @isql
             --exec(@isql)
             
             fetch next from c1 into @dbname
             end
       close c1
       deallocate c1


GO

/****** Object:  StoredProcedure [dbo].[spu_GerenciaBD]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   procedure [dbo].[spu_GerenciaBD] as  
  
-- Evitando exibição de registros  
  
set nocount on  
  
-- Declarando variável para multi-servidor  
  
DECLARE @SERVIDOR_MONITORANDO VARCHAR(100)  
DECLARE @BANCO_MONITORANDO VARCHAR(100)  
DECLARE @TABELA_TABELA_MONITORANDO VARCHAR(100)  
DECLARE @SERVIDOR_MONITORADO nvarchar(128)  
  
-- Atribuindo variáveis para configuração do GerenciaBD GACO  
  
SET  @SERVIDOR_MONITORANDO = (select @@servername)  
SET  @BANCO_MONITORANDO = 'DBMANAGER'  
SET  @TABELA_TABELA_MONITORANDO = 'TRACE_DIA_GERAL'  


DECLARE 
		@ChkSrvName varchar(128)					/*Stores Server Name*/
		,@PhysicalSrvName VARCHAR(128)				/*Stores physical name*/
		,@TrueSrvName varchar(128)					/*Stores Full Name*/

SET @PhysicalSrvName = CAST(SERVERPROPERTY('MachineName') AS VARCHAR(128)) 
set @ChkSrvName = CAST(SERVERPROPERTY('INSTANCENAME') AS VARCHAR(128)) 

IF @ChkSrvName IS NULL								/*Detect default or named instance*/
	BEGIN 
		SET @TrueSrvName = @PhysicalSrvName
	END 
ELSE
	BEGIN
		SET @TrueSrvName =  @PhysicalSrvName +'\' + @ChkSrvName
		
	END 

print @TrueSrvName 
   
SET  @SERVIDOR_MONITORADO = @TrueSrvName
  
-- Coletando caminho do SQL Server para gravar trace file otimizado, via server trace  
  
declare @rc2 int, @dir nvarchar(4000)    
   
exec @rc2 = master.dbo.xp_instance_regread   
      N'HKEY_LOCAL_MACHINE',   
      N'Software\Microsoft\MSSQLServer\Setup',   
      N'SQLPath',    
      @dir output, 'no_output'   
  
--select @dir AS InstallationDirectory  
--PRINT @dir + '\indicador_performance_dia'  
  
-- Localizando e finalizando server trace anterior somente do GerenciaBD  
  
declare @traceid2 int  
declare @caminho varchar(1000)  
declare @caminho2 varchar(1000)  
  
set @caminho =  'c:\temp' + '\indicador_performance_dia'  
set @caminho2 =  'c:\temp' + '\indicador_performance_dia.trc'  
  
SELECT top 1 @traceid2 = traceid FROM :: fn_trace_getinfo(default) where value = @caminho  
  
if @traceid2 is null   
 SELECT top 1 @traceid2 = traceid FROM :: fn_trace_getinfo(default) where value = @caminho2  
  
select @traceid2  
  
if @traceid2 is not null   
begin  
 EXEC sp_trace_setstatus @traceid2, 0   
 EXEC sp_trace_setstatus @traceid2, 2  
  
  
  
-- Definindo comando para contabilização de indicadores do GerenciaBD  
  
 DECLARE @COMANDO_INSERT_SERVIDOR_MONITORANDO VARCHAR(8000)  

IF EXISTS (SELECT * FROM dbo.sysobjects WHERE id = OBJECT_ID(N'prodver') AND OBJECTPROPERTY(id, N'IsUserTable') = 1)                                            
drop table prodver                    
create table prodver ([index] int, Name nvarchar(50),Internal_value int, Charcater_Value nvarchar(50))                    
insert into prodver exec master.dbo.xp_msver 'ProductVersion'                    


 --if (select substring(Charcater_Value,1,1)from prodver)<= 8 -- Verificando a versão o server trace  
 
  IF 10 <= 8 
  
  
 SET @COMANDO_INSERT_SERVIDOR_MONITORANDO = 'insert into [' +@SERVIDOR_MONITORANDO + ']' + '.' + @BANCO_MONITORANDO + '.DBO.' + @TABELA_TABELA_MONITORANDO +  
         ' SELECT '+  '''' +@SERVIDOR_MONITORADO +''',textdata, databaseid, ntusername, hostname, applicationname, loginname, duration/1000, starttime   
      from ::fn_trace_gettable(''' + 'c:\temp' + '\indicador_performance_dia.trc''' + ', default)'  
  
else  
  
 SET @COMANDO_INSERT_SERVIDOR_MONITORANDO = 'insert into [' +@SERVIDOR_MONITORANDO + ']' + '.' + @BANCO_MONITORANDO + '.DBO.' + @TABELA_TABELA_MONITORANDO +  
         ' SELECT '+  '''' +@SERVIDOR_MONITORADO +''',textdata, databaseid, ntusername, hostname, applicationname, loginname, duration/1000000, starttime   
      from ::fn_trace_gettable(''' + 'c:\temp' + '\indicador_performance_dia.trc''' + ', default)'  

/*  
  USE [DB_MANUTENCAO]
GO

drop table trace_dia_geral
go

CREATE TABLE [dbo].[trace_dia_geral](
	[cod_servidor] [varchar](255) NULL,
	[TextData] [ntext] NULL,
	[DatabaseID] [int] NULL,
	[NTUserName] [nvarchar](128) NULL,
	[HostName] [nvarchar](128) NULL,
	[ApplicationName] [nvarchar](128) NULL,
	[LoginName] [nvarchar](128) NULL,
	[Duration] [bigint] NULL,
	[StartTime] [datetime] NULL)

	
	
		[CPU] [int] NULL,
	[Reads] [bigint] NULL,
	[Writes] [bigint] NULL,

	[ClientProcessID] [int] NULL,
	[SPID] [int] NULL,

	[EndTime] [datetime] NULL,
	[BinaryData] [image] NULL,

	[DatabaseName] [nvarchar](128) NULL,
	[Error] [int] NULL,
	[EventSequence] [bigint] NULL,
	[GroupID] [int] NULL,

	[IntegerData] [int] NULL,
	[IsSystem] [int] NULL,
	[LoginSid] [image] NULL,
	[NTDomainName] [nvarchar](128) NULL,
	[ObjectName] [nvarchar](128) NULL,
	[RequestID] [int] NULL,
	[RowCounts] [bigint] NULL,
	[SessionLoginName] [nvarchar](128) NULL,
	[TransactionID] [bigint] NULL,
	[XactSequence] [bigint] NULL,
PRIMARY KEY CLUSTERED 
(
	[RowNumber] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO


*/
  
-- Executando comando para contabilização de indicadores do GerenciaBD  
  
 exec (@COMANDO_INSERT_SERVIDOR_MONITORANDO)  
  
end  
  
-- Definindo comando para deleção de arquivos de trace já contabilizado  
  
 DECLARE @COMANDO_DELECAO VARCHAR (1000)  
  
 SET @COMANDO_DELECAO = 'del "'+ 'c:\temp' + '\indicador_performance_dia.trc"'  
  
 print @COMANDO_DELECAO  
  
-- Executando comando para deleção de arquivo de trace já contabilizado  
  
 exec master..xp_cmdshell @COMANDO_DELECAO  
  
  
-- Gerando server trace otimizado do GerenciaBD  
  
/****************************************************/  
/* Created by: SQL Profiler                         */  
/* Date: 27/04/2005  16:16:01         */  
/****************************************************/  
  
  
-- Create a Queue  
declare @rc int  
declare @TraceID int  
declare @maxfilesize bigint  
declare @datetime datetime  
--declare @caminho varchar(50)  
SET DATEFORMAT ymd;    
set @datetime = cast ((select convert (varchar(10),getdate(),120) + ' 23:59:59.99') as datetime)

print @datetime
set @maxfilesize = 10000   
  
--print @dir  
declare @arquivo_trace nvarchar(128)  
set @arquivo_trace = 'c:\temp' + '\indicador_performance_dia'  
print @arquivo_trace  
-- Please replace the text InsertFileNameHere, with an appropriate  
-- filename prefixed by a path, e.g., c:\MyFolder\MyTrace. The .trc extension  
-- will be appended to the filename automatically. If you are writing from  
-- remote server to local drive, please use UNC path and make sure server has  
-- write access to your network share  
  
--set @caminho = 'D:\SQLADMIN\MSSQL\LOG\' + convert (varchar(50),getdate(),112)  
--select @caminho  
exec @rc = sp_trace_create @TraceID output, 0, @arquivo_trace, @maxfilesize, @datetime  
if (@rc != 0) goto error  
  
  
  
-- Client side File and Table cannot be scripted  
  
-- Writing to a table is not supported through the SP's  
  
-- Set the events  
declare @on bit  
set @on = 1  
exec sp_trace_setevent @TraceID, 10, 1, @on  
exec sp_trace_setevent @TraceID, 10, 3, @on  
exec sp_trace_setevent @TraceID, 10, 6, @on  
exec sp_trace_setevent @TraceID, 10, 8, @on  
exec sp_trace_setevent @TraceID, 10, 9, @on  
exec sp_trace_setevent @TraceID, 10, 10, @on  
exec sp_trace_setevent @TraceID, 10, 11, @on  
exec sp_trace_setevent @TraceID, 10, 12, @on  
exec sp_trace_setevent @TraceID, 10, 13, @on  
exec sp_trace_setevent @TraceID, 10, 14, @on  
exec sp_trace_setevent @TraceID, 10, 16, @on  
exec sp_trace_setevent @TraceID, 10, 17, @on  
exec sp_trace_setevent @TraceID, 10, 18, @on  
exec sp_trace_setevent @TraceID, 12, 1, @on  
exec sp_trace_setevent @TraceID, 12, 3, @on  
exec sp_trace_setevent @TraceID, 12, 6, @on  
exec sp_trace_setevent @TraceID, 12, 8, @on  
exec sp_trace_setevent @TraceID, 12, 9, @on  
exec sp_trace_setevent @TraceID, 12, 10, @on  
exec sp_trace_setevent @TraceID, 12, 11, @on  
exec sp_trace_setevent @TraceID, 12, 12, @on  
exec sp_trace_setevent @TraceID, 12, 13, @on  
exec sp_trace_setevent @TraceID, 12, 14, @on  
exec sp_trace_setevent @TraceID, 12, 16, @on  
exec sp_trace_setevent @TraceID, 12, 17, @on  
exec sp_trace_setevent @TraceID, 12, 18, @on  
  
  
-- Set the Filters  
declare @intfilter int  
declare @bigintfilter bigint  
  
-- Verifica qual a versão do SQL Server para filtrar o server trace  
  
IF 10 <= 8 

--if (select substring(Charcater_Value,1,1) from prodver)<= 8  
	begin 
		set @bigintfilter = 3000   
	end
else 
	begin 
		set @bigintfilter = 3000000  
	end
	
exec sp_trace_setfilter @TraceID, 13, 0, 4, @bigintfilter  
exec sp_trace_setfilter @TraceID, 8, 0, 7, @SERVIDOR_MONITORADO  
exec sp_trace_setfilter @TraceID, 10, 0, 7, N'SQL Profiler'  
exec sp_trace_setfilter @TraceID, 10, 0, 7, N'SQLAgent%'  
set @intfilter = 100  
exec sp_trace_setfilter @TraceID, 22, 0, 4, @intfilter  
  
  
  
-- Set the trace status to start  
exec sp_trace_setstatus @TraceID, 1  
  
-- display trace id for future references  
select TraceID=@TraceID  
goto finish  
  
error:   
select ErrorCode=@rc  
  
finish:   
  
   
--EXEC sp_trace_setstatus 1, 0   
--EXEC sp_trace_setstatus 1, 2  
  
--EXEC sp_trace_setstatus 2, 0   
--EXEC sp_trace_setstatus 2, 2  
  
  
--SELECT * FROM :: fn_trace_getinfo(default)  
--select * into Trace_Table from ::fn_trace_gettable('c:\ind_perf\sicla_indicador_perform  
  
  
-- Contabilizando informações de Bloqueios coletadas pelo job schedulado Alerta - Monitora Processos Bloqueados  
  






GO

/****** Object:  StoredProcedure [dbo].[spu_get_db_files_near_maxsize]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO



CREATE PROCEDURE [dbo].[spu_get_db_files_near_maxsize] (@nearMaxSizePct DECIMAL (5,1) = 10.0)  
AS  
BEGIN  
SET NOCOUNT ON  
  
CREATE TABLE ##ALL_DB_Files (  
dbname SYSNAME,  
fileid smallint,  
groupid smallint,  
[size] INT NOT NULL,  
[maxsize] INT NOT NULL,  
growth INT NOT NULL,  
status INT,  
perf INT,  
[name] SYSNAME NOT NULL,  
[filename] NVARCHAR(260) NOT NULL)  
  
-- loop over all databases and collect the information from sysfiles  
-- to the ALL_DB_Files tables using the sp_MsForEachDB system procedure  
EXEC sp_MsForEachDB  
@command1='use [$];Insert into ##ALL_DB_Files select db_name(), * from sysfiles',  
@replacechar = '$'  
  
-- output the results  
SELECT   
[dbname] AS DatabaseName,  
[name] AS dbFileLogicalName,  
[filename] AS dbFilePhysicalFilePath,  
ROUND(size * CONVERT(FLOAT,8) / 1024,0) AS ActualSizeMB,  
ROUND(maxsize * CONVERT(FLOAT,8) / 1024,0) AS MaxRestrictedSizeMB,  
ROUND(maxsize * CONVERT(FLOAT,8) / 1024,0) - ROUND(size * CONVERT(FLOAT,8) / 1024,0) AS SpaceLeftMB  
FROM ##ALL_DB_Files  
WHERE maxsize > -1 AND -- skip db files that have no max size   
([maxsize] - [size]) * 1.0 < 0.01 * @nearMaxSizePct * [maxsize] -- find db files within percentage  
ORDER BY 6  
  
DROP TABLE ##ALL_DB_Files  
  
SET NOCOUNT OFF  
END  

-------------------

GO

/****** Object:  StoredProcedure [dbo].[spu_health_check]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE   PROCEDURE [dbo].[spu_health_check]-- with encryption
AS
BEGIN
	SET NOCOUNT ON;	

-- ##########

DECLARE
	@profile_nam        VARCHAR(MAX) = 'DBA',
	@recipient          NVARCHAR(MAX) = 'vpmaciel@gmail.com;',	
	@subjec             VARCHAR(MAX) ,		
	@HTML				VARCHAR(MAX),
	@HTML2				VARCHAR(MAX)

-- ########## ASSUNTO DO EMAIL

SET @subjec = 'Health Check - <CLIENTE> - ' 
	+ CAST(@@servername AS NVARCHAR(1000)) + ' - '
	+ convert(nvarchar, getdate(), 20)
	
-- ########## TÍTULO

SET @HTML =  
'<h2>REPORT STATUS - SQL SERVER</h2>
<br/><br/>'

-- ########## SQL SERVER VERSION

DECLARE	@MENSAGEM VARCHAR(MAX)

IF OBJECT_ID(N'tempdb..##INFORMACOES_VERSAO_SQL') IS NOT NULL
	DROP TABLE ##INFORMACOES_VERSAO_SQL

CREATE TABLE ##INFORMACOES_VERSAO_SQL (
[Version] VARCHAR(MAX)
)

SET @MENSAGEM =  @@VERSION
INSERT INTO ##INFORMACOES_VERSAO_SQL VALUES(@MENSAGEM)

--Cabecalho
SET @HTML = @HTML +
'<h2>SQL SERVER VERSION</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##INFORMACOES_VERSAO_SQL', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = ''	

SET @HTML = @HTML + @HTML2

-- ########## SERVER

IF OBJECT_ID(N'tempdb..##INFORMACOES_SERVER') IS NOT NULL
	DROP TABLE ##INFORMACOES_SERVER
SELECT
	CASE SERVERPROPERTY('IsClustered') 
		WHEN 1 THEN 'CLUSTERED' 
		WHEN 0 THEN 'NOT CLUSTERED' 
		ELSE 'STANDALONE' 
	END AS [Instance Type],
	CASE SERVERPROPERTY('IsClustered') 
		WHEN 1 THEN SERVERPROPERTY('ComputerNamePhysicalNetBIOS') 
		ELSE '-' 
	END AS [Computer Name Physical NetBIOS],
    CASE SERVERPROPERTY('IsClustered') 
		WHEN 1 THEN (
						SELECT DISTINCT STUFF((SELECT ', ' + [NodeName] 
						FROM sys.dm_os_cluster_nodes 
						ORDER BY NodeName Asc FOR XML PATH(''),TYPE).value('(./text())[1]','VARCHAR(MAX)'),1,2,'') AS NameValues FROM sys.dm_os_cluster_nodes) 
		ELSE '-' 
	END [Cluster Nodes Name],
	RTRIM(CONVERT(CHAR(3),DATEDIFF(second,login_time,getdate())/86400)) + ':' +
	RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400/3600)),2) + ':' +
	RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400%3600/60)),2) + ':' +
	RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400%3600%60)),2) AS [Uptime SQL Server (DD:HRS:MIN:SEC)],
	(SELECT 
		CASE 
			WHEN AgentStatus = 0 AND IsExpress = 0 THEN 'OFFLINE' 
			ELSE 'ONLINE' 
		END 
     FROM 
		(SELECT 
			CASE 
				WHEN REPLACE(CAST(SERVERPROPERTY('edition') AS VARCHAR), ' Edition', '') LIKE '%Express%' THEN 1 
				ELSE 0 
			END [IsExpress] 
			, COUNT(1) AgentStatus 
	     FROM master.sys.sysprocesses 
		 WHERE program_name = N'SQLAgent - Generic Refresher') TabAgent
		) AS [Agent Status]
INTO ##INFORMACOES_SERVER
FROM master.sys.sysprocesses
WHERE spid = 1 

--Cabecalho
SET @HTML = @HTML +
'<h2>SERVER</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##INFORMACOES_SERVER', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = ''	
	
SET @HTML = @HTML + @HTML2

IF @HTML2 IS NULL 
BEGIN
	SET @HTML = @HTML +'
		<br/><br/>
		NO INFORMATION<br/><br/>'		
END

-- ########## SQL SERVER UPTIME

IF OBJECT_ID(N'tempdb..##ULTIMO_INICIO_SQL_SERVER') IS NOT NULL
	DROP TABLE ##ULTIMO_INICIO_SQL_SERVER

--Calculate SQLServer Uptime -Returns [Days:Hours:Minutes:Seconds]
SELECT RTRIM(CONVERT(CHAR(3),DATEDIFF(second,login_time,getdate())/86400)) + ':' +
	RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400/3600)),2) + ':' +
	RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400%3600/60)),2) + ':' +
	RIGHT('00'+RTRIM(CONVERT(CHAR(2),DATEDIFF(second,login_time,getdate())%86400%3600%60)),2) AS [Uptime SQL Server (DD:HRS:MIN:SEC)]
	INTO ##ULTIMO_INICIO_SQL_SERVER
FROM sys.sysprocesses  --sysprocesses for SQL versions <2000
WHERE spid = 1 

--Cabecalho
SET @HTML = @HTML +
'<h2>SQL SERVER UPTIME</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##ULTIMO_INICIO_SQL_SERVER', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = ''	

SET @HTML = @HTML + @HTML2

-- ########## MALWARE

IF OBJECT_ID(N'tempdb..##CHECK_MALWARE') IS NOT NULL
	DROP TABLE ##CHECK_MALWARE

SELECT COUNT(1) AS Malware	
	INTO ##CHECK_MALWARE
FROM sys.server_principals 		
WHERE [name] = 'Default'

--Cabecalho
SET @HTML = @HTML +
'<h2>MALWARE</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##CHECK_MALWARE', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = ''	

SET @HTML = @HTML + @HTML2

-- ########## DRIVES

IF OBJECT_ID(N'tempdb..##INFORMACOES_DISCO') IS NOT NULL
DROP TABLE ##INFORMACOES_DISCO

--Solucao 01
--CREATE TABLE ##INFORMACOES_DISCO (
--Drive VARCHAR(MAX),
--[Free MB] VARCHAR(MAX)
--)
--INSERT INTO ##INFORMACOES_DISCO EXEC xp_fixeddrives

--Solucao 02
SELECT DISTINCT
	VS.volume_mount_point [Drive] ,
	VS.logical_volume_name AS [Volume] ,
	CAST(CAST(VS.total_bytes AS DECIMAL(19, 2)) / 1024 / 1024 / 1024 AS DECIMAL(10, 2)) AS [Total (GB)] ,
	CAST(CAST(VS.available_bytes AS DECIMAL(19, 2)) / 1024 / 1024 / 1024 AS DECIMAL(10, 2)) AS [Available (GB)] ,
	CAST(( CAST(VS.available_bytes AS DECIMAL(19, 2)) / CAST(VS.total_bytes AS DECIMAL(19, 2)) * 100 ) AS DECIMAL(10, 2)) AS [Available ( % )] ,
	CAST(( 100 - CAST(VS.available_bytes AS DECIMAL(19, 2)) / CAST(VS.total_bytes AS DECIMAL(19, 2)) * 100 ) AS DECIMAL(10, 2)) AS [Use ( % )]
	INTO ##INFORMACOES_DISCO
FROM
	sys.master_files AS MF
	CROSS APPLY [sys].[dm_os_volume_stats](MF.database_id, MF.file_id) AS VS
WHERE
	CAST(VS.available_bytes AS DECIMAL(19, 2)) / CAST(VS.total_bytes AS DECIMAL(19, 2)) * 100 < 100
ORDER BY VS.volume_mount_point

--Cabecalho
SET @HTML = @HTML +
'<h2>DRIVES</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##INFORMACOES_DISCO', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = ''	

SET @HTML = @HTML + @HTML2
--f

-- ########## BACKUP SQL SERVER

IF OBJECT_ID(N'tempdb..##INFORMACOES_BACKUP') IS NOT NULL
DROP TABLE ##INFORMACOES_BACKUP

SELECT @@servername [Server Name]
	, a.[name] [Database Name]
	,backup_date [Backup Date]
	, 'FULL' [Type]
	, GETDATE() [Finish Date]
	INTO ##INFORMACOES_BACKUP
FROM master.dbo.sysdatabases  a (NOLOCK)  
	LEFT JOIN 
		(
		SELECT database_name
			,max(backup_finish_date) backup_date 
		FROM msdb.dbo.backupset (NOLOCK) 
		WHERE type in ('D') 
		GROUP BY database_name
		)  b 
	ON  a.[name] = b.database_name 
WHERE a.[name] NOT IN ('tempdb','master','model','msdb','CtrDad1','CtrDadBiohosp','DBManager','Traces')  
	AND databasepropertyex([name], 'Status') = 'ONLINE'
	AND backup_date <= getdate()-7 
	OR backup_date IS NULL 
	AND a.[name] NOT IN ('tempdb','master','model','msdb','CtrDad1','CtrDadBiohosp','DBManager','Traces') 
	AND databasepropertyex([name], 'Status') = 'ONLINE'
UNION 
SELECT 
	@@servername cod_servidor
	, a.[name],backup_date
	, 'DIFF' tip_event
	, GETDATE() dth_atualiza 
FROM master.dbo.sysdatabases  a (NOLOCK)
	LEFT JOIN 
		(
			SELECT database_name,max(backup_finish_date) backup_date 
			FROM msdb.dbo.backupset (NOLOCK) 
			WHERE type in ('I') 
			GROUP BY database_name
		)  b 
	ON  a.[name] = b.database_name 
WHERE rtrim (lower (a.[name])) NOT IN ('tempdb','master','model','msdb','CtrDad1','CtrDadBiohosp','DBManager','Traces')  
	AND databasepropertyex([name], 'Status') = 'ONLINE'	
	AND backup_date <= getdate()-1 
	OR backup_date IS NULL 
	AND [name] NOT IN ('tempdb','master','model','msdb','CtrDad1','CtrDadBiohosp','DBManager','Traces')  
	AND databasepropertyex([name], 'Status') = 'ONLINE'
UNION 
SELECT @@servername cod_servidor
	, a.[name],backup_date, 'LOG' tip_evento
	, GETDATE() dth_atualiza 
FROM master.dbo.sysdatabases  a (NOLOCK)
	LEFT JOIN 
		(
			SELECT database_name,max(backup_finish_date) backup_date 
			FROM msdb.dbo.backupset (NOLOCK) 
			WHERE type in ('L') 
			GROUP BY database_name
		)  b 
		ON  a.[name] = b.database_name 
WHERE name NOT IN ('tempdb','master','model','msdb','CtrDad1','CtrDadBiohosp','DBManager','Traces') 
	AND  ((databasepropertyex([name], 'Recovery') = 'FULL') 
			or databasepropertyex([name], 'Recovery') = 'BULK_LOGGED') 
	AND databasepropertyex([name], 'Status') = 'ONLINE' 
	AND databasepropertyex([name], 'Updateability') <> 'READ_ONLY' 	
	AND backup_date <= getdate()-1 
	OR backup_date IS NULL 
	AND name NOT IN ('tempdb','master','model','msdb','CtrDad1','CtrDadBiohosp','DBManager','Traces') 
	AND databasepropertyex(name, 'Recovery') = 'FULL' 
	AND databasepropertyex(name, 'Status') = 'ONLINE' 
	AND databasepropertyex(name, 'Updateability') <> 'READ_ONLY' 

--Cabecalho
SET @HTML = @HTML +
'<h2>BACKUP SQL SERVER</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##INFORMACOES_BACKUP', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = ''	

SET @HTML = @HTML + @HTML2

-- ########## DATABASE READ ONLY, STATUS RESTORING OR OFFLINE

IF OBJECT_ID(N'tempdb..##BANCOS_ESTADO') IS NOT NULL
DROP TABLE ##BANCOS_ESTADO

DECLARE @state_desc VARCHAR(64)

SELECT name [Name],
	CASE databasepropertyex(name, 'Updateability')  
		WHEN 'READ_ONLY' THEN 'Yes' 
		ELSE 'No' 
	END AS [Read Only],
	CASE databasepropertyex(name, 'status') 
		WHEN 'RESTORING' THEN 'Yes' 
		ELSE 'No' 
	END AS [Restoring],
	CASE databasepropertyex(name, 'status') 
		WHEN 'OFFLINE' THEN 'Yes' 
		ELSE 'No' 
	END AS [Offline]
	INTO ##BANCOS_ESTADO
FROM master..sysdatabases (NOLOCK)
WHERE name NOT IN ('master','model','tempdb') 
		AND databasepropertyex(name, 'Updateability') = 'READ_ONLY' 
		OR databasepropertyex(name, 'status') = 'RESTORING' 
		OR databasepropertyex(name, 'status') = 'OFFLINE'
		AND cmptlevel <> 65

--Cabecalho
SET @HTML = @HTML +
'<h2>DATABASE READ ONLY, RESTORING OR OFFLINE</h2>'

DECLARE @SQL AS VARCHAR(MAX)
DECLARE SQL_CURSOR CURSOR FOR
	SELECT [name] FROM ##BANCOS_ESTADO
OPEN SQL_CURSOR;
FETCH NEXT FROM SQL_CURSOR INTO @SQL 
IF @@FETCH_STATUS = -1
	BEGIN
		SET @HTML = @HTML +'		
		NO INFORMATION<br/><br/>'		
	END
	ELSE
	BEGIN
		--Tabela
		EXEC master.dbo.spu_Export_Table_HTML_Output
			@Ds_Tabela = '##BANCOS_ESTADO', -- varchar(max)
			@Ds_Saida = @HTML2 OUT, -- varchar(max)
			@Ds_Alinhamento = 'LEFT',
			@Ds_OrderBy = ''
		SET @HTML = @HTML + @HTML2
	END
CLOSE SQL_CURSOR
DEALLOCATE SQL_CURSOR

-- ########## DATABASE RECOVERY MODEL 

IF OBJECT_ID(N'tempdb..##INFORMACOES_RECOVERY_MODEL') IS NOT NULL
DROP TABLE ##INFORMACOES_RECOVERY_MODEL

SELECT Name [Database Name]
	,CAST( databasepropertyex(Name,'RECOVERY') AS VARCHAR(64)) AS [Recovery Model]
	INTO ##INFORMACOES_RECOVERY_MODEL
FROM master.dbo.sysdatabases 
WHERE name NOT IN ('master','msdb','model','tempdb')
ORDER BY 2,1 DESC

--Cabecalho
SET @HTML = @HTML +
'<h2>DATABASE RECOVERY MODEL</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##INFORMACOES_RECOVERY_MODEL', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = '[Recovery Model]'	

SET @HTML = @HTML + @HTML2

-- ########## DATABASES STATUS NOT ONLINE

IF OBJECT_ID(N'tempdb..##DATABASE_STATUS_NOT_ONLINE') IS NOT NULL
	DROP TABLE ##DATABASE_STATUS_NOT_ONLINE

SELECT [name] [Name Database], [state_desc] [State Description]
	INTO ##DATABASE_STATUS_NOT_ONLINE
FROM master.sys.databases	
WHERE state_desc <> 'ONLINE'

--Cabecalho
SET @HTML = @HTML +
'<h2>DATABASES STATUS NOT ONLINE</h2>'

--DECLARE @SQL AS VARCHAR(MAX)
DECLARE SQL_CURSOR CURSOR FOR
	SELECT [Name Database] FROM ##DATABASE_STATUS_NOT_ONLINE
OPEN SQL_CURSOR;
FETCH NEXT FROM SQL_CURSOR INTO @SQL 
IF @@FETCH_STATUS = -1
	BEGIN
		SET @HTML = @HTML +'		
		NO INFORMATION<br/><br/>'		
	END
	ELSE
	BEGIN
		--Tabela
		EXEC master.dbo.spu_Export_Table_HTML_Output
			@Ds_Tabela = '##DATABASE_STATUS_NOT_ONLINE', -- varchar(max)
			@Ds_Saida = @HTML2 OUT, -- varchar(max)
			@Ds_Alinhamento = 'LEFT',
			@Ds_OrderBy = ''	
		SET @HTML = @HTML + @HTML2
	END
CLOSE SQL_CURSOR
DEALLOCATE SQL_CURSOR

-- ########## PERFORMANCE

IF OBJECT_ID(N'tempdb..##CHECK_PERFORMANCE') IS NOT NULL
	DROP TABLE ##CHECK_PERFORMANCE

SELECT cntr_value AS 'Page Life Expectancy'
	, CASE 
		WHEN cntr_value < 10 THEN 'Too low, 14 / 5.000
Resultados de tradução risk of generating erros, asserts e dumps'
		WHEN cntr_value < 300 AND cntr_value >= 10 THEN 'Low'
		WHEN cntr_value < 1000 AND cntr_value >= 300 THEN 'Reasonable'
		WHEN cntr_value < 5000 AND cntr_value >= 1000 THEN 'Fine'
		ELSE 'Great'
	END  AS [Status]
	INTO ##CHECK_PERFORMANCE
FROM sys.dm_os_performance_counters
WHERE counter_name = 'Page life expectancy'
	AND object_name LIKE '%Buffer Manager%'

--Cabecalho
SET @HTML = @HTML +
'<h2>PERFORMANCE</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##CHECK_PERFORMANCE', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = ''	

SET @HTML = @HTML + @HTML2

-- ########## JOBS WITH PROBLEMS

IF OBJECT_ID(N'tempdb..##JOBS_PROBLEMAS') IS NOT NULL
	DROP TABLE ##JOBS_PROBLEMAS

SELECT  DISTINCT(j.[name]) [Job Name]     
	INTO ##JOBS_PROBLEMAS
FROM    msdb.dbo.sysjobhistory h  
        INNER JOIN msdb.dbo.sysjobs j  
        ON h.job_id = j.job_id  
        INNER JOIN msdb.dbo.sysjobsteps s  
        ON j.job_id = s.job_id 
			AND h.step_id = s.step_id  
WHERE    h.run_status = 0 AND h.run_date > CONVERT(int, CONVERT(varchar(10), DATEADD(DAY, -1, GETDATE()), 112))

--Cabecalho
SET @HTML = @HTML +
'<h2>JOBS WITH PROBLEMS</h2>'

DECLARE SQL_CURSOR CURSOR FOR
	SELECT [Job Name] FROM ##JOBS_PROBLEMAS
OPEN SQL_CURSOR;
FETCH NEXT FROM SQL_CURSOR INTO @SQL 
IF @@FETCH_STATUS = -1
	BEGIN
		SET @HTML = @HTML +'		
		NO INFORMATION<br/><br/>'		
	END
	ELSE
	BEGIN
		--Tabela
		EXEC master.dbo.spu_Export_Table_HTML_Output
			@Ds_Tabela = '##JOBS_PROBLEMAS', -- varchar(max)
			@Ds_Saida = @HTML2 OUT, -- varchar(max)
			@Ds_Alinhamento = 'LEFT',
			@Ds_OrderBy = ''	
		SET @HTML = @HTML + @HTML2
	END
CLOSE SQL_CURSOR
DEALLOCATE SQL_CURSOR

-- ########## SQL SERVER OPERATING SYSTEM

IF OBJECT_ID(N'tempdb..##INFORMACAO_CPU') IS NOT NULL
DROP TABLE ##INFORMACAO_CPU

DECLARE @ts_now bigint = (SELECT cpu_ticks/(cpu_ticks/ms_ticks)FROM sys.dm_os_sys_info);  

SELECT TOP(1)  
	[record_id] [Record ID], 
	SQLProcessUtilization AS [SQL Server Process CPU Utilization],  
	SystemIdle AS [System Idle Process],  
	100 - SystemIdle - SQLProcessUtilization AS [Other Process CPU Utilization],  
	DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) AS [Event Time]  
	INTO ##INFORMACAO_CPU
FROM (  
		SELECT record.value('(./Record/@id)[1]', 'int') AS record_id,  
			record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')  AS [SystemIdle],  
			record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]',  'int')  AS [SQLProcessUtilization], [timestamp]  
		FROM 
			(  
				SELECT [timestamp], CONVERT(xml, record) AS [record]  
				FROM sys.dm_os_ring_buffers  
				WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'  
					AND record LIKE '%<SystemHealth>%') AS x  
			) AS y  
ORDER BY [Event Time] DESC;

--Cabecalho
SET @HTML = @HTML +
'<h2>SQL SERVER OPERATING SYSTEM</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##INFORMACAO_CPU', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = ''	

SET @HTML = @HTML + @HTML2

-- ########## MEMORY INFORMATION FROM THE OPERATING SYSTEM

--Consultas de memória

/*Esta consulta nos dá a memória do sistema operacional. 
Em minha máquina, tenho muita memória física disponível, então o resultado diz A memória física disponível está alta. 
Isso é bom para o sistema e nada com que se preocupar.
*/

IF OBJECT_ID(N'tempdb..##INFORMACAO1_MEMORIA') IS NOT NULL
DROP TABLE ##INFORMACAO1_MEMORIA
		
SELECT CAST(total_physical_memory_kb/1024 AS VARCHAR) [Total Physical Memory in MB],
	CAST(available_physical_memory_kb/1024 AS VARCHAR) [Physical Memory Available in MB],
	CAST(system_memory_state_desc AS VARCHAR) [System Memory State Description]
	INTO ##INFORMACAO1_MEMORIA
FROM sys.dm_os_sys_memory;

--Cabecalho
SET @HTML = @HTML +
'<h2>MEMORY - INFORMATION FROM THE OPERATING SYSTEM</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##INFORMACAO1_MEMORIA', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = ''	

SET @HTML = @HTML + @HTML2

-- ########## MEMORY - PROCESS ADDRESS SPACE

/*
Essa consulta nos dá o resultado do processo do SQL Server em execução no sistema operacional e também indica se há um problema de pouca memória ou não. 
No nosso caso, ambos os valores são zero e isso é bom. 
Se algum dos valores BAIXOS for 1, é uma questão de preocupação e deve-se começar a investigar o problema de memória.
*/

IF OBJECT_ID(N'tempdb..##INFORMACAO2_MEMORIA') IS NOT NULL
DROP TABLE ##INFORMACAO2_MEMORIA
		
SELECT physical_memory_in_use_kb/1024 [Physical Memory Used in MB],
	process_physical_memory_low [Physical Memory Low],
	process_virtual_memory_low [Virtual Memory Low]
	INTO ##INFORMACAO2_MEMORIA
FROM sys.dm_os_process_memory;

--Cabecalho
SET @HTML = @HTML +
'<h2>MEMORY - PROCESS ADDRESS SPACE</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##INFORMACAO2_MEMORIA', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = ''	

SET @HTML = @HTML + @HTML2

-- ########## MEMORY - RESOURCES AVAILABLE TO AND CONSUMED BY SQL SERVER

/*Essa consulta nos fornece quanta memória foi comprometida com o SQL Server e qual é a projeção atual para o comprometimento de memória de destino do SQL Server. 
Como a memória comprometida de destino é menor do que a memória disponível para nós, também estamos bem nessa consulta.
*/

IF OBJECT_ID(N'tempdb..##INFORMACAO3_MEMORIA') IS NOT NULL
DROP TABLE ##INFORMACAO3_MEMORIA
		
SELECT committed_kb/1024 [SQL Server Committed Memory in MB],
	committed_target_kb/1024 [SQL Server Target Committed Memory in MB]
	INTO ##INFORMACAO3_MEMORIA
FROM sys.dm_os_sys_info;

--Cabecalho
SET @HTML = @HTML +
'<h2>MEMORY - RESOURCES AVAILABLE TO AND CONSUMED BY SQL SERVER</h2>'

--Tabela
EXEC master.dbo.spu_Export_Table_HTML_Output
    @Ds_Tabela = '##INFORMACAO3_MEMORIA', -- varchar(max)
    @Ds_Saida = @HTML2 OUT, -- varchar(max)
    @Ds_Alinhamento = 'LEFT',
    @Ds_OrderBy = ''	

SET @HTML = @HTML + @HTML2

-- ########## LOCK SQL SERVER

IF OBJECT_ID(N'tempdb..##LOCK') IS NOT NULL
DROP TABLE ##LOCK

CREATE TABLE ##LOCK (
[Session ID] VARCHAR(MAX),
[Lock Request Status] VARCHAR(MAX),
[Login] VARCHAR(MAX),
[Host Name] VARCHAR(MAX),
[BlkBy] VARCHAR(MAX),
[Database Name] VARCHAR(MAX),
Command VARCHAR(MAX),
[Program Name] VARCHAR(MAX),
)

INSERT INTO ##LOCK EXEC sp_quem

--Cabecalho
SET @HTML = @HTML +
'<h2>LOCK</h2>'

DECLARE SQL_CURSOR CURSOR FOR
	SELECT [Session ID] FROM ##LOCK
OPEN SQL_CURSOR;
FETCH NEXT FROM SQL_CURSOR INTO @SQL 
IF @@FETCH_STATUS = -1
	BEGIN
		SET @HTML = @HTML +'		
		NO INFORMATION<br/><br/>'		
	END
	ELSE	
	BEGIN
		--Tabela
		EXEC master.dbo.spu_Export_Table_HTML_Output
			@Ds_Tabela = '##LOCK', -- varchar(max)
			@Ds_Saida = @HTML2 OUT, -- varchar(max)
			@Ds_Alinhamento = 'LEFT',
			@Ds_OrderBy = ''	
		SET @HTML = @HTML + @HTML2
	END
CLOSE SQL_CURSOR
DEALLOCATE SQL_CURSOR

-- ########## LOGSPACE

IF OBJECT_ID(N'tempdb..##LOGSPACE') IS NOT NULL
DROP TABLE ##LOGSPACE

CREATE TABLE ##LOGSPACE (
[Database Name] VARCHAR(MAX),
[Log Size (MB)] VARCHAR(MAX),
[Log Space Used (%)] VARCHAR(MAX),
[Status] VARCHAR(MAX)
)

INSERT INTO ##LOGSPACE EXEC ('DBCC SQLPERF(LOGSPACE)')

--Cabecalho
SET @HTML = @HTML +
'<h2>LOGSPACE</h2>'

DECLARE SQL_CURSOR CURSOR FOR
	SELECT [Database Name] FROM ##LOGSPACE
OPEN SQL_CURSOR;
FETCH NEXT FROM SQL_CURSOR INTO @SQL 
IF @@FETCH_STATUS = -1
	BEGIN
		SET @HTML = @HTML +'		
		NO INFORMATION<br/><br/>'		
	END
	ELSE	
	BEGIN
		--Tabela
		EXEC master.dbo.spu_Export_Table_HTML_Output
			@Ds_Tabela = '##LOGSPACE', -- varchar(max)
			@Ds_Saida = @HTML2 OUT, -- varchar(max)
			@Ds_Alinhamento = 'LEFT',
			@Ds_OrderBy = ''	
		SET @HTML = @HTML + @HTML2
	END
CLOSE SQL_CURSOR
DEALLOCATE SQL_CURSOR

-- ########## ASSINATURA DO EMAIL
SET @HTML = @HTML +'
<br/><br/>
Em caso de dúvidas, favor entrar em contato.<br/><br/>
Atenciosamente,<br/><br/>
Suporte - DBA <br/><br/>
<img src="https://static.wixstatic.com/media/cd93ac_c07e03423d404a24a22c55e7e359b2a9~mv2.png/v1/fill/w_353,h_244,al_c,lg_1,q_85,enc_auto/NOVA%20LOGO.png" height="150" width="216"/></a>
';

-- ########## ENVIAR EMAIL
EXEC msdb.dbo.sp_send_dbmail
	@profile_name = 'DBA',
	@recipients = @recipient,
	@subject = @subjec,
	@body = @HTML, 
    @body_format = 'html',
	@query_result_width = 20000,
	@query_result_header = 1, 
	@query_no_truncate = 1,
	@query_result_no_padding = 0;
END
GO

/****** Object:  StoredProcedure [dbo].[spu_Kill_Users]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER OFF
GO






create procedure [dbo].[spu_Kill_Users] (@DBName varchar(30)) as  
--   
Declare @LoginName   varchar(30)  
Declare @QualDB      varchar(30)  
Declare @NumSPID     integer  
Declare @UndoFile    varchar(60)  
Declare @DeviceName  varchar(70)  
Declare @Comando     varchar(30)  
--   
Declare UsuariosAtivos Cursor For  
  select sysp.spid, sysp.loginame  
    from master..sysprocesses sysp (nolock),  
         master..sysdatabases sysdb (nolock)  
   where sysp.dbid = sysdb.dbid  
     and name = @DBName  
--  
Open UsuariosAtivos  
--  
Fetch Next from UsuariosAtivos Into @NumSPID, @LoginName  
While @@FETCH_STATUS = 0  
  Begin  
    if (Upper(@LoginName) <> 'SA') OR (Upper(@LoginName) <> 'CPD\SICLASQLSERVICE')  
      Begin  
       set @Comando = 'Kill ' + convert(varchar(4),@NumSPID) + ' -- Usu�rio: ' + @LoginName  
       print @Comando  
       set @Comando = 'Kill ' + convert(varchar(4),@NumSPID)  
       execute ( @Comando )  
      End  
    Fetch Next From UsuariosAtivos Into @NumSPID, @LoginName  
  End  
--  
Close UsuariosAtivos  
Deallocate UsuariosAtivos  
return  
GO

/****** Object:  StoredProcedure [dbo].[spu_otimizacao_necessaria]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


 CREATE procedure [dbo].[spu_otimizacao_necessaria] as    
print char(13)+'OTIMIZANDO O BANCO '+db_name()+' '+char(13)+char(13)    
set nocount on    
declare @tablename varchar (128)    
declare @TABLE_SCHEMA varchar (128)   
declare @execstr   varchar (255)    
declare @ObjectId  int    
declare @indexid   int    
declare @frag      decimal    
declare @maxfrag   decimal    
declare @mindens  decimal    
declare @dens   decimal    
declare @nome_indice varchar(3000)  
select @maxfrag = 10    
select @mindens = 70    
  
declare tables cursor for    
   select TABLE_NAME,TABLE_SCHEMA  from INFORMATION_SCHEMA.TABLES (nolock)  where TABLE_TYPE = 'BASE TABLE' order by TABLE_NAME    
create table #tabela_framentacao_acima_10_densidade_abaixo_70 (    
   ObjectName CHAR (255),    
   ObjectId INT,    
   IndexName CHAR (255),    
   IndexId INT,    
   Lvl INT,    
   CountPages INT,    
   CountRows INT,    
   MinRecSize INT,    
   MaxRecSize INT,    
   AvgRecSize INT,    
   ForRecCount INT,    
   Extents INT,    
   ExtentSwitches INT,    
   AvgFreeBytes INT,    
   AvgPageDensity INT,    
   ScanDensity DECIMAL,    
   BestCount INT,    
   ActualCount INT,    
   LogicalFrag DECIMAL,    
   ExtentFrag DECIMAL)    
create table #resultado_frag_lista_de_comandos_para_otimizacao (des_comando varchar(8000))    
open tables    
fetch next from tables into @tablename,@TABLE_SCHEMA    
while @@fetch_status = 0    
begin    
   insert into #tabela_framentacao_acima_10_densidade_abaixo_70 exec ('dbcc showcontig (''' + @TABLE_SCHEMA + '.' + @tablename + ''')  with fast, tableresults, all_indexes, no_infomsgs')    
   fetch next from tables into @tablename,@TABLE_SCHEMA    
end  
close tables    
deallocate tables  
declare indexes cursor for    
   select ObjectName,table_schema, ObjectId, IndexId, LogicalFrag, ScanDensity from #tabela_framentacao_acima_10_densidade_abaixo_70 tbl_frg, INFORMATION_SCHEMA.TABLES tbl (nolock)    
   where (LogicalFrag >= @maxfrag or ScanDensity < @mindens)  and indexproperty (ObjectId, IndexName, 'INDEXDEPTH') > 0 and tbl_frg.ObjectName COLLATE DATABASE_DEFAULT = tbl.table_name COLLATE DATABASE_DEFAULT and tbl.TABLE_TYPE = 'BASE TABLE'
 COLLATE DATABASE_DEFAULT   
open indexes    
fetch next from indexes into @tablename, @TABLE_SCHEMA,@ObjectId, @indexid, @frag, @dens    
while @@fetch_status = 0    
begin    
 select @nome_indice = (select name from sysindexes (nolock) where id=@ObjectId and indid = @indexid)    
insert into #resultado_frag_lista_de_comandos_para_otimizacao   select 'dbcc dbreindex (['+@TABLE_SCHEMA + '.'+rtrim(@tablename) + '],[' + rtrim(@nome_indice) + '])  -- fragmentation currently '       + rtrim(convert(varchar(15),@frag)) + '%' + '    -- density '+ rtrim(convert(varchar(15),@dens))+'%' + char(13) +  'dbcc updateusage (['+db_name()+'],'+ '['+ @TABLE_SCHEMA + '.' + rtrim(@tablename) + '],[' + rtrim(@nome_indice) + '])' + char(13) + 'update statistics [' + @TABLE_SCHEMA + '].' + '['+ rtrim(@tablename) + '] [' + rtrim(@nome_indice) + '] with fullscan' + char(13)+ ';'  
   fetch next from indexes into @tablename, @TABLE_SCHEMA,@ObjectId, @indexid, @frag, @dens    
end    
close indexes    
deallocate indexes  
insert into #resultado_frag_lista_de_comandos_para_otimizacao     
select distinct 'exec sp_recompile [' + TABLE_SCHEMA COLLATE DATABASE_DEFAULT + '.' + rtrim (ObjectName) COLLATE DATABASE_DEFAULT + ']' resultado_frag from #tabela_framentacao_acima_10_densidade_abaixo_70  tbl_frg, INFORMATION_SCHEMA.TABLES tbl (nolock) where (LogicalFrag >= @maxfrag or ScanDensity < @mindens)  and indexproperty (ObjectId, IndexName, 'indexdepth') > 0 and tbl_frg.ObjectName COLLATE DATABASE_DEFAULT = tbl.table_name COLLATE DATABASE_DEFAULT and tbl.TABLE_TYPE = 'BASE TABLE'  COLLATE DATABASE_DEFAULT  
DECLARE @comando varchar(8000)    
DECLARE @comando_header varchar(8000)    
DECLARE tnames_cursor CURSOR FOR     
select ltrim (des_comando) resultado_frag from #resultado_frag_lista_de_comandos_para_otimizacao order by des_comando    
OPEN tnames_cursor    
FETCH NEXT FROM tnames_cursor INTO @comando    
WHILE (@@fetch_status <> -1)    
BEGIN    
 IF (@@fetch_status <> -2)    
 BEGIN  SET @comando_header = RTRIM(UPPER(@comando))    
  PRINT @comando_header    
         EXEC (@comando)    
 END    
 FETCH NEXT FROM tnames_cursor INTO @comando    
END    
SELECT @comando_header = '*NO MORE TABLES' + '  *'  
PRINT @comando_header    
PRINT 'Statistics have been updated for all tables.'+char(13)    
DEALLOCATE tnames_cursor  
drop table #tabela_framentacao_acima_10_densidade_abaixo_70    
drop table #resultado_frag_lista_de_comandos_para_otimizacao
GO

/****** Object:  StoredProcedure [dbo].[spu_otimizacao_necessaria_todos_bancos]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


create proc [dbo].[spu_otimizacao_necessaria_todos_bancos] as    
    
/*  This procedure will check all users databases    */    
--use master    
DECLARE @DatabaseName varchar(200)        
DECLARE @Mensagem varchar(300)        
DECLARE @CmdLine varchar(250)    
--    
DECLARE DBNames_cursor CURSOR FOR     
        select name from master..sysdatabases (nolock) where name not in ('master','model','tempdb') 
		and databasepropertyex(name, 'Updateability') <> 'READ_ONLY'  and cmptlevel <> 65		
		Order by Name --Exclui bancos de sistemas, banco em Read-Only e bancos 6.5
OPEN DBNames_cursor    
FETCH NEXT FROM DBNames_cursor INTO @DatabaseName    
WHILE (@@fetch_status <> -1)    
  BEGIN    
    IF (@@fetch_status <> -2)    
      BEGIN    
 Select @Mensagem = 'Verificando o Banco ' + RTRIM(UPPER(@DatabaseName))    
 PRINT @Mensagem    
        Select @CmdLine = 'exec [' + @DatabaseName + '].dbo.spu_otimizacao_necessaria'    
 print @cmdline    
        EXEC (@CmdLine)    
      END    
    FETCH NEXT FROM DBNames_cursor INTO @DatabaseName    
  END    
PRINT ' '    
PRINT ' '    
SELECT @Mensagem = '*************  NO MORE DATABASES *************'    
PRINT @Mensagem    
    
PRINT ' '    
PRINT 'Todos bancos de dados foram reorganizados'
DEALLOCATE DBNames_cursor    

GO

/****** Object:  StoredProcedure [dbo].[spu_prepara_otimizacao_necessaria]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE proc [dbo].[spu_prepara_otimizacao_necessaria] as 
declare
       @isql varchar(MAX),
       @dbname varchar(MAX),
       @logfile varchar(MAX)
       
       declare c1 cursor for 
       SELECT  d.name from  sys.databases d
       where recovery_model_desc <> 'SIMPLE'   
       open c1
       fetch next from c1 into @dbname
       While @@fetch_status <> -1
             begin
             select @isql = 'ALTER DATABASE [' + @dbname + '] SET RECOVERY BULK_LOGGED'
             print @isql
             exec(@isql)
             --select @isql='USE ' + @dbname + ' checkpoint'
             --print @isql
             --exec(@isql)
             --select @isql='USE ' + @dbname + ' DBCC SHRINKFILE (' + @logfile + ', 1)'
             --print @isql
             --exec(@isql)
             
             fetch next from c1 into @dbname
             end
       close c1
       deallocate c1

GO

/****** Object:  StoredProcedure [dbo].[spu_Rebuild_Index_All_Databases]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[spu_Rebuild_Index_All_Databases] (
  @fillfactor tinyint = null
)
AS

Set Nocount on
Declare db Cursor For	
		Select name from master.dbo.sysdatabases
		Where name not in ('master','TempDB')
Declare @dbname varchar(100)
Declare @dbre varchar(1000)
DECLARE @execstr nvarchar(255)
Open db
Fetch Next from db into @dbname
While @@Fetch_status=0
   begin
	if @dbname is null 
	  Begin
   	    Print 'null Value'
	  end
	else 
	  Begin
	    PRINT '*************************************************************************** '
            PRINT 'Reindexing All Tables in ' +@dbname
  	    IF @fillfactor IS NULL
                SELECT @execstr = 'EXEC ' + @dbname + '..sp_MSforeachtable @command1="print ''?'' DBCC DBREINDEX (''?'')"'
            ELSE
                SELECT @execstr = 'EXEC ' + @dbname + '..sp_MSforeachtable @command1="print ''?'' DBCC DBREINDEX (''?'','''',' + str(@fillfactor) + ')"'
            EXEC(@execstr)
	    PRINT ''
          End
     Fetch Next from db into @dbname	
   end
Close db
Deallocate db

GO

/****** Object:  StoredProcedure [dbo].[spu_shrinkfile_all_logs]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


create procedure [dbo].[spu_shrinkfile_all_logs] as

EXEC sp_MSforeachdb '
DECLARE @sqlcommand nvarchar (500)
IF ''?'' NOT IN (''master'', ''model'', ''msdb'')
BEGIN
USE [?]
SELECT @sqlcommand = ''DBCC SHRINKFILE (N'''''' + 
name
FROM [sys].[database_files]
WHERE type_desc = ''LOG''
SELECT @sqlcommand = @sqlcommand + '''''' , 0)''
EXEC sp_executesql @sqlcommand
END'


GO

/****** Object:  StoredProcedure [dbo].[spu_updatestats_fullscan]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE procedure [dbo].[spu_updatestats_fullscan] as

DECLARE updatestats CURSOR FOR
SELECT table_name FROM INFORMATION_SCHEMA.TABLES
	where TABLE_TYPE = 'BASE TABLE' and TABLE_SCHEMA = 'dbo' 
OPEN updatestats

DECLARE @tablename NVARCHAR(128)
DECLARE @Statement NVARCHAR(300)

FETCH NEXT FROM updatestats INTO @tablename
WHILE (@@FETCH_STATUS = 0)
BEGIN
   PRINT N'UPDATING STATISTICS ' + @tablename
   SET @Statement = 'UPDATE STATISTICS ['  + @tablename + ']  WITH FULLSCAN'
   EXEC sp_executesql @Statement
   FETCH NEXT FROM updatestats INTO @tablename
END
-- Fechando Cursor para leitura
CLOSE updatestats
 
-- Finalizado o cursor
DEALLOCATE updatestats
GO

/****** Object:  StoredProcedure [dbo].[spu_updatestats_fullscan_1]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




create      procedure [dbo].[spu_updatestats_fullscan_1] as
Set Nocount on
DECLARE @comando varchar(1000)
Declare db Cursor For	
		Select name from master.dbo.sysdatabases
		Where name not in ('master','TempDB')
Declare @dbname varchar(100)
Declare @dbre varchar(1000)
DECLARE @execstr nvarchar(255)
Open db
Fetch Next from db into @dbname
While @@Fetch_status=0
   begin	
		DECLARE updatestats CURSOR FOR
		SELECT table_name FROM information_schema.tables
			where TABLE_TYPE = 'BASE TABLE'
		OPEN updatestats

		DECLARE @tablename NVARCHAR(128)
		DECLARE @Statement NVARCHAR(300)
		SET @comando = 'USE ' + @dbname
		PRINT 'USE ' + @dbname
		 EXEC(@comando)
		  

		FETCH NEXT FROM updatestats INTO @tablename
		WHILE (@@FETCH_STATUS = 0)
		BEGIN
		   		   
		   SET @Statement = 'UPDATE STATISTICS '  + @tablename + '  WITH FULLSCAN'
		   if @tablename <> 'Solucionare29112022 Tarde'
		   begin
		   PRINT N'UPDATING STATISTICS ' + @tablename
		   EXEC sp_executesql @Statement
		   end
		   FETCH NEXT FROM updatestats INTO @tablename
		END
		Close updatestats
		Deallocate updatestats 
		Fetch Next from db into @dbname	
	 End
Close db
Deallocate db




GO

/****** Object:  StoredProcedure [dbo].[spu_updatestats_fullscan_2]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




create      procedure [dbo].[spu_updatestats_fullscan_2] as
Set Nocount on
DECLARE @comando varchar(1000)
Declare db Cursor For	
		Select name from master.dbo.sysdatabases
		Where name not in ('master','TempDB')
Declare @dbname varchar(100)
Declare @dbre varchar(1000)
DECLARE @execstr nvarchar(255)
Open db
Fetch Next from db into @dbname
While @@Fetch_status=0
   begin	
		DECLARE updatestats CURSOR FOR
		SELECT table_name FROM information_schema.tables
			where TABLE_TYPE = 'BASE TABLE'
		OPEN updatestats

		DECLARE @tablename NVARCHAR(128)
		DECLARE @Statement NVARCHAR(300)
		SET @comando = 'USE ' + @dbname
		PRINT 'USE ' + @dbname
		EXEC(@comando)
		  

		FETCH NEXT FROM updatestats INTO @tablename
		WHILE (@@FETCH_STATUS = 0)
		BEGIN
		   		   
		   SET @Statement = 'UPDATE STATISTICS '  + @tablename + '  WITH FULLSCAN'
		   if @tablename <> 'Solucionare29112022 Tarde'
		   begin
		   PRINT N'UPDATING STATISTICS ' + @tablename
		   EXEC sp_executesql @Statement
		   end
		   FETCH NEXT FROM updatestats INTO @tablename
		END
		Close updatestats
		Deallocate updatestats 
		Fetch Next from db into @dbname	
	 End
Close db
Deallocate db




GO

/****** Object:  StoredProcedure [dbo].[spu_updatestats_fullscan_3]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




create      procedure [dbo].[spu_updatestats_fullscan_3] as
Set Nocount on
DECLARE @comando varchar(1000)
Declare db Cursor For	
		Select name from master.dbo.sysdatabases
		Where name not in ('master','TempDB')
Declare @dbname varchar(100)
Declare @dbre varchar(1000)
DECLARE @execstr nvarchar(255)
Open db
Fetch Next from db into @dbname
While @@Fetch_status=0
   begin	
		DECLARE updatestats CURSOR FOR
		SELECT table_name FROM information_schema.tables
			where TABLE_TYPE = 'BASE TABLE'
		OPEN updatestats

		DECLARE @tablename NVARCHAR(128)
		DECLARE @Statement NVARCHAR(300)
		SET @comando = 'USE ' + @dbname
		PRINT 'USE ' + @dbname
		EXEC(@comando)
		  

		FETCH NEXT FROM updatestats INTO @tablename
		WHILE (@@FETCH_STATUS = 0)
		BEGIN
		   		   
		   SET @Statement = 'UPDATE STATISTICS '  + @tablename + '  WITH FULLSCAN'
		   if @tablename <> 'Solucionare29112022 Tarde'
		   begin
		   PRINT N'UPDATING STATISTICS ' + @tablename
		   EXEC sp_executesql @Statement
		   end
		   FETCH NEXT FROM updatestats INTO @tablename
		END
		Close updatestats
		Deallocate updatestats 
		Fetch Next from db into @dbname	
	 End
Close db
Deallocate db




GO

/****** Object:  StoredProcedure [dbo].[spu_updatestats_fullscan_versao2]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE      procedure [dbo].[spu_updatestats_fullscan_versao2] as
Set Nocount on
DECLARE @comando varchar(1000)
Declare db Cursor For	
		Select name from sys.databases
		Where name not in ('master','TempDB')
Declare @dbname varchar(100)
Declare @dbre varchar(1000)
DECLARE @execstr nvarchar(255)
Open db
Fetch Next from db into @dbname
While @@Fetch_status=0
   begin	
		SET @comando = 'USE ' + @dbname
		EXEC (@comando)
		PRINT 'USE ' + @dbname
		EXEC sp_updatestats 
		Fetch Next from db into @dbname
	End
Close db
Deallocate db
GO

/****** Object:  StoredProcedure [dbo].[spu_verifica_todos_bancos_gerenciabd]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE procedure [dbo].[spu_verifica_todos_bancos_gerenciabd] as

/* 	This procedure will check all users databases    */
--use master
DECLARE @DatabaseName varchar(130)
DECLARE @Mensagem varchar(175)
DECLARE @CmdLine varchar(1250)
--
DECLARE DBNames_cursor CURSOR FOR 
        SELECT name FROM master..sysdatabases (nolock) where name not in ('tempdb', 'Northwind', 'pubs')
OPEN DBNames_cursor
FETCH NEXT FROM DBNames_cursor INTO @DatabaseName
WHILE (@@fetch_status <> -1)
  BEGIN
    IF (@@fetch_status <> -2)
      BEGIN
	Select @Mensagem = 'Verificando o Banco [' + RTRIM(UPPER(@DatabaseName)) + ']'
	PRINT @Mensagem
        Select @CmdLine = 'dbcc checkdb ([' + @DatabaseName + ']) with NO_INFOMSGS'
 --print @cmdline
        EXEC (@CmdLine)
      END
    FETCH NEXT FROM DBNames_cursor INTO @DatabaseName
  END
PRINT ' '
PRINT ' '
SELECT @Mensagem = '*************  NO MORE DATABASES *************'
PRINT @Mensagem

PRINT ' '
--PRINT 'All users databases were backed up'
DEALLOCATE DBNames_cursor

GO

/****** Object:  StoredProcedure [dbo].[usp_whatsup]    Script Date: 05/12/2022 10:20:29 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



-- Replace CREATE PROCEDURE with ALTER PROCEDURE or CREATE OR ALTER PROCEDURE to allow new changes to the SP if the SP is already present.

CREATE PROCEDURE [dbo].[usp_whatsup] @sqluptime bit = 1, @requests bit = 1, @blocking bit = 1, @spstats bit = 0, @qrystats bit = 0, @trstats bit = 0, @fnstats bit = 0, @top smallint = 100
AS

-- Returns running sessions/requests; blocking information; sessions that have been granted locks or waiting for locks; and optionally top SP/Query/Trigger/Function execution stats.

SET NOCOUNT ON;

DECLARE @sqlmajorver int, @sqlbuild int, @sqlcmd VARCHAR(8000), @sqlcmdup NVARCHAR(500), @params NVARCHAR(500)
SELECT @sqlmajorver = CONVERT(int, (@@microsoftversion / 0x1000000) & 0xff);
SELECT @sqlbuild = CONVERT(int, @@microsoftversion & 0xffff);

IF @sqluptime = 1
BEGIN
	DECLARE @UpTime VARCHAR(12), @StartDate DATETIME

	IF @sqlmajorver = 9
	BEGIN
		SET @sqlcmdup = N'SELECT @StartDateOUT = login_time, @UpTimeOUT = DATEDIFF(mi, login_time, GETDATE()) FROM master..sysprocesses WHERE spid = 1';
	END
	ELSE
	BEGIN
		SET @sqlcmdup = N'SELECT @StartDateOUT = sqlserver_start_time, @UpTimeOUT = DATEDIFF(mi,sqlserver_start_time,GETDATE()) FROM sys.dm_os_sys_info';
	END

	SET @params = N'@StartDateOUT DATETIME OUTPUT, @UpTimeOUT VARCHAR(12) OUTPUT';

	EXECUTE sp_executesql @sqlcmdup, @params, @StartDateOUT=@StartDate OUTPUT, @UpTimeOUT=@UpTime OUTPUT;

	SELECT 'Uptime_Information' AS [Information], GETDATE() AS [Current_Time], @StartDate AS Last_Startup, CONVERT(VARCHAR(4),@UpTime/60/24) + 'd ' + CONVERT(VARCHAR(4),@UpTime/60%24) + 'h ' + CONVERT(VARCHAR(4),@UpTime%60) + 'm' AS Uptime

END;

-- Running Sessions/Requests Report
IF @requests = 1
BEGIN
	IF @sqlmajorver = 9
	BEGIN
		SELECT @sqlcmd = N'SELECT ''Requests'' AS [Information], es.session_id, DB_NAME(er.database_id) AS [database_name], OBJECT_NAME(qp.objectid, qp.dbid) AS [object_name], -- NULL if Ad-Hoc or Prepared statements
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt
		FOR XML PATH(''''), TYPE) AS [running_batch],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		SUBSTRING(qt2.text,
		1+(CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END),
		1+(CASE WHEN er.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er.statement_end_offset/2 END - (CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END))),
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt2
		FOR XML PATH(''''), TYPE) AS [running_statement],
	--ot.task_state AS [status],
	er.status,
	--er.command,
	qp.query_plan,
	er.percent_complete,
	CONVERT(VARCHAR(20),DATEADD(ms,er.estimated_completion_time,GETDATE()),20) AS [ETA_completion_time],
	(er.cpu_time/1000) AS cpu_time_sec,
	(er.reads*8)/1024 AS physical_reads_KB,
	(er.logical_reads*8)/1024 AS logical_reads_KB,
	(er.writes*8)/1024 AS writes_KB,
	(er.total_elapsed_time/1000)/60 AS elapsed_minutes,
	er.wait_type,
	er.wait_resource,
	er.last_wait_type,
	(SELECT CASE
		WHEN pageid = 1 OR pageid % 8088 = 0 THEN ''Is_PFS_Page''
		WHEN pageid = 2 OR pageid % 511232 = 0 THEN ''Is_GAM_Page''
		WHEN pageid = 3 OR (pageid - 1) % 511232 = 0 THEN ''Is_SGAM_Page''
		WHEN pageid IS NULL THEN NULL
		ELSE ''Is_not_PFS_GAM_SGAM_page'' END
	FROM (SELECT CASE WHEN er.[wait_type] LIKE ''PAGE%LATCH%'' AND er.[wait_resource] LIKE ''%:%''
		THEN CAST(RIGHT(er.[wait_resource], LEN(er.[wait_resource]) - CHARINDEX('':'', er.[wait_resource], LEN(er.[wait_resource])-CHARINDEX('':'', REVERSE(er.[wait_resource])))) AS int)
		ELSE NULL END AS pageid) AS latch_pageid
	) AS wait_resource_type,
	er.wait_time AS wait_time_ms,
	er.cpu_time AS cpu_time_ms,
	er.open_transaction_count,
	DATEADD(s, (er.estimated_completion_time/1000), GETDATE()) AS estimated_completion_time,
	LEFT (CASE COALESCE(er.transaction_isolation_level, es.transaction_isolation_level)
		WHEN 0 THEN ''0-Unspecified''
		WHEN 1 THEN ''1-ReadUncommitted''
		WHEN 2 THEN ''2-ReadCommitted''
		WHEN 3 THEN ''3-RepeatableRead''
		WHEN 4 THEN ''4-Serializable''
		WHEN 5 THEN ''5-Snapshot''
		ELSE CONVERT (VARCHAR(30), er.transaction_isolation_level) + ''-UNKNOWN''
    END, 30) AS transaction_isolation_level,
	mg.requested_memory_kb,
	mg.granted_memory_kb,
	--mg.ideal_memory_kb,
	mg.query_cost,
	es.[host_name],
	es.login_name,
	--es.original_login_name,
	es.[program_name],
	--ec.client_net_address,
	es.is_user_process
FROM sys.dm_exec_requests (NOLOCK) er
	LEFT OUTER JOIN sys.dm_exec_query_memory_grants (NOLOCK) mg ON er.session_id = mg.session_id AND er.request_id = mg.request_id
	LEFT OUTER JOIN sys.dm_db_session_space_usage (NOLOCK) ssu ON er.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_exec_sessions (NOLOCK) es ON er.session_id = es.session_id
	OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) qp
WHERE er.session_id <> @@SPID AND es.is_user_process = 1
ORDER BY er.total_elapsed_time DESC, er.logical_reads DESC, [database_name], session_id'
	END
	ELSE IF @sqlmajorver IN (10,11,12) OR (@sqlmajorver = 13 AND @sqlbuild < 4000)
	BEGIN
		SET @sqlcmd = N';WITH tsu AS (SELECT session_id, SUM(user_objects_alloc_page_count) AS user_objects_alloc_page_count, 
SUM(user_objects_dealloc_page_count) AS user_objects_dealloc_page_count, 
SUM(internal_objects_alloc_page_count) AS internal_objects_alloc_page_count, 
SUM(internal_objects_dealloc_page_count) AS internal_objects_dealloc_page_count FROM sys.dm_db_task_space_usage (NOLOCK) GROUP BY session_id)
SELECT ''Requests'' AS [Information], es.session_id, DB_NAME(er.database_id) AS [database_name], OBJECT_NAME(qp.objectid, qp.dbid) AS [object_name],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt
		FOR XML PATH(''''), TYPE) AS [running_batch],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		SUBSTRING(qt2.text,
		1+(CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END),
		1+(CASE WHEN er.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er.statement_end_offset/2 END - (CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END))),
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt2
		FOR XML PATH(''''), TYPE) AS [running_statement],
	er.status,
	er.command,
	qp.query_plan,
	er.percent_complete,
	CONVERT(VARCHAR(20),DATEADD(ms,er.estimated_completion_time,GETDATE()),20) AS [ETA_completion_time],
	(er.cpu_time/1000) AS cpu_time_sec,
	(er.reads*8)/1024 AS physical_reads_KB,
	(er.logical_reads*8)/1024 AS logical_reads_KB,
	(er.writes*8)/1024 AS writes_KB,
	(er.total_elapsed_time/1000)/60 AS elapsed_minutes,
	er.wait_type,
	er.wait_resource,
	er.last_wait_type,
	(SELECT CASE
		WHEN pageid = 1 OR pageid % 8088 = 0 THEN ''Is_PFS_Page''
		WHEN pageid = 2 OR pageid % 511232 = 0 THEN ''Is_GAM_Page''
		WHEN pageid = 3 OR (pageid - 1) % 511232 = 0 THEN ''Is_SGAM_Page''
		WHEN pageid IS NULL THEN NULL
		ELSE ''Is_not_PFS_GAM_SGAM_page'' END
	FROM (SELECT CASE WHEN er.[wait_type] LIKE ''PAGE%LATCH%'' AND er.[wait_resource] LIKE ''%:%''
		THEN CAST(RIGHT(er.[wait_resource], LEN(er.[wait_resource]) - CHARINDEX('':'', er.[wait_resource], LEN(er.[wait_resource])-CHARINDEX('':'', REVERSE(er.[wait_resource])))) AS int)
		ELSE NULL END AS pageid) AS latch_pageid
	) AS wait_resource_type,
	er.wait_time AS wait_time_ms,
	er.cpu_time AS cpu_time_ms,
	er.open_transaction_count,
	DATEADD(s, (er.estimated_completion_time/1000), GETDATE()) AS estimated_completion_time,
	CASE WHEN mg.wait_time_ms IS NULL THEN DATEDIFF(ms, mg.request_time, mg.grant_time) ELSE mg.wait_time_ms END AS [grant_wait_time_ms],
	LEFT (CASE COALESCE(er.transaction_isolation_level, es.transaction_isolation_level)
		WHEN 0 THEN ''0-Unspecified''
		WHEN 1 THEN ''1-ReadUncommitted''
		WHEN 2 THEN ''2-ReadCommitted''
		WHEN 3 THEN ''3-RepeatableRead''
		WHEN 4 THEN ''4-Serializable''
		WHEN 5 THEN ''5-Snapshot''
		ELSE CONVERT (VARCHAR(30), er.transaction_isolation_level) + ''-UNKNOWN''
    END, 30) AS transaction_isolation_level,
	mg.requested_memory_kb,
	mg.granted_memory_kb,
	mg.ideal_memory_kb,
	mg.query_cost,
	((((ssu.user_objects_alloc_page_count + tsu.user_objects_alloc_page_count) -
		(ssu.user_objects_dealloc_page_count + tsu.user_objects_dealloc_page_count))*8)/1024) AS user_obj_in_tempdb_MB,
	((((ssu.internal_objects_alloc_page_count + tsu.internal_objects_alloc_page_count) -
		(ssu.internal_objects_dealloc_page_count + tsu.internal_objects_dealloc_page_count))*8)/1024) AS internal_obj_in_tempdb_MB,
	es.[host_name],
	es.login_name,
	--es.original_login_name,
	es.[program_name],
	--ec.client_net_address,
	es.is_user_process,
	g.name AS workload_group
FROM sys.dm_exec_requests (NOLOCK) er
	LEFT OUTER JOIN sys.dm_exec_query_memory_grants (NOLOCK) mg ON er.session_id = mg.session_id AND er.request_id = mg.request_id
	LEFT OUTER JOIN sys.dm_db_session_space_usage (NOLOCK) ssu ON er.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_exec_sessions (NOLOCK) es ON er.session_id = es.session_id
	LEFT OUTER JOIN tsu ON tsu.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_resource_governor_workload_groups (NOLOCK) g ON es.group_id = g.group_id
	OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) qp
WHERE er.session_id <> @@SPID AND es.is_user_process = 1
ORDER BY er.total_elapsed_time DESC, er.logical_reads DESC, [database_name], session_id'
	END
	ELSE IF (@sqlmajorver = 13 AND @sqlbuild > 4000) OR @sqlmajorver = 14 OR (@sqlmajorver = 15 AND @sqlbuild < 1400)
	BEGIN
		SELECT @sqlcmd = N'WITH tsu AS (SELECT session_id, SUM(user_objects_alloc_page_count) AS user_objects_alloc_page_count, 
SUM(user_objects_dealloc_page_count) AS user_objects_dealloc_page_count, 
SUM(internal_objects_alloc_page_count) AS internal_objects_alloc_page_count, 
SUM(internal_objects_dealloc_page_count) AS internal_objects_dealloc_page_count FROM sys.dm_db_task_space_usage (NOLOCK) GROUP BY session_id)
SELECT ''Requests'' AS [Information], es.session_id, DB_NAME(er.database_id) AS [database_name], OBJECT_NAME(qp.objectid, qp.dbid) AS [object_name],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt
		FOR XML PATH(''''), TYPE) AS [running_batch],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		SUBSTRING(qt2.text,
		1+(CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END),
		1+(CASE WHEN er.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er.statement_end_offset/2 END - (CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END))),
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt2
		FOR XML PATH(''''), TYPE) AS [running_statement],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		ib.event_info,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_input_buffer(er.session_id, er.request_id) AS ib
		FOR XML PATH(''''), TYPE) AS [input_buffer],
	er.status,
	er.command,
	qp.query_plan,
	CASE WHEN qes.query_plan IS NULL THEN ''Lightweight Query Profiling Infrastructure is not enabled'' ELSE qes.query_plan END AS [live_query_plan_snapshot],
	er.percent_complete,
	CONVERT(VARCHAR(20),DATEADD(ms,er.estimated_completion_time,GETDATE()),20) AS [ETA_completion_time],
	(er.cpu_time/1000) AS cpu_time_sec,
	(er.reads*8)/1024 AS physical_reads_KB,
	(er.logical_reads*8)/1024 AS logical_reads_KB,
	(er.writes*8)/1024 AS writes_KB,
	(er.total_elapsed_time/1000)/60 AS elapsed_minutes,
	er.wait_type,
	er.wait_resource,
	er.last_wait_type,
	(SELECT CASE
		WHEN pageid = 1 OR pageid % 8088 = 0 THEN ''Is_PFS_Page''
		WHEN pageid = 2 OR pageid % 511232 = 0 THEN ''Is_GAM_Page''
		WHEN pageid = 3 OR (pageid - 1) % 511232 = 0 THEN ''Is_SGAM_Page''
		WHEN pageid IS NULL THEN NULL
		ELSE ''Is_not_PFS_GAM_SGAM_page'' END
	FROM (SELECT CASE WHEN er.[wait_type] LIKE ''PAGE%LATCH%'' AND er.[wait_resource] LIKE ''%:%''
		THEN CAST(RIGHT(er.[wait_resource], LEN(er.[wait_resource]) - CHARINDEX('':'', er.[wait_resource], LEN(er.[wait_resource])-CHARINDEX('':'', REVERSE(er.[wait_resource])))) AS int)
		ELSE NULL END AS pageid) AS latch_pageid
	) AS wait_resource_type,
	er.wait_time AS wait_time_ms,
	er.cpu_time AS cpu_time_ms,
	er.open_transaction_count,
	DATEADD(s, (er.estimated_completion_time/1000), GETDATE()) AS estimated_completion_time,
	CASE WHEN mg.wait_time_ms IS NULL THEN DATEDIFF(ms, mg.request_time, mg.grant_time) ELSE mg.wait_time_ms END AS [grant_wait_time_ms],
	LEFT (CASE COALESCE(er.transaction_isolation_level, es.transaction_isolation_level)
		WHEN 0 THEN ''0-Unspecified''
		WHEN 1 THEN ''1-ReadUncommitted''
		WHEN 2 THEN ''2-ReadCommitted''
		WHEN 3 THEN ''3-RepeatableRead''
		WHEN 4 THEN ''4-Serializable''
		WHEN 5 THEN ''5-Snapshot''
		ELSE CONVERT (VARCHAR(30), er.transaction_isolation_level) + ''-UNKNOWN''
    END, 30) AS transaction_isolation_level,
	mg.requested_memory_kb,
	mg.granted_memory_kb,
	mg.ideal_memory_kb,
	mg.query_cost,
	((((ssu.user_objects_alloc_page_count + tsu.user_objects_alloc_page_count) -
		(ssu.user_objects_dealloc_page_count + tsu.user_objects_dealloc_page_count))*8)/1024) AS user_obj_in_tempdb_MB,
	((((ssu.internal_objects_alloc_page_count + tsu.internal_objects_alloc_page_count) -
		(ssu.internal_objects_dealloc_page_count + tsu.internal_objects_dealloc_page_count))*8)/1024) AS internal_obj_in_tempdb_MB,
	es.[host_name],
	es.login_name,
	--es.original_login_name,
	es.[program_name],
	--ec.client_net_address,
	es.is_user_process,
	g.name AS workload_group
FROM sys.dm_exec_requests (NOLOCK) er
	LEFT OUTER JOIN sys.dm_exec_query_memory_grants (NOLOCK) mg ON er.session_id = mg.session_id AND er.request_id = mg.request_id
	LEFT OUTER JOIN sys.dm_db_session_space_usage (NOLOCK) ssu ON er.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_exec_sessions (NOLOCK) es ON er.session_id = es.session_id
	LEFT OUTER JOIN tsu ON tsu.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_resource_governor_workload_groups (NOLOCK) g ON es.group_id = g.group_id
	OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) qp 
	OUTER APPLY sys.dm_exec_query_statistics_xml(er.session_id) qes
WHERE er.session_id <> @@SPID AND es.is_user_process = 1
ORDER BY er.total_elapsed_time DESC, er.logical_reads DESC, [database_name], session_id'
	END
	ELSE IF (@sqlmajorver = 15 AND @sqlbuild >= 1400) OR @sqlmajorver > 15 
	BEGIN
		SELECT @sqlcmd = N'WITH tsu AS (SELECT session_id, SUM(user_objects_alloc_page_count) AS user_objects_alloc_page_count, 
SUM(user_objects_dealloc_page_count) AS user_objects_dealloc_page_count, 
SUM(internal_objects_alloc_page_count) AS internal_objects_alloc_page_count, 
SUM(internal_objects_dealloc_page_count) AS internal_objects_dealloc_page_count FROM sys.dm_db_task_space_usage (NOLOCK) GROUP BY session_id)
SELECT ''Requests'' AS [Information], es.session_id, DB_NAME(er.database_id) AS [database_name], OBJECT_NAME(qp.objectid, qp.dbid) AS [object_name],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt
		FOR XML PATH(''''), TYPE) AS [running_batch],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		SUBSTRING(qt2.text,
		1+(CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END),
		1+(CASE WHEN er.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er.statement_end_offset/2 END - (CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END))),
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(er.sql_handle) AS qt2
		FOR XML PATH(''''), TYPE) AS [running_statement],
	--ot.task_state AS [status],
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		ib.event_info,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_input_buffer(er.session_id, er.request_id) AS ib
		FOR XML PATH(''''), TYPE) AS [input_buffer],
	er.status,
	er.command,
	qp.query_plan,
	CASE WHEN qes.query_plan IS NULL THEN ''Lightweight Query Profiling Infrastructure is not enabled'' ELSE qes.query_plan END AS [live_query_plan_snapshot],
	CASE WHEN qps.query_plan IS NULL THEN ''Lightweight Query Profiling Infrastructure is not enabled'' ELSE qps.query_plan END AS [last_actual_execution_plan],
	er.percent_complete,
	CONVERT(VARCHAR(20),DATEADD(ms,er.estimated_completion_time,GETDATE()),20) AS [ETA_completion_time],
	(er.cpu_time/1000) AS cpu_time_sec,
	(er.reads*8)/1024 AS physical_reads_KB,
	(er.logical_reads*8)/1024 AS logical_reads_KB,
	(er.writes*8)/1024 AS writes_KB,
	(er.total_elapsed_time/1000)/60 AS elapsed_minutes,
	er.wait_type,
	er.wait_resource,
	er.last_wait_type,
	pi.page_type_desc AS wait_resource_type,
	er.wait_time AS wait_time_ms,
	er.cpu_time AS cpu_time_ms,
	er.open_transaction_count,
	DATEADD(s, (er.estimated_completion_time/1000), GETDATE()) AS estimated_completion_time,
	CASE WHEN mg.wait_time_ms IS NULL THEN DATEDIFF(ms, mg.request_time, mg.grant_time) ELSE mg.wait_time_ms END AS [grant_wait_time_ms],
	LEFT (CASE COALESCE(er.transaction_isolation_level, es.transaction_isolation_level)
		WHEN 0 THEN ''0-Unspecified''
		WHEN 1 THEN ''1-ReadUncommitted''
		WHEN 2 THEN ''2-ReadCommitted''
		WHEN 3 THEN ''3-RepeatableRead''
		WHEN 4 THEN ''4-Serializable''
		WHEN 5 THEN ''5-Snapshot''
		ELSE CONVERT (VARCHAR(30), er.transaction_isolation_level) + ''-UNKNOWN''
    END, 30) AS transaction_isolation_level,
	mg.requested_memory_kb,
	mg.granted_memory_kb,
	mg.ideal_memory_kb,
	mg.query_cost,
	((((ssu.user_objects_alloc_page_count + tsu.user_objects_alloc_page_count) -
		(ssu.user_objects_dealloc_page_count + tsu.user_objects_dealloc_page_count))*8)/1024) AS user_obj_in_tempdb_MB,
	((((ssu.internal_objects_alloc_page_count + tsu.internal_objects_alloc_page_count) -
		(ssu.internal_objects_dealloc_page_count + tsu.internal_objects_dealloc_page_count))*8)/1024) AS internal_obj_in_tempdb_MB,
	es.[host_name],
	es.login_name,
	--es.original_login_name,
	es.[program_name],
	--ec.client_net_address,
	es.is_user_process,
	g.name AS workload_group
FROM sys.dm_exec_requests (NOLOCK) er
	LEFT OUTER JOIN sys.dm_exec_query_memory_grants (NOLOCK) mg ON er.session_id = mg.session_id AND er.request_id = mg.request_id
	LEFT OUTER JOIN sys.dm_db_session_space_usage (NOLOCK) ssu ON er.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_exec_sessions (NOLOCK) es ON er.session_id = es.session_id
	LEFT OUTER JOIN tsu ON tsu.session_id = ssu.session_id
	LEFT OUTER JOIN sys.dm_resource_governor_workload_groups (NOLOCK) g ON es.group_id = g.group_id
	OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) qp 
	OUTER APPLY sys.dm_exec_query_statistics_xml(er.session_id) qes
	OUTER APPLY sys.dm_exec_query_plan_stats(er.plan_handle) qps
	OUTER APPLY sys.fn_PageResCracker(er.page_resource) pc  
	OUTER APPLY sys.dm_db_page_info(ISNULL(pc.db_id, 0), ISNULL(pc.file_id, 0), ISNULL(pc.page_id, 0), ''LIMITED'') pi
WHERE er.session_id <> @@SPID AND es.is_user_process = 1
ORDER BY er.total_elapsed_time DESC, er.logical_reads DESC, [database_name], session_id'
	END

	EXECUTE (@sqlcmd)
END;

-- Waiter and Blocking Report
IF @blocking = 1
BEGIN
	SELECT 'Waiter_Blocking_Report' AS [Information],
		-- blocked
		es.session_id AS blocked_spid,
		es.[status] AS [blocked_spid_status],
		ot.task_state AS [blocked_task_status],
		owt.wait_type AS blocked_spid_wait_type,
		COALESCE(owt.wait_duration_ms, DATEDIFF(ms, es.last_request_start_time, GETDATE())) AS blocked_spid_wait_time_ms,
		--er.total_elapsed_time AS blocked_elapsed_time_ms,
		/* 
			Check sys.dm_os_waiting_tasks for Exchange wait types in http://technet.microsoft.com/en-us/library/ms188743.aspx.
			- Wait Resource e_waitPipeNewRow in CXPACKET waits � Producer waiting on consumer for a packet to fill.
			- Wait Resource e_waitPipeGetRow in CXPACKET waits � Consumer waiting on producer to fill a packet.
		*/
		owt.resource_description AS blocked_spid_res_desc,
		owt.[objid] AS blocked_objectid,
		owt.pageid AS blocked_pageid,
		CASE WHEN owt.pageid = 1 OR owt.pageid % 8088 = 0 THEN 'Is_PFS_Page'
			WHEN owt.pageid = 2 OR owt.pageid % 511232 = 0 THEN 'Is_GAM_Page'
			WHEN owt.pageid = 3 OR (owt.pageid - 1) % 511232 = 0 THEN 'Is_SGAM_Page'
			WHEN owt.pageid IS NULL THEN NULL
			ELSE 'Is_not_PFS_GAM_SGAM_page' END AS blocked_spid_res_type,
		(SELECT qt.text AS [text()] 
			FROM sys.dm_exec_sql_text(COALESCE(er.sql_handle, ec.most_recent_sql_handle)) AS qt 
			FOR XML PATH(''), TYPE) AS [blocked_batch],
		(SELECT SUBSTRING(qt2.text, 
			1+(CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END),
			1+(CASE WHEN er.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er.statement_end_offset/2 END - (CASE WHEN er.statement_start_offset = 0 THEN 0 ELSE er.statement_start_offset/2 END))) AS [text()]
			FROM sys.dm_exec_sql_text(COALESCE(er.sql_handle, ec.most_recent_sql_handle)) AS qt2 
			FOR XML PATH(''), TYPE) AS [blocked_statement],
		es.last_request_start_time AS blocked_last_start,
		LEFT (CASE COALESCE(es.transaction_isolation_level, er.transaction_isolation_level)
			WHEN 0 THEN '0-Unspecified' 
			WHEN 1 THEN '1-ReadUncommitted(NOLOCK)' 
			WHEN 2 THEN '2-ReadCommitted' 
			WHEN 3 THEN '3-RepeatableRead' 
			WHEN 4 THEN '4-Serializable' 
			WHEN 5 THEN '5-Snapshot'
			ELSE CONVERT (VARCHAR(30), COALESCE(es.transaction_isolation_level, er.transaction_isolation_level)) + '-UNKNOWN' 
		END, 30) AS blocked_tran_isolation_level,

		-- blocker
		er.blocking_session_id As blocker_spid,
		CASE 
			-- session has an active request, is blocked, but is blocking others or session is idle but has an open tran and is blocking others
			WHEN (er2.session_id IS NULL OR owt.blocking_session_id IS NULL) AND (er.blocking_session_id = 0 OR er.session_id IS NULL) THEN 1
			-- session is either not blocking someone, or is blocking someone but is blocked by another party
			ELSE 0
		END AS is_head_blocker,
		(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			qt2.text,
			NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
			AS [text()]
			FROM sys.dm_exec_sql_text(COALESCE(er2.sql_handle, ec2.most_recent_sql_handle)) AS qt2 
			FOR XML PATH(''), TYPE) AS [blocker_batch],
		(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
			SUBSTRING(qt2.text, 
			1+(CASE WHEN er2.statement_start_offset = 0 THEN 0 ELSE er2.statement_start_offset/2 END),
			1+(CASE WHEN er2.statement_end_offset = -1 THEN DATALENGTH(qt2.text) ELSE er2.statement_end_offset/2 END - (CASE WHEN er2.statement_start_offset = 0 THEN 0 ELSE er2.statement_start_offset/2 END))),
			NCHAR(0),N'?'),NCHAR(1),N'?'),NCHAR(2),N'?'),NCHAR(3),N'?'),NCHAR(4),N'?'),NCHAR(5),N'?'),NCHAR(6),N'?'),NCHAR(7),N'?'),NCHAR(8),N'?'),NCHAR(11),N'?'),NCHAR(12),N'?'),NCHAR(14),N'?'),NCHAR(15),N'?'),NCHAR(16),N'?'),NCHAR(17),N'?'),NCHAR(18),N'?'),NCHAR(19),N'?'),NCHAR(20),N'?'),NCHAR(21),N'?'),NCHAR(22),N'?'),NCHAR(23),N'?'),NCHAR(24),N'?'),NCHAR(25),N'?'),NCHAR(26),N'?'),NCHAR(27),N'?'),NCHAR(28),N'?'),NCHAR(29),N'?'),NCHAR(30),N'?'),NCHAR(31),N'?') 
			AS [text()]
			FROM sys.dm_exec_sql_text(COALESCE(er2.sql_handle, ec2.most_recent_sql_handle)) AS qt2 
			FOR XML PATH(''), TYPE) AS [blocker_statement],
		es2.last_request_start_time AS blocker_last_start,
		LEFT (CASE COALESCE(er2.transaction_isolation_level, es.transaction_isolation_level)
			WHEN 0 THEN '0-Unspecified' 
			WHEN 1 THEN '1-ReadUncommitted(NOLOCK)' 
			WHEN 2 THEN '2-ReadCommitted' 
			WHEN 3 THEN '3-RepeatableRead' 
			WHEN 4 THEN '4-Serializable' 
			WHEN 5 THEN '5-Snapshot' 
			ELSE CONVERT (VARCHAR(30), COALESCE(er2.transaction_isolation_level, es.transaction_isolation_level)) + '-UNKNOWN' 
		END, 30) AS blocker_tran_isolation_level,

		-- blocked - other data
		DB_NAME(er.database_id) AS blocked_database, 
		es.[host_name] AS blocked_host,
		es.[program_name] AS blocked_program, 
		es.login_name AS blocked_login,
		CASE WHEN es.session_id = -2 THEN 'Orphaned_distributed_tran' 
			WHEN es.session_id = -3 THEN 'Defered_recovery_tran' 
			WHEN es.session_id = -4 THEN 'Unknown_tran' ELSE NULL END AS blocked_session_comment,
		es.is_user_process AS [blocked_is_user_process],

		-- blocker - other data
		DB_NAME(er2.database_id) AS blocker_database,
		es2.[host_name] AS blocker_host,
		es2.[program_name] AS blocker_program,	
		es2.login_name AS blocker_login,
		CASE WHEN es2.session_id = -2 THEN 'Orphaned_distributed_tran' 
			WHEN es2.session_id = -3 THEN 'Defered_recovery_tran' 
			WHEN es2.session_id = -4 THEN 'Unknown_tran' ELSE NULL END AS blocker_session_comment,
		es2.is_user_process AS [blocker_is_user_process]
	FROM sys.dm_exec_sessions (NOLOCK) es
	LEFT OUTER JOIN sys.dm_exec_requests (NOLOCK) er ON es.session_id = er.session_id
	LEFT OUTER JOIN sys.dm_exec_connections (NOLOCK) ec ON es.session_id = ec.session_id
	LEFT OUTER JOIN sys.dm_os_tasks (NOLOCK) ot ON er.session_id = ot.session_id AND er.request_id = ot.request_id
	LEFT OUTER JOIN sys.dm_exec_sessions (NOLOCK) es2 ON er.blocking_session_id = es2.session_id
	LEFT OUTER JOIN sys.dm_exec_requests (NOLOCK) er2 ON es2.session_id = er2.session_id
	LEFT OUTER JOIN sys.dm_exec_connections (NOLOCK) ec2 ON es2.session_id = ec2.session_id
	LEFT OUTER JOIN 
	(
		-- In some cases (e.g. parallel queries, also waiting for a worker), one thread can be flagged as 
		-- waiting for several different threads.  This will cause that thread to show up in multiple rows 
		-- in our grid, which we don't want.  Use ROW_NUMBER to select the longest wait for each thread, 
		-- and use it as representative of the other wait relationships this thread is involved in. 
		SELECT waiting_task_address, session_id, exec_context_id, wait_duration_ms, 
			wait_type, resource_address, blocking_task_address, blocking_session_id, 
			blocking_exec_context_id, resource_description,
			CASE WHEN [wait_type] LIKE 'PAGE%' AND [resource_description] LIKE '%:%' THEN CAST(RIGHT([resource_description], LEN([resource_description]) - CHARINDEX(':', [resource_description], LEN([resource_description])-CHARINDEX(':', REVERSE([resource_description])))) AS int)
				WHEN [wait_type] LIKE 'LCK%' AND [resource_description] LIKE '%pageid%' AND ISNUMERIC(RIGHT(LEFT([resource_description],CHARINDEX('dbid=', [resource_description], CHARINDEX('pageid=', [resource_description])+6)-1),CHARINDEX('=',REVERSE(RTRIM(LEFT([resource_description],CHARINDEX('dbid=', [resource_description], CHARINDEX('pageid=', [resource_description])+6)-1)))))) = 1 THEN CAST(RIGHT(LEFT([resource_description],CHARINDEX('dbid=', [resource_description], CHARINDEX('pageid=', [resource_description])+6)-1),CHARINDEX('=',REVERSE(RTRIM(LEFT([resource_description],CHARINDEX('dbid=', [resource_description], CHARINDEX('pageid=', [resource_description])+6)-1))))) AS bigint)
				ELSE NULL END AS pageid,
			CASE WHEN [wait_type] LIKE 'LCK%' AND [resource_description] LIKE '%associatedObjectId%' AND ISNUMERIC(RIGHT([resource_description],CHARINDEX('=', REVERSE([resource_description]))-1)) = 1 THEN CAST(RIGHT([resource_description],CHARINDEX('=', REVERSE([resource_description]))-1) AS bigint)
				ELSE NULL END AS [objid],
			ROW_NUMBER() OVER (PARTITION BY waiting_task_address ORDER BY wait_duration_ms DESC) AS row_num
		FROM sys.dm_os_waiting_tasks (NOLOCK)
	) owt ON ot.task_address = owt.waiting_task_address AND owt.row_num = 1
	--OUTER APPLY sys.dm_exec_sql_text(er.sql_handle) est
	--OUTER APPLY sys.dm_exec_query_plan(er.plan_handle) eqp
	WHERE es.session_id <> @@SPID AND es.is_user_process = 1 
		--AND ((owt.wait_duration_ms/1000 > 5) OR (er.total_elapsed_time/1000) > 5 OR er.total_elapsed_time IS NULL) --Only report blocks > 5 Seconds plus head blocker
		AND (es.session_id IN (SELECT er3.blocking_session_id FROM sys.dm_exec_requests (NOLOCK) er3) OR er.blocking_session_id IS NOT NULL OR er.blocking_session_id > 0)
	ORDER BY blocked_spid, is_head_blocker DESC, blocked_spid_wait_time_ms DESC, blocker_spid
END;

-- Query stats
IF @qrystats = 1 AND @sqlmajorver >= 11
BEGIN 
	SELECT @sqlcmd = N'SELECT' + CASE WHEN @top IS NULL THEN '' ELSE ' TOP ' + CONVERT(NVARCHAR(10), @top) END + ' CASE WHEN CONVERT(int,pa.value) = 32767 THEN ''ResourceDB'' ELSE DB_NAME(CONVERT(int,pa.value)) END AS DatabaseName,
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		st.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_sql_text(qs.sql_handle) AS st
		FOR XML PATH(''''), TYPE) AS [sqltext],
	qs.creation_time AS cached_time,
	qs.last_execution_time,
	qs.execution_count,
	qs.total_elapsed_time/qs.execution_count AS avg_elapsed_time,
	qs.last_elapsed_time,
	qs.total_worker_time/qs.execution_count AS avg_cpu_time,
	qs.last_worker_time AS last_cpu_time,
	qs.min_worker_time AS min_cpu_time, qs.max_worker_time AS max_cpu_time,
	qs.total_logical_reads/qs.execution_count AS avg_logical_reads,
	qs.last_logical_reads, qs.min_logical_reads, qs.max_logical_reads,
	qs.total_physical_reads/qs.execution_count AS avg_physical_reads,
	qs.last_physical_reads, qs.min_physical_reads, qs.max_physical_reads,
	qs.total_logical_writes/qs.execution_count AS avg_logical_writes,
	qs.last_logical_writes, qs.min_logical_writes, qs.max_logical_writes' + CASE WHEN @sqlmajorver >= 13 THEN ',
	CASE WHEN qs.total_grant_kb IS NOT NULL THEN qs.total_grant_kb/qs.execution_count ELSE -1 END AS avg_grant_kb,
	CASE WHEN qs.total_used_grant_kb IS NOT NULL THEN qs.total_used_grant_kb/qs.execution_count ELSE -1 END AS avg_used_grant_kb,
	COALESCE(((qs.total_used_grant_kb * 100.00) / NULLIF(qs.total_grant_kb,0)), 0) AS grant2used_ratio,
	CASE WHEN qs.total_ideal_grant_kb IS NOT NULL THEN qs.total_ideal_grant_kb/qs.execution_count ELSE -1 END AS avg_ideal_grant_kb,
	CASE WHEN qs.total_dop IS NOT NULL THEN qs.total_dop/qs.execution_count ELSE -1 END AS avg_dop,
	CASE WHEN qs.total_reserved_threads IS NOT NULL THEN qs.total_reserved_threads/qs.execution_count ELSE -1 END AS avg_reserved_threads,
	CASE WHEN qs.total_used_threads IS NOT NULL THEN qs.total_used_threads/qs.execution_count ELSE -1 END AS avg_used_threads' ELSE '' END + 
	CASE WHEN @sqlmajorver >= 15 OR (@sqlmajorver = 13 AND @sqlbuild >= 5026) OR (@sqlmajorver = 14 AND @sqlbuild >= 3015) THEN ',
	CASE WHEN qs.total_columnstore_segment_reads IS NOT NULL THEN qs.total_columnstore_segment_reads/qs.execution_count ELSE -1 END AS avg_columnstore_segment_reads,
	CASE WHEN qs.total_columnstore_segment_skips IS NOT NULL THEN qs.total_columnstore_segment_skips/qs.execution_count ELSE -1 END AS avg_columnstore_segment_skips,
	CASE WHEN qs.total_spills IS NOT NULL THEN qs.total_spills/qs.execution_count ELSE -1 END AS avg_spills' ELSE '' END +'
FROM sys.dm_exec_query_stats (NOLOCK) AS qs
CROSS APPLY sys.dm_exec_plan_attributes(qs.plan_handle) AS pa
WHERE pa.attribute = ''dbid'''
	EXEC (@sqlcmd);
END;

-- Stored procedure stats
IF @spstats = 1 AND @sqlmajorver >= 11
BEGIN 
	SET @sqlcmd = N'SELECT' + CASE WHEN @top IS NULL THEN '' ELSE ' TOP ' + CONVERT(NVARCHAR(10), @top) END + ' CASE WHEN ps.database_id = 32767 THEN ''ResourceDB'' ELSE DB_NAME(ps.database_id) END AS DatabaseName, 
	CASE WHEN ps.database_id = 32767 THEN NULL ELSE OBJECT_NAME(ps.[object_id], ps.database_id) END AS ObjectName,
	type_desc,
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_procedure_stats (NOLOCK) ps2 CROSS APPLY sys.dm_exec_sql_text(ps2.sql_handle) qt
		WHERE ps2.database_id = ps.database_id AND ps2.[object_id] = ps.[object_id] 
		FOR XML PATH(''''), TYPE) AS [sqltext],
	qp.query_plan,
	ps.cached_time,
	ps.last_execution_time,
	ps.execution_count,
	ps.total_elapsed_time/ps.execution_count AS avg_elapsed_time,
	ps.last_elapsed_time,
	ps.total_worker_time/ps.execution_count AS avg_cpu_time,
	ps.last_worker_time AS last_cpu_time,
	ps.min_worker_time AS min_cpu_time, ps.max_worker_time AS max_cpu_time,
	ps.total_logical_reads/ps.execution_count AS avg_logical_reads,
	ps.last_logical_reads, ps.min_logical_reads, ps.max_logical_reads,
	ps.total_physical_reads/ps.execution_count AS avg_physical_reads,
	ps.last_physical_reads, ps.min_physical_reads, ps.max_physical_reads,
	ps.total_logical_writes/ps.execution_count AS avg_logical_writes,
	ps.last_logical_writes, ps.min_logical_writes, ps.max_logical_writes
 FROM sys.dm_exec_procedure_stats (NOLOCK) ps
 CROSS APPLY sys.dm_exec_query_plan(ps.plan_handle) qp'
	EXEC (@sqlcmd);
END;

-- Trigger stats
IF @trstats = 1 AND @sqlmajorver >= 11
BEGIN
	SET @sqlcmd = N'SELECT' + CASE WHEN @top IS NULL THEN '' ELSE ' TOP ' + CONVERT(NVARCHAR(10), @top) END + ' CASE WHEN ts.database_id = 32767 THEN ''ResourceDB'' ELSE DB_NAME(ts.database_id) END AS DatabaseName, 
	CASE WHEN ts.database_id = 32767 THEN NULL ELSE OBJECT_NAME(ts.[object_id], ts.database_id) END AS ObjectName,
	type_desc,
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_trigger_stats (NOLOCK) ts2 CROSS APPLY sys.dm_exec_sql_text(ts2.sql_handle) qt 
		WHERE ts2.database_id = ts.database_id AND ts2.[object_id] = ts.[object_id] 
		FOR XML PATH(''''), TYPE) AS [sqltext],
	qp.query_plan,
	ts.cached_time,
	ts.last_execution_time,
	ts.execution_count,
	ts.total_elapsed_time/ts.execution_count AS avg_elapsed_time,
	ts.last_elapsed_time,
	ts.total_worker_time/ts.execution_count AS avg_cpu_time,
	ts.last_worker_time AS last_cpu_time,
	ts.min_worker_time AS min_cpu_time, ts.max_worker_time AS max_cpu_time,
	ts.total_logical_reads/ts.execution_count AS avg_logical_reads,
	ts.last_logical_reads, ts.min_logical_reads, ts.max_logical_reads,
	ts.total_physical_reads/ts.execution_count AS avg_physical_reads,
	ts.last_physical_reads, ts.min_physical_reads, ts.max_physical_reads,
	ts.total_logical_writes/ts.execution_count AS avg_logical_writes,
	ts.last_logical_writes, ts.min_logical_writes, ts.max_logical_writes
FROM sys.dm_exec_trigger_stats (NOLOCK) ts
CROSS APPLY sys.dm_exec_query_plan(ts.plan_handle) qp'
	EXEC (@sqlcmd);
END;

-- Function stats
IF @fnstats = 1 AND @sqlmajorver >= 13
BEGIN
	SET @sqlcmd = N'SELECT' + CASE WHEN @top IS NULL THEN '' ELSE ' TOP ' + CONVERT(NVARCHAR(10), @top) END + ' CASE WHEN fs.database_id = 32767 THEN ''ResourceDB'' ELSE DB_NAME(fs.database_id) END AS DatabaseName, 
	CASE WHEN fs.database_id = 32767 THEN NULL ELSE OBJECT_NAME(fs.[object_id], fs.database_id) END AS ObjectName,
	type_desc,
	(SELECT REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
		qt.text,
		NCHAR(0),N''?''),NCHAR(1),N''?''),NCHAR(2),N''?''),NCHAR(3),N''?''),NCHAR(4),N''?''),NCHAR(5),N''?''),NCHAR(6),N''?''),NCHAR(7),N''?''),NCHAR(8),N''?''),NCHAR(11),N''?''),NCHAR(12),N''?''),NCHAR(14),N''?''),NCHAR(15),N''?''),NCHAR(16),N''?''),NCHAR(17),N''?''),NCHAR(18),N''?''),NCHAR(19),N''?''),NCHAR(20),N''?''),NCHAR(21),N''?''),NCHAR(22),N''?''),NCHAR(23),N''?''),NCHAR(24),N''?''),NCHAR(25),N''?''),NCHAR(26),N''?''),NCHAR(27),N''?''),NCHAR(28),N''?''),NCHAR(29),N''?''),NCHAR(30),N''?''),NCHAR(31),N''?'') 
		AS [text()]
		FROM sys.dm_exec_function_stats (NOLOCK) fs2 CROSS APPLY sys.dm_exec_sql_text(fs2.sql_handle) qt 
		WHERE fs2.database_id = fs.database_id AND fs2.[object_id] = fs.[object_id] 
		FOR XML PATH(''''), TYPE) AS [sqltext],
	qp.query_plan,
	fs.cached_time,
	fs.last_execution_time,
	fs.execution_count,
	fs.total_elapsed_time/fs.execution_count AS avg_elapsed_time,
	fs.last_elapsed_time,
	fs.total_worker_time/fs.execution_count AS avg_cpu_time,
	fs.last_worker_time AS last_cpu_time,
	fs.min_worker_time AS min_cpu_time, fs.max_worker_time AS max_cpu_time,
	fs.total_logical_reads/fs.execution_count AS avg_logical_reads,
	fs.last_logical_reads, fs.min_logical_reads, fs.max_logical_reads,
	fs.total_physical_reads/fs.execution_count AS avg_physical_reads,
	fs.last_physical_reads, fs.min_physical_reads, fs.max_physical_reads,
	fs.total_logical_writes/fs.execution_count AS avg_logical_writes,
	fs.last_logical_writes, fs.min_logical_writes, fs.max_logical_writes
FROM sys.dm_exec_function_stats (NOLOCK) fs
CROSS APPLY sys.dm_exec_query_plan(fs.plan_handle) qp'
	EXEC (@sqlcmd);
END;
GO

