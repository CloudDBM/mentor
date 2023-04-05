drop table #Temp
go
create table #Temp
(
	[session_id] Varchar(50)
      ,[blocked_by] Varchar(50)
      ,[login] Varchar(50)
      ,[host_name] Varchar(50)
      ,[program_name] Varchar(50)
      ,[Query] Varchar(50)
      ,[Command] Varchar(50)
      ,[database] Varchar(50)
      ,[last_wait_type] Varchar(50)
      ,[wait_time_sec] Varchar(50)
      ,[last_batch] Varchar(50)
      ,[login_time] Varchar(50)
      ,[status] Varchar(50)
      ,[cpu] Varchar(50)
      ,[capture_time] Varchar(50)
      ,[ID_log] Varchar(50)
)

Insert Into #Temp
Select TOP (10) [session_id]
      ,[blocked_by]
      ,left([login], 50)
      ,left([host_name], 50)
      ,left([program_name], 50)
      ,left([Query], 50)
      ,left([Command], 50)
      ,left([database], 50)
      ,[last_wait_type]
      ,[wait_time_sec]
      ,[last_batch]
      ,[login_time]
      ,left([status], 50)
      ,[cpu]
      ,[capture_time]
      ,[ID_log]
FROM [msdb].[dbo].[log_locks]



--select * from #Temp



EXEC msdb.dbo.sp_send_dbmail
    @profile_name = 'ProfileEnvioEmail',
    @recipients = 'vpmaciel@gmail.com',
    @query = 'SELECT TOP (10) [session_id]
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
  FROM tempdb.dbo.#Temp' ,
    @subject = 'ANEXO',
    @attach_query_result_as_file = 1,
	@query_attachment_filename = 'Results.csv',
	@query_result_separator = ';',	
	@query_no_truncate = 0,
	@query_result_no_padding = 0,
	@query_result_width = 32767
	
	