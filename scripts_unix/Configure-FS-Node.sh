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

yum install nfs-utils -y

"$basedir/Join-Domain.sh" $DomainAdminUser $DomainDNSName $DomainAdminPassword
if [ $? -ne 0 ]; then
    echo "Failed to provide join domain"
    exit 1
fi

usernameFull="$ServiceUser@$DomainDNSName"

realm permit $usernameFull
if [ $? -ne 0 ]; then
    echo "Failed to provide login permissions"
    exit 1
fi
mkhomedir_helper $usernameFull

runuser -l $usernameFull -c '. /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; mfds --listen-all; mfds &'
if [ $? -ne 0 ]; then
    echo "Failed to start MFDS"
    exit 1
fi

mkdir ~/tmp
cd ~/tmp
mkdir /FSdata/
chown -R $usernameFull /FSdata/

systemctl enable nfs-server
systemctl enable rpcbind
systemctl start rpcbind
systemctl start nfs-server
echo '/FSdata *(rw,sync)' >> /etc/exports
exportfs -r
systemctl restart nfs-server

"$basedir/Prepare-Demo" Y N N
runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; fs -pf /FSdata/pass.dat -u SYSAD -pw SYSAD"
runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; fs -pf /FSdata/pass.dat -u FSVIEW -pw $FSVIEWUserPassword"

echo "-s FS1,MFPORT:$FSPort" > /FSdata/fs.conf
echo "-pf /FSdata/pass.dat" >> /FSdata/fs.conf
echo "-cm CCITCP">> /FSdata/fs.conf

unzip ./BankDemo_FS.zip
rm ./BankDemo_FS.zip
cp -r ./BankDemo_FS/System/catalog/data/* /FSdata
cp -r ./BankDemo_FS/System/catalog/PRC /FSdata
cp -r ./BankDemo_FS/System/catalog/CTLCARDS /FSdata
chown -R $usernameFull /FSdata

runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; cd /FSdata; fs -cf /FSdata/fs.conf &"
if [ $? -ne 0 ]; then
    echo "Failed to start Fileshare"
    exit 1
fi

service firewalld stop

cd ~
rm -rf ~/tmp