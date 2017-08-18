#!/bin/bash
#===================================================================================
#
#         FILE: deploy_config_url_response.sh
#
#        USAGE: ./deploy_config_url_response.sh
#
#  DESCRIPTION: Build and deploy configuration file(s)
#
#      PACKAGE: clr_12_13
#        PROBE: URL_RESPONSE
#
#      OPTIONS: NONE
# REQUIREMENTS: $package_home/lib/common.sh
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: John Achee, Principal Developer
#      COMPANY: CA Technologies
#      VERSION: 1.4
#      CREATED: 04.05.2012
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
    [ -e $tmp_config_file      ] && rm --force $tmp_config_file
    [ -e /tmp/profile.tmp      ] && rm --force /tmp/profile.tmp
    UpdateLog "Completed processing of config for probe [url_response]" $log_file 3
    exit ${1:-1}
}

#-------------------------------------------------------------------------------
# Import all common libraries
#-------------------------------------------------------------------------------
. "$package_home/lib/common.sh"

probe_home="$nms_home/probes/application/url_response"
template_dir="$package_home/url_response/templates"
config_file="$probe_home/url_response.cfg"
setup_template="$template_dir/url_response_setup.template"
tmp_config_file="/tmp/url_response.cfg"
log_file="$probe_home/url_response.log"
config_dir="$package_home/url_response/config/generic"
GetHostname


UpdateLog "Building probe config for:  [url_response]" $log_file 3

#-------------------------------------------------------------------------------
# Set default configuration file path, Exit if not found
#-------------------------------------------------------------------------------
default_config="$probe_home/url_response.cfx"
if [ ! -f $default_config ]; then
    UpdateLog "Default configuration file was not found: $default_config. Exiting..." $log_file 1
    ExitProgram 1
fi


#-------------------------------------------------------------------------------
# Check that clarity is installed
#-------------------------------------------------------------------------------
GetClarityVersion

if [ $? -ne 0 ]; then
    UpdateLog "Failed to capture Clarity Version. Exiting..." $log_file 1
    ExitProgram 1
fi

#-------------------------------------------------------------------------------
# Gather clarity properties and settings
#-------------------------------------------------------------------------------
GetClarityProperties $niku_home $debug_enabled       # $niku_home provided by GetClarityVersion

# Convert to arrays
app_array=($app_array)

#-------------------------------------------------------------------------------
# Provide default config if app and reports is not enabled
#-------------------------------------------------------------------------------
if [ -z "$app_array" ] && [ "$reports_installed" == "no" ]; then
    UpdateLog "App and BO are not enabled, providing probe with default config..." $log_file 3
    MakeConfigFile $default_config $config_file $log_file $debug_enabled 0 "url_response" $nms_home
    ExitProgram 0
fi


#-------------------------------------------------------------------------------
# Functions to interface with clarity port settings
#-------------------------------------------------------------------------------
waPort () {
    local this_app=$1
    for str in ${sso_status_array[@]}; do
        app="${str%%:*}"
        status="${str##*:}"
        if [[ "$app" == "$this_app" ]]; then
            if [[ "$status" == "true" ]]; then
                app_last_char=`echo "$app" | sed 's/^.*\(.\)$/\1/'`

                if [[ "$app_last_char" == "${app_last_char//[^0-9]/}" ]]; then
                    wa_port=$(( 8081 + ( $app_last_char - 1 ) ))
                    ssl_active="no"
                else
                    wa_port=8081
                    ssl_active="no"
                fi
            fi
        fi
    done
}


appNonSSLPort () {
    local this_app=$1

    for str in ${non_ssl_ports[@]}; do
        local app="${str%%:*}"
        local port="${str##*:}"
        if [[ "$app" == "$this_app" ]]; then
            non_ssl_port=$port
        fi
    done
    return 1
}

appSSLPort () {
    local this_app=$1

    for str in ${ssl_ports[@]}; do
        local app="${str%%:*}"
        local port="${str##*:}"
        if [[ "$app" == "$this_app" ]]; then
            return $port
        fi
    done
    return 0
}

#-------------------------------------------------------------------------------
# Add "setup" section to temporary configuration file
#-------------------------------------------------------------------------------
setup_definition="$config_dir/url_response_setup.cfg"

