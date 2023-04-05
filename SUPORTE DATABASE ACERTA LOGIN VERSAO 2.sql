use master
exec spu_backup_full CR_RRSat
go
exec spu_backup_diff CR_RRSat
go
exec spu_backup_log_init  CR_RRSat
go
exec spu_backup_log_noinit CR_RRSat