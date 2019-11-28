ECHO OFF
CLS
SETLOCAL
set MFESDIAGSVER=2.9c
ECHO *** MFESDIAGS.CMD VERSION %MFESDIAGSVER% ***
REM ECHO %DATE% %TIME%
echo.
ECHO *** Copyright © Micro Focus [2010]-[2016]. All rights reserved.
echo.
ECHO *** This script can be run from from Windows Explorer or from a command prompt
ECHO *** The Region name will be prompted for
ECHO *** The region name can optionally be specified when run from the command prompt
ECHO *** Run as the user that started the region to ensure a casdump can be taken
ECHO *** MFES_SYSDIR can be manually set to the System Directory if necessary
ECHO *** This script can be run from region start/stop scripts by setting MFES_NOPROMPT=1
REM      If MFES_NOPROMPT=1 the script will run non-interactively (no prompts)
REM      This allows MFESdiags to be called from a region startup script for example.
REM      System files etc will still be collected if no region name was provided
REM      SNAPDIR will still be removed at the end of the script (with no prompting)
echo.
REM *** This script will attempt to identify the intalled product from the registry
REM *** If Enterprise Developer isn't found it will look for Net Express.
REM *** It will work for both the Server and the Development products.
REM *** It uses an external utility mdump to get configuration information from MFDS
REM *** It runs mfSupportInfo and collects additional OS information
REM *** Then it collect logs and other files for the specified region 
REM *** A 'CASDUMP' will be attempted (region needs to be running, user needs to be correct).
REM *** The region is prompted for when the script is run. 
REM *** If the script is run from a command prompt the region name can also be specified.
REM *** If there are problems running mdump, the environment variable MFES_SYSDIR can be 
REM *** set to the System Directory location to allow the main files to be collected.
REM *** The information is collected in a 'snapshot' directory (in %TEMP%\MFESDIAGDIR)
REM *** The 'snapshot' information should be zipped up and attached to an incident.
REM
REM *** A Zip utility can be configured in this script to zip the contents of the snapshot directory
REM *** otherwise a .vbs script is created/used
REM ====================================
REM Usage:
REM 
REM MFESDIAGS <Region>
REM  where:                                                                                                                                                
REM    Region is the name of the region                                                                                                                    
REM  ====================================
@ECHO off

REM ====================================
REM History
REM V1 - original ESpoll script
REM v2.2 - May 2012 revamped version to work with ED
REM v2.2a - July 2013 includes mdump3.7 as well
REM v2.3  - Aug 2013  - copies all files from system/region directory
REM v2.31 - July 2013 Expands multiple $ environment variables in paths. Gets CTF.cfg file
REM v2.31a - Aug 2013 Includes MSVCR100.dll, gets COBCONFIG_ cfg file
REM v2.4 - Sept 2013 Renamed to MFESDIAGS.cmd. Gets CTF trace files. Uses older mdump.exe for pre-ED.
REM v2.5 - Oct 2013 Uses task scheduler (SYSTEM account) to get casdump if no psexec etc 
REM     a-          No longer redirecting casdump output - leave message on screen
REM     b-          No longer using/providing msvcr100.dll - renaming if found locally
REM     c-          Added mdump retry with any locally existing version in product bin dir
REM                 Redirecting SET o/p to unique filenames for different requests
REM                 Try any locally existing mdump if problems running supplied mdump
REM                 Continue with script/casdump even if mdump wasn't successful
REM                 Path for  dfhdrdat file now relative to bin directory (server/dev products)
REM                 Only get default dfhdrdat if not set in region
REM     d-          Getting current directory location, removed un-needed popd at end
REM     e-          Convert UTLDIR to short path (incase of spaces)
REM v2.6 - Dec 2013 Supports Visual Cobol 2012 and 2013
REM								  copying dfhdrdat (from region or OS) to main snapshot dir
REM							    Handling exact strings when looking up region config values
REM                 Support for ES_SERVER
REM                 Improved error handling if variables not set etc.
REM                 Now getting EXTFH, COBCONFIG_ and FHREDIR from region if set
REM                 Use mdump.exe from product install dir if it exists
REM     a- Jan 2014 Wasn't setting Version correctly in NetExpress environment
REM                 MFDS_SCHEMA_DIR empty string test now works whether quoted or spacey (DOS complained)
REM v2.7 - Mar 2014 Added message to show when 'converting to short path'
REM                 Added support for "MFES_SYSDIR" external environment variable - used if sysdir can't be obtained from region
REM                 If DEF_WORKAREA isn't set, now prompts for System Directory
REM                 Checking DEF_WORKAREA for empty string (works whether string is quoted or not)
REM                 Running mfSupportInfo earlier in script if possible, along with other non-ES collections
REM								  If can't run mfSupportInfo earlier, re-attempt after PATH is setup
REM                 Retrying with different mdump version if initial version fails
REM                 Script now runs to completion even if all data can't be collected (e.g. if can't get PRODUCT_DIR or region config)
REM                 Using Windows ZIP utility if no command-line utility available
REM                 Using WMIC to get command line info of running REGION processes
REM                 Running TASKLIST.exe asynchronously so it doesn't delay script
REM                 Improved messages to screen
REM v2.7a- Apr 2014 Launching Windows Explorer at end of script for SNAPSHOT dir

REM     b- May 2014 Removing any double quotes when checking region env vars
REM     c- Jun 2014 Fixed quotes in Get_MFtraceConfig after GetVarFromFile removes them
REM     d-          Fixed more quotes after calls to GetVarFromFile (spacey pathname with no quotes hits error)
REM                 Double-quoting path provided to GetVarFromFile (maybe space in pathname as read from config file)
REM     e- Aug 2014 casdump command for task scheduler now includes cmd.exe 
REM                 Check error when running SCHTASKS task, retry without /I argument for backward compatability
REM                 Check for cscript before running eventquery.vbs and _zipit.vbs, skip if can't run cscript
REM v2.7f  Sep 2014 Quoting characters when checking for trailing slash in checkForDollar (might be trailing spaces)
REM v2.7g  Dec 2014 Copy mfds.journal.ctf.txt if it exists.
REM                 Get MFDS export for specific region separately.
REM                 Using DOS net command to get drive mappings and other info.
REM v2.7h  Nov 2015 using -a on mdump command. Also saving any messages from 1st attempt to run mdump
REM v2.8   Jan 2016 Fixed problem of skipping prompt for Region name (related to mfSupportInfo test)
REM                 Running mfSupportInfo with START command so we don't have to wait for it.
REM                 Now getting journal file location from MFDS
REM                 Env Var MFES_NOEXPWIN=1 prevents explorer window being opened
REM                 Checking OS for env vars not found in region config.
REM 								Added copyright note.
REM     a-2Mar 2016 Using DOS PATH to find and set full path to mdump - takes away the reliance on non-spacey paths.
REM                 Simplified copying of default dfhdrdat files - just copies if it finds it in either of the possible directories (NX or ED)
REM                 Quoted UTILDIR when used to run the older mdumps - in case we can't get the short path
REM     b-17Mar2016 Added global switch to use short paths
REM                 Getting ipconfig and route print outputs, plus net stats server
REM                 Renamed some collected files to clarify what they contain
REM                 Corrected some script labels for checking/getting config files
REM                 Using CheckPath function to convert to short paths.
REM     c-23Mar2016 Reworked script so it can run non-interactively using MFES_NOEXPWIN renamed to MFES_NOPROMPT - set Region name to DUMMY if none provided
REM                 Added user/pass for mfds -x command; wait for output if command is repeated; overwrite any existing output
REM                 Added checks for 8dot3 support on any used drives
REM                 Renamed CheckStr function to CheckPath
REM                 Converting JOURNAL_LOC to short path with CheckPath
REM                 Checking for psexec.exe using MSDOS PATH loop
REM                 Reworked casdump task scheduler command block to remove nested if loop
REM                 Moved the setlocal EnableDelayedExpansion into the ProcessFile fn so as not to affect the rest of the script
REM                 If no console.log AND we are non-interactive allow script to continue to collect MFDS info etc.
REM                 Catering for certain strings to be empty as well as <null> in the region - DFHDRDAT_LOG and REGION_WORKAREA
REM                 If no MDUMP_ENV_FILE, skip the collection of region-specfic files like CTF.
REM     d-31Mar2016 Calling CheckPath for MFES_SYSDIR env var
REM                 CheckPath now removes trailing slash and adds double-quotes - for when no shortname
REM                 Corrected return from CheckPath to work when no shortpathname found.
REM                 Subsequently stripping the double-quotes added by CheckPath for each variable
REM                 Check for Visual Cobol product 1st as per ED 2.3 
REM                 Further reworked GetCasDump task scheduler to work line-by-line and escaped double-quote to prevent the \Micro error.
REM                 Re-prompting for region to be re-entered if null
REM                 Removing SNAPSHOT files if ZIP successful
REM                 Added TESTING values.
REM  2.8e-25Apr2016 Testing presence of casdumpx.rec to determine whether the dump was successful or not.
REM                 If unable to create journal.txt with mfds -t (permississions problems), retry with SNAPDIR\journal_as_text.txt as output
REM       25May2016 Setting ZIP=none as default - spaces in path can still cause problems on non-8.3 drive
REM       26May2016 If a specified ZIP isn't found, fall back to use .vbs ZIP_IT
REM                 Clarified final message about removing temp files + use Ctrl-C to abort and keep files.
REM  2.8f 26May2016 Added more TESTING states and messages 
REM  2.8g-03Jun2016 Script continues to collect what it can if entered region isn't valid. If region is not in MFDS no region-specific files are collected
REM                 - if region is found in MFDS but there is no console.log etc, then the normal check for CTF trace etc are still made.
REM                 In getWorkArea, splitup the for loop for NEW_WORKAREA due to the delayedexpansion problem
REM                 - if non-interactive, set Region_Workarea to %DEF_WORKAREA%\%REGION% if region not found
REM  2.9  06Jul2016 Incremented version number
REM  2.9a 11Oct2016 Improved error handling in ZIP_IT, setting ZIP_ERRORLEVEL.
REM                 Now checking ZIP_ERRORLEVEL before removing files.   
REM  2.9b 04Nov2016 cScript doesn't set ERRORLEVEL on runtime errors - redirect stderr to a file and check there.
REM       10Nov2016 cScript zip now waits until all items are copied before continuing (files may be deleted next)
REM  2.9c 11Nov2016 Prevent xcopy copying any empty sub-dirs (can cause the .vbs zip script a problem)
REM                 Added timeout to cScript zip command - if occurs don't remove SNAPSHOT files but do remove any partial zip file
REM                 Creating .txt files in MFDS_SCHEMA and each CTF sub-dir created to prevent them being empty.
REM                 Running tasklist in foreground - needs to complete before zipping starts
REM
REM ====================================

REM ====================================
REM TESTING VALUES
REM set TESTING=...
REM >= 1 skip to end of file, pause if non-interactive
REM >= 2 created local snapshot.log
REM >= 3 Not removing snapdir
REM ====================================

REM Note: short path conversion will only work if it was already setup on the relevant drive.
REM To determine whether short paths are enabled, run the windows command:
REM  fsutil 8dot3name query <drive:>

REM ====================================
REM NOTE Don't call TEE until snapshot dir is setup!
REM Setup directory for diagnostics capture
set snapdir_exists=0
call :CREATE_SNAPDIR
if %snapdir_exists% == 1 goto stop
REM ====================================


call :TEE1 Starting diagnostic collection on %DATE% %TIME%
echo.


REM This should be the 1st entry in the snapshot.log
call :TEE2 %DATE% %TIME% *** MFESDIAGS.CMD VERSION %MFESDIAGSVER% ***
call :TEE2 Snapshot log is %SNAPLOG% 

REM TEST if set to 1 or above
if "%TESTING%" GEQ "1" (
  echo TESTING Level %TESTING%...
  set ZIP=none
  goto GetFromInstallLoc
)
REM TEST

set NO_MFDS=0
set PRODUCT_PATH=
set MFDS_SCHEMA_DIR=

call :TEE2 Checking short path name situation for all drives:
fsutil 8dot3name query >> %SNAPLOG% 2>&1
set CURR_DRIVE=%cd:~0,2%
call :TEE2 Checking short path name support on current drive: %CURR_DRIVE% 
fsutil 8dot3name query %CURR_DRIVE% >> %SNAPLOG% 2>&1
set UTIL_DRIVE=%~d0
call :TEE2 Checking short path name support on drive with this script: %UTIL_DRIVE% 
fsutil 8dot3name query %UTIL_DRIVE% >> %SNAPLOG% 2>&1

REM Remove any leading spaces from MFES_NOPROMPT
REM This shouldn't be necessary but we can't set: =1 in Execute on demand script so have to set: = 1
REM Check if its set 1st
if "%MFES_NOPROMPT%x" NEQ "x" (
  call :TEE2 Checking for and removing any leading spaces from MFES_NOPROMPT [%MFES_NOPROMPT%]
  for /f "tokens=* delims= " %%a in ("%MFES_NOPROMPT%") do set MFES_NOPROMPT=%%a
)
call :TEE2  MFES_NOPROMPT after leading space check [%MFES_NOPROMPT%]   

REM Doing this separately to prevent nested if statements.
if "%MFES_NOPROMPT%" EQU "1" (
  call :TEE2 Script running non-interactively - CD to %TEMP%
REM We may be in a system directly so CD to TEMP
  echo CD=%CD% >> %SNAPLOG%
  cd %TEMP%
) else (
  call :TEE2 Script running interactively
)
echo CD=%CD% >> %SNAPLOG%

set MFDS_USER=SYSAD
set MFDS_PASS=SYSAD

REM ====================================
set ZIP=none
REM Modify the following "ZIP" parameter to point at a command-line zip utility if required
REM The command-line zip utility must take the -r (recursive) and -p (pathnames) arguments
set ZIP=none
REM set ZIP=C:\Program Files (x86)\IZArc\izarcc.exe
REM set ZIP=C:\Program Files (x86)\jZip\jZip.exe

REM Convert to short path:
call :CheckPath ZIP
if NOT EXIST "%ZIP%" set ZIP=none

REM Note if ZIP utility is provided with spaces in the path it could still cause the script to abort if on an non-8.3 drive
REM If no external ZIP utility is provided, this script will use a .vbs script to zip the files.

REM ====================================
set UTLDIR=%~dp0
::Remove any trailing slash
IF %UTLDIR:~-1%==\ SET UTLDIR=%UTLDIR:~0,-1%

REM Now convert to short path
call :CheckPath UTLDIR

set PATH=%UTLDIR%;%PATH%
call :TEE2 UTLDIR=%UTLDIR%

call :TEE2 Getting initial environment variables 
set > %SNAPDIR%\set1.out

REM WhoAmiI?
whoami >> %SNAPLOG%
whoami /ALL > %SNAPDIR%\WhoAMi.out

