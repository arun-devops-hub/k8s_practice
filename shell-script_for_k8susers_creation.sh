#!/bin/bash

# Variables
USER_NAME=$1
NAMESPACE=$2
CLUSTER_NAME=$3
CLUSTER_API_SERVER=$4
CLUSTER_CA_CERT=$5
KEY_DIR=${6:-./certs}

# Check for required arguments
if [[ -z "$USER_NAME" || -z "$NAMESPACE" || -z "$CLUSTER_NAME" || -z "$CLUSTER_API_SERVER" || -z "$CLUSTER_CA_CERT" ]]; then
    echo "Usage: $0 <user_name> <namespace> <cluster_name> <cluster_api_server> <cluster_ca_cert> [key_dir]"
    exit 1
fi

# Create directory for keys and certs if it doesn't exist
mkdir -p $KEY_DIR

# Generate private key and CSR
openssl genrsa -out ${KEY_DIR}/${USER_NAME}.key 2048
openssl req -new -key ${KEY_DIR}/${USER_NAME}.key -out ${KEY_DIR}/${USER_NAME}.csr -subj "/CN=${USER_NAME}/O=${NAMESPACE}"

# Generate the certificate using the Kubernetes CA
openssl x509 -req -in ${KEY_DIR}/${USER_NAME}.csr -CA $CLUSTER_CA_CERT -CAkey $CLUSTER_CA_CERT.key -CAcreateserial -out ${KEY_DIR}/${USER_NAME}.crt -days 365

# Create ClusterRole for the user
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${USER_NAME}-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "deployments"]
  verbs: ["get", "list", "watch"]
EOF

# Create ClusterRoleBinding for the user
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${USER_NAME}-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${USER_NAME}-role
subjects:
- kind: User
  name: ${USER_NAME}
  apiGroup: rbac.authorization.k8s.io
EOF

# Create kubeconfig file for the user
KUBECONFIG_FILE=${KEY_DIR}/${USER_NAME}-kubeconfig

kubectl config set-cluster ${CLUSTER_NAME} \
  --certificate-authority=$CLUSTER_CA_CERT \
  --embed-certs=true \
  --server=${CLUSTER_API_SERVER} \
  --kubeconfig=${KUBECONFIG_FILE}

kubectl config set-credentials ${USER_NAME} \
  --client-certificate=${KEY_DIR}/${USER_NAME}.crt \
  --client-key=${KEY_DIR}/${USER_NAME}.key \
  --embed-certs=true \
  --kubeconfig=${KUBECONFIG_FILE}

kubectl config set-context ${USER_NAME}@${CLUSTER_NAME} \
  --cluster=${CLUSTER_NAME} \
  --user=${USER_NAME} \
  --namespace=${NAMESPACE} \
  --kubeconfig=${KUBECONFIG_FILE}

kubectl config use-context ${USER_NAME}@${CLUSTER_NAME} --kubeconfig=${KUBECONFIG_FILE}

echo

