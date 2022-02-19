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