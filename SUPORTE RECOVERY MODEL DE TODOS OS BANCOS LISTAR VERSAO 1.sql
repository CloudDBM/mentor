SELECT name
, DATABASEPROPERTYEX(name,'RECOVERY') AS [Recovery Model]
FROM master.dbo.sysdatabases