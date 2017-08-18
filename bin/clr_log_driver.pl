#!/usr/bin/perl
# 
#   clr_log_driver.pl
#  
#   Automatic BG OOM and DB Disconnect restarts
#   App OOM alarm notification, with Tanuki Wrapper restart notifier
#
#   Auth: John Achee
#
#      Maintenance History
#      -------- ----------- ------------------------------------------------
#      achjo03  05/15/2013  Created. (R.2.0)    
#
#
BEGIN {

    our $APP_PATH = "/fs0/od/nimsoft/probes/super/ppm_app";
    push @INC, "$APP_PATH/lib";
}

our $debug           = 0;
our $debug_logsearch = 0;

our %dbg;

DEBUG_OVERRIDES:
{
    %dbg = (
        program      => 'app',
        clr_log      => "/home//clr_19/app-system.log",
        current_time => '2013-05-19 13:41:04',

        #current_time  => '2013-05-19 13:46:04',
        #current_time  => '2013-05-19 13:51:04',
        #current_time  => '2013-05-19 13:56:04',
        #current_time  => '2013-05-19 14:01:04',
        #current_time  => '2013-05-19 14:06:04',
        #current_time  => '2013-05-19 14:11:04',
        os        => 'linux',
        condition => 'oom',
        threshold => 300,
    );
}

use strict;
use warnings;
use Getopt::Long ();
use File::Basename;
use Logger;
use ClrUtils
qw/ nms_home      clarity_version
    restart       get_proglog
    search_log    validate_attr
    get_fmtd_time get_clarity_pid
    niku_home     get_epoch_time/;

use constant SAVED_STATE_ATTRS =>
qw/ OCCURRED_ON
    MIN_RESTART_TIME
    NEXT_INSTRUCTION
    WAIT_CT
    RESTART_CT/;

select STDOUT;
$|++;

our $APP_PATH;

our $nms_home = nms_home();

our (
    $override_clr_log, $override_current_time,
    $clarity_process,  $alarm_condition,
    $threshold,        $clr_log_type,          $clarity_process_log,
    $clarity_log_dir
);

# Override restarts for particular clarity process types
my %allowed_restarts = (
    app_restart_allowed => 0,
    bg_restart_allowed  => 1,
);

# For clarity environments using the tanuki wrapper, we will give it up to 2 cycles (10 min)
# to restart on its own, if we find it trying to do so ...
my $max_tanuki_waits = 2;



#
#  Various log entries we're interesting in checking for
#
my %log_entries = (
    oom           => 'outofmemory',
    disc          => 'exception due to db connection failure',
    recovered     => 'clarity .*?[0-9\.]+ ready',
    recovered_alt => 'event manager started succe[s]{1,2}fully',
    tanuki        => 'dumping heap',
);



#
#
# Create some simple closures for some of the busy logging work
#
my $log_n_stdout  = logger_prototype( undef, 1 );
my $this_log      = logger_prototype( undef, 0, 1);




#
#
# Create some simple closures for alarm definitions
#

my %ALARM = (
    restarted_by_me => alarm_prototype(
        is_restarter => 1,
        restarted    => 1,
        restarted_by => 'me'
    ),
    restarted_by_tanuki => alarm_prototype(
        is_restarter => 1,
        restarted    => 1,
        restarted_by => 'tanuki'
    ),
    restart_failed => alarm_prototype( is_restarter => 1, restarted => 0 ),
    alarm_only     => alarm_prototype( is_restarter => 0 ),
);


#
#
#  Setup application default settings, override with user-input and debug settings
#
#


APPLICATION_DEFAULTS:
{

    $threshold = $debug && $dbg{threshold} ? $dbg{threshold} : 300;

    $clarity_process = $debug && $dbg{program}   ? $dbg{program}   : undef;
    $alarm_condition = $debug && $dbg{condition} ? $dbg{condition} : undef;

    Getopt::Long::GetOptions(
        'p=s' => \$clarity_process,
        'e=s' => \$alarm_condition,
        't=i' => \$threshold,

    ) or usage();



    usage()
      unless (
           ( defined $clarity_process && $clarity_process =~ /^(app|bg)[0-9]?$/i )
        && ( defined $alarm_condition && $alarm_condition =~ /^oom|disc$/i )
        && ( defined $threshold       && $threshold       =~ /^[0-9]+$/ ));

}

