--Acompanhar a % de andamento do shrink 
select percent_complete,* from sys.dm_exec_requests where command in('DbccSpaceReclaim','DbccFilesCompact')