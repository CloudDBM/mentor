USE [AuditDB];
GO

INSERT INTO [AuditDB].[dbo].[DDLEvents]
(
    EventType,
    EventDDL,
    DatabaseName,
    SchemaName,
    ObjectName,
    LoginName
)
VALUES
(
SELECT
    'CREATE_PROCEDURE',
    OBJECT_DEFINITION([object_id]),
    DB_NAME(),
    OBJECT_SCHEMA_NAME([object_id]),
    OBJECT_NAME([object_id]),
    'my name'
FROM
    sys.procedures;
)