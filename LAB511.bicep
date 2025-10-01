// ===============================================
// Bicep template for LAB511
// Creates: Storage Account, AI Search, Search Index, OpenAI Service, GPT5, GPT5Mini, Text Embedding Model
// ===============================================

@description('Lab user object ID for role assignments')
param labUserObjectId string

@description('The name prefix for all resources')
param resourcePrefix string = 'lab511'

@description('The location where all resources will be deployed')
param location string = 'eastus'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_RAGRS'

@description('AI Search service SKU')
@allowed(['basic', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2'])
param searchServiceSku string = 'standard'

@description('OpenAI service SKU')
@allowed(['S0'])
param openAiSku string = 'S0'

@description('Text embedding model name')
@allowed(['text-embedding-3-large'])
param embeddingModelName string = 'text-embedding-3-large'

@description('Text embedding model version')
param embeddingModelVersion string = '1'

@description('Embedding model deployment capacity')
@minValue(1)
@maxValue(200)
param embeddingModelCapacity int = 150

@description('GPT-5 model name')
param gpt5ModelName string = 'gpt-5'

@description('GPT-5 model version')
param gpt5ModelVersion string = '2025-08-07'

@description('GPT-5 deployment capacity')
@minValue(1)
@maxValue(200)
param gpt5Capacity int = 50

@description('GPT-5 mini model name')
param gpt5MiniModelName string = 'gpt-5-mini'

@description('GPT-5 mini model version')
param gpt5MiniModelVersion string = '2025-08-07'

@description('GPT-5 mini deployment capacity')
@minValue(1)
@maxValue(200)
param gpt5MiniCapacity int = 50



// Variables for resource naming and configuration
var uniqueSuffix = uniqueString(resourceGroup().id)
var resourceNames = {
  storageAccount: '${resourcePrefix}st${uniqueSuffix}'
  searchService: '${resourcePrefix}-search-${uniqueSuffix}'
  searchIndex: '${resourcePrefix}-index'
  openAiService: '${resourcePrefix}-openai-${uniqueSuffix}'
  embeddingDeployment: 'text-embedding'
  gpt5Deployment: 'gpt-5'
  gpt5MiniDeployment: 'gpt-5-mini'
}

// Ensure storage account name meets requirements (3-24 chars, lowercase alphanumeric)
var storageAccountName = length(resourceNames.storageAccount) > 24 ? substring(resourceNames.storageAccount, 0, 24) : resourceNames.storageAccount

// ===============================================
// AZURE STORAGE ACCOUNT
// ===============================================

@description('Azure Storage Account for document storage and processing')
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
  }
}

// Create blob service for the storage account
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    isVersioningEnabled: true
  }
}

// Create container for documents
resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'documents'
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'Document storage for AI processing'
    }
  }
}

// ===============================================
// AZURE AI SEARCH SERVICE
// ===============================================

@description('Azure AI Search service for vector search and document indexing')
resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: resourceNames.searchService
  location: location
  sku: {
    name: searchServiceSku
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    networkRuleSet: {
      ipRules: []
    }
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    disableLocalAuth: false
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    semanticSearch: 'free'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ===============================================
// SERVICE PRINCIPAL ROLE ASSIGNMENTS
// ===============================================

// Cognitive Services User
resource CogsUserSPRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, searchService.name, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  properties: {
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
  }
}

// OpenAI host role assignment (scoped to the OpenAI resource group's scope)
resource openAiRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, searchService.name, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  properties: {
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  }
}

// Storage Blob Data Reader role (scoped to the storage resource group)
resource storageReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, searchService.name, '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  properties: {
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
  }
}

// Storage Blob Data Contributor role (scoped to the storage resource group)
resource storageContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, searchService.name, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  properties: {
    principalId: searchService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  }
}

// ===============================================
// LAB USER ROLE ASSIGNMENTS
// ===============================================

// Contributor at RG scope
resource userRgContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, labUserObjectId, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: resourceGroup()
  properties: {
    principalId: labUserObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  }
}

// Storage Blob Data Contributor role for lab user
resource userStorageContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, storageAccount.name, labUserObjectId, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    principalId: labUserObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  }
}

// Search Service Contributor role for lab user
resource userSearchContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, searchService.name, labUserObjectId, '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  scope: searchService
  properties: {
    principalId: labUserObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  }
}

