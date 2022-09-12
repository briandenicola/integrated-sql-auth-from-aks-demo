# Overview
_TBD_


# Setup
## Existing Infrastructure 
1. A Windows Domain
1. A SQL Server on Windows 
1. A Domain Account for SQL Server
1. A Domain Account for the application 
1. An AKS cluster or equivalent 
1. An Azure Key Vault 
1. An Azure Container Registry or equivalent 
1. A User Assigned Managed Identity
1. Docker

### Note:
1. The Key Vault and Managed Identity are optional. They are only included in this demo to showcase the secure storage of the keytab file using AKS's Key Vault CSI driver

## Example
* DOMAIN: bjdazure.local
* Domain Controller: dc01.bjdazure.local
* SQL Server Account: svc_db01
* Application Service Account: svc_app01
* User Assigned Managed Identity: sqltest-pod-identity
* Namespace: kerberosdemo

## Steps
### Domain Controller
```cmd
setspn -A MSSQLSvc/sql01.bjdazure.local:1433 svc_db01
setspn -A MSSQLSvc/sql01:1433 svc_db01
setspn -U -s HTTP/spn_svc_app01 svc_app01
ktpass -out svc_app01.keytab -mapUser svc_app01@BJDAZURE.LOCAL -pass ${PASSWORD} -ptype KRB5_NT_PRINCIPAL -princ HTTP/spn_svc_app01@BJDAZURE.LOCAL
```

### AKS
```bash
RESOURCEID=`az identity show --name sqltest-pod-identity --resource-group SQL_RG --query id -o tsv`
az aks pod-identity add --resource-group ${CLUSTER_RG} --cluster-name ${CLUSTER_NAME} --namespace kerberosdemo --name sqltest-pod-identity --identity-resource-id ${RESOURCEID}%
```

### Key Vault
```bash
az keyvault secret set --name keytab --vault-name ${KEYVAULT} --file ./svc_app01.keytab --encoding base64
az role assignment create --assignee sqltest-pod-identity --role 'Key Vault Secrets User' --scope ${KEYVAULT_ID}
```

### Build
```bash
    docker build -t ${ACR}.azurecr.io/sql/demoapp:3.0 -f Dockerfile.app .
    docker build -t ${ACR}.azurecr.io/sql/demoapp-sidecar:3.0 -f Dockerfile.sidecar .
    az acr login -n ${ACR}
    docker push ${ACR}.azurecr.io/sql/demoapp-sidecar:3.0 
    docker push ${ACR}.azurecr.io/sql/demoapp:3.0 
```

# Validate
```bash
    #Update values in deploy\values.yaml
    cd deploy
    helm upgrade -i kerberosdemo -n kerberosdemo --create-namespace . 
    kubectl -n kerberosdemo exec -it -c demoapp --bash 
    >>dotnet /app/sql.dll
```

### Results
```bash
    Query data example:
    =========================================

    take out trash False
    clean room False

    Done. Press enter.
```
