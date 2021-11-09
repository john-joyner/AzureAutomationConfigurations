<#PSScriptInfo
.VERSION 1.0
.GUID 97dd6686-aedb-4951-b850-4ef1350ab881
.AUTHOR John Joyner
.COMPANYNAME AccountabilIT
.COPYRIGHT 
.TAGS AzureAutomation AzureArc AzureVM
.LICENSEURI 
.PROJECTURI Get-ComputerStatus.ps1
.ICONURI 
.EXTERNALMODULEDEPENDENCIES 
.REQUIREDSCRIPTS 
.EXTERNALSCRIPTDEPENDENCIES 
.RELEASENOTES
#>

#Requires -Module Az.Account
#Requires -Module Az.Compute
#Requires -Module Az.ResourceGraph
#Requires -Module AzureAD

<#
.SYNOPSIS 
    Given a computer name, returns the Azure VM or Azure Arc server status.
.DESCRIPTION
    Inspects the Azure Resource Manager status flag of the Azure VM or Azure Arc server resource.
    Requires that AzureRunAsConnection is already created before running.
.PARAMETER VMName
    Required. The name of the Azure VM or Azure Arc server. Can be an FQDN or single hostname. 
.EXAMPLE
    Get-ComputerStatus.ps1 -VMName "MyComputerName" 
.NOTES
    AUTHOR: John Joyner
    LASTEDIT: April 4, 2021  
#>

Param (
    [Parameter (Mandatory = $true)][string] $VMName
)

#convert FQDN to hostname
$hostname = [regex]::Escape( $VMName.split( '.', 2 )[0] )

#log into Azure AD using Azure Automation RunAs connection to retrieve service principal credential
$connectionName = "AzureRunAsConnection"
$servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         
Connect-AzureAD -TenantId $servicePrincipalConnection.TenantId -ApplicationId $servicePrincipalConnection.ApplicationId -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

#log into Azure subscription using service principal credential
$TenantId = $servicePrincipalConnection.TenantId
$ApplicationId = $servicePrincipalConnection.ApplicationId
$Thumbprint = $servicePrincipalConnection.CertificateThumbprint
Connect-AzAccount -ServicePrincipal -CertificateThumbprint $Thumbprint -ApplicationId $ApplicationId -TenantId $TenantId | Out-Null

#if Azure VM will return data
$vm = Get-AzVM -WarningAction Ignore -Name $hostname

#if no data returned, not Azure VM, might be Azure Arc server
if($vm -eq $null) {
    "Non-Azure VM detected, possible Azure Arc server"
    Import-Module -Name Az.ResourceGraph
    #if Azure Arc server will return data
    #Azure Connected Machine agent requires 10 additional minutes wait
    Start-Sleep 600 
    $vm = Search-AzGraph -Query "Resources | where (( type =~ 'microsoft.hybridcompute/machines' ) and ( properties notcontains 'Disconnected' )) and (( type =~ 'microsoft.hybridcompute/machines' ) and ( properties contains '$hostname' )) "
    #if no data returned, Azure Arc server status is Offline or Unknown, or resource is not an Azure Arc server
        if($vm -eq $null) {
        "$VMName status is: Not Connected or Unknown"
        } else {
        #if data retuned, Azure Arc server is connected
        "$VMName Azure Arc server status is: Connected"    
        }
    } else {
#if data retuned, object is an Azure VM
"Azure VM detected"
$vmStatus = Get-AzVM -ResourceGroupName $vm.ResourceGroupName -Name $hostname -Status -WarningAction Ignore
$vmAgentDisplayStatus = $vmStatus.VMAgent.Statuses[0].DisplayStatus
#if Azure VM is deallocated $vmAgentDisplayStatus is not retured, in that case report Not Ready
if ($vmAgentDisplayStatus -eq $null) {
    "$VMName Azure VM status is: Not Ready (deallocated)"
    } else {       
    "$VMName Azure VM status is: $vmAgentDisplayStatus" }
}