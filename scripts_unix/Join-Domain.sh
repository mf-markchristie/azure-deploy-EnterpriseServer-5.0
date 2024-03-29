#! /bin/bash -e
if [ "$#" -ne 3 ]
then
  echo "Not Enough Arguments supplied."
  echo "JoinTo-Domain-Linux.sh <Join_account> <Domain> <Password>"
  exit 1
fi

Join_account=$1
Domain=$2
Password=$3

yum install realmd oddjob oddjob-mkhomedir sssd samba-common samba-common-tools -y


localIp=`ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`
hostName=`hostname`
echo "$localIp $hostName.$Domain $hostName" >> /etc/hosts # To ensure DNS record is generated
# Join the domain
echo $Password | realm join -v -U $Join_account $Domain --install=/
if [ $? -ne 0 ]; then
    echo "JoinTo-Domain-Linux has FAILED"
    exit 1
fi

sed -i "s/reddog.microsoft.com/$Domain/" /etc/resolv.conf

if [ $? -ne 0 ]; then
    echo "JoinTo-Domain-Linux has FAILED"
    exit 1
fi

echo "JoinTo-Domain-Linux has PASSED"