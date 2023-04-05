IF OBJECT_ID('tempdb.dbo.#RunningJobs') IS NOT NULL
      DROP TABLE #RunningJobs
CREATE TABLE #RunningJobs (  
Job_ID UNIQUEIDENTIFIER,  
Last_Run_Date INT,  
Last_Run_Time INT,  
Next_Run_Date INT,  
Next_Run_Time INT,  
Next_Run_Schedule_ID INT,  
Requested_To_Run INT,  
Request_Source INT,  
Request_Source_ID VARCHAR(100),  
Running INT,  
Current_Step INT,  
Current_Retry_Attempt INT,  
State INT )    
     
INSERT INTO #RunningJobs EXEC master.dbo.xp_sqlagent_enum_jobs 1,garbage  
 
SELECT    
  name AS [Job Name]
 ,CASE WHEN next_run_date=0 THEN '[Not scheduled]' ELSE
   CONVERT(VARCHAR,DATEADD(S,(next_run_time/10000)*60*60 /* hours */ 
  +((next_run_time - (next_run_time/10000) * 10000)/100) * 60 /* mins */ 
  + (next_run_time - (next_run_time/100) * 100)  /* secs */, 
  CONVERT(DATETIME,RTRIM(next_run_date),112)),100) END AS [Start Time]
FROM     #RunningJobs JSR 
JOIN     msdb.dbo.sysjobs 
ON       JSR.Job_ID=sysjobs.job_id 
WHERE    Running=1 -- i.e. still running 
ORDER BY name,next_run_date,next_run_time 
