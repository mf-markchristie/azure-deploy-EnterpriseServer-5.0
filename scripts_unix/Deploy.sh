#! /bin/bash -e
. /opt/microfocus/EnterpriseDeveloper/bin/cobsetenv ""
export MFDBFH_CONFIG=`pwd`/BankDemo_PAC/System/MFDBFH.cfg
dbfhdeploy create sql://ESPACDatabase/VSAM

# deploy catalog into the db
dbfhdeploy -quiet data add `pwd`/BankDemo_PAC/System/catalog/CATALOG.DAT sql://ESPACDatabase/VSAM/CATALOG.DAT

# deploy data files into the db
dbfhdeploy -quiet data add `pwd`/BankDemo_PAC/System/catalog/data/MFI01V.MFIDEMO.BNKACC.DAT sql://ESPACDatabase/VSAM/MFI01V.MFIDEMO.BNKACC.DAT?folder=/DATA
dbfhdeploy -quiet data add `pwd`/BankDemo_PAC/System/catalog/data/MFI01V.MFIDEMO.BNKATYPE.DAT sql://ESPACDatabase/VSAM/MFI01V.MFIDEMO.BNKATYPE.DAT?folder=/DATA
dbfhdeploy -quiet data add `pwd`/BankDemo_PAC/System/catalog/data/MFI01V.MFIDEMO.BNKCUST.DAT sql://ESPACDatabase/VSAM/MFI01V.MFIDEMO.BNKCUST.DAT?folder=/DATA
dbfhdeploy -quiet data add `pwd`/BankDemo_PAC/System/catalog/data/MFI01V.MFIDEMO.BNKHELP.DAT sql://ESPACDatabase/VSAM/MFI01V.MFIDEMO.BNKHELP.DAT?folder=/DATA
dbfhdeploy -quiet data add `pwd`/BankDemo_PAC/System/catalog/data/MFI01V.MFIDEMO.BNKTXN.DAT sql://ESPACDatabase/VSAM/MFI01V.MFIDEMO.BNKTXN.DAT?folder=/DATA

# deploy prc files
dbfhdeploy -quiet data add `pwd`/BankDemo_PAC/System/catalog/prc/YBATTSO.prc sql://ESPACDatabase/VSAM/YBATTSO.PRC?folder=/PRC\;type=lseq\;reclen=80,80
dbfhdeploy -quiet data add `pwd`/BankDemo_PAC/System/catalog/prc/YBNKEXTV.prc sql://ESPACDatabase/VSAM/YBNKEXTV.PRC?folder=/PRC\;type=lseq\;reclen=80,80
dbfhdeploy -quiet data add `pwd`/BankDemo_PAC/System/catalog/prc/YBNKPRT1.prc sql://ESPACDatabase/VSAM/YBNKPRT1.PRC?folder=/PRC\;type=lseq\;reclen=80,80
dbfhdeploy -quiet data add `pwd`/BankDemo_PAC/System/catalog/prc/YBNKSRT1.prc sql://ESPACDatabase/VSAM/YBNKSRT1.PRC?folder=/PRC\;type=lseq\;reclen=80,80

# deploy CTL cards
dbfhdeploy -quiet data add `pwd`/BankDemo_PAC/System/catalog/ctlcards/KBNKSRT1.txt sql://ESPACDatabase/VSAM/KBNKSRT1.TXT?folder=/CTLCARDS\;type=lseq\;reclen=80,80
exit 0