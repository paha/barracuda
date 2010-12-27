# subroutines for barracuda scripts
# 
### subversion info
# $LastChangedDate: 2010-04-21 13:56:37 -0700 (Wed, 21 Apr 2010) $
# revision $Rev: 1497 $ committed by $Author: snagovpa $
# $HeadURL: https://svn.speakeasy.priv/svn/eng/systems/scripts/barracuda/barracuda_subs.pl $
# 
# use strict; # To share global varibles ( logfile, HOST, passwd, ldapserver, user_pref_path ), strict is used only in original script that requares this one

use warnings;
use Frontier::Client;
# use Data::Dumper; for testing
# use MIME::Lite; # used to send email 
use Net::LDAP; # used to query ldap
use Net::SNMP; # used to send snmptrap
# use YAML; # we store some sensitive data in a yaml file.

sub con {
  # expecting: 1 - host; 2 password
  new Frontier::Client( 
    url => "https://$_[0]/cgi-mod/api.cgi?password=$_[1]");
};

sub makecall {
  # expecting: 1 - rpccall; 2 - hash with arguments 
  my $xmlrpc = con( $HOST, $passwd );
  my ( $rpccall, %args ) = @_;
  write_log("Executed:: $rpccall { @{[%args]} }");
  $xmlrpc->call( $rpccall, \%args );
};

sub barracuda_ping {
  # To verify that we can talk to the barracuda API
  # expecting: no arguments
  eval { 
    my $results = config_get( 'dns_cache', '', 'global' );
  };
  if ( $@ || $$results{faultStr} ) {
    if ($$results{faultStr} ) {
      write_log( "Cuda ping failed: $$results{faultStr}" );
    } else {
      write_log( "Cuda ping failed: Couldn't reach $HOST." );
    };
    send_snmptrap( "Barracuda ping failed" );
    exit(1);
  };
};

sub config_get {
  # expecting: 1 - variable; 2 - path; 3 - type
  # example: { variable => 'user_scana_sender_allow', path => 'paha@speakeasy.net', type => 'user' }
  my %args = ( 
    variable => $_[0], 
    path => $_[1], 
    type => $_[2] );
  makecall('config.get', %args);
};

sub config_set {
  # expecting: 1 - type; 2 - path; 3 - variable; 4 - value
  # example: { type => 'user', path => 'paha@speakeasy.net', user_spam_scan_scoring_defaults => 'No' }
  my %args = ( 
    type => $_[0], 
    path => $_[1], 
    $_[2] => $_[3] );
  makecall( 'config.set', %args);
};

sub config_add {
  # expecting: 1 - type; 2 - path; 3 - variable; 4 - value
  # example: { type => 'user', path => 'paha@speakeasy.net', user_spam_scan_scoring_defaults => 'No' }
  my %args = (
    parent_type => $_[0],
    parent_path => $_[1],
    variable    => $_[2],
    values      => $_[3]);
  makecall( 'config.add', %args);
};

sub config_remove {
  # expecting: 1 - parent_type; 2 - parent_path; 3 - variable; 4 - value 
  my %args = (
    parent_type => $_[0],
    parent_path => $_[1],
    variable    => $_[2],
    values      => $_[3]);
  makecall( 'config.remove', %args);
};

# for tied variables, instead of config.add use config.create.
# expecting: 1 - parent_type; 2 -parent_path; 3 - type; 4 - name, 5 - variable, 6 - value 
# Multiple variables could be set, but this function doesn't handle that, use makecall() for now if there is such a need
sub config_create {
  my %args = (
    parent_type => $_[0],
    parent_path => $_[1],
    type        => $_[2],
    name        => $_[3],
    $_[4]       => $_[5], );
  makecall( 'config.create', %args);
};

# for tied variables use this instead of config_remove()
# expecting: 1 - 
sub config_delete {
  my %args = (
    type  => $_[0],
    path  => $_[1], );
  makecall( 'config.delete', %args);
};

sub add_domain {
  # expecting: 1 - domain name
  foreach my $domain ( @_ ) {
    my %args = ( domain => $domain );
    makecall( 'domain.add', %args );
    # set domain defaults 
    domain_defaults( $domain );
  };
};

sub delete_domain {
  # expecting: 1 - domain name(s)
  foreach my $domain ( @_ ) {
    my %args = ( domain => $domain );
    makecall( 'domain.delete', %args );
  };
};

sub list_domains {
  # expecting no arguments
  my %args = ( 
    type => 'global', 
    child_type => 'domain' );
  makecall( 'config.list', %args );
};

