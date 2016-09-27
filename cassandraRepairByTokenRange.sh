#!/bin/bash
#
# Repair will be executed by keyspace.table & token range
# Assumptions:
# * Cassandra is running
# * nodetool is available via PATH env var
#


SCH=$(echo "describe schema;" | cqlsh)
for KSP in $(echo "${SCH}" | awk '/KEYSPACE/ {print $3}'); do
    KSP=${KSP//\"/}
    for RNG in $(nodetool describering ${KSP} | awk -F: '/TokenRange/ && /start_token/ {print $2, $3}' | awk '{print "-st_"$1"_-et_"$3}'); do
        RNG=${RNG//_/ }
        RNG=${RNG//,/}
        for TBL in $(echo "${SCH}" | sed -n '/'${KSP}'/,/CREATE KEYSPACE/p' | awk '/CREATE TABLE/ {print $3}'); do
            TBL=${TBL/*./}
            CMD="nodetool repair -pr ${RNG} -- ${KSP} ${TBL}"
            printf "INFO: Executing ${CMD} \n"
            $CMD
        done
    done
done
