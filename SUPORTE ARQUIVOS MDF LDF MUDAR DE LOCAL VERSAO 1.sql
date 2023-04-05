use AdventureWorks2012
go
exec sp_helpfile

use master
alter database AdventureWorks2012
modify file( name=AdventureWorks2012, filename='D:\DBA_SQL\DATABASE\DATA\AdventureWorksLT2012.mdf')
go
alter database AdventureWorks2012
modify file( name=AdventureWorks2012_log, filename='D:\DBA_SQL\DATABASE\LOG\AdventureWorksLT2012_log.ldf')
go

alter database AdventureWorks2012 set offline

alter database AdventureWorks2012 set online