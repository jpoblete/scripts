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
         if [ "${tokens[i+1]}" ]; then
            #
            # If STP > 1
            # We are breaking into subranges
            # Helps to have an even lower footprint
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
            # Otherwise... STP=1
            # We are repaiting the whole range
            #
            else
               doRepair ${KSP} ${TBL} ${tokens[i]} ${tokens[i+1]}
            fi
         fi
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
#EOF
