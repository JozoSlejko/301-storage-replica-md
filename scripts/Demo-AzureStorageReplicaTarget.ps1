#Deploy Storage Replica Target to Azure

$SRSourceComputer = Read-Host -Prompt "Source Computer Name"

.\New-AzureStorageReplicaTarget.ps1 `
    -SRSourceComputer $SRSourceComputer `
    -DomainName contoso.com `
    -SRSourceDataDrive F `
    -SRSourceLogDrive G `
    -SRAsyncRPO 300

#Check status of SR Partnership

$SRPartnership = Get-SRPartnership -ComputerName $SRSourceComputer

$SRPartnership

#Check status of SR Replication

(Get-SRGroup -ComputerName $SRSourceComputer).Replicas

#Generate IO activity to data volume on source

Start-Process `
    -FilePath "ROBOCOPY.EXE" `
    -ArgumentList "C:\Windows \\${SRSourceComputer}\F$ /S /E /V /R:1 /W:1 /IS"

#Check status of SR Replication

(Get-SRGroup -ComputerName $SRSourceComputer).Replicas

#Failover SR Target

$SRPartnership = Get-SRPartnership -ComputerName $SRSourceComputer

Set-SRPartnership `
    -NewSourceComputerName $($SRPartnership.DestinationComputerName) `
    -SourceRGName $($SRPartnership.DestinationRGName) `
    -DestinationComputerName $($SRPartnership.SourceComputerName) `
    -DestinationRGName $($SRPartnership.SourceRGName) `
    -Confirm:$true

Get-SRPartnership

#Test access to new Source

$SRPartnership = Get-SRPartnership

$SourcePath = "\\$($SRPartnership.SourceComputerName)\F$"

Do {

    $contents = Get-ChildItem `
        -Path $SourcePath `
        -ErrorAction SilentlyContinue

} Until ($contents)

$contents | Out-GridView -Title $SourcePath
