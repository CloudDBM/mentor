DECLARE @Result bit = 0
     IF EXISTS (SELECT job.name
                  FROM msdb.dbo.sysjobs_view job
            INNER JOIN msdb.dbo.sysjobactivity activity ON job.job_id = activity.job_id
            INNER JOIN msdb.dbo.syssessions sess ON sess.session_id = activity.session_id
            INNER JOIN (SELECT MAX(agent_start_date) AS max_agent_start_date
                          FROM msdb.dbo.syssessions) sess_max ON sess.agent_start_date = sess_max.max_agent_start_date
                 WHERE run_requested_date IS NOT NULL 
                   AND stop_execution_date IS NULL
                   AND job.name = 'GerenciaBD')
   SET @Result = 1

IF (@Result = 1)
BEGIN
	EXEC dbo.sp_stop_job N'GerenciaBD'
END
ELSE
BEGIN
	PRINT '0'
END