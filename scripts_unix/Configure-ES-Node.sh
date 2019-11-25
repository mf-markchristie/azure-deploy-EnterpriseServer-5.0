#! /bin/bash -e
if [ "$#" -ne 4 ]
then
  echo "Not Enough Arguments supplied."
  echo "Usage Configure-ES-Node DomainDNSName DomainAdminUser DomainAdminPassword ServiceUser"
  exit 1
fi
DomainDNSName=$1
DomainAdminUser=$2
DomainAdminPassword=$3
ServiceUser=$4
basedir=`pwd`
export TERM="xterm"
shift
"$basedir/Join-Domain.sh" $DomainAdminUser $DomainDNSName $DomainAdminPassword
if [ "$saveError" -ne "0" ]; then
    echo "Failed to join domain. Error $saveError"
    exit 1
fi

usernameFull="$ServiceUser@$DomainDNSName"

realm permit $usernameFull
saveError=$?
if [ "$saveError" -ne "0" ]; then
    echo "Failed to provide login permissions. Error $saveError"
    exit 1
fi

. /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv
mfds --listen-all

runuser -l $usernameFull -c '. /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; mfds &'