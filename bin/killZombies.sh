#!/bin/ksh

INSTALL_DIR=/fs0/clarity1/clarity
PCKG_DIR=/fs0/od/nimsoft/probes/super/ppm_app
PCKG_LOG=$PCKG_DIR/log/killzombies.log
TMP_LOG=${PCKG_LOG}.tmp
TS=""

upd_ts() {
  TS=`date '+%m/%d/%Y %R'`
}


# Approach:
#
# Check the hosts.xml file to see which services should be active.  Based on those, check to see if there are
# existing .pid files
#
# For services that don't have a .pid file, any running instance is considered a zombie and should be killed.
# For services that do have a .pid file, use 'ps' and find the service PIDs that aren't related to the .pid (wrapper PID)
# that we have recorded for this service. 

# gather a list of active services for this host

#-------------------------------------------------------------------------------------------------------------------
# Modified for automated killing through Nimsoft monitoring
# Package: clr_12_13
# Author: achjo03
# 4/29/2013
#
# Converted to Korn shell Associate Array support missing in bash 3.x
# Generate aggregates by service and kill count

# Ghetto log rotation
if [ -r $PCKG_LOG ]; then
  tail -1000 $PCKG_LOG > $TMP_LOG
  mv $TMP_LOG $PCKG_LOG
fi


typeset -A zp  # zombies killed per service
parentsum=0    # sum of parents killed


for service in `grep "active=\"true\"" $INSTALL_DIR/config/hosts.xml | awk '{print $2}' | awk -F\" '{print $2}'`
do

  # determine if this service is supposed to be running
  PIDFILE=$INSTALL_DIR/bin/${service}.pid
  if [ ! -f $PIDFILE ]; then
    PIDFILE=$INSTALL_DIR/config/${service}.pid
  fi
  if [ ! -f $PIDFILE ]; then
    WRAPPER_PID=-1
  else
    WRAPPER_PID=`cat $PIDFILE`
  fi

  # If there's no wrapper, all instances of this service are targets for a bullet to the brain
  if [ "$WRAPPER_PID" == -1 ]; then

    # Check for a zombie here
    PIDCOUNT=`ps -ef | grep "serviceId=${service}@" | grep -v grep | wc -l`
    if [ "$PIDCOUNT" != 0 ]; then
      PID=`ps -ef | grep "serviceId=${service}@" | grep -v grep | awk '{print $2}'`
      PARENT_PID=`ps -ef | grep "serviceId=${service}@" | grep -v grep | awk '{print $3}'`

      # Get your gun
      if [ "$PARENT_PID" != 1 ]; then
        echo "killing $PARENT_PID ($service wrapper)"
        kill -9 $PARENT_PID
        parentsum=$((parentsum+1))

      fi
      echo "killing $PID ($service)"
      kill -9 $PID
      zp[$service]=$((zp[$service]]+1))

    fi

    
  else

    # Otherwise, we need to take care to only get the zombies.
    WRAPPER_PID=`cat $PIDFILE`

    # Find any PIDs for this service that are NOT linked to this parent PID
    for badpid in `ps -ef | grep "serviceId=${service}@" | grep -v grep | grep -v $WRAPPER_PID | awk '{print $2}'`
    do

      # See if it has a parent.. some zombie services have a legitimate wrapper proc
      PARENT=`ps -ef | grep $badpid | grep -v grep | awk '{print $3}'`
      if [ "$PARENT" != 1 ]; then
        echo "killing $PARENT ($service wrapper)"
        kill -9 $PARENT
        parentsum=$((parentsum+1))

      fi
      echo "killing $badpid ($service)"
      kill -9 $badpid
      zp[$service]=$((zp[$service]]+1))

    done
  fi
done



# Message part for killed zombies
for i in "${!zp[@]}"
do
  svc=$i
  count=${zp[$i]}
  es=""
  [ $count -eq 0 ] && continue
  [ $count -gt 1 ] && es="es"
  if [ "$msg" == "" ]
  then
    msg="ZOMBIES Killed: Found and killed $count $svc zombie process${es}"
  else
    msg="$msg, $count $svc process${es}"
  fi
done

# Get sum of parents killed
es=""
[ $parentsum  -gt 1 ] && es="es"
[ $parentsum  -gt 0 ] && msg="$msg, and ${parentsum} zombie parent process${es}"



# print message for logmon

upd_ts

if [ "$msg" != "" ]; then
  echo $msg 
  echo "[$TS] $msg" >> $PCKG_LOG
else
  echo "[$TS] No zombies found" >> $PCKG_LOG
fi
exit 0

