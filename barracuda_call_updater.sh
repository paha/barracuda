#!/bin/bash 
#
### subversion info
# $LastChangedDate: 2010-04-12 17:20:46 -0700 (Mon, 12 Apr 2010) $
# revision $Rev: 1483 $ committed by $Author: erichey $
# $HeadURL: https://svn.speakeasy.priv/svn/eng/systems/scripts/barracuda/barracuda_call_updater.sh $
#### 
#
# Call barracuda_updater.pl with the username passed by myspeak
#

args=($@)
user=${args[0]}

if [ -n "${user}" ]; then
  cd /usr/local/barracuda/bin
  ./barracuda_updater.pl -u $user 
  if [ $? -eq 0 ]; then
    exit 0
  else 
    exit 1
  fi
else 
  exit 1
fi

