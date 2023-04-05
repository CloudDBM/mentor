-- limpa fila DBMail com status "failed"

EXECUTE msdb.dbo.sysmail_delete_mailitems_sp   
    @sent_status = 'failed' ;  
GO

-- limpa fila toda do DBMail

DECLARE @GETDATE datetime  
SET @GETDATE = GETDATE();  
EXECUTE msdb.dbo.sysmail_delete_mailitems_sp @sent_before = @GETDATE;  
GO

-- consulta fila DBMail

EXECUTE msdb.dbo.sysmail_help_queue_sp ;  
GO

-- limpa log DBMail

EXECUTE msdb.dbo.sysmail_delete_log_sp ;  
GO