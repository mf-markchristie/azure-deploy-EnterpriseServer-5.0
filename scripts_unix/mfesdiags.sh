#!/usr/bin/env bash
#set -x
MFESDIAGS_VER=6.2i
################################################################################
################################################################################
##                                                                            ##
## Micro Focus Support - Enterprise Server 6.x Assistance Utility             ##
##                                                                            ##
## @(#)mfesdiags        6.x                                                   ##
##                                                                            ##
## Purpose: This utility was created to assist the Micro Focus Support        ##
##          in gleaning information from the user's Enterprise Server         ##
##          environment.                                                      ##
##                                                                            ##
##     ******************************************************************     ##
##     * Copyright 1989-2016 Micro Focus International Ltd.             *     ##
##     * All Rights Reserved.                                           *     ##
##     * This diagnostic program is provided for use by users of        *     ##
##     * Micro Focus products and may be used, modified and             *     ##
##     * distributed as part of your application provided that you      *     ##
##     * properly acknowledge the copyright of Micro Focus in this      *     ##
##     * material.                                                      *     ##
##     ******************************************************************     ##
##                                                                            ##
##                                                                            ##
## History:                                                                   ##
##                                                                            ##
## Date    Who    Remarks                                                     ##
## ------- ----   ------------------------------------------------------      ##
## 18Nov04 BDS    Original                                                    ##
## 01Nov07 BDS    General reworking                                           ##
## 21Jan08 BDS    64-bit reworking                                            ##
## 04Feb08 BDS    compress $OUTFILE to .trz   
## 25Sep13 GMC    v6.0 Updating to mfesdiags                                  ##
##                 removed y/n prompt to start
#                  specify server name on command line
#                  get user ID
#                  copying all *.dat files
#                  getting MFDS port from mfds script file
#                  Logging to SNAPLOG 
#                  Mdump to also get security info and env vars
#                  Getting CTF trace configuration file and any CTF logs
#                  Getting dfhdrdat, EXTFH, COBCONFIG, cobver
#                  Copying files from system dir to separate folder
#                  tar file now called mfesdiags
#                  Allowing ES_SERVER and region to be expanded to region name
#                  Only wait for mfsupport o/p if command was successful
#                  Checking more results from operations, making tests more robust.
# 16Oct2013 GMC    Making tmp directory user-specific to have permissions to remove
# 21Oct2013 GMC    If mdump wasn't successful don't try to lookup region variables
# 10Sep2014 GMC  6.0b  Fixed indirection lookup for all shells (in checkfordollar)
# 14Jul2015 GMC  6.0c  Using CCITCP2_PORT if set in environment
#                      Copying mfds.journal.ctf.txt if it exists
#                      Also copy .xml and .cfg files with .dat files (from etc)
#                      Create tar of mfds directory as a relative path
#                      Prompt for region if not specified/valid
#                      Attempt MFDS region export
# 16Sep2015 GMC 6.1 Can't use grep -F on Solaris, need run ggrep (or XPG4)
#                   Don't force script to run as bourne shell
#                   Not creating MFDS region Export as sub-dirs end up owned by root
# 19Jan2016 GMC 6.2 Exporting mfds with -x to /tmp, copying files so are owned by current user. Using SYSAD on mfds command
#                   adding '-a localhost' option to all mdump commands
#                   Getting actual Journal log location from config file using mfds -h
#                   Creating .txt version of journal file to copy 
#                   Using schemaadmin for mdump command (in case mfds was started with -b (which doesn't allow anonymous binds)). #2844227
# 12Mar2016 GMC 6.2a Check output from mfds -t to see if -j was used for journal location, otherwise get location from mfds options file
#                   Finding CASROOT only at start of line in cas.cfg (it may have old commented-out entries)
#                   Check status of mdump region export command - if unsuccessful script carries on but won't have access to get region config...
#                   Create tmp directory for mfds export so *we* own it - mfds runs as root so would otherwise prevent access
#                   If we needed anonymous access to get initial mdump o/p retain this for the subsequent security dump
#                   Setting umask=002 so directory access for groups is allowed
#                   If no journal.txt file was created re-try mfds -t specifying the output directory (write permission)
#                   Fixed problem of files being created in wrong tmp dir - not CD-ing anymore
#                   Capture stderr from casdump and only calling casdup if .rec was created
#                   Redirecing stdout from mfsupport (otherwise hangs on some platforms)
#                   Retrying mfsupport under ksh if error running under current shell
#                   mfpoll.txt now being created directly in WRKDIR
# 16Mar2016 GMC 6.2b Updated prompt for region name to be less ambiguous
#                   Only attempt to make TMP_MFDS_EXPORT_DIR if it doesn't still exist
#                   Getting 2nd network status at end of run
#                   Re-organised to collect useful info when the region is not valid on this mfds
#                   Message asking for mfds.journal.ctf.txt if we don't have access to copy it
#                   Running mfsupport in the backgroud and earlier in the script.
#                   Removed unnecessary mdump to get COBMODE
#                   Creating journal.txt directly in SNAPDIR
# 18Mar2016 GMC 6.2c Added prompt for user/pass for mdump command if default credentials do not work
#                   Checking for SERVER_DOWN on initial mdump attempt 
#                   Added prompt to remove tmp files at end of script
#                   Remove lines with Password in from output files
# 21Mar2016 GMC 6.2d Collecting ifconfig output (sbin)
# 18May2016 GMC 6.2e Now using grep -i for Textfile and Binfile Location in CTF.cfg
#                    Typo in version name string
#                    Using .txt* and .ctb* to copy CTF files so we get all generations
# 13Jul2016 GMC 6.2f Allow script to continue even if no sysdir (region may never have been started)
# 11Jan2017 GMC      Always resolve $ variables with lookup as they may be set in OS environment. ES_SERVER is special case
# 17Jan2017 GMC 6.2g Attempting additional casdumps
# 17Mar2017 GMC 6.2h Escaping '$' and use default grep for $ detection on solaris
#                    Using cobmode to set user working mode to 32|64 for casdump to work
# 11Apr2017 GMC      mkdir to keep system/default files separate (.cfg etc)
# 20Apr2017 GMC      Modified final prompt for removal of tmp files (problem with RegEx in some shells)
#                    Converting region name to uppercase when entered on command line
# 21Apr2017 GMC 6.2i Added check to ensure CCITCP2_PORT is set to a number
#                  
################################################################################

################################################################################
#Global Variables
MDUMP_USER=schemaadmin
MDUMP_PASS=schemaadmin
MFDS_USER=SYSAD
MFDS_PASS=SYSAD

################################################################################

################################################################################
# Functions 
################################################################################

# logit function declaration
logit()
{
	MSG_LEVEL=$1

	# Shifts the position of the parameters over one place.
	shift

	if [ "$MSG_LEVEL" -ge 1 ] && [ "$MSG_LEVEL" -le 3 ]; then
		if [ "$MSG_LEVEL" -eq 1 ]; then
			echo "$@"
		elif [ "$MSG_LEVEL" -eq 2 ]; then
			echo "$@" | tee -a $SNAPLOG
		elif [ "$MSG_LEVEL" -eq 3 ]; then
# For testing, o/p level3 to screen and log 
#			echo "$@" 
			echo "$@" >>  $SNAPLOG
		fi
	fi
}

################################################################################

################################################################################

