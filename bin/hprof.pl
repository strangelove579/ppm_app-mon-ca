#!/fs0/od/perl/bin/perl

#
#  PHD Java heap dump discovery and staging script
#  1. Discovers new heap dumps
#  2. Zips hprof files
#  3. Copies environment details to file for reading by PHD
#
#  John Achee
#  Rev 1.1 - 9/13/2013
#

use lib qw{/fs0/od/nimsoft/probes/super/ppm_app/lib};
use FileHandle;
use Fcntl;
use subs qw/LOG DEBUG ERROR FATAL/;
use Sys::Hostname;
use Logger;
use Try::Tiny;

my $debug = @ARGV || '0';

my $app_path = '/fs0/od/nimsoft/probes/super/ppm_app';


# Initialize log
my $log = new Logger ("$app_path/log/hprof.log");
$|++; # autoflush



# Exit if I'm already running...theres only room for one of us in this town! :*(
my $pid = $$;
my ($proc) = `ps -ef | grep -iP "fs0/od/perl/bin/perl.*hprof" | grep -v grep | grep -v "$pid"`;
unless ($?) { print "Already running [$?] so exiting"; exit; }




# Gather some environment information which we will pass along to PHD...
my ($hostname) = (hostname =~ /^(\w+)/);
my ($env,$type,$fh);

DEBUG "About to read environment details from robot config";
my $rbt_cfg    = "/fs0/od/nimsoft/robot/robot.cfg";

$fh = FileHandle->new;

if ($fh->open("< $rbt_cfg")) {
    while (<$fh>) {
        chomp;
        $env  = $1 if /os_user2\s*=\s*(.*?)\s*$/;
        $type = $1 if /os_user1\s*=\s*(.*?)\s*$/;
    }
    $env  ||= 'Not defined';
    $type ||= 'Not defined';
    $fh->close;
} else {
    ERROR "Failed to open robot.cfg for read";
}
DEBUG "Done, found [$env], [$type].";





# Configuration and bit-buckets for the below heap processing operations
my %cfg = ( zip_delay => 300, sleep_time => 60, del_logger_after => 1 );
my %heaps;
my %tot = ( success => 0, failed => 0 );

my $heapdir    = "/fs0/clarity1/clarity/logs";
#my $heapdir = '/tmp';

# Default heap (and related file) properties
my %file_props = ( uid => 601, gid => 263723754, mode => 0644 );


# And away we go....

chdir($heapdir) or do  {
    FATAL "Failed to change directory to [$heapdir]. Cannot continue...";
};


while (1) {

#
# Heaps that are found, become queued for processing so that we do not accidentally
# start the zip operation while it is still dumping. We wait to see that the file isn't growing
# in 5 min interval checks (300s)
#
####################################################################################################


#
# 1.  Open Clarity log directory, search for new heaps to process...
#---------------------------------------------------------------------------------------------------
#


    DEBUG "About to open Clarity logs directory [$heapdir]";


    opendir (my $d, $heapdir) or do {
        FATAL "Unable to open [$heapdir] for read: $!";
    };

    DEBUG "Directory open, reading files";
    $counts{found} = 0;

    foreach my $heap (grep /hprof$/i, readdir($d)) {
        next if exists $heaps{$heap};
        next if -M $heap > 7;
        next if -f "$heap.gz";

        LOG "Found heap file less than 1 day old, not yet zipped. Watching to see that its not still dumping... [$heap]";
        $counts{found}++;
        $heaps{$heap} = {
            file       => $heap,
            tmpname    => ".${heap}.tmp",
            tmpzip     => ".${heap}.tmp.gz",
            zipfile    => "$heap.gz",
            logger     => ".$heap.gz.log",
            size       => -s $heap,
            next_check => time() + $cfg{zip_delay},
            found_on   => time()
        };

    }
    DEBUG "[$counts{found} new heaps found for processing, added to queue...";

#
#  2.  Run a 2nd pass through the logs directory, and make sure any *hprof* files have the appropriate
#      ownership and permissions set...
#---------------------------------------------------------------------------------------------------
#

    DEBUG "Rewind directory and look for any *hprof*, and make sure its stats (uid,gid,permissions) are all accurate";

    rewinddir($d);

    foreach my $file (grep /hprof/i, readdir($d)) {

        DEBUG "Found file for stats update: $file";

        my @stats = get_stats($file);
        set_stats(@stats,$file);

        DEBUG "Removing any out-dated loggers that PHD didnt pick up";
        unlink $file if $file =~ /hprof\.gz\.log$/ && -M $file > 7;
    }
    closedir $d;







#
#  3. Check on heaps pending zip operation...and execute zip when ready
#---------------------------------------------------------------------------------------------------
#
    PENDING_HEAPS:
    foreach my $heap (keys %heaps) {

        # Get size and the timestamp from when it was last checked
        my ($size,$chk,$found) = @{$heaps{$heap}}{qw/size next_check found_on/};

        # Skip if were not ready to check yet... (currently this is a 300 second check interval)
        next unless $chk < time();


        LOG "Checking back in, to see if heap is ready for zip: $heap";

        # Verify our heap file hasn't disappeared on us..
        unless ( -e $heap ) {
            $tot{failed}++;
            ERROR "Ooops, it disappeared on us. Removing it from the queue";
            delete $heaps{$heap};
            next PENDING_HEAPS;
        }

        # If size has not increased since the last check, the heap is no longer dumping and we
        # can go ahead and zip it up
        my $newsize = -s $heap;

        if ( $size != $newsize ) {
            LOG "[$size] != [$newsize]: Size is still growing, we'll check back in another " . (int($cfg{zip_delay} / 60)) . " min";
            $heaps{$heap}{next_check} += $cfg{zip_delay};
            $heaps{$heap}{size}       = -s $heap;
            next PENDING_HEAPS;
        }

        LOG "Heap size has not changed in the past ". (int($cfg{zip_delay} / 60)) . " min";
        LOG "Zipping file...";

        # run zip routine
        my $zipped = do_packaging( $heaps{$heap} );

        # zip routine failed, count this as a failed attempt, and try again after (300) sec.
        unless ($zipped) {
            DEBUG "Packaging for heap $heap failed with status [$rv]";
            $tot{failed}++;
            $heaps{$heap}{next_check} += $cfg{zip_delay};
            $heaps{$heap}{size}       = -s $heap;

        # else, we zipped successfully, count it as a successful attempt and delete
        # the heap record from our hash. were done with it.
        } else {
            $tot{success}++;
            my $del = delete $heaps{$heap};
            DEBUG "Deleted heaps [$del]";
        }
    }


    # Stay alive if we have heaps waiting to be processed...

    last unless keys %heaps;
    DEBUG "Taking a quick nap, brb";

    sleep $cfg{sleep_time};
    DEBUG "Im awake! Im awake!";
}

