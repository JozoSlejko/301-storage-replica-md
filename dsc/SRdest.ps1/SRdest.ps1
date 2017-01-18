#
# CopyrightMicrosoft Corporation. All rights reserved."
#

configuration SRdest
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$AdminCreds,
        
        [String]$DomainNetbiosName=(Get-NetBIOSName -DomainName $DomainName),

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30,
        [Int]$SRDataSize=512,
        [Int]$SRLogSize=256,
        [String]$DataVolume='E',
        [String]$LogVolume='F',
        [String]$DataVolumeLabel='Data',
        [String]$LogVolumeLabel='Log'

    )

    Import-DscResource -ModuleName xComputerManagement,xActiveDirectory,xSR 

    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainNetbiosName}\$($Admincreds.UserName)", $Admincreds.Password)
    [System.Management.Automation.PSCredential]$DomainFQDNCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)

    Node localhost
    {

        WindowsFeature ADPS
        {
            Name = "RSAT-AD-PowerShell"
            Ensure = "Present"
        }

        WindowsFeature FS
        {
            Name = "FS-FileServer"
            Ensure = "Present"
        }

        WindowsFeature SR
        {
            Name = "Storage-Replica"
            Ensure = "Present"
        }

        WindowsFeature SRPS
        {
            Name = "RSAT-Storage-Replica"
            Ensure = "Present"
        }

        WindowsFeature SMBBandwidth
        {
            Name = "FS-SMBBW"
            Ensure = "Present"
        }

        xWaitForADDomain DscForestWait 
        { 
            DomainName = $DomainName 
            DomainUserCredential= $DomainCreds
            RetryCount = $RetryCount 
            RetryIntervalSec = $RetryIntervalSec 
            DependsOn = "[WindowsFeature]ADPS"
        }

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainCreds
            DependsOn = "[xWaitForADDomain]DscForestWait"
        }

        Script EnableSRDestination
        {
            SetScript = "New-StoragePool -FriendlyName S2D -PhysicalDisks (Get-PhysicalDisk -CanPool $True) -StorageSubSystemFriendlyName *"
            TestScript = "(Get-StoragePool -FriendlyName S2D -ErrorAction SilentlyContinue).HealthStatus -eq 'Healthy'"
            GetScript = "@{Ensure = if ((Get-StoragePool -FriendlyName S2D -ErrorAction SilentlyContinue).ShareState -eq 'Online') {'Present'} Else {'Absent'}}"
	        DependsOn = "[xComputer]DomainJoin"
        }

        Script CreateSRDataVolume
        {
            SetScript = "New-Volume -StoragePoolFriendlyName S2D* -FriendlyName $DataVolumeLabel -FileSystem REFS -Size $($SRDataSize*1024*1024*1024) -DriveLetter $DataVolume"
            TestScript = "(Get-Volume -FileSystemLabel $DataVolumeLabel -ErrorAction SilentlyContinue).HealthStatus -eq 'Healthy'"
            GetScript = "@{Ensure = if ((Get-Volume -Name $DataVolumeLabel -ErrorAction SilentlyContinue).ShareState -eq 'Online') {'Present'} Else {'Absent'}}"
	        DependsOn = "[Script]EnableSRDestination"
        }

        Script CreateSRLogVolume
        {
            SetScript = "New-Volume -StoragePoolFriendlyName S2D* -FriendlyName $LogVolumeLabel -FileSystem REFS -Size $($SRLogSize*1024*1024*1024) -DriveLetter $LogVolume"
            TestScript = "(Get-Volume -FileSystemLabel $LogVolumeLabel -ErrorAction SilentlyContinue).HealthStatus -eq 'Healthy'"
            GetScript = "@{Ensure = if ((Get-Volume -Name $LogVolumeLabel -ErrorAction SilentlyContinue).ShareState -eq 'Online') {'Present'} Else {'Absent'}}"
	        DependsOn = "[Script]CreateSRDataVolume"
        }

        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $True
        }

    }
}

function Get-NetBIOSName
{ 
    [OutputType([string])]
    param(
        [string]$DomainName
    )

    if ($DomainName.Contains('.')) {
        $length=$DomainName.IndexOf('.')
        if ( $length -ge 16) {
            $length=15
        }
        return $DomainName.Substring(0,$length)
    }
    else {
        if ($DomainName.Length -gt 15) {
            return $DomainName.Substring(0,15)
        }
        else {
            return $DomainName
        }
    }
} 