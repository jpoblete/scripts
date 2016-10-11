
#!/bin/bash
########################
# PYTHON CODE BLOCK
########################
#=##!/usr/bin/env python
#=## topthreads.py - takes the top and thread dump output from multidump.sh and produces a
#=## list of the top threads by average CPU consumption including Java thread names
#=## usage: topthreads.py [top file] [thread dump file]
#=## Note : needs python 2.7
#=#import sys
#=#import collections
#=#import re
#=#
#=#topfile = open(sys.argv[1])
#=#dumpfile = open(sys.argv[2])
#=#
#=#regex = re.compile(r'"([^"]*)".*nid=0x([0-9a-f]*)')
#=#thread_names = {}
#=#for line in dumpfile:
#=#    match = regex.match(line)
#=#    if match:
#=#        name, pid = match.groups()
#=#        thread_names[int(pid, 16)] = name
#=#
#=#cpu_use = collections.defaultdict(list)
#=#for line in topfile:
#=#    if line[1:5].isdigit():
#=#        fields=line.split()
#=#        cpu_use[int(fields[0])].append(float(fields[8]))
#=#avg_cpu_use = {pid: sum(list)/len(list) for pid, list in cpu_use.iteritems()}
#=#sorted_cpu_use = sorted(avg_cpu_use.iteritems(), key=lambda x: x[1], reverse=True)
#=#
#=#print 'PID   %CPU  Process'
#=#print '===== ===== ======='
#=#for pid, avg in sorted_cpu_use:
#=#    if avg > 0:
#=#       print '{0:5d} {1:.2f} {2:s}'.format(pid, avg, thread_names.get(pid))
########################
# END OF PYTHON CODE
########################

usage(){
   echo "Usage: $0 -i <interval> -c <count> -pid <PID> -pgm [jstack|kill]"
   echo "       Default interval: 5 secs"
   echo "       Default count   : 60"
   echo "       Default PID     : DSE java PID"
   echo "       Default PGM     : jstack"
   exit 1
}

runPython(){
   awk '/^#=#/{print $0}' $0 | sed -e 's/#=#//g' > /tmp/topThreads.py
   cd /tmp
   chmod +x topThreads.py
   /tmp/topThreads.py top.out jstack.out | tee -a  /tmp/topThreads.out
}

while [ $# -gt 0 ] ; do
        case "$1" in
           -i)   INTERVAL=$2
                 shift 2
                 ;;
           -c)   COUNT=$2
                 shift 2
                 ;;
           -pid) PID=$2
                 shift 2
                 ;;
           -pgm) PGM=$2
                 shift 2
                 ;;
           *)    echo "Unknown option: $1"
                 usage
                 exit 0
                 ;;
        esac
done
#INTERVAL=$1
#COUNT=$2
#PID=$3
#PGM=$4
[ -z "${INTERVAL}" ] && INTERVAL=5
#
[ -z "${COUNT}"    ] && COUNT=60
#
if [ -z ${PID} ]; then
   [ -f /var/run/dse/dse.pid ] && PID=$(cat /var/run/dse/dse.pid)
   [ -z "${PID}" ]             && PID=$(ps -ef | awk '/java/ && !/awk/ && /cassandra/ {print $2}')
   [ -z "${PID}" ]             && echo "Error: Could not determine Cassandra\'s PID, exiting..." && exit 1
else
   if [ "${PID}" != "$(ps -p ${PID} | tail -1 | awk '{print $1}')" ]; then
      echo "Error: Could not find a java PID=${PID}, exiting..."
      exit 1
   fi
fi
#
# We use jstack by default or whatever specified on cmd line
# Also check that jstack is present/executable
#
if [ ! -x "${PGM}" ] then 
   [ "${PGM}" ] && echo "Notice: ${PGM} provided is not executable"
   PGM="jstack"
   if [ "${PGM}" != "kill" ]; then
      if [ -x "$(which jstack)" ]; then
         PGM=$(which jstack)
      else
         PGM="kill"   
         echo "Notice: jstack not found, using kill -3 instead"
      fi
   fi
fi
#
# Check I'm the JVM owner 
#
ME=${USER}
ME_UID=$(id -u ${ME})
C_USER_UID=$(ps -e -o uid,pid,cmd | awk '( $2 == '"${PID}"'){print $1}')
C_USER=$(getent passwd ${C_USER_UID} | cut -d: -f1)
#
# Check we have valid interval/counts
#
( [ -z "${INTERVAL}" ] || [ -z "${COUNT}" ] ) && usage
#
main(){
   if [ "$(echo ${PGM##*\/})" == jstack ]; then
      PGM="${PGM} -l"
   else
      PGM="${PGM} -3"
   fi
   echo "Begin processing..."
   rm -f /tmp/top.out /tmp/jstack.out/ /tmp/topThreads.out
   RUN="true"
   if [ "${RUN}" ]; then
      for i in `seq $COUNT`; do
          echo "stack trace $i of $COUNT"    >> /tmp/jstack.out
          ${PGM} $PID                        >> /tmp/jstack.out
          echo "------------------------"    >> /tmp/jstack.out
          top -bHc -d $INTERVAL -n 1 -p $PID >> /tmp/top.out
          sleep $INTERVAL
      done
   fi
   runPython
   echo ""
   echo "Collecting files..."
   tar czvpf multidump.tgz *.out
   echo "End processing, please collect /tmp/multidump.tgz"
}


if [ "${ME}" != "${C_USER}" ]; then
   sudo su -c "$(echo "$0 $@")" -s /bin/bash ${C_USER}
else
   main
fi
#EOF
