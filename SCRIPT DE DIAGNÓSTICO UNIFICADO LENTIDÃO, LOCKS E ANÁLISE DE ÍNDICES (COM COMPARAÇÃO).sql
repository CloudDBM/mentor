-- ========================================================================================
-- SCRIPT DE DIAGNÓSTICO UNIFICADO: LENTIDÃO, LOCKS E ANÁLISE DE ÍNDICES (COM COMPARAÇÃO)
-- ========================================================================================

SET NOCOUNT ON;

PRINT '==================================================================================='
PRINT ' [1] ANALISANDO BLOQUEIOS (LOCKS) ATIVOS NO MOMENTO'
PRINT '==================================================================================='
SELECT 
    'ALERTA DE LOCK' AS StatusMonitoramento,
    r.blocking_session_id AS SessaoBloqueadora,
    r.session_id AS SessaoBloqueada,
    r.wait_type AS TipoEspera,
    r.wait_time AS TempoEspera_ms,
    r.wait_resource AS RecursoAguardado,
    st.text AS ConsultaBloqueada
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
WHERE r.blocking_session_id <> 0;

PRINT '==================================================================================='
PRINT ' [2] MAPEANDO AS 10 CONSULTAS MAIS LENTAS (HISTÓRICO DO CACHE)'
PRINT '==================================================================================='
SELECT TOP 10
    'CONSULTA LENTA' AS StatusMonitoramento,
    (qs.total_elapsed_time / qs.execution_count) / 1000.0 AS TempoMedio_ms,
    qs.execution_count AS QuantidadeExecucoes,
    SUBSTRING(st.text, (qs.statement_start_offset/2) + 1,
    ((CASE statement_end_offset 
        WHEN -1 THEN DATALENGTH(st.text)
        ELSE qs.statement_end_offset END 
            - qs.statement_start_offset)/2) + 1) AS TrechoConsultaLenta
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY (qs.total_elapsed_time / qs.execution_count) DESC;

PRINT '==================================================================================='
PRINT ' [3] DIAGNÓSTICO DE AUSÊNCIA DE ÍNDICES (COM VERIFICAÇÃO DE EXISTENTES)'
PRINT '==================================================================================='
SELECT TOP 10
    'ÍNDICE AUSENTE' AS StatusMonitoramento,
    ROUND(migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans), 0) AS ImpactoEstimado,
    mid.statement AS Tabela,
    ISNULL(mid.equality_columns, '') + 
        CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ', ' ELSE '' END + 
        ISNULL(mid.inequality_columns, '') AS ColunasChaveSugeridas,
    ISNULL(mid.included_columns, 'NENHUMA') AS ColunasIncludeSugeridas,
    -- Subconsulta para listar os índices atuais e suas colunas chave para comparação
    ISNULL(STUFF((
        SELECT ' | ' + i.name + ' [' + 
            STUFF((
                SELECT ', ' + COL_NAME(ic.object_id, ic.column_id)
                FROM sys.index_columns ic
                WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
                ORDER BY ic.key_ordinal
                FOR XML PATH('')
            ), 1, 2, '') + ']'
        FROM sys.indexes i
        WHERE i.object_id = mid.object_id AND i.type > 0
        FOR XML PATH('')
    ), 1, 3, ''), 'NENHUM ÍNDICE EXISTENTE') AS IndicesAtuaisDaTabela,
    'CREATE INDEX IX_' + OBJECT_NAME(mid.object_id) + '_' + 
    REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns, mid.inequality_columns), '[', ''), ']', ''), ', ', '_') + 
    ' ON ' + mid.statement + ' (' + ISNULL(mid.equality_columns, '') + 
    CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL THEN ', ' ELSE '' END + 
    ISNULL(mid.inequality_columns, '') + ')' + 
    ISNULL(' INCLUDE (' + mid.included_columns + ')', '') AS ScriptSugerido
FROM sys.dm_db_missing_index_group_stats AS migs
INNER JOIN sys.dm_db_missing_index_groups AS mig ON migs.group_handle = mig.index_group_handle
INNER JOIN sys.dm_db_missing_index_details AS mid ON mig.index_handle = mid.index_handle
ORDER BY ImpactoEstimado DESC;

PRINT '==================================================================================='
PRINT ' [4] DICAS E RECOMENDAÇÕES DE OTIMIZAÇÃO (LEIA COM ATENÇÃO)'
PRINT '==================================================================================='
PRINT ' AÇÃO 1 (LOCKS):'
PRINT ' - Analise a "SessaoBloqueadora". Use KILL [NumeroDaSessao] apenas se for seguro cancelar a transação em andamento.'
PRINT ''
PRINT ' AÇÃO 2 (CONSULTAS LENTAS):'
PRINT ' - Copie o "TrechoConsultaLenta" e analise o Plano de Execução no SSMS (CTRL+L) em busca de Table Scans.'
PRINT ''
PRINT ' AÇÃO 3 (ÍNDICES - AGORA COM VALIDAÇÃO):'
PRINT ' - Compare a coluna "ColunasChaveSugeridas" com a coluna "IndicesAtuaisDaTabela".'
PRINT ' - Se a tabela já possuir um índice com as mesmas chaves iniciais, NÃO USE o "ScriptSugerido".'
PRINT '   Em vez disso, faça um DROP no índice existente e recrie-o adicionando as colunas listadas em '
PRINT '   "ColunasIncludeSugeridas" na cláusula INCLUDE.'
PRINT ' - Só execute o "ScriptSugerido" caso as chaves recomendadas sejam totalmente diferentes das atuais.'
PRINT ' - Execute a criação de índices em horários de baixo movimento.'
PRINT '==================================================================================='