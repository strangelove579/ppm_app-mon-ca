package ClrUtils;

#my $cms = 1;
#my $webi = 0;
  use strict;
  use warnings;
#  use diagnostics;
  use Cwd qw'abs_path cwd';
  use ClrProps;
  use Time::Local;
  require Exporter;
  use base ("Exporter");

  our @EXPORT_OK = qw{ nms_home clarity_version clarity_mjr_version restart
                   check_log validate_attr get_epoch_time search_log
                   get_fmtd_time get_proglog get_clarity_pid
                   log_injection niku_home get_BOServerStatus_content
                   webi_online cms_online restart_webi get_pckg_home
                  };

  our $path = "/fs0/od/nimsoft/probes/super/ppm_app";
  our $zombie_script = "/fs0/od/offering/SCRIPTS/killZombies.sh";

  our $props = ClrProps->new();

  our %shell_cmds = (
    webi_status  =>  "/bin/ps aux | /bin/grep -i \"webintelligenceprocessingserver.*pid\" | grep -v grep | wc -l 2>/dev/null",
    cms_status   =>  "/bin/ps aux | /bin/grep -i \"centralmanagementserver.*pid\" | grep -v grep | wc -l 2>/dev/null",
    webi_restart =>  "/bin/su - clarity1 -c \'/bin/sh /fs0/od/CA/SharedComponents/CommonReporting3/bobje/ccm.sh " .
                     "-managedrestart localhost.WebIntelligenceProcessingServer -cms " .
                     ( $props->bo_volumename() || '') . " -username " . ( $props->bo_user() || '' ) . " -password " . ( $props->bo_pass() || '' ). "\'",
  );

  sub get_pckg_home {
    return $path;
  }

  sub get_BOServerStatus_content {
    my $name = $props->scheduler_url() . "/niku/BOServerStatus.jsp";
    return `wget -qO- "$name" | cat | sed -n '/Servers Status/,/Maximum Concurrent WEBI/p' | tr -d \$'\r' | sed 's/<[^>]*>//g;'| perl -e '\$/ = undef; \$_ = <>; \$_ =~ s/,[ \t ]*[\n\r]*/,/g; \$_ =~ s/(general metrics|queue metrics)/\n\$1/gi; print \$_'`;
  }

  sub webi_online {
    return `$shell_cmds{webi_status}` ? 1 : 0;
    #return $webi ? 1 : 0;
  }

  sub cms_online {
    return `$shell_cmds{cms_status}` ? 1 : 0;
    #return $cms ? 1 : 0;
  }

  sub restart_webi {
    my $output;
    eval {
        local $SIG{ALRM} = sub { die "[ERROR]: Failed to start webi in a timely manner (2 min)\n" }; # NB: \n required
        alarm 120;
        $output = `$shell_cmds{webi_restart}`;
        alarm 0;
    };
    if ($@) {
        $output .= "[ERROR]: $@"
    }
    return $output;
  }

  sub get_clarity_pid {
    my $program = shift;
    return `ps -ef|grep -n "${program}@"|grep clarity1|cut -f2 -d' '`
  }

  sub get_proglog {
    my $prog = shift;
    my $log_type = shift;
    return undef unless $log_type =~ /^system|main$/i &&
                        $prog =~ /^(app|bg)[0-9]?$/;

    my $niku_logs = niku_home() . "/logs";
    #my $niku_logs = "/home/oracle/clr_19";
    my %prog_logs = (
      system => ["$niku_logs/${prog}-system.log",
                 "$niku_logs/niku${prog}-system.log"],
      main   => ["$niku_logs/${prog}-ca.log",
                 "$niku_logs/${prog}-niku.log"]
    );
    my $log = -f $prog_logs{lc $log_type}[0]
              ? $prog_logs{lc $log_type}[0]
              : -f $prog_logs{lc $log_type}[1]
              ? $prog_logs{lc $log_type}[1]
              : undef;
    return undef unless $log;
    return $log;
  }

  sub log_injection {
    my $log = shift;
    my $msg = shift;
    return undef unless defined $log && defined $msg;
    return undef unless -f $log;
    my $timestamp = get_timestamp();
    $msg = $timestamp . " [NSM Monitoring]: $msg\n";
    `echo $msg >> $log`;
  }

  sub niku_home {
    my $profile_content = `cat /etc/odprofile`;
    my ($niku_home) = ($profile_content =~ m/export NIKU_HOME=([^\n]+)/);
    return $niku_home;
  }

  sub nms_home {
    (my $nms_home = $path) =~ s{^(.*?nimsoft).*$}{$1};
    return $nms_home;
  }

  sub clarity_version {
      my $niku_home = niku_home();
      #my $vfile = `cat /home/achjo03/ppm_app/samples/version.properties`;
      my $vfile = `cat $niku_home/.setup/version.properties`;
      my ($version) = ($vfile =~ m/^version=([^\n]+)/m);
      $version =~ s/\r//g;
      $version
  }

  sub clarity_mjr_version {
    my $version = clarity_version();
    my ($mjr) = ($version =~ m/^([0-9]+)/);
    return $mjr;
  }

  sub restart {
      my $program = shift;
      #print "Calling: /usr/bin/perl $path/bin/clarity_action.pl -a restart -p $program -k 1 > /dev/null 2>&1\n";
      #`/usr/bin/perl $path/bin/clarity_action.pl -a restart -p $program -k 1 > /dev/null 2>&1 &`;
      `/usr/bin/perl $path/bin/clarity_action.pl -a restart -p $program -k 1 -o /tmp/bg_restart.tmp > /dev/null 2>&1 &`;
      #`$path/bin/clarity_action.pl -a restart -p $program -k 1 > /dev/null 2>&1 &`;

      return 1;
  }

  #
  #
  #  sub search_log
  #
  #   Check a log for a matching expression, that
  #   occurs on or after a timestamp
  #
  #  Returns
  #    0               = no match
  #    epoch timestamp = timestamp of last matching log entry
  #    2               = no match and log appears to have rolled over

  sub search_log {
    my ($logfile,$min_ts,$max_ts,$expr_to_search,$logger,$recursion_level) = @_;
    
    my $debug  ||= 0;
    $logger ||= '';
    $recursion_level = 1 unless $recursion_level;
    $max_ts = time() unless $max_ts;
    my $retval = 0;
    
    my $expr_regex = qr!$expr_to_search!i;
    my $date_regex = qr!(\d{4}).(\d{2}).(\d{2})\s(\d{2}).(\d{2}).(\d{2})!;

    EACH_FILE:
    for my $level (0..$recursion_level-1) {
      my $filename = $logfile . ( $level > 0 ? ".$level" : "");
      return 0 unless -f $filename;
      my @captured = qx{ grep -PiB1 \"$expr_to_search\" $filename 2>&- };
      my $missing_ts_flag = 0;

      local $_ = undef;
      
      my @final_matches = ();
 
      # Pre-Filter log for matching expression [$expr_to_search] and related timestamp
      # Allow for 1 linebreak between matching entry and log line with timestamp
      FILTER:
      foreach my $i (0..$#captured) {
          my ($this_line,$prev_line) = ($captured[$i],$captured[$i-1]);
          chomp($this_line,$prev_line);
          $_ = $this_line;
          
          # If the line contains a date string followed by our matching text
          # always capture these
          if (/${date_regex}.*?${expr_regex}/) { 
              push @final_matches, $this_line;

          } 
          # If the line contains our matching text, and the previous line contains
          # a date string, combine to a single line
          elsif (/$expr_regex/ 
            && defined $prev_line
            && $prev_line !~ /$expr_regex/  
            && $prev_line =~ /$date_regex/) {

              push @final_matches, (join ' ', ($prev_line,$this_line));

          }
      }
      # End Filter
      
      MATCH_ON_TS:
      foreach (@final_matches) {
        chomp;
        
        my @ts = ();
        if (@ts = $_ =~ m!(\d{4}).(\d{2}).(\d{2})\s(\d{2}).(\d{2}).(\d{2})!) {
          $ts[1]--;
          my $log_entry_time = timelocal @ts[5,4,3,2,1,0];
          # Capture online lines with timestamps that fall into our desired range
          next MATCH_ON_TS 
            unless $log_entry_time >= $min_ts and $log_entry_time <= $max_ts;
          $retval = $log_entry_time

        } else {
          print "Warning: Did not find a timestamp in the line: $_\n" if $debug;
        }
      }
      # Return the timestamp of the last matching entry
      return $retval if $retval;
    }
    print "search_log():  No matching entry found\n" if $debug;
    return $retval;
  }


  sub validate_attr {
      my ($name,$val,$exit,$log) = @_;
      return 1 if defined $val;
      $log->write("ERROR: Attribute found missing or could not be resolved: [" . uc $name . "]. " . ($exit ? "Exiting..." : ""));
      return defined $val ? 1 : 0;
  }

  sub get_epoch_time {
      my $ts = shift || get_fmtd_time();
      my @t = $ts =~ m!^(\d{4}).(\d{2}).(\d{2})\s(\d{2}).(\d{2}).(\d{2})!;
      return undef unless scalar @t > 0;
      $t[1]--;
      timelocal @t[5,4,3,2,1,0];
  }

  sub get_fmtd_time {
      my $timestamp = shift || time;
      my $pad = sub { my $n = shift; return length($n) == 1 ? '0'.$n : $n;};
      my ($sec, $min, $hour, $day,$month,$year) = (localtime($timestamp))[0,1,2,3,4,5];
      $year += 1900;
      $month++;
      $sec = $pad->($sec);
      $min = $pad->($min);
      $hour = $pad->($hour);
      $month = $pad->($month);
      $day = $pad->($day);
      my $fmtd = "$year/$month/$day $hour:$min:$sec";
  }