our $os =
    $debug && defined $dbg{os}
  ? $dbg{os}
  : $^O;

#
#
#  Get a friendly name for our alarm condition (oom, db_disc)
#
our $event =
  $alarm_condition =~ /disc/i
  ? "DATABASE DISCONNECT"
  : "OUT OF MEMORY EXCEPTION";


#   Statefulness -
#
#   We keep track of past restart attempts, and clarity's own 'automated' restart by tracking
#   this in a 'state file', allowing this script to be state-ful.
#
#   State-file is created when an alarm condition occurs and an action is performed that needs
#   to be acted upon, on the next run, such as a restart.
#
#   State-file is deleted on each read, and recrated as needed

our $state_file =
  "$APP_PATH/config/${clarity_process}_${alarm_condition}_state_file";

our %state = get_saved_state($state_file);
%state = () unless scalar keys %state;

#
#  Define our date range for starting and ending log search period
#

my $now =
  $debug && defined $dbg{current_time}
  ? get_epoch_time $dbg{current_time}
  : time;

our $std_threshold = $now - $threshold;



mkdir "$APP_PATH/log" unless -d "$APP_PATH/log";

our $log = Logger->new("$APP_PATH/log/log_driver.log");
$log->rotateLogs();




#  Clarity log selection
#
#  Choose the clarity log to work with. This could be a bg log
#  or app log, and depending on the alarm condition, and operating
#  system teype, we could read the system or 'ca/niku' log
#
#
SELECT_CLARITY_LOG:
{
    if ( $debug && $dbg{clr_log} ) {
        $clarity_process_log = $dbg{clr_log};
    }
    else {
        $clr_log_type = ($os ne 'linux' || $clarity_process =~ /app/ || $alarm_condition =~ /disc/) ? 'main' : 'system';
        
#          $os eq 'linux' && $alarm_condition eq 'oom' ? 'system' : 'main';

        $clarity_process_log = get_proglog( $clarity_process, $clr_log_type );
        
        $clarity_process_log = $override_clr_log
          if $debug && defined $override_clr_log && -f $override_clr_log;
        
        #do { 
        #     $this_log->("ERROR: No valid log file found for [$clarity_process] [$clr_log_type]");
        #     exit 1;
        #} unless -f $clarity_process_log;
           
        my $clr_log_filename = basename $clarity_process_log;
        unless (defined $clarity_process_log && -f $clarity_process_log) {
          $this_log->("ERROR: Failed to find Clarity log [".($clarity_process_log||"<NULL>")."], none were found for this alarm condition [$alarm_condition]");
          exit 1;
        }
    }
}

($clarity_log_dir) = ($clarity_process_log =~ m{^(.*)/[^/]+$});