REM set path and filename for mdump output (gets created later)
set MDUMP_FILE=%SNAPDIR%\MFDS_info.out
set MDUMP_ENV_FILE=%SNAPDIR%\MDUMP_ENV.out
call :TEE2 MDUMP_FILE=%MDUMP_FILE%
call :TEE2 MDUMP_ENV_FILE=%MDUMP_ENV_FILE%

set MDUMP_SECY_FILE=%SNAPDIR%\MFDS_SECY_info.out
call :TEE2 MDUMP_SECY_FILE=%MDUMP_SECY_FILE%

REM **********************************************
REM CALL mfsupportInfo and other OS related functions before any ES-specific ones (in case of problems with script completing)
REM **********************************************
REM May not be on the path - try now and if not try later once we have the PBIN path

Call :TEE2 Checking whether we can run mfSupportInfo at this stage

set MFsupportRUN=0
REM Assume failure:
set MFSI_E1=1
set MFSI_E2=1

REM Test if we can run it
call :TEE1 Checking if mfSupportInfo can be run here

set PathToMFSI=
for %%e in (%PATHEXT%) do (
  for %%X in (MFSupportInfo%%e) do (
    if not defined PathToMFSI (
      set PathToMFSI=%%~$PATH:X
    )
  )
)
call :TEE2  PathToMFSI=%PathToMFSI%

if "%PathToMFSI%"=="" (
  call :TEE2 can't run MFSupportInfo.exe yet-not on path
  set MFsupportRUN=0
  goto Skip_MFSI
) else (
  call :TEE2 MFSupportInfo.exe found on path
)

REM Now we should be able to run it
call :TEE1 Running mfSupportInfo...
call :TEE2 start "" /b MFSupportInfo.exe /S /L%SNAPDIR%
start "" /b MFSupportInfo.exe /S /L%SNAPDIR%
set MFSI_E2=%ERRORLEVEL%
set MFsupportRUN=1
if %MFSI_E2% NEQ 0 set MFsupportRUN=0

:Skip_MFSI
call :TEE2 MFSI_E2=%MFSI_E2%, MFsupportRUN=%MFsupportRUN%

REM ----------------------------------------------------------------------------
REM Collect additional OS info/stats
REM, pslist, netstat, Event Mgr Info (psloglist etc), tasklist, psserver
REM ----------------------------------------------------------------------------

call :Get_Netstat

call :Get_CCITCP2_info

Call :Get_EventLog

REM Get 1st process/task list
call :Get_ProcessList 1

call :TEE1 Getting drive mappings
net use > %SYSINFODIR%\DriveMappings.out 2>&1
net share > %SYSINFODIR%\NetShare.out 2>&1
net stats workstation > %SYSINFODIR%\NetStatisticsWrk.out 2>&1
net stats server > %SYSINFODIR%\NetStatisticsSvr.out 2>&1
net user > %SYSINFODIR%\NetUserAcc.out 2>&1 

call :TEE1 Getting ipconfig
ipconfig /all > %SYSINFODIR%\ipconfig.out 2>&1

call :TEE1 Getting route print output
route print > %SYSINFODIR%\route_print.out 2>&1

REM **********************************************
REM End of Initial non-ES specific collection
REM **********************************************

REM Force collection of NX product using 2nd command line parameter:
call :TEE2 if NOT "%2"=="" set NETX_VER=%2 else call :GetProdVer
if NOT "%2"=="" (
	set NETX_VER=%2
	set VERSION=NetExpress
	set FULL_VERSION=%VERSION%\%NETX_VER%
   ) else ( 
	call :GetProdVer
   )
if {%ED_VER%} == {} (
    if {%NETX_VER%} == {} (
      call :TEE1 - unable to determine installed product from registry - continuing anyway.
      REM goto stop
    )
)

echo.
if NOT "%ED_VER%"=="" call :TEE1 Collecting for Enterprise Developer ver:%ED_VER%
if NOT "%NETX_VER%"=="" call :TEE1 Collecting for Net Express ver:%NETX_VER%

REM Do a check here to see if the product bin directory is already available/on the path?
REM If so should be able to run mdump.exe - although won't be able to copy the additional files - without quoting the path...
Call :GetInstallDir

REM If we haven't been able to create the short path but we DID get the product path OK we should still be able to add this to the PATH env var.
REM Since we're going to continue anyway, lets not do the check here - as its the the test on PRODUCT_PATH when it contains spaces that aborts the script!

REM PRODUCT_PATH is used for *.dat files, edver, cobver and PBINDIR
call :TEE2 PRODUCT_PATH=%PRODUCT_PATH%

REM Get the drive of where the product is installed and check for 8dot3
set PROD_DRIVE=%PRODUCT_PATH:~0,2%

call :TEE2 Checking short path name support on install drive: %PROD_DRIVE% 
fsutil 8dot3name query %PROD_DRIVE% >> %SNAPLOG% 2>&1

REM Take account of ED|Server|Studio installs:
set PBINDIR=
REM Using double-quotes here should prevent the script aborting if PRODUCT_PATH contains spaces
if exist "%PRODUCT_PATH%\bin\mldap.dll" set PBINDIR=%PRODUCT_PATH%\bin
if exist "%PRODUCT_PATH%\Base\bin\mldap.dll" set PBINDIR=%PRODUCT_PATH%\Base\bin
if  "%PBINDIR%1"=="1" (
  call :TEE2 no mldap.dll found - Visual Cobol?
  call :TEE2 No PBINDIR, won't be able to set PATH or check for mdump.exe, get default dfhdrdat or run casdump.exe 
)

REM PBINDIR used to add to PATH, check for mdump.exe, get default dfhdrdat and to run casdump.exe

call :TEE2 PBINDIR=%PBINDIR%

REM Add product path to PATH
set PATH=%PBINDIR%;%PATH%
set COBDIR=%COBDIR%;%PBINDIR%

Call :TEE2 Now checking whether still need to run mfSupportInfo - PATH should be setup now
if %MFsupportRUN%==1 (
  Call :TEE2 mfSupportInfo already run
  goto skip_MFSI2
)

call :TEE1 Running mfSupportInfo...
call :TEE2 start "" /b MFSupportInfo.exe /S /L%SNAPDIR%
REM start "" /b MFSupportInfo.exe /S /L%SNAPDIR% 2>>%SNAPLOG%
start "" /b MFSupportInfo.exe /S /L%SNAPDIR%
set MFSI_E3=%ERRORLEVEL%
call :TEE2 MFSI_E3="%MFSI_E3%"
if NOT "%MFSI_E3%"=="0" (
  call :TEE1 Unable to run MFSupportInfo.exe 
  call :TEE1 - please check its location, the PATH environment variable and access permissions
  call :TEE1 - please provide the relevant mfsupportinfo log file separately
  )

:skip_MFSI2

REM Get Region Name
set REGION=
if NOT %1"" == "" (
  call :TEE2 Using region provided on command line: %1
  set REGION=%1
) else (
  call :TEE2 No region provided on command line
  CALL :GetRegion
)

call :TEE2 Region=%region%

Rem now set ES_SERVER to region name in case this is referenced in the region config
set ES_SERVER=%region%
call :TEE2 ES_SERVER=%ES_SERVER%

set NO_REGION=0
Call :Get_Region_Info
if "%NO_REGION%"=="1" (
  call :TEE1 *** CAN'T FIND THIS REGION:[%REGION%] ***
  if "%MFES_NOPROMPT%" EQU "1" (
    call :TEE2 Running non-interactively - continuing anyway
  ) else (
REM    call :TEE1 Please re-run script and specify correct region
    call :TEE1 Continuing to collect remaining files
REM  REM    call :TEE1 Terminating  
REM REM     goto stop
  )
)
REM Kick off the region export here - it may take a while - we check for its output later.

REM ----------------------------------------------------------------------------
REM Attempt Region export
REM ----------------------------------------------------------------------------
call :TEE1 MFDS Region Export
REM Can request a region export before MFDS_DIR is known
set MFDSEXPORT_REGIONDIR="%SNAPDIR%\MFDSEXPORT_%REGION%"
mkdir %MFDSEXPORT_REGIONDIR%
REM to ensure directory can't be empty
echo MFDS EXPORT DIR > %MFDSEXPORT_REGIONDIR%\mfdsExportDir.txt

REM Note this won't work without credentials if MFDS administration access is restricted
REM mfds -x 1 %MFDSEXPORT_REGIONDIR% %REGION% S >>%SNAPLOG% 2>&1
REM This won't work if Admin Access is restricted.

REM Use credentials - admin may be restricted, or mfds started with -b
REM Use SO to allow to over-write if there was any existing output.
call :TEE2 MFDS export: mfds -x 1 %MFDSEXPORT_REGIONDIR% %REGION% SO %MFDS_USER% %MFDS_PASS% 
mfds -x 1 %MFDSEXPORT_REGIONDIR% %REGION% SO %MFDS_USER% %MFDS_PASS% >>%SNAPLOG% 2>&1
REM Check if files have been generated - could prompt for a different user here
REM mfds -x can take a few seconds for the files to appear so check after the casdump etc journal and MFDS info copy..


REM ----------------------------------------------------------------------------
REM run casdump for this region
REM ----------------------------------------------------------------------------
REM get mfServerStatus: from mdump o/p, run casdump only if region is Started
set SERVER_STATUS=
for /f "Tokens=1,2*" %%i in ('findstr mfServerStatus: %MDUMP_FILE%') do set SERVER_STATUS=%%j
call :TEE2 SERVER_STATUS=%SERVER_STATUS%
REM TEST if "%SERVER_STATUS%"=="Stopped" echo Region %REGION% is stopped & if exist casdump.exe casdump /d /r%REGION% >>%SNAPLOG%
REM Also run casdump if mdump wasn't able to run etc
if %NO_MFDS% EQU 1 set RUNCASDUMP=1
if "%SERVER_STATUS%"=="Started" set RUNCASDUMP=1
if "%RUNCASDUMP%"=="1" ( 
    if "%SERVER_STATUS%"=="Started" (
      call :TEE1 Region %REGION% is started - attempting to get a casdump 
      ) else (
      call :TEE1 %REGION% region not started or status not detected - attempting casdump anyway
      )
    call :GetCasDump
  ) ELSE (
    call :TEE1 Region [%REGION%] not currently running - cannot take casdump
  )

REM ----------------------------------------------------------------------------
REM Copy files from Region Workarea/system directoy
REM includes console.log, log.html, cas AUX and Dump files and any HSF o/p - may be large! (prompt if over a certain size??)
REM ----------------------------------------------------------------------------
call :GetWorkarea
call :TEE2 REGION_WORKAREA="%REGION_WORKAREA%"
REM prevent

REM IF no console.log found, skip the copy but then if running interactively give up...
if "%NO_CONSOLELOG%"=="1" goto SKIP_COPY_WA

call :TEE1 Copying System Directory files from %REGION_WORKAREA%
REM *** Note that one sharing violation is expected ***
mkdir %SNAPDIR%\%REGION%
REM May get sharing violation so redirect o/p to NUL
REM Note no subdirectories will be copied
xcopy "%REGION_WORKAREA%" %SNAPDIR%\%REGION% /c/Y/q  >>%SNAPLOG% 2>&1

call :TEE2 %DATE%,%TIME%, %REGION_WORKAREA% copied

REM continue with RDO file copy
goto JUMP_TO_RDO_FILES

:SKIP_COPY_WA
REM Give up if running interactively - will output a relevant message.
REM Don't skip the collection of journal files etc even if running interactively 
REM REM if "%MFES_NOPROMPT%" NEQ "1" goto NO_WArea
REM otherwise will continue from here if no console.log BUT we are running non-interactively...

:JUMP_TO_RDO_FILES
REM ----------------------------------------------------------------------------
REM Get dfhdrdat files
REM ----------------------------------------------------------------------------
call :Get_dfhdrdat

REM ----------------------------------------------------------------------------
REM Copy journal.dat
REM ----------------------------------------------------------------------------
call :TEE1 MFDS journal log
call :GetMFDSdir
if %MFDS_DIR_OK%==0 (
  Call :TEE1 Skipping MFDS file collection
  goto SKIP_MFDS_FILES
  )
  
REM Get the drive of where MFDS is installed and check for 8dot3
set MFDS_DRIVE=%MFDS_SCHEMA_DIR:~0,2%
call :TEE2 Checking short path name support on MFDS drive: %MFDS_DRIVE% 
fsutil 8dot3name query %MFDS_DRIVE% >> %SNAPLOG% 2>&1

Call :TEE1 Create journal.txt
mfds -t >>%SNAPLOG% 2>&1
set JOURN_ERR=%ERRORLEVEL%
if NOT %JOURN_ERR%==1 (
  call :TEE2 - unable to create journal text file in MFDS directory [%JOURN_ERR%] - retry with SNAPDIR
  mfds -t %SNAPDIR%\journal_as_text.txt >>%SNAPLOG% 2>&1
)
if %JOURN_ERR%==0 call :TEE2 Created journal text file

call :TEE2 Copy Journal.dat - 1st check location of journal using mfds -h 0:
SET MFDSCFGFILE=%SNAPDIR%\MFDS_cfg.out
SET MFDSCFGOUT=%SNAPDIR%\MFDS_CFG2.out
mfds -h 0 > %MFDSCFGFILE% 2>&1

REM Need this for journal.dat - when is the endlocal?
REM Set in processFile routine...
REM setlocal EnableDelayedExpansion

set skipnextRead=0
call :TEE2 call :ProcessFile with %MFDSCFGFILE% %MFDSCFGOUT%
call :ProcessFile < %MFDSCFGFILE% > %MFDSCFGOUT%

call :TEE2 Parse %MFDSCFGOUT% to find journal directory path
for /f "Tokens=1,3*" %%i in ('findstr /c:"Journal Directory" %MFDSCFGOUT%') do set JOURNAL_LOC=%%k
call :TEE2 Journal location from mfds output is: [%JOURNAL_LOC%]
REM Stip off any trailing slash and conver to short path
call :CheckPath JOURNAL_LOC
REM strip off the double quotes
for /f "useback tokens=*" %%a in ('%JOURNAL_LOC%') do set JOURNAL_LOC=%%~a

if exist "%JOURNAL_LOC%\journal.dat" echo Copying %JOURNAL_LOC%\journal.dat & copy "%JOURNAL_LOC%\journal.*" %SNAPDIR% >>%SNAPLOG% 2>&1
if not exist "%JOURNAL_LOC%\journal.dat" call :TEE2 File doesn't exist: [%JOURNAL_LOC%\journal.dat]

REM if exist "%MFDS_SCHEMA_DIR%\..\journal.dat" echo Copying %MFDS_SCHEMA_DIR%\..\journal.dat & copy "%MFDS_SCHEMA_DIR%\..\journal.*" %SNAPDIR% >>%SNAPLOG% 2>&1
REM if not exist "%MFDS_SCHEMA_DIR%\..\journal.dat" call :TEE1 "%MFDS_SCHEMA_DIR%\..\journal.dat" not found

