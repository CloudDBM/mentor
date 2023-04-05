SELECT
    CASE database_id WHEN 32767 THEN 'ResourceDb' ELSE DB_NAME(database_id)END AS database_name,
    COUNT(*) AS cached_pages_count,
    COUNT(*) * .0078125 AS cached_megabytes /* Each page is 8kb, which is .0078125 of an MB */
FROM
    sys.dm_os_buffer_descriptors
GROUP BY
    DB_NAME(database_id),
    database_id
ORDER BY
    cached_pages_count DESC;