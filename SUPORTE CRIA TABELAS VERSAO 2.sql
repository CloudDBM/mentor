DECLARE @DatabaseName VARCHAR(MAX)
DECLARE @TableName VARCHAR(MAX)
DECLARE @SQLCommand NVARCHAR(MAX)

DECLARE @@sql_table VARCHAR(MAX)


DECLARE DatabaseCursor CURSOR FOR
SELECT name
FROM sys.databases
WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb') -- Seleciona todos os bancos de dados, exceto os bancos de dados do sistema

OPEN DatabaseCursor
FETCH NEXT FROM DatabaseCursor INTO @DatabaseName

WHILE @@FETCH_STATUS = 0
BEGIN
	DECLARE @@table_name VARCHAR(MAX)	
    SET @SQLCommand = 'USE ' + QUOTENAME(@DatabaseName) + '; ' + CHAR(13) + CHAR(10) -- Cria um comando USE para o banco de dados atual
    SET @SQLCommand += 'SELECT name FROM sys.tables;' -- Cria um comando SELECT para selecionar o nome de cada tabela no banco de dados atual
    -- PRINT 'Tabelas no banco de dados ' + @DatabaseName + ':' -- Imprime o nome do banco de dados atual
    EXEC sp_executesql @SQLCommand -- Executa o comando USE e SELECT
	
	SET @@sql_table = 'CREATE TABLE ' + @@table_name + ' ('

		SELECT @@sql_table = @@sql_table + 
			COLUMN_NAME + ' ' + 
			DATA_TYPE + 
			CASE 
				WHEN CHARACTER_MAXIMUM_LENGTH IS NULL THEN ''
				ELSE '(' + CAST(CHARACTER_MAXIMUM_LENGTH AS VARCHAR(5)) + ')'
			END + ' ' +
			CASE 
				WHEN IS_NULLABLE = 'No' THEN 'NOT NULL'
				ELSE 'NULL'
			END + ','
		FROM INFORMATION_SCHEMA.COLUMNS
		WHERE TABLE_NAME = @@table_name
		ORDER BY ORDINAL_POSITION

		SET @@sql_table = LEFT(@@sql_table, LEN(@@sql_table) - 1) + ')'

		PRINT @@sql_table

    FETCH NEXT FROM DatabaseCursor INTO @DatabaseName
END

CLOSE DatabaseCursor
DEALLOCATE DatabaseCursor
