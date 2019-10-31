#! /bin/bash -e
installerExeName="ent_server_redhat_x86_64.rpm"
updateExeName="ent_server_update_redhat_x86_64.rpm"
installerLocation="https://mfenterprisestorage.blob.core.windows.net/enterpriseserverdeploy"

echo "Downloading Installer"
azcopy copy "${installerLocation}/${installerExeName}" "."
if [ "$?" -ne "0" ]; then
    echo "Failed to download installer."
    exit 1
fi

azcopy copy "${installerLocation}/${updateExeName}" "."
if [ "$?" -ne "0" ]; then
    echo "Failed to download installer."
    exit 1
fi