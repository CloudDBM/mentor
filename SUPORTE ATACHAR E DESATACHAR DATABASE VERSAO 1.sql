-- Enable advanced options in the master database of the SQL Server 2019 instance

USE master;  
GO  
EXEC sp_configure 
     'show advanced option', 
     '1';  
RECONFIGURE WITH OVERRIDE;
-- Enable Xp_cmdshell extended stored procedure

EXEC sp_configure 'xp_cmdshell', 1;  
GO  
RECONFIGURE;
--EXEC xp_cmdshell 'whoami'
-- desatachar
USE master;  
GO  
EXEC sp_detach_db @dbname = N'AdventureWorksLT2019';  
GO

EXEC xp_cmdshell  'COPY "C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\AdventureWorksLT2012.mdf" "C:\temp\AdventureWorksLT2012.mdf"';
EXEC xp_cmdshell  'COPY "C:\Program Files\Microsoft SQL Server\MSSQL15.MSSQLSERVER\MSSQL\DATA\AdventureWorksLT2012_Log.ldf" "C:\temp\AdventureWorksLT2012_Log.ldf"';
EXEC xp_cmdshell  'COPY "D:\abc.txt" "C:\temp\sss.txt"';


-- atachar
USE master;  
GO  
CREATE DATABASE AdventureWorksLT2019   
    ON (FILENAME = 'C:\temp\AdventureWorksLT2012.mdf'),  
    (FILENAME = 'C:\temp\AdventureWorksLT2012_Log.ldf')  
    FOR ATTACH;  
GO

