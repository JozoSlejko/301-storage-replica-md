#
# xSRCreateReplicaDestination: DSC resource to create Storage Replication destination with Storage Pool
#

function Get-TargetResource
{
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.Uint32]
        $NumberOfDisks,

        [ValidateNotNullOrEmpty()]
        [System.Uint32]
        $NumberOfColumns = 0,

        [parameter(Mandatory = $true)]
        [System.String]
        $LogVolumeLetter,

        [parameter(Mandatory = $true)]
        [System.String]
        $LogVolumeSize,

        [parameter(Mandatory = $true)]
        [System.Uint64]
        $LogVolumeAllocationUnitSize,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $DataVolumeLetter,

        [parameter(Mandatory = $true)]
        [System.String]
        $DataVolumeSize,

        [parameter(Mandatory = $true)]
        [System.Uint64]
        $DataVolumeAllocationUnitSize,

        [parameter(Mandatory = $true)]
        [System.Uint32]
        $StartingDeviceID,

        [ValidateNotNullOrEmpty()]
        [Bool]$RebootVirtualMachine = $false 
    )
    
    $bConfigured = Test-TargetResource -NumberOfDisks $NumberOfDisks -NumberOfColumns $NumberOfColumns -LogVolumeLetter $LogVolumeLetter -LogVolumeSize $LogVolumeSize -LogVolumeAllocationUnitSize $LogVolumeAllocationUnitSize -DataVolumeLetter $DataVolumeLetter -DataVolumeSize $DataVolumeSize -DataVolumeAllocationUnitSize $DataVolumeAllocationUnitSize -RebootVirtualMachine $RebootVirtualMachine

    $retVal = @{
        NumberOfDisks = $NumberOfDisks
        NumberOfColumns = $NumberOfColumns
        LogVolumeLetter = $LogVolumeLetter
        LogVolumeSize = $LogVolumeSize
        LogVolumeAllocationUnitSize = $LogVolumeAllocationUnitSize
        DataVolumeLetter = $DataVolumeLetter
        DataVolumeSize = $DataVolumeSize
        DataVolumeAllocationUnitSize = $DataVolumeAllocationUnitSize
        StartingDeviceID = $StartingDeviceID
        RebootVirtualMachine = $RebootVirtualMachine
    }

    $retVal
}

function Test-TargetResource
{
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.Uint32]
        $NumberOfDisks,

        [ValidateNotNullOrEmpty()]
        [System.Uint32]
        $NumberOfColumns = 0,

        [parameter(Mandatory = $true)]
        [System.String]
        $LogVolumeLetter,

        [parameter(Mandatory = $true)]
        [System.Uint64]
        $LogVolumeSize,

        [parameter(Mandatory = $true)]
        [System.Uint64]
        $LogVolumeAllocationUnitSize,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $DataVolumeLetter,

        [parameter(Mandatory = $true)]
        [System.Uint64]
        $DataVolumeSize,

        [parameter(Mandatory = $true)]
        [System.Uint64]
        $DataVolumeAllocationUnitSize,

        [parameter(Mandatory = $true)]
        [System.Uint32]
        $StartingDeviceID,

        [ValidateNotNullOrEmpty()]
        [Bool]$RebootVirtualMachine = $false 
    )
    
    $result = [System.Boolean]

    Try 
    {
        if (Get-volume -DriveLetter $LogVolumeLetter -ErrorAction SilentlyContinue)
        {
            Write-Verbose "'$($LogVolumeLetter)' exists on target."
            $result = $true
            $ExistingDrive = $LogVolumeLetter
        }
        elseif (Get-volume -DriveLetter $DataVolumeLetter -ErrorAction SilentlyContinue)
        {
            Write-Verbose "'$($DataVolumeLetter)' exists on target."
            $result = $true
            $ExistingDrive = $DataVolumeLetter
        }
        else
        {
            Write-Verbose "'Log and Data drives not found on target."
            $result = $false
        }
    }
    Catch 
    {
        throw "An error occured getting the '$($ExistingDrive)' drive informations. Error: $($_.Exception.Message)"
    }

    $result    
}

