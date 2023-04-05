 USE MASTER
 DROP DATABASE DB_TESTE_SNAPSHOT
 CREATE DATABASE DB_TESTE_SNAPSHOT ON	
	( NAME=DB_TESTE, FILENAME='D:\DBA_SQL\DATABASE\SNAPSHOT\DB_TESTE.ss'),
	( NAME = DB_TESTE_LDF_01, FILENAME = 'D:\DBA_SQL\DATABASE\SNAPSHOT\DB_TESTE_LDF_01.ldf'),  
	( NAME = DB_TESTE_LDF_02, FILENAME = 'D:\DBA_SQL\DATABASE\SNAPSHOT\DB_TESTE_LDF_02.ldf')
	AS SNAPSHOT OF DB_TESTE

	use DB_TESTE
	--create table aluno (	codigo int	)

	insert into aluno values (1)
	insert into aluno values (2)
	insert into aluno values (3)

	
	USE DB_TESTE_SNAPSHOT
	select * from [dbo].[aluno]