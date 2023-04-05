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