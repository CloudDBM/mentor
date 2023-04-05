--<<< RETIRE OS COMENTARIOS DA 5 E 8 LINHA >>>
--=============================================

--> 1 - DELETE A LETRA DA UNIDADE
-- exec xp_cmdshell 'net use Z: /delete'

--> 2 - RECRIE O CAMINHO DO BACKUP
-- exec xp_cmdshell 'net use Z: \\GSCSPRP03\BkpSKFSPRP01 /user:ger\user senha'

--> 3 - TESTAR
exec xp_cmdshell 'dir Z:\'