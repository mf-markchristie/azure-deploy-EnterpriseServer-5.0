#! /bin/bash -e
installerExeName="setup_ent_server_redhat_x86_64"
updateExeName="setup_ent_server_update_redhat_x86_64"
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