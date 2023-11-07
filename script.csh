#!/bin/csh 
alias source 'source `source.path \!\!:1`'

#####################################################################
#
#        Job Script:     SYSJDLTR_WISFTP
#
#        Description:    This job copies the letters from the ftp      
#                        directory to the report routing directory.
#
#####################################################################
# Change log: 
#
# Ref#      Change Date  Name             Description
# ----      -----------  ---------------  ---------------------------
#
# Implement 08/21/2023   o. maycotte      Wisconsin Implementation
#####################################################################

source  $SRCDIR/job_begin.src

if ($restart_step != "") then
   goto $restart_step
endif
  
echo "Environment is:  ${SYSSTAT}"
if ( $SYSSTAT == 'prod' ) then
    set ftp_account="etkadmin"
    set ftp_remotedir="/export/ftp/ETK0010P/incoming"
else if ( $SYSSTAT == 'mod' ) then
    set ftp_account="etkadmin"
    set ftp_remotedir="/export/ftp/ETK0010P/incoming"
else
    echo "Unsupported run environment: $SYSSTAT"
    echo "No job steps executed."
    exit (-1)
endif

setenv target_dir "$TEMPDA/ETK0010P"

setenv FTP_ETK_ACCOUNT "$ftp_account"

# make sure the target directory exists
if ( ! -d ${target_dir} ) then
    mkdir -p ${target_dir}
endif


#####################################################################
#
#        js10 - Copy the Letters               
#
#####################################################################
js10:
setenv JS         "js10"
jsbeg_msg.csh

#####################################################################
#
#        Input files: 
#
#####################################################################

#####################################################################
#
#        Output files: 
#
#####################################################################
        # FTP commands to list the file(s). 
setenv dd_FTPSYSINF "$TEMPDA/ETK0010P_$$.dat"

############################################################
# Apply Overrides
############################################################

source $SRCDIR/override.src

#############################################################
# Create FTP commands to list the input file
#############################################################

echo "ls -1 $ftp_remotedir/*.pdf"        > $dd_FTPSYSINF
echo "quit"                             >> $dd_FTPSYSINF

# if file not found then SFTP throws a "Can't ls" message
execpgm.csh 'CallSFTP.ksh dot30 $dd_FTPSYSINF $FTP_ETK_ACCOUNT' | tee "$LOGSDIR/etk_ftp_list.log"
# 
setenv NOTFOUND "`cat $LOGSDIR/etk_ftp_list.log | grep 't ls:' | wc -l`"
#
if ("$NOTFOUND" == "1") then
    echo "#############################################################"
    echo "#"
    echo "# No files found..."
    echo "#"
    echo "#############################################################"
    exit (0)
#
# Check for processing errors other than "Can't ls".
# it will stop here if any errors
else if ($status != 0) then
   echo $JS":Error occurred in FTP process (CallSFTP) to list the input files"
   abend_msg.csh
   exit (-1)
endif

# remove temp file 
rm -f $dd_FTPSYSINF

setenv REMOTEFILES "/tmp/remote_pdf_files.sftp"

# get the actual list of remote files if any
cat "$LOGSDIR/etk_ftp_list.log" | grep ".pdf" | sed 1d > $REMOTEFILES
#############################################################
# Verify whether the input file exists.
# this is a WEAK verification
#############################################################
# this line here needs a fix, should be minus 1
setenv filecount `cat $REMOTEFILES | grep '.pdf' | wc -l`

echo "Filecount is: $filecount"

# it will stop here if filecount == 0
if ($filecount > 0) then
        echo "${filecount} file(s) found in dot30 server under folder: ${ftp_remotedir}"

else if ($filecount == 0) then
        echo "NO files found in dot30 server under folder: ${ftp_remotedir}"
        exit (0)
        
else
        echo "##############################################################################"
        echo "STOP!!!"
        echo "Something bad really happened here..."
        echo"##############################################################################"
        exit(-1)
endif


##############################################################################
##############################################################################
#
# js020 - Create and execute a file of FTP commands to get the remote file.
#
##############################################################################
##############################################################################
js020:
setenv JS "js020"
jsbeg_msg.csh

##############################################################
# Input Files
##############################################################
        # None 
##############################################################
# Output Files
##############################################################

        # FTP commands to get a file. 
setenv dd_FTPSYSGET "$TEMPDA/ETK0010P_$$.dat"
setenv dd_TARGETPATH "${target_dir}"

############################################################
# Apply Overrides
############################################################

source $SRCDIR/override.src

##############################################################################
# Create file of SFTP commands to retrieve the input file(s)
##############################################################################
# position ourselves in the target folder
cd ${dd_TARGETPATH}

rm -f $dd_FTPSYSGET
#this is sort of redundant, it does not hurt
touch $dd_FTPSYSGET
# step through the list of remote files and creates the FTP cards
foreach line ( "`cat $REMOTEFILES`" )
    echo "get " \"$line\"                          >> $dd_FTPSYSGET
end
echo "quit"                                       >> $dd_FTPSYSGET

execpgm.csh 'CallSFTP.ksh dot30 $dd_FTPSYSGET $FTP_ETK_ACCOUNT'  | tee "$LOGSDIR/etk_ftp_list.log"

# Check for processing errors
if ($status != 0) then
   echo "Error occurred in FTP process (CallSFTP) to retrieve the input file.";
   abend_msg.csh
   exit (-1)
endif

echo "Removing $dd_FTPSYSGET"
rm -f $dd_FTPSYSGET


#####################################################################
#
#        Apply any global or local variable overrides
#
#####################################################################
###############################################################################
# js030 - Move letters to target folder.
#
##############################################################################
##############################################################################
js030:
setenv JS "js30"
jsbeg_msg.csh

source $SRCDIR/override.src

#####################################################################
#
#        Execute program
#
#####################################################################
# copy files from local temp folder to routing folder
execpgm.csh 'sydltr_copy_wisftp.ksh'

if ($status != 0) then
    exit (-1)
endif

##############################################################################
##############################################################################
#
# js040 - Create and execute a file of FTP commands to remove the remote file.
#
##############################################################################
##############################################################################
js040:
setenv JS "js40"
jsbeg_msg.csh

##############################################################
# Input Files
##############################################################
        # None 
##############################################################
# Output Files
##############################################################
        # FTP commands to remove a file. 
setenv dd_FTPSYSDEL "$TEMPDA/etk_ftp_del_$$.dat"

############################################################
# Apply Overrides
############################################################

source $SRCDIR/override.src

##############################################################################
# Create file of SFTP commands to retrieve the input file
##############################################################################

#Removing files from remote site
rm -f $dd_FTPSYSDEL
#this is sort of redundant
touch $dd_FTPSYSDEL
# step through the list of remote files 
foreach line ( "`cat $REMOTEFILES`" )
    echo "rm " \"$line\"                          >> $dd_FTPSYSDEL
end
echo "quit"                                       >> $dd_FTPSYSDEL

execpgm.csh 'CallSFTP.ksh dot30 $dd_FTPSYSDEL $FTP_ETK_ACCOUNT' | tee "$LOGSDIR/etk_ftp_list.log"

# Check for processing errors
if ($status != 0) then
   echo "Error occurred in FTP process (CallSFTP) to delete the input file";
   abend_msg.csh
   exit (-1)
endif

rm -f $dd_FTPSYSDEL
rm -f $REMOTEFILES

#####################################################################
#
#####################################################################
#
#        END of JOB
#
#####################################################################
js050:
setenv JS "js50"
eoj_msg.csh $0
