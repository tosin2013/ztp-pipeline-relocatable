#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -m

usage() { echo "Usage: $0 <pull-secret-file> <ocp-version(4.10.6)> <acm_version(2.4)> <ocs_version(4.8)>" 1>&2; exit 1; }

if [ $# -ne 4 ]; then
    usage
fi

export pull_secret=${1}
export ocp_version=${2}
export acm_version=${3}
export ocs_version=${4}

if [ -z "${pull_secret}" ] || [ -z "${ocp_version}" ] || [ -z "${acm_version}" ] || [ -z "${ocs_version}" ]; then
    usage
fi

if [[ "$ocp_version" =~ [0-9]+.[0-9]+.[0-9]+ ]]; then
    echo "ocp_version is valid"
else
    echo $ocp_version
    echo "ocp_version is not valid"
    usage
fi


# variables
# #########
export DEPLOY_OCP_DIR="./"
export OC_RELEASE="quay.io/openshift-release-dev/ocp-release:$ocp_version-x86_64"
export OC_CLUSTER_NAME="test-ci"
export OC_DEPLOY_METAL="yes"
export OC_NET_CLASS="ipv4"
export OC_TYPE_ENV="connected"
export VERSION="ci"
export CLUSTERS=0
export OC_PULL_SECRET="'$(cat $pull_secret)'"
export OC_OCP_VERSION="${ocp_version}"
export OC_ACM_VERSION="${acm_version}"
export OC_OCS_VERSION="${ocs_version}"

echo ">>>> Set the Pull Secret"
echo ">>>>>>>>>>>>>>>>>>>>>>>>"
echo $OC_PULL_SECRET | tr -d [:space:] | sed -e 's/^.//' -e 's/.$//' >./openshift_pull.json

echo ">>>> kcli create plan"
echo ">>>>>>>>>>>>>>>>>>>>>"

if [ "${OC_DEPLOY_METAL}" = "yes" ]; then
    if [ "${OC_NET_CLASS}" = "ipv4" ]; then
        if [ "${OC_TYPE_ENV}" = "connected" ]; then
            echo "Metal3 + Ipv4 + connected"
            t=$(echo "${OC_RELEASE}" | awk -F: '{print $2}')
            git pull
            kcli create network --nodhcp --domain ztpfw -c 192.168.7.0/24 ztpfw
            kcli create plan --force --paramfile=lab-metal3.yml -P disconnected="false" -P version="${VERSION}" -P tag="${t}" -P openshift_image="${OC_RELEASE}" -P cluster="${OC_CLUSTER_NAME}" "${OC_CLUSTER_NAME}"
        else
            echo "Metal3 + ipv4 + disconnected"
            t=$(echo "${OC_RELEASE}" | awk -F: '{print $2}')
            kcli create plan --force --paramfile=lab-metal3.yml -P disconnected="true" -P version="${VERSION}" -P tag="${t}" -P openshift_image="${OC_RELEASE}" -P cluster="${OC_CLUSTER_NAME}" "${OC_CLUSTER_NAME}"
        fi
    else
        echo "Metal3 + ipv6 + disconnected"
        t=$(echo "${OC_RELEASE}" | awk -F: '{print $2}')
        kcli create plan --force --paramfile=lab_ipv6.yml -P disconnected="true" -P version="${VERSION}" -P tag="${t}" -P openshift_image="${OC_RELEASE}" -P cluster="${OC_CLUSTER_NAME}" "${OC_CLUSTER_NAME}"

    fi
else
    echo "Without Metal3 + ipv4 + connected"
    kcli create kube openshift --force --paramfile lab-withoutMetal3.yml -P tag="${OC_RELEASE}" -P cluster="${OC_CLUSTER_NAME}" "${OC_CLUSTER_NAME}"
fi

# Spokes.yaml file generation

#Empty file before we start

>spokes.yaml

# Default configuration
echo "config: " >> spokes.yaml
echo "  OC_OCP_VERSION: '"${OC_OCP_VERSION}"'" >> spokes.yaml
echo "  OC_ACM_VERSION: '"${OC_ACM_VERSION}"'" >> spokes.yaml
echo "  OC_OCS_VERSION: '"${OC_OCS_VERSION}"'" >> spokes.yaml
echo "spokes: " >> spokes.yaml


kcli create dns -n bare-net httpd-server.apps.test-ci.alklabs.com -i 192.168.150.252
kcli create dns -n bare-net ztpfw-registry-ztpfw-registry.apps.test-ci.alklabs.com -i 192.168.150.252

echo ">>>> EOF"
echo ">>>>>>>>"
