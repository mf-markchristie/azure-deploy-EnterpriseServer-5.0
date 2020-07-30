#! /bin/bash -e
if [ "$#" -ne 10 ]
then
  echo "Not Enough Arguments supplied."
  echo "Usage Configure-ES-Node DomainDNSName DomainAdminUser DomainAdminPassword ServiceUser ServicePassword ClusterPrefix RedisPassword DeployDbDemo DeployPacDemo DeployFsDemo"
  exit 1
fi
DomainDNSName=$1
DomainAdminUser=$2
DomainAdminPassword=$3
ServiceUser=$4
ServicePassword=$5
ClusterPrefix=$6
RedisPassword=$7
DeployDbDemo=$8
DeployPacDemo=$9
DeployFsDemo=${10}
basedir=`pwd`
export TERM="xterm"

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

cd /home/$usernameFull
ln -s `pwd` /home/demouser
echo "export CCITCP2_PORT=1086" >> .bash_profile
echo "export CCITCP2_PORT=1086" >> .bashrc
"$basedir/Prepare-Demo" $DeployFsDemo $DeployDbDemo $DeployPacDemo

if [ "$DeployDbDemo" = "Y" ] || [ "$DeployPacDemo" = "Y" ]; then
    curl "https://packages.microsoft.com/config/rhel/7/prod.repo" > /etc/yum.repos.d/mssql-release.repo
    ACCEPT_EULA=Y yum install -y msodbcsql17
    ACCEPT_EULA=Y yum install -y mssql-tools krb5-workstation

    Server="$ClusterPrefix-sqlLB"

    runuser -l $usernameFull -c "echo $ServicePassword | kinit $ServiceUser@`printf '%s\n' "$DomainDNSName" | awk '{ print toupper($0) }'`"


    if [ "$DeployDbDemo" = "Y" ]; then
        cat <<EOT >> /tmp/odbc.ini
[DBNASEDB]
Driver = ODBC Driver 17 for SQL Server
Server = $Server
port = 1433
Database = BANKDEMO
Trusted_Connection = yes
EOT
    fi

    if [ "$DeployPacDemo" = "Y" ]; then
        cat <<EOT >> /tmp/odbc.ini
[SS.VSAM]
Driver = ODBC Driver 17 for SQL Server
Server = $Server
port = 1433
Database = MicroFocus\$SEE\$Files\$VSAM
Trusted_Connection = yes
[SS.MASTER]
Driver = ODBC Driver 17 for SQL Server
Server = $Server
port = 1433
Database = master
Trusted_Connection = yes
[SS.REGION]
Driver = ODBC Driver 17 for SQL Server
Server = $Server
port = 1433
Database = MicroFocus\$CAS\$Region\$DEMOPAC
Trusted_Connection = yes
[SS.CROSSREGION]
Driver = ODBC Driver 17 for SQL Server
Server = $Server
port = 1433
Database = MicroFocus\$CAS\$CrossRegion
Trusted_Connection = yes
EOT
    fi
    odbcinst -i -s -l -f /tmp/odbc.ini
fi

. /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv ""
casperm.sh << EOF
n
$usernameFull

EOF

if [ "$DeployFsDemo" = "Y" ]; then
    yum install nfs-utils rpcbind -y
    echo "$ClusterPrefix-fs:/FSdata /DATA nfs rw 0 0" >> /etc/fstab
    mkdir /DATA
    mount -a
    unzip ./BankDemo_FS.zip
    rm -f ./BankDemo_FS.zip
    chown -R $usernameFull ./BankDemo_FS
    chmod -R 755 ./BankDemo_FS
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; mfds /g 5 `pwd`/BankDemo_FS/Repo/BNKDMFS.xml D"
    sleep 5
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; export FSHOST=$ClusterPrefix-fs; casstart32 -rBNKDMFS"
fi

if [ "$DeployDbDemo" = "Y" ]; then
    unzip ./BankDemo_SQL.zip
    rm -f ./BankDemo_SQL.zip
    chown -R $usernameFull ./BankDemo_SQL
    chmod -R 755 ./BankDemo_SQL
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; mfds /g 5 `pwd`/BankDemo_SQL/Repo/BNKDMSQL.xml D"
    sleep 5
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; casstart64 -rBNKDMSQL"
fi

if [ "$DeployPacDemo" = "Y" ]; then
    yum install curl -y
    unzip ./BankDemo_PAC.zip
    rm -f ./BankDemo_PAC.zip
    chown -R $usernameFull ./BankDemo_PAC
    chmod -R 755 ./BankDemo_PAC
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; mfds /g 5 `pwd`/BankDemo_PAC/Repo/BNKDM.xml D"
    sleep 5

    JMessage="{ \"mfUser\": \"\", \"mfPassword\": \"\" }"
    RequestURL="http://$ClusterPrefix-esadmin:10086/logon"
    Origin="Origin: http://$ClusterPrefix-esadmin:10086"
    curl -sX POST $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H "$Origin" -d "$JMessage" --cookie-jar cookie.txt

    JMessage="{ \
        \"mfCASSOR\": \":ES_SCALE_OUT_REPOS_1=DemoPSOR=redis,$ClusterPrefix-redis:6379##TMP\", \
        \"mfCASPAC\": \"DemoPAC\" \
    }"
    HostName=`hostname`
    RequestURL="http://$ClusterPrefix-esadmin:10086/native/v1/regions/$HostName/1086/BNKDM"
    curl -sX PUT $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H "$Origin" -d "$JMessage" --cookie-jar cookie.txt
    if [ $? -ne 0 ]; then
        sleep 30
        curl -sX PUT $RequestURL -H 'accept: application/json' -H 'X-Requested-With: AgileDev' -H 'Content-Type: application/json' -H "$Origin" -d "$JMessage" --cookie-jar cookie.txt
    fi
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; mfsecretsadmin write microfocus/CAS/SOR-DEMOPSOR-Pass $RedisPassword"

    cp $basedir/Deploy.sh .
    chmod +xr ./Deploy.sh
    runuser -l $usernameFull -c "./Deploy.sh"
    if [ $? -ne 0 ]; then # If this fails it means it might be running somewhere else, so wait for it to complete
        sleep 30
    fi
    rm ./Deploy.sh
    runuser -l $usernameFull -c ". /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv; export CCITCP2_PORT=1086; casstart64 -rBNKDM -s:c"
fi