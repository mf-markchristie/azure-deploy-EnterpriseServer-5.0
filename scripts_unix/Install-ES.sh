#! /bin/bash -e

if [ "$#" -ne 2 ]
then
  echo "Not Enough Arguments supplied."
  echo "Usage Install-ES license mountDrive"
  exit 1
fi
license=$1
mountDrive=$2
export TERM="xterm"
shift

mkdir ~/utils
cp ./azcopy.tar.gz ~/utils
cd ~/utils
tar -xf azcopy.tar.gz
rm azcopy.tar.gz
export PATH=`pwd`:$PATH
cd -
mkdir ~/tmp
cd ~/tmp

installerExeName="ent_server_redhat_x86_64.rpm"
updateExeName="ent_server_update_redhat_x86_64.rpm"
installerLocation="https://mfenterprisestorage.blob.core.windows.net/enterpriseserverdeploy"

echo "Downloading Installer"
azcopy copy "${installerLocation}/${installerExeName}" "."
if [ "$?" -ne "0" ]; then
    echo "Failed to download installer."
    exit 1
fi


exit 0