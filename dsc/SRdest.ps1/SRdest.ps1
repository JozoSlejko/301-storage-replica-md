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

        [parameter(Mandatory)]
        [string] $SourceComputerName,

        [Parameter(Mandatory)]
        [Int]$NumberOfDisks,

        [Parameter(Mandatory)]
        [String]$LogVolumeLetter,

        [Parameter(Mandatory)]
        [Int]$LogVolumeSize,

        [Parameter(Mandatory)]
        [Int]$LogVolumeAllocationUnitSize,

        [Parameter(Mandatory)]
        [String]$DataVolumeLetter,

        [Parameter(Mandatory)]
        [Int]$DataVolumeSize,

        [Parameter(Mandatory)]
        [Int]$DataVolumeAllocationUnitSize,

        [Parameter(Mandatory)]
        [String]$ReplicationMode,

        [Parameter(Mandatory)]
        [Int]$AsyncRPO,
        
        [String]$DomainNetbiosName=(Get-NetBIOSName -DomainName $DomainName),

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30        
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
            DependsOn = "[WindowsFeature]SMBBandwidth"
        }

        xComputer DomainJoin
        {
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainCreds
            DependsOn = "[xWaitForADDomain]DscForestWait"
        }

 
         xSRCreateReplicaDestination CreateDestination
        {
            NumberOfDisks = $NumberOfDisks
            NumberOfColumns = $NumberOfDisks
            LogVolumeLetter = $LogVolumeLetter
            LogVolumeSize = $LogVolumeSize
            LogVolumeAllocationUnitSize = $LogVolumeAllocationUnitSize
            DataVolumeLetter = $DataVolumeLetter
            DataVolumeSize = $DataVolumeSize
            DataVolumeAllocationUnitSize = $DataVolumeAllocationUnitSize
            StartingDeviceID = 2
            DependsOn = "[xComputer]DomainJoin" 
        }

        xSRComputerPartnerShip CreateComputerPartership
        {
            SourceComputerName = $SourceComputerName
            SourceLogVolume = $LogVolumeLetter
            SourceDataVolume = $DataVolumeLetter
            DestinationComputerName = $env:COMPUTERNAME
            DestinationLogVolume = $LogVolumeLetter
            DestinationDataVolume = $DataVolumeLetter
            ReplicationMode = $ReplicationMode
            AsyncRPO = $AsyncRPO
            DomainAdministratorCredential = $DomainCreds
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