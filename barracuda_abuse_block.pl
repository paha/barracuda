#!/usr/bin/env perl
#
### subversion info
# $LastChangedDate: 2010-04-12 17:10:00 -0700 (Mon, 12 Apr 2010) $
# revision $Rev: 1481 $ committed by $Author: snagovpa $
# $HeadURL: https://svn.speakeasy.priv/svn/eng/systems/scripts/barracuda/barracuda_abuse_block.pl $

#### 
# 
# 1. Adds ips from abuse list into barracuda.
# 2. Adds abuse email/domains to be blocked into barracuda.
# 
# The script uses subroutines from barracuda_subs.pl, make sure you have it available.
# 

use strict;
use warnings;

use YAML;
use Fcntl qw(:flock);

require 'barracuda_subs.pl';

our $logfile = '/usr/local/barracuda/log/barracuda_abuse.log';
my $config_file = '/usr/local/barracuda/etc/config.yml';
my $list_file = '/home/speakeasy/tcpcontrol/tcp.smtp';
my $email_block_list = '/home/speakeasy/tcpcontrol/badmailfrom';

# Insure only one script is runnning
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
  my $msg = "There is already another instance of $0 runnig. Exiting.";
  write_log( $msg );
  # print $msg;
  exit(1);
};

my $yml = YAML::LoadFile($config_file);
our $HOST = $yml->{barracuda_host};
our $passwd = $yml->{api_passwd};

# Verify that we can talk to the Barracuda API
barracuda_ping();

# Get array of abuse IPs from barracuda.
my $cur_block_list = config_get('mta_acl_ip_block_address', '', 'global');
# pack each IP element
@$cur_block_list = map( pack("C4", split(/\./,$_)), @$cur_block_list );

# Process abuse list file
open (FILE,$list_file);
while( <FILE> ) {
  chomp;
  if ( /:deny$/ ) {
    my ( $ip, $netmask ) = get_ip($_);
    if ( $netmask eq 'broken') {
      write_log( "ERROR: found invalid entry in abuse list - $ip, will not be added to Barracuda." );
      next;
    };
    # List received from barracuda will contain only elements that need deletion.
    my $last_size = $#$cur_block_list;
    # removing current ip from the original array we got from barracuda
    @$cur_block_list = grep { $_ ne $ip } @$cur_block_list;
    # If our ip wan't in the barracuda list, we need to add it
    if ( $#$cur_block_list == $last_size ) {
      # print "Need to add " . join(".", unpack("C4", $ip)) . "\n";
      # Unpacking the ip
      $ip = join(".", unpack("C4", $ip));
      config_create( 'global', '', 'mta_acl_ip_block_address', $ip, 'mta_acl_ip_block_netmask', $netmask ); 
    };
  };
};
close( FILE );

# At this point our original array we got from Barracuda suppose to have only items that need to be removed.
foreach ( @$cur_block_list ) {  
  # print "Need to delete" .  join(".", unpack("C4", $_)) . "\n";
  my $ip = join(".", unpack("C4", $_));
  config_delete( 'mta_acl_ip_block_address', $ip );
}; 

# Processing email abuse list---------------------------------------------------
my ( @block_domains, @block_emails );
open ( FILE, $email_block_list ) || write_log("$!");
while ( <FILE> ) {
  chomp;
  if ( /^@([a-z0-9-]+)(\.[a-z0-9-]+)*(\.[a-z]{2,5})$/ ) {
    my $domain_block = (split(/@/, $_))[1];
    push(@block_domains, $domain_block);
  } elsif ( /^(['_a-z0-9-]+)(\.['_a-z0-9-]+)*@([a-z0-9-]+)(\.[a-z0-9-]+)*(\.[a-z]{2,5})$/ ) {
    push(@block_emails, $_);
  }; 
};
close(FILE);

# get emails and domains that are currently blocked
my $cur_emails_blocked = config_get( 'mta_acl_email_src_block_address', '', 'global' );
my $cur_domains_blocked = config_get( 'mta_acl_domain_block_name', '', 'global' );

# compare
my @to_del_emails_block = grep!${{map{$_,1}@block_emails}}{$_},@$cur_emails_blocked;
my @to_add_emails_block = grep!${{map{$_,1}@$cur_emails_blocked}}{$_},@block_emails;
my @to_del_domains_block = grep!${{map{$_,1}@block_domains}}{$_},@$cur_domains_blocked;
my @to_add_domains_block = grep!${{map{$_,1}@$cur_domains_blocked}}{$_},@block_domains;

# adding and deleting
foreach my $email_block ( @to_del_emails_block ) {
  # on barracuda web interface: Block/Accept -> Sender Email - Blocked Email Addresses
  config_delete( 'mta_acl_email_src_block_address', $email_block );
}; 
foreach my $email_block ( @to_add_emails_block ) {
  config_create( 'global', '', 'mta_acl_email_src_block_address', $email_block, 'mta_acl_email_src_block_action', 'Block');
};
foreach my $domain_block ( @to_del_domains_block ) {
  # on barracuda web interface: Block/Accept -> Sender Domain - Blocked Sender Domain/Subdomain
  config_delete( 'mta_acl_domain_block_name', $domain_block );
};
foreach my $domain_block ( @to_add_domains_block ) {
  config_create( 'global', '', 'mta_acl_domain_block_name', $domain_block, 'mta_acl_domain_block_action', 'Block');
};

sub get_ip {
  # expecting: 1 - ip
  my $ip = (split(':', $_[0]))[0];
  my $netmask;
  if ( $ip =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/ ) { 
    $netmask = '255.255.255.255';
  } elsif ( $ip =~ /^(\d{1,3}\.\d{1,3}\.\d{1,3}\.)$/ ) { 
    $ip = $ip . "0";
    $netmask = '255.255.255.0';
  } elsif ( $ip =~ /^(\d{1,3}\.\d{1,3}\.)$/ ) { 
    $ip = $ip . "0.0";
    $netmask = '255.255.0.0';
  } else {
    $netmask = 'broken';
  };  
  return $ip if ($ip eq 'broken');
  # packing
  $ip =  pack("C4", split(/\./,$ip));
  return ( $ip, $netmask );
};

__DATA__
DATA section for flock().