getCTFfromMFTRACE()
{

logit 3 getCTFfromMFTRACE $1

#Get MFTRACE_LOGS setting

#get only MFTRACE_LOGS lines
grep MFTRACE_LOGS $MDUMP_ENV_FILE > $1_ENV_MFTRACE
while read line
do
# check whether we have an exact match of the variable
  if [ `echo "$line" | cut -c1-12` = "MFTRACE_LOGS" ]; then 
# get the bit after the equals and remove any spaces
    MFtraceConfig_LOGS=`echo $line | cut -f2 -d= | sed -e 's/^[ \t]*//'`
    logit 3 MFtraceConfig_LOGS=$MFtraceConfig_LOGS
  fi
done < $MDUMP_ENV_MFTRACE

if [ "${MFtraceConfig_LOGS}x" = "x" ] ; then  # MFTRACE_LOGS not set region 
  logit 3 "MFTRACE_LOGS not set in region"
  if [ "${MFTRACE_LOGS}x" = "x" ] ; then # MFTRACE_LOGS not set in OS
    logit 3 "MFTRACE_LOGS not set in OS environment"
    return # from this function
  else # MFTRACE_LOGS is set in OS environment - get the logs
    mkdir $SNAPDIR/CTFlogsFromOSenv >>$SNAPLOG
    RET=$?
    if [ $RET -ne 0 ] ; then
      logit 3 mkdir logsFromOSenv returned:$RET
    fi
    logit 2 "copying CTF $1 files"
    if [ $1 = BIN ]; then
      logit 3 cp -p $MFTRACE_LOGS/'*.ctb' $SNAPDIR/CTFlogsFromOSenv
      cp -p $MFTRACE_LOGS/*.ctb $SNAPDIR/CTFlogsFromOSenv >> $SNAPLOG 2>&1
      RET=$?
      if [ $RET -ne 0 ]; then
        logit 2 "Unable to copy CTF $1 files from $MFTRACE_LOGS [ret=$RET]"
      fi    		
    else
      logit 3 cp -p $MFTRACE_LOGS/'*.log' $SNAPDIR/CTFlogsFromOSenv
      cp -p $MFTRACE_LOGS/*.log $SNAPDIR/CTFlogsFromOSenv >> $SNAPLOG  2>&1
      RET=$?
      if [ $RET -ne 0 ]; then
        logit 2 "Unable to copy CTF $1 files from $MFTRACE_LOGS [ret=$RET]"
      fi    		
    fi
  fi
else # Region env var is set
  logit 3 "MFtraceConfig_LOGS=[$MFtraceConfig_LOGS]"
  NEW_PATH=
  CheckForDollar $MFtraceConfig_LOGS
  MFtraceConfig_LOGS=$NEW_PATH
  mkdir $SNAPDIR/CTFlogsFromRegionEnv >>$SNAPLOG  2>&1
  RET=$?
  if [ $RET -ne 0 ]; then
    logit 3 mkdir returned:$RET
  fi
  logit 2 "copying CTF $1 files"
  if [ $1 = BIN ]; then
      logit 3 cp -p $MFtraceConfig_LOGS/'*.ctb' $SNAPDIR/CTFlogsFromRegionEnv
      cp -p $MFtraceConfig_LOGS/*.ctb $SNAPDIR/CTFlogsFromRegionEnv >> $SNAPLOG 2>&1
      RET=$?
      if [ $RET -ne 0 ]; then
        logit 2 Unable to copy CTF $1 files from $MFtraceConfig_LOGS [ret=$RET]
      fi    		
  else
      logit 3 cp -p $MFtraceConfig_LOGS/'*.log' $SNAPDIR/CTFlogsFromRegionEnv
      cp -p $MFtraceConfig_LOGS/*.log $SNAPDIR/CTFlogsFromRegionEnv >> $SNAPLOG  2>&1
      RET=$?
      if [ $RET -ne 0 ]; then
        logit 2 Unable to copy CTF $1 files from $MFtraceConfig_LOGS [ret=$RET]
      fi    		
  fi
  return # from this function
fi
}
#####################################################################################
# get_MFTRACE_LOGS function declaration
get_MFTRACE_LOGS()
{

logit 3 get_MFTRACE_LOGS

if [ ! $MFTRACE_CONFIG  ]
then
  logit 3 No CTF trace config file, returning
  return
else
  logit 3 MFTRACE_CONFIG set to [$MFTRACE_CONFIG]
fi

# check in MFTRACE_CONFIG file whether the log location is set for binfile and/or textfile
# else check if MFTRACE_LOGS is set in region configuration
# otherwise check for MFTRACE_LOGS in OS environment    

#Need to find the valid mftrace.dest setting
MFTRACE_DEST_SET=$(grep "^mftrace.dest" $MFTRACE_CONFIG | awk -F"=" '{print $2}')
logit 3 MFTRACE_DEST_SET=$MFTRACE_DEST_SET
MFTRACE_DEST_SET=`echo $MFTRACE_DEST_SET | sed -e 's/^[ \t]*//'`

#Check if binfile is set:
echo $MFTRACE_DEST_SET | grep -i "binfile" >> $SNAPLOG
if [ $? -eq 0 ] ; then
  BINDEST=1
else 
  BINDEST=0
fi
logit 3 BINDEST=$BINDEST

#Check if txtfile is set:
echo $MFTRACE_DEST_SET | grep -i "textfile" >> $SNAPLOG
if [ $? -eq 0 ] ; then
  TXTDEST=1
else 
  TXTDEST=0
fi
logit 3 TXTDEST=$TXTDEST

if [ $BINDEST=1 -o $TXTDEST=1 ] 
then
  CTFDESTSET=1
else
  CTFDESTSET=0
fi
logit 3 CTFDESTSET2=$CTFDESTSET

MFTRACE_TXT_LCN=$(grep -i "^mftrace.emitter.textfile#location" $MFTRACE_CONFIG | awk -F"=" '{print $2}')
MFTRACE_TXT_LCN=`echo $MFTRACE_TXT_LCN | sed -e 's/^[ \t]*//'`
logit 3 MFTRACE_TXT_LCN=$MFTRACE_TXT_LCN 
MFTRACE_BIN_LCN=$(grep -i "^mftrace.emitter.binfile#location" $MFTRACE_CONFIG | awk -F"=" '{print $2}')
logit 3 MFTRACE_BIN_LCN=$MFTRACE_BIN_LCN  
MFTRACE_BIN_LCN=`echo $MFTRACE_BIN_LCN | sed -e 's/^[ \t]*//'`
logit 3 MFTRACE_BIN_LCN2=$MFTRACE_BIN_LCN

CTFLOCSET=0
if [ "${MFTRACE_TXT_LCN}x" != "x" -o "${MFTRACE_BIN_LCN}x" != "x" ] ; then 
  CTFLOCSET=1
fi
logit 3 CTFLOCSET=$CTFLOCSET 

# now check where we get the files from 
# if BINDEST get files from BINloc or MFTRACE:
#  if BINloc get files from BINloc 
#  else if TEXTloc get BIN files from TEXTloc - incorrect behaviour (Unix) - take out 
#       else get BIN files from MFTRACE_LOGS
if [ $BINDEST = 1 ]; then
  logit 3 "BINDEST is set"
  if [ "${MFTRACE_BIN_LCN}x" != "x" ] ; then
    logit 3 "BIN LOC is set:$MFTRACE_BIN_LCN"
    mkdir $SNAPDIR/CTFlogs-Binfile >>$SNAPLOG 2>&1
    RET=$?
    if [ $RET -ne 0 ]; then
      logit 3 Unable to mkdir $SNAPDIR/CTFlogs-Binfile [ret=$RET]
    fi    		
    logit 2 copying CTF BIN files
    logit 3 cp -p $MFTRACE_BIN_LCN/'*.ctb*' $SNAPDIR/CTFlogs-Binfile
    cp -p $MFTRACE_BIN_LCN/*.ctb* $SNAPDIR/CTFlogs-Binfile >> $SNAPLOG  2>&1
    RET=$?
    if [ $RET -ne 0 ]; then
      logit 2 Unable to copy CTF files from $MFTRACE_BIN_LCN [ret=$RET]
    fi    		
    CTFBINFILE=1
    if [ $TXTDEST = 0 ] ; then # bindest was set OK but since txtdest isn't set there is no more to do
      logit 3 "Bin dest set but textdest isn't so nothing more to copy"
      return 
    fi
  else # BINdest set but no BINLOC so get from MFTRACE_LOGS lcn:
    logit 3 "bindest set, BINloc not set so get BIN logs from MFTRACE_LOGS lcn"
    getCTFfromMFTRACE BIN
  fi
else
  logit 3 "BINDEST NOT set - not copying ctb files"
fi

#check where we get the text files from 
#if TEXTloc set 
#  if Textdest is set OR Bindest is NOT set then get text logs from this textloc (whether TEXTdest is set or not)
#else
#  If TEXTdest is set get text logs from MFTRACE

if [ "${MFTRACE_TXT_LCN}x" != "x" ] ; then # TXT location is set
  if [[ $TXTDEST = 1 || $BINDEST = 0 ]] ; then
    logit 3 TXT location is set - get TXT logs from here
    mkdir $SNAPDIR/CTFlogs-Textfile >>$SNAPLOG  2>&1
    RET=$?
    if [ $RET -ne 0 ]; then
      logit 3 Unable to mkdir $SNAPDIR/CTFlogs-Textfile [ret=$RET]
    fi    		
    logit 2 copying CTF TXT files
    logit 3 cp -p $MFTRACE_TXT_LCN/'*.log*' $SNAPDIR/CTFlogs-Textfile
    cp -p $MFTRACE_TXT_LCN/*.log* $SNAPDIR/CTFlogs-Textfile >> $SNAPLOG  2>&1
    RET=$?
    if [ $RET -ne 0 ]; then
      logit 2 Unable to copy CTF Text files from $MFTRACE_TXT_LCN [ret=$RET]
    fi    		
    set CTFTXTFILE=1
  else
    logit 3 TXT location is set but not TXTDEST, or BINDEST was also set!
  fi  
else
   logit 3 TXT location Not set, check TEXTdest
   if [ $TXTDEST = 1 ]; then
     logit 3 TEXTdest set - get TXT logs from MFTRACE lcn
     getCTFfromMFTRACE TXT
   fi
fi
logit 3 end get_MFTRACE_LOGS

}
################################################################################
# getEnvFromFile function declaration
# takes the name and length of a region env var and the file to lookup
# Returns the value of the region env var as set in the region config
# Can use logit 3 from this function but not logit 2 or echo to stdout as this 
#  messes up the return
#####################################################################################
getEnvFromFile ()
{
NAME=$1
LEN=$2
FILE=$3
#get only lines with this name
logit 3 getEnvFromFile $NAME, $LEN, $FILE, $MDUMP_ENV_ONLY

#Special case
if [ $NAME = ES_SERVER ] ; then
  logit 3 special case $NAME
	ES_SERVER=$SRVNAME
  CONFIG_SET=$ES_SERVER
  # Note CONFIG_SET can be reset to null if NO_MFDS is true...
else # not special case

#Only do lookup if NO_MFDS is zero, otherwise return null (should result in getting default value)
if [ $NO_MFDS -eq 0 ] ; then
#convert to uppercase
#NAME=`echo $NAME | tr '[:lower:]' '[:upper:]'`
  grep -i  "$NAME" $FILE > $MDUMP_ENV_ONLY

  while read line
  do
# check whether we have an exact match of the variable
    if [ "`echo "$line" | cut -c1-$LEN`" = "$NAME" ]; then 
# get the bit after the equals and remove any spaces
      CONFIG_SET=`echo $line | cut -f2 -d= | sed -e 's/^[ \t]*//'`
      logit 3 CONFIG_SET=$CONFIG_SET
    fi
  done < $MDUMP_ENV_ONLY
else # not NO_MFDS
  logit 3 NO_MFDS set, setting CONFIG_SET to null
  CONFIG_SET=
fi # NO_MFDS

fi # special case


if [ "${CONFIG_SET}x" = "x" ] # null
then
   logit 3 "$NAME not found in region's configuration"
# Need this echo to return the value from this function
   echo ""
else
# do not call CheckForDollar here as it would be recurrsive
# set return value
# Need this echo to return the value from this function
  echo $CONFIG_SET
fi

}
# ============================================================================
#CheckForDollar
# EG: call :CheckForDollar REGION_WORKAREA
# Takes in path/string and checks if there is a $ anywhere in string - if not then return.
# If $variable NOT already set, lookup path for this $variable from the mdump ENV o/p file
# Note: this should allow ES_SERVER and region to be substituted if referenced directly.
# Substitutes the variable for the actual path/setting
# Recursively call this function to check for and expand any more $ strings
# Pass fully-expanded path back (sets variable passed in to new string)
# ============================================================================
CheckForDollar()
{
DOLLARSTR=$1
logit 3 CheckForDollar DOLLARSTR=$DOLLARSTR

# Check if there is a $ anywhere in the passed in string:

# On solaris need to use gnu grep (ggrep)
# Now using standard grep on Solaris but without the -F (fixed-strings) arg, escape the $ (special char) instead
if [ `uname` == "SunOS" ]; then
  echo  "$DOLLARSTR" | grep '\$' >> $SNAPLOG
else
  echo  "$DOLLARSTR" | grep -F '$' >> $SNAPLOG
fi  
if [ $? -eq 0 ] ; then
  DollarFound=1
  logit 3  $ found in string $DOLLARSTR
else
  DollarFound=0
  NEW_PATH=$DOLLARSTR
  logit 3 No $ found in string $DOLLARSTR: NEW_PATH=$NEW_PATH
  return
fi

#Check whether string already has a trailing slash - to leave it like this at end
#Add a trailing slash for now if there isn't one
case $DOLLARSTR in
*/) 
    TrailingNeeded=1 # need to make sure string has slash at end when we are done
    logit 3 trailing slash found
  ;;