// Search Index Data Contributor role for lab user
resource userSearchIndexContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, searchService.name, labUserObjectId, '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  scope: searchService
  properties: {
    principalId: labUserObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  }
}

// Cognitive Services Contributor role for lab user
resource userOpenAiContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, openAiService.name, labUserObjectId, '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68')
  scope: openAiService
  properties: {
    principalId: labUserObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '25fbc0a9-bd7c-42a3-aa1a-3b75d497ee68')
  }
}

// Cognitive Services OpenAI User role for lab user
resource userOpenAiUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, openAiService.name, labUserObjectId, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  scope: openAiService
  properties: {
    principalId: labUserObjectId
    principalType: 'User'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  }
}

// Cognitive Services User
resource CogsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, searchService.name, 'a97b65f3-24c7-4388-baec-2e87135dc908')
  properties: {
    principalId: searchService.identity.principalId
    principalType: 'User'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
  }
}

// ===============================================
// AZURE OPENAI SERVICE
// ===============================================

@description('Azure OpenAI service for AI models and embeddings')
resource openAiService 'Microsoft.CognitiveServices/accounts@2023-10-01-preview' = {
  name: resourceNames.openAiService
  location: 'swedencentral'
  sku: {
    name: openAiSku
  }
  kind: 'OpenAI'
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: resourceNames.openAiService
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ===============================================
// TEXT EMBEDDING MODEL DEPLOYMENT
// ===============================================

@description('Text embedding model deployment for vector generation')
resource embeddingModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiService
  name: resourceNames.embeddingDeployment
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'Standard'
    capacity: embeddingModelCapacity
  }
}

// ===============================================
// GPT-5 MODEL DEPLOYMENT
// ===============================================

@description('GPT-5 model deployment for chat and reasoning')
resource gpt5ModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiService
  name: resourceNames.gpt5Deployment
  properties: {
    model: {
      format: 'OpenAI'
      name: gpt5ModelName
      version: gpt5ModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'GlobalStandard'
    capacity: gpt5Capacity
  }
}

// ===============================================
// GPT-5 MINI MODEL DEPLOYMENT
// ===============================================

