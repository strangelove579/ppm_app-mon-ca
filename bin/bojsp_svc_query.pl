#!/fs0/od/perl/bin/perl

BEGIN {
    use Cwd qw/abs_path/;
    our $ap = abs_path $0;
    $ap =~ s{/bin/[^/]+$}{};
    push @INC, "$ap/lib";
}
use ClrUtils qw/clarity_version/;
use ClrProps;
my $props = ClrProps->new();

my $package             = '/fs0/od/nimsoft/probes/super/ppm_app';
my $live_procs          = "$package/config/.live_bo_processes.cfg";
my $default_procs       = "$package/config/.default_bo_processes.cfg";
my $unverified_flagfile = "$package/config/.boss_unverified";

unless (-e $unverified_flagfile) {
  exit 0;
} 


# BOServerStatus.jsp query has not been run or has not returned our list of services, so we provide default list
if (-e $unverified_flagfile) {
  `cat $default_procs > $live_procs`;
}

# Expecting Scheduler URL, exit if we didn't receive it
unless (defined $ARGV[0]) {
    print "Usage $0 <nsa_url>\n";
    exit 1;
}



my $url = $props->scheduler_url();


my $ppm_version = clarity_version();
if ( $ppm_version =~ /^1[23]|14.2/ ) {
   $url .= "/niku/BOServerStatus.jsp";
} else {
   $url .= "/niku/serverstatus/bostatus";
}

# Try to get list of services from BOServerStatus.jsp
my @out;
my $timeout = 60;
eval {
    local $SIG{ALRM} = sub { die "$0: Timeout was reached while attempting to curl [$url]\n" };
    alarm $timeout;
    @out = `/usr/bin/curl --silent --connect-timeout 60 --url $url`;
#    @out = `/usr/bin/curl --silent --connect-timeout 60 --url $url | grep -iP '^(server|enabled|running)'`;
#print   "/usr/bin/curl --silent --connect-timeout 60 --url http://$url:14001/niku/BOServerStatus.jsp | grep -iP '^(server|enabled|running)'";
#exit;
    alarm 0;
};

# No list of services, exit out
if ($@) {
  print "BO Query ERROR: $@\n";
  exit 1;
}
chomp(@out);

unless (scalar @out) {
  print "BO jsp output was not returned\n";
  exit 1;
}

if ( $ppm_version !~ /^1[23]|14.2/ ) {
   my $o = shift @out;
   $o =~ s/(<br>|,)\s*/\U$1\n/mg;
   @out = split /\n/, $o;
}
@out = grep { /^(server|enabled|running)/i } @out;

my $status = join ' ', @out;
my @wanted;

while ($status =~ /server:(.*?)\.([^,]+),.*?enabled:\s*([^,]+),.*?running:\s*([^<]+)/gsmi) {
    my ($ssvc,$svc,$enabled) = ($1,$2,$3);
    $svc=$ssvc if($svc =~ /localhost/i);
    $svc =~ s/\s//g;
    push @wanted, $svc if $enabled =~ /true/;
} 

# Build list of services found enabled on this BO Server, and format them for inclusing in processes probe config
if (scalar @wanted) {
    unlink ($unverified_flagfile,$live_procs);
    my $prefix = '\^\/fs0\*.';
    my $post   = '.pid\*';
    foreach my $svc (@wanted) {
print "${prefix}${svc}${post}\n";        
        `echo \'${prefix}${svc}${post}\' >> $live_procs`
    }
}
exit 0;