if [ ! -f $setup_definition ]; then
    UpdateLog "Setup file has not been provided. Exiting..." $log_file 1
    ExitProgram 1
fi

. $setup_definition
cp -f $setup_template $tmp_config_file


/bin/sed -i "s/@LOGLEVEL@/$loglevel/g" $tmp_config_file
/bin/sed -i "s/@LOGSIZE@/$logsize/g" $tmp_config_file
/bin/sed -i "s/@FORCE_SYNCH@/$force_synchronous/g" $tmp_config_file
/bin/sed -i "s/@MIN_THREADS@/$min_threads/g" $tmp_config_file
/bin/sed -i "s/@MAX_THREADS@/$max_threads/g" $tmp_config_file
/bin/sed -i "s/@ALARM_EACH_SAMPLE@/$alarm_on_each_sample/g" $tmp_config_file


#-------------------------------------------------------------------------------
# Populate temporary profiles file
#-------------------------------------------------------------------------------
echo "" > /tmp/profile.tmp


#-------------------------------------------------------------------------------
# Build list of profile definition files, exclude the Sample
#-------------------------------------------------------------------------------
#   Clarity app
if echo "$niku_version" | egrep "^14.[3-9]|15.[1-9]" > /dev/null; then
  match_string=\"CLARITY_LOGIN\":\"1\"
#  profile_definition="$config_dir/url_response_profile_appservice.cfg"
else
  match_string="LOGIN_SUCCESS=1"
fi

profile_definition="$config_dir/url_response_profile_app.cfg"
. $profile_definition


