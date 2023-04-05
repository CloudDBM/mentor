SELECT 
    A.job_id,
    A.[name],
    B.session_id,
    B.run_requested_date,
    B.run_requested_source,
    B.queued_date,
    B.start_execution_date,
    B.last_executed_step_id,
    B.last_executed_step_date,
    B.stop_execution_date,
    B.job_history_id,
    B.next_scheduled_run_date	
FROM
    msdb.dbo.sysjobs A
    JOIN msdb.dbo.sysjobactivity B ON B.job_id = A.job_id