# Change kubeconfig to Microk8s
$env:KUBECONFIG = "C:\Users\mdrrahman\.kube\microk8s"

##############################################################
# Generate Tanzu images
##############################################################

# Load Tanzu images
docker load -i ./images/postgres-instance
docker load -i ./images/postgres-operator

docker images "postgres-*"
# REPOSITORY          TAG       IMAGE ID       CREATED       SIZE
# postgres-operator   v1.5.0    aee1e609d53f   6 weeks ago   111MB
# postgres-instance   v1.5.0    6392beb0deae   6 weeks ago   1.64GB

# Tag and push to mdrrakiburrahman Docker registry
docker tag postgres-operator:v1.5.0 mdrrakiburrahman/postgres-operator:v1.5.0
docker tag postgres-instance:v1.5.0 mdrrakiburrahman/postgres-instance:v1.5.0

docker push mdrrakiburrahman/postgres-operator:v1.5.0
docker push mdrrakiburrahman/postgres-instance:v1.5.0

##############################################################
# Generate dockerfiles: run in WSL (bash)
##############################################################
cd dockerfiles/

# Defines an alias command that we're going to reuse
alias dfimage="docker run -v /var/run/docker.sock:/var/run/docker.sock --rm alpine/dfimage"

# Call against container of choice and pull out the Dockerfile
dfimage -sV=1.36 mdrrakiburrahman/postgres-operator:v1.5.0 | grep -Pzo '.*Dockerfile(.*\n)*' > postgres-operator.Dockerfile
dfimage -sV=1.36 mdrrakiburrahman/postgres-instance:v1.5.0 | grep -Pzo '.*Dockerfile(.*\n)*' > postgres-instance.Dockerfile

##############################################################
# Container dump: run in WSL (bash)
##############################################################
# Operator
cd ../dump/postgres-operator
docker create -it --name postgres-operator mdrrakiburrahman/postgres-operator:v1.5.0 bash
docker cp postgres-operator:/ .
docker rm -f postgres-operator

# Instance
cd ../postgres-instance
docker create -it --name postgres-instance mdrrakiburrahman/postgres-instance:v1.5.0 bash
docker cp postgres-instance:/ .
docker rm -f postgres-instance

