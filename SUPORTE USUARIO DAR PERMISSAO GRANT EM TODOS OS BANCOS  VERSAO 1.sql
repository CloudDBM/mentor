DECLARE @dbName varchar(30), @cmd varchar(1000), @Indice Int

DECLARE cur_SpaceUsed CURSOR FOR

SELECT name FROM SYSDATABASES

WHERE  name NOT IN ('master', 'msdb', 'model', 'tempdb')

OPEN cur_SpaceUsed

FETCH NEXT FROM cur_SpaceUsed

INTO @dbName

WHILE @@FETCH_STATUS = 0

BEGIN

         EXEC ('use ' + @dbName)
		 EXEC ('GRANT VIEW DEFINITION TO [paulo]')
		 EXEC ('GRANT EXEC TO [paulo]')
		 
FETCH NEXT FROM cur_SpaceUsed

INTO @dbName

END

CLOSE cur_SpaceUsed

DEALLOCATE cur_SpaceUsed