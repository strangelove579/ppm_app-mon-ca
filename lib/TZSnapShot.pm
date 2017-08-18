package TZSnapShot;

BEGIN {
  our $VERSION = "1.0";
}
use POSIX qw/strftime/;
use constant PROPS => qw/tz offset is_dst ss_tz ss_offset ss_is_dst ss_tz snapshot_file/;
our $vars;
@vars{(PROPS)} = (1) x scalar (PROPS);

sub new {
  my $class = shift;
  $class = ref($class) ? ref($class) : $class;
  my $self = {};
  bless $self, $class;
  my $k = shift;
  if (@_) {
    $self->{$key} = shift if $key eq 'snapshot_file';
  } else {
    $self->{snapshot_file} = $k if defined $k;
  }
  $self->{tz} = strftime("%Z", localtime());
  chomp($self->{offset} = `date +%z`);
  $self->{is_dst} = (localtime)[8];
  $self->read_snapshot() if defined $$self{snapshot_file} ;
  return $self;
}


sub snapshot_file {
  my $self = shift;
  $self->{snapshot_file} = shift if @_;
  $self->{snapshot_file};
}

sub snapshot_exists {
   my $self = shift;
   my $file = $self->snapshot_file();
   return undef unless defined $file;
   return -f $file ? 1 : 0;
}

sub take_snapshot {
  my $self = shift;
  foreach (qw/tz offset snapshot_file is_dst/) {
    return undef unless defined $self->{$_};
  }
  my $snapshot_file = $self->snapshot_file();
  my ($os,$dst,$tz) = @$self{qw/offset is_dst tz/};
  `echo "$os $dst $tz" > $snapshot_file`;
  $self->read_snapshot();
  1;
}

sub read_snapshot {
  my $self = shift;
  open (SS, " < " . $self->snapshot_file()) || return undef;
  chomp($_ = <SS>);
  @$self{qw/ss_offset ss_is_dst ss_tz/} = split ' ';
  close SS;
  1;
}

sub has_changed {
  my $self = shift;
  my $debug = 0;
  foreach (PROPS) {
    print "cant check timezone, undefined $_\n" && return undef
       unless defined $$self{$_};
  }
  use Time::Local;
  #use POSIX;
  my ($before_tz, $after_tz) = @{$self}{qw/ss_tz tz/};
  my ($before,$after) = (timelocal(0,0,0,1,1,2013)) x 2;
  my ($before_dst,$after_dst) = ($$self{ss_is_dst},$$self{is_dst});
  my ($before_hr, $before_min) = ($$self{ss_offset} =~ /^[\-+]?(\d{2})(\d{2})/);
  my ($after_hr, $after_min) = ($$self{offset} =~ /^[\-+]?(\d{2})(\d{2})/);
  my ($before_mod) = ($$self{ss_offset} =~ /^([\-+]?)/);
  my ($after_mod) = ($$self{offset} =~ /^([\-+]?)/);
  my $before_sec = $before_hr * 3600 + $before_min * 60;
  my $after_sec = $after_hr * 3600 + $after_min * 60;
  $before_mod eq '-' ? ($before -= $before_sec) : ($before += $before_sec);
  $after_mod eq '-' ? ($after -= $after_sec) : ($after += $after_sec);

  my $diff = substr ($before - $after,0,10) / 3600;
  print "$before - $after = $diff\n" if $debug;

  CHANGED: {
          $before_tz ne $after_tz && $diff == 0 && do { print "Timezone name changed, timezone offset stayed the same" if $debug; return 1;};
          $diff == 0 && $before_dst == $after_dst && do { print "no change\n" if $debug;last CHANGED;};
          abs $diff >= 2 && do { print "Failed, diff is greater than or equal to 2 hours " if $debug; return 1;};
          $diff != 0 && $before_dst == $after_dst && do { print "Failed, dst same, time changed" if $debug; return 1;};
          #$diff == 0 && $before_dst != $after_dst && do { print "Failed, dst changed, offset same" if $debug; return 1;};
          $after_dst == 1 && $diff > -2 && $diff <= 0 && do { print "OK diff is negative between 0 and -2 and moved into of DST" if $debug; last CHANGED;};
          $after_dst == 0 && $diff < 2 && $diff >= 0 && do { print "OK diff is positive and less than 2 and moved out of DST" if $debug; last CHANGED;};
          $after_dst == 1 && $diff < 2 && $diff >= 0 && do { print "Failed, diff is positive, less than 2 and moved into DST" if $debug; return 1;};
          $after_dst == 0 && $diff > 2 && $diff <= 0 && do { print "Failed, diff is negative, less than 2 and moved out of DST" if $debug; return 1;};
  }
  $self->take_snapshot();
  0;
}

sub AUTOLOAD {
  my $self = shift;
  my $called = our $AUTOLOAD;
  if ($called =~ /:([^:]+)$/) {
    my $v = $1;
    return undef unless $vars{$v};
    return $self->{$v};
  }
  undef;
}


1;
