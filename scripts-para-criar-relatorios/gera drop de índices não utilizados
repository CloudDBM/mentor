select SCHEMA_NAME(tbl.schema_id) as [Schema Name],
OBJECT_NAME(us.object_id) as [Table Name],
 'DROP INDEX '+i.name + ' ON  [' + SCHEMA_NAME(tbl.schema_id)+'].['+ OBJECT_NAME(us.object_id)+ ']' as [Drop Index Script],
 us.last_user_seek [Last Seek Time],
 us.user_seeks [Seek Count],
 CASE us.user_seeks WHEN 0 THEN 0
 ELSE us.user_seeks*1.0 /(us.user_scans + us.user_seeks) * 100.0 END AS [Percent Of Seek],
 us.last_user_scan [Last Scan Time],
 us.user_scans [Scan Count],
 CASE us.user_scans WHEN 0 THEN 0
 ELSE us.user_scans*1.0 /(us.user_scans + us.user_seeks) * 100.0 END AS [Percent Of Scan],
 us.last_user_update [Last Update Time], --If the table is being used, this column will up to date. But this does not means the index is used.
 us.user_updates [Update Count]
FROM sys.dm_db_index_usage_stats us
INNER JOIN sys.indexes i ON i.object_id=us.object_id and i.index_id = us.index_id 
INNER JOIN sys.tables tbl ON tbl.object_id=us.object_id
WHERE us.database_id = DB_ID('Zelo') 
AND us.user_seeks=0 
AND us.user_scans=0 
AND i.is_primary_key = 0 -- To not return the Primary Key as a result. Even if it is not used, its presence is needed.
AND i.is_unique = 0      -- To not return the Unique Indexes as a result. Even if it is not used, its presence may be needed.
AND i.is_disabled=0      -- To not return the Disable Indexes as a result. Disable indexes can be deleted because they are not used.
and  us.user_updates > 1000
