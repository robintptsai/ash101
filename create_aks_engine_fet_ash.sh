#!/bin/bash
# user defined variable
RESOURCE_GROUP="rgRobinAks"
CLUSTER_PREFIX="robin-aks"

#  CB103001 on fetcb103001
SUBSCRIPTION_ID="92b3282e-9136-4c5a-94c4-ce0836a10cab"

# spStackApp123 on fetcb103001
SP_CLIENT_ID="8b631e16-011f-4ea2-b685-01da9455d732"
SP_CLIENT_SECRET="MaE7Q~XyvvBP1tMHvtWP-_Rwh2Oi1.RjFgEBa"


IDENTITY_SYSTEM="azure_ad" #adfs or azure_ad
AGENT_SUBNET_ID="/subscriptions/92b3282e-9136-4c5a-94c4-ce0836a10cab/resourceGroups/rgRobinAks/providers/Microsoft.Network/virtualNetworks/vnetAks/subnets/agent-sn"
MASTER_SUBNET_ID="/subscriptions/92b3282e-9136-4c5a-94c4-ce0836a10cab/resourceGroups/rgRobinAks/providers/Microsoft.Network/virtualNetworks/vnetAks/subnets/control-sn"
FIRST_MASTER_IP="10.100.0.239"
LOCATION="taipei"
FQDN="fetazure.fetnet.net"
 


# Install require package
apt-get -f -y install
apt-get -y update
apt-get install --no-install-recommends -y pax curl apt-transport-https lsb-release software-properties-common dirmngr
 
# Download AKS engine
AKSE_VERSION="v0.67.0"
AKSE_ZIP_NAME="aks-engine-${AKSE_VERSION}-linux-amd64"
AKSE_ZIP_URL="https://github.com/Azure/aks-engine/releases/download/${AKSE_VERSION}/${AKSE_ZIP_NAME}.tar.gz"
curl --retry 5 --retry-delay 10 --max-time 60 -L -s -f -O $AKSE_ZIP_URL
tar -zxf $AKSE_ZIP_NAME.tar.gz
 
# Generate ssh key pair
mv -f sshkey sshkey.bak
mv -f sshkey.pub sshkey.pub.bak
ssh-keygen -t rsa -f sshkey -q -N ""
SSH_PUB_KEY=`cat sshkey.pub`
 
# Ensure cert
AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH="/var/lib/waagent/Certificates.pem"
AZURESTACK_ROOT_CERTIFICATE_DEST_PATH="/usr/local/share/ca-certificates/azsCertificate.crt"
cp $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH
AZURESTACK_ROOT_CERTIFICATE_SOURCE_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_SOURCE_PATH -noout -fingerprint`
AZURESTACK_ROOT_CERTIFICATE_DEST_FINGERPRINT=`openssl x509 -in $AZURESTACK_ROOT_CERTIFICATE_DEST_PATH -noout -fingerprint`
update-ca-certificates
REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
 
# Output API model
cat << EOF > /tmp/clusterDefinition.json
{
  "apiVersion": "vlabs",
  "location": "${LOCATION}",
  "properties": {
    "orchestratorProfile": {
      "orchestratorType": "Kubernetes",
      "orchestratorRelease": "1.19",
      "kubernetesConfig": {
        "kubernetesImageBase": "mcr.microsoft.com/k8s/azurestack/core/",
        "useInstanceMetadata": false,
        "networkPlugin": "azure",
        "networkPolicy": "",
        "containerRuntime": "docker",
        "cloudProviderBackoff": true,
        "cloudProviderBackoffRetries": 1,
        "cloudProviderBackoffDuration": 30,
        "cloudProviderRateLimit": true,
        "cloudProviderRateLimitQPS": 3,
        "cloudProviderRateLimitBucket": 10,
        "cloudProviderRateLimitQPSWrite": 3,
        "cloudProviderRateLimitBucketWrite": 10,
        "kubeletConfig": {
          "--node-status-update-frequency": "1m",
          "--max-pods": "50"
         },
        "controllerManagerConfig": {
          "--node-monitor-grace-period": "5m",
          "--pod-eviction-timeout": "5m",
          "--route-reconciliation-period": "1m"
        },
        "addons": [
          {
            "name": "tiller",
            "enabled": false
          }
        ]
      }
    },
    "customCloudProfile": {
      "portalURL": "https://portal.${LOCATION}.${FQDN}/",
      "authenticationMethod": "client_secret",
      "identitySystem": "${IDENTITY_SYSTEM}"
    },
    "masterProfile": {
      "dnsPrefix": "${CLUSTER_PREFIX}",
      "distro": "aks-ubuntu-18.04",
      "osDiskSizeGB": 50,
      "availabilityProfile": "AvailabilitySet",
      "count": 1,
      "vmSize": "Standard_D2_v2",
      "vnetSubnetId": "${MASTER_SUBNET_ID}",
      "firstConsecutiveStaticIP": "${FIRST_MASTER_IP}"
    },
    "agentPoolProfiles": [
      {
        "name": "linuxpool",
        "osDiskSizeGB": 50,
        "AcceleratedNetworkingEnabled": false,
        "distro": "aks-ubuntu-18.04",
        "count": 3,
        "vmSize": "Standard_D2_v2",
        "availabilityProfile": "AvailabilitySet",
        "vnetSubnetId": "${AGENT_SUBNET_ID}"
      }
    ],
    "linuxProfile": {
      "adminUsername": "azureuser",
      "ssh": {
        "publicKeys": [
          {
            "keyData": "${SSH_PUB_KEY}"
          }
        ]
      }
    },
    "windowsProfile": {
      "adminUsername": "azureuser",
      "adminPassword": "",
      "sshEnabled": true
    },
    "servicePrincipalProfile": {
      "clientId": "${SP_CLIENT_ID}",
      "secret": "${SP_CLIENT_SECRET}"
    }
  }
}
EOF
 
# Run AKS engine to build cluster
./${AKSE_ZIP_NAME}/aks-engine deploy -f \
 -g ${RESOURCE_GROUP} \
 --api-model /tmp/clusterDefinition.json \
 --auth-method client_secret \
 --azure-env AzureStackCloud \
 --location ${LOCATION} \
 --client-id ${SP_CLIENT_ID} \
 --client-secret ${SP_CLIENT_SECRET} \
 --identity-system ${IDENTITY_SYSTEM} \
 --subscription-id ${SUBSCRIPTION_ID}
 
mkdir ~/.kube/
cp -f _output/${CLUSTER_PREFIX}/kubeconfig/kubeconfig.${LOCATION}.json ~/.kube/config


