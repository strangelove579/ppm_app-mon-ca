#!/bin/bash
#===================================================================================
#
#         FILE: deploy_config_logmon.sh
#
#        USAGE: ./deploy_config_logmon.sh
#
#  DESCRIPTION: Build and deploy configuration file(s)
#
#      PACKAGE: CLRT_12.1.x_13
#        PROBE: LOGMON
#
#      OPTIONS: NONE
# REQUIREMENTS: <pckg_home>/lib/common.sh
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: John Achee, Principal Developer
#      COMPANY: CA Technologies
#      VERSION: 1.0
#      CREATED: 04.05.2012
#     REVISION: 02
#     05312012 - Mai Le : change AddProfile to process the service and profile found.  Change checking for service
#                         to also looking number of profile in the logfile directory.  Simply add other config in
#                         without updating code
#===================================================================================
#set -xv

debug_enabled="$1"
debug_enabled=${debug_enabled:-"0"}
nms_home="$2"
nms_home=${nms_home:-"/fs0/od/nimsoft"}
package_home="$3"
package_home=${package_home:-"$nms_home/probes/super/ppm_app"}
enable_bg_restart="1"
enable_webi_restart="1"
#=== FUNCTION ================================================================
#        NAME: ExitProgram
# DESCRIPTION: Cleanup temp files and exit with specified exit_status
# PARAMETER 1: exit status
#=============================================================================
ExitProgram() {
    [ -e $tmp_config_file       ] && rm --force $tmp_config_file
    [ -e /tmp/profiles.tmp      ] && rm --force /tmp/profiles.tmp
    UpdateLog "Completed processing of config for probe [logmon]" $log_file 3
    exit ${1:-1}
}
#=== FUNCTION ================================================================
#        NAME: AddProfile
# DESCRIPTION: Add a Profile and one or many embedded watchers
# PARAMETER 1: base_program ()
# PARAMETER 2: Name (used for pcmd in exception configurations, such as bg
#               app and bo)
#=============================================================================
AddProfile() {
    local program=$1
    local profile=$2
    local base_program=`echo $program | sed -e "s/[0-9]//"`
    local watcher="$config_dir_exception/${profile}_watcher_${base_program}.cfg"
	enable=""
    profile_enable=""


#
#  Watcher bind variables
#
PROF_DESC=$(printf "Adding profile %-20.20s type: %s\n" "[$profile]" "[$program]")
UpdateLog "$PROF_DESC" $log_file 3
#    UpdateLog "Adding profile [$profile] type: [$program]" $log_file 3

    cat $watcher >> /tmp/watchers.tmp
    /bin/sed -i "s/@NAME@/$program/" /tmp/watchers.tmp
    /bin/sed -i "s|@DB_FAILOVER_HOST@|$db_failover_host|" /tmp/watchers.tmp
    /bin/sed -i "s|@DB_PRIMARY_HOST@|$db_primary_host|" /tmp/watchers.tmp
    /bin/sed -i "s|@DB_PRIMARY_PORT@|$db_primary_port|g" /tmp/watchers.tmp
    /bin/sed -i "s|@DB_FAILOVER_PORT@|$db_failover_port|g" /tmp/watchers.tmp
    /bin/sed -i "s|@DB_SID@|$dbsid|g" /tmp/watchers.tmp


    if [ "$program" == "bo" ]; then
      if echo "$niku_version" | egrep "^(12.1.1|13|14)" > /dev/null; then
        /bin/sed -i "s|@ENABLE@|yes|" /tmp/watchers.tmp
      else
        /bin/sed -i "s|@ENABLE@|no|" /tmp/watchers.tmp
      fi
    fi


    if [[ "$base_program" == "bg" ]] && ( [[ "$profile" == "oom" ]] || [[ "$profile" == "disc" ]] ); then

      if [ "$enable_bg_restart" == "1" ]  && echo "$niku_version" | egrep "^(12.1.1|1[3-9])" > /dev/null; then
        /bin/sed -i "s/@ACTIVE-NORMAL@/no/" /tmp/watchers.tmp
        /bin/sed -i "s/@ACTIVE-RESTART@/yes/" /tmp/watchers.tmp
      else
        /bin/sed -i "s/@ACTIVE-NORMAL@/yes/" /tmp/watchers.tmp
        /bin/sed -i "s/@ACTIVE-RESTART@/no/" /tmp/watchers.tmp
      fi
    fi


#
#  Profile bind variables
#

    local cfg="$profile"
    /bin/sed -e "/@WATCHER@/r /tmp/watchers.tmp" -e "/@WATCHER@/d" $template_dir/logmon_profile.template >> /tmp/profiles.tmp
      
    bo_status_url="BOServerStatus.jsp"
    url_suffix="monitor.jsp"
    if echo "$niku_version" | egrep "^14.[3-9]|15.[1-9]" > /dev/null; then
	url_suffix="serverstatus/status?run=PE_HEARTBEAT,NJS_HEARTBEAT,LAST_SLICING,IS_ROLLOVER,DB_LOGIN"
	bo_status_url="serverstatus/bostatus"
    fi 
    
    . "$config_dir_exception/${profile}_profile_${base_program}.cfg"
	
    if [ "$profile_enable" == "" ]; then
       profile_enable="yes"
    fi
    /bin/sed -i "s|@PROFILE_ENABLE@|$profile_enable|g" /tmp/profiles.tmp
    /bin/sed -i "s|@URL_SUFFIX@|$url_suffix|g" /tmp/profiles.tmp
    /bin/sed -i "s|@BO_STATUS_URL@|$bo_status_url|g" /tmp/profiles.tmp
    
    /bin/sed -i "s/@INTERVAL@/$interval/g" /tmp/profiles.tmp
    /bin/sed -i "s|@FILENAME@|$filename|g" /tmp/profiles.tmp
    /bin/sed -i "s/@SCANMODE@/$scanmode/g" /tmp/profiles.tmp
    /bin/sed -i "s/@QOS@/$qos/g" /tmp/profiles.tmp
    /bin/sed -i "s/@EXCLUDES@/$excludes/g" /tmp/profiles.tmp
    /bin/sed -i "s/@EMATCH@/$ematch/g" /tmp/profiles.tmp
    /bin/sed -i "s/@PROFILE@/$profile/g" /tmp/profiles.tmp
    /bin/sed -i "s/@NAME@/$program/g" /tmp/profiles.tmp
    /bin/sed -i "s/@ALARM@/$alarm/g" /tmp/profiles.tmp
    /bin/sed -i "s|@PCKG_HOME@|$package_home|g" /tmp/profiles.tmp
    /bin/sed -i "s|@ORACLE_HOME@|$oracle_home|g" /tmp/profiles.tmp
    /bin/sed -i "s|@SCHEDULER_URL@|$schedulerurl|g" /tmp/profiles.tmp
    /bin/sed -i "s|@NSA_URL@|$nsa_url|g" /tmp/profiles.tmp
    /bin/sed -i "s|@DB_FAILOVER_HOST@|$db_failover_host|g" /tmp/profiles.tmp
    /bin/sed -i "s|@DB_PRIMARY_HOST@|$db_primary_host|g" /tmp/profiles.tmp
    /bin/sed -i "s|@DB_PRIMARY_PORT@|$db_primary_port|g" /tmp/profiles.tmp
    /bin/sed -i "s|@DB_FAILOVER_PORT@|$db_failover_port|g" /tmp/profiles.tmp
    /bin/sed -i "s|@DB_SID@|$dbsid|g" /tmp/profiles.tmp


    if [[ "$base_program" == "bg" ]] && ( [[ $cfg == "oom" ]] || [[ $cfg == "disc" ]] ); then
      if [ $enable_bg_restart == "1" ]  && echo $niku_version | egrep "^(12.1.1|1[3-9])" > /dev/null; then
        /bin/sed -i "s/@RUNMODE@/fancy_restart/" /tmp/profiles.tmp
      else
        /bin/sed -i "s/@RUNMODE@/normal/" /tmp/profiles.tmp
      fi
    fi


    echo > /tmp/watchers.tmp

}


