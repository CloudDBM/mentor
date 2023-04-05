SELECT
    B.[name] + '.' + A.[name] AS table_name
FROM
    sys.tables A
    JOIN sys.schemas B ON A.[schema_id] = B.[schema_id]
    JOIN sys.indexes C ON A.[object_id] = C.[object_id]
WHERE
    C.[type] = 0 -- = Heap 
ORDER BY
    table_name