REM Check and copy any MFDS ctf trace text file:
set MFDSCTFLOG="%MFDS_SCHEMA_DIR%\..\mfds.journal.ctf.txt"
if exist %MFDSCTFLOG% (
  call :TEE2 Copying %MFDSCTFLOG%
  copy %MFDSCTFLOG% %SNAPDIR% >>%SNAPLOG% 2>&1
) else (
  call :TEE2 %MFDSCTFLOG% doesn't exist
)

REM ----------------------------------------------------------------------------
REM Copy all MFDS info - region export via mfds may not have worked
REM ----------------------------------------------------------------------------
call :TEE1 Copying MFDS info
REM Xcopy doesn't like a trailing slash...
REM Don't copy empty sub-directories (causes .vbs zip script a problem)
call :TEE2 %DATE%,%TIME%, xcopy "%MFDS_SCHEMA_DIR%\." %SNAPDIR%\MFDS_SCHEMA /s/c/Y/i/q
if exist "%MFDS_SCHEMA_DIR%\srv.dat" xcopy "%MFDS_SCHEMA_DIR%\." %SNAPDIR%\MFDS_SCHEMA /s/c/Y/i/q >>%SNAPLOG% 2>&1
if not exist "%MFDS_SCHEMA_DIR%\srv.dat" call :TEE1 "%MFDS_SCHEMA_DIR%\srv.dat" not found

:SKIP_MFDS_FILES

REM ----------------------------------------------------------------------------
REM Checking if Region export was successful 
REM ----------------------------------------------------------------------------
call :TEE2 Checking MFDS exported files for this region in [%MFDSEXPORT_REGIONDIR%]
if not exist %MFDSEXPORT_REGIONDIR%\srv.dat (
  Call :TEE2 No region export - retrying using anonymous access
  mfds -x 1 %MFDSEXPORT_REGIONDIR% %REGION% SO >>%SNAPLOG% 2>&1
  REM Check again
  Call :TEE2 Sleeping for 2 seconds to allow the export to complete...
  ping 127.0.0.1 -n 3 > NUL
  if not exist %MFDSEXPORT_REGIONDIR%\srv.dat Call :TEE2 Still no region export - need different credentials?
) else (
  Call :TEE2 Export files exist for this region
)

REM If we didn't generate the MDUMP_ENV_FILE then don't bother to get any region-specific files
REM This means we won't get any equivalent defaults either
IF NOT EXIST "%MDUMP_ENV_FILE%" call :TEE2 No %MDUMP_ENV_FILE% file - skip CTF etc & goto GetFromInstallLoc

REM ----------------------------------------------------------------------------
REM Get CTF info MFTRACE_CONFIG, MFTRACE_LOGS
REM ----------------------------------------------------------------------------
call :TEE2 *** Get CTF info from MFTRACE_CONFIG, MFTRACE_LOGS ***
call :TEE1 Checking CTF trace configuration information
Call :Get_MFtraceConfig

REM ----------------------------------------------------------------------------
REM Get EXTFH, COBCONFIG and FHREDIR
REM ----------------------------------------------------------------------------
REM if exist "%EXTFH%" call :TEE1 %EXTFH% & copy "%EXTFH%" %SNAPDIR% >>%SNAPLOG%
call :Get_EXTFH
REM if exist "%COBCONFIG_%" call :TEE1 %COBCONFIG_% & copy "%COBCONFIG_%" %SNAPDIR% >>%SNAPLOG%
call :Get_COBCONFIG_
call :Get_FHREDIR

:GetFromInstallLoc
REM Get files from installation location
REM Other "*.dat" files (e.g. mf-client.dat, mf-server.dat)
call :TEE2 *** Copy other "*.dat" files (e.g. mf-client.dat, mf-server.dat) ***
call :TEE1 Copying additional config and .dat and files:
if exist "%PRODUCT_PATH%\bin" dir /b "%PRODUCT_PATH%\bin\*.dat" & copy "%PRODUCT_PATH%\bin\*.dat" %SNAPDIR% >>%SNAPLOG% 2>&1
if exist "%PRODUCT_PATH%\Base\bin" dir /b "%PRODUCT_PATH%\Base\bin\*.dat" & copy "%PRODUCT_PATH%\Base\bin\*.dat" %SNAPDIR% >>%SNAPLOG% 2>&1
REM COBVER or EDVER
if exist "%PRODUCT_PATH%\etc\edver" call :TEE1 Copying %PRODUCT_PATH%\etc\edver & copy "%PRODUCT_PATH%\etc\edver" %SNAPDIR% >>%SNAPLOG% 2>&1
if exist "%PRODUCT_PATH%\Bin\cobver" call :TEE1 Copying %PRODUCT_PATH%\Bin\cobver & copy "%PRODUCT_PATH%\Bin\cobver" %SNAPDIR% >>%SNAPLOG% 2>&1
if exist "%PRODUCT_PATH%\Base\Bin\cobver" call :TEE1 Copying %PRODUCT_PATH%\Base\Bin\cobver & copy "%PRODUCT_PATH%\Base\Bin\cobver" %SNAPDIR% >>%SNAPLOG% 2>&1

REM ----------------------------------------------------------------------------

call :TEE1 Getting final environment variables
set > %SNAPDIR%\set2.out

call :Get_ProcessList 2

call :TEE1 End of Collection

call :ZIP_FILES

REM ============================================================================
REM End of collection
REM ============================================================================
goto stop

REM ============================================================================
:GetRegion
REM Will prompt for region if running interactively
REM Otherwise set region to DUMMY so that script continues.
REM ============================================================================
:GetRegion
call :TEE2 GetRegion
REM (could also be entered as the 1st parameter to this script)

echo.
:PromptForRegion
if "%MFES_NOPROMPT%" NEQ "1" (
  call :TEE2 Running interactively - prompting for region
REM  echo.
  set /p REGION="Please enter your REGION name: "
  call :TEE2 REGION=[%REGION%]
) else (
  call :TEE2 Running non-interactively, not prompting for region - set to DUMMY
  set REGION=DUMMY
)
REM Check if region is now set - would be DUMMY if non-interactive
if "%REGION%"=="" (
REM pause and prompt if running interactively
  call :TEE1 No region entered - please re-enter Region
  call :TEE2 goto PromptForRegion to re-prompt
  goto PromptForRegion
)
echo.
goto :eof
REM ============================================================================
REM End of GetRegion
REM ============================================================================

REM ============================================================================
:getWorkArea
REM ============================================================================
call :TEE2 getWorkArea
set WORKAREA=
set REGION_WORKAREA=

call :GetDefWA

call :TEE2 DEF_WORKAREA=%DEF_WORKAREA%

REM First check/parse MFES_SYSDIR if set as we can use this in 2 places below
REM Note parameter should be set in the environment without quotes!
if NOT "%MFES_SYSDIR%"x == ""x (
  call :CheckPath MFES_SYSDIR
  REM strip off any double quotes
  for /f "useback tokens=*" %%a in ('%MFES_SYSDIR%') do set MFES_SYSDIR=%%~a
)

REM (NO_MFDS==1 if MFDS not running)
if "%NO_MFDS%"=="1" goto UpdWArea

for /f "Tokens=1,2*" %%i in ('findstr mfCASSysDir: %MDUMP_FILE%') do set REGION_WORKAREA=%%j
REM If mfds has "<null>" for mfCASSysDir then it MUST be using the default
if "%REGION_WORKAREA%" == "<null>" set REGION_WORKAREA=%DEF_WORKAREA%\%REGION%
REM If REGION_WORKAREA is the empty string also set it to the default area
if "%REGION_WORKAREA%" == "" set REGION_WORKAREA=%DEF_WORKAREA%\%REGION%

call :TEE2 REGION_WORKAREA="%REGION_WORKAREA%"
call :CheckForDollar REGION_WORKAREA 

REM If we've obtained the full path to the system dir (from mfds):
IF EXIST "%REGION_WORKAREA%\console.log" goto EndGWA  

REM If we get here, its most likely that the dir wasn't specified AND the default can't be obtained
REM If we simply haven't been able to retrieve the region config we should have gone to UpdWArea...
REM Now allow for user to have specified the actual system dir (console.log not found so far)
if NOT "%MFES_SYSDIR%"x == ""x (
  CALL :TEE2 MFES_SYSDIR is set [%MFES_SYSDIR%]
  Call :TEE1 Using System Directory from environment variable MFES_SYSDIR
  set REGION_WORKAREA=%MFES_SYSDIR%
  REM not using delayedExpansion so check with original variable at this stage
  IF EXIST "%MFES_SYSDIR%\console.log" (
    goto EndGWA
  ) ELSE (
    call :TEE1 No console.log found in MFES_SYSDIR [%MFES_SYSDIR%\console.log]
  )
)

echo.
call :TEE1 Unable to find console.log in: %REGION_WORKAREA%

REM prompt for correct region area:
REM If we get here, fall into UpdWArea to prompt for the dir
REM Otherwise we 'goto' UpdWArea if MFDS not available

:UpdWArea
REM CLS
call :TEE2 UpdWArea
echo.