###################################################################################
# 1. Installing a Tanzu Postgres Operator
###################################################################################
# Create kubernetes secret for accessing Docker registry
kubectl create secret docker-registry regsecret `
    --docker-server=https://index.docker.io/v1/ `
    --docker-username='mdrrakiburrahman' `
    --docker-password='57a...'

# Install cert-manager
kubectl create namespace cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager --namespace cert-manager  --version v1.7.1 --set installCRDs=true

kubectl get all --namespace=cert-manager
# NAME                                           READY   STATUS    RESTARTS   AGE
# pod/cert-manager-cainjector-7d55bf8f78-wfkcx   1/1     Running   0          3m9s
# pod/cert-manager-6d6bb4f487-xl7qx              1/1     Running   0          3m9s
# pod/cert-manager-webhook-5c888754d5-pxkc4      1/1     Running   0          3m9s

# NAME                           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE  
# service/cert-manager-webhook   ClusterIP   10.152.183.5    <none>        443/TCP    3m10s
# service/cert-manager           ClusterIP   10.152.183.26   <none>        9402/TCP   3m10s

# NAME                                      READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/cert-manager-cainjector   1/1     1            1           3m9s
# deployment.apps/cert-manager              1/1     1            1           3m9s
# deployment.apps/cert-manager-webhook      1/1     1            1           3m9s

# NAME                                                 DESIRED   CURRENT   READY   AGE     
# replicaset.apps/cert-manager-cainjector-7d55bf8f78   1         1         1       3m9s    
# replicaset.apps/cert-manager-6d6bb4f487              1         1         1       3m9s    
# replicaset.apps/cert-manager-webhook-5c888754d5      1         1         1       3m9s

# Deploy helm charts for Tanzu
helm install my-postgres-operator operator/ `
    --values=operator/values-overrides.yaml `
    --wait
# NAME: my-postgres-operator
# LAST DEPLOYED: Sat Feb 19 11:56:48 2022
# NAMESPACE: default
# STATUS: deployed
# REVISION: 1
# TEST SUITE: None

# Watch for changes
while (1) {kubectl get all; sleep 5; clear;}
# NAME                                     READY   STATUS    RESTARTS   AGE
# pod/postgres-operator-7dbb479fcb-v6h6w   1/1     Running   0          48s

# NAME                                        TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)  
#  AGE
# service/kubernetes                          ClusterIP   10.152.183.1     <none>        443/TCP  
#  3h51m
# service/postgres-operator-webhook-service   ClusterIP   10.152.183.123   <none>        443/TCP  
#  48s

# NAME                                READY   UP-TO-DATE   AVAILABLE   AGE
# deployment.apps/postgres-operator   1/1     1            1           48s

# NAME                                           DESIRED   CURRENT   READY   AGE
# replicaset.apps/postgres-operator-7dbb479fcb   1         1         1       48s

# Poll logs from operator
kubectl logs -l app=postgres-operator --follow

# Operator owned resources
kubectl api-resources --api-group=sql.tanzu.vmware.com

# NAME                      SHORTNAMES   APIVERSION                NAMESPACED   KIND
# postgres                  pg           sql.tanzu.vmware.com/v1   true         Postgres
# postgresbackuplocations                sql.tanzu.vmware.com/v1   true         PostgresBackupLocation
# postgresbackups                        sql.tanzu.vmware.com/v1   true         PostgresBackup        
# postgresbackupschedules                sql.tanzu.vmware.com/v1   true         PostgresBackupSchedule
# postgresrestores                       sql.tanzu.vmware.com/v1   true         PostgresRestore       
# postgresversions                       sql.tanzu.vmware.com/v1   false        PostgresVersion

###################################################################################
# 2. Deploying a Postgres Instance
###################################################################################
# Get supported Postgres versions
kubectl get postgresversion
# NAME          DB VERSION
# postgres-13   13.5
# postgres-11   11.14
# postgres-14   14.1
# postgres-12   12.9

cd .\kubernetes

# Create single Postgres instance
kubectl apply -f postgres-single.yaml

# Get all resources created for this instance
kubectl get all -l postgres-instance=postgres-sample
# NAME                            READY   STATUS    RESTARTS   AGE
# pod/postgres-sample-monitor-0   4/4     Running   0          3m23s
# pod/postgres-sample-0           5/5     Running   0          3m9s

# NAME                            TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)          AGE  
# service/postgres-sample         LoadBalancer   10.152.183.63   192.168.0.105   5432:30860/TCP   3m23s
# service/postgres-sample-agent   ClusterIP      None            <none>          <none>           3m23s

# NAME                                       READY   AGE
# statefulset.apps/postgres-sample-monitor   1/1     3m23s
# statefulset.apps/postgres-sample           1/1     3m9s

# NAME                                            STATUS    DB VERSION   BACKUP LOCATION   AGE
# postgres.sql.tanzu.vmware.com/postgres-sample   Running   14.1                           3m23s

# Verify Postgres instance
kubectl get postgres
# NAME              STATUS    DB VERSION   BACKUP LOCATION   AGE
# postgres-sample   Running   14.1                           80s

# Generate dump of the created YAMLs
mkdir postgres-single

kubectl get pod/postgres-operator-7dbb479fcb-vzbhs -o yaml > postgres-single/postgres-operator.yaml
kubectl get pod/postgres-sample-monitor-0 -o yaml > postgres-single/postgres-sample-monitor.yaml
kubectl get pod/postgres-sample-0 -o yaml > postgres-single/postgres-sample.yaml

# Get State via pg_autoctl
kubectl exec -it pod/postgres-sample-0 -- pg_autoctl show state
#   Name |  Node |                                                              Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
# -------+-------+------------------------------------------------------------------------+----------------+--------------+---------------------+--------------------
# node_1 |     1 | postgres-sample-0.postgres-sample-agent.default.svc.cluster.local:5432 |   1: 0/181E798 |   read-write |              single |              single

# Connect to the instance via psql
kubectl exec -it postgres-sample-0 -c pg-container -- bash -c "psql"
# postgres=# \l
#                                     List of databases
#       Name       |  Owner   | Encoding | Collate |  Ctype  |      Access privileges       
# -----------------+----------+----------+---------+---------+------------------------------
#  postgres        | postgres | UTF8     | C.UTF-8 | C.UTF-8 | =Tc/postgres                +
#                  |          |          |         |         | postgres=CTc/postgres       +
#                  |          |          |         |         | postgres_exporter=c/postgres 
#  postgres-sample | postgres | UTF8     | C.UTF-8 | C.UTF-8 | =Tc/postgres                +
#                  |          |          |         |         | postgres=CTc/postgres       +
#                  |          |          |         |         | pgappuser=CTc/postgres       
#  template0       | postgres | UTF8     | C.UTF-8 | C.UTF-8 | =c/postgres                 +
#                  |          |          |         |         | postgres=CTc/postgres        
#  template1       | postgres | UTF8     | C.UTF-8 | C.UTF-8 | =c/postgres                 +
#                  |          |          |         |         | postgres=CTc/postgres        

# Connect to the instance via Azure Data Studio

# Secret
kubectl get secret postgres-sample-db-secret -o go-template='{{range $k,$v := .data}}{{printf \"%s: \" $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{\"\n\"}}{{end}}'
# dbname: postgres-sample
# instancename: postgres-sample
# namespace: default
# password: m6Yf0Ovv43FFk0E50q18mJx7eeVUQu
# username: pgadmin

# Access via Azure Data Studio
kubectl port-forward service/postgres-sample 5432:5432

###################################################################################
# 4. Updating a Postgres Instance Configuration
###################################################################################
kubectl edit storageclass microk8s-hostpath
# Added:
# allowVolumeExpansion: true

# Check the PVC
kubectl get pvc
# NAME                                                STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS        AGE 
# postgres-sample-monitor-postgres-sample-monitor-0   Bound    pvc-c8ef8908-57a7-4f06-b1e8-f4e25142b72d   1G         RWO            microk8s-hostpath   155m
# postgres-sample-pgdata-postgres-sample-0            Bound    pvc-b53f7189-c431-4266-8c98-de2c84dda8e2   800M       RWO            microk8s-hostpath   154m

# Let's change the second one to 5GB in our YAML
kubectl apply -f C:\Users\mdrrahman\Documents\GitHub\tanzu-sql\postgres-for-kubernetes-v1.5.0\kubernetes\postgres-single.yaml

# Warning  ExternalExpanding  5m34s  volume_expand  Ignoring the PVC: didn't find a plugin capable of expanding the volume; waiting for an external controller to process this PVC.

# Looks like Microk8s doesn't support it

###################################################################################
# 4. Deleting the instance
###################################################################################
# Interesting, they delete the PVCs as well

kubectl delete -f C:\Users\mdrrahman\Documents\GitHub\tanzu-sql\postgres-for-kubernetes-v1.5.0\kubernetes\postgres-single.yaml

###################################################################################
# 5. Backing Up and Restoring Tanzu Postgres
###################################################################################
# Uses these 4 CRDs:

# postgresbackuplocations
# References an external blobstore and the necessary credentials for blobstore access.

# postgresbackups              
# References a Postgres backup artifact that exists in an external blobstore such as S3 or Minio. Every time you generate an on-demand or scheduled backup, Tanzu Postgres creates a new PostgresBackup resource

# postgresbackupschedules
# Represents a CronJob schedule specifying when to perform backups.

# postgresrestores
# References a Postgres restore artifact that receives a PostgresBackup resource and restores the data from the backup to a new Postgres instance or to the same postgres instance (an in-place restore).

# Deploy MINIO
helm repo add minio https://charts.min.io/
helm repo update

helm install --namespace minio --create-namespace --set rootUser=boor,rootPassword=acntorPRESTO! --set persistence.enabled=true --set persistence.size=2Gi --set resources.requests.cpu=1 --set resources.limits.cpu=2 --set resources.requests.memory=1Gi --set resources.limits.memory=2Gi --set mode=distributed,replicas=4 --generate-name minio/minio

# NAME: minio-1645306336
# LAST DEPLOYED: Sat Feb 19 16:32:16 2022
# NAMESPACE: minio
# STATUS: deployed
# REVISION: 1
# TEST SUITE: None
# NOTES:
# MinIO can be accessed via port 9000 on the following DNS name from within your cluster:
# minio-1645306336.minio.svc.cluster.local

# Access via browser
kubectl port-forward service/minio-1645306336-console 9001:9001 -n minio
# Browse at http://localhost:9001/

# Create bucket access secret and backuplocation
kubectl apply -f backuplocation.yaml

# Validate
kubectl get postgresbackuplocation minio-s3 -o jsonpath='{.spec}' | ConvertFrom-Json | ConvertTo-Json
# {
#     "storage": {
#       "s3": {
#         "bucket": "postgres",
#         "bucketPath": "/",
#         "enableSSL": true,
#         "endpoint": "https://10.152.183.172:9000",
#         "forcePathStyle": false,
#         "region": "us-east-1",
#         "secret": "@{name=minio-s3-creds}"
#       }
#     }
#   }

# Create Postgres with backuplocation configured
kubectl apply -f postgres-single.yaml
kubectl get postgres/postgres-sample -o jsonpath='{.spec.backupLocation}'
# {"name":"minio-s3"}

# Create an On-Demand Backup
kubectl apply -f .\backup.yaml

# We see some errors
kubectl get events --field-selector involvedObject.name=minio-backup
# LAST SEEN   TYPE      REASON   OBJECT                        MESSAGE
# 111s        Warning   Failed   postgresbackup/minio-backup   WARN: environment contains invalid option 'config-version'ERROR: [031]: 'https://10.152.183.172:9000' is not valid for option 'repo1-s3-endpoint'       HINT: is more than one port specified?

###################################################################################
# 6. Configuring High Availability in Tanzu Postgres
###################################################################################
# Create HA instance
kubectl apply -f postgres-ha.yaml

# Log into both pods and use pg_autoctl
kubectl exec -ti pod/postgres-sample-0 -- pg_autoctl show state
kubectl exec -ti pod/postgres-sample-1 -- pg_autoctl show state

# Both shows
# Name |  Node |                                                              Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
# -------+-------+------------------------------------------------------------------------+----------------+--------------+---------------------+--------------------
# node_1 |     1 | postgres-sample-1.postgres-sample-agent.default.svc.cluster.local:5432 |   1: 0/3021DA8 |   read-write |             primary |             primary
# node_2 |     2 | postgres-sample-0.postgres-sample-agent.default.svc.cluster.local:5432 |   1: 0/3021DA8 |    read-only |           secondary |           secondary

# Let's flip the primary to 0
kubectl delete pod postgres-sample-1 --grace-period=0 --force

#   Name |  Node |                                                              Host:Port |       TLI: LSN |   Connection |      Reported State |      Assigned State
# -------+-------+------------------------------------------------------------------------+----------------+--------------+---------------------+--------------------
# node_1 |     1 | postgres-sample-1.postgres-sample-agent.default.svc.cluster.local:5432 |   2: 0/3023DE8 |    read-only |           secondary |           secondary
# node_2 |     2 | postgres-sample-0.postgres-sample-agent.default.svc.cluster.local:5432 |   2: 0/3023DE8 |   read-write |             primary |             primary

# Cool!

###################################################################################
# 7. Log into FSM
###################################################################################
kubectl get secret postgres-sample-monitor-secret -o go-template='{{range $k,$v := .data}}{{printf \"%s: \" $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{\"\n\"}}{{end}}'
# instancename: postgres-sample
# namespace: default
# password: 7Ulo22ne50n55moNGhMvnQpwe47h6C
# username: autoctl_node

# Try to access
kubectl port-forward pod/postgres-sample-monitor-0 5432:5432

# Access internally
kubectl exec -it pod/postgres-sample-monitor-0 -c monitor -- /bin/bash