#-------------------------------------------------------------------------------
# Import all common libraries
#-------------------------------------------------------------------------------
. "$package_home/lib/common.sh"

probe_home="$nms_home/probes/system/logmon"
template_dir="$package_home/logmon/templates"
config_file="$probe_home/logmon.cfg"
tmp_config_file="/tmp/logmon.cfg"
log_file="$probe_home/logmon.log"
config_dir_generic="$package_home/logmon/config/generic"
config_dir_exception="$package_home/logmon/config/exception"

UpdateLog "Building probe config for: [logmon]" $log_file 3

#-------------------------------------------------------------------------------
# Set default configuration file path, Exit if not found
#-------------------------------------------------------------------------------
default_config="$probe_home/logmon.cfx"
if [ ! -f $default_config ]; then
    UpdateLog "Default configuration file was not found: $default_config. Exiting..." $log_file 1
    ExitProgram 1
fi

#-------------------------------------------------------------------------------
# Check that clarity is installed and the correct version
#-------------------------------------------------------------------------------
GetClarityVersion

if [ $? -ne 0 ]; then
    UpdateLog "Clarity was not found! Exiting..." $log_file 1
    ExitProgram 1
fi

#-------------------------------------------------------------------------------
# Gather clarity properties and settings
#-------------------------------------------------------------------------------
GetClarityProperties $niku_home $debug_enabled       # $niku_home provided by GetClarityVersion, 0 indicates debug_enabled off
# Convert to arrays
app_array=($app_array)
bg_array=($bg_array)
beacon_array=($beacon_array)
#-------------------------------------------------------------------------------
# Provide default config if app and bg are not enabled
#-------------------------------------------------------------------------------
if [ -z "$app_array" ] && [ -z "$bg_array" ] && [ -z "$db_primary_host" ] && [ "$reports_installed" != "yes" ]; then
    UpdateLog "No enabled services found, providing probe with default config..." $log_file 3
    MakeConfigFile $default_config $config_file $log_file $debug_enabled 0 "logmon" $nms_home
    ExitProgram $?
