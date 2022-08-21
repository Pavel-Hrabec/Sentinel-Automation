# Sentinel Automation

Sources:

[https://github.com/Azure/Azure-Sentinel/wiki#test-your-contribution](https://github.com/Azure/Azure-Sentinel/wiki#test-your-contribution)

[https://github.com/Azure/Azure-Sentinel/tree/master/Solutions#guide-to-building-microsoft-sentinel-solutions](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions#guide-to-building-microsoft-sentinel-solutions)

[https://docs.microsoft.com/en-us/azure/sentinel/ci-cd?tabs=github](https://docs.microsoft.com/en-us/azure/sentinel/ci-cd?tabs=github)

[Export Sentinel Playbooks](https://techcommunity.microsoft.com/t5/microsoft-sentinel-blog/export-microsoft-sentinel-playbooks-or-azure-logic-apps-with/ba-p/3275898)

[Export Sentinel Automation Rules](https://www.garybushey.com/2022/05/08/get-or-export-microsoft-sentinel-automation-rules/)

[https://github.com/javiersoriano/sentinelascode](https://github.com/javiersoriano/sentinelascode)

https://github.com/javiersoriano/sentinel-scripts

- format needs to be in ARM template. You can’t import as gallery view in workbook format

workspaceParameterFile
parameterFileMapping

function GetParameterFile($path) { // this creates parameter file

```
Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $path -workspace $WorkspaceName // cannot be changed

```

- [https://youtu.be/3IRwtbGlshk](https://youtu.be/3IRwtbGlshk) > > > Logics apps might need to be build separately to create/store secrets for connections and use those as parameters/variables for deployment

# Sentinel GitHub Connection

- Order of resource deployment
    1. Analytics rules
    2. Automation rules
    3. Hunting queries
    4. Parsers
    5. Playbooks
    6. Workbooks

## How to export resources from Sentinel

### Workbooks

- View workbook > Edit > Advanced Editor > ARM template
- File needs to be in json format
- Edit your workbook
    - Remove parameter workbookSourceID
        
        ```json
        "workbookSourceId": {
          "type": "string",
          "defaultValue": "/subscriptions/xxxyyyzzz/resourcegroups/xxxyyyzzz/providers/microsoft.operationalinsights/workspaces/xxxyyyzzz",
          "metadata": {
            "description": "The id of resource instance to which the workbook will be associated"
          }
        },
        ```
        
    - Parameters section needs to be extended - add parameters workspace, resourceGroupName and subscription ID
    
    ```json
    "resourceGroupName": {
      "type": "string",
      "defaultValue": "[resourceGroup().name]",
      "metadata": {
        "description": "Name of the resource group where the workbook will be saved"
      }
    },
    "subscriptionID": {
      "type": "string",
      "defaultValue": "[subscription().id]",
      "metadata": {
        "description": "Unique subscription ID for tenant where the workbook will be saved"
      }
    },
    "workspace": {
      "type": "string",
      "metadata": {
        "description": "Name of the workspace name where workbook will be saved"
      }
    },
    ```
    
- Variables section for “fallbackResourceIDs and resources section for sourceId needs to be edited.
    
    ```json
    "fallbackResourceIds": [
      "[concat(parameters('subscriptionID'), '/resourcegroups/', parameters('resourceGroupName'), '/providers/microsoft.operationalinsights/workspaces/', parameters('workspace'))]"
    ],
    
    "sourceId": "[concat(parameters('subscriptionID'), '/resourcegroups/', parameters('resourceGroupName'), '/providers/microsoft.operationalinsights/workspaces/', parameters('workspace'))]",
    ```
    
- After you import your workbooks and you want to see them in “My workbooks” tab you will have to initially save them
    - Navigate to Microsoft Sentinel > Workbooks > Add workbook > Open > Select your workbook > Save
    - [I could use single user managed identity for connection to sentinel](https://techcommunity.microsoft.com/t5/microsoft-sentinel-blog/what-s-new-managed-identity-for-azure-sentinel-logic-apps/ba-p/2068204)

![Untitled](https://s3-us-west-2.amazonaws.com/secure.notion-static.com/04d5081e-d6bf-4ab4-831a-43515b140597/Untitled.png)

### Automation Rules

- Requirements
    - [PowerShell 6.2 or later](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.2#installing-the-msi-package)
    - [NET Framework 4.7.2 or later](https://docs.microsoft.com/en-us/dotnet/framework/install/)
    - Make sure you have the latest version of PowerShellGet
        
        ```powershell
        Install-Module -Name PowerShellGet -Force
        ```
        
    - Install Microsoft Azure Az Powershell module
        
        ```powershell
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
        
        Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
        ```
        
    - Sign in to your Azure environment
        
        ```powershell
        Connect-AzAccount
        ```
        
- [Download Powershell script created by garybushey](https://github.com/garybushey/MicrosoftSentinelAutomation)
- Run script with your parameters, more in his article [how to export automation rules](https://www.garybushey.com/2022/05/08/get-or-export-microsoft-sentinel-automation-rules/)
    
    ```powershell
    .\Export-AzSentinelAutomationRule.ps1 -WorkSpaceName "xxxyyyzzz" -ResourceGroupName "xxxyyyzzz"
    ```
    
- Use ARM template
    
    ```json
    {
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
        "contentVersion": "1.0.0.0",
        "parameters": {
            "workspace": {
                "type": "string",
                "metadata": {
                    "description": "The name of the Sentinel workspace where the automation rule will be deployed."
                }
            },
            "automationRuleName": {
                "type": "string",
                "metadata": {
                    "description": "The name of the automation rule that will be deployed."
                },
    	    "defaultValue": "AutomationRule1"
            }
        },
        "variables": {
            "automationRuleGuid": "[uniqueString(parameters('automationRuleName'))]" 
        },
        "resources": [
            {
                "type": "Microsoft.OperationalInsights/workspaces/providers/automationRules",
                "name": "[concat(parameters('workspace'),'/Microsoft.SecurityInsights/',parameters('automationRuleName'))]",
                "apiVersion": "2019-01-01-preview",
                "properties": {
                    "displayName": "[parameters('automationRuleName')]",
                    
                }
            }
        ],
        "outputs": {}
    }
    ```
    
- Edit template with your exported code. Everything starting under “displayName” needs to be changed, line 29
    
    ```json
    "properties": {
        "displayName": "[parameters('automationRuleName')]",
        "ChangeFromHere": 3,
    ```
    
    ![Untitled](https://s3-us-west-2.amazonaws.com/secure.notion-static.com/49d67ec4-1b1c-44be-8131-6c36938f353b/Untitled.png)
    
- Edit “default value” for parameter “automationRuleName”, line 16
    
    ```json
    "defaultValue": "AutomationRule1"
    ```
    

### Playbooks

- Template schema version: 2019-04-01 is required
- Download Azure Logic App/Playbook ARM Template Generator tool from [Azure Sentinel GitHub repository](https://github.com/Azure/Azure-Sentinel/tree/master/Tools/Playbook-ARM-Template-Generator)
- Allow PowerShell script execution
    
    ```powershell
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    ```
    
- Run the script and select which playbook do you want to convert into ARM template - [youtube video demonstration](https://techcommunity.microsoft.com/t5/microsoft-sentinel-blog/export-microsoft-sentinel-playbooks-or-azure-logic-apps-with/ba-p/3275898)

### Playbooks with API Connections

- To deploy Playbooks & API with ARM template [article by Sacha Bruttin explains steps](https://www.bruttin.com/2017/06/13/deploy-logic-app-with-arm.html)
- You will have to edit ARM template with parameters based on your specific deployment. In my case I’ve connected playbook to log analytics workspace
- Parameters depend on API connection type. To retrieve required parameters from you dev environment [use tool ARMClient created by ProjectKudu](https://github.com/projectkudu/ARMClient)
    - Install ArmClient with Chocolatey
        
        ```powershell
        choco install armclient --source=https://chocolatey.org/api/v2/
        ```
        
    - To use ArmClient
        
        ```powershell
        armclient.exe get https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.Web/locations/{region}/managedApis/{ApiName}?api-version=2016-06-01
        ```
        
        - To list Azure regions
            
            ```powershell
            az account list-locations -o table
            ```
            
    - Output will similar to this (username as WorkspaceID and password as WorkspaceKey are provided in this case)
        
        ```json
        "properties": {
            "name": "azureloganalyticsdatacollector",
            "connectionParameters": {
              "username": {
                "type": "string",
                "uiDefinition": {
                  "displayName": "Workspace ID",
                  "description": "The unique identifier of the Azure Log Analytics workspace.",
                  "tooltip": "Provide ID of the Azure Log Analytics workspace.",
                  "constraints": {
                    "required": "true"
                  }
                }
              },
              "password": {
                "type": "securestring",
                "uiDefinition": {
                  "displayName": "Workspace Key",
                  "description": "The primary or secondary key of the Azure Log Analytics workspace.",
                  "tooltip": "Provide primary or secondary key of the Azure Log Analytics workspace.",
                  "constraints": {
                    "required": "true"
                  }
                }
              }
            }
        ```
        
- Expand Parameters in your ARM template (For me it’s WorkspaceID and WorkspaceKey)
    
    ```json
    "parameters": {
            "PlaybookName": {
                "defaultValue": "DataIngestionRepo",
                "type": "string"
            },
            "WorkspaceID": {
                "defaultValue": "xxxyyyzzz",
                "type": "string"
            },
            "WorkspaceKey": {
                "defaultValue": "xxxyyyzzz",
                "type": "string"
            }
        },
    ```
    
- Edit resource connection with your parameters. “customParameterValue” needs to be renamed to “parameterValues”
    
    ```json
    {
        "type": "Microsoft.Web/connections",
        "apiVersion": "2016-06-01",
        "name": "[variables('AzureloganalyticsdatacollectorConnectionName')]",
        "location": "[resourceGroup().location]",
        "kind": "V1",
        "properties": {
            "displayName": "[variables('AzureloganalyticsdatacollectorConnectionName')]",
            "customParameterValues": {},
            "api": {
                "id": "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/managedApis/Azureloganalyticsdatacollector')]"
            }
        }
    }
    ```
    
- After adjustments
    
    ```json
    {
        "type": "Microsoft.Web/connections",
        "apiVersion": "2016-06-01",
        "name": "[variables('AzureloganalyticsdatacollectorConnectionName')]",
        "location": "[resourceGroup().location]",
        "kind": "V1",
        "properties": {
            "displayName": "[variables('AzureloganalyticsdatacollectorConnectionName')]",
            "parameterValues": {
                "username": "[parameters('WorkspaceID')]",
                "password": "[parameters('WorkspaceKey')]"
            },
            "api": {
                "id": "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/managedApis/Azureloganalyticsdatacollector')]"
            }
        }
    }
    ```
    
    - 
- 

## How to pass custom parameters from Pipeline

- For this to work multiple steps are required.
    1. Parameters are added as environment variables in Pipeline 
    2. Parameter file with variables is created with deployment
    3. Parameter file is used for resource deployment 

### Parameters are added as environment variables in Pipeline

- First of all environment variable needs to be added to Github actions
    - Navigate to your repository, go to “Settings”. Under Security section select “Secrets” and “Actions”
    - Here you can extend your secrets with “New repository secret” option - pick name and secret
    
    ![Untitled](https://s3-us-west-2.amazonaws.com/secure.notion-static.com/0cecf8a6-1fc0-429a-8d02-3cf1f15aec65/Untitled.png)
    
- Extend your pipeline with the new variable, edit sentinel-deploy-xxxyyyzzz.yml
    
    ```powershell
    jobs:
      deploy-content:
        runs-on: windows-latest
        env:
          workspaceKey: ${{ secrets.NameOfYourVariable }}
    ```
    

### Parameter file with variables is created with deployment

- Create parameter.json file with your pipeline environment variable and assign path to this file as variable
    - [ARM template](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/variables#example-template) is used to specify paramater.json file with parameters (In this case workspaceId and workspaceKey)

```powershell
$DataIngestionRepoParam = "DataIngestionRepoParam.json"
@"
{
    "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "WorkspaceID": {
            "type": "string",
            "value": "$Env:workspaceId"
        },
        "WorkspaceKey": {
            "type": "string",
            "value": "$Env:workspaceKey"
        }
    }
}
"@ | Out-File -FilePath $DataIngestionRepoParam
```

### Parameter file is used for resource deployment

- Function LoadDeploymentConfig needs to be adjusted for parameter file mapping. Below is code before changes.
    
    ```powershell
    function LoadDeploymentConfig() {
        Write-Host "[Info] load the deployment configuration from [$configPath]"
        $global:parameterFileMapping = @{}
    ```
    
- Code needs to be expanded with path to your ARM template and which ARM template should be used for this deployment
    
    ```powershell
    function LoadDeploymentConfig() {
        Write-Host "[Info] load the deployment configuration from [$configPath]"
        $global:parameterFileMapping = @{
            'Playbooks/DataIngestionRepo.json' = $DataIngestionRepoParam
        }
    ```
    
- Further changes are required to test deployment with this Parameter file for function IsValidTemplate. Below is code before changes.
    
    ```powershell
    function IsValidTemplate($path, $templateObject) {
        Try {
            if (DoesContainWorkspaceParam $templateObject) {
                Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $path -workspace $WorkspaceName -TemplateParameterFile $parameterFile
            }
            else {
                Test-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $path
            }
            return $true
    ```
    
- Another conditions is added if parameter file is present, which is also added as variable
    
    ```powershell
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
    ```
    
- Call function IsValidTemplate with variable ParameterFile
    
    ```powershell
    $isValid = IsValidTemplate $path $templateObject $parameterFile
    ```
    
- During deployment you should see something similar
    
    ```powershell
    [Info] Deploy D:\a\Sentinel-Automation\Sentinel-Automation\AnalyticsRules\Audit log data deletion.json with parameter file: [D:\a\Sentinel-Automation\Sentinel-Automation\AuditDataParam.json]
    ```
    
