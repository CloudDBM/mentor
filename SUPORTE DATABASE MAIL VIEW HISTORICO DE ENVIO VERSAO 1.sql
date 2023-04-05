Use msdb
go
IF OBJECT_ID('[dbo].[vwMonitoramento_Email]', 'V') IS NOT NULL
    DROP VIEW [dbo].[vwMonitoramento_Email]
GO
CREATE  VIEW  [dbo].[vwMonitoramento_Email] AS
SELECT
    A.send_request_date AS DataEnvio,
    A.sent_date AS DataEntrega,
    (CASE    
        WHEN A.sent_status = 0 THEN '0 - Aguardando envio'
        WHEN A.sent_status = 1 THEN '1 - Enviado'
        WHEN A.sent_status = 2 THEN '2 - Falhou'
        WHEN A.sent_status = 3 THEN '3 - Tentando novamente'
    END) AS Situacao,
    A.from_address AS Remetente,
    A.recipients AS Destinatario,
    A.subject AS Assunto,
    A.reply_to AS ResponderPara,
    A.body AS Mensagem,
    A.body_format AS Formato,
    A.importance AS Importancia,
    A.file_attachments AS Anexos,
    A.send_request_user AS Usuario,
    B.description AS Erro,
    B.log_date AS DataFalha
FROM 
    msdb.dbo.sysmail_mailitems                  A    WITH(NOLOCK)
    LEFT JOIN msdb.dbo.sysmail_event_log        B    WITH(NOLOCK)    ON A.mailitem_id = B.mailitem_id
GO
SELECT 
DataEnvio,
DataEntrega,
DataFalha,
Situacao,
Assunto,
Mensagem,
Formato,
Importancia,
Anexos,
Usuario,
Erro
FROM [dbo].[vwMonitoramento_Email]
ORDER BY dataEnvio desc