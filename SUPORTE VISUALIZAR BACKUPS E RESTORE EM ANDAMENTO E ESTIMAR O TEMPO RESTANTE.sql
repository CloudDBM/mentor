SELECT
    R.session_id,
    R.command AS Ds_Operacao,
    B.name AS Nm_Banco,
    R.start_time AS Dt_Inicio,
    CONVERT(VARCHAR(20), DATEADD(MS, R.estimated_completion_time, GETDATE()), 20) AS Dt_Previsao_Fim,
    CONVERT(NUMERIC(6, 2), R.percent_complete) AS Vl_Percentual_Concluido,
    CONVERT(NUMERIC(6, 2), R.total_elapsed_time / 1000.0 / 60.0) AS Qt_Minutos_Execucao,
    CONVERT(NUMERIC(6, 2), R.estimated_completion_time / 1000.0 / 60.0) AS Qt_Minutos_Restantes,
    CONVERT(NUMERIC(6, 2), R.estimated_completion_time / 1000.0 / 60.0 / 60.0) AS Qt_Horas_Restantes,
    CONVERT(VARCHAR(MAX), ( SELECT
                                SUBSTRING(text, R.statement_start_offset / 2, CASE WHEN R.statement_end_offset = -1 THEN 1000 ELSE ( R.statement_end_offset - R.statement_start_offset ) / 2 END)
                            FROM
                                sys.dm_exec_sql_text(sql_handle)
                            )) AS Ds_Comando
FROM
    sys.dm_exec_requests	R	WITH(NOLOCK)
    JOIN sys.databases		B	WITH(NOLOCK)	 ON R.database_id = B.database_id
WHERE
    R.command IN ( 
        'BACKUP DATABASE', 
        'RESTORE DATABASE', 
        'ALTER INDEX REORGANIZE', 
        'AUTO_SHRINK option with ALTER DATABASE', 
        'CREATE INDEX',
        'DBCC CHECKDB',
        'DBCC CHECKFILEGROUP',
        'DBCC CHECKTABLE',
        'DBCC INDEXDEFRAG',
        'DBCC SHRINKDATABASE',
        'DBCC SHRINKFILE',
        'KILL',
        'UPDATE STATISTICS',
        'DBCC'
    )
    AND R.estimated_completion_time > 0 