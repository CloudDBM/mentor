--------------------------------------------------------------------------------
-- Habilitando o xp_cmdshell (Se não estiver ativado)
--------------------------------------------------------------------------------

DECLARE @Fl_Xp_CmdShell_Ativado BIT = (SELECT (CASE WHEN CAST([value] AS VARCHAR(MAX)) = '1' THEN 1 ELSE 0 END) FROM sys.configurations WHERE [name] = 'xp_cmdshell')

IF (@Fl_Xp_CmdShell_Ativado = 0)
BEGIN

    EXECUTE SP_CONFIGURE 'show advanced options', 1;
    RECONFIGURE WITH OVERRIDE;
    
    EXEC sp_configure 'xp_cmdshell', 1;
    RECONFIGURE WITH OVERRIDE;
    
END


--------------------------------------------------------------------------------
-- Código fonte
--------------------------------------------------------------------------------

IF (OBJECT_ID('tempdb..#Retorno_CmdShell') IS NOT NULL) DROP TABLE #Retorno_CmdShell
CREATE TABLE #Retorno_CmdShell (
    Id INT IDENTITY(1, 1),
    Descricao VARCHAR(MAX)
)

INSERT INTO #Retorno_CmdShell
EXEC master.dbo.xp_cmdshell 'wmic logicaldisk where drivetype=3 get Caption,FreeSpace,Size,FileSystem,VolumeName /FORMAT:list'


IF (OBJECT_ID('tempdb..#Informacoes_Disco') IS NOT NULL) DROP TABLE #Informacoes_Disco
CREATE TABLE #Informacoes_Disco (
    Ds_Drive NVARCHAR (256) COLLATE Latin1_General_CI_AI NULL,
    Ds_Volume NVARCHAR (256) COLLATE Latin1_General_CI_AI NULL,
    Ds_FileSystem NVARCHAR (128) COLLATE Latin1_General_CI_AI NULL,
    Qt_Tamanho NUMERIC(18, 2) NULL,
    Qt_Utilizado NUMERIC(18, 2) NULL,
    Qt_Livre NUMERIC(18, 2) NULL,
    Perc_Utilizado NUMERIC(18, 2) NULL,
    Perc_Livre NUMERIC(18, 2) NULL
)

DECLARE 
    @Contador INT = 3, 
    @Total INT = (SELECT COUNT(*) FROM #Retorno_CmdShell),
    @Ds_Drive VARCHAR(100),
    @Ds_Volume VARCHAR(100),
    @Ds_Filesystem VARCHAR(100),
    @Qt_Tamanho FLOAT,
    @Qt_Utilizado FLOAT,
    @Qt_Livre FLOAT,
    @Perc_Utilizado FLOAT,
    @Perc_Livre FLOAT
    
    
WHILE(@Contador <= @Total)
BEGIN
    

    SELECT @Ds_Drive = REPLACE(SUBSTRING(Descricao, CHARINDEX('=', Descricao) + 1, 99999999), CHAR(13), '')
    FROM #Retorno_CmdShell
    WHERE Id = @Contador


    -- Se chegou ao final, força sair do WHILE
    IF (NULLIF(@Ds_Drive, '') IS NULL)
        BREAK


    SELECT @Ds_Filesystem = REPLACE(SUBSTRING(Descricao, CHARINDEX('=', Descricao) + 1, 99999999), CHAR(13), '')
    FROM #Retorno_CmdShell
    WHERE Id = @Contador + 1

    SELECT @Qt_Livre = REPLACE(SUBSTRING(Descricao, CHARINDEX('=', Descricao) + 1, 99999999), CHAR(13), '')
    FROM #Retorno_CmdShell
    WHERE Id = @Contador + 2

    SELECT @Qt_Tamanho = REPLACE(SUBSTRING(Descricao, CHARINDEX('=', Descricao) + 1, 99999999), CHAR(13), '')
    FROM #Retorno_CmdShell
    WHERE Id = @Contador + 3

    SELECT @Ds_Volume = REPLACE(SUBSTRING(Descricao, CHARINDEX('=', Descricao) + 1, 99999999), CHAR(13), '')
    FROM #Retorno_CmdShell
    WHERE Id = @Contador + 4

    
    SELECT
        @Qt_Utilizado = @Qt_Tamanho - @Qt_Livre,
        @Perc_Utilizado = @Qt_Utilizado / @Qt_Tamanho,
        @Perc_Livre = @Qt_Livre / @Qt_Tamanho


    INSERT INTO #Informacoes_Disco (
        Ds_Drive ,
        Ds_Volume ,
        Ds_FileSystem ,
        Qt_Tamanho ,
        Qt_Utilizado ,
        Qt_Livre ,
        Perc_Utilizado ,
        Perc_Livre
    )
    VALUES  (
        @Ds_Drive, -- Ds_Drive - nvarchar(256)
        @Ds_Volume, -- Ds_Volume - nvarchar(256)
        @Ds_Filesystem, -- Ds_FileSystem - nvarchar(128)
        @Qt_Tamanho / 1073741824.0, -- Qt_Tamanho - float
        @Qt_Utilizado / 1073741824.0, -- Qt_Utilizado - float
        @Qt_Livre / 1073741824.0, -- Qt_Livre - float
        @Perc_Utilizado, -- Perc_Utilizado - float
        @Perc_Livre -- Perc_Livre - float
    )


    SET @Contador += 7


END


SELECT * FROM #Informacoes_Disco


--------------------------------------------------------------------------------
-- Desativando o xp_cmdshell (Se não estava habilitado antes)
--------------------------------------------------------------------------------

IF (@Fl_Xp_CmdShell_Ativado = 0)
BEGIN

    EXEC sp_configure 'xp_cmdshell', 0;
    RECONFIGURE WITH OVERRIDE;

    EXECUTE SP_CONFIGURE 'show advanced options', 0;
    RECONFIGURE WITH OVERRIDE;

END