sub test_domain { 
  # expecting: 1 - domain
  # catch exception if there is no such domain
  eval { 
    config_get( 'mta_relay_advanced_host', $_[0], 'domain' ) 
  };
  return "No" if $@;
  return "Ok";
};

sub domain_catchall {
  # expecting 1 - domain
  my $domain = $_[0];
  my $ldap = Net::LDAP->new($ldap_server, timeout => 10 );
  # anonimouse binding 
  $ldap->bind( version   => 3 );
  my $ldap_results = $ldap->search(
    base    => "dc=speakeasy, dc=net",
    filter  => "(&(objectclass=qmailUser)(mail=catchall\@$domain))",
    attrs   => [ 'mail' ],
  );
  $ldap->disconnect();
  return $ldap_results->count;
};

sub domain_defaults {
  # expecting: 1 - domain name
  my $domain = $_[0];
  if ( domain_catchall( $domain ) > 0 ) {
    # Turn off LDAP verification to allow catchall
    config_set('domain', $domain, 'mta_recipient_verify_advanced_exchange', 'No' );
  } else {
    # Set LDAP verification to Yes -> Users/LDAP Configuration - LDAP Verification:
    config_set('domain', $domain, 'mta_recipient_verify_advanced_exchange', 'Yes' );
  };
  # Set ldap server -> Users/LDAP Configuration - LDAP Server
  config_set('domain', $domain, 'mta_ldap_advanced_host', $cuda_ldap_server );
  # Setting LDAP Server Type to 'OpenLDAP', default is AD -> Users/LDAP Configuration - LDAP Server Type
  config_set( 'domain', $domain, 'mta_ldap_advanced_server_type', 'OpenLDAP' );
  # Set ldap search base, by default it's uses ${defaultNamingContext} -> Users/LDAP Configuration - LDAP Search Base
  config_set('domain', $domain, 'mta_ldap_advanced_searchbase', 'dc=speakeasy,dc=net' );
  # Setting LDAP filter -> Users/LDAP Configuration - LDAP Filter
  my $filter = '(&(objectClass=qmailUser)(|(mail=${recipient_email})(mailAlternateAddress=${recipient_email}))(!(accountStatus=deleted)))';
  config_set('domain', $domain, 'mta_ldap_advanced_filter', $filter);
  # setting LDAP UID, -> Users/LDAP Configuration - LDAP UID
  config_set('domain', $domain, 'mta_ldap_advanced_unique_attr', 'uid');
  # setting Use Local Database: to Yes () -> Users/Valid Recipients - Use Local Database
  config_set('domain', $domain, 'recipient_use_localdb', 'Yes');
  # Disable User Quarantine -> Users/User Add/Update - Enable User(s) Quarantine:
  config_set('domain', $domain, 'quarantine_account_enable', 'No');
  # Disable new user Email -> Users/User Add/Update - Email New User(s):
  config_set('domain', $domain, 'quarantine_account_welcome_email', 'No');
  # Domain per-user preferences to yes -> Basic/Quarantine - Per-User Quarantine
  config_set('domain', $domain, 'scana_pd_pu_quarantine', 'Yes');
  # Domain Enable User Features -> Basic/Quarantine - Per-User Features
  config_set('domain', $domain, 'scana_pd_pu_preferences', 'Yes');
  # To inherit settings from aliases Users/LDAP Configuration - Unify Email Aliases have to be 'Yes'
  config_set('domain', $domain, 'mta_recipient_verify_advanced_unify', 'Yes' );
};

sub user_defaults {
  # expecting: 1- username
  my $user = $_[0];
  my $domain = (split(/@/, $user))[1];
  # Enabling per user spam scoring -> Preferences/Spam Settings - Use System Defaults:
  config_set('user', $user, 'user_spam_scan_scoring_defaults', 'No');
  # For tagging - 5 -> Preferences/Spam Settings - Tag:
  config_set('user', $user, 'user_scana_tag_level', '5');
  # Though 0 score is practically 'disable', we will explicitly disable Quarantine
  config_set('user', $user, 'user_quarantine_enable', 'No');
  # 'user_block_enable' have to be enabled to set white/black lists
  # config_set('user', $user, 'user_block_enable', 'No');
  # set domain
  config_set('user', $user, 'user_domains', $domain);
  # No quarantine notifications Preferences/Whitelist/Blacklist - Notification Interval:
  config_set('user', $user, 'user_quarantine_notify', 'Never');
  # Disable user quarantine by setting it to 10 -> Preferences/Spam Settings -Quarantine :
  config_set( 'user', $user, 'user_scana_quarantine_level', '10' );
  # Disable user blocking by setting it to 10 -> Preferences/Spam Settings - Block:
  config_set( 'user', $user, 'user_scana_block_level', '10' );
  user_pref_update( $user );
};

