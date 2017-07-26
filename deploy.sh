#!/bin/bash

#========================================================
#echo setup
#========================================================
NC="\x1b[39;49;00m"
GR='\033[0;32m'
RE='\033[0;31m'
DONE_MSG="${GR}[DONE]${NC}" 
FAIL_MSG="${RE}[FAIL]${NC}"

#========================================================
#parse arguments
#========================================================
DEFAULT_OPENSHIFT_PROJECT=auto-project
DEFAULT_OPENSHIFT_USER=developer

while getopts :c:u:p:h opt; do
    case $opt in
        c)
            OS_CLUSTER=$OPTARG
            ;;
        u)
            OS_USER=$OPTARG
            USER_REQUESTED=true
            ;;
        p)
            PROJECT=$OPTARG
            ;;
        h)
			echo
            echo "Usage: deploy.sh [options]"
            echo
            echo "Automatic deployment of the Oshinko suite and your notebook/data into OpenShift "
            echo
            echo "optional arguments:"
            echo "  -h            show this help message"
            echo "  -c CLUSTER    OpenShift cluster url to login against (default: https://localhost:8443)"
            echo "  -u USER       OpenShift user to run commands as (default: $DEFAULT_OPENSHIFT_USER)"
            echo "  -p PROJECT    OpenShift project name (default: $DEFAULT_OPENSHIFT_PROJECT)"
            echo
            exit
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit
            ;;
    esac
done

if [ -z "$PROJECT" ]
then
    echo "project name not set, using default value"
    PROJECT=$DEFAULT_OPENSHIFT_PROJECT
fi

if [ -z "$OS_USER" ]
then
    echo "openshift user not set, using default value"
    OS_USER=$DEFAULT_OPENSHIFT_USER
fi

#========================================================
#here's the actual script
#========================================================

#define new project name
PNAME=${PROJECT}-$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-z' | fold -w 2 | head -n 1)

#get docker username
USERNAME=$(docker info | sed '/Username:/!d;s/.* //')

if [ -z "$USERNAME" ]
then
    echo "Are you not logged into docker? Please login and try again"
    exit
fi

#get deploy dir, format logs
LOG_DIR=$(pwd)/deploy.log
echo "Deploy started at $(date)" > ${LOG_DIR}

#build worker image
echo -n "Building worker image...               " 
cd spark-worker
docker build -t ${USERNAME}/auto-spark-worker . >> ${LOG_DIR}
echo -e "${DONE_MSG}"

#push worker image
echo -n "Pushing worker image...                "
docker push ${USERNAME}/auto-spark-worker >> ${LOG_DIR}
echo -e "${DONE_MSG}"

#build notebook image
cd ../notebook
echo -n "Building notebook image...             "
docker build -t ${USERNAME}/auto-notebook . >> ${LOG_DIR}
echo -e "${DONE_MSG}"

#push notebook image
echo -n "Pushing notebook image...              "
docker push ${USERNAME}/auto-notebook >> ${LOG_DIR}
echo -e "${DONE_MSG}"

#check for OpenShift credentials
#this is hacky, can it be made better?
cd ..
echo -n "Checking OpenShift credentials...      "
if [ ! -z "$(oc login $OS_CLUSTER -u $OS_USER </dev/null | grep Password)" ]
then
    echo
    echo "Authentication required for ${OS_CLUSTER} (openshift)"
    echo "Username: ${OS_USER}"
    read -s -p "Password: " PASSWORD
    echo
    oc login $OS_CLUSTER -u $OS_USER -p $PASSWORD >> ${LOG_DIR}
    PASSWORD="blank"
    echo
else
    echo -e "${DONE_MSG}" 
fi

#deploy oshinko
echo -n "Deploying Oshinko...                   "
./oshinko-deploy.sh -s ${USERNAME}/auto-spark-worker -u $OS_USER -p $PNAME -c $OS_CLUSTER  >> ${LOG_DIR}
echo -e "${DONE_MSG}"

#delete old projects under same name family
echo -n "Cleaning old auto-deploy projects...   "
oc delete project $(oc projects -q | grep ${PROJECT} | grep -v ${PNAME}) >> ${LOG_DIR}
echo -e "${DONE_MSG}"

#expose REST server
echo -n "Exposing Oshinko REST server...        "
oc expose service oshinko-rest >> ${LOG_DIR}
REST_URL=$(oc get routes | awk '{print $2}' | grep rest)/clusters
echo -e "${DONE_MSG}"

#wait until oshinko is fully deployed
echo -n "Waiting for Oshinko pods to spin up... "
while [[ $(oc get pods | awk '/oshinko/ && !/deploy/' | awk '{print $2}') != "2/2" ]] 
	do
		sleep 3
	done
echo -e "${DONE_MSG}"

#create Spark cluster
echo -n "Creating Spark cluster...              "
SPARK_SUCC=$(curl -s -H "Content-Type: application/json" -X POST -d '{"name": "sparky", "config": {"workerCount": 9, "masterCount": 1}}' $REST_URL)
echo $SPARK_SUCC >> ${LOG_DIR}

#check to make sure it worked
if [ "${SPARK_SUCC: -10:7}" != 'Running' ]
then
    echo -e "${FAIL_MSG}"
    echo $SPARK_SUCC
    echo  
    echo "Spark cluster creation failed. Check the logs or run ./auto-deploy -c -s to try again."
    echo
    exit
fi
echo -e "${DONE_MSG}"

#add notebook image
echo -n "Creating notebook image...             "
oc new-app ${USERNAME}/auto-notebook >> ${LOG_DIR}
echo -e "${DONE_MSG}"

#expose route to notebook
echo -n "Exposing notebook image...             "
oc expose service auto-notebook >> ${LOG_DIR}
NOTEBOOK_URL=$(oc get routes | awk '{print $2}' | grep auto-notebook)
echo -e "${DONE_MSG}"

#wait until notebook is fully deployed
echo -n "Waiting for notebook pod to spin up... "
while [[ $(oc get pods | awk '/notebook/ && !/deploy/' | awk '{print $2}') != "1/1" ]] 
	do
		sleep 3
	done
echo -e "${DONE_MSG}"

#give the Jupyter server some time to get ready
echo -n "Waiting for Jupyter readiness...       "
while [ ! -z "$(curl -s http://${NOTEBOOK_URL}/login | grep 'not available')" ] || [ ! -z "$(curl -sS http://${NOTEBOOK_URL}/login 2>&1 >/dev/null | grep 't resolve host')" ]
    do
        sleep 3
    done
echo -e "${DONE_MSG}"

#open the notebook for the user
open http://$NOTEBOOK_URL

#report success!
echo "Auto-deployment complete!"
echo