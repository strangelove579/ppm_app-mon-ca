#!/usr/bin/perl
use lib qw'/fs0/od/nimsoft/probes/super/ppm_app/lib';
use TZSnapShot;
my $tzs = TZSnapShot->new('/fs0/od/nimsoft/probes/super/ppm_app/config/tz.cfg');
$_ = $ARGV[0];
my ($old_tz, $new_tz, $old_offset, $new_offset) = ($tzs->ss_tz(), $tzs->tz(), $tzs->ss_offset(), $tzs->offset());
if (/--set/) {
  $tzs->take_snapshot();
  print "Snapshot taken. Timezone now: $new_tz [$new_offset]\n";
} elsif (/--get/) {
  my $changed = $tzs->has_changed();
  print "Timezone has changed. Was: $old_tz [$old_offset], is now: $new_tz [$new_offset]\n" if $changed;
}
