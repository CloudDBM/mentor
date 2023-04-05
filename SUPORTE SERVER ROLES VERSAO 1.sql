SELECT 
    B.[name] AS Ds_Usuario,
    C.[name] AS Ds_Server_Role
FROM 
    sys.server_role_members A
    JOIN sys.server_principals B ON A.member_principal_id = B.principal_id
    JOIN sys.server_principals C ON A.role_principal_id = C.principal_id