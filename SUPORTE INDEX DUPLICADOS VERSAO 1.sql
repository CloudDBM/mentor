IF OBJECT_ID('tempdb..#TableIndexDuplicado') IS NOT NULL DROP TABLE #TableIndexDuplicado;

WITH indexcols AS

 (SELECT object_id AS id,
 index_id AS indid,
 name,
  
 (SELECT CASE keyno
 WHEN 0 THEN NULL
 ELSE colid
 END AS [data()]
 FROM sys.sysindexkeys AS k
 WHERE k.id = i.object_id
 AND k.indid = i.index_id
 ORDER BY keyno,
 colid
 FOR XML PATH('') ) AS cols,

 (SELECT CASE keyno
 WHEN 0 THEN colid
 ELSE NULL
 END AS [data()]
 FROM sys.sysindexkeys AS k
 WHERE k.id = i.object_id
 AND k.indid = i.index_id
 ORDER BY colid
 FOR XML PATH('') ) AS inc
 FROM sys.indexes AS i )
SELECT DB_NAME() AS 'DBName',
 OBJECT_SCHEMA_NAME(c1.id) + '.' + OBJECT_NAME(c1.id) AS 'TableName',
c1.name + CASE c1.indid WHEN 1 THEN ' (clustered index)' ELSE ' (nonclustered index)' 
END AS 'IndexName', c2.name + CASE c2.indid
 WHEN 1 THEN ' (clustered index)'
 ELSE ' (nonclustered index)'
 END AS 'ExactDuplicatedIndexName', ('DROP INDEX [' + c1.name + '] ON [' + OBJECT_SCHEMA_NAME(c1.id) + '].[' + OBJECT_NAME(c1.id) + '];') as  'DropIndex '
INTO #TableIndexDuplicado
FROM indexcols AS c1
INNER JOIN indexcols AS c2 ON c1.id = c2.id
AND c1.indid < c2.indid
AND c1.cols = c2.cols
AND c1.inc = c2.inc;

-- Get all existing indexes, but NOT the primary keys
DECLARE @SCRIPT VARCHAR(4000)

IF OBJECT_ID('tempdb..#TableIndex') IS NOT NULL DROP TABLE #TableIndex 
--CREATE TABLE #TableIndex (DBName VARCHAR(1000),TableName VARCHAR(1000),IndexName VARCHAR(1000),ExactDuplicatedIndexName VARCHAR(1000),DropIndex VARCHAR(1000))
CREATE TABLE #TableIndex (SCRIPT NVARCHAR(4000))

DECLARE cIX CURSOR FOR
    SELECT OBJECT_NAME(SI.Object_ID), SI.Object_ID, SI.Name, SI.Index_ID
        FROM Sys.Indexes SI 
            LEFT JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS TC ON SI.Name = TC.CONSTRAINT_NAME AND OBJECT_NAME(SI.Object_ID) = TC.TABLE_NAME
        WHERE TC.CONSTRAINT_NAME IS NULL
            AND OBJECTPROPERTY(SI.Object_ID, 'IsUserTable') = 1
        ORDER BY OBJECT_NAME(SI.Object_ID), SI.Index_ID

DECLARE @IxTable SYSNAME
DECLARE @IxTableID INT
DECLARE @IxName SYSNAME
DECLARE @IxID INT

-- Loop through all indexes
OPEN cIX
FETCH NEXT FROM cIX INTO @IxTable, @IxTableID, @IxName, @IxID
WHILE (@@FETCH_STATUS = 0)
BEGIN
    DECLARE @IXSQL NVARCHAR(4000) SET @IXSQL = ''
    SET @IXSQL = 'CREATE '

    -- Check if the index is unique
    IF (INDEXPROPERTY(@IxTableID, @IxName, 'IsUnique') = 1)
        SET @IXSQL = @IXSQL + 'UNIQUE '
    -- Check if the index is clustered
    IF (INDEXPROPERTY(@IxTableID, @IxName, 'IsClustered') = 1)
        SET @IXSQL = @IXSQL + 'CLUSTERED '

    SET @IXSQL = @IXSQL + 'INDEX ' + @IxName + ' ON ' + @IxTable + '('

    -- Get all columns of the index
    DECLARE cIxColumn CURSOR FOR 
        SELECT SC.Name
        FROM Sys.Index_Columns IC
            JOIN Sys.Columns SC ON IC.Object_ID = SC.Object_ID AND IC.Column_ID = SC.Column_ID
        WHERE IC.Object_ID = @IxTableID AND Index_ID = @IxID
        ORDER BY IC.Index_Column_ID

    DECLARE @IxColumn SYSNAME
    DECLARE @IxFirstColumn BIT SET @IxFirstColumn = 1

    -- Loop throug all columns of the index and append them to the CREATE statement
    OPEN cIxColumn
    FETCH NEXT FROM cIxColumn INTO @IxColumn
    WHILE (@@FETCH_STATUS = 0)
    BEGIN
        IF (@IxFirstColumn = 1)
            SET @IxFirstColumn = 0
        ELSE
            SET @IXSQL = @IXSQL + ', '

        SET @IXSQL = @IXSQL + @IxColumn

        FETCH NEXT FROM cIxColumn INTO @IxColumn
    END
    CLOSE cIxColumn
    DEALLOCATE cIxColumn

    SET @IXSQL = @IXSQL + ')'
    -- Print out the CREATE statement for the index
    IF @IXSQL != '' BEGIN 
		PRINT @IXSQL 
		INSERT INTO #TableIndex VALUES (CAST (@IXSQL AS NVARCHAR(4000)))
	END
	
    FETCH NEXT FROM cIX INTO @IxTable, @IxTableID, @IxName, @IxID
END

CLOSE cIX
DEALLOCATE cIX

--SELECT * FROM #TableIndex
--SELECT * FROM #TableIndexDuplicado
IF OBJECT_ID('tempdb..#TableIndexBackup') IS NOT NULL DROP TABLE #TableIndexBackup;



DECLARE @INDEX VARCHAR(60)
 
-- Cursor para percorrer os registros
DECLARE cursor1 CURSOR FOR
SELECT D.[DropIndex ] FROM #TableIndexDuplicado D
 
--Abrindo Cursor
OPEN cursor1
 
-- Lendo a próxima linha
FETCH NEXT FROM cursor1 INTO @INDEX
 
-- Percorrendo linhas do cursor (enquanto houverem)
WHILE @@FETCH_STATUS = 0
BEGIN
 
-- Executando as rotinas desejadas manipulando o registro

 
-- Lendo a próxima linha
FETCH NEXT FROM cursor1 INTO @INDEX
END
 
-- Fechando Cursor para leitura
CLOSE cursor1
 
-- Finalizado o cursor
DEALLOCATE cursor1