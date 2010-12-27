#!/usr/bin/env perl
#
### subversion info
# $LastChangedDate: 2010-04-14 15:14:27 -0700 (Wed, 14 Apr 2010) $
# revision $Rev: 1488 $ committed by $Author: snagovpa $
# $HeadURL: https://svn.speakeasy.priv/svn/eng/systems/scripts/barracuda/barracuda_load_users_updater.pl $

#### 
# 
# Picks user_prefs files that have been modified in the last 30 days and updates 
#  
# The script uses subroutines from barracuda_subs.pl, make sure you have it available.
#

use strict;
use warnings;

use YAML;
use Getopt::Long;
use Fcntl qw(:flock);

require 'barracuda_subs.pl';

our $logfile = '/usr/local/barracuda/log/barracuda_updater.log';
our $user_pref_path = "/home/speakeasy/spamrules";
my $config_file = '/usr/local/barracuda/etc/config.yml';

# Insure only one script is runnning
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
  my $msg = "There is already another instance of $0 runnig. Exiting.";
  write_log( $msg );
  # print $msg;
  exit(1);
};

# getting options.
our ($debug, $letter);
GetOptions(
  'letter|l=s' => \$letter,
);

die "Have to have a letter as an Argument (-l letter)" unless $letter;

# Loading parameters from yaml file.
my $yml = YAML::LoadFile($config_file);
our $HOST = $yml->{barracuda_host};
our $passwd = $yml->{api_passwd};
our $cuda_ldap_server = $yml->{cuda_ldap_server};
our $default_md5 = $yml->{default_md5sum};
our $ldap_server = $yml->{ldapserver};

# Verify that we can talk to the Barracuda API.
# barracuda_ping();

foreach my $file (`find $user_pref_path/$letter/ -type f -mtime -30`) {
  chomp($file);
  my $user = ( split( '\/', $file ) )[5];
  print "Processing $user\n";
  process_user( $user ); 
};

__DATA__
DATA section for flock().
