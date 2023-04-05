SELECT

SERVERPROPERTY('Servername') AS 'Servidor',

msdb.dbo.backupset.database_name As 'Database',

CASE msdb..backupset.type

WHEN 'D' THEN 'Database'

WHEN 'L' THEN 'Log'

WHEN 'I' THEN 'Diferencial'

WHEN 'F' THEN 'File ou Filegroup'

WHEN 'G' THEN 'Diferencial Arquivo'

WHEN 'P' THEN 'Parcial'

WHEN 'Q' THEN 'Diferencial Parcial'

END AS 'Tipo do Backup',

msdb.dbo.backupset.backup_start_date As 'Data Execucao',

msdb.dbo.backupset.backup_finish_date As 'Data Encerramento',

msdb.dbo.backupset.expiration_date As 'Data de Validade', 

msdb.dbo.backupset.user_name As 'Usuario', 

msdb.dbo.backupset.machine_name As 'Nome da Maquina',

(msdb.dbo.backupset.backup_size / 1024) As 'Tamanho do  Backup em MBs',

msdb.dbo.backupmediafamily.logical_device_name As 'Dispositivo ou Local de Backup',

msdb.dbo.backupmediafamily.physical_device_name As 'Caminho do Arquivo',

msdb.dbo.backupset.description As 'Descricao',

Case msdb.dbo.backupset.compatibility_level

When 80 Then 'SQL Server 2000'

When 90 Then 'SQL Server 2005'

When 100 Then 'SQL Server 2008 ou SQL Server 2008 R2'

When 110 Then 'SQL Server 2012'

When 120 Then 'SQL Server 2014'

When 130 Then 'SQL Server 2016'

When 140 Then 'SQL Server 2017'

When 150 Then 'SQL Server 2019'

When 160 Then 'SQL Server 2022'

End As 'Nvel de Compatibilidade',

msdb.dbo.backupset.name AS 'Backup Set'

FROM

msdb.dbo.backupmediafamily INNER JOIN msdb.dbo.backupset

ON msdb.dbo.backupmediafamily.media_set_id = msdb.dbo.backupset.media_set_id

WHERE

(CONVERT(datetime, msdb.dbo.backupset.backup_start_date, 103) >= GETDATE() - 15)

ORDER

BY msdb.dbo.backupset.database_name, msdb.dbo.backupset.backup_finish_date desc