EXEC xp_cmdshell 'forfiles /P C:\temp\  /S /M *.bak /C "cmd /c del @path /F /Q"'



-- APAGAR ARQUIVOS QUE TENHAM MAIS DE SETE DIAS APENAS

EXEC xp_cmdshell 'forfiles -p "C:\temp" -s -m *.* /D -7 /C "cmd /c del @path /F /Q"'
