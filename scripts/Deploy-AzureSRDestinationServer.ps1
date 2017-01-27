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

#Sign-in with Azure account

    $Error.Clear()

    Login-AzureRmAccount

#Select Azure Subscription

    $subscriptionId = 
        ( Get-AzureRmSubscription |
            Out-GridView `
              -Title "Select an Azure Subscription ..." `
              -PassThru
        ).SubscriptionId

    Select-AzureRmSubscription `
        -SubscriptionId $subscriptionId

#Specify unique deployment name prefix (up to 6 alphanum chars)

    $NamePrefix = -join ((97..122) | Get-Random -Count 6 | % {[char]$_})

#Specify deployment parameters

    $VMSize = "Standard_DS13_v2"

    $enableAcceleratedNetworking = $false

    $VMDiskSize = 1023

    $DomainName = Read-Host -Prompt 'Input the Active Directory Domain name'

    $AdminCreds = Get-Credential -Message "Enter Admin Username and Password for existing AD Domain"

    $AdminUsername = $AdminCreds.UserName

    $AdminPassword = $AdminCreds.GetNetworkCredential().Password

    $SRSourceComputer = Read-Host -Prompt 'Input the Storage Replica source name'

    $SRSourceDataDrive = Read-Host -Prompt 'Input the Storage Replica source data volume letter'

    $SRSourceLogDrive = Read-Host -Prompt 'Input the Storage Replica source log volume letter (minimum 9GB)'

    $replicationMode = 'asynchronous'

    $SRAsyncRPO = 300

    $artifactsLocation = "https://raw.githubusercontent.com/albertwo1978/301-storage-replica-md/master"

    $artifactsLocationSasToken = ""

#Specify deployment values for Storage Replica Destination

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

#Specify source volume characteristics

    $SRSourceCIM = new-cimSession -ComputerName $SRSourceComputer

    $SRDataVolumeSize = (Get-Partition -CimSession $SRSourceComputer -DriveLetter $SRSourceDataDrive).Size /1GB

    $SRDataVolumeAllocationUnitSize = (Get-Volume -CimSession $SRSourceComputer -DriveLetter $SRSourceDataDrive).AllocationUnitSize

    $SRLogVolumeSize = (Get-Partition -CimSession $SRSourceComputer -DriveLetter $SRSourceLogDrive).Size /1GB

    $SRLogVolumeAllocationUnitSize = (Get-Volume -CimSession $SRSourceComputer -DriveLetter $SRSourceLogDrive).AllocationUnitSize

#Add disks to match total volume size

$VMDiskCount = 1

Do{

    $VMDiskCount = $VMDiskCount + 1

    If($VMDiskCount -gt 32) {Write-Output "Total volume exceeds maximum disks for Azure Vitual Machine. Exiting script."; exit}

} Until (($VMDiskSize * $VMDiskCount) -gt ($SRDataVolumeSize + $SRLogVolumeSize))

#Define hash table for parameter values

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

try
{

    #Storage Replica destination template deployment

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