my $fix_permissions = qx{ /bin/chmod a+r $clarity_log_dir/* 2>&-  };

#
#  Create a simple closure for adding log messages to the clarity log
#  we are working with...
#
my $clarity_logger = logger_prototype($clarity_process_log);

#
#
#  The Tanuki Wrapper is expected to attempt to restart clarity
#  when it is OOM, on linux (12.1 or 12.1.1+)
#
#  We will check for its "Dumping heap" message after an alarm occurrance,
#  and if we find it, we'll let it try to restart it on its own
#
my $check_tanuki = $os =~ /linux/ ? 1 : 0;




my $restarts_qualified =
           ( $clarity_process =~ /bg/ && $allowed_restarts{bg_restart_allowed} )
        || ( $clarity_process =~ /app/ && $allowed_restarts{app_restart_allowed} ) 
     ? 1
     : 0;

my $restart_attempts = $state{RESTART_CT} || 0;

debug_vars( 'restarts_qualified', $restarts_qualified, 'check_tanuki',
    $check_tanuki, 'state_file', $state_file, %state, %allowed_restarts );

my $min_restart_time = $state{MIN_RESTART_TIME} || $std_threshold;



my ($instruction_handler) = $state{NEXT_INSTRUCTION} ? ($state{NEXT_INSTRUCTION} =~ m/^([^_]+)/ ) : ('NEW');


debug_vars( 'Instruction handler', $instruction_handler );

my ( $alarmed_on, $tanuki_invoked_on, $restarted_on, $next_instruction );


#
#  Main executable block
#  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#  Execution comes in 4 basic 'forms'. The form is determined by the content of 
#  "$instruction_handler", which is the first value saved to the state file.
#  The instruction handler determines which block is executed on the next run, after
#  an alarm condition is detected. If no condition is detected, the instruction handler
#  will have a value of "NEW" and will execute the NEW block.
#
#     NEW     - A state file does not exist, so this is a fresh check for the
#               alarm condition.
#     LAST    - We've completed our last restart attempt, or we are waiting for
#               clarity to auto-restart and we do not have restarts enabled, and
#               we've exhausted max_waits.
#     WAIT    - We are checking for successful clarity initiated auto-restart.
#               This transitions to 'RESTART' if it fails to do so after max_waits.
#     RESTART - We are checking for successful clr_log_driver initiated restart
#               success. (up to 3 restarts)
#
#

MAIN_EXECUTION:
{

    local $_ = $instruction_handler;
    my $msg = '';

    /NEW/ && do {

        # Check for alarm condition
        $state{OCCURRED_ON} = search(
            check_for             => 'ALARM_COND',
            occurring_on_or_after => $min_restart_time
        );
        # Exit out if not found
        unless ($state{OCCURRED_ON}) {
          $this_log->("Condition [$alarm_condition] not found in log [$clarity_process_log]");
          last MAIN_EXECUTION;
        }
        
        # Out of memory found, first save occurrance for mat automation
        # Get os_user data fields from robot.cfg
        
        if (lc $alarm_condition eq 'oom') {
          my @robot_cfg = qx{ grep -i os_user /fs0/od/nimsoft/robot/robot.cfg 2>&- };
          my %OS_USERS = (os_user1 => 'undefined', os_user2 => 'undefined');
          foreach (@robot_cfg) {
            chomp;
            next if /^\s*$/;
            my ($key,$val) = split /\s*=\s*/;
            next unless defined $val and $val !~ /^\s*$/ and $key =~ /os_user(1|2)/i;
            $OS_USERS{"\L$key"} = $val;
          }
          my $tracker_file = "$clarity_log_dir/${clarity_process}_oom_tracker.log";
          my $cmd = "echo \"$clarity_process $alarm_condition $state{OCCURRED_ON} $OS_USERS{os_user1} $OS_USERS{os_user2}\" >> $tracker_file";
          my $print_for_mat_auto = qx{ $cmd 2>&-;/bin/chown clarity1:app^chsadmins $tracker_file 2>&- };
          
        }        



        # Check for log entry indicating that clarity is auto-restarting
        $tanuki_invoked_on = search(
            check_for             => 'TANUKI_RESTART',
            occurring_on_or_after => $state{OCCURRED_ON}
        ) if $check_tanuki && $state{OCCURRED_ON};

        # Check to see if it has already restarted
        $restarted_on = search(
            check_for             => 'RESTART',
            occurring_on_or_after => $state{OCCURRED_ON}
        ) if $state{OCCURRED_ON};


        $state{MIN_RESTART_TIME} = $tanuki_invoked_on || $state{OCCURRED_ON};

        # If its restarted, then we're done
        if ($restarted_on) {
            $ALARM{restarted_by_tanuki}->( occurred_on => $state{OCCURRED_ON} );
        }
        # If its trying to restart, then we wait 10 minutes (2 checks)
        elsif ($tanuki_invoked_on) {
            $msg = "[NSM CLR_12_13]: [$event] DETECTED - Service appears to be attempting self recovering. Monitoring will wait 10 min before acting";
            $clarity_logger->($msg);
            $this_log->("Tanunki is attempting to restart, we will give it 10 minutes [2 checks]");
            $state{WAIT_CT}++;
            $state{NEXT_INSTRUCTION} = "WAIT_" . $state{WAIT_CT};
            update_state_file( \%state );
        }
        # If it hasn't restarted, and we are in restart mode, then perform a restart, save state, and exit
        elsif ($restarts_qualified) {

            exec_restart($clarity_process);
            $state{RESTART_CT}++;
            $state{NEXT_INSTRUCTION} = "RESTART_" . $state{RESTART_CT};
            update_state_file( \%state );
            $msg = "[NSM CLR_12_13]: [$event] DETECTED - ATTEMPTING RESTART [$state{RESTART_CT}] of [3]";
            $clarity_logger->($msg);
            $this_log->($msg);
        }
        # If it hasn't restarted, and we are NOT in restart mode, then raise an alarm and exit - dont save state
        else {
            $ALARM{alarm_only}->( occurred_on => $state{OCCURRED_ON} );
        }
        last MAIN_EXECUTION;
    };

    /LAST/ && do {
        # Check if restart was successful
        $restarted_on = search(
            check_for             => 'RESTART',
            occurring_on_or_after => $min_restart_time
        );


        if ($restarted_on) {
            # If we restarted it, print a message indicating as such
            if ($restart_attempts) {
                $ALARM{restarted_by_me}->( occurred_on => $state{OCCURRED_ON} );
            }
            # If it recovered on its own, state as such
            else {
                $ALARM{restarted_by_tanuki}->( occurred_on => $state{OCCURRED_ON} );
            }
        }

        else {
            if ($restart_attempts) {
                # If it did not restart, and we attempted restarts, then report unsuccessful restart attempts
                $ALARM{restart_failed}->( occurred_on => $state{OCCURRED_ON} );
            }
            else {
                # If it did not restart, and we did not attempt restart, then report critical alarm
                $ALARM{alarm_only}->( occurred_on => $state{OCCURRED_ON} );
            }
        }
        last MAIN_EXECUTION;

    };

    /WAIT/ && do {
        # Check if a successful restart has occurred
        my $restarted_on = search(
            check_for             => 'RESTART',
            occurring_on_or_after => $min_restart_time
        );

        my $restarted = $restarted_on && $restarted_on =~ /^\d+$/;

        # Since we are only in wait mode, then a successful restart must have been due to clarity auto-restart
        if ($restarted) {
            $ALARM{restarted_by_tanuki}->( occurred_on => $state{OCCURRED_ON} );
        }
        # If we have not successfully restarted, determine what to do next
        else {
            # If we have more time to wait for clarity auto-recovery, then save state, exit and wait
            if ( $state{WAIT_CT} < $max_tanuki_waits ) {
                $state{WAIT_CT}++;
                $state{NEXT_INSTRUCTION} = "WAIT_" . $state{WAIT_CT};
                update_state_file( \%state );
                $this_log->("Restart not yet found. Waiting 5 more minutes...");
            }
            # Otherwise, either perform a restart if we are in restart mode, or exit with critical
            else {

                if ($restarts_qualified) {

                    exec_restart($clarity_process);
                    $state{WAIT_CT} = 0;
                    $state{RESTART_CT}++;
                    $state{NEXT_INSTRUCTION} = 'RESTART_2';
                    $state{MIN_RESTART_TIME} = $now;
                    update_state_file( \%state );
                    $msg = "[NSM CLR_12_13]: [$event] DETECTED - ATTEMPTING RESTART [$state{RESTART_CT}] of [3]";
                    $clarity_logger->($msg);
                    $this_log->($msg);
                }
                else {
                    $ALARM{alarm_only}->( occurred_on => $state{OCCURRED_ON} );
                }
            }
        }

        last MAIN_EXECUTION;
    };

    /RESTART/ && do {
        # Check if a successful restart has occurred
        $restarted_on = search(
            check_for             => 'RESTART',
            occurring_on_or_after => $min_restart_time
        );
        my $restarted = $restarted_on && $restarted_on =~ /^\d+$/;

        # Since we are only in restart mode, then a successful restart must have been initiated by this script
        if ($restarted) {
            $ALARM{restarted_by_me}->( occurred_on => $state{OCCURRED_ON} );
        }
        # Restart was not successful, decide what to do next.
        # If we've reached max restarts, then alarm indicating such, else restart again.
        else {

            exec_restart($clarity_process);
            $state{RESTART_CT}++;
            $msg = "[NSM CLR_12_13]: [$event] DETECTED - ATTEMPTING RESTART [$state{RESTART_CT}] of [3]";
            $clarity_logger->($msg);
            $this_log->($msg);
            $state{WAIT_CT} = 0;
            $state{NEXT_INSTRUCTION} =
              $state{RESTART_CT} == 3
              ? 'LAST'
              : "RESTART_" . $state{RESTART_CT};
            $state{MIN_RESTART_TIME} = $now;
            update_state_file( \%state );
        }

        last MAIN_EXECUTION;
    };

}

