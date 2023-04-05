EXEC sp_configure 'show advanced options', 1
RECONFIGURE
GO
EXEC sp_configure 'ad hoc distributed queries', 1
RECONFIGURE
GO

INSERT INTO OPENROWSET('Microsoft.ACE.OLEDB.12.0','Text;Database=D:\TESTE;HDR=YES;FMT=Delimited','SELECT * FROM [aluno.csv]')
SELECT codigo, idade FROM DB_TESTE.dbo.aluno
-- jeito 1
exec master.dbo.xp_cmdshell 'sqlcmd -S DESKTOP-NQAADLM\MSSQLSERVER,1433 -Q "select * from DB_TESTE.dbo.aluno" –s "," –o "D:\TESTE\aluno.csv" -E';  

EXEC xp_cmdshell 'sqlcmd -S DESKTOP-NQAADLM\MSSQLSERVER -Database DB_TESTE -Query "select * from DB_TESTE.dbo.aluno" |  –o "D:\TESTE\aluno.csv" - E'

EXEC msdb.dbo.sp_send_dbmail
	@profile_name = 'ProfileEnvioEmail',
	@recipients='vpmaciel@gmail.com',
	@subject='Anexo 2',
	@body='Please find your latest report attached',
	@file_attachments='D:\TESTE\aluno.csv';

-- jeito 2
use msdb

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
  FROM [msdb].[dbo].[log_locks]' ,
    @subject = 'ANEXO',
    @attach_query_result_as_file = 1,
	@query_attachment_filename = 'Results.csv',
	@query_result_separator = ',',
	@query_result_header = 1,
	@query_no_truncate = 0,
	@query_result_no_padding = 0

