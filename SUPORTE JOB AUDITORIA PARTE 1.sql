CREATE TABLE Job_Audit (
    [Id_Auditoria] [INT] IDENTITY(1,1) PRIMARY KEY CLUSTERED NOT NULL,
    [Dt_Evento] [DATETIME] NULL DEFAULT (GETDATE()),
    [Ds_Usuario] [VARCHAR](50) NULL,
    [Ds_Job] [sysname] NULL,
    [Ds_Hostname] [VARCHAR](50) NULL,
    [Ds_Query] [VARCHAR](MAX) NULL,
    [Fl_Situacao] [TINYINT] NULL
)
WITH (DATA_COMPRESSION=PAGE)

select * from Job_Audit