REM First allow for user to have specified the actual system dir (for cases when mdump doesn't run etc)
if NOT "%MFES_SYSDIR%"x == ""x (
  CALL :TEE2 MFES_SYSDIR is set [%MFES_SYSDIR%]
  Call :TEE1 Using System Directory from environment variable MFES_SYSDIR
  set REGION_WORKAREA=%MFES_SYSDIR%
  REM not using delayedExpansion so check with original variable at this stage
  IF EXIST "%MFES_SYSDIR%\console.log" (
    goto EndGWA
  ) ELSE (
    call :TEE1 No console.log found in MFES_SYSDIR [%MFES_SYSDIR%\console.log]
  )
)

REM At this point we have been unable to find console.log - hence no SYSDIR, so prompt user for location  
call :TEE1 This script needs the system directory path for [%REGION%]
set NEW_WORKAREA=
set REGION_WORKAREA=
echo.
call :TEE1 Default location is [%DEF_WORKAREA%]


REM Doing the following prompt+set and use in 2 stages due to delayedexpansion problem
echo.
if "%MFES_NOPROMPT%" NEQ "1" (
  call :TEE2 Running interactively so will prompt for path
  call :TEE1 Enter full System Directory path for [%REGION%]:
  set /p NEW_WORKAREA=[or press CR to use the above default]
) else (
  call :TEE2 Running non-interactively, not prompting for path
)
REM second stage, now that NEW_WORKAREA is set, if entered
REM Note NEW_WORKAREA will only be set if running interactively

if "%NEW_WORKAREA%1" == "1" (
  call :TEE2 Must be non-interactive, NEW_WORKAREA not set so use default location [%DEF_WORKAREA%]
  set REGION_WORKAREA=%DEF_WORKAREA%\%REGION%
) ELSE (
  call :TEE2 Running interactively and NEW_WORKAREA Entered:[%NEW_WORKAREA%]
  set REGION_WORKAREA=%NEW_WORKAREA%
)
  
call :TEE2 System Directory set to: %REGION_WORKAREA%
IF NOT EXIST "%REGION_WORKAREA%\console.log" (
  REM only one additional attempt with a different default
  REM if NO_CONSOLELOG==2 goto EndGWA
  call :TEE2 still no console.log found, settting NO_CONSOLELOG=1 to skip WorkArea copy
  set NO_CONSOLELOG=1
  REM Could check for the 64bit default (win2008?)
  REM "%windir%\SysWOW64\config\systemprofile\My Documents\Micro Focus\...
  REM set DEF_WORKAREA=...
  REM goto UpdWArea
  REM set NO_CONSOLELOG=2
  )

:EndGWA

goto :eof

REM ============================================================================
REM End of GetWorkArea
REM ============================================================================

REM ============================================================================
:GetDefWA
REM ============================================================================
call :TEE2 GetDefWA

Call :TEE1 Getting the Default System Work Area from Registry

if NOT "%NETX_VER%"=="" (
  call :TEE2 REG QUERY "HKEY_LOCAL_MACHINE\SOFTWARE\Micro Focus\NetExpress\%NETX_VER%\cobol\%NETX_VER%\install"  /v work
  for /f "Skip=2 Tokens=1,2*" %%i in ('REG QUERY "HKEY_LOCAL_MACHINE\SOFTWARE\Micro Focus\NetExpress\%NETX_VER%\cobol\%NETX_VER%\install"  /v work') do set DEF_WORKAREA=%%k
  ) else (
  call :TEE2 reg query "HKLM\Software\Micro Focus\%FULL_VERSION%\MFCICS\Install" /v WORK
  for /F "tokens=1,2*" %%g in ('reg query "HKLM\Software\Micro Focus\%FULL_VERSION%\MFCICS\Install" /v WORK') do (
    set DEF_WORKAREA=%%i
  )
  )
REM if "%DEF_WORKAREA%" == "" goto :eof
REM Need to check whether string is empty
REM problem here is double quotes
REM ED currently returns a string with spaces in but no quotes
REM NX returns a quoted string
REM Dos complains if you try to quote an already-quoted string
REM So problem would be if string was empty...

set "param2=%DEF_WORKAREA%"
setlocal EnableDelayedExpansion
REM Need DEF_WA_OK to be set outside this local block for GOTO as well as normal end
if "!param2!"=="" ( 
  call :TEE2 DEF_WA String not valid {!param2!} 
  call :TEE1 - Default Workarea directory not found in registry
  set DEF_WA_OK=0
  REM Make DEF_WA_OK available to rest of script after the goto
  goto END_GetDefWA 
  ) else (
  call :TEE2 DEF_WA String is valid {!param2!} 
  set DEF_WA_OK=1
  )
REM endlocal now at end of this routine
REM endlocal & set DEF_WA_OK=%DEF_WA_OK%

:PROCESS_WA
REM Expand all environment variables within DEF_WORKAREA (includes USERPROFILE)
call set DEF_WORKAREA=%DEF_WORKAREA%
call :TEE2 DEF_WORKAREA=%DEF_WORKAREA%

REM strip off the double quotes
for /f "useback tokens=*" %%a in ('%DEF_WORKAREA%') do set DEF_WORKAREA=%%~a

::Does string have a trailing slash? if so remove it 
IF %DEF_WORKAREA:~-1%==\ SET DEF_WORKAREA=%DEF_WORKAREA:~0,-1%

REM Now convert to short path
call :CheckPath DEF_WORKAREA
REM strip off the double quotes
for /f "useback tokens=*" %%a in ('%DEF_WORKAREA%') do set DEF_WORKAREA=%%~a

:END_GetDefWA
REM We can GOTO here from the setlocal loop
REM Need DEF_WA_OK to be set after this endlocal
REM Also need to expose DEF_WORKAREA as this is also now set in the local block
endlocal & set DEF_WA_OK=%DEF_WA_OK%& set DEF_WORKAREA=%DEF_WORKAREA%

goto :eof
REM ============================================================================
End GetDefWA
REM ============================================================================

REM ============================================================================
:NO_WArea
REM ============================================================================
REM cls
echo.
call :TEE1 System Directory not set correctly (%REGION_WORKAREA%)
call :TEE1  - no console.log file found!
call :TEE1 Unable to collect any Region files
call :TEE1 Please re-run this script and provide the full system directory path for %REGION%
call :TEE1 NOTE: The environment variable MFES_SYSDIR can be set to the system directory
echo.
REM Only pause if running interactively
if "%MFES_NOPROMPT%" NEQ "1" PAUSE

Call :TEE1 mfSupportInfo output has been created plus some Operating System files,
Call :TEE1 please provide the snapshot directory even if Region files can't be generated.
echo.
REM Only pause if running interactively
if "%MFES_NOPROMPT%" NEQ "1" PAUSE
call :ZIP_FILES
goto stop
REM ============================================================================
REM end NO_WArea
REM ============================================================================

REM ============================================================================
:GetProdVer
REM ============================================================================
call :TEE2 GetProdVer
set ED_VER=
set NETX_VER=
set FULL_VERSION=
set ED_NOT_FOUND=0

REM check for highest level of product and work down...
REM Note that before ED2.3 the different versions of Visual Studio resulted in different specific products installations
if {%ED_VER%} == {} (
    REM Get Enterprise Developer default version.
    (for /F "tokens=1,2*" %%g in ('reg query "HKLM\Software\Micro Focus\Visual COBOL" /v DefaultVersion') do set ED_VER=%%i) >>%SNAPLOG% 2>&1
		set VERSION=Visual COBOL
)

if {%ED_VER%} == {} (
    REM Get Enterprise Developer default version.
    (for /F "tokens=1,2*" %%g in ('reg query "HKLM\Software\Micro Focus\Visual COBOL 2013" /v DefaultVersion') do set ED_VER=%%i) >>%SNAPLOG% 2>&1
		set VERSION=Visual COBOL 2013
)

if {%ED_VER%} == {} (
    REM Get Enterprise Developer default version.
    (for /F "tokens=1,2*" %%g in ('reg query "HKLM\Software\Micro Focus\Visual COBOL 2012" /v DefaultVersion') do set ED_VER=%%i) >>%SNAPLOG% 2>&1
		set VERSION=Visual COBOL 2012
)


if {%ED_VER%} == {} (
    call :TEE2 Enterpise Developer not found - checking for Net Express
    (for /f "Skip=2 Tokens=1,2*" %%i in ('reg query "HKLM\SOFTWARE\Micro Focus\NetExpress" /v DefaultVersion') do set NETX_VER=%%k) >>%SNAPLOG% 2>&1
    set VERSION=NetExpress
    REM If we get here then ED_VER didn't get set 
    set ED_NOT_FOUND=1
)

REM If no ED_VER and no NETX_VER then no point trying to set FULL_VERSION
if %ED_NOT_FOUND% == 1 (
  if {%NETX_VER%} == {} (
    call :TEE2 No ED_VER and no NETX_VER 
    goto :eof
  ) else (
    REM NX found - set FULL_VERSION 
    set FULL_VERSION=%VERSION%\%NETX_VER%
  )
) else (
  REM ED found - set FULL_VERSION
  set FULL_VERSION=%VERSION%\%ED_VER%
)

call :TEE2 VERSION={%VERSION%}, ED_VER={%ED_VER%}
call :TEE2 FULL_VERSION=%FULL_VERSION%

goto :eof
REM ============================================================================
REM End GetProdVer
REM ============================================================================

REM ============================================================================
:GetInstallDir
REM ============================================================================
call :TEE2 GetInstallDir
call :TEE2 "NETX_VER"="%NETX_VER%"
call :TEE2 FULL_VERSION={%FULL_VERSION%}

Call :TEE1 Getting Product Installation Directory from Registry

if NOT "%NETX_VER%"=="" (
  for /f "Skip=2 Tokens=1,2*" %%i in ('REG QUERY "HKEY_LOCAL_MACHINE\SOFTWARE\Micro Focus\NetExpress\%NETX_VER%\Setup"  /v RootDir') do (
    set PRODUCT_PATH=%%k
    )
  call :TEE2 Collecting for Net Express ver:%NETX_VER%
) else (
  for /F "tokens=1,2*" %%g in ('reg query "HKLM\Software\Micro Focus\%FULL_VERSION%" /v INSTALLDIR') do (
    set PRODUCT_PATH=%%i
    )
  call :TEE2 Collecting for %FULL_VERSION%
)


call set PRODUCT_PATH=%PRODUCT_PATH%
call :TEE2 PRODUCT_PATH=%PRODUCT_PATH%
REM Check we have product_path set before parsing it
REM Both 6.0 and ED have the product install dir un-quoted.
if "%PRODUCT_PATH%"x == ""x (
  call :TEE2 - unable to determine PRODUCT_PATH for this version from registry lookup
  REM We will carry on anyway with no product dir
  GOTO END_GetInstallDir
  )

::Does string have a trailing slash? if so remove it
REM This is done in CheckPath
REM IF %PRODUCT_PATH:~-1%==\ SET PRODUCT_PATH=%PRODUCT_PATH:~0,-1%
REM call :TEE2 PRODUCT_PATH=%PRODUCT_PATH%
REM Now convert to short path
call :CheckPath PRODUCT_PATH
REM strip off the double quotes
for /f "useback tokens=*" %%a in ('%PRODUCT_PATH%') do set PRODUCT_PATH=%%~a

:END_GetInstallDir

goto :eof
REM ============================================================================
REM End GetInstallDir
REM ============================================================================

REM ============================================================================
:GetMFDSdir
REM ============================================================================
call :TEE2 GetMFDSdir, NETX_VER=%NETX_VER%

Call :TEE1 Getting the MFDS install location from Registry

if NOT "%NETX_VER%"=="" (
  for /f "Skip=2 Tokens=1,2*" %%i in ('REG QUERY "HKEY_LOCAL_MACHINE\SOFTWARE\Micro Focus\NetExpress\%NETX_VER%\MFDS\%NETX_VER%\install"  /v SCHEMA') do set MFDS_SCHEMA_DIR=%%k
  ) else (
    for /F "tokens=1,2*" %%g in ('reg query "HKLM\Software\Micro Focus\%FULL_VERSION%\MFDS\Install" /v SCHEMA') do (
    set MFDS_SCHEMA_DIR=%%i
  )
  )

call :TEE2 MFDS_SCHEMA_DIR=[%MFDS_SCHEMA_DIR%]

REM Need to check whether string is empty
REM problem here is double quotes
REM ED currently returns a string with spaces in but no quotes
REM NX returns a quoted string
REM Dos complains if you try to quote an already-quoted string
REM So problem would be if string was empty...

set "param1=%MFDS_SCHEMA_DIR%"
setlocal EnableDelayedExpansion
REM Need MFDS_DIR_OK to be available outside this local block for GOTO as well as normal end
if "!param1!"=="" ( 
  call :TEE2 MFDS String not valid {!param1!} 
  call :TEE1 MFDS directory not found in registry
  set MFDS_DIR_OK=0
  REM Need to make MFDS_DIR_OK available to rest of script after the goto
  goto END_GetMFDSdir 
  ) else (
  call :TEE2 MFDS String is valid {!param1!} 
  set MFDS_DIR_OK=1
  )
REM endlocal & set MFDS_DIR_OK=%MFDS_DIR_OK%

REM strip off the double quotes
for /f "useback tokens=*" %%a in ('%MFDS_SCHEMA_DIR%') do set MFDS_SCHEMA_DIR=%%~a

::Does string have a trailing slash? if so remove it
IF %MFDS_SCHEMA_DIR:~-1%==\ SET MFDS_SCHEMA_DIR=%MFDS_SCHEMA_DIR:~0,-1%

call :TEE2 Now convert to short path MFDS_SCHEMA_DIR=[%MFDS_SCHEMA_DIR%]
call :CheckPath MFDS_SCHEMA_DIR
REM strip off the double quotes
for /f "useback tokens=*" %%a in ('%MFDS_SCHEMA_DIR%') do set MFDS_SCHEMA_DIR=%%~a

call :TEE2 End GetMFDS - MFDS_SCHEMA_DIR=[%MFDS_SCHEMA_DIR%]

:END_GetMFDSdir
REM We can GOTO here from the setlocal loop
REM Need MFDS_DIR_OK to be set after this endlocal
REM Also need to expose MFDS_SCHEMA_DIR as this is also now set in the local block
endlocal & set MFDS_DIR_OK=%MFDS_DIR_OK%& set MFDS_SCHEMA_DIR=%MFDS_SCHEMA_DIR%

goto :eof
REM ============================================================================
REM End GetMFDSdir
REM ============================================================================

REM ============================================================================
:Get_Region_info
REM Dumps Region Configuration info to a file
REM Checks if unable to get dump:
REM sets set NO_MFDS=1 if MFDS not running or mdump failed to run
REM Needs mdump.exe to exist in the PATH or the current directory 
REM (or the same directory as this script when run from Explorer)
REM Sets NO_REGION if could run mdump but didn't get info about this region
REM ============================================================================
call :TEE2 %DATE%,%TIME%, Get_Region_Info
set NO_MFDS=0
call :TEE1 Getting configuration info for [%REGION%] from MFDS...
REM should be on path (see UTLDIR above)
PATH >> %SNAPLOG%

REM No longer want to use any copy of MSVDR100.dll that may have been previously provided,
REM this should mean we'll use the version in the OS
if EXIST "%UTLDIR%\msvcr100.dll" (
  Call :TEE2 Renaming previously provided msvcr100.dll in %UTLDIR%
  move "%UTLDIR%\msvcr100.dll" "%UTLDIR%\msvcr100_mfesdiagMoved.dll" >> %SNAPLOG% 2>&1
)

REM Set this so we can retry with older version of mdump if required
set USE_MDUMP2=1
REM Note that this forces mdump3_7 to be used if problems, however we should now be using mdump from product anyway.

REM Default to using mdump.exe supplied with product
REM use FOR with PATHEXT and SET to determine whether mdump.exe is on the path...
REM This way we don't need to worry about/use PBINDIR and spacey paths...
REM Note that at this point in the script we should have added the product path to the PATH env var so will find mdump.exe if its in the product.

set MDUMP_EXE=
for %%e in (%PATHEXT%) do (
  for %%X in (mdump%%e) do (
    if not defined MDUMP_EXE (
      set MDUMP_EXE=%%~$PATH:X
    )
  )
 )
 
if "%MDUMP_EXE%"=="" (
    call :TEE2 no mdump on PATH - using supplied version
    REM use supplied mdump, depending on product - Assume ED
    set MDUMP_EXE=%UTLDIR%\mdump.exe 
    REM If NX set mdump to older version:
    if NOT "%NETX_VER%"=="" set MDUMP_EXE=%UTLDIR%\mdump3.7.exe& set USE_MDUMP2=0
) else (
    call :TEE2 found mdump.exe on PATH
)
 
CALL :TEE2 MDUMP_EXE=%MDUMP_EXE%

REM Run mdump to get region info
REM Took out double-quotes round MDUMP_EXE - aborts script if a spacey path???
call :TEE2 %MDUMP_EXE% -a localhost -n %REGION% 
"%MDUMP_EXE%" -a localhost -n %REGION% > %MDUMP_FILE% 2>&1
 
set MDUMP_ERRORLEVEL=%ERRORLEVEL%

call :TEE2 MDUMP_ERRORLEVEL=%MDUMP_ERRORLEVEL%
if %MDUMP_ERRORLEVEL% NEQ 0 set NO_MFDS=1

set MDUMPERR=0
if %MDUMP_ERRORLEVEL%==9009 set MDUMPERR=1
if %MDUMP_ERRORLEVEL% LSS 0 set MDUMPERR=1
if %MDUMPERR% EQU 1 call :TEE2 Problem with .dll or not found error returned from mdump

set MDUMP_ERRLVL2=0

if %MDUMP_ERRORLEVEL% NEQ 0 (
  REM Copy any error message in the MDUMP_FILE to snapshot log before continuing (we overwrite it next)
  type %MDUMP_FILE% >> %SNAPLOG%
  REM reset NO_MFDS flag
  set NO_MFDS=0
  REM see whether to retry with older version (or the newer version if collecting for NX)
  if %USE_MDUMP2% EQU 1 (
    set MDUMP_EXE=%UTLDIR%\mdump3.7.exe
    REM not using delayedexpansion...
    call :TEE2 %UTLDIR%\mdump3.7.exe -a localhost -n %REGION% 
    "%UTLDIR%\mdump3.7.exe" -a localhost -n %REGION% > %MDUMP_FILE% 2>&1
  ) else (
  REM this would be USE_MDUMP2==0 so we can retry with the newer version just in case this works!
    set MDUMP_EXE=%UTLDIR%\mdump.exe
    REM not using delayedexpansion...
    call :TEE2 %UTLDIR%\mdump.exe -a localhost -n %REGION% 
    "%UTLDIR%\mdump.exe" -a localhost -n %REGION% > %MDUMP_FILE% 2>&1
    )
)
REM Need to set this outside of above loop since no delayed expansion...
set MDUMP_ERRLVL2=%ERRORLEVEL%

REM now check if the other mdump ran ok
call :TEE2 MDUMP_ERRLVL2=%MDUMP_ERRLVL2%
if %MDUMP_ERRLVL2% NEQ 0 set NO_MFDS=1

call :TEE2 MDUMP_EXE=%MDUMP_EXE%, NO_MFDS=%NO_MFDS%

if %NO_MFDS%==1 call :TEE1 - can't get Region configuration: unable to run mdump.exe or MFDS not on default port?

REM NO_REGION should still be 0 so that we allow prompt for sysdir
if %NO_MFDS%==1 goto End_GRI

REM Now we should have an MDUMP_FILE generated
REM MDUMP_EXE should be set appropriately

CALL :TEE2 check mdump output for valid output - mfStructVersion
findstr "mfStructVersion:" %MDUMP_FILE% >> %SNAPLOG%
if %ERRORLEVEL%==0 (
  set NO_REGION=0
  call :TEE2 mfStructVersion string found in mdump output
  ) else (
  set NO_REGION=1
  call :TEE2 mfStructVersion string NOT in mdump output - no region found
  goto End_GRI
  )

REM check the valid mdump output for THIS region info
type %MDUMP_FILE% | findstr "NO_SUCH_OBJECT" >> %SNAPLOG%
if %ERRORLEVEL%==0 (
  call :TEE2 No info on this region in mdump output
  set NO_REGION=1
  goto End_GRI
  ) else (
  set NO_REGION=0
)

REM If we get here then mdump worked and we have the region configuration file to work with

REM mdump seems to o/p info for all regions if MFDS isn't 1.15 - o/p to separate file
REM Try a 2nd mdump with the -e option for security config info 
REM older versions of mdump don't support the -e option - need MFDS v1.15 or above 
REM IF not ED then don't try to get security info
  call :TEE2 If ED, do 2nd mdump with the -e option to get security config info
  if NOT "%ED_VER%"=="" "%MDUMP_EXE%" -e 2 -a localhost -n %REGION% > %MDUMP_SECY_FILE% 2>>%SNAPLOG% &
  set MDUMP_SECY_ERR_LVL=%ERRORLEVEL%
  if %MDUMP_SECY_ERR_LVL% NEQ 0 call :TEE2 MDUMP_SECY_ERR_LVL=%MDUMP_SECY_ERR_LVL%

Rem Now get just the environment variable parameters (i.e. set with the equals sign)
Rem this is used to obtain the individual env var values later
REM Don't want any commented-out lines
call :TEE2 Get just the environment variable parameters


findstr = %MDUMP_FILE% | findstr -v # > %MDUMP_ENV_FILE%
set FINDSTR_ERROR=%ERRORLEVEL%

if %FINDSTR_ERROR% NEQ 0 call :TEE2 No Env vars found, ret=%FINDSTR_ERROR%
if %FINDSTR_ERROR% EQU 0 type %MDUMP_ENV_FILE% >> %SNAPLOG%

:End_GRI

goto :eof
REM ============================================================================
REM End Get_Region_info
REM ============================================================================


REM ============================================================================
:CREATE_SNAPDIR
REM Creates SNAPDIR, SYSINFODIR and SNAPLOG
REM ============================================================================
setlocal
rem ** Dynamic log directory...
Rem Below we substitute various characters that may be in DATE and TIME to make a valid dir/file name
set SNAPDIR=
set TMPSNAPSHOT=
set TMPSNAPSHOT=%DATE%_%TIME%.snapshot
set TMP2SNAPSHOT=%TMPSNAPSHOT:/=-%
set TMP3SNAPSHOT=%TMP2SNAPSHOT::=-%
set TMP5SNAPSHOT=%TMP3SNAPSHOT:,=-%
set TMP6SNAPSHOT=%TMP5SNAPSHOT:.=-%
set SNAPSHOTNAME=%TMP6SNAPSHOT: =-%
REM set SNAPDIR=%TEMP%\MFESDIAGDIR\%TMP6SNAPSHOT: =-%
set SNAPDIR=%TEMP%\MFESDIAGDIR\%SNAPSHOTNAME%

REM Now convert to short path
REM Can't write to log yet - dir isn't created!!! call :TEE2 Convert to short path: %SNAPDIR%
for %%I in ("%SNAPDIR%") do set SHORT_SNAPDIR=%%~sI
set SNAPDIR=%SHORT_SNAPDIR%

rem check to see if the snapshot is already present...
if exist "%SNAPDIR%" goto snapExist

if not exist %SNAPDIR% mkdir %SNAPDIR%
REM Make a subdir for OS+System output
set SYSINFODIR=%SNAPDIR%\SystemInfo
mkdir %SYSINFODIR%
 
set SNAPLOG=%SNAPDIR%\snapshot.log
REM REM for testing:
if "%TESTING%" GEQ "2" (
  echo TESTING Using local snapshot.log
  set SNAPLOG=.\snapshot.log
  echo TESTING SNAPLOG=%SNAPLOG%
REM REM Testing: do a CD here to show where we create the snapshot.log when testing...
  cd
)

echo The diagnostic files will be collected under %%TEMP%%\MFESDIAGDIR.
echo The Snapshot directory used to collect files for this run is:
echo %SNAPDIR%
echo.

endlocal & set SNAPDIR=%SNAPDIR%& set SYSINFODIR=%SYSINFODIR%& set SNAPLOG=%SNAPLOG%

goto :eof
 
REM ============================================================================
REM End CREATE_SNAPDIR
REM ============================================================================

REM ============================================================================
:snapExist
REM ============================================================================
call :TEE1 %SNAPDIR% directory already exists!
set snapdir_exists=1
goto stop
REM ============================================================================
REM End snapExist
REM ============================================================================

REM ============================================================================
:workarea_copy_failed
REM ============================================================================
call :TEE1 --- Error during xcopy of workarea
goto stop
REM ============================================================================
REM end workarea_copy_failed
REM ============================================================================

REM ============================================================================
:Get_ProcessList
REM Uses passed-in parameter 1 for the output filename
REM ============================================================================
echo %TIME% >> %SYSINFODIR%\tasklist%1.out
call :TEE2 %DATE% %TIME% Get_ProcessList
call :TEE1 Taking process listing %1 ...

echo process listing %1 >> %SYSINFODIR%\tasklist%1.out
REM Use WMIC for REGION processes to get the command line/args etc:
set WMIC_ERR=0
REM only do this on the 2nd call, once we've got the region name
if %1% EQU 2 (
  call :TEE2 WMIC PROCESS WHERE  "NOT Caption='findstr.exe'" get Caption,Processid,CommandLine,ExecutablePath,ParentProcessId,Status,ThreadCount - findstr /i "%region%  mfds caption"
  WMIC PROCESS WHERE  "NOT Caption='findstr.exe'" get Caption,Processid,CommandLine,ExecutablePath,ParentProcessId,Status,ThreadCount | findstr /i "%region%  mfds caption" > %SYSINFODIR%\WMIC%1.out
  set WMIC_ERR=%ERRORLEVEL%
)
If NOT %WMIC_ERR% EQU 0 Call:TEE2 Error running WMIC: %WMIC_ERR%

REM WMIC doesn't get username of process, use tasklist for this
REM No longer running in background as may not have copmletd before zip is started...
if EXIST %WINDIR%\System32\tasklist.exe (
 call :TEE2 found tasklist.exe
 TASKLIST /v /fo table >> %SYSINFODIR%\tasklist%1.out
 TASKLIST /v /fo CSV > %SYSINFODIR%\tasklist%1.csv 2>>NUL
) ELSE (
 REM try pslist
 call :TEE2 Try pslist
 pslist >> %SYSINFODIR%\tasklist%1.out 2>>%SNAPLOG%
)
REM Note: can't echo to tasklist at this point o/p as we're running asynchronously
REM no longer running in background so can echo the end time
echo ================================================================================ >> %SYSINFODIR%\tasklist%1.out
echo %TIME% >> %SYSINFODIR%\tasklist%1.out
call :TEE2 %DATE%,%TIME%,       tasklist%1.out generated

goto :eof
REM ============================================================================
Rem End Get_ProcessList
REM ============================================================================

REM ============================================================================
:Get_Netstat
REM ============================================================================
call :TEE1 Taking a netstat of connections
set NOW=%DATE% %TIME%
echo %NOW% >> %SYSINFODIR%\netstat.lst
REM Netstat arg -b needs elevant/admin permissons (displays the process name, however -o shows the pid)
netstat -ano > %SYSINFODIR%\netstat.lst 2>&1
set NOW=%DATE% %TIME%
echo %NOW% >> %SYSINFODIR%\netstat.lst
call :TEE2 %DATE%,%TIME%      netstat.lst generated

goto :eof
REM ============================================================================
Rem End Get_Netstat
REM ============================================================================

REM ============================================================================
:Get_CCITCP2_info
REM ============================================================================
call :TEE1 Getting info on mF_CCITCP2 service (MFDS)
REM (SERVICE_NAME: mf_CCITCP2) -> use Tasklist, and SC or psservice
REM C:\Windows\System32\sc.exe
if EXIST %WINDIR%\System32\tasklist.exe (
 tasklist /svc /fi "imagename eq MFDS.exe" >>%SYSINFODIR%\mf_CCITCP_status.lst 2>>%SNAPLOG%
 tasklist /fi "services eq mF_CCITCP2" >>%SYSINFODIR%\mf_CCITCP_status.lst 2>>%SNAPLOG%
 sc qc mf_CCITCP2 >>%SYSINFODIR%\mf_CCITCP_status.lst 2>>%SNAPLOG%
) ELSE (
 REM try psservice
 psservice query mF_CCITCP2 >>%SYSINFODIR%\mf_CCITCP_status.lst 2>>%SNAPLOG%
)

call :TEE2 %DATE%,%TIME%,     mf_CCITCP_status.lst created

goto :eof
REM ============================================================================
REM End Get_CCITCP2_info
REM ============================================================================

REM ============================================================================
:Get_EventLog
REM ============================================================================
call :TEE1 Get Event log list info (last 60 events)
REM psloglist -x -n 60 >%SYSINFODIR%\syslog.lst 2>>%SNAPLOG%
REM Windows7 or Vista
set WinVISTA=0
if EXIST %WINDIR%\system32\wevtutil.exe (
  set WinVISTA=1
  call :TEE2 using wevtutil.exe
  wevtutil qe system /c:60 /rd:true /f:text >%SYSINFODIR%\system_wevtutil.log 2>>%SNAPLOG%
  wevtutil qe application /c:60 /rd:true /f:text >%SYSINFODIR%\application_wevtutil.log 2>>%SNAPLOG%
  wevtutil qe system /c:60 /rd:true /f:XML >%SYSINFODIR%\system_wevtutil.xml 2>>%SNAPLOG%
  wevtutil qe application /c:60 /rd:true /f:XML >%SYSINFODIR%\application_wevtutil.xml 2>>%SNAPLOG%
  ) else (
    call :TEE2  wevtutil.exe not found, will check for eventquery.vbs
  )

if %WinVISTA% EQU 1 goto skip_cscript

REM WindowsXP/Win2003
call :TEE2 Checking for cscript
cscript /? >> "%SNAPLOG%" 2>&1
if %ERRORLEVEL%==1 goto skip_cscript
set CSCRIPT_ERROR=0

if EXIST %WINDIR%\system32\eventquery.vbs (
  call :TEE2 using eventquery.vbs
  call :TEE2 cscript %WINDIR%\system32\eventquery.vbs /r 60 /l application /v /fo CSV
  cscript %WINDIR%\system32\eventquery.vbs /r 60 /l application /v /fo CSV > %SYSINFODIR%\Application_eventquery.csv
  set CSCRIPT_ERROR=%ERRORLEVEL%
  cscript %WINDIR%\system32\eventquery.vbs /r 60 /l system /v /fo CSV > %SYSINFODIR%\System_eventquery.csv
  cscript %WINDIR%\system32\eventquery.vbs /r 60 /l application /v /fo LIST > %SYSINFODIR%\Application_eventquery.log
  cscript %WINDIR%\system32\eventquery.vbs /r 60 /l system /v /fo LIST > %SYSINFODIR%\System_eventquery.log
  ) else (
    call :TEE2 eventquery.vbs not found.
  )
if %CSCRIPT_ERROR% NEQ 0 call :TEE2 CSCRIPT_ERROR=%CSCRIPT_ERROR%

:skip_cscript
call :TEE2 %DATE%,%TIME%, End of Get_EventLog

goto :eof
REM ============================================================================
REM End Get_EventLog
REM ============================================================================

REM ============================================================================
REM Get dfhdrdat files
REM ============================================================================
:Get_dfhdrdat
call :TEE2 Get_dfhdrdat


REM Set this so we get default file if can't get region info (NO_MFDS)
set REGION_DFHDRDAT=0

REM Setup the relevant path outside the IF loop (variable expansion problem!)
REM Default to ED
REM Make path relative to bin dir to take account of server/dev products
REM set DFHDRDAT_PATH="%PBINDIR%\..\etc\cas"

if NOT "%NETX_VER%"=="" (
  set NXINST=1
  )

REM call :TEE2 Default DFHDRDAT_PATH=%DFHDRDAT_PATH%

REM get location for this region (mfCASTXRDTP: (mdump) | mfCASTXRDTP= (mfds -x 5 ...))
REM Relies on 'mdump' having been run already to generate the output file
REM (NO_MFDS=1 if MFDS not running)
REM if %NO_MFDS%==1 echo can't get region's dfhdrdat location - try default location...
if %NO_MFDS%==1 goto GetDefRDO
for /f "Tokens=1,2*" %%i in ('findstr mfCASTXRDTP: %MDUMP_FILE%') do set DFHDRDAT_LOC=%%j
if "%DFHDRDAT_LOC%" == "<null>" Call :TEE2 No dfhdrdat location set in region & goto GetDefRDO
if "%DFHDRDAT_LOC%" == "" Call :TEE2 dfhdrdat location is empty string & goto GetDefRDO
REM DFHDRDAT file set in region
set REGION_DFHDRDAT=1
call :TEE1 Copying dfhdrdat from region's configured location
call :CheckForDollar DFHDRDAT_LOC 
call :TEE2 copy "%DFHDRDAT_LOC%\dfhdr*" 
copy "%DFHDRDAT_LOC%\dfhdr*" %SNAPDIR% >> %SNAPLOG%
REM All done - don't want any default file now
goto End_RegRDO

:GetDefRDO
REM only get default file if not set in region
if %REGION_DFHDRDAT% EQU 0 (
REM get default location (install dir)
  call :TEE1 copying default dfhdrdat files
REM Check and copy from NETX and ED locations as appropriate...
  if exist "%PBINDIR%\..\etc\cas"\dfhdrdat copy "%PBINDIR%\..\etc\cas"\dfhdr* %SNAPDIR% >> %SNAPLOG%
  if exist "%PBINDIR%\..\FILES\SYS"\dfhdrdat copy "%PBINDIR%\..\FILES\SYS"\dfhdr* %SNAPDIR% >> %SNAPLOG%
) else (
  call :TEE2 Default DFHDRDAT not needed -set in region
)

:End_RegRDO

goto :eof
REM ============================================================================
REM End Get dfhdrdat files
REM ============================================================================

REM ============================================================================
REM Get MFtraceConfig files
REM ============================================================================
:Get_MFtraceConfig
SETLOCAL
call :TEE2 Get_MFtraceConfig
set getCTFlogs=0

REM see if set in region config
REM Relies on 'mdump' having been run already to generate the output file
REM (NO_MFDS=1 if MFDS not running)
REM if %NO_MFDS%==1 echo can't get region's MFtraceConfig location - skipping...
if %NO_MFDS%==1 goto skipRegCTF

REM if no MDUMP_ENV_FILE goto check in the OS
IF NOT EXIST "%MDUMP_ENV_FILE%" call :TEE2 No %MDUMP_ENV_FILE% file - skip region check & goto ChkOSCTF

REM See if MFTRACE_CONFIG is set in the region's environment and if so return its value (in arg 1) - need name of variable and its length
Call :TEE2 check for MFTRACE_CONFIG in region's environment
call :GetVarFromFile MFtraceConfig_FILE MFTRACE_CONFIG 14 %MDUMP_ENV_FILE%
if "%MFtraceConfig_FILE%"=="" call :TEE2 MFTRACE_CONFIG not set in region & goto ChkOSCTF
if NOT "%MFtraceConfig_FILE%"==""  call :TEE2 MFtraceConfig_FILE=[%MFtraceConfig_FILE%] & call :CheckForDollar MFtraceConfig_FILE 
if EXIST "%MFtraceConfig_FILE%" (
  call :TEE1 Copying region CTF config file: "%MFtraceConfig_FILE%" 
  copy "%MFtraceConfig_FILE%" %SNAPDIR% >> %SNAPLOG%
  set getCTFlogs=1
  set MFTRACE_CONFIG=%MFtraceConfig_FILE%
  goto GetCTFlg
  ) else (
  call :TEE1 MFTRACE_CONFIG set in region but file doesn't exist [%MFtraceConfig_FILE%]
  )
REM Although the region config may not be valid, since MFTRACE_CONFIG was actually set that should override the OS env setting...
goto GetCTFlg

:ChkOSCTF
REM If not set in region, check/get from OS environment

Call :TEE2 Check for MFTRACE_CONFIG in OS environment
if "%MFTRACE_CONFIG%"=="" call :TEE2 MFTRACE_CONFIG not set in OS & goto GetCTFlg
if NOT "%MFTRACE_CONFIG%"==""  call :TEE2 MFTRACE_CONFIG=[%MFTRACE_CONFIG%]
if EXIST "%MFTRACE_CONFIG%" (
  call :TEE1 copying OS CTF config file: "%MFTRACE_CONFIG%" 
  copy "%MFTRACE_CONFIG%" %SNAPDIR% >> %SNAPLOG%
  set getCTFlogs=1
  ) else (
  call :TEE1 MFTRACE_CONFIG set in OS but file doesn't exist [%MFTRACE_CONFIG%]
  )

:GetCTFlg
if %getCTFlogs%==1 call :Get_MFtraceLogs "%MFTRACE_CONFIG%"

:skipRegCTF

ENDLOCAL
goto :eof
REM ============================================================================
REM End Get MFtraceConfig files
REM ============================================================================

REM ============================================================================
REM Get MFtraceLog files
REM ============================================================================
:Get_MFtraceLogs
SETLOCAL
Call :TEE2 *** Get_MFtraceLogs ***

Rem open config file and get location
call :TEE2 MFTRACE_CONFIG = %MFTRACE_CONFIG%

REM If textfile.location is specified this will be used (dest=textfile assumed)
REM if dest=binfile is set this will override the above
REM if dest=binfile AND textfile then both locations are used
REM if dest=binfile but binfile location isn't set, use textfile.location or MFTRACE_LOGS

call :GetVarFromFile MFTRACE_DEST mftrace.dest 12 "%MFTRACE_CONFIG%"
CALL :TEE2 MFTRACE_DEST=%MFTRACE_DEST%

REM Check if binfile is set:
echo.%MFTRACE_DEST% | findstr /i /C:"binfile" 1>nul
if errorlevel 1 (
  set BINDEST=0
) ELSE (
  set BINDEST=1
)

REM Check whether textfile is set:
echo.%MFTRACE_DEST% | findstr /i /C:"textfile" 1>nul
if errorlevel 1 (
  set TXTDEST=0
) ELSE (
  set TXTDEST=1
)

call :TEE2 BINDEST=%BINDEST%, TXTDEST=%TXTDEST%

set CTFDESTSET=0
REM Set flag if either dest is set:
if %BINDEST%==1 set CTFDESTSET=1
if %TXTDEST%==1 set CTFDESTSET=1

REM Use this flag to get files using MFTRACE_LOGS setting:
set getCTFfromMFTRACE_LOGS=0


call :GetVarFromFile MFTRACE_TXT_LCN mftrace.emitter.textfile#location 33 "%MFTRACE_CONFIG%"
call :TEE2 MFTRACE_TXT_LCN=[%MFTRACE_TXT_LCN%]

call :GetVarFromFile MFTRACE_BIN_LCN mftrace.emitter.binfile#location 32 "%MFTRACE_CONFIG%"
call :TEE2 MFTRACE_BIN_LCN=%MFTRACE_BIN_LCN%

REM Set flag if either location is set:
set CTFLOCSET=0
if NOT "%MFTRACE_TXT_LCN%1"=="1" set CTFLOCSET=1
if NOT "%MFTRACE_BIN_LCN%1"=="1" set CTFLOCSET=1

REM if location not set, use MFTRACE_LOGS
if %CTFLOCSET%==0 (
  set getCTFfromMFTRACE_LOGS=1 
  echo CTF location not set in cfg file - using MFTRACE_LOGS
)

Rem now check where we get the files from - if BINDEST and LOC set get file from here else from MFTRACE_LOGS:
If %BINDEST%==1 (
  if NOT "%MFTRACE_BIN_LCN%1"=="1" (
    mkdir %SNAPDIR%\CTFlogs-Binfile >> %SNAPLOG% 2>&1
    REM to ensure the directory can't be empty
    echo CTF Binary files > %SNAPDIR%\CTFlogs-Binfile\ctfbindir.txt
    call :TEE1 Copying CTF Bin files using CTF.cfg location: "%MFTRACE_BIN_LCN%"
    copy "%MFTRACE_BIN_LCN%\*.ctb" %SNAPDIR%\CTFlogs-Binfile > NUL 2>> %SNAPLOG%
    set CTFBINFILE=1
    if %TXTDEST%==0 goto endMFLgs
    ) else (
      set getCTFfromMFTRACE_LOGS=1
    )
)

REM IF textfile is set OR dest isn't set to anything THEN get text logs from textloc
REM i.e. IF textfile NOT set AND dest set to something THEN skip textdest
set skipTextDest=0
if not %TXTDEST%==1 if %CTFDESTSET%==1 set skipTextDest=1

REM Now get files from text location unless we're skipping
if %skipTextDest%==0 (
  if NOT "%MFTRACE_TXT_LCN%1"=="1" (
    mkdir %SNAPDIR%\CTFlogs-Textfile >> %SNAPLOG% 2>&1
    REM to ensure the directory can't be empty
    echo CTF text files > %SNAPDIR%\CTFlogs-Textfile\ctftxtdir.txt
    call :TEE1 Copying CTF text files using CTF.cfg location: "%MFTRACE_TXT_LCN%"
    copy "%MFTRACE_TXT_LCN%\*.log" %SNAPDIR%\CTFlogs-Textfile > NUL 2>> %SNAPLOG%
    set CTFTXTFILE=1
  )
)

REM if dest is set in ctf.cfg to either textfile or binfile or both then this over-rides MFTRACE_LOGS
REM if (%CTFTXTFILE%==1) OR (%CTFBINFILE%==1) goto endMFLgs
REM if not set get MFTRACE_LOGS from region/OS

REM Now check whether to get files from MFTRACE_LOGS or skip to end:
if %getCTFfromMFTRACE_LOGS%==0 (
  call :TEE2 Not using MFTRACE_LOGS for ctf log files
  goto endMFLgs
  )

:getCTFfromRegion
call :GetVarFromFile  MFtraceConfig_LOGS MFTRACE_LOGS 12 %MDUMP_ENV_FILE%
if "%MFtraceConfig_LOGS%"=="" call :TEE2 MFTRACE_LOGS not set in region & goto getCTFOS
REM Region env var is set
call :TEE2 MFtraceConfig_LOGS=[%MFtraceConfig_LOGS%] 
call :CheckForDollar MFtraceConfig_LOGS
if NOT "%MFtraceConfig_LOGS%1"=="1" (
  mkdir %SNAPDIR%\CTFlogsFromRegionEnv >> %SNAPLOG% 2>&1
  REM to ensure the directory can't be empty
  echo CTF Logs from Region Env > %SNAPDIR%\CTFlogsFromRegionEnv\ctflogs.txt
  call :TEE1 Copying CTF files using Region Env Var: "%MFtraceConfig_LOGS%" 
  copy "%MFtraceConfig_LOGS%\*" %SNAPDIR%\CTFlogsFromRegionEnv > NUL 2>> %SNAPLOG%
  goto endMFLgs
  )

REM get MFTRACE_LOGS from OS
:getCTFOS
REM Note that we won't get files from MFTRACE_LOGS in the OS env IF the logs location is set in the region or the CTF.cfg file
REM however it may be necessary to get files from the OS env location AS WELL AS region/CTF.cfg locations -
REM this would be for the casstart, casstop and cascd processes (as these are started outside of the region config)
if "%MFTRACE_LOGS%1"=="1" call :TEE2 MFTRACE_LOGS not set in OS environment & goto endMFLgs
if NOT "%MFTRACE_LOGS%1"=="1" (
  REM to ensure the directory can't be empty
  mkdir %SNAPDIR%\CTFlogsFromOSenv >> %SNAPLOG% 2>&1
  echo CTF text files from OS Env > %SNAPDIR%\CTFlogsFromOSenv\ctftxtdirOS.txt
  call :TEE1 Copying CTF files using OS environment: %MFTRACE_LOGS% 
  copy "%MFTRACE_LOGS%\*" %SNAPDIR%\CTFlogsFromOSenv > NUL 2>> %SNAPLOG%
  )

:endMFLgs
ENDLOCAL
goto :eof
REM ============================================================================
REM end Get MFtraceLog files
REM ============================================================================

REM ============================================================================
:GetVarFromFile
REM Finds the value from a name=value pair (nvp) in the file
REM Looks for arg 2 (len=arg3) in file (arg4)
REM if found, sets the env var (arg1) to the correct value
REM ============================================================================
call :TEE2 GetVarFromFile %1 %2 %3 %4
SETLOCAL
call set ENVNAME=%2
call set count=%3
call set file=%4


REM use findstr to find lines in the file which have this name
REM use only a valid/active entry (i.e found string is exactly the correct length)
REM Also need to check whether a space or an equals follows, otherwise could be start of another word...
REM Add 1 to count and check whether this is a space or an equals
setlocal ENABLEDELAYEDEXPANSION
set char_ok=0
set FOUND_ENV=0
for /f "Tokens=*" %%i in ('findstr /i %ENVNAME% %file%') do (
  set MF_ENV=%%i
REM  call :TEE2 MF_ENV=!MF_ENV!
  if /I "!MF_ENV:~0,%count%!" =="%ENVNAME%" (
REM    call :TEE2 Found valid beginning [%%i]
    set next_char=!MF_ENV:~%count%,1!
REM    call :TEE2 next_char is [!next_char!]
REM now check whether next char is an equals OR a space
    if "!next_char!" EQU "=" set char_ok=1
    if "!next_char!" EQU " " set char_ok=1
    if !char_ok! == 1 (
REM      call :TEE2 Env var found
      set ENV_SETTING=%%i
      set FOUND_ENV=1
      set char_ok=0
REM Actually we need to continue in this for look incase there is a another occurence of this var - which would take precedence...
REM   goto got_Env
    )    
  )
)  
if %FOUND_ENV% EQU 0 (
  call :TEE2 ENVNAME [%ENVNAME%] not found in file
  set ENV_SETTING=
)
:got_Env
call :TEE2 ENV_SETTING from file is [%ENV_SETTING%]
REM Need to switch DELAYEDEXPANSION off otherwise can't pass variable back 
REM Also need ENV_SETTING to continue to be set after the endlocal (which would otherwise trash all local variables!)
endlocal & set ENV_SETTING=%ENV_SETTING%
if "%ENV_SETTING%1"=="1" (
  call :TEE2 ENVNAME not set in %file%
	set ENVPATH=
	goto end_GVFF
	)

REM now get the bit after the = sign
REM What about spaces in pathnames?
FOR /f "tokens=1* delims==" %%a IN ("%ENV_SETTING%") DO (set ENVPATH=%%b)

call :TEE2 ENVPATH is [%ENVPATH%] 
REM Check for double-quotes - remove if found:
REM Don't use checkStr as that is only for PATHs
REM strip off the double quotes
for /f "useback tokens=*" %%a in ('%ENVPATH%') do set ENVPATH=%%~a
REM if NOT "%ENVPATH%"x == ""x call :CheckStr ENVPATH

call :TEE2 ENVPATH quotes removed [%ENVPATH%] 

REM Remove any leading spaces from ENVPATH
for /f "tokens=* delims= " %%a in ("%ENVPATH%") do set ENVPATH=%%a
call :TEE2  ENVPATH leading spaces removed [%ENVPATH%]   

:end_GVFF
( ENDLOCAL & REM RETURN VALUES
    IF "%~1" NEQ "" (SET %~1=%ENVPATH%)
    )
endlocal    
goto :eof
REM ============================================================================
REM End GetVarFromFile
REM ============================================================================

REM ============================================================================
:CheckForDollar
REM EG: call :CheckForDollar REGION_WORKAREA
REM Takes in path/string and checks if there is a $ anywhere in string - if not then return.
REM Note: if ES_SERVER is referenced in a string, we should substitute this directly for REGION (name) first.
REM Looks up actual path for this $ variable from the mdump o/p file
REM Substitutes the variable for the actual path
REM Recursively call this function to check for and expand any more $ strings
REM Pass fully-expanded path back (sets variable passed in to new string)
REM ============================================================================
SETLOCAL

call :TEE2 CheckForDollar

REM Expand the 1st param to enclose in %'s
call set DOLLARSTR=%%%~1%%
call :TEE2 DOLLARSTR=%DOLLARSTR%

REM Check if there is a $ anywhere in the passed in string:
echo.%DOLLARSTR% | findstr /C:"$" 1>nul
if errorlevel 1 (
  set DollarFound=0
) ELSE (
  set DollarFound=1
)
if %DollarFound%==0 (
	call :TEE2 No $ found in string %DOLLARSTR%
	set NEW_PATH=%DOLLARSTR%
	goto endChk4D
	)

::Check whether string already has a trailing slash
if "%DOLLARSTR:~-1%"=="\" (
  set TrailingNeeded=1
  ) else (
  set TrailingNeeded=0
)

