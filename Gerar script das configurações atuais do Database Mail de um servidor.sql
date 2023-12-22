USE msdb;
GO

DECLARE
  @SQLText VARCHAR(MAX),
  @CrLf CHAR(2) = CHAR(13) + CHAR(10);

SELECT @SQLText = '
EXEC msdb.dbo.sp_configure
  @configname = ''show advanced options'',
  @configvalue = 1;

RECONFIGURE;
EXEC msdb.dbo.sp_configure
  @configname = ''Database Mail XPs'',
  @configvalue = 1;
RECONFIGURE;

EXECUTE msdb.dbo.sysmail_add_profile_sp
  @profile_name = ''' + p.name + ''',
  @description  = ''' + ISNULL(p.description,'') + ''';

EXEC msdb.dbo.sysmail_add_account_sp
  @account_name = ' + CASE WHEN a.name IS NULL THEN 'NULL' ELSE + '''' + a.name + '''' END + ',
  @email_address = ' + CASE WHEN a.email_address IS NULL THEN 'NULL' ELSE + '''' + a.email_address + '''' END + ',
  @display_name = ' + CASE WHEN a.display_name IS NULL THEN 'NULL' ELSE + '''' + a.display_name + '''' END + ',
  @replyto_address = ' + CASE WHEN a.replyto_address IS NULL THEN 'NULL' ELSE + '''' + a.replyto_address + '''' END + ',
  @description = ' + CASE WHEN a.description IS NULL THEN 'NULL' ELSE + '''' + a.description + '''' END + ',
  @mailserver_name = ' + CASE WHEN s.servername IS NULL THEN 'NULL' ELSE + '''' + s.servername + '''' END + ',
  @mailserver_type = ' + CASE WHEN s.servertype IS NULL THEN 'NULL' ELSE + '''' + s.servertype + '''' END + ',
  @port = ' + CASE WHEN s.port IS NULL THEN 'NULL' ELSE + '''' + CONVERT(VARCHAR,s.port) + '''' END + ',
  @username = ' + CASE WHEN c.credential_identity IS NULL THEN 'NULL' ELSE + '''' + c.credential_identity   + '''' END + ',
  @password = ' + CASE WHEN c.credential_identity IS NULL THEN 'NULL' ELSE + '''NotTheRealPassword''' END + ',
  @use_default_credentials = ' + CASE WHEN s.use_default_credentials = 1 THEN '1' ELSE '0' END + ',
  @enable_ssl = ' + CASE WHEN s.enable_ssl = 1 THEN '1' ELSE '0' END + ';

EXEC msdb.dbo.sysmail_add_profileaccount_sp
  @profile_name = ''' + p.name + ''',
  @account_name = ''' + a.name + ''',
  @sequence_number = ' + CAST(pa.sequence_number AS NVARCHAR(3)) + ';
' +
  COALESCE('
EXEC msdb.dbo.sysmail_add_principalprofile_sp
  @profile_name = ''' + p.name + ''',
  @principal_name = ''' + dp.name + ''',
  @is_default = ' + CAST(pp.is_default AS NVARCHAR(1)) + ';
', '')
FROM msdb.dbo.sysmail_profile AS p
INNER JOIN msdb.dbo.sysmail_profileaccount AS pa ON
  p.profile_id = pa.profile_id
INNER JOIN msdb.dbo.sysmail_account AS a ON
  pa.account_id = a.account_id
LEFT OUTER JOIN msdb.dbo.sysmail_principalprofile AS pp ON
  p.profile_id = pp.profile_id
LEFT OUTER JOIN msdb.sys.database_principals AS dp ON
  pp.principal_sid = dp.sid
LEFT OUTER JOIN msdb.dbo.sysmail_server AS s ON
  a.account_id = s.account_id
LEFT OUTER JOIN sys.credentials AS c ON
  s.credential_id = c.credential_id;

WITH R2(N) AS (SELECT 1 UNION ALL SELECT 1),
R4(N) AS (SELECT 1 FROM R2 AS a CROSS JOIN R2 AS b),
R8(N) AS (SELECT 1 FROM R4 AS a CROSS JOIN R4 AS b),
R16(N) AS (SELECT 1 FROM R8 AS a CROSS JOIN R8 AS b),
R32(N) AS (SELECT 1 FROM R16 AS a CROSS JOIN R16 AS b),
R64(N) AS (SELECT 1 FROM R32 AS a CROSS JOIN R32 AS b),
R128(N) AS (SELECT 1 FROM R64 AS a CROSS JOIN R64 AS b),
Tally(N) AS (
  SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL))
  FROM R128
),
SplitText(SplitIndex, [Text]) AS (
  SELECT
    N,
    SUBSTRING(
      @CrLf + @SQLText + @CrLf,
      N + DATALENGTH(@CrLf),
      CHARINDEX(
        @CrLf,
        @CrLf + @SQLText + @CrLf,
        N + DATALENGTH(@CrLf)
      ) - N - DATALENGTH(@CrLf)
    )
  FROM Tally
  WHERE
    N < DATALENGTH(@CrLf + @SQLText) AND
    SUBSTRING(@CrLf + @SQLText + @CrLf, N, DATALENGTH(@CrLf)) = @CrLf
)
SELECT [Text]
FROM SplitText
ORDER BY SplitIndex;