SELECT t.name AS tablename, c.name AS columnname

FROM sys.tables AS t

INNER JOIN sys.columns AS c ON t.object_id = c.object_id

ORDER BY tablename, columnname