sp_spaceused nometabela
go
select count(*) from nometabela nolock
go
sp_helptindex nometabela
go
update statistics nometabela with fullscan