#!/bin/bash
#===================================================================================
#
#         FILE: deploy_config_processes.sh
#
#        USAGE: ./deploy_config_processes.sh
#
#  DESCRIPTION: Build and deploy configuration file(s)
#
#      PACKAGE: CLRT_12.1.x_13
#        PROBE: PROCESSES
#
#      OPTIONS: NONE
# REQUIREMENTS: <pckg_home>/lib/common.sh
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: John Achee, Principal Developer
#      COMPANY: CA Technologies
#      VERSION: 1.0
#      CREATED: 04.05.2012
#     REVISION: 01
#===================================================================================

debug_enabled="$1"
debug_enabled=${debug_enabled:-"0"}
nms_home="$2"
nms_home=${nms_home:-"/fs0/od/nimsoft"}
package_home="$3"
package_home=${package_home:-"$nms_home/probes/super/ppm_app"}
#=== FUNCTION ================================================================
#        NAME: ExitProgram
# DESCRIPTION: Cleanup temp files and exit with specified exit_status
# PARAMETER 1: exit status
#=============================================================================
ExitProgram() {
    [ -e $tmp_config_file       ] && rm --force $tmp_config_file
    [ -e /tmp/watchers.tmp      ] && rm --force /tmp/watchers.tmp
    exit ${1:-1}
}
#=== FUNCTION ================================================================
#        NAME: AddWatcher
# DESCRIPTION: Add a watcher to /tmp/watcher, and populate its bind variables
# PARAMETER 1: Watcher Name
# PARAMETER 2: Name (used for pcmd in exception configurations, such as bg
#               app and bo)
#=============================================================================
AddWatcher() {
    local watcher=$1
    local name=$2    # Needed for exception cases, for generic configs supply
                      #  watcher name to both parameters
    local svc="$3"
    
    cat $template_dir/processes_watcher.template >> /tmp/watchers.tmp

    if [ "$svc" == "" ]; then
        /bin/sed -i "s/@PCMD@/$pcmd/g" /tmp/watchers.tmp
    else
       /bin/sed -i "s/@PCMD@/$svc/g" /tmp/watchers.tmp
    fi
    /bin/sed -i "s/@WATCHER@/$watcher/g" /tmp/watchers.tmp
    /bin/sed -i "s/@REPORT@/$report/g" /tmp/watchers.tmp
    /bin/sed -i "s/@SUBSYSTEM@/$subsystem/g" /tmp/watchers.tmp
    /bin/sed -i "s/@PROCESS@/$process/g" /tmp/watchers.tmp
    /bin/sed -i "s/@SCHEDULE@/$schedule/g" /tmp/watchers.tmp
    /bin/sed -i "s/@NAME@/$name/g" /tmp/watchers.tmp    
}

#-------------------------------------------------------------------------------
# Import all common libraries
#-------------------------------------------------------------------------------
. "$package_home/lib/common.sh"


probe_home="$nms_home/probes/system/processes"
template_dir="$package_home/processes/templates"
config_file="$probe_home/processes.cfg"
tmp_config_file="/tmp/processes.cfg"
log_file="$probe_home/processes.log"
config_dir_generic="$package_home/processes/config/generic"
config_dir_exception="$package_home/processes/config/exception"

#-------------------------------------------------------------------------------
# Set default configuration file path, Exit if not found
#-------------------------------------------------------------------------------
default_config="$probe_home/processes.cfx"
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


if [[ "$reports_installed" != "yes" ]]; then 
    rm -f "$package_home/config/.boss_unverified"
fi

#-------------------------------------------------------------------------------
# Provide default config if app and reports is not enabled
#-------------------------------------------------------------------------------
if [ -z "$app_array" ] && [ "$reports_installed" == "no" ] && [ -z "$bg_array" ]; then
    UpdateLog "App, BG, and Reports are not enabled, providing probe with default config..." $log_file 3
    MakeConfigFile $default_config $config_file $log_file $debug_enabled 0 "processes" $nms_home
    ExitProgram 0
fi

#-------------------------------------------------------------------------------
# Add "schedules" section to temporary configuration file
#-------------------------------------------------------------------------------
cp -f $template_dir/processes_schedule.template $tmp_config_file

#-------------------------------------------------------------------------------
# Add "header" section to temporary configuration file
#-------------------------------------------------------------------------------
cat $template_dir/processes_header.template >> $tmp_config_file

#-------------------------------------------------------------------------------
# Build list of watcher definition files, exclude the Sample
#-------------------------------------------------------------------------------
exception_watcher_definitions=(`find $config_dir_exception -type f -name "*watcher*.cfg" -not -name "Sample*"`)

echo "" > /tmp/watchers.tmp


# Exceptions (app,bg,bo)
for definition in "${exception_watcher_definitions[@]}"; do
    . $definition
    if [[ "$watcher" == "PPM app process"  &&  ! -z "$app_array" ]]; then
        for (( i=0;i<${#app_array[@]};i++ )); do
            if [ ${app_array[i]} != "" ]; then
            AddWatcher "PPM ${app_array[i]}" ${app_array[i]}
            fi
        done

    elif [[ "$watcher" == "PPM BG process"  &&  ! -z "$bg_array" ]]; then
        for (( i=0;i<${#bg_array[@]};i++ )); do
            if [ ${bg_array[i]} != "" ]; then
            AddWatcher "PPM ${bg_array[i]}" ${bg_array[i]}
           fi
        done

    elif [[ "$watcher" == "PPM webagent process" &&  "$use_webagent" == "true" ]]; then
        AddWatcher "PPM webagent" "wa"
    
    elif [[ "$reports_installed" == "yes" ]]; then
     
        if [[ "$watcher" == "PPM nsa process" ]]; then 
            #AddWatcher "PPM nsa" "nsa"
            echo

        elif [[ "$watcher" == "PPM BO process"  ]]; then
            #$package_home/bin/bojsp_svc_query.pl "$nsa_url"
          
            $package_home/bin/bojsp_svc_query.pl "$schedulerurl"
        
            for svc in `cat $package_home/config/.live_bo_processes.cfg`; do
                svcname=`echo \'$svc\' | perl -pe 's/^.*?\.([^.]+)\..*?\$/\$1/'`
                AddWatcher "PPM $svcname" "$svcname" "$svc"

            done
        fi
    fi
done

# Generic configs
for definition in "${generic_watcher_definitions[@]}"; do
    . $definition
    AddWatcher "$watcher" "$watcher"
done

#-------------------------------------------------------------------------------
# Join watchers into temporary config file, and cleanup
#-------------------------------------------------------------------------------
echo "<watchers>"       >> $tmp_config_file
cat /tmp/watchers.tmp   >> $tmp_config_file
echo "</watchers>"      >> $tmp_config_file

rm -f /tmp/watchers.tmp

/bin/sed -i "/^$/d" $tmp_config_file            # Clear out any blank lines

#-------------------------------------------------------------------------------
# Compare existing configuration file and new configuration file
#            Replace only if they're different
#-------------------------------------------------------------------------------
#config_file="/home/achjo03/ppm_app/samples/processes.cfg"
MakeConfigFile $tmp_config_file $config_file $log_file $debug_enabled 1 "processes" $nms_home

trap ExitProgram SIGHUP SIGINT SIGPIPE SIGTERM


ExitProgram 0

