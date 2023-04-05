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

-- Transforma o conteúdo da query em HTML
DECLARE @HTML VARCHAR(MAX);  
 
SET @HTML = '
<html>
<head>  
<meta charset="utf-8"/>    
</head>
<body>
&#128994;

<span style="color: red">CSS em outro lugar</span><br>
<table border="1">
    <tr>
        <th>JOB_NAME</th>
        <th>RUN_TIME_STAMP</th>        
		<th>JOB_RUN_STATUS</th>
    </tr>
	</thead>
    
    <tbody>'
	+  
    CAST ( 
    (
        SELECT TOP 2000 
            td = I.JOB_NAME, '',
            td = I.RUN_TIME_STAMP, '',			
            td =  (CASE WHEN I.JOB_RUN_STATUS = 'Failed' THEN '<span style="color: red">CSS em outro lugar</span><br>' ELSE '<span style="color: red">CSS em outro lugar</span><br>' END)
        FROM ##INFORMACOES I GROUP BY I.JOB_NAME,I.RUN_TIME_STAMP, I.JOB_RUN_STATUS ORDER BY JOB_NAME, RUN_TIME_STAMP
        FOR XML PATH('tr'), TYPE
    ) AS NVARCHAR(MAX) ) + '
   </tbody>
</table></body>';

DECLARE @assunto as VARCHAR(500) 
SET @assunto =  N'<ELEVA> - ALERTA DE JOB TERMINADO - ' + @@SERVERNAME 

-- Envia o e-mail
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'DBA', -- sysname
    @recipients = 'vpmaciel@gmail.com', -- varchar(max)
    @subject = @assunto, 
    @body = @HTML,
    @body_format = 'html'