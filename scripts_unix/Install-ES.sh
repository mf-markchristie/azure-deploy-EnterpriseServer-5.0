#! /bin/bash -e

if [ "$#" -ne 3 ]
then
  echo "Not Enough Arguments supplied."
  echo "Usage Install-ES license user mountDrive"
  exit 1
fi
license=$1
user=$2
mountDrive=$3
installerExeName="setup_ent_server_redhat_x86_64"
updateExeName="setup_ent_server_update_redhat_x86_64"
basedir=`pwd`
export TERM="xterm"
shift

mkdir ~/utils
sudo cp $basedir/azcopy.tar.gz ~/utils
cd ~/utils
tar -xf azcopy.tar.gz
rm -f azcopy.tar.gz
cp azcopy_linux*/azcopy .
rm -rf azcopy_linux*
chmod +x ./azcopy
export PATH=`pwd`:$PATH
cd -
mkdir ~/tmp
cd ~/tmp

"$basedir/Prepare-Installer"
if [ "$?" -ne "0" ]; then
    echo "Failed to prepare installer."
    exit 1
fi

yum install gcc glibc.i686 libgcc.i686 libstdc++.i686 pax java-1.7.0-openjdk-devel -y

chmod +x $installerExeName
./$installerExeName -ESadminID=$user -IAcceptEULA
saveError=$?
if [ "$saveError" -ne "0" ]; then
    echo "Failed to install. Error $saveError"
    exit 1
fi

chmod +x $updateExeName
./$updateExeName -ESadminID=$user -IAcceptEULA
saveError=$?
if [ "$saveError" -ne "0" ]; then
    echo "Failed to install. Error $saveError"
    exit 1
fi

mkdir license
cd license
azcopy copy $license .
licenseFileName=`ls` #This will be the only file in this directory

# Currently interactive, so need this workaround
/var/microfocuslicensing/bin/cesadmintool.sh -install `pwd`/$licenseFileName << block

block
. /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv
mfds --listen-all

if [ "$mountDrive" = "Y" ]; then
    fdisk /dev/sdc << EOF
n
p
1


t
fd
w
EOF
    mkfs -t ext4 /dev/sdc1
    echo "/dev/sdc1 /datadrive ext4 defaults,nofail 0 2" >> /etc/fstab
    mkdir /datadrive
    mount /dev/sdc1
fi

rm -rf ~/tmp

exit 0