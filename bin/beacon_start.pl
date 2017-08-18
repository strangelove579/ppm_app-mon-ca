#!/usr/bin/perl -w
# beacon_start.pl
# Ramu Boga, 08/14/2017

use strict;
use Getopt::Long;

my ( $process,$action );
Getopt::Long::GetOptions (
                'p=s' => \$process,
                'a=s' => \$action
) or usage();

usage()
unless ((defined $process && $process =~ /^beacon$/i) &&
(defined $action && $action =~ /^start$/i));

beacon_status($process,$action);

##
# sub beacon_status
# $process - Process Name
# $action - Process Status
##
sub beacon_status {
	($process, $action ) = @_;
	my $cmd = qq { su - clarity1 -c "service $process status" };
	my @cmd_out = qx { $cmd };
	if ( grep { /not\s*running/ } @cmd_out ){
	    print "CRITICAL: \u$process process is not running...!\n";
		beacon_start($process,$action);
	}else{
		print "\u$process process is already running...!\n";
	}
}

##
# sub beacon_start
# $process - Process Name
# $action - Process Status
##
sub beacon_start {
($process,$action) = @_;
	my $i = 0;
	BEACON:
	while(1){
		if ( $i > 2 ){
			print "CRITICAL: Failed to restart the \u$process process after $i attempts...!\n";
			exit 1;
		}
		my $cmd = qq { su - clarity1 -c "service $process $action" };
		my @cmd_out = qx { $cmd };
		if ( $?>>8 == 0) {
			if ( grep {  /running\s*:\s*pid\s*:\s*\d+/i } @cmd_out ){
				print "INFORMATION: \u$process process successfully restarted...!\n";
				exit 0;

			}else{
				print "Failed to restart \u$process process attempting [$i]...\n";
				$i++;
				next BEACON;
			}
		}else{
			# If we are unable to run the $cmd due to some permission or OS issue we need 
			# to exit the while loop.
			print "CRITICAL: Failed to run the $cmd\n";
			exit 1;
		}
	}
}

##
# sub usage
##
sub usage {
        my @params = (
                '-p <program>               (ex: process)',
                '[ -a <action>]             (ex: start)'
        );
        print STDERR "usage: ./beacon_start.pl [Options]\n" . ((" ") x 7) . "Options:\n";
        print STDERR "" . ((" ") x 10) . $_ . "\n"foreach @params;
        exit 1;
}