$this_log->("Finished checking [$clarity_process_log] for [$event]");
#
#  get_saved_state( $state_file );
#
#  Routine to read-in the current state of this alarm condition check
#  (ie: are we awaiting the results of a restart initiated by us or by clarity auto-recovery?)
#
sub get_saved_state {
    my %saved_state;
    my $state_file = shift;

    $saved_state{$_} = undef foreach (SAVED_STATE_ATTRS);
    $saved_state{NEXT_INSTRUCTION} = 'NEW';
    @saved_state{ (qw/RESTART_CT WAIT_CT/) } = (0) x 2;

    if ( -e $state_file ) {

        open SVD_ST, "<", $state_file
          or do {
            die "Unable to open state file [$state_file] $!";
          };
        my $state_line = do { local $/; <SVD_ST> };
        chomp($state_line);

        close SVD_ST;
        delete_state_file($state_file);

        my @content = split ' ', $state_line;

        my $i = 0;
        $saved_state{$_} = $content[ $i++ ] foreach (SAVED_STATE_ATTRS);
        
        # Start anew if our original restart time was over 35 minutes ago
        %saved_state = () if time() - $saved_state{MIN_RESTART_TIME} > (35 * 60);

    }

    return %saved_state;
}


#
#  update_state_file( $state_hashref )
#
#  Record the current state of alarm condition recovery, to evaluate on the next check
#
sub update_state_file {
    my %state = %{ $_[0] };

    my $state_line = '';

    open ST, ">", $state_file
      or do  {
        $this_log->("ERROR: Unable to create state file [$state_file]: $!");
        exit 1;
    };

    foreach (SAVED_STATE_ATTRS) {
        $state_line .= $state{$_} . ' ';
    }
    chop($state_line);
    print ST $state_line;
    close ST;
    1;
}