*) 
    TrailingNeeded=0
    logit 3 no trailing slash found
    DOLLARSTR=$DOLLARSTR/ 
  ;;
esac

logit 3 DOLLARSTR-with slash=$DOLLARSTR

# Check if 1st char is a $ 
if [ `echo $DOLLARSTR |cut -c1-1` = $ ]; then
  Dollar1=1
  logit 3 1st char is  dollar 
else 
  Dollar1=0
  logit 3 1st char NOT a dollar 
fi

# split string at the 1st $ - keep 1st bit if not NULL and take the 2nd bit upto the next slash as env name and lookup 
# If 1st char of initial string was a $ just take the rest of the string
str1=

sep='$'
case $DOLLARSTR in
  (*"$sep"*)
    str1=${DOLLARSTR%%"$sep"*} # string before sep
    str2=${DOLLARSTR#*"$sep"}  # string after sep
    ;;
  (*)
    str2=$DOLLARSTR
    str1=
    ;;
esac

logit 3 str1=$str1
logit 3 str2=$str2

# Only want the part upto the (first) slash (should be the name of the variable set) from str2
# Should have a trailing slash even if its the last/only string (added on entry to this function)

sep='/'
case $str2 in
  (*"$sep"*)
    ENVNAME=${str2%%"$sep"*} # string before sep
    TheRest=${str2#*"$sep"}  # string after sep
    ;;
  (*)
    TheRest=$str2
    ENVNAME=
    ;;
esac

logit 3 ENVNAME=$ENVNAME
logit 3 TheRest=$TheRest

# check if ENVNAME is already set or still needs translating:
# This needs to work for all shells, can't just use BASH indirection syntax {!ENVNAME}
# Note double-dollar translates to PID so need to esacpe the 1st one
logit 3 ENVNAME=$ENVNAME, dollarENVNAME=\$$ENVNAME
# Use backquotes to get the actual string - need to escape the backslash!

# Always do lookup for now
# problem if env var is already set in the OS environment
##if [ `eval echo \\\$$ENVNAME`x != x ] ; then
#  logit 3 $ENVNAME is already set - no need to lookup
#  # set ENVNAME_SET to the contents of what the variable in ENVNAME is pointing to!
#  ENVNAME_SET=`eval echo \\\$$ENVNAME`
##else
  logit 3 $ENVNAME not yet resolved
# get the path that this string is set to
# also need to pass length of var and file to check in
  ENVNAME_SET=`getEnvFromFile $ENVNAME ${#ENVNAME} $MDUMP_ENV_FILE`
#If we didn't find this ENV in the config file, set it to some value?

  ENVNAME_SET=${ENVNAME_SET%/} # Remove any trailing slash
  logit 3 remove any trailing slashes: ENVNAME_SET=$ENVNAME_SET

#set specific environment name (i.e. that ENVNAME is current set to) to the relevant string:
  logit 3 setting $ENVNAME to $ENVNAME_SET
#  eval $ENVNAME=\$ENVNAME_SET
  eval $ENVNAME=$ENVNAME_SET
# env var (e.g. BASE) should now be set (so we don't need to look it up again)
##fi

# re-compose string:
# Check whether str1 was null:
if [ "${str1}x" = "x" ] ; then # null
  NEW_PATH="$ENVNAME_SET/$TheRest"
else
  str1=${str1%/} # Remove any trailing slash
  logit 3 Remove any trailing slash: str1=$str1
  NEW_PATH="$str1/$ENVNAME_SET/$TheRest"
fi  

# Now we should have a path with the initial $ variable expanded.
logit 3 NEW_PATH=$NEW_PATH

#check if need to end up with a trailing slash
if [ $TrailingNeeded = 1 ] ; then
  case $NEW_PATH in
    */) : ;;
    *) NEW_PATH=$NEW_PATH/ ;; # add trailing slash back
  esac
  NEW_PATH="$NEW_PATH"/ # path already has trailing slash
else
  NEW_PATH=${NEW_PATH%/} # Remove any trailing slash
fi
logit 3 add or remove trailing slash: NEW_PATH=$NEW_PATH

