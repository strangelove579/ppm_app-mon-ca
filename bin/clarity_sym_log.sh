#!/bin/bash
# Author 		|	Created Date |   File Name 			|	Modified Date
# Mahesh Marri	|	2015-NOV-01	 |   clarity_sym_log.sh	|   2015-NOV-02
#  
# Create symlink for latest app-access log file 
# Handled scenario to check logfile presence.if not found we will raise an alarm

CLARITY_LOG_FOLDER="/fs0/clarity1/clarity/logs"
LINK=/fs0/od/nimsoft/probes/super/ppm_app/log/app-access-symlink.log
cd $CLARITY_LOG_FOLDER
THE_LOG=`ls -lt app-access-*log | head -1|awk '{print $9}'`

# Check if symlink pointing to the right file
if [ ! -f "$LINK" ] || [ ! "$(readlink $LINK)" = "$THE_LOG" ]; then
# point symlink to the right file:
          rm -f "$LINK"
          ln -s "$CLARITY_LOG_FOLDER/$THE_LOG" "$LINK"
          echo "Created link: $LINK pointing to $THE_LOG"
fi

exit 0
