package Logger;

use Sys::Syslog qw( :DEFAULT setlogsock);


sub new {
  my $class = shift;
  $class = ref($class) ? ref($class) : $class;
  my $self = {};
  $self->{FILENAME} = scalar @_ > 0 ? shift : undef;
  $self->{MAX_LOG_SIZE} = scalar @_ > 0 ? shift : 1000000;

  $self->{ERROR} = "";
  bless $self,$class;
  return $self;
}

sub filename {
  my $self = shift;
  $self->{FILENAME} = shift if @_;
  return $self->{FILENAME};
}



sub _sysLogMsg {
  my $msg = shift || "Generic failure";
  setlogsock("unix");
  my ($pgmname) = ($0 =~ m'([^/]+)$');
  openlog("$pgmname", "", "user");
  syslog("info","$msg");
  closelog;
}



sub _open {
    my $filename = shift;
    my $openFail = "Failed to open log file $filename";
    my $LOG = shift;
    foreach my $i (1..100) {
        eval {
		    (my $logdir = $filename) =~ s/\/[^\/]*$//;
             mkdir $logdir, 0775 unless -d $logdir;
             open ($LOG, " >> $filename") || die "$!";
        };

        if ($@) {
            print $openFail ." trying again in 30 seconds\n";
            sleep(30);
        }
        else {
            return $LOG;
        }
    }
    _sysLogMsg($openFail);
    die "$openFail, tried 100 times in 30 sec intervals. Done trying...";
}

sub logSize {
  my $self = shift;
  return ( -s $self->{FILENAME} );
}

sub error {
  my $self = shift;
  return $self->{ERROR};
}

# Rotate log if it grows beyond 5 mb
# Keep 5 backup logs

sub rotateLogs {
  my $self = shift;
  my $max_log_size = scalar @_ > 0 ? shift : $self->{MAX_LOG_SIZE};

  my $current_log = $self->{FILENAME};
  return undef unless -f $current_log;

  my @log = map { "$current_log.$_" } (1..5);

  if ((-s $current_log) > $max_log_size) { # 5 MB
		unlink $log[4] if -e $log[4];
		my $i = @log;
		while ( $i-- ) {
			rename $log[$i], $log[$i+1] if -e $log[$i];
		}
		rename $current_log, $log[0] if -e $current_log;
		qx(touch $current_log);
  }
  return 1;
}

#
#  write() - writes a line or lines to the log.  If the first parameter passed in is an ARRAY ref, then the
#  ARRAY contents are written, otherwise all of the parameters are considered as text, and are written to the
#  log.  This method uses the "flock()" function...  it probably will not function properly under Windoze
#

sub write {
  my $self = shift;
  my $msg;
  my $screen_msg;
  my $LOG;

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  my $timestamp = sprintf("[%4.4d-%2.2d-%2.2d %2.2d:%2.2d:%2.2d]",
                     $year+1900, $mon+1, $mday, $hour, $min, $sec);
  return undef unless @_;
  unless ($self->{FILENAME}) {
    $self->{ERROR} = "Error: filename must be set before attempting write()";
    return undef;
  }

  $LOG = _open($self->{FILENAME},$LOG);

  select $LOG;
  $|++;
  select STDOUT;
  $|++;

  unless ( flock($LOG, 2) ) {
    $self->{ERROR} = "Error obtaining exclusive flock on $self->{FILENAME}: $!";
    return undef;
  }

  if ( (scalar @_ == 1) && (ref($_[0]) =~ m/ARRAY/) ) {
	$screen_msg = $_[0] . "\n";
	$msg = join "", (map {"$timestamp $_\n"} @{$_[0]});
  } else {
	$screen_msg = join "", (map { $_ . "\n"} @_);
	$msg = join "", (map {"$timestamp $_\n"} @_);
  }
  print $LOG $msg;

  close $LOG;
  return 1;
}

sub DESTROY {
  my $self = shift;
  $self->rotateLogs();
}

1;

