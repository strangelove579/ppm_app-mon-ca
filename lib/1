#!/bin/bash
#===================================================================================
#
#         FILE: common.sh
#
#        USAGE: . common.sh
#
#  DESCRIPTION: Functions common to all deploy_config.sh
#
#      PACKAGE: *
#        PROBE: *
#
#      OPTIONS: NONE
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: John Achee, Principal Developer
#      COMPANY: CA Technologies
#      VERSION: 1.0
#      CREATED: 04.05.2012
#     REVISION: 01.1
#===================================================================================
#=== FUNCTION ================================================================
#        NAME: GetHostname
# DESCRIPTION: Sets the hostname and full_hostname variables based on current
#              config in /etc/sysconfig/network
# PARAMETERS:  none
#=============================================================================
GetHostname() {
    hostname=`grep -i 'hostname' /etc/sysconfig/network | cut -d= -d. -f1 |cut -d= -f2`
    full_hostname=`grep -i 'hostname' /etc/sysconfig/network | cut -d=  -f2`
    if [ "$hostname" = "localhost" ]; then
        hostname=(`hostname | cut -d= -d. -f1`)
    fi
    export hostname
    export full_hostname
}

#=== FUNCTION ================================================================
#        NAME: SetOracleEnv
# DESCRIPTION: If Oracle is installed, standard oracle ENV vars, else
#              set exit status to 1
# PARAMETER 1: none
#=============================================================================
SetOracleEnv() {
    if [ -d "/fs0/oracle" ]; then

        ORACLE_BASE=/fs0/oracle
        ORACLE_HOME=`cat /etc/oratab |head -n1 |cut -f2 -d':'`
        LD_LIBRARY_PATH=$ORACLE_HOME/lib:/lib:/usr/lib:/usr/local/lib:$LD_LIBRARY_PATH
        PATH=$ORACLE_HOME/bin:/usr/local/bin:$PATH
        NLS_LANG=AMERICAN_AMERICA.UTF8
    else
        return 1
    fi
}



#=== FUNCTION ================================================================
#        NAME: Errorfn
# DESCRIPTION: Writes system exception to error log and exits
# PARAMETER 1: Required: Message text
# PARAMETER 2: Required: Log File name
# PARAMETER 3: (Optional) Log Level. Default "3", this prints an INFO msg
#=============================================================================
Errorfn() {
    trap "" ERR
    set +o errexit
    MESSAGE="$1"
    LOGFILE="$2"
    [ "$MESSAGE" == "" ] && MESSAGE="Unknown problem during the installation."
    echo $(date '+%Y-%m-%d %H:%M:%S') " [[ FAILED ]]" $MESSAGE >> $LOGFILE
    echo "$MESSAGE"
    echo "Please check the $LOGFILE for details."
    exit 1
}


#=== FUNCTION ================================================================
#        NAME: UpdateLog
# DESCRIPTION: Writes text to log file, with error level indicator
# PARAMETER 1: Required: Message text
# PARAMETER 2: Required: Log File name
# PARAMETER 3: (Optional) Log Level. Default "3", this prints an INFO msg
#=============================================================================
UpdateLog() {
    LOGMESSAGE="$1"
    LOGFILE="$2"
    if [  -n "$3" -a "$3" -eq "1" ]; then
        LOGTYPE="[[ FAILED ]] "
    elif [ -n "$3" -a  "$3" -eq "2" ]; then
        LOGTYPE="[[ WARNING ]] "
    else
       LOGTYPE="[[ INFO ]] "
    fi
    echo $(date '+%Y-%m-%d %H:%M:%S') " " $LOGTYPE $LOGMESSAGE >> $LOGFILE
    echo $LOGMESSAGE
}


