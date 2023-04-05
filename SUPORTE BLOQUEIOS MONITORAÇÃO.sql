sp_quem
dbcc opentran
SP_OPERADOR
DECLARE @VALOR VARCHAR(4)
SET @VALOR = '1001'
EXEC sp_who2 @VALOR
GO
dbcc inputbuffer (@VALOR)