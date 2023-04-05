/*==================================================================
Script: Monitor Backup Restore Dbcc.sql
Description: This script will display estimated completion times
and ETAs of Backup, Restore and DBCC operations.
Date created: 13.09.2018 (Dominic Wirth)
Last change: -
Script Version: 1.0
SQL Version: SQL Server 2008 or higher
====================================================================*/
SELECT Req.percent_complete AS PercentComplete
,CONVERT(NUMERIC(6,2),Req.estimated_completion_time/1000.0/60.0) AS MinutesUntilFinish
,DB_NAME(Req.database_id) AS DbName,
Req.session_id AS SPID, Txt.text AS Query,
Req.command AS SubQuery,
Req.start_time AS StartTime
,(CASE WHEN Req.estimated_completion_time < 1
THEN NULL
ELSE DATEADD(SECOND, Req.estimated_completion_time / 1000, GETDATE())
END) AS EstimatedFinishDate
,Req.[status] AS QueryState, Req.wait_type AS BlockingType,
Req.blocking_session_id AS BlockingSPID
FROM sys.dm_exec_requests AS Req
CROSS APPLY sys.dm_exec_sql_text(Req.[sql_handle]) AS Txt
WHERE Req.command IN ('BACKUP DATABASE','RESTORE DATABASE','BACKUP LOG','RESTORE LOG') OR Req.command LIKE 'DBCC%';