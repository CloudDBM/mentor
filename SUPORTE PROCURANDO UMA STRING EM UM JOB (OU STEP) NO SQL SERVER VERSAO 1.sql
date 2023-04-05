DECLARE @String VARCHAR(100) = 'ALUNO' -- STRING PARA PESQUISAR

SELECT
    [sJOB].[name] AS [JobName] ,
    CASE [sJOB].[enabled]
        WHEN 1 THEN 'Yes'
        WHEN 0 THEN 'No'
    END AS [IsEnabled] ,
    [sJOB].[date_created] AS [JobCreatedOn] ,
    [sJOB].[date_modified] AS [JobLastModifiedOn] ,
    [sJSTP].[step_id] AS [StepNo] ,
    [sJSTP].[step_name] AS [StepName] ,
    [sDBP].[name] AS [JobOwner] ,
    [sCAT].[name] AS [JobCategory] ,
    [sJOB].[description] AS [JobDescription] ,
    CASE [sJSTP].[subsystem]
        WHEN 'ActiveScripting' THEN 'ActiveX Script'
        WHEN 'CmdExec' THEN 'Operating system (CmdExec)'
        WHEN 'PowerShell' THEN 'PowerShell'
        WHEN 'Distribution' THEN 'Replication Distributor'
        WHEN 'Merge' THEN 'Replication Merge'
        WHEN 'QueueReader' THEN 'Replication Queue Reader'
        WHEN 'Snapshot' THEN 'Replication Snapshot'
        WHEN 'LogReader' THEN 'Replication Transaction-Log Reader'
        WHEN 'ANALYSISCOMMAND' THEN 'SQL Server Analysis Services Command'
        WHEN 'ANALYSISQUERY' THEN 'SQL Server Analysis Services Query'
        WHEN 'SSIS' THEN 'SQL Server Integration Services Package'
        WHEN 'TSQL' THEN 'Transact-SQL script (T-SQL)'
        ELSE sJSTP.subsystem
    END AS [StepType] ,
    [sPROX].[name] AS [RunAs] ,
    [sJSTP].[database_name] AS [Database] ,
    [sJSTP].[command] AS [ExecutableCommand] ,
    CASE [sJSTP].[on_success_action]
        WHEN 1 THEN 'Quit the job reporting success'
        WHEN 2 THEN 'Quit the job reporting failure'
        WHEN 3 THEN 'Go to the next step'
        WHEN 4 THEN 'Go to Step: ' + QUOTENAME(CAST([sJSTP].[on_success_step_id] AS VARCHAR(3))) + ' ' + [sOSSTP].[step_name]
    END AS [OnSuccessAction] ,
    [sJSTP].[retry_attempts] AS [RetryAttempts] ,
    [sJSTP].[retry_interval] AS [RetryInterval (Minutes)] ,
    CASE [sJSTP].[on_fail_action]
        WHEN 1 THEN 'Quit the job reporting success'
        WHEN 2 THEN 'Quit the job reporting failure'
        WHEN 3 THEN 'Go to the next step'
        WHEN 4 THEN 'Go to Step: ' + QUOTENAME(CAST([sJSTP].[on_fail_step_id] AS VARCHAR(3))) + ' ' + [sOFSTP].[step_name]
    END AS [OnFailureAction],
    CASE
        WHEN [sSCH].[schedule_uid] IS NULL THEN 'No'
        ELSE 'Yes'
        END AS [IsScheduled],
    [sSCH].[name] AS [JobScheduleName],
    CASE [sJOB].[delete_level]
        WHEN 0 THEN 'Never'
        WHEN 1 THEN 'On Success'
        WHEN 2 THEN 'On Failure'
        WHEN 3 THEN 'On Completion'
        END AS [JobDeletionCriterion]
FROM
    [msdb].[dbo].[sysjobsteps] AS [sJSTP]
    INNER JOIN [msdb].[dbo].[sysjobs] AS [sJOB] ON [sJSTP].[job_id] = [sJOB].[job_id]
    LEFT JOIN [msdb].[dbo].[sysjobsteps] AS [sOSSTP] ON [sJSTP].[job_id] = [sOSSTP].[job_id] AND [sJSTP].[on_success_step_id] = [sOSSTP].[step_id]
    LEFT JOIN [msdb].[dbo].[sysjobsteps] AS [sOFSTP] ON [sJSTP].[job_id] = [sOFSTP].[job_id] AND [sJSTP].[on_fail_step_id] = [sOFSTP].[step_id]
    LEFT JOIN [msdb].[dbo].[sysproxies] AS [sPROX] ON [sJSTP].[proxy_id] = [sPROX].[proxy_id]
    LEFT JOIN [msdb].[dbo].[syscategories] AS [sCAT] ON [sJOB].[category_id] = [sCAT].[category_id]
    LEFT JOIN [msdb].[sys].[database_principals] AS [sDBP] ON [sJOB].[owner_sid] = [sDBP].[sid]
    LEFT JOIN [msdb].[dbo].[sysjobschedules] AS [sJOBSCH] ON [sJOB].[job_id] = [sJOBSCH].[job_id]
    LEFT JOIN [msdb].[dbo].[sysschedules] AS [sSCH] ON [sJOBSCH].[schedule_id] = [sSCH].[schedule_id]
WHERE
    [sJSTP].[command] LIKE '%' + @String + '%'
    OR [sJOB].[name] LIKE '%' + @String + '%'
ORDER BY
    [JobName] ,
    [StepNo]