--Gerar scripts de backup de bancos de forma automatizada
select 'backup database ' + name + ' to disk = ''C:\Temp\' + name + '.bak'' with copy_only,stats=1' 
from sysdatabases 

-- Opção de filtrar por nome de alguns bancos apenas
where name in ('NOMEBANCO1',
'NOMEBANCO2','NOMEBANCO3')