::Add a trailing slash if there isn't one
IF NOT "%DOLLARSTR:~-1%"=="\" SET DOLLARSTR=%DOLLARSTR%\
REM call :TEE2 DOLLARSTR=%DOLLARSTR%

REM Check if 1st char is a $ 
if "%DOLLARSTR:~0,1%"=="$" ( set Dollar1=1 ) else (set Dollar1=0)

call :TEE2 $ found in string
REM split string at the 1st $ - keep 1st bit if not NULL and take the 2nd bit upto the next slash as env name and lookup 
REM If 1st char of initial string was a $, this will have been lost so add it back and reset now:
if %Dollar1%==1 (
  for /f "tokens=* delims=$" %%a in ("%DOLLARSTR%") do set str2=%%a& set str1=
  ) else (
  FOR /F "tokens=1* delims=$" %%i in ("%DOLLARSTR%") do set str1=%%i& set str2=%%j
)
call :TEE2 str1={%str1%}, str2={%str2%}
  
REM Only want the part upto the (first) slash (should be the name of the variable set) from str2
REM Should have a trailing slash even if its the last/only string (added on entry to this function)
FOR /f "tokens=1* delims=\" %%a IN ("%str2%") DO set ENVNAME=%%a& set TheRest=%%b

call :TEE2 ENVNAME=%ENVNAME%, TheRest=[%TheRest%]

