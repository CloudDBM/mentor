SELECT  @@SERVERNAME AS [Server Name] ,
		service_account ,
        instant_file_initialization_enabled,
        RIGHT(@@version, LEN(@@version) - 3 - CHARINDEX(' ON ', @@VERSION)) AS [OS Info] ,
        LEFT(@@VERSION, CHARINDEX('-', @@VERSION) - 2) + ' '
        + CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(300)) AS [SQL Server Version]        
FROM    sys.dm_server_services
WHERE   servicename LIKE 'SQL Server (%'