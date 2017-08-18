# STK::Args.pm -- Standard Toolkit's Arg processing shortcuts

package STK::Args;

# Author          : John Achee
# Created On      : Sat Jun 6 15:00:12 2013
# Last Modified By: John Achee
# Last Modified On: Sat Jun 6 20:05:01 2013
# Status          : Released

################ END Module Preamble ################

use strict;
require 5.004;

our $VERSION = 1.00;

use Carp qw(confess);
require Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK);
@ISA = qw(Exporter);

BEGIN {
    @EXPORT_OK = qw();
    @EXPORT    = qw( hashify
                     hashify_secure
                     hashify_trap
                     missing_keys );
}

sub hashify_trap {
    my %hashed = ();
    %hashed = STK::Args::hashify(@_);
    if (defined $hashed{allowed_keys}
        and ref($hashed{allowed_keys}) !~ /ARRAY/) {
        confess "$0: Allowed keys must be an arrayref";
    } 
    my ($secure, $trapped) = STK::Args::_split_keys(
             $hashed{allowed_keys},
             \%hashed
     );
    return ($secure,$trapped);
}

sub missing_keys {
    my %p = (@_);
    my ($want,$got) = @p{qw/want got/};
    return -1 unless
         ref($want)   =~ /ARRAY/
      && ref($got)    =~ /ARRAY/;
      
    my %got = map { $_ => 1 } @{$got};
    my @missing = grep { ! $got{$_} } @{$want};
    return @missing;
}

sub hashify_secure {
    my $secure;
    ($secure,undef) = hashify_trap(@_);
    return wantarray() ? %{$secure} : $secure;  
}

sub hashify {
    my @unraveled = ();
    # breakdown all arguments into an array
    # top-level hashref/arrayrefs will dereference
    # filter-out keys we dont want, if the 'allowed_keys'
    # option is provided
    while (@_) {
        local $_ = shift;
        if (/HASH/) {
            push @unraveled, (%{$_});
        } elsif (/ARRAY/) {
            push @unraveled, (@{$_});
        } else {
            push @unraveled, $_;
        }
    }
    unless (+@unraveled % 2 == 0) {
        confess "$0: Odd number of elements in hash assignment"
    } 
    my %ret = +@unraveled ? (@unraveled) : ();

    return wantarray() ? %ret : \%ret;
}

sub _split_keys {
    my $allowed = shift;  # Arrayref of permissable keys
    my $keys = shift;     # Hashref of user provided keys
    
    my %allowed = map { $_ => 1 } @{$allowed};
    
    my %valid = map { $_ => $keys->{$_} }
                grep { $keys->{$_} }
                @{$allowed};
                
    my %invalid = map { $_ => $keys->{$_} }
                  keys %{$keys};
                  
    delete @invalid{(@{$allowed},'allowed_keys')};
    return (\%valid || \(), \%invalid || \());
    
}

1;
