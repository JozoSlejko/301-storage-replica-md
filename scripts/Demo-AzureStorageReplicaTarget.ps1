#Deploy Storage Replica Target to Azure
.\New-AzureStorageReplicaTarget.ps1 -SRSourceComputer kems2svm01 -DomainName contoso.com -SRSourceDataDrive F -SRSourceLogDrive G

#Check status of SR Partnership
Get-SRPartnership

#Check status of SR Replication
(Get-SRGroup).Replicas

#Generate IO activity to data volume on source

Start-Process -FilePath "ROBOCOPY.EXE" -ArgumentList "C:\Windows F:\ /S /E /V /R:1 /W:1 /IS"

#Check status of SR Replication

(Get-SRGroup).Replicas

#Failover SR Target

$SRPartnership = Get-SRPartnership

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
    $contents = Get-ChildItem -Path $SourcePath -ErrorAction SilentlyContinue
} Until ($contents)

$contents | Out-GridView -Title $SourcePath
