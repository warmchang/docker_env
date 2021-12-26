#!/usr/bin/env bash

set -e
set -x

build_number_list=$(cat << EOF
4.6.12
EOF
)

# params for operator hub images
export var_date='2021.01.18.1338'
echo $var_date
export var_major_version='4.6'
echo ${var_major_version}

/bin/rm -rf /data/ocp4/tmp/
mkdir -p /data/ocp4/tmp/
cd /data/ocp4/tmp/
git clone https://github.com/wangzheng422/docker_env

cd /data/ocp4/tmp/docker_env
git checkout dev
git pull origin dev
/bin/cp -f /data/ocp4/tmp/docker_env/redhat/ocp4/4.6/scripts/* /data/ocp4/

cd /data/ocp4/

mkdir -p /data/ocp4/clients
# client for camle-k
wget  -nd -np -e robots=off --reject="index.html*" -P /data/ocp4/clients --recursive https://mirror.openshift.com/pub/openshift-v4/clients/camel-k/latest/

# client for helm
wget  -nd -np -e robots=off --reject="index.html*" -P /data/ocp4/clients --recursive https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/

# client for pipeline
wget  -nd -np -e robots=off --reject="index.html*" -P /data/ocp4/clients --recursive https://mirror.openshift.com/pub/openshift-v4/clients/pipeline/latest/

# client for serverless
wget  -nd -np -e robots=off --reject="index.html*" -P /data/ocp4/clients --recursive https://mirror.openshift.com/pub/openshift-v4/clients/serverless/latest/

# coreos-installer
wget  -nd -np -e robots=off --reject="index.html*" -P /data/ocp4/clients --recursive https://mirror.openshift.com/pub/openshift-v4/clients/coreos-installer/latest/

mkdir -p /data/ocp4
/bin/rm -f /data/finished
cd /data/ocp4

install_build() {
    BUILDNUMBER=$1
    echo ${BUILDNUMBER}

    rm -rf /data/ocp4/${BUILDNUMBER}
    mkdir -p /data/ocp4/${BUILDNUMBER}
    cd /data/ocp4/${BUILDNUMBER}

    wget -O release.txt https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${BUILDNUMBER}/release.txt

    wget -O openshift-client-linux-${BUILDNUMBER}.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${BUILDNUMBER}/openshift-client-linux-${BUILDNUMBER}.tar.gz
    wget -O openshift-install-linux-${BUILDNUMBER}.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${BUILDNUMBER}/openshift-install-linux-${BUILDNUMBER}.tar.gz

    tar -xzf openshift-client-linux-${BUILDNUMBER}.tar.gz -C /usr/local/sbin/
    tar -xzf openshift-install-linux-${BUILDNUMBER}.tar.gz -C /usr/local/sbin/

    export OCP_RELEASE=${BUILDNUMBER}
    export LOCAL_REG='registry.redhat.ren:5443'
    export LOCAL_REPO='ocp4/openshift4'
    export UPSTREAM_REPO='openshift-release-dev'
    export LOCAL_SECRET_JSON="/data/pull-secret.json"
    export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=${LOCAL_REG}/${LOCAL_REPO}:${OCP_RELEASE}
    export RELEASE_NAME="ocp-release"

    oc adm release mirror -a ${LOCAL_SECRET_JSON} \
    --from=quay.io/${UPSTREAM_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-x86_64 \
    --to-release-image=${LOCAL_REG}/${LOCAL_REPO}:${OCP_RELEASE} \
    --to=${LOCAL_REG}/${LOCAL_REPO}

    export RELEASE_IMAGE=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${BUILDNUMBER}/release.txt | grep 'Pull From: quay.io' | awk -F ' ' '{print $3}')

    oc adm release extract --registry-config ${LOCAL_SECRET_JSON} --command='openshift-baremetal-install' ${RELEASE_IMAGE}


}

while read -r line; do
    install_build $line
done <<< "$build_number_list"

cd /data/ocp4

wget --recursive --no-directories --no-parent -e robots=off --accept="rhcos-live*,rhcos-qemu*,rhcos-metal*,rhcos-openstack*"  https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${var_major_version}/latest/

wget -O ocp-deps-sha256sum.txt https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/${var_major_version}/latest/sha256sum.txt

wget -O ocp4-upi-helpernode.zip https://github.com/wangzheng422/ocp4-upi-helpernode/archive/master.zip

wget -O docker_env.zip https://github.com/wangzheng422/docker_env/archive/dev.zip

wget -O agnosticd.zip https://github.com/wangzheng422/agnosticd/archive/wzh-ccn-ocp-4.6.zip

podman pull quay.io/wangzheng422/filetranspiler
podman save quay.io/wangzheng422/filetranspiler | pigz -c > filetranspiler.tgz

podman pull docker.io/library/registry:2
podman save docker.io/library/registry:2 | pigz -c > registry.tgz

oc image mirror --filter-by-os='linux/amd64' docker.io/wangzheng422/operator-catalog:redhat-${var_major_version}-${var_date} ${LOCAL_REG}/ocp4/operator-catalog:redhat-${var_major_version}-${var_date}
oc image mirror --filter-by-os='linux/amd64' docker.io/wangzheng422/operator-catalog:certified-${var_major_version}-${var_date} ${LOCAL_REG}/ocp4/operator-catalog:certified-${var_major_version}-${var_date}
oc image mirror --filter-by-os='linux/amd64' docker.io/wangzheng422/operator-catalog:community-${var_major_version}-${var_date} ${LOCAL_REG}/ocp4/operator-catalog:community-${var_major_version}-${var_date}
oc image mirror --filter-by-os='linux/amd64' docker.io/wangzheng422/operator-catalog:redhat-marketplace-${var_major_version}-${var_date} ${LOCAL_REG}/ocp4/operator-catalog:redhat-marketplace-${var_major_version}-${var_date}

cd /data/ocp4

# 以下命令要运行 2-3个小时，耐心等待。。。
# bash image.mirror.install.sh

# some github, and so on
bash demos.sh

# build operator catalog
find /tmp -type d -regex '^/tmp/[0-9]+$' -exec rm -rf {} + 

oc adm catalog mirror --filter-by-os='linux/amd64' \
    docker.io/wangzheng422/operator-catalog:redhat-${var_major_version}-$var_date \
    registry.redhat.ren:5443/ocp4 \
    --manifests-only 
/bin/cp -f operator-catalog-manifests/mapping.txt mapping-redhat.txt
sed -i 's/=.*//g' mapping-redhat.txt

