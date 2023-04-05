SET NOCOUNT ON
DECLARE @hr int
DECLARE @fso int
DECLARE @drive char(1)
DECLARE @odrive int
DECLARE @TotalSize varchar(20) 
DECLARE @MB Numeric 
SET @MB = 1048576
CREATE TABLE #drives 
    (drive char(1) PRIMARY KEY, 
     FreeSpace int NULL,
     TotalSize int NULL) 

INSERT #drives(drive,FreeSpace) 

EXEC master.dbo.xp_fixeddrives 

EXEC @hr=sp_OACreate 'Scripting.FileSystemObject', @fso OUT 
IF @hr <> 0 
EXEC sp_OAGetErrorInfo @fso

DECLARE dcur CURSOR LOCAL FAST_FORWARD
FOR SELECT drive from #drives ORDER by drive

OPEN dcur FETCH NEXT FROM dcur INTO @drive
WHILE @@FETCH_STATUS=0
BEGIN
EXEC @hr = sp_OAMethod @fso,'GetDrive', @odrive OUT, @drive

IF @hr <> 0 EXEC sp_OAGetErrorInfo @fso EXEC @hr =
sp_OAGetProperty
@odrive,'TotalSize', 
@TotalSize OUT IF @hr <> 0 

EXEC sp_OAGetErrorInfo @odrive 

UPDATE #drives SET TotalSize=@TotalSize/@MB 
WHERE  drive=@drive 
FETCH NEXT FROM dcur INTO @drive
End
Close dcur
DEALLOCATE dcur
EXEC @hr=sp_OADestroy @fso IF @hr <> 0 EXEC sp_OAGetErrorInfo @fso

DECLARE @tableHTML NVARCHAR(MAX);

SET @tableHTML = N'<H1>ESPAÇO DOS DISCOS</H1>' + N'<table border="1">' + N'<tr>' +
				N'<th>DRIVE</th>' + 
				N'<th>TOTAL (MB)</th>' + 
                N'<th>FREE (MB)</th>'  + 
				N'<th>FREE (%)</th>'  + 
				'</tr>' + CAST((

SELECT
 td = drive , '', 
 td = TotalSize, '', 
 td = FreeSpace, '', 
 td = cast((1 - (cast (FreeSpace as float))/(cast (TotalSize as float))) *100 as decimal(4,2))
FROM #drives
ORDER BY drive 
FOR XML PATH('tr')
                    ,TYPE
                ) AS NVARCHAR(MAX)) + N'</table>';
DECLARE @tableHTMLCondicao NVARCHAR(MAX);
SET @tableHTMLCondicao = N'<H1>ESPAÇO DOS DISCOS</H1>' + N'<table border="1">' + N'<tr>' +
				N'<th>DRIVE</th>' + 
				N'<th>TOTAL (MB)</th>' + 
                N'<th>FREE (MB)</th>'  + 
				N'<th>FREE (%)</th>'  + 
				'</tr>' + CAST((

SELECT
 td = drive , '', 
 td = TotalSize, '', 
 td = FreeSpace, '', 
 td = cast((1 - (cast (FreeSpace as float))/(cast (TotalSize as float))) as decimal(4,2))
FROM #drives
ORDER BY drive 
FOR XML PATH('tr')
                    ,TYPE
                ) AS NVARCHAR(MAX)) + N'</table>';

DROP TABLE #drives 

DECLARE @assunto VARCHAR(100) = N'DISCOS NO SERVIDOR BAIXO: ' + @@SERVERNAME + ' ' + CAST (GETDATE() AS VARCHAR)

if CHARINDEX('0.2',@tableHTMLCondicao) > 0 -- se a porcentagem for menor que 10% envia email
BEGIN
EXEC msdb.dbo.sp_send_dbmail @body = @tableHTML
        ,@body_format = 'HTML'
        ,@profile_name = N'DBA'
        --,@recipients = N'monitoramento@clouddbm.com'
		,@recipients = N'vpmaciel@gmail.com'
        ,@Subject = @assunto
END