function Set-TargetResource
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.Uint32]
        $NumberOfDisks,

        [ValidateNotNullOrEmpty()]
        [System.Uint32]
        $NumberOfColumns = 0,

        [parameter(Mandatory = $true)]
        [System.String]
        $LogVolumeLetter,

        [parameter(Mandatory = $true)]
        [System.Uint64]
        $LogVolumeSize,

        [parameter(Mandatory = $true)]
        [System.Uint64]
        $LogVolumeAllocationUnitSize,
        
        [parameter(Mandatory = $true)]
        [System.String]
        $DataVolumeLetter,

        [parameter(Mandatory = $true)]
        [System.Uint64]
        $DataVolumeSize,

        [parameter(Mandatory = $true)]
        [System.Uint64]
        $DataVolumeAllocationUnitSize,

        [parameter(Mandatory = $true)]
        [System.Uint32]
        $StartingDeviceID,

        [ValidateNotNullOrEmpty()]
        [Bool]$RebootVirtualMachine = $false 
    )

    #Validating Paramters
    if ($NumberOfColumns -gt $NumberOfDisks)
    {
        Write-Verbose "NumberOfColumns ( $($NumberOfColumns) ) if greater than NumberOfDisks ( $($NumberOfDisks) ). exiting"
        return $false
    } 
        
    # Set the reboot flag if necessary
    if ($RebootVirtualMachine -eq $true)
    {
        $global:DSCMachineStatus = 1
    }

    #Generating VirtualDiskName/StoragePoolName/VolumeLabelName
    $NewStoragePoolName = GenerateStoragePoolName

    $NewVirtualDiskName = GenerateVirtualDiskName

    $NewLogVolumeName = GenerateLogVolumeName

    $NewDataVolumeName = GenerateDataVolumeName

    #Get Disks for storage pool
    $DisksForStoragePool = GetPhysicalDisks -DeviceID $StartingDeviceID -NumberOfDisks $NumberOfDisks

    if (!$DisksForStoragePool)
    {
        Write-Error "Unable to get any disks for creating Storage Pool. exiting"
        return $false
    }

    if ($DisksForStoragePool -and (1 -eq $NumberOfDisks))
    {
        Write-Verbose "Got $($NumberOfDisks) disks for creating Storage Pool. "
    }
    elseif ($DisksForStoragePool -and ($DisksForStoragePool.Count -eq $NumberOfDisks))
    {
        Write-Verbose "Got $($NumberOfDisks) disks for creating Storage Pool. "
    }
    else 
    {
        Write-Error "Unable to get $($NumberOfDisks) disks for creating Storage Pool. exiting"
        return $false
    }

    #Generate Storage Pool Size
    #Generate Storage Pool Size
    $PoolSizeInGB = 0
    Foreach ($CanPool in $DisksForStoragePool)
    {
        $PoolSizeInGB = $PoolSizeInGB + ($CanPool.Size)
    }  


    #Creating Storage Pool
    Write-Verbose "Creating Storage Pool $($NewStoragePoolName)"
 
    New-StoragePool -FriendlyName $NewStoragePoolName -StorageSubSystemUniqueId (Get-StorageSubSystem)[0].uniqueID -PhysicalDisks $DisksForStoragePool
    
    #Validating Storage Pool
    Verify-NewStoragePool -TimeOut 20
        
    Write-Verbose "Storage Pool $($NewStoragePoolName) created successfully."        
    
    #Creating Virtual Disk for Storage Replica
    Write-Verbose "Creating Virtual Disk $($NewVirtualDiskName)"


    if ($NumberOfColumns -eq 0)
    {   
        Write-Verbose "Creating Virtual Disk $($NewVirtualDiskName) with AutoNumberOfColumns"
        
        New-VirtualDisk -FriendlyName $NewVirtualDiskName -StoragePoolFriendlyName $NewStoragePoolName -Size $PoolSizeInGB -AutoNumberOfColumns -ResiliencySettingName Simple -ProvisioningType Thin 
    
    }
    else 
    {
        Write-Verbose "Creating Virtual Disk $($NewVirtualDiskName) with $($NumberOfColumns) number of columns"
        
        New-VirtualDisk -FriendlyName $NewVirtualDiskName -StoragePoolFriendlyName $NewStoragePoolName -Size $PoolSizeInGB -NumberOfColumns $NumberOfColumns -ResiliencySettingName Simple -ProvisioningType Thin
     
    }

    #Validating Virtual Disk
    Verify-VirtualDisk -TimeOut 20

    #Initializing Virtual Disk 
    Write-Verbose "Initializing Virtual Disk $($NewVirtualDiskName)"

    #Log and data disks must be initialized as GPT, not MBR 
    Initialize-Disk -VirtualDisk (Get-VirtualDisk -FriendlyName $NewVirtualDiskName) -PartitionStyle GPT
       
    $diskNumber = ((Get-VirtualDisk -FriendlyName $NewVirtualDiskName | Get-Disk).Number)
 
    #Create Log Partition
    Write-Verbose "Creating Log Partition $($NewLogVolumeName)"

    $LogPartitionSize = $LogVolumeSize * 1024 * 1024 * 1024
 
    New-Partition -DiskNumber $diskNumber -Size $LogPartitionSize -DriveLetter $LogVolumeLetter
    
    Verify-Partition -TimeOut 20 -DiskLetter $LogVolumeLetter
 
    #Formatting Log Volume
    Write-Verbose 'Formatting Log Volume'
    
    #All file systems that are used by Windows organize your hard disk based on cluster size (also known as allocation unit size). 
    #Cluster size represents the smallest amount of disk space that can be used to hold a file. 
    #When file sizes do not come out to an even multiple of the cluster size, additional space must be used to hold the file (up to the next multiple of the cluster size). On the typical hard disk partition, the average amount of space that is lost in this manner can be calculated by using the equation (cluster size)/2 * (number of files).  
    Format-Volume -DriveLetter $LogVolumeLetter -FileSystem NTFS -AllocationUnitSize $LogVolumeAllocationUnitSize -NewFileSystemLabel $NewLogVolumeName -Confirm:$false -Force

    Verify-Volume -TimeOut 20 -DiskLetter $LogVolumeLetter

    #Create Data Partition
    Write-Verbose "Creating Data Partition $($NewDataVolumeName)"

    $DataPartitionSize = $DataVolumeSize * 1024 * 1024 * 1024
 
    New-Partition -DiskNumber $diskNumber -Size $DataPartitionSize -DriveLetter $DataVolumeLetter
    
    Verify-Partition -TimeOut 20 -DiskLetter $DataVolumeLetter
 
    #Formatting Data Volume
    Write-Verbose 'Formatting Data Volume'
    
    #All file systems that are used by Windows organize your hard disk based on cluster size (also known as allocation unit size). 
    #Cluster size represents the smallest amount of disk space that can be used to hold a file. 
    #When file sizes do not come out to an even multiple of the cluster size, additional space must be used to hold the file (up to the next multiple of the cluster size). On the typical hard disk partition, the average amount of space that is lost in this manner can be calculated by using the equation (cluster size)/2 * (number of files).  
    Format-Volume -DriveLetter $DataVolumeLetter -FileSystem NTFS -AllocationUnitSize $DataVolumeAllocationUnitSize -NewFileSystemLabel $NewDataVolumeName -Confirm:$false -Force

    Verify-Volume -TimeOut 20 -DiskLetter $DataVolumeLetter
    
    return $true
}