#=== FUNCTION ================================================================
#        NAME: TryPu
# DESCRIPTION: Executes a command (intended to execute PU command)
#              Tries 10 times with 5 second waits
# PARAMETER 1: Required: command to run
#=============================================================================
TryPU () {
  command=$1
  #for i in {1..3}    Per Mais request, we no longer retry pu commands
  #do
    sleep 2
    $command
    [ $? -eq 0 ] && return 0
  #done
  return 1
}

#=== FUNCTION ================================================================
#        NAME: RestartProbe
# DESCRIPTION: Restarts the specified Nimsoft probe
# PARAMETER 1: Required: probe name (name of probe to restart)
# PARAMETER 2: Required: log file name to write log information
# PARAMETER 3: (Optional) NMS_HOME directory. Default: /fs0/od/nimsoft
#=============================================================================
ProbeAction () {
  probe_name=$1
  log_file=$2
  nms_home=$3
  action=$4
  action=${action:-"restart"}
  nms_user="probe_admin"
  nms_passwd="admin01"
  nms_home=${nms_home:-"/fs0/od/nimsoft"}
  pu_cmd="$nms_home/bin/pu -u $nms_user -p $nms_passwd "

# Standard restart steps
  restart_step[0]="$pu_cmd controller probe_deactivate $probe_name"
  restart_step[1]="$pu_cmd controller probe_activate $probe_name"
#  restart_step[2]="$pu_cmd -I $probe_name"

# Commands for when things go south..
  plan_b[0]="$pu_cmd -R $probe_name"
#  plan_b[1]=$restart_step[2]

  pu="cant fail us now!"



# Execute commands based-on the supplied action (activate/deactive/restart)
# One activate command, one deactivate command
  UpdateLog "Performing [$action] of [$probe_name]" $log_file 3
  for cmd in "${restart_step[@]}"
  do
    if [ "$action" == "activate" ] && [[ "$cmd" =~ "probe_deactivate"  ]]; then
      continue
    elif [ "$action" == "deactivate" ] && [[ "$cmd" =~ "probe_activate" ]]; then
      continue
    fi
    TryPU "$cmd"
    [ $? -ne 0 ] && pu="failed us again" && break
  done

# If the above was succesful, log and exit. If failed:
#   1) If action=activate or deactivate, error out
#   2) If action=restart, attempt restart using -R probename args
  if [ ! "$pu" == "failed us again"  ]; then
    UpdateLog "[$action] successful for probe [$probe_name]" $log_file 3
    return 0
  elif [ ! "$action" == "restart" ]; then
    UpdateLog "[$action] FAILED for probe [$probe_name]" $log_file 1
    return 1
  else
    for cmd in "${plan_b[@]}"
    do
      TryPU "$cmd"
      if [ $? -ne 0 ]; then
          UpdateLog "[$action] FAILED for probe [$probe_name]" $log_file 1
          return 1
      fi
      UpdateLog "[$action] successful for probe [$probe_name]" $log_file 3 

    done
  fi

}

#=== FUNCTION ================================================================
#        NAME: GetClarityVersion
# DESCRIPTION: Gets the clarity path, clarity major and full version
#              Populates into $niku_home, $niku_mjr, and $niku_version
#              respectively.
#              Returns exit status = 1 if "/etc/odprofile" doesn't exist or
#              it doesn't define NIKU_HOME variable
#=============================================================================
GetClarityVersion () {
    odprofile="/etc/odprofile"
    if [ -e $odprofile ] && egrep "^(export )?NIKU_HOME=" $odprofile > /dev/null; then
        niku_home=`cat $odprofile | grep 'NIKU_HOME=' | sed -e "s/.*=\(.*\)/\1/"`
#        niku_version=`cat "/tmp/version.properties" | egrep -i "^version=" | cut -d= -f2 | sed -e "s/\r//g"`
	niku_version=`cat "$niku_home/.setup/version.properties" | egrep -i "^version=" | cut -d= -f2 | sed -e "s/\r//g"`
#	niku_version=`cat "/home/achjo03/ppm_app/samples/version.properties" | egrep -i "^version=" | cut -d= -f2 | sed -e "s/\r//g"`
        niku_mjr=`echo $niku_version | /usr/bin/perl -ne "print m/^([0-9]+)/"`
    else
        return 1                                     # Clarity not found
    fi
}