#
#  delete_state_file( $state_file );
#
#  Safely, and persistently delete state file
#
sub delete_state_file {
    my $file    = shift;
    my $deleted = 0;

    DELETE_FILE:
    for ( my $i = 1 ; $i <= 6 ; $i++ ) {
        eval { $deleted = unlink $file; };
        last DELETE_FILE if $deleted;
        $this_log->("ERROR: Unable to delete state file [$file] Attempt [$i] of [6]: $@")
          if $@;
        sleep 10;
    }

    return $deleted;
}


#
#  exec_restart( $clarity_process );
#
#  Execute restart routine (from ClrUtils.pm)
#
sub exec_restart {
    my $process = shift;
    #print "calling: restart $process\n";
    restart $process;
    1;
}


#
# logger_prototype ( $external_log, $send_to_stdout, $self_only )
#
# Function template for building logger routines
#

sub logger_prototype {
    
    my $external_log   = shift || 0;
    my $send_to_stdout = shift || 0;
    my $self_only      = shift || 0;

    return sub {
        my @msg  = @_;
        my $time = get_fmtd_time( time() );
        my $one_liner = join ' ', @msg;

        $log->write(@msg) unless $external_log;
        return 1 if $self_only;

        if ( $external_log && $os =~ /linux/ ) {
            `echo "$time: $one_liner" >> $nms_home/probes/system/logmon/logmon.log`;
            `echo -n "\n$time: $one_liner\n" >> $external_log`;
        }
        print $one_liner  if $send_to_stdout;
      }
}


#
# alarm_prototype ( \%attrs )
#
# Function template for building alarm routines
#

