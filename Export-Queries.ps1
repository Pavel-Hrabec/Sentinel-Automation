#export only the saved search categories specified in the $Categories variable below.

param (
    [Parameter(Mandatory = $true)]
    [string]$WorkSpaceName,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName

)
# Only export saved queries from these categories - comma separated

$Categories = ("Hunting Queries")

(Get-AzOperationalInsightsSavedSearch -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkSpaceName).Value.Properties | Where-Object { $Categories -contains $_.Category } | ConvertTo-Json -depth 100