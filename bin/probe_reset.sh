#!/bin/bash

PROBES=/fs0/od/nimsoft/probes
LOGMON=$PROBES/system/logmon/logmon.cfg
JDBCRESP=$PROBES/database/jdbc_response/jdbc_response.cfg
URLRESP=$PROBES/application/url_response/url_response.cfg
CDM=$PROBES/system/cdm/cdm.cfg
NEXEC=$PROBES/service/nexec/nexec.cfg
PROCESSES=$PROBES/system/processes/processes.cfg

TS=$(date +"%m%d%Y%H%M%S")

for i in $LOGMON $JDBCRESP $URLRESP $CDM $NEXEC $PROCESSES; 
do 
    cp -f $i $i.$TS
    rm -f $i
done

echo "All probe configs are cleared, package can be re-deployed for testing"

exit
