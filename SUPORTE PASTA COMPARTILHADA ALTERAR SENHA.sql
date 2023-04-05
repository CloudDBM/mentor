3 – Identifique novo caminho de backup no servidor de desti o, abra nova query, entre com script abaixo com alteração do novo caminho, inserindo uma letra a qual será alguma aleatória, neste caso abaixo, (p) e execute como teste

(exec xp_cmdshell 'net use P: \\gscsprp03\BkpSKFSPRP01  /user:gerdau\exgjunio Cloud@23'')
Teste = exec xp_cmdshell 'dir P:'
Para caso for remover letra = exec xp_cmdshell 'net use z: /delete'