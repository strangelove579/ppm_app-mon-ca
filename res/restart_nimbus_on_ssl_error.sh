#!/bin/bash
##################################################################################
#
# Written by syeno01
#
# Purpose: read the last two lines of controller.log and if "accept failed" is found then restart the nimbus service 
############################################################

#The max number of attempts to restart
maxAttempts=2;

#wait between checking controller logs
sleepCheckControllerLog=180

#wait between attempts trying to restart multiple times
sleepBetweenAttempts=300

#after this sleep time the attempts are reset to 0
sleepResetAttempts=1800

#current attempts
attempts=0;

#previous restart time
pTime=0

while true
do

# while there are attempts remaining to try and restart

  while [ "$attempts" -le "$maxAttempts" ];
  do
  
#check if the last line in the controller.log contains accept failed or SSL_accept
    tail -1 /fs0/od/nimsoft/robot/controller.log | egrep -wi 'accept failed|SSL_accept error' 1>&2 2>/dev/null
   
    if [[ $? -eq 0 ]]; then
      let attempts=attempts+1;
  
#currentTime - previousTime is more than half an hour then it is eligible for restart with attempts
      cTime=`date +%s`
      timeDiff=$((cTime - pTime))
  
      if [[ $timeDiff -ge $sleepResetAttempts ]]; then
  
        pTime=`date +%s`
        attempts=0;
        echo "service nimbus restart at `date`" >> /var/log/restart_nimbus_ssl_error.log
        /etc/rc.d/init.d/nimbus restart
  
      fi
    fi

#sleep between attempts
    sleep $sleepBetweenAttempts;

  done

#sleep while checking the log file
  sleep $sleepCheckControllerLog;
done
