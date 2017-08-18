package STK::Writer;

    use STK::Args;
    use vars '$VERSION';
    $VERSION = '2.00';


#   Writer.pm
#
#   John Achee
#
#   Revised 6/4/2013
#
#   Formerly 'Logger.pm', some added functionality and its a bit more useful.
#
#    * Enable/disable exclusive flocking
#    * Automated and configurable log rotation
#    * Obeys existing flocks
#    * Override exclusive flocks with Injection() Use with caution!
#    * Windoz/*nix compatible
#    * Syslog() failover on *nix
#    * Miscellaneous message decoration options,
#      such as:
#         - Message timestamping
#         - Enable/disable trailing new-line
#         - Configure how messages are printed when provided
#           in list context


    use Carp;
    use File::Copy;

    our %DEFAULTS = (
            MAX_LOG_SIZE       => 10000000, # Allow logs to grow to 10 MB by default
            MAX_LOG_FILES      => 5,        # Allow for 5 archived logs, labeled <filename>.[1-5]
            ROTATE             => 0,        # Automatic log rotation on DESTROY
                                            #      or invoke manually with rotateLogs()
            STDOUT             => 0,        # Echo message to STDOUT
            TIMESTAMPED        => 1,        # Timestamp all log entries
                                            #      does not timestamp echo's or injections
            AUTO_NL            => 3,        # Tag each message with a newline at the end
                                            #      0 = none, 1 = log only, 2 = stdout only, 3 = both
            ERROR              => '',
            MULTILINE          => 0,        # When incoming messages are separate strings, print each
                                            # on a new line.
                                            #      0 = none, 1 = log only, 2 = stdout only, 3 = both
            FLOCK              => 1,        # Flock (exclusive) before log write operations
            CSV                => 0,        # Write multi-value messages in CSV format
            CSV_DELIM          => ',',
            CSV_ENCLOSE        => '"',
            CSV_ESC            => '\\',
            PREFIX             => '',
            METHOD             => 'NORMAL',
            CYGPATH            => 'C:\\cygwin',
    );

    our %ALLOWED = map { $_ => 1 } (keys %DEFAULTS);


    sub new {
        my $class = shift;
        $class = ref($class) ? ref($class) : $class;
        my $self = {};


        $self->{FILENAME} = shift
          if @_ == 1 or @_ % 2 > 0;

        my ($valid,$junk) = hashify_trap(
                @_,
                { allowed_keys => [(keys %DEFAULTS, 'FILENAME')] }
        );
        %{$self} = (%{$self}, %DEFAULTS, %{$valid});
        $$self{"\U$_"} = $$self{$_} foreach keys %{$self};

        foreach (keys %{$junk}) {
            carp "Provided key [$_] is not valid for STK::Writer->new()\n";
        }
        bless $self,$class;
        return $self;
    }

    sub _sysLogMsg {
      return unless $^O =~ /n*x$/;
      local $/;
      my $nix_code = <<"CODE";
      use Sys::Syslog qw( :DEFAULT setlogsock );
      my $msg = shift || "Generic failure";
      setlogsock("unix");
      my ($pgmname) = ($0 =~ m'([^/]+)$');
      openlog("$pgmname", "", "user");
      syslog("info","$msg");
      closelog;
CODE
      eval ($nix_code) or return undef;

    }

    sub set {
      my $self = shift;
      my %p = (@_);
      # Check that the supplied keys are valid
      my @invalid_keys =  grep { ! exists $ALLOWED{"\U$_"} } (keys %p);

      if (@invalid_keys) {
        my $err = "ERROR: Invalid parameters supplied to Logger->new():\n";
        $err .= "$_\n" foreach @invalid_keys;
        croak $err;
      }
      # Set the new values
      map { $self->{"\U$_"} = $p{$_} } (keys %p);
      1;
    }

    sub error {
        my $self = shift;

        # Prefix any incoming error message, carp it and store it
        if (@_) {
          my $error = 'Error: ' . $_[0];
          carp "$error\n";
          $self->{ERROR} = $error;
        }
        return $self->{ERROR};
    }

    # Our own private logrotate without all the drama
    sub rotateLogs {
        my $self = shift;
        my ($f,$mf,$ms,$rotate) = @{$self}{qw/FILENAME MAX_LOG_FILES MAX_LOG_SIZE ROTATE/};
        return unless defined $f and -f $f and $rotate and -s $f >= $ms;
        # Blast the final log
        unlink "$f.$mf";
        # Shuffle logs down the tree starting at the bottom
        my $i = $mf -1;
        while (--$i) {
            move "$f.$i", "$f.".($i+1) if -e "$f.$i"
        }
        move $f, $f.'.1';
        qx(touch $f);
        1;
    }

    #
    #  write() - this function is largely moved to _dolog()
    #            and exists as just a simple interface

    sub write {
        my $self = shift;
        return undef unless @_;
        my @msg = ref($_[0]) =~ /array/i ? @{$_[0]} : @_;
        my $result;

        $result = defined $$self{METHOD} && $self->{METHOD} =~ /inject/i
        ? $self->inject(@_)
        : $self->_dolog('log',@msg);

        $result;
    }

    sub get {
       my $self = shift;
       return $self->{"\U$_[0]"} ? $self->{"\U$_[0]"}  : undef;
    }

    sub _dolog {
      my $self = shift;
      my $type = shift;
      my @msg = @_;

      unless ($self->{FILENAME}) {
            $self->error("Operation failed, filename not set");
            return undef;
       }

      my $filename = $self->{FILENAME};

      my $cmd = $_[0] if $type =~ /inject/;
      my $result = 0;


      # Make a CSV if enabled
      my ($is_csv,$sep,$enc,$esc) = @{$self}{(qw/CSV CSV_DELIM CSV_ENCLOSE CSV_ESC/)};
      my $csvline = '';
      if ($is_csv) {
        $_ =~ s/$enc/${esc}${enc}/g foreach @msg;
        $_ =~ s/(\r|\n)//g foreach @msg;
        my $joiner = $enc . $sep . $enc;
        $csvline = $enc . ( join ($joiner, @msg) ) . $enc;
        @msg = ($csvline);
        $self->set(MULTILINE => 0);
      }

      my @stdout = $self->{STDOUT} ? @msg : ();

      my $pre = $self->{PREFIX} ne '' ? '_PREFIX:' . $self->{PREFIX} : ' ';

      local $_ = $self->{MULTILINE};                    # If enabled, convert multi-value messages
      /1|3/ && do { @msg    = (join "\n", (_prefix($pre, @msg )) ) };   # to multi-line log entries
      /2|3/ &&
          scalar @stdout &&
              do { @stdout = (join "\n", @stdout) };   # <-- or terminal output


      local $_ = $self->{AUTO_NL};           # Automatically append new-line
      /1|3/ && do { $msg[-1]    .= "\n" };   # the last line of the message
      /2|3/ &&
          scalar @stdout &&
              do { $stdout[-1] .= "\n" };   # if enabled (enabled by default)


      $msg[0] = _ts_prefix($msg[0])          # Prefix message with timestamp (enabled by default)
        if $self->{TIMESTAMPED};


      my $outted = 0;
       # Its the callers responsibilty to shell quote their strings,
       # This is way out of scope for this module.

      my $i = 0;
      while (++$i) { # 10 attempts at 2 second intervals with 5 second timeout, for total attempt time of 1:10
         eval {
           local $SIG{ALRM} = sub { die "Timeout was reached in attempt to write to the log\n" };
           alarm 5;
           WRITE2LOG:
           {
             local $_ = $type;
             if (/inject/) {
              $result = qx{ $cmd };

             } elsif (/log/) {

               do {

                select STDOUT;
                $|++;
                print "@stdout";
                $outted = 1;
               } if $self->{STDOUT} && ! $outted;

                # Finally ..print something to file
                my $logdir = $filename;

                if ($^O eq 'MSWin32') {
                    $logdir =~ s/[^\\]+$//
                } else {
                    $logdir =~ s{/[^/]+$}{}
                }

                mkdir $logdir, 0775 unless -d $logdir;

                open LOG, ">>",  $filename or die "Cannot open file [$filename]$!";
                unless ($self->{FLOCK} == 0 or flock(LOG, 2) ) {
                  close LOG;
                  die "Unable to obtaining exclusive flock on $self->{FILENAME}: $!";
                }

                select LOG;
                $|++;
                select STDOUT;
                print LOG "@msg"
                 or die "$!";
                close LOG;
                $result = 1;
             };
           }
           alarm 0;
         };
         if ($@) {
           my $errm = $@;
           #carp "$@";
           #return;
           if ($i <= 11) {
             $errm .= ". Trying again, attempt [$i] of 10.";
             $self->error($errm);
             sleep 2;
             next;
           } else {
             my $syslog = "Unable to write to log after attempting for the past 1 minute. Done trying...[Error: $errm]";
             _sysLogMsg($syslog) if $^O =~ /n*x$/;
             croak "$syslog\n";
           }
         }
         last;
      }
      $result;
    }

    sub _prefix {
        my $pre = shift;
        return unless $pre =~ /_PREFIX/;
        $pre =~ s/^_PREFIX://;
        my @lines = map { "$pre $_" } @_;
        return wantarray() ? @lines : \@lines;
    }

    sub _ts_prefix {
        my $str = shift;
        my @time = reverse ((localtime(time))[0..5]);
        $time[0] += 1900;
        $time[1]++;
        my $ts = sprintf("[%4.4d-%2.2d-%2.2d %2.2d:%2.2d:%2.2d]", @time);
        return "$ts $str";
    }

    sub inject {              # For those logs that have existing exclusive flocks
       my $self = shift;      # we want to over-ride. Be nice, use with care!
       $self->{ERROR} = '';

       my @msg =   ref($_[0]) =~ /array/i
                  ? @{$_[0]}
                  : @_;
       return unless @msg;

       my $filename = $self->{FILENAME};

       do {
         $self->error('Filename must be provided before performing injection');
         return undef;
       } unless $filename;

       my $cmd;

       my $is_windoz = $^O =~ /win/i ? 1 : 0;

       # Roll the message onto 1 line
       my $msg = join ' ', @msg;
       $msg = _ts_prefix($msg)
         if $self->{TIMESTAMPED};

       if ($is_windoz) {

         my $cygwin = $self->{CYGPATH};
         my $echo = "$cygwin\\bin\\echo.exe";

         unless (-d $cygwin) {
           $self->error("Cygwin path is not defined, unable to perform log injection");
           return undef;
         }
         unless (-e $echo) {
           $self->error("Cygwin is installed, but required binaries are missing, unable to perform log injection");
           return undef;
         }
         $cmd = "$echo $msg >> $filename";
       } else {
         $cmd = "/bin/echo $msg >> $filename"
       }

       my $result = $self->_dolog('inject', $cmd);
       $result;
    }


    sub clone {
        my $self = shift;
        my %opts = hashify_secure(@_, { allowed_keys => ['FILENAME'] });
        my %clone = %{$self};
        $clone->filename($opts{FILENAME})
          if $opts{FILENAME};
        return \%clone;
    }

    sub complain {
        my $msg = shift;
        carp $msg;
    }

    sub filename {
      my $self = shift;
      $self->{FILENAME} = shift if @_;
      return $self->{FILENAME};
    }


    sub DESTROY {
        my $self = shift;
        eval {
           local $SIG{ALRM} = sub { die "Timed out rotating"; };
           alarm 10;
           $self->rotateLogs();
           alarm 0;
        } or return undef;
    }

    1;
