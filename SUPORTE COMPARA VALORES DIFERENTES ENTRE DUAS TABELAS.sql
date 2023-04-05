USE DBManager

--SELECT * INTO [monitora_email] FROM [msdb].[dbo].[sysmail_server]
--SELECT * FROM [dbo].[monitora_email]

SELECT 
	'sysmail_server' AS [table],
	ss.[servertype],
    ss.[servername],
	ss.[account_id],
    ss.[servertype],
    ss.[port],
    ss.[username],
    ss.[credential_id],
    ss.[use_default_credentials],
    ss.[enable_ssl],
    ss.[flags],
    ss.[timeout],
    ss.[last_mod_datetime],
    ss.[last_mod_user] 
FROM [msdb].[dbo].[sysmail_server] ss
LEFT JOIN
    [dbo].[monitora_email] AS me ON ( me.[account_id] = ss.[account_id] )
WHERE
    ( me.[account_id] = ss.[account_id] )
	AND (ss.[servertype] <> me.[servertype]
	OR ss.[servername] <> me.[servername]
	OR ss.[servertype] <> me.[servertype]
	OR ss.[port] <> me.[port]
	OR ss.[username] <> me.[username]
	OR ss.[credential_id] <> me.[credential_id]
	OR ss.[use_default_credentials] <> me.[use_default_credentials]
	OR ss.[enable_ssl] <> me.[enable_ssl]
	OR ss.[flags] <> me.[flags]
	OR ss.[timeout] <> me.[timeout]
	OR ss.[last_mod_datetime] <> me.[last_mod_datetime]
	OR ss.[last_mod_user] <> me.[last_mod_user]
	)

UNION
SELECT DISTINCT
  'monitora_email' AS [table],
   me.[servertype],
   me.[servername],
   me.[account_id],
   me.[servertype],
   me.[port],
   me.[username],
   me.[credential_id],
   me.[use_default_credentials],
   me.[enable_ssl],
   me.[flags],
   me.[timeout],
   me.[last_mod_datetime],
   me.[last_mod_user] 

FROM
    [monitora_email] AS me
LEFT JOIN
    [msdb].[dbo].[sysmail_server] AS ss ON ( me.[account_id] = ss.[account_id] )
WHERE
    ( me.[account_id] = ss.[account_id] )
	AND (ss.[servertype] <> me.[servertype]
	OR ss.[servername] <> me.[servername]
	OR ss.[servertype] <> me.[servertype]
	OR ss.[port] <> me.[port]
	OR ss.[username] <> me.[username]
	OR ss.[credential_id] <> me.[credential_id]
	OR ss.[use_default_credentials] <> me.[use_default_credentials]
	OR ss.[enable_ssl] <> me.[enable_ssl]
	OR ss.[flags] <> me.[flags]
	OR ss.[timeout] <> me.[timeout]
	OR ss.[last_mod_datetime] <> me.[last_mod_datetime]
	OR ss.[last_mod_user] <> me.[last_mod_user]
	)


DECLARE @TOTAL_ME INT, @TOTALSS INT
SELECT @TOTAL_ME = count(account_id) FROM [dbo].[monitora_email] 
SELECT @TOTALSS = count(account_id) FROM [msdb].[dbo].[sysmail_server]
print @TOTAL_ME
print @TOTALSS
IF (@TOTAL_ME <> @TOTALSS)
BEGIN
EXEC msdb.dbo.sp_send_dbmail 
	--@recipients='monitoramento@clouddbm.com',
	@recipients='vpmaciel@gmail.com',
	@subject = '<Cliente> - Alterado parâmetros do database mail no Servidor'
END