REM use findstr from the MDUMP o/p to get the path that this string is set to

REM Get all parameters that are set to something (=) from MDUMP_FILE:
if NOT exist "%MDUMP_ENV_FILE%" findstr = %MDUMP_FILE% | findstr -v # > %MDUMP_ENV_FILE%
REM now find this var in that o/p and what its set to:
call :GetStrLen %ENVNAME% LEN
if "%ENVNAME%"=="ES_SERVER" (
  call :TEE2 resolving ES_SERVER
  set ENV_SETTING=%ES_SERVER%
  ) ELSE (
  call :GetVarFromFile ENV_SETTING %ENVNAME% %LEN% %MDUMP_ENV_FILE%
  )

setlocal ENABLEDELAYEDEXPANSION
REM GetVarFromFile can return empty string or the actual setting
REM check if empty and set to some value to prevent script errors!
REM actual file exists test will fail
:: ENV_SETTING will be null if don't find ENVNAME in mdump_env.out
:: Try to see if this resolves in the OS
:: indirection - need to read the contents of the variable name!
if "%ENV_SETTING%"=="" (
  if NOT "!%ENVNAME%!"=="" (
    CALL :TEE2 EVNNAME [%ENVNAME%] is set in OS to: "!%ENVNAME%!"
    set ENVPATH=!%ENVNAME%!
  ) else (
    CALL :TEE2 EVNNAME [%ENVNAME%] NOT set in OS
    set ENVPATH=NOT_RESOLVED
  )
) else (
  set ENVPATH=%ENV_SETTING%
)
endlocal & set ENVPATH=%ENVPATH%

