#!/usr/bin/env perl
#
### subversion info
# $LastChangedDate: 2010-04-12 17:10:00 -0700 (Mon, 12 Apr 2010) $
# revision $Rev: 1481 $ committed by $Author: snagovpa $
# $HeadURL: https://svn.speakeasy.priv/svn/eng/systems/scripts/barracuda/barracuda_updater.pl $

#### 
# 
# The script is meant to be invoked by when a new user preferences file is being scp-ed. 
# It will verify if domain for that user exists, if not it will create it and set defaults,
# and if user settings are not defaults it will create user in Barracuda and set defaults, whitelist/blacklist and preferences.
# 
# The script uses subroutines from barracuda_subs.pl, make sure you have it available.
# 

use strict;
use warnings;

use Getopt::Long;
use YAML; # we store some sensitive data in a yaml file.

require 'barracuda_subs.pl';

our $logfile = '/usr/local/barracuda/log/barracuda_updater.log';
our $user_pref_path = "/home/speakeasy/spamrules";
my $config_file = '/usr/local/barracuda/etc/config.yml';

# Loading parameters from yaml file.
my $yml = YAML::LoadFile($config_file);
our $HOST = $yml->{barracuda_host};
our $passwd = $yml->{api_passwd};
our $cuda_ldap_server = $yml->{cuda_ldap_server};
our $default_md5 = $yml->{default_md5sum};
our $zenoss_host = $yml->{zenoss_host};
our $snmp_community = $yml->{snmp_community};
our $ldap_server = $yml->{ldapserver};

# getting options. 
my ( $help, $user );
GetOptions(
  'help|?|h' => \$help,
  'user|u=s' => \$user,
);

usage() if $help;
usage() unless ( $user );

sub usage {
  print <<USAGE;

  Usage: $0 -u(ser) useremail -f(ile) path_to_user_prefs

  Description: The script is meant to be invoked by when a new user preferences file is being scp-ed by moses. 
  It will verify if domain for that user exists, if not it will create it and set defaults,
  if user settings are not defaults it will create user in Barracuda and set defaults, whitelist/blacklist and preferences. 

  The script uses subroutines from barracuda_subs.pl, make sure you have it available.

  -u/--user   : useremail
  -h/--help   : this message
  
USAGE
  exit;
};

# Verify that we can talk to the Barracuda API
# snmptrap is sent to zenoss if we can't ping barracuda
barracuda_ping();

# everything is done in that subroutine from barracuda_subs.pl
# including: domain creation, if needed, setting domain preferences, parsing user preferences, black/white lists and adding it to barracuda if different from defaults.
# snmptrap is sent to zenoss if we fail to add user
process_user( $user );
