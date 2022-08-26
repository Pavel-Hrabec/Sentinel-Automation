## Globals ##
$CloudEnv = $Env:cloudEnv
$ResourceGroupName = $Env:resourceGroupName
$WorkspaceName = $Env:workspaceName
$WorkspaceId = $Env:workspaceId
$Directory = $Env:directory
$Creds = $Env:creds
$contentTypes = $Env:contentTypes
$WorkspaceKey = $Env:workspaceKey
$contentTypeMapping = @{
    "AnalyticsRule"=@("Microsoft.OperationalInsights/workspaces/providers/alertRules", "Microsoft.OperationalInsights/workspaces/providers/alertRules/actions");
    "AutomationRule"=@("Microsoft.OperationalInsights/workspaces/providers/automationRules");
    "HuntingQuery"=@("Microsoft.OperationalInsights/workspaces/savedSearches");
    "Parser"=@("Microsoft.OperationalInsights/workspaces/savedSearches");
    "Playbook"=@("Microsoft.Web/connections", "Microsoft.Logic/workflows", "Microsoft.Web/customApis");
    "Workbook"=@("Microsoft.Insights/workbooks");
}
$sourceControlId = $Env:sourceControlId 
$rootDirectory = $Env:rootDirectory
$githubAuthToken = $Env:githubAuthToken
$githubRepository = $Env:GITHUB_REPOSITORY
$branchName = $Env:branch
$smartDeployment = $Env:smartDeployment
$csvPath = "$rootDirectory\.sentinel\tracking_table_$sourceControlId.csv"
$configPath = "$rootDirectory\sentinel-deployment.config"
$global:localCsvTablefinal = @{}
$global:updatedCsvTable = @{}
$global:parameterFileMapping = @{}
$global:prioritizedContentFiles = @()
$global:excludeContentFiles = @()

$guidPattern = '(\b[0-9a-f]{8}\b-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-\b[0-9a-f]{12}\b)'
$namePattern = '([-\w\._\(\)]+)'
$sentinelResourcePatterns = @{
    "AnalyticsRule" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.OperationalInsights/workspaces/$namePattern/providers/Microsoft.SecurityInsights/alertRules/$namePattern"
    "AutomationRule" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.OperationalInsights/workspaces/$namePattern/providers/Microsoft.SecurityInsights/automationRules/$namePattern"
    "HuntingQuery" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.OperationalInsights/workspaces/$namePattern/savedSearches/$namePattern"
    "Parser" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.OperationalInsights/workspaces/$namePattern/savedSearches/$namePattern"
    "Playbook" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.Logic/workflows/$namePattern"
    "Workbook" = "/subscriptions/$guidPattern/resourceGroups/$namePattern/providers/Microsoft.Insights/workbooks/$namePattern"
}

if ([string]::IsNullOrEmpty($contentTypes)) {
    $contentTypes = "AnalyticsRule"
}

$DataIngestionRepoParam = "DataIngestionRepoParam.json"
@"
{
    "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "WorkspaceID": {
            "type": "string",
            "value": "$WorkspaceId"
        },
        "WorkspaceKey": {
            "type": "string",
            "value": "$WorkspaceKey"
        }
    }
}
"@ | Out-File -FilePath $DataIngestionRepoParam

$metadataFilePath = "metadata.json"
@"
{
    "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "parentResourceId": {
            "type": "string"
        },
        "kind": {
            "type": "string"
        },
        "sourceControlId": {
            "type": "string"
        },
        "workspace": {
            "type": "string"
        },
        "contentId": {
            "type": "string"
        }
    },
    "variables": {
        "metadataName": "[concat(toLower(parameters('kind')), '-', parameters('contentId'))]"
    },
    "resources": [
        {
            "type": "Microsoft.OperationalInsights/workspaces/providers/metadata",
            "apiVersion": "2022-01-01-preview",
            "name": "[concat(parameters('workspace'),'/Microsoft.SecurityInsights/',variables('metadataName'))]",
            "properties": {
                "parentId": "[parameters('parentResourceId')]",
                "kind": "[parameters('kind')]",
                "source": {
                    "kind": "SourceRepository",
                    "name": "Repositories",
                    "sourceId": "[parameters('sourceControlId')]"
                }
            }
        }
    ]
}
"@ | Out-File -FilePath $metadataFilePath 
$resourceTypes = $contentTypes.Split(",") | ForEach-Object { $contentTypeMapping[$_] } | ForEach-Object { $_.ToLower() }
$MaxAttempts = 5
$initialSecondsBetweenAttempts = 5
$Directory = $(get-location).Path;
$csvPath = "$rootDirectory\.sentinel\tracking_table_$sourceControlId.csv"
$configPath = "$rootDirectory\sentinel-deployment.config"
$global:localCsvTablefinal = @{}
$global:updatedCsvTable = @{}
$global:parameterFileMapping = @{}
$global:prioritizedContentFiles = @()
$global:excludeContentFiles = @()