REM call :TEE2 re-compose PATH string:
REM Remove any trailing slash:
IF "%ENVPATH:~-1%"=="\" SET ENVPATH=%ENVPATH:~0,-1%

REM Now set a (global?) variable name equal to the variable setting
REM set contents-of ENVNAME = contents-of ENV_SETTING
REM Could set this on exit of function...
REM now check if we got $ES_SERVER back, if so set this to actual region name
IF "%ENVPATH%"=="$ES_SERVER" (
	call :TEE2 ES_SERVER was used
	set ES_SERVER=%REGION%
	set ENVPATH=%REGION%
	REM Can't output actual ENVPATH in this IF loop without enabling delayedExpansion...
  call :TEE2 ENVPATH after ES_SERVER check=[%REGION%]
)

REM Remove any slash from str1
REM str1 might be a null - need to do this to allow DOS to parse it:
set str1=%str1%A
IF %str1:~-2%==\A (SET str1=%str1:~0,-2%) else (set str1=%str1:~0,-1%)

call :TEE2 str1(after)=[%str1%]
REM call :TEE2 re-compose string:
REM Check whether str1 was null:
IF %str1%A==A (
  set NEW_PATH=%ENVPATH%\%TheRest%
  ) else (
  set NEW_PATH=%str1%\%ENVPATH%\%TheRest%
  )

IF %NEW_PATH:~-1%==\ SET NEW_PATH=%NEW_PATH:~0,-1%
Call :TEE2 NEW_PATH=%NEW_PATH%

REM Now we should have a path with the initial $ variable expanded.
REM Now need to check whether there is another $ in the expanded path
call :CheckForDollar NEW_PATH

REM put trailing slash back if it was there originally!
if %TrailingNeeded%==1 set NEW_PATH=%NEW_PATH%\

:endChk4D
( ENDLOCAL & REM RETURN VALUES
    IF "%~1" NEQ "" (SET %~1=%NEW_PATH%)
    )

goto :eof
REM ============================================================================
REM End CheckForDollar
REM ============================================================================


REM ============================================================================
REM GetCasDump
REM ============================================================================
:GetCasDump 
call :TEE2 :GetCasDump
SETLOCAL ENABLEDELAYEDEXPANSION
set RUN_SCHTASKS=0
set CASDUMP_ERROR=0
set RUN_PSEXEC=0

rem Check if have access to psexec - do this outside the following IF block
set PSEXEC_FOUND=0
set PathToPSEXEC=
for %%e in (%PATHEXT%) do (
  for %%X in (psexec%%e) do (
    if not defined PathToPSEXEC (
      set PathToPSEXEC=%%~$PATH:X
    )
  )
)
call :TEE2  PathToPSEXEC=[%PathToPSEXEC%]

if "%PathToPSEXEC%"=="" (
  call :TEE2 can't run psexec.exe - not on path
  set PSEXEC_FOUND=0
) else (
  call :TEE2 psexec.exe found on path
  set PSEXEC_FOUND=1
)

REM First try as logged-on user
call :TEE2 casdump command: casdump /d /r%REGION%
REM Don't redirect output from casdump - it will think its in the backgroung so nothing is redirected
REM Any error message will be shown on the screen (stdout)
call :TEE1 Attempting casdump as logged-on user:
casdump /d /r%REGION%
set CASDUMP_ERROR=%ERRORLEVEL%
REM call :TEE2 CASDUMP_ERROR=%CASDUMP_ERROR%

REM Check here specifically for casdumpx.rec to see whether the requested dump was successful or not...
if NOT EXIST %SNAPDIR%\%REGION%\casdumpx.rec (
  call :TEE2 Couldn't create casdump as logged-on user [error:%CASDUMP_ERROR%]:
  whoami >> %SNAPLOG%
  call :TEE2 retry as Local SYSTEM
REM If we are unable to run psexec we will try task scheduler  
  set RUN_PSEXEC=1
)

REM Only need to do this if normal casdump wasn't successful
if %RUN_PSEXEC% == 1 (
  call :TEE2 do we have psexec?
    if %PSEXEC_FOUND% EQU 1 (
    call :TEE2 psexec -s "%PBINDIR%\casdump" /d /r%REGION%  
    call :TEE1 Attempting casdump using psexec as local system account
    psexec -s "%PBINDIR%\casdump" /d /r%REGION% >> %SNAPLOG% 2>&1
    if !ERRORLEVEL! NEQ 0 call :TEE2 couldn't create casdump with psexec as system& set RUN_SCHTASKS=1
  ) else (
    call :TEE2 no psexec available - try task scheduler
    set RUN_SCHTASKS=1
  )
) 
REM echo PBINDIR=%PBINDIR%

REM do this in stages/line-by-line - nested IF giving problems...
REM Create the task if we need to
call :TEE2 Use task scheduler to get dump as local system? [RUN_SCHTASKS=%RUN_SCHTASKS%]:
REM Need escaped double-quotes round PBINDIR as a single-quote ran into the error: Micro was unexpected at this time...
call :TEE2 SCHTASKS /Create /F /RU "NT AUTHORITY\SYSTEM" /SC ONSTART /TN MFCASDUMP /TR "%windir%\system32\CMD.EXE /C \"%PBINDIR%\casdump\" /d /r%REGION%"


if %RUN_SCHTASKS% == 1 call :TEE1 Attempting casdump using task scheduler as local system account
REM Need escaped double-quotes round PBINDIR as a single-quote ran into the error: Micro was unexpected at this time...
if %RUN_SCHTASKS% == 1     SCHTASKS /Create /F /RU "NT AUTHORITY\SYSTEM" /SC ONSTART /TN MFCASDUMP /TR "%windir%\system32\CMD.EXE /C \"%PBINDIR%\casdump\" /d /r%REGION%" >> %SNAPLOG% 2>&1

REM setup command for task scheduler
  if %WinVISTA%==1 (
    set SCHEDTASK_CMD=SCHTASKS /run  /I /TN MFcasdump
  ) else (
    call :TEE2 before Vista, try without /I (backward compatability)
    REM /I is Runs the task immediately for SCHTASKS /run
    set SCHEDTASK_CMD=SCHTASKS /run /TN MFcasdump
  )
  call :TEE2 SCHEDTASK_CMD=%SCHEDTASK_CMD%

REM now run the command if necessary
if %RUN_SCHTASKS% == 1 (
  call :TEE2 Running task scheduler command
  %SCHEDTASK_CMD% >> %SNAPLOG% 2>&1
  REM Now remove the command from Task scheduler
  SCHTASKS /delete /TN MFcasdump /f >> %SNAPLOG% 2>&1
  call :TEE2 Note if unable to create casdump, check what users the CAS and MFDS processes are running under in SystemInfo\tasklist1.out
)

ENDLOCAL
goto :eof
REM ============================================================================
REM END GetCasDump
REM ============================================================================

REM ============================================================================
REM Get EXTFH file
REM ============================================================================
:Get_EXTFH
SETLOCAL
call :TEE2 Get_EXTFH

REM see if set in region config
REM Relies on 'mdump' having been run already to generate the output file
REM (NO_MFDS=1 if MFDS not running)
REM if %NO_MFDS%==1 echo can't get region's EXTFH location - skipping...
if %NO_MFDS%==1 goto ChkOSXFH

REM See if EXTFH is set in the region's environment and if so return its value (in arg 1) - need name of variable and its length
Call :TEE2 check for EXTFH in region's environment
call :GetVarFromFile EXTFH_FILE EXTFH 5 %MDUMP_ENV_FILE%
if "%EXTFH_FILE%"=="" call :TEE2 EXTFH not set in region & goto ChkOSXFH
if NOT "%EXTFH_FILE%"==""  call :TEE2 EXTFH_FILE=[%EXTFH_FILE%] & call :CheckForDollar EXTFH_FILE 
if EXIST "%EXTFH_FILE%" (
  call :TEE1 Copying region EXTFH file: "%EXTFH_FILE%" 
  copy "%EXTFH_FILE%" %SNAPDIR% >> %SNAPLOG%
  ) else (
  call :TEE1 EXTFH set in region but file doesn't exist [%EXTFH_FILE%]
  )
REM Although the region config may not be valid, since EXTFH_CFG was actually set that should override the OS env setting...
goto skipOSXFHF

:ChkOSXFH
REM If not set in region, check/get from OS environment
Call :TEE2 Check for EXTFH in OS environment
if "%EXTFH%"=="" call :TEE2 EXTFH not set in OS & goto skipOSXFHF
if NOT "%EXTFH%"==""  call :TEE2 EXTFH=[%EXTFH%]
if EXIST "%EXTFH%" (
  call :TEE1 copying OS EXTFH config file: "%EXTFH%" 
  copy "%EXTFH%" %SNAPDIR% >> %SNAPLOG%
  ) else (
  call :TEE1 EXTFH set in OS but file doesn't exist [%EXTFH%]
  )

:skipOSXFHF

ENDLOCAL
goto :eof
REM ============================================================================
REM End Get EXTFH file
REM ============================================================================

REM ============================================================================
REM Get COBCONFIG_ file
REM ============================================================================
:Get_COBCONFIG_
SETLOCAL
call :TEE2 Get_COBCONFIG_

REM see if set in region config
REM Relies on 'mdump' having been run already to generate the output file
REM (NO_MFDS=1 if MFDS not running)
REM if %NO_MFDS%==1 echo can't get region's COBCONFIG_ location - skipping...
if %NO_MFDS%==1 goto ChkOSCOB

REM See if COBCONFIG_ is set in the region's environment and if so return its value (in arg 1) - need name of variable and its length
Call :TEE2 check for COBCONFIG_ in region's environment
call :GetVarFromFile COBCONFIG__FILE COBCONFIG_ 10 %MDUMP_ENV_FILE%
if "%COBCONFIG__FILE%"=="" call :TEE2 COBCONFIG_ not set in region & goto ChkOSCOB
if NOT "%COBCONFIG__FILE%"==""  call :TEE2 COBCONFIG__FILE=[%COBCONFIG__FILE%] & call :CheckForDollar COBCONFIG__FILE 
if EXIST "%COBCONFIG__FILE%" (
  call :TEE1 Copying region COBCONFIG_ file: "%COBCONFIG__FILE%" 
  copy "%COBCONFIG__FILE%" %SNAPDIR% >> %SNAPLOG%
  ) else (
  call :TEE1 COBCONFIG_ set in region but file doesn't exist [%COBCONFIG__FILE%]
  )
REM Although the region config may not be valid, since COBCONFIG__CFG was actually set that should override the OS env setting...
goto skipOSCOB

:ChkOSCOB
REM If not set in region, check/get from OS environment
Call :TEE2 Check for COBCONFIG_ in OS environment
if %COBCONFIG_%""=="" call :TEE2 COBCONFIG_ not set in OS & goto skipOSCOB
if NOT %COBCONFIG_%""==""  call :TEE2 COBCONFIG_=[%COBCONFIG_%]
if EXIST "%COBCONFIG_%" (
  call :TEE1 copying OS COBCONFIG_ config file: "%COBCONFIG_%" 
  copy "%COBCONFIG_%" %SNAPDIR% >> %SNAPLOG%
  ) else (
  call :TEE1 COBCONFIG_ set in OS but file doesn't exist [%COBCONFIG_%]
  )

:skipOSCOB

ENDLOCAL
goto :eof
REM ============================================================================
REM End Get COBCONFIG_ file
REM ============================================================================

REM ============================================================================
REM Get FHREDIR file
REM ============================================================================
:Get_FHREDIR
SETLOCAL
call :TEE2 Get_FHREDIR

REM see if set in region config
REM Relies on 'mdump' having been run already to generate the output file
REM (NO_MFDS=1 if MFDS not running)
REM if %NO_MFDS%==1 echo can't get region's FHREDIR location - skipping...
if %NO_MFDS%==1 goto ChkOSFHR

REM See if FHREDIR is set in the region's environment and if so return its value (in arg 1) - need name of variable and its length
Call :TEE2 check for FHREDIR in region's environment
call :GetVarFromFile FHREDIR_FILE FHREDIR 7 %MDUMP_ENV_FILE%
if "%FHREDIR_FILE%"=="" call :TEE2 FHREDIR not set in region & goto ChkOSFHR
if NOT "%FHREDIR_FILE%"==""  call :TEE2 FHREDIR_FILE=[%FHREDIR_FILE%] & call :CheckForDollar FHREDIR_FILE 
if EXIST "%FHREDIR_FILE%" (
  call :TEE1 Copying region FHREDIR file: "%FHREDIR_FILE%" 
  copy "%FHREDIR_FILE%" %SNAPDIR% >> %SNAPLOG%
  ) else (
  call :TEE1 FHREDIR set in region but file doesn't exist [%FHREDIR_FILE%]
  )
REM Although the region config may not be valid, since FHREDIR_CFG was actually set that should override the OS env setting...
goto skipOSFHR

:ChkOSFHR
REM If not set in region, check/get from OS environment
Call :TEE2 Check for FHREDIR in OS environment
if %FHREDIR%""=="" call :TEE2 FHREDIR not set in OS & goto skipOSFHR
if NOT %FHREDIR%""==""  call :TEE2 FHREDIR=[%FHREDIR%]
if EXIST "%FHREDIR%" (
  call :TEE1 copying OS FHREDIR config file: "%FHREDIR%" 
  copy "%FHREDIR%" %SNAPDIR% >> %SNAPLOG%
  ) else (
  call :TEE1 FHREDIR set in OS but file doesn't exist [%FHREDIR%]
  )

:skipOSFHR

ENDLOCAL
goto :eof
REM ============================================================================
REM End Get FHREDIR file
REM ============================================================================

REM ============================================================================
:ZIP_FILES
REM ============================================================================
CALL :TEE2 ZIP_FILES ZIP=[%ZIP%]
REM Note that once the ZIP has been created, any further updates to snapshot.log won't be collected

Call :TEE1 Zipping files...

REM Default this as though ZIP was unsuccessful
set ZIP_ERRORLEVEL=1

