DECLARE @DATA AS VARCHAR (20)

SELECT @DATA = CONVERT(VARCHAR, GETDATE(), 105)

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
        WHEN js.last_run_outcome = 1 THEN 'Success'
        WHEN js.last_run_outcome = 2 THEN 'Retry'
        WHEN js.last_run_outcome = 3 THEN 'Cancelled'
        ELSE 'Unknown' 
    END JobRunStatus
	
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobservers js on js.job_id = j.job_id
WHERE j.enabled = 1 AND (js.last_run_outcome = 1 OR  js.last_run_outcome = 0)
AND (js.last_run_date >= CONVERT(char(8), (select dateadd (day, -1, getdate())), 112)) AND (j.name like '%DBA - Health_Check%'
OR j.name like '%INSERT%' OR j.name like '%SELECT%')
ORDER BY j.name, js.last_run_date, last_run_time 

DECLARE @JOB_NAME AS VARCHAR(MAX),
		@RUN_TIME_STAMP AS VARCHAR(MAX),		
		@JOB_RUN_STATUS AS VARCHAR(MAX)

DECLARE @SAIDA AS VARCHAR(MAX) = '<html><body><label>Status Manutenção Diária Data: ' + @DATA + ' Host: ' + @@SERVERNAME


	DECLARE c9 CURSOR FOR
	SELECT 
		JOB_NAME,
		RUN_TIME_STAMP,		
		JOB_RUN_STATUS
	FROM ##INFORMACOES
	OPEN c9

	FETCH NEXT FROM c9 INTO 
		@JOB_NAME,
		@RUN_TIME_STAMP,		
		@JOB_RUN_STATUS

	WHILE @@fetch_status <> -1
	BEGIN
		SET @SAIDA = @SAIDA + '<br><br>' + 'JOB_NAME: ' + @JOB_NAME							  
		IF ( @JOB_RUN_STATUS = 'Success')
			SET @SAIDA = @SAIDA + '<br>' + 'JOB_RUN_STATUS: <label style="color:green">' + @JOB_RUN_STATUS + '</label>&nbsp;&#128994;' + '<br>'
		ELSE
			SET @SAIDA = @SAIDA + '<br>' + 'JOB_RUN_STATUS: <label style="color:red">' + @JOB_RUN_STATUS + '</label>&nbsp;&#128308;' + '<br>'
							  						  
	FETCH NEXT FROM c9 INTO 
		@JOB_NAME,
		@RUN_TIME_STAMP,		
		@JOB_RUN_STATUS
	END

	CLOSE c9

	DEALLOCATE c9
SET @SAIDA = @SAIDA + '</html></body>'
DECLARE @assunto AS VARCHAR(MAX) 
SET @assunto =  N'<ELEVA> - ALERTA DE JOB TERMINADO - ' + @@SERVERNAME 

-- Envia o e-mail
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'DBA', -- sysname
    @recipients = 'vpmaciel@gmail.com', -- varchar(max)
    @body = @SAIDA,  
	@body_format = 'html',
    @subject = @assunto ; 