IF OBJECT_ID(N'tempdb..##INFORMACOES') IS NOT NULL
DROP TABLE ##INFORMACOES

CREATE TABLE ##INFORMACOES(
JOB_ID VARCHAR(500)
)

DECLARE @JOB_ID AS VARCHAR(500)
DECLARE @JOB_NAME AS VARCHAR(500)
DECLARE @SAIDA AS VARCHAR(MAX)

SET @SAIDA = 'USE [master]' + CHAR(13) + CHAR(10)
SET @SAIDA = @SAIDA + 'GO' + CHAR(13) + CHAR(10)

INSERT INTO ##INFORMACOES
SELECT A.job_id [Job ID] FROM msdb.dbo.sysjobs A  WHERE [name] LIKE '%%' GROUP BY A.job_id, A.[name]  -- TESTE DE FILTRO NO LIKE

DECLARE SQL_CURSOR CURSOR FOR
	SELECT JOB_ID FROM ##INFORMACOES
	OPEN SQL_CURSOR

	FETCH NEXT FROM SQL_CURSOR INTO @JOB_ID

	WHILE @@fetch_status <> -1

	BEGIN
		SET @SAIDA = @SAIDA + 'EXEC msdb.dbo.sp_update_job @job_id=N''' + @JOB_ID + '''' +  CHAR(13) + CHAR(10)
		SET @SAIDA = @SAIDA + '@notify_level_email=1, @notify_level_page=2, @notify_email_operator_name=N''DBA''' + CHAR(13) + CHAR(10)
		SET @SAIDA = @SAIDA + 'GO' + CHAR(13) + CHAR(10)
		SET @SAIDA = @SAIDA + 'EXEC msdb.dbo.sp_attach_schedule @job_id=N''' + @JOB_ID + ',@schedule_id=16'
		FETCH NEXT FROM SQL_CURSOR INTO @JOB_ID
		SET @SAIDA = @SAIDA + 'GO' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
	END

CLOSE SQL_CURSOR

DEALLOCATE SQL_CURSOR

PRINT @SAIDA

USE [msdb]
GO
EXEC msdb.dbo.sp_update_job @job_id=N'03f4c14f-204e-4abd-865e-d4dcf04687ab', 
		@notify_level_email=1, 
		@notify_level_page=2, 
		@notify_email_operator_name=N'DBA'
GO
EXEC msdb.dbo.sp_attach_schedule @job_id=N'03f4c14f-204e-4abd-865e-d4dcf04687ab',@schedule_id=16
GO
