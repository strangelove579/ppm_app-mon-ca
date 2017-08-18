#!/fs0/od/perl/bin/perl
our $debug = 1; 


use 5.010;
use strict;
use warnings;

BEGIN {
    use Cwd qw/abs_path/;
    our $ap = abs_path $0;
    $ap =~ s{/bin/[^/]+$}{};
    push @INC, "$ap/lib";
}

use File::Spec;
use STK::Writer;
use Sys::Hostname;
use STK::TimeUtils qw/toggle_format/;
use ClrUtils qw/clarity_version/;
use ClrProps;
use subs qw/ERROR/;

my $props = ClrProps->new();
my $scheduler_url = $props->scheduler_url();

&close_stderr unless $debug;   # So we dont risk logmon converting error output into unintelligible alarms..


our $niku_home = $ENV{NIKU_HOME} // $ENV{niku_home} //  '/fs0/clarity1/clarity';
our $pfile = "$niku_home/config/properties.xml";
#our $pfile = "/home/achjo03/ppm_app/samples/properties.xml";
our $ap;
our $queuefile = "$ap/log/bosvc_alarms_queued.log";
our $log        = new STK::Writer(FILENAME => "$ap/log/bosvc_monitor.log", ROTATE => 1);
our $alarm_send = new STK::Writer(FILENAME => "$ap/log/bosvc_alarms_sent.log", STDOUT => 1, ROTATE => 1);

our $alarm_queue = new STK::Writer(FILENAME => "$ap/log/bosvc_alarms_queued.log", ROTATE => 1);
our $svcs_down;

our ($savederr,$savedout);

our $get_prop = properties_parse();


MAIN:
{
    $svcs_down = get_down();
    
    if ($$svcs_down{CentralManagementServer}) {
       # BO just went down, so now our queue is unnecessary and we need to restart everything
        my @cms_process = `ps -ef | grep 'CentralManagementServer' | grep -v grep`;
        if (scalar @cms_process) { 
           $log->write("INFO: CMS process appears to be running, thus we are not restarting CMS. Please investigate issue with URL");
        } else  {
            `echo > $ap/log/bosvc_alarms_queued.log`; 
            restart_bo();    
            $alarm_queue->write('CentralManagementServer');
            exit 0;
        }
        exit;
    }
 
    my $queue = read_queue();

    if (scalar keys %$queue) {
        my %recovered = map { $_ => $$queue{$_}  } grep { ! $$svcs_down{$_} } keys %{$queue};
        my $time = time();
        foreach (keys %recovered) {
            my $failed_on = toggle_format($recovered{$_});
            my $timediff = $time - $failed_on;
            if ($timediff < (60 * 60 * 4)) {  # We dont want to alarm on a service restart that occurred
                $time = toggle_format($time); # hours ago...
                $failed_on = toggle_format($failed_on);
                my $servicename = $_ eq 'CentralManagementServer' ? "$_**" : $_;
                $alarm_send->write("$servicename was not running as of [$failed_on], and was successfully restarted by monitoring @ [$time]");
                $time = toggle_format($time);

            }
            
        }
    }
    &close_stdout unless $debug;


    foreach (keys %{$svcs_down} ) {
       last if /CentralManagementServer/;
       restart_svc($_);        
       $alarm_queue->write($_);
    }
}

exit;




sub read_queue {
    our $queuefile;
    my $queue;
    if (-f $queuefile ) { 
       open (FH, "<", $queuefile) or  ERROR "Unable to open queue file for read: $!";
    } else { 
       return {};
    }

    while (<FH>) {
      next if /^\s*$/;
      chomp;
  
      if (/^\[([^\]]+)] (.+)$/) {
           $$queue{$2} = $1;
      }
    }
    close FH;
    unlink $queuefile;
    return $queue;
}


sub restart_svc { 
   my ($server) = @_;
   my $volumename = $get_prop->(name => 'volumename', tag => 'reportserver');
   my $user = $get_prop->(name => 'username', tag => 'reportserver');
   my $pass  = $get_prop->(name => 'password', tag => 'reportserver');

   my $cmd = "/bin/su - clarity1 -c \'/bin/sh /fs0/od/CA/SharedComponents/CommonReporting3/bobje/ccm.sh " .
                     "-managedrestart localhost.${server} -cms " .
                     $volumename . " -username " . $user . " -password " . $pass ;
   $cmd .= $debug ? " \' " : " 2>&- \' 2>&- ";

   my $timeout = 60;
   eval {
        local $SIG{ALRM} = sub { die "$0: Timeout was reached while attempting to start the BO service [$server]\n" };
        alarm $timeout;
        qx{ $cmd } ;#unless $debug;
        alarm 0;
    };
    if ($@) {
        ERROR "$@";
    }
}