# Now need to check whether there is another $ in the expanded path
CheckForDollar $NEW_PATH

logit 3 end of checkForDollar: NEW_PATH=$NEW_PATH
}
################################################################################
# get_DFHDRDAT function declaration
#####################################################################################
get_DFHDRDAT ()
{
#get RDO from region
logit 3 get_DFHDRDAT 

# Setup to get default file if mfds not running-no region config
if [ $NO_MFDS -eq 1 ] ; then
  logit 3 NO_MFDS set - need default file
  DFHDRDAT='<null>'
else
  logit 3 checking for region definition
  DFHDRDAT=$(grep "mfCASTXRDTP" $MDUMP_FILE | awk -F":" '{print $2}')
fi

# Check whether it was set to something in region
# On solaris need to use gnu grep (ggrep)
if [ `uname` == "SunOS" ]; then
  echo  "$DFHDRDAT" | ggrep -F '<null>' >> $SNAPLOG
else
  echo  "$DFHDRDAT" | grep -F '<null>' >> $SNAPLOG
fi
if [ $? != 0 ] # DFHDRDAT is set to some string
then
  logit 3 DFHDRDAT=$DFHDRDAT
  # remove leading (white)spaces:
  DFHDRDAT=`echo $DFHDRDAT | sed -e 's/^[ \t]*//'`
  logit 3 DFHDRDAT=$DFHDRDAT
  NEW_PATH=
  CheckForDollar $DFHDRDAT
  DFHDRDAT=$NEW_PATH

  logit 2 "Copying RDO file from region's configured location"
  logit 3 cp -p $DFHDRDAT/dfhdr* $WRKDIR
  cp -p $DFHDRDAT/dfhdr* $WRKDIR
  RET=$?
  if [ $RET -ne 0 ]; then
    logit 2 Unable to copy RDO file from $DFHDRDAT [ret=$RET]
  fi    		
else
  logit 3 "RDO file not configured in region - try default location"
  logit 2 "Copying RDO file from default location"
  logit 3 cp -p $COBDIR/etc/cas/dfhdr* $WRKDIR
  cp -p $COBDIR/etc/cas/dfhdr* $WRKDIR
  RET=$?
  if [ $RET -ne 0 ]; then
    logit 2 Unable to copy RDO file defule location $COBDIR/etc/cas [ret=$RET]
  fi    		
fi
}
################################################################################
# End of Functions 
################################################################################

################################################################################
# SCRIPT STARTS HERE
################################################################################

WRKDIR_BASE=/tmp/$USER
WRKDIR=$WRKDIR_BASE/mfesdiags.tmp     # diagnostics are collected here.
OUTDIR=$PWD                   # mfesdiags.trz is written to here.



SNAPDIR=$WRKDIR
SNAPLOG=$SNAPDIR/snapshot.log

clear

echo mfesdiags script version $MFESDIAGS_VER

echo "Ensure you are logged on as the Enterprise Server Administrator"
echo "and that you have your COBOL environment loaded."   
echo "This script will gather diagnostic information about an ES Server"
echo "and the environment."
echo "It creates mfesdiags.trz which you should forward to support"
echo ' '
echo "You should enter the relevent region name when prompted"
echo "(The region name could also be specified directly on the command line)"
echo ' '
#####echo "Press 'y' to continue? (y/n)"
#  read RESP
#  case $RESP in
#    y|Y)
#       echo ' '
#       ;;
#    *) echo "Run terminated"
#       exit 1
#       ;;
#  esac

#We cd to the WRKDIR if it exists and then move 1 level up
#Need to cd back to it once we have created it again
if test -d $WRKDIR
then
   echo "Deleting old work area: $WRKDIR"
   cd $WRKDIR
   rm -rf *
   cd ..
   rmdir $WRKDIR
   RET=$?
   if [ $RET -ne 0 ] ; then
        echo "Couldn't delete work area"
        exit 6
   fi
fi

#set umask to allow read for others
umask 002

#cd into WRKDIR once it has been created
mkdir -p $WRKDIR
RET=$?
if [ $RET -eq 0 ]
then
        touch $SNAPLOG
        logit 3 mfesdigs script verion: $MFESDIAGS_VER
        logit 2 "Creating new work area: $WRKDIR"
        cd $WRKDIR
else
        echo "Couldn't make work area: $WRKDIR"
        exit 3
fi

if [ ! "$COBDIR" ] # is COBDIR set ?
then
   echo ' ';echo "COBOL environment is not set.  Exiting."
   exit 2
fi

## is user root? - library path is dropped when using root
if test -w /etc/passwd
then
        echo "You should not run this script as root"
        exit 3
fi

## cas.cfg is created when you elect to install ES or run casperm

if [ ! -f $COBDIR/etc/cas/cas.cfg ]
then
   logit 2 "cas.cfg missing, suggests ES is not configured"
   exit 4
fi

#need to set this to a region that doesn't exist so we work out to prompt for a valid region/directory!
SRVNAME=dummy
CASROOT=`grep ^CASROOT $COBDIR/etc/cas/cas.cfg | cut -f2 -d=`
logit 3 CASROOT=$CASROOT

LOGS_LOC=$CASROOT/../logs
SRVNAME=$1
#Check if a region name was provided - prompt if not
if [ "${SRVNAME}x" = "x" ] ; then
 echo "Enter the Region name (or press the 'Carriage Return' key to quit):"
   read SRVNAME
     if [ "${SRVNAME}x" = "x" ] ; then
# No need to do anything else here - user decided not to enter any region name
        logit 2 "Run terminated"
        exit 5
     fi
   logit 3 SRVNAME=$SRVNAME 
#convert to uppercase
   SRVNAME=`echo $SRVNAME | tr "a-z" "A-Z"`
fi

#convert to uppercase
   SRVNAME=`echo $SRVNAME | tr "a-z" "A-Z"`

#save the region name that was entered above
SRVNAME_save=$SRVNAME
logit 3 SRVNAME_save=$SRVNAME_save

#Now check that this is a valid system directory
#If there is no sysdir, reprompt for correct region name but also allow script to continue anyway
while [ ! -d $CASROOT/$SRVNAME ]
do
 logit 2 "System Directory for region [$SRVNAME] not found"
 logit 2 "[location as obtained from cas.cfg: $CASROOT]"
 echo "Is the region name correct?"
 echo "Press the 'Carriage Return' key to continue anyway,"
 echo "or enter a different Region name:"
 
   read SRVNAME
     if [ "${SRVNAME}x" = "x" ] # 
 
     then
#        Reset region name to that actually entered
        SRVNAME=$SRVNAME_save
        logit 2 "Continuing to collect diagnostics for region [$SRVNAME]"
#        Break out of while loop
        break
     fi
# If we get here then a SRVNAME was entered...     
# Convert any new region name entered into uppercase     
   SRVNAME=`echo $SRVNAME | tr "a-z" "A-Z"`
# update saved SRVNAME      
   SRVNAME_save=$SRVNAME
done

# Note we now have a region name but it may not have a system directory in the expected location (from cas.cfg)
# also: it may not be a valid System Directory
#       it may not be for a region on the MFDS we are going to work with

logit 2 "Collecting data for:" $SRVNAME

################## MFSUPPORT ##################
#Kick off an mfsupport collection. At the end of this script we'll get the resultant mfpoll.txt

# Standard support system report
#logit 2 "Running mfsupport - Please wait..."
logit 2 "Launching mfsupport"
# do not redirect stderr to dev/null as user will not see any errors with this command!
# but do redirect stdout to a file - using null didn't work on some solaris and some Linux...
# Also mfsupport will try to create mfpoll.txt in the current dir, so needs write access.
# We should be in the tmp WRKDIR:
echo pwd=`pwd` >> $SNAPLOG 2>&1

# 1st need to check whether we can run in this shell, if so then launch in background,
# if not then check if can run under ksh and if yes then launch in background...
#mfsupport test prevents the actual output being generated
$COBDIR/bin/mfsupport test > $WRKDIR/mfsupport.out 2>&1 
RET=$?
if [ $RET -ne 0 ] ; then
  logit 3 "Error [$RET] trying to run $COBDIR/bin/mfsupport in this shell"
  logit 3 "Retrying mfsupport under ksh..."
  echo current shell=$SHELL >> $SNAPLOG 2>&1
