#require -Modules Az, AzureAD

#Configure-ClassSubscription.ps1

# TODO: Take a subscription ID or Name, set teacher(s) as "Contributor", register all Microsoft resource-providers.

param(
    $SubscriptionName
)


$AzContext = Get-AzContext

if ($null -eq $AzContext) {

	try {
		"Connecting to Azure..." | Write-Host -ForegroundColor Magenta
		$connection = Connect-AzAccount -ErrorAction Stop
		"Connected as '{0}' to Tenant '{1}' ('{2}')" -f $connection.context.Account.Id, $connection.context.Tenant.Id, $connection.context.Environment.Name | Write-Host -ForegroundColor Magenta
	} catch {
		Write-Host "An error occured while trying to connect Azure!"
		$_ | Out-string | Write-Host -ForegroundColor "Red"
		return
	}
	
} else {
	"Already connected to Azure tenant '{0}' ({1}) as '{2}' using subscription '{3}'" -f $AzContext.TenantId, $AzContext.Environment, $AzContext.Account, $azContext.SubscriptionName | Write-Host -ForegroundColor Magenta
}

$subscription = Get-AzSubscription | Where-Object Name -eq $subscriptionName


"Looking for subscription named '{0}'... " -f $subscriptionName | Write-Host -ForegroundColor Magenta

if ($null -eq $subscription) {
	"Unable to find the desired subscription, quitting." | Write-Host -ForegroundColor Red
	if ($null -ne $AzContext) {
		Disconnect-AzAccount | Out-Null
	}
	return
} else {
	"Found a {1} subscription with ID '{0}'." -f $subscription.Id, $subscription.State | Write-Host -ForegroundColor Magenta
}


try {
    Write-Host "Selecting the subscription..."
    $context = Select-AzSubscription $subscription
} catch {
    "Unable to select the subscription!:" | Write-Host -ForegroundColor Red
    $_ | Out-string | Write-Host -ForegroundColor Red
	if ($null -ne $AzContext) {
		Disconnect-AzAccount | Out-Null
	}
	
}

Get-AzResourceProvider -ListAvailable | ? ProviderNamespace -like "Microsoft*" | Register-AzResourceProvider



"Disconnecting from Azure tenant..." | Write-Host -ForegroundColor Magenta
Disconnect-AzAccount

"Done!" | Write-Host -Foreground Green