sub restart_bo {
  my $stopbo  = '/fs0/od/bin/boexec stop';
  my $startbo = '/fs0/od/bin/boexec start';

   my $timeout = 60;
   eval {
        local $SIG{ALRM} = sub { die "$0: Timeout was reached while attempting to start Central Management Server\n" };
        alarm $timeout;
        qx{ $stopbo  };#unless $debug;
        qx{ $startbo };
        alarm 0;
    };
    if ($@) {
        ERROR "$@";
    }
}


sub properties_parse {

    our @props = `cat $pfile`
      or ERROR "Unable to find clarity properties @ [$pfile]: $!", exit;

    chomp @props;
    local $_ = join  ' ', @props;
    my @clean = split /\/\>/;

    return sub {
      my $rt = undef;
      my %p = (@_);
      
      foreach (@clean) {
         $rt = $1 if /\s$p{name}="([^"]*)/msi;
         last if /<$p{tag}\s.*/msi;
      }
     $rt;
    }
}


sub get_down {
    my $down_svcs = {};

#    my $url = $get_prop->(name => 'schedulerurl', tag => 'webserver' );
#    my ($volumeName) = map { lc } $get_prop->(name => 'volumeName', tag => 'reportServer' )=~ m{^([^:]+)};A
    
    my $url;
    my $ppm_version = clarity_version();
    if ( $ppm_version =~ /^1[23]|14.2/ ) { 
       $url = "$scheduler_url/niku/BOServerStatus.jsp";
    } else { 
       $url = "$scheduler_url/niku/serverstatus/bostatus";
    }
    
    my @out;
    my $timeout = 60;
    eval {
        local $SIG{ALRM} = sub { die "$0: Timeout was reached while attempting to curl [$url]\n" };
        alarm $timeout;
        @out = `/usr/bin/curl --silent --connect-timeout 60 --url $url`;
#        @out = `/usr/bin/curl --silent --connect-timeout 60 --url $url | grep -iP '^(server|enabled|running)'`;
        alarm 0;
    };
    if ($@) {
        ERROR "$@";
    }
    
    chomp(@out);

    unless (scalar @out) {

#        return {} if -e "$ap/config/.boss_unverified";
        ERROR "CMS is not responding. Restarting BO...$url";
        $down_svcs->{CentralManagementServer} = time();
        return $down_svcs;

    }
    #say "$_" foreach @out;
    if ( $ppm_version !~ /^1[23]|14.2/ ) {
       my $o = shift @out;
       $o =~ s/(<br>|,)\s*/\U$1\n/mg;
       @out = split /\n/, $o;
    } 
    @out = grep { /^(server|enabled|running)/i } @out;

    my $status = join ' ', @out;

    while ($status =~ /server:(.*?)\.([^,]+),.*?enabled:\s*([^,]+),.*?running:\s*([^<]+)/gsmi) {

        my ($ssvc,$svc,$enabled,$running) = ($1,$2,$3,$4);
        #$log->write("Service: $ssvc $svc, Enabled: $enabled, Running: $running");# if $debug;
        $svc=$ssvc if($svc =~ /localhost/i);
        $svc =~ s/\s//g;
        next if $svc =~ /^central\s*manage.*/i or $svc eq 'cms';
       
        $down_svcs->{$svc} = time()
            if $running =~ /false/ && $enabled =~ /true/;

    }
    #say "$_ => $$down_svcs{$_}" foreach keys %{$down_svcs};
    return $down_svcs;

}





sub ERROR {
   $log->write("Error: @_");
}

sub close_stderr {
  our $devnull = File::Spec->devnull();
  open $savederr, ">&STDERR" or die "Couldn't save stderr $!";
  open (STDERR, ">", $devnull) || die "Couldn't redirect stderr $!";
}


sub close_stdout {
  our $devnull = File::Spec->devnull();
  open $savedout, ">&STDERR" or die "Couldn't save stdout $!";
  open (STDOUT, ">", $devnull) || die "Couldn't redirect stdout $!";
}


sub open_stderr {
  open (STDERR, ">&", $savederr) || die "Couldn't bring back stderr $!";
}



