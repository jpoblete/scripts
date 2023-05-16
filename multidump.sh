
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
   echo "Usage: $0 -i <interval> -c <count> -pid <PID>"
   echo "       Default interval: 5 secs"
   echo "       Default count   : 60"
   echo "       Default PID     : JVM's PID"
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
           *)    echo "Unknown option: $1"
                 usage
                 exit 0
                 ;;
        esac
done
#
# These are our arguments
#
#INTERVAL=$1
#COUNT=$2
#PID=$3
#PGM=$4
#
# Check we have valid interval/counts
#
[ -z "${INTERVAL}" ] && INTERVAL=5
[ -z "${COUNT}"    ] && COUNT=60
( [ "${INTERVAL}" -le 0 ] || [ -z "${COUNT}" -le 0 ] ) && usage
#
# The PID is used to:
#
# * Verify the PID belongs to a JAVA process
# * Localize JSTACK command 
#
if [ -z "${PID}" ]; then
   echo "ERROR: PID is required but none was provided, exiting..." && exit 1
else
   OWNER=$(ps -o euser fp ${PID} | awk '!/EUSER/ {print $1}')
   JAVA=$(ps -o cmd   fp ${PID}  | awk ' /java/  {print $1}')
   JSTACK=${JAVA%java}jstack
   if [ "${PID}" ] &&  [ -f "${JSTACK}" ]; then
      PGM=${JSTACK}
   else
      echo "ERROR: JSTACK command could not be found, exiting..." && exit 1
   fi
fi
#
# Check who is executing this script
# Find out who is the cassandra user -> JVM owner 
#
ME=${USER}
ME_UID=$(id -u ${ME})
OWNER_UID=$(ps -e -o uid,pid,cmd | awk '( $2 == '"${PID}"'){print $1}')
#
# If this is executed as the OWNER, then continue to main()
# Otherwise, we need to fork as the JVM owner 
#
if [ "${ME}" != "${C_USER}" ] && [ "${ME}" == "root" ]; then
   su -s /bin/bash -c "$(echo "$0 -i ${INTERVAL} -c ${COUNT} -pid ${PID}")" - ${OWNER}
else
   main
fi
#
# This is where the thread dump is executed
#
main(){
   PGM="${PGM} -l"
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
#EOF
