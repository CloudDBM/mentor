Description:
The script provides detailed access permission report on all levels, i.e. server, database, 
object and column, of SQL Server 2005 for all logins. Users would also be able to customize 
the report result by specifying two parameters: @loginName and @dbName at the beginning of 
the script to retrieve permission assignments on particular logins and databases. 
Reports of permissions possessed by System fixed roles, e.g. public and SQLAgentOperatorRole, 
can be excluded from the report by simply removing the comment marks on all the "type NOT IN ('R')" 
condition in the Where-clause in the script.

****************************************/
USE master
GO
SET NOCOUNT ON
DECLARE @loginName sysname, @dbName sysname

/* Set the two Parameters here. By defaul All logins and databases will be reported */
SET @loginName = '%' -- e.g. 'NorthAmerica\JSmith1'
SET @dbName = '%' -- e.g. 'ReportServer'


-- Get Server Role Level Info
SELECT 
 suser_sname(p.sid) AS Login_Name, 
 p.type_desc AS [Login_Type], 
 r.is_disabled,
 r.name AS Permission_Name, 
 r.type_desc AS Permission_Type, 
 p.create_date, p.modify_date
FROM
 master.sys.server_principals r
 LEFT OUTER JOIN master.sys.server_role_members m ON r.principal_id = m.role_principal_id
 LEFT OUTER JOIN master.sys.server_principals p ON p.principal_id = m.member_principal_id
WHERE p.name LIKE @loginName 
 --AND p.type NOT IN ('R')
UNION
SELECT 
 suser_sname(prin.sid) AS Login_Name, 
 prin.type_desc AS [Login_Type], 
 prin.is_disabled,
 perm.permission_name COLLATE SQL_Latin1_General_CP1_CI_AS AS Permission_Name, 
 perm.class_desc AS Permission_Type, 
 prin.create_date, prin.modify_date
FROM master.sys.server_permissions perm
 LEFT OUTER JOIN master.sys.server_principals prin ON perm.grantee_principal_id = prin.principal_id
 LEFT OUTER JOIN master.sys.server_principals grantor ON perm.grantor_principal_id = grantor.principal_id
WHERE prin.name LIKE @loginName 
 --AND prin.type NOT IN ('R')
ORDER BY Login_Name, r.name


-- Retrieve DB Role Level Info
DECLARE @DBRolePermissions TABLE(
 DatabaseName varchar(300), 
 Principal_Name sysname, 
 Login_Name sysname NULL, 
 DB_RoleMember varchar(300), 
 Permission_Type sysname)

INSERT INTO @DBRolePermissions
EXEC sp_MSforeachdb '
 SELECT DISTINCT ''?'' AS DatabaseName, users.Name AS UserName, suser_sname(users.sid) AS Login_Name, 
 roles.Name AS Role_Member_Name, roles.type_desc
 FROM [?].sys.database_role_members r 
 LEFT OUTER JOIN [?].sys.database_principals users on r.member_principal_id = users.principal_id
 LEFT OUTER JOIN [?].sys.database_principals roles on r.role_principal_id = roles.principal_id
 --WHERE users.type not in (''R'')'

