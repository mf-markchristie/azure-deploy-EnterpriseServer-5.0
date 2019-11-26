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

# Join the domain
echo $Password | realm join -v -U $Join_account $Domain --install=/
if [ $? -eq 0 ]; then
    echo "JoinTo-Domain-Linux has passed"
    exit 0
else
    echo "JoinTo-Domain-Linux has FAILED"
    exit 1
fi

# Allow domain users to logon via passwords
sed -i '/PasswordAuthentication/s/no.*/yes/' /etc/ssh/sshd_config
systemctl restart sshd.service

if [ $? -eq 0 ]; then
    echo "JoinTo-Domain-Linux has passed"
    exit 0
else
    echo "JoinTo-Domain-Linux has FAILED"
    exit 1
fi
