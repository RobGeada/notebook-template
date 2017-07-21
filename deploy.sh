#!/bin/bash

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
username=$(docker info | sed '/Username:/!d;s/.* //')

if [ -z "$username" ]
then
    echo "Are you not logged into docker? Please login and try again"
    exit
fi

#push worker image
cd spark-worker
docker build -t ${username}/auto-spark-worker .
docker push ${username}/auto-spark-worker

#push notebook image
cd ../notebook
docker build -t ${username}/auto-notebook .
docker push ${username}/auto-notebook

#deploy oshinko
cd ..
echo 
./oshinko-deploy.sh -s ${username}/auto-spark-worker -u $OS_USER -p $PNAME -c $OS_CLUSTER

#delete old projects under same name family
oc delete project $(oc projects -q | grep ${PROJECT})

#expose REST server
oc expose service oshinko-rest
REST_URL=$(oc get routes | awk '{print $2}' | grep rest)/clusters

#wait until oshinko is fully deployed
while [[ $(oc get pods | awk '/oshinko/ && !/deploy/' | awk '{print $2}') != "2/2" ]] 
	do
		echo "Waiting for Oshinko pods to spin up..."
		sleep 5
	done
oc get pods

#create Spark cluster
curl -H "Content-Type: application/json" -X POST -d '{"name": "sparky", "config": {"workerCount": 10, "masterCount": 1}}' $REST_URL

#add notebook image
oc new-app ${username}/auto-notebook

#expose route to notebook
oc expose service auto-notebook
NOTEBOOK_URL=$(oc get routes | awk '{print $2}' | grep auto-notebook)

#wait until notebook is fully deployed
while [[ $(oc get pods | awk '/notebook/ && !/deploy/' | awk '{print $2}') != "1/1" ]] 
	do
		echo "Waiting for notebook pod to spin up..."
		sleep 5
	done

echo "Waiting for Jupyter page to ready up..."
sleep 10
open http://$NOTEBOOK_URL