REM use .vbs if no command line ZIP utility set

if "%ZIP%"=="none" (
  call :TEE2 Zipping with .vbs script
  call :ZIP_IT
) ELSE (
REM Here we should have a ZIP command line program set
  call :TEE2 ZIP=%ZIP%
  if not exist %ZIP% (
    echo.
    call :TEE2 The specified zip utility was not found [%ZIP%] - using vbs script
    call :ZIP_IT
  ) else (
    call :TEE1 zipping snapshot contents to %SNAPDIR%.zip
    echo %ZIP% -p -r %SNAPDIR%.zip %SNAPDIR% >>%SNAPLOG%
    %ZIP% -p -r %SNAPDIR%.zip %SNAPDIR% 2>&1 >>%SNAPLOG%
    set ZIP_ERRORLEVEL=%ERRORLEVEL%
  )
)
REM OK to continue to update snapshot.log here if the zip wasn't successful!
echo.
if %ZIP_ERRORLEVEL% NEQ 0 call :TEE1 Unable to zip: "%SNAPDIR%" - please zip directory manually&echo.
REM Note we check ZIP_ERRORLEVEL before prompting to remove the snapshot directory

REM Check if this operation is being suppressed
if "%MFES_NOPROMPT%" EQU "1" (
  call :TEE2 Skipping Explorer Window due to MFES_NOPROMPT=%MFES_NOPROMPT%
) else (
  call :TEE2 open Explorer Window, MFES_NOPROMPT=%MFES_NOPROMPT%
  call :TEE1 Opening Explorer Window on snapshot directory
  start %SystemRoot%\explorer.exe %SNAPDIR%\..
)

echo.
echo *********************************************************
echo.
REM Now check ZIP_ERRORLEVEL and only remove files if this is 0
REM if exist "%SNAPDIR%.zip" 
if %ZIP_ERRORLEVEL% EQU 0 (
  echo Please provide the following file to Micro Focus support:
  echo.
  echo "%SNAPDIR%.zip" 
  echo.
  call :TEE2 setup to remove the SNAPDIR files as the zip was successful
  set REMOVE_SNAPDIR=1
 ) ELSE (
  call :TEE2 ZIP not successful, keeping SNAPDIR files
  set REMOVE_SNAPDIR=0
  Echo Please provide a zip archive of the following directory to Micro Focus support:
  echo.
  echo "%SNAPDIR%"
  echo.
)
echo Please include a problem summary which describes the manifestation 
echo of the issue and the steps leading up to the problem. 
echo.
echo *********************************************************
echo.
goto :eof

REM ============================================================================
REM End ZIP_Files
REM ============================================================================

REM ============================================================================
REM ZIP_IT
REM Creates a vbs script to zip the SNAPSHOT folder then runs it
REM ============================================================================
:ZIP_IT
call :TEE2 ZIP_IT

set ZIPITVBS=%SNAPDIR%\_zipIt.vbs

REM create temp .vbs script file
    echo Set objArgs = WScript.Arguments > %ZIPITVBS%
    echo InputFolder = objArgs(0) >> %ZIPITVBS%
    echo ZipFile = objArgs(1) >> %ZIPITVBS%
    echo CreateObject("Scripting.FileSystemObject").CreateTextFile(ZipFile, True).Write "PK" ^& Chr(5) ^& Chr(6) ^& String(18, vbNullChar) >> %ZIPITVBS%
    echo Set objShell = CreateObject("Shell.Application") >> %ZIPITVBS%
    echo Set source = objShell.NameSpace(InputFolder) >> %ZIPITVBS%
		echo set zip = objShell.NameSpace(ZipFile) >> %ZIPITVBS%
		echo zip.copyHere (source.Items) >> %ZIPITVBS%
		echo Do Until zip.Items.Count = source.Items.Count >> %ZIPITVBS%
		echo     WScript.Sleep 1000 >> %ZIPITVBS%
		echo Loop >> %ZIPITVBS%

REM Run vbs script

set cScript_ERRLEVEL=0
set cScript_RUNERRLVL=0
set cScript_TIMEOUT=0

call :TEE2 Checking for cscript
cscript /? >> "%SNAPLOG%" 2>&1
if %ERRORLEVEL% NEQ 0 set ZIP_ERRORLEVEL=%ERRORLEVEL%&goto SKIP_ZIP

echo CD=%CD% >> %SNAPLOG%
call :TEE2 About to zip up files in collection
call :TEE2 If successful, script will continue to tidy up and exit but no more will be written into the zipped snapshot.log
call :TEE2 CScript //T:60 %ZIPITVBS%  %SNAPDIR%  %SNAPDIR%.zip  

REM No point redirecting o/p from cscript to SNAPLOG as this has now been zipped up,
REM However redirect stderr to a separate file so we can check for any runtime errors.
REM Use script timeout to prevent script waiting indefinitely (in Items.Count loop):
REM The script may take a while to zip/compress the files and it will wait in a loop
REM   until all items have been copied. If there was a problem coping one of the items,
REM  (e.g. an empty folder) it would remain in this loop. The overall timeout on the
REM   cScript command itself will get out of this situation. If this happens the
REM   collection files WON'T be removed and so can be zipped separately.
CScript //T:60 %ZIPITVBS%  %SNAPDIR%  %SNAPDIR%.zip  > "%SNAPDIR%\..\MFESDIAGS-cScript-output.log" 2>&1
set cScript_ERRLEVEL=%ERRORLEVEL%

if %cScript_ERRLEVEL% EQU 0 (
rem Also check for VBScript runtime errors which CSCRIPT does not return
  for /f "delims=" %%x in ('findstr /C:"Microsoft VBScript runtime error:" "%SNAPDIR%\..\MFESDIAGS-cScript-output.log"') do @set  cScript_RUNERRLVL=1
)

if %cScript_ERRLEVEL% EQU 0 (
rem Also check for VBScript timeout 
for /f "delims=" %%x in ('findstr /C:"Script execution time was exceeded" "%SNAPDIR%\..\MFESDIAGS-cScript-output.log"') do @set  cScript_TIMEOUT=1
)

if  %cScript_ERRLEVEL% NEQ 0 (
  call :TEE1 error running cScript:%cScript_ERRLEVEL%
  set ZIP_ERRORLEVEL=1
  goto END_ZIP
)

if %cScript_RUNERRLVL% NEQ 0 (
  call :TEE1 cScript run-time error running cScript
  Call :TEE1 see: "%SNAPDIR%\..\MFESDIAGS-cScript-output.log"
  set ZIP_ERRORLEVEL=2
  goto END_ZIP
) 

if %cScript_TIMEOUT% NEQ 0 (
  call :TEE1 cScript Script execution time was exceeded
  Call :TEE1 see: "%SNAPDIR%\..\MFESDIAGS-cScript-output.log"
  call :TEE2: Removing any partial-zip file that was created
  del %SNAPDIR%.zip >> %SNAPLOG% 2>&1
  set ZIP_ERRORLEVEL=3
  goto END_ZIP
) 

if  %cScript_ERRLEVEL% EQU 0 (
  call :TEE2 cScript ran successfully
  set ZIP_ERRORLEVEL=0
)

goto END_ZIP

:SKIP_ZIP    
REM Remove temp vbs file
REM REM del %ZIPITVBS%
call :TEE2 unable to run cScript command ZIP_ERRORLEVEL=%ZIP_ERRORLEVEL%

:END_ZIP

goto :eof
REM ============================================================================
REM End ZIP_IT
REM ============================================================================

    
REM ============================================================================
REM GetStrLen
REM %1 is string to check
REM length is returned in %2
REM ============================================================================
:GetStrLen
SETLOCAL
REM call :TEE2 GetStrLen %1 %2
set #=%1
set length=0
REM Take the last char off the var each time and count the number of times until no more chars
:loop
if defined # (set #=%#:~1%&set /A length += 1&goto loop)
REM call :TEE2 %1 is %length% characters long

( ENDLOCAL & REM RETURN VALUES
    IF "%~2" NEQ "" (SET %~2=%length%)
    )
    
goto :eof
REM ============================================================================
REM End GetStrLen
REM ============================================================================


REM ============================================================================
REM CheckPath
REM %1 is name of var containing string to check - this should only be a PATH
REM post-process string incase it contains a terminating slash or a long/spacey path...
REM No longer removing quotes 
REM Pass back checked/converted string in same var name that was passed in.
REM ============================================================================
:CheckPath

SETLOCAL
call :TEE2 CheckPath %1
REM Expand the 1st param to enclose in %'s
call set CHKSTR=%%%~1%%
call :TEE2 CHKSTR=%CHKSTR%
call set CHKSTR=%CHKSTR%

::Does string have a trailing slash? if so remove it 
IF %CHKSTR:~-1%==\ SET CHKSTR=%CHKSTR:~0,-1%

REM Now convert to short path
call :TEE2 Convert to short path: %CHKSTR%

REM This removes the double quotes as well so add them back...

for %%I in ("%CHKSTR%") do set SHRT_STR="%%~sI"
REM TESTING
REM set SHRT_STR=%CHKSTR%

REM echo SHRT_STR is %SHRT_STR%
REM echo 1st Param is %~1
ENDLOCAL & SET %~1=%SHRT_STR%

goto :eof
REM ============================================================================
REM End CheckPath
REM ============================================================================

REM ============================================================================
:ProcessFile
REM Call this function with an input and an output file which joins up any
REM  directory paths that are split across 2 lines.
REM Then it is possible to find the path for the Journal file for example.
REM Function is implemented as a loop. Loop exit is in 2 places: 
REM when no line is read from input file OR if there is no nextline to read.
REM Created ProcFile_loop label so that we can setlocal outside the loop.
REM
REM ============================================================================
call :TEE2 Processfile
setlocal EnableDelayedExpansion
REM endlocal is on exit - when eof is reached.

:ProcFile_loop
REM Need to have line unset so we can check when we've reached EOF
  set line=

REM Don't read next line if we've already got it from last time round
if %skipnextRead%==0 (
  REM read next/first line of input 
  set /P line=
) else (
  REM Set current line to the previous nextline
  set "line=!nextLine!
)
REM check if we've reached EOF
if not defined line (
  call :TEE2 no line to read - exit Processfile
  endlocal 
  exit /B
)  
REM @echo line=%line%
REM Now read the following line
   set nextLine=
   set /P nextLine=
REM check if we've reached EOF
   if not defined nextLine (
     REM if the following line is EOF then simply output the current line and exit
     echo !line!
     call :TEE2 no nextline to read - exit Processfile
     endlocal 
     exit /B
   )
REM  echo nextline=!nextLine!
   REM Check whether nextline continues this line, i.e. starts with a space...
   REM echo nextLine:~0,1= ["!nextLine:~0,1!"]
   if "!nextLine:~0,1!"==" " (
     for /f "tokens=* delims= " %%a in ("!nextLine!") do set nextLine=%%a
     REM echo nextLine=!nextLine!
     REM Concatenate these lines, leave 1 space between 
     set "line=!line! !nextLine!"
     REM We want to continue reading lines
     set skipnextRead=0
   ) else (
     REM output this line as no change needed
     REM echo !line!
     REM Set currentline to nextline and recheck
     REM set "line=!nextLine!
     REM We don't want to read another line yet as we already have one to process since it wasn't a continuation line...
     set skipnextRead=1
   )
REM write line to output file
echo !line!
goto ProcFile_loop

REM ============================================================================
REM End ProcessFile
REM ============================================================================
        
REM ============================================================================
:TEE1
REM Outputs any passed in strings to console and log - use for normal o/p
REM Call this function as per the following example:
REM call :TEE1 %DATE%,%TIME%,<STRING>
REM ============================================================================
for /f "tokens=*" %%Z in ("%*") do (
     >  CON ECHO.%%Z
     >> "%SNAPLOG%" ECHO.%%Z
     goto :EOF
)
REM ============================================================================
REM End :TEE1
REM ============================================================================

REM ============================================================================
:TEE2
REM Outputs any passed in strings to log - use for debug log
REM Take out the 'REM' to see debug lines on the console
REM CAll this function as per the following example:
REM call :TEE %DATE%,%TIME%,<STRING>
REM ============================================================================
for /f "tokens=*" %%Z in ("%*") do (
REM    >  CON ECHO.%%Z
     >> "%SNAPLOG%" ECHO.%%Z
     goto :EOF
)
REM ============================================================================
REM End :TEE2
REM ============================================================================


:stop
REM Already ZIPed files so not much point writing to the snapshot.log as we're about to remove it!
REM Although OK to if we are testing with snapshot.log in a different location
call :TEE1 End of diagnostic collection at: %TIME%
REM echo REMOVE_SNAPDIR=%REMOVE_SNAPDIR%

REM TEST
if "%TESTING%" GEQ "3" (
  echo TESTING Not removing snapdir
  set REMOVE_SNAPDIR=0
)
REM Can't do this in the above if loop as that is where the env var is being set
if "%TESTING%" GEQ "3" echo REMOVE_SNAPDIR=%REMOVE_SNAPDIR%, MFES_NOPROMPT=[%MFES_NOPROMPT%]

REM Doing this in stages so we could output to the log file BEFORE it gets removed
if "%MFES_NOPROMPT%" EQU "1" (
  call :TEE2 Running in non-interactive mode - tidy up and exit both script and cmd.exe
) else (
  call :TEE2 Running in interactive mode - tidy up and exiting
  REM Unset any env vars that remain
  set DFHDRDAT_LOC=
  set ES_SERVER=
  SET MDUMP_ENV_FILE=
  SET MDUMP_FILE=
  SET MDUMP_SECY_FILE=
  set REGION=
  set REGION_WORKAREA=
  set SERVER_STATUS=
)

call :TEE2 About to exit, remove snapshot files if ZIP OK: REMOVE_SNAPDIR=%REMOVE_SNAPDIR%, MFES_NOPROMPT=[%MFES_NOPROMPT%]

REM Blank line
@echo.

if "%REMOVE_SNAPDIR%"=="1" (
  call :TEE1 ZIP file created OK, will now remove temporary files and exit script:
REM  call :TEE1 ["%SNAPDIR%"]
  REM Pause if we are interactive:
  if "%MFES_NOPROMPT%" NEQ "1"  echo [or press Ctrl-C to terminate and keep files]
  if "%MFES_NOPROMPT%" NEQ "1"  PAUSE
  rmdir /q /s "%SNAPDIR%"
) else (
REM not removing snapshot dir
  call :TEE2 ZIP wasn't successful, not removing SNAPDIR files: "%SNAPDIR%"
)

REM DON'T CALL TEE1 or TEE2 FROM NOW ON - directory should have been removed

REM TESTING
REM PAUSE

if "%MFES_NOPROMPT%" EQU "1" (
  echo exiting script and cmd.exe

REM TEST
if "%TESTING%" GEQ "1" PAUSE  

  exit
) else (
  endlocal
REM Pause here if we didn't above
  if "%REMOVE_SNAPDIR%" NEQ "1" PAUSE
  REM Exit script but not CMD.exe
  echo exiting script 
  exit /B
)

