DECLARE @data_atual DATETIME = getdate()
DECLARE @data_inicio_sql DATETIME

SELECT @data_inicio_sql = sqlserver_start_time FROM sys.dm_os_sys_info

IF ( DATEDIFF(MINUTE, @data_inicio_sql, @data_atual) < 30)
BEGIN
	EXEC msdb.dbo.sp_send_dbmail 		
	@profile_name = N'ProfileEmail',	
	@recipients = N'monitoramento@clouddbm.com',	
	@subject = 'AFYA - SERVIÇO SQL REINICIADO EM MENOS DE 30 MINUTOS',
	@body = 'AFYA - SERVIÇO SQL REINICIADO EM MENOS DE 30 MINUTOS',
    @body_format = 'TEXT'
END