VAR_DIR=`find /tmp -type d -regex '^/tmp/[0-9]+$' `
echo "select * from related_image ;" \
  | sqlite3 -line $VAR_DIR/index.db \
  | paste -d " " - - - | sed 's/ *image = //g' \
  | sed 's/operatorbundle_name =//g' \
  | sort | uniq > redhat-operator-image.list

find /tmp -type d -regex '^/tmp/[0-9]+$' -exec rm -rf {} + 

oc adm catalog mirror --filter-by-os='linux/amd64' \
    docker.io/wangzheng422/operator-catalog:certified-${var_major_version}-$var_date \
    registry.redhat.ren:5443/ocp4 \
    --manifests-only 
/bin/cp -f operator-catalog-manifests/mapping.txt mapping-certified.txt
sed -i 's/=.*//g' mapping-certified.txt

VAR_DIR=`find /tmp -type d -regex '^/tmp/[0-9]+$' `
echo "select * from related_image ;" \
  | sqlite3 -line $VAR_DIR/index.db \
  | paste -d " " - - - | sed 's/ *image = //g' \
  | sed 's/operatorbundle_name =//g' \
  | sort | uniq > certified-operator-image.list

find /tmp -type d -regex '^/tmp/[0-9]+$' -exec rm -rf {} + 

oc adm catalog mirror --filter-by-os='linux/amd64' \
    docker.io/wangzheng422/operator-catalog:community-${var_major_version}-$var_date \
    registry.redhat.ren:5443/ocp4 \
    --manifests-only 
/bin/cp -f operator-catalog-manifests/mapping.txt mapping-community.txt
sed -i 's/=.*//g' mapping-community.txt

VAR_DIR=`find /tmp -type d -regex '^/tmp/[0-9]+$' `
echo "select * from related_image ;" \
  | sqlite3 -line $VAR_DIR/index.db \
  | paste -d " " - - - | sed 's/ *image = //g' \
  | sed 's/operatorbundle_name =//g' \
  | sort | uniq > community-operator-image.list

find /tmp -type d -regex '^/tmp/[0-9]+$' -exec rm -rf {} + 

oc adm catalog mirror --filter-by-os='linux/amd64' \
    docker.io/wangzheng422/operator-catalog:redhat-marketplace-${var_major_version}-$var_date \
    registry.redhat.ren:5443/ocp4 \
    --manifests-only
/bin/cp -f operator-catalog-manifests/mapping.txt mapping-redhat-marketplace.txt
sed -i 's/=.*//g' mapping-redhat-marketplace.txt

VAR_DIR=`find /tmp -type d -regex '^/tmp/[0-9]+$' `
echo "select * from related_image ;" \
  | sqlite3 -line $VAR_DIR/index.db \
  | paste -d " " - - - | sed 's/ *image = //g' \
  | sed 's/operatorbundle_name =//g' \
  | sort | uniq > redhat-marketplace-image.list

bash image.registries.conf.sh nexus.ocp4.redhat.ren:8083

/bin/rm -f index.html*
/bin/rm -rf operator-catalog-manifests
/bin/rm -f sha256sum.txt*
/bin/rm -f clients/sha256sum.txt*
/bin/rm -rf /data/ocp4/tmp
/bin/rm -rf operator-catalog-manifests
find /tmp -type d -regex '^/tmp/[0-9]+$' -exec rm -rf {} + 

cd /data

var_finish_date=$(date '+%Y-%m-%d-%H%M')
echo $var_finish_date > /data/finished

