#!/fs0/od/perl/bin/perl

#  ./versions.pl
#  NMS Versions -
#    Takes a Nimsoft "versions.txt" and prints a distinct
#    list of all packages installed
#
#    * Sorted by last install date (oldest to newest)
#    * 'Version' is the Package's version of the most recent install
#    * 'Identified by' is the package section used to identify the install details
#    * Windows compatible
#
#  John Achee, 07/10/13
#
#

use strict;
use warnings;
use v5.10;
use Class::Struct;
use Time::Piece;

struct( Package =>
  [ name         => '$',
    version      => '$',
    section      => '$',
    installed_on => 'Time::Piece', ]
);

my $precedent = sub {
    local $_ = shift;
    return /^generic|all|general|common$/i ? 4 :
           /^(linux|windows|win_?\d+)$/i   ? 3 :
           ! /-cfg$/i                      ? 2 : 1;
};

my $nms_versions = $ARGV[0] // '';

open (FH, "<", $nms_versions)
    || die "Couldn't open versions.txt [ $nms_versions ] $!";

my %pkgs;

while (<FH>) {
    chomp;
    next if /^\s*$/ or /^\s*#/;
    my ($datestr,$full_pkg_section,$version) = split /:/;
    my ($package,$section) = ($full_pkg_section =~ m{^(\S+)\s-\s(.*?)$});

    my $installed_on = Time::Piece->strptime($datestr,'%m-%d-%Y');
    if (! exists $pkgs{$package}) {
        $pkgs{$package} = Package->new( name         => $package,
                                        version      => $version,
                                        section      => $section,
                                        installed_on => $installed_on,
        );

    } elsif ($precedent->( $section ) >= $precedent->( $pkgs{$package}->section() )) {
        for ($pkgs{$package}) {
            $_->version($version);
            $_->section($section);
            $_->installed_on($installed_on);
        }
    }
}

printf "%-15.15s  %-25.25s  %-25.25s %s\n", qw/Last_Installed Package Identified_by Version/;

foreach my $name (
    sort {     $pkgs{$a}->installed_on->epoch
           cmp $pkgs{$b}->installed_on->epoch } keys %pkgs
)
{
    printf "%-15.15s  %-25.25s  %-25.25s %s\n",
      $pkgs{$name}->installed_on->mdy("/"),
      $name,
      $pkgs{$name}->section,
      $pkgs{$name}->version;
}
exit 0;
