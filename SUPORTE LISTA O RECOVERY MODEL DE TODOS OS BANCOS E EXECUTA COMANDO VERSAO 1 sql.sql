USE MASTER


declare

 @isql varchar(2000),

 @dbname varchar(128),

 @logfile varchar(128) declare c1 cursor for


SELECT name AS [Nome_Banco] FROM sys.databases
where recovery_model_desc <> 'SIMPLE' and name not in ('master','model','msdb','tempdb')

 open c1

 fetch next from c1 into @dbname

 While @@fetch_status <> -1

  begin

  select @isql = 'exec spu_backup_log_noinit ' + @dbname

  print @isql

  --exec (@isql)


  fetch next from c1 into @dbname

  end

 close c1

 deallocate c1