#!/usr/bin/perl

BEGIN {
    our $path = "/fs0/od/nimsoft/probes/super/ppm_app";
    push @INC, "$path/lib";
}

use strict;
use warnings;
use ClrUtils qw/ niku_home /;
use Getopt::Long ();

my $kz_script = "/fs0/od/offering/SCRIPTS/killZombies.sh";
my ($program,$action);
my $killzombies = 0;
my $niku_home = niku_home();
my $output_path = '/dev/null';
my $path = -f "/fs0/od/bin/clarity" ? "/fs0/od/bin/clarity" : ( -f "$niku_home/bin/service" ? "$niku_home/bin/service" : "$niku_home/bin/niku" );

Getopt::Long::GetOptions (
      'p=s' => \$program,
      'k=s' => \$killzombies,
      'a=s' => \$action,
      'o=s' => \$output_path,
  ) or usage();

die usage() unless (defined $program && $program =~ /^(app|bg|beacon|nsa)/) &&
(defined $killzombies && $killzombies =~ /0|1/) &&
(defined $action && $action =~ /^(stop|start|restart)$/);

$_ = $action;
if (/restart/) {
  run_command ("su - clarity1 $path stop $program > $output_path");
  run_command ("su - clarity1 $kz_script >> $output_path") unless $path =~ /clarity$/;
  run_command ("su - clarity1 $path start $program >> $output_path");
} else {
  run_command ("su - clarity1 $path $action $program > $output_path");
  run_command ("su - clarity1 $kz_script >> $output_path") if $killzombies;
}

sub run_command {
  my $cmd = shift;

  print "Running command: $cmd\n";
  eval {
    my $timeout = 180;
    local $SIG{ALRM} = sub { die "Failed to perform service action [$action] on clarity service [$program] within [$timeout] seconds" };
    alarm $timeout;
    `$cmd 2>&1\n`;
    alarm 0;
  };
  if ($@) {
    # expand on this later
    die "$@\n";
  }
  1;
}

sub usage {
    my @params = (
                  '-p <program>     (REQ, app|app2|bg|bg2|beacon etc..)',
                  '-a <action>      (REQ, stop|start|restart)',
                  '-o <output_path> (OPTIONAL, path to send stdout/err. Default => /dev/null)',
                  '-k <0|1>         (OPTIONAL, run killzombies.sh after stop command, default 0 (no))',
                 );
    print STDERR "usage: ./clarity_action.pl [Options]\n" . ((" ") x 7) . "Options:\n";
    print STDERR "" . ((" ") x 10) . $_ . "\n"foreach @params;
    exit 1;
}

