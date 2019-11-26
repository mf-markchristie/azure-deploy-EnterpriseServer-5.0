#! /bin/bash -e
if [ "$#" -ne 9 ]
then
  echo "Not Enough Arguments supplied."
  echo "Usage Configure-ES-Node DomainDNSName DomainAdminUser DomainAdminPassword ServiceUser ESCount clusterPrefix RedisIp DeployFsDemo DeployPacDemo"
  exit 1
fi
DomainDNSName=$1
DomainAdminUser=$2
DomainAdminPassword=$3
ServiceUser=$4
ESCount=$5
clusterPrefix=$6
RedisIp=$7
DeployFsDemo=$8
DeployPacDemo=$9
basedir=`pwd`
export TERM="xterm"
shift

yum install curl -y

"$basedir/Join-Domain.sh" $DomainAdminUser $DomainDNSName $DomainAdminPassword
saveError=$?
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
chown $usernameFull /opt/microfocus/EnterpriseDeveloper/etc/commonwebadmin.json
find /opt/microfocus/EnterpriseDeveloper/etc -type d -exec chmod 777 {} \; # So escwa can write to the logfile

runuser -l $usernameFull -c '. /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; escwa &'
saveError=$?
if [ "$saveError" -ne "0" ]; then
    echo "Failed to start escwa. Error $saveError"
    exit 1
fi

function addDS () {
    if [ "$#" -ne 3 ]
    then
        echo "Not Enough Arguments supplied."
        echo "Usage addDS Hostname Port Name"
        exit 1
    fi
    HostName=$1
    Port=$2
    Name=$3
    JMessage="{ \
        \"MfdsHost\": \"$HostName\", \
        \"MfdsIdentifier\": \"$Name\", \
        \"MfdsPort\": \"$Port\" \
    }"

    RequestURL='http://localhost:10004/server/v1/config/mfds'
    Origin='Origin: http://localhost:10004'

    curl -sX POST $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H "$Origin" -d "$JMessage" --cookie cookie.txt
}

function jsonValue() {
    KEY=$1
    num=$2
    awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/'$KEY'\042/){print $(i+1)}}}' | tr -d '"' | sed -n ${num}p | sed -e 's/^[[:space:]]*//'
}

echo "Configuring ESCWA"
JMessage="{ \"mfUser\": \"\", \"mfPassword\": \"\" }"

RequestURL='http://localhost:10004/logon'
Origin='Origin: http://localhost:10004'

i="0"
while [ ! -f ./cookie.txt ]; do
    sleep 5 # Give ESCWA some time to start up
    curl -sX POST $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H "$Origin" -d "$JMessage" --cookie-jar cookie.txt
    i=$[$i+1]
    if [ $i -ge 5 ]; then
        break
    fi
done

RequestURL='http://localhost:10004/server/v1/config/mfds'
Uid=`curl -sX GET "$RequestURL" -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H "$Origin" --cookie cookie.txt | jsonValue Uid 1`
RequestURL="http://localhost:10004/server/v1/config/mfds/$Uid"
curl -sX DELETE "$RequestURL" -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H "$Origin" --cookie cookie.txt

addDS "$clusterPrefix-es01" 1086 "$clusterPrefix-es01"
if [ "$ESCount" -eq 2 ]; then
    addDS "$clusterPrefix-es02" 1086 "$clusterPrefix-es02"
fi
if [ "$DeployFsDemo" = "Y" ]; then
    addDS "$clusterPrefix-fs" 1086 "$clusterPrefix-fs"
fi

if [ "$DeployPacDemo" = "Y" ]; then
    JMessage="{ \
            \"SorName\": \"DemoPSOR\", \
            \"SorDescription\": \"Demo Redis\", \
            \"SorType\": \"redis\", \
            \"SorConnectPath\": \"$RedisIp:6379\" \
        }"

    RequestURL="http://localhost:10004/server/v1/config/groups/sors"
    sorUid=`curl -sX POST "$RequestURL" -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H "$Origin" -d "$JMessage" --cookie-jar cookie.txt | jsonValue Uid 1`

    JMessage="{ \
            \"PacName\": \"DemoPAC\", \
            \"PacDescription\": \"Demo PAC\", \
            \"PacResourceSorUid\": \"$sorUid\" \
        }"
    RequestURL="http://localhost:10004/server/v1/config/groups/pacs"
    curl -sX POST "$RequestURL" -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H "$Origin" -d "$JMessage" --cookie-jar cookie.txt
fi

service firewalld stop