
package TagUtils;

use Carp;
use English '-no_match_vars';

require Exporter;
use base ("Exporter");
@EXPORT_OK = qw{ hash_it binder get_rand32 get_fmtd_time get_timestamp };



#
# sub: hash_it(@pairs)
#      hash_it($pairs_arrayref, [$pairs_hashref_or_arrayref]...)
#      hash_it($pairs_hashref, [$pairs_hashref_or_arrayref]...)
#      hash_it($scalar) # scalar, not a pair
#
#    Auth: John Achee until Nathan Hilterbrand completely re-wrote it.
#    11/14/2012
#
#        Worker to parse key/val pairs into hashref
#        If it receives a scalar, the scalar will be keyed by _NOKEY
#
#    hash_it will "unroll" HASHREFS and/or ARRAYREFS until it sees an
#    argument that is not a reference.  This allows calls such as:
#
#    sub new {
#      my $class = shift;
#      my %defaults = (parm1 -> "default1", parm2 => "default2");
#      my $parms = hash_it(\%defaults, \@_);
#    ...
#    }
#
#    The parameters passed in to new() will then be used to override the defaults.
#    The example used one reference and a series of discrete values from @_,
#    but more references can be used if desired.  They must, however, be the
#    first parameters to hash_it.  Subsequent references will be treated as keys
#    or values.  This is a necessary "feature" to allow the use of references
#    as keys or values in parameter lists
#

  sub hash_it {

    my %rhash = ();
    my @gather = ();

    unless (@_) {
      carp "TagUtils::hash_it called with no arguments";
      return wantarray() ? (%rhash) : \%rhash;
    }

    my $refsdone = 0;
    while (@_ and not $refsdone) {
      my $arg = shift;
      unless ($refsdone) {
        if (ref($arg) =~ /ARRAY/) {
          push @gather, (@{$arg});
        } elsif (ref($arg) =~ /HASH/) {
          push @gather, (%{$arg});
        } else {
          push @gather, $arg;
          $refsdone = 1;
        }
      }
      #local $" = '", "';
    }

    push @gather, @_ if @_;

    #  Now all the parms are gathered into @gather

    if (scalar @gather == 1) {
      $rhash{"_NOKEY"} = shift @gather;
    } elsif (scalar @gather % 2) {    # odd number
      carp "Error: odd number of arguments to TagUtil::hashit";
      local $LIST_SEPARATOR = '", "';
      carp "\"@gather\"";
    } else {
      %rhash = (@gather);
    }

    return wantarray() ? (%rhash) : \%rhash;

  }


