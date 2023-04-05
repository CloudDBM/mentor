IF OBJECT_ID(N'tempdb..##INFORMACOES') IS NOT NULL
DROP TABLE ##INFORMACOES

CREATE TABLE ##INFORMACOES(
JOB_NAME VARCHAR(500),
RUN_TIME_STAMP VARCHAR(500),
JOB_STATUS VARCHAR(500),
JOB_RUN_STATUS VARCHAR(500)
)

INSERT INTO ##INFORMACOES
SELECT
    j.name AS JobName
    ,IIF(js.last_run_date > 0, 
        DATETIMEFROMPARTS(js.last_run_date/10000, js.last_run_date/100%100, js.last_run_date%100, 
        js.last_run_time/10000, js.last_run_time/100%100, js.last_run_time%100, 0), 
        NULL) AS RunTimeStamp
    ,CASE
        WHEN j.enabled = 1 THEN 'Enabled' 
        ELSE 'Disabled' 
    END JobStatus
    ,CASE
        WHEN js.last_run_outcome = 0 THEN 'Failed'
        WHEN js.last_run_outcome = 1 THEN 'Succeeded'
        WHEN js.last_run_outcome = 2 THEN 'Retry'
        WHEN js.last_run_outcome = 3 THEN 'Cancelled'
        ELSE 'Unknown' 
    END JobRunStatus
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobservers js on js.job_id = j.job_id
WHERE j.enabled = 1 AND js.last_run_outcome = 1
AND (js.last_run_date >= CONVERT(char(8), (select dateadd (day, 0, getdate())), 112))	
ORDER BY j.name, js.last_run_date, js.last_run_time 

DECLARE @JOB_NAME AS VARCHAR(500)
DECLARE @SAIDA AS VARCHAR(500)

DECLARE SQL_CURSOR CURSOR FOR
	SELECT JOB_NAME FROM ##INFORMACOES WHERE JOB_RUN_STATUS = 'Succeeded' AND RUN_TIME_STAMP >= DateADD(mi, -5, Current_TimeStamp)
OPEN SQL_CURSOR;
FETCH NEXT FROM SQL_CURSOR INTO @JOB_NAME
IF @@FETCH_STATUS = -1
	BEGIN
		PRINT ''
	END
	ELSE
	BEGIN
		SET @SAIDA = '<AFYA> <' + @@SERVERNAME + '> <' + @JOB_NAME + '> <Job Completado Com Sucesso>'

		EXEC msdb.dbo.sp_send_dbmail
			@profile_name = 'DBA',
			@recipients = 'monitoramento@clouddbm.com',
			@subject = @SAIDA,
			@body = @SAIDA, 
			@body_format = 'TEXT',
			@query_result_width = 20000,
			@query_result_header = 1, 
			@query_no_truncate = 1,
			@query_result_no_padding = 0;
	END
CLOSE SQL_CURSOR
DEALLOCATE SQL_CURSOR