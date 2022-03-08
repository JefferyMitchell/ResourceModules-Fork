targetScope = 'subscription'

@description('Name of the resource group')
param resourceGroupName string = 'rg-hub'

@description('A /16 to contain the cluster')
@minLength(10)
@maxLength(18)
param clusterVnetAddressSpace string = '10.240.0.0/16'

@description('The hub\'s regional affinity.')
param location string

var orgAppId = 'contoso'
var clusterVNetName = 'vnet-spoke-${orgAppId}-00'
var nsgNodePoolsName = 'nsg-${clusterVNetName}-nodepools'
var nsgAksiLbName = 'nsg-${clusterVNetName}-aksilbs'
var primaryClusterPipName = 'pip-${orgAppId}-00'
var subRgUniqueString = uniqueString('aks', subscription().subscriptionId, resourceGroupName)
var clusterName = 'aks-${subRgUniqueString}'
var logAnalyticsWorkspaceName = 'la-${clusterName}'
var clusterControlPlaneIdentityName = 'mi-${clusterName}-controlplane'
var keyVaultName = 'kv-${clusterName}'

module rg '../../../arm/Microsoft.Resources/resourceGroups/deploy.bicep' = {
  name: resourceGroupName
  params: {
    name: resourceGroupName
    location: location
  }
}

module law '../../../arm/Microsoft.OperationalInsights/workspaces/deploy.bicep' = {
  name: logAnalyticsWorkspaceName
  params: {
    name: logAnalyticsWorkspaceName
    location: location
    serviceTier: 'PerGB2018'
    dataRetention: 30
    // publicNetworkAccessForIngestion: 'Enabled'
    // publicNetworkAccessForQuery: 'Enabled'
    gallerySolutions: [
      {
        name: 'ContainerInsights'
        product: 'OMSGallery'
        publisher: 'Microsoft'
      }
      {
        name: 'KeyVaultAnalytics'
        product: 'OMSGallery'
        publisher: 'Microsoft'
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module nsgNodePools '../../../arm/Microsoft.Network/networkSecurityGroups/deploy.bicep' = {
  name: nsgNodePoolsName
  params: {
    name: nsgNodePoolsName
    location: location
    networkSecurityGroupSecurityRules: []
    diagnosticWorkspaceId: law.outputs.resourceId
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module nsgAksiLb '../../../arm/Microsoft.Network/networkSecurityGroups/deploy.bicep' = {
  name: nsgAksiLbName
  params: {
    name: nsgAksiLbName
    location: location
    networkSecurityGroupSecurityRules: []
    diagnosticWorkspaceId: law.outputs.resourceId
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module clusterVNet '../../../arm/Microsoft.Network/virtualNetworks/deploy.bicep' = {
  name: clusterVNetName
  params: {
    name: clusterVNetName
    location: location
    addressPrefixes: array(clusterVnetAddressSpace)
    diagnosticWorkspaceId: law.outputs.resourceId
    subnets: [
      {
        name: 'snet-clusternodes'
        addressPrefix: '10.240.0.0/22'
        // routeTableName: routeTable.outputs.name
        networkSecurityGroupName: nsgNodePools.outputs.name
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Enabled'
      }
      {
        name: 'snet-clusteringressservices'
        addressPrefix: '10.240.4.0/28'
        // routeTableName: routeTable.outputs.name
        networkSecurityGroupName: nsgAksiLb.outputs.name
        privateEndpointNetworkPolicies: 'Disabled'
        privateLinkServiceNetworkPolicies: 'Disabled'
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module primaryClusterPip '../../../arm/Microsoft.Network/publicIPAddresses/deploy.bicep' = {
  name: primaryClusterPipName
  params: {
    name: primaryClusterPipName
    location: location
    skuName: 'Standard'
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    zones: [
      '1'
      '2'
      '3'
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module clusterControlPlaneIdentity '../../../arm/Microsoft.ManagedIdentity/userAssignedIdentities/deploy.bicep' = {
  name: clusterControlPlaneIdentityName
  params: {
    name: clusterControlPlaneIdentityName
    location: location
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module mi_appgateway_frontend '../../../arm/Microsoft.ManagedIdentity/userAssignedIdentities/deploy.bicep' = {
  name: 'mi-appgateway-frontend'
  params: {
    name: 'mi-appgateway-frontend'
    location: location
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module podmi_ingress_controller '../../../arm/Microsoft.ManagedIdentity/userAssignedIdentities/deploy.bicep' = {
  name: 'podmi-ingress-controller'
  params: {
    name: 'podmi-ingress-controller'
    location: location
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
  ]
}

module keyVault '../../../arm/Microsoft.KeyVault/vaults/deploy.bicep' = {
  name: keyVaultName
  params: {
    name: keyVaultName
    location: location
    accessPolicies: []
    vaultSku: 'standard'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
    enableRbacAuthorization: true
    enableVaultForDeployment: false
    enableVaultForDiskEncryption: false
    enableVaultForTemplateDeployment: false
    enableSoftDelete: true
    diagnosticWorkspaceId: law.outputs.resourceId
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Key Vault Secrets User (preview)'
        principalIds: [
          mi_appgateway_frontend.outputs.principalId
          podmi_ingress_controller.outputs.principalId
        ]
      }
      {
        roleDefinitionIdOrName: 'Key Vault Reader (preview)'
        principalIds: [
          mi_appgateway_frontend.outputs.principalId
          podmi_ingress_controller.outputs.principalId
        ]
      }
    ]
  }
  scope: resourceGroup(resourceGroupName)
  dependsOn: [
    rg
    mi_appgateway_frontend
    podmi_ingress_controller
  ]
}