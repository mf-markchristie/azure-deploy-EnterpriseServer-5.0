#! /bin/bash -e
if [ "$#" -ne 10 ]
then
  echo "Not Enough Arguments supplied."
  echo "Usage Configure-ES-Node DomainDNSName DomainAdminUser DomainAdminPassword ServiceUser ClusterPrefix RedisIp RedisPassword DeployDbDemo DeployPacDemo DeployFsDemo"
  exit 1
fi
DomainDNSName=$1
DomainAdminUser=$2
DomainAdminPassword=$3
ServiceUser=$4
ClusterPrefix=$5
RedisIp=$6
RedisPassword=$7
DeployDbDemo=$8
DeployPacDemo=$9
DeployFsDemo=${10}
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
mkhomedir_helper $usernameFull

runuser -l $usernameFull -c '. /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; mfds --listen-all; mfds &'

service firewalld stop