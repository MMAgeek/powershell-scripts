<#
.SYNOPSIS
  Exports Active Directory information for analysis or import into a lab environment

.DESCRIPTION
  This script does the following:
  Exports a csv file of users from Active directory, with common attributes such as SamAccountName, GivenName, Surname, DistinguishedName, ProfilePath, ScriptPath, HomeDirectory, HomeDrive.
  Exports a csv file of the OU structure
  Exports a csv file of group names and memberships
  Exports all the group policy objects, 1 html file per group policy object

.PARAMETER <Parameter_Name>
  None

.INPUTS
  None

.OUTPUTS
  CSV files for Users, OUs and Groups.
  HTML files for GPOs

.NOTES
  Version:        1.1
  Author:         Arran Martindale
  Creation Date:  15/07/2018
  Purpose/Change: Resolved GPO export issue

.EXAMPLE
./export-adinfo.ps1
#>

#---------------------------------------------------------[Script Parameters]------------------------------------------------------

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

# Set Error Action to Stop, to stop the script if it can't import the required modules
$ErrorActionPreference = 'stop'

# Import the ActiveDirectory Module 
Import-Module ActiveDirectory 

#----------------------------------------------------------[Declarations]----------------------------------------------------------

# Set the directory to output to
$ExportDir = "C:\temp"

# Filename for AD users export
$UsersFile = "$ExportDir\adusers.csv"

# Filename for AD OU export
$OUsFile = "$ExportDir\adOUs.csv"

# Filename for AD groups export
$GroupsFile = "$ExportDir\adgroups.csv"

# Set the subdirectory to export Group policy configuration to
$GpoDir = "$ExportDir\gpos"

#-----------------------------------------------------------[Functions]------------------------------------------------------------

#-----------------------------------------------------------[Execution]------------------------------------------------------------

# Create temp directory if it doesnt exist
if (!(Test-Path -Path $ExportDir )) {
    New-Item -ItemType directory -Path $ExportDir
}

#### Export a list of AD users with their profile and script information ####
Get-ADUser -Properties * -Filter * | Select-Object SamAccountName, GivenName, Surname, DistinguishedName, ProfilePath, ScriptPath, HomeDirectory, HomeDrive | Export-Csv -Path $UsersFile -NoTypeInformation   

##### Exports the domains OU structure ####
$OUs = Get-ADOrganizationalUnit -filter * | Select-Object Name, DistinguishedName
Add-Content -Path $OUsFile  -Value '"Name","Path"'
foreach ($OU in $OUs) {
    $OUName = $OU.Name
    $OUParent = (([adsi]"LDAP://$($OU.DistinguishedName)").Parent).Substring(7)
    $tabledata = @(
        "`"$OUName`",`"$OUParent`""
    )
    $tabledata | Add-content -Path $OUsFile 
}

#### Exports Group names and their members ####
# Create empty array
$CSVOutput = @() 
 
# Get all AD groups in the domain 
$ADGroups = Get-ADGroup -Filter * 
 
# Set progress bar variables 
$i = 0 
$tot = $ADGroups.count 
 
foreach ($ADGroup in $ADGroups) { 
    # Set up progress bar 
    $i++ 
    $status = "{0:N0}" -f ($i / $tot * 100) 
    Write-Progress -Activity "Exporting AD Groups" -status "Processing Group $i of $tot : $status% Completed" -PercentComplete ($i / $tot * 100) 
 
    # Ensure Members variable is empty 
    $Members = "" 
 
    # Get group members which are also groups and add to string 
    $MembersArr = Get-ADGroup -filter {Name -eq $ADGroup.Name} | Get-ADGroupMember | Select-Object Name 
    if ($MembersArr) { 
        foreach ($Member in $MembersArr) { 
            $Members = $Members + "," + $Member.Name 
        } 
        $Members = $Members.Substring(1, ($Members.Length) - 1) 
    } 
 
    # Set up hash table and add values 
    $HashTab = $NULL 
    $HashTab = [ordered]@{ 
        "Name"     = $ADGroup.Name 
        "Category" = $ADGroup.GroupCategory 
        "Scope"    = $ADGroup.GroupScope 
        "Path"    = $ADGroup.DistinguishedName
        "Members"  = $Members 
    } 
 
    # Add hash table to CSV data array 
    $CSVOutput += New-Object PSObject -Property $HashTab 
} 
 
# Export to CSV file
$CSVOutput | Sort-Object Name | Export-Csv $GroupsFile -NoTypeInformation 
 
##### Export group policy settings ####

# Create the gpo subdir if it doesn't exist
if (!(Test-Path -Path $GpoDir )) {
    New-Item -ItemType directory -Path $GpoDir
}

$GPOs = get-GPO -All

# Export all the group policy objects as html files
foreach ($gpo in $GPOs) {
$GpoName = $gpo.DisplayName
    Get-GPOReport -Name $GpoName -ReportType "html" -Path "$GpoDir\$GpoName.html"
}

# Notify that the script is complete
Write-Host " Script is complete!" -ForegroundColor green