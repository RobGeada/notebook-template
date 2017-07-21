#!/bin/bash

#login to OpenShift
#oc login -u rgeada -p rgeada https://et0.et.eng.bos.redhat.com:8443/

#define new project name
PNAME=neuralspark-$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-z' | fold -w 2 | head -n 1)

#delete old projects under same name family
oc delete project $(oc projects -q | grep neuralspark)

#push worker image
cd spark-worker
docker build -t rgeada/spark-worker .
docker push rgeada/spark-worker

#push notebook image
cd ../notebook
docker build -t rgeada/notebook .
docker push rgeada/notebook

#deploy oshinko
cd ..
oc new-project $PNAME
oc create configmap default-oshinko-cluster-config --from-file=desired-cluster-config
./oshinko-deploy.sh -s rgeada/spark-worker -u rgeada -p $PNAME

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
oc new-app rgeada/notebook

#expose route to notebook
oc expose service notebook
NOTEBOOK_URL=$(oc get routes | awk '{print $2}' | grep notebook)

#wait until notebook is fully deployed
while [[ $(oc get pods | awk '/notebook/ && !/deploy/' | awk '{print $2}') != "1/1" ]] 
	do
		echo "Waiting for notebook pod to spin up..."
		sleep 5
	done

open http://$NOTEBOOK_URL