# problem running on solaris - do not source the file as this would exit the shell on completion.
# re-try with ksh
  /usr/bin/ksh $COBDIR/bin/mfsupport test > $WRKDIR/mfsupport2.out 2>&1
  RET=$?
  if [ $RET -ne 0 ] ; then
    echo ' '
    logit 2 Unable to run $COBDIR/bin/mfsupport [ret=$RET] - check permissions and access rights 
    logit 2 "*** Please re-run mfsupport separately and provide the resulting mfpoll.txt file ***"
    echo ' '
  else
    logit 3 test under ksh was OK, launching mfsupport in background
    /usr/bin/ksh $COBDIR/bin/mfsupport >> $WRKDIR/mfsupport2.out 2>&1 &
#   Assuming here that it will run OK since the test ran ok...
    mfsuppRanOK=1
  fi  
else
  logit 3 test was OK, launching mfsupport in background
  $COBDIR/bin/mfsupport >> $WRKDIR/mfsupport.out 2>&1 &
# Assuming here that it will run OK since the test ran ok...
  mfsuppRanOK=1
fi
################## MFSUPPORT ##################

SRV_LOC=$CASROOT/$SRVNAME
logit 3 SRV_LOC=$SRV_LOC

#set ES_SERVER and region to region name in case this is referenced in the region config
ES_SERVER=$SRVNAME
region=$SRVNAME # actaully this seems to be shown in the region env vars so a lookup would work.
logit 3 ES_SERVER set to $ES_SERVER
logit 3 region set to $region

# Setup files for mdump output
MDUMP_FILE=$WRKDIR/MFDS_info.out
MDUMP_ENV_FILE=$WRKDIR/MDUMP_ENV.out
MDUMP_SECY_FILE=$WRKDIR/MFDS_SECY_info.out
MDUMP_ENV_MFTRACE=$WRKDIR/MDUMP_ENV_MFTRACE.out
MDUMP_ENV_ONLY=$WRKDIR/MDUMP_ENV_ONLY.out
MFDS_OPTIONS_FILE=$WRKDIR/mfds_options.out

#get user ID
id  > $WRKDIR/id.out

logit 2 "Getting process and shared memory details"
ps -ef  > $WRKDIR/ps.lst
date   >> $WRKDIR/ps.lst
ipcs -a > $WRKDIR/ipcs.lst
date   >> $WRKDIR/ipcs.lst

logit 2 "Getting network status"
netstat -an > $WRKDIR/netstat.lst
date >> $WRKDIR/netstat.lst

IFCONFIG=
logit 2 "Getting ifconfig output"
if [ -f /sbin/ifconfig ]; then
  IFCONFIG=/sbin/ifconfig 
elif [ -f /usr/sbin/ifconfig ]; then
  IFCONFIG=/usr/sbin/ifconfig 
else
  logit 3 "ifconfig not found"
  IFCONFIG=
fi

if [ $IFCONFIG ]; then
  logit 3 "Found ifconfig: $IFCONFIG"
  $IFCONFIG -a > $WRKDIR/ifconfig.out 2>> $SNAPLOG
  if [ $? != 0 ]; then
    logit 3 "Cannot use -a, try lan0"
    $IFCONFIG lan0 > $WRKDIR/ifconfig.out 2>> $SNAPLOG
  fi
fi


