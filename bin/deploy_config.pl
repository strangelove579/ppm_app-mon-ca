#!/usr/bin/perl
#
#   deploy_config.pl
#   Auth: John Achee, 12/14/12
#   Deploy dynamic probe configurations for ppm_app
#
#   Revision 1.5, 7/9/13  John Achee


  use strict;
  use warnings;
  use Cwd qw/realpath/;
  use POSIX qw/strftime/;
  use Time::Local;
  use subs qw/LOG/;

  our $apphome;

  BEGIN {
      # Sort out home directory dynamically.
      # Expect that script is contained within standard 'bin' directory
      local $_ = realpath($0);
      $apphome = m{^(.*?)/bin/[^/]+$} ? $1 : undef;
      die "Unable to find application path, is this script running from ./bin?"
        unless $apphome;

      # Push any private libraries to the bottom of the @INC stack
      # so it is searched first
      if (my $priv_lib = "$apphome/lib") {
        unshift @INC, $priv_lib;
      }
  }
 
  $|++;

  use Logger;
  use Configurator;
  use ClrUtils qw/clarity_version clarity_mjr_version/;
  #
  # Logging - Setup output directories for logging
  #
  #
#  my $admin_dir   = '/home/achjo03/ppm_app/samples/admin';
  my $admin_dir   = '/fs0/clarity1/admin';
  my $uim_log     = "$admin_dir/uim";
  my $version_log = "$uim_log/versions.txt";
  `rm -rf $admin_dir/nms`;
  `mkdir -p $uim_log` and die "Unable to create directory structure for logging to [$uim_log] $!";
  `chown -R clarity1:app^chsadmins $uim_log` and die "Unable to chown directory structure for [$uim_log] $!";

  # Flag BOServerStatus.jsp as 'unverified'
  `touch $apphome/config/.boss_unverified`;  

  #  unelegant 1-off perl symlink generator
  #  /fs0/od/perl is required by other scripts in this package
  `ln -s /fs0/od/offering/PERL/perl /fs0/od/perl` unless (-e "/fs0/od/perl" );


  #
  # Initialize standard vars
  #
  # declared as globals, so that symbolic references can see them

  our $nms_home        = '/fs0/od/nimsoft';
  our $niku_home       = '/fs0/clarity1/clarity';
  our $clarity_version = clarity_version();



  # Initialize configs
  my $cfg         = Configurator->new("$apphome/config/common.cfg");
  my $res_cfg     = Configurator->new("$apphome/config/res.cfg");
  my $tz_snapshot = "$apphome/config/tz.cfg";
  my $debug       = $cfg->debug();
  my $log         = Logger->new("$uim_log/deploy.log");
  my $installed_log    = "$uim_log/installed.log";
  my $ts;
  


 
  LOG "===============================================================";
  LOG "    Deploying ppm_app v." . $cfg->version();
  LOG "===============================================================";
  LOG "NMS_HOME  = $nms_home";
  LOG "NIKU_HOME = $niku_home";
  LOG "Clarity Version = $clarity_version";

  foreach my $var (qw/nms_home niku_home clarity_version /) {
      no strict 'refs';
      unless ( defined $$var ) {
          LOG "ERROR: Environment is not in an expected state, cannot continue with deployment [$var is not defined]";
          exit 1;
      }
  }


  my $deployed_flag_file = "$apphome/bin/.is_deployed";
  my $is_deployed = -f $deployed_flag_file ? 1 : 0;

  LOG "Deployment method: " . ( $is_deployed ? 'nexec/cron/manual' : 'package-install process');



  #  Timezone Monitoring
  #  Take a snapshot of the system timezone, its offset and daylight saving time status
  #  for monitoring of manual changes

  LOG "Verifying timezone snapshot has been taken, for timezone monitoring config...";

  unless (-f $tz_snapshot ) {
      use TZSnapShot;
      my $tzs = TZSnapShot->new($tz_snapshot);
      $tzs->take_snapshot();
      LOG "Snapshot created. Timezone: [". $tzs->ss_tz(). "], Offset: [". $tzs->ss_offset(). "], DST: [". ($tzs->ss_is_dst() ? "yes" : "no") . "]";
  }

  # Execute rpm installs
  #install_sysstat(); 


  #  Resource Deployment
  #  Resources here are defined as the package's payload such as scripts, data, and other content related files
  #  that must be deployed to locations outside of this package. Default probe configs, BOServerStatus.jsp are examples.
  #
  LOG "Deploy any res files requiring update...";

  foreach my $key ($res_cfg->cget_keys()) {

      my $res_file = "$apphome/" . $key;
      my $props = $res_cfg->$key();
      $props =~ s/\$\{?niku_home\}?/$niku_home/g;
      $props =~ s/\$\{?nms_home\}?/$nms_home/g;

      my ($target_path,$octset,$ids,$overwrite,$script) = split / /, $props;

      

      if ( (! -f $target_path )                        # If target doesnt exist
           || ($overwrite == 1)                           # or enabled: always overwrite
           || ($overwrite == 2 && ( -s $target_path != -s $res_file )) ) # or enabled: overwrite only if sizes are different
      {
          # create the directory path if it doesn't exist:
          my ($dir) = ($target_path =~ m{^(.*?)/[^/]+$});
          `mkdir -p $dir` unless -d $dir;

          LOG "Deploying file [$res_file]...";
          LOG "File properties: Target: [$target_path],  Octset: [$octset], IDs: [$ids] Overwrite: [$overwrite]  Script: [" . (defined $script ? $script : "<none>") . "]";

          my $cp = qx{ /bin/cp -f $res_file $target_path };
          LOG "Unexpected result in file copy for $res_file->$target_path:  [$cp]" if $cp =~ /\S/;

          my $chmod = qx{chmod $octset $target_path};
          LOG "Unexpected result in file permission change for [$target_path]:  [$chmod]" if $chmod =~ /\S/;

          my $chown = qx{ chown $ids $target_path };
          LOG "Unexpected result in file ownership change for [$ids - $target_path]:  [$chown]" if $chown =~ /\S/;

          my $scr   = qx{$script} if defined $script;

          LOG "Done.";
      } else {
          LOG "Deployment not needed for file [$res_file]";
      }
  }
  LOG "Finished payload deployment";




  LOG "Generate new probe configurations...";
  #
  #  Run auto-config scripts
  #
  my @scripts = split / /, $cfg->config_scripts();
  foreach my $script (@scripts) {
      (my $probe = $script) =~ s{^([^/]+).*$}{$1};
      LOG sprintf("%-50.50s", "\U$probe  " . ("*" x 50)); 
      $script = "/bin/bash $apphome/" . $script;
      my @out = qx{$script 0 "$nms_home" "$apphome"};
      foreach (@out) {
        chomp;
        next if /^\s*$/;
        LOG "... $_"
      }
      LOG " ";
  }
  my $ppm_version = clarity_version();
  print "VERIFY --> $_\n" foreach $cfg->verify_probes();
  my @verify_probes = split /\s*,\s*/, $cfg->verify_probes;
  foreach (@verify_probes) { 
      chomp;
      s/^\s*//;
      s/\s*$//;
      #s{^.*/}{};
      my ($group,$dir)  = split /\s*\/\s*/;
      my $probe_config = "/fs0/od/nimsoft/probes/$group/$dir/$dir.cfg";
      print "PROBE CONFIG: $probe_config\n";
	  
	  if ($ppm_version =~ /^15.[1-9]/) {
		`/usr/bin/perl -pi -e 's/2001\.[1-4]+\./2001\.152\./g' $probe_config`;
	  }
      elsif ($ppm_version =~ /^14.[3-9]/) {
        `/usr/bin/perl -pi -e 's/2001\.[1-4]+\./2001\.143\./g' $probe_config`;
      } else { 
        `/usr/bin/perl -pi -e 's/2001\.[1-4]+\./2001\.133\./g' $probe_config`;
      }
  }
  my $do_probe_verifys       = $cfg->do_probe_verifys();
  my $do_probe_deactivations = $cfg->do_probe_deactivations();
  my $do_probe_activations   = $cfg->do_probe_activations();
  

  #
  #  
  #     Verify probes if required
  #     
  #        
  if ($do_probe_verifys)  {

  LOG "Probe Verification - Perform any verifications needed...";

      my @probes;
      my $probes_base = "$nms_home/probes";
      foreach ($cfg->verify_probes()) {
          next unless defined $_;
          next if /^\s*$/;
          s/\s//g;
          push @probes, ( split /,/ );
      }
      my @names;
      foreach (@probes) {
          sleep 1;
          my ($name) = ($_ =~ m{([\w]+)$});
          my $probe_log = "$probes_base/$_/${name}.log";
          my $attempts = 0;
          VERIFY_PROBE: {
            $attempts++;
            local $_ = qx{ $nms_home/bin/pu -uprobe_admin -padmin01 controller probe_verify $name };

            $ts = strftime "%m/%d/%Y %H:%M:%S", localtime(time);

            unless (/_command failed|communication error/) {
                LOG "Probe is verified:  [$name] ";
                `echo $ts [ppm_app deploy_config.pl]: [$name] probe verified >> $probe_log`;
            } else {
                LOG "ERROR [$name] probe verification failed. Output was:\n $_";
                `echo $ts [ppm_app deploy_config.pl]: ERROR [$name] probe failed to verify >> $probe_log`;
                redo VERIFY_PROBE unless $attempts >= 3;
            }
         }
      }
  }

  #
  #
  #  Deactivate probes if required
  #
  #
  if ($do_probe_deactivations)  {
  
  LOG "Probe Deactivations - Perform any force deactivations...";
  
      my @probes;
      my $probes_base = "$nms_home/probes";
      foreach ($cfg->deactivate_probes()) {
          next unless defined $_;
          next if /^\s*$/;
          s/\s//g;
          push @probes, ( split /,/ );
      }
      my @names;
      foreach (@probes) {
          sleep 1;
          my ($name) = ($_ =~ m{([\w]+)$});
          my $probe_log = "$probes_base/$_/${name}.log";
          my $attempts = 0;

          DEACTIVATE_PROBE: {
            $attempts++;

            local $_ = qx{ $nms_home/bin/pu -uprobe_admin -padmin01 controller probe_deactivate $name };

            $ts = strftime "%m/%d/%Y %H:%M:%S", localtime(time);

            unless (/_command failed|communication error/) {
                LOG "Probe is deactivated:  [$name] ";
                `echo $ts [ppm_app deploy_config.pl]: [$name] probe deactivated >> $probe_log`;
            } else {
                LOG "ERROR [$name] probe failed to deactivate. Output was:\n $_";
                `echo $ts [ppm_app deploy_config.pl]: ERROR [$name] probe failed to deactivate >> $probe_log`;
                sleep(5);
                redo DEACTIVATE_PROBE unless $attempts >= 3;
            }
         }
      }
  }

  #   Probe re-activation
  #   Check if this package was already deployed, if not then
  #   run probe re-activation... This block allows re-activation
  #   of probes on deployment, but not when running auto-config
  #   from nexec probe.

  if ($do_probe_activations)  {

  LOG "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-";
  LOG "    Probe Activations - Perform any force activations";
  LOG "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-";

      my @probes;
      my $probes_base = "$nms_home/probes";
      foreach ($cfg->activate_probes()) {
          next unless defined $_;
          next if /^\s*$/;
          s/\s//g;
          push @probes, ( split /,/ );
      }
      my @names;
      foreach (@probes) {
          sleep 1;
          my ($name) = ($_ =~ m{([\w]+)$});
          my $probe_log = "$probes_base/$_/${name}.log";
          my $attempts = 0;
          
          ACTIVATE_PROBE: {
            $attempts++;

            local $_ = qx{ $nms_home/bin/pu -uprobe_admin -padmin01 controller probe_activate $name };

            $ts = strftime "%m/%d/%Y %H:%M:%S", localtime(time);

            unless (/_command failed|communication error/) {
                LOG "Probe is activated:  [$name] ";
                `echo $ts [ppm_app deploy_config.pl]: [$name] probe activated >> $probe_log`;
            } else {
                LOG "ERROR [$name] probe failed to activate. Output was:\n $_";
                `echo $ts [ppm_app deploy_config.pl]: ERROR [$name] probe failed to activate >> $probe_log`;
                sleep(5);
                redo ACTIVATE_PROBE unless $attempts >= 3;
            }
         }
      }
  }


  $ts = strftime "%b %e, %Y %H:%M:%S %Z", localtime(time);
  qx{ echo "$ts" > $deployed_flag_file };

  my $msg = "ppm_app v."  .$cfg->version(). " last deployed on ". strftime "%m/%d/%Y %H:%M:%S", localtime(time);
  `echo $msg > $installed_log`;
 
  #
  #  Write all probe package versions to /fs0/clarity1/clarity/nms/versions.txt
  #  with last install date
  #
  LOG "Generating package/probe version(s) rollup summary...";
  LOG "Parsing and summarizing NMS Versions Log: $nms_home/robot/pkg/versions.txt";
  my $out = qx{/fs0/od/perl/bin/perl $apphome/bin/versions.pl $nms_home/robot/pkg/versions.txt > $version_log};
  my $status = $? >> 8;

  if ($status == 0) {
      LOG "Done.";
      LOG "Package/probe version rollup report is located here:  $version_log";
  } else {
      LOG "ERROR: Failed to generate Package report. Exit status was $status. Output was: $out";
  }

  LOG " ";
  LOG "Deployment Finished.";
  LOG " ";
  `chmod 0777 -R $uim_log/`;
  exit 0;





  sub install_sysstat {    

    my ($install,$add,$remove,$skip_chkconfig) = (0,0,0);
    
    local $_ = `/bin/rpm -q sysstat`;
    
    if (/is not installed/) {
        LOG "sysstat is not installed, going to install it...";
        $install = 1;
    } else {
        LOG "sysstat already installed, skipping sysstat installation";
    }
    
    if ($install) {
      my $res = system("/usr/bin/yum -y install sysstat 2>&1 > /dev/null");
      $res = $res >> 8;
      if ($res) {
        LOG "ERROR: yum failed to install sysstat with error code: [$res]";
        $skip_chkconfig = 1;
      } else {
        LOG "Yum installed sysstat successfully";
      }
    }
    
    unless ($skip_chkconfig) {
        local $_ = `/sbin/chkconfig --list sysstat`;
        chomp;
#        print "chkconfig: $_\n";
        unless (/0.*?1.*?2.*?3.*?4.*?5.*?6/) {
            LOG "sysstat is not yet added to chkconfig, going to add it...";
            $add = 1;
        } else {
            unless (/0\:off\s+1\:off\s+2\:on\s+3\:on\s+4\:off\s+5\:on\s+6\:off/) {
                LOG "sysstat exists in chkconfig, but its levels are wrong...going to fix it. levels should be 2,3,5";
                $add = 1;
                $remove = 1;
            } else {
                LOG "chkconfig is properly configured for sysstat";
            }
        }
    }
    if ($remove && ! $skip_chkconfig) {
      my $res = system("/sbin/chkconfig --del sysstat");
      $res = $res >> 8;
      if ($res) {
        LOG "ERROR: chkconfig levels were wrong for sysstat, but chkconfig failed to remove sysstat for re-install, with error code: [$res]";
        $skip_chkconfig = 1;
      } else {
        LOG "sysstat was successfully removed from chkconfig";
      }
      
    }
    if ($add && ! $skip_chkconfig) {
      my $res = system("/sbin/chkconfig --level 235 sysstat on");
      $res = $res >> 8;
      if ($res) {
        LOG "ERROR: chkconfig failed to install sysstat";
      } else {
        LOG "sysstat was successfully added to chkconfig";
      }
    }
    1;
  }

  sub LOG {
      my @msg = @_;
      $log->write(@msg);
      print "@msg\n";
  }
