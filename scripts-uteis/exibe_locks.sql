-- Exibe os locks

SELECT TOP (1000) [session_id] "ID Bloqueado"
      ,[blocked_by] "ID Bloqueando"
      ,[login] "Login"
      ,[host_name] "Host"
      ,[wait_time_sec] "Tempo de espera"
	  ,[program_name] "Programa"
      ,[Query] "Query"
      ,[Command] "Comando"
      ,[database] "Banco"
      ,[capture_time] "Data e hora de captura"
	  ,[last_batch] "Data e hora que rodou por último"
      ,[login_time] "Data e hora de login"
      ,[status] "Status"
	  ,[cpu] "CPU"
	  ,[last_wait_type] "Último tipo de espera" 
      ,[ID_log] "ID Log"
	  
  FROM msdb.[dbo].[log_locks]
 -- where [wait_time_sec] > 10 
 order by capture_time des