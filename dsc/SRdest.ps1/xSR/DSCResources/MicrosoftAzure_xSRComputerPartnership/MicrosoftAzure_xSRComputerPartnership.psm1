#
# xSRPartnership: DSC resource to configure a Storage Replica partnership. 
#

function Get-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [string] $SourceComputerName,

        [parameter(Mandatory)]
        [string] $SourceLogVolume,

        [parameter(Mandatory)]
        [string] $SourceDataVolume,

        [parameter(Mandatory)]
        [string] $DestinationComputerName,

        [parameter(Mandatory)]
        [string] $DestinationLogVolume,

        [parameter(Mandatory)]
        [string] $DestinationDataVolume,

        [parameter(Mandatory)]
        [string] $ReplicationMode,

        [parameter(Mandatory)]
        [Uint32] $AsyncRPO,

        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )
    
    $DataVolume = $DestinationDataVolume + ':\'

    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential
        $retvalue = @{Ensure = if (((Get-SRGroup -ErrorAction SilentlyContinue).Replicas).DataVolume -eq $DataVolume) {'Present'} Else {'Absent'}}
    }
    finally
    {
        if ($context)
        {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }
    }

    $retvalue
}

function Set-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [string] $SourceComputerName,

        [parameter(Mandatory)]
        [string] $SourceLogVolume,

        [parameter(Mandatory)]
        [string] $SourceDataVolume,

        [parameter(Mandatory)]
        [string] $DestinationComputerName,

        [parameter(Mandatory)]
        [string] $DestinationLogVolume,

        [parameter(Mandatory)]
        [string] $DestinationDataVolume,

        [parameter(Mandatory)]
        [string] $ReplicationMode,

        [parameter(Mandatory)]
        [Uint32] $AsyncRPO,

        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )
 
    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential

        $SourceRGName = GenerateRGName -ComputerName $SourceComputerName
        $DestinationRGName = GenerateRGName -ComputerName $DestinationComputerName

        InstallSourceFeatures -ComputerName $SourceComputerName -TimeOut 300

        New-SRPartnership -SourceComputerName $SourceComputerName -SourceRGName $SourceRGName -SourceVolumeName $SourceDataVolume -SourceLogVolumeName $SourceLogVolume -DestinationComputerName $DestinationComputerName -DestinationRGName $DestinationRGName -DestinationVolumeName $DestinationDataVolume -DestinationLogVolumeName $DestinationLogVolume -ReplicationMode $ReplicationMode -AsyncRPO $AsyncRPO
    }
    finally
    {
        if ($context)
        {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }
    }

}

function Test-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [string] $SourceComputerName,

        [parameter(Mandatory)]
        [string] $SourceLogVolume,

        [parameter(Mandatory)]
        [string] $SourceDataVolume,

        [parameter(Mandatory)]
        [string] $DestinationComputerName,

        [parameter(Mandatory)]
        [string] $DestinationLogVolume,

        [parameter(Mandatory)]
        [string] $DestinationDataVolume,

        [parameter(Mandatory)]
        [string] $ReplicationMode,

        [parameter(Mandatory)]
        [uint32] $AsyncRPO,

        [parameter(Mandatory)]
        [PSCredential] $DomainAdministratorCredential
    )

    $DataVolume = $DestinationDataVolume + ':\'

    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $DomainAdministratorCredential
        $retvalue = (((Get-SRGroup -ErrorAction SilentlyContinue).Replicas).DataVolume -eq $DataVolume)
    }
    finally
    {
        if ($context)
        {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }
    }

    $retvalue
    
}

function Get-ImpersonateLib
{
    if ($script:ImpersonateLib)
    {
        return $script:ImpersonateLib
    }

    $sig = @'
[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, int dwLogonType, int dwLogonProvider, ref IntPtr phToken);

[DllImport("kernel32.dll")]
public static extern Boolean CloseHandle(IntPtr hObject);
'@
   $script:ImpersonateLib = Add-Type -PassThru -Namespace 'Lib.Impersonation' -Name ImpersonationLib -MemberDefinition $sig

   return $script:ImpersonateLib
}

function ImpersonateAs([PSCredential] $cred)
{
    [IntPtr] $userToken = [Security.Principal.WindowsIdentity]::GetCurrent().Token
    $userToken
    $ImpersonateLib = Get-ImpersonateLib

    $bLogin = $ImpersonateLib::LogonUser($cred.GetNetworkCredential().UserName, $cred.GetNetworkCredential().Domain, $cred.GetNetworkCredential().Password, 
    9, 0, [ref]$userToken)

    if ($bLogin)
    {
        $Identity = New-Object Security.Principal.WindowsIdentity $userToken
        $context = $Identity.Impersonate()
    }
    else
    {
        throw "Can't log on as user '$($cred.GetNetworkCredential().UserName)'."
    }
    $context, $userToken
}

function CloseUserToken([IntPtr] $token)
{
    $ImpersonateLib = Get-ImpersonateLib

    $bLogin = $ImpersonateLib::CloseHandle($token)
    if (!$bLogin)
    {
        throw "Can't close token."
    }
}

function GenerateRGName
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $ComputerName
    )

    $BaseName = 'AzureReplicaRG'

    $NewName = $BaseName + ((Get-SRGroup -ComputerName $ComputerName | measure).Count + 1 )

    return $NewName
}

function InstallSourceFeatures
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.String]
        $ComputerName,

        [parameter(Mandatory = $true)]
        [System.Uint32]
        $TimeOut
    )

    Install-WindowsFeature -ComputerName $ComputerName -Name Storage-Replica,FS-FileServer -IncludeManagementTools -restart

    start-sleep -seconds 60

    $timespan = new-timespan -Seconds $TimeOut

    $sw = [diagnostics.stopwatch]::StartNew()

    while ($sw.elapsed -lt $timespan){
        
    $SourceOnline = Get-Service LANMANSERVER -ComputerName $ComputerName -ErrorAction SilentlyContinue

        if ($SourceOnline){
            return $true
        }
 
        start-sleep -seconds 1
    }
 
    Write-Error "Storage Replica source computer $($ComputerName) unresponsive after $($TimeOut)"
}


Export-ModuleMember -Function *-TargetResource
