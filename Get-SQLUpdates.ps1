<#
.SYNOPSIS
Get-SQLPatches retrives list of SQL Patches (SP/CU/Hot-fixes) for a Computer.
.DESCRIPTION
Get-SQLPatches uses WMI to retrieve a list of the Win32_OperatingSystem BuildNumber, CSName.
Get-SQLPatches uses Get-ChildItem to retrieve a list of DisplayName, DisplayVersion, InstallDate
from path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall.

Created By: Hiram Fleitas aka. DBA2.o @hiramfleitas
Modified: 4/17/2019 05:09:35 PM  
Version 1.0

.PARAMETER ComputerName
The Computer name to query. Default: Localhost.
.EXAMPLE
Get-SQLPatches -ComputerName HiramSQL1
Gets the SQL Server patches from HiramSQL1
.EXAMPLE
Get-SQLPatches -ComputerName (Get-Content C:\Monitoring\Servers.txt)
Gets the SQL Server patches from a list of computers in C:\Monitoring\Servers.txt.
#>
Function Get-SQLPatches {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false,
                        Position=0,
                        ValueFromPipeline=$true,
                        ValueFromPipelineByPropertyName=$true)]
        [Alias("Name")]
        [string[]]$ComputerName=$env:COMPUTERNAME
        )

    begin{}

    process {
        foreach ($Computer in $ComputerName) {
            try {
			    $WMI_OS = Get-WmiObject -Class Win32_OperatingSystem -Property BuildNumber, CSName -ComputerName $Computer -ErrorAction Stop
                
				$Patches = Invoke-command -computer $Computer {
					Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall `
					| Get-ItemProperty `
					| Sort-Object -Property @{Expression = "InstallDate"; Descending = $True} `
					| Select-Object -Property DisplayName, DisplayVersion, InstallDate `
					| Where-Object { `
							($_.DisplayName -like "Hotfix*SQL*") `
						-or ($_.DisplayName -like "Service Pack*SQL*") `
					}
				}
				
				foreach ($Patch in $Patches) {
					## Creating Custom PSObject and Select-Object Splat
					$List = @{
						Property=(
							'Computer',
							'DisplayName',
							'DisplayVersion',
							'InstallDate'
						)}
					New-Object -TypeName PSObject -Property @{
						Computer=$WMI_OS.CSName
						DisplayName=$Patch.DisplayName
						DisplayVersion=$Patch.DisplayVersion
						InstallDate=$Patch.InstallDate
					} | Sort-Object -Property @{Expression = "InstallDate"; Descending = $True} | Select-Object @List
					} 
				}
				
            catch [Exception] {
                Write-Output "$computer $($_.Exception.Message)"
                #return
                }
        }
    }
    end{}
}

$Servers = Get-Content C:\Monitoring\Servers.txt
$file = "C:\Monitoring\SQLPatches.txt"
c:
cd c:\Monitoring

##Generate Report
Get-SQLPatches -ComputerName $Servers |ft -autosize -wrap |out-file $file

##Wait 5 Seconds
Start-Sleep -s 5 

##Send Email Report
$smtpServer = "smtp.yourdomain.com"
$att = new-object Net.Mail.Attachment($file)
$msg = new-object Net.Mail.MailMessage
$msg.From = "you@yourdomain.com"
$msg.To.Add("you@yourdomain.com")
#$msg.To.Add("group@yourdomain.com")
$msg.Subject = "SQL Server Updates Installed"
$msg.IsBodyHtml = $True 
$msg.Body = "See attached report."
$msg.Attachments.Add($att)

$smtp = new-object Net.Mail.SmtpClient($smtpServer)
$smtp.Send($msg)
$att.Dispose()
