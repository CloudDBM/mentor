USE master;  
GO  
EXEC sp_detach_db @dbname = N'CR_Manager';  
GO
USE master;  
GO
EXEC xp_cmdshell  'COPY "S:\MSSQL\DATA\CR_Manager.mdf" K:\MSSQL\Data';
GO
EXEC xp_cmdshell  'COPY "S:\MSSQL\DATA\CR_Manager.ldf" K:\MSSQL\Data';
GO

-- atachar
USE master;  
GO  
CREATE DATABASE CR_Manager   
    ON (FILENAME = 'K:\MSSQL\Data\CR_Manager.mdf'),  
    (FILENAME = 'K:\MSSQL\Data\CR_Manager.ldf')  
    FOR ATTACH;  
GO
/*
EXEC xp_cmdshell  'del S:\MSSQL\DATA\CR_Manager.mdf'  
GO
EXEC xp_cmdshell  'del S:\MSSQL\DATA\CR_Manager.ldf'
*/