USE [msdb]
GO

/***************************************************************************************************
-- Trigger para os Jobs
***************************************************************************************************/
IF ((SELECT COUNT(*) FROM sys.triggers WHERE name = 'trgJobs_Status') > 0) DROP TRIGGER dbo.trgJobs_Status
GO

CREATE OR ALTER TRIGGER trgJobs_Status ON sysjobs
AFTER INSERT, UPDATE, DELETE AS
BEGIN
    
    
    SET NOCOUNT ON  


    DECLARE 
        @UserName VARCHAR(50) = SYSTEM_USER, 
        @HostName VARCHAR(50) = HOST_NAME(),  
        @JobName sysname,  
        @New_Enabled INT,  
        @Old_Enabled INT,  
        @ExecStr VARCHAR(100),
        @Qry VARCHAR(MAX)

        
    SELECT @New_Enabled = [enabled] FROM Inserted
    SELECT @Old_Enabled = [enabled] FROM Deleted
    SELECT @JobName = [name] FROM Deleted


    IF (@JobName IS NULL)
        SELECT @JobName = [name] FROM Deleted


    -- Identificando a query executada
    CREATE TABLE #inputbuffer (
        [EventType] NVARCHAR(60), 
        [Parameters] INT, 
        [EventInfo] VARCHAR(MAX)
    )

    SET @ExecStr = 'DBCC INPUTBUFFER(' + STR(@@SPID) + ')'

    INSERT INTO #inputbuffer 
    EXEC (@ExecStr)

    SET @Qry = (SELECT EventInfo FROM #inputbuffer)


    -- Verifica se houve alteração de status
    IF (@New_Enabled != @Old_Enabled)
    BEGIN  
        

        IF (@New_Enabled = 1)
        BEGIN  

            INSERT INTO [DBManager].dbo.Job_Audit( Ds_Usuario, Ds_Job, Ds_Hostname, Ds_Query, Fl_Situacao )
            SELECT @UserName, @JobName, @HostName, @Qry, 1

        END  


        IF (@New_Enabled = 0)
        BEGIN  
            
            INSERT INTO [DBManager].dbo.Job_Audit ( Ds_Usuario, Ds_Job, Ds_Hostname, Ds_Query, Fl_Situacao )
            SELECT @UserName, @JobName, @HostName, @Qry, 0

        END  

    END
    ELSE BEGIN

        INSERT INTO [DBManager].dbo.Job_Audit ( Ds_Usuario, Ds_Job, Ds_Hostname, Ds_Query )
        SELECT @UserName, @JobName, @HostName, @Qry

    END

END
GO

/***************************************************************************************************
-- Trigger para os Schedules dos Jobs
***************************************************************************************************/
IF ((SELECT COUNT(*) FROM sys.triggers WHERE name = 'trgAudit_Schedules') > 0) DROP TRIGGER dbo.trgAudit_Schedules
GO

CREATE OR ALTER TRIGGER [dbo].[trgAudit_Schedules] ON [dbo].[sysschedules]
AFTER UPDATE, DELETE 
AS
BEGIN
    
    
    SET NOCOUNT ON  


    DECLARE 
        @UserName VARCHAR(50) = SYSTEM_USER, 
        @HostName VARCHAR(50) = HOST_NAME(),  
        @JobName VARCHAR(MAX) = '',  
        @ExecStr VARCHAR(100),
        @Qry VARCHAR(MAX)


    IF ((SELECT COUNT(*) FROM Inserted) > 0)
    BEGIN

        SELECT @JobName += (CASE WHEN @JobName != '' THEN ' | ' ELSE '' END) + A.[name]
        FROM msdb.dbo.sysjobs A
        JOIN msdb.dbo.sysjobschedules B ON A.job_id = B.job_id
        JOIN Inserted C ON B.schedule_id = C.schedule_id

    END
    ELSE BEGIN

        SELECT @JobName += (CASE WHEN @JobName != '' THEN ' | ' ELSE '' END) + A.[name]
        FROM msdb.dbo.sysjobs A
        JOIN msdb.dbo.sysjobschedules B ON A.job_id = B.job_id
        JOIN Deleted C ON B.schedule_id = C.schedule_id

    END

        
    -- Identificando a query executada
    CREATE TABLE #inputbuffer (
        [EventType] NVARCHAR(60), 
        [Parameters] INT, 
        [EventInfo] VARCHAR(MAX)
    )

    SET @ExecStr = 'DBCC INPUTBUFFER(' + STR(@@SPID) + ')'

    INSERT INTO #inputbuffer 
    EXEC (@ExecStr)

    SET @Qry = (SELECT EventInfo FROM #inputbuffer)

    IF (@JobName != '')
    BEGIN
    
        INSERT INTO [DBManager].dbo.Job_Audit ( Ds_Usuario, Ds_Job, Ds_Hostname, Ds_Query )
        SELECT @UserName, @JobName, @HostName, @Qry

    END


END
GO

ALTER TABLE [dbo].[sysschedules] ENABLE TRIGGER [trgAudit_Schedules]
GO

/***************************************************************************************************
-- Trigger para os Schedules
***************************************************************************************************/
IF ((SELECT COUNT(*) FROM sys.triggers WHERE name = 'trgAudit_Jobs_Schedules') > 0) DROP TRIGGER dbo.trgAudit_Jobs_Schedules
GO

CREATE OR ALTER TRIGGER [dbo].[trgAudit_Jobs_Schedules] ON [dbo].[sysjobschedules]  
AFTER INSERT 
AS
BEGIN
    
    
    SET NOCOUNT ON  


    DECLARE 
        @UserName VARCHAR(50) = SYSTEM_USER, 
        @HostName VARCHAR(50) = HOST_NAME(),  
        @JobName sysname,  
        @ExecStr VARCHAR(100),
        @Qry VARCHAR(MAX)


    IF ((SELECT COUNT(*) FROM Inserted) > 0)
    BEGIN

        SELECT @JobName = A.[name]
        FROM msdb.dbo.sysjobs A
        JOIN Inserted B ON A.job_id = B.job_id

    END
    ELSE BEGIN

        SELECT @JobName = A.[name]
        FROM msdb.dbo.sysjobs A
        JOIN Deleted B ON A.job_id = B.job_id

    END

        
    -- Identificando a query executada
    CREATE TABLE #inputbuffer (
        [EventType] NVARCHAR(60), 
        [Parameters] INT, 
        [EventInfo] VARCHAR(MAX)
    )

    SET @ExecStr = 'DBCC INPUTBUFFER(' + STR(@@SPID) + ')'

    INSERT INTO #inputbuffer 
    EXEC (@ExecStr)

    SET @Qry = (SELECT EventInfo FROM #inputbuffer)

    
    INSERT INTO [DBManager].dbo.Job_Audit ( Ds_Usuario, Ds_Job, Ds_Hostname, Ds_Query )
    SELECT @UserName, @JobName, @HostName, @Qry


END
GO

ALTER TABLE [dbo].[sysjobschedules] ENABLE TRIGGER [trgAudit_Jobs_Schedules]
GO