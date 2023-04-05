use msdb
go
SELECT name, database_id, create_date  
FROM sys.databases   
order by 2;

GO