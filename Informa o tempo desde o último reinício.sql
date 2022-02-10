SELECT sqlserver_start_time FROM sys.dm_os_sys_info;
go
SELECT create_date  AS SQLServerStartTime FROM sys.databases WHERE name = 'tempdb';

go


SELECT (DATEDIFF(DAY, create_date, GETDATE()))
       AS [Days],
       ((DATEDIFF(MINUTE, create_date, GETDATE())/60)%24)
       AS [Hours],
       DATEDIFF(MINUTE, create_date, GETDATE())%60
       AS [Minutes]
FROM   sys.databases
WHERE  name = 'tempdb'