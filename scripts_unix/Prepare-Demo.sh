#! /bin/bash -e

if [ "$#" -ne 3 ]
then
  echo "Not Enough Arguments supplied."
  echo "Usage Prepare-Demo deployFsDemo deployDbDemo deployPacDemo"
  exit 1
fi
deployFsDemo=$1
deployDbDemo=$2
deployPacDemo=$3
export PATH=~/utils:$PATH

downloadBase="https://mfenterprisestorage.blob.core.windows.net/enterpriseserverdeploy"

if [ "$deployFsDemo" -eq "Y" ]; then
    echo "Downloading FS Demo"
    azcopy copy "$downloadBase/BankDemo_FS.zip" "."
fi

if [ "$deployDbDemo" -eq "Y" ]; then
    echo "Downloading DB Demo"
    azcopy copy "$downloadBase/BankDemo_SQL.zip" "."
fi

if [ "$deployPacDemo" -eq "Y" ]; then
    echo "Downloading PAC Demo"
    azcopy copy "$downloadBase/BankDemo_PAC.zip" "."
fi
