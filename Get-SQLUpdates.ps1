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
                
				$Patches = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall `
				| Get-ItemProperty `
				| Sort-Object -Property DisplayName `
				| Select-Object -Property DisplayName, DisplayVersion, InstallDate `
				| Where-Object { `
						($_.DisplayName -like "Hotfix*SQL*") `
					-or ($_.DisplayName -like "Service Pack*SQL*") `
				}
				
				foreach ($Patch in $Patches) {
					## Creating Custom PSObject and Select-Object Splat
					$SelectSplat = @{
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
					} | Select-Object @SelectSplat
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

##Wait 30 Seconds
Start-Sleep -s 30 

##Send Email Report
$smtpServer = "smtp.fleitasarts.com"
$att = new-object Net.Mail.Attachment($file)
$msg = new-object Net.Mail.MailMessage
$msg.From = "hiram@fleitasarts.com"
$msg.To.Add("hiram@fleitasarts.com")
#$msg.To.Add("audit@fleitasarts.com")
$msg.Subject = "SQL Server Patches Installed"
$msg.IsBodyHtml = $True 
$msg.Body = "See attached report."
$msg.Attachments.Add($att)

$smtp = new-object Net.Mail.SmtpClient($smtpServer)
$smtp.Send($msg)
$att.Dispose()
