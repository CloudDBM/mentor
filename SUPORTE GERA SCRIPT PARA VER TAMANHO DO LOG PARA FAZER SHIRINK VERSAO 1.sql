USE master

DECLARE @dbName varchar(30), @cmd varchar(1000), @Indice Int
DECLARE @TAMANHO VARCHAR(2)
DECLARE @CALCULO VARCHAR(255)

SET @TAMANHO = 'MB' -- DIGITE AQUI GB OU MB PARA A UNIDADE DE MEDIDA USADA

IF (@TAMANHO = 'GB')
SET @CALCULO = '(CAST((size) / 1048576 AS DECIMAL(10,2)))'
ELSE
SET @CALCULO = '((size*8)/1024)'


DECLARE cur_SpaceUsed CURSOR FOR


SELECT name FROM SYS.DATABASES

WHERE  name NOT IN ('master', 'msdb', 'model', 'tempdb')

and    state_desc  = 'ONLINE'

OPEN cur_SpaceUsed

FETCH NEXT FROM cur_SpaceUsed

INTO @dbName

WHILE @@FETCH_STATUS = 0

BEGIN

         SELECT @cmd =  'SET NOCOUNT ON' + char(10) +
         'USE ' + @dbName + '' + char(10) +
         'Go' + char(10) +
         'DECLARE @Indice Int' + char(10) +
         'SELECT @Indice = SUM(reserved) FROM ' + @dbName +
'..
SYSINDEXES WHERE indid IN (0, 1, 255)' + Char(10) +
         'SELECT DB_NAME() AS "DB Name", (CAST(name AS VARCHAR(30))) 
AS name, ''total ' + @TAMANHO +''' = 
 ' + @CALCULO +
' FROM sysfiles
'

Print @cmd

FETCH NEXT FROM cur_SpaceUsed

INTO @dbName

END

CLOSE cur_SpaceUsed

DEALLOCATE cur_SpaceUsed