sub add_user {
  # expecting; 1 - usename
  my %args = ( user => $_[0] );
  makecall( 'user.create', %args );
  # NOTE: user defaults are not set here!
};

sub delete_user {
  # expecting: 1 - username
  my %args = ( user => $_[0] );
  makecall( 'user.remove', %args );
};

sub user_pref_update {
  # expecting: 1 - username
  my %args = ( user => $_[0] );
  makecall( 'user.update_pref', %args );
};

sub test_user {
  # expecting: 1 - username
  # catch exception if there is no such user
  eval { 
    config_get( 'user_uid', $_[0], 'user' ); 
  } or do {
    return "No";
  };
  return "Ok";
};

sub set_list { 
  # expecting either 'user_scana_sender_allow' or 'user_scana_sender_block' as the first argument
  # expecting: 1 - list method; 2 - username; 3 - list to set 
  my ( $method, $user, $list ) = @_;
  # 1. test if user exists. Should be done elsewhere
  # 2. get the curent list from barracuda
  my $current_list = config_get( $method , $user, 'user' );
  
  # 3. Compare the list with the current barracuda list.
  my @to_del_list = grep!${{map{$_,1}@$list}}{$_},@$current_list;
  my @to_add_list = grep!${{map{$_,1}@$current_list}}{$_},@$list;  
  
  # 4. delete entries that need deletion, if any
  if ( @to_del_list ) {
    my %args = ( 
      parent_type => 'user', 
      parent_path => $user, 
      variable => $method, 
      values => \@to_del_list);
    makecall ( 'config.remove', %args );
  };
  
  # 5. Adding entries, if any
  if ( @to_add_list ) {
    my %args = ( 
      parent_type => 'user', 
      parent_path => $user, 
      variable => $method, 
      values => \@to_add_list );
    makecall( 'config.add', %args );
  };
  user_pref_update( $user );
};

sub prefs_set {
  # expecting: 1 - username; 2 - hash with preferences
  # the only preference that is being set is 'required_hits' -> 'user_scana_tag_level':
  my $prefs = $_[1];
  config_set( 'user', $_[0], 'user_scana_tag_level', $$prefs{'required_hits'} );
  user_pref_update( $_[0] );
};

sub process_user {
  # expecting: 1 - username
  my $user = $_[0];
  my $domain = (split(/@/, $user))[1];
  # $user_pref_path have to be globally set /home/speakeasy/spamrules/
  my $file = $user_pref_path . "/" . substr($user, 0, 1) . "/" . $user . "/user_prefs";
  
  # Domain have to be added if not there
  add_domain( $domain ) unless ( test_domain( $domain ) eq 'Ok' );
  
  # in case we have no user_preferences, we assume defaults are used and will skip the processing
  unless ( -e $file ) {
    write_log( "SKIPPED: No preferences file found for $user. Skipping." );
    return;
  };
  
  # Test md5sum , and if it's just defaults we will not add users or do anything.
  my $checksum = `md5sum $file | awk '{print \$1}'`;
  chomp $checksum;
  if ( $checksum eq $default_md5 ) {
    write_log( "SKIPPED: $user has default preferences, will not be added to Barracuda" );
    return;
  };
  
  # if user exists we leave the preferences the way they are
  unless ( test_user( $user ) eq 'Ok' ) {
    my $results = add_user( $user );
    # if we fail to validate LDAP user we will not add the user and exit out of this function here.
    if ( $$results{faultCode} ) {
      # validation in add_user is removed, we need to validate here and catch accounts that are not in LDAP
      write_log( "FAILED: To add $user. :: -- Check if $user is in LDAP? }");
      send_snmptrap( "Failed to add user $user" );
      return;
    } else {
      write_log( "Success: Added user $user" );
    };
    # user defaults have to be set here too, add_user() doesn't set them.
    user_defaults( $user );
  };  
  # setting whitelist
  my $wlist = process_user_list( $user, "whitelist" );
  set_list( 'user_scana_sender_allow', $user, $wlist ) if $wlist;
  # setting balcklist
  my $blist = process_user_list( $user, "blacklist" );
  set_list( 'user_scana_sender_block' , $user, $blist ) if $blist;
  # getting and setting user prefs
  my $prefs = process_user_settings( $user );
  prefs_set( $user, $prefs );
};

