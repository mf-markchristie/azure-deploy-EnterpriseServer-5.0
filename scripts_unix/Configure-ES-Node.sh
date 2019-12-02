#! /bin/bash -e
if [ "$#" -ne 10 ]
then
  echo "Not Enough Arguments supplied."
  echo "Usage Configure-ES-Node DomainDNSName DomainAdminUser DomainAdminPassword ServiceUser ClusterPrefix RedisPassword DeployDbDemo DeployPacDemo DeployFsDemo"
  exit 1
fi
DomainDNSName=$1
DomainAdminUser=$2
DomainAdminPassword=$3
ServiceUser=$4
ClusterPrefix=$5
RedisPassword=$6
DeployDbDemo=$7
DeployPacDemo=$8
DeployFsDemo=$9
basedir=`pwd`
export TERM="xterm"
shift

service firewalld stop

"$basedir/Join-Domain.sh" $DomainAdminUser $DomainDNSName $DomainAdminPassword
if [ $? -ne 0 ]; then
    echo "JoinTo-Domain-Linux has FAILED"
    exit 1
fi

usernameFull="$ServiceUser@$DomainDNSName"

realm permit $usernameFull
if [ $? -ne 0 ]; then
    echo "Failed to provide login permissions."
    exit 1
fi
mkhomedir_helper $usernameFull

runuser -l $usernameFull -c '. /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; mfds --listen-all; mfds &'
if [ $? -ne 0 ]; then
    echo "Failed to start MFDS."
    exit 1
fi

cd ~mfservice@contoso.local
"$basedir/Prepare-Demo" $DeployFsDemo $DeployDbDemo $DeployPacDemo

if [ "$DeployDbDemo" = "Y" ] || [ "$DeployPacDemo" = "Y" ]; then
    curl "https://packages.microsoft.com/config/rhel/7/prod.repo" > /etc/yum.repos.d/mssql-release.repo
    ACCEPT_EULA=Y yum install -y msodbcsql17
    ACCEPT_EULA=Y yum install -y mssql-tools

    Server="$ClusterPrefix-sqlLB"

    if [ "$DeployDbDemo" = "Y" ]; then
        cat <<EOT >> /tmp/odbc.ini
[DBNASEDB]
Driver = ODBC Driver 17 for SQL Server
Server = $Server
port = 1433
Database = BANKDEMO
EOT
    fi

    if [ "$DeployPacDemo" = "Y" ]; then
        cat <<EOT >> /tmp/odbc.ini
[SS.VSAM]
Driver = ODBC Driver 17 for SQL Server
Server = $Server
port = 1433
Database = MicroFocus\$SEE\$Files\$VSAM
[SS.MASTER]
Driver = ODBC Driver 17 for SQL Server
Server = $Server
port = 1433
Database = master
[SS.REGION]
Driver = ODBC Driver 17 for SQL Server
Server = $Server
port = 1433
Database = MicroFocus\$CAS\$Region\$DEMOPAC
[SS.CROSSREGION]
Driver = ODBC Driver 17 for SQL Server
Server = $Server
port = 1433
Database = MicroFocus\$CAS\$CrossRegion
EOT
    fi
    odbcinst -i -s -l -f /tmp/odbc.ini
fi

if [ "$DeployFsDemo" = "Y" ]; then
    yum install nfs-utils rpcbind -y
    echo "$ClusterPrefix-fs:/FSdata /DATA nfs rw 0 0" >> /etc/fstab
    mkdir /DATA
    mount -a
    unzip ./BankDemo_FS.zip
    chown -R $usernameFull ./BankDemo_FS
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; mfds /g 5 `pwd`/BankDemo_FS/Repo/BNKDMFS.xml D"
    sleep 5
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; export FSHOST=$ClusterPrefix-fs; casstart -rBNKDMFS"
fi

if [ "$DeployDbDemo" = "Y" ]; then
    unzip ./BankDemo_SQL.zip
    chown -R $usernameFull ./BankDemo_SQL
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; mfds /g 5 `pwd`/BankDemo_SQL/Repo/BNKDMSQL.xml D"
    sleep 5
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; casstart -rBNKDMSQL"
fi

if [ "$DeployPacDemo" = "Y" ]; then
    yum install curl -y
    unzip ./BankDemo_PAC.zip
    chown -R $usernameFull ./BankDemo_PAC
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; mfds /g 5 `pwd`/BankDemo_SQL/Repo/BNKDM.xml D"
    sleep 5

    JMessage="{ \"mfUser\": \"\", \"mfPassword\": \"\" }"
    RequestURL="http://$ClusterPrefix-esadmin:10004/logon"
    Origin="Origin: http://$ClusterPrefix-esadmin:10004"
    curl -sX POST $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H "$Origin" -d "$JMessage" --cookie-jar cookie.txt

    JMessage="{ \
        \"mfCASSOR\": \":ES_SCALE_OUT_REPOS_1=DemoPSOR=redis,$ClusterPrefix-redis:6379##TMP\", \
        \"mfCASPAC\": \"DemoPAC\" \
    }"
    HostName=`hostname`
    $RequestURL = "http://$ClusterPrefix-esadmin:10004/native/v1/regions/$HostName/1086/BNKDM"
    curl -sX PUT $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H "$Origin" -d "$JMessage" --cookie-jar cookie.txt

    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; mfsecretsadmin write microfocus/CAS/SOR-DemoPSOR-Pass $RedisPassword"

    runuser -l $usernameFull -c "$basedir/Deploy-Start-ES.sh BNKDM"
fi