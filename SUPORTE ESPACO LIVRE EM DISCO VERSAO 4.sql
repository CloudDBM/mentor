declare @chkCMDShell as sql_variant
select @chkCMDShell = value from sys.configurations where name = 'xp_cmdshell'
if @chkCMDShell = 0
begin
   EXEC sp_configure 'xp_cmdshell', 1
   RECONFIGURE;
end
else
begin
   Print ''
   --Print 'xp_cmdshell is already enabled'
end

declare @svrName varchar(255)
declare @sql varchar(400)
--by default it will take the current server name, we can the set the server name as well
set @svrName = @@SERVERNAME
set @sql = 'powershell.exe -c "Get-WmiObject -ComputerName ' + QUOTENAME(@svrName,'''') + ' -Class Win32_Volume -Filter ''DriveType = 3'' | select name,capacity,freespace | foreach{$_.name+''|''+$_.capacity/1048576+''%''+$_.freespace/1048576+''*''}"'
--creating a temporary table
CREATE TABLE #output
(line varchar(255))
--inserting disk name, total space and free space value in to temporary table
insert #output
EXEC xp_cmdshell @sql
--script to retrieve the values in MB from PS Script output
select rtrim(ltrim(SUBSTRING(line,1,CHARINDEX('|',line) -1))) as drivename
   ,round(cast(rtrim(ltrim(SUBSTRING(line,CHARINDEX('|',line)+1,
   (CHARINDEX('%',line) -1)-CHARINDEX('|',line)) )) as Float),0) as 'capacity(MB)'
   ,round(cast(rtrim(ltrim(SUBSTRING(line,CHARINDEX('%',line)+1,
   (CHARINDEX('*',line) -1)-CHARINDEX('%',line)) )) as Float),0) as 'freespace(MB)'
from #output
where line like '[A-Z][:]%'
order by drivename
--script to retrieve the values in GB from PS Script output
select rtrim(ltrim(SUBSTRING(line,1,CHARINDEX('|',line) -1))) as drivename
   ,round(cast(rtrim(ltrim(SUBSTRING(line,CHARINDEX('|',line)+1,
   (CHARINDEX('%',line) -1)-CHARINDEX('|',line)) )) as Float)/1024,0) as 'capacity(GB)'
   ,round(cast(rtrim(ltrim(SUBSTRING(line,CHARINDEX('%',line)+1,
   (CHARINDEX('*',line) -1)-CHARINDEX('%',line)) )) as Float) /1024 ,0)as 'freespace(GB)'
from #output
where line like '[A-Z][:]%'
order by drivename
--script to drop the temporary table
drop table #output