#  sub: binder (template => $scalar,
#               identifier => $scalar,
#               err_level => $scalar,
#               scalarmap => $hashref,
#               listmap => $hashref,
#               );
#
#
#  Auth: John Achee, 11/16/2012
#
#   Super light-weight templating tool. Use solely to populate a
#   text-template's bind variables
#
#   Two methods of variable replacement:
#     Replace variable with scalar value (ie: 'City' field in a Mailing Address)
#     Replace row of variables with array of values (ie: 'Order Item' rows on an Invoice)
#
#                INPUT
#
#   Input is a hashref containing the following:
#
#     * denotes required
#
#       KEY             TYPE
#       --------------  -----------
#     * template        scalar       Text to process
#       id_prefix       scalar       Character(s) prefix that identify a string
#                                    as a bind variable. Default is colon ":"
#       err_level       scalar       Should errors be thrown if unpopulated bind
#                                    variables still exist ?
#                                      0=No, 1=Warn, 2=Error (Default=1)
#       scalarmap       hashref      A hashref of bindvariable names, and the values
#                                    to map them to.
#       listmap         hashref      A hashref of multi-row binds. See "Multi-Row"
#                                    processing below.
#
#             RETURN
#
#   Returns plain-ole-text.
#
#
#
#   Bind variables
#
#   1)  Bind variable strings must follow the format:
#       <id_prefix><Word string, ie: [a-zA-Z0-9_]+>
#
#         eg:   :foo_100  # Valid
#               :foo-100  # Invalid, dash not allowed
#               !!foo_100  # Valid, if id_prefix is set to '!!'
#
#   2)  Escaping: Bind variable identifiers can be escaped within templates using '\'.
#       binder() will however remove escape characters from the output.
#
#   3)  "List areas" are identified by:
#                 @[[name  ...content ... ]]
#
#  printf-style Formatting Supported
#    binder() will apply sprintf() formatting to any bind variable defined with a
#    format string. For example, the below will print only 1 character for any middle
#    name provided.
#
#       eg:    :fname :mname.FMT(%.1s) :lname
#
#  Scalarmaps
#    A simple search and replace list for normal bind variables
#      scalarmap => {bindvar_name => 'new val', bindvar_name2 => 'new val2', etc..}
#
#  Listmaps
#    A more complex search and replace, for repeating areas of text. The repeating areas
#  may themselves contain bind varaiables or even other listmaps. A 'list area' must begin
#  with @[[ followed by the list areas name, then any repeating content, finished by ']]'
#
#
#
#   Example:
#   Template w/ list 'ord_item':
#         Order Invoice:
#           Item#    Description                         Price
#           @[[ord_item    :item_no.FMT(%-8.8s) :description.FMT(%-30.30s) :price.FMT(%10.10s) ]]
#
#   Listmap defined as:
#   my @ord_items = ({item_no => '10001',
#                    description => 'Cordless phone shaver gear with extra bits and pieces',
#                    price  =>'1000.00'},
#                    {item_no => '10002',
#                    description => 'Random bag of gems',
#                    price =>'1000000.00'},
#                    {item_no => '10003',
#                    description => 'General supplies',
#                    price =>'99.00'},);
#
#   $output = binder(template => $template, listmap => {ord_item => \@ord_items});
#
#
#    Produces:
#
#
#  Order Invoice:
#    Item#    Description                         Price
#    10001    Cordless phone shaver gear wit    1000.00
#    10002    Random bag of gems             1000000.00
#    10003    General supplies                    99.00
#
#



  sub binder {
    my $default_in = {
            template      => undef,
            id_prefix    => ':',
            err_level     => 1,
            scalarmap     => {},
            listmap       => {},
    };
    my $in = hash_it ($default_in, \@_);
    return undef unless defined $in->{template};

    (my $out_template = $in->{template}) =~ s/\n/|LB|/sg;
    my ($prefix,$esc_pre,$s_map,$l_map) = @{$in}{qw/id_prefix id_prefix scalarmap listmap/};
    $esc_pre =~ s{([\$\^\&\*\-\_\=\+])}{\\$1}g;

    # Find n bind any multi-row repeating vars
    while (my ($v, $found) = ($out_template =~ /\@\[\[(\w+)(.*?)\]\]/)) {
      if (exists $l_map->{$v}) {
        my $addrows;
        foreach (@{$l_map->{$v}}) {
          $addrows .= binder ( template => $found, id_prefix => $prefix, scalarmap => $_ ) . '|LB|' ;
        }
        $out_template =~ s/\@\[\[.*?\]\]/$addrows/;
      }
    }

    # Find n bind any single value scalar bindvars
    foreach my $var (keys %{$s_map}) {
     while (my ($match, $format_str)
                   = ($out_template =~ m{(?:[^\\]{1}|^)($esc_pre[\{]?$var[\}]?)(?:\.FMT\((.*?)\))?})) {
         my $fmtd = defined $format_str ? sprintf("$format_str", $s_map->{$var}) : $s_map->{$var};
         $fmtd = defined $fmtd ? $fmtd : '';
         $out_template =~ s{([^\\]{1}|^)($esc_pre[\{]?$var[\}]?)(\.FMT\(.*?\))?}{$1$fmtd}g;

       }
    }

    # Bark for any leftovers
    if ($out_template =~ /[^\\]$esc_pre[\{]?(\w+)[\}]?/g) {
      carp "Warning: binder() failed to populate all bind variables"
        if $in->{err_level} == 1;
      croak "Error: binder() failed to populate all bind variables"
        if $in->{err_level} > 1;
    }

    $out_template =~ s/(\\)$esc_pre/$prefix/g;
    $out_template =~ s/\|LB\|/\n/sg;
    return $out_template;
  }


  #
  #  sub: get_rand32()
  #
  #    Auth: Nathan Hilterbrand, 12/4/2012
  #
  #    Gets a 32 bit random number from /dev/urandom
  #
  #

  sub get_rand32 {

    open my $rnd, "<:raw",  "/dev/urandom" or
      die "Error opening /dev/urandom for input: $!";
    my $rndchars;
    my $cnt = sysread $rnd, $rndchars, 4;
    my $val = unpack("L", $rndchars);
    return $val;

  }

  # John Achee
  # Simple function to format your epoch localtime to something readable, or
  # or supply no arguments and get the current time
  # Format returned: YYYY/MM/DD HH24:MI:SS
  # 12/18/12

  sub get_fmtd_time {
    my $timestamp = shift || time;
    my $pad = sub { my $n = shift; return length($n) == 1 ? '0'.$n : $n;};
    my ($sec, $min, $hour, $day,$month,$year) = (localtime($timestamp))[0,1,2,3,4,5];
    $year += 1900;
    $month++;
    $sec = $pad->($sec);
    $min = $pad->($min);
    $hour = $pad->($hour);
    $month = $pad->($month);
    $day = $pad->($day);
    my $fmtd = "$year/$month/$day $hour:$min:$sec";
  }

  # John Achee,12/12/12
  # Simply get a timestamp in the format YYYYMMDDHHHISS
  # (Which I find useful for logfile naming, tempfile naming etc)

  sub get_timestamp {
    my @now = localtime();
    my $timestamp = sprintf("%04d%02d%02d%02d%02d%02d",
                    $now[5]+1900, $now[4]+1, $now[3],
                    $now[2],      $now[1],   $now[0]);
  }

1;
