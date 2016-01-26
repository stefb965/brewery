#!/bin/bash

set -e

source ${BUILD_DIRECTORY:-.}/scripts/cf-common.sh
root=`pwd`

READY_FOR_TESTS="no"
echo "Waiting for RabbitMQ to boot for [$(( WAIT_TIME * RETRIES ))] seconds"
# create RabbitMQ
APP_NAME=rabbitmq
cf s | grep ${APP_NAME} && echo "found ${APP_NAME}" && READY_FOR_TESTS="yes" ||
    cf cs cloudamqp lemur ${APP_NAME} && echo "Started RabbitMQ" && READY_FOR_TESTS="yes"

if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
    echo "RabbitMQ failed to start..."
    exit 1
fi

READY_FOR_TESTS="no"
echo "Waiting for Zookeeper to boot for [$(( WAIT_TIME * RETRIES ))] seconds"
cf s | grep "zookeeper" && cf ds -f "zookeeper"
deploy_service "zookeeper" && READY_FOR_TESTS="yes"

if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
    echo "Zookeeper failed to start..."
    exit 1
fi

# Boot zipkin-stuff
echo -e "\n\nBooting up MySQL"
READY_FOR_TESTS="no"
# create MySQL DB
APP_NAME=mysql
cf s | grep ${APP_NAME} && echo "found ${APP_NAME}" && READY_FOR_TESTS="yes" ||
    cf cs cleardb spark ${APP_NAME} && echo "Started ${APP_NAME}" && READY_FOR_TESTS="yes"

if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
    echo "MySQL failed to start..."
    exit 1
fi

cd $root

# deploy zipkin-server
echo -e "\n\nBooting up Zipkin Server"
zq=zipkin-server
cd $root/$zq
reset $zq
cf d -f $zq
cd $root/zipkin-server
cf push && READY_FOR_TESTS="yes"

if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
    echo "Zipkin Server failed to start..."
    exit 1
fi
cd $root

# deploy zipkin-web
zw=zipkin-web
reset $zw
cf d -f $zw
zqs_name=`app_domain $zq`
cd $root/zipkin-web
cf push --no-start
jcjm=`$root/scripts/deploy-helper.py $zqs_name`
cf set-env $zw JBP_CONFIG_JAVA_MAIN "${jcjm}"
cf restart $zw && READY_FOR_TESTS="yes"

if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
    echo "Zipkin Web failed to start..."
    exit 1
fi
cd $root

# Boot config-server
READY_FOR_TESTS="no"
echo "Waiting for the Config Server app to boot for [$(( WAIT_TIME * RETRIES ))] seconds"
cf s | grep "config-server" && cf ds -f "config-server"
deploy_service "config-server" && READY_FOR_TESTS="yes"

if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
    echo "Config server failed to start..."
    exit 1
fi

cd $root
echo -e "\n\nStarting brewery apps..."
deploy_app "presenting"
deploy_app "brewing"
deploy_app "zuul"

echo -e "\n\nSetting test opts for sleuth stream to call localhost"
ACCEPTANCE_TEST_OPTS="-DLOCAL_URL=http://localhost"