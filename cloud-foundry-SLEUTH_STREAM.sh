#!/bin/bash

set -e

source ${BUILD_DIRECTORY:-.}/scripts/cf-common.sh
root=`pwd`

# ====================================================
if [[ -z "${DEPLOY_ONLY_APPS}" ]] ; then
    echo -e "\nDeploying infrastructure apps\n\n"

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

    # ====================================================]

    READY_FOR_TESTS="no"
    echo "Waiting for Eureka to boot for [$(( WAIT_TIME * RETRIES ))] seconds"
    cf s | grep "discovery" && cf ds -f "discovery"
    deploy_app_with_name "eureka" "discovery" && READY_FOR_TESTS="yes"
    deploy_service "discovery" && READY_FOR_TESTS="yes"

    if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
        echo "Eureka failed to start..."
        exit 1
    fi

    DISCOVERY_HOST=`app_domain discovery`
    echo -e "Discovery host is [${DISCOVERY_HOST}]"

    # ====================================================
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

    # ====================================================
    cd $root

    echo -e "\n\nDeploying Zipkin Server"
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

    # ====================================================
    echo -e "\n\nDeploying Zipkin Web"
    zw=zipkin-web
    reset $zw
    cf d -f $zw
    zqs_name=`app_domain $zq`
    echo -e "Zipkin Web server host is [${zqs_name}]"
    cd $root/zipkin-web
    cf push --no-start
    jcjm=`$root/scripts/zipkin-deploy-helper.py $zqs_name`
    echo -e "Setting env vars [${jcjm}]"
    cf set-env $zw JBP_CONFIG_JAVA_MAIN "${jcjm}"
    cf restart $zw && READY_FOR_TESTS="yes"

    if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
        echo "Zipkin Web failed to start..."
        exit 1
    fi
    cd $root

    # ====================================================

    # Boot config-server
    READY_FOR_TESTS="no"
    echo "Waiting for the Config Server app to boot for [$(( WAIT_TIME * RETRIES ))] seconds"
    cf s | grep "config-server" && cf ds -f "config-server"
    deploy_app "config-server" && READY_FOR_TESTS="yes"
    deploy_service "config-server"

    if [[ "${READY_FOR_TESTS}" == "no" ]] ; then
        echo "Config server failed to start..."
        exit 1
    fi
else
    echo -e "\nWill not deploy infrastructure apps. Proceeding to brewery apps deployment.\n\n"
fi

# ====================================================

cd $root
echo -e "\n\nStarting brewery apps..."
deploy_app "presenting"
deploy_app "brewing"
deploy_app "zuul"

# ====================================================

PRESENTING_HOST=`app_domain presenting`
ZIPKIN_SERVER_HOST=`app_domain zipkin-server`
echo -e "Presenting host is [${PRESENTING_HOST}]"
echo -e "Zikpin server host is [${ZIPKIN_SERVER_HOST}]"

ACCEPTANCE_TEST_OPTS="-DLOCAL_URL=http://${ZIPKIN_SERVER_HOST} -Dpresenting.url=http://${PRESENTING_HOST} -Dzipkin.query.port=80"
echo -e "\n\nSetting test opts for sleuth stream to call ${ACCEPTANCE_TEST_OPTS}"
