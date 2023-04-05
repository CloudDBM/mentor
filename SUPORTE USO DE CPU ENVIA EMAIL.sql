DECLARE @ts_now BIGINT

IF OBJECT_ID(N'tempdb..##USO_CPU') IS NOT NULL
	DROP TABLE ##USO_CPU

CREATE TABLE ##USO_CPU(
	record_id INT,
	hora DATETIME,
	uso_sql INT,
	idle INT,
	uso_outros INT
)


SELECT @ts_now = cpu_ticks / CONVERT(FLOAT, ms_ticks) FROM sys.dm_os_sys_info

INSERT INTO ##USO_CPU
	SELECT TOP 
		15 record_id,
		DATEADD(ms, -1 * (@ts_now - [timestamp]), GETDATE()) AS EventTime,
		SQLProcessUtilization,
		SystemIdle,
		100 - SystemIdle - SQLProcessUtilization AS OtherProcessUtilization
	FROM (
		SELECT
			record.value('(./Record/@id)[1]', 'int') AS record_id,
			record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
			record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
			TIMESTAMP
		FROM (
			SELECT 
				TIMESTAMP, CONVERT(XML, record) AS record 
			FROM
				sys.dm_os_ring_buffers 
			WHERE 
				ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR' AND record LIKE '% %'
		) AS x
	) AS y

DECLARE @uso_sql INT
DECLARE @uso_outros INT

DECLARE C CURSOR FOR
SELECT
	uso_sql,
	uso_outros	
FROM ##USO_CPU
OPEN C
FETCH NEXT FROM C INTO @uso_sql, @uso_outros

	WHILE @@fetch_status <> -1

	BEGIN		
		IF (( @uso_outros + @uso_sql) > 90)
		BEGIN
		EXEC msdb.dbo.sp_send_dbmail 
				@recipients='monitoramento@clouddbm.com',
				@subject = '<DIRECIONAL> USO TOTAL DE CPU MAIOR QUE 90%',				
				@body = '<DIRECIONAL> USO TOTAL DE CPU MAIOR QUE 90%';
		END
		
		FETCH NEXT FROM C INTO @uso_sql, @uso_outros
	END
CLOSE C
DEALLOCATE C