RG=mbb
AKS=aks-mbb-sandbox
AZURE_CLIENT_ID=$(az identity show --name java-maven-mid --resource-group $RG --query clientId -o tsv)


# Get the AKS Resource ID
AKS_ID=$(az aks show --name $AKS --resource-group $RG --query id -o tsv)

# Assign the RBAC Cluster Admin role (the Data Plane role)
az role assignment create \
  --assignee "slinhtet@palo-it.com" \
  --role "Azure Kubernetes Service RBAC Admin" \
  --scope "$AKS_ID"

az login --identity --username $AZURE_CLIENT_ID
az login --identity --client-id $AZURE_CLIENT_ID

az aks get-credentials --resource-group $RG --name $AKS --admin


#AKS OIDC ISSUER

export AKS_OIDC_ISSUER="$(az aks show -n $AKS -g $RG --query "oidcIssuerProfile.issuerUrl" -o tsv)"

UAMI_ID=$(az identity show --name java-maven-mid --resource-group $RG --query id -o tsv)
CLIENT_ID=$(az identity show --name java-maven-mid --resource-group $RG --query clientId -o tsv)

# Add federated credential for the specific repo/branch
az identity federated-credential create \
  --name github-actions-fed \
  --identity-name java-maven-mid \
  --resource-group $RG \
  --issuer https://token.actions.githubusercontent.com \
  --subject repo:paloitmbb/mbb-java-maven:ref:refs/heads/main \
  --audiences api://AzureADTokenExchange

#Testing
#Testing 1
