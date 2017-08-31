#!/bin/bash
#
# Perform repair by local token range
# Local ranges are broken into sub range repairs
# Assumptions:
# * Cassandra is running
# * The following is known
#
USR=cassandra
PWD=cassandra
#
# CQLSH invoke
#
TIMEOUT="300"
CQLSH="cqlsh -u ${USR} -p ${PWD} --request-timeout=${TIMEOUT}"
#
# Invoke Repair
#
function doRepair(){
   KSP=$1
   TBL=$2
   STR=$3
   ETR=$4
   nodetool -u ${USR} -pw ${PWD} repair -st ${STR} -et ${ETR} -- ${KSP} ${TBL} 
}
#
# Get Local Tokens
#
function getTokens(){
   for i in $($CQLSH -e "select tokens from system.local;" | awk -F, '/{/{print $0}' | tr -d '{' | tr -d '}' | tr -d ','); do
       echo ${i//\'/}
   done | sort -n
}
#
#
#
function repairByTokenRange(){
   i=0
   STP=256
   KSP=1
   TBL=2
   tokens=($(getTokens))
   while [ ${i} -lt ${#tokens[@]} ]; do
         # Do nothing
         #[ ${i} -eq 0 ]  
         if [ "${tokens[i+1]}" ]; then
            #
            # We are breaking into subranges
            #
            if [ "${STP}" -gt 1 ]; then
               j=0
               range=$(echo "(${tokens[i+1]} - ${tokens[i]})" | bc -l)
               step=$(echo "scale=0; ${range} /${STP}" | bc -l)
               if (( ${range} % ${STP} == 0 )); then
                  subTokens=($(seq ${tokens[i]} ${step} ${tokens[i+1]}))
               else
                  subTokens=($(seq ${tokens[i]} ${step} ${tokens[i+1]}) ${tokens[i+1]})
               fi
               while [ ${j} -lt ${#subTokens[@]} ] && [ "${subTokens[j+1]}" ]; do
                     doRepair ${KSP} ${TBL} ${subTokens[j]} ${subTokens[j+1]}
                     ((j++))
               done
            #
            # We are repaiting the whole range
            #
            else
               doRepair ${KSP} ${TBL} ${tokens[i]} ${tokens[i+1]}
            fi
         fi
         # Do Nothing 
         #[ ! "${tokens[i+1]}" ] 
         ((i++))
   done 
}
#
# Where all comes together
#
main(){
   SCHEMA=$($CQLSH -e "describe schema;")
   echo "Begin processing ..."
   for KSP in $(echo "${SCHEMA}" | awk '/KEYSPACE/ {print $3}'); do
       for TBL in $(echo "${SCHEMA}" | sed -n '/'${KSP}'/,/CREATE KEYSPACE/p' | awk '/CREATE TABLE/ {print $3}'); do
           TBL=${TBL/*./}
           repairByTokenRange ${KSP} ${TBL}
       done
   done    
   echo "End procesing"
}
#
# Execution
#
main
#
# Below is the old way this was implemented
#
# Repair on the primary range will be executed by keyspace.table & token range
# Because it works on the primary range, it needs to be executed on each node of the DC/Cluster
#
# Assumptions:
#
# * Cassandra is running
# * nodetool is available via PATH env var
#
#
# This is the old way
# Not quite removing it yet
#
#SCH=$(echo "describe schema;" | cqlsh)
#for KSP in $(echo "${SCH}" | awk '/KEYSPACE/ {print $3}'); do
#    KSP=${KSP//\"/}
#    for RNG in $(nodetool describering ${KSP} | awk -F: '/TokenRange/ && /start_token/ {print $2, $3}' | awk '{print "-st_"$1"_-et_"$3}'); do
#        RNG=${RNG//_/ }
#        RNG=${RNG//,/}
#        for TBL in $(echo "${SCH}" | sed -n '/'${KSP}'/,/CREATE KEYSPACE/p' | awk '/CREATE TABLE/ {print $3}'); do
#            TBL=${TBL/*./}
#            CMD="nodetool repair ${RNG} -- ${KSP} ${TBL}"
#            printf "INFO: Executing ${CMD} \n"
#            $CMD
#        done
#    done
#done
#
# EOF
