DECLARE
    @value VARCHAR(64),
    @key VARCHAR(512) = 'SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'
 
EXEC master..xp_regread
    @rootkey = 'HKEY_LOCAL_MACHINE',
    @key = @key,
    @value_name = 'ActivePowerScheme',
    @value = @value OUTPUT;
 
SELECT (CASE 
    WHEN @value = '381b4222-f694-41f0-9685-ff5bb260df2e' THEN '(Balanced)'
    WHEN @value = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' THEN '(High performance)'
    WHEN @value = 'a1841308-3541-4fab-bc81-f71556f20b4a' THEN '(Power saver)'
END)