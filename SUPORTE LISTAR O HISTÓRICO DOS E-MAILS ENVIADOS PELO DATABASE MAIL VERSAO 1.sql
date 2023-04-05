SELECT
    a.send_request_date AS DataEnvio,
    a.sent_date AS DataEntrega,
    (CASE    
        WHEN a.sent_status = 0 THEN '0 - Aguardando envio'
        WHEN a.sent_status = 1 THEN '1 - Enviado'
        WHEN a.sent_status = 2 THEN '2 - Falhou'
        WHEN a.sent_status = 3 THEN '3 - Tentando novamente'
    END) AS Situacao,
    a.from_address AS Remetente,
    A.recipients AS Destinatario,
    a.subject AS Assunto,
    a.reply_to AS ResponderPara,
    a.body AS Mensagem,
    a.body_format AS Formato,
    a.importance AS Importancia,
    a.file_attachments AS Anexos,
    a.send_request_user AS Usuario,
    B.description AS Erro,
    B.log_date AS DataFalha
FROM 
    msdb.dbo.sysmail_mailitems                  A    WITH(NOLOCK)
    LEFT JOIN msdb.dbo.sysmail_event_log        B    WITH(NOLOCK)    ON A.mailitem_id = B.mailitem_id