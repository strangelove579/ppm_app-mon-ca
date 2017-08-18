package ClrProps;

our %clr_attributes = (
  bo_hostname   => ['\svolumename="([^:"]*)','<reportserver\s'],
  bo_port       => ['\svolumename=".*?:([^"]*)','<reportserver\s'],
  bo_volumename => ['\svolumename="([^"]*)','<reportserver\s'],
  bo_user       => ['\susername="([^"]*)','<reportserver\s'],
  bo_pass       => ['\spassword="([^"]*)','<reportserver\s'],
  scheduler_url => ['\sschedulerurl="([^"]*)','<webserver\s.*'],
);


sub new {
  my $class = shift;
  $class = ref($class) ? ref($class) : $class;
  my $self = {};
  bless $self, $class;
  $self->loadProps();
  return $self;
}

sub loadProps {
  my $self = shift;
  foreach my $key (keys %clr_attributes) {
    my @val = _get_property($clr_attributes{$key}->[0], $clr_attributes{$key}->[1]);
    push @{$self->{$key}}, @val;
  }
  1;
}

sub _niku_home {
  my $profile_content = `cat /etc/odprofile`;
  my ($niku_home) = ($profile_content =~ m/export NIKU_HOME=([^\n]+)/);
  return $niku_home;
}

sub _clean_properties {
  my $filename = shift;
  my @orig = `cat $filename`;
  chomp(@orig);
  local $_ = join ' ', @orig;
  my @clean = split /\/\>/;
  return wantarray() ? @clean : \@clean;
}

sub _get_property {
  my $property_expr = shift  || return ();
  my $qualifier_expr = shift || return ();
  my $prop_file = _niku_home() . "/config/properties.xml";
  #my $prop_file = "/home/achjo03/ppm_app/samples/properties.xml";
  return () unless -f $prop_file;
  my @cleansed_props = _clean_properties($prop_file);
  my @retvals;
  foreach (@cleansed_props) {
    if (/$qualifier_expr/msi) {
      if (/$property_expr/msi) {
        push @retvals, $1;
      }
    }
  }
  return wantarray() ? @retvals : \@retvals;
}

sub get_keys {
  my $self = shift;
  return wantarray() ? (keys %clr_attributes) : \(keys %clr_attributes);
}

sub get_pairs {
  my $self = shift;
  my @pairs = ();
  foreach (keys %clr_attributes) {
    push @pairs, [ $_, defined $self->{$_}->[-1] ? $self->{$_}->[-1] : '' ];
  }
  return wantarray() ? @pairs : \@pairs;
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
