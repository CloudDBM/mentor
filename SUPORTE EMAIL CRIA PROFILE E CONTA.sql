sp_configure 'Database Mail XPs', 1;
GO
RECONFIGURE
GO
sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
 
sp_configure 'Database Mail XPs', 1;
GO
RECONFIGURE
GO
-- Create a Database Mail profile  
EXECUTE msdb.dbo.sysmail_add_profile_sp  
    @profile_name = 'DBA',  
    @description = 'Profile used for sending outgoing DBA using Gmail.' ;  
GO

-- Grant access to the profile to the DBMailUsers role  
EXECUTE msdb.dbo.sysmail_add_principalprofile_sp  
    @profile_name = 'DBA',  
    @principal_name = 'public',  
    @is_default = 1 ;
GO
 
sp_configure 'Database Mail XPs', 1;
GO
RECONFIGURE
GO
 
sp_configure 'show advanced options', 1;
GO
RECONFIGURE;
GO
 
sp_configure 'Database Mail XPs', 1;
GO
RECONFIGURE
GO


-- Create a Database Mail profile  
EXECUTE msdb.dbo.sysmail_add_profile_sp  
    @profile_name = 'DBA',  
    @description = 'Profile used for sending outgoing DBA using Gmail.' ;  
GO


-- Grant access to the profile to the DBMailUsers role  
EXECUTE msdb.dbo.sysmail_add_principalprofile_sp  
    @profile_name = 'DBA',  
    @principal_name = 'public',  
    @is_default = 1 ;
GO


-- Create a Database Mail account  
EXECUTE msdb.dbo.sysmail_add_account_sp  
    @account_name = 'Gmail',  
    @description = 'Conta de email do Gmail.',  
    @email_address = 'clouddb.email@gmail.com',  
    @display_name = 'CloudDB Email',  
    @mailserver_name = 'smtp.gmail.com',
    @port = 587,
    @enable_ssl = 1,
    @username = 'clouddb.email@gmail.com',
    @password = 'etenynwdxmtkutjm' ;  
GO
-- Add the account to the profile  
EXECUTE msdb.dbo.sysmail_add_profileaccount_sp  
    @profile_name = 'DBA',  
    @account_name = 'Gmail',  
    @sequence_number =1 ;  
GO