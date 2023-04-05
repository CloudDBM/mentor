SELECT  DISTINCT(j.[name]), h.step_id, 
 h.step_name, h.sql_message_id          
FROM    msdb.dbo.sysjobhistory h  
        INNER JOIN msdb.dbo.sysjobs j  
            ON h.job_id = j.job_id  
        INNER JOIN msdb.dbo.sysjobsteps s  
            ON j.job_id = s.job_id 
                AND h.step_id = s.step_id  
WHERE    h.run_status = 0 AND h.run_date > CONVERT(int, CONVERT(varchar(10), DATEADD(DAY, -1, GETDATE()), 112))