function GenerateStoragePoolName
{
    $BaseName = 'S2D'

    $NewName = $BaseName + ((Get-VirtualDisk | measure).Count + 1 )

    return $NewName
}

function GenerateVirtualDiskName
{
    $BaseName = 'StorageReplica'
    
    $NewName = $BaseName + ((Get-VirtualDisk | measure).Count + 1 )
    
    return $NewName
}

function GenerateLogVolumeName
{
    $BaseName = 'SRLog'
    
    $NewName = $BaseName + ((Get-VirtualDisk | measure).Count + 1 )
    
    return $NewName
}

function GenerateDataVolumeName
{
    $BaseName = 'SRData'
    
    $NewName = $BaseName + ((Get-VirtualDisk | measure).Count + 1 )
    
    return $NewName
}

function GetPhysicalDisks
{
    param
    (
        [parameter(Mandatory = $true)]
        [System.Uint32]
        $DeviceID,

        [parameter(Mandatory = $true)]
        [System.Uint32]
        $NumberOfDisks
    )

    $upperDeviceID = $DeviceID + $NumberOfDisks - 1

    $Disks= Get-PhysicalDisk | Where-Object { ([int]$_.DeviceId -ge $DeviceID) -and ([int]$_.DeviceId -le $upperDeviceID) -and ($_.CanPool -eq $true)}

    return $Disks
}


