use master
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'ProfileEnvioEmail',
    @recipients = 'vpmaciel@gmail.com',
    @query = 'SELECT TOP (1) [session_id]
      ,[blocked_by]
      ,[login]
      ,[host_name]
      ,[program_name]
      ,[Query]
      ,[Command]
      ,[database]
      ,[last_wait_type]
      ,[wait_time_sec]
      ,[last_batch]
      ,[login_time]
      ,[status]
      ,[cpu]
      ,[capture_time]
      ,[ID_log]
  FROM [msdb].[dbo].[log_locks]' ,
    @subject = 'ANEXO',
	@query_result_width = 32767,
    @attach_query_result_as_file = 1,
	@query_attachment_filename = 'Results.csv',
	@query_result_separator = ',',	
	@query_result_no_padding=1
	

