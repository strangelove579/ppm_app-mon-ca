#!/usr/bin/perl
# bglog_driver.pl
# John Achee, 12/14/12
  
  BEGIN {
      our $path = "/fs0/od/nimsoft/probes/super/ppm_app";
      push @INC, "$path/lib";
  }


#
#  Debug overrides
#
#     timestamp format for '$override_current_time' = YYYY/MM/DD HH24:MI:SS
#

  our $debug = 1;
  our $override_bglog = undef;#"/home/achjo03/bg-ca.log";         # when not using  set to undef!
  our $override_current_time = undef;#'2012-09-05 10:50:07';  # when not using, set to undef!
  our $debug_mode = undef;#'fancy_restart';
  
  use strict;
  use warnings;
  use Getopt::Long ();
  use Logger;
  use ClrUtils qw/ nms_home
                   clarity_version
                   restart
                   search_log validate_attr get_epoch_time
                   get_fmtd_time get_proglog get_clarity_pid
                   niku_home
               /;

  use subs qw/
                delete_queue_files
                tell_bg
                log_n_stdout
                update_queue_file
                log_n_quit
                last_queue_file
                queue_match
                import_queue
                log
            /;

  use subs qw! ALREADY_TRIED_TO_RESTART
               RESTART_BG_AGAIN   CHECK_FOR_OOM_OR_DISC
               RESTART_BG         THERES_PENDING_RESTART_CHECKS
               SUCCESS_WERE_DONE  IT_RESTARTED_SUCCESSFULLY
               IM_DONE_TRYING     WE_HAVENT_HIT_3_ATTEMPTS

             !;
  our $path;
  our $nms_home = nms_home();
  
  our ($bg, $check_event);
  our $mode = 'normal';
  our $threshold = 300;
  Getopt::Long::GetOptions (
      'p=s' => \$bg,
      'e=s' => \$check_event,
      't=i' => \$threshold,
      'm=s' => \$mode,
  ) or usage();
  usage()
  unless ((defined $bg && $bg =~ /^bg[0-9]?$/i) &&
          (defined $check_event && $check_event =~ /^oom|disc$/i) &&
          (defined $threshold && $threshold =~ /^[0-9]+$/) &&
          (defined $mode && $mode =~ /^normal|fancy_restart$/i));

#
#
#  Initialize our utilities, and application state...
#

  our %queue;
  our %queue_match;
  our $queue_path = "$path/queue/";
  our $last_queue_file;
  our $ts_of_match;
  our $recovered_time;
  our $min_timestamp;

  my $current_time = $debug && defined $override_current_time
                     ? $override_current_time
                     : time;
  $current_time = get_epoch_time $current_time unless $current_time =~ /^[0-9]+$/;
  $min_timestamp = $current_time - $threshold;

  our $log = Logger->new("$path/log/log_driver-$bg.log");
  $log->rotateLogs();

  my $oom_match        = 'outofmemory';
  my $db_disc          = 'exception due to db connection failure';
  my $bg_restarted     = 'clarity background [0-9\.]+ ready';
  my $bg_restarted_alt = "event manager started succe[s]{1,2}fully";

  $_ = $check_event;
  my $event = /disc/i ? "DATABASE DISCONNECT" : "OUT OF MEMORY EXCEPTION";
  my $check_expr = /disc/i ? $db_disc : $oom_match;

  our $working_log;
  if ($debug && defined $override_bglog) {
      $working_log = $override_bglog
  } else {
      $working_log = get_proglog ($bg, ($check_event =~ /^oom$/i ? 'system' : 'main'));
  }
  my ($wl_filename) = ($working_log =~ m{([^/]+)$});
  log_n_quit "ERROR: Failed to find bg log [".($working_log||"<NULL>")."], none were found for this check event [$check_event]"
    unless $working_log && -f $working_log;
  $mode = $debug_mode if defined $debug_mode;
  import_queue;

#
#      Workflow executor
#
#  ** In "normal" mode, we raise alarm and exit at 'Condition Found' (#1) below

  if (CHECK_FOR_OOM_OR_DISC || THERES_PENDING_RESTART_CHECKS) {    #1
      if (ALREADY_TRIED_TO_RESTART) {

          if (IT_RESTARTED_SUCCESSFULLY) {
             SUCCESS_WERE_DONE
          }
          elsif (WE_HAVENT_HIT_3_ATTEMPTS) {
             RESTART_BG_AGAIN
          }
          else {
             IM_DONE_TRYING
          }
      }
      elsif (IT_RESTARTED_SUCCESSFULLY) {
        SUCCESS_WERE_DONE
      }
      else {  # I_HAVENT_TRIED_TO_RESTART_YET
         RESTART_BG
      }
  }


  exit 0;



