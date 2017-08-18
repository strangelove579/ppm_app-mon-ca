package Configurator;

use constant APP_PROPS => qw/FILE KEEP _FILTER _KEEP_HIST/;
use TagUtils qw/ hash_it /;

sub new {
  my $class = shift;
  $class = ref($class) ? ref($class) : $class;
  my $self = {};
  bless $self, $class;
  $self->cparse(@_) if @_;
  return $self;
}

sub cparse {
  my $self = shift;
  return undef unless @_;
  my $params = hash_it(@_);
  if (defined $params->{_NOKEY}) {
    $self->{FILE} = $params->{_NOKEY};
  } else {
    foreach (FILE,KEEP) {
      $self->{$_} = $params->{$_};
      #delete ${$params}{$_};
    }
    $self->_store($_,$params->{$_}) foreach (keys %{$params});
  }
  my $cfile = $self->{FILE};

  if (defined $cfile) {
    open CFG, " < $cfile " or die "Config Error: Unable to open file: $cfile\n$!\n";
      while (<CFG>) {
        chomp;
        next if m/^\s*([#<].*)*$/;
        $self->_store($_);
      }
  }
  #delete ${$self}{$_} foreach (FILE, KEEP, _NOKEY);
  1;
}

sub cpurge {
  my $self = shift;
  delete @{$self}{@{ $self->cget_keys() }};
  1;
}

sub cset {
  my $self = shift;
  my $config = hash_it(@_) || return undef;
  $self->{_$_} = $config->{$_} foreach (keys %{$config});
  return 1;
}


sub _filter {
  my $self = shift;
  my $key = shift || return undef;
  if (defined $self->{_FILTER}) {
    return undef unless defined $self->{_FILTER}->{$key};
  }
  if (defined $self->{KEEP}) {
    return undef unless scalar grep {/^$key$/} @{$self->{KEEP}};
  }
  if (defined $self->{_KEEP_HIST} and
      $self->{_KEEP_HIST} == 0) {
    return undef if defined $self->{$key};
  }
  return 1;
}

sub cfilter {
  my $self = shift;
  delete ${$self}{_FILTER};
  return 1 unless @_;
  my @fkeys = ref($_[0]) =~ /ARRAY/ ? @{$_[0]} : @_;
  foreach (@fkeys) {
    $self->{_FILTER}->{$_} = 1;
  }
  my @rm_keys = grep(!defined $self->{_FILTER}->{$_}, $self->cget_keys);
  delete @{$self}{ @rm_keys };
  1;
}

sub _store {
  my $self = shift;
  my ($key,$val);
  if (scalar @_ == 1) {
    ($key, $val) = (split ('=', $_[0], 2));
  } else {
    ($key,$val) = (@_);

  }
  $val =~ s/^\s*(.*?)\s*$/$1/ if defined $val;
  $key =~ s/\s*//g;
  push @{$self->{$key}}, $val if $self->_filter($key);

  1;
}


sub cget_keys {
  my $self = shift;
  my %props = map { $_ => 1 } APP_PROPS;
  my @keys = grep(!defined $props{$_}, (keys %{$self}));
  return wantarray() ? @keys : \@keys;
}

sub cdefined {
  my $self = shift;
  return $self->_check('D',@_);
}

sub cexists {
  my $self = shift;
  return $self->_check('E',@_);
}

# Worker for cdefined/cexists
sub _check {
  my $self = shift;
  my $check_for = shift;
  my @cflds = @_;
  return undef unless @_;

  my @rflds;
  foreach (@cflds) {
    unshift @rflds, $_ unless ($check_for eq 'E'
                             ? exists $self->{$_}
                             : defined $self->{$_}[0]);
  }
  return wantarray() ? @rflds : \@rflds;
}


sub AUTOLOAD {

  my $self = shift;
  my $index = (@_) ? shift : -1;

  our $AUTOLOAD;

  my $property = $AUTOLOAD;

  $property =~ s/.*://;

  if (lc($index) eq "all") {
    my @vals = @{$self->{$property}};
    return wantarray() ? @vals : \@vals;
  }

  return ${$self->{$property}}[$index] || undef;

}
1;

