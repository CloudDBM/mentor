-- Para limpar o TempDB sem reiniciar o serviço do SQL Server, você pode executar o seguinte script no Management Studio:
USE TempDB;
GO
DBCC FREEPROCCACHE;
GO
DBCC DROPCLEANBUFFERS;
GO
