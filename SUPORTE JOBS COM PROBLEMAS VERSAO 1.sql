USE msdb;

;WITH CTE_MostRecentJobRun AS 
 ( 
 -- For each job get the most recent run (this will be the one where Rnk=1) 
 SELECT job_id,run_status,run_date,run_time 
 ,RANK() OVER (PARTITION BY job_id ORDER BY run_date DESC,run_time DESC) AS Rnk 
 FROM sysjobhistory 
 WHERE step_id=0 
 ) 
SELECT  
  name  AS [Job Name]
 ,CONVERT(VARCHAR,DATEADD(S,(run_time/10000)*60*60 /* hours */ 
  +((run_time - (run_time/10000) * 10000)/100) * 60 /* mins */ 
  + (run_time - (run_time/100) * 100)  /* secs */, 
  CONVERT(DATETIME,RTRIM(run_date),113)),100) AS [Time Run]
 ,CASE WHEN enabled=1 THEN 'Enabled' 
     ELSE 'Disabled' 
  END [Job Status]
FROM     CTE_MostRecentJobRun MRJR 
JOIN     sysjobs SJ 
ON       MRJR.job_id=sj.job_id 
WHERE    Rnk=1 
AND      run_status=0 -- i.e. failed 
ORDER BY name 