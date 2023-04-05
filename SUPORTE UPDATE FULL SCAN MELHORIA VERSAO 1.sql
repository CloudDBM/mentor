--PASSOS DO PROCEDIMENTO

-- 1 - acessar banco de dados
USE CORTEZDELIMA
GO

-- 2 - mudar nível de compatibilidade
exec sp_dbcmptlevel CORTEZDELIMA, 150
go

exec sp_updatestats

ALTER DATABASE SCOPED CONFIGURATION SET LEGACY_CARDINALITY_ESTIMATION = On;
GO
-- 3 - criar a stored procedure de update fullscan
create or alter procedure [dbo].[spu_updatestats_fullscan] as

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

go

-- Executar a stored procedure
exec [spu_updatestats_fullscan]