sub alarm_prototype {
    my %p            = (@_);
    my $is_restarter = $p{is_restarter};
    my $restarted    = $p{restarted} ? $p{restarted} : 0;
    my $restarted_by = $p{restarted_by} ? $p{restarted_by} : '';
    return sub {
        my %parms       = (@_);
        my $occurred_on = $parms{occurred_on};
        my $u_clarity_process = uc $clarity_process;
        my ( $msg, $clr_log_msg );

        if ($is_restarter) {
            if ($restarted) {
                if ( $restarted_by eq 'me' ) {
                    $msg = "$u_clarity_process RESTARTED SUCCESSFULLY FROM [$event] - [$u_clarity_process] @ ["
                           . get_fmtd_time($occurred_on) . "]";
                    $clr_log_msg = "[NSM CLR_12_13]: PROGRAM RESTARTED SUCCESSFULLY FROM [$event]";
                }
                else {
                    $msg = "$u_clarity_process [$event] DETECTED, AND RECOVERED ON ITS OWN - [$u_clarity_process] @ ["
                           . get_fmtd_time($occurred_on) . "]";
                }
            }
            else {
                $msg = "CRITICAL_DB: $u_clarity_process RESTARTED UNSUCCESSFULLY FROM [$event] - [$u_clarity_process] @ ["
                       . get_fmtd_time($occurred_on) . "]";
                $clr_log_msg = "[NSM CLR_12_13]: CRITICAL_DB RAISED: $event FOUND AND MAX RESTART ATTEMPTS REACHED";
            }
        }
        else {
            $msg = "CRITICAL_DB: $u_clarity_process [$event] DETECTED - [$u_clarity_process] @ ["
                   . get_fmtd_time($occurred_on) . "]";
        }

        $log_n_stdout->($msg);
        $clarity_logger->($clr_log_msg || $msg);
      }
}



#
#
#  search ( check_for => '<TYPE_OF_MSG>' )
#
#  Pre-processor routine for scanning log file for entry by date/time range
#  (returning most recent entry timestamp)
#
#
sub search {
    my %p = (@_);
    local $_ = $p{check_for};
    my $occurring_after = $p{occurring_on_or_after};

    my $occurred_on;
    my @log_entries;

    /^RESTART/
      && do { push @log_entries, ( @log_entries{qw/recovered recovered_alt/} ) };
    /^ALARM_COND/ && do { push @log_entries, $log_entries{$alarm_condition} };
    /^TANUKI_RESTART/ && do { push @log_entries, $log_entries{tanuki} };

    debug_vars( 'search log for: ', $_ ) foreach @log_entries;

    foreach my $find_expr (@log_entries) {
        $occurred_on =
          search_log( $debug_logsearch, $clarity_process_log, $occurring_after,
            $now, $find_expr );
        last if $occurred_on && $occurred_on =~ /^\d+$/;
    }

    if ( /^RESTART/ && $occurred_on && $occurred_on > 0 ) {

        my $cond_occurred_again =
          search_log( $debug_logsearch, $clarity_process_log, $occurred_on, $now,
            $log_entries{$alarm_condition} );

        $occurred_on = 0
          if $cond_occurred_again && $cond_occurred_again > 0;
    }

    debug_vars( 'occurred_on: ', $occurred_on );
    return $occurred_on || 0;
}


#
#  debug_vars ( %hash_of_vars )
#
#  simple Data::Dumper type routine to write a hash of key/val pairs to the screen
#  for debugging

sub debug_vars {
    return undef unless $debug;
    my %p = (@_);
    print "\nDEBUG::\n";
    $p{$_} = defined $p{$_} ? $p{$_} : '<NULL>' foreach keys %p;
    printf "%-30.30s %s\n", $_, $p{$_} foreach keys %p;
}

sub usage {
    my %args = (
        -p => {
            name        => 'program',
            example     => 'app, app2, bg, bg2',
            default     => 'none',
            description => 'Clarity program abbr'
        },
        -e => {
            name        => 'event',
            example     => 'oom|disc',
            default     => 'none',
            description => 'Log driver will search for this type of event'
        },
        -t => {
            name    => 'threshod',
            example => 300,
            default => 300,
            description => 'Peroid of time (sec) which log_driver should look back, to find alarm condition occurrances'
        },
    );
    my $fmt = "%-4.4s %-10.10s %-20.20s %-10.10s %s\n";

    print STDERR "usage: $0 [Options]\n";
    printf STDERR $fmt, "Opt", "Name", "Ex.", "Default", "Desc";

    printf STDERR $fmt, $_,
      @{ $args{$_} }{ (qw/name example default description/) }
      foreach (qw/-p -e/);

    exit 1;

}
