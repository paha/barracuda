#!/usr/bin/env perl
#
### subversion info
# $LastChangedDate: 2010-04-12 17:10:00 -0700 (Mon, 12 Apr 2010) $
# revision $Rev: 1481 $ committed by $Author: snagovpa $
# $HeadURL: https://svn.speakeasy.priv/svn/eng/systems/scripts/barracuda/barracuda_updater_domains.pl $

#### 
# 
# The script queries ldap, to obtain any domain used either in 'mail' or 'mailAlternateAddress' attributes,
# Compares the list of domains from barracuda and makes a list of domains to remove and to add.
#  
# The script uses subroutines from barracuda_subs.pl, make sure you have it available.
#

use strict;
use warnings;

use Net::LDAP;
use YAML;
use Fcntl qw(:flock);

require 'barracuda_subs.pl';

our $logfile = '/usr/local/barracuda/log/barracuda_updater_domains.log';
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
our $ldap_server = $yml->{ldapserver};
my $ldap_passwd = $yml->{ldap_passwd};

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
  filter  => '(&(objectclass=qmailUser)(!(accountStatus=deleted)))',
  attrs   => [ 'mail', 'mailAlternateAddress'],
);

$ldap->disconnect();

# Comparing hash's keys is faster then comparing arrays. Constructing hashes for both domains in ldap and in barracuda.
my $cuda_domains = list_domains();
my %cur_domains;
foreach ( @$cuda_domains ) {
  $cur_domains { $_ } = 1;
};

# processing ldap results, domains we find will be dropped into an hash, and compared to the list of domains in cuda to make a list of domains to add.
my ( @add_domains, %domains );
foreach my $entry ($ldap_results->entries) {
  foreach my $attr ( sort $entry->attributes ) {
    next if ( $attr =~ /;binary$/ );
    # domain for this attribute
    my $domain = (split(/@/, $entry->get_value( $attr )))[1];
    # we will add only domains that do not exist in the array already.
    # insure lowcase
    $domain =~ tr/A-Z/a-z/; 
    $domains { $domain } = 1 unless ( defined ( $domains { $domain } ));
    # while we are in this iteration, we will create array to add domains 
    push( @add_domains, $domain ) unless ( defined ( $cur_domains { $domain} ));
  };
};

# Find domains that need to be removed
my @del_domains;
foreach my $domain ( keys( %cur_domains ) ) {
  push( @del_domains, $domain ) unless ( defined ( $domains { $domain } ));
};

# Deleting domains
foreach my $domain ( @del_domains ) { 
  delete_domain( $domain );
};

# Adding domains
foreach my $domain ( @add_domains ) { 
  add_domain( $domain );
};

__DATA__
DATA section for flock().
