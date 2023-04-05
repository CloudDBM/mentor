EXEC msdb.dbo.sp_send_dbmail 
@recipients='vpmaciel@gmail.com;monitoramento@clouddbm.com',  
@subject = 'Enviando email sem profile',  
@body = 'Enviando email sem profile',  
@body_format = 'HTML' ;