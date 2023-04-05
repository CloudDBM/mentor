SELECT DISTINCT
volume_mount_point as Drive,
total_bytes/1073741824 as SizeGB,
available_bytes/1073741824 as FreeSpaceGB,
LEFT((CAST(available_bytes as decimal) / CAST(total_bytes as decimal)*100),5)+'%' as PercentFree
FROM sys.master_files smf
CROSS APPLY sys.dm_os_volume_stats(smf.database_id,smf.file_id)
ORDER BY volume_mount_point;