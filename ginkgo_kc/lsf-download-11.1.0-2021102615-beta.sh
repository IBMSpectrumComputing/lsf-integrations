#!/bin/bash
#-----------------------------------
# Copyright IBM Corp. 1992, 2021. All rights reserved.
# US Government Users Restricted Rights - Use, duplication or disclosure
# restricted by GSA ADP Schedule Contract with IBM Corp.
#-----------------------------------

# lsf-download.sh pull down LSF suites images from IBM Cloud Container Registry
# Environment variable: API_KEY must be set

REGISTRY="icr.io"
IMAGE_REGISTRY="icr.io/ibm-spectrum-lsf"
IMAGE_REGISTRY_OP="icr.io/cpopen"
SUITE_VERSION="11.1.0-2021102615"
KAFKA_VERSION="latest"
ZOOKEEPER_VERSION="latest"
#BUILDNUM="_BUILDNUM_"
ARCH=`arch`
NARCH=$(if [ `arch` = "x86_64" ]; then echo "amd64" ; else echo "`arch`" ; fi)

# only download LSF core images for beta1.
LSF_IMAGES="ibm-spectrum-lsf-operator lsf-scheduler lsf-license-scheduler"
#LSF_IMAGES="ibm-spectrum-lsf-operator lsf-scheduler lsf-data-manager lsf-license-scheduler lsf-gui lsf-explorer-node lsf-cognitive lsf-simulator lsf-rtm-server lsf-rtm-lsfpoller lsf-rtm-licpoller lsf-rtm-client"


# expect environment variable API_KEY for image download
#export API_KEY=xxxxxxxx
if [[ x"$API_KEY" == x ]]; then
   echo "Missing API_KEY in environment variable."
   echo "<How to get ibm cloud API_KEY>"
   echo "    step 1: register a free acount on https://cloud.ibm.com/registration"
   echo "    step 2: request download permission by sending email to: "
   echo "            bill.mcmillan@uk.ibm.com, georgeg@ca.ibm.com"
   echo "    step 3: login https://cloud.ibm.com with the new account"
   echo "    step 4: In ibm cloud web console, click on 'Manage' on the top menu, select 'Access(IAM)'"
   echo "            Select 'API keys' on the left menu, click on 'Create an IBM Cloud API key'"
   echo "    step 5: copy and paste the API key string for environment variable: API_KEY"
fi

main(){
   checkenv
   login
   download
   extract
}

login(){
    if [[ "$API_KEY" == "" ]]; then
        echo "Environment API_KEY is required."
        exit
    fi

    docker login ${REGISTRY} -u iamapikey -p ${API_KEY}
    if [[ $? != 0 ]]; then
        echo "failed to login IBM Cloud Container registry."
        exit
    fi
}

download(){
    mkdir -p image_repo
    cd image_repo

    for image in $LSF_IMAGES
    do
        echo "pull down image: $image "
        TAR_FILE="${image}-${NARCH}_${SUITE_VERSION}.tgz"
        SIF_FILE="${image}-${NARCH}_${SUITE_VERSION}.sif"
        if [[ -f $TAR_FILE ]]; then
            rm -fr ${TAR_FILE}.old
            mv ${TAR_FILE} ${TAR_FILE}.old
        fi
        if [[ -f $SIF_FILE ]]; then
            rm -fr ${SIF_FILE}.old
            mv ${SIF_FILE} ${SIF_FILE}.old
        fi
        if [[ "$image" != "ibm-spectrum-lsf-operator" ]]; then
            IMAGE_PATH="${IMAGE_REGISTRY}/${image}:${SUITE_VERSION}-${NARCH}"
        else
            IMAGE_PATH="${IMAGE_REGISTRY_OP}/${image}:${SUITE_VERSION}-${NARCH}"
        fi
        if docker inspect $IMAGE_PATH > /dev/null 2>&1; then
            docker image rm -f $IMAGE_PATH
        fi

        docker image pull $IMAGE_PATH > /dev/null 2>&1
        if docker inspect $IMAGE_PATH > /dev/null 2>&1; then
            docker save $IMAGE_PATH | gzip > $TAR_FILE
        fi
    done

    # pull down mariaDB and Elasticsearcg image
    #if [[ ! -f mariadb_10.5.9-focal.tgz ]]; then
    #    docker pull mariadb:10.5.9-focal
    #    if docker inspect mariadb:10.5.9-focal > /dev/null 2>&1; then
    #        docker save mariadb:10.5.9-focal | gzip > mariadb_10.5.9-focal.tgz
    #    fi
    #fi
    #if [[ ! -f elasticsearch_7.12.1.tgz ]]; then
    #    docker pull docker.elastic.co/elasticsearch/elasticsearch:7.12.1
    #    if docker inspect docker.elastic.co/elasticsearch/elasticsearch:7.12.1 > /dev/null 2>&1; then
    #        docker save docker.elastic.co/elasticsearch/elasticsearch:7.12.1 |gzip > elasticsearch_7.12.1.tgz
    #    fi
    #fi
    if [[ ! -f zookeeper_${ZOOKEEPER_VERSION}.tgz ]]; then
        docker pull zookeeper:${ZOOKEEPER_VERSION}
        if docker inspect zookeeper:${ZOOKEEPER_VERSION} > /dev/null 2>&1; then
            docker save zookeeper:${ZOOKEEPER_VERSION} | gzip > zookeeper_${ZOOKEEPER_VERSION}.tgz
        fi
    fi
    if [[ ! -f kafka_${KAFKA_VERSION}.tgz ]]; then
        docker pull wurstmeister/kafka:${KAFKA_VERSION}
        if docker inspect wurstmeister/kafka:${KAFKA_VERSION} > /dev/null 2>&1; then
            docker save wurstmeister/kafka:${KAFKA_VERSION} | gzip > kafka_${KAFKA_VERSION}.tgz
        fi
    fi
    #if [[ ! -f docker_dind.tgz ]]; then
    #    docker pull docker:dind
    #    if docker inspect docker:dind > /dev/null 2>&1; then
    #        docker save docker:dind | gzip > docker_dind.tgz
    #    fi
    #fi

    cd ../
}

