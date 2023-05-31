-- Para limpar o TempDB sem reiniciar o serviço do SQL Server, você pode executar o seguinte script no Management Studio:
USE TempDB;
GO
DBCC FREEPROCCACHE;
GO
DBCC DROPCLEANBUFFERS;
GO
CHECKPOINT;
GO
DBCC DROPCLEANBUFFERS;
GO
DBCC FREEPROCCACHE;
GO
DBCC FREESYSTEMCACHE ('ALL');
GO
DBCC FREESESSIONCACHE;
GO
DBCC SHRINKFILE (TEMPDEV, 20480);   --- New file size in MB
GO
ALTER DATABASE [tempdb] ADD FILE ( NAME = N'tempdev02', FILENAME = N'D:\Program Files\Microsoft SQL Server\MSSQL10.MSSQLSERVER\MSSQL\DATA\tempdev02.ndf' , SIZE = 25428992KB , FILEGROWTH = 10%)
GO

USE tempdb
GO
SET NOCOUNT ON;
 
 
IF OBJECT_ID('tempdb.dbo.#tmp1') IS NOT NULL
  DROP TABLE #tmp1
GO
 
CREATE TABLE [dbo].[#tmp1](
                [dbName] [nvarchar](130) NULL,
                [TableName] [nvarchar](391) NULL,
                [Statistic] [nvarchar](128) NULL,
                [WasAutoCreated] [bit] NULL,
                [WasUserCreated] [bit] NULL,
                [IsFiltered] [bit] NULL,
                [FilterDefinition] [nvarchar](max) NULL,
                [IsTemporary] [bit] NULL,
                [StatsLastUpdated] [datetime2](7) NULL,
                [RowsInTable] [bigint] NULL,
                [RowsSampled] [bigint] NULL,
                [UnfilteredRows] [bigint] NULL,
                [RowModifications] [bigint] NULL,
                [HistogramSteps] [int] NULL,
                [PercentChange] [decimal](18, 2) NULL,
                [UpdateStatCmd] [nvarchar](539) NULL
) ON [PRIMARY] 
GO
 
IF OBJECT_ID('tempdb.dbo.#db') IS NOT NULL
  DROP TABLE #db
GO
 
SELECT d1.[name] into #db
FROM sys.databases d1
where d1.state_desc = 'ONLINE' and is_read_only = 0
--and d1.name in ('Angellira')
 
DECLARE @SQL NVARCHAR(MAX)
declare @database_name sysname
 
DECLARE c_databases CURSOR read_only FOR
    SELECT [name] FROM #db
OPEN c_databases
 
FETCH NEXT FROM c_databases
into @database_name
WHILE @@FETCH_STATUS = 0
BEGIN
 
  SET @SQL = 'use [' + @database_name + ']; '  
  
  
  SET @SQL = @SQL + '
  SELECT ''['' + DB_NAME() + '']'' AS dbName,
                                 ''['' + DB_NAME() + '']'' + ''['' + [sch].[name] + ''].['' + [so].[name] + '']'' AS [TableName],
                                 [ss].[name] AS [Statistic],
                                 [ss].[auto_created] AS [WasAutoCreated],
                                 [ss].[user_created] AS [WasUserCreated],
                                 [ss].[has_filter] AS [IsFiltered],
                                 [ss].[filter_definition] AS [FilterDefinition],
                                 [ss].[is_temporary] AS [IsTemporary],
                                 [sp].[last_updated] AS [StatsLastUpdated],
                                 [sp].[rows] AS [RowsInTable],
                                 [sp].[rows_sampled] AS [RowsSampled],
                                 [sp].[unfiltered_rows] AS [UnfilteredRows],
                                 [sp].[modification_counter] AS [RowModifications],
                                 [sp].[steps] AS [HistogramSteps],
                                 CAST(100 * [sp].[modification_counter] / [sp].[rows] AS DECIMAL(18, 2)) AS [PercentChange],
                                 ''UPDATE STATISTICS '' + ''['' + DB_NAME() + ''].['' + [sch].[name] + ''].['' + [so].[name] + ''] '' + [ss].[name] AS UpdateStatCmd
  FROM [sys].[stats] [ss] 
                  JOIN [sys].[objects] [so]
                                 ON [ss].[object_id] = [so].[object_id]
                  JOIN [sys].[schemas] [sch]
                                 ON [so].[schema_id] = [sch].[schema_id]
                  OUTER APPLY [sys].[dm_db_stats_properties]([so].[object_id], [ss].[stats_id]) sp
  WHERE [so].[type] = ''U''
  ORDER BY CAST(100 * [sp].[modification_counter] / [sp].[rows] AS DECIMAL(18, 2)) DESC;'
  

  INSERT INTO #tmp1
  
  exec (@SQL)
  
  FETCH NEXT FROM c_databases
  into @database_name
END
CLOSE c_databases
DEALLOCATE c_databases
GO
 
 
-- Query result... 
SELECT * FROM #tmp1
WHERE 1=1
--AND dbName = '[Escola1]' 
AND PercentChange > 1.00
ORDER BY PercentChange DESC, RowModifications DESC
GO
 
 
 
-- Run update statistic for all statistics with percent change greater than 1%
DECLARE @SQL NVarChar(MAX), 
        @statusMsg NVARCHAR(MAX), 
        @StatsCount INT, 
        @PercentChange [decimal](18, 2), 
        @i INT,
        @Db NVARCHAR(500),
                               @Execute Char(1)
 
SET @PercentChange = 1.00 -- 1%
SET @Db = NULL -- Set NULL to run update for all dbs
SET @Execute = 'Y' -- Change to 'Y' to run script, otherwise it will only print the result
 
SELECT @StatsCount = COUNT(*) 
  FROM #tmp1
WHERE PercentChange > @PercentChange
   AND (dbName = @db OR @db IS NULL)
 
SET @i = 0
 
DECLARE c_stats CURSOR read_only FOR
    SELECT UpdateStatCmd 
     FROM #tmp1
    WHERE PercentChange > @PercentChange
      AND (dbName = @db OR @db IS NULL)
OPEN c_stats
 
FETCH NEXT FROM c_stats
into @SQL
WHILE @@FETCH_STATUS = 0
BEGIN
  SET @i = @i + 1
  SELECT @statusMsg = '--Working on stat ' + CAST(@i  AS VARCHAR(10))
        + ' of ' + CAST(@StatsCount  AS VARCHAR(10)) + ' Command = ' --+ @SQL
 
  RAISERROR(@statusMsg, 0, 42) WITH NOWAIT;
 
  IF @Execute = 'Y'
  BEGIN
    BEGIN TRY
	  SET @SQL = @SQL + ' with fullscan'
	  print @SQL
      exec (@SQL) --mudei aqui
                END TRY
    BEGIN CATCH
      SET @statusMsg = 'Error processing statistic = ' + @SQL + ' skipping this obj...'
      RAISERROR(@statusMsg, 0, 42) WITH NOWAIT;
    END CATCH
  END 
  
  FETCH NEXT FROM c_stats
  into @SQL
END
CLOSE c_stats
DEALLOCATE c_stats
GO
