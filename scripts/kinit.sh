#!/bin/bash 

SLEEP_SECONDS=3600
cat /etc/keytabs/keytab | base64 -d > ${APP_KEYTAB}

echo "[$(date)] - Initialize kinit"
kinit -kV ${APP_SPN} -t ${APP_KEYTAB}

if [ ${POD_TYPE} == "INIT" ]; then exit 0; fi

while true
do
    echo "[$(date)] - Refeshing kinit"
    kinit -R

    echo "[$(date)] - Sleeping for ${SLEEP_SECONDS} seconds"
    sleep ${SLEEP_SECONDS}
done