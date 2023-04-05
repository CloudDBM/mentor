declare @name varchar(64)

declare c1 cursor for
SELECT  DISTINCT(j.[name])          
FROM    msdb.dbo.sysjobhistory h  
        INNER JOIN msdb.dbo.sysjobs j  
            ON h.job_id = j.job_id  
        INNER JOIN msdb.dbo.sysjobsteps s  
            ON j.job_id = s.job_id 
                AND h.step_id = s.step_id  
WHERE    h.run_status = 0 AND h.run_date > CONVERT(int, CONVERT(varchar(10), DATEADD(DAY, -1, GETDATE()), 112))

open c1

fetch next from c1 into @name

	While @@fetch_status <> -1

	begin
		print @name
		fetch next from c1 into @name
	end

	close c1

deallocate c1