sub list_users {
  # bogus arguments, Frontier wants it.
  my %args = ( something => 'be' );
  makecall( 'user.list', %args );
};

sub config_reload {
  my %args = ( something => 'be' );
  makecall( 'config.reload', %args );
};

###########
# processing:
#-------------------------------------------------------------------------------

sub process_user_list {
  # expecting: 1 - user, 2 - type of list (blacklist/whitelist)
  my ( $user, $type ) = @_;
  # $user_pref_path have to be globally set, currently /home/speakeasy/spamrules/
  my $file = $user_pref_path . "/" . substr($user, 0, 1) . "/" . $user . "/user_prefs";
  my ( @list, @list_domains );
  open FILE, $file || write_log( "Couldn't open prefs file $file" );
  while (<FILE>) {
    chomp;
    my $pattern = $type . "_from"; 
    next unless (/^$pattern/);
    my $email = (split(' ', $_))[1];
    $email =~ tr/A-Z/a-z/;
    # indentify valid entries. Not valid entries will be skipped, it will be added to log
    if ( $email =~ /^(['_*A-Za-z0-9-]+)(\.['_*A-Za-z0-9-]+)*@([A-Za-z0-9-]+)(\.[A-Za-z0-9-]+)*(\.[A-Za-z]{2,5})$/ ) {
      # indentify *@domain
      if ( $email =~ /^\*@/ ) {
        my $tmp_domain = (split(/@/, $email))[1];
        # moses allows to add user@domain when we have *@domain, barracuda doesn't.
        if ( grep { $_ eq $tmp_domain } @list_domains ) {
          # insure we have no duplicate entries and add the entry to our array
          push( @list, $email ) unless ( grep { $_ eq $email } @list );
          next;
        };
        # keep track of *@domain entries
        push( @list_domains, $tmp_domain );
      };
      # insure we have no duplicate entries and add the entry to the array
      push( @list, $email ) unless ( grep { $_ eq $email } @list );
    } else {
      # barracuda doesn't take regex in the domain part, have to sort them out. user impact.
      write_log( "Processing whitelist for $user found invalid entry $email " );
    };
  };
  close(FILE);
  # at this point we would use other functions to add values to our user preferences
  # returning just the list
  return \@list;
}; 

sub process_user_settings {
  # expecting; 1 - username
  my $user = $_[0];
  # $user_pref_path have to be globally set /home/speakeasy/spamrules/
  my $file = $user_pref_path . "/" . substr($user, 0, 1) . "/" . $user . "/user_prefs";
  # grep from file anything except whitelist, balcklist and whitespace and put it into a hash.
  my %prefs;
  open FILE, $file || write_log("ERROR: Couldn't open preefs file $file");
  while (<FILE>) {
    chomp;
    next if /^\s*($|#|whitelist_from|blacklist_from)/;
    # ($key, $value) = split(' ', $_);
    my @line = split(' ', $_);
    my $key = $line[0];
    # our value is everything that comes after the parameter name
    splice(@line, 0, 1);
    $prefs{$key} = join(' ', @line);
  };
  close(FILE);
  return \%prefs;
};

sub write_log {
  # logfile have to be set as a global variable
  my $msg = $_[0];
  my $date = localtime();
  open LOGFILE, ">>$logfile" || die "Can't open logfile $logfile";
  print LOGFILE " [ " . $date . " ] " . "::" . $msg . "\n";
  close(LOGFILE);
};

#sub send_email {
#  # for some things we want notifications 
#  $message = MIME::Lite->new(
#    To      => 'snagovpa@hq.speakeasy.net',
#    Subject => 'Populating Barracuda through API notification',
#    Data    => $email_msg,
#  );
#  $message->send();
#};

sub send_snmptrap {
  my $msg = $_[0];
  my $session = Net::SNMP->session( 
    -hostname  => $zenoss_host, 
    -community => $snmp_community,
    -timeout   => 20,
  ); 
  
  my $result = $session->trap(
    # using OIDs from https://nocweb.speakeasy.hq/engwiki/bin/view/Main/SpeakeasyAssignedOIDs
    -enterprise   => 1.3.6.1.4.1.18110.2.3.100,
    -specifictrap =>  101,
    -varbindlist  => ['1.3.6.1.4.1.18110.2.3.100.101.0', OCTET_STRING, $msg ]
  );
  $session->close();
};

return 1;

