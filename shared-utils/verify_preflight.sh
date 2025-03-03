#!/usr/bin/env bash

set -o pipefail
set -o errexit
set -o nounset
set -m

# variables
# #########
# uncomment it, change it or get it from gh-env vars (default behaviour: get from gh-env)
# export KUBECONFIG=/root/admin.kubeconfig

# Load common vars
source ${WORKDIR}/shared-utils/common.sh

echo ">>>> Verify jq"
echo ">>>>>>>>>>>>>>"

if ! (command -v jq &>/dev/null); then
    echo "INFO: jq command not found. Installing..."
    curl -Ls https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 >/usr/bin/jq
    chmod u+x /usr/bin/jq

    if [ ! -d "/root/bin" ]; then
        mkdir -p /root/bin
        export PATH="${PATH}:/root/bin"
    fi
fi

echo ">>>> Verify oc"
echo ">>>>>>>>>>>>>>"
if ! (command -v oc &>/dev/null); then
    echo "INFO: oc command not found. Installing..."
    curl -k -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz | tar xvz -C /usr/bin
    chmod +x /usr/bin/oc /usr/bin/kubectl
fi

echo ">>>> Verify oc-mirror"
echo ">>>>>>>>>>>>>>"
if ! (command -v oc-mirror &>/dev/null); then
    echo "INFO: oc-mirror command not found. Installing..."
    # Need to use 4.13 because there's an ugly bug in oc-mirror<4.13 that won't let us create catalog sources for orgs with nested repos
    # https://github.com/openshift/oc-mirror/issues/540
    curl -k -s curl -sL https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp-dev-preview/latest-4.13/oc-mirror.tar.gz | tar xvz -C /usr/bin
    chmod +x /usr/bin/oc-mirror
fi

echo ">>>> Verify opm"
echo ">>>>>>>>>>>>>>>"
if ! (command -v opm &>/dev/null); then
    echo "INFO: opm command not found. Installing..."
    curl -k -s https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/opm-linux.tar.gz | tar xvz -C /usr/bin
    chmod +x /usr/bin/opm
fi

echo ">>>> Verify kubectl"
echo ">>>>>>>>>>>>>>>>>>>"
if ! (command -v kubectl &>/dev/null); then
    echo "INFO: opm command not found. Installing..."
    curl -L https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl >/usr/bin/kubectl
    chmod u+x /usr/bin/kubectl
fi

oc completion bash >>/etc/bash_completion.d/oc_completion

echo ">>>> Verify podman and htpasswd command"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
if ! (command -v podman &>/dev/null && command -v htpasswd &>/dev/null && command -v envsubst &>/dev/null); then
    echo "INFO: podman command not found. Installing..."
    yum install -y podman httpd-tools conmon skopeo gettext
fi

echo ">>>> Verify yq command"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
if ! command -v yq &>/dev/null; then
    echo "INFO: yq command not found. Installing..."
    curl -k -s https://github.com/mikefarah/yq/releases/download/v4.14.2/yq_linux_amd64 -o /usr/bin/yq &&
        chmod +x /usr/bin/yq
fi

echo ">>>> Loading the Kubeconfig file"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
if [ ! -f "${KUBECONFIG}" ]; then
    echo "Error: Kubeconfig file not found in the path passed in github actions"
    exit 1
fi

echo ">>>> Verify oc get nodes"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>"
# TO-DO: Installed VSphere with assisted installer and enable VSphere during deployment
# Get the deployment provider type from the API if the provider type is VSphere and 3 workers are ready then then contiune with script
PLATFORM_TYPE=$(oc get Infrastructure cluster -o jsonpath='{.spec.platformSpec.type}')
if [[ $(oc get nodes | grep -i ready | wc -l) -ne 1 ]] && [[ $(oc get nodes | grep -i ready | wc -l) -ne 3 ]] && [[ $PLATFORM_TYPE == "None" ]] then
    echo "Error: Nodes are not ready"
    exit 1
elif [[ $(oc get nodes -o wide -l "node-role.kubernetes.io/worker"| grep Ready | wc -l) -ge 3 ]] && [[ $PLATFORM_TYPE == "VSphere" ]] then
    echo "INFO: Nodes are ready"
else
    exit 1
fi

echo ">>>> Verify the cluster operator ready"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
retry=1
while [ ${retry} != 0 ]; do
    if [[ $(oc get co | awk '{print $3}' | grep -i true | wc -l) -ne $(($(oc get co | wc -l) - 1)) ]]; then
        echo "INFO: ClusterOperators are not ready. Trying again... ${retry}"
        sleep 10
        retry=$((retry + 1))
    else
        echo ">>>> Cluster Operators are ready"
        retry=0
    fi
    if [ ${retry} == 20 ]; then
        echo ">>>> ERROR: Retry limit reached to get Cluster Operators ready"
        exit 1
    fi
done

echo ">>>> Verify the metal3 pods ready"
echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
if [[ $(oc get pod -n openshift-machine-api | wc -l) -lt 1 ]]; then
    echo "Error: metal3 pods are not available to use ztp"
    exit 1
fi

echo ">>>> EOF"
echo ">>>>>>>>"
exit 0