#=== FUNCTION ================================================================
#        NAME: GetClarityProperties
# DESCRIPTION: Exports clarity specific variables, with values from
#              hosts.xml, properties.xml
# PARAMETER 1: (REQUIRED) NIKU_HOME:  (path to the base directory of Clarity
#                                      application)
# PARAMETER 2: (OPTIONAL) DEBUG: default 0, if 1 then variables will be echoed
#              to stdout
#=============================================================================
GetClarityProperties () {

    niku_home=$1
    niku_pfile="$niku_home/config/properties.xml"
    #niku_pfile="/home/achjo03/ppm_app/samples/properties.xml"
    niku_host_file="$niku_home/config/hosts.xml"
    #niku_host_file="/home/achjo03/ppm_app/samples/hosts.xml"
    #debug=$2
    #debug=${debug:-0}
    debug="0"
    
    GetHostname

    oracle_base=`cat /etc/odprofile | egrep -i "^(export )?oracle_base" | sed -e 's|^.*ORACLE_BASE=\(.*\)$|\1|'`
    oracle_home=`cat /etc/odprofile | egrep -i "^(export )?oracle_home" | sed -e 's|^.*ORACLE_HOME=\(.*\)$|\1|' | sed 's|\$ORACLE_BASE|'"$oracle_base"'|'`

    # enabled services...

    bg_array=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /id="(bg[^"]*)/msi; print "$out " if (/\sid="bg/msi && /\sservicetype="bg"/msi && /\sactive="true"/msi)}' $niku_host_file`
    app_array=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /id="(app[^"]*)/msi; print "$out " if (/\sid="app/msi && /\sservicetype="app"/msi && /\sactive="true"/msi )}' $niku_host_file`

    beacon_array=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /id="(beacon[^"]*)/msi; print "$out " if (/\sid="beacon/msi && /\sservicetype="beacon"/msi && /\sactive="true"/msi )}' $niku_host_file`
    bo_hostname=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /\svolumename="([^:"]*)/msi; print $out if m|<reportserver.*?sc.commonreporting|msi}' $niku_pfile`
    bo_port=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /\svolumename=".*?:([^"]*)/msi; print $out if m|<reportserver.*?sc.commonreporting|msi}' $niku_pfile`
    export bo_volumename="$bo_hostname:$bo_port"
    export bo_user=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /\susername="([^"]*)/msi; print $out if m|<reportserver.*?sc.commonreporting|msi}' $niku_pfile`
    export bo_pass=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /\spassword="([^"]*)/msi; print $out if m|<reportserver.*?sc.commonreporting|msi}' $niku_pfile`
    hostname=`echo $hostname | tr [:upper:] [:lower:]`
    bo_hostname=`echo $bo_hostname | tr [:upper:] [:lower:]`
    reports_url=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /\sweburl="([^"]*)/msi; print $out  if (m/<reportserver.*?sc.commonreporting/msi)}' $niku_pfile`
    if [ "${reports_url: -1:1}" == "/" ]; then
      reports_url="${reports_url:0:${#reports_url}-1}"
    fi
    if [ "$bo_hostname" == "localhost" ] || [ "$bo_hostname" == "$hostname" ]; then
        reports_installed="yes"
        rpts="Clarity_BO"
    else
        reports_installed="no"
    fi

    enabled_services=`perl -nle 'print $1  if /id="([^"]*)".*?active="true"/i' $niku_host_file`


    # database...
    dbschema=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /\sschemaname="([^"]*)/msi; print $out  if (m/<database.*?\sid="niku".*/msi)}' $niku_pfile`
    dbsid=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /;sid=([^\;]*)\;/msi; print $out if (/<database.*?\sid="niku".*/msi)}' $niku_pfile`
    dbhostname=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /jdbc:clarity:oracle:\/\/([^:]*):/msi; print $out if (/<database.*? id="niku".*/msi)}' $niku_pfile`
    db_primary_host="$dbhostname"
    db_failover_host=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /alternateservers=[\(]?([^:]*):/msi; print $out if (/<database.*? id="niku".*/msi)}' $niku_pfile`
    db_primary_port=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /jdbc:clarity:oracle:.*?:(\d{4});/msi; print $out if (/<database.*? id="niku".*/msi)}' $niku_pfile`
    db_failover_port=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /alternateservers=.*?:(\d{4})/msi; print $out if (/<database.*? id="niku".*/msi)}' $niku_pfile`
    if [ "$dbsid" == "" ]
    then
      dbsid=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /\sserviceId="([^"]+)"/ms; print $out if (/<database.*?\sid="niku".*/msi)}' $niku_pfile`
    fi

    # nsa 
    nsa_enabled=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = /\sid="nsa"/msi && /\sactive="true"/msi ? 1 : $out}  print $out' $niku_host_file`
    
    # nsa / reports url
    export nsa_url=`echo "http://${bo_hostname}:8090" | tr [:upper:] [:lower:]`
     
    tz_changed=`perl /fs0/od/nimsoft/probes/super/ppm_app/bin/timezone.pl compare`
    tz_old=`perl /fs0/od/nimsoft/probes/super/ppm_app/bin/timezone.pl get_stored_tz`
    tz_new=`perl /fs0/od/nimsoft/probes/super/ppm_app/bin/timezone.pl get_tz`

    non_ssl_ports=()
    ssl_ports=()
    sso_status_array=()
    use_webagent="false"

    for app in ${app_array[@]}; do
        export app

       nport=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /\sport="([^"]*)/msi; print $out if /<webserverinstance.*?\sid="$ENV{app}".*/msi}' $niku_pfile`
       sport=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /\ssslport="([^"]*)/msi; print $out if /<webserverinstance.*?\sid="$ENV{app}"/msi}' $niku_pfile`
       sso_status=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /\susesso="([^"]*)/msi; print $out if /<applicationserverinstance.*?\sid="$ENV{app}"/msi}' $niku_pfile`

        non_ssl_ports+=("$app:$nport")
        ssl_ports+=("$app:$sport")
        sso_status_array+=("$app:$sso_status")
        if [ "$sso_status" == "true" ]; then
            use_webagent="true"
        fi
    done

    export schedulerurl=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /\sschedulerurl="([^"]*)/msi; print $out if /<webserver\s.*/msi}' $niku_pfile`

    if [ $debug == 1 ]; then

        for app in "${non_ssl_ports[@]}"; do
            key="${app%%:*}"
            val="${app##*:}"
            echo "Non-SSL Port: $key - $val"
        done

        for app in "${ssl_ports[@]}"; do
            key="${app%%:*}"
            val="${app##*:}"
            echo "SSL Port: $key - $val"
        done

        for app in "${sso_status_array[@]}"; do
            key="${app%%:*}"
            val="${app##*:}"
            echo "SSO Status: $key - $val"
        done
    fi



    # ssl status...
    ssl_enabled=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /enablesslport="([^"]*)/msi; print "$out " if /\sid="app.*?"/msi}' $niku_pfile`

    # use webagent (if sso is enabled on any app service, this will return true)
    export sso_status_array
    # log directory...

    log_path=`perl -e '@l=<>; chomp @l; $_ = join / /, @l; @clean = split /\/\>/; foreach (@clean) {$out = $1 if /alternatedirectory="([^"]*)/msi; print $out if /<logger\s+/msi}' $niku_pfile`
    : ${log_path:="$niku_home/log"}
    if [ $debug == 1 ]; then
        echo -e "app_array:  $app_array \nbg_array:  $bg_array \nrpts:  $rpts \nenabled services:  $enabled_services"
        echo -e "dbschema:  $dbschema \ndbsid:  $dbsid \ndbhostname:  $dbhostname"
        echo -e "\nbo_hostname:  $bo_hostname \nlog_path:  $log_path \nscheduler_url: $schedulerurl"
    fi
}


