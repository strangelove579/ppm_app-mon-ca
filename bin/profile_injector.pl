#!/usr/bin/perl
use Cwd qw'abs_path';

# Define the new profiles we want to add/replace into nexec
my %new_profiles = (
  # profile name in nexec   =>  resource filename with new profile content
  create_hprof_profile => 'hprof_profile',
  create_perl_symlink => 'symlink_profile'
);


# Setup directories and paths
my $p = abs_path($0);
$p =~ s{/bin/[^/]+$}{};
my $res_dir = "$p/res";
my $nms_home = '/fs0/od/nimsoft';
my $probe_home = "$nms_home/probes/service/nexec";
my $probe_config = "$probe_home/nexec.cfg";

# generic config replacer prototype
sub replace_config {
    my $file = shift;
    return sub {
      my $content = shift;
      my $now = time();
      use File::Copy;
      copy $file, "$file.${now}";
      open CFG, ">", $file or die "Failed to overwrite nexec.cfg with $!";
      print {CFG} $content;
      close CFG;
    }
}
# callback for nexec config replacement
my $replace_nexec_cfg = replace_config($probe_config);

# callback for nexec probe restart
my $do_probe = sub { system("$nms_home/bin/pu -uprobe_admin -padmin01 controller probe_$_[0] nexec"); sleep 5; };




MAIN_EXEC:
{

  # Slurp the current config file content
  my $nexec_cfg = do { local $/; `cat $probe_config`; };
    print $nexec_cfg;
  # Uncomment the next line to see the ORIGINAL config
  #print "Old nexec.cfg:\n$nexec_cfg\n\n";
  
  # Add or replace each profile
  foreach my $profile (keys %new_profiles) {

    # Path where new profile exists (in the res directory)
    my $prof_content = $res_dir . '/' . $new_profiles{$profile};

    # Slurp the new profile content
    my $new_profile = do { local $/; `cat $prof_content`; };

    if ($nexec_cfg =~ / *<$profile>/msi) {
      # Replace the existing profile with new one
      $nexec_cfg =~ s/ *<$profile..*?\/$profile> *\n/$new_profile/msi;
      } else {
      # Or add it, if it doesn't already exist
      $nexec_cfg =~ s{</profiles>}{$new_profile</profiles>}msi;
    }

  }

  # Uncomment the next line to see the NEW config
  #print "New nexec.cfg:\n$nexec_cfg\n\n";

  # Replace config on disk, and restart
  $replace_nexec_cfg->($nexec_cfg);
  $do_probe->("deactivate");
  $do_probe->("activate");

}
exit 0;
