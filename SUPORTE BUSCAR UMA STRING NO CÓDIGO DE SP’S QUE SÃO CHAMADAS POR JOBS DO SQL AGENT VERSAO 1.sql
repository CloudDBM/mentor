DECLARE
    @Ds_Busca VARCHAR(200) = 'full' -- DIGITE A STRING PARA BUSCAR


IF (OBJECT_ID('tempdb..#Resultado') IS NOT NULL) DROP TABLE #Resultado
CREATE TABLE #Resultado (
    Ds_Database SYSNAME NULL,
    Ds_Objeto SYSNAME NULL,
    Ds_Schema SYSNAME NULL,
    Ds_Tipo VARCHAR(100) NULL
)
 
    
DECLARE @Query VARCHAR(MAX) = '
SELECT 
    DB_NAME(DB_ID(''?''))       AS Ds_Database,
    B.name                      AS Ds_Objeto,
    C.name                      AS Ds_Schema,
    B.type_desc                 AS Ds_Tipo
FROM 
    [?].sys.sql_modules         A   WITH(NOLOCK)
    JOIN [?].sys.objects        B   WITH(NOLOCK)    ON A.object_id = B.object_id
    JOIN [?].sys.schemas        C   WITH(NOLOCK)    ON B.schema_id = C.schema_id
WHERE
    A.definition LIKE ''%' + @Ds_Busca + '%''
'
 
 
INSERT INTO #Resultado
EXEC master.sys.sp_msforeachdb @Query
 
 
SELECT
    C.Ds_Database,
    C.Ds_Schema,
    C.Ds_Objeto,
    A.[name] AS job_name,
    A.[enabled],
    B.step_id,
    B.step_name,
    B.[database_name],
    (CASE WHEN B.last_run_date != 0 THEN msdb.dbo.agent_datetime(B.last_run_date, B.last_run_time) ELSE NULL END) AS last_run,
    REPLACE(REPLACE(REPLACE(B.[command], CHAR(10) + CHAR(13), ' '), CHAR(13), ' '), CHAR(10), ' ') AS [ExecutableCommand],
    E.[name] AS [JobScheduleName],
    CASE 
        WHEN E.[freq_type] = 64 THEN 'Start automatically when SQL Server Agent starts'
        WHEN E.[freq_type] = 128 THEN 'Start whenever the CPUs become idle'
        WHEN E.[freq_type] IN (4,8,16,32) THEN 'Recurring'
        WHEN E.[freq_type] = 1 THEN 'One Time'
    END [ScheduleType], 
    CASE E.[freq_type]
        WHEN 1 THEN 'One Time'
        WHEN 4 THEN 'Daily'
        WHEN 8 THEN 'Weekly'
        WHEN 16 THEN 'Monthly'
        WHEN 32 THEN 'Monthly - Relative to Frequency Interval'
        WHEN 64 THEN 'Start automatically when SQL Server Agent starts'
        WHEN 128 THEN 'Start whenever the CPUs become idle'
    END [Occurrence], 
    CASE E.[freq_type]
        WHEN 4 THEN 'Occurs every ' + CAST([freq_interval] AS VARCHAR(3)) + ' day(s)'
        WHEN 8 THEN 'Occurs every ' + CAST([freq_recurrence_factor] AS VARCHAR(3)) + ' week(s) on '
                + CASE WHEN E.[freq_interval] & 1 = 1 THEN 'Sunday' ELSE '' END
                + CASE WHEN E.[freq_interval] & 2 = 2 THEN ', Monday' ELSE '' END
                + CASE WHEN E.[freq_interval] & 4 = 4 THEN ', Tuesday' ELSE '' END
                + CASE WHEN E.[freq_interval] & 8 = 8 THEN ', Wednesday' ELSE '' END
                + CASE WHEN E.[freq_interval] & 16 = 16 THEN ', Thursday' ELSE '' END
                + CASE WHEN E.[freq_interval] & 32 = 32 THEN ', Friday' ELSE '' END
                + CASE WHEN E.[freq_interval] & 64 = 64 THEN ', Saturday' ELSE '' END
        WHEN 16 THEN 'Occurs on Day ' + CAST([freq_interval] AS VARCHAR(3)) + ' of every ' + CAST(E.[freq_recurrence_factor] AS VARCHAR(3)) + ' month(s)'
        WHEN 32 THEN 'Occurs on '
                    + CASE E.[freq_relative_interval]
                    WHEN 1 THEN 'First'
                    WHEN 2 THEN 'Second'
                    WHEN 4 THEN 'Third'
                    WHEN 8 THEN 'Fourth'
                    WHEN 16 THEN 'Last'
                    END
                    + ' ' 
                    + CASE E.[freq_interval]
                    WHEN 1 THEN 'Sunday'
                    WHEN 2 THEN 'Monday'
                    WHEN 3 THEN 'Tuesday'
                    WHEN 4 THEN 'Wednesday'
                    WHEN 5 THEN 'Thursday'
                    WHEN 6 THEN 'Friday'
                    WHEN 7 THEN 'Saturday'
                    WHEN 8 THEN 'Day'
                    WHEN 9 THEN 'Weekday'
                    WHEN 10 THEN 'Weekend day'
                    END
                    + ' of every ' + CAST(E.[freq_recurrence_factor] AS VARCHAR(3)) + ' month(s)'
    END AS [Recurrence], 
    CASE E.[freq_subday_type]
        WHEN 1 THEN 'Occurs once at ' + STUFF(STUFF(RIGHT('000000' + CAST(E.[active_start_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
        WHEN 2 THEN 'Occurs every ' + CAST(E.[freq_subday_interval] AS VARCHAR(3)) + ' Second(s) between ' + STUFF(STUFF(RIGHT('000000' + CAST(E.[active_start_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')+ ' & ' + STUFF(STUFF(RIGHT('000000' + CAST(E.[active_end_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
        WHEN 4 THEN 'Occurs every ' + CAST(E.[freq_subday_interval] AS VARCHAR(3)) + ' Minute(s) between ' + STUFF(STUFF(RIGHT('000000' + CAST(E.[active_start_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')+ ' & ' + STUFF(STUFF(RIGHT('000000' + CAST(E.[active_end_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
        WHEN 8 THEN 'Occurs every ' + CAST(E.[freq_subday_interval] AS VARCHAR(3)) + ' Hour(s) between ' + STUFF(STUFF(RIGHT('000000' + CAST(E.[active_start_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')+ ' & ' + STUFF(STUFF(RIGHT('000000' + CAST(E.[active_end_time] AS VARCHAR(6)), 6), 3, 0, ':'), 6, 0, ':')
    END [Frequency], 
    STUFF(STUFF(CAST(E.[active_start_date] AS VARCHAR(8)), 5, 0, '-'), 8, 0, '-') AS [ScheduleUsageStartDate], 
    STUFF(STUFF(CAST(E.[active_end_date] AS VARCHAR(8)), 5, 0, '-'), 8, 0, '-') AS [ScheduleUsageEndDate]
FROM 
    msdb.dbo.sysjobs A WITH(NOLOCK)
    JOIN msdb.dbo.sysjobsteps B WITH(NOLOCK) ON A.job_id = B.job_id
    JOIN #Resultado C ON B.command LIKE '%' + C.Ds_Objeto + '%'
    LEFT JOIN [msdb].[dbo].[sysjobschedules] AS D ON [A].[job_id] = D.[job_id]
    LEFT JOIN [msdb].[dbo].[sysschedules] AS E ON D.[schedule_id] = E.[schedule_id]
WHERE
    C.Ds_Database = B.[database_name]