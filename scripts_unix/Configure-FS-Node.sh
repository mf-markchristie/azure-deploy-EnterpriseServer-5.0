#! /bin/bash -e

if [ "$#" -ne 4 ]
then
  echo "Not Enough Arguments supplied."
  echo "Usage Configure-FS-Node FSVIEWUserPassword FSPort DomainDNSName ServiceUser"
  exit 1
fi
FSVIEWUserPassword=$1
FSPort=$2
DomainDNSName=$3
ServiceUser=$4
export TERM="xterm"
shift
source /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv

cp -r /home/ec2-user/BankDemo_FS/System/catalog/data/* /FSdata
cp /tmp/fs.conf /FSdata
chmod 777 /FSdata/*
fs -pf /FSdata/pass.dat -u SYSAD -pw SYSAD
fs -pf /FSdata/pass.dat -u FSVIEW -pw $FSVIEWUserPassword
