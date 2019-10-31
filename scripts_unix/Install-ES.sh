#! /bin/bash -e

if [ "$#" -ne 2 ]
then
  echo "Not Enough Arguments supplied."
  echo "Usage Install-ES license mountDrive"
  exit 1
fi
license=$1
mountDrive=$2
installerExeName="ent_server_redhat_x86_64.rpm"
updateExeName="ent_server_update_redhat_x86_64.rpm"
export TERM="xterm"
shift

basedir=$(dirname "$0")

mkdir ~/utils
cp ./azcopy.tar.gz ~/utils
cd ~/utils
tar -xf azcopy.tar.gz
rm azcopy.tar.gz
chmod +x ./azcopy
export PATH=`pwd`:$PATH
cd -
mkdir ~/tmp
cd ~/tmp

. "$basedir/Prepare-Installer"
if [ "$?" -ne "0" ]; then
    echo "Failed to prepare installer."
    exit 1
fi


exit 0