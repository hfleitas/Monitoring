function Get-SQLPatches {
    <#
        .SYNOPSIS
            Retrives a historical list of all SQL Patches (CUs, Service Packs & Hot-fixes) installed on a Computer.

        .DESCRIPTION
            Uses WMI to retrieve a list of the Win32_OperatingSystem BuildNumber, CSName.
            Uses Get-ChildItem to retrieve a list of DisplayName, DisplayVersion, InstallDate from path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall.

        .PARAMETER ComputerName
            Allows you to specify a comma separated list of servers to query. Default: localhost.

        .NOTES
            Author: Hiram Fleitas, http://twitter.com/hiramfleitas, http://fleitasarts.com
            Tags: Updates, Patches

            Website: http://fleitasarts.com
            Copyright: (c) 2019 by Hiram Fleitas, licensed under MIT
            -           License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://github.com/hfleitas/Monitoring/blob/master/Get-SQLUpdates.ps1

        .EXAMPLE
            PS C:\> Get-SQLPatches -ComputerName HiramSQL1, HiramSQL2

            Gets a list of SQL Server patches installed on HiramSQL1 and HiramSQL2.

        .EXAMPLE
            PS C:\> Get-SQLPatches -ComputerName (Get-Content C:\Monitoring\Servers.txt)

            Gets the SQL Server patches from a list of computers in C:\Monitoring\Servers.txt.

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, Position=0, ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [string[]]$ComputerName=$env:COMPUTERNAME
        )

    begin{}

    process {
        foreach ($Computer in $ComputerName) {
            try {
		    $WMI_OS = Get-WmiObject -Class Win32_OperatingSystem -Property BuildNumber, CSName -ComputerName $Computer -ErrorAction Stop
		}
		catch [Exception] {
			Write-Output "$computer $($_.Exception.Message)"
		}

		try {
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
		}
		catch [Exception] {
			Write-Output "$computer $($_.Exception.Message)"
		}

		$inst = Invoke-Command -computer $Computer {
			(get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances
		}

		foreach ($i in $inst) {	
			$p = Invoke-Command -computer $Computer -ArgumentList $i {
			param($i)
			   (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL').$i
			"{0}" -f $using:i
			}
			$level = Invoke-Command -computer $Computer -ArgumentList $p {
			param($p)
				(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$p\Setup").PatchLevel
			"{0}" -f $using:p
			}

			foreach ($Patch in $Patches) {
				$List = @{
					Property=(
						'Computer',
						'DisplayName',
						'InstallDate',
						'DisplayVersion',
						'InstanceVersion',
						'Instance'
					)
				}
				New-Object -TypeName PSObject -Property @{
					Computer	= $WMI_OS.CSName
					DisplayName	= $Patch.DisplayName
					InstallDate	= $Patch.InstallDate
					DisplayVersion	= $Patch.DisplayVersion
					InstanceVersion	= $level | select-object -first 1
					Instance	= $level | select-object -last 1
				} | Sort-Object -Property @{Expression = "InstallDate"; Descending = $True} | Select-Object @List
			}
		}
        }
    }
    end{}
}


$local
$Servers = Get-Content C:\Monitoring\Servers.txt
$file = "C:\Monitoring\SQLPatches.txt"
$Csv = "C:\Monitoring\SQLPatches.csv"
$Type = "csv" #or txt
c:
cd c:\Monitoring

##Generate Report
if ($Type -eq "csv") {
	$file = $Csv
	Get-SQLPatches -ComputerName $Servers | Export-CSV -LiteralPath $file -Force -NoTypeInformation
} else 	{
	Get-SQLPatches -ComputerName $Servers |ft -autosize -wrap | out-file $file
}

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