LOG "Finished processing heaps, with $tot{success} successful and $tot{failed} failed"
  if $tot{success} || $tot{failed};


exit 0;


sub do_packaging {
    my $heap = shift;

    # Compile the properties of the file we're about to mangle..i mean zip.
    my @stats = get_stats($heap->{file});
    $heap->{stats} = \@stats;

     # First, rename (HIDE) the heap so that it is not tampered with during this operation
    rename $heap->{file}, $heap->{tmpname};

    DEBUG "Heap tentantively renamed so that it is not fiddled with while we work....";
    my $rv = set_stats(@stats,$heap->{tmpname});

    try {


        DEBUG "Zipping heap [". $heap->{tmpname} . "]";
        my $tmp = $heap->{tmpname};
        my $res = qx{/usr/bin/gzip -f $tmp};
        my $status = $? >> 8;

        if ($status == 0 && -f $heap->{tmpzip}) {

            LOG "File [$heap->{file}] was successfully zipped, releasing file to PHD";

            rename $heap->{tmpzip}, $heap->{zipfile};
            DEBUG "Renamed $heap->{tmpzip} to $heap->{zipfile}";

            #@{ $heap->{stats} }
            set_stats(@{ $heap->{stats} }, $heap->{zipfile});

            my $fhl = FileHandle->new($heap->{logger},O_RDWR|O_TRUNC|O_CREAT);
            my $info = qq{"$hostname","$env","$type"};
            print $fhl "$info\n" if defined $fhl;
            undef $fhl;

            set_stats(@{ $heap->{stats} }, $heap->{logger});

            DEBUG "Created logger [$heap->{logger}]";

            if (-e $heap->{file}){
                LOG "File $heap->{file} was zipped but was not automatically removed";
            }

        } else {
            ERROR "Attempt to zip file [$file] failed with: $status $! [$res]";
            $heap->{next_check} += 600;

        }

    } catch {
       ERROR "An error occurred trying to zip heap dump [$file]. Will reattempt to process the file in ". (int($cfg{zip_delay} / 60)) . " min";
       $heaps{$file}{next_check} += $cfg{zip_delay};

    };


    1;


}



sub get_stats {
    my ($atime,$mtime) = (stat($_[0]))[8,9];

    my ($uid,$gid,$mode) = (@file_props{qw/uid gid mode/});

    my @ret = ($uid,$gid,$mode,$atime,$mtime);

    return wantarray()? @ret : \@ret;

}

sub set_stats {
    my ($uid,$gid,$mode,$atime,$mtime,$file) = @_;
    return undef unless -f $file;

    $mode = sprintf ( "%04o", $mode & 0777);
    DEBUG "Setting mode to $mode on file [$file]";

    chmod oct($mode), $file
      or ERROR "Failed to chmod [$file]: $!";

    DEBUG "Setting uid,gid to $uid,$gid on file [$file]";

    chown $uid, $gid, $file
      or ERROR "Failed to chown [$file]: $!";

    DEBUG "Setting atime,mtime to $atime,$mtime on file [$file]";

    utime($atime, $mtime, $file)
      or ERROR "Couldnt set atime and mtime for [$file]: $!";
    1;

}

sub copy_stats {
    my ($src,$dest) = @_;
    my @stats = get_stats($src);
    return set_stats( @stats, $dest );
}


sub DEBUG { return 1 unless $debug; LOG "DEBUG: @_" };
sub FATAL { LOG "FATAL: @_"; exit 1; }
sub ERROR { LOG "ERROR: @_" }
sub LOG   { $log->write(@_) }
