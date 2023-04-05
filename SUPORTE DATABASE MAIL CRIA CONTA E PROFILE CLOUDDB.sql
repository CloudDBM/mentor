--
-- Informar email e senha
--
-- habilita xp_cmdshell

-- To allow advanced options to be changed.  
EXECUTE sp_configure 'show advanced options', 1;  
GO  
-- To update the currently configured value for advanced options.  
RECONFIGURE;  
GO  
-- To enable the feature.  
EXECUTE sp_configure 'xp_cmdshell', 1;  
GO  
-- To update the currently configured value for this feature.  
RECONFIGURE;  
GO  

-- configura DBMail

-- Habilita o envio de emails
sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
sp_configure 'Database Mail XPs', 1;
GO
RECONFIGURE
GO

----------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------
USE [master]

DECLARE @pid INT;
DECLARE @acctid INT;

--Criar profile
IF NOT EXISTS (
	select 1 
	from msdb.dbo.sysmail_profile
	where name = 'DBA'
)
BEGIN
EXEC msdb.dbo.sysmail_add_profile_sp
  @profile_name = 'DBA',
  @profile_id = @pid OUTPUT;
END

--Criar account
IF NOT EXISTS (
	select 1 
	from msdb.dbo.sysmail_account
	where name = 'CloudDB'
)
BEGIN
EXEC msdb.dbo.sysmail_add_account_sp 
  @account_name = 'CloudDB',
  @email_address = 'clouddb.email@gmail.com',
  @display_name = 'CloudDB Email',
  @replyto_address = '',
  @mailserver_name = 'smtp.gmail.com',
  @port = 587,
  @enable_ssl = 1,
  @username =  'clouddb.email@gmail.com', 
  @password = 'etenynwdxmtkutjm',
  @account_id = @acctid OUTPUT;
END