#
#
#   Workflow Handling Routines
#
#

  sub CHECK_FOR_OOM_OR_DISC {
      $ts_of_match = search_log ($working_log, $min_timestamp, $current_time, $check_expr, $log);
      log "Error: An unknown error occurred while looking for check event [$check_event] in log [$working_log]"
        unless defined $ts_of_match && ($ts_of_match == 0 or $ts_of_match =~ /^[0-9]{2,}$/);
      if ($ts_of_match == 0) {
          #log "No new matches for check event [$event] found" if $debug;
          return undef;
      }
      if ($mode eq "normal") {
        log_n_stdout "CRITICAL_DB: BG [$event] DETECTED - [$bg] @ [" . get_fmtd_time($ts_of_match) . "]";
        exit 0;
      }
      queue_match;
      last_queue_file;
      IT_RESTARTED_SUCCESSFULLY
      return $ts_of_match;
  }

  sub ALREADY_TRIED_TO_RESTART {
      return (defined $queue_match{timestamp} ? 1 : 0);
  }
  sub RESTART_BG_AGAIN {
      RESTART_BG;
  }

  sub IM_DONE_TRYING {
      delete_queue_files;
      tell_bg      "" . get_fmtd_time( time() ) . " [NSM CLR_12_13]: CRITICAL_DB RAISED: $event FOUND AND MAX RESTART ATTEMPTS REACHED";
      log_n_stdout "CRITICAL_DB: BG RESTARTED UNSUCCESSFULLY FROM [$event] - [$bg] @ [" . get_fmtd_time($ts_of_match) . "]";
  }

  sub RESTART_BG {
      restart($bg);
      update_queue_file;
      my $fmtd_ts = get_fmtd_time($ts_of_match);
      my $count = $queue_match{restart_count} || 0;
      $count++;
      my $msg =   "" . get_fmtd_time( time() ) . " [NSM CLR_12_13]: $event DETECTED WITH TIMESTAMP [" .
                  $fmtd_ts . "], ATTEMPTING BG RESTART [ Attempt $count of 3 ]";
      tell_bg $msg;
      log_n_quit $msg;
  }

  sub THERES_PENDING_RESTART_CHECKS {
      return ( last_queue_file );
  }

  sub SUCCESS_WERE_DONE {
      delete_queue_files;
      tell_bg      "" . get_fmtd_time( time() ) . " [NSM CLR_12_13]: BG RESTARTED SUCCESSFULLY FROM [$event]";
      log_n_stdout "INFO_DB:  BG RESTARTED SUCCESSFULLY FROM [$event] - [$bg] @ [" . get_fmtd_time($ts_of_match) . "]";
  }
  sub IT_RESTARTED_SUCCESSFULLY {
      $recovered_time = search_log ($working_log, $ts_of_match, undef, $bg_restarted, $log);
      unless ($recovered_time) {
        $recovered_time = search_log ($working_log, $ts_of_match, undef, $bg_restarted_alt, $log);
        log "Error: An unknown error occurred while looking for BG Restart message for [$check_event] in log [$working_log]"
        unless defined $recovered_time && ($recovered_time == 0 or $recovered_time =~ /^[0-9]{2,}$/);
      }
      return $recovered_time
  }

  sub WE_HAVENT_HIT_3_ATTEMPTS {
      return $queue_match{restart_count} < 3 ? 1 : 0;
  }


#
#
#   Queue Manager Routines
#
#
  sub last_queue_file {
    return undef unless scalar (keys %queue);
    $last_queue_file = ( sort keys %queue )[-1];
    $ts_of_match = $queue{$last_queue_file}->{timestamp};
    queue_match;
    return $last_queue_file

  }

  sub queue_match {
      foreach (keys %queue) {
        if ($queue{$_}->{timestamp} eq $ts_of_match) {
          $queue_match{filename}  = $_;
          $queue_match{timestamp} = $queue{$_}->{timestamp};
          $queue_match{restart_count} = $queue{$_}->{restart_count};
        }
      }
  }

  sub import_queue {
      my $prefix = lc $check_event;
      opendir Q, $queue_path;
      my @q = readdir(Q);
      return 1 unless scalar @q > 0;
      foreach my $file (@q) {
          chomp($file);
          next unless $file =~ /^$prefix\-$wl_filename\-([0-9]+)\-([0-9]{1})\.q$/;
          # Delete queue files great than 1 hr old
          my ($ts,$rc) = ($1,$2);
          unless ($ts >= $current_time - 3600) {
            unlink "$queue_path/$file";
            next;
          }
          $queue{$file} = {
             timestamp     =>  $ts,
             restart_count =>  $rc,
          };
      }
      1;
  }

  sub update_queue_file {
      if (defined $queue_match{filename}) {
        my $full_path = "$path/queue/$queue_match{filename}";
        unlink $full_path if -f $full_path;
        return 1 if $queue_match{restart_count} == 3;
      }
      my $count = $queue_match{restart_count} || 0;
      $count++;
      my $file = $path . "/queue/" . (join '-', (lc $check_event,$wl_filename,$ts_of_match,$count)) . ".q";
      `echo "[$file]" > $file`;
  }

  sub delete_queue_files {
      unlink "$queue_path/$_" foreach keys %queue;
  }

#
#
#
#   Notification routines
#
#
#
#
  sub tell_bg {
      my $msg = shift;
      my $log = shift if @_;
      $log ||= $working_log;
      `echo "" >> $log`;
      `echo "$msg" >> $log`;
      `echo "" >> $log`
  }

  sub log_n_stdout {
      log @_;
      print STDOUT "@_\n";
  }

  sub log {
      my @msg = @_;
      $log->write(@_);
      # Send to logmon.log
      my $one_liner = "" . get_fmtd_time( time() ) . ": ";
      $one_liner .= join ' ', @_;
      `echo "$one_liner" >> $nms_home/probes/system/logmon/logmon.log`;
  }

  sub log_n_quit {
      log @_ if $debug;
      exit 0;
  }

  sub usage {
      my @params = (
                    '-p <program>               (ex: bg, bg2)',
                    '-e <check_event>           (ex: "OOM" for OutOfMemory error processing, "DISC" for database disconnect processing)',
                    '[ -t <threshold_seconds> ] (OPTIONAL ex: 300 - Log time comparison threshold, default=300)',
                    '[ -m <mode>  ]             (OPTIONAL ex: normal, fancy_restart - Determines if program will attempt to restart bg, default=normal)'
                   );
      print STDERR "usage: ./log_driver.pl [Options]\n" . ((" ") x 7) . "Options:\n";
      print STDERR "" . ((" ") x 10) . $_ . "\n"foreach @params;
      exit 1;
  }


