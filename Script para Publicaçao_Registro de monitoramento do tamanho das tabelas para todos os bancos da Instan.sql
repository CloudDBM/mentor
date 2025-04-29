/****** Object: Script de Historico de Crescimento de Tabela em Todos os bancos V1 Date: 29/04/2025 ******
EMPRESA: CLOUDDB
SITE: https://www.clouddb.com.br/
***************************************************************************************/

--Verifica/Cria a tabela de armazenamento no banco DBManager
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'DBManager')
BEGIN
    CREATE DATABASE DBManager;
END
GO

USE [DBManager]
GO

IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'table_size_history' AND schema_id = SCHEMA_ID('dbo'))
BEGIN

-- Cria uma tabela temporária para armazenar os resultados
CREATE TABLE table_size_history (
    database_name NVARCHAR(128),
    schema_name NVARCHAR(128),
    table_name NVARCHAR(128),
    row_count BIGINT,
    table_size_mb DECIMAL(18,2),
    index_size_mb DECIMAL(18,2),
    total_size_mb DECIMAL(18,2)
);
END
-- Gera e executa o SQL dinâmico para cada banco de dados
DECLARE @sql NVARCHAR(MAX);
DECLARE @dbname NVARCHAR(128);

DECLARE db_cursor CURSOR FOR 
SELECT name FROM sys.databases 
WHERE state = 0 -- apenas bancos online
AND name NOT IN ('master', 'tempdb', 'model', 'msdb') -- exclui bancos do sistema
ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE [' + @dbname + N'];
    INSERT INTO [DBManager].[dbo].[table_size_history]
    SELECT 
        DB_NAME() AS database_name,
        s.name AS schema_name,
        t.name AS table_name,
        p.rows AS row_count,
        SUM(a.data_pages) * 8.0 / 1024 AS table_size_mb,
        SUM(a.used_pages - a.data_pages) * 8.0 / 1024 AS index_size_mb,
        SUM(a.total_pages) * 8.0 / 1024 AS total_size_mb
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.indexes i ON t.object_id = i.object_id
    INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
    INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
    WHERE t.is_ms_shipped = 0
    GROUP BY s.name, t.name, p.rows;';
    
    BEGIN TRY
        EXEC sp_executesql @sql;
    END TRY
    BEGIN CATCH
        PRINT 'Erro ao processar o banco ' + @dbname + ': ' + ERROR_MESSAGE();
    END CATCH
    
    FETCH NEXT FROM db_cursor INTO @dbname;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Exibe os resultados
SELECT * FROM table_size_history
ORDER BY database_name, schema_name, table_name;