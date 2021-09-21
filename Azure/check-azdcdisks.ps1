<#
.SYNOPSIS
  Checks Active Directory domain controller disks in Azure to ensure disk caching is not enabled, and that sysvol is not on the temp drive.
  Must be run from an Active directory domain controller or a machine with the AD PowerShell module installed.
  Change the resource group and subscription ID as required.

.OUTPUTS
  CSV file
.NOTES
  Version:        1.0
  Author:         Arran Martindale
  Creation Date:  15/07/2021
#>

# Install powershell Az module
if (!(Get-Module -ListAvailable "AZ")) {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name Az
}

# Azure subscription ID
$AzSubscription = ""
# Azure Resource Group
$ResourceGroup = ""

# Report Folder name
$ReportFolder = "C:\temp"

# Create report folder if it doesn't exist
if (!(Test-Path $ReportFolder)) {
    New-Item -Path $ReportFolder -ItemType Directory
}

# Connect to Azure
Connect-AzAccount

# Set the subscription to manage it
Set-AzContext -Subscription $AzSubscription

# Get list of Azure VMs
$VmList = Get-AzVM -ResourceGroupName $ResourceGroup

# Get list of domain controllers
$DomainControllers = Get-ADDomainController -filter * | Select-Object -ExpandProperty Name
$DomainDn = (Get-ADDomain).DistinguishedName

$DomConArray = @()
foreach ($vm in $VmList | Where-Object { $_.name -in $DomainControllers }) {
    $VmHostName = $vm.OSProfile.ComputerName
    #get the location of Sysvol on the domain controller disk
    $SysVolPath = Get-ADObject "CN=SYSVOL Subscription,CN=Domain System Volume,CN=DFSR-LocalSettings,CN=$VmHostName,OU=Domain Controllers,$DomainDn" -properties msDFSR-RootPath | Select-Object -expand "msDFSR-RootPath"
    $item = New-Object PSObject
    $item | Add-Member -type NoteProperty -Name VmName -Value $vm.name
    $item | Add-Member -type NoteProperty -Name SysvolLocation -Value $SysVolPath
    if ($SysVolPath -like "C:\Windows\*") {
        # Sysvol is on C drive, so check Azure OS disk for caching
        $item | Add-Member -type NoteProperty -Name SysvolAzureDrive -Value "OS Disk"
        $item | Add-Member -type NoteProperty -Name SysvolDriveCaching -Value $vm.StorageProfile.OsDisk.Caching
    }
    elseif ($SysVolPath -like "D:\*") {
        # Sysvol is on a different drive, get location and check Azure data disk for caching
        $item | Add-Member -type NoteProperty -Name SysvolAzureDrive -Value "TEMP DRIVE"
        $item | Add-Member -type NoteProperty -Name SysvolDriveCaching -Value "TEMP DRIVE"
    }

    else {
        # Split the sysvol path to get the drive letter, before the : character
        $DriveLetter = $SysVolPath.split(":")[0]
        $AzureLunId = Invoke-Command -ComputerName $VmHostName -ScriptBlock {
            # Get the Lun Path. This is a long SCSI identifier
            $WindowsLunId = (Get-Disk -Number ((Get-Partition -DriveLetter $Using:DriveLetter).DiskNumber)).Path
            # Split the Lun Path by the hash character and take 3rd value. Then find the last letter of that value eg 000001. The last number is the Azure LUN ID. Convert to integer
            [convert]::ToInt32(($WindowsLunId.split("#")[2])[-1], 10)           
        }
        $dataDisk = $vm.StorageProfile.DataDisks | Where-Object { $_.Lun -eq $AzureLunId }
        $dataDisk = $vm.StorageProfile.DataDisks | Where-Object { $_.Lun -eq $AzureLunId }

        $item | Add-Member -type NoteProperty -Name SysvolAzureDrive -Value $dataDisk.name
        $item | Add-Member -type NoteProperty -Name SysvolDriveCaching -Value $dataDisk.caching
    }
    $DomConArray += $item
}

# Export to CSV
$DomreportName = $ReportFolder + "\" + $ResourceGroup + "-DomainControllerReport.csv"
$DomConArray | Export-Csv $DomReportName -NoTypeInformation
