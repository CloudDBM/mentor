USE [DBManager]
GO

/****** Object:  Table [dbo].[sysobjects]    Script Date: 17/06/2022 11:54:28 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO
IF NOT EXISTS (SELECT * FROM sysobjects where name='tbl_sys_objects'and xtype='U')
CREATE TABLE [DBManager].[dbo].[tbl_sys_objects](
	[name] [sysname] NOT NULL,
	[id] [int] NOT NULL,
	[xtype] [char](2) NOT NULL,
	[crdate] [datetime] NOT NULL,
	[type] [char](2) NULL,
	[userstat] [smallint] NULL,
	[sysstat] [smallint] NULL,
	[indexdel] [smallint] NULL,
	[refdate] [datetime] NOT NULL,
	[deltrig] [int] NULL,
	[instrig] [int] NULL,
	[updtrig] [int] NULL,
	[seltrig] [int] NULL
) ON [PRIMARY]

USE DBManager;

declare 
    @name sysname,
	@id int,
	@xtype char(2),
	@crdate datetime,
	@type char(2),
	@userstat smallint,
	@sysstat smallint,
	@indexdel smallint,
	@refdate datetime,
	@deltrig int,
	@instrig int,
	@updtrig int,
	@seltrig int  

declare c1 cursor for
SELECT [name],[id],[xtype],[crdate],[type],[userstat],[sysstat],[indexdel],[refdate],[deltrig],[instrig],[updtrig],[seltrig] FROM Master.[sys].[sysobjects]
  where type = 'V' ORDER BY 9 DESC;
open c1    
fetch next from c1 into	@name,@id,@xtype,@crdate,@type,@userstat,@sysstat,@indexdel,@refdate,@deltrig,@instrig,@updtrig,@seltrig

	While @@fetch_status <> -1
	begin
		INSERT INTO [DBManager].[dbo].[tbl_sys_objects]
		(
		   [name] ,[id] ,[xtype] ,[crdate] ,[type] ,[userstat] ,[sysstat] ,[indexdel] ,[refdate] ,[deltrig] ,[instrig] ,[updtrig]  ,[seltrig]
		)
		VALUES (
		@name,@id,@xtype,@crdate,@type,@userstat,@sysstat,@indexdel,@refdate,@deltrig,@instrig,@updtrig,@seltrig
		)
		fetch next from c1 into @name,@id,@xtype,@crdate,@type,@userstat,@sysstat,@indexdel,@refdate,@deltrig,@instrig,@updtrig,@seltrig
	end

	close c1

deallocate c1