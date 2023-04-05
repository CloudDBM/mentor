 --produto de hoje 
select @@servername cod_servidor, a.name,backup_date, 'FULL' tip_evento, GETDATE() dth_atualiza from master.dbo.sysdatabases  a (nolock)  

      left join 
            (select database_name,max(backup_finish_date) backup_date 
            from msdb.dbo.backupset (nolock) where type in ('D') 
            group by database_name)  b 
      on  a.name = b.database_name 
where a.name not in ('tempdb') 
--and backup_date is null 
AND backup_date <= getdate()-7 
OR backup_date IS NULL 
AND a.name not in ('tempdb') 
UNION 
select @@servername cod_servidor, a.name,backup_date, 'DIFF' tip_evento, GETDATE() dth_atualiza from master.dbo.sysdatabases  a (nolock)  

      left join 
            (select database_name,max(backup_finish_date) backup_date 
            from msdb.dbo.backupset (nolock) where type in ('I') 
            group by database_name)  b 
      on  a.name = b.database_name 
where a.name not in ('tempdb','MASTER','MODEL','MSDB') 
--and backup_date is null 
AND backup_date <= getdate()-1
OR backup_date IS NULL 
AND a.name not in ('tempdb','MASTER','MODEL','MSDB') 
UNION 
select @@servername cod_servidor, a.name,backup_date, 'LOG' tip_evento, GETDATE() dth_atualiza from master.dbo.sysdatabases  a (nolock)

      left join 
            (select database_name,max(backup_finish_date) backup_date 
            from msdb.dbo.backupset (nolock) where type in ('L') 
            group by database_name)  b 
      on  a.name = b.database_name 
where name not in ('tempdb','model') 
AND databasepropertyex(name, 'Recovery') = 'FULL' 
--and backup_date is null 
AND backup_date <= getdate()-1 
OR backup_date IS NULL 
AND name not in ('tempdb','model') 
AND databasepropertyex(name, 'Recovery') in ('FULL','BULK_LOGGED')
