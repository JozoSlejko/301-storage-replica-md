#-------------------------------------------------------------------------
# Copyright (c) Microsoft.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#--------------------------------------------------------------------------

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$SRSourceComputer,

    [string]$SRSourceDataDrive="F",

    [string]$SRSourceLogDrive="G",

    [string]$DomainName=$env:USERDNSDOMAIN
)

$ErrorActionPreference="Stop"

#Install AzureRM PowerShell modules on Admin PC

If ("AzureRM" -inotin (Get-Package).Name) { 

    Install-Package `
        -Name AzureRM `
        -Confirm:$false `
        -Force

}

#Sign-in with Azure account

$session = Login-AzureRmAccount 

#Select Azure Subscription

$subscriptionId = 
    ( Get-AzureRmSubscription |
        Out-GridView `
            -Title "Select an Azure Subscription ..." `
            -PassThru
    ).SubscriptionId

$subscription =
    Select-AzureRmSubscription `
    -SubscriptionId $subscriptionId

#Specify unique deployment name prefix (up to 6 alphanum chars)

$NamePrefix = -join ((97..122) | Get-Random -Count 6 | % {[char]$_})

#Enter Domain Admin Credentials

$AdminCreds = Get-Credential -Message "Enter Domain Admin credentials for your AD Domain"
$AdminUsername = $AdminCreds.UserName
$AdminPassword = $AdminCreds.GetNetworkCredential().Password

#Specify deployment values for Storage Replica target in Azure

$enableAcceleratedNetworking = $false
$VMDiskSize = 1023
$SRSourceComputer = $SRSourceComputer.ToLower()
$SRSourceDataDrive = $SRSourceDataDrive.Substring(0,1)
$SRSourceLogDrive = $SRSourceLogDrive.Substring(0,1)
$replicationMode = 'asynchronous'
$SRAsyncRPO = 300
$artifactsLocation = "https://raw.githubusercontent.com/albertwo1978/301-storage-replica-md/master"
$artifactsLocationSasToken = ""
$SRTemplateName = "azuredeploy.json"
$SRDeploymentName = "${NamePrefix}-srdest-deploy"

$SRRGName =
    ( Get-AzureRmResourceGroup |
        Out-GridView `
            -Title "Select Azure Resource Group for Storage Replica Destination VM. This Resource Group should already have an existing virtual network where the destination VM will deploy" `
            -PassThru
    ).ResourceGroupName

$SRRegionRG = 
    Get-AzureRmResourceGroup `
        -Name $SRRGName

$SRRegion =
    $SRRegionRG.Location

$SRVnetName = 
    ( Get-AzureRmVirtualNetwork `
        -ResourceGroupName $SRRGName 
    ).Name | 
    Out-GridView `
        -Title "Select a VNET to deploy Storage Replica Destionation VM" `
        -PassThru

$SRVnet = 
    Get-AzureRmVirtualNetwork `
        -ResourceGroupName $SRRGName `
        -Name $SRVnetName

$SRSubnetName = 
    ( Get-AzureRmVirtualNetworkSubnetConfig `
        -VirtualNetwork $SRVnet
    ).Name | 
    Out-GridView `
        -Title "Select a Subnet within the destination vNet." `
        -PassThru

#Specify source volume characteristics for Storage Replica target to match Source

$SRSourceCIM = 
    New-CimSession -ComputerName $SRSourceComputer

[int]$SRDataVolumeSize = 
    [Math]::Ceiling((Get-Volume -CimSession $SRSourceComputer -DriveLetter $SRSourceDataDrive).Size /1GB)

$SRDataVolumeAllocationUnitSize = 
    (Get-Volume -CimSession $SRSourceComputer -DriveLetter $SRSourceDataDrive).AllocationUnitSize

[int]$SRLogVolumeSize = 
    [Math]::Ceiling((Get-Volume -CimSession $SRSourceComputer  -DriveLetter $SRSourceLogDrive).Size /1GB)

$SRLogVolumeAllocationUnitSize = 
    (Get-Volume -CimSession $SRSourceComputer -DriveLetter $SRSourceLogDrive).AllocationUnitSize

#Determine # of data disks for Azure VM Storage Replica Target

$MaxDiskCount =
    ((Get-AzureRmVmSize -Location $SRRegion | Where-Object Name -Like 'Standard_DS*_v2').MaxDataDiskCount | Sort-Object -Descending)[0]

$VMDiskCount = 1

Do {

    $VMDiskCount++

    If( $VMDiskCount -gt $MaxDiskCount ) { 
        Write-Output "Total volume exceeds maximum disks for Azure Virtual Machine. Exiting script."
        Exit 
    }

} Until (($VMDiskSize * $VMDiskCount) -gt ($SRDataVolumeSize + $SRLogVolumeSize))

#Determine Azure VM Size based on # of data disks needed

$VMSize = 
    ((Get-AzureRmVMSize -Location $SRRegion | 
        Where-Object Name -Like 'Standard_DS*_v2' | 
        Sort-Object MaxDataDiskCount | 
        Where-Object MaxDataDiskCount -ge $VMDiskCount).Name)[0]

#Prepare source server with Windows Features for Storage Replica

$result = 
    (Install-WindowsFeature `
        -ComputerName $SRSourceComputer `
        -Name FS-FileServer, 
                Storage-Replica, 
                RSAT-Storage-Replica, 
                FS-SMBBW
    ).RestartNeeded

if ( $result -eq "Yes" ) { 

    Restart-Computer -ComputerName $SRSourceComputer -Confirm:$true

}

#Define hash table for ARM Template parameter values

$ARMTemplateParams = @{
    "namePrefix" = "$NamePrefix";
    "vmSize" = "$VMSize";
    "enableAcceleratedNetworking" = $enableAcceleratedNetworking;
    "vmDiskSize" = $VMDiskSize;
    "vmDiskCount" = $VMDiskCount;
    "existingDomainName" = "$DomainName";
    "adminUsername" = "$AdminUserName";
    "adminPassword" = "$AdminPassword";
    "existingVirtualNetworkRGName" = "$SRRGName"; 
    "existingVirtualNetworkName" = "$SRVnetName";
    "existingSubnetName" = "$SRSubnetName";
    "sourceComputerName" = "$SRSourceComputer";
    "logVolumeLetter" = "$SRSourceLogDrive";
    "logVolumeSize" = $SRLogVolumeSize;
    "logVolumeAllocationUnitSize" = $SRLogVolumeAllocationUnitSize;
    "dataVolumeLetter" = "$SRSourceDataDrive";
    "dataVolumeSize" = $SRDataVolumeSize;
    "dataVolumeAllocationUnitSize" = $SRDataVolumeAllocationUnitSize;
    "replicationMode" = "$replicationMode";
    "AsyncRPO" = $SRAsyncRPO;
    "_artifactsLocation" = "$artifactsLocation";
    "_artifactsLocationSasToken" = "$artifactsLocationSasToken"
}

#Deploy Storage Replica target to Azure via ARM template deployment

try
{
    
    New-AzureRmResourceGroupDeployment `
        -Name $SRDeploymentName `
        -ResourceGroupName $SRRGName `
        -TemplateParameterObject $ARMTemplateParams `
        -TemplateUri "${artifactsLocation}/${SRTemplateName}${artifactsLocationSasToken}" `
        -Mode Incremental `
        -ErrorAction Stop `
        -Confirm

}
catch 
{
    Write-Error -Exception $_.Exception
}


#Clear deployment parameters

$ARMTemplateParams = @{}
