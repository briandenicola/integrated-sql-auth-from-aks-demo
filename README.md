# Overview
This repository is for a simple demostration on how to authenticate a pod running on AKS to a SQL Server database running on a Windows machine using Kerberos.  It includes the steps required to setup the Kerberos (kinit,keypass, cache) and the Active Directory Service Principals (SPN) as well as sample Kerberos [krb5.conf configuration files](./krb5/krb5.conf).  There is also a script that demostrations how to handle [Kerberos ticket refreshes](./scripts/kinit.sh).  

There are two containers in this demo
1. demoapp - This container houses the SQL client application. Its an interactive console app at this time. 
1. demoapp-sidecar - This container handles kerberos cache initilization as a Init Container and then handles cache refresh once an hour as a sidecar in the pod

The side car is required because Kerberos tickets have a lifespan and must be refreshed periodically.  Traditionally, this was handled by the Operating System that was joined to a LDAP domain (Active Directory for example).  Since neither nodes in AKS nor containers join any domain in the typical manner, Kerberos ticket generation and refresh has to be handled by the application.  A side car is just one method to than can use the ticket refresh by invoking `kinit -R` before the ticket cache has expired.  This [article](https://cloud.redhat.com/blog/kerberos-sidecar-container) goes into deeper depth on this pattern. 

All containers use /tmp as a shared volume. The Kerberos cache ticket is written to /tmp/krb5cc_0, which is the default location. The application code does not require any special configuration to read the cache when it opens a connection to SQL Server. Modifiying [Enivronment Variables](https://web.mit.edu/kerberos/krb5-1.12/doc/admin/env_variables.html) can be used to influence where the cache is stored.

`export KRB5_TRACE=/dev/stdout kinit` can be used to display detailed debug traces to help troubleshoot any possible issues.  

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

## Example Values
Component | Value
------ | ------
Domain Name | bjdazure.local
Domain Controller | dc01.bjdazure.local
SQL Server VM | sql01.bjdazure.local
SQL Server Account | svc_db01
Application Service Account | svc_app01
User Assigned Managed Identity | sqltest-pod-identity
Kubernetes Namespace | kerberosdemo

## Manual Configurations
### Domain Controller
```powershell
    setspn -A MSSQLSvc/sql01.bjdazure.local:1433 svc_db01
    setspn -A MSSQLSvc/sql01:1433 svc_db01
    setspn -U -s HTTP/spn_svc_app01 svc_app01
    ktpass -out svc_app01.keytab -mapUser svc_app01@BJDAZURE.LOCAL -pass ${PASSWORD}`
         -ptype KRB5_NT_PRINCIPAL -princ HTTP/spn_svc_app01@BJDAZURE.LOCAL
```

### SQL Server 
```SQL
    CREATE DATABASE [tododb];
    CREATE TABLE dbo.Todos ( [Id] INT PRIMARY KEY, [Name] VARCHAR(250) NOT NULL, [IsComplete] BIT);
    CREATE LOGIN [BJDAZURE\svc_app01] FROM WINDOWS WITH DEFAULT_DATABASE=[tododb];
    ALTER ROLE db_datareader ADD MEMBER [BJDAZURE\svc_app01];
    ALTER ROLE db_datawriter ADD MEMBER [BJDAZURE\svc_app01];
    INSERT INTO dbo.Todos VALUES (1, 'take out trash', 0);
    INSERT INTO dbo.Todos VALUES (2, 'clean room', 0);
```

### AKS
```bash
    RESOURCEID=`az identity show --name sqltest-pod-identity --resource-group ${RG} --query id -o tsv`
    az aks pod-identity add \
        --resource-group ${CLUSTER_RG} \
        --cluster-name ${CLUSTER_NAME} \
        --namespace kerberosdemo \
        --name sqltest-pod-identity \
        --identity-resource-id ${RESOURCEID}
```

### Key Vault
```bash
    az keyvault secret set --name svc-app01-keytab \
        --vault-name ${KEYVAULT} \
        --file svc_app01.keytab \
        --encoding base64
    KEYVAULT_ID=`az keyvault show --name ${KEYVAULT} --resource-group ${RG} --query id -o tsv`
    az role assignment create --assignee sqltest-pod-identity \
        --role 'Key Vault Secrets User' --scope ${KEYVAULT_ID}
```

## Build
```bash
    docker build -t ${ACR}.azurecr.io/sql/demoapp:3.0 -f Dockerfile.app .
    docker build -t ${ACR}.azurecr.io/sql/demoapp-sidecar:3.0 -f Dockerfile.sidecar .
    az acr login -n ${ACR}
    docker push ${ACR}.azurecr.io/sql/demoapp-sidecar:3.0 
    docker push ${ACR}.azurecr.io/sql/demoapp:3.0 
```

## Deploy 
```bash
    #Update values in deploy\values.yaml
        #COMMIT_VERSION: '3.0'
        #ACR_NAME: '${ACR}.azurecr.io'
        #NAMESPACE: 'kerberosdemo'
        #MSI_SELECTOR: 'sqltest-pod-identity'
        #APP_SPN: 'HTTP/spn_svc_app01'
        #APP_KEYTAB: '/etc/keytabs/svc-app01-keytab'
        #TENANT_ID: '${AAD_TENANT_ID}'
        #CONNECTION_STRING: 'Server=tcp:sql01.bjdazure.local,1433;Initial Catalog=Tododb;Integrated Security=True;TrustServerCertificate=True'
        #KEYVAULT_NAME: '${KEYVAULT}'
    cd deploy
    helm upgrade -i kerberosdemo -n kerberosdemo --create-namespace . 
```

## Validate
```bash
    pod=`kubectl -n kerberosdemo get pods -o name --no-headers=true`
    kubectl -n kerberosdemo exec -it ${pod} -c demoapp -- dotnet /app/sql.dll
```

### Result
```bash
    Query data example:
    =========================================

    take out trash False
    clean room False

    Done. Press enter.
```