extract(){
    if [ -d lsf_repo ]; then
        rm -rf lsf_repo.old
	mv -f lsf_repo lsf_repo.old
    fi
    docker run -it --rm -v `pwd`:/copyto -v /etc/localtime:/etc/localtime -e "DEPLOYER_NAME=$HOSTNAME" --user=root --entrypoint extract-files.sh ${IMAGE_REGISTRY_OP}/ibm-spectrum-lsf-operator:${SUITE_VERSION}-${NARCH} 
    
    # append or modify IMAGE_REGISTRY and IMAGE_REGISTRY_OP 
    REGISTRY_COMMENT="# The following area is generated by lsf-download-${SUITE_VERSION}.sh, do not change it."

    if [[ ! -f lsf-config.yml ]]; then
        echo "Cannot find lsf-config.yml."
        return
    fi

    grep "^IMAGE_REGISTRY:" lsf-config.yml  > /dev/null
    if [[ $? == 0 ]];then
         sed -i 's/^IMAGE_REGISTRY:.\+//g' lsf-config.yml
    fi

    grep "^IMAGE_REGISTRY_OP:" lsf-config.yml  > /dev/null
    if [[ $? == 0 ]];then
         sed -i 's/^IMAGE_REGISTRY_OP:.\+//g' lsf-config.yml
    fi
    echo $REGISTRY_COMMENT  >> lsf-config.yml
    echo "IMAGE_REGISTRY: \"$IMAGE_REGISTRY\"" >> lsf-config.yml
    echo "IMAGE_REGISTRY_OP: \"$IMAGE_REGISTRY_OP\"" >> lsf-config.yml
}

checkenv(){
    if [[ "$API_KEY" == "" ]]; then
        echo "Environment API_KEY is required."
        exit
    fi
    # docker must be installed
    if ! command -v docker &> /dev/null
    then
        echo "docker is not installed."
        exit
    fi
    docker_version=`docker --version |cut -d" " -f3 |cut -d. -f1`
    v_value=`expr $docker_version`
    if [[ $v_value -lt 19 ]]; then
        echo "Docker version must be 19.x or above."
        exit
    fi

    #check disk space
    _path=`pwd`
    _rspace=`df -m $_path | awk '(NR > 1){
        if (NF==1) {
            if (index(tmp_devices, ","$1",")) {
                same_device_double_line_flag=1;
            } else {
                tmp_devices=tmp_devices","$1",";
                filesystmp=$1
            }
        }
        if (NF==5) {
            if (same_device_double_line_flag==1) {
                same_device_double_line_flag=0;
            } else {
                printf("%s %s %s %s %s %s %s\n",filesystmp,$1,$2,$3,$4,$5,$6);
            }
        }
        if (NF==6) {
            if (index(tmp_devices, ","$1",")) {
                tmp_devices=tmp_devices","$1",";
            } else {
                tmp_devices=tmp_devices","$1",";
                print
            }
        }
    }' | grep "\/"  | awk '{printf("%s\n",$4)}'`
    if [[ $_rspace -lt 30720 ]] ; then
        echo "Not enough available disk space($_rspace K) to install LSF suite. it requires 30G or more available disk space."
        exit
    fi
}

main "$@"
