--restore filelistonly FROM  DISK = N'E:\backup\BkpLG_RM_NREMon.bak' 
go
--restore headeronly FROM  DISK = N'E:\backup\BkpLG_RM_NREMon.bak' 
go

restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with 
move 'BaseVazia' to 'R:\DATA\RM_NRE_DATA_1.mdf',
move 'BaseVazia_log' to	'I:\LOG\RM_NRE_LOG_1.ldf',
move 'RM_LOG' to 'I:\LOG\RM_NRE_LOG_2.ldf', norecovery, file=1
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=2
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=3
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=4
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=5
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=6
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=7
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=8
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=9
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=10
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=11
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=12
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=13
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=14
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=15
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=16
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=17
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=18
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=19
go
restore log RM_NRE from disk = 'E:\backup\BkpLG_RM_NREMon.bak' with norecovery,file=20
go