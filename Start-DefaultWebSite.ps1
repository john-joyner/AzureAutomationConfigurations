[cmdletbinding()]
Param(
    $SubscriptionID = '<Your Subscription GUID>',
    $ResourceGroup = '<Your resource group name>',
    $VMNames = @('<Azure VM name>'),
    $StorageAccount = '<Your storage account name>',
    $StorageAccountKey = '<Your storage account key>',
    $StorageContainer = '<Your storage account container such as 'scripts'>', 
    $ScriptName = 'Start-DefaultWebSite.ps1',
    $UploadScript = $false,
    $ScriptBlock = {
        import-module WebAdministration
        Start-WebSite -Name 'Default Web Site'
    }
)
<#
    
    # John Joyner @ blog.johnjoyner.net
    # Customize this script in the Param section above with your data. 
    # Paste your complete PowerShell remediation script body in the $ScriptBlock section.
    # When testing the script the first time, change the $UploadScript to $true.
    # Your PowerShell remediation script will be copied to the $StorageContainer.
    # After testing the script, change $UploadScript back to $false.
    # Save and Publish the script with the $UploadScript set to $false.

#>

################
################
#
# DO NOT CHANGE BELOW
#
################
################

function Invoke-AzureRmVmScript {
<#
    
    # Vikingur Saemundsson @ Xenit AB
    # Credit to source https://github.com/RamblingCookieMonster/PowerShell/blob/master/Invoke-AzureRmVmScript.ps1
    # Made som small modifications to allow control over if the scriptfile is uploaded or not to avoid extra data to containers and shorten the executiontime
    #

    .FUNCTIONALITY
        Azure
#>
    [cmdletbinding()]
    param(
        # todo: add various parameter niceties
        [Parameter(Mandatory = $True,
                    Position = 0,
                    ValueFromPipelineByPropertyName = $True)]
        [string[]]$ResourceGroupName,
        
        [Parameter(Mandatory = $True,
                    Position = 1,
                    ValueFromPipelineByPropertyName = $True)]
        [string[]]$VMName,
        
        [Parameter(Mandatory = $True,
                    Position = 2)]
        [scriptblock]$ScriptBlock, #todo: add file support.
        
        [Parameter(Mandatory = $True,
                    Position = 3)]
        [string]$StorageAccountName,

        [string]$StorageAccountKey, #Maybe don't use string...

        $StorageContext,
        
        [string]$StorageContainer = 'sc-scripts',
        
        [string]$Filename, # Auto defined if not specified...
        
        [string]$ExtensionName, # Auto defined if not specified

        [bool]$UploadScript = $true,

        [switch]$ForceExtension,
        [switch]$ForceBlob,
        [switch]$Force
    )
    begin
    {
        if($Force)
        {
            $ForceExtension = $True
            $ForceBlob = $True
        }
    }
    process
    {
        Foreach($ResourceGroup in $ResourceGroupName)
        {
            Foreach($VM in $VMName)
            {
                if(-not $Filename)
                {
                    $GUID = [GUID]::NewGuid().Guid -replace "-", "_"
                    $FileName = "$GUID.ps1"
                }
                if(-not $ExtensionName)
                {
                    $ExtensionName = $Filename -replace '.ps1', ''
                }

                $CommonParams = @{
                    ResourceGroupName = $ResourceGroup
                    VMName = $VM
                }

                Write-Verbose "Working with ResourceGroup $ResourceGroup, VM $VM"
                # Why would Get-AzureRMVmCustomScriptExtension support listing extensions regardless of name? /grumble
                Try
                {
                    $AzureRmVM = Get-AzureRmVM @CommonParams -ErrorAction Stop
                    $AzureRmVMExtended = Get-AzureRmVM @CommonParams -Status -ErrorAction Stop
                }
                Catch
                {
                    Write-Error $_
                    Write-Error "Failed to retrieve existing extension data for $VM"
                    continue
                }

                # Handle existing extensions
                Write-Verbose "Checking for existing extensions on VM '$VM' in resource group '$ResourceGroup'"
                $Extensions = $null
                $Extensions = @( $AzureRmVMExtended.Extensions | Where {$_.Type -like 'Microsoft.Compute.CustomScriptExtension'} )
                if($Extensions.count -gt 0)
                {
                    Write-Verbose "Found extensions on $VM`:`n$($Extensions | Format-List | Out-String)"
                    if(-not $ForceExtension)
                    {
                        Write-Warning "Found CustomScriptExtension '$($Extensions.Name)' on VM '$VM' in Resource Group '$ResourceGroup'.`n Use -ForceExtension or -Force to remove this"
                        continue
                    }
                    Try
                    {
                        # Theoretically can only be one, so... no looping, just remove.
                        $Output = Remove-AzureRmVMCustomScriptExtension @CommonParams -Name $Extensions.Name -Force -ErrorAction Stop
                        if($Output.StatusCode -notlike 'OK')
                        {
                            Throw "Remove-AzureRmVMCustomScriptExtension output seems off:`n$($Output | Format-List | Out-String)"
                        }
                    }
                    Catch
                    {
                        Write-Error $_
                        Write-Error "Failed to remove existing extension $($Extensions.Name) for VM '$VM' in ResourceGroup '$ResourceGroup'"
                        continue
                    }
                }
                
                if(-not $StorageContainer)
                {
                    $StorageContainer = 'scripts'
                }
                if(-not $Filename)
                {
                    $Filename = 'CustomScriptExtension.ps1'
                }
                if(-not $StorageContext)
                {
                    if(-not $StorageAccountKey)
                    {
                        Try
                        {
                            $StorageAccountKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroup -Name $storageAccountName -ErrorAction Stop)[0].value
                        }
                        Catch
                        {
                            Write-Error $_
                            Write-Error "Failed to obtain Storage Account Key for storage account '$StorageAccountName' in Resource Group '$ResourceGroup' for VM '$VM'"
                            continue
                        }
                    }
                    Try
                    {
                        $StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
                    }
                    Catch
                    {
                        Write-Error $_
                        Write-Error "Failed to generate storage context for storage account '$StorageAccountName' in Resource Group '$ResourceGroup' for VM '$VM'"
                        continue
                    }
                }
                If($UploadScript){
                    Write-Verbose "Uploading script to storage account $StorageAccountName"
                    Try
                    {
                        $Script = $ScriptBlock.ToString()
                        $LocalFile = [System.IO.Path]::GetTempFileName()
                        Start-Sleep -Milliseconds 500 #This might not be needed
                        Set-Content $LocalFile -Value $Script -ErrorAction Stop
            
                        $params = @{
                            Container = $StorageContainer
                            Context = $StorageContext
                        }

                        $Existing = $Null
                        $Existing = @( Get-AzureStorageBlob @params -ErrorAction Stop )

                        if($Existing.Name -contains $Filename -and -not $ForceBlob)
                        {
                            Write-Warning "Found blob '$FileName' in container '$StorageContainer'.`n Use -ForceBlob or -Force to overwrite this"
                            continue
                        }
                        $Output = Set-AzureStorageBlobContent @params -File $Localfile -Blob $Filename -ErrorAction Stop -Force
                        if($Output.Name -notlike $Filename)
                        {
                            Throw "Set-AzureStorageBlobContent output seems off:`n$($Output | Format-List | Out-String)"
                        }
                    }
                    Catch
                    {
                        Write-Error $_
                        Write-Error "Failed to generate or upload local script for VM '$VM' in Resource Group '$ResourceGroup'"
                        continue
                    }
                }

                # We have a script in place, set up an extension!
                Write-Verbose "Adding CustomScriptExtension to VM '$VM' in resource group '$ResourceGroup'"
                Try
                {
                    $Output = Set-AzureRmVMCustomScriptExtension -ResourceGroupName $ResourceGroup `
                                                                    -VMName $VM `
                                                                    -Location $AzureRmVM.Location `
                                                                    -FileName $Filename `
                                                                    -Run $Filename `
                                                                    -ContainerName $StorageContainer `
                                                                    -StorageAccountName $StorageAccountName `
                                                                    -StorageAccountKey $StorageAccountKey `
                                                                    -Name $ExtensionName `
                                                                    -TypeHandlerVersion 1.1 `
                                                                    -ErrorAction Stop

                    if($Output.StatusCode -notlike 'OK')
                    {
                        Throw "Set-AzureRmVMCustomScriptExtension output seems off:`n$($Output | Format-List | Out-String)"
                    }
                }
                Catch
                {
                    Write-Error $_
                    Write-Error "Failed to set CustomScriptExtension for VM '$VM' in resource group $ResourceGroup"
                    continue
                }

                # collect the output!
                Try
                {
                    $AzureRmVmOutput = $null
                    $AzureRmVmOutput = Get-AzureRmVM @CommonParams -Status -ErrorAction Stop
                    $SubStatuses = ($AzureRmVmOutput.Extensions | Where {$_.name -like $ExtensionName} ).substatuses
                }
                Catch
                {
                    Write-Error $_
                    Write-Error "Failed to retrieve script output data for $VM"
                    continue
                }

                $Output = [ordered]@{
                    ResourceGroupName = $ResourceGroup
                    VMName = $VM
                    Substatuses = $SubStatuses
                }

                foreach($Substatus in $SubStatuses)
                {
                    $ThisCode = $Substatus.Code -replace 'ComponentStatus/', '' -replace '/', '_'
                    $Output.add($ThisCode, $Substatus.Message)
                }

                [pscustomobject]$Output
            }
        }
    }
}
Try{
    #region Connection to Azure
    write-verbose "Connecting to Azure"
    $connectionName = "AzureRunAsConnection"

    try
    {
        # Get the connection "AzureRunAsConnection "
        $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         

        "Logging in to Azure..."
        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
    }
    catch {
        if (!$servicePrincipalConnection)
        {
            $ErrorMessage = "Connection $connectionName not found."
            throw $ErrorMessage
        } else{
            Write-Error -Message $_.Exception.Message
            throw $_.Exception
        }
    }

    Select-AzureRmSubscription -SubscriptionId $SubscriptionID
    $RG = Get-AzureRmResourceGroup -Name $ResourceGroup
    Foreach($VMName in $VMNames){
        $AzureVM = Get-AzureRmVM -Name $VMName -ResourceGroupName $RG.ResourceGroupName
    
        $Params = @{
            ResourceGroupName = $ResourceGroup
            VMName = $AzureVM.Name
            StorageAccountName = $StorageAccount
            StorageAccountKey = $StorageAccountKey
            StorageContainer = $StorageContainer
            FileName = $ScriptName
            ExtensionName = $ExtensionName
            UploadScript = $UploadScript
        }

        Invoke-AzureRmVmScript @Params -ScriptBlock $ScriptBlock -Force -Verbose
    }
}
Catch{
    Write-Error -Message $_.Exception.Message
    Exit Throw $_
}
