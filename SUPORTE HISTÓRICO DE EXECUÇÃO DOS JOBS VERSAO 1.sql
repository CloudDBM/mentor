SELECT 
    A.job_id,
    A.[name],
    msdb.dbo.agent_datetime(B.run_date, B.run_time) AS execution_date,
    A.[enabled],
    B.step_id,
    B.step_name,
    B.[message],
    (CASE B.run_status
        WHEN 0 THEN '0 - Failed'
        WHEN 1 THEN '1 - Succeeded'
        WHEN 2 THEN '2 - Retry'
        WHEN 3 THEN '3 - Canceled'
        WHEN 4 THEN '4 - In Progress'
    END) AS run_status,
    B.run_duration
FROM
    msdb.dbo.sysjobs A
    JOIN msdb.dbo.sysjobhistory B ON B.job_id = A.job_id