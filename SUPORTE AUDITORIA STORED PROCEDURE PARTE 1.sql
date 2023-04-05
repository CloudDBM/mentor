CREATE DATABASE AuditDB;
GO
USE AuditDB;
GO


CREATE TABLE dbo.DDLEvents
(
    EventDate    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    EventType    NVARCHAR(64),
    EventDDL     NVARCHAR(MAX),
    EventXML     XML,
    DatabaseName NVARCHAR(255),
    SchemaName   NVARCHAR(255),
    ObjectName   NVARCHAR(255),
    HostName     VARCHAR(64),
    IPAddress    VARCHAR(48),
    ProgramName  NVARCHAR(255),
    LoginName    NVARCHAR(255)
);