-- Capture permissions generated FROM sys.database_permissions
INSERT INTO @DBRolePermissions
EXEC sp_msforeachdb '
 SELECT DISTINCT ''?'' AS DatabaseName, users.Name AS UserName, suser_sname(users.sid) AS Login_Name, 
 r.Permission_Name AS DB_RoleMember, r.class_desc
 FROM [?].sys.database_permissions r 
 LEFT OUTER JOIN [?].sys.database_principals users on r.Grantee_principal_id = users.principal_id
 WHERE r.class_desc = ''DATABASE'''

SELECT DISTINCT Principal_Name, Login_Name, DatabaseName, DB_RoleMember AS Permission_Name, Permission_Type
FROM @DBRolePermissions 
WHERE (ISNULL(Login_Name, '') LIKE @loginName OR ISNULL(Principal_Name, '') LIKE @loginName)
 AND DatabaseName LIKE @dbName
ORDER BY Principal_Name, DatabaseName, DB_RoleMember


-- Get Object/Column Level Permissions
DECLARE @ObjectPermissions TABLE (
 DatabaseName varchar(300), 
 Principal_Name sysname, 
 Login_Name sysname NULL, 
 ObjectType sysname, 
 ObjectName varchar(500), 
 PermissionName varchar(300), 
 state_desc varchar(300), 
 Grantor varchar(300))

DECLARE @CurrentDB sysname, @SQLCmd varchar(4000)
DECLARE DBCursor CURSOR FOR 
 SELECT [name] 
 FROM master.sys.databases 
 WHERE state = 0 AND [name] LIKE @dbName

OPEN DBCursor
FETCH NEXT FROM DBCursor INTO @CurrentDB

WHILE (@@fetch_status = 0)
BEGIN

-- Capture permissions generated FROM sys.database_permissions
SET @SQLCmd = 'USE [' + @CurrentDB + '] 
 SELECT ''' + @CurrentDB + ''' AS DatabaseName,
 grantee.name AS Principal_Name, 
 suser_sname(grantee.sid) AS Login_Name, 
 p.class_desc AS ObjectType,
 CASE p.class_desc
 WHEN ''SCHEMA'' THEN CONVERT(sysname, (SELECT objects.name FROM sys.schemas objects WHERE objects.schema_id = p.major_id)) COLLATE Latin1_General_CI_AS
 WHEN ''DATABASE'' THEN CONVERT(sysname, p.class_desc) COLLATE Latin1_General_CI_AS
 WHEN ''OBJECT_OR_COLUMN'' THEN 
 CONVERT(sysname, ISNULL((SELECT o.name + ''.'' + objects.name FROM sys.columns objects WHERE objects.[object_id] = p.major_id and objects.column_id = p.minor_id), o.name)) COLLATE Latin1_General_CI_AS

 WHEN ''DATABASE_PRINCIPAL'' THEN CONVERT(sysname, (SELECT objects.name FROM sys.database_principals objects WHERE objects.principal_id = p.major_id)) COLLATE Latin1_General_CI_AS
 WHEN ''ASSEMBLY'' THEN CONVERT(sysname, (SELECT objects.name FROM sys.assemblies objects WHERE objects.assembly_id = p.major_id)) COLLATE Latin1_General_CI_AS
 WHEN ''TYPE'' THEN CONVERT(sysname, (SELECT objects.name FROM sys.types objects WHERE objects.user_type_id = p.major_id)) COLLATE Latin1_General_CI_AS
 WHEN ''XML_SCHEMA_COLLECTION'' THEN CONVERT(sysname, (SELECT objects.name FROM sys.xml_schema_collections objects WHERE objects.xml_collection_id = p.major_id)) COLLATE Latin1_General_CI_AS
 WHEN ''MESSAGE_TYPE'' THEN CONVERT(sysname, (SELECT objects.name FROM sys.service_message_types objects WHERE objects.message_type_id = p.major_id)) COLLATE Latin1_General_CI_AS

 WHEN ''SERVICE_CONTRACT'' THEN CONVERT(sysname, (SELECT objects.name FROM sys.service_contracts objects WHERE objects.service_contract_id = p.major_id)) COLLATE Latin1_General_CI_AS
 WHEN ''REMOTE_SERVICE_BINDING'' THEN CONVERT(sysname, (SELECT distinct objects.name FROM sys.remote_service_bindings objects WHERE objects.remote_service_binding_id = p.major_id)) COLLATE Latin1_General_CI_AS
 WHEN ''ROUTE'' THEN CONVERT(sysname, (SELECT objects.name FROM sys.routes objects WHERE objects.route_id = p.major_id)) COLLATE Latin1_General_CI_AS
 WHEN ''FULLTEXT_CATALOG'' THEN CONVERT(sysname, (SELECT objects.name FROM sys.fulltext_catalogs objects WHERE objects.fulltext_catalog_id = p.major_id)) COLLATE Latin1_General_CI_AS
 WHEN ''SYMMETRIC_KEY'' THEN CONVERT(sysname, (SELECT distinct objects.name FROM sys.symmetric_keys objects WHERE objects.symmetric_key_id = p.major_id)) COLLATE Latin1_General_CI_AS
 WHEN ''CERTIFICATE'' THEN CONVERT(sysname, (SELECT distinct objects.name FROM sys.certificates objects WHERE objects.certificate_id = p.major_id)) COLLATE Latin1_General_CI_AS
 WHEN ''ASYMMETRIC_KEY'' THEN CONVERT(sysname, (SELECT objects.name FROM sys.asymmetric_keys objects WHERE objects.asymmetric_key_id = p.major_id)) COLLATE Latin1_General_CI_AS
 ELSE CONVERT(sysname, ''n\a'') COLLATE Latin1_General_CI_AS
 END AS ObjectName,
 Permission_name, state_desc, grantor.name AS Grantor
 FROM [' + @CurrentDB + '].sys.database_permissions p 
 LEFT OUTER JOIN [' + @CurrentDB + '].sys.database_principals grantee on p.grantee_principal_id = grantee.principal_id
 LEFT OUTER JOIN [' + @CurrentDB + '].sys.all_objects o on p.major_id = o.[object_id]
 LEFT OUTER JOIN [' + @CurrentDB + '].sys.database_principals grantor on p.grantor_principal_id = grantor.principal_id
 WHERE p.class_desc not in (''DATABASE'') 
 --AND grantee.type not in (''R'') '

INSERT INTO @ObjectPermissions
EXEC (@SQLCmd)

FETCH NEXT FROM DBCursor into @CurrentDB
END

CLOSE DBCursor
DEALLOCATE DBCursor


SELECT DISTINCT Principal_Name, Login_Name, DatabaseName, ObjectName, ObjectType,
 PermissionName, state_desc, Grantor
FROM @ObjectPermissions 
WHERE ISNULL(Login_Name, '') like @loginName OR ISNULL(Principal_Name, '') like @loginName
ORDER BY DatabaseName, Principal_Name, ObjectName, PermissionName