if [ -d $COBDIR/etc ]
then
    mkdir $WRKDIR/etc_files
    RET=$?
    if [ $RET -eq 0 ]
    then
      logit 3 "Created etc_files directory to copy etc files to"
      logit 2 "Copying product .dat .xml and .cfg files"
      cp $COBDIR/etc/*.dat $WRKDIR/etc_files | tee -a $SNAPLOG
      cp $COBDIR/etc/*.xml $WRKDIR/etc_files | tee -a $SNAPLOG
      cp $COBDIR/etc/*.cfg $WRKDIR/etc_files | tee -a $SNAPLOG
    else
      logit 2 "Couldn't create directory for etc files: $WRKDIR/etc_files"
    fi
else
   logit 2 "directory etc not exist!"
fi

## establish mfds port
#Use environment if set, otherwise use value from mfds script, else default=86 
#Check to see if port is already set in environment
if [ ! $CCITCP2_PORT  ]
then
  logit 3 No CCITCP2_PORT set, checking mfds script
  CCITCP2_PORT_MFDS=`grep  CCITCP2_PORT= $COBDIR/bin/mfds  | cut -f2 -d=`
  if [ "${CCITCP2_PORT_MFDS}x" != "x" ] # is CCITCP2_PORT_MFDS set ?
  then
     logit 2 "Using MFDS port set in local script: $CCITCP2_PORT_MFDS"
     CCITCP2_PORT=$CCITCP2_PORT_MFDS
  else
    logit 2 "CCITCP2_PORT not set, defaulting to port 86"
    logit 2 "if this is not the correct port, set CCITCP2_PORT in the environment and re-run this script"
    CCITCP2_PORT=86
  fi
else
  logit 2 MFDS CCITCP2_PORT set to: [$CCITCP2_PORT]
  # check that port number set in the environment is valid
  case $CCITCP2_PORT in
   (*[!0-9]*|'') 
       logit 2 CCITCP2_PORT not set to a valid number 
       logit 2 "resetting to default port 86"
       CCITCP2_PORT=86
       ;;
   (*)           
       logit 3 CCITCP2_PORT set to a number [$CCITCP2_PORT]
       ;;
  esac

fi


## Now check whether we actually have a valid region on this MFDS
logit 2 "Attempting MFDS repository dump for this region"
NO_MFDS=0
USE_ANON=0
USE_PROV=0
logit 3 Attempt mdump with default credentials
logit 3 mdump -v 2 -a localhost -p $CCITCP2_PORT -n $SRVNAME -u cn=$MDUMP_USER -x $MDUMP_PASS -$MDUMP_FILE
mdump -v 2 -a localhost -p $CCITCP2_PORT -n $SRVNAME -u cn=$MDUMP_USER -x $MDUMP_PASS>$MDUMP_FILE 2>&1
RET=$?

#################################################################################
# 1st remove any lines with Password in them - this would be in the mdump output
  logit 3 "removing lines with Password in from $MDUMP_FILE"
#  sed --in-place '/\* Password/d'  $MDUMP_FILE 
  sed '/\* Password/d' $MDUMP_FILE > $OUTDIR/tmp.$$
  mv $OUTDIR/tmp.$$ $MDUMP_FILE >> $SNAPLOG 2>&1
#################################################################################

if [ $RET -ne 0 ]; then
  logit 3 output of 1st mdump output:
  cat $MDUMP_FILE >> $SNAPLOG
  logit 3 end of 1st mdump output.

#########
# Now check the output to see if we have a SERVER_DOWN situation before retrying with different credentials
  logit 3 "Checking MFDS bind status ..."
  MDUMP_FILE_STATUS=`grep "m_ldap_bind:" $MDUMP_FILE | awk  '{print $3}'`
  if [ "$MDUMP_FILE_STATUS" == "SERVER_DOWN" ] ; then
    logit 2 Unable to connect to MFDS on this port: [$CCITCP2_PORT]
    logit 2 [$MDUMP_FILE_STATUS]
    logit 3 Setting NO_MFDS to 1
    NO_MFDS=1
# Else MFDS bind wasn't successful but server is up so try other credentials...
  else
    logit 3 MFDS server is up on [$CCITCP2_PORT]
    logit 3 MDUMP_FILE_STATUS = [$MDUMP_FILE_STATUS]
    NO_MFDS=0
#########

    logit 3 Unable to run mdump on port $CCITCP2_PORT using default credentials [ret=$RET]
    logit 3 Retry MFDS dump using anonymous access - will not work if mfds -b is used
    logit 3 mdump -v 2 -a localhost -p $CCITCP2_PORT -n $SRVNAME -$MDUMP_FILE
    mdump -v 2 -a localhost -p $CCITCP2_PORT -n $SRVNAME >$MDUMP_FILE 2>&1
    RET=$?
#################################################################################
#   remove any lines with Password in them - this would be in the mdump output
    logit 3 "removing lines with Password in from 2nd $MDUMP_FILE"
#     sed --in-place '/\* Password/d'  $MDUMP_FILE 
    sed '/\* Password/d' $MDUMP_FILE > $OUTDIR/tmp.$$
    mv $OUTDIR/tmp.$$ $MDUMP_FILE >> $SNAPLOG 2>&1
#################################################################################

#   Return from 2nd mdump was not 0    
    if [ $RET -ne 0 ]; then
      logit 3 Not able to run mdump on port $CCITCP2_PORT using default credentials or anonymous access [ret=$RET]
      logit 3 output from 2nd mdump attempt:
      cat $MDUMP_FILE >> $SNAPLOG
      logit 3 end of 2nd mdump output.
      logit 2 Unable to access mfds with default credentials, please provide alternative username and password:
      read -p "Enter Username: " MDUMP_USER
      echo ' '
      read -s -p "Enter Password: " MDUMP_PASS
      echo ' '
      logit 3 Retry MFDS dump using provided credentials - probably needed if mfds -b has been used
      logit 3 mdump -v 2 -a localhost -p $CCITCP2_PORT -n $SRVNAME -u cn=$MDUMP_USER -x \<provided\> -$MDUMP_FILE
      # Trying with provided credentials
      mdump -v 2 -a localhost -p $CCITCP2_PORT -n $SRVNAME -u cn=$MDUMP_USER -x $MDUMP_PASS>$MDUMP_FILE 2>&1
      RET=$?
#################################################################################
#     remove any lines with Password in them - this would be in the mdump output
      logit 3 "removing lines with Password in from 3rd $MDUMP_FILE"
#       sed --in-place '/\* Password/d'  $MDUMP_FILE 
      sed '/\* Password/d' $MDUMP_FILE > $OUTDIR/tmp.$$
      mv $OUTDIR/tmp.$$ $MDUMP_FILE >> $SNAPLOG 2>&1
#################################################################################

      if [ $RET -ne 0 ]; then
        logit 2 Not able to run mdump on port $CCITCP2_PORT using supplied credentials, user=$MDUMP_USER [ret=$RET]
        logit 2 Script will continue to collect other information
        NO_MFDS=1
        logit 3 output from 3rd mdump attempt:
        cat $MDUMP_FILE >> $SNAPLOG
        logit 3 end of 3rd mdump output.
      else
        logit 3 output from 3nd mdump attempt worked using provided credentials.
        NO_MFDS=0
        USE_ANON=0
        USE_PROV=1
        # Set MFDS_USER to the provided credentials
        MFDS_USER=$MDUMP_USER
        MFDS_PASS=$MDUMP_PASS
      fi
#   ELSE-IF Return from 2nd mdump was not 0
    else
      logit 3 output from 2nd mdump attempt worked using anonymous access.
      NO_MFDS=0
      USE_ANON=1
      USE_PROV=0
#   END-ELSE Return from 2nd mdump was not 0
    fi

# END-ELSE MFDS bind wasn't successful but server is up so try other credentials...
  fi

else
    logit 3 output from 1st mdump attempt worked using default security.
    NO_MFDS=0
    USE_ANON=0
    USE_PROV=0
fi


#If we were able to run mdump continue to check if region is valid and get security information
# Check if the region was valid
NO_REGION=0
if [ $NO_MFDS -eq 0 ] ; then
  logit 3 mdump ran OK on port $CCITCP2_PORT - should have region config:
  head -30 $MDUMP_FILE >> $SNAPLOG
  logit 3 [....end of top of mdump output]
  logit 3 "Checking for valid content in MDUMP_FILE (did we get valid config for this region?)..."
#  NO_SUCH_OBJECT  
#  m_ldap_search
  MDUMP_FILE_STATUS=`grep "m_ldap_search(server" $MDUMP_FILE | awk  '{print $4}'`
  if [ "$MDUMP_FILE_STATUS" != "Success" ] ; then
    logit 2 Unable to get configuration for region: [$ES_SERVER] on this MFDS: [$CCITCP2_PORT]
    logit 2 [$MDUMP_FILE_STATUS]
    logit 3 Setting NO_REGION to 1
    NO_REGION=1
  else
    logit 3 Region config obtained for $ES_SERVER 
    NO_REGION=0
  fi

#Since we can run mdump, attempt to get security information
# If region isn't valid we will still get mfds security information
  logit 2 "Get security info from repository"
  if [ $USE_ANON -eq 1 ]; then
    logit 3 using anonymous access:
    logit 3 mdump -e 2 -a localhost -p $CCITCP2_PORT -n $SRVNAME -$MDUMP_SECY_FILE
    mdump -e 2 -a localhost -p $CCITCP2_PORT -n $SRVNAME > $MDUMP_SECY_FILE 2>&1
  else
    logit 3 using credentials:
    if [ $USE_PROV -eq 1 ] ; then
      logit 3 mdump -e 2 -a localhost -p $CCITCP2_PORT -n $SRVNAME -u cn=$MDUMP_USER -x $MDUMP_PASS -$MDUMP_SECY_FILE
    else  
      logit 3 mdump -e 2 -a localhost -p $CCITCP2_PORT -n $SRVNAME -u cn=$MDUMP_USER -x \<provided\> -$MDUMP_SECY_FILE
    fi
    mdump -e 2 -a localhost -p $CCITCP2_PORT -n $SRVNAME -u cn=$MDUMP_USER -x $MDUMP_PASS > $MDUMP_SECY_FILE 2>&1
  fi

# However, there will only be env vars if the region was valid 
  if [ $NO_REGION -eq 0 ]; then
    #Get just the environment variable parameters
    logit 3 grep for = in $MDUMP_FILE to create $MDUMP_ENV_FILE...
    grep = $MDUMP_FILE > $MDUMP_ENV_FILE
  fi 

#end if NO_MFDS
fi

# We can still attempt an MFDS export whether mfds is running or not
# If MFDS is not running we will not know if the region is valid or not...

######### Start of Region Export #########
logit 2 "Attempting MFDS region export ..."
#Note this won't work if Security is on/Admin Access is restricted (unless default user/pass are still available)
#Need to generate output in /tmp (which will be owned by root) then copy to snapshot dir (to be owned by *this* process),
#  otherwise we won't be able to cleanup these files on the next run!
# Does mean that we'll leave a copy of the repository in /tmp - would need to be cleaned up in normal OS housekeeping...
# S (after servername)= export server AND security manager configuration,
# also using the O option to delete and overwrite any existing/previous export here.

TMP_MFDS_EXPORT_DIR=/tmp/mfesdiags-mfdsexport_temp
# Create the tmp directory in this script so we own it, otherwise mfds will create it and it will probably be owned by root
# This way we should still be able to read the files that are put there by mfds running as root etc.
# Note that we still won't be able to remove the files after, however mfds should be able to overwrite them on the next run...
# 1st try to remove it if it already exits
if test -d $TMP_MFDS_EXPORT_DIR
then
  logit 3 "Attempting to delete old mfds export tmp area: $TMP_MFDS_EXPORT_DIR"
  if [ -d $TMP_MFDS_EXPORT_DIR ]; then
    logit 3 "attempt to delete any files in: $TMP_MFDS_EXPORT_DIR"
    rm -rf $TMP_MFDS_EXPORT_DIR/* >> $SNAPLOG 2>&1
    RET=$?
    if [ $RET -eq 0 ]; then
      logit 3 "all files removed, now delete the directory"
      rmdir $TMP_MFDS_EXPORT_DIR >> $SNAPLOG 2>&1 
      RET=$?
      if [ $RET -ne 0 ] ; then
        logit 3 "Couldn't delete $TMP_MFDS_EXPORT_DIR - continuing"
      fi
    else
      logit 3 "Not able to remove all files - continuing"
    fi
#  else
#     logit 3 "Unable to CD to $TMP_MFDS_EXPORT_DIR - continuing"
  fi
fi

#Now attempt to make a new directory, unless it still exits
if [ ! -d $TMP_MFDS_EXPORT_DIR ]; then
  logit 3 "Attempting to make new mfds export tmp area: $TMP_MFDS_EXPORT_DIR"
  mkdir $TMP_MFDS_EXPORT_DIR >> $SNAPLOG 2>&1
  RET=$?
  if [ $RET -eq 0 ]; then
        logit 3 "Created temp mfds export area: $TMP_MFDS_EXPORT_DIR"
  else
        logit 3 "Couldn't create new directory from this script - continuing"
  fi
else
  logit 3 "$TMP_MFDS_EXPORT_DIR still exits"
fi

# If the export doesn't work (e.g. need valid user/pass) it won't generate any new output 
# - and we won't see any error (except in journal.dat).
# If a previous export is there however, the subsequent test will think everything is OK 
# (and will copy it anyway)
# So we'll only try once but we'll use the default user/pass in this attempt...

logit 2 "Exporting MFDS information for this region..."
#Note this will create files under the user that mfds is running under - probably root...
# Don't log password if it was provided by the user...
    if [ $USE_PROV -eq 1 ] ; then
      logit 3 "mfds -x 1 $TMP_MFDS_EXPORT_DIR $SRVNAME SO $MFDS_USER \<provided\>"
    else
      logit 3 "mfds -x 1 $TMP_MFDS_EXPORT_DIR $SRVNAME SO $MFDS_USER $MFDS_PASS"
    fi
mfds -x 1 $TMP_MFDS_EXPORT_DIR $SRVNAME SO $MFDS_USER $MFDS_PASS >> $SNAPLOG 2>&1
#wait for output to be there...
sleep 1

logit 3 "If there is a transcoding error message here, will need to set: LC_ALL=en_US.UTF-8 and re-run script"

if [ ! -f $TMP_MFDS_EXPORT_DIR/srv.dat ] ; then
  logit 3 "srv.dat not available in tmp export directory"
  logit 3 "Restrict Admin Access or filesystem permissions may be preventing this"
  logit 2 "MFDS Region export not available - check journal log for errors...continuing"
else
  logit 3 "copy mfds exported files to workarea as current user..."
  mkdir $WRKDIR/mfds_export >>$SNAPLOG 2>&1
  logit 3 copying $TMP_MFDS_EXPORT_DIR contents to $WRKDIR/mfds_export
  cp -r $TMP_MFDS_EXPORT_DIR/* $WRKDIR/mfds_export >>$SNAPLOG 2>&1
fi

#Now tar up the mfds repository anyway - from the install location 
logit 2 "Tar up mfds repository directory..."
tar cf $WRKDIR/mfds.tar -C $COBDIR/etc/ mfds >/dev/null 2>&1

######### End of Region Export #########


## ========== Only do the following operations if this region was valid on this MFDS =========
## Note that if NO_REGION==1 we will also now set NO_MFDS to 1 to stop mdump being run anymore 
## - the getenvfromfile and getdfhdrdat functions currently check for NO_MFDS.
## We have already got everything we want from MFDS by this point.

if [ $NO_REGION -eq 1 ] ; then
  NO_MFDS=1
fi

# If we have a valid region set COBMODE and attempt a region dump:
if [ $NO_REGION -eq 0 ] ; then
  SRVMODE64=0
  # don't need to use mdump again here as one has already been taken successfully if we are here!
  #echo "mdump -a localhost -p $CCITCP2_PORT  -n $SRVNAME grep mfCAS64Bit | awk '{print $2}'"
  logit 3 checking SRVMODE64 in MDUMP_FILE
  SRVMODE64=`grep mfCAS64Bit $MDUMP_FILE | grep mfCAS64Bit | awk '{print $2}'`
  logit 3 SRVMODE64=[$SRVMODE64]
## set COBMODE to server mode
  COBMODE=32
  # quote and use x in case not set to anything
  if [ "$SRVMODE64"x = "1"x ]
  then
  	logit 3 Setting working user mode to 64
    cobmode -u 64
  else
  	logit 3 Setting working user mode to 32
    cobmode -u 32
  fi
  logit 2 "COBMODE is "  $COBMODE
  cobmode >>$SNAPLOG

  logit 2 "Attempt offline system dump (unprotected)"
## casdump will not work if COBMODE is set incorrectly. hence the above
# Redirect stderr to SNAPLOG and both stdout and stderr to both screen and log
  logit 3 casdump -r$SRVNAME -d 
  casdump -r$SRVNAME -d 2>>$SNAPLOG | tee -a $SNAPLOG
  RET=$?
  if [ $RET -ne 0 ]; then
    logit 3 Unable to run casdump [ret=$RET]
  fi    		

  if [ -f $SRV_LOC/casdumpx.rec ]; then
    logit 2 "Converting system dump to text..."
    ## convert casdumpx.rec to textfile 
    casdup /i$SRV_LOC/casdumpx.rec /f$WRKDIR/casdumpx.txt >/dev/null 2>&1
  else
    logit 3 "casdump.rec not created"
  fi

#Now try casdump /b for memory as a block
  logit 3 casdump -r$SRVNAME -b
  casdump -r$SRVNAME -b 2>>$SNAPLOG | tee -a $SNAPLOG 
  RET=$?                     
  if [ $? != 0 ] ; then
    logit 3 'unable to run casdump -b [ret=$RET]'
  fi
  
#Now try casdump /f for faqe chain
  logit 3 casdump -r$SRVNAME -f
  casdump -r$SRVNAME -f 2>>$SNAPLOG | tee -a $SNAPLOG                      
  RET=$?                     
  if [ $? != 0 ] ; then
    logit 3 'unable to run casdump -f [ret=$RET]'
  fi

#End of NO_REGION
fi


#####
## Each of the following functions test for NO_MFDS and return null if its set
## On return we generally then get the appropriate default file
#Get MFTRACE_CONFIG file
logit 2 Checking for MFTRACE_CONFIG config file
COLLECTCTF=1
MFTRACE_CONFIG_SET=`getEnvFromFile MFTRACE_CONFIG 14 $MDUMP_ENV_FILE`
logit 3 MFTRACE_CONFIG_SET=$MFTRACE_CONFIG_SET
if [ "$MFTRACE_CONFIG_SET" ]
then
  MFTRACE_CONFIG=$MFTRACE_CONFIG_SET
  NEW_PATH=
  CheckForDollar $MFTRACE_CONFIG
  MFTRACE_CONFIG=$NEW_PATH
  logit 2 "Copying CTF trace config file"
  logit 3 cp -p $MFTRACE_CONFIG $WRKDIR
  cp -p $MFTRACE_CONFIG $WRKDIR
  RET=$?
  if [ $RET -ne 0 ]; then
    logit 2 Unable to copy CTF trace config file from $MFTRACE_CONFIG [ret=$RET]
    COLLECTCTF=0
  fi    		
else
  logit 3 MFTRACE_CONFIG not set in region - check OS
  if [ "$MFTRACE_CONFIG" ]; then
    logit 2 "Copying CTF trace config file"
    logit 3 cp -p $MFTRACE_CONFIG $WRKDIR
    cp -p $MFTRACE_CONFIG $WRKDIR
    RET=$?
    if [ $RET -ne 0 ]; then
      logit 2 Unable to copy CTF trace config file from $MFTRACE_CONFIG [ret=$RET]
      COLLECTCTF=0
    fi    		
  else
    logit 3 "MFTRACE_CONFIG not set in region or OS - no CTF trace"
    COLLECTCTF=0
  fi
fi
   
logit 2 Checking for EXTFH config file
EXTFH_SET=`getEnvFromFile EXTFH 5 $MDUMP_ENV_FILE`
logit 3 EXTFH_SET=$EXTFH_SET
if [ "${EXTFH_SET}x" != "x" ] # not null
then
  NEW_PATH=
  CheckForDollar $EXTFH_SET
  EXTFH_SET=$NEW_PATH
  logit 2 copying EXTFH
  logit 3 cp -p $EXTFH_SET $WRKDIR
  cp -p $EXTFH_SET $WRKDIR
  RET=$?
  if [ $RET -ne 0 ]; then
    logit 2 Unable to copy $EXTFH file [ret=$RET]
  fi    		
else  
  logit 3 EXTFH_SET not set in region - check OS
  if [ "${EXTFH}x" != "x" ] ; then # not null
    if [ -f $EXTFH ] ; then
      logit 2 copying EXTFH
      cp -p $EXTFH $WRKDIR
      RET=$?
      if [ $RET -ne 0 ]; then
        logit 2 Unable to copy $EXTFH file [ret=$RET]
      fi    		
    else
      logit 3 no file: $EXTFH
    fi
  else
    logit 3 EXTFH not set OS
  fi 
fi

logit 2 Checking for COBCONFIG file
COBCONFIG_SET=`getEnvFromFile COBCONFIG 9 $MDUMP_ENV_FILE`
if [ "${COBCONFIG_SET}x" != "x" ] # not null
then
  NEW_PATH=
  CheckForDollar $COBCONFIG_SET
  COBCONFIG_SET=$NEW_PATH
  logit 2 copying COBCONFIG
  logit 3 cp -p $COBCONFIG_SET $WRKDIR
  cp -p $COBCONFIG_SET $WRKDIR
  RET=$?
  if [ $RET -ne 0 ]; then
    logit 2 Unable to copy $COBCONFIG file [ret=$RET]
  fi    		
else  
  logit 3 COBCONFIG_SET not set in region - check OS
  if [ "${COBCONFIG}x" != "x" ] ; then # not null
    if [ -f $COBCONFIG ] ; then
      logit 2 copying COBCONFIG
      cp -p $COBCONFIG $WRKDIR
      RET=$?
      if [ $RET -ne 0 ]; then
        logit 2 Unable to copy $COBCONFIG file [ret=$RET]
      fi    		
    else
      logit 3 no file: $COBCONFIG
    fi
  else
    logit 3 COBCONFIG not set OS
  fi 
fi

#Get CTF Trace logs
if [ $COLLECTCTF -ne 0 ] ; then
  logit 2 Checking for CTF Trace logs
  get_MFTRACE_LOGS
fi

logit 2 Get RDO file
get_DFHDRDAT

logit 2 Get cobver
cp -p $COBDIR/etc/cobver $WRKDIR

#####
## check here specifically whether this was a valid region on this MFDS rather than the directory existing
# Only copy region files if region is valid for this MFDS
if [ $NO_REGION -eq 1 ] ; then
    logit 3 "Region not valid on this MFDS"
else
    logit 2 "Copying ES directory:" $SRVNAME
    mkdir $WRKDIR/$SRVNAME
    RET=$?
    if [ $RET -eq 0 ]
    then
      logit 3 "Created directory to copy Region files to"
      logit 3 cp -R $SRV_LOC/* $WRKDIR/$SRVNAME
      cp -R $SRV_LOC/* $WRKDIR/$SRVNAME
    else
      logit 2 "Couldn't create directory for region files: $WRKDIR/$SRVNAME"
      cp -R $SRV_LOC/* $WRKDIR
    fi
fi

# Journal 

# If mfds -j has been used on the mfds command line we need to get the journal file from there
# Alternatively, the default location may have been changed in the mfdsacfg config file - mfds -h 0
# However the mfds -t o/p looks like it will contain the path to the relevant journal.dat file, whichever method was set to change it:

# Need to use this 2-step approach due to stderr being used (can't grep that directly)
logit 3 "Create text version of Journal.dat + capture mfds -t output to $SNAPDIR/mfds-t.out" 
# Specify output directory in case there are permissions problems
mfds -t $SNAPDIR/journal.txt $JOURNAL_DAT > $SNAPDIR/mfds-t.out 2>&1
JOURET=$?
logit 3 "Return from mfds -t was: [$JOURET]"

#JOURNAL_LOC=$(grep "/journal." $SNAPDIR/mfds-t.out | awk -F\" '{print $2}')
# Now check in mfds -t o/p to see if -j was specified (will see 'Using:..' in the o/p)
JOURNAL_LOC=$(grep "Using" $WRKDIR/mfds-t.out | awk '{print $2}')
# If JOURNAL_LOC is empty then -j wasn't used 
if [ $JOURNAL_LOC  ]; then
  logit 3 "Found Journal file location from -j:" $JOURNAL_LOC
else
# Didn't find 'Using' in mfds -t o/p so -j wasn't specified on mfds command line 
# so get the journal location from the mfds options file:
  mfds -h 0 > $MFDS_OPTIONS_FILE 2>&1
  JOURNAL_LOC=$(grep "Journal Directory:" $MFDS_OPTIONS_FILE | awk '{print $4}')
  logit 3 "Found Journal file location from mfds options file:" $JOURNAL_LOC
fi

JOURNAL_DAT=$JOURNAL_LOC/journal.dat
JOURNAL_TXT=$JOURNAL_LOC/journal.txt 

if [ ! -f $JOURNAL_DAT ]
then
  logit 2 "No Journal.dat found in" $JOURNAL_LOC
else
  logit 2 "Copying Journal.dat from:" $JOURNAL_LOC
  cp $JOURNAL_DAT $WRKDIR 2>&1 | tee -a $SNAPLOG
fi
# Journal.txt file should already have been created directly in the SNAPDIR

logit 3 "Checking for Journal CTF txt file in:" $COBDIR
if [ -f $COBDIR/mfds.journal.ctf.txt ] ; then
  logit 2 "Copying: $COBDIR/mfds.journal.ctf.txt"
#  cp $COBDIR/mfds.journal.ctf.txt $WRKDIR 2>&1 | tee -a $SNAPLOG
  cp $COBDIR/mfds.journal.ctf.txt $WRKDIR 2>&1 >> $SNAPLOG
  RET=$?
  if [ $RET -ne 0 ] ; then
    echo ' '    
    logit 2 "Unable to copy mfds.journal.ctf.txt [Error=$RET]"
    logit 2 "*** Please copy $COBDIR/mfds.journal.ctf.txt manually and provide separately ***"
    echo ' '    
  fi
else
  logit 3 "no mfds.journal.ctf.txt file found"
fi

# mfsupport was run in the background at the beginning of this script.
if [ $mfsuppRanOK -eq 1 ] ; then
  logit 2 "Copying mfpoll.txt..."
  while [ ! -f mfpoll* ]
  do
    sleep 2 
    logit 2 "Waiting for mfsupport to finish writing output..."
  done
logit 3 checking that mfpoll.txt was created directly in WRKDIR
  if [ -f $WRKDIR/mfpoll.txt ]; then
    logit 3 "mfpoll created in WRKDIR OK"
  else
    logit 3 "mfpoll.txt not found in WRKDIR - assume its in cwd and copy..."
    echo pwd=`pwd` >> $SNAPLOG 2>&1
    cp mfpoll* $WRKDIR >> $SNAPLOG 2>&1
    logit 3 "removing mfpoll*"
    rm mfpoll* >> $SNAPLOG 2>&1
  fi
fi

## Second image may highlight loops

logit 3 "Getting 2nd set of status output file"
ps -ef  > $WRKDIR/ps2.lst
date   >> $WRKDIR/ps2.lst
ipcs -a > $WRKDIR/ipcs2.lst
date   >> $WRKDIR/ipcs2.lst
netstat -an > $WRKDIR/netstat2.lst
date >> $WRKDIR/netstat2.lst

################# Collection complete, create .tar file #################

cd $WRKDIR
logit 2 "Creating mfesdiags.tar"

#################################################################################
# No need to remove password from the snapshot.log as it was removed from the mdump output 
#   before that output was copied into snapshot.log
#  sed --in-place '/\* Password/d'  $SNAPLOG 
#  sed --in-place=.bak '/\* Password/d'  $SNAPLOG 
#################################################################################

tar cf $OUTDIR/mfesdiags.tar * >/dev/null 2>&1
TAR_RET=$?
if [ $TAR_RET = 0 ]; then
  if [ -f $OUTDIR/mfesdiags.trz ]
  then
    logit 2 "Removing old compressed file"
    rm  $OUTDIR/mfesdiags.trz
  fi
  logit 2 "Compressing tar file - details follow:"
  gzip -c $OUTDIR/mfesdiags.tar > $OUTDIR/mfesdiags.trz 
  if [ $? != 0 ] ; then
    logit 2 'gzip failed - compress manually as required'
  else
    rm $OUTDIR/mfesdiags.tar
#   tar file created OK so we can remove the tmp files
    REMOVE_TMP_FILES=1
  fi
else  
  logit 3 "Error creating mfesdiags.tar [$TAR_RET]"
  logit 2 "Unable to create tar file - please create manually"
#IF TAR_RET
fi

ls -l $OUTDIR/mfesdiags.trz | tee -a $SNAPLOG


#Tidy up - note can't output to snapshot.log on/after the rm command...
if [ "$REMOVE_TMP_FILES" = "1" ]; then
  echo    # new line
  echo "Compressed tar file created successfully, remove temporary files in $WRKDIR?"
  echo "(press 'y' to remove, any other key to keep):"
  read -n 1 -r RESP
#  echo    # (optional) move to a new line
  case $RESP in
    y|Y)
      logit 2 'Removing tmp files...'
      cd $OUTDIR >> $SNAPLOG 2>&1 
#      cp $SNAPLOG $WRKDIR/..
      rm -rf $WRKDIR
      rmdir $WRKDIR_BASE
      ;;
    *)
      logit 2 "(Keeping temporary files in $WRKDIR)"
      ;;
  esac

# If we are here, the compressed tar operation was successful so tell user to provide this collection
  echo ' '
  echo "*************************************************************************"
  echo "Please send $OUTDIR/mfesdiags.trz to Micro Focus Customer Care"
  echo "*************************************************************************"
  echo "(Rename file to include date, time and incident number)"
  echo "(FTP details are available on request)"

fi

echo ' '
echo 'End of diagnostics collection'
echo ' '
