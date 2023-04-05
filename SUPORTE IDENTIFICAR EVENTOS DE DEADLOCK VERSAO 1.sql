DECLARE @TimeZone INT = DATEDIFF(HOUR, GETUTCDATE(), GETDATE())

SELECT
    DATEADD(HOUR, @TimeZone, xed.value('@timestamp', 'datetime2(3)')) AS CreationDate,
    xed.query('.') AS XEvent
FROM
(
    SELECT 
        CAST(st.[target_data] AS XML) AS TargetData
    FROM 
        sys.dm_xe_session_targets AS st
        INNER JOIN sys.dm_xe_sessions AS s ON s.[address] = st.event_session_address
    WHERE 
        s.[name] = N'system_health'
        AND st.target_name = N'ring_buffer'
) AS [Data]
CROSS APPLY TargetData.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEventData (xed)
ORDER BY 
    CreationDate DESC