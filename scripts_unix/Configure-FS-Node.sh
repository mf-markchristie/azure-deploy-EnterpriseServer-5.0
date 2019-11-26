#! /bin/bash -e
if [ "$#" -ne 6 ]
then
  echo "Not Enough Arguments supplied."
  echo "Usage Configure-FS-Node FSVIEWUserPassword FSPort DomainDNSName DomainAdminUser DomainAdminPassword ServiceUser"
  exit 1
fi
FSVIEWUserPassword=$1
FSPort=$2
DomainDNSName=$3
DomainAdminUser=$4
DomainAdminPassword=$5
ServiceUser=$6
basedir=`pwd`
export TERM="xterm"
shift
"$basedir/Join-Domain.sh" $DomainAdminUser $DomainDNSName $DomainAdminPassword

export CCITCP2_PORT=1086
runuser -l $usernameFull -c '. /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; mfds --listen-all; mfds &'

"$basedir/Prepare-Demo" Y N N
fs -pf /FSdata/pass.dat -u SYSAD -pw SYSAD
fs -pf /FSdata/pass.dat -u FSVIEW -pw $FSVIEWUserPassword

echo "/s FS1,MFPORT:$FSPort" > /FSdata/fs.conf
echo "/pf /FSdata/pass.dat" >> /FSdata/fs.conf
echo "/wd /FSdata" >> /FSdata/fs.conf
echo "/cm CCITCP">> /FSdata/fs.conf

unzip ./BankDemo_FS -D BankDemo_FS
cp -r ./BankDemo_FS/System/catalog/data/* /FSdata
chmod 777 /FSdata/*

runuser -l $usernameFull -c '. /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; fs -cf /FSdata/fs.conf &'

# Todo:
#  - Network share
#  - Convert demo files if needed
