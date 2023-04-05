USE [DBManager]
GO

DISABLE TRIGGER [DDLTrigger_Sample] ON DATABASE;

USE [DBManager]
GO

ENABLE TRIGGER [DDLTrigger_Sample] ON DATABASE;

SELECT *
    FROM AuditDB.dbo.DDLEvents
    WHERE EventType = 'ALTER_PROCEDURE';