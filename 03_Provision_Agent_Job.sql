USE [msdb];
GO

DECLARE @JobId BINARY(16);
EXEC dbo.sp_add_job 
    @job_name = N'Daily Developer Commit Audit', 
    @enabled = 1, 
    @description = N'Queries GitHub API, handles US time zones, and flags non-compliance dynamically.',
    @job_id = @JobId OUTPUT;

EXEC dbo.sp_add_jobstep 
    @job_id = @JobId, 
    @step_name = N'Execute Timezone Aware PowerShell Report', 
    @subsystem = N'PowerShell', 
    @command = N'powershell.exe -File "C:\Scripts\DailyCommitReport.ps1"', 
    @retry_attempts = 1, \r\n    @retry_interval = 5;

DECLARE @ScheduleId INT;
EXEC dbo.sp_add_schedule \r\n    @schedule_name = N'Daily_7AM_Weekday_Schedule', 
    @freq_type = 4,          
    @freq_interval = 1,      
    @active_start_time = 070000, 
    @schedule_id = @ScheduleId OUTPUT;
GO
