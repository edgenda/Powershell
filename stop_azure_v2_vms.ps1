<#
.SYNOPSIS
  Connects to Azure and stops of all VMs in the specified Azure subscription or resource group

.DESCRIPTION
  This runbook connects to Azure and stops all VMs in an Azure subscription or resource group.  
  You can attach a schedule to this runbook to run it at a specific time. Note that this runbook does not stop
  Azure classic VMs. Use https://gallery.technet.microsoft.com/scriptcenter/Stop-Azure-Classic-VMs-7a4ae43e for that.

  REQUIRED AUTOMATION ASSETS
  1. An Automation variable asset called "AzureSubscriptionId" that contains the GUID for this Azure subscription.  
     To use an asset with a different name you can pass the asset name as a runbook input parameter or change the default value for the input parameter.
  2. An Automation credential asset called "AzureCredential" that contains the Azure AD user credential with authorization for this subscription. 
     To use an asset with a different name you can pass the asset name as a runbook input parameter or change the default value for the input parameter.

PARAMETER AzureCredentialAssetName
   Optional with default of "AzureCredential".
   The name of an Automation credential asset that contains the Azure AD user credential with authorization for this subscription. 
   To use an asset with a different name you can pass the asset name as a runbook input parameter or change the default value for the input parameter.

.PARAMETER AzureSubscriptionIdAssetName
   Optional with default of "AzureSubscriptionId".
   The name of An Automation variable asset that contains the GUID for this Azure subscription.
   To use an asset with a different name you can pass the asset name as a runbook input parameter or change the default value for the input parameter.

.PARAMETER ResourceGroupName
   Optional
   Allows you to specify the resource group containing the VMs to stop.  
   If this parameter is included, only VMs in the specified resource group will be stopped, otherwise all VMs in the subscription will be stopped.  

.NOTES
   Based on the original "Stop Azure V2 VMs" script by
   AUTHOR: System Center Automation Team 
   LASTEDIT: January 7, 2016
#>

param (
#    [Parameter(Mandatory=$false)] 
#    [String]  $AzureCredentialAssetName = 'AzureCredential',
        
    [Parameter(Mandatory=$false)]
    [String] $AzureSubscriptionIdAssetName = 'AzureSubscriptionId',

    [Parameter(Mandatory=$false)] 
    [String] $ResourceGroupName
)

# Returns strings with status messages
[OutputType([String])]

$connectionName = "AzureRunAsConnection"
$servicePrincipalConnection = Get-AutomationConnection -Name $connectionName
"Logging into Azure..."
$null = Add-AzureRmAccount `
	-ServicePrincipal `
	-TenantId $servicePrincipalConnection.TenantId `
	-ApplicationId $servicePrincipalConnection.ApplicationId `
	-CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
	-ErrorAction Stop `
	-ErrorVariable err

# Connect to Azure and select the subscription to work against
#$Cred = Get-AutomationPSCredential -Name $AzureCredentialAssetName -ErrorAction Stop
#$null = Add-AzureRmAccount -Credential $Cred -ErrorAction Stop -ErrorVariable err

if($err) {
	throw $err
}

$SubId = Get-AutomationVariable -Name $AzureSubscriptionIdAssetName -ErrorAction Stop

# If there is a specific resource group, then get all VMs in the resource group,
# otherwise get all VMs in the subscription.
if ($ResourceGroupName) 
{ 
	$VMs = Get-AzureRmVM -ResourceGroupName $ResourceGroupName
}
else 
{ 
	$VMs = Get-AzureRmVM
}

# Stop each of the VMs
foreach ($VM in $VMs)
{
    $VMDetail = $VM | Get-AzureRmVM -Status

    foreach ($VMStatus in $VMDetail.Statuses)
    { 
        if($VMStatus.Code -like "PowerState/*")
        {
            $VMStatusDetail = $VMStatus.DisplayStatus
        }
    }

    Write-Output ("Current VM: " + $VM.Name);
    Write-Output ($VM.Name + " status is '" + $VMStatusDetail + "'");

    if ($VMStatusDetail -eq "VM deallocated")
    {
        Write-Output ("Not attempting to stop " + $VM.Name + " as it's aleady deallocated.")
    }
    else 
    {
        $StopRtn = $VM | Stop-AzureRmVM -Force -ErrorAction Continue

#   Write-Output ("Stop Status:")
#   Write-Output ($StopRtn.StatusCode)

        if ($StopRtn.IsSuccessStatusCode -ne $True)
        {
            # The VM failed to stop, so send notice
            Write-Output ($VM.Name + " failed to stop")
            Write-Error ($VM.Name + " failed to stop. Error was:") -ErrorAction Continue
            Write-Error ($StopRtn.ReasonPhrase) -ErrorAction Continue
        }
        else
        {
            # The VM stopped, so send notice
            Write-Output ($VM.Name + " has been stopped")
        }
    }   
}