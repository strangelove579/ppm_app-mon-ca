# STK::TimeUtils.pm -- Standard Toolkit's Arg processing shortcuts

package STK::TimeUtils;

# Author          : John Achee
# Created On      : Sat Jun 6 15:00:12 2013
# Last Modified By: John Achee
# Last Modified On: Sat Jun 6 20:05:01 2013
# Status          : Released

################ END Module Preamble ################

use strict;
require 5.004;

our $VERSION = 1.00;

use Time::Local;
use vars qw(@ISA);
require Exporter;
@ISA = qw(Exporter);



our @EXPORT = qw(
     toggle_format
);
our @EXPORT_OK;

# Toggles a timestamp between a pretty format date, and epoch format

sub toggle_format {
      
      local $_ = shift;
      my $opts = shift || {};
      return unless $_;
      if (/^\d+$/) {
          my @time = reverse ((localtime($_))[0..5]);
          $time[0] += 1900;
          $time[1]++;

          local $_ = $$opts{style} || 'long';
                       
          /long/  && do { return sprintf("%4.4d-%2.2d-%2.2d %2.2d:%2.2d:%2.2d", @time); };
          /stamp/ && do { return sprintf("%4.4d%2.2d%2.2d%2.2d%2.2d%2.2d", @time); };
      } else {
          my @t = $_ =~ m{^(\d{4}).(\d{2}).(\d{2})\s(\d{2}).(\d{2}).(\d{2})};
          if (+@t) {
              $t[1]--;
              return scalar @t ? timelocal @t[5,4,3,2,1,0] : undef;
          }
      }
      return undef;
}
1;