for (( i=0;i<${#app_array[@]};i++ )); do
    appNonSSLPort ${app_array[i]}
    
    ssl_active="no"
    if [ -z $non_ssl_port ]; then
        UpdateLog "Unable to determine NON-SSL port from clarity properties.xml." $log_file 1
        UpdateLog "Please verify properties.xml. Exiting..." $log_file 1
        ExitProgram 1
    fi

   if echo "$niku_version" | egrep "^14.[3-9]|15.[1-9]" > /dev/null; then
       url="http://localhost:${non_ssl_port}/niku/serverstatus/status?run=CLARITY_LOGIN"
   else
       url="http://localhost:${non_ssl_port}/niku/monitor.jsp"
   fi
    
    UpdateLog "Adding monitor for app URL: [$url]" $log_file 3

    cat $template_dir/url_response_profile.template >> /tmp/profile.tmp
    /bin/sed -i "s/@NAME@/PPM ${hostname}_${app_array[i]}/g" /tmp/profile.tmp
	/bin/sed -i "s/@ACTIVE@/$active/g" /tmp/profile.tmp
    /bin/sed -i "s/@QOS@/$qos/g" /tmp/profile.tmp
    /bin/sed -i "s/@QOS_SUBSTRING_FOUND@/$qos_substring_found/g" /tmp/profile.tmp
    /bin/sed -i "s/@INTERVAL@/$interval/g" /tmp/profile.tmp
    /bin/sed -i "s/@TIMEOUT@/$timeout/g" /tmp/profile.tmp
    /bin/sed -i "s/@RETRY@/$retry/g" /tmp/profile.tmp
    /bin/sed -i "s|@URL@|$url|g" /tmp/profile.tmp
    /bin/sed -i "s/@SSL_ACTIVE@/$ssl_active/g" /tmp/profile.tmp
    /bin/sed -i "s/@SUBSYSTEM@/$subsystem/g" /tmp/profile.tmp
    /bin/sed -i "s/@ALARM_ACTIVE@/$alarm_active/g" /tmp/profile.tmp
    /bin/sed -i "s/@MATCH_STRING@/$match_string/g" /tmp/profile.tmp
    /bin/sed -i "s|@THRESHOLD@|$threshold|g" /tmp/profile.tmp
	/bin/sed -i "s|@NOT_MATCH@|$not_match|g" /tmp/profile.tmp

done


#CSK_ADM_PPMSchema (Advance reporting)
if echo "$niku_version" | egrep "^15.[1-9]" > /dev/null; then
     profile_definition="$config_dir/url_response_profile_csk_adm_ppms.cfg"
    . $profile_definition

    for (( i=0;i<${#app_array[@]};i++ )); do
         appNonSSLPort ${app_array[i]}

	 ssl_active="no"
	 if [ -z $non_ssl_port ]; then
	      UpdateLog "Unable to determine NON-SSL port from clarity properties.xml." $log_file 1
	      UpdateLog "Please verify properties.xml. Exiting..." $log_file 1
	      ExitProgram 1
	 fi

	 url="http://localhost:${non_ssl_port}/niku/serverstatus/advrptstatus?rpt=/ca_ppm/reports/administration/CSK_ADM_DatabaseConnectionCheckPPM\&usr=ppm_monitor@ca.com"
	 
	 UpdateLog "Adding monitor for PPMSchema Adv Reporting URL: [$url]" $log_file 3

         cat $template_dir/url_response_profile.template >> /tmp/profile.tmp
         /bin/sed -i "s/@NAME@/PPM ${hostname}_PPMSchema_${app_array[i]}/g" /tmp/profile.tmp
		 /bin/sed -i "s/@ACTIVE@/$active/g" /tmp/profile.tmp
         /bin/sed -i "s/@QOS@/$qos/g" /tmp/profile.tmp
		 /bin/sed -i "s/@QOS_SUBSTRING_FOUND@/$qos_substring_found/g" /tmp/profile.tmp
         /bin/sed -i "s/@INTERVAL@/$interval/g" /tmp/profile.tmp
         /bin/sed -i "s/@TIMEOUT@/$timeout/g" /tmp/profile.tmp
         /bin/sed -i "s/@RETRY@/$retry/g" /tmp/profile.tmp
         /bin/sed -i "s|@URL@|$url|g" /tmp/profile.tmp
         /bin/sed -i "s/@SSL_ACTIVE@/$ssl_active/g" /tmp/profile.tmp
         /bin/sed -i "s/@SUBSYSTEM@/$subsystem/g" /tmp/profile.tmp
		 /bin/sed -i "s/@ALARM_ACTIVE@/$alarm_active/g" /tmp/profile.tmp
         /bin/sed -i "s/@MATCH_STRING@/$match_string/g" /tmp/profile.tmp
         /bin/sed -i "s|@THRESHOLD@|$threshold|g" /tmp/profile.tmp
		 /bin/sed -i "s|@NOT_MATCH@|$not_match|g" /tmp/profile.tmp
    done
fi

#CSK_ADM_DataWarehouseSchema (Advance reporting)
if echo "$niku_version" | egrep "^15.[1-9]" > /dev/null; then
      profile_definition="$config_dir/url_response_profile_csk_adm_dws.cfg"
    . $profile_definition

    for (( i=0;i<${#app_array[@]};i++ )); do
         appNonSSLPort ${app_array[i]}

	 ssl_active="no"
	 if [ -z $non_ssl_port ]; then
	      UpdateLog "Unable to determine NON-SSL port from clarity properties.xml." $log_file 1
	      UpdateLog "Please verify properties.xml. Exiting..." $log_file 1
	      ExitProgram 1
	 fi

	 url="http://localhost:${non_ssl_port}/niku/serverstatus/advrptstatus?rpt=/ca_ppm/reports/administration/CSK_ADM_DatabaseConnectionCheckDWH\&usr=ppm_monitor@ca.com"
	 
	 UpdateLog "Adding monitor for PPM DWSchema Adv ReportingURL: [$url]" $log_file 3

         cat $template_dir/url_response_profile.template >> /tmp/profile.tmp
         /bin/sed -i "s/@NAME@/PPM ${hostname}_DWSchema_${app_array[i]}/g" /tmp/profile.tmp
		 /bin/sed -i "s/@ACTIVE@/$active/g" /tmp/profile.tmp
         /bin/sed -i "s/@QOS@/$qos/g" /tmp/profile.tmp
		 /bin/sed -i "s/@QOS_SUBSTRING_FOUND@/$qos_substring_found/g" /tmp/profile.tmp
         /bin/sed -i "s/@INTERVAL@/$interval/g" /tmp/profile.tmp
         /bin/sed -i "s/@TIMEOUT@/$timeout/g" /tmp/profile.tmp
         /bin/sed -i "s/@RETRY@/$retry/g" /tmp/profile.tmp
         /bin/sed -i "s|@URL@|$url|g" /tmp/profile.tmp
         /bin/sed -i "s/@SSL_ACTIVE@/$ssl_active/g" /tmp/profile.tmp
         /bin/sed -i "s/@SUBSYSTEM@/$subsystem/g" /tmp/profile.tmp
	     /bin/sed -i "s/@ALARM_ACTIVE@/$alarm_active/g" /tmp/profile.tmp
         /bin/sed -i "s/@MATCH_STRING@/$match_string/g" /tmp/profile.tmp
         /bin/sed -i "s|@THRESHOLD@|$threshold|g" /tmp/profile.tmp
		 /bin/sed -i "s|@NOT_MATCH@|$not_match|g" /tmp/profile.tmp
    done
fi

#   Webagent
profile_definition="$config_dir/url_response_profile_wa.cfg"
. $profile_definition

for (( i=0;i<${#app_array[@]};i++ )); do
    wa_port=""
    waPort ${app_array[i]}
    
    if [[  $? == 1 ]]; then
        UpdateLog "Unable to determine web agent state. Please verify application configuration" $log_file 1
        ExitProgram 1
    fi

    if [[ ! -z $wa_port && ! "$wa_port" == "0" ]]; then

        url="http://localhost:${wa_port}/niku/wsdl"

        UpdateLog "Adding monitor for wa URL: [$url]" $log_file 3

        cat $template_dir/url_response_profile.template >> /tmp/profile.tmp
        /bin/sed -i "s/@NAME@/PPM ${hostname}_webagent_${app_array[i]}/g" /tmp/profile.tmp
		/bin/sed -i "s/@ACTIVE@/$active/g" /tmp/profile.tmp
        /bin/sed -i "s/@QOS@/$qos/g" /tmp/profile.tmp
		/bin/sed -i "s/@QOS_SUBSTRING_FOUND@/$qos_substring_found/g" /tmp/profile.tmp
        /bin/sed -i "s/@INTERVAL@/$interval/g" /tmp/profile.tmp
        /bin/sed -i "s/@TIMEOUT@/$timeout/g" /tmp/profile.tmp
        /bin/sed -i "s/@RETRY@/$retry/g" /tmp/profile.tmp
        /bin/sed -i "s|@URL@|$url|g" /tmp/profile.tmp
        /bin/sed -i "s/@SSL_ACTIVE@/$ssl_active/g" /tmp/profile.tmp
        /bin/sed -i "s/@SUBSYSTEM@/$subsystem/g" /tmp/profile.tmp
		/bin/sed -i "s/@ALARM_ACTIVE@/$alarm_active/g" /tmp/profile.tmp
        /bin/sed -i "s/@MATCH_STRING@//g" /tmp/profile.tmp
        /bin/sed -i "s|@THRESHOLD@|$threshold|g" /tmp/profile.tmp
		/bin/sed -i "s|@NOT_MATCH@|$not_match|g" /tmp/profile.tmp
    fi
done


# Add a profile for reports if BO is enabled
#   Clarity app
profile_definition="$config_dir/url_response_profile_bo.cfg"
. $profile_definition

if [ "$reports_installed" == "yes" ]; then
    url="$reports_url/InfoViewApp"
    ssl_active="no"
    
    UpdateLog "Adding monitor for InfoView URL: [$url]" $log_file 3

    cat $template_dir/url_response_profile.template >> /tmp/profile.tmp
    /bin/sed -i "s/@NAME@/PPM ${hostname}_bo/g" /tmp/profile.tmp
	/bin/sed -i "s/@ACTIVE@/$active/g" /tmp/profile.tmp
    /bin/sed -i "s/@QOS@/$qos/g" /tmp/profile.tmp
    /bin/sed -i "s/@QOS_SUBSTRING_FOUND@/$qos_substring_found/g" /tmp/profile.tmp
    /bin/sed -i "s/@INTERVAL@/$interval/g" /tmp/profile.tmp
    /bin/sed -i "s/@TIMEOUT@/$timeout/g" /tmp/profile.tmp
    /bin/sed -i "s/@RETRY@/$retry/g" /tmp/profile.tmp
    /bin/sed -i "s|@URL@|$url|g" /tmp/profile.tmp
    /bin/sed -i "s/@SSL_ACTIVE@/$ssl_active/g" /tmp/profile.tmp
    /bin/sed -i "s/@SUBSYSTEM@/$subsystem/g" /tmp/profile.tmp
    /bin/sed -i "s/@ALARM_ACTIVE@/$alarm_active/g" /tmp/profile.tmp
    /bin/sed -i "s/@MATCH_STRING@//g" /tmp/profile.tmp
    /bin/sed -i "s|@THRESHOLD@|$threshold|g" /tmp/profile.tmp
	/bin/sed -i "s|@NOT_MATCH@|$not_match|g" /tmp/profile.tmp
fi

# Add a profile for BOSS (BO Server Status jsp script)
#   BOSS .. only if 12.1.1+ !


if [ "$reports_installed" == "yes" ]; then


  if echo "$niku_version" | egrep "^(12.1.1|13|14.[0-2])" > /dev/null; then
      url="$schedulerurl/niku/BOServerStatus.jsp"
  else
      url="$schedulerurl/niku/serverstatus/bostatus"
  fi
  profile_definition="$config_dir/url_response_profile_boss.cfg"
  . $profile_definition
      ssl_active="no"
      
      UpdateLog "Adding monitor for BOServerStatus.jsp: [$url]" $log_file 3
      
      cat $template_dir/url_response_profile.template >> /tmp/profile.tmp
      /bin/sed -i "s/@NAME@/PPM ${hostname}_boss/g" /tmp/profile.tmp
	  /bin/sed -i "s/@ACTIVE@/$active/g" /tmp/profile.tmp
      /bin/sed -i "s/@QOS@/$qos/g" /tmp/profile.tmp
      /bin/sed -i "s/@QOS_SUBSTRING_FOUND@/$qos_substring_found/g" /tmp/profile.tmp
      /bin/sed -i "s/@INTERVAL@/$interval/g" /tmp/profile.tmp
      /bin/sed -i "s/@TIMEOUT@/$timeout/g" /tmp/profile.tmp
      /bin/sed -i "s/@RETRY@/$retry/g" /tmp/profile.tmp
      /bin/sed -i "s|@URL@|$url|g" /tmp/profile.tmp
      /bin/sed -i "s/@SSL_ACTIVE@/$ssl_active/g" /tmp/profile.tmp
      /bin/sed -i "s/@SUBSYSTEM@/$subsystem/g" /tmp/profile.tmp
      /bin/sed -i "s/@ALARM_ACTIVE@/$alarm_active/g" /tmp/profile.tmp
      /bin/sed -i "s/@MATCH_STRING@/$match_string/g" /tmp/profile.tmp
      /bin/sed -i "s|@THRESHOLD@|$threshold|g" /tmp/profile.tmp
	  /bin/sed -i "s|@NOT_MATCH@|$not_match|g" /tmp/profile.tmp
fi

#-------------------------------------------------------------------------------
# Join connections and profiles into temporary config file, and cleanup
#-------------------------------------------------------------------------------
echo "<profiles>"                                >> $tmp_config_file
cat /tmp/profile.tmp                             >> $tmp_config_file
echo "</profiles>"                               >> $tmp_config_file
echo "<messages>"                                >> $tmp_config_file
cat $template_dir/url_response_messages.template >> $tmp_config_file
echo "</messages>"                               >> $tmp_config_file

/bin/sed -i "/^$/d" $tmp_config_file            # Clear out any blank lines

rm -f /tmp/profile.tmp
#-------------------------------------------------------------------------------
# Compare existing configuration file and new configuration file
#            Replace only if they're different
#-------------------------------------------------------------------------------
#config_file="/home/achjo03/ppm_app/samples/url_response.cfg"
MakeConfigFile $tmp_config_file $config_file $log_file $debug_enabled 1 "url_response" $nms_home

UpdateLog "Completed probe config for: [url_response]" $log_file 3


trap ExitProgram SIGHUP SIGINT SIGPIPE SIGTERM


ExitProgram 0

