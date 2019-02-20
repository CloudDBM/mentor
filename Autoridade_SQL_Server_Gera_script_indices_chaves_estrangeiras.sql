
--Create non clustered indexes for all foreign key references in the database
DECLARE @sql nvarchar(max) 
SELECT @sql = IsNull(@sql + ';' + char(13) , '') +  'CREATE NONCLUSTERED INDEX [IX_' + tablename + '_' + columnname +'] ON ' + schema_names + '.[' + tablename + '] ( [' + columnname + '] ASC)'
FROM 
--Display the sql that will be executed
(
SELECT        o.name AS tablename, cols.name AS columnName,  sch.name as 'schema_names'
FROM sys.foreign_key_columns fc       
 inner join sys.objects o on fc.parent_object_id = o.object_id     
    inner join sys.columns cols on cols.object_id = o.object_id and fc.parent_column_id = cols.column_id  
          inner join sys.schemas sch on o.schema_id = sch.schema_id

      EXCEPT         
      SELECT o.name, cols.name ,sch.name as 'schema_names' 
      FROM sys.index_columns icols            
      inner join sys.objects o on icols.object_Id = o.object_id            
      inner join sys.columns cols on cols.object_id = o.object_id 
      inner join sys.schemas sch on o.schema_id = sch.schema_id
      and icols.column_id = cols.column_id) T


Print @sql 


--select * from sys.objects

--select * from sys.schemas