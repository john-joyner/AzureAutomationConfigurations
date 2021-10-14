<#PSScriptInfo
.VERSION 1.0
.GUID d41ec1aa-f177-40eb-a6eb-3d200f878b901
.AUTHOR John Joyner
.COMPANYNAME AccountabilIT
.COPYRIGHT 
.TAGS AzureAutomation AzureArc AzureVM
.LICENSEURI 
.PROJECTURI FGT-add-IP-to-group.ps1
.ICONURI 
.EXTERNALMODULEDEPENDENCIES 
.REQUIREDSCRIPTS 
.EXTERNALSCRIPTDEPENDENCIES 
.RELEASENOTES
#>

#Requires -Module Orchestrator.AssetManagement.Cmdlets
#Requires -Module PowerFGT

<#
.SYNOPSIS 
    Given an IP, adds the IP to a Fortinet firewall block list.
.DESCRIPTION
    Performs on-demand blocking of IPs identified in an Azure Sentinel incident.
    Requires that Azure Automation credential "PowerFGT Credential" is already created before running.
    Edit the device address in this script to match the IP of your Fortinet device (192.168.1.99 in the sample).
.PARAMETER VMName
    Required. The IP address to add to the firewall block list. 
.EXAMPLE
    FGT-add-IP-to-group.ps1 -IP "1.2.3.4" 
.NOTES
    AUTHOR: John Joyner
    LASTEDIT: October 14, 2021  
#>


Param (
    [Parameter (Mandatory = $true)][string] $IP
)

Import-Module Orchestrator.AssetManagement.Cmdlets
$myCred = Get-AutomationPSCredential -Name "PowerFGT Credential"
$userName = $myCred.UserName
$securePassword = $myCred.Password
$password = $myCred.GetNetworkCredential().Password | ConvertTo-SecureString -AsPlainText -Force

Import-Module PowerFGT
Connect-FGT 192.168.1.99 -Username $userName -Password $password -SkipCertificateCheck
Add-FGTFirewallAddress -Name $IP -ip $IP -mask 255.255.255.255
Get-FGTFirewallAddressGroup -name "Blocked Address Group" | Add-FGTFirewallAddressGroupMember -member $IP