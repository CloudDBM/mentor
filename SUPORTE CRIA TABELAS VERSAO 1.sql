DECLARE @DatabaseName VARCHAR(100)
DECLARE @TableName VARCHAR(100)
DECLARE @SQLCommand NVARCHAR(MAX)

DECLARE DatabaseCursor CURSOR FOR
SELECT name
FROM sys.databases
WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb') -- Seleciona todos os bancos de dados, exceto os bancos de dados do sistema

OPEN DatabaseCursor
FETCH NEXT FROM DatabaseCursor INTO @DatabaseName

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQLCommand = 'USE ' + QUOTENAME(@DatabaseName) + '; ' + CHAR(13) + CHAR(10) -- Cria um comando USE para o banco de dados atual
    SET @SQLCommand += 'SELECT name FROM sys.tables;' -- Cria um comando SELECT para selecionar o nome de cada tabela no banco de dados atual
    PRINT 'Tabelas no banco de dados ' + @DatabaseName + ':' -- Imprime o nome do banco de dados atual
    EXEC sp_executesql @SQLCommand -- Executa o comando USE e SELECT
    FETCH NEXT FROM DatabaseCursor INTO @DatabaseName
END

CLOSE DatabaseCursor
DEALLOCATE DatabaseCursor
