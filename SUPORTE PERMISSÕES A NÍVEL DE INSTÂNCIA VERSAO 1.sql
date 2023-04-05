SELECT
    A.class_desc AS Ds_Tipo_Permissao,
    A.state_desc AS Ds_Tipo_Operacao,
    A.[permission_name] AS Ds_Permissao,
    B.[name] AS Ds_Login,
    B.[type_desc] AS Ds_Tipo_Login
FROM 
    sys.server_permissions A
    JOIN sys.server_principals B ON A.grantee_principal_id = B.principal_id
WHERE
    B.[name] NOT LIKE '##%'
ORDER BY
    B.[name],
    A.[permission_name]