fi





#-------------------------------------------------------------------------------
# Add "header" section to temporary configuration file
#-------------------------------------------------------------------------------
cp -f $template_dir/logmon_header.template $tmp_config_file
. $config_dir_generic/logmon_setup.cfg
/bin/sed -i "s/@LOGSIZE@/$logsize/g" $tmp_config_file
/bin/sed -i "s/@DEBUG@/$cfg_debug/g" $tmp_config_file


echo "" > /tmp/watchers.tmp
echo "" > /tmp/profiles.tmp


# Add app and bg profiles
for program in "${app_array[@]}" "${bg_array[@]}"; do
    if [[ $program == "bg" ]] || [[ $program == "app" ]]; then
       echo "Evaluating instance; $program"
    else
       continue
    fi
    servicetype=`echo $program | sed -e "s/[0-9]//"`
    # Grab profile name based on file name and trim the name to anything before _profile_${servicetype}.cfg
#    profiles=`find $config_dir_exception -type f -name "*profile*${servicetype}.cfg" |cut -d / -f8 |cut -d _ -f1`
   profiles=`find $config_dir_exception -type f -name "*profile*${servicetype}.cfg" |cut -d / -f11 |cut -d _ -f1`
    
    for profile in ${profiles[@]}; do
      if [[ $profile == "disc" ]] && echo $niku_version | egrep "^12.1.0" > /dev/null; then
        continue
      fi
      AddProfile $program $profile  # process each profile 1 at a time
    done
done

# Add beacon profile
for program in "${beacon_array[@]}"; do
    if [[ $program == "beacon" ]]; then
       echo "Evaluating instance; $program"
    else
       continue
    fi
    servicetype=`echo $program | sed -e "s/[0-9]//"`
    # Grab profile name based on file name and trim the name to anything before _profile_${servicetype}.cfg
#    profiles=`find $config_dir_exception -type f -name "*profile*${servicetype}.cfg" |cut -d / -f8 |cut -d _ -f1`
   profiles=`find $config_dir_exception -type f -name "*profile*${servicetype}.cfg" |cut -d / -f11 |cut -d _ -f1`
    
    for profile in ${profiles[@]}; do
      AddProfile $program $profile  # process each profile 1 at a time
    done
done

# Add DB related profiles
if [ "$db_primary_host" != "" ]; then
    AddProfile "db" "tnsping-primary"
fi

if [ "$db_failover_host" != "" ] && [ "$rac_db" != "yes" ]; then
    AddProfile "db" "tnsping-failover"
fi


# Add reports/BO related profiles
if [[ "$reports_installed" == "yes" ]] && [ ! `echo $niku_version  | egrep "^12.1.0"` ]; then
  #profiles=`find $config_dir_exception -type f -name "*profile_bo.cfg" | cut -d / -f8 |cut -d _ -f1`
  profiles=`find $config_dir_exception -type f -name "*profile_bo.cfg" | cut -d / -f11 |cut -d _ -f1`
  for profile in ${profiles[@]}; do
    AddProfile "bo" "$profile"
  done
fi

# Add required profiles
#AddProfile "required" "fs0-iostat"
AddProfile "required" "timezone-changed"
AddProfile "required" "killzombies"



#-------------------------------------------------------------------------------
# Join watchers into temporary config file, and cleanup
#-------------------------------------------------------------------------------
echo "<profiles>"       >> $tmp_config_file
cat /tmp/profiles.tmp   >> $tmp_config_file
echo "</profiles>"      >> $tmp_config_file

rm -f /tmp/profiles.tmp
rm -f /tmp/watchers.tmp

/bin/sed -i "/^$/d" $tmp_config_file            # Clear out any blank lines
#-------------------------------------------------------------------------------
# Compare existing configuration file and new configuration file
#            Replace only if they're different
#-------------------------------------------------------------------------------
#config_file="/home/achjo03/ppm_app/samples/logmon.cfg"
MakeConfigFile $tmp_config_file $config_file $log_file $debug_enabled 1 "logmon" $nms_home


trap ExitProgram SIGHUP SIGINT SIGPIPE SIGTERM


ExitProgram 0