#=== FUNCTION ================================================================
#        NAME: GetClarityDBTimeDiff
# DESCRIPTION: Captures the time offset between the application server
#              (local environment) and the Clarity database server.
#              Returns timediff or -99 if $ORACLE_HOME is not set
# PARAMETER 1: REQUIRED: SID - oracle database sid
#=============================================================================
GetClarityDBTimeDiff () {
    odprofile="/etc/odprofile"
    . $odprofile

    dbuser="monitor"
    dbpwd="M0n1torm3256"
    dbsid=$1
    log_file=$2
    local_time=`date +'%d-%m-%Y %H:%M:%S'`
    #dbuser="system"
    #dbpwd="oracle"
    #dbsid="orcl"
    dbtimediff=`sqlplus -S $dbuser/$dbpwd@$dbsid << EOF
        SET HEADING OFF ECHO OFF VERIFY OFF
	select ROUND((to_date('$local_time','DD-MM-YYYY HH24:MI:SS')
	- sysdate) *24*60,0) from dual;
EOF`

      if [[ `echo "$dbtimediff" | grep "^ERROR*"` ]]; then
	dbtimediff="0"  # EMC RAC issue  so we just going to assume dbtimediff is 0
      fi
}


#=== FUNCTION ================================================================
#        NAME: Deploy Resource File
# DESCRIPTION: Copy resource files (<pckg>/res/files) to target locations and assign appropriate
#              groups and file permissions as defined in res config
#=============================================================================

#=== FUNCTION ================================================================
#        NAME: MakeConfigFile
# DESCRIPTION: Back-up config file and replace with new file and restart probe
# PARAMETER 1: New config file (absolute path)
# PARAMETER 2: Current config file (absolute path)
# PARAMETER 3: Log file (absolute path)
# PARAMETER 4: Debug (0=off, 1=on)
# PARAMETER 5: CopyMode (0=copy file into place, 1=move file into place)
# PARAMETER 6: Probe name (for restart routine)
# PARAMETER 7: NMS HOME - passed to probe restart routine
#=============================================================================
MakeConfigFile() {
  new_config_file=$1
  original_config_file=$2
  log_file=$3
  debug=1
  copy_mode=$5
  probe=$6
  nms_home=$7

# First, make sure what we're being given is valid...
  if [ ! -f $new_config_file ]; then
    UpdateLog "The new config file wasn't found...cant create a config file from thin air...Exiting.." $log_file 1
    exit 1
  fi

# If we already had a config file, was it any different than this
# new one?
  if [ -f $original_config_file ]; then
    cmp -s $original_config_file $new_config_file > /dev/null
    if [ $? -eq 0 ]; then
      if [ "$debug" -eq 1 ]; then
        UpdateLog "Probe config generated for [$probe] matches the current installed config. No change required. Not deploying" $log_file 3
      fi
      rm -f $new_config_file
      exit 0
    fi
  fi

# Back up the original
  if [ -f $original_config_file ]; then
    cp -f ${original_config_file} ${original_config_file}\.old
  fi

# And copy in the new
  if [ $copy_mode -eq 0 ]; then
    cp -f $new_config_file $original_config_file
    rm -f $new_config_file
  else
    mv -f $new_config_file $original_config_file
  fi

# If the copy didn't work, then bomb out
  if [ ! $? -eq 0 ]; then
    UpdateLog "Could not install probe config" $log_file 1
    exit 1
  elif [ "$debug" -eq 1 ]; then
    UpdateLog "Probe config installed successfully" $log_file 3
  fi

# If we got here, then we need to restart the probe
  ProbeAction $probe $log_file $nms_home
}