#Converts hashtable to string that can be set as content when pushing csv file
function ConvertTableToString {
    $output = "FileName, CommitSha`n"
    $global:updatedCsvTable.GetEnumerator() | ForEach-Object {
        $key = RelativePathWithBackslash $_.Key
        $output += "{0},{1}`n" -f $key, $_.Value
    }
    return $output
}

$base64AuthInfo= [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($systemAccessToken)"))
$header = @{Authorization=("Basic {0}" -f $base64AuthInfo)}

#Gets all files and commit shas using Get Items API 
function GetItems() {
    $body = @{
        recursionLevel = "full"
        latestProcessedChange = "true"
        "versionDescriptor.version" = $branchName
    }  
    $shaResult = AttemptInvokeRestMethod "Get" "$collectionUri/$projectId/_apis/git/repositories/$repositoryName/items?api-version=6.0" $body $null 3
    return $shaResult
}

#Gets objectId of branch so that it can be used to update csv
function GetBranchObjectId {
    $body = @{filterContains = $branchName}
    $result = AttemptInvokeRestMethod "Get" "$collectionUri/$projectId/_apis/git/repositories/$repositoryName/refs?api-version=6.0" $body $null 3
    $objectId = $result.value.objectId
    return $objectId
}

#Creates a table using the reponse from the items api, creates a table 
function GetCommitShaTable($getItemsResponse) {
    $shaTable = @{}
    $getItemsResponse.value | ForEach-Object {
        $truePath =  AbsolutePathWithSlash $_.path
        if (([System.IO.Path]::GetExtension($_.path) -eq ".json") -or ($truePath -eq $configPath))
        {
            $shaTable.Add($truePath, $_.latestProcessedChange.commitId)
        }
    }
    return $shaTable
}

#Pushes new/updated csv file to the user's repository. If updating file, will need csv commit sha. 
function PushCsvToRepo($csvExists) {
    $status = if ($csvExists) {"edit"} else {"add"}
    $objectId = GetBranchObjectId
    $content = ConvertTableToString  
    $contentType = "application/json"
    $relativeCsvPath = RelativePathWithBackslash $csvPath

    $body = @{
        refUpdates = @(@{
            name = "refs/heads/$branchName"
            oldObjectId = $objectId
        })
        commits = @(@{
            "comment" = "Added $csvPath"
            "changes" = @(@{
                "changeType" = $status
                "item" = @{path = $relativeCsvPath}
                "newContent" = @{
                    "content" = $content
                    "contentType" = "rawtext"}
            })
        })
    } | ConvertTo-Json -Depth 5

    $Parameters = @{
        Method      = "Post"
        Uri         = "$collectionUri/$projectId/_apis/git/repositories/$repositoryName/pushes?api-version=6.0"
        Headers     = $header
        Body        = $body | ConvertTo-Json -Depth 5
        ContentType = "application/json"
    }
    $createResult = AttemptInvokeRestMethod "Post" "$collectionUri/$projectId/_apis/git/repositories/$repositoryName/pushes?api-version=6.0" $body $contentType 3 
}

#Reads csv tracking table into a hashtable object
function ReadCsvToTable {
    $csvTable = Import-Csv -Path $csvPath
    $HashTable=@{}
    foreach($r in $csvTable)
    {
        $key = AbsolutePathWithSlash $r.FileName 
        $HashTable[$key]=$r.CommitSha
    }   
    return $HashTable    
}

function AttemptInvokeRestMethod($method, $url, $body, $contentTypes, $maxRetries) {
    $Stoploop = $false
    $retryCount = 0
    do {
        try {
            $result = Invoke-RestMethod -Uri $url -Method $method -Headers $header -Body $body -ContentType $contentTypes
            $Stoploop = $true
        }
        catch {
            if ($retryCount -gt $maxRetries) {
                Write-Host "[Error] API call failed after $retryCount retries: $_"
                $Stoploop = $true
            }
            else {
                Write-Host "[Warning] API call failed: $_.`n Conducting retry #$retryCount."
                Start-Sleep -Seconds 5
                $retryCount = $retryCount + 1
            }
        }
    }
    While ($Stoploop -eq $false)
    return $result
}

function AttemptDeployMetadata($deploymentName, $resourceGroupName, $templateObject) {
    $deploymentInfo = $null
    try {
        $deploymentInfo = Get-AzResourceGroupDeploymentOperation -DeploymentName $deploymentName -ResourceGroupName $ResourceGroupName -ErrorAction Ignore
    }
    catch {
        Write-Host "[Warning] Unable to fetch deployment info for $deploymentName, no metadata was created for the resources in the file. Error: $_"
        return
    }
    $deploymentInfo | Where-Object { $_.TargetResource -ne "" } | ForEach-Object {
        $resource = $_.TargetResource
        $sentinelContentKinds = GetContentKinds $resource
        if ($sentinelContentKinds.Count -gt 0) {
            $contentKind = ToContentKind $sentinelContentKinds $resource $templateObject
            $contentId = $resource.Split("/")[-1]
            try {
                New-AzResourceGroupDeployment -Name "md-$deploymentName" -ResourceGroupName $ResourceGroupName -TemplateFile $metadataFilePath `
                    -parentResourceId $resource `
                    -kind $contentKind `
                    -contentId $contentId `
                    -sourceControlId $sourceControlId `
                    -workspace $workspaceName `
                    -ErrorAction Stop | Out-Host
                Write-Host "[Info] Created metadata metadata for $contentKind with parent resource id $resource"
            }
            catch {
                Write-Host "[Warning] Failed to deploy metadata for $contentKind with parent resource id $resource with error $_"
            }
        }
    }
}

function GetContentKinds($resource) {
    return $sentinelResourcePatterns.Keys | Where-Object { $resource -match $sentinelResourcePatterns[$_] }
}

function ToContentKind($contentKinds, $resource, $templateObject) {
    if ($contentKinds.Count -eq 1) {
       return $contentKinds 
    }
    if ($null -ne $resource -and $resource.Contains('savedSearches')) {
       if ($templateObject.resources.properties.Category -eq "Hunting Queries") {
           return "HuntingQuery"
       }
       return "Parser"
    }
    return $null
}

function IsValidTemplate($path, $templateObject, $parameterFile) {
    Try {
        if (DoesContainWorkspaceParam $templateObject) 
        {
            if ($parameterFile) {
                Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $path -TemplateParameterFile $parameterFile -workspace $WorkspaceName 
            }
            else 
            {
                Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $path -workspace $WorkspaceName 
            }
        }
        else 
        {
            if ($parameterFile) {
                Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $path -TemplateParameterFile $parameterFile
            }
            else 
            {
                Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $path
            }
        }
        return $true
    }
    Catch {
        Write-Host "[Warning] The file $path is not valid: $_"
        return $false
    }
}

function IsRetryable($deploymentName) {
    $retryableStatusCodes = "Conflict","TooManyRequests","InternalServerError","Unauthorized","DeploymentActive"
    Try {
        $deploymentResult = Get-AzResourceGroupDeploymentOperation -DeploymentName $deploymentName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        return $retryableStatusCodes -contains $deploymentResult.StatusCode
    }
    Catch {
        return $false
    }
}

function IsValidResourceType($template) {
    try {
        $isAllowedResources = $true
        $template.resources | ForEach-Object { 
            $isAllowedResources = $resourceTypes.contains($_.type.ToLower()) -and $isAllowedResources
        }
    }
    catch {
        Write-Host "[Error] Failed to check valid resource type."
        $isAllowedResources = $false
    }
    return $isAllowedResources
}

function DoesContainWorkspaceParam($templateObject) {
    $templateObject.parameters.PSobject.Properties.Name -contains "workspace"
}

function AttemptDeployment($path, $parameterFile, $deploymentName, $templateObject) {
    Write-Host "[Info] Deploying $path with deployment name $deploymentName"
    $isValid = IsValidTemplate $path $templateObject $parameterFile
    if (-not $isValid) {
        Write-Host "Not deploying $path since the template is not valid"
        return $false
    }
    $isSuccess = $false
    $currentAttempt = 0
    While (($currentAttempt -lt $MaxAttempts) -and (-not $isSuccess)) 
    {
        $currentAttempt ++
        Try 
        {
            Write-Host "[Info] Deploy $path with parameter file: [$parameterFile]"
            if (DoesContainWorkspaceParam $templateObject) 
            {
                if ($parameterFile) {
                    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName -TemplateFile $path -workspace $workspaceName -TemplateParameterFile $parameterFile -ErrorAction Stop | Out-Host
                }
                else 
                {
                    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName -TemplateFile $path -workspace $workspaceName -ErrorAction Stop | Out-Host
                }
            }
            else 
            {
                if ($parameterFile) {
                    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName -TemplateFile $path -TemplateParameterFile $parameterFile -ErrorAction Stop | Out-Host
                }
                else 
                {
                    New-AzResourceGroupDeployment -Name $deploymentName -ResourceGroupName $ResourceGroupName -TemplateFile $path -ErrorAction Stop | Out-Host
                }
            }
            AttemptDeployMetadata $deploymentName $ResourceGroupName $templateObject

            $isSuccess = $true
        }
        Catch [Exception] 
        {
            $err = $_
            if (-not (IsRetryable $deploymentName)) 
            {
                Write-Host "[Warning] Failed to deploy $path with error: $err"
                break
            }
            else 
            {
                if ($currentAttempt -lt $MaxAttempts) 
                {
                    $retryDelaySeconds = [math]::Pow($initialSecondsBetweenAttempts, $currentAttempt)
                    $retryDelaySeconds = $retryDelaySeconds - 1
                    Write-Host "[Warning] Failed to deploy $path with error: $err. Retrying in $retryDelaySeconds seconds..."
                    Start-Sleep -Seconds $retryDelaySeconds 
                }
                else
                {
                    Write-Host "[Warning] Failed to deploy $path after $currentAttempt attempts with error: $err"
                }
            }
        }
    }
    return $isSuccess
}

function GenerateDeploymentName() {
    $randomId = [guid]::NewGuid()
    return "Sentinel_Deployment_$randomId"
}

#Load deployment configuration
function LoadDeploymentConfig() {
    Write-Host "[Info] load the deployment configuration from [$configPath]"
    $global:parameterFileMapping = @{
        'Playbooks/DataIngestionRepo.json' = $DataIngestionRepoParam

    }
    $global:prioritizedContentFiles = @()
    $global:excludeContentFiles = @()
    try {
        if (Test-Path $configPath) {
            $deployment_config = Get-Content $configPath | Out-String | ConvertFrom-Json
            $parameterFileMappings = @{}
            if ($deployment_config.parameterfilemappings) {
                $deployment_config.parameterfilemappings.psobject.properties | ForEach { $parameterFileMappings[$_.Name] = $_.Value }
            }
            $key = ($parameterFileMappings.Keys | ? { $_ -eq $workspaceId })
            if ($null -ne $key) {
                $parameterFileMappings[$key].psobject.properties | ForEach { $global:parameterFileMapping[$_.Name] = $_.Value }
            }
            if ($deployment_config.prioritizedcontentfiles) {
                $global:prioritizedContentFiles = $deployment_config.prioritizedcontentfiles
            }
            $excludeList = $global:parameterFileMapping.Values + $global:prioritizedcontentfiles
            if ($deployment_config.excludecontentfiles) {
                $excludeList = $excludeList + $deployment_config.excludecontentfiles
            }
			
            $global:excludeContentFiles = $excludeList | Where-Object { Test-Path (AbsolutePathWithSlash $_) }
        }
    }
    catch {
        Write-Host "[Warning] An error occurred while trying to load deployment configuration."
        Write-Host "Exception details: $_"
        Write-Host $_.ScriptStackTrace
    }
}

function filterContentFile($path) {
	$temp = RelativePathWithBackslash $path
	return $global:excludeContentFiles | ? {$temp.StartsWith($_, 'CurrentCultureIgnoreCase')}
}

function RelativePathWithBackslash($absolutePath) {
	return $absolutePath.Replace($rootDirectory + "\", "").Replace("\", "/")
}

function AbsolutePathWithSlash($relativePath) {
	return Join-Path -Path $rootDirectory -ChildPath $relativePath
}

#resolve parameter file name, return $null if there is none.
function GetParameterFile($path) {
    $index = RelativePathWithBackslash $path
    $key = ($global:parameterFileMapping.Keys | ? { $_ -eq $index })
    if ($key) {
        $mappedParameterFile = AbsolutePathWithSlash $global:parameterFileMapping[$key]
        if (Test-Path $mappedParameterFile) {
            return $mappedParameterFile
        }
    }

    $parameterFilePrefix = $path.TrimEnd(".json")
    
    $workspaceParameterFile = $parameterFilePrefix + ".parameters-$WorkspaceId.json"
    if (Test-Path $workspaceParameterFile) {
        return $workspaceParameterFile
    }
    
    $defaultParameterFile = $parameterFilePrefix + ".parameters.json"
    if (Test-Path $defaultParameterFile) {
        return $defaultParameterFile
    }
    
    return $null
}

function Deployment($fullDeploymentFlag, $remoteShaTable, $csvExists) {
    Write-Host "Starting Deployment for Files in path: $Directory"
    if (Test-Path -Path $Directory) 
    {
        $totalFiles = 0;
        $totalFailed = 0;
	      $iterationList = @()
        $global:prioritizedContentFiles | ForEach-Object  { $iterationList += (AbsolutePathWithSlash $_) }
        Get-ChildItem -Path $Directory -Recurse -Filter *.json -exclude *metadata.json, *.parameters*.json |
                        Where-Object { $null -eq ( filterContentFile $_.FullName ) } |
                        Select-Object -Property FullName |
                        ForEach-Object { $iterationList += $_.FullName }
        $iterationList | ForEach-Object {
            $path = $_
            Write-Host "[Info] Try to deploy $path"
            if (-not (Test-Path $path)) {
                Write-Host "[Warning] Skipping deployment for $path. The file doesn't exist."
                return
            }
            $templateObject = Get-Content $path | Out-String | ConvertFrom-Json
            if (-not (IsValidResourceType $templateObject))
            {
                Write-Host "[Warning] Skipping deployment for $path. The file contains resources for content that was not selected for deployment. Please add content type to connection if you want this file to be deployed."
                return
            }       
            $parameterFile = GetParameterFile $path
            $result = SmartDeployment $fullDeploymentFlag $remoteShaTable $path $parameterFile $templateObject
            if ($result.isSuccess -eq $false) {
                $totalFailed++
            }
            if (-not $result.skip) {
                $totalFiles++
            }
            if ($result.isSuccess -or $result.skip) {
                $global:updatedCsvTable[$path] = $remoteShaTable[$path]
                if ($parameterFile) {
                    $global:updatedCsvTable[$parameterFile] = $remoteShaTable[$parameterFile]
                }
            }
        }
        PushCsvToRepo $csvExists
        if ($totalFiles -gt 0 -and $totalFailed -gt 0) 
        {
            $err = "$totalFailed of $totalFiles deployments failed."
            Throw $err
        }
    }
    else 
    {
        Write-Output "[Warning] $Directory not found. nothing to deploy"
    }
}

function SmartDeployment($fullDeploymentFlag, $remoteShaTable, $path, $parameterFile, $templateObject) {
    try {
        $skip = $false
        $isSuccess = $null
        if (!$fullDeploymentFlag) {
            $existingSha = $global:localCsvTablefinal[$path]
            $remoteSha = $remoteShaTable[$path]
            $skip = (($existingSha) -and ($existingSha -eq $remoteSha))
            if ($skip -and $parameterFile) {
                $existingShaForParameterFile = $global:localCsvTablefinal[$parameterFile]
                $remoteShaForParameterFile = $remoteShaTable[$parameterFile]
                $skip = (($existingShaForParameterFile) -and ($existingShaForParameterFile -eq $remoteShaForParameterFile))
            }
        }
        if (!$skip) {
            $deploymentName = GenerateDeploymentName
            $isSuccess = AttemptDeployment $path $parameterFile $deploymentName $templateObject    
        }
        return @{
            skip = $skip
            isSuccess = $isSuccess
        }
    }
    catch {
        Write-Host "[Error] An error occurred while trying to deploy file $path. Exception details: $_"
        Write-Host $_.ScriptStackTrace
    }
}

function main() {
    $csvExists = Test-Path $csvPath
    if ($csvExists) {
        $global:localCsvTablefinal = ReadCsvToTable
    }
    LoadDeploymentConfig

    $items = GetItems
    $remoteShaTable = GetCommitShaTable $items

    $existingConfigSha = $global:localCsvTablefinal[$configPath]
    $remoteConfigSha = $remoteShaTable[$configPath]
    $modifiedConfig = ($existingConfigSha -xor $remoteConfigSha) -or ($existingConfigSha -and $remoteConfigSha -and ($existingConfigSha -ne $remoteConfigSha))
    if ($remoteConfigSha) {
        $global:updatedCsvTable[$configPath] = $remoteConfigSha
    }

    $fullDeploymentFlag = $modifiedConfig -or (-not (Test-Path $csvPath)) -or ($smartDeployment -eq "false")
    Deployment $fullDeploymentFlag $remoteShaTable $csvExists
}

main