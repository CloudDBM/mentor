/****** Script for SelectTopNRows command from SSMS  ******/
SELECT TOP (1000) [NOME]
      ,LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(CAST(NOME AS VARCHAR(MAX)), CHAR(9), ''), CHAR(10), ''), CHAR(13), ''))) as NOME
  FROM [TESTE].[dbo].[ALUNO]