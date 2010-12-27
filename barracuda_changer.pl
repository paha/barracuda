#!/usr/bin/env perl
#
### subversion info
# $LastChangedDate: 2010-04-12 17:10:00 -0700 (Mon, 12 Apr 2010) $
# revision $Rev: 1481 $ committed by $Author: snagovpa $
# $HeadURL: https://svn.speakeasy.priv/svn/eng/systems/scripts/barracuda/barracuda_changer.pl $

#### 
# 
# The script is to update any domain or user settings. Modify main to do desired changes.
#  
# The script uses subroutines from barracuda_subs.pl, make sure you have it available.
#

use strict;
use warnings;

use YAML;
use Fcntl qw(:flock);

require 'barracuda_subs.pl';

our $logfile = '/usr/local/barracuda/log/barracuda_updater.log';
# our $user_pref_path = "/home/speakeasy/spamrules";
my $config_file = '/usr/local/barracuda/etc/config.yml';

# Insure only one script is runnning
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
  my $msg = "There is already another instance of $0 runnig. Exiting.";
  write_log( $msg );
  # print $msg;
  exit(1);
};

# Loading parameters from yaml file.
my $yml = YAML::LoadFile($config_file);
our $HOST = $yml->{barracuda_host};
our $passwd = $yml->{api_passwd};
our $cuda_ldap_server = $yml->{cuda_ldap_server};
# our $default_md5 = $yml->{default_md5sum};
our $ldap_server = $yml->{ldapserver};
# our $ldap_passwd = $yml->{ldap_passwd};

# Verify that we can talk to the Barracuda API.
barracuda_ping();

# Getting a list of domains and changing a setting on each
print "Obtaining a list of domains\n";
my $cuda_domains = list_domains();
my $count = 1;
my $total = $#$cuda_domains;
foreach my $domain ( @$cuda_domains ) {
  print "Updating $domain - $count of $total\n";
  # updating domains ldap filter in include catchall
  # my $filter = '(&(objectClass=qmailUser)(|(mail=${recipient_email})(mailAlternateAddress=${recipient_email}))(!(accountStatus=deleted)))';
  # config_set('domain', $domain, 'mta_ldap_advanced_filter', $filter);
  # changing mta_recipient_verify_advanced_unify to 'yes', to inherit settings from aliases
  # config_set('domain', $domain, 'mta_recipient_verify_advanced_unify', 'Yes' );
  # setting Use Local Database: to Yes () -> Users/Valid Recipients - Use Local Database
  # config_set('domain', $domain, 'recipient_use_localdb', 'Yes');
  if ( domain_catchall( $domain ) > 0 ) {
    # Turn off LDAP verification to allow catchall
    config_set('domain', $domain, 'mta_recipient_verify_advanced_exchange', 'No' );
    print "Turned off LDAP verification for $domain\n";
  }
  $count++;
};

print "\n\tDone updating domains\n";

## Getting a list of users and changing a setting for each
#my $cuda_users = list_users();
#$count = 1;
#$total = $#$cuda_users;
#foreach my $user ( @$cuda_users ) {
#  print "Updating $user - $count of $total\n";
#  # Disable user quarantine by setting it to 10 -> Preferences/Spam Settings -Quarantine :
#  config_set( 'user', $user, 'user_scana_quarantine_level', '10' );
#  # Disable user blocking by setting it to 10 -> Preferences/Spam Settings - Block:
#  config_set( 'user', $user, 'user_scana_block_level', '10' );
#  $count++;
#};
# 
#print "\n\tDone updating users\n";

__DATA__
DATA section for flock().
