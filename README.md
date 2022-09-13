# Overview
This repository is for a simple demostration on how to authenticate a pod running on AKS to a SQL Server database running on a Windows machine using Kerberos.  It includes the steps required to setup the Kerberos (kinit,keypass, cache) and the Active Directory Service Principals (SPN) as well as sample Kerberos [krb5.conf configuration files](./krb5/krb5.conf).  There is also a script that demostrations how to handle [Kerberos ticket refreshes](./scripts/kinit.sh).  

There are two containers in this demo
1. demoapp - This container houses the SQL client application. Its an interactive console app at this time. 
1. demoapp-sidecar - This container handles kerberos cache initilization as a Init Container and then handles cache refresh once an hour as a sidecar in the pod

All containers use /tmp as a shared volume. The Kerberos cache ticket is written to /tmp/krb5cc_0

This demo also utilizes Azure Key Vault and an Azure Managed Identity to store the encrypted [keytab](https://web.mit.edu/kerberos/krb5-1.12/doc/basic/keytab_def.html) file. The [Azure Key Vault CSI driver](https://docs.microsoft.com/en-us/azure/aks/csi-secrets-store-driver) is used to securely mount the keytab file in the sidecar at /etc/keytabs/svc-app01-keytab. _This is optional_

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

## Example Configuration
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
    az aks pod-identity add --resource-group ${CLUSTER_RG} --cluster-name ${CLUSTER_NAME} --namespace kerberosdemo --name sqltest-pod-identity --identity-resource-id ${RESOURCEID}
```

### Key Vault
```bash
    az keyvault secret set --name svc-app01-keytab --vault-name ${KEYVAULT} --file svc_app01.keytab --encoding base64
    KEYVAULT_ID=`az keyvault show --name ${KEYVAULT} --resource-group SQL_RG --query id -o tsv`
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
    kubectl -n kerberosdemo exec -it $(kubectl -n kerberosdemo get pods -o name --no-headers=true) -c demoapp -- dotnet /app/sql.dll
```

### Results
```bash
    Query data example:
    =========================================

    take out trash False
    clean room False

    Done. Press enter.
```