@description('GPT-5 mini model deployment for lightweight chat tasks')
resource gpt5MiniModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-10-01-preview' = {
  parent: openAiService
  name: resourceNames.gpt5MiniDeployment
  properties: {
    model: {
      format: 'OpenAI'
      name: gpt5MiniModelName
      version: gpt5MiniModelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
  sku: {
    name: 'GlobalStandard'
    capacity: gpt5MiniCapacity
  }
}

// ===============================================
// OUTPUTS
// ===============================================

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account primary endpoint')
output storageAccountPrimaryEndpoint string = storageAccount.properties.primaryEndpoints.blob

@description('Documents container name')
output documentsContainerName string = documentsContainer.name

@description('AI Search service name')
output searchServiceName string = searchService.name

@description('AI Search service endpoint')
output searchServiceEndpoint string = 'https://${searchService.name}.search.windows.net'

@description('OpenAI service name')
output openAiServiceName string = openAiService.name

@description('OpenAI service endpoint')
output openAiServiceEndpoint string = openAiService.properties.endpoint

@description('Text embedding model deployment name')
output embeddingDeploymentName string = embeddingModelDeployment.name

@description('Resource group location')
output resourceGroupLocation string = location

@description('Unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix

@description('GPT-5 model deployment name')
output gpt5DeploymentName string = gpt5ModelDeployment.name

@description('GPT-5 mini model deployment name')
output gpt5MiniDeploymentName string = gpt5MiniModelDeployment.name

@description('Lab user object ID')
output labUserObjectId string = labUserObjectId

// ===============================================
// KNOWLEDGE SOURCE (data-plane via deployment script)
// ===============================================

@description('Name of the knowledge source to create in Azure AI Search.')
param knowledgeSourceName string = 'blob-knowledge-source'

@description('Optional virtual folder inside the documents container (empty = root).')
param blobFolderPath string = ''

@description('If true, enable image verbalization using the chat model deployment.')
param useVerbalization bool = false

// -- Keys / endpoints we need for the REST call
var saKeys = listKeys(storageAccount.id, '2023-05-01')
var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${saKeys.keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

var searchAdminKeys = listAdminKeys(searchService.id, '2023-11-01')
var searchEndpoint = 'https://${searchService.name}.search.windows.net'

// OpenAI: get key + endpoint + deployment names already defined above
var openAiKeys = listKeys(openAiService.id, '2023-10-01-preview')
var openAiEndpoint = openAiService.properties.endpoint

// Choose which chat deployment to reference for verbalization (you can switch to mini if you like)
var chatDeploymentName = resourceNames.gpt5Deployment
var chatModelName = gpt5ModelName

// Script env values
var envs = [
  { name: 'SEARCH_URL', value: searchEndpoint }
  { name: 'SEARCH_ADMIN_KEY', value: searchAdminKeys.primaryKey }
  { name: 'KS_NAME', value: knowledgeSourceName }
  { name: 'STORAGE_CONN', secureValue: storageConnectionString }
  { name: 'CONTAINER', value: documentsContainer.name }
  { name: 'FOLDER', value: empty(blobFolderPath) ? '' : blobFolderPath }
  { name: 'AOAI_ENDPOINT', value: openAiEndpoint }
  { name: 'AOAI_KEY', secureValue: openAiKeys.key1 }
  { name: 'EMBED_DEPLOYMENT', value: resourceNames.embeddingDeployment }
  { name: 'EMBED_MODEL', value: embeddingModelName }
  { name: 'CHAT_DEPLOYMENT', value: chatDeploymentName }
  { name: 'CHAT_MODEL', value: chatModelName }
  { name: 'USE_VERBALIZATION', value: string(useVerbalization) }
]

// Creates/updates the Knowledge Source via Search data-plane (preview API)
resource createKnowledgeSource 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${resourcePrefix}-ks-create'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    azCliVersion: '2.62.0'
    timeout: 'PT30M'
    forceUpdateTag: utcNow()
    environmentVariables: envs
    // Using pure bash + here-docs (no jq dependency)
    scriptContent: '''
set -e

echo "Creating knowledge source: ${KS_NAME} in ${SEARCH_URL}"

if [ "${USE_VERBALIZATION}" = "true" ]; then
  cat > body.json << JSON
{
  "name": "${KS_NAME}",
  "kind": "azureBlob",
  "azureBlobParameters": {
    "connectionString": "${STORAGE_CONN}",
    "containerName": "${CONTAINER}",
    "folderPath": "${FOLDER}",
    "embeddingModel": {
      "kind": "azureOpenAI",
      "azureOpenAIParameters": {
        "resourceUri": "${AOAI_ENDPOINT}",
        "deploymentId": "${EMBED_DEPLOYMENT}",
        "apiKey": "${AOAI_KEY}",
        "modelName": "${EMBED_MODEL}"
      }
    },
    "chatCompletionModel": {
      "kind": "azureOpenAI",
      "azureOpenAIParameters": {
        "resourceUri": "${AOAI_ENDPOINT}",
        "deploymentId": "${CHAT_DEPLOYMENT}",
        "apiKey": "${AOAI_KEY}",
        "modelName": "${CHAT_MODEL}"
      }
    },
    "disableImageVerbalization": false
  }
}
JSON
else
  cat > body.json << JSON
{
  "name": "${KS_NAME}",
  "kind": "azureBlob",
  "azureBlobParameters": {
    "connectionString": "${STORAGE_CONN}",
    "containerName": "${CONTAINER}",
    "folderPath": "${FOLDER}",
    "embeddingModel": {
      "kind": "azureOpenAI",
      "azureOpenAIParameters": {
        "resourceUri": "${AOAI_ENDPOINT}",
        "deploymentId": "${EMBED_DEPLOYMENT}",
        "apiKey": "${AOAI_KEY}",
        "modelName": "${EMBED_MODEL}"
      }
    },
    "disableImageVerbalization": true
  }
}
JSON
fi

# PUT knowledge source (preview api-version)
az rest \
  --method put \
  --url "${SEARCH_URL}/knowledgeSources/${KS_NAME}?api-version=2025-08-01-preview" \
  --headers "Content-Type=application/json" "api-key=${SEARCH_ADMIN_KEY}" \
  --body @body.json

echo "Knowledge source created/updated: ${KS_NAME}"
'''
    retentionInterval: 'P1D'
  }
  dependsOn: [
    documentsContainer
    searchService
    embeddingModelDeployment
    gpt5ModelDeployment
    gpt5MiniModelDeployment
  ]
}

// Helpful outputs
@description('Knowledge Source name')
output knowledgeSourceName string = knowledgeSourceName

