-- SQL Server - SP Sentinela com intervalo de tempo 

-- Esse script criar uma procedure que permite matar os processos que estão causando bloqueios acima do tempo estipulado como parâmetro informado.
-- Eventos que tenham bloqueios com tempo menor do que o informado não serão mortos a não ser que estejam dentro do tempo padrão.


-- Procedure sp_sentinela_param que permite colocarmos na frente dela ao a chamarmos um número de quantos minutos seria o limite de bloqueio para matar o causador. 

-- Exemplo: Para matar processos bloqueados acima de 5 minutos
-- EXEC dbmanager.dbo.sp_sentinela_param 5



USE [A]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE   PROCEDURE [dbo].[sp_sentinela_param] 
    @Minutos INT = 10 -- Parâmetro de entrada (o padrão é 10 caso não seja informado)
AS 
BEGIN
    SET NOCOUNT ON;

    -- Converte o tempo informado em minutos para milissegundos (waittime usa ms)
    DECLARE @WaitTimeMs INT = @Minutos * 60 * 1000;
    
    DECLARE @DatabaseName NVARCHAR(50);
    SET @DatabaseName = DB_NAME();
    
    DECLARE @SQL VARCHAR(MAX);
    SET @SQL = '';

    -- Monta a string com os comandos KILL
    SELECT @SQL = @SQL + 'KILL ' + CONVERT(VARCHAR, SPId) + ';'
    FROM master.dbo.sysprocesses
    WHERE SPId <> @@SPId
      AND spid IN (
          SELECT blocked 
          FROM master.dbo.sysprocesses 
          WHERE waittime > @WaitTimeMs
            AND blocked > 0 -- Filtro de segurança: garante que existe de fato um bloqueio
      );

    -- Mostra os processos que serão mortos (útil para debug)
    SELECT @SQL AS Comandos_Kill;

    -- Só tenta executar se encontrou algum processo
    IF LEN(@SQL) > 0
    BEGIN
        EXEC(@SQL);
    END
    ELSE
    BEGIN
        PRINT 'Nenhum processo bloqueando acima do tempo estipulado.';
    END
END
GO


