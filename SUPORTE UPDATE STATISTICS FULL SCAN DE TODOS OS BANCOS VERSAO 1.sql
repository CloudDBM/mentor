USE [master]
GO

/****** XObject:  StoredProcedure [dbo].[spu_updatestats_fullscan]    Script Date: 29/11/2022 08:17:05 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE OR ALTER procedure [dbo].[spu_updatestats_fullscan] as
Set Nocount on
DECLARE @comando varchar(1000)
Declare db Cursor For	
		Select name from master.dbo.sysdatabases
		Where name not in ('master','TempDB')
Declare @dbname varchar(100)
Declare @dbre varchar(1000)
DECLARE @execstr nvarchar(255)
Open db
Fetch Next from db into @dbname
While @@Fetch_status=0
   begin	
		DECLARE updatestats CURSOR FOR
		SELECT table_name FROM information_schema.tables
			where TABLE_TYPE = 'BASE TABLE'
		OPEN updatestats

		DECLARE @tablename NVARCHAR(128)
		DECLARE @Statement NVARCHAR(300)

		FETCH NEXT FROM updatestats INTO @tablename
		WHILE (@@FETCH_STATUS = 0)
		BEGIN
		   SET @comando = 'USE ' + @dbname
		   PRINT 'USE ' + @dbname
		   EXEC(@comando)
		   PRINT N'UPDATING STATISTICS ' + @tablename
		   SET @Statement = 'UPDATE STATISTICS '  + @tablename + '  WITH FULLSCAN'
		   EXEC sp_executesql @Statement
		   FETCH NEXT FROM updatestats INTO @tablename
		END
		Close updatestats
		Deallocate updatestats 
		Fetch Next from db into @dbname	
	 End
Close db
Deallocate db




