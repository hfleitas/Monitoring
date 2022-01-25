use MyMonitoringDB
go
create or alter procedure [dbo].[uspAlertFailedReportSubscription]
as
DECLARE @count INT

SELECT Cat.[Name]
	,Rep.[ScheduleId]
	,Own.UserName
	,ISNULL(REPLACE(Sub.[Description], 'send e-mail to ', ''), ' ') AS Recipients
	,Sub.[LastStatus]
	,Cat.[Path]
	,Sub.[LastRunTime]
INTO #tFailedSubs
FROM ReportServer.dbo.[Subscriptions] Sub WITH (NOLOCK)
INNER JOIN ReportServer.dbo.[Catalog] Cat WITH (NOLOCK) ON Sub.[Report_OID] = Cat.[ItemID]
INNER JOIN ReportServer.dbo.[ReportSchedule] Rep WITH (NOLOCK) ON (
		cat.[ItemID] = Rep.[ReportID]
		AND Sub.[SubscriptionID] = Rep.[SubscriptionID]
		)
INNER JOIN ReportServer.dbo.[Users] Own WITH (NOLOCK) ON Sub.[OwnerID] = Own.[UserID]
WHERE Sub.[LastStatus] NOT LIKE '%was written%' --File Share subscription
	AND Sub.[LastStatus] NOT LIKE '%pending%' --Subscription in progress. No result yet
	AND Sub.[LastStatus] NOT LIKE '%mail sent%' --Mail sent successfully.
	AND Sub.[LastStatus] NOT LIKE '%New Subscription%' --New Sub. Not been executed yet
	AND Sub.[LastStatus] NOT LIKE '%been saved%' --File Share subscription
	AND Sub.[LastStatus] NOT LIKE '% 0 errors.' --Data Driven subscription
	AND Sub.[LastStatus] NOT LIKE '%succeeded%' --Success! Used in cache refreshes
	AND Sub.[LastStatus] NOT LIKE '%successfully saved%' --File Share subscription
	AND Sub.[LastStatus] NOT LIKE '%New Cache%' --New cache refresh plan
	AND Sub.[LastStatus] NOT IN (
		 'Completed Data Refresh'
		,'Refreshing data'
		,'Saving model to the catalog'
		,'Completed Saving model to the catalog' 
		,'Removing credentials from the model'
        ,'Retrieving report information'
        ,'Streaming model to Analysis Server'
		) --Power BI
	AND Sub.[LastStatus] NOT LIKE 'Failure writing file \\nas\share$\file%.csv : The process cannot access the file%' --domain\username
	AND Sub.[LastStatus] <> 'Disabled' --Actual Result when Disabled.
	AND Sub.[LastRunTime] > dateadd(mi, -6, getdate()) 
	AND Own.UserName <> 'domain\username' --to exclude an owner if needed

-- If any failed subscriptions found, proceed to build HTML & send mail.
SELECT @count = COUNT(*)
FROM #tFailedSubs

IF (@count > 0)
BEGIN
	DECLARE @EmailRecipient NVARCHAR(200)
	DECLARE @SubjectText NVARCHAR(1000)
	DECLARE @tableHTML1 NVARCHAR(MAX)
	DECLARE @tableHTMLAll NVARCHAR(MAX)

	SET NOCOUNT ON

    --notify a specific report owner
	if exists (select top 1 1 FROM #tFailedSubs where Username = 'domain\username') --replace username
	begin 
		SET @EmailRecipient = 'username@domain.com' --replace email
		SET @tableHTML1 = N'<p align="left" style="color:red;">Failed Subscriptions.</p>' + N'<p></p>' + N'<table border="1" style="text-align:left">' + N'<tr style="font-weight:bold">' + N'<th>Report</th><th>SQL Job Name</th><th>Owner</th><th>Description</th><th>Result</th><th>Path</th><th>Last run</th></tr>' + CAST((
				SELECT td = t.[Name]
					,''
					,td = t.[ScheduleId]
					,''
					,td = t.[UserName]
					,''
					,td = t.[Recipients]
					,''
					,td = t.[LastStatus]
					,''
					,td = t.[Path]
					,''
					,td = t.[LastRunTime]
				FROM #tFailedSubs t
				where t.UserName = 'domain\username' --replace username
				FOR XML PATH('tr')
					,TYPE
				) AS NVARCHAR(MAX)) + N'</table>'
	end
	
	SET @SubjectText = 'Alert: Failed Report Subscription'
	SET @tableHTMLAll = ISNULL(@tableHTML1, '')

	IF @tableHTMLAll <> ''
	BEGIN
		--SELECT @tableHTMLAll
		EXEC msdb.dbo.sp_send_dbmail @recipients = @EmailRecipient
			,@body = @tableHTMLAll
			,@body_format = 'HTML'
			,@subject = @SubjectText
	END

	SET NOCOUNT OFF

	DROP TABLE #tFailedSubs
END
GO
