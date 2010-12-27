#!/usr/bin/env perl
#
### subversion info
# $LastChangedDate: 2010-04-12 17:10:00 -0700 (Mon, 12 Apr 2010) $
# revision $Rev: 1481 $ committed by $Author: snagovpa $
# $HeadURL: https://svn.speakeasy.priv/svn/eng/systems/scripts/barracuda/barracuda_load_users.pl $

#### 
# 
# The script queries ldap, to obtain any domain used either in 'mail' or 'mailAlternateAddress' attributes,
# and creates those domains in barracuda through API.
#  
# The script uses subroutines from barracuda_subs.pl, make sure you have it available.
#

use strict;
use warnings;

use Net::LDAP;
use YAML;
use Getopt::Long;

require 'barracuda_subs.pl';

our $logfile = '/usr/local/barracuda/log/barracuda_load_users.log';
our $user_pref_path = "/home/speakeasy/spamrules";
my $config_file = '/usr/local/barracuda/etc/config.yml';

# Loading parameters from yaml file.
my $yml = YAML::LoadFile($config_file);
our $HOST = $yml->{barracuda_host};
our $passwd = $yml->{api_passwd};
our $cuda_ldap_server = $yml->{cuda_ldap_server};
our $default_md5 = $yml->{default_md5sum};
our $ldap_server = $yml->{ldapserver};
my $ldap_passwd = $yml->{ldap_passwd};

# getting options.
our ($debug, $letter);
my $help;
GetOptions(
  'help|?|h' => \$help,
  'letter|l=s' => \$letter,
);

usage() if $help;
usage() unless $letter;

sub usage {
  print <<USAGE;

  Usage: $0 -l(etter) letter

  Description: This script will query ldap to get every qmailUser for specified letter to get mail and mailAlternateAddress attributes.
  And add users that need to be in barracuda ( those that have custom settings ), if domain isn't there it will also be added.
  for both users and domains default settings will be set.
  
  The script uses subroutines from barracuda_subs.pl, make sure you have it available.

  -l/--letter   : letter to process
  -h/--help   : this message
  
USAGE
  exit;
};

# Verify that we can talk to the Barracuda API.
barracuda_ping();

# Obtaining domains from ldap.
my $ldap = Net::LDAP->new($ldap_server, timeout => 10 );
$ldap->bind( "cn=ldapread,dc=speakeasy,dc=net",
  password  => $ldap_passwd,
  version   => 3 );
# $ldap->bind( version   => 3 ); # anonymous bind used for testing

# The ldap query is pretty expensive. 
my $ldap_results = $ldap->search(
  base    => "dc=speakeasy, dc=net",
  filter  => "(&(objectClass=qmailUser)(|(mail=$letter*)(mailAlternateAddress=$letter*))(!(accountStatus=deleted)))",
  attrs   => [ 'mail', 'mailAlternateAddress'],
);

$ldap->disconnect();

# processing ldap results, domains we find will be dropped into an array
my $count = 1;
my $total = $ldap_results->count;
foreach my $entry ( $ldap_results->entries ) {
  foreach my $attr ( sort $entry->attributes ) {
    next if ( $attr =~ /;binary$/ );
    # print "Found user " . $entry->get_value( $attr ) . "\n";
    my $user = $entry->get_value( $attr );
    # insure lowcase
    $user =~ tr/A-Z/a-z/;
    print "Processing $user - $count of $total\n";
    process_user( $user );
  };
  $count++;
};
