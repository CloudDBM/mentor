SELECT
    A.class_desc AS Ds_Tipo_Permissao, 
    A.[permission_name] AS Ds_Permissao,
    A.state_desc AS Ds_Operacao,
    B.[name] AS Ds_Usuario_Permissao,
    C.[name] AS Ds_Login_Permissao,
    D.[name] AS Ds_Objeto
FROM 
    sys.database_permissions A
    JOIN sys.database_principals B ON A.grantee_principal_id = B.principal_id
    LEFT JOIN sys.server_principals C ON B.[sid] = C.[sid]
    LEFT JOIN sys.objects D ON A.major_id = D.[object_id]
WHERE
    A.major_id >= 0