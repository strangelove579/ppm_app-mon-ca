#!/bin/bash
#===================================================================================
#
#         FILE: deploy_config_jdbc_response.sh
#
#        USAGE: ./deploy_config_jdbc_response.sh
#
#  DESCRIPTION: Build and deploy configuration file(s)
#
#      PACKAGE: CLRT_12.1.x_13
#        PROBE: JDBC_RESPONSE
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


debug_enabled="$1"                                             # Change debug_enabled =1 to turn on debug_enabled
debug_enabled=${debug_enabled:-"0"}
nms_home="$2"
nms_home=${nms_home:-"/fs0/od/nimsoft"}
package_home="$3"
package_home=${package_home:-"$nms_home/probes/super/clrt_12_1_x_13"}

#=== FUNCTION ================================================================
#        NAME: ExitProgram
# DESCRIPTION: Cleanup temp files and exit with specified exit_status
# PARAMETER 1: exit status
#=============================================================================
ExitProgram() {
    [ -e $tmp_config_file      ] && rm --force $tmp_config_file
    [ -e /tmp/profile.tmp      ] && rm --force /tmp/profile.tmp
    [ -e /tmp/connection.tmp   ] && rm --force /tmp/connection.tmp
    exit ${1:-1}
}
program_name=$(basename $0)

#-------------------------------------------------------------------------------
# Import all common libraries
#-------------------------------------------------------------------------------
. $package_home/lib/common.sh

probe_home="$nms_home/probes/database/jdbc_response"
template_dir="$package_home/jdbc_response/templates"
config_file="$probe_home/jdbc_response.cfg"
setup_template="$template_dir/jdbc_response_setup.template"
tmp_config_file="/tmp/jdbc_response.cfg"
log_file="$probe_home/jdbc_response.log"
config_dir="$package_home/jdbc_response/config/generic"

UpdateLog "Building probe config for: [jdbc_response]" $log_file 3

#-------------------------------------------------------------------------------
# Set default configuration file path, Exit if not found
#-------------------------------------------------------------------------------
default_config="$package_home/jdbc_response/config/default/jdbc_response.cfg"
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

GetClarityProperties $niku_home $debug_enabled       # $niku_home provided by GetClarityVersion, 0 indicates debug_enabled off

#-------------------------------------------------------------------------------
# Provide default config if bg is not enabled
#-------------------------------------------------------------------------------
if [ -z "$bg_array" ]; then
    UpdateLog "BG is not enabled, providing probe with default config..." $log_file 3
    MakeConfigFile $default_config $config_file $log_file $debug_enabled 0 "jdbc_response" $nms_home
    ExitProgram 0
else 
    UpdateLog "Clarity bg found enabled, monitoring is required" $log_file 3
fi

#-------------------------------------------------------------------------------
# Get the time difference between local machine and database
#-------------------------------------------------------------------------------
GetClarityDBTimeDiff $dbsid $log_file       # $dbsid provided by GetClarityProperties
if [ -z "$dbtimediff" ]; then
    UpdateLog "Failed to capture App and DB time difference. Exiting..." $log_file 1
    ExitProgram 1
fi

#-------------------------------------------------------------------------------
# Add "setup" section to temporary configuration file
#-------------------------------------------------------------------------------
setup_definition="$config_dir/jdbc_response_setup.cfg"

if [ ! -f $setup_definition ]; then
    UpdateLog "Setup file has not been provided. Exiting..." $log_file 1
    ExitProgram 1
fi

. $setup_definition
cp -f $setup_template $tmp_config_file


/bin/sed -i "s/@LOG_LEVEL@/$log_level/g" $tmp_config_file
/bin/sed -i "s/@REPORT_LEVEL@/$report_level/g" $tmp_config_file  
/bin/sed -i "s/@INTERVAL@/$interval/g" $tmp_config_file
/bin/sed -i "s/@HEARTBEAT@/$heartbeat/g" $tmp_config_file  
/bin/sed -i "s/@CONNECTION_ERROR@/$connection_error/g" $tmp_config_file
/bin/sed -i "s/@MAX_ERRORS@/$max_errors/g" $tmp_config_file  
/bin/sed -i "s/@COMM_TIMEOUT@/$comm_timeout/g" $tmp_config_file

echo "" > /tmp/connection.tmp
echo "" > /tmp/profile.tmp

#-------------------------------------------------------------------------------
# Build list of connection definition files, exclude the Sample
#-------------------------------------------------------------------------------
connection_definitions=(`find $config_dir -type f -name "*conn.cfg" -not -name "Sample*"`)
#-------------------------------------------------------------------------------
# Populate temporary connections file
#-------------------------------------------------------------------------------
for connection in "${connection_definitions[@]}"; do
    . $connection
    
    cat $template_dir/jdbc_response_connection.template >> /tmp/connection.tmp
    
    jdbcurl="jdbc:oracle:thin:@$dbhostname:$db_primary_port:$dbsid"
    /bin/sed -i "s|@DBSID@|$dbsid|g" /tmp/connection.tmp
    /bin/sed -i "s|@JDBC_URL@|$jdbcurl|g"    /tmp/connection.tmp
    /bin/sed -i "s/@ERROR_SEVERITY@/$error_severity/g"    /tmp/connection.tmp
    /bin/sed -i "s/@TIMEOUT@/$timeout/g"    /tmp/connection.tmp
done

#-------------------------------------------------------------------------------
# Build list of profile definition files, exclude the Sample
#-------------------------------------------------------------------------------
profile_definitions=(`find $config_dir -type f -name "*profile.cfg" -not -name "Sample*"`)

#-------------------------------------------------------------------------------
# Populate temporary profiles file
#-------------------------------------------------------------------------------
for profile in "${profile_definitions[@]}"; do
    . $profile
    comparison=${comparison:-"numeric"}
    cat $template_dir/jdbc_response_profile.template >> /tmp/profile.tmp
    /bin/sed -i "s/@NAME@/$name/g" /tmp/profile.tmp
    /bin/sed -i "s/@DBSID@/$dbsid/g" /tmp/profile.tmp    
    /bin/sed -i "s/@CONNECTION@/$name/g" /tmp/profile.tmp
    /bin/sed -i "s/@INTERVAL@/$interval/g" /tmp/profile.tmp
    /bin/sed -i "s/@TIMEOUT@/$timeout/g" /tmp/profile.tmp
    /bin/sed -i "s|@QUERY@|$query|g" /tmp/profile.tmp
    dbtimediff=`echo $dbtimediff | sed '/^$/d'`
    /bin/sed -i "s/@DBTIMEDIFF@/$dbtimediff/g" /tmp/profile.tmp
    /bin/sed -i "s/@DBSCHEMA@/$dbschema/g" /tmp/profile.tmp
    /bin/sed -i "s/@QOS@/$qos/g" /tmp/profile.tmp
    /bin/sed -i "s/@COMPARISON@/$comparison/g" /tmp/profile.tmp
    /bin/sed -i "s/@LOW_THRESHOLD@/$low_threshold/g" /tmp/profile.tmp
    /bin/sed -i "s/@HIGH_THRESHOLD@/$high_threshold/g" /tmp/profile.tmp
    /bin/sed -i "s/@LOW_CONDITION@/$low_condition/g" /tmp/profile.tmp
    /bin/sed -i "s/@HIGH_CONDITION@/$high_condition/g" /tmp/profile.tmp
    /bin/sed -i "s/@LOW_SEVERITY@/$low_severity/g" /tmp/profile.tmp
    /bin/sed -i "s/@HIGH_SEVERITY@/$high_severity/g" /tmp/profile.tmp
    /bin/sed -i "s/@COLUMN@/$column/g" /tmp/profile.tmp
    /bin/sed -i "s/@SUBSYSTEM@/$subsystem/g"    /tmp/profile.tmp
    /bin/sed -i "s/@HOSTNAME@/$hostname/g" /tmp/profile.tmp
done

#-------------------------------------------------------------------------------
# Join connections and profiles into temporary config file, and cleanup
#-------------------------------------------------------------------------------
echo "<connections>"    >> $tmp_config_file 
cat /tmp/connection.tmp >> $tmp_config_file
echo "</connections>"   >> $tmp_config_file
echo "<profiles>"       >> $tmp_config_file
cat /tmp/profile.tmp    >> $tmp_config_file
echo "</profiles>"      >> $tmp_config_file
/bin/sed -i "/^$/d" $tmp_config_file            # Clear out any blank lines

rm -f /tmp/connection.tmp /tmp/profile.tmp




#-------------------------------------------------------------------------------
# Compare existing configuration file and new configuration file
#            Replace only if they're different
#-------------------------------------------------------------------------------

MakeConfigFile $tmp_config_file $config_file $log_file $debug_enabled 1 "jdbc_response" $nms_home



trap ExitProgram SIGHUP SIGINT SIGPIPE SIGTERM

   
ExitProgram 0