function Verify-NewStoragePool{
    param
    (
        [parameter(Mandatory = $true)]
        [System.Uint32]
        $TimeOut
    )

   $timespan = new-timespan -Seconds $TimeOut

   $sw = [diagnostics.stopwatch]::StartNew()

    while ($sw.elapsed -lt $timespan){
        
    $StoragePool = Get-StoragePool -FriendlyName $NewStoragePoolName -ErrorAction SilentlyContinue

        if ($StoragePool){
            return $true
        }
 
        start-sleep -seconds 1
    }
 
    Write-Error "Unable to find Storage Pool $($NewStoragePoolName) after $($TimeOut)"
}

function Verify-VirtualDisk{
    param
    (
        [parameter(Mandatory = $true)]
        [System.Uint32]
        $TimeOut
    )

   $timespan = new-timespan -Seconds $TimeOut

   $sw = [diagnostics.stopwatch]::StartNew()

    while ($sw.elapsed -lt $timespan){
        
    $VirtualDisk = Get-VirtualDisk -FriendlyName $NewVirtualDiskName -ErrorAction SilentlyContinue

        if ($VirtualDisk){
            return $true
        }
 
        start-sleep -seconds 1
    }
 
    Write-Error "Unable to find Vitrual Disk $($NewVirtualDiskName) after $($TimeOut)"
}

function Verify-Partition{
    param
    (
        [parameter(Mandatory = $true)]
        [System.Uint32]
        $TimeOut,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiskLetter
    )

   $timespan = new-timespan -Seconds $TimeOut

   $sw = [diagnostics.stopwatch]::StartNew()

   while ($sw.elapsed -lt $timespan){
        
   $Partition = Get-partition -DriveLetter $DiskLetter -ErrorAction SilentlyContinue

       if ($Partition){
            return $true
       }
 
       start-sleep -seconds 1
    }
 
   Write-Error "Unable to find Partition $($DiskLetter) after $($TimeOut)"
}

function Verify-Volume{
    param
    (
        [parameter(Mandatory = $true)]
        [System.Uint32]
        $TimeOut,

        [parameter(Mandatory = $true)]
        [System.String]
        $DiskLetter
    )

   $timespan = new-timespan -Seconds $TimeOut

   $sw = [diagnostics.stopwatch]::StartNew()

   while ($sw.elapsed -lt $timespan){
        
   $Volume = Get-Volume -DriveLetter $DiskLetter -ErrorAction SilentlyContinue

       if ($Volume){
            return $true
       }
 
       start-sleep -seconds 1
    }
 
   Write-Error "Unable to find Volume $($DiskLetter) after $($TimeOut)"
}

Export-ModuleMember -Function *-TargetResource
