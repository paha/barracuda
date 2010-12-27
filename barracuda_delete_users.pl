#!/usr/bin/env perl
#
### subversion info
# $LastChangedDate: 2010-04-12 17:10:00 -0700 (Mon, 12 Apr 2010) $
# revision $Rev: 1481 $ committed by $Author: snagovpa $
# $HeadURL: https://svn.speakeasy.priv/svn/eng/systems/scripts/barracuda/barracuda_delete_users.pl $

#### 
# 
# This script is meant to be run on periodical bases to remove users that could be defined in Barracuda.
# Getting all users from ldap that have accountStatus=deleted and remove them if exist in Barracuda through API
# 
# The script uses subroutines from barracuda_subs.pl, make sure you have it available.
# 

use strict;
use warnings;

use Net::LDAP; # used to query ldap
use YAML; # we store some sensitive data in a yaml file.
use Fcntl qw(:flock);

require 'barracuda_subs.pl';

our $logfile = '/usr/local/barracuda/log/barracuda_updater.log';
my $config_file = '/usr/local/barracuda/etc/config.yml';

# Loading parameters from yaml file.
my $yml = YAML::LoadFile($config_file);
our $HOST = $yml->{barracuda_host};
our $passwd = $yml->{api_passwd};
my $ldap_server = $yml->{ldapserver};
my $ldap_passwd = $yml->{ldap_passwd};

# Insure only one script is runnning
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
  my $msg = "There is already another instance of $0 runnig. Exiting.";
  write_log( $msg );
  # print $msg;
  exit(1);
};

# Verify that we can talk to the Barracuda API
barracuda_ping();

# Getting a list of users to delete from ldap. 
my $ldap = Net::LDAP->new($ldap_server, 
  timeout => 10 );
$ldap->bind( "cn=ldapread,dc=speakeasy,dc=net",
  password  => $ldap_passwd,
  version   => 3 );
# $ldap->bind( version   => 3 ); # anonymous bind used for testing

my $ldap_results = $ldap->search(
  base    => "dc=speakeasy, dc=net",
  filter  => '(&(objectclass=qmailUser)(accountStatus=deleted))',
  attrs   => [ 'mail', 'mailAlternateAddress'],
);

my @delete_users;
foreach my $entry ($ldap_results->entries) {
  foreach my $attr ( sort $entry->attributes ) {
    next if ( $attr =~ /;binary$/ );
    my $user = $entry->get_value( $attr );
    unless ( grep {$_ eq $user} @delete_users ) {
      push( @delete_users, $user )
    };
  };
};

$ldap->disconnect();

# Deleting every set for deletion user that exists 
foreach ( @delete_users ) {
  my $user = $_;
  next if ( test_user( $user ) eq "No" );
  # print "User $user marked for delition\n";
  # look at the logfile for user deletions
  user_delete( $user );
};

__DATA__
DATA section for flock().
