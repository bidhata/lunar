#!/bin/sh

# Name:         lunar (Lockdown UNIX Analyse Report)
# Version:      2.1.9
# Release:      1
# License:      Open Source
# Group:        System
# Source:       N/A
# URL:          http://lateralblast.com.au/
# Distribution: Solaris, Red Hat Linux, SuSE Linux, Debian Linux, 
#               Ubuntu Linux, Mac OS X
# Vendor:       UNIX
# Packager:     Richard Spindler <richard@lateralblast.com.au>
# Description:  Audit script based on various benchmarks
#               Addition improvements added
#               Writen in bourne shell so it can be run on different releases

# No warrantry is implied or given with this script
# It is based on numerous security guidelines
# As with any system changes, the script should be vetted and
# changed to suit the environment in which it is being used

# Unless your organization is specifically using the service, disable it. 
# The best defense against a service being exploited is to disable it.

# Even if a service is set to off the script will audit the configuration
# file so that if a service is re-enabled the configuration is secure
# Where possible checks are made to make sure the package is installed
# if the package is not installed the checks will not be run

# To do:
#
# - nosuid,noexec for Linux
# - Disable user mounted removable filesystems for Linux
# - Disable USB devices for Linux
# - Grub password
# - Restrict NFS client requests to privileged ports Linux

# Solaris Release Information
#  1/06 U1
#  6/06 U2
# 11/06 U3
#  8/07 U4
#  5/08 U5
# 10/08 U6
#  5/09 U7
# 10/09 U8
#  9/10 U9
#  8/11 U10
#  1/13 U11

# audit_mode = 1 : Audit Mode
# audit_mode = 0 : Lockdown Mode
# audit_mode = 2 : Restore Mode

# Set up some global variables

args=$@
score=0
pkg_company="LTRL"
pkg_suffix="lunar"
base_dir="/opt/$pkg_company$pkg_suffix"
date_suffix=`date +%d_%m_%Y_%H_%M_%S`
work_dir="$base_dir/$date_suffix"
temp_dir="$base_dir/tmp"
temp_file="$temp_dir/temp_file"
wheel_group="wheel"
reboot=0
total=0
verbose=0
modules_dir="modules"
private_dir="private"

# This is the company name that will go into the securit message
# Change it as required

company_name="Lateral Blast Pty Ltd"

# print_usage
#
# If given a -h or no valid switch print usage information

print_usage () {
  echo ""
  echo "Usage: $0 [-a|c|l|h|V] [-u]"
  echo ""
  echo "-a: Run in audit mode (no changes made to system)"
  echo "-A: Run in audit mode (no changes made to system)"
  echo "    [includes filesystem checks which take some time]"
  echo "-s: Run in selective mode (only run tests you want to)"
  echo "-S: List functions available to selective mode"
  echo "-l: Run in lockdown mode (changes made to system)"
  echo "-L: Run in lockdown mode (changes made to system)"
  echo "    [includes filesystem checks which take some time]"
  echo "-d: Show changes previously made to system"
  echo "-p: Show previously versions of file"
  echo "-u: Undo lockdown (changes made to system)"
  echo "-h: Display usage"
  echo "-V: Display version"
  echo "-v: Verbose mode [used with -a and -A]"
  echo "    [Provides more information about the audit taking place]"
  echo ""
  echo "Examples:"
  echo ""
  echo "Run in Audit Mode"
  echo ""
  echo "$0 -a"
  echo ""
  echo "Run in Audit Mode and provide more information"
  echo ""
  echo "$0 -a -v"
  echo ""
  echo "Display previous backups:"
  echo ""
  echo "$0 -b"
  echo "Previous backups:"
  echo "21_12_2012_19_45_05  21_12_2012_20_35_54  21_12_2012_21_57_25"
  echo ""
  echo "Restore from previous backup:"
  echo ""
  echo "$0 -u 21_12_2012_19_45_05"
  echo ""
  echo "List tests:"
  echo ""
  echo "$0 -S"
  echo ""
  echo "Only run shell based tests:"
  echo ""
  echo "$0 -s audit_shell_services"
  echo ""
  exit
}

# funct_print_audit_info
#
# This function searches the script for the information associated
# with a function.
# It finds the line starting with # function_name
# then reads until it finds a #.
#.

funct_print_audit_info () {
  if [ "$verbose" = 1 ]; then
    function=$1
    comment_text=0
    while read line
    do
      if [ "$line" = "# $function" ]; then
        comment_text=1
      else
        if [ "$comment_text" = 1 ]; then
          if [ "$line" = "#." ]; then
            echo ""
            comment_text=0
          fi
          if [ "$comment_text" = 1 ]; then
            if [ "$line" = "#" ]; then
              echo ""
            else
              echo "$line"
            fi
          fi
        fi
      fi
    done < $0
  fi
}

# funct_verbose_message
#
# Print a message if verbose mode enabled
#.

funct_verbose_message () {
  if [ "$verbose" = 1 ]; then
    audit_text=$1
    audit_style=$2
    if [ "$audit_style" = "fix" ]; then
      if [ "$audit_text" = "" ]; then
        echo ""
      else
        echo "# Fix:     # $audit_text"
      fi
    else
      echo ""
      echo "# $audit_text"
      echo ""
    fi
  fi
}

# check_os_release
#
# Get OS release information
#.

check_os_release () {
  echo ""
  echo "# SYSTEM INFORMATION:"
  echo ""
  os_name=`uname`
  if [ "$os_name" = "Darwin" ]; then
    `set -- $(sw_vers | awk 'BEGIN { FS="[:\t.]"; } /^ProductVersion/ && $0 != "" {print $3, $4, $5}')`
    os_version=$1.$2
    os_update=$3
    os_vendor="Apple"
  fi
  if [ "$os_name" = "Linux" ]; then
    if [ -f "/etc/redhat-release" ]; then
      os_version=`cat /etc/redhat-release | awk '{print $3}' |cut -f1 -d'.'`
      os_update=`cat /etc/redhat-release | awk '{print $3}' |cut -f2 -d'.'`
      os_vendor=`cat /etc/redhat-release | awk '{print $1}'`
      linux_dist="redhat"  
    else 
      if [ -f "/etc/debian_version" ]; then
        os_version=`lsb_release -r |awk '{print $2}' |cut -f1 -d'.'`
        os_update=`lsb_release -r |awk '{print $2}' |cut -f2 -d'.'`
        os_vendor=`lsb_release -i |awk '{print $3}'`
        linux_dist="debian"  
        if [ ! -f "/usr/sbin/sysv-rc-conf" ]; then
          echo "Notice:    The sysv-rc-conf package is required by this script"
          echo "Notice:    Attempting to install"
          apt-get install sysv-rc-conf
        fi
        if [ ! -f "/usr/bin/bc" ]; then
          echo "Notice:    The bc package is required by this script"
          echo "Notice:    Attempting to install"
          apt-get install bc 
        fi
      else
        if [ -f "/etc/SuSE-release" ]; then
          os_version=`cat /etc/SuSe-release |grep '^VERSION' |awk '{print $3}' |cut -f1 -d "."`
          os_update=`cat /etc/SuSe-release |grep '^VERSION' |awk '{print $3}' |cut -f2 -d "."`
          os_vendor="SuSE"
          linux_dist="suse"
        fi
      fi
    fi
  fi
  if [ "$os_name" = "SunOS" ]; then
    os_vendor="Oracle Solaris"
    os_version=`uname -r |cut -f2 -d"."`
    if [ "$os_version" = "11" ]; then
      os_update=`cat /etc/release |grep Solaris |awk '{print $3}' |cut -f2 -d'.'`
    fi
    if [ "$os_version" = "10" ]; then
      os_update=`cat /etc/release |grep Solaris |awk '{print $5}' |cut -f2 -d'_' |sed 's/[A-z]//g'`
    fi
    if [ "$os_version" = "9" ]; then
      os_update=`cat /etc/release |grep Solaris |awk '{print $4}' |cut -f2 -d'_' |sed 's/[A-z]//g'`
    fi
  fi
  if [ "$os_name" != "Linux" ] && [ "$os_name" != "SunOS" ] && [ "$os_name" != "Darwin" ]; then
    echo "OS not supported"
    exit
  fi
  os_platform=`uname -p`
  echo "Platform:  $os_vendor $os_name $os_version Update $os_update on $os_platform"
}

# funct_deb_check
#
# Check if a deb is installed, if so rpm_check will be be set with name of dep,
# otherwise it will be empty
#.

funct_deb_check () {
  package_name=$1
  rpm_check=`dpkg -l $package_name 2>&1 |grep $package_name |awk '{print $2}' |grep "^$package_name$"`
}

# funct_rpm_check
#
# Check if an rpm is installed, if so rpm_check will be be set with name of rpm,
# otherwise it will be empty
#.

funct_rpm_check () {
  if [ $os_name = "Linux" ]; then
    package_name=$1
    if [ "$linux_dist" = "debian" ]; then
      funct_deb_check $package_name
    else
      rpm_check=`rpm -qi $package_name |grep $package_name |grep Name |awk '{print $3}'`
    fi
  fi
}

# check_environment
#
# Do some environment checks
# Create base and temporary directory
#.

check_environment () {
  check_os_release
  if [ "$os_name" = "SunOS" ]; then
    id_check=`id |cut -c5`
  else
    id_check=`id -u`
  fi
  if [ "$id_check" != "0" ]; then
    if [ "$os_name" != "Darwin" ]; then
      echo ""
      echo "Stopping: $0 needs to be run as root"
      echo ""
      exit
    else
      base_dir="$HOME/.$pkg_suffix"
      temp_dir="/tmp"
      work_dir="$base_dir/$date_suffix"
    fi
  fi
  # Load modules for modules directory
  if [ -d "$module_dir" ]; then
    for file_name in `ls $module_dir/*.sh`; do
      if [ "$os_name" = "SunOS" ]; then
        . $file_name
      else
        source $file_name
      fi
    done
  fi
  # Private modules for customers
  if [ -d "$private_dir" ]; then
    for file_name in `ls $private_dir/*.sh`; do
      if [ "$os_name" = "SunOS" ]; then
        . $file_name
      else
        source $file_name
      fi
    done
  fi
  if [ ! -d "$base_dir" ]; then
    mkdir -p $base_dir
    chmod 700 $base_dir
    if [ "$os_name" != "Darwin" ]; then
      chown root:root $base_dir
    fi
  fi
  if [ ! -d "$temp_dir" ]; then
    mkdir -p $temp_dir
  fi
  if [ "$audit_mode" = 0 ]; then
    if [ ! -d "$work_dir" ]; then
      mkdir -p $work_dir
    fi
  fi
}

# print_previous
#
# Print previous changes
#.

print_previous () {
  if [ -d "$base_dir" ]; then
    find $base_dir -type f -print -exec cat -n {} \;
  fi
}

# print_changes
#
# Do a diff between previous file (saved) and existing file
#.

print_changes () {
  for saved_file in `find $base_dir -type f -print`; do
    check_file=`echo $saved_file |cut -f 5- -d"/"`
    top_dir=`echo $saved_file |cut -f 1-4 -d"/"`
    echo "Directory: $top_dir"
    log_test=`echo "$check_file" |grep "log$"`
    if [ `expr "$log_test" : "[A-z]"` = 1 ]; then
      echo "Original system parameters:"
      cat $saved_file |sed "s/,/ /g"
    else
      echo "Changes to /$check_file:"
      diff $saved_file /$check_file
    fi
  done
}

# funct_command_value
#
# Audit command output values
#
# Depending on the command_name send an appropriate check_command and set_command are set
# If the current_value is not the correct_value then it is fixed if run in lockdown mode
# A copy of the value is stored in a log file, which can be restored
#.

funct_command_value () {
  command_name=$1
  parameter_name=$2
  correct_value=$3
  service_name=$4
  total=`expr $total + 1`
  if [ "$audit_mode" = 2 ]; then
    restore_file="$restore_dir/$command_name.log"
    if [ -f "$restore_file" ]; then
      parameter_name=`cat $restore_file |grep '$parameter_name' |cut -f1 -d','`
      correct_value=`cat $restore_file |grep '$parameter_name' |cut -f2 -d','`
      if [ `expr "$parameter_name" : "[A-z]"` = 1 ]; then
        echo "Returning $parameter_name to $correct_value"
        if [ "$command_name" = "routeadm" ]; then
          if [ "$correct_value" = "disabled" ]; then
            set_command="routeadm -d"
          else
            set_command="routeadm -e"
          fi
          $set_command $parameter_name
        else
          $set_command $parameter_name $correct_value
          if [ `expr "$parameter_name" : "tcp_trace"` = 9 ]; then
            svcadm refresh svc:/network/inetd
          fi
        fi
      fi
    fi
  else
    if [ "$parameter_name" = "tcp_wrappers" ]; then
      echo "Checking:  Service $service_name has \"$parameter_name\" set to \"$correct_value\""
    else
      echo "Checking:  Output of $command_name \"$parameter_name\" is \"$correct_value\""
    fi
  fi
  if [ "$command_name" = "inetadm" ]; then
    check_command="inetadm -l $service_name"
    set_command="inetadm -M"
    current_value=`$check_command |grep "$parameter_name" |awk '{print $2}' |cut -f2 -d'='`
  fi
  if [ "$command_name" = "routeadm" ]; then
    check_command="routeadm -p $parameter_name"
    current_value=`$check_command |awk '{print $3}' |cut -f2 -d'='`
  fi
  log_file="$work_dir/$command_name.log"
  if [ "$current_value" != "$correct_value" ]; then
    if [ "$audit_mode" = 1 ]; then
      score=`expr $score - 1`
      echo "Warning:   Parameter \"$parameter_name\" not set to \"$correct_value\" [$score]"
      if [ "$command_name" = "routeadm" ]; then
        if [ "$correct_value" = "disabled" ]; then
          set_command="routeadm -d"
        else
          set_command="routeadm -e"
        fi
        funct_verbose_message "" fix
        funct_verbose_message "$set_command $parameter_name" fix
        funct_verbose_message "" fix
      else
        funct_verbose_message "" fix
        funct_verbose_message "$set_command $parameter_name=$correct_value" fix
        funct_verbose_message "" fix
      fi
    else
      if [ "$audit_mode" = 0 ]; then
        echo "Setting:   $parameter_name to $correct_value"
        echo "$parameter_name,$current_value" >> $log_file
        if [ "$command_name" = "routeadm" ]; then
          if [ "$correct_value" = "disabled" ]; then
            set_command="routeadm -d"
          else
            set_command="routeadm -e"
          fi
          $set_command $parameter_name
        else
          $set_command $parameter_name=$correct_value
        fi
      fi
    fi
  else
    if [ "$audit_mode" != 2 ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score + 1`
        if [ "$parameter_name" = "tcp_wrappers" ]; then
          echo "Secure:    Service $service_name already has \"$parameter_name\" set to \"$correct_value\""
        else
          echo "Secure:    Output for command $command_name \"$parameter_name\" already set to \"$correct_value\" [$score]"
        fi
      fi
    fi
  fi
}

# funct_backup_file
#
# Backup file
#.

funct_backup_file () {
  check_file=$1
  backup_file="$work_dir$check_file"
  if [ ! -f "$backup_file" ]; then
    echo "Saving:    File $check_file to $backup_file"
    find $check_file | cpio -pdm $work_dir 2> /dev/null
  fi
}

# funct_restore_file
#
# Restore file
#
# This routine restores a file from the backup directory to its original
# As par of the restore it also restores the original permissions
#
# check_file      = The name of the original file
# restore_dir     = The directory to restore from
#.

funct_restore_file () {
  check_file=$1
  restore_dir=$2
  restore_file="$restore_dir$check_file"
  if [ -f "$restore_file" ]; then
    sum_check_file=`cksum $check_file |awk '{print $1}'`
    sum_restore_file=`cksum $restore_file |awk '{print $1}'`
    if [ "$sum_check_file" != "$sum_restore_file" ]; then
      echo "Restoring: File $restore_file to $check_file"
      cp -p $restore_file $check_file
      if [ "$os_name" = "SunOS" ]; then
        if [ "$os_version" != "11" ]; then
          pkgchk -f -n -p $check_file 2> /dev/null
        else
          pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
        fi
        if [ "$check_file" = "/etc/system" ]; then
          reboot=1
          echo "Notice:    Reboot required"
        fi
      fi
      if [ "$check_file" = "/etc/ssh/sshd_config" ] || [ "$check_file" = "/etc/sshd_config" ]; then
        echo "Notice:    Service restart required for SSH"
      fi
    fi
  fi
}

# funct_file_value
#
# Audit file values
#
# This routine takes four values
#
# check_file      = The name of the file to check 
# parameter_name  = The parameter to be checked
# seperator       = Character used to seperate parameter name from it's value (eg =)
# correct_value   = The value we expect to be returned
# comment_value   = Character used as a comment (can be #, *, etc)
#
# If the current_value is not the correct_value then it is fixed if run in lockdown mode
# A copy of the value is stored in a log file, which can be restored
#.

funct_file_value () {
  check_file=$1
  parameter_name=$2
  separator=$3
  correct_value=$4
  comment_value=$5
  position=$6
  search_value=$7
  total=`expr $total + 1`
  if [ "$comment_value" = "star" ]; then
    comment_value="*"
  else
    if [ "$comment_value" = "bang" ]; then
      comment_value="!"
    else
      comment_value="#"
    fi
  fi
  if [ `expr "$separator" : "eq"` = 2 ]; then
    separator="="
    spacer="\="
  else
    if [ `expr "$separator" : "space"` = 5 ]; then
      separator=" "
      spacer=" "
    else
      if [ `expr "$separator" : "colon"` = 5 ]; then
        separator=":"
        space=":"
      fi
    fi
  fi
  if [ "$audit_mode" = 2 ]; then
    funct_restore_file $check_file $restore_dir
  else
    echo "Checking:  Value of \"$parameter_name\" in $check_file is \"$correct_value\""
    if [ ! -f "$check_file" ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   Parameter \"$parameter_name\" not set to \"$correct_value\" in $check_file [$score]"
        if [ "$check_file" = "/etc/default/sendmail" ] || [ "$check_file" = "/etc/sysconfig/mail" ]; then
          funct_verbose_message "" fix
          funct_verbose_message "echo \"$parameter_name$separator\"$correct_value\" >> $check_file" fix
          funct_verbose_message "" fix
        else
          funct_verbose_message "" fix
          funct_verbose_message "echo \"$parameter_name$separator$correct_value\" >> $check_file" fix
          funct_verbose_message "" fix
        fi
      else
        if [ "$audit_mode" = 0 ]; then
          echo "Setting:   Parameter \"$parameter_name\" to \"$correct_value\" in $check_file"
          if [ "$check_file" = "/etc/system" ]; then
            reboot=1
            echo "Notice:    Reboot required"
          fi
          if [ "$check_file" = "/etc/ssh/sshd_config" ] || [ "$check_file" = "/etc/sshd_config" ]; then
            echo "Notice:    Service restart required for SSH"
          fi
          funct_backup_file $check_file
          if [ "$check_file" = "/etc/default/sendmail" ] || [ "$check_file" = "/etc/sysconfig/mail" ]; then
            echo "$parameter_name$separator\"$correct_value\"" >> $check_file
          else
            echo "$parameter_name$separator$correct_value" >> $check_file
          fi
        fi
      fi
    else
      if [ "$separator" = "tab" ]; then
        check_value=`cat $check_file |grep -v "^$comment_value" |grep "$parameter_name" |awk '{print $2}' |sed 's/"//g' |uniq`
      else
        check_value=`cat $check_file |grep -v "^$comment_value" |grep "$parameter_name" |cut -f2 -d"$separator" |sed 's/"//g' |sed 's/ //g' |uniq`
      fi
      if [ "$check_value" != "$correct_value" ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Parameter \"$parameter_name\" not set to \"$correct_value\" in $check_file [$score]"
          if [ "$check_parameter" != "$parameter_name" ]; then
            if [ "$separator_value" = "tab" ]; then
              funct_verbose_message "" fix
              funct_verbose_message "echo -e \"$parameter_name\t$correct_value\" >> $check_file" fix
              funct_verbose_message "" fix
            else
              if [ "$position" = "after" ]; then
                funct_verbose_message "" fix
                funct_verbose_message "cat $check_file |sed \"s,$search_value,&\n$parameter_name$separator$correct_value,\" > $temp_file" fix
                funct_verbose_message "cat $temp_file > $check_file" fix
                funct_verbose_message "" fix
              else
                funct_verbose_message "" fix
                funct_verbose_message "echo \"$parameter_name$separator$correct_value\" >> $check_file" fix
                funct_verbose_message "" fix
              fi
            fi
          else
            if [ "$check_file" = "/etc/default/sendmail" ] || [ "$check_file" = "/etc/sysconfig/mail" ]; then
              funct_verbose_message "" fix
              funct_verbose_message "sed \"s/^$parameter_name.*/$parameter_name$spacer\"$correct_value\"/\" $check_file > $temp_file" fix
            else
              funct_verbose_message "" fix
              funct_verbose_message "sed \"s/^$parameter_name.*/$parameter_name$spacer$correct_value/\" $check_file > $temp_file" fix
            fi
            funct_verbose_message "cat $temp_file > $check_file" fix
            funct_verbose_message "" fix
          fi
        else
          if [ "$audit_mode" = 0 ]; then
            if [ "$separator" = "tab" ]; then
              check_parameter=`cat $check_file |grep -v "^$comment_value" |grep "$parameter_name" |awk '{print $1}'`
            else  
              check_parameter=`cat $check_file |grep -v "^$comment_value" |grep "$parameter_name" |cut -f1 -d"$separator" |sed 's/ //g' |uniq`
            fi
            echo "Setting:   Parameter \"$parameter_name\" to \"$correct_value\" in $check_file"
            if [ "$check_file" = "/etc/system" ]; then
              reboot=1
              echo "Notice:    Reboot required"
            fi
            if [ "$check_file" = "/etc/ssh/sshd_config" ] || [ "$check_file" = "/etc/sshd_config" ]; then
              echo "Notice:    Service restart required for SSH"
            fi
            funct_backup_file $check_file
            if [ "$check_parameter" != "$parameter_name" ]; then
              if [ "$separator_value" = "tab" ]; then
                echo -e "$parameter_name\t$correct_value" >> $check_file
              else
                if [ "$position" = "after" ]; then
                  cat $check_file |sed "s,$search_value,&\n$parameter_name$separator$correct_value," > $temp_file
                  cat $temp_file > $check_file
                else
                  echo "$parameter_name$separator$correct_value" >> $check_file
                fi
              fi
            else
              if [ "$check_file" = "/etc/default/sendmail" ] || [ "$check_file" = "/etc/sysconfig/mail" ]; then
                sed "s/^$parameter_name.*/$parameter_name$spacer\"$correct_value\"/" $check_file > $temp_file
              else
                sed "s/^$parameter_name.*/$parameter_name$spacer$correct_value/" $check_file > $temp_file
              fi
              cat $temp_file > $check_file
              if [ "$os_name" = "SunOS" ]; then
                if [ "$os_version" != "11" ]; then
                  pkgchk -f -n -p $check_file 2> /dev/null
                else
                  pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
                fi
              fi
              rm $temp_file
            fi
          fi
        fi
      else
        if [ "$audit_mode" != 2 ]; then
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    Parameter \"$parameter_name\" already set to \"$correct_value\" in $check_file [$score]"
          fi
        fi
      fi
    fi
  fi
}

# funct_disable_value
#
# Code to comment out a line
#
# This routine takes 3 values
# check_file      = Name of file to check
# parameter_name  = Line to comment out
# comment_value   = The character to use as a comment, eg # (passed as hash) 
#.

funct_disable_value () {
  check_file=$1
  parameter_name=$2
  comment_value=$3
  total=`expr $total + 1`
  if [ -f "$check_file" ]; then
    if [ "$comment_value" = "star" ]; then
      comment_value="*"
    else
      if [ "$comment_value" = "bang" ]; then
        comment_value="!"
      else
        comment_value="#"
      fi
    fi
    if [ "$audit_mode" = 2 ]; then
      funct_restore_file $check_file $restore_dir
    else
      echo "Checking:  Parameter \"$parameter_name\" in $check_file is disabled"
    fi
    if [ "$separator" = "tab" ]; then
      check_value=`cat $check_file |grep -v "^$comment_value" |grep "$parameter_name" |uniq`
      if [ "$check_value" != "$parameter_name" ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Parameter \"$parameter_name\" not set to \"$correct_value\" in $check_file [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "cat $check_file |sed 's/$parameter_name/$comment_value&' > $temp_file" fix
          funct_verbose_message "cat $temp_file > $check_file" fix
          funct_verbose_message "" fix
        else
          if [ "$audit_mode" = 0 ]; then
            echo "Setting:   Parameter \"$parameter_name\" to \"$correct_value\" in $check_file"
            if [ "$check_file" = "/etc/system" ]; then
              reboot=1
              echo "Notice:    Reboot required"
            fi
            if [ "$check_file" = "/etc/ssh/sshd_config" ] || [ "$check_file" = "/etc/sshd_config" ]; then
              echo "Notice:    Service restart required SSH"
            fi
            funct_backup_file $check_file
            cat $check_file |sed 's/$parameter_name/$comment_value&' > $temp_file
            cat $temp_file > $check_file
            if [ "$os_name" = "SunOS" ]; then
              if [ "$os_version" != "11" ]; then
                pkgchk -f -n -p $check_file 2> /dev/null
              else
                pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
              fi
            fi
            rm $temp_file
          fi
        fi
      else
        if [ "$audit_mode" != 2 ]; then
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    Parameter \"$parameter_name\" already set to \"$correct_value\" in $check_file [$score]"
          fi
        fi
      fi
    fi
  fi
}

# funct_append_file
#
# Code to append a file with a line
#
# check_file      = The name of the original file
# parameter       = The parameter/line to add to a file
# comment_value   = The character used in the file to distinguish a line as a comment
#.

funct_append_file () {
  check_file=$1
  parameter=$2
  comment_value=$3
  total=`expr $total + 1`
  if [ "$comment_value" = "star" ]; then
    comment_value="*"
  else 
    comment_value="#"
  fi
  if [ "$audit_mode" = 2 ]; then
    restore_file="$restore_dir$check_file"
    if [ -f "$restore_file" ]; then
      diff_check=`diff $check_file $restore_file |wc -l`
      if [ "$diff_check" != 0 ]; then
        funct_restore_file $check_file $restore_dir
        if [ "$check_file" = "/etc/system" ]; then
          reboot=1
          echo "Notice:    Reboot required"
        fi
        if [ "$check_file" = "/etc/ssh/sshd_config" ] || [ "$check_file"i = "/etc/sshd_config" ]; then
          echo "Notice:    Service restart required for SSH"
        fi
      fi
    fi
  else
    echo "Checking:  Parameter \"$parameter\" is set in $check_file"
  fi
  if [ ! -f "$check_file" ]; then
    if [ "$audit_mode" = 1 ]; then
      score=`expr $score - 1`
      echo "Warning:   Parameter \"$parameter\" does not exist in $check_file [$score]"
      funct_verbose_message "" fix
      funct_verbose_message "echo \"$parameter\" >> $check_file" fix
      funct_verbose_message "" fix
    else
      if [ "$audit_mode" = 0 ]; then
        echo "Setting:   Parameter \"$parameter_name\" in $check_file"
        if [ "$check_file" = "/etc/system" ]; then
          reboot=1
          echo "Notice:    Reboot required"
        fi
        if [ "$check_file" = "/etc/ssh/sshd_config" ] || [ "$check_file" = "/etc/sshd_config" ]; then
          echo "Notice:    Service restart required for SSH"
        fi
        if [ ! -f "$work_dir$check_file" ]; then
          touch $check_file
          funct_backup_file $check_file
        fi
        echo "$parameter" >> $check_file
      fi
    fi
  else
    check_value=`cat $check_file |grep -v '^$comment_value' |grep '$parameter'`
    if [ "$check_value" != "$parameter" ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   Parameter \"$parameter\" does not exist in $check_file [$score]"
        funct_verbose_message "" fix
        funct_verbose_message "echo \"$parameter\" >> $check_file" fix
        funct_verbose_message "" fix
      else
        if [ "$audit_mode" = 0 ]; then
          echo "Setting:   Parameter \"$parameter\" in $check_file"
          if [ "$check_file" = "/etc/system" ]; then
            reboot=1
            echo "Notice:    Reboot required"
          fi
          if [ "$check_file" = "/etc/ssh/sshd_config" ] || [ "$check_file" = "/etc/sshd_config" ]; then
            echo "Notice:    Service restart required for SSH"
          fi
          funct_backup_file $check_file
          echo "$parameter" >> $check_file
        fi
      fi
    else
      if [ "$audit_mode" != 2 ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Parameter \"$parameter\" exists in $check_file [$score]"
        fi
      fi
    fi
  fi
}

#
# funct_file_exists
#
# Check to see a file exists and create it or delete it
# 
# check_file    = File to check fo
# check_exists  = If equal to no and file exists, delete it
#                 If equal to yes and file doesn't exist, create it
#.

funct_file_exists () {
  check_file=$1
  check_exists=$2
  log_file="$work_dir/file.log"
  total=`expr $total + 1`
  if [ "$check_exists" = "no" ]; then
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  File $check_file does not exist"
    fi
    if [ -f "$check_file" ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   File $check_file exists [$score]"
      fi
      if [ "$audit_mode" = 0 ]; then
        funct_backup_file $check_file
        echo "Removing:  File $check_file"
        echo "$check_file,rm" >> $log_file
        rm $check_file
      fi
    else
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score + 1`
        echo "Secure:    File $check_file does not exist [$score]"
      fi
    fi
  else
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  File $check_file exists"
    fi
    if [ ! -f "$check_file" ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   File $check_file does not exist [$score]"
      fi
      if [ "$audit_mode" = 0 ]; then
        echo "Creating:  File $check_file"
        touch $check_file
        echo "$check_file,touch" >> $log_file
      fi
    else
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Secure:    File $check_file exists [$score]"
      fi
    fi
  fi
  if [ "$audit_mode" = 2 ]; then
    funct_restore_file $check_file $restore_dir
  fi
}

# Get the path the script starts from

start_path=`pwd`

# Get the version of the script from the script itself

script_version=`cd $start_path ; cat $0 | grep '^# Version' |awk '{print $3}'`

# If given no command line arguments print usage information

if [ `expr "$args" : "\-"` != 1 ]; then
  print_usage
fi

# funct_replace_value
#
# Replace a value in a file with the correct value
#
# As there is no interactive sed on Solaris, ie sed -i
# pipe through sed to a temporary file, then replace original file
# Some handling is added to replace / when searching so sed works
#
# check_file    = File to replace value in
# check_value   = Value to check for
# correct_value = What the value should be
# position      = Position of value in the line
#.

funct_replace_value () {
  check_file=$1
  check_value=$2
  new_check_value="$check_value"
  correct_value=$3
  new_correct_value="$correct_value"
  position=$4
  if [ "$position" = "start" ]; then
    position="^"
  else
    position=""
  fi
  string_check=`expr "$check_value" : "\/"`
  if [ "$string_check" = 1 ]; then
    new_check_value=`echo "$check_value" |sed 's,/,\\\/,g'`
  fi
  string_check=`expr "$correct_value" : "\/"`
  if [ "$string_check" = 1 ]; then
    new_correct_value=`echo "$correct_value" |sed 's,/,\\\/,g'`
  fi
  new_check_value="$position$new_check_value"
  if [ "$audit_mode" != 2 ]; then
    echo "Checking:  File $check_file contains \"$correct_value\" rather than \"$check_value\""
  fi
	if [ -f "$check_file" ]; then
	  check_dfs=`cat $check_file |grep "$new_check_value" |wc -l |sed "s/ //g"`
	fi
  if [ "$check_dfs" != 0 ]; then
    if [ "$audit_mode" != 2 ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   File $check_file contains \"$check_value\" rather than \"$correct_value\" [$score]"
        funct_verbose_message "" fix
        funct_verbose_message "sed -e \"s/$new_check_value/$new_correct_value/\" < $check_file > $temp_file" fix
        funct_verbose_message "cp $temp_file $check_file" fix
        funct_verbose_message "" fix
      fi
      if [ "$audit_mode" = 0 ]; then
        funct_backup_file $check_file
        echo "Setting:   Share entries in $check_file to be secure"
        sed -e "s/$new_check_value/$new_correct_value/" < $check_file > $temp_file
        cp $temp_file $check_file
        if [ "$os_version" != "11" ]; then
          pkgchk -f -n -p $check_file 2> /dev/null
        else
          pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
        fi
        rm $temp_file
      fi
    else
      if [ "$audit_mode" = 2 ]; then
        funct_restore_file $check_file $restore_dir
      fi
    fi
  else
    if [ "$audit_mode" = 1 ]; then
      score=`expr $score + 1`
      echo "Secure:    File $check_file contains \"$correct_value\" rather than \"$check_value\" [$score]"
    fi
  fi
}

# apply_latest_patches
#
# Code to apply patches
# Nothing done with this yet
#.

apply_latest_patches () {
  :
}

# funct_check_pkg
#
# Check is a package is installed
#
# Install package if it's not installed and in the pkg dir under the base dir
# Needs some more work
#.

funct_check_pkg () {
  if [ "$os_name" = "SunOS" ]; then
    pkg_name=$1
    pkg_check=`pkginfo $1`
    log_file="$work_dir/pkg.log"
    total=`expr $total + 1`
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Package $pkg_name is installed"
    fi
    if [ `expr "$pkg_check" : "ERROR"` != 5 ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score + 1`
        echo "Secure:    Package $pkg_name is already installed [$score]"
      fi
    else
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   Package $pkg_name is not installed [$score]"
        if [ "$os_version" = "11" ]; then
          funct_verbose_message "" fix
          funct_verbose_message  "pkgadd $pkg_name" fix
          funct_verbose_message "" fix
        else
          funct_verbose_message "" fix
          funct_verbose_message  "pkgadd -d $base_dir/pkg $pkg_name" fix
          funct_verbose_message "" fix
        fi
      fi
      if [ "$audit_mode" = 0 ]; then
        pkg_dir="$base_dir/pkg/$pkg_name"
        if [ -d "$pkg_dir" ]; then
          echo "Installing: $pkg_name"
          if [ "$os_version" = "11" ]; then
            pkgadd $pkg_name
          else
            pkgadd -d $base_dir/pkg $pkg_name
            pkg_check=`pkginfo $1`
          fi
          if [ `expr "$pkg_check" : "ERROR"` != 5 ]; then
            echo "$pkg_name" >> $log_file
          fi
        fi
      fi
    fi
    if [ "$audit_mode" = 2 ]; then
      restore_file="$restore_dir/pkg.log"
      if [ -f "$restore_file" ]; then
        restore_check=`cat $restore_file |grep "^$pkg_name$" |head -1`
        if [ "$restore_check" = "$pkg_name" ]; then
          echo "Removing:   $pkg_name"
          if [ "$os_version" = "11" ]; then
            pkg uninstall $pkg_name
          else
            pkgrm $pkg_name
          fi
        fi
      fi
    fi
  fi
}

# audit_encryption_kit
#
# The Solaris 10 Encryption Kit contains kernel modules that implement 
# various encryption algorithms for IPsec and Kerberos, utilities that 
# encrypt and decrypt files from the command line, and libraries with 
# functions that application programs call to perform encryption. 
# The Encryption Kit enables larger key sizes (> 128) of the following 
# algorithms:
#
# AES (128, 192, and 256-bit key sizes)
# Blowfish (32 to 448-bit key sizes in 8-bit increments)
# RCFOUR/RC4 (8 to 2048-bit key sizes)
#
# This action is not needed for systems running Solaris 10 08/07 and newer
# as the Solaris 10 Encryption Kit is installed by default.
#.

audit_encryption_kit () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Encryption Toolkit"
      funct_check_pkg SUNWcry
      funct_check_pkg SUNWcryr
      if [ $os_update -le 4 ]; then
        funct_check_pkg SUNWcryman
      fi
    fi
  fi
}

# funct_svcadm_service
# 
# Function to audit a svcadm service and enable or disable
#
# service_name    = Name of service
# correct_status  = What the status of the service should be, ie enabled/disabled
#.

funct_svcadm_service () {
  if [ "$os_name" = "SunOS" ]; then
    service_name=$1
    correct_status=$2
    service_exists=`svcs -a |grep "$service_name" | awk '{print $3}'`
    if [ "$service_exists" = "$service_name" ]; then
      total=`expr $total + 1`
      service_status=`svcs -Ho state $service_name`
      file_header="svcadm"
      log_file="$work_dir/$file_header.log"
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  Service $service_name is $correct_status"
      fi
      if [ "$service_status" != "$correct_status" ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Service $service_name is enabled [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "inetadm -d $service_name" fix
          funct_verbose_message "svcadm refresh $service_name" fix
          funct_verbose_message "" fix
        else
          if [ "$audit_mode" = 0 ]; then
            echo "Setting:   Service $service_name to $correct_status"
            echo "Notice:    Previous state stored in $log_file"
            echo "$service_name,$service_status" >> $log_file
            inetadm -d $service_name
            svcadm refresh $service_name
          fi
        fi
      else
        if [ "$audit_mode" = 2 ]; then
          restore_file="$restore_dir/$file_header.log"
          if [ -f "$restore_file" ]; then
            restore_status=`cat $restore_file |grep "^$service_name" |cut -f2 -d','`
            if [ `expr "$restore_status" : "[A-z]"` = 1 ]; then
              if [ "$restore_status" != "$service_status" ]; then
                restore_status=`echo $restore_status |sed 's/online/enable/g' |sed 's/offline/disable/g'`
                echo "Restoring: Service $service_name to $restore_status""d"
                svcadm $restore_status $service_name
                svcadm refresh $service_name
              fi
            fi
          fi
        else
          if [ "$audit_mode" != 2 ]; then
            if [ "$audit_mode" = 1 ]; then
              score=`expr $score + 1`
              echo "Secure:    Service $service_name is already disabled [$score]"
            fi
          fi
        fi
      fi
    fi
  fi
}

# funct_initd_service
#
# Code to audit an init.d service, and enable, or disable service
#
# service_name    = Name of service
# correct_status  = What the status of the service should be, ie enabled/disabled
#.

funct_initd_service () {
  if [ "$os_name" = "SunOS" ]; then
    service_name=$1
    correct_status=$2
    log_file="initd.log"
    service_check=`ls /etc/init.d |grep "^$service_name$" |wc -l |sed 's/ //g'`
    if [ "$service_check" != 0 ]; then
      if [ "$correct_status" = "disabled" ]; then
        check_file="/etc/init.d/_$service_name"
        if [ -f "$check_file" ]; then
          actual_status="disabled"
        else
          actual_status="enabled"
        fi
      else
        check_file="/etc/init.d/$service_name"
        if [ -f "$check_file" ]; then
          actual_status="enabled"
        else
          actual_status="disabled"
        fi
      fi
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  If init.d service $service_name is $correct_status"
      fi
      total=`expr $total + 1`
      if [ "$actual_status" != "$correct_status" ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Service $service_name is not $correct_status [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "mv /etc/init.d/$service_name /etc/init.d/_$service_name" fix
          funct_verbose_message "/etc/init.d/$service_name stop" fix
          funct_verbose_message "" fix
        else
          if [ "$audit_mode" = 0 ]; then
            log_file="$work_dir/$log_file"
            echo "$service_name,$actual_status" >> $log_file
            echo "Setting:   Service $service_name to $correct_status"
            if [ "$correct_status" = "disabled" ]; then
              /etc/init.d/$service_name stop
              mv /etc/init.d/$service_name /etc/init.d/_$service_name
            else
              mv /etc/init.d/_$service_name /etc/init.d/$service_name
              /etc/init.d/$service_name start
            fi
          fi
        fi
      else
        if [ "$audit_mode" = 2 ]; then
          restore_file="$restore_dir/$log_file"
          if [ -f "$restore_file" ]; then
            check_name=`cat $restore_file |grep $service_name |cut -f1 -d","`
            if [ "$check_name" = "$service_name" ]; then
              check_status=`cat $restore_file |grep "$service_name" |cut -f2 -d","`
              echo "Restoring: Service $service_name to $check_status"
              if [ "$check_status" = "disabled" ]; then
                /etc/init.d/$service_name stop
                mv /etc/init.d/$service_name /etc/init.d/_$service_name
              else
                mv /etc/init.d/_$service_name /etc/init.d/$service_name
                /etc/init.d/$service_name start
              fi
            fi
          fi
        else
          if [ "$audit_mode" != 2 ]; then
            if [ "$audit_mode" = 1 ]; then
              score=`expr $score + 1`
              echo "Secure:    Service $service_name is $correct_status [$score]"
            fi
          fi
        fi
      fi
    fi
  fi
}

# funct_inetd_service
#
# Change status of an inetd (/etc/inetd.conf) services
#
#.

funct_inetd_service () {
  if [ "$os_name" = "Linux" ] || [ "$os_name" = "SunOS" ]; then
    service_name=$1
    correct_status=$2
    check_file="/etc/inetd.conf"
    log_file="$service_name.log"
    if [ -f "$check_file" ]; then
      if [ "$correct_status" = "disabled" ]; then
        actual_status=`cat $check_file |grep '^$service_name' |grep -v '^#' |awk '{print $1}'`
      else
        actual_status=`cat $check_file |grep '^$service_name' |awk '{print $1}'`
      fi
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  If inetd service $service_name is set to $correct_status"
        total=`expr $total + 1`
        if [ "$actual_status" != "" ]; then
          if [ "$audit_mode" = 1 ]; then  
            score=`expr $score - 1`
            echo "Warning:   Service $service_name does not have $parameter_name set to $correct_status [$score]"
          else
            if [ "$audit_mode" = 0 ]; then
              funct_backup_file $check_file
              if [ "$correct_status" = "disable" ]; then
                funct_disable_value $check_file $service_name hash 
              else
                :
              fi
            fi
          fi
        else
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    Service $service_name is set to $correct_status [$score]"
          fi
        fi
      else
        funct_restore_file $check_file $restore_dir
      fi
    fi
  fi
}

# audit_xinetd_service
#
# Code to audit an xinetd service, and enable, or disable
#
# service_name    = Name of service
# correct_status  = What the status of the service should be, ie enabled/disabled
#.

audit_xinetd_service () {
  if [ "$os_name" = "Linux" ]; then
    service_name=$1
    parameter_name=$2
    correct_status=$3
    check_file="/etc/xinetd.d/$service_name"
    log_file="$service_name.log"
    if [ -f "$check_file" ]; then
      actual_status=`cat $check_file |grep $parameter_name |awk '{print $3}'`
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  If xinetd service $service_name has $parameter_name set to $correct_status"
        total=`expr $total + 1`
        if [ "$actual_status" != "$correct_status" ]; then
          if [ "$audit_mode" = 1 ]; then	
            score=`expr $score - 1`
            echo "Warning:   Service $service_name does not have $parameter_name set to $correct_status [$score]"
            if [ "$linux_dist" = "debian" ]; then
              command_line="update-rc.d $service_name $correct_status"
            else
              command_line="chkconfig $service_name $correct_status"
            fi
            funct_verbose_message "" fix
            funct_verbose_message "$command_line" fix
            funct_verbose_message "" fix
          else
            if [ "$audit_mode" = 0 ]; then
              log_file="$work_dir/$log_file"
              echo "$parameter_name,$actual_status" >> $log_file
              echo "Setting:   Parameter $parameter_name for $service_name to $correct_status"
              funct_backup_file $check_file
              if [ "$parameter_name" != "disable" ]; then
                cat $check_file |sed 's/$parameter_name.*/$parameter_name = $correct_status/g' > $temp_file
                cp $temp_file $check_file
              else
                if [ "$linux_dist" = "debian" ]; then
                  update-rc.d $service_name $correct_status
                else
                  chkconfig $service_name $correct_status
                fi
              fi
            fi
          fi
        else
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    Service $service_name has $parameter_name set to $correct_status [$score]"
          fi
        fi
      else
        restore_file="$restore_dir/$log_file"
        if [ -f "$restore_file" ]; then
          check_name=`cat $restore_file |grep $service_name |cut -f1 -d","`
          if [ "$check_name" = "$service_name" ]; then
            check_status=`cat $restore_file |grep $service_name |cut -f2 -d","`
            if [ "$actual_status" != "$check_status" ]; then
              funct_restore_file $check_file $restore_dir
            fi
          fi
        fi
      fi
    fi
  fi
}

# funct_chkconfig_service
#
# Code to audit a service managed by chkconfig, and enable, or disbale
#
# service_name    = Name of service
# correct_status  = What the status of the service should be, ie enabled/disabled
#.

funct_chkconfig_service () {
  if [ "$os_name" = "Linux" ]; then
    service_name=$1
    service_level=$2
    correct_status=$3
    if [ "$linux_dist" = "debian" ]; then
      chk_config="/usr/sbin/sysv-rc-conf"
    else
      chk_config="/usr/sbin/chkconfig"
    fi
    log_file="chkconfig.log"
    if [ "$service_level" = "3" ]; then
      actual_status=`$chk_config --list $service_name 2> /dev/null |awk '{print $5}' |cut -f2 -d':' |awk '{print $1}'`
    fi
    if [ "$service_level" = "5" ]; then
      actual_status=`$chk_config --list $service_name 2> /dev/null |awk '{print $7}' |cut -f2 -d':' |awk '{print $1}'`
    fi
    if [ "$actual_status" = "on" ] || [ "$actual_status" = "off" ]; then
      total=`expr $total + 1`
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  Service $service_name at run level $service_level is $correct_status"
      fi
      if [ "$actual_status" != "$correct_status" ]; then
        if [ "$audit_mode" != 2 ]; then
          if [ "$audit_mode" = 1 ]; then	
            score=`expr $score - 1`
            echo "Warning:   Service $service_name at run level $service_level is not $correct_status [$score]"
            command_line="$chk_config --level $service_level $service_name $correct_status"
            funct_verbose_message "" fix
            funct_verbose_message "$command_line" fix
            funct_verbose_message "" fix
          else
            if [ "$audit_mode" = 0 ]; then
              log_file="$work_dir/$log_file"
              echo "$service_name,$service_level,$actual_status" >> $log_file
              echo "Setting:   Service $service_name at run level $service_level to $correct_status"
              $chk_config --level $service_level $service_name $correct_status
            fi
          fi
        fi
      else
        if [ "$audit_mode" != 2 ]; then
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    Service $service_name at run level $service_level is $correct_status [$score]"
          fi
        fi
      fi
      if [ "$audit_mode" = 2 ]; then
        restore_file="$restore_dir/$log_file"
        if [ -f "$restore_file" ]; then
          check_status=`cat $restore_file |grep $service_name |grep ",$service_level," |cut -f3 -d","`
          if [ "$check_status" = "on" ] || [ "$check_status" = "off" ]; then
            if [ "$check_status" != "$actual_status" ]; then
              echo "Restoring: Service $service_name at run level $service_level to $check_status"
              $chk_config --level $service_level $service_name $check_status
            fi
          fi
        fi
      fi
    else
      if [ "$audit_mode" = 1 ]; then
        total=`expr $total + 1`
        score=`expr $score + 1`
        echo "Checking:  Service $service_name at run level $service_level"
        echo "Notice:    Service $service_name is not installed [$score]"
      fi
    fi
  fi
}

# funct_service
#
# Service audit routine wrapper, sends to appropriate function based on service type
#
# service_name    = Name of service
# correct_status  = What the status of the service should be, ie enable/disabled
#.

funct_service () {
  if [ "$os_name" = "SunOS" ]; then
    service_name=$1
    correct_status=$2
    if [ `expr "$service_name" : "svc:"` = 4 ]; then
      funct_svcadm_service $service_name $correct_status
    else
      funct_initd_service $service_name $correct_status
      funct_inetd_service $service_name $correct_status
    fi
  fi
}

# audit_cde_ttdb
#
# The ToolTalk service enables independent CDE applications to communicate
# with each other without having direct knowledge of each other. 
# Not required unless running CDE applications.
#.

audit_cde_ttdb () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "CDE ToolTalk Database Server"
      service_name="svc:/network/rpc/cde-ttdbserver:tcp"
      funct_service $service_name disabled
    fi
  fi
}

# audit_cde_cal () {
#
# CDE Calendar Manager is an appointment and resource scheduling tool. 
# Not required unless running CDE applications.
#.

audit_cde_cal () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Local CDE Calendar Manager"
      service_name="svc:/network/rpc/cde-calendar-manager:default"
      funct_service $service_name disabled
    fi
  fi
}


# audit_cde_spc
#
# CDE Subprocess control. Not required unless running CDE applications.
#.

audit_cde_spc () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Subprocess control"
      service_name="svc:/network/cde-spc:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_opengl
#
# OpenGL. Not required unless running a GUI. Not required on a server.
#.

audit_opengl () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "OpenGL"
      service_name="svc:/application/opengl/ogl-select:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_cde_print
#
# CDE Printing services. Not required unless running CDE applications.
#.

audit_cde_print () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "CDE Print"
      service_name="svc:/application/cde-printinfo:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_ppd_cache
#
# Cache for Printer Descriptions. Not required unless using print services.
#.

audit_ppd_cache () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "PPD Cache"
      service_name="svc:/application/print/ppd-cache-update:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_gdm_conf
#
# Gnome Display Manager should not be used on a server, but if it is it
# should be locked down to disable root access.
#.

audit_gdm_conf () {
  if [ "$os_name" = "Linux" ]; then
    check_file="/etc/X11/gdm/gdm.conf"
    if [ -e "$check_file" ]; then
      funct_verbose_message "GDM Configuration"
      funct_file_value $check_file AllowRoot eq false hash
      funct_file_value $check_file AllowRemoteRoot eq false hash
      funct_file_value $check_file Use24Clock eq true hash
      funct_check_perms $check_file 0644 root root
    fi
  fi
}

# audit_xlogin
#
# The CDE login service provides the capability of logging into the system 
# using  Xwindows. XDMCP provides the capability of doing this remotely.
# If XDMCP remote session access to a machine is not required at all, 
# but graphical login access for the console is required, then
# leave the service in local-only mode. 
#
# Most modern servers are rack mount so you will not be able to log
# into the console using X Windows anyway.
# Disabling these does not prevent support staff from running
# X Windows applications remotely over SSH.
#
# Running these commands will kill  any active graphical sessions 
# on the console or using XDMCP. It will not kill any X Windows
# applications running via SSH.
#.

audit_xlogin () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "XDMCP Listening"
    fi
    if [ "$os_version" = "10" ]; then
      service_name="svc:/application/graphical-login/cde-login"
      funct_service $service_name disabled
      service_name="svc:/application/gdm2-login"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "11" ]; then
      service_name="svc:/application/graphical_login/gdm:default"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "10" ]; then
      service_name="dtlogin"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    check_file="/etc/X11/xdm/Xresources"
    if [ -f "$check_file" ]; then
      funct_verbose_message "X Security Message"
      total=`expr $total + 1`
     if [ "$audit_mode" != 2 ]; then
       greet_check=`cat $check_file |grep 'private system' |wc -l`
       if [ "$greet_check" != 1 ]; then
         echo "Checking:  Checking $check_file for security message"
         greet_mesg="This is a private system --- Authorized use only!"
         if [ "$audit_mode" = 1 ]; then
           score=`expr $score - 1`
           echo "Warning:   File $check_file does not have a security message [$score]"
           funct_verbose_message "" fix
           funct_verbose_message "cat $check_file |awk '/xlogin\*greeting:/ { print GreetValue; next }; { print }' GreetValue=\"$greet_mesg\" > $temp_file" fix
           funct_verbose_message "cat $temp_file > $check_file" fix
           funct_verbose_message "rm $temp_file" fix
           funct_verbose_message "" fix
         else
           echo "Setting:   Security message in $check_file"
           funct_backup_file $check_file
           cat $check_file |awk '/xlogin\*greeting:/ { print GreetValue; next }; { print }' GreetValue="$greet_mesg" > $temp_file
           cat $temp_file > $check_file
           rm $temp_file
           fi
        else
          score=`expr $score + 1`
          echo "Secure:    File $check_file has security message [$score]"
        fi
      else
        funct_restore_file $check_file $restore_dir
      fi  
    fi
    check_file="/etc/X11/xdm/kdmrc"
    if [ -f "$check_file" ]; then
      funct_verbose_message "X Security Message"
      total=`expr $total + 1`
      if [ "$audit_mode" != 2 ]; then
        greet_check= `cat $check_file |grep 'private system' |wc -l`
        greet_mesg="This is a private system --- Authorized USE only!"
        if [ "$greet_check" != 1 ]; then
           echo "Checking:  File $check_file for security message"
           if [ "$audit_mode" = 1 ]; then
             score=`expr $score - 1`
             echo "Warning:   File $check_file does not have a security message [$score]"
             funct_verbose_message "" fix
             funct_verbose_message "cat $check_file |awk '/GreetString=/ { print \"GreetString=\" GreetString; next }; { print }' GreetString=\"$greet_mesg\" > $temp_file" fix
             funct_verbose_message "cat $temp_file > $check_file" fix
             funct_verbose_message "rm $temp_file" fix
             funct_verbose_message "" fix
           else
             echo "Setting:   Security message in $check_file"
             funct_backup_file $check_file
             cat $check_file |awk '/GreetString=/ { print "GreetString=" GreetString; next }; { print }' GreetString="$greet_mesg" > $temp_file
             cat $temp_file > $check_file
             rm $temp_file
           fi
        else
          score=`expr $score + 1`
          echo "Secure:    File $check_file has security message [$score]"
        fi
      else
        funct_restore_file $check_file $restore_dir
      fi  
    fi
    check_file="/etc/X11/xdm/Xservers"
    if [ -f "$check_file" ]; then
      funct_verbose_message "X Listening"
      total=`expr $total + 1`
      if [ "$audit_mode" != 2 ]; then
        greet_check=`cat $check_file |grep 'nolisten tcp' |wc -l`
        if [ "$greet_check" != 1 ]; then
           echo "Checking:  For X11 nolisten directive in $check_file"
           if [ "$audit_mode" = 1 ]; then
             score=`expr $score - 1`
             echo "Warning:   X11 nolisten directive not found in $check_file [$score]"
             funct_verbose_message "" fix
             funct_verbose_message "cat $check_file |awk '( $1 !~ /^#/ && $3 == \"/usr/X11R6/bin/X\" ) { $3 = $3 \" -nolisten tcp\" }; { print }' > $temp_file" fix
             funct_verbose_message "cat $check_file |awk '( $1 !~ /^#/ && $3 == \"/usr/bin/X\" ) { $3 = $3 \" -nolisten tcp\" }; { print }' > $temp_file" fix
             funct_verbose_message "cat $temp_file > $check_file" fix
             funct_verbose_message "rm $temp_file" fix
             funct_verbose_message "" fix
           else
             echo "Setting:   Security message in $check_file"
             funct_backup_file $check_file
             cat $check_file |awk '( $1 !~ /^#/ && $3 == "/usr/X11R6/bin/X" ) { $3 = $3 " -nolisten tcp" }; { print }' > $temp_file
             cat $check_file |awk '( $1 !~ /^#/ && $3 == "/usr/bin/X" ) { $3 = $3 " -nolisten tcp" }; { print }' > $temp_file
             cat $temp_file > $check_file
             rm $temp_file
           fi
        else
          score=`expr $score + 1`
          echo "Secure:    X11 nolisten directive found in $check_file [$score]"
        fi
      else
        funct_restore_file $check_file $restore_dir
      fi  
    fi
  fi
}

# audit_postfix_daemon
#
# Postfix is installed and active by default on SUSE.
# If the system need not accept remote SMTP connections, disable remote SMTP 
# connections by setting SMTPD_LISTEN_REMOTE="no" in the /etc/sysconfig/mail 
# SMTP connections are not accepted in a default configuration.
#.

audit_postfix_daemon () {
  if [ "$os_name" = "Linux" ]; then
    if [ "$linux_dist" = "suse" ]; then
      check_file="/etc/sysconfig/mail"
      funct_file_value $check_file SMTPD_LISTEN_REMOTE eq no hash
    fi
  fi
}

# audit_sendmail_daemon
#
# If sendmail is set to local only mode, users on remote systems cannot 
# connect to the sendmail daemon. This eliminates the possibility of a 
# remote exploit attack against sendmail. Leaving sendmail in local-only 
# mode permits mail to be sent out from the local system. 
# If the local system will not be processing or sending any mail, 
# disable the sendmail service. If you disable sendmail for local use, 
# messages sent to the root account, such as for cron job output or audit 
# daemon warnings, will fail to be delivered properly. 
# Another solution often used is to disable sendmail's local-only mode and 
# to have a cron job process all mail that is queued on the local system and 
# send it to a relay host that is defined in the sendmail.cf file. 
# It is recommended that sendmail be left in localonly mode unless there is 
# a specific requirement to disable it.
#.

audit_sendmail_daemon () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Sendmail Daemon"
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      service_name="svc:/network/smtp:sendmail"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "10" ]; then
      service_name="sendmail"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "9" ] || [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      check_file="/etc/default/sendmail"
      funct_file_value $check_file QUEUEINTERVAL eq 15m hash
      funct_append_file $check_file "MODE=" hash
    else
      funct_initd_service sendmail disable
      check_file="/var/spool/cron/crontabs/root"
      check_string="0 * * * * /usr/lib/sendmail -q"
      funct_append_file $check_file $check_string has
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_chkconfig_service sendmail 3 off
    funct_chkconfig_service sendmail 5 off
    check_file="/etc/sysconfig/sendmail"
    funct_file_value $check_file DAEMON eq no hash
    funct_file_value $check_file QUEUE eq 1h hash
  fi
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    check_file="/etc/mail/sendmail.cf"
    if [ -f "$check_file" ]; then
      funct_verbose_message "Sendmail Configuration"
      search_string="Addr=127.0.0.1"
      restore=0
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  Mail transfer agent is running in local-only mode"
        total=`expr $total + 1`
        check_value=`cat $check_file |grep -v '^#' |grep 'O DaemonPortOptions' |awk '{print $3}' |grep '$search_string'`
        if [ "$check_value" = "$search_string" ]; then
          if [ "$audit_mode" = "1" ]; then
            score=`expr $score - 1`
            echo "Warning:   Mail transfer agent is not running in local-only mode [$score]"
            funct_verbose_message "" fix
            funct_verbose_message "cp $check_file $temp_file" fix
            funct_verbose_message "cat $temp_file |awk 'O DaemonPortOptions=/ { print \"O DaemonPortOptions=Port=smtp, Addr=127.0.0.1, Name=MTA\"; next} { print }' > $check_file" fix
            funct_verbose_message "rm $temp_file" fix
            funct_verbose_message "" fix
          fi
          if [ "$audit_mode" = 0 ]; then
            funct_backup_file $check_file 
            echo "Setting:   Mail transfer agent to run in local-only mode"
            cp $check_file $temp_file
            cat $temp_file |awk 'O DaemonPortOptions=/ { print "O DaemonPortOptions=Port=smtp, Addr=127.0.0.1, Name=MTA"; next} { print }' > $check_file
            rm $temp_file
          fi
        else
          if [ "$audit_mode" = "1" ]; then  
            score=`expr $score + 1`
            echo "Secure:    Mail transfer agent is running in local-only mode [$score]"
          fi
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_webconsole
#
# The Java Web Console (smcwebserver(1M)) provides a common location 
# for users to access web-based system management applications. 
#.

audit_webconsole () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Web Console"
      service_name="svc:/system/webconsole:console"
      funct_service $service_name disabled
    fi
  fi
}

# audit_wbem
#
# Web-Based Enterprise Management (WBEM) is a set of management and Internet 
# technologies. Solaris WBEM Services software provides WBEM services in the 
# Solaris OS, including secure access and manipulation of management data. 
# The software includes a Solaris platform provider that enables management 
# applications to access information about managed resources such as devices 
# and software in the Solaris OS. WBEM is used by the Solaris Management 
# Console (SMC).
#.

audit_wbem () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Web Based Enterprise Management"
      service_name="svc:/application/management/wbem"
      funct_service $service_name disabled
    fi
  fi
}

# audit_print
#
# RFC 1179 describes the Berkeley system based line printer protocol. 
# The service is used to control local Berkeley system based print spooling. 
# It listens on port 515 for incoming print jobs. 
# Secure by default limits access to the line printers by only allowing 
# print jobs to be initiated from the local system. 
# If the machine does not have locally attached printers, 
# disable this service. 
# Note that this service is not required for printing to a network printer.
#.

audit_print () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Printing Daemons"
      service_name="svc:/application/print/ipp-listener:default"
      funct_service $service_name disabled
      service_name="svc:/application/print/rfc1179"
      funct_service $service_name disabled
      service_name="svc:/application/print/server:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_keyserv
#
# The keyserv process is only required for sites that are using 
# Oracle's Secure RPC mechanism. The most common uses for Secure RPC on 
# Solaris machines are NIS+ and "secure NFS", which uses the Secure RPC 
# mechanism to provide higher levels of security than the standard NFS 
# protocols. Do not confuse "secure NFS" with sites that use Kerberos 
# authentication as a mechanism for providing higher levels of NFS security. 
# "Kerberized" NFS does not require the keyserv process to be running.
#.

audit_keyserv () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "RPC Encryption Key"
      service_name="svc:/network/rpc/keyserv"
      funct_service $service_name disabled
    fi
  fi
}

# audit_nis_server
#
# These daemons are only required on systems that are acting as an 
# NIS server for the local site. Typically there are only a small 
# number of NIS servers on any given network. 
# These services are disabled by default unless the system has been 
# previously configured to act as a NIS server.
#.

audit_nis_server () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "NIS Server Daemons"
    fi
    if [ "$os_version" = "10" ]; then
      service_name="svc:/network/nis/server"
      funct_service $service_name disabled
      service_name="svc:/network/nis/passwd"
      funct_service $service_name disabled
      service_name="svc:/network/nis/update"
      funct_service $service_name disabled
      service_name="svc:/network/nis/xfr"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "11" ]; then
      service_name="svc:/network/nis/server"
      funct_service $service_name disabled
      service_name="svc:/network/nis/domain"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "NIS Server Daemons"
    for service_name in yppasswdd ypserv ypxfrd; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_nis_client
#
# If the local site is not using the NIS naming service to distribute 
# system and user configuration information, this service may be disabled. 
# This service is disabled by default unless the NIS service has been 
# configured on the system.
#.

audit_nis_client () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "NIS Client Daemons"
      service_name="svc:/network/nis/client"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "NIS Client Daemons"
    service_name="ypbind"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_nisplus
#
# NIS+ was designed to be a more secure version of NIS. However, 
# the use of NIS+ has been deprecated by Oracle and customers are 
# encouraged to use LDAP as an alternative naming service. 
# This service is disabled by default unless the NIS+ service has 
# been configured on the system.
#.

audit_nisplus () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "NIS+ Daemons"
      service_name="svc:/network/rpc/nisplus"
      funct_service $service_name disabled
    fi
  fi
}

# audit_ldap_cache
#
# If the local site is not currently using LDAP as a naming service, 
# there is no need to keep LDAP-related daemons running on the local 
# machine. This service is disabled by default unless LDAP client 
# services have been configured on the system. 
# If a naming service is required, users are encouraged to use LDAP 
# instead of NIS/NIS+.
#.

audit_ldap_cache () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "LDAP Client"
      service_name="svc:/network/ldap/client"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "LDAP Client"
    service_name="ldap"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_kerberos_tgt
#
# While Kerberos can be a security enhancement, if the local site is 
# not currently using Kerberos then there is no need to have the 
# Kerberos TGT expiration warning enabled.
#.

audit_kerberos_tgt () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Kerberos Ticket Warning"
      service_name="svc:/network/security/ktkt_warn"
      funct_service $service_name disabled
    fi
  fi
}

# audit_gss
#
# The GSS API is a security abstraction layer that is designed to make it 
# easier for developers to integrate with different authentication schemes. 
# It is most commonly used in applications for sites that use Kerberos for 
# network authentication, though it can also allow applications to 
# interoperate with other authentication schemes.
# Note: Since this service uses Oracle's standard RPC mechanism, it is 
# important that the system's RPC portmapper (rpcbind) also be enabled 
# when this service is turned on. This daemon will be taken offline if 
# rpcbind is disabled.
#
# GSS does not expose anything external to the system as it is configured 
# to use TLI (protocol = ticotsord) by default. However, unless your 
# organization is using the GSS API, disable it.
#.

audit_gss () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Generic Security Services"
      service_name="svc:/network/rpc/gss"
      funct_service $service_name disabled
    fi
  fi
}

# audit_volfs
#
# The volume manager automatically mounts external devices for users whenever 
# the device is attached to the system. These devices include CD-R, CD-RW, 
# floppies, DVD, USB and 1394 mass storage devices. See the vold (1M) manual 
# page for more details.
# Note: Since this service uses Oracle's standard RPC mechanism, it is 
# important that the system's RPC portmapper (rpcbind) also be enabled 
# when this service is turned on.
#
# Allowing users to mount and access data from removable media devices makes 
# it easier for malicious programs and data to be imported onto your network. 
# It also introduces the risk that sensitive data may be transferred off the 
# system without a log record. Another alternative is to edit the 
# /etc/vold.conf file and comment out any removable devices that you do not 
# want users to be able to mount.
#.


audit_volfs () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Volume Management Daemons"
    fi
    if [ "$os_version" = "10" ]; then
      service_name="svc:/system/filesystem/volfs"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "11" ]; then
      service_name="svc:/system/filesystem/rmvolmgr"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      service_name="svc:/network/rpc/smserver"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "10" ]; then
      service_name="volmgt"
      funct_service $service_name disabled
    fi
  fi
}

# audit_samba
#
# Solaris includes the popular open source Samba server for providing file 
# and print services to Windows-based systems. This allows a Solaris system 
# to act as a file or print server on a Windows network, and even act as a 
# Domain Controller (authentication server) to older Windows operating 
# systems. Note that on Solaris releases prior to 11/06 the file 
# /etc/sfw/smb.conf does not exist and the service will not be started by 
# default even on newer releases.
#.

audit_samba () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Samba Daemons"
    fi
    if [ "$os_version" = "10" ]; then
      if [ $os_update -ge 4 ]; then
        service_name="svc:/network/samba"
        funct_service $service_name disabled
      else
        service_name="samba"
        funct_service $service_name disabled
      fi
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Samba Daemons"
    service_name="smb"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_autofs
#
# The automount daemon is normally used to automatically mount NFS file systems 
# from remote file servers when needed. However, the automount daemon can also 
# be configured to mount local (loopback) file systems as well, which may 
# include local user home directories, depending on the system configuration. 
# Sites that have local home directories configured via the automount daemon 
# in this fashion will need to ensure that this daemon is running for Oracle's 
# Solaris Management Console administrative interface to function properly. 
# If the automount daemon is not running, the mount points created by SMC will 
# not be mounted.
# Note: Since this service uses Oracle's standard RPC mechanism, it is important 
# that the system's RPC portmapper (rpcbind) also be enabled when this service 
# is turned on.
#.

audit_autofs () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Automount services"
      service_name="svc:/system/filesystem/autofs"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Automount services"
    service_name="autofs"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_apache
#
# The action in this section describes disabling the Apache 1.x and 2.x web 
# servers provided with Solaris 10. Both services are disabled by default. 
# Run control scripts for Apache 1 and the NCA web servers still exist, 
# but the services will only be started if the respective configuration 
# files have been set up appropriately, and these configuration files do not 
# exist by default.
# Even if the system is a Web server, the local site may choose not to use 
# the Web server provided with Solaris in favor of a locally developed and 
# supported Web environment. If the machine is a Web server, the administrator 
# is encouraged to search the Web for additional documentation on Web server 
# security.
#.

audit_apache () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Apache"
    fi
    if [ "$os_version" = "10" ]; then
      service_name="svc:/network/http:apache2"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "11" ]; then
      service_name="svc:/network/http:apache22"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "10" ]; then
      service_name="apache"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Apache and web based services"
    for service_name in httpd apache tomcat5 squid prixovy; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_svm
#
# The Solaris Volume Manager, formerly known as Solstice DiskSuite, provides 
# functionality for managing disk storage, disk arrays, etc. However, many 
# systems without large storage arrays do not require that these services be 
# enabled or may be using an alternate volume manager rather than the bundled 
# SVM functionality. This service is disabled by default in the OS.
#.

audit_svm () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Solaris Volume Manager Daemons"
      service_name="svc:/system/metainit"
      funct_service $service_name disabled
      service_name="svc:/system/mdmonitor"
      funct_service $service_name disabled
      if [ $os_update -lt 4 ]; then
        service_name="svc:/platform/sun4u/mpxio-upgrade"
      else
        service_name="svc:/system/device/mpxio-upgrade"
      fi
      funct_service $service_name disabled
    fi
  fi
}

# audit_svm_gui
#
# The Solaris Volume Manager, formerly Solstice DiskSuite, provides software 
# RAID capability for Solaris systems. This functionality can either be 
# controlled via the GUI administration tools provided with the operating 
# system, or via the command line. However, the GUI tools cannot function 
# without several daemons listed in Item 2.3.12 Disable Solaris Volume 
# Manager Services enabled. If you have disabled Solaris Volume Manager 
# Services, also disable the Solaris Volume Manager GUI.
# Note: Since these services use Oracle's standard RPC mechanism, it is 
# important that the system's RPC portmapper (rpcbind) also be enabled 
# when these services are turned on.
#
# Since the same functionality that is in the GUI is available from the 
# command line interface, administrators are strongly urged to leave these 
# daemons disabled and administer volumes directly from the command line.
#.

audit_svm_gui () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Solaris Volume Manager GUI Daemons"
      service_name="svc:/network/rpc/mdcomm"
      funct_service $service_name disabled
      service_name="svc:/network/rpc/meta"
      funct_service $service_name disabled
      service_name="svc:/network/rpc/metamed"
      funct_service $service_name disabled
      service_name="svc:/network/rpc/metamh"
      funct_service $service_name disabled
    fi
  fi
}

# audit_svccfg_value
#
# Remote Procedure Calls (RPC) is used by many services within the Solaris 10 
# operating system. Some of these services allow external connections to use 
# the service (e.g. NFS, NIS).
#
# RPC-based services are typically deployed to use very weak or non-existent 
# authentication and yet may share very sensitive information. Unless one of 
# the services is required on this machine, it is best to disable RPC-based 
# tools completely. If you are unsure whether or not a particular third-party 
# application requires RPC services, consult with the application vendor.
#.

audit_svccfg_value () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "RPC Port Mapping"
    service_name=$1
    service_property=$2
    correct_value=$3
    current_value=`svccfg -s $service_name listprop $service_property |awk '{print $3}'`
    file_header="svccfg"
    log_file="$work_dir/$file_header.log"
    total=`expr $total + 1`
    if [ "$audit_mode" = 2 ]; then
      restore_file="$restore_dir/$file_header.log"
      if [ -f "$restore_file" ]; then
        restore_property=`cat $restore_file |grep "$service_name" |cut -f2 -d','`
        restore_value=`cat $restore_file |grep "$service_name" |cut -f3 -d','`
        if [ `expr "$restore_property" : "[A-z]"` = 1 ]; then
          if [ "$current_value" != "$restore_vale" ]; then
            echo "Restoring: $service_name $restore_propert to $restore_value"
            svccfg -s $service_name setprop $restore_property = $restore_value
          fi
        fi
      fi
    else
      echo "Checking:  Service $service_name"
    fi
    if [ "$current_value" != "$correct_value" ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   Service $service_name $service_property not set to $correct_value [$score]"
        command_line="svccfg -s $service_name setprop $service_property = $correct_value"
        funct_verbose_message "" fix
        funct_verbose_message "$command_line" fix
        funct_verbose_message "" fix
      else
        if [ "$audit_mode" = 0 ]; then
          echo "Setting:   $service_name $service_propery to $correct_value"
          echo "$service_name,$service_property,$current_value" >> $log_file
          svccfg -s $service_name setprop $service_property = $correct_value
        fi
      fi
    else
      if [ "$audit_mode" != 2 ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Service $service_name $service_property already set to $correct_value [$score]"
        fi
      fi
    fi
  fi
}

# audit_rpc_bind
#
# The rpcbind utility is a server that converts RPC program numbers into 
# universal addresses. It must be running on the host to be able to make 
# RPC calls on a server on that machine.
# When an RPC service is started, it tells rpcbind the address at which it is 
# listening, and the RPC program numbers it is prepared to serve. When a client 
# wishes to make an RPC call to a given program number, it first contacts 
# rpcbind on the server machine to determine the address where RPC requests 
# should be sent.
# The rpcbind utility should be started before any other RPC service. Normally, 
# standard RPC servers are started by port monitors, so rpcbind must be started 
# before port monitors are invoked.
# Check that rpc bind has tcp wrappers enabled in case it's turned on.
#.

audit_rpc_bind () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "RPC Bind"
      service_name="svc:/network/rpc/bind"
      service_property="config/enable_tcpwrappers"
      correct_value="true"
      audit_svccfg_value $service_name $service_property $correct_value
    fi
    if [ "$os_version" = "11" ]; then
      service_name="svc:/network/rpc/bind"
      funct_service $service_name disabled
    fi
  fi
}

# secure_baseline
#
# Establish a Secure Baseline
# This uses the Solaris 10 svcadm baseline
# Don't really need this so haven't coded anything for it yet
#.

secure_baseline () {
  :
}

# audit_tcp_wrappers
#
# TCP Wrappers is a host-based access control system that allows administrators 
# to control who has access to various network services based on the IP address 
# of the remote end of the connection. TCP Wrappers also provide logging 
# information via syslog about both successful and unsuccessful connections. 
# Rather than enabling TCP Wrappers for all services with "inetadm -M ...", 
# the administrator has the option of enabling TCP Wrappers for individual 
# services with "inetadm -m <svcname> tcp_wrappers=TRUE", where <svcname> is 
# the name of the specific service that uses TCP Wrappers. 
#
# TCP Wrappers provides more granular control over which systems can access 
# services which limits the attack vector. The logs show attempted access to 
# services from non-authorized systems, which can help identify unauthorized 
# access attempts. 
#.

audit_tcp_wrappers () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "TCP Wrappers"
      audit_rpc_bind
      for service_name in `inetadm |awk '{print $3}' |grep "^svc"`; do
        funct_command_value inetadm tcp_wrappers TRUE $service_name
      done
    fi
  fi
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Hosts Allow/Deny"
    check_file="/etc/hosts.deny"
    funct_file_value $check_file ALL colon " ALL" hash
    check_file="/etc/hosts.allow"
    funct_file_value $check_file ALL colon " localhost" hash
    funct_file_value $check_file ALL colon " 127.0.0.1" hash
    if [ ! -f "$check_file" ]; then
      for ip_address in `ifconfig -a |grep 'inet addr' |grep -v ':127.' |awk '{print $2}' |cut -f2 -d":"`; do
        netmask=`ifconfig -a |grep '$ip_address' |awk '{print $3}' |cut -f2 -d":"`
        funct_file_value $check_file ALL colon " $ip_address/$netmask" hash
      done
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "TCP Wrappers"
    if [ "$dist_linux" = "redhat" ] || [ "$dist_linux" = "suse" ]; then
      package_name="tcp_wrappers"
      total=`expr $total + 1`
      log_file="$package_name.log"
      audit_linux_package check $package_name
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  TCP Wrappers is installed"
      fi
      if [ "$package_name" != "tcp_wrappers" ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   TCP Wrappers is not installed [$score]"
        fi
        if [ "$audit_mode" = 0 ]; then
          echo "Setting:   TCP Wrappers to installed"
          log_file="$work_dir/$log_file"
          echo "Installed $package_name" >> $log_file
          audit_linux_package install $package_name
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    TCP Wrappers is installed [$score]"
        fi
        if [ "$audit_mode" = 2 ]; then
          restore_file="$restore_dir/$log_file"
          audit_linux_package restore $package_name $restore_file
        fi
      fi
    fi
  fi
}

# audit_ndd_value
#
# Modify Network Parameters
# Checks and sets ndd values
#
# Network device drivers have parameters that can be set to provide stronger 
# security settings, depending on environmental needs. 
#
# The tcp_extra_priv_ports_add parameter adds a non privileged port to the 
# privileged port list.
# Lock down dtspcd(8) (CDE Subprocess Control Service). This optional service 
# is seldom used. It has historically been associated with malicious scans. 
# Making it a privileged port prevents users from opening up the service on a 
# Solaris machine.
#.

audit_ndd_value () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      ndd_name=$1
      ndd_property=$2
      correct_value=$3
      total=`expr $total + 1`
      if [ "$ndd_property" = "tcp_extra_priv_ports_add" ]; then
        current_value=`ndd -get $ndd_name tcp_extra_priv_ports |grep "$correct_value"`
      else
        current_value=`ndd -get $ndd_name $ndd_property`
      fi
      file_header="ndd"
      log_file="$work_dir/$file_header.log"
      if [ "$audit_mode" = 2 ]; then
        restore_file="$restore_dir/$file_header.log"
        if [ -f "$restore_file" ]; then
          restore_property=`cat $restore_file |grep "$ndd_property," |cut -f2 -d','`
          restore_value=`cat $restore_file |grep "$ndd_property," |cut -f3 -d','`
          if [ `expr "$restore_property" : "[A-z]"` = 1 ]; then
            if [ "$ndd_property" = "tcp_extra_priv_ports_add" ]; then
              current_value=`ndd -get $ndd_name tcp_extra_priv_ports |grep "$restore_value" |wc -l`
            fi
            if [ `expr "$current_value" : "[1-9]"` = 1 ]; then
              if [ "$current_value" != "$restore_value" ]; then
                if [ "$ndd_property" = "tcp_extra_priv_ports_add" ]; then
                  ndd_property="tcp_extra_priv_ports_del"
                fi
                echo "Restoring: $ndd_name $ndd_property to $restore_value"
                ndd -set $ndd_name $ndd_property $restore_value
              fi
            fi
          fi
        fi
      else
        echo "Checking:  NDD $ndd_name $ndd_property"
      fi
      if [ "$current_value" -ne "$correct_value" ]; then
        command_line="ndd -set $ndd_name $ndd_property $correct_value"
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   NDD \"$ndd_name $ndd_property\" not set to \"$correct_value\" [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "$command_line" fix
          funct_verbose_message "" fix
        else
          if [ "$audit_mode" = 0 ]; then
            echo "Setting:   NDD \"$ndd_name $ndd_property\" to \"$correct_value\""
            echo "$ndd_name,$ndd_property,$correct_value" >> $log_file
            `$command_line`
          fi
        fi
      else
        if [ "$audit_mode" != 2 ]; then
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    NDD \"$ndd_name $ndd_property\" already set to \"$correct_value\" [$score]"
          fi
        fi
      fi
    fi
  fi
}

# audit_kernel_params
#
# Network device drivers have parameters that can be set to provide stronger 
# security settings, depending on environmental needs. This section describes 
# modifications to network parameters for IP, ARP and TCP.
# The settings described in this section meet most functional needs while 
# providing additional security against common network attacks. However, 
# it is important to understand the needs of your particular environment 
# to determine if these settings are appropriate for you.
#
# The ip_forward_src_routed and ip6_forward_src_routed parameters control 
# whether IPv4/IPv6 forwards packets with source IPv4/IPv6 routing options
# Keep this parameter disabled to prevent denial of service attacks through 
# spoofed packets.
#
# The ip_forward_directed_broadcasts parameter controls whether or not Solaris 
# forwards broadcast packets for a specific network if it is directly connected 
# to the machine.
# The default value of 1 causes Solaris to forward broadcast packets. 
# An attacker could send forged packets to the broadcast address of a remote 
# network, resulting in a broadcast flood. Setting this value to 0 prevents 
# Solaris from forwarding these packets. Note that disabling this parameter 
# also disables broadcast pings.
#
# The ip_respond_to_timestamp parameter controls whether or not to respond to 
# ICMP timestamp requests.
# Reduce attack surface by restricting a vector for host discovery.
#
# The ip_respond_to_timestamp_broadcast parameter controls whether or not to 
# respond to ICMP broadcast timestamp requests.
# Reduce attack surface by restricting a vector for bulk host discovery.
#
# The ip_respond_to_address_mask_broadcast parameter controls whether or not 
# to respond to ICMP netmask requests, typically sent by diskless clients when 
# booting.
# An attacker could use the netmask information to determine network topology. 
# The default value is 0.
#
# The ip6_send_redirects parameter controls whether or not IPv6 sends out 
# ICMPv6 redirect messages.
# A malicious user can exploit the ability of the system to send ICMP redirects 
# by continually sending packets to the system, forcing the system to respond 
# with ICMP redirect messages, resulting in an adverse impact on the CPU and 
# performance of the system.
#
# The ip_respond_to_echo_broadcast parameter controls whether or not IPv4 
# responds to a broadcast ICMPv4 echo request.
# Responding to echo requests verifies that an address is valid, which can aid 
# attackers in mapping out targets. ICMP echo requests are often used by 
# network monitoring applications.
#
# The ip6_respond_to_echo_multicast and ip_respond_to_echo_multicast parameters 
# control whether or not IPv6 or IPv4 responds to a multicast IPv6 or IPv4 echo 
# request.
# Responding to multicast echo requests verifies that an address is valid, 
# which can aid attackers in mapping out targets.
#
# The ip_ire_arp_interval parameter determines the intervals in which Solaris 
# scans the IRE_CACHE (IP Resolved Entries) and deletes entries that are more 
# than one scan old. This interval is used for solicited arp entries, not 
# un-solicited which are handled by arp_cleanup_interval.
# This helps mitigate ARP attacks (ARP poisoning). Consult with your local 
# network team for additional security measures in this area, such as using 
# static ARP, or fixing MAC addresses to switch ports.
#
# The ip_ignore_redirect and ip6_ignore_redirect parameters determine if 
# redirect messages will be ignored. ICMP redirect messages cause a host to 
# re-route packets and could be used in a DoS attack. The default value for 
# this is 0. Setting this parameter to 1 causes redirect messages to be 
# ignored.
# IP redirects should not be necessary in a well-designed, well maintained 
# network. Set to a value of 1 if there is a high risk for a DoS attack. 
# Otherwise, the default value of 0 is sufficient.
#
# The ip_strict_dst_multihoming and ip6_strict_dst_multihoming parameters 
# determines whether a packet arriving on a non -forwarding interface can be 
# accepted for an IP address that is not explicitly configured on that 
# interface. If ip_forwarding is enabled, or xxx:ip_forwarding (where xxx is 
# the interface name) for the appropriate interfaces is enabled, then this 
# parameter is ignored because the packet is actually forwarded.
# Set this parameter to 1 for systems that have interfaces that cross strict 
# networking domains (for example, a firewall or a VPN node).
#
# The ip_send_redirects parameter controls whether or not IPv4 sends out 
# ICMPv4 redirect messages.
# A malicious user can exploit the ability of the system to send ICMP 
# redirects by continually sending packets to the system, forcing the system 
# to respond with ICMP redirect messages, resulting in an adverse impact on 
# the CPU performance of the system.
#
# The arp_cleanup_interval parameter controls the length of time, in 
# milliseconds, that an unsolicited Address Resolution Protocal (ARP) 
# request remains in the ARP cache.
# If unsolicited ARP requests are allowed to remain in the ARP cache for long 
# periods an attacker could fill up the ARP cache with bogus entries. 
# Set this parameter to 60000 ms (1 minute) to reduce the effectiveness of ARP 
# attacks. The default value is 300000.
#
# The tcp_rev_src_routes parameter determines if TCP reverses the IP source 
# routing option for incoming connections. If set to 0, TCP does not reverse 
# IP source. If set to 1, TCP does the normal reverse source routing. 
# The default setting is 0.
# If IP source routing is needed for diagnostic purposes, enable it. 
# Otherwise leave it disabled.
#
# The tcp_conn_req_max_q0 parameter determines how many half-open TCP 
# connections can exist for a port. This setting is closely related with 
# tcp_conn_req_max_q.
# It is necessary to control the number of completed connections to the system 
# to provide some protection against Denial of Service attacks. Note that the 
# value of 4096 is a minimum to establish a good security posture for this 
# setting. In environments where connections numbers are high, such as a busy 
# webserver, this value may need to be increased.
#
# The tcp_conn_req_max_q parameter determines the maximum number of incoming 
# connections that can be accepted on a port. This setting is closely related 
# with tcp_conn_req_max_q0.
# Restricting the number of "half open" connections limits the damage of DOS 
# attacks where the attacker floods the network with "SYNs". Having this split 
# from the tcp_conn_req_max_q parameter allows the administrator some discretion 
# in this area.
# Note that the value of 1024 is a minimum to establish a good security posture 
# for this setting. In environments where connections numbers are high, such as 
# a busy webserver, this value may need to be increased.
#.

funct_create_nddscript () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" != "11" ]; then
      funct_verbose_message "Kernel ndd Parameters"
      check_file="/etc/init.d/ndd-netconfig"
      rcd_file="/etc/rc2.d/S99ndd-netconfig"
      if [ "$audit_mode" = 0 ]; then
        if [ ! -f "$check_file" ]; then
          echo "Creating:  Init script $check_file"
          echo "#!/sbin/sh" > $check_file
          echo "case \"\$1\" in" >> $check_file
          echo "start)" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/ip ip_forward_src_routed 0" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/ip ip_forwarding 0" >> $check_file
          if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
            echo "\t/usr/sbin/ndd -set /dev/ip ip6_forward_src_routed 0" >> $check_file
            echo "\t/usr/sbin/ndd -set /dev/tcp tcp_rev_src_routes 0" >> $check_file
            echo "\t/usr/sbin/ndd -set /dev/ip ip6_forwarding 0" >> $check_file
          fi
          echo "\t/usr/sbin/ndd -set /dev/ip ip_forward_directed_broadcasts 0" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/tcp tcp_conn_req_max_q0 4096" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/tcp tcp_conn_req_max_q 1024" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/ip ip_respond_to_timestamp 0" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/ip ip_respond_to_timestamp_broadcast 0" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/ip ip_respond_to_address_mask_broadcast 0" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/ip ip_respond_to_echo_multicast 0" >> $check_file
          if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
            echo "\t/usr/sbin/ndd -set /dev/ip ip6_respond_to_echo_multicast 0" >> $check_file
          fi
          echo "\t/usr/sbin/ndd -set /dev/ip ip_respond_to_echo_broadcast 0" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/arp arp_cleanup_interval 60000" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/ip ip_ire_arp_interval 60000" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/ip ip_ignore_redirect 1" >> $check_file
          if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
            echo "\t/usr/sbin/ndd -set /dev/ip ip6_ignore_redirect 1" >> $check_file
          fi
          echo "\t/usr/sbin/ndd -set /dev/tcp tcp_extra_priv_ports_add 6112" >> $check_file
          echo "\t/usr/sbin/ndd -set /dev/ip ip_strict_dst_multihoming 1" >> $check_file
          if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
            echo "\t/usr/sbin/ndd -set /dev/ip ip6_strict_dst_multihoming 1" >> $check_file
          fi
          echo "\t/usr/sbin/ndd -set /dev/ip ip_send_redirects 0" >> $check_file
          if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
            echo "\t/usr/sbin/ndd -set /dev/ip ip6_send_redirects 0" >> $check_file
          fi
          echo "esac" >> $check_file
          echo "exit 0" >> $check_file
          chmod 750 $check_file
          if [ ! -f "$rcd_file" ]; then
            ln -s $check_file $rcd_file
          fi
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          funct_verbose_message "" fix
          if [ ! -f "$check_file" ]; then
            funct_verbose_message "Create an init script $check_file containing the following:"
            funct_verbose_message "#!/sbin/sh" fix
            funct_verbose_message "case \"\$1\" in" fix
            funct_verbose_message "start)" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_forward_src_routed 0" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_forwarding 0" fix
            if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
              funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip6_forward_src_routed 0" fix
              funct_verbose_message "\t/usr/sbin/ndd -set /dev/tcp tcp_rev_src_routes 0" fix
              funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip6_forwarding 0" fix
            fi
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_forward_directed_broadcasts 0" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/tcp tcp_conn_req_max_q0 4096" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/tcp tcp_conn_req_max_q 1024" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_respond_to_timestamp 0" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_respond_to_timestamp_broadcast 0" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_respond_to_address_mask_broadcast 0" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_respond_to_echo_multicast 0" fix
            if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
              funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip6_respond_to_echo_multicast 0" fix
            fi
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_respond_to_echo_broadcast 0" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/arp arp_cleanup_interval 60000" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_ire_arp_interval 60000" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_ignore_redirect 1" fix
            if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
              funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip6_ignore_redirect 1" fix
            fi
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/tcp tcp_extra_priv_ports_add 6112" fix
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_strict_dst_multihoming 1" fix
            if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
              funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip6_strict_dst_multihoming 1" fix
            fi
            funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip_send_redirects 0" fix
            if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
              funct_verbose_message "\t/usr/sbin/ndd -set /dev/ip ip6_send_redirects 0" fix
            fi
            funct_verbose_message "esac" fix
            funct_verbose_message "exit 0" fix
            funct_verbose_message "" fix
            funct_verbose_message "Then run the following command(s)" fix
            funct_verbose_message "chmod 750 $check_file" fix
            if [ ! -f "$rcd_file" ]; then
              funct_verbose_message "ln -s $check_file $rcd_file" fix
            fi
          fi
        fi
      fi
    fi
  fi
}

audit_kernel_params () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" != "11" ]; then
      funct_create_nddscript 
      funct_verbose_message "Kernel ndd Parameters"
      check_file="/etc/init.d/ndd-netconfig"
      rcd_file="/etc/rc2.d/S99ndd-netconfig"
      audit_ndd_value /dev/ip ip_forward_src_routed 0
      audit_ndd_value /dev/ip ip_forwarding 0
      if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
        audit_ndd_value /dev/ip ip6_forward_src_routed 0
        audit_ndd_value /dev/tcp tcp_rev_src_routes 0
        audit_ndd_value /dev/ip ip6_forwarding 0
      fi
      audit_ndd_value /dev/ip ip_forward_directed_broadcasts 0
      audit_ndd_value /dev/tcp tcp_conn_req_max_q0 4096
      audit_ndd_value /dev/tcp tcp_conn_req_max_q 1024
      audit_ndd_value /dev/ip ip_respond_to_timestamp 0
      audit_ndd_value /dev/ip ip_respond_to_timestamp_broadcast 0
      audit_ndd_value /dev/ip ip_respond_to_address_mask_broadcast 0
      audit_ndd_value /dev/ip ip_respond_to_echo_multicast 0
      if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
        audit_ndd_value /dev/ip ip6_respond_to_echo_multicast 0
      fi
      audit_ndd_value /dev/ip ip_respond_to_echo_broadcast 0
      audit_ndd_value /dev/arp arp_cleanup_interval 60000
      audit_ndd_value /dev/ip ip_ire_arp_interval 60000
      audit_ndd_value /dev/ip ip_ignore_redirect 1
      if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
        audit_ndd_value /dev/ip ip6_ignore_redirect 1
      fi
      audit_ndd_value /dev/tcp tcp_extra_priv_ports_add 6112
      audit_ndd_value /dev/ip ip_strict_dst_multihoming 1
      if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
        audit_ndd_value /dev/ip ip6_strict_dst_multihoming 1
      fi
      audit_ndd_value /dev/ip ip_send_redirects 0
      if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
        audit_ndd_value /dev/ip ip6_send_redirects 0
      fi
    fi
    if [ "$audit_mode" = 2 ]; then
      if [ -f "$check_file" ]; then
        funct_file_exists $check_file no
      fi
    fi
  fi
}

# audit_core_dumps
#
# Restrict Core Dumps to Protected Directory
#
# Although /etc/coreadm.conf isn't strictly needed,
# creating it and importing it makes it easier to
# enable or disable changes
#
# Example /etc/coreadm.conf
#
# COREADM_GLOB_PATTERN=/var/cores/core_%n_%f_%u_%g_%t_%p
# COREADM_INIT_PATTERN=core
# COREADM_GLOB_ENABLED=yes
# COREADM_PROC_ENABLED=no
# COREADM_GLOB_SETID_ENABLED=yes
# COREADM_PROC_SETID_ENABLED=no
# COREADM_GLOB_LOG_ENABLED=yes
#
# The action described in this section creates a protected directory to store 
# core dumps and also causes the system to create a log entry whenever a regular 
# process dumps core.
# Core dumps, particularly those from set-UID and set-GID processes, may contain 
# sensitive data.
#.

audit_core_dumps () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Core Dumps"
    if [ "$os_version" != "6" ]; then
      cores_dir="/var/cores"
      check_file="/etc/coreadm.conf"
      cores_check=`coreadm |head -1 |awk '{print $5}'`
      total=`expr $total + 1`
      if [ `expr "$cores_check" : "/var/cores"` != 10 ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Cores are not restricted to a private directory [$score]"
        else
          if [ "$audit_mode" = 0 ]; then
            echo "Setting:   Making sure restricted to a private directory"
            if [ -f "$check_file" ]; then
              echo "Saving:    File $check_file to $work_dir$check_file"
              find $check_file | cpio -pdm $work_dir 2> /dev/null
            else
              touch $check_file
              find $check_file | cpio -pdm $work_dir 2> /dev/null
              rm $check_file
              log_file="$work_dir/$check_file"
              coreadm | sed -e 's/^ *//g' |sed 's/ /_/g' |sed 's/:_/:/g' |awk -F: '{ print $1" "$2 }' | while read option value; do
                if [ "$option" = "global_core_file_pattern" ]; then
                  echo "COREADM_GLOB_PATTERN=$value" > $log_file
                fi
                if [ "$option" = "global_core_file_content" ]; then
                  echo "COREADM_GLOB_CONTENT=$value" >> $log_file
                fi
                if [ "$option" = "init_core_file_pattern" ]; then
                  echo "COREADM_INIT_PATTERN=$value" >> $log_file
                fi
                if [ "$option" = "init_core_file_content" ]; then
                  echo "COREADM_INIT_CONTENT=$value" >> $log_file
                fi
                if [ "$option" = "global_core_dumps" ]; then
                  if [ "$value" = "enabled" ]; then
                    value="yes"
                  else
                    value="no"
                  fi
                  echo "COREADM_GLOB_ENABLED=$value" >> $log_file
                fi
                if [ "$option" = "per-process_core_dumps" ]; then
                  if [ "$value" = "enabled" ]; then
                    value="yes"
                  else
                    value="no"
                  fi
                  echo "COREADM_PROC_ENABLED=$value" >> $log_file
                fi
                if [ "$option" = "global_setid_core_dumps" ]; then
                  if [ "$value" = "enabled" ]; then
                    value="yes"
                  else
                    value="no"
                  fi
                  echo "COREADM_GLOB_SETID_ENABLED=$value" >> $log_file
                fi
                if [ "$option" = "per-process_setid_core_dumps" ]; then
                  if [ "$value" = "enabled" ]; then
                    value="yes"
                  else
                    value="no"
                  fi
                  echo "COREADM_PROC_SETID_ENABLED=$value" >> $log_file
                fi
                if [ "$option" = "global_core_dump_logging" ]; then
                  if [ "$value" = "enabled" ]; then
                    value="yes"
                  else
                    value="no"
                  fi
                  echo "COREADM_GLOB_LOG_ENABLED=$value" >> $log_file
                fi
              done
            fi
            coreadm -g /var/cores/core_%n_%f_%u_%g_%t_%p -e log -e global -e global-setid -d process -d proc-setid
          fi
          if [ ! -d "$cores_dir" ]; then
            mkdir $cores_dir
            chmod 700 $cores_dir
            chown root:root $cores_dir
          fi
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Cores are restricted to a private directory [$score]"
        fi
      fi
      if [ "$audit_mode" = 2 ]; then
        funct_restore_file $check_file $restore_dir
        restore_file="$restore_dir$check_file"
        if [ -f "$restore_file" ]; then
          coreadm -u
        fi
      fi
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Core Dumps"
    for service_name in kdump; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_stack_protection
#
# Stack Protection
#
# Checks for the following values in /etc/system:
#
# set noexec_user_stack=1
# set noexec_user_stack_log=1
# 
# Buffer overflow exploits have been the basis for many highly publicized 
# compromises and defacements of large numbers of Internet connected systems. 
# Many of the automated tools in use by system attackers exploit well-known 
# buffer overflow problems in vendor-supplied and third-party software.
#
# Enabling stack protection prevents certain classes of buffer overflow 
# attacks and is a significant security enhancement. However, this does not 
# protect against buffer overflow attacks that do not execute code on the 
# stack (such as return-to-libc exploits).
#.

audit_stack_protection () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Stack Protection"
    check_file="/etc/system"
    funct_file_value $check_file "set noexec_user_stack" eq 1 star
    funct_file_value $check_file "set noexec_user_stack_log" eq 1 star
  fi
}

# audit_tcp_strong_iss
#
# Strong TCP Sequence Number Generation
#
# Checks for the following values in /etc/default/inetinit:
#
# TCP_STRONG_ISS=2
#
# The variable TCP_STRONG_ISS sets the mechanism for generating the order of 
# TCP packets. If an attacker can predict the next sequence number, it is 
# possible to inject fraudulent packets into the data stream to hijack the 
# session. Solaris supports three sequence number methods:
#
# 0 = Old-fashioned sequential initial sequence number generation. 
# 1 = Improved sequential generation, with random variance in increment. 
# 2 = RFC 1948 sequence number generation, unique-per-connection-ID.
#
# The RFC 1948 method is widely accepted as the strongest mechanism for TCP 
# packet generation. This makes remote session hijacking attacks more difficult, 
# as well as any other network-based attack that relies on predicting TCP 
# sequence number information. It is theoretically possible that there may be a 
# small performance hit in connection setup time when this setting is used, but 
# there are no benchmarks that establish this.
#.

audit_tcp_strong_iss () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "TCP Sequence Number Generation"
    check_file="/etc/default/inetinit"
    funct_file_value $check_file TCP_STRONG_ISS eq 2 hash
    if [ "$os_version" != "11" ]; then
      audit_ndd_value /dev/tcp tcp_strong_iss 2
    fi
    if [ "$os_version" = "11" ]; then
      audit_ipadm_value _strong_iss tcp 2
    fi
  fi
}

# audit_ipadm_value
#
# Code to drive ipadm on Solaris 11
#.

audit_ipadm_value () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "11" ]; then
      ipadm_name=$1
      ipadm_property=$2
      correct_value=$3
      current_value=`ipadm show-prop -p $ipadm_name -co current $ipadm_property`
      file_header="ipadm"
      total=`expr $total + 1`
      log_file="$work_dir/$file_header.log"
      if [ "$audit_mode" = 2 ]; then
        restore_file="$restore_dir/$file_header.log"
        if [ -f "$restore_file" ]; then
          restore_property=`cat $restore_file |grep "$ipadm_property," |cut -f2 -d','`
          restore_value=`cat $restore_file |grep "$ipadm_property," |cut -f3 -d','`
          if [ `expr "$restore_property" : "[A-z]"` = 1 ]; then
            if [ "$current_value" != "$restore_value" ]; then
              echo "Restoring: $ipadm_name $ipadm_property to $restore_value"
              ipadm set-prop -p $ipadm_name=$restore_value $ipadm_property
            fi
          fi
        fi
      else
        echo "Checking:  Value of \"$ipadm_name\" for \"$ipadm_property\" is \"$correct_value\""
      fi
      if [ "$current_value" -ne "$correct_value" ]; then
        command_line="ipadm set-prop -p $ipadm_name=$correct_value $ipadm_property"
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Value of \"$ipadm_name $ipadm_property\" not set to \"$correct_value\" [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "$command_line" fix
          funct_verbose_message "" fix
        else
          if [ "$audit_mode" = 0 ]; then
            echo "Setting:   Value of \"$ipadm_name $ipadm_property\" to \"$correct_value\""
            echo "$ipadm_name,$ipadm_property,$correct_value" >> $log_file
            `$command_line`
          fi
        fi
      else
        if [ "$audit_mode" != 2 ]; then
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    Value of \"$ipadm_name $ipadm_property\" already set to \"$correct_value\" [$score]"
          fi
        fi
      fi
    fi
  fi
}

# audit_routing_params
#
# Network Routing
# Source Packet Forwarding
# Directed Broadcast Packet Forwarding
# Response to ICMP Timestamp Requests
# Response to ICMP Broadcast Timestamp Requests
# Response to ICMP Broadcast Netmask Requests
# Response to Broadcast ICMPv4 Echo Request
# Response to Multicast Echo Request
# Ignore ICMP Redirect Messages
# Strict Multihoming
# ICMP Redirect Messages
# TCP Reverse IP Source Routing
# Maximum Number of Half-open TCP Connections
# Maximum Number of Incoming Connections
#
# The network routing daemon, in.routed, manages network routing tables. 
# If enabled, it periodically supplies copies of the system's routing tables 
# to any directly connected hosts and networks and picks up routes supplied 
# to it from other networks and hosts. 
# Routing Internet Protocol (RIP) is a legacy protocol with a number of 
# security issues (e.g. no authentication, no zoning, and no pruning).
# Routing (in.routed) is disabled by default in all Solaris 10 systems, 
# if there is a default router defined. If no default gateway is defined 
# during system installation, network routing is enabled.
#.

audit_routing_params () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "IP Routing"
      funct_command_value routeadm ipv4-routing disabled
      funct_command_value routeadm ipv6-routing disabled
      funct_verbose_message "IP Forwarding"
      funct_command_value routeadm ipv4-forwarding disabled
      funct_command_value routeadm ipv6-forwarding disabled
      funct_file_exists /etc/notrouter yes
    fi
    if [ "$os_version" = "11" ]; then
      funct_verbose_message "IP Routing"
      audit_ipadm_value _forward_src_routed ipv4 0
      audit_ipadm_value _forward_src_routed ipv6 0
      audit_ipadm_value _rev_src_routes tcp 0
      funct_verbose_message "Broadcasting"
      audit_ipadm_value _forward_directed_broadcasts ip 0
      audit_ipadm_value _respond_to_timestamp ip 0
      audit_ipadm_value _respond_to_timestamp_broadcast ip 0
      audit_ipadm_value _respond_to_address_mask_broadcast ip 0
      audit_ipadm_value _respond_to_echo_broadcast ip 0
      funct_verbose_message "Multicasting"
      audit_ipadm_value _respond_to_echo_multicast ipv4 0
      audit_ipadm_value _respond_to_echo_multicast ipv6 0
      funct_verbose_message "IP Redirecting"
      audit_ipadm_value _ignore_redirect ipv4 1
      audit_ipadm_value _ignore_redirect ipv6 1
      audit_ipadm_value _send_redirects ipv4 0
      audit_ipadm_value _send_redirects ipv6 0
      funct_verbose_message "Multihoming"
      audit_ipadm_value _strict_dst_multihoming ipv4 1
      audit_ipadm_value _strict_dst_multihoming ipv6 1
      funct_verbose_message "Queue Sizing"
      audit_ipadm_value _conn_req_max_q0 tcp 4096
      audit_ipadm_value _conn_req_max_q tcp 1024
    fi
  fi
}

# audit_create_class
#
# Creating Audit Classes improves the auditing capabilities of Solaris.
#.

audit_create_class () {
  if [ "$os_name" = "SunOS" ]; then
    check_file="/etc/security/audit_class"
		if [ -f "$check_file" ]; then
      funct_verbose_message "Audit Classes"
	    class_check=`cat $check_file |grep "Security Lockdown"`
	    total=`expr $total + 1`
	    if [ `expr "$class_check" : "[A-z]"` != 1 ]; then
	      if [ "$audit_mode" = 1 ]; then
	        score=`expr $score - 1`
	        echo "Warning:   Audit class not enabled [$score]"
	      else
	        if [ "$audit_mode" = 0 ]; then
	          echo "Setting:   Audit class to enabled"
	          if [ ! -f "$work_dir$check_file" ]; then
	            echo "Saving:    File $check_file to $work_dir$check_file"
	            find $check_file | cpio -pdm $work_dir 2> /dev/null
	          fi
	          file_length=`wc -l $check_file |awk '{print $1}' |sed 's/ //g'`
	          file_length=`expr $file_length - 1`
	          head -$file_length $check_file > $temp_file
	          echo "0x0100000000000000:lck:Security Lockdown" >> $temp_file
	          tail -1 $check_file >> $temp_file
	          cp $temp_file $check_file
	        fi
	      fi
	    fi
	    if [ "$audit_mode" = 2 ]; then
	      if [ -f "$restore_dir/$check_file" ]; then
	        cp -p $restore_dir/$check_file $check_file
	        if [ "$os_version" = "10" ]; then
	          pkgchk -f -n -p $check_file 2> /dev/null
	        else
	          pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
 	       fi
				fi
      fi
    fi
  fi
}

# audit_network_connections
#
# Auditing of Incoming Network Connections
#.

audit_network_connections () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "11" ]; then
      funct_verbose_message "Auditing of Incomming Network Connections"
      funct_append_file $check_file "lck:AUE_ACCEPT" hash
      funct_append_file $check_file "lck:AUE_CONNECT" hash
      funct_append_file $check_file "lck:AUE_SOCKACCEPT" hash
      funct_append_file $check_file "lck:AUE_SOCKCONNECT" hash
      funct_append_file $check_file "lck:AUE_inetd_connect" hash
    fi
  fi
}

# audit_file_metadata
#
# Auditing of File Metadata Modification Events
#.

audit_file_metadata () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "11" ]; then
      funct_verbose_message "Auditing of File Metadata Modification Events"
      funct_append_file $check_file "lck:AUE_CHMOD" hash
      funct_append_file $check_file "lck:AUE_CHOWN" hash
      funct_append_file $check_file "lck:AUE_FCHOWN" hash
      funct_append_file $check_file "lck:AUE_FCHMOD" hash
      funct_append_file $check_file "lck:AUE_LCHOWN" hash
      funct_append_file $check_file "lck:AUE_ACLSET" hash
      funct_append_file $check_file "lck:AUE_FACLSET" hash
    fi
  fi
}

# audit_privilege_events
#
# Auditing of Process and Privilege Events
#.

audit_privilege_events () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "11" ]; then
      funct_verbose_message "Auditing of Privileged Events"
      funct_append_file $check_file "lck:AUE_CHROOT" hash
      funct_append_file $check_file "lck:AUE_SETREUID" hash
      funct_append_file $check_file "lck:AUE_SETREGID" hash
      funct_append_file $check_file "lck:AUE_FCHROOT" hash
      funct_append_file $check_file "lck:AUE_PFEXEC" hash
      funct_append_file $check_file "lck:AUE_SETUID" hash
      funct_append_file $check_file "lck:AUE_NICE" hash
      funct_append_file $check_file "lck:AUE_SETGID" hash
      funct_append_file $check_file "lck:AUE_PRIOCNTLSYS" hash
      funct_append_file $check_file "lck:AUE_SETEGID" hash
      funct_append_file $check_file "lck:AUE_SETEUID" hash
      funct_append_file $check_file "lck:AUE_SETPPRIV" hash
      funct_append_file $check_file "lck:AUE_SETSID" hash
      funct_append_file $check_file "lck:AUE_SETPGID" hash
    fi
  fi
}

# audit_audit_class
#
# Create audit class on Solaris 11
# Need to investigate more auditing capabilities on Solaris 10
#.

audit_audit_class () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "11" ]; then
      audit_create_class
      audit_network_connections
      audit_file_metadata
      audit_privilege_events
    fi
  fi
}

# funct_command_output
#
# Code to test command output
#.

funct_command_output () {
  if [ "$os_name" = "SunOS" ]; then
    command_name=$1
    total=`expr $total + 1`
    if [ "$command_name" = "getcond" ]; then
      get_command="auditconfig -getcond |cut -f2 -d'=' |sed 's/ //g'"
    fi
    if [ "$command_name" = "getpolicy" ]; then
      get_command="auditconfig -getpolicy |head -1 |cut -f2 -d'=' |sed 's/ //g'"
      correct_value="argv,cnt,zonename"
      restore_command="auditconfig -setpolicy"
    fi
    if [ "$command_name" = "getnaflages" ]; then
      get_command="auditconfig -getpolicy |head -1 |cut -f2 -d'=' |sed 's/ //g' |cut -f1 -d'('"
      correct_value="lo"
      restore_command="auditconfig -setnaflags"
    fi
    if [ "$command_name" = "getflages" ]; then
      get_command="auditconfig -getflags |head -1 |cut -f2 -d'=' |sed 's/ //g' |cut -f1 -d'('"
      correct_value="lck,ex,aa,ua,as,ss,lo,ft"
      restore_command="auditconfig -setflags"
    fi
    if [ "$command_name" = "getplugin" ]; then
      get_command="auditconfig -getplugin audit_binfile |tail-1 |cut -f3 -d';'"
      correct_value="p_minfree=1"
      restore_command="auditconfig -setplugin audit_binfile active"
    fi
    if [ "$command_name" = "userattr" ]; then
      get_command="userattr audit_flags root"
      correct_value="lo,ad,ft,ex,lck:no"
      restore_command="auditconfig -setplugin audit_binfile active"
    fi
    if [ "$command_name" = "getcond" ]; then
      set_command="auditconfig -conf"
    else
      if [ "$command_name" = "getflags" ]; then
        set_command="$restore_command lo,ad,ft,ex,lck"
      else
        set_command="$restore_command $correct_value"
      fi
    fi
    log_file="$command_name.log"
    check_value=`$get_command`
    if [ "$audit_mode" = 1 ]; then
      if [ "$check_value" != "$correct_value" ]; then
        score=`expr $score - 1`
        echo "Warning:   Command $command_name does not return correct value [$score]"
      else
        score=`expr $score + 1`
        echo "Secure:    Command $command_name returns correct value [$score]"
      fi
    fi
    if [ "$audit_mode" = 0 ]; then
      log_file="$work_dir/$log_file"
      if [ "$check_value" != "$test_value" ]; then
        echo "Setting:   Command $command_name to correct value"
        $test_command > $log_file
        $set_command
      fi
    fi
    if [ "$audit_mode" = 2 ]; then
      restore_file="$restore_dir/$log_file"
      if [ -f "$restore_file" ]; then
        echo "Restoring: Previous value for $command_name"
        if [ "$command_name" = "getcond" ]; then
          $restore_command
        else
          restore_string=`cat $restore_file`
          $restore_command $restore_string
        fi
      fi
    fi
  fi
}

# audit_solaris_auditing
#
# Check auditing setup on Solaris 11
# Need to investigate more auditing capabilities on Solaris 10
#.

audit_solaris_auditing () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "11" ]; then
      funct_verbose_message "Solaris Auditing"
      funct_command_output getcond
      funct_command_output getpolicy
      funct_command_output getnaflags
      funct_command_output getplugin
      funct_command_output userattr
      if [ "$audit_mode" != 1 ]; then
        audit -s
      fi
      check_file="/var/spool/cron/crontabs/root"
      if [ "$audit_mode" = 0 ]; then
        log_file="$workdir$check_file"
        rolemod -K audit_flags=lo,ad,ft,ex,lck:no root
				if [ -f "$check_file" ]; then
	        audit_check=`cat $check_file |grep "audit -n" |cut -f4 -d'/'`
	        if [ "$audit_check" != "audit -n" ]; then
	          if [ ! -f "$log_file" ]; then
	            echo "Saving:    File $check_file to $work_dir$check_file"
	            find $check_file | cpio -pdm $work_dir 2> /dev/null
	          fi
	          echo "0 * * * * /usr/sbin/audit -n" >> $check_file
	          chown root:root /var/audit 
	          chmod 750 /var/audit
	          pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
					fi
        fi
      fi
    fi
  fi
}

# audit_cron_perms
#
# Make sure system cron entries are only viewable by system accounts.
# Viewing cron entries may provide vectors of attack around temporary
# file creation and race conditions.
#.

audit_cron_perms () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Cron Permissions"
    check_file="/etc/crontab"
    funct_check_perms $check_file 0640 root root
    check_file="/var/spool/cron"
    funct_check_perms $check_file 0750 root root
    check_file="/etc/cron.daily"
    funct_check_perms $check_file 0750 root root
    check_file="/etc/cron.weekly"
    funct_check_perms $check_file 0750 root root
    check_file="/etc/cron.mounthly"
    funct_check_perms $check_file 0750 root root
    check_file="/etc/cron.hourly"
    funct_check_perms $check_file 0750 root root
    check_file="/etc/anacrontab"
    funct_check_perms $check_file 0750 root root
  fi
}

# audit_inetd_logging
#
# The inetd process starts Internet standard services and the "tracing" feature 
# can be used to log information about the source of any network connections 
# seen by the daemon.
# Rather than enabling inetd tracing for all services with "inetadm -M ...", 
# the administrator has the option of enabling tracing for individual services 
# with "inetadm -m <svcname> tcp_trace=TRUE", where <svcname> is the name of 
# the specific service that uses tracing.
# This information is logged via syslogd (1M) and is deposited by default in 
# /var/adm/messages with other system log messages. If the administrator wants 
# to capture this information in a separate file, simply modify /etc/syslog.conf 
# to log daemon.notice to some other log file destination. 
#.

audit_inetd_logging () {
  if [ "$os_name" = "SunOS" ]; then
    check_file="/etc/default/syslogd"
    funct_file_value $check_file LOG_FROM_REMOTE eq NO hash
    if [ "$os_version" ="10" ] || [ "$os_version" = "9" ]; then
      funct_verbose_message "" fix
      funct_verbose_message "Logging inetd Connections"
      funct_verbose_message "" fix
    fi
    if [ "$os_version" = "10" ]; then
      funct_command_value inetadm tcp_trace TRUE tcp
    fi
    if [ "$os_version" = "9" ]; then
      check_file="/etc/default/inetd"
      funct_file_value $check_file ENABLE_CONNECTION_LOGGING eq YES hash
    fi
  fi
}


# audit_ftp_logging
# 
# Information about FTP sessions will be logged via syslogd (1M), 
# but the system must be configured to capture these messages.
# If the FTP daemon is installed and enabled, it is recommended that the 
# "debugging" (-d) and connection logging (-l) flags also be enabled to 
# track FTP activity on the system. Note that enabling debugging on the FTP 
# daemon can cause user passwords to appear in clear-text form in the system 
# logs, if users accidentally type their passwords at the username prompt.
# All of this information is logged by syslogd (1M), but syslogd (1M) must be 
# configured to capture this information to a separate file so it may be more 
# easily reviewed.
#.

audit_ftp_logging () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "FTPD Daemon Logging"
      get_command="svcprop -p inetd_start/exec svc:/network/ftp:default"
      check_value=`$get_command |grep "\-d" | wc -l`
      file_header="ftpd_logging"
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  File $file_header"
      fi
      log_file="$work_dir/$file_header.log"
      total=`expr $total + 1`
      if [ "$audit_mode" = 1 ]; then
        if [ "$check_value" -eq 0 ]; then
          score=`expr $score - 1`
          echo "Warning:   FTP daemon logging not enabled [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "inetadm -m svc:/network/ftp exec=\"/usr/sbin/in.ftpd -a -l -d\"" fix
          funct_verbose_message "" fix
        else
          score=`expr $score + 1`
          echo "Secure:    FTP daemon logging enabled [$score]"
        fi
      else
        if [ "$audit_mode" = 0 ]; then
          if [ "$check_value" -eq 0 ]; then
            echo "Setting:   FTP daemon logging to enabled"
            $get_command > $log_file
            inetadm -m svc:/network/ftp exec="/usr/sbin/in.ftpd -a -l -d"
          fi
        else
          if [ "$audit_mode" = 2 ]; then
            restore_file="$restore_dir/$file_header.log"
            if [ -f "$restore_file" ]; then
              exec_string=`cat $restore_file`
              echo "Restoring: Previous value for FTP daemon to $exec_string"
              inetadm -m svc:/network/ftp exec="$exec_string"
            fi
          fi
        fi
      fi
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "FTPD Daemon Message"
    funct_rpm_check vsftpd
    if [ "$rpm_check" = "vsftpd" ]; then
      check_file="/etc/vsftpd.conf"
      if [ -f "$check_file" ]; then
        funct_file_value $check_file log_ftp_protocol eq YES hash
        funct_file_value $check_file ftpd_banner eq "Authorized users only. All activity may be monitored and reported." hash
        funct_check_perms $check_file 0600 root root
      fi
      check_file="/etc/vsftpd/vsftpd.conf"
      if [ -f "$check_file" ]; then
        funct_file_value $check_file log_ftp_protocol eq YES hash
        funct_file_value $check_file ftpd_banner eq "Authorized users only. All activity may be monitored and reported." hash
        funct_check_perms $check_file 0600 root root
      fi
    fi
  fi
}

# audit_syslog_conf
#
# By default, Solaris systems do not capture logging information that is sent 
# to the LOG_AUTH facility.
# A great deal of important security-related information is sent via the 
# LOG_AUTH facility (e.g., successful and failed su attempts, failed login 
# attempts, root login attempts, etc.).
#.

audit_syslog_conf () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "SYSLOG Configuration"
    check_file="/etc/syslog.conf"
    funct_file_value $check_file "authpriv.*" tab "/var/log/secure" hash
    funct_file_value $check_file "auth.*" tab "/var/log/messages" hash
  fi
}

# audit_logadm_value
#
# Enable Debug Level Daemon Logging. Improved logging capability.
#.

audit_logadm_value () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Debug Level Daemon Logging"
      log_name=$1
      log_facility=$2
      check_file="/etc/logadm.conf"
      check_log=`logadm -V |grep -v '^#' |grep "$log_name"`
      log_file="/var/log/$log_name"
      total=`expr $total + 1`
      if [ `expr "$check_log" : "[A-z]"` != 1 ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Logging for $log_name not enabled [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "logadm -w $log_name -C 13 -a 'pkill -HUP syslogd' $log_file" fix
          funct_verbose_message "svcadm refresh svc:/system/system-log" fix
          funct_verbose_message "" fix
        else
          if [ "$audit_mode" = 0 ]; then
            echo "Setting:   Syslog to capture $log_facility"
          fi
          funct_backup_file $check_file
          if [ "$log_facility" != "none" ]; then
            check_file="/etc/syslog.conf"
            if [ ! -f "$work_dir$check_file" ]; then
              echo "Saving:    File $check_file to $work_dir$check_file"
              find $check_file | cpio -pdm $work_dir 2> /dev/null
            fi
          fi
          echo "$log_facility\t\t\t$log_file" >> $check_file
          touch $log_file
          chown root:root $log_file
          if [ "$log_facility" = "none" ]; then
            logadm -w $log_name -C 13 $log_file
          else
            logadm -w $log_name -C 13 -a 'pkill -HUP syslogd' $log_file
            svcadm refresh svc:/system/system-log
          fi
        fi
        if [ "$audit_mode" = 2 ]; then
          if [ -f "$restore_dir/$check_file" ]; then
            cp -p $restore_dir/$check_file $check_file
            if [ "$os_version" != "11" ]; then
              pkgchk -f -n -p $check_file 2> /dev/null
            else
              pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
            fi
          fi
          if [ "$log_facility" = "none" ]; then
            check_file="/etc/syslog.conf"
            if [ -f "$restore_dir/$check_file" ]; then
              cp -p $restore_dir/$check_file $check_file
              if [ "$os_version" != "11" ]; then
                pkgchk -f -n -p $check_file 2> /dev/null
              else
                pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
              fi
            fi
            svcadm refresh svc:/system/system-log
          fi
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Logging for $log_name already enabled [$score]"
        fi
      fi
    fi
  fi
}

# audit_debug_logging
#
# Connections to server should be logged so they can be audited in the event
# of and attack.
#.

audit_debug_logging () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Connection Logging"
      audit_logadm_value connlog daemon.debug
    fi
  fi
}

# audit_syslog_auth
#
# Make sure authentication requests are logged. This is especially important
# for authentication requests to accounts/roles with raised priveleges.
#.

audit_syslog_auth () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "SYSLOG AUTH Messages"
      audit_logadm_value authlog auth.info
    fi
  fi
}

# audit_login_records
#
# If the file /var/adm/loginlog exists, it will capture failed login attempt 
# messages with the login name, tty specification, and time. This file does 
# not exist by default and must be manually created.
# Tracking failed login attempts is critical to determine when an attacker 
# is attempting a brute force attack on user accounts. Note that this is only 
# for login-based such as login, telnet, rlogin, etc. and does not include SSH. 
# Review the loginlog file on a regular basis.
#.

audit_login_records () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Login Records"
      audit_logadm_value loginlog none
    fi
  fi
}

# audit_failed_logins
#
# The SYS_FAILED_LOGINS variable is used to determine how many failed login 
# attempts occur before a failed login message is logged. Setting the value 
# to 0 will cause a failed login message on every failed login attempt.
# The SYSLOG_FAILED_LOGINS parameter in the /etc/default/login file is used 
# to control how many login failures are allowed before log messages are 
# generated-if set to zero then all failed logins will be logged.
#.

audit_failed_logins () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Failed Login Attempts"
      check_file="/etc/default/login"
      funct_file_value $check_file SYSLOG_FAILED_LOGINS eq 0 hash
      check_file="/etc/default/login"
      funct_file_value $check_file SYSLOG eq YES hash
      check_file="/etc/default/su"
      funct_file_value $check_file SYSLOG eq YES hash
    fi
  fi
}


# audit_cron_logging
#
# Setting the CRONLOG parameter to YES in the /etc/default/cron file causes 
# information to be logged for every cron job that gets executed on the system. 
# This setting is the default for Solaris.
# A common attack vector is for programs that are run out of cron to be 
# subverted to execute commands as the owner of the cron job. Log data on 
# commands that are executed out of cron can be found in the /var/cron/log file. 
# Review this file on a regular basis.
#.

audit_cron_logging () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Cron Logging"
      check_file="/etc/default/cron"
      funct_file_value $check_file CRONLOG eq YES hash
      check_file="/var/cron/log"
      funct_check_perms $check_file 0640 root root
    fi
  fi
}


# audit_linux_package
#
# Check package
# Takes the following variables:
# package_mode:   Mode, eg check install uninstall restore
# package_check:  Package to check for
# restore_file:   Restore file to check 
#.

audit_linux_package () {
  if [ "$os_name" = "Linux" ]; then
    package_mode=$1
    package_check=$2
    restore_file=$3
    if [ "$os_name" = "Linux" ]; then
      if [ "$package_mode" = "check" ]; then
        if [ "$linux_dist" = "debian" ]; then
          package_name=`dpkg -l $package_check 2>1 |grep $package_check |awk '{print $2}'`
        else
          package_name=`rpm -qi $package_check |grep '^Name' |awk '{print $3}'`
        fi
      fi
      if [ "$package_mode" = "install" ]; then
        if [ "$linux_dist" = "redhat" ]; then
          yum -y install $package_check
        fi
        if [ "$linux_dist" = "suse" ]; then
          zypper install $package_check
        fi
        if [ "$linux_dist" = "debian" ]; then
          apt-get install $package_check
        fi
      fi
      if [ "$package_mode" = "uninstall" ]; then
        if [ "$linux_dist" = "redhat" ]; then
          rpm -e $package_check
        fi
        if [ "$linux_dist" = "suse" ]; then
          zypper remove $package_check
        fi
        if [ "$linux_dist" = "debian" ]; then
          apt-get purge $package_check
        fi
      fi
      if [ "$package_mode" = "restore" ]; then
        if [ -f "$restore_file" ]; then
          restore_check=`cat $restore_file |grep $package_check |awk '{print $2}'`
          if [ "$restore_check" = "$package_check" ]; then
            package_action=`cat $restore_file |grep $package_check |awk '{print $1}'`
            echo "Restoring: Package $package_action to $package_action"
            if [ "$package_action" = "Installed" ]; then
              if [ "$linux_dist" = "redhat" ]; then
                rpm -e $package_check
              fi
              if [ "$linux_dist" = "debian" ]; then
                apt-get purge $package_check
              fi
              if [ "$linux_dist" = "suse" ]; then
                zypper remove $package_check
              fi
            else
              if [ "$linux_dist" = "redhat" ]; then
                yum -y install $package_check
              fi
              if [ "$linux_dist" = "debian" ]; then
                apt-get install $package_check
              fi
              if [ "$linux_dist" = "suse" ]; then
                zypper install $package_check
              fi
            fi
          fi
        fi
      fi
    fi
  fi
}

# audit_system_accounting
#
# System accounting gathers baseline system data (CPU utilization, disk I/O, 
# etc.) every 20 minutes. The data may be accessed with the sar command, or by 
# reviewing the nightly report files named /var/adm/sa/sar*.
# Note: The sys id must be added to /etc/cron.allow to run the system 
# accounting commands..
# Once a normal baseline for the system has been established, abnormalities 
# can be investigated to detect unauthorized activity such as CPU-intensive 
# jobs and activity outside of normal usage hours.
#.

audit_system_accounting () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "System Accounting"
    total=`expr $total + 1`
    log_file="sysstat.log"
    audit_linux_package check sysstat
    if [ "$linux_dist" = "debian" ]; then
      check_file="/etc/default/sysstat"
      funct_file_value $check_file ENABLED eq true hash
    fi
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  System accounting is enabled"
    fi
    if [ "$package_name" != "sysstat" ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   System accounting not enabled [$score]"
        funct_verbose_message "" fix
        if [ "$linux_dist" = "redhat" ]; then
          funct_verbose_message "yum -y install $package_check" fix
        fi
        if [ "$linux_dist" = "redhat" ]; then
          funct_verbose_message "zypper install $package_check" fix
        fi
        if [ "$linux_dist" = "debian" ]; then
          funct_verbose_message "apt-get install $package_check" fix
        fi
        funct_verbose_message "" fix
      fi
      if [ "$audit_mode" = 0 ]; then
        echo "Setting:   System Accounting to enabled"
        log_file="$work_dir/$log_file"
        echo "Installed sysstat" >> $log_file
        audit_linux_package install sysstat
      fi
    else
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score + 1`
        echo "Secure:    System accounting enabled [$score]"
      fi
      if [ "$audit_mode" = 2 ]; then
        restore_file="$restore_dir/$log_file"
        audit_linux_package restore sysstat $restore_file
      fi
    fi
    check_file="/etc/audit/audit.rules"
    # Set failure mode to syslog notice
    funct_append_file $check_file "-f 1" hash
    # Things that could affect time
    funct_append_file $check_file "-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time-change" hash
    if [ "$os_platform" = "x86_64" ]; then
      funct_append_file $check_file "-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time-change" hash
    fi
    funct_append_file $check_file "-a always,exit -F arch=b32 -S clock_settime -k time-change" hash
    if [ "$os_platform" = "x86_64" ]; then
      funct_append_file $check_file "-a always,exit -F arch=b64 -S clock_settime -k time-change" hash
    fi
    funct_append_file $check_file "-w /etc/localtime -p wa -k time-change" hash
    # Things that affect identity
    funct_append_file $check_file "-w /etc/group -p wa -k identity" hash
    funct_append_file $check_file "-w /etc/passwd -p wa -k identity" hash
    funct_append_file $check_file "-w /etc/gshadow -p wa -k identity" hash
    funct_append_file $check_file "-w /etc/shadow -p wa -k identity" hash
    funct_append_file $check_file "-w /etc/security/opasswd -p wa -k identity" hash
    # Things that could affect system locale
    funct_append_file $check_file "-a exit,always -F arch=b32 -S sethostname -S setdomainname -k system-locale" hash
    if [ "$os_platform" = "x86_64" ]; then
      funct_append_file $check_file "-a exit,always -F arch=b64 -S sethostname -S setdomainname -k system-locale" hash
    fi
    funct_append_file $check_file "-w /etc/issue -p wa -k system-locale" hash
    funct_append_file $check_file "-w /etc/issue.net -p wa -k system-locale" hash
    funct_append_file $check_file "-w /etc/hosts -p wa -k system-locale" hash
    funct_append_file $check_file "-w /etc/sysconfig/network -p wa -k system-locale" hash
    # Things that could affect MAC policy
    funct_append_file $check_file "-w /etc/selinux/ -p wa -k MAC-policy" hash
    # Things that could affect logins
    funct_append_file $check_file "-w /var/log/faillog -p wa -k logins" hash
    funct_append_file $check_file "-w /var/log/lastlog -p wa -k logins" hash
    #- Process and session initiation (unsuccessful and successful)
    funct_append_file $check_file "-w /var/run/utmp -p wa -k session" hash
    funct_append_file $check_file "-w /var/log/btmp -p wa -k session" hash
    funct_append_file $check_file "-w /var/log/wtmp -p wa -k session" hash
    #- Discretionary access control permission modification (unsuccessful and successful use of chown/chmod)
    funct_append_file $check_file "-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=500 -F auid!=4294967295 -k perm_mod" hash
    if [ "$os_platform" = "x86_64" ]; then
      funct_append_file $check_file "-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=500 -F auid!=4294967295 -k perm_mod" hash
    fi
    funct_append_file $check_file "-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=500 - F auid!=4294967295 -k perm_mod" hash
    if [ "$os_platform" = "x86_64" ]; then
      funct_append_file $check_file "-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=500 - F auid!=4294967295 -k perm_mod" hash
    fi
    funct_append_file $check_file "-a always,exit -F arch=b32 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=500 -F auid!=4294967295 -k perm_mod" hash
    if [ "$os_platform" = "x86_64" ]; then
      funct_append_file $check_file "-a always,exit -F arch=b64 -S setxattr -S lsetxattr -S fsetxattr -S removexattr -S lremovexattr -S fremovexattr -F auid>=500 -F auid!=4294967295 -k perm_mod" hash
    fi
    #- Unauthorized access attempts to files (unsuccessful)
    funct_append_file $check_file "-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=500 -F auid!=4294967295 -k access" hash
    funct_append_file $check_file "-a always,exit -F arch=b32 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=500 -F auid!=4294967295 -k access" hash
    if [ "$os_platform" = "x86_64" ]; then
      funct_append_file $check_file "-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EACCES -F auid>=500 -F auid!=4294967295 -k access" hash
      funct_append_file $check_file "-a always,exit -F arch=b64 -S creat -S open -S openat -S truncate -S ftruncate -F exit=-EPERM -F auid>=500 -F auid!=4294967295 -k access" hash
    fi
    #- Use of privileged commands (unsuccessful and successful)
    #funct_append_file $check_file "-a always,exit -F path=/bin/ping -F perm=x -F auid>=500 -F auid!=4294967295 -k privileged" hash
    funct_append_file $check_file "-a always,exit -F arch=b32 -S mount -F auid>=500 -F auid!=4294967295 -k export" hash
    if [ "$os_platform" = "x86_64" ]; then
      funct_append_file $check_file "-a always,exit -F arch=b64 -S mount -F auid>=500 -F auid!=4294967295 -k export" hash
    fi
    #- Files and programs deleted by the user (successful and unsuccessful)
    funct_append_file $check_file "-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=500 -F auid!=4294967295 -k delete" hash
    if [ "$os_platform" = "x86_64" ]; then
      funct_append_file $check_file "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=500 -F auid!=4294967295 -k delete" hash
    fi
    #- All system administration actions
    funct_append_file $check_file "-w /etc/sudoers -p wa -k scope" hash
    funct_append_file $check_file "-w /etc/sudoers -p wa -k actions" hash
    #- Make sue kernel module loading and unloading is recorded
    funct_append_file $check_file "-w /sbin/insmod -p x -k modules" hash
    funct_append_file $check_file "-w /sbin/rmmod -p x -k modules" hash
    funct_append_file $check_file "-w /sbin/modprobe -p x -k modules" hash
    funct_append_file $check_file "-a always,exit -S init_module -S delete_module -k modules" hash
    #- Tracks successful and unsuccessful mount commands
    if [ "$os_platform" = "x86_64" ]; then
      funct_append_file $check_file "-a always,exit -F arch=b64 -S mount -F auid>=500 -F auid!=4294967295 -k mounts" hash
    fi
    funct_append_file $check_file "-a always,exit -F arch=b32 -S mount -F auid>=500 -F auid!=4294967295 -k mounts" hash
    #funct_append_file $check_file "" hash
    #funct_append_file $check_file "" hash
    funct_append_file $check_file "" hash
    #- Manage and retain logs
    funct_append_file $check_file "space_left_action = email" hash
    funct_append_file $check_file "action_mail_acct = email" hash
    funct_append_file $check_file "admin_space_left_action = email" hash
    #funct_append_file $check_file "" hash
    funct_append_file $check_file "max_log_file = MB" hash
    funct_append_file $check_file "max_log_file_action = keep_logs" hash
    #- Make file immutable - MUST BE LAST!
    funct_append_file $check_file "-e 2" hash
    service_name="sysstat"
    funct_chkconfig_service $service_name 3 on
    funct_chkconfig_service $service_name 5 on
    service_bname="auditd"
    funct_chkconfig_service $service_name 3 on
    funct_chkconfig_service $service_name 5 on
  fi
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      cron_file="/var/spool/cron/crontabs/sys"
      funct_verbose_message "System Accounting"
			if [ -f "$check_file" ]; then
	      sar_check=`cat $check_file |grep -v "^#" |grep "sa2"`
      fi
	    total=`expr $total + 1`
	    if [ `expr "$sar_check" : "[A-z]"` != 1 ]; then
	      if [ "$audit_mode" = 1 ]; then
	        score=`expr $score - 1`
	        echo "Warning:   System Accounting is not enabled [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "echo \"0,20,40 * * * * /usr/lib/sa/sa1\" >> $check_file" fix
          funct_verbose_message "echo \"45 23 * * * /usr/lib/sa/sa2 -s 0:00 -e 23:59 -i 1200 -A\" >> $check_file" fix
          funct_verbose_message "chown sys:sys /var/adm/sa/*" fix
          funct_verbose_message "chmod go-wx /var/adm/sa/*" fix
          funct_verbose_message "" fix
	      fi
	      if [ "$audit_mode" = 0 ]; then
	        echo "Setting:   System Accounting to enabled"
	        if [ ! -f "$log_file" ]; then
	          echo "Saving:    File $check_file to $work_dir$check_file"
	          find $check_file | cpio -pdm $work_dir 2> /dev/null
	        fi
	        echo "0,20,40 * * * * /usr/lib/sa/sa1" >> $check_file
	        echo "45 23 * * * /usr/lib/sa/sa2 -s 0:00 -e 23:59 -i 1200 -A" >> $check_file
	        chown sys:sys /var/adm/sa/* 
	        chmod go-wx /var/adm/sa/*
	        if [ "$os_version" = "10" ]; then
	          pkgchk -f -n -p $check_file 2> /dev/null
	        else
	          pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
	        fi
	      fi
	    else
	      if [ "$audit_mode" = 1 ]; then
	        score=`expr $score + 1`
	        echo "Secure:    System Accounting is already enabled [$score]"
	      fi
	      if [ "$audit_mode" = 2 ]; then
	        funct_restore_file $check_file $restore_dir
	      fi
      fi
    fi
  fi
}

# audit_kernel_accounting
#
# Kernel-level auditing provides information on commands and system calls that 
# are executed on the local system. The audit trail may be reviewed with the 
# praudit command. Note that enabling kernel-level auditing on Solaris disables 
# the automatic mounting of external devices via the Solaris volume manager 
# daemon (vold).
# Kernel-level auditing can consume a large amount of disk space and even cause 
# system performance impact, particularly on heavily used machines. 
#.

audit_kernel_accounting () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      check_file="/etc/system"
			if [ -f "$check_file" ]; then
        funct_verbose_message "Kernel and Process Accounting"
	      check_acc=`cat $check_file |grep -v '^*' |grep 'c2audit:audit_load'`
	      if [ `expr "$check_acc" : "[A-z]"` != 1 ]; then
	        funct_file_value $check_file c2audit colon audit_load star
	        if [ "$audit_mode" = 0 ]; then
	          log_file="$work_dir/bsmconv.log"
	          echo "y" >> $log_file
	          echo "y" | /etc/security/bsmconv
	        fi
	      fi
	      if [ "$audit_mode" = 2 ]; then
	        restore_file="$restore_dir/bsmconv.log"
	        if [ -f "$restore_file" ]; then
	          echo "y" | /etc/security/bsmunconv
	        fi
	      fi
	      check_file="/etc/security/audit_control"
	      funct_file_value $check_file flags colon "lo,ad,cc" hash
	      funct_file_value $check_file naflags colon "lo,ad,ex" hash
	      funct_file_value $check_file minfree colon 20 hash
	      check_file="/etc/security/audit_user"
	      funct_file_value $check_file root colon "lo,ad:no" hash
	    fi
		fi
  fi
}

# audit_daemon_umask
#
# The umask (1) utility overrides the file mode creation mask as specified by 
# the CMASK value in the /etc/default/init file. The most permissive file 
# permission is mode 666 ( 777 for executable files). The CMASK value subtracts 
# from this value. For example, if CMASK is set to a value of 022, files 
# created will have a default permission of 644 (755 for executables). 
# See the umask (1) manual page for a more detailed description.
# Note: There are some known bugs in the following daemons that are impacted by 
# changing the CMASK parameter from its default setting: 
# (Note: Current or future patches may have resolved these issues. 
# Consult with your Oracle Support representative)
# 6299083 picld i initialise picld_door file with wrong permissions after JASS
# 4791006 ldap_cachemgr initialise i ldap_cache_door file with wrong permissions
# 6299080 nscd i initialise name_service_door file with wrong permissions after 
# JASS
# The ldap_cachemgr issue has been fixed but the others are still unresolved. 
# While not directly related to this, there is another issue related to 077 
# umask settings:
# 2125481 in.lpd failed to print files when the umask is set 077
# Set the system default file creation mask (umask) to at least 022 to prevent 
# daemon processes from creating world-writable files by default. The NSA and 
# DISA recommend a more restrictive umask values of 077 (Note: The execute bit 
# only applies to executable files). This may cause problems for certain 
# applications- consult vendor documentation for further information. 
# The default setting for Solaris is 022.
#.

audit_daemon_umask () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "11" ]; then
      funct_verbose_message "Daemon Umask"
      umask_check=`svcprop -p umask/umask svc:/system/environment:init`
      umask_value="022"
      log_file="umask.log"
      total=`expr $total + 1`
      if [ "$umask_check" != "$umask_value" ]; then
        log_file="$work_dir/$log_file"
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Default service file creation mask not set to $umask_value [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "svccfg -s svc:/system/environment:init setprop umask/umask = astring:  \"$umask_value\"" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          echo "Setting:   Default service file creation mask to $umask_value"
          if [ ! -f "$log_file" ]; then
            echo "$umask_check" >> $log_file
          fi
          svccfg -s svc:/system/environment:init setprop umask/umask = astring:  "$umask_value"
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Default service file creation mask set to $umask_value [$score]"
        fi
        if [ "$audit_mode" = 2 ]; then
          restore_file="$restore_dir/$log_file"
          if [ -f "$restore_file" ]; then
            restore_value=`cat $restore_file`
            if [ "$restore_value" != "$umask_check" ]; then
              echo "Restoring:  Default service file creation mask to $restore_vaule"
              svccfg -s svc:/system/environment:init setprop umask/umask = astring:  "$restore_value"
            fi
          fi
        fi
      fi
    else
      if [ "$os_version" = "7" ] || [ "$os_version" = "6" ]; then
        funct_verbose_message "Daemon Umask"
        check_file="/etc/init.d/umask.sh"
        funct_file_value $check_file umask space 022 hash
        if [ "$audit_mode" = "0" ]; then
          if [ -f "$check_file" ]; then
            funct_check_perms $check_file 0744 root sys
            for dir_name in /etc/rc?.d; do
              link_file="$dir_name/S00umask"
              if [ ! -f "$link_file" ]; then
                ln -s $check_file $link_file
              fi
            done
          fi
        fi
      else
        check_file="/etc/default/init"
        funct_file_value $check_file CMASK eq 022 hash
      fi
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Daemon Umask"
    check_file="/etc/sysconfig/init"
    funct_file_value $check_file umask space 027 hash
    if [ "$audit_mode" = "0" ]; then
      if [ -f "$check_file" ]; then
        funct_check_perms $check_file 0755 root root
      fi
    fi
  fi
}

# audit_mount_setuid
#
# If the volume manager (vold) is enabled to permit users to mount external 
# devices, the administrator can force these file systems to be mounted with 
# the nosuid option to prevent users from bringing set-UID programs onto the 
# system via CD-ROMs, floppy disks, USB drives or other removable media.
# Removable media is one vector by which malicious software can be introduced 
# onto the system. The risk can be mitigated by forcing use of the nosuid 
# option. Note that this setting is included in the default rmmount.conf file 
# for Solaris 8 and later.
#.

audit_mount_setuid () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      check_file="/etc/rmmount.conf"
			if [ -f "$check_file" ]; then
        funct_verbose_message "# Set-UID on User Monunted Devices"
	      nosuid_check=`cat $check_file |grep -v "^#" |grep "\-o nosuid"`
	      log_file="$work_dir/$check_file"
	      total=`expr $total + 1`
	      if [ `expr "$nosuid_check" : "[A-z]"` != 1 ]; then
	        if [ "$audit_mode" = 1 ]; then
	          score=`expr $score - 1`
	          echo "Warning:   Set-UID not restricted on user mounted devices [$score]"
	        fi
	        if [ "$audit_mode" = 0 ]; then
	          echo "Setting:   Set-UID restricted on user mounted devices"
	          funct_backup_file $check_file
	          funct_append_file $check_file "mount * hsfs udfs ufs -o nosuid" hash
	        fi
	      else
	        if [ "$audit_mode" = 1 ]; then
	          score=`expr $score + 1`
	          echo "Secure:    Set-UID not restricted on user mounted devices [$score]"
	        fi
	        if [ "$audit_mode" = 2 ]; then
	          funct_restore_file $check_file $restore_dir
	        fi
				fi
      fi
    fi
  fi
}

# audit_unconfined_daemons
#
# Unconfined daemons.
#.

audit_unconfined_daemons () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Unconfined Daemons"
    daemon_check=`ps -eZ | egrep "initrc" | egrep -vw "tr|ps|egrep|bash|awk" | tr ':' ' ' | awk '{ print $NF }'`
    total=`expr $total + 1`
    if [ "$daemon_check" = "" ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   Unconfined daemons $daemon_check [$score]"
      fi
    else
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score + 1`
        echo "Secure:    No unconfined daemons [$score]"
      fi
    fi
  fi
}

# audit_sulogin
#
# Check single user mode requires password.
#
# Permissions on /etc/inittab.
#
# With remote console access it is possible to gain access to servers as though
# you were in front of them, therefore entering single user mode should require
# a password.
#.

audit_sulogin () {
  if [ "$os_name" = "Linux" ]; then
    check_file="/etc/inittab"
    if [ -f "$check_file" ]; then
      funct_verbose_message "Single User Mode Requires Password"
      sulogin_check=`grep -l sulogin $check_file`
      total=`expr $total + 1`
      if [ "$sulogin_check" = "" ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   No Authentication required for single usermode [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "cat $check_file |awk '{ print }; /^id:[0123456sS]:initdefault:/ { print \"~~:S:wait:/sbin/sulogin\" }' > $temp_file" fix
          funct_verbose_message "cat $temp_file > $check_file" fix
          funct_verbose_message "rm $temp_file" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          echo "Setting:   Single user mode to require authentication"
          funct_backup_file $check_file
          cat $check_file |awk '{ print }; /^id:[0123456sS]:initdefault:/ { print "~~:S:wait:/sbin/sulogin" }' > $temp_file
          cat $temp_file > $check_file
          rm $temp_file
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Single usermode requires authentication [$score]"
        fi
        if [ "$audit_mode" = 2 ]; then
          funct_restore_file $check_file $restore_dir
        fi
        funct_check_perms $check_file 0600 root root
      fi
      check_file="/etc/sysconfig/init"
      funct_file_value $check_file SINGLE eq "/sbin/sulogin" hash
      funct_file_value $check_file PROMPT eq no hash
      funct_check_perms $check_file 0600 root root
    fi
  fi
}

# audit_mount_nodev
#
# Check filesystems are mounted with nodev
#
# Prevents device files from being created on filesystems where they should
# not be created. This can stop possible vectors of attack and escalated
# privileges.
# Ignore / and /boot.
#.

audit_mount_nodev () {  
  if [ "$os_name" = "Linux" ]; then
    check_file="/etc/fstab"
		if [ -e "$check_file" ]; then
      funct_verbose_message "File Systems mounted with nodev"
	    if [ "$audit_mode" != "2" ]; then
	      nodev_check=`cat $check_file |grep -v "^#" |egrep "ext2|ext3" |grep -v '/ ' |grep -v '/boot' |head -1 |wc -l`
	      total=`expr $total + 1`
	      if [ "$nodev_check" = 1 ]; then
	        if [ "$audit_mode" = 1 ]; then
	          score=`expr $score - 1`
	          echo "Warning:   Found filesystems that should be mounted nodev [$score]"
            funct_verbose_message "" fix
            funct_verbose_message "cat $check_file | awk '( $3 ~ /^ext[23]$/ && $2 != \"/\" ) { $4 = $4 \",nodev\" }; { printf \"%-26s %-22s %-8s %-16s %-1s %-1s\n\",$1,$2,$3,$4,$5,$6 }' > $temp_file" fix
            funct_verbose_message "cat $temp_file > $check_file" fix
            funct_verbose_message "rm $temp_file" fix
            funct_verbose_message "" fix
	        fi
	        if [ "$audit_mode" = 0 ]; then
	          echo "Setting:   Setting nodev on filesystems"
	          funct_backup_file $check_file
	          cat $check_file | awk '( $3 ~ /^ext[23]$/ && $2 != "/" ) { $4 = $4 ",nodev" }; { printf "%-26s %-22s %-8s %-16s %-1s %-1s\n",$1,$2,$3,$4,$5,$6 }' > $temp_file
	          cat $temp_file > $check_file
	          rm $temp_file
	        fi
	      else
	        if [ "$audit_mode" = 1 ]; then
	          score=`expr $score + 1`
	          echo "Secure:    No filesystem that should be mounted with nodev [$score]"
	        fi
	        if [ "$audit_mode" = 2 ]; then
	          funct_restore_file $check_file $restore_dir
	        fi
	      fi
	    fi
	    funct_check_perms $check_file 0644 root root
		fi
  fi
}

# audit_mount_fdi
#
# User mountable file systems on Linux.
#
# This can stop possible vectors of attack and escalated privileges.
#.

audit_mount_fdi () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "User Mountable Filesystems"
    check_dir="/usr/share/hal/fdi/95userpolicy"
    if [ -e "$check_dir" ]; then
      check_file="$check_dir/floppycdrom.fdi"
    else
      check_dir="/usr/share/hal/fdi/policy/20thirdparty"
      check_file="$check_dir/floppycdrom.fdi"
    fi
    if [ -d "$check_dir" ]; then
      if [ ! -f "$check_file" ]; then
        touch $check_file
        chmod 640 $check_file
        chown root:root $check_file
      fi
    fi
    if [ -f "$check_file" ]; then
      if [ "$audit_mode" != "2" ]; then
        fdi_check=`cat $check_file |grep -v "Default policies" |head -1 |wc -l`
        total=`expr $total + 1`
        if [ "$fdi_check" = 1 ]; then
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score - 1`
            echo "Warning:   User mountable filesystems enabled [$score]"
            funct_verbose_message "" fix
            funct_verbose_message "echo '<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?> <!-- -*- SGML -*- --> >' > $temp_file" fix
            funct_verbose_message "echo '<deviceinfo version=\"0.2\">' >> $temp_file" fix
            funct_verbose_message "echo '  <!-- Default policies merged onto computer root object -->' >> $temp_file" fix
            funct_verbose_message "echo '  <device>' >> $temp_file" fix
            funct_verbose_message "echo '    <match key=\"info.udi\" string=\"/org/freedesktop/Hal/devices/computer\">' >> $temp_file" fix
            funct_verbose_message "echo '      <merge key=\"storage.policy.default.mount_option.nodev\" type=\"bool\">true</merge>' >> $temp_file" fix
            funct_verbose_message "echo '      <merge key=\"storage.policy.default.mount_option.nosuid\" type=\"bool\">true</merge>' >> $temp_file" fix
            funct_verbose_message "echo '    </match>' >> $temp_file" fix
            funct_verbose_message "echo '  </device>' >> $temp_file" fix
            funct_verbose_message "echo '</deviceinfo>' >> $temp_file" fix
            funct_verbose_message "cat $temp_file > $check_file" fix
            funct_verbose_message "rm $temp_file" fix
            funct_verbose_message "" fix
          fi
          if [ "$audit_mode" = 0 ]; then
            echo "Setting:   Disabling user mountable filesystems"
            funct_backup_file $check_file
            echo '<?xml version="1.0" encoding="ISO-8859-1"?> <!-- -*- SGML -*- --> >' > $temp_file
            echo '<deviceinfo version="0.2">' >> $temp_file
            echo '  <!-- Default policies merged onto computer root object -->' >> $temp_file
            echo '  <device>' >> $temp_file
            echo '    <match key="info.udi" string="/org/freedesktop/Hal/devices/computer">' >> $temp_file
            echo '      <merge key="storage.policy.default.mount_option.nodev" type="bool">true</merge>' >> $temp_file
            echo '      <merge key="storage.policy.default.mount_option.nosuid" type="bool">true</merge>' >> $temp_file
            echo '    </match>' >> $temp_file
            echo '  </device>' >> $temp_file
            echo '</deviceinfo>' >> $temp_file
            cat $temp_file > $check_file
            rm $temp_file
          fi
        else
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    User mountable filesystems disabled [$score]"
          fi
          if [ "$audit_mode" = 2 ]; then
            funct_restore_file $check_file $restore_dir
          fi
        fi
      fi
    fi
    funct_check_perms $check_file 0640 root root
  fi
}

# audit_sticky_bit
#
# When the so-called sticky bit (set with chmod +t) is set on a directory, 
# then only the owner of a file may remove that file from the directory 
# (as opposed to the usual behavior where anybody with write access to that 
# directory may remove the file).
# Setting the sticky bit prevents users from overwriting each others files, 
# whether accidentally or maliciously, and is generally appropriate for most 
# world-writable directories (e.g. /tmp). However, consult appropriate vendor 
# documentation before blindly applying the sticky bit to any world writable 
# directories found in order to avoid breaking any application dependencies 
# on a given directory.
#.

audit_sticky_bit () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "World Writable Directories and Sticky Bits"
    total=`expr $total + 1`
    if [ "$os_version" = "10" ]; then
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  Sticky bits set on world writable directories [This may take a while]"
      fi
      log_file="$work_dir/sticky_bits"
      for check_dir in `find / \( -fstype nfs -o -fstype cachefs \
        -o -fstype autofs -o -fstype ctfs \
        -o -fstype mntfs -o -fstype objfs \
        -o -fstype proc \) -prune -o -type d \
        \( -perm -0002 -a ! -perm -1000 \) -print`; do
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Sticky bit not set on $check_dir [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "chmod +t $check_dir" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          echo "Setting:   Sticky bit on $check_dir"
          chmod +t $check_dir
          echo "$check_dir" >> $log_file
        fi
      done
      if [ "$audit_mode" = 2 ]; then
        restore_file="$restore_dir/sticky_bits"
        if [ -f "$restore_file" ]; then
          for check_dir in `cat $restore_file`; do
            if [ -d "$check_dir" ]; then
              echo "Restoring:  Removing sticky bit from $check_dir"
              chmod -t $check_dir
            fi
          done
        fi
      fi
    fi
  fi
}

# audit_selinux
#
# Make sure SELinux is configured appropriately.
#.

audit_selinux () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "SELinux"
    check_file="/etc/selinux/config"
    funct_file_value $check_file SELINUX eq enforcing hash
    funct_file_value $check_file SELINUXTYPE eq targeted hash
  fi
}

# audit_yum_conf
#
# Make sure GPG checks are enabled for yum so that malicious sofware can not
# be installed.
#.

audit_yum_conf () {
  if [ "$os_name" = "Linux" ]; then
    if [ "$linux_dist" = "redhat" ]; then
      funct_verbose_message "Yum Configuration"
      check_file="/etc/yum.conf"
      funct_file_value $check_file gpgcheck eq 1 hash
    fi
  fi
}

# audit_ssh_config
#
# Configure SSH
# SSH Protocol to 2
# SSH X11Forwarding
# SSH MaxAuthTries to 3
# SSH MaxAuthTriesLog to 0
# SSH IgnoreRhosts to yes
# SSH RhostsAuthentication to no
# SSH RhostsRSAAuthentication to no
# SSH root login
# SSH PermitEmptyPasswords to no
# SSH Banner
# Warning Banner for the SSH Service
#
# SSH is a secure, encrypted replacement for common login services such as 
# telnet, ftp, rlogin, rsh, and rcp.
# It is strongly recommended that sites abandon older clear-text login 
# protocols and use SSH to prevent session hijacking and sniffing of 
# sensitive data off the network. Most of these settings are the default 
# in Solaris 10 with the following exceptions:
# MaxAuthTries (default is 6) 
# MaxAuthTriesLog (default is 3) 
# Banner (commented out) 
# X11Forwarding (default is "yes")
#
# SSH supports two different and incompatible protocols: SSH1 and SSH2. 
# SSH1 was the original protocol and was subject to security issues. 
# SSH2 is more advanced and secure.
# Secure Shell version 2 (SSH2) is more secure than the legacy SSH1 version, 
# which is being deprecated.
#
# The X11Forwarding parameter provides the ability to tunnel X11 traffic 
# through the connection to enable remote graphic connections.
# Disable X11 forwarding unless there is an operational requirement to use 
# X11 applications directly. There is a small risk that the remote X11 servers 
# of users who are logged in via SSH with X11 forwarding could be compromised 
# by other users on the X11 server. Note that even if X11 forwarding is disabled 
# that users can may be able to install their own forwarders.
#
# The MaxAuthTries paramener specifies the maximum number of authentication 
# attempts permitted per connection. The default value is 6.
# Setting the MaxAuthTries parameter to a low number will minimize the risk of 
# successful brute force attacks to the SSH server.
#
# The MaxAuthTriesLog parameter specifies the maximum number of failed 
# authorization attempts before a syslog error message is generated. 
# The default value is 3.
# Setting this parameter to 0 ensures that every failed authorization is logged.
#
# The IgnoreRhosts parameter specifies that .rhosts and .shosts files will not 
# be used in RhostsRSAAuthentication or HostbasedAuthentication.
# Setting this parameter forces users to enter a password when authenticating 
# with SSH.
# 
# The RhostsAuthentication parameter specifies if authentication using rhosts 
# or /etc/hosts.equiv is permitted. The default is no.
# Rhosts authentication is insecure and should not be permitted.
# Note that this parameter only applies to SSH protocol version 1.
#
# The RhostsRSAAuthentication parameter specifies if rhosts or /etc/hosts.equiv 
# authentication together with successful RSA host authentication is permitted. 
# The default is no.
# Rhosts authentication is insecure and should not be permitted, even with RSA 
# host authentication.
#
# The PermitRootLogin parameter specifies if the root user can log in using 
# ssh(1). The default is no.
# The root user must be restricted from directly logging in from any location 
# other than the console.
#
# The PermitEmptyPasswords parameter specifies if the server allows login to 
# accounts with empty password strings.
# All users must be required to have a password.
#
# The Banner parameter specifies a file whose contents must sent to the remote 
# user before authentication is permitted. By default, no banner is displayed.
# Banners are used to warn connecting users of the particular site's policy 
# regarding connection. Consult with your legal department for the appropriate 
# warning banner for your site.
#.

audit_ssh_config () {
  if [ "$os-name" = "SunOS" ] || [ "$os_name" = "Linux" ] || [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "SSH Configuration"
    if [ "$os_name" = "Darwin" ]; then
      check_file="/etc/sshd_config"
      funct_file_value $check_file GSSAPIAuthentication space yes hash
      funct_file_value $check_file GSSAPICleanupCredentials space yes hash
    else
      check_file="/etc/ssh/sshd_config"
    fi
    #funct_file_value $check_file Host space "*" hash
    funct_file_value $check_file Protocol space 2 hash
    funct_file_value $check_file X11Forwarding space no hash
    funct_file_value $check_file MaxAuthTries space 3 hash
    funct_file_value $check_file MaxAuthTriesLog space 0 hash
    funct_file_value $check_file RhostsAuthentication space no hash
    funct_file_value $check_file IgnoreRhosts space yes hash
    funct_file_value $check_file StrictModes space yes hash
    funct_file_value $check_file AllowTcpForwarding space no hash
    funct_file_value $check_file ServerKeyBits space 1024 hash
    funct_file_value $check_file GatewayPorts space no hash
    funct_file_value $check_file RhostsRSAAuthentication space no hash
    funct_file_value $check_file PermitRootLogin space no hash
    funct_file_value $check_file PermitEmptyPasswords space no hash
    funct_file_value $check_file PermitUserEnvironment space no hash
    funct_file_value $check_file HostbasedAuthentication space no hash
    funct_file_value $check_file Banner space /etc/issue hash
    funct_file_value $check_file PrintMotd space no hash
    funct_file_value $check_file ClientAliveInterval space 300 hash
    funct_file_value $check_file ClientAliveCountMax space 0 hash
    funct_file_value $check_file LogLevel space VERBOSE hash
    funct_file_value $check_file RSAAuthentication space no hash
    funct_file_value $check_file UsePrivilegeSeparation space yes hash
    funct_file_value $check_file LoginGraceTime space 120 hash
    # Check for kerberos
    check_file="/etc/krb5/krb5.conf"
    if [ -f "$check_file" ]; then
      admin_check=`cat $check_file |grep -v '^#' |grep "admin_server" |cut -f2 -d= |sed 's/ //g' |wc -l |sed 's/ //g'`
      if [ "$admin_server" != "0" ]; then
        check_file="/etc/ssh/sshd_config"
        funct_file_value $check_file GSSAPIAuthentication space yes hash
        funct_file_value $check_file GSSAPIKeyExchange space yes hash
        funct_file_value $check_file GSSAPIStoreDelegatedCredentials space yes hash
        funct_file_value $check_file UsePAM space yes hash
        #funct_file_value $check_file Host space "*" hash
      fi
    fi
    #
    # Additional options:
    # Review these options if required, eg using PAM or Kerberos/AD
    #
    # 
    #
    # Enable on new machines
    # funct_file_value $check_file Cipher space "aes128-ctr,aes192-ctr,aes256-ctr" hash
  fi
}

# audit_serial_login
#
# The pmadm command provides service administration for the lower level of the 
# Service Access Facility hierarchy and can be used to disable the ability to 
# login on a particular port.
# By disabling the login: prompt on the system serial devices, unauthorized 
# users are limited in their ability to gain access by attaching modems, 
# terminals, and other remote access devices to these ports. Note that this 
# action may safely be performed even if console access to the system is 
# provided via the serial ports, because the login: prompt on the console 
# device is provided through a different mechanism.
#.

audit_serial_login () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Login on Serial Ports"
    total=`expr $total + 1`
    if [ "$os_version" = "10" ]; then
      serial_test=`pmadm -L |egrep "ttya|ttyb" |cut -f4 -d ":" |grep "ux" |wc -l`
      log_file="$work_dir/pmadm.log"
      if [ `expr "$serial_test" : "2"` = 1 ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Serial port logins disabled [$score]"
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Serial port logins not disabled [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "pmadm -d -p zsmon -s ttya" fix
          funct_verbose_message "pmadm -d -p zsmon -s ttyb" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          echo "Setting:   Serial port logins to disabled"
          echo "ttya,ttyb" >> $log_file
          pmadm -d -p zsmon -s ttya
          pmadm -d -p zsmon -s ttyb
        fi
      fi
      if [ "$audit_mode" = 2 ]; then
        restore_file="$restore_dir/pmadm.log"
        if [ -f "$restore_file" ]; then
          echo "Restoring: Serial port logins to enabled"
          pmadm -e -p zsmon -s ttya
          pmadm -e -p zsmon -s ttyb
        fi
      fi
    fi
  fi
}

# audit_nobody_rpc 
#
# The keyserv process, if enabled, stores user keys that are utilized with 
# Sun's Secure RPC mechanism.
# The action listed prevents keyserv from using default keys for the nobody 
# user, effectively stopping this user from accessing information via Secure 
# RPC.
#.

audit_nobody_rpc () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "Nobody Access for RPC Encryption Key Storage Service"
      check_file="/etc/default/keyserv"
      funct_file_value $check_file ENABLE_NOBODY_KEYS eq NO hash
    fi
  fi
}

# audit_pam_rhosts
#
# Used in conjunction with the BSD-style "r-commands" (rlogin, rsh, rcp), 
# .rhosts files implement a weak form of authentication based on the network 
# address or host name of the remote computer (which can be spoofed by a 
# potential attacker to exploit the local system).
# Disabling .rhosts support helps prevent users from subverting the system's 
# normal access control mechanisms.
#.

audit_pam_rhosts () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "PAM RHosts Configuration"
    check_file="/etc/pam.conf"
    total=`expr $total + 1`
    if [ "$audit_mode" = 2 ]; then
      funct_restore_file $check_file $restore_dir
    else
			if [ -f "$check_file" ]; then
	      echo "Checking:  Rhost authentication disabled in $check_file"
	      pam_check=`cat $check_file | grep -v "^#" |grep "pam_rhosts_auth" |head -1 |wc -l`
	      if [ "$pam_check" = "1" ]; then
	        if [ "$audit_mode" = 1 ]; then
	          score=`expr $score -1`
	          echo "Warning:   Rhost authentication enabled in $check_file [$score]"
            funct_verbose_message "" fix
            funct_verbose_message "sed -e 's/^.*pam_rhosts_auth/#&/' < $check_file > $temp_file" fix
            funct_verbose_message "cat $temp_file > $check_file" fix
            funct_verbose_message "rm $temp_file" fix
            funct_verbose_message "" fix
	        else
	          log_file="$work_dir$check_file"
	          if [ ! -f "$log_file" ]; then
	            echo "Saving:    File $check_file to $work_dir$check_file"
	            find $check_file | cpio -pdm $work_dir 2> /dev/null
	          fi
	          echo "Setting:   Rhost authentication to disabled in $check_file"
	          sed -e 's/^.*pam_rhosts_auth/#&/' < $check_file > $temp_file
	          cat $temp_file > $check_file
	          rm $temp_file
	          if [ "$os_version" != "11" ]; then
	            pkgchk -f -n -p $check_file 2> /dev/null
	          else
	            pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
	          fi
	        fi
	      else
	        if [ "$audit_mode" = 1 ]; then
	          score=`expr $score + 1`
	          echo "Secure:    Rhost authentication disabled in $check_file [$score]"
	        fi
	      fi
			fi
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "PAM .rhosts Configuration"
    for check_file in `ls /etc/pam.d/*`; do
      if [ "$audit_mode" = 2 ]; then
        funct_restore_file $check_file $restore_dir
      else
        echo "Checking:  Rhost authentication disabled in $check_file [$score]"
        pam_check=`cat $check_file | grep -v "^#" |grep "rhosts_auth" |head -1 |wc -l`
        if [ "$pam_check" = "1" ]; then
          if [ "$audit_mode" = 1 ]; then
            total=`expr $total + 1`
            score=`expr $score - 1`
            echo "Warning:   Rhost authentication enabled in $check_file [$score]"
            funct_verbose_message "" fix
            funct_verbose_message "sed -e 's/^.*rhosts_auth/#&/' < $check_file > $temp_file" fix
            funct_verbose_message "cat $temp_file > $check_file" fix
            funct_verbose_message "rm $temp_file" fix
            funct_verbose_message "" fix
          fi
          if [ "$audit_mode" = 0 ]; then
            funct_backup_file $check_file
            echo "Setting:   Rhost authentication to disabled in $check_file"
            sed -e 's/^.*rhosts_auth/#&/' < $check_file > $temp_file
            cat $temp_file > $check_file
            rm $temp_file
          fi
        else
          if [ "$audit_mode" = 1 ]; then
            total=`expr $total + 1`
            score=`expr $score + 1`
            echo "Secure:    Rhost authentication disabled in $check_file [$score]"
          fi
        fi
      fi
    done
  fi
}

# audit_old_users
#
# Audit users to check for accounts that have not been logged into etc
#.

audit_old_users () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ] || ["$os_name" = "Darwin" ]; then
    never_count=0
    if [ "$audit_mode" = 2 ]; then
      check_file="/etc/shadow"
      funct_restore_file $check_file $restore_dir
    else
      check_file="/etc/passwd"
      for user_name in `cat $check_file |grep -v "/usr/bin/false" |egrep -v "^halt|^shutdown|^root|^sync|/sbin/nologin" |cut -f1 -d:`; do
        check_file="/etc/shadow"
        shadow_field=`cat $check_file |grep "^$user_name:" |cut -f2 -d":" |egrep -v "\*|\!\!|NP|LK|UP"`
        if [ "$shadow_field" != "" ]; then
          login_status=`finger $user_name |grep "Never logged in" |awk '{print $1}'`
          if [ "$login_status" = "Never" ]; then
            if [ "$audit_mode" = 1 ]; then
              never_count=`expr $never_count + 1`
              total=`expr $total + 1`
              score=`expr $score - 1`
              echo "Warning:   User $user_name has never logged in and their account is not locked [$score]"
              funct_verbose_message "" fix
              funct_verbose_message "passwd -l $user_name" fix
              funct_verbose_message "" fix
            fi
            if [ "$audit_mode" = 0 ]; then
              funct_backup_file $check_file
              echo "Setting:   User $user_name to locked"
              passwd -l $user_name
            fi
          fi
        fi
      done
      if [ "$never_count" = 0 ]; then
        if [ "$audit_mode" = 1 ]; then
          total=`expr $total + 1`
          score=`expr $score + 1`
          echo "Secure:    No user has never logged in and their account is not locked [$score]"
        fi
      fi
    fi
  fi
}

# audit_ftp_users
#
# If FTP is permitted to be used on the system, the file /etc/ftpd/ftpusers is 
# used to specify a list of users who are not allowed to access the system via 
# FTP.
# FTP is an old and insecure protocol that transfers files and credentials in 
# clear text and is better replaced by using sftp instead. However, if it is 
# permitted for use in your environment, it is important to ensure that the 
# default "system" accounts are not permitted to transfer files via FTP, 
# especially the root account. Consider also adding the names of other 
# privileged or shared accounts that may exist on your system such as user 
# oracle and the account which your Web server process runs under.
#.

audit_ftp_users () {
  if [ "$os_name" = "SunOS" ]; then
    check_file=$1
    total=`expr $total + 1`
    for user_name in adm bin daemon gdm listen lp noaccess \
      nobody nobody4 nuucp postgres root smmsp svctag \
      sys uucp webserverd; do
      user_check=`cat /etc/passwd |cut -f1 -d":" |grep "^$user_name$"`
      if [ `expr "$user_check" : "[A-z]"` = 1 ]; then
        ftpuser_check=`cat $check_file |grep -v '^#' |grep "^$user_name$"`
        if [ `expr "$ftpuser_check" : "[A-z]"` != 1 ]; then
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score - 1`
            echo "Warning:   User $user_name not in $check_file [$score]"
          fi
          if [ "$audit_mode" = 0 ]; then
            funct_backup_file $check_file
            echo "Setting:   User $user_name to not be allowed ftp access"
            funct_append_file $check_file $user_name hash
          fi
        else
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    User $user_name in $check_file [$score]"
          fi
        fi
      fi
    done
    if [ "$audit_mode" = 2 ]; then
      funct_restore_file $check_file $restore_dir
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    check_file=$1
    total=`expr $total + 1`
    for user_name in root bin daemon adm lp sync shutdown halt mail \
    news uucp operator games nobody; do
      user_check=`cat /etc/passwd |cut -f1 -d":" |grep "^$user_name$"`
      if [ `expr "$user_check" : "[A-z]"` = 1 ]; then
        ftpuser_check=`cat $check_file |grep -v '^#' |grep "^$user_name$"`
        if [ `expr "$ftpuser_check" : "[A-z]"` != 1 ]; then
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score - 1`
            echo "Warning:   User $user_name not in $check_file [$score]"
          fi
          if [ "$audit_mode" = 0 ]; then
            funct_backup_file $check_file
            echo "Setting:   User $user_name to not be allowed ftp access"
            funct_append_file $check_file $user_name hash
          fi
        else
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    User $user_name in $check_file [$score]"
          fi
        fi
      fi
    done
    if [ "$audit_mode" = 2 ]; then
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_ftp_conf
#
# Audit FTP Configuration
#.

audit_ftp_conf () {
  funct_verbose_message "FTP users"
  if [ "$os_name" = "SunOS" ]; then
    audit_ftp_users /etc/ftpd/ftpusers
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_rpm_check vsftpd
    if [ "$rpm_check" = "vsftpd" ]; then
      audit_ftp_users /etc/vsftpd/ftpusers
    fi
  fi
}

# audit_pass_req
#
# Set PASSREQ to YES in /etc/default/login to prevent users from loging on
# without a password
#

audit_pass_req () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message"Delay between Failed Login Attempts"
    check_file="/etc/default/login"
    funct_file_value $check_file PASSREQ eq YES hash
  fi
}


# audit_login_delay
#
# The SLEEPTIME variable in the /etc/default/login file controls the number of 
# seconds to wait before printing the "login incorrect" message when a bad 
# password is provided.
# Delaying the "login incorrect" message can help to slow down brute force 
# password-cracking attacks.
#.

audit_login_delay () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message"Delay between Failed Login Attempts"
    check_file="/etc/default/login"
    funct_file_value $check_file SLEEPTIME eq 4 hash
  fi
}

# audit_cde_screen_lock
#
# The default timeout for keyboard/mouse inactivity is 30 minutes before a 
# password-protected screen saver is invoked by the CDE session manager.
# Many organizations prefer to set the default timeout value to 10 minutes, 
# though this setting can still be overridden by individual users in their 
# own environment.
#.

audit_cde_screen_lock () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Screen Lock for CDE Users"
    for check_file in `ls /usr/dt/config/*/sys.resources 2> /dev/null`; do
      dir_name=`dirname $check_file |sed 's/usr/etc/'`
      if [ ! -d "$dir_name" ]; then
        mkdir -p $dir_name
      fi
      new_file="$dir_name/sys.resources"
      funct_file_value $new_file "dtsession*saverTimeout" colon " 10" star
      funct_file_value $new_file "dtsession*lockTimeout" colon " 10" star
      if [ "$audit_mode" = 0 ]; then
        if [ -f "$new_file" ]; then
          funct_check_perms $new_file 0444 root sys
        fi
      fi
    done
  fi
}

# audit_gnome_screen_lock
#
# The default timeout is 30 minutes of keyboard and mouse inactivity before a 
# password-protected screen saver is invoked by the Xscreensaver application 
# used in the GNOME windowing environment.
# Many organizations prefer to set the default timeout value to 10 minutes, 
# though this setting can still be overridden by individual users in their 
# own environment.
#.

audit_gnome_screen_lock () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Screen Lock for GNOME Users"
    check_file="/usr/openwin/lib/app-defaults/XScreenSaver"
    funct_file_value $check_file "*timeout:" space "0:10:00" bang
    funct_file_value $check_file "*lockTimeout:" space "0:00:00" bang
    funct_file_value $check_file "*lockTimeout:" space "0:00:00" bang
  fi
}

# audit_cron_allow
#
# The cron.allow and at.allow files are a list of users who are allowed to run 
# the crontab and at commands to submit jobs to be run at scheduled intervals.
# On many systems, only the system administrator needs the ability to schedule 
# jobs.
# Note that even though a given user is not listed in cron.allow, cron jobs can 
# still be run as that user. The cron.allow file only controls administrative 
# access to the crontab command for scheduling and modifying cron jobs. 
# Much more effective access controls for the cron system can be obtained by 
# using Role-Based Access Controls (RBAC).
# Note that if System Accounting is enabled, add the user sys to the cron.allow 
# file in addition to the root account.
#.

audit_cron_allow () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "At/Cron Authorized Users"
    check_file="/etc/cron.deny"
    funct_file_exists $check_file no
    check_file="/etc/at.deny"
    funct_file_exists $check_file no
    check_file="/etc/cron.allow"
    funct_file_exists $check_file yes
    if [ "$audit_mode" = 0 ]; then
      if [ "$os_name" = "SunOS" ]; then
        if [ "`cat $check_file |wc -l`" = "0" ]; then
          dir_name="/var/spool/cron/crontabs"
          if [ -d "$dir_name" ]; then
            for user_name in `ls $dir_name`; do
              check_id=`cat /etc/passwd |grep '^$user_name' |cut -f 1 -d:`
              if [ "$check_id" = "$user_name" ]; then
                echo "$user_name" >> $check_file
              fi
            done
          fi
        fi
      fi
      if [ "$os_name" = "Linux" ]; then
        if [ "`cat $check_file |wc -l`" = "0" ]; then
          dir_name="/var/spool/cron"
          if [ -d "$dir_name" ]; then
            for user_name in `ls $dir_name`; do
              check_id=`cat /etc/passwd |grep '^$user_name' |cut -f 1 -d:`
              if [ "$check_id" = "$user_name" ]; then
                echo "$user_name" >> $check_file
              fi
            done
          fi
        fi
      fi
      if [ "$os_name" = "Linux" ]; then
        for dir_name in /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.yearly; do
          if [ -d "$dir_name" ]; then
            for user_name in `ls -l $dir_name grep '-' |awk '{print $4}' |uniq`; do
              user_check=`cat $check_file |grep ''$user_name''`
              if [ "$user_check" != "$user_name" ]; then
                echo "$user_name" >> $check_file
              fi
            done
          fi
        done
      fi
    fi
    funct_check_perms $check_file 0640 root root
    check_file="/etc/at.allow"
    funct_file_exists $check_file yes
    if [ "$audit_mode" = 0 ]; then
      if [ "$os_name" = "SunOS" ]; then
        if [ "`cat $check_file |wc -l`" = "0" ]; then
          dir_name="/var/spool/cron/atjobs"
          if [ -d "$dir_name" ]; then
            for user_name in `ls $dir_name`; do
              user_check=`cat $check_file |grep ''$user_name''`
              if [ "$user_check" != "$user_name" ]; then
                echo "$user_name" >> $check_file
              fi
            done
          fi
        fi
      fi
      if [ "$os_name" = "Linux" ]; then
        if [ "`cat $check_file |wc -l`" = "0" ]; then
          dir_name="/var/spool/at/spool"
          if [ -d "$dir_name" ]; then
            for user_name in `ls /var/spool/at/spool`; do
              user_check=`cat $check_file |grep ''$user_name''`
              if [ "$user_check" != "$user_name" ]; then
                echo "$user_name" >> $check_file
              fi
            done
          fi
        fi
      fi
    fi
    funct_check_perms $check_file 0640 root root
    if [ "$os_name" = "Linux" ]; then
      for dir_name in /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.yearly; do
        funct_check_perms $dir_name 0640 root root
      done
      check_file="/etc/crontab"
      funct_check_perms $check_file 0640 root root
      check_file="/etc/anacrontab"
      funct_check_perms $check_file 0640 root root
    fi
  fi
}

# audit_console_login
#
# Privileged access to the system via the root account must be accountable 
# to a particular user. The system console is supposed to be protected from 
# unauthorized access and is the only location where it is considered 
# acceptable # to permit the root account to login directly, in the case of 
# system emergencies. This is the default configuration for Solaris.
# Use an authorized mechanism such as RBAC, the su command or the freely 
# available sudo package to provide administrative access through unprivileged 
# accounts. These mechanisms provide at least some limited audit trail in the 
# event of problems.
# Note that in addition to the configuration steps included here, there may be 
# other login services (such as SSH) that require additional configuration to 
# prevent root logins via these services.
# A more secure practice is to make root a "role" instead of a user account. 
# Role Based Access Control (RBAC) is similar in function to sudo, but provides 
# better logging ability and additional authentication requirements. With root 
# defined as a role, administrators would have to login under their account and 
# provide root credentials to invoke privileged commands. This restriction also 
# includes logging in to the console, except for single user mode.
#.

audit_console_login () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Root Login to System Console"
    if [ "$os_version" = "10" ]; then
      check_file="/etc/default/login"
      funct_file_value $check_file CONSOLE eq /dev/console hash
    fi
    if [ "$os_version" = "11" ]; then
      service_name="svc:/system/console-login:terma"
      funct_service $service_name disabled
      service_name="svc:/system/console-login:termb"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Root Login to System Console"
    disable_ttys=0
    check_file="/etc/securetty"
    console_list=""
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Remote consoles"
      for console_device in `cat $check_file |grep '^tty[0-9]'`; do
        disable_ttys=1
        console_list="$console_list $console_device"
      done
      if [ "$disable_ttys" = 1 ]; then
        if [ "$audit_mode" = 1 ]; then
          total=`expr $total + 1`
          score=`expr $score - 1`
          echo "Warning:   Consoles enabled on$console_list [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "cat $check_file |sed 's/tty[0-9].*//g' |grep '[a-z]' > $temp_file" fix
          funct_verbose_message "cat $temp_file > $check_file" fix
          funct_verbose_message "rm $temp_file" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Consoles to disabled on$console_list"
          cat $check_file |sed 's/tty[0-9].*//g' |grep '[a-z]' > $temp_file
          cat $temp_file > $check_file
          rm $temp_file 
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          total=`expr $total + 1`
          score=`expr $score + 1`
          echo "Secure:    No consoles enabled on tty[0-9]* [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_retry_limit
#
# The RETRIES parameter is the number of failed login attempts a user is 
# allowed before being disconnected from the system and forced to reconnect. 
# When LOCK_AFTER_RETRIES is set in /etc/security/policy.conf, then the user's 
# account is locked after this many failed retries (the account can only be 
# unlocked by the administrator using the command:passwd -u <username>
# Setting these values helps discourage brute force password guessing attacks. 
# The action specified here sets the lockout limit at 3, which complies with 
# NSA and DISA recommendations. This may be too restrictive for some operations 
# with large user populations.
#.

audit_retry_limit () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Retry Limit for Account Lockout"
      check_file="/etc/default/login"
      funct_file_value $check_file RETRIES eq 3 hash
      check_file="/etc/security/policy.conf"
      funct_file_value $check_file LOCK_AFTER_RETRIES eq YES hash
      if [ "$os_version" = "11" ]; then
        svcadm restart svc:/system/name-service/cache
      fi
    fi
  fi
}

# audit_crypt_policy
#
# Set default cryptographic algorithms
#.

audit_crypt_policy () {
  if [ "$os_name" = "SunOS" ]; then
    check_file="/etc/security/policy.conf"
    funct_file_value $check_file CRYPT_DEFAULT eq 6 hash
    funct_file_value $check_file CRYPT_ALGORITHMS_ALLOW eq 6 hash
  fi
}

# audit_eeprom_security
#
# Oracle SPARC systems support the use of a EEPROM password for the console.
# Setting the EEPROM password helps prevent attackers with physical access to 
# the system console from booting off some external device (such as a CD-ROM 
# or floppy) and subverting the security of the system.
#.

audit_eeprom_security () {
  :
}

# audit_grub_security
#
# GRUB is a boot loader for x86/x64 based systems that permits loading an OS 
# image from any location. Oracle x86 systems support the use of a GRUB Menu 
# password for the console.
# The flexibility that GRUB provides creates a security risk if its 
# configuration is modified by an unauthorized user. The failsafe menu entry 
# needs to be secured in the same environments that require securing the 
# systems firmware to avoid unauthorized removable media boots. Setting the 
# GRUB Menu password helps prevent attackers with physical access to the 
# system console from booting off some external device (such as a CD-ROM or 
# floppy) and subverting the security of the system.
# The actions described in this section will ensure you cannot get to failsafe 
# or any of the GRUB command line options without first entering the password. 
# Note that you can still boot into the default OS selection without a password.
#.

audit_grub_security () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    if [ "$os_name" = "Linux" ]; then
      funct_verbose_message "Grub Menu Security"
      check_file="/etc/grub.conf"
      funct_check_perms $check_file 0600 root root
    fi
#  if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
#    check_file="/boot/grub/menu.lst"
#    grub_check=`cat $check_file |grep "^password --md5" |awk '{print $1}'`
#    if [ "$grub_check" != "password" ]; then
#      if [ "$audit_mode" = 1 ]; then
#        score=`expr $score - 1`
#        echo "Warning:   Grub password not set [$score]"
#      fi
#      This code needs work
#      if [ "$audit_mode" = 0 ]; then
#        echo "Setting:   Grub password"
#        if [ ! -f "$log_file" ]; then
#          echo "Saving:    File $check_file to $log_file"
#          find $check_file | cpio -pdm $work_dir 2> /dev/null
#        fi
#   echo -n "Enter password: "
#   read $password_string
#   password_string=`htpasswd -nb test $password_string |cut -f2 -d":"`
#   echo "password --md5 $password_string" >> $check_file
#   chmod 600 $check_file
#   lock_check=`cat $check_file |grep lock`
#   if [ "$lock_check" != "lock"]; then
#     cat $check_file |sed 's,Solaris failsafe,Solaris failsafe\
#Lock,g' >> $temp_file
#     cp $temp_file $check_file
#     rm $temp_file
#   fi
#     fi
#    else
#      if [ "$audit_mode" = 1 ]; then
#        score=`expr $score + 1`
#        echo "Secure:    Set-UID not restricted on user mounted devices [$score]"
#      fi
#      if [ "$audit_mode" = 2 ]; then
#        restore_file="$restore_dir$check_file"
#        if [ -f "$restore_file" ]; then
#          echo "Restoring:  $restore_file to $check_file"
#          cp -p $restore_file $check_file
#          if [ "$os_version" = "10" ]; then
#            pkgchk -f -n -p $check_file 2> /dev/null
#          else
#            pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
#          fi
#        fi
#      fi
#    fi
#  fi
  fi
}

# audit_system_accounts
#
# There are a number of accounts provided with the Solaris OS that are used to 
# manage applications and are not intended to provide an interactive shell.
# It is important to make sure that accounts that are not being used by regular
# users are locked to prevent them from logging in or running an interactive 
# shell. By default, Solaris sets the password field for these accounts to an 
# invalid string, but it is also recommended that the shell field in the 
# password file be set to "false." This prevents the account from potentially 
# being used to run any commands.
#.

audit_system_accounts () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "System Accounts that do not have a shell"
    check_file="/etc/passwd"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  System accounts have valid shells"
      for user_name in `egrep -v "^\+" /etc/passwd | awk -F: '($1!="root" && $1!="sync" && $1!="shutdown" && $1!="halt" && $3<500 && $7!="/sbin/nologin" && $7!="/bin/false" ) {print $1}'`; do
        shadow_field=`grep "$user_name:" /etc/shadow |egrep -v "\*|\!\!|NP|UP|LK" |cut -f1 -d:`;
        if [ "$shadow_field" = "$user_name" ]; then
          echo "Warning:   System account $user_name has an invalid shell but the account is disabled"
        else
          if [ "$audit_mode" = 1 ]; then
            total=`expr $total + 1`
            score=`expr $score - 1`
            echo "Warning:   System account $user_name has an invalid shell"
            funct_verbose_message "" fix
            funct_verbose_message "usermod -s /sbin/nologin $user_name" fix
            funct_verbose_message "" fix
          fi
          if [ "$audit_mode" = 0 ]; then
            echo "Setting:   System account $user_name to have shell /sbin/nologin"
            funct_backup_file $check_file
            usermod -s /sbin/nologin $user_name
          fi
        fi
      done
    else
      funct_restore_file $check_file $restore_dir 
    fi
  fi
}

# audit_password_expiry
#
# Many organizations require users to change passwords on a regular basis.
# Since /etc/default/passwd sets defaults in terms of number of weeks 
# (even though the actual values on user accounts are kept in terms of days), 
# it is probably best to choose interval values that are multiples of 7.
# Actions for this item do not work on accounts stored on network directories 
# such as LDAP.
# The commands for this item set all active accounts (except the root account) 
# to force password changes every 91 days (13 weeks), and then prevent password 
# changes for seven days (one week) thereafter. Users will begin receiving 
# warnings 28 days (4 weeks) before their password expires. Sites also have the
# option of expiring idle accounts after a certain number of days (see the on-
# line manual page for the usermod command, particularly the -f option).
# These are recommended starting values, but sites may choose to make them more 
# restrictive depending on local policies.
# For Linux this will apply to new accounts
#
# To fix existing accounts:
# useradd -D -f 7
# chage -m 7 -M 90 -W 14 -I 7
#.

audit_password_expiry () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Password Expiration Parameters on Active Accounts"
    check_file="/etc/default/passwd"
    funct_file_value $check_file MAXWEEKS eq 13 hash
    funct_file_value $check_file MINWEEKS eq 1 hash
    funct_file_value $check_file WARNWEEKS eq 4 hash
    check_file="/etc/default/login"
    funct_file_value $check_file DISABLETIME eq 3600 hash
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Password Expiration Parameters on Active Accounts"
    check_file="/etc/login.defs"
    funct_file_value $check_file PASS_MAX_DAYS eq 90 hash
    funct_file_value $check_file PASS_MIN_DAYS eq 7 hash
    funct_file_value $check_file PASS_WARN_AGE eq 14 hash
    funct_file_value $check_file PASS_MIN_LEN eq 9 hash
    funct_check_perms $check_file 0640 root root
  fi
}

# audit_strong_password
#
# Password policies are designed to force users to make better password choices 
# when selecting their passwords.
# Administrators may wish to change some of the parameters in this remediation 
# step (particularly PASSLENGTH and MINDIFF) if changing their systems to use 
# MD5, SHA-256, SHA-512 or Blowfish password hashes ("man crypt.conf" for more 
# information). Similarly, administrators may wish to add site-specific 
# dictionaries to the DICTIONLIST parameter.
# Sites often have differing opinions on the optimal value of the HISTORY 
# parameter (how many previous passwords to remember per user in order to 
# prevent re-use). The values specified here are in compliance with DISA 
# requirements. If this is too restrictive for your site, you may wish to set 
# a HISTORY value of 4 and a MAXREPEATS of 2. Consult your local security 
# policy for guidance.
#.

audit_strong_password () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Strong Password Creation Policies"
    check_file="/etc/default/passwd"
    funct_file_value $check_file PASSLENGTH eq 8 hash
    funct_file_value $check_file NAMECHECK eq YES hash
    funct_file_value $check_file HISTORY eq 10 hash
    funct_file_value $check_file MINDIFF eq 3 hash
    funct_file_value $check_file MINALPHA eq 2 hash
    funct_file_value $check_file MINUPPER eq 1 hash
    funct_file_value $check_file MINLOWER eq 1 hash
    funct_file_value $check_file MINDIGIT eq 1 hash
    funct_file_value $check_file MINNONALPHA eq 1 hash
    funct_file_value $check_file MAXREPEATS eq 0 hash
    funct_file_value $check_file WHITESPACE eq YES hash
    funct_file_value $check_file DICTIONDBDIR eq /var/passwd hash
    funct_file_value $check_file DICTIONLIST eq /usr/share/lib/dict/words hash
  fi
}

# audit_root_group
#
# Set Default Group for root Account
# For Solaris 9 and earlier, the default group for the root account is the 
# "other" group, which may be shared by many other accounts on the system. 
# Solaris 10 has adopted GID 0 (group "root") as default group for the root 
# account.
# If your system has been upgraded from an earlier version of Solaris, the 
# password file may contain the older group classification for the root user. 
# Using GID 0 for the root account helps prevent root-owned files from 
# accidentally becoming accessible to non-privileged users.
#.

audit_root_group () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Default Group for root Account"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Root default group"
    fi
    group_check=`grep root /etc/passwd | cut -f4 -d":"`
    log_file="$work_dir/rootgroup.log"
    total=`expr $total + 1`
    if [ "$group_check" != 0 ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   Root default group incorrectly set [$score]"
        funct_verbose_message "" fix
        funct_verbose_message "passmgmt -m -g 0 root" fix
        funct_verbose_message "" fix
      fi
      if [ "$audit_mode" = 0 ]; then
        echo "$group_check" >> $log_file
        echo "Setting:   Root default group correctly"
        passmgmt -m -g 0 root
      fi
    else
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score + 1`
        echo "Secure:    Root default group correctly set [$score]"
      fi
    fi
    if [ "$audit_mode" = 2 ]; then
      restore_file="$restore_dir/rootgroup.log"
      if [ -f "$restore_file" ]; then
        $group_check=`cat $restore_file`
        echo "Restoring: Root default group $group_check"
        passmgmt -m -g $group_check root
      fi
    fi
  fi
}

# audit_root_home
#
# By default, the Solaris OS root user's home directory is "/".
# Changing the home directory for the root account provides segregation from 
# the OS distribution and activities performed by the root user. A further 
# benefit is that the root home directory can have more restricted permissions, 
# preventing viewing of the root system account files by non-root users.
#.

audit_root_home () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Home Directory Permissions for root Account"
    total=`expr $total + 1`
    if [ "$os_name" = "SunOS" ]; then
      if [ "$os_version" = "10" ]; then
        if [ "$audit_mode" != 2 ]; then
          echo "Checking:  Root home directory"
        fi
        home_check=`grep root /etc/passwd | cut -f6 -d:`
        log_file="$work_dir/roothome.log"
        if [ "$home_check" != "/root" ]; then
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score - 1`
            echo "Warning:   Root home directory incorrectly set [$score]"
            funct_verbose_message "" fix
            funct_verbose_message "mkdir -m 700 /root" fix
            funct_verbose_message "mv -i /.?* /root/" fix
            funct_verbose_message "passmgmt -m -h /root root" fix
            funct_verbose_message "" fix
          fi
          if [ "$audit_mode" = 0 ]; then
            echo "$home_check" >> $log_file
            echo "Setting:   Root home directory correctly"
            mkdir -m 700 /root
            mv -i /.?* /root/
            passmgmt -m -h /root root
          fi
        else
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    Root home directory correctly set [$score]"
          fi
        fi
        if [ "$audit_mode" = 2 ]; then
          restore_file="$restore_dir/rootgroup.log"
          if [ -f "$restore_file" ]; then
            $home_check=`cat $restore_file`
            echo "Restoring: Root home directory $home_check"
            mv -i $home_check/.?* /
            passmgmt -m -h $group_check root
          fi
        fi
      fi
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
      funct_check_perms /root 0700 root root
  fi
}

# audit_default_umask
#
# The default umask(1) determines the permissions of files created by users. 
# The user creating the file has the discretion of making their files and 
# directories readable by others via the chmod(1) command. Users who wish to 
# allow their files and directories to be readable by others by default may 
# choose a different default umask by inserting the umask command into the 
# standard shell configuration files (.profile, .cshrc, etc.) in their home 
# directories.
# Setting a very secure default value for umask ensures that users make a 
# conscious choice about their file permissions. A default umask setting of 
# 077 causes files and directories created by users to not be readable by any 
# other user on the system. A umask of 027 would make files and directories 
# readable by users in the same Unix group, while a umask of 022 would make 
# files readable by every user on the system.
#.

audit_default_umask () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Default umask for Users"
  fi
  if [ "$os_name" = "SunOS" ]; then
    check_file="/etc/default/login"
    funct_file_value $check_file UMASK eq 077 hash
  fi
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    for check_file in /etc/.login /etc/profile /etc/skel/.bash_profile; do
      funct_file_value $check_file "umask" space 077 hash
    done
    for check_file in /etc/bashrc /etc/skel/.bashrc; do
      funct_file_value $check_file UMASK eq 077 hash
    done
  fi
}

# audit_ftp_umask
#
# If FTP is permitted, set the umask value to apply to files created by the 
# FTP server.
# Many users assume that files transmitted over FTP inherit their system umask 
# value when they do not. This setting ensures that files transmitted over FTP 
# are protected.
#.

audit_ftp_umask () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Default umask for FTP Users"
    if [ "$os_version" = "10" ]; then
      check_file="/etc/ftpd/ftpaccess"
      funct_file_value $check_file defumask space 077 hash
    fi
    if [ "$os_version" = "11" ]; then
      check_file="/etc/proftpd.conf"
      funct_file_value $check_file Umask space 027 hash
    fi
  fi
}

# audit_shells
#
# Check that shells in /etc/shells exist
#.

audit_shells () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    check_file="/etc/shells"
    if [ -f "$check_file" ]; then
      if [ "$audit_mode" = 2 ]; then
        restore_file $check_file $restore_dir
      else
        for check_shell in `cat $check_file |grep -v '^#'`; do
          if [ ! -f "check_shell" ]; then
            if [ "$audit_mode" = 1 ]; then
              score=`expr $score - 1`
              echo "Warning:   Shell $check_shell in $check_file does not exit [$score]" 
            fi
            if [ "$audit_mode" = 0 ]; then
              temp_file="$temp_dir/shells"
              echo "Backing up $check_file"
              backup_file $check_file
              grep -v "^$check_shell" $check_file > $temp_file
              cat $temp_file > $check_file
            fi
          fi
        done
      fi
    fi
  fi
}

# audit_mesgn
#
# The "mesg n" command blocks attempts to use the write or talk commands to 
# contact users at their terminals, but has the side effect of slightly 
# strengthening permissions on the user's tty device.
# Note: Setting mesg n for all users may cause "mesg: cannot change mode" 
# to be displayed when using su - <user>.
# Since write and talk are no longer widely used at most sites, the incremental 
# security increase is worth the loss of functionality.
#.

audit_mesgn () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Default mesg Settings for Users"
    for check_file in /etc/.login /etc/profile /etc/skel/.bash_profile \
      /etc/skel/.bashrc; do
      funct_file_value $check_file mesg space n hash
    done
  fi
}

# audit_inactive_users
#
# Guidelines published by the U.S. Department of Defense specify that user 
# accounts must be locked out after 35 days of inactivity. This number may 
# vary based on the particular site's policy.
# Inactive accounts pose a threat to system security since the users are not 
# logging in to notice failed login attempts or other anomalies.
#.

audit_inactive_users () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Inactive User Accounts"
    check_file="/usr/sadm/defadduser"
    funct_file_value $check_file definact eq 35 hash
    check_file="/etc/shadow"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Lockout status for inactive user accounts"
      total=`expr $total + 1`
      for user_check in `cat $check_file |grep -v 'nobody4' |grep -v 'root'` ; do
        total=`expr $total + 1`
        inactive_check=`echo $user_check |cut -f 7 -d":"`
        user_name=`echo $user_check |cut -f 1 -d":"`
        if [ "$inactive_check" = "" ]; then
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score - 1`
            echo "Warning:   Inactive lockout not set for $user_name [$score]"
            funct_verbose_message "" fix
            funct_verbose_message "usermod -f 35 $user_name" fix
            funct_verbose_message "" fix
          fi
          if [ "$audit_mode" = 0 ]; then
            echo "Saving:    File $check_file to $work_dir$check_file"
            find $check_file | cpio -pdm $work_dir 2> /dev/null
            echo "Setting:   Inactive lockout for $user_name [$score]"
            usermod -f 35 $user_name
          fi
        else
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    Inactive lockout set for $user_name [$score]"
          fi
        fi
      done
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_security_banner
#
# Presenting a warning message prior to the normal user login may assist the 
# prosecution of trespassers on the computer system. Changing some of these 
# login banners also has the side effect of hiding OS version information and 
# other detailed system information from attackers attempting to target 
# specific exploits at a system.
# Guidelines published by the US Department of Defense require that warning 
# messages include at least the name of the organization that owns the system, 
# the fact that the system is subject to monitoring and that such monitoring 
# is in compliance with local statutes, and that use of the system implies 
# consent to such monitoring. It is important that the organization's legal 
# counsel review the content of all messages before any system modifications 
# are made, as these warning messages are inherently site-specific. 
# More information (including citations of relevant case law) can be found at 
# http://www.justice.gov/criminal/cybercrime/
#.

audit_security_banner () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Warnings for Standard Login Services"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Security banners"
    fi
    funct_file_exists /etc/motd yes
    funct_check_perms /etc/motd 0644 root root
    funct_file_exists /etc/issue yes
    funct_check_perms /etc/issue 0644 root root
  fi
}

# audit_cde_banner
#
# The Common Desktop Environment (CDE) provides a uniform desktop environment 
# for users across diverse Unix platforms.
# Warning messages inform users who are attempting to login to the system of 
# their legal status regarding the system and must include the name of the 
# organization that owns the system and any monitoring policies that are in 
# place. Consult with your organization's legal counsel for the appropriate 
# wording for your specific organization.
#.

audit_cde_banner () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message"CDE Warning Banner"
    for check_file in /usr/dt/config/*/Xresources ; do
      dir_name=`dirname $check_file |sed 's/usr/etc/'`
      new_file="$dir_name/Xresources"
      if [ -f "$new_file" ]; then
        funct_file_value $new_file "Dtlogin*greeting.labelString" colon "Authorized uses only" star
        funct_file_value $new_file "Dtlogin*greeting.persLabelString" colon "Authorized uses only" star
      fi
    done
  fi
}

# audit_gnome_banner
#
# Create Warning Banner for GNOME Users
#.

audit_gnome_banner () {
  if [ "$os_name" = "SunOS" ]; then
    total=`expr $total + 1`
    if [ "$os_version" = "10" ]; then
      funct_verbose_message"Gnome Warning Banner"
      check_file="/etc/X11/gdm.conf"
      funct_file_value $check_file Welcome eq "Authorised users only" hash
    fi
    if [ "$os_version" = "11" ]; then
      funct_verbose_message "Gnome Warning Banner"
      check_file="/etc/gdm/Init/Default"
      if [ "$audit_mode" != 2 ]; then
        if [ -f "$check_file" ]; then
          gdm_check=`cat $check_file |grep 'Security Message' |cut -f3 -d"="`
          if [ "$gdm_check" != "/etc/issue" ]; then
            if [ "$audit_mode" = 1 ]; then
              score=`expr $score - 1`
              echo "Warning:   Warning banner not found in $check_file [$score]"
              funct_verbose_message "" fix
              funct_verbose_message "echo \"   --title=\"Security Message\" --filename=/etc/issue\" >> $check_file" fix
              funct_verbose_message "" fix
            fi
            if [ "$audit_mode" = 0 ]; then
              funct_backup_file $check_file
              echo "Setting:   Warning banner in $check_file"
              echo "   --title=\"Security Message\" --filename=/etc/issue" >> $check_file
              if [ "$os_version" = "10" ]; then
                pkgchk -f -n -p $check_file 2> /dev/null
              else
                pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
              fi
            fi
          fi
          if [ "$file_entry" = "" ]; then
            if [ "$audit_mode" = 1 ]; then
              score=`expr $score + 1`
              echo "Secure:    Warning banner in $check_file [$score]"
            fi
          fi
        else
          funct_restore_file $check_file $restore_dir
        fi
      fi
    fi
  fi
}

# funct_defaults_check
#
# Function to check defaults under OS X
#.

funct_defaults_check () {
  if [ "$os_name" = "Darwin" ]; then
    defaults_file=$1
    defaults_parameter=$2
    defaults_value=$3
    defaults_type=$4
    defaults_host=$5
    defaults_read="read"
    defaults_write="write"
    backup_file=$defaults_file
    defaults_command="sudo defaults"
    total=`expr $total + 1`
    if [ "$audit_mode" != 2 ]; then
      if [ "$defaults_host" = "currentHost" ]; then
        defaults_read="-currentHost $defaults_read" 
        defaults_write="-currentHost $defaults_write" 
        backup_file="~/Library/Preferences/ByHost/$defaults_file*"
        defaults_command="defaults"
      fi 
      check_vale=`$defaults_command $defaults_read $defaults_file $defaults_parameter 2>&1` 
      temp_value=defaults_value
      if [ "$defaults_type" = "bool" ]; then
        if [ "$defaults_value" = "no" ]; then
          temp_value=0
        fi
        if [ "$defaults_value" = "yes" ]; then
          temp_value=1
        fi
      fi
      if [ "$check_value" != "$temp_value" ]; then
        score=`expr $score - 1`
        echo "Warning:   Parameter \"$defaults_parameter\" not set to \"$defaults_value\" in \"$defaults_file\" [$score]"
        funct_verbose_message "" fix
        funct_verbose_message "$defaults_command write $defaults_file $defaults_parameter $defaults_value" fix
        if [ "$defaults_value" = "" ]; then
          funct_verbose_message "$defaults_command delete $defaults_file $defaults_parameter" fix
        else
          funct_verbose_message "$defaults_command write $defaults_file $defaults_parameter $defaults_value" fix
        fi
        funct_verbose_message "" fix
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file "$backup_file"
          echo "Setting:   Parameter \"$defaults_parameter\" to \"$defaults_value\" in \"$defaults_file\""
          if [ "$defaults_value" = "" ]; then
            $defaults_command delete $defaults_file $defaults_parameter
          else
            if [ "$defaults_type" = "bool" ]; then
              $defaults_command write $defaults_file $defaults_parameter -bool "$defaults_value"
            else
              if [ "$defaults_type" = "int" ]; then
                $defaults_command write $defaults_file $defaults_parameter -int $defaults_value
                if [ "$defaults_file" ="/Library/Preferences/com.apple.Bluetooth" ]; then
                  killall -HUP blued
                fi
              fi
            fi
          fi
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Parameter \"$defaults_parameter\" is set to \"$defaults_value\" in \"$defaults_file\" [$score]"
        fi
      fi
    else
      funct_restore_file $backup_file $restore_dir
    fi
  fi
}

# funct_launchctl_check
#
# Function to check launchctl output under OS X
#.

funct_launchctl_check () {
  if [ "$os_name" = "Darwin" ]; then
    launchctl_service=$1
    total=`expr $total + 1`
    if [ "$audit_mode" != 2 ]; then
      check_vale=`launchctl list |grep $launchctl_service |awk '{print $3}'` 
      if [ "$check_value" = "$launchctl_service" ]; then
        score=`expr $score - 1`
        echo "Warning:   Service $launchctl_service enabled [$score]"
        funct_verbose_message "" fix
        funct_verbose_message "sudo launchctl unload -w $launchctl_service.plist" fix
        funct_verbose_message "" fix
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $dscl_dir$dscl_file
          echo "Setting:   Service $launchctl_service to disabled"
          sudo dscl . -create $dscl_file $dscl_parameter \"$dscl_value\"
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Service $launchctl_service to disabled [$score]"
        fi
      fi
    else
      sudo launchctl load -w $launchctl_service.plist
    fi
  fi
}

# funct_dscl_check
#
# Function to check dscl output under OS X
#.

funct_dscl_check () {
  if [ "$os_name" = "Darwin" ]; then
    dscl_file=$1
    dscl_parameter=$2
    dscl_value=$3
    dscl_dir="/var/db/dslocal/nodes/Default"
    total=`expr $total + 1`
    if [ "$audit_mode" != 2 ]; then
      check_vale=`sudo dscl . -read $dscl_file $dscl_parameter` 
      if [ "$check_value" != "$dscl_value" ]; then
        score=`expr $score - 1`
        echo "Warning:   Parameter \"$dscl_parameter\" not set to \"$dscl_value\" in \"$dscl_file\" [$score]"
        funct_verbose_message "" fix
        funct_verbose_message "sudo dscl . -create $dscl_file $dscl_parameter \"$dscl_value\"" fix
        funct_verbose_message "" fix
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $dscl_dir$dscl_file
          echo "Setting:   Parameter \"$dscl_parameter\" to \"$dscl_value\" in $dscl_file"
          sudo dscl . -create $dscl_file $dscl_parameter \"$dscl_value\"
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Parameter \"$dscl_parameter\" is set to \"$dscl_value\" in \"$dscl_file\" [$score]"
        fi
      fi
    else
      funct_restore_file $dscl_dir$dscl_file $restore_dir
    fi
  fi
}

# audit_bt_sharing
#
# Bluetooth can be very useful, but can also expose a Mac to certain risks.
# Unless specifically needed and configured properly, Bluetooth should be 
# turned off.
# Bluetooth internet sharing can expose a Mac and the network to certain 
# risks and should be turned off.
# Unless you are using a Bluetooth keyboard or mouse in a secure environment, 
# there is no reason to allow Bluetooth devices to wake the computer. 
# An attacker could use a Bluetooth device to wake a computer and then 
# attempt to gain access.
#.

audit_bt_sharing () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Bluetooth services and file sharing"
    funct_defaults_check /Library/Preferences/com.apple.Bluetooth ControllerPowerState 0 int
    funct_defaults_check /Library/Preferences/com.apple.Bluetooth PANServices 0 int
    funct_defaults_check /Library/Preferences/com.apple.Bluetooth BluetoothSystemWakeEnable 0 bool
  fi
}

# audit_guest_sharing
#
# If files need to be shared, a dedicated file server should be used. 
# If file sharing on the client Mac must be used, then only authenticated 
# access should be used. Guest access allows guest to access files they 
# might not need access to.
#.

audit_guest_sharing () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Guest account file sharing"
    funct_defaults_check /Library/Preferences/com.apple.AppleFileServer guestAccess no bool
    funct_defaults_check /Library/Preferences/SystemConfiguration/com.apple.smb.server AllowGuestAccess no bool
  fi
}

# audit_file_sharing
#
# Apple's File Sharing uses a combination of many technologies: FTP, SMB 
# (Windows sharing) and AFP (Mac sharing). Generally speaking, file sharing 
# should be turned off and a dedicated, well-managed file server should be 
# used to share files. If file sharing must be turned on, the user should be 
# aware of the security implications of each option.
#.

audit_file_sharing () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Apple File Sharing"
    funct_launchctl_check com.apple.AppleFileServer
    funct_verbose_message "FTP Services"
    funct_launchctl_check ftp
    funct_verbose_message "Samba Services"
    funct_launchctl_check nmbd
    funct_launchctl_check smbd
  fi
}

# audit_web_sharing
#
# Web Sharing uses the Apache 2.2.x Web server to turn the Mac into an HTTP/Web 
# server. When Web Sharing is on, files in /Library/WebServer/Documents as well 
# as each user's "Sites" folder are made available on the Web. As with File 
# Sharing, Web Sharing is best left off and a dedicated, well-managed Web server 
# is recommended. 
# Web Sharing can be configured using the /etc/apache2/httpd.conf file 
# (for global configurations). By default, Apache is fairly secure, but it can 
# be made more secure with a few additions to the /etc/apache2/httpd.conf file.
#.

audit_web_sharing () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Web sharing"
    funct_launchctl_check org.apache.httpd
    check_file="/etc/apache2/httpd.conf"
    funct_file_value $check_file ServerTokens space Prod hash
    funct_file_value $check_file ServerSignature space Off hash
    funct_file_value $check_file UserDir space Disabled hash
    funct_file_value $check_file TraceEnable space Off hash
  fi
}

# audit_login_warning
#
# Displaying an access warning that informs the user that the system is reserved 
# for authorized use only, and that the use of the system may be monitored, may 
# reduce a casual attacker’s tendency to target the system. 
#.

audit_login_warning () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Login message warning"
    funct_defaults_check com.apple.screensaver idleTime 900 int currentHost
  fi
}

# audit_firewall_setting
#
# Apple's firewall will protect your computer from certain incoming attacks. 
# Apple offers three firewall options: Allow all, Allow only essential, and 
# Allow access for specific incoming connections. Unless you have a specific 
# need to allow incoming connection (for services such as SSH, file sharing, 
# or web services), set the firewall to "Allow only essential services," 
# otherwise use the "allow access for specific incoming connections" option.
#
# 0 = off
# 1 = on for specific services
# 2 = on for essential services 
#.

audit_firewall_setting () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Firewall Settings"
    funct_defaults_check /Library/Preferences/com.apple.alf globalstate 1 int
  fi
}

# audit_infrared_remote
#
# A remote could be used to page through a document or presentation, thus 
# revealing sensitive information. The solution is to turn off the remote 
# and only turn it on when needed
#.

audit_infrared_remote () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Apple Remote Activation"
    funct_defaults_check /Library/Preferences/com.apple.driver.AppleIRController DeviceEnabled no bool
  fi
}

# audit_setup_file
#
# Check ownership of /var/db/.AppleSetupDone
# Incorrect ownership could lead to tampering. If deleted the Administrator
# password will be reset on next boot.
#.

audit_setup_file () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Setup file"
    check_file="/var/db/.AppleSetupDone"
    funct_check_perms $check_file 0400 root $wheel_group 
  fi
}

# audit_screen_lock
#
# Sometimes referred to as a screen lock this option will keep the casual user 
# away from your Mac when the screen saver has started.
# If the machine automatically logs out, unsaved work might be lost. The same 
# level of security is available by using a Screen Saver and the 
# "Require a password to wake the computer from sleep or screen saver" option.
#.

audit_screen_lock () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Screen lock"
    funct_defaults_check com.apple.screensaver askForPassword 1 int currentHost
    funct_defaults_check /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay 0 int
  fi
}

# audit_secure_swap
#
# Passwords and other sensitive information can be extracted from insecure 
# virtual memory, so it’s a good idea to secure virtual memory. If an attacker 
# gained control of the Mac, the attacker would be able to extract user names 
# and passwords or other kinds of data from the virtual memory swap files.
#.

audit_secure_swap () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Secure swap"
    funct_defaults_check /Library/Preferences/com.apple.virtualMemory UseEncryptedSwap yes bool
  fi
}

# audit_login_guest
#
# Password hints can give an attacker a hint as well, so the option to display 
# hints should be turned off. If your organization has a policy to enter a help 
# desk number in the password hints areas, do not turn off the option. 
#.

audit_login_guest () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Guest login"
    funct_dscl_check /Users/Guest AuthenticationAuthority ";basic;"
    funct_dscl_check /Users/Guest passwd "*"
    funct_dscl_check /Users/Guest UserShell "/sbin/nologin"
  fi
}

# audit_login_hints
#
# Password hints can give an attacker a hint as well, so the option to display 
# hints should be turned off. If your organization has a policy to enter a help 
# desk number in the password hints areas, do not turn off the option. 
#.

audit_login_hints () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Password hints"
    funct_defaults_check /Library/Preferences/com.apple.loginwindow RetriesUntilHint 0 int
  fi
}

# audit_login_details
#
# Displaying the names of the accounts on the computer may make breaking in 
# easier. Force the user to enter a login name and password to log in.
#.

audit_login_details () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Login display details"
    funct_defaults_check /Library/Preferences/com.apple.loginwindow SHOWFULLNAME yes bool
  fi
}

# audit_login_autologin
#
# Having a computer automatically log in bypasses a major security feature 
# (the login) and can allow a casual user access to sensitive data in that 
# user’s home directory and keychain.
#.

audit_login_autologin () {
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Core dumps"
    funct_defaults_check /Library/Preferences/.GlobalPreferences com.apple.userspref.DisableAutoLogin yes bool
  fi
}

# audit_core_limit
#
# When an application encounters a runtime error the operating system has the 
# opportunity to dump the application’s state, including memory contents, to 
# disk. This operation is called a core dump. It is possible for a core dump 
# to contain sensitive information, including passwords. Therefore it is 
# recommended that core dumps be disabled in high security scenarios.
#.

audit_core_limit () {
  if [ "$os_name" = "Darwin" ]; then
    total=`expr $total + 1`
    funct_verbose_message "Core dumps"
    if [ "$audit_mode" != 2 ]; then
      check_vale=`launchctl limit core |awk '{print $3}'`
      login_message="Authorized use only"
      if [ "$check_value" != "0" ]; then
        score=`expr $score - 1`
        echo "Warning:   Core dumps unlimited [$score]"
        funct_verbose_message "" fix
        funct_verbose_message "launchctl limit core 0" fix
        funct_verbose_message "" fix
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Core dump limits"
          launchctl limit core 0
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Login warning exists [$score]"
        fi
      fi
    else
      launchctl limit core unlimited
    fi
  fi
}

# audit_tcpsyn_cookie
#
#  TCP SYN Cookie Protection
#.

audit_tcpsyn_cookie () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "TCP SYN Cookie Protection"
    check_file="/etc/rc.d/local"
    funct_append_file $check_file "echo 1 > /proc/sys/net/ipv4/tcp_syncookies" hash
    funct_check_perms $check_file 0600 root root
  fi
}

# audit_ftp_banner
#
# The action for this item sets a warning message for FTP users before they 
# log in. Warning messages inform users who are attempting to access the 
# system of their legal status regarding the system. Consult with your 
# organization's legal counsel for the appropriate wording for your 
# specific organization.
#.

audit_ftp_banner () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "FTP Warning Banner"
      check_file="/etc/ftpd/banner.msg"
      funct_file_value $check_file Authorised space "users only" hash
      if [ "$audit_mode" = 0 ]; then
        funct_check_perms $check_file 0444 root root
      fi
    fi
    if [ "$os_version" = "11" ]; then
      funct_verbose_message"FTP Warning Banner"
      check_file="/etc/proftpd.conf"
      funct_file_value $check_file DisplayConnect space /etc/issue hash
      if [ "$audit_mode" = 0 ]; then
        svcadm restart ftp
      fi
    fi
  fi
}

# audit_telnet_banner
#
# The BANNER variable in the file /etc/default/telnetd can be used to display 
# text before the telnet login prompt. Traditionally, it has been used to 
# display the OS level of the target system.
# The warning banner provides information that can be used in reconnaissance 
# for an attack. By default, Oracle distributes this file with the BANNER 
# variable set to null. It is not necessary to create a separate warning banner 
# for telnet if a warning is set in the /etc/issue file.
#.

audit_telnet_banner () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Telnet Banner"
    check_file="/etc/default/telnetd"
    funct_file_value $check_file BANNER eq /etc/issue hash
  fi
}

# audit_remote_consoles
#
# The consadm command can be used to select or display alternate console devices.
# Since the system console has special properties to handle emergency situations, 
# it is important to ensure that the console is in a physically secure location 
# and that unauthorized consoles have not been defined. The "consadm -p" command 
# displays any alternate consoles that have been defined as auxiliary across 
# reboots. If no remote consoles have been defined, there will be no output from 
# this command.
#
# On Linux remove tty[0-9]* from /etc/securetty if run in lockdown mode
#.

audit_remote_consoles () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Remote Consoles"
    log_file="remoteconsoles.log"
    if [ "$audit_mode" != 2 ]; then
      disable_ttys=0
      echo "Checking:  Remote consoles"
      log_file="$work_dir/$log_file"
      for console_device in `/usr/sbin/consadm -p`; do
        total=`expr $total + 1`
        disable_ttys=1
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Console enabled on $console_device [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "consadm -d $console_device" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          echo "$console_device" >> $log_file
          echo "Setting:   Console disabled on $console_device"
          consadm -d $console_device
        fi
      done
      if [ "$disable_ttys" = 0 ]; then
        if [ "$audit_mode" = 1 ]; then
          total=`expr $total + 1`
          score=`expr $score + 1`
          echo "Secure:    No remote consoles enabled [$score]"
        fi
      fi
    else
      restore_file="$restore_dir$log_file"
      if [ -f "$restore_file" ]; then
        for console_device in `cat $restore_file`; do
          echo "Restoring: Console to enabled on $console_device"
          consadm -a $console_device
        done
      fi
    fi
  fi
}

# audit_file_perms
#
# It is important to ensure that system files and directories are maintained 
# with the permissions they were intended to have from the OS vendor (Oracle).
#.

audit_file_perms () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "System File Permissions"
    log_file="fileperms.log"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  File permissions [This may take a while]"
      if [ "$os_version" = "11" ]; then
        error=0
        command=`pkg verify |grep file |awk '{print $2}'`
      else
        command=`pkgchk -n 2>&1 |grep ERROR |awk '{print $2}'`
      fi
      for check_file in $command; do
        if [ "$audit_mode" = 1 ]; then
          echo "Warning:   Incorrect permissions on $check_file"
        fi
        if [ "$audit_mode" = 0 ]; then
          if [ "$os_version" = "10" ]; then
            echo "Setting:   Correct permissions on $check_file"
            log_file="$work_dir/$log_file"
            file_perms=`ls -l $check_file |echo "obase=8;ibase=2;\`awk '{print $1}' |cut -c2-10 |tr 'xrws-' '11110'\`" |/usr/bin/bc`
            file_owner=`ls -l $check_file |awk '{print $3","$4}'`
            echo "$check_file,$file_perms,$file_owner" >> $log_file
            pkgchk -f -n -p $file_name 2> /dev/null
          else
            error=1
          fi
        fi
      done
      if [ "$os_version" = "11" ]; then
        if [ "$audit_mode" = 0 ]; then
          if [ "$error" = 1 ]; then
            log_file="$work_dir/$log_file"
            file_perms=`ls -l $check_file |echo "obase=8;ibase=2;\`awk '{print $1}' |cut -c2-10 |tr 'xrws-' '11110'\`" |/usr/bin/bc`
            file_owner=`ls -l $check_file |awk '{print $3","$4}'`
            echo "$check_file,$file_perms,$file_owner" >> $log_file
            pkg fix
          fi
        fi
      fi
    else
      restore_file="$restore_dir/$log_file"
      if [ -f "$restore_file" ]; then
        restore_check=`cat $restore_file |grep "$check_file" |cut -f1 -d","`
        if [ "$restore_check" = "$check_file" ]; then
          restore_info=`cat $restore_file |grep "$check_file"`
          restore_perms=`echo "$restore_info" |cut -f2 -d","`
          restore_owner=`echo "$restore_info" |cut -f3 -d","`
          restore_group=`echo "$restore_info" |cut -f4 -d","`
          echo "Restoring: File $check_file to previous permissions"
          chmod $restore_perms $check_file
          if [ "$check_owner" != "" ]; then
            chown $restore_owner:$restore_group $check_file
          fi
        fi
      fi
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "System File Permissions"
    log_file="fileperms.log"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  File permissions [This may take a while]"
      for check_file in `rpm -Va --nomtime --nosize --nomd5 --nolinkt| awk '{print $2}'`; do
        if [ "$audit_mode" = 1 ]; then
          echo "Warning:   Incorrect permissions on $file_name"
          funct_verbose_message "" fix
          funct_verbose_message "yum reinstall $rpm_name" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          echo "Setting:   Correct permissions on $file_name"
          log_file="$work_dir/$log_file"
          file_perms=`stat -c %a $check_file`
          file_owner=`ls -l $check_file |awk '{print $3","$4}'`
          echo "$check_file,$file_perms,$file_owner" >> $log_file
          yum reinstall $rpm_name
        fi
      done
    else
      restore_file="$restore_dir/$log_file"
      if [ -f "$restore_file" ]; then
        restore_check=`cat $restore_file |grep "$check_file" |cut -f1 -d","`
        if [ "$restore_check" = "$check_file" ]; then
          restore_info=`cat $restore_file |grep "$check_file"`
          restore_perms=`echo "$restore_info" |cut -f2 -d","`
          restore_owner=`echo "$restore_info" |cut -f3 -d","`
          restore_group=`echo "$restore_info" |cut -f4 -d","`
          echo "Restoring: File $check_file to previous permissions"
          chmod $restore_perms $check_file
          if [ "$check_owner" != "" ]; then
            chown $restore_owner:$restore_group $check_file
          fi
        fi
      fi
    fi
  fi
}

# audit_password_fields
#
# Ensure Password Fields are Not Empty
# Verify System Account Default Passwords
# Ensure Password Fields are Not Empty
#
# An account with an empty password field means that anybody may log in as 
# that user without providing a password at all (assuming that PASSREQ=NO 
# in /etc/default/login). All accounts must have passwords or be locked.
#.

audit_password_fields () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Password Fields"
    check_file="/etc/shadow"
    empty_count=0
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Password fields"
      total=`expr $total + 1`
      for user_name in `cat /etc/shadow |awk -F":" '{print $1":"$2":"}' |grep "::$" |cut -f1 -d":"`; do
        empty_count=1
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   No password field for $user_name in $check_file [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "passwd -d $user_name" fix
          if [ "$os_name" = "SunOS" ]; then
            funct_verbose_message "passwd -N $user_name" fix
          fi
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   No password for $user_name"
          passwd -d $user_name
          if [ "$os_name" = "SunOS" ]; then
            passwd -N $user_name
          fi
        fi
      done
      if [ "$empty_count" = 0 ]; then
        score=`expr $score + 1`
        echo "Secure:    No empty password entries"
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_nis_entries
#
# The character + in various files used to be markers for systems to insert 
# data from NIS maps at a certain point in a system configuration file. 
# These entries are no longer required on Solaris systems, but may exist in 
# files that have been imported from other platforms.
# These entries may provide an avenue for attackers to gain privileged access 
# on the system.
#.

audit_nis_entries () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "NIS Map Entries"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Legacy NIS '+' entries"
    fi
    total=`expr $total + 1`
    for check_file in /etc/passwd /etc/shadow /etc/group; do
      if [ "$audit_mode" != 2 ]; then
        for file_entry in `cat $check_file |grep "^+"`; do
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score - 1`
            echo "Warning:   NIS entry \"$file_entry\" in $check_file [$score]"
            funct_verbose_message "" fix
            funct_verbose_message 'sed -e "s/^+/#&/" < $check_file > $temp_file' fix
            funct_verbose_message "cat $temp_file > $check_file" fix
            funct_verbose_message "" fix
          fi
          if [ "$audit_mode" = 0 ]; then
            funct_backup_file $check_file
            echo "Setting:   File $check_file to have no NIS entries"
            sed -e "s/^+/#&/" < $check_file > $temp_file
            cat $temp_file > $check_file
            if [ "$os_name" = "SunOS" ]; then
              if [ "$os_version" != "11" ]; then
                pkgchk -f -n -p $check_file 2> /dev/null
              else
                pkg fix `pkg search $check_file |grep pkg |awk '{print $4}'`
              fi
            fi
            rm $temp_file
          fi
        done
        if [ "$file_entry" = "" ]; then
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    No NIS entries in $check_file [$score]"
          fi
        fi
      else
        funct_restore_file $check_file $restore_dir
      fi
    done
  fi
}

# audit_super_users
#
# Any account with UID 0 has superuser privileges on the system.
# This access must be limited to only the default root account 
# and only from the system console.
#.

audit_super_users () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Accounts with UID 0"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Super users other than root"
      total=`expr $total + 1`
      for user_name in `awk -F: '$3 == "0" { print $1 }' /etc/passwd |grep -v root`; do
        echo "$user_name"
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   UID 0 for $user_name [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "userdel $user_name" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          check_file="/etc/shadow"
          funct_backup_file $check_file
          check_file="/etc/passwd"
          backup_file="$work_dir$check_file"
          funct_backup_file $check_file
          echo "Removing:  Account $user_name it UID 0"
          userdel $user_name
        fi
      done
      if [ "$user_name" = "" ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    No accounts other than root have UID 0 [$score]"
        fi
      fi
    else
      check_file="/etc/shadow"
      funct_restore_file $check_file $restore_dir
      check_file="/etc/passwd"
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# funct_check_perms
#
# Code to check permissions on a file
# If running in audit mode it will check permissions and report
# If running in lockdown mode it will fix permissions if they
# don't match those passed to routine
# Takes:
# check_file:   Name of file
# check_perms:  Octal of file permissions, eg 755
# check_owner:  Owner of file
# check_group:  Group ownership of file
#.

funct_check_perms () {
  check_file=$1
  check_perms=$2
  check_owner=$3
  check_group=$4
  if [ "$audit_mode" != 2 ]; then
    echo "Checking:  File permissions on $check_file"
  fi
  total=`expr $total + 1`
  if [ ! -f "$check_file" ] && [ ! -d "$check_file" ]; then
    if [ "$audit_mode" != 2 ]; then
      score=`expr $score + 1`
      echo "Notice:    File $check_file does not exist [$score]"
    fi
    return
  fi
  if [ "$check_owner" != "" ]; then
    check_result=`find $check_file -perm $check_perms -user $check_owner -group $check_group`
  else
    check_result=`find $check_file -perm $check_perms`
  fi
  log_file="fileperms.log"
  if [ "$check_result" != "$check_file" ]; then
    if [ "$audit_mode" = 1 ]; then
      score=`expr $score - 1`
      echo "Warning:   File $check_file has incorrect permissions [$score]"
      funct_verbose_message "" fix
      funct_verbose_message "chmod $check_perms $check_file" fix
      if [ "$check_owner" != "" ]; then
        funct_verbose_message "chown $check_owner:$check_group $check_file" fix
      fi
      funct_verbose_message "" fix
    fi
    if [ "$audit_mode" = 0 ]; then
      log_file="$work_dir/$log_file"
      if [ "$os_name" = "SunOS" ]; then
        file_perms=`truss -vstat -tstat ls -ld $check_file 2>&1 |grep 'm=' |tail -1 |awk '{print $3}' |cut -f2 -d'=' |cut -c4-7`
      else
        file_perms=`stat -c %a $check_file`
      fi
      file_owner=`ls -l $check_file |awk '{print $3","$4}'`
      echo "$check_file,$file_perms,$file_owner" >> $log_file
      echo "Setting:   File $check_file to have correct permissions [$score]"
      chmod $check_perms $check_file
      if [ "$check_owner" != "" ]; then
        chown $check_owner:$check_group $check_file
      fi
    fi
  else
    if [ "$audit_mode" = 1 ]; then
      score=`expr $score + 1`
      echo "Secure:    File $check_file has correct permissions [$score]"
    fi
  fi
  if [ "$audit_mode" = 2 ]; then
    restore_file="$restore_dir/$log_file"
    if [ -f "$restore_file" ]; then
      restore_check=`cat $restore_file |grep "$check_file" |cut -f1 -d","`
      if [ "$restore_check" = "$check_file" ]; then
        restore_info=`cat $restore_file |grep "$check_file"`
        restore_perms=`echo "$restore_info" |cut -f2 -d","`
        restore_owner=`echo "$restore_info" |cut -f3 -d","`
        restore_group=`echo "$restore_info" |cut -f4 -d","`
        echo "Restoring: File $check_file to previous permissions"
        chmod $restore_perms $check_file
        if [ "$check_owner" != "" ]; then
          chown $restore_owner:$restore_group $check_file
        fi
      fi
    fi
  fi
}

# audit_dot_files
#
# Check for a dot file and copy it to backup directory
#.

audit_dot_files () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Dot Files"
    check_file=$1
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  For $check_file files"
      for dir_name in `cat /etc/passwd |cut -f6 -d':'`; do
        if [ "$dir_name" = "/" ]; then
          dot_file="/$check_file"
        else
          dot_file="$dir_name/$check_file"
        fi
        if [ -f "$dot_file" ]; then
          if [ "$audit_mode" = 1 ];then
            total=`expr $total + 1`
            score=`expr $score - 1`
            echo "Warning:   File $dot_file exists [$score]"
            funct_verbose_message "mv $dot_file $dot_file.disabled" fix
          fi
          if [ "$audit_mode" = 0 ];then
            funct_backup_file $dot_file
          fi
        else
          if [ "$audit_mode" = 1 ];then
            total=`expr $total + 1`
            score=`expr $score + 1`
            echo "Secure:    File $dot_file does not exist [$score]"
          fi          
        fi
      done
    else
      for check_file in `cd $restore_dir ; find . -name "$check_file" |sed "s/^\.//g"`; do
        funct_restore_file $check_file $restore_dir
      done
    fi
  fi
}

# audit_root_path
#
# The root user can execute any command on the system and could be fooled into 
# executing programs unemotionally if the PATH is not set correctly.
# Including the current working directory (.) or other writable directory in 
# root's executable path makes it likely that an attacker can gain superuser 
# access by forcing an administrator operating as root to execute a Trojan 
# horse program.
#.

audit_root_path () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Root PATH Environment Integrity"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Root PATH"
      if [ "$audit_mode" = 1 ]; then
        if [ "`echo $PATH | grep :: `" != "" ]; then
          total=`expr $total + 1`
          score=`expr $score - 1`
          echo "Warning:   Empty directory in PATH [$score]"
        else
          total=`expr $total + 1`
          score=`expr $score + 1`
          echo "Secure:    No empty directory in PATH [$score]"
        fi
        if [ "`echo $PATH | grep :$`"  != "" ]; then
          total=`expr $total + 1`
          score=`expr $score - 1`
          echo "Warning:   Trailing : in PATH [$score]"
        else
          total=`expr $total + 1`
          score=`expr $score + 1`
          echo "Secure:    No trailing : in PATH [$score]"
        fi
        for dir_name in `echo $PATH | sed -e 's/::/:/' -e 's/:$//' -e 's/:/ /g'`; do
          if [ "$dir_name" = "." ]; then
            total=`expr $total + 1`
            score=`expr $score - 1`
            echo "Warning:   PATH contains . [$score]"
          fi
          if [ -d "$dir_name" ]; then
            dir_perms=`ls -ld $dir_name | cut -f1 -d" "`
            if [ "`echo $dir_perms | cut -c6`" != "-" ]; then
              total=`expr $total + 1`
              score=`expr $score - 1`
              echo "Warning:   Group write permissions set on directory $dir_name [$score]"
            else
              total=`expr $total + 1`
              score=`expr $score + 1`
              echo "Secure:    Group write permission not set on directory $dir_name [$score]"
            fi
            if [ "`echo $dir_perms | cut -c9`" != "-" ]; then
              total=`expr $total + 1`
              score=`expr $score - 1`
              echo "Warning:   Other write permissions set on directory $dir_name [$score]"
            else
              total=`expr $total + 1`
              score=`expr $score + 1`
              echo "Secure:    Other write permission not set on directory $dir_name [$score]"
            fi
          fi
        done
      fi
    fi
  fi
}

# audit_home_perms
#
# While the system administrator can establish secure permissions for users' 
# home directories, the users can easily override these.
# Group or world-writable user home directories may enable malicious users to 
# steal or modify other users' data or to gain another user's system privileges.
#.

audit_home_perms () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Home Directory Permissions"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  User home directory permissions"
    fi
    check_fail=0
    for home_dir in `cat /etc/passwd |cut -f6 -d":" |grep -v "^/$" |grep "home"`; do
      if [ -d "$home_dir" ]; then
        funct_check_perms $home_dir 0700
      fi
    done
  fi
}

# audit_user_dotfiles
#
# While the system administrator can establish secure permissions for users' 
# "dot" files, the users can easily override these.
# Group or world-writable user configuration files may enable malicious users to 
# steal or modify other users' data or to gain another user's system privileges.
#.

audit_user_dotfiles () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "User Dot Files"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  User dot file permissions"
    fi
    check_fail=0
    for home_dir in `cat /etc/passwd |cut -f6 -d":" |grep -v "^/$"`; do
      for check_file in $home_dir/.[A-Za-z0-9]*; do
        if [ -f "$check_file" ]; then
          funct_check_perms $check_file 0600
        fi
      done
    done
  fi
}

# audit_user_netrc
#
# While the system administrator can establish secure permissions for users' 
# .netrc files, the users can easily override these.
# Users' .netrc files may contain unencrypted passwords that may be used to 
# attack other systems.
#.

audit_user_netrc () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "User Netrc Files"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  User netrc file permissions"
    fi
    check_fail=0
    for home_dir in `cat /etc/passwd |cut -f6 -d":" |grep -v "^/$"`; do
      check_file="$home_dir/.netrc"
      if [ -f "$check_file" ]; then
        check_fail=1
        funct_check_perms $check_file 0600
      fi
    done
    if [ "$check_fail" != 1 ]; then
      if [ "$audit_mode" = 1 ]; then
        total=`expr $total + 1`
        score=`expr $score + 1`
        echo "Secure:    No user netrc files exist [$score]"
      fi
    fi
  fi
}

# audit_user_rhosts
#
# While no .rhosts files are shipped with Solaris, users can easily create them.
# This action is only meaningful if .rhosts support is permitted in the file 
# /etc/pam.conf. Even though the .rhosts files are ineffective if support is 
# disabled in /etc/pam.conf, they may have been brought over from other systems 
# and could contain information useful to an attacker for those other systems.
#.

audit_user_rhosts () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "User RHosts Files"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  User rhosts files"
    fi
    check_fail=0
    for home_dir in `cat /etc/passwd |cut -f6 -d":" |grep -v "^/$"`; do
      check_file="$home_dir/.rhosts"
      if [ -f "$check_file" ]; then
        check_fail=1
        funct_file_exists $check_file no
      fi
    done
    if [ "$check_fail" != 1 ]; then
      if [ "$audit_mode" = 1 ]; then
        total=`expr $total + 1`
        score=`expr $score + 1`
        echo "Secure:    No user rhosts files exist [$score]"
      fi
    fi
  fi
}

# audit_groups_exist
#
# Over time, system administration errors and changes can lead to groups being 
# defined in /etc/passwd but not in /etc/group.
# Groups defined in the /etc/passwd file but not in the /etc/group file pose a 
# threat to system security since group permissions are not properly managed.
#.

audit_groups_exist () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "User Groups"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Groups in passwd file exist in group file"
    fi
    check_file="/etc/group"
    group_fail=0
    total=`expr $total + 1`
    if [ "$audit_mode" != 2 ]; then
      for group_id in `getent passwd |cut -f4 -d ":"`; do
        group_exists=`cat $check_file |grep -v "^#" |cut -f3 -d":" |grep "^$group_id$" |wc -l |sed "s/ //g"`
        if [ "$group_exists" = 0 ]; then
          group_fail=1
          if [ "$audit_mode" = 1 ];then
            score=`expr $score - 1`
            echo "Warning:   Group $group_id does not exist in group file [$score]"
          fi
        fi
      done
      if [ "$group_fail" != 1 ]; then
        if [ "$audit_mode" = 1 ];then
          score=`expr $score + 1`
          echo "Secure:    No non existant group issues [$score]"
        fi
      fi
    fi
  fi
}

# audit_root_group
#
# Make sure root's primary group is root
#.

audit_root_group () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Root Primary Group"
    log_file="root_primary_grooup.log"
    check_file="/etc/group"
    group_check=`grep "^root:" /etc/passwd | cut -f4 -d:`
    total=`expr $total + 1`
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Primary group for root is root"
      if [ "$group_check" != "0" ];then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Group $group_id does not exist in group file [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "usermod -g 0 root" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ];then
          log_file="$work_dir/$log_file"
          echo "$group_check" > $log_file
          echo "Setting:   Primary group for root to root"
          usermod -g 0 root
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Primary group for root is root [$score]"
        fi
      fi
    else
      restore_file="$restore_dir/$log_file"
      if [ -e "$restore_file" ]; then
        restore_value=`cat $restore_file`
        if [ "$restore_value" != "$group_check" ]; then
          usermod -g $restore_value root
        fi
      fi
    fi
  fi
}

# audit_home_ownership
#
# Check That Users Are Assigned Home Directories
# Check That Defined Home Directories Exist
# Check User Home Directory Ownership
#
# The /etc/passwd file defines a home directory that the user is placed in upon 
# login. If there is no defined home directory, the user will be placed in "/" 
# and will not be able to write any files or have local environment variables set.
# All users must be assigned a home directory in the /etc/passwd file.
#
# Users can be defined to have a home directory in /etc/passwd, even if the 
# directory does not actually exist.
# If the user's home directory does not exist, the user will be placed in "/" 
# and will not be able to write any files or have local environment variables set.
#
# The user home directory is space defined for the particular user to set local 
# environment variables and to store personal files.
# Since the user is accountable for files stored in the user home directory, 
# the user must be the owner of the directory.
#.

audit_home_ownership () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Ownership of Home Directories"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Ownership of home directories"
    fi
    home_check=0
    total=`expr $total + 1`
    if [ "$audit_mode" != 2 ]; then
      getent passwd | awk -F: '{ print $1" "$6 }' | while read check_user home_dir; do
        found=0
        for test_user in root daemon bin sys adm lp uucp nuucp smmsp listen \
          gdm webservd postgres svctag nobody noaccess nobody4 unknown; do
          if [ "$check_user" = "$test_user" ]; then
            found=1
          fi
        done
        if [ "$found" = 0 ]; then
          home_check=1
          if [ -z "$home_dir" ] || [ "$home_dir" = "/" ]; then
            if [ "$audit_mode" = 1 ];then
              score=`expr $score - 1`
              echo "Warning:   User $check_user has no home directory defined [$score]"
            fi
          else
            if [ -d "$home_dir" ]; then
              dir_owner=`ls -ld $home_dir/. | awk '{ print $3 }'`
              if [ "$dir_owner" != "$check_user" ]; then
                if [ "$audit_mode" = 1 ];then
                  score=`expr $score - 1`
                  echo "Warning:   Home Directory for $check_user is owned by $dir_owner [$score]"
                fi
              else
                if [ -z "$home_dir" ] || [ "$home_dir" = "/" ]; then
                  if [ "$audit_mode" = 1 ];then
                    score=`expr $score - 1`
                    echo "Warning:   User $check_user has no home directory [$score]"
                  fi
                fi
              fi
            fi
          fi
        fi
      done
      if [ "$home_check" = 0 ]; then
        if [ "$audit_mode" = 1 ];then
          score=`expr $score + 1`
          echo "Secure:    No ownership issues with home directories [$score]"
        fi
      fi
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    echo ""
    echo "# Ownership of Home Directories"
    echo ""
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Ownership of home directories"
    fi
    home_check=0
    total=`expr $total + 1`
    if [ "$audit_mode" != 2 ]; then
      getent passwd | awk -F: '{ print $1" "$6 }' | while read check_user home_dir; do
        found=0
        for test_user in root bin daemon adm lp sync shutdown halt mail news uucp \
          operator games gopher ftp nobody nscd vcsa rpc mailnull smmsp pcap \
          dbus sshd rpcuser nfsnobody haldaemon distcache apache \
          oprofile webalizer dovecot squid named xfs gdm sabayon; do
          if [ "$check_user" = "$test_user" ]; then
            found=1
          fi
        done
        if [ "$found" = 0 ]; then
          home_check=1
          if [ -z "$home_dir" ] || [ "$home_dir" = "/" ]; then
            if [ "$audit_mode" = 1 ];then
              score=`expr $score - 1`
              echo "Warning:   User $check_user has no home directory defined [$score]"
            fi
          else
            if [ -d "$home_dir" ]; then
              dir_owner=`ls -ld $home_dir/. | awk '{ print $3 }'`
              if [ "$dir_owner" != "$check_user" ]; then
                if [ "$audit_mode" = 1 ];then
                  score=`expr $score - 1`
                  echo "Warning:   Home Directory for $check_user is owned by $dir_owner [$score]"
                fi
              else
                if [ -z "$home_dir" ] || [ "$home_dir" = "/" ]; then
                  if [ "$audit_mode" = 1 ];then
                    score=`expr $score - 1`
                    echo "Warning:   User $check_user has no home directory [$score]"
                  fi
                fi
              fi
            fi
          fi
        fi
      done
      if [ "$home_check" = 0 ]; then
        if [ "$audit_mode" = 1 ];then
          score=`expr $score + 1`
          echo "Secure:    No ownership issues with home directories [$score]"
        fi
      fi
    fi
  fi
}

# audit_reserved_ids
#
# Traditionally, Unix systems establish "reserved" UIDs (0-99 range) that are 
# intended for system accounts.
# If a user is assigned a UID that is in the reserved range, even if it is not 
# presently in use, security exposures can arise if a subsequently installed 
# application uses the same UID.
#.

audit_reserved_ids () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Reserved IDs"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Whether reserved UUIDs are assigned to system accounts"
    fi
    total=`expr $total + 1`
    if [ "$audit_mode" != 2 ]; then
      getent passwd | awk -F: '($3 < 100) { print $1" "$3 }' | while read check_user check_uid; do
        found=0
        for test_user in root daemon bin sys adm lp uucp nuucp smmsp listen \
        gdm webservd postgres svctag nobody noaccess nobody4 unknown; do
          if [ "$check_user" = "$test_user" ]; then
            found=1
          fi
        done
        if [ "$found" = 0 ]; then
          uuid_check=1
          if [ "$audit_mode" = 1 ];then
            score=`expr $score - 1`
            echo "Warning:   User $check_user has a reserved UID ($check_uid) [$score]"
          fi
        fi
      done
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Reserved IDs"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Whether reserved UUIDs are assigned to system accounts"
    fi
    total=`expr $total + 1`
    if [ "$audit_mode" != 2 ]; then
      getent passwd | awk -F: '($3 < 500) { print $1" "$3 }' | while read check_user check_uid; do
        found=0
        for test_user in root bin daemon adm lp sync shutdown halt mail news uucp \
          operator games gopher ftp nobody nscd vcsa rpc mailnull smmsp pcap \
          dbus sshd rpcuser nfsnobody haldaemon distcache apache \
          oprofile webalizer dovecot squid named xfs gdm sabayon; do
          if [ "$check_user" = "$test_user" ]; then
            found=1
          fi
        done
        if [ "$found" = 0 ]; then
          uuid_check=1
          if [ "$audit_mode" = 1 ];then
            score=`expr $score - 1`
            echo "Warning:   User $check_user has a reserved UID ($check_uid) [$score]"
          fi
        fi
      done
    fi
  fi
}

# audit_duplicate_ids
#
# Code to check for duplicate IDs
# Routine to check a file for duplicates
# Takes:
# field:      Field number
# function:   String describing action, eg users
# term:       String describing term, eg name
# check_file: File to parse
#
# Although the useradd program will not let you create a duplicate User ID 
# (UID), it is possible for an administrator to manually edit the /etc/passwd 
# file and change the UID field.
#.

audit_duplicate_ids () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Duplicate IDs"
    field=$1
    function=$2
    term=$3
    duplicate=0
    check_file=$4
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  For $function with duplicate $term"
      total=`expr $total + 1`
      for file_info in `cat $check_file | cut -f$field -d":" | sort -n | uniq -c |awk '{ print $1":"$2 }'`; do
        file_check=`expr "$file_info" : "[A-z,0-9]"`
        if [ "$file_check" = 1 ]; then
          file_check=`expr "$file_info" : "2"`
          if [ "$file_check" = 1 ]; then
            file_id=`echo "$file_info" |cut -f2 -d":"`
            if [ "$audit_mode" = 1 ];then
              score=`expr $score - 1`
              echo "Warning:   There are multiple $function with $term $file_id [$score]"
              duplicate=1
            fi
          fi
        fi
      done
      if [ "$audit_mode" = 1 ]; then
        if [ "$duplicate" = 0 ];then
          score=`expr $score + 1`
          echo "Secure:    No $function with duplicate $term [$score]"
        fi
      fi
    fi
  fi
}

# audit_duplicate_users
#
# Although the useradd program will not let you create a duplicate User ID 
# (UID), it is possible for an administrator to manually edit the /etc/passwd 
# file and change the UID field.
# Users must be assigned unique UIDs for accountability and to ensure 
# appropriate access protections.
#
# Although the useradd program will not let you create a duplicate user name, 
# it is possible for an administrator to manually edit the /etc/passwd file 
# and change the user name.
# If a user is assigned a duplicate user name, it will create and have access 
# to files with the first UID for that username in /etc/passwd. For example, 
# if "test4" has a UID of 1000 and a subsequent "test4" entry has a UID of 2000, 
# logging in as "test4" will use UID 1000. Effectively, the UID is shared, which 
# is a security problem.
#.

audit_duplicate_users () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Duplicate Users"
    audit_duplicate_ids 1 users name /etc/passwd
    audit_duplicate_ids 3 users id /etc/passwd
  fi
}

# audit_duplicate_groups
#
# Duplicate groups may result in escalation of privileges through administative 
# error.
# Although the groupadd program will not let you create a duplicate Group ID 
# (GID), it is possible for an administrator to manually edit the /etc/group 
# file and change the GID field.
# 
# Although the groupadd program will not let you create a duplicate group name, 
# it is possible for an administrator to manually edit the /etc/group file and 
# change the group name.
# If a group is assigned a duplicate group name, it will create and have access 
# to files with the first GID for that group in /etc/groups. Effectively, the 
# GID is shared, which is a security problem.
#.

audit_duplicate_groups () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Duplicate Groups"
    audit_duplicate_ids 1 groups name /etc/group
    audit_duplicate_ids 3 groups id /etc/group
  fi
}

# audit_netrc_files
#
# .netrc files contain data for logging into a remote host for file transfers 
# via FTP
# The .netrc file presents a significant security risk since it stores passwords 
# in unencrypted form.
#.

audit_netrc_files () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "User Netrc Files"
    audit_dot_files .netrc
  fi
}

# audit_forward_files
#
# .forward files should be inspected to make sure information is not leaving 
# the organisation
#
# The .forward file specifies an email address to forward the user's mail to.
# Use of the .forward file poses a security risk in that sensitive data may be 
# inadvertently transferred outside the organization. The .forward file also 
# poses a risk as it can be used to execute commands that may perform unintended 
# actions.
#.

audit_forward_files () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "User Forward Files"
    audit_dot_files .forward
  fi
}

# audit_writable_files
#
# Unix-based systems support variable settings to control access to files. 
# World writable files are the least secure. See the chmod(2) man page for more 
# information.
# Data in world-writable files can be modified and compromised by any user on 
# the system. World writable files may also indicate an incorrectly written 
# script or program that could potentially be the cause of a larger compromise 
# to the system's integrity.
#.

audit_writable_files () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "World Writable Files"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  For world writable files [This might take a while]"
    fi
    log_file="worldwritable.log"
    total=`expr $total + 1`
    if [ "$audit_mode" = 0 ]; then
      log_file="$work_dir/$log_file"
    fi
    if [ "$audit_mode" != 2 ]; then
      for check_file in `find / \( -fstype nfs -o -fstype cachefs \
        -o -fstype autofs -o -fstype ctfs -o -fstype mntfs \
        -o -fstype objfs -o -fstype proc \) -prune \
        -o -type f -perm -0002 -print`; do
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   File $check_file is world writable [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "chmod o-w $check_file" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          echo "$check_file" >> $log_file
          echo "Setting:   File $check_file non world writable [$score]"
          chmod o-w $check_file
        fi
      done
    fi
    if [ "$audit_mode" = 2 ]; then
      restore_file="$restore_dir/$log_file"
      if [ -f "$restore_file" ]; then
        for check_file in `cat $restore_file`; do
          if [ -f "$check_file" ]; then
            echo "Restoring: File $check_file to previous permissions"
            chmod o+w $check_file
          fi
        done
      fi
    fi
  fi
}

# audit_suid_files
#
# The owner of a file can set the file's permissions to run with the owner's or 
# group's permissions, even if the user running the program is not the owner or 
# a member of the group. The most common reason for a SUID/SGID program is to 
# enable users to perform functions (such as changing their password) that 
# require root privileges.
# There are valid reasons for SUID/SGID programs, but it is important to 
# identify and review such programs to ensure they are legitimate.
#.

audit_suid_files () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Set UID/GID Files"
    if [ "$audit_mode" = 1 ]; then
      echo "Checking:  For files with SUID/SGID set [This might take a while]"
      for check_file in `find / \( -fstype nfs -o -fstype cachefs \
        -o -fstype autofs -o -fstype ctfs -o -fstype mntfs \
        -o -fstype objfs -o -fstype proc \) -prune \
        -o -type f \( -perm -4000 -o -perm -2000 \) -print`; do
        echo "Warning:   File $check_file is SUID/SGID"
        file_type=`file $check_file |awk '{print $5}'`
        if [ "$file_type" != "script" ]; then
          elfsign_check=`elfsign verify -e $check_file 2>&1`
          echo "Result:    $elfsign_check"
        else
          echo "Result:    Shell script"
        fi
      done
    fi
  fi
}

# audit_unowned_files
#
# Sometimes when administrators delete users from the password file they 
# neglect to remove all files owned by those users from the system.
# A new user who is assigned the deleted user's user ID or group ID may then 
# end up "owning" these files, and thus have more access on the system than 
# was intended.
#.

audit_unowned_files () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Unowned Files and Directories"
    if [ "$audit_mode" = 1 ]; then
      echo "Checking:  For Un-owned files and directories [This might take a while]"
      for check_file in `find / \( -fstype nfs -o -fstype cachefs \
        -o -fstype autofs -o -fstype ctfs -o -fstype mntfs \
        -o -fstype objfs -o -fstype proc \) -prune \
        -o \( -nouser -o -nogroup \) -print`; do
        total=`expr $total + 1`
        score=`expr $score - 1`
        echo "Warning:   File $check_file is unowned [$score]"
      done
    fi
  fi
}

# audit_extended_attributes
#
# Extended attributes are implemented as files in a "shadow" file system that 
# is not generally visible via normal administration commands without special 
# arguments.
# Attackers or malicious users could "hide" information, exploits, etc. 
# in extended attribute areas. Since extended attributes are rarely used, 
# it is important to find files with extended attributes set.
#.

audit_extended_attributes () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Extended Attributes"
    if [ "$audit_mode" = 1 ]; then
      echo "Checking:  For files and directories with extended attributes [This might take a while]"
      for check_file in `find / \( -fstype nfs -o -fstype cachefs \
        -o -fstype autofs -o -fstype ctfs -o -fstype mntfs \
        -o -fstype objfs -o -fstype proc \) -prune \
        -o -xattr -print`; do
        total=`expr $total + 1`
        score=`expr $score - 1`
        echo "Warning:   File $check_file has extended attributes [$score]"
      done
    fi
  fi
}

# audit_process_accounting
#
# Enable process accounting at boot time
# Process accounting logs information about every process that runs to 
# completion on the system, including the amount of CPU time, memory, etc. 
# consumed by each process.
#.

audit_process_accounting () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Process Accounting"
    check_file="/etc/rc3.d/S99acct"
    init_file="/etc/init.d/acct"
    log_file="$work_dir/acct.log"
    total=`expr $total + 1`
    if [ ! -f "$check_file" ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   Process accounting not enabled [$score]"
      fi
      if [ "$audit_mode" = 0 ]; then
        echo "Setting:   Process accounting to enabled"
        echo "disabled" > $log_file
        ln -s $init_file $check_file
        echo "Notice:    Starting Process accounting"
        $init_file start 2>&1 > /dev/null
      fi
    else
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score + 1`
        echo "Secure:    Process accounting not enabled [$score]"
      fi
      if [ "$audit_mode" = 2 ]; then
        log_file="$restore_dir/acct.log"
        if [ -f "$log_file" ]; then
          rm $check_file
          echo "Restoring: Process accounting to disabled"
          echo "Notice:    Stoping Process accounting"
          $init_file stop 2>&1 > /dev/null
        fi
      fi
    fi
  fi
}

# audit_dfstab
#
# The commands in the dfstab file are executed via the /usr/sbin/shareall 
# script at boot time, as well as by administrators executing the shareall 
# command during the uptime of the machine.
# It seems prudent to use the absolute pathname to the share command to 
# protect against any exploits stemming from an attack on the administrator's 
# PATH environment, etc. However, if an attacker is able to corrupt root's path 
# to this extent, other attacks seem more likely and more damaging to the 
# integrity of the system
#.

audit_dfstab () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Full Path Names in Exports"
    funct_replace_value /etc/dfs/dfstab share /usr/bin/share start
  fi
}

# audit_power_management
#
# The settings in /etc/default/power control which users have access to the 
# configuration settings for the system power management and checkpoint and 
# resume features. By setting both values to -, configuration changes are 
# restricted to only the root user.
#.

audit_power_management () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Power Management"
    total=`expr $total + 1`
    if [ "$os_version" = "10" ]; then
      funct_file_value /etc/default/power PMCHANGEPERM eq "-" hash
      funct_file_value /etc/default/power CPRCHANGEPERM eq "-" hash
    fi
    if [ "$os_version" = "11" ]; then
      poweradm_test=`poweradm list |grep suspend |awk '{print $2}' |cut -f2 -d"="`
      log_file="poweradm.log"
      if [ "$audit_mode" = 2 ]; then
        log_file="$restore_dir"
        if [ -f "$log_file" ]; then
          restore_value=`cat $log_file`
          if [ "$poweradm_test" != "$restore_value" ]; then
            echo "Restoring: Power suspend to $restore_value"
            poweradm set suspend-enable=$restore_value
            poweradm update
          fi
        fi
      fi
      if [ "$poweradm_test" != "false" ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   Power suspend enabled [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "poweradm set suspend-enable=false" fix
          funct_verbose_message "poweradm update" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          log_file="$work_dir/$log_file"
          echo "Setting:   Power suspend to disabled"
          echo "$poweradm_test" > $log_file
          poweradm set suspend-enable=false
          poweradm update
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Power suspend disabled [$score]"
        fi
      fi
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Power Management"
    service_name="apmd"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_email_services
#
# Remote mail clients (like Eudora, Netscape Mail and Kmail) may retrieve mail 
# from remote mail servers using IMAP, the Internet Message Access Protocol, 
# or POP, the Post Office Protocol. If this system is a mail server that must 
# offer the POP protocol then either qpopper or cyrus may be activated.
#.

audit_email_services () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Cyrus IMAP Daemon"
    service_name="cyrus"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 3 off
    funct_verbose_message "IMAP Daemon"
    service_name="imapd"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 3 off
    funct_verbose_message "Qpopper POP Daemon"
    service_name="qpopper"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 3 off
  fi
}

# audit_sys_suspend
#
# The /etc/default/sys-suspend settings control which users are allowed to use 
# the sys-suspend command to shut down the system.
# Bear in mind that users with physical access to the system can simply remove 
# power from the machine if they are truly motivated to take the system 
# off-line, and granting sys-suspend access may be a more graceful way of 
# allowing normal users to shut down their own machines.
#.

audit_sys_suspend () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "System Suspend"
    funct_file_value /etc/default/sys-suspend PERMS eq "-" hash
  fi
}

# audit_rhosts_files
#
# The /.rhosts, /.shosts, and /etc/hosts.equiv files enable a weak form of 
# access control. Attackers will often target these files as part of their 
# exploit scripts. By linking these files to /dev/null, any data that an 
# attacker writes to these files is simply discarded (though an astute 
# attacker can still remove the link prior to writing their malicious data).
#.

audit_rhosts_files () {
  if [ "$os_name" = "SunOS" ]; then 
    funct_verbose_message "Rhosts Files"
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  Rhosts files"
      fi
      for check_file in /.rhosts /.shosts /etc/hosts.equiv; do
        funct_file_exists $check_file no
      done
    fi
  fi
  if [ "$os_name" = "Linux" ]; then 
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Rhosts files"
    fi
    for check_file in /.rhosts /.shosts /etc/hosts.equiv; do
      funct_file_exists $check_file no
    done
  fi
}

# audit_inetd
#
# If the actions in this section result in disabling all inetd-based services, 
# then there is no point in running inetd at boot time.
#.

audit_inetd () {
  if [ "$os_name" = "SunOS" ]; then 
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Internet Services"
      service_name="svc:/network/inetd:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_ssh_forwarding
#
# This one is optional, generally required for apps
#.

audit_ssh_forwarding () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ] || [ "$os_name" = "Darwin" ]; then
    if [ "$os_name" = "Darwin" ]; then
      check_file="/etc/sshd_config"
    else
      check_file="/etc/ssh/sshd_config"
    fi
    funct_verbose_message "SSH Forwarding"
    funct_file_value $check_file AllowTcpForwarding space yes hash
  fi
}

# audit_issue_banner
#
# The contents of the /etc/issue file are displayed prior to the login prompt 
# on the system's console and serial devices, and also prior to logins via 
# telnet. /etc/motd is generally displayed after all successful logins, no 
# matter where the user is logging in from, but is thought to be less useful 
# because it only provides notification to the user after the machine has been 
# accessed.
# Warning messages inform users who are attempting to login to the system of 
# their legal status regarding the system and must include the name of the 
# organization that owns the system and any monitoring policies that are in 
# place. Consult with your organization's legal counsel for the appropriate 
# wording for your specific organization.
#.

audit_issue_banner () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Security Warning Message"
    total=`expr $total + 1`
    check_file="/etc/issue"
    issue_check=0
    if [ -f "$check_file" ]; then
      issue_check=`cat $check_file |grep 'NOTICE TO USERS' |wc -l`
    fi
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Security message in $check_file"
      if [ "$issue_check" != 1 ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   No security message in $check_file [$score]"
        fi
        if [ "$audit_mode" = 0 ]; then
          echo "Setting:   Security message in $check_file"
          funct_backup_file $check_file
          echo "" > $check_file
          echo "                            NOTICE TO USERS" >> $check_file
          echo "                            ---------------" >> $check_file
          echo "This computer system is the private property of $company_name, whether" >> $check_file
          echo "individual, corporate or government. It is for authorized use only. Users" >> $check_file
          echo "(authorized & unauthorized) have no explicit/implicit expectation of privacy" >> $check_file
          echo "" >> $check_file
          echo "Any or all uses of this system and all files on this system may be" >> $check_file
          echo "intercepted, monitored, recorded, copied, audited, inspected, and disclosed" >> $check_file
          echo "to your employer, to authorized site, government, and/or law enforcement" >> $check_file
          echo "personnel, as well as authorized officials of government agencies, both" >> $check_file
          echo "domestic and foreign." >> $check_file
          echo "" >> $check_file
          echo "By using this system, the user expressly consents to such interception," >> $check_file
          echo "monitoring, recording, copying, auditing, inspection, and disclosure at the" >> $check_file
          echo "discretion of such officials. Unauthorized or improper use of this system" >> $check_file
          echo "may result in civil and criminal penalties and administrative or disciplinary" >> $check_file
          echo "action, as appropriate. By continuing to use this system you indicate your" >> $check_file
          echo "awareness of and consent to these terms and conditions of use. LOG OFF" >> $check_file
          echo "IMMEDIATELY if you do not agree to the conditions stated in this warning." >> $check_file
          echo "" >> $check_file
        fi
      else
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    Security message in $check_file [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_smbpasswd_perms
#
# Set the permissions of the smbpasswd file to 600, so that the contents of 
# the file can not be viewed by any user other than root
# If the smbpasswd file were set to read access for other users, the lanman 
# hashes could be accessed by an unauthorized user and cracked using various 
# password cracking tools. Setting the file to 600 limits access to the file 
# by users other than root.
#.

audit_smbpasswd_perms () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "SMB Password File"
    funct_check_perms /etc/sfw/private/smbpasswd 0600 root root
  fi
}

# audit_smbconf_perms
#
# The smb.conf file is the configuration file for the Samba suite and contains 
# runtime configuration information for Samba.
# All configuration files must be protected from tampering.
#.

audit_smbconf_perms () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "SMB Config Permissions"
    funct_check_perms /etc/samba/smb.conf 0644 root root
  fi
}

# audit_syslog_perms
#
# The log file for sendmail (by default in Solaris 10, /var/log/syslog) 
# is set to 644 so that sendmail (running as root) can write to the file and 
# anyone can read the file.
# Setting the log file /var/log/syslog to 644 allows sendmail (running as root) 
# to create entries, but prevents anyone (other than root) from modifying the 
# log file, thus rendering the log data worthless.
#.

audit_syslog_perms () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Syslog Permissions"
    funct_check_perms /var/log/syslog 0640 root sys
  fi
}

# audit_rarp
#
# rarp: Turn off rarp if not in use
# rarp is required for jumpstart servers
#.

audit_rarp () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "RARP Daemon"
      service_name="svc:/network/rarp:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_wins
#
# Turn off wins if not required
#.

audit_wins () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "WINS Daemon"
      service_name="svc:/network/wins:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "RARP Daemon"
    service_name="rarpd"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_winbind
#
# Turn off winbind if not required
#.

audit_winbind () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Winbind Daemon"
      service_name="svc:/network/winbind:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Winbind Daemon"
    service_name="winbind"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_bootparams
#
# Turn off bootparams if not required
# Required for jumpstart servers
#.

audit_bootparams () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Bootparams Daemon"
      service_name="svc:/network/rpc/bootparams:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Bootparams Daemon"
    service_name="bootparamd"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_postgresql
#
# Turn off postgresql if not required
# Recommend removing this from base install as it slows down patching significantly
#.

audit_postgresql () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "PostgreSQL Database"
      service_name="svc:/application/database/postgresql_83:default_32bit"
      funct_service $service_name disabled
      service_name="svc:/application/database/postgresql_83:default_64bit"
      funct_service $service_name disabled
      service_name="svc:/application/database/postgresql:version_81"
      funct_service $service_name disabled
      service_name="svc:/application/database/postgresql:version_82"
      funct_service $service_name disabled
      service_name="svc:/application/database/postgresql:version_82_64bit"
      funct_service $service_name disabled
    fi
  fi  
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "PostgreSQL Database"
    service_name="postgresql"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_webmin
#
# Webmin is a web-based system configuration tool for Unix-like systems, 
# although recent versions can also be installed and run on Windows.
# With it, it is possible to configure operating system internals, such 
# as users, disk quotas, services or configuration files, as well as modify 
# and control open source apps, such as the Apache HTTP Server, PHP or MySQL.
#
# Turn off webmin if it is not being used.
#.

audit_webmin () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Webmin Daemon"
      service_name="svc:/application/management/webmin:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_dns_server
#
# The Domain Name System (DNS) is a hierarchical distributed naming system 
# for computers, services, or any resource connected to the Internet or a 
# private network. It associates various information with domain names 
# assigned to each of the participating entities. 
# In general servers will be clients of an upstream DNS server within an
# organisation so do not need to provide DNS server services themselves.
# An obvious exception to this is DNS servers themselves and servers that
# provide boot and install services such as Jumpstart or Kickstart servers.
#.

audit_dns_server () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "DNS Server"
      service_name="svc:/network/dns/server:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "DNS Server"
    for service_name in avahi avahi-autoipd avahi-daemon avahi-dnsconfd named; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_avahi_conf
#
# The multicast Domain Name System (mDNS) is a zero configuration host name 
# resolution service. It uses essentially the same programming interfaces, 
# packet formats and operating semantics as the unicast Domain Name System 
# (DNS) to resolve host names to IP addresses within small networks that do 
# not include a local name server, but can also be used in conjunction with 
# such servers.
# It is best to turn off mDNS in a server environment, but if it is used then
# the services advertised should be restricted.
#.

audit_avahi_conf () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Multicast DNS Server"
    check_file="/etc/avahi/avahi-daemon.conf"
    funct_file_value $check_file disable-user-service-publishing eq yes hash after "\[publish\]"
    funct_file_value $check_file disable-publishing eq yes hash after "\[publish\]"
    funct_file_value $check_file publish-address eq no hash after "\[publish\]"
    funct_file_value $check_file publish-binfo eq no hash after "\[publish\]"
    funct_file_value $check_file publish-workstation eq no hash after "\[publish\]"
    funct_file_value $check_file publish-domain eq no hash after "\[publish\]"
    funct_file_value $check_file disallow-other-stacks eq yes hash after "\[server\]"
    funct_file_value $check_file check-response-ttl eq yes hash after "\[server\]"
  fi
}

# audit_dns_client
#
# Nscd is a daemon that provides a cache for the most common name service 
# requests. The default configuration file, /etc/nscd.conf, determines the 
# behavior of the cache daemon.
# Unless required disable Name Server Caching Daemon as it can result in
# stale or incorrect DNS information being cached by the system.
#.

audit_dns_client () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Name Server Caching Daemon"
    for service_name in nscd; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_ntp
#
# Network Time Protocol (NTP) is a networking protocol for clock synchronization 
# between computer systems.
# Most security mechanisms require network time to be synchronized.
#.

audit_ntp () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Network Time Protocol"
    check_file="/etc/inet/ntp.conf"
    funct_file_value $check_file server space pool.ntp.org hash
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      service_name="svc:/network/ntp4:default"
      funct_service $service_name enabled
    fi
  fi
  if [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Network Time Protocol"
    check_file="/private/etc/hostconfig"
    funct_file_value $check_file TIMESYNC eq -YES- hash
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Network Time Protocol"
    check_file="/etc/ntp.conf"
    total=`expr $total + 1`
    log_file="ntp.log"
    audit_linux_package check ntp
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  NTP is enabled"
    fi
    if [ "$package_name" != "ntp" ]; then
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score - 1`
        echo "Warning:   NTP not enabled [$score]"
      fi
      if [ "$audit_mode" = 0 ]; then
        echo "Setting:   NTP to enabled"
        log_file="$work_dir/$log_file"
        echo "Installed ntp" >> $log_file
        audit_linux_package install ntp
      fi
    else
      if [ "$audit_mode" = 1 ]; then
        score=`expr $score + 1`
        echo "Secure:    NTP enabled [$score]"
      fi
      if [ "$audit_mode" = 2 ]; then
        restore_file="$restore_dir/$log_file"
        audit_linux_package restore ntp $restore_file
      fi
    fi
    service_name="ntp"
    funct_chkconfig_service $service_name 3 on 
    funct_chkconfig_service $service_name 5 on
    funct_append_file $check_file "restrict default kod nomodify nopeer notrap noquery" hash
    funct_append_file $check_file "restrict -6 default kod nomodify nopeer notrap noquery" hash
    funct_file_value $check_file OPTIONS eq "-u ntp:ntp -p /var/run/ntpd.pid" hash
  fi
}

# audit_krb5
#
# Turn off kerberos if not required
#.

audit_krb5 () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Kerberos"
      service_name="svc:/network/security/krb5kdc:default"
      funct_service $service_name disabled
      service_name="svc:/network/security/kadmin:default"
      funct_service $service_name disabled
      service_name="svc:/network/security/krb5_prop:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Kerberos"
    for service_name in kadmin kprop krb524 krb5kdc; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_routing_daemons
#
# Turn off routing services if not required
#.

audit_routing_daemons () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Routing Daemons"
      service_name="svc:/network/routing/zebra:quagga"
      funct_service $service_name disabled
      service_name="svc:/network/routing/ospf:quagga"
      funct_service $service_name disabled
      service_name="svc:/network/routing/rip:quagga"
      funct_service $service_name disabled
      service_name="svc:/network/routing/ripng:default"
      funct_service $service_name disabled
      service_name="svc:/network/routing/ripng:quagga"
      funct_service $service_name disabled
      service_name="svc:/network/routing/ospf6:quagga"
      funct_service $service_name disabled
      service_name="svc:/network/routing/bgp:quagga"
      funct_service $service_name disabled
      service_name="svc:/network/routing/legacy-routing:ipv4"
      funct_service $service_name disabled
      service_name="svc:/network/routing/legacy-routing:ipv6"
      funct_service $service_name disabled
      service_name="svc:/network/routing/rdisc:default"
      funct_service $service_name disabled
      service_name="svc:/network/routing/route:default"
      funct_service $service_name disabled
      service_name="svc:/network/routing/ndp:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Routing Daemons"
    for service_name in bgpd ospf6d ospfd ripd ripngd; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_ipmi
#
# Turn off ipmi environment daemon
#.

audit_ipmi () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "IPMI Daemons"
      service_name="svc:/network/ipmievd:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "IPMI Daemons"
    for service_name in ipmi; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_apocd
#
# Turn off apocd
#.

audit_apocd () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "APOC Daemons"
      service_name="svc:/network/apocd/udp:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_vnc
#
# Turn off VNC
#.

audit_vnc () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "VNC Daemons"
      service_name="svc:/application/x11/xvnc-inetd:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "VNC Daemons"
    for service_name in vncserver; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_ipsec
#
# Turn off IPSEC
#.

audit_ipsec () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "IPSEC Services"
      service_name="svc:/network/ipsec/manual-key:default"
      funct_service $service_name disabled
      service_name="svc:/network/ipsec/ike:default"
      funct_service $service_name disabled
      service_name="svc:/network/ipsec/ipsecalgs:default"
      funct_service $service_name disabled
      service_name="svc:/network/ipsec/policy:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_ticotsord
#
# Turn off ticotsord
#.

audit_ticotsord () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Ticotsor Daemon"
      service_name="svc:/network/rpc-100235_1/rpc_ticotsord:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_ftp_server
#
# Turn off ftp server
#.

audit_ftp_server () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "FTP Daemon"
      service_name="svc:/network/ftp:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_ipfilter
#
# Turn off IP filter
#.

audit_ipfilter () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "IP Filter"
      service_name="svc:/network/ipfilter:default"
      funct_service $service_name disabled
      service_name="svc:/network/pfil:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_echo
#
# Turn off echo and chargen services
#.

audit_echo () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Echo and Chargen Services"
      service_name="svc:/network/echo:dgram"
      funct_service $service_name disabled
      service_name="svc:/network/echo:stream"
      funct_service $service_name disabled
      service_name="svc:/network/time:dgram"
      funct_service $service_name disabled
      service_name="svc:/network/time:stream"
      funct_service $service_name disabled
      service_name="svc:/network/tname:default"
      funct_service $service_name disabled
      service_name="svc:/network/comsat:default"
      funct_service $service_name disabled
      service_name="svc:/network/discard:dgram"
      funct_service $service_name disabled
      service_name="svc:/network/discard:stream"
      funct_service $service_name disabled
      service_name="svc:/network/chargen:dgram"
      funct_service $service_name disabled
      service_name="svc:/network/chargen:stream"
      funct_service $service_name disabled
      service_name="svc:/network/rpc/spray:default"
      funct_service $service_name disabled
      service_name="svc:/network/daytime:dgram"
      funct_service $service_name disabled
      service_name="svc:/network/daytime:stream"
      funct_service $service_name disabled
      service_name="svc:/network/talk:default"
      funct_service $service_name disabled
    fi
  fi
#  if [ "$os_name" = "Linux" ]; then
#    funct_verbose_message "Telnet and Rlogin Services"
#    for service_name in telnet login rlogin rsh shell; do
#      funct_chkconfig_service $service_name 3 off
#      funct_chkconfig_service $service_name 5 off
#    done
#  fi
}

# audit_remote_shell
#
# Turn off remote shell services
#.

audit_remote_shell () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Telnet and Rlogin Services"
      service_name="svc:/network/shell:kshell"
      funct_service $service_name disabled
      service_name="svc:/network/login:eklogin"
      funct_service $service_name disabled
      service_name="svc:/network/login:klogin"
      funct_service $service_name disabled
      service_name="svc:/network/rpc/rex:default"
      funct_service $service_name disabled
      service_name="svc:/network/rexec:default"
      funct_service $service_name disabled
      service_name="svc:/network/shell:default"
      funct_service $service_name disabled
      service_name="svc:/network/login:rlogin"
      funct_service $service_name disabled
      service_name="svc:/network/telnet:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Telnet and Rlogin Services"
    for service_name in telnet login rlogin rsh shell; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_font_server
#
# Turn off cont server
#.

audit_font_server () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Font Server"
      service_name="svc:/application/x11/xfs:default"
      funct_service $service_name disabled
      service_name="svc:/application/font/stfsloader:default"
      funct_service $service_name disabled
      service_name="svc:/application/font/fc-cache:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Font Server"
    for service_name in xfs; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_remote_info
#
# Turn off remote info services like rstat and finger
#.

audit_remote_info () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Remote Information Services"
      service_name="svc:/network/rpc/rstat:default"
      funct_service $service_name disabled
      service_name="svc:/network/nfs/rquota:default"
      funct_service $service_name disabled
      service_name="svc:/network/rpc/rusers:default"
      funct_service $service_name disabled
      service_name="svc:/network/finger:default"
      funct_service $service_name disabled
      service_name="svc:/network/rpc/wall:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_nfs
#
# Turn off NFS services
#.

audit_nfs () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "NFS Services"
      service_name="svc:/network/nfs/mapid:default"
      funct_service $service_name disabled
      service_name="svc:/network/nfs/status:default"
      funct_service $service_name disabled
      service_name="svc:/network/nfs/cbd:default"
      funct_service $service_name disabled
      service_name="svc:/network/nfs/nlockmgr:default"
      funct_service $service_name disabled
      service_name="svc:/network/nfs/client:default"
      funct_service $service_name disabled
      service_name="svc:/network/nfs/server:default"
      funct_service $service_name disabled
    fi
    if [ "$os_version" != "11" ]; then
      service_name="nfs.server"
      funct_service $service_name disabled
    fi
    check_file="/etc/system"
    funct_file_value $check_file "nfssrv:nfs_portmon" eq 1 star
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "NFS Services"
    for service_name in nfs nfslock portmap rpc; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_tftp_server
#
# Turn off tftp
#.

audit_tftp_server () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "TFTPD Daemon"
      service_name="svc:/network/tftp/udp6:default"
      funct_service $service_name disabled
      service_name="svc:/network/tftp/udp4:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "TFTPD Daemon"
    funct_chkconfig_service tftp 3 off
    funct_chkconfig_service tftp 5 off
    if [ -e "/tftpboot" ]; then
      funct_check_perms /tftpboot 0744 root root
    fi
  fi  
}

# audit_dhcp_server
#
# Turn off dhcp server
#.

audit_dhcp_server () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "DHCP Server"
      service_name="svc:/network/dhcp-server:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_iscsi
#
# Turn off iscsi target
#.

audit_iscsi () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "iSCSI Target Service"
      service_name="svc:/system/iscsitgt:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "iSCSI Target Service"
    service_name="iscsi"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
    service_name="iscsd"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_boot_server
#
# Turn off boot services
#.

audit_boot_server () {
  audit_rarp
  audit_bootparams
  audit_tftp_server
  audit_dhcp_server
}

# audit_uucp
#
# Turn off uucp and swat
#.

audit_uucp () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Samba Web Configuration Deamon"
      service_name="svc:/network/swat:default"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "UUCP Service"
      service_name="uucp"
      funct_service $service_name disabled
    fi
  fi
}

# audit_ocfserv
#
# Turn off ocfserv
#.

audit_ocfserv () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "OCF Service"
      service_name="svc:/network/rpc/ocfserv:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_hotplug
#
# Turn off hotplug
#.

audit_hotplug () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Hotplug Service"
      service_name="svc:/system/hotplug:default"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Hardware Daemons"
    service_name="pcscd"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
    service_name="haldaemon"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
    service_name="kudzu"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_tname
#
# Turn off tname
#.

audit_tname () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Tname Daemon"
      service_name="svc:/network/tname:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_slp
#
# Turn off slp
#.

audit_slp () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "SLP Daemon"
      service_name="svc:/network/slp:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_tnd
#
# Turn off tnd
#.

audit_tnd () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "TN Daemon"
      service_name="svc:/network/tnd:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_labeld
#
# Turn off labeld
#.

audit_labeld () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Label Daemon"
      service_name="svc:/system/labeld:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_ldap
#
# Turn off ldap
#.

audit_ldap () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "LDAP Client"
      service_name="svc:/network/ldap/client:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_kdm_config
#
# Turn off kdm config
#.

audit_kdm_config () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Graphics Configuration"
      service_name="svc:/platform/i86pc/kdmconfig:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_bpcd
#
# BPC 
#
# Turn off bpcd
#.

audit_bpcd () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "BPC Daemon"
      service_name="svc:/network/bpcd/tcp:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_vnetd
#
# VNET Daemon
#
# Turn off vnetd
#.

audit_vnetd () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "VNET Daemon"
      service_name="svc:/network/vnetd/tcp:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_vopied
#
# Veritas Online Passwords In Everything
#
# Turn off vopied if not required. It is associated with Symantec products.
#.

audit_vopied () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "VOPIE Daemon"
      service_name="svc:/network/vopied/tcp:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_bpjava_msvc
#
# BPJava Service
#
# Turn off bpjava-msvc if not required. It is associated with NetBackup.
#.

audit_bpjava_msvc () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "BPJava Service"
      service_name="svc:/network/bpjava-msvc/tcp:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_service_tags
#
# A service tag enables automatic discovery of assets, including software and 
# hardware. A service tag uniquely identifies each tagged asset, and allows 
# information about the asset to be shared over a local network in a standard 
# XML format.
# Turn off Service Tags if not being used. It can provide information that can
# be used as vector of attack.
#.

audit_service_tags () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "Service Tags Daemons"
      service_name="svc:/network/stdiscover:default"
      funct_service $service_name disabled
      service_name="svc:/network/stlisten:default"
      funct_service $service_name disabled
      service_name="svc:/application/stosreg:default"
      funct_service $service_name disabled
    fi
  fi
}

# audit_zones
#
# Operating system-level virtualization is a server virtualization method 
# where the kernel of an operating system allows for multiple isolated 
# user-space instances, instead of just one. Such instances (often called 
# containers, VEs, VPSs or jails) may look and feel like a real server, 
# from the point of view of its owner. 
#
# Turn off Zone services if zones are not being used.
#.

audit_zones () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      zone_check=`zoneadm list -civ |awk '{print $1}' |grep 1`
      if [ "$zone_check" != "1" ]; then
        funct_verbose_message "Zone Daemons"
        service_name="svc:/system/rcap:default"
        funct_service $service_name disabled
        service_name="svc:/system/pools:default"
        funct_service $service_name disabled
        service_name="svc:/system/tsol-zones:default"
        funct_service $service_name disabled
        service_name="svc:/system/zones:default"
        funct_service $service_name disabled
      fi
    fi
  fi
}

# audit_xen
#
# Xen is a hypervisor providing services that allow multiple computer 
# operating systems to execute on the same computer hardware concurrently.
#
# Turn off Xen services if they are not being used.
#.

audit_xen () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Xen Daemons"
    service_name="xend"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
    service_name="xendomains"
    funct_chkconfig_service $service_name 3 off
    funct_chkconfig_service $service_name 5 off
  fi
}

# audit_snmp
#
# Simple Network Management Protocol (SNMP) is an "Internet-standard protocol 
# for managing devices on IP networks". Devices that typically support SNMP 
# include routers, switches, servers, workstations, printers, modem racks, and 
# more. It is used mostly in network management systems to monitor network-
# attached devices for conditions that warrant administrative attention.
# Turn off SNMP if not used. If SNMP is used lock it down. SNMP can reveal
# configuration information about systems leading to vectors of attack.
#.

audit_snmp () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" = "10" ] || [ "$os_version" = "11" ]; then
      funct_verbose_message "SNMP Daemons"
      service_name="svc:/application/management/seaport:default"
      funct_service $service_name disabled
      service_name="svc:/application/management/snmpdx:default"
      funct_service $service_name disabled
      service_name="svc:/application/management/dmi:default"
      funct_service $service_name disabled
      service_name="svc:/application/management/sma:default"
      funct_service $service_name disabled
    fi
    if [ "$os_version" = "10" ]; then
      funct_verbose_message "SNMP Daemons"
      service_name="init.dmi"
      funct_service $service_name disabled
      service_name="init.sma"
      funct_service $service_name disabled
      service_name="init.snmpdx"
      funct_service $service_name disabled
    fi
  fi
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "SNMP Daemons"
    funct_rpm_check net-snmp
    if [ "$rpm_check" = "net-snmp" ]; then
      service_name="snmpd"
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
      service_name="snmptrapd"
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
      funct_append_file /etc/snmp/snmpd.conf "com2sec notConfigUser default public" hash
    fi
  fi
}

# audit_modprobe_conf
#
# Check entries are in place so kernel modules can't be force loaded.
# Some modules may getting unintentionally loaded that could reduce system
# security.
#.

audit_modprobe_conf () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Modprobe Configuration"
    check_file="/etc/modprobe.conf"
    funct_append_file $check_file "install tipc /bin/true"
    funct_append_file $check_file "install rds /bin/true"
    funct_append_file $check_file "install sctp /bin/true"
    funct_append_file $check_file "install dccp /bin/true"
    #funct_append_file $check_file "install udf /bin/true"
    #funct_append_file $check_file "install squashfs /bin/true"
    #funct_append_file $check_file "install hfs /bin/true"
    #funct_append_file $check_file "install hfsplus /bin/true"
    #funct_append_file $check_file "install jffs2 /bin/true"
    #funct_append_file $check_file "install freevxfs /bin/true"
    #funct_append_file $check_file "install cramfs /bin/true"
  fi
}

# audit_sysctl
#
# Network tuning parameters for sysctl under Linux.
# Check and review to see which are suitable for you environment.
#.

audit_sysctl () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Sysctl Configuration"
    check_file="/etc/sysctl.conf"
    funct_file_value $check_file net.ipv4.conf.default.secure_redirects eq 0 hash
    funct_file_value $check_file net.ipv4.conf.all.secure_redirects eq 0 hash
    funct_file_value $check_file net.ipv4.icmp_echo_ignore_broadcasts eq 1 hash
    funct_file_value $check_file net.ipv4.conf.all.accept_redirects eq 0 hash
    funct_file_value $check_file net.ipv4.conf.default.accept_redirects eq 0 hash
    funct_file_value $check_file net.ipv4.tcp_syncookies eq 1 hash
    funct_file_value $check_file net.ipv4.tcp_max_syn_backlog eq 4096 hash
    funct_file_value $check_file net.ipv4.conf.all.rp_filter eq 1 hash
    funct_file_value $check_file net.ipv4.conf.default.rp_filter eq 1 hash
    funct_file_value $check_file net.ipv4.conf.all.accept_source_route eq 0 hash
    funct_file_value $check_file net.ipv4.conf.default.accept_source_route eq 0 hash
    # Disable these if machine used as a firewall or gateway
    funct_file_value $check_file net.ipv4.tcp_max_orphans eq 256 hash
    funct_file_value $check_file net.ipv4.conf.all.log_martians eq 1 hash
    funct_file_value $check_file net.ipv4.ip_forward eq 0 hash
    funct_file_value $check_file net.ipv4.conf.all.send_redirects eq 0 hash
    funct_file_value $check_file net.ipv4.conf.default.send_redirects eq 0 hash
    funct_file_value $check_file net.ipv4.icmp_ignore_bogus_error_responses eq 1 hash
    # IPv6 stuff
    funct_file_value $check_file net.ipv6.conf.default.accept_redirects eq 0 hash
    funct_file_value $check_file net.ipv6.conf.default.accept_ra eq 0 hash
    # Randomise kernel memory placement
    funct_file_value $check_file kernel.randomize_va_space eq 1 hash
    # Configure kernel shield
    funct_file_value $check_file kernel.exec-shield eq 1 hash
    # Restrict core dumps
    funct_file_value $check_file fs.suid.dumpable eq 0 hash
    funct_append_file /etc/security/limits.conf "* hard core 0"
    # Check file permissions
    funct_check_perms $check_file 0600 root root  
  fi
}

# audit_xinetd
#
# Audit xinetd services on Linux. Make sure services that are not required
# are not running. Leaving unrequired services running can lead to vectors
# of attack.
#.

audit_xinetd () {
  if [ "$os_name" = "Linux" ]; then
    check_dir="/etc/xinetd.d"
    if [ -d "$check_dir" ]; then
      funct_verbose_message "Xinet Services"
      xinetd_check=`cat $check_dir/* |grep disable |awk '{print $3}' |grep no |head -1 |wc -l`
      if [ "$xinetd_check" = "1" ]; then
        for service_name in amanda amandaidx amidxtape auth chargen-dgram \
          chargen-stream cvs daytime-dgram daytime-stream discard-dgram \
          echo-dgram echo-stream eklogin ekrb5-telnet gssftp klogin krb5-telnet \
          kshell ktalk ntalk rexec rlogin rsh rsync talk tcpmux-server telnet \
          tftp time-dgram time-stream uucp; do
          audit_xinetd_service $service_name disable yes
        done
      else
        funct_chkconfig_service xinetd 3 off
        funct_chkconfig_service xinetd 5 off
      fi
    fi
  fi
}

# audit_legacy
#
# Turn off inetd and init.d services on Solaris (legacy for Solaris 10+).
# Most of these services have now migrated to the new Service Manifest
# methodology.
#.

audit_legacy () {
  if [ "$os_name" = "SunOS" ]; then
    if [ "$os_version" != "11" ]; then
      funct_verbose_message "Inet Services"
      for service_name in time echo discard daytime chargen fs dtspc \
        exec comsat talk finger uucp name xaudio netstat ufsd rexd \
        systat sun-dr uuidgen krb5_prop 100068 100146 100147 100150 \
        100221 100232 100235 kerbd rstatd rusersd sprayd walld \
        printer shell login telnet ftp tftp 100083 100229 100230 \
        100242 100234 100134 100155 rquotad 100424 100422; do
        funct_inetd_service $service_name disabled
      done
      funct_verbose_message "Init Services"
      for service_name in llc2 pcmcia ppd slpd boot.server autoinstall \
        power bdconfig cachefs.daemon cacheos.finish asppp uucp flashprom \
        PRESERVE ncalogd ncad ab2mgr dmi mipagent nfs.client autofs rpc \
        directory ldap.client lp spc volmgt dtlogin ncakmod samba dhcp \
        nfs.server kdc.master kdc apache snmpdx; do
        funct_initd_service $service_name disabled
      done
    fi
  fi
}
  
# audit_cups
#
# Printing Services Turn off cups if not required on Linux.
#.

audit_cups () {
  if [ "$os_name" = "Linux" ]; then
    funct_rpm_check cups
    if [ "$rpm_check" = "cups" ]; then
      funct_verbose_message "Printing Services"
      service_name="cups"
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
      service_name="cups-lpd"
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
      service_name="cupsrenice"
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
      funct_check_perms /etc/init.d/cups 0744 root root
      funct_check_perms /etc/cups/cupsd.conf 0600 lp sys
      funct_check_perms /etc/cups/client.conf 0644 root lp
      funct_file_value /etc/cups/cupsd.conf User space lp hash
      funct_file_value /etc/cups/cupsd.conf Group space sys hash
    fi
  fi
}

# audit_chkconfig
#
# Check services are turned off via chkconfig in Linux that do not need to be
# enabled. 
# Running services that are not required can leave potential vectors of attack
# open.
#.

audit_chkconfig () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Miscellaneous Services"
    for service_name in wu-ftpd ftp vsftpd aaeventd\
      tftp acpid amd arptables_jg arpwatch atd netfs irda isdn \
      bluetooth capi conman cpuspeed cryrus-imapd dc_client \
      dc_server dhcdbd dhcp6s dhcrelay chargen chargen-udp\
      dovecot dund gpm hidd hplip ibmasm innd ip6tables \
      lisa lm_sensors mailman mctrans mdmonitor mdmpd microcode_ctl \
      mysqld netplugd network NetworkManager openibd \
      pand postfix psacct mutipathd daytime daytime-udp\
      radiusd radvd rdisc readahead_early readahead_later rhnsd \
      rpcgssd rpcimapd rpcsvcgssd rstatd rusersd rwhod saslauthd \
      settroubleshoot smartd spamassasin echo echo-udp\
      time time-udp vnc svcgssd rpmconfigcheck rsh rsync rsyncd \
      saslauthd powerd raw rexec rlogin rpasswdd openct\
      ipxmount joystick esound evms fam gpm gssd pcscd\
      tog-pegasus tux wpa_supplicant zebra ncpfs; do
      funct_chkconfig_service $service_name 3 off
      funct_chkconfig_service $service_name 5 off
    done
  fi
}

# audit_linux_logfiles
#
# Check permission on log files under Linux. Make sure they are only readable
# by system accounts. This stops sensitive system information from being
# disclosed
#.

audit_linux_logfiles () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Log File Permissions"
    for log_file in boot.log btml cron dmesg ksyms httpd lastlog maillog \
      mailman messages news pgsql rpm pkgs sa samba scrollkeeper.log \
      secure spooler squid vbox wtmp; do
      if [ -f "/var/log/$log_file" ]; then
        funct_check_perms /var/log/$log_file 0640 root root
      fi
    done
  fi
}

# audit_passwd_perms
#
# Audit password file permission under Linux. This stops password hashes and
# other information being disclosed. Password hashes can be used to crack
# passwords via brute force cracking tools.
#.

audit_passwd_perms () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Group and Password File Permissions"
    funct_check_perms /etc/group 0644 root root
    funct_check_perms /etc/passwd 0644 root root
    funct_check_perms /etc/gshadow 0400 root root
    funct_check_perms /etc/shadow 0400 root root
  fi
}

# audit_sendmail_greeting
#
# Make sure sendmail greeting does not expose version or system information.
# This reduces information that can be obtained remotely and thus reduces
# vectors of attack.
#.

audit_sendmail_greeting () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    check_file="/etc/mail/sendmail.cf"
    if [ -f "$check_file" ]; then
      funct_verbose_message "Sendmail Greeting"
      search_string="v/"
      restore=0
      if [ "$audit_mode" != 2 ]; then
        total=`expr $total + 1`
        check_value=`cat $check_file |grep -v '^#' |grep 'O SmtpGreetingMessage' |awk '{print $4}' |grep 'v/'`
        if [ "$check_value" = "$search_string" ]; then
          if [ "$audit_mode" = "1" ]; then
            score=`expr $score - 1`
            echo "Warning:   Found version information in sendmail greeting [$score]"
            funct_verbose_message "" fix
            funct_verbose_message "cp $check_file $temp_file" fix
            funct_verbose_message 'cat $temp_file |awk '/O SmtpGreetingMessage=/ { print "O SmtpGreetingMessage=Mail Server Ready; $b"; next} { print }' > $check_file' fix
            funct_verbose_message "rm $temp_file" fix
            funct_verbose_message "" fix
          fi
          if [ "$audit_mode" = 0 ]; then
            funct_backup_file $check_file 
            echo "Setting:   Sendmail greeting to have no version information"
            cp $check_file $temp_file
            cat $temp_file |awk '/O SmtpGreetingMessage=/ { print "O SmtpGreetingMessage=Mail Server Ready; $b"; next} { print }' > $check_file
            rm $temp_file
          fi
        else
          if [ "$audit_mode" = "1" ]; then  
            score=`expr $score + 1`
            echo "Secure:    No version information in sendmail greeting [$score]"
          fi
        fi
      else
        funct_restore_file $check_file $restore_dir
      fi
      funct_disable_value $check_file "O HelpFile" hash
      if [ "$audit_mode" != 2 ]; then
        total=`expr $total + 1`
        check_value=`cat $check_file |grep -v '^#' |grep '$search_string'`
        if [ "$check_value" = "$search_string" ]; then
          if [ "$audit_mode" = "1" ]; then
            score=`expr $score - 1`
            echo "Warning:   Found help information in sendmail greeting [$score]"
          fi
          if [ "$audit_mode" = 0 ]; then
            funct_backup_file $check_file
            echo "Setting:   Sendmail to have no help information"
            cp $check_file $temp_file
            cat $temp_file |sed 's/^O HelpFile=/#O HelpFile=/' > $check_file
            rm $temp_file
          fi
        else
          if [ "$audit_mode" = "1" ]; then  
            score=`expr $score + 1`
            echo "Secure:    No help information in sendmail greeting [$score]"
          fi
        fi
      else
        funct_restore_file $check_file $restore_dir
      fi
      funct_check_perms $check_file 0444 root root
    fi
  fi
}

# audit_sendmail_aliases
#
# Make sure sendmail aliases are configured appropriately.
#.

audit_sendmail_aliases () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Sendmail Aliases"
    check_file="/etc/aliases"
    funct_disable_value $check_file "decode" hash
    funct_check_perms $check_file 0644 root root
  fi
}

# audit_system_auth_nullok
#
# Ensure null passwords are not accepted
#.

audit_system_auth_nullok () {
  if [ "$os_name" = "Linux" ]; then
    if [ "$linux_dist" = "debian" ] || [ "$linux_dist" = "suse" ]; then
      check_file="/etc/pam.d/common-auth"
    fi
    if [ "$linux_dist" = "redhat" ]; then
      check_file="/etc/pam.d/system-auth"
    fi
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  For nullok entry in $check_file"
      total=`expr $total + 1`
      check_value=0
      check_value=`cat $check_file |grep -v '^#' |grep 'nullok' |head -1 |wc -l`
      if [ "$check_value" = 1 ]; then
        if [ "$audit_mode" = "1" ]; then
          score=`expr $score - 1`
          echo "Warning:   Found nullok entry in $check_file [$score]"
          funct_verbose_message "cp $check_file $temp_file" fix
          funct_verbose_message "cat $temp_file |sed 's/ nullok//' > $check_file" fix
          funct_verbose_message "rm $temp_file" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Removing nullok entries from $check_file"
          cp $check_file $temp_file
          cat $temp_file |sed 's/ nullok//' > $check_file
          rm $temp_file
        fi
      else
        if [ "$audit_mode" = "1" ]; then  
          score=`expr $score + 1`
          echo "Secure:    No nullok entries in $check_file [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_system_auth_password_history
#
# Audit the number of remembered passwords
#.

audit_system_auth_password_history () {
  auth_string=$1
  search_string=$2
  search_value=$3
  if [ "$os_name" = "Linux" ]; then
    check_file="/etc/security/opasswd"
    funct_file_exists $check_file 
    funct_check_perms $check_file 0600 root root
    if [ "$linux_dist" = "debian" ] || [ "$linux_dist" = "suse" ]; then
      check_file="/etc/pam.d/common-auth"
    fi
    if [ "$linux_dist" = "redhat" ]; then
      check_file="/etc/pam.d/system-auth"
    fi
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Password entry $search_string set to $search_value in $check_file"
      total=`expr $total + 1`
      check_value=`cat $check_file |grep '^$auth_string' |grep '$search_string$' |awk -F '$search_string=' '{print $2}' |awk '{print $1}'`
      if [ "$check_value" != "$search_value" ]; then
        if [ "$audit_mode" = "1" ]; then
          score=`expr $score - 1`
          echo "Warning:   Password entry $search_string is not set to $search_value in $check_file [$score]"
          funct_verbose_message "cp $check_file $temp_file" fix
          funct_verbose_message "cat $temp_file |awk '( $1 == \"password\" && $3 == \"pam_unix.so\" ) { print $0 \" $search_string=$search_value\"; next };' > $check_file" fix
          funct_verbose_message "rm $temp_file" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Password entry in $check_file"
          cp $check_file $temp_file
          cat $temp_file |awk '( $1 == "password" && $3 == "pam_unix.so" ) { print $0 " $search_string=$search_value"; next };' > $check_file
          rm $temp_file
        fi
      else
        if [ "$audit_mode" = "1" ]; then  
          score=`expr $score + 1`
          echo "Secure:    Password entry $search_string set to $search_value in $check_file [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_system_auth_no_magic_root
#
# Make sure root account isn't locked as part of account locking
#.

audit_system_auth_no_magic_root () {
  auth_string=$1
  search_string=$2
  if [ "$os_name" = "Linux" ]; then
    if [ "$linux_dist" = "debian" ] || [ "$linux_dist" = "suse" ]; then
      check_file="/etc/pam.d/common-auth"
    fi
    if [ "$linux_dist" = "redhat" ]; then
      check_file="/etc/pam.d/system-auth"
    fi
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Auth entry not enabled in $check_file"
      total=`expr $total + 1`
      check_value=`cat $check_file |grep '^$auth_string' |grep '$search_string$' |awk '{print $5}'`
      if [ "$check_value" != "$search_string" ]; then
        if [ "$audit_mode" = "1" ]; then
          score=`expr $score - 1`
          echo "Warning:   Auth entry not enabled in $check_file [$score]"
          funct_verbose_message "rm $temp_file" fix
          funct_verbose_message "cat $temp_file |awk '( $1 == \"auth\" && $2 == \"required\" && $3 == \"pam_deny.so\" ) { print \"auth\trequired\tpam_tally2.so onerr=fail no_magic_root\"; print $0; next };' > $check_file" fix
          funct_verbose_message "rm $temp_file" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Auth entry in $check_file"
          cp $check_file $temp_file
          cat $temp_file |awk '( $1 == "auth" && $2 == "required" && $3 == "pam_deny.so" ) { print "auth\trequired\tpam_tally2.so onerr=fail no_magic_root"; print $0; next };' > $check_file
          rm $temp_file
        fi
      else
        if [ "$audit_mode" = "1" ]; then  
          score=`expr $score + 1`
          echo "Secure:    Auth entry enabled in $check_file [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_system_auth_account_reset
#
# Reset attempt counter to 0 after number of tries have been used
#.

audit_system_auth_account_reset () {
  auth_string=$1
  search_string=$2
  if [ "$os_name" = "Linux" ]; then
    if [ "$linux_dist" = "debian" ] || [ "$linux_dist" = "suse" ]; then
      check_file="/etc/pam.d/common-auth"
    fi
    if [ "$linux_dist" = "redhat" ]; then
      check_file="/etc/pam.d/system-auth"
    fi
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Account reset entry not enabled in $check_file"
      total=`expr $total + 1`
      check_value=`cat $check_file |grep '^$auth_string' |grep '$search_string$' |awk '{print $6}'`
      if [ "$check_value" != "$search_string" ]; then
        if [ "$audit_mode" = "1" ]; then
          score=`expr $score - 1`
          echo "Warning:   Account reset entry not enabled in $check_file [$score]"
          funct_verbose_message "cp $check_file $temp_file" fix
          funct_verbose_message "cat $temp_file |awk '( $1 == \"account\" && $2 == \"required\" && $3 == \"pam_permit.so\" ) { print \"auth\trequired\tpam_tally2.so onerr=fail no_magic_root reset\"; print $0; next };' > $check_file" fix
          funct_verbose_message "rm $temp_file" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Account reset entry in $check_file"
          cp $check_file $temp_file
          cat $temp_file |awk '( $1 == "account" && $2 == "required" && $3 == "pam_permit.so" ) { print "auth\trequired\tpam_tally2.so onerr=fail no_magic_root reset"; print $0; next };' > $check_file
          rm $temp_file
        fi
      else
        if [ "$audit_mode" = "1" ]; then  
          score=`expr $score + 1`
          echo "Secure:    Account entry enabled in $check_file [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_system_auth_password_policy
# 
# Audit password policies
#.

audit_system_auth_password_policy () {
  auth_string=$1
  search_string=$2
  search_value=$3
  if [ "$os_name" = "Linux" ]; then
    if [ "$linux_dist" = "debian" ] || [ "$linux_dist" = "suse" ]; then
      check_file="/etc/pam.d/common-auth"
    fi
    if [ "$linux_dist" = "redhat" ]; then
      check_file="/etc/pam.d/system-auth"
    fi
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Password $search_string is set to $search_value in $check_file"
      total=`expr $total + 1`
      check_value=`cat $check_file |grep '^$auth_string' |grep '$search_string$' |awk -F '$search_string=' '{print $2}' |awk '{print $1}'`
      if [ "$check_value" != "$search_value" ]; then
        if [ "$audit_mode" = "1" ]; then
          score=`expr $score - 1`
          echo "Warning:   Password $search_string is not set to $search_value in $check_file [$score]"
          funct_verbose_message "cp $check_file $temp_file" fix
          funct_verbose_message "cat $temp_file |awk '( $1 == \"password\" && $2 == \"requisite\" && $3 == \"pam_cracklib.so\" ) { print $0  \" dcredit=-1 lcredit=-1 ocredit=-1 ucredit=-1 minlen=9\"; next }; { print }' > $check_file" fix
          funct_verbose_message "rm $temp_file" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Password $search_string to $search_value in $check_file"
          cp $check_file $temp_file
          cat $temp_file |awk '( $1 == "password" && $2 == "requisite" && $3 == "pam_cracklib.so" ) { print $0  " dcredit=-1 lcredit=-1 ocredit=-1 ucredit=-1 minlen=9"; next }; { print }' > $check_file
          rm $temp_file
        fi
      else
        if [ "$audit_mode" = "1" ]; then  
          score=`expr $score + 1`
          echo "Secure:    Password $search_string set to $search_value in $check_file [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_system_auth_password_strength
#
# Audit password strength
#.

audit_system_auth_password_strength () {
  auth_string=$1
  search_string=$2
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "PAM Authentication"
    if [ "$linux_dist" = "debian" ] || [ "$linux_dist" = "suse" ]; then
      check_file="/etc/pam.d/common-auth"
    fi
    if [ "$linux_dist" = "redhat" ]; then
      check_file="/etc/pam.d/system-auth"
    fi
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Password minimum strength enabled in $check_file"
      total=`expr $total + 1`
      check_value=`cat $check_file |grep '^$auth_string' |grep '$search_string$' |awk '{print $8}'`
      if [ "$check_value" != "$search_string" ]; then
        if [ "$audit_mode" = "1" ]; then
          score=`expr $score - 1`
          echo "Warning:   Password strength settings not enabled in $check_file [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Password minimum length in $check_file"
          cp $check_file $temp_file
          cat $temp_file |sed 's/^password.*pam_deny.so$/&\npassword\t\trequisite\t\t\tpam_passwdqc.so min=disabled,disabled,16,12,8/' > $check_file
          rm $temp_file
        fi
      else
        if [ "$audit_mode" = "1" ]; then  
          score=`expr $score + 1`
          echo "Secure:    Password strength settings enabled in $check_file [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_system_auth_unlock_time
#
# Audit time before account is unlocked after unsuccesful tries
#.

audit_system_auth_unlock_time () {
  auth_string=$1
  search_string=$2
  search_value=$3
  if [ "$os_name" = "Linux" ]; then
    if [ "$linux_dist" = "redhat" ]; then
      check_file="/etc/pam.d/system-auth"
    fi
    if [ "$linux_dist" = "debian" ] || [ "$linux_dist" = "suse" ]; then
      check_file="/etc/pam.d/common-auth"
    fi
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Lockout time for failed password attempts enabled in $check_file"
      total=`expr $total + 1`
      check_value=`cat $check_file |grep '^$auth_string' |grep '$search_string$' |awk -F '$search_string=' '{print $2}' |awk '{print $1}'`
      if [ "$check_value" != "$search_string" ]; then
        if [ "$audit_mode" = "1" ]; then
          score=`expr $score - 1`
          echo "Warning:   Lockout time for failed password attempts not enabled in $check_file [$score]"
          funct_verbose_message "cp $check_file $temp_file" fix
          funct_verbose_message "cat $temp_file |sed 's/^auth.*pam_env.so$/&\nauth\t\trequired\t\t\tpam_faillock.so preauth audit silent deny=5 unlock_time=900\nauth\t\t[success=1 default=bad]\t\t\tpam_unix.so\nauth\t\t[default=die]\t\t\tpam_faillock.so authfail audit deny=5 unlock_time=900\nauth\t\tsufficient\t\t\tpam_faillock.so authsucc audit deny=5 $search_string=$search_value\n/' > $check_file" fix
          funct_verbose_message "rm $temp_file" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Password minimum length in $check_file"
          cp $check_file $temp_file
          cat $temp_file |sed 's/^auth.*pam_env.so$/&\nauth\t\trequired\t\t\tpam_faillock.so preauth audit silent deny=5 unlock_time=900\nauth\t\t[success=1 default=bad]\t\t\tpam_unix.so\nauth\t\t[default=die]\t\t\tpam_faillock.so authfail audit deny=5 unlock_time=900\nauth\t\tsufficient\t\t\tpam_faillock.so authsucc audit deny=5 $search_string=$search_value\n/' > $check_file
          rm $temp_file
        fi
      else
        if [ "$audit_mode" = "1" ]; then  
          score=`expr $score + 1`
          echo "Secure:    Lockout time for failed password attempts enabled in $check_file [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_system_auth_use_uid
#
# Audit wheel Set UID
#.

audit_system_auth_use_uid () {
  auth_string=$1
  search_string=$2
  check_file="/etc/pam.d/su"
  if [ "$os_name" = "Linux" ]; then
    if [ "$linux_dist" = "redhat" ]; then
      check_file="/etc/pam.d/system-auth"
    fi
    if [ "$linux_dist" = "debian" ] || [ "$linux_dist" = "suse" ]; then
      check_file="/etc/pam.d/common-auth"
    fi
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Lockout for failed password attempts enabled in $check_file"
      total=`expr $total + 1`
      check_value=`cat $check_file |grep '^$auth_string' |grep '$search_string$' |awk '{print $8}'`
      if [ "$check_value" != "$search_string" ]; then
        if [ "$audit_mode" = "1" ]; then
          score=`expr $score - 1`
          echo "Warning:   Lockout for failed password attempts not enabled in $check_file [$score]"
          funct_verbose_message "cp $check_file $temp_file" fix
          funct_verbose_message "cat $temp_file |sed 's/^auth.*use_uid$/&\nauth\t\trequired\t\t\tpam_wheel.so use_uid\n/' > $check_file" fix
          funct_verbose_message "rm $temp_file" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Password minimum length in $check_file"
          cp $check_file $temp_file
          cat $temp_file |sed 's/^auth.*use_uid$/&\nauth\t\trequired\t\t\tpam_wheel.so use_uid\n/' > $check_file
          rm $temp_file
        fi
      else
        if [ "$audit_mode" = "1" ]; then  
          score=`expr $score + 1`
          echo "Secure:    Lockout for failed password attempts enabled in $check_file [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}


# audit_system_auth
#
# Audit /etc/pam.d/system-auth on RedHat
# Audit /etc/pam.d/common-auth on Debian
# Lockout accounts after 5 failures
# Set to remember up to 4 passwords
# Set password length to a minimum of 9 characters
# Set strong password creation via pam_cracklib.so and pam_passwdqc.so
# Restrict su command using wheel
#.

audit_system_auth () { 
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "PAM Authentication"
    funct_rpm_check libpam-cracklib
    if [ "$linux_dist" = "debian" ] || [ "$linux_dist" = "suse" ]; then
      check_file="/etc/pam.d/common-auth"
    fi
    if [ "$linux_dist" = "redhat" ]; then
      check_file="/etc/pam.d/system-auth"
    fi
    if [ "$audit_mode" != 2 ]; then
      audit_system_auth_nullok
      auth_string="account"
      search_string="remember"
      search_value="10"
      audit_system_auth_password_history $auth_string $search_string $search_value
      auth_string="auth"
      search_string="no_magic_root"
      audit_system_auth_no_magic_root $auth_string $search_string
      auth_string="account"
      search_string="reset"
      audit_system_auth_account_reset $auth_string $search_string
      auth_string="password"
      search_string="minlen"
      search_value="9"
      audit_system_auth_password_policy $auth_string $search_string $search_value
      auth_string="password"
      search_string="dcredit"
      search_value="-1"
      audit_system_auth_password_policy $auth_string $search_string $search_value
      auth_string="password"
      search_string="lcredit"
      search_value="-1"
      audit_system_auth_password_policy $auth_string $search_string $search_value
      auth_string="password"
      search_string="ocredit"
      search_value="-1"
      audit_system_auth_password_policy $auth_string $search_string $search_value
      auth_string="password"
      search_string="ucredit"
      search_value="-1"
      audit_system_auth_password_policy $auth_string $search_string $search_value
      auth_string="password"
      search_string="16,12,8"
      audit_system_auth_password_strength $auth_string $search_string
      auth_string="auth"
      search_string="unlock_time"
      search_value="900"
      audit_system_auth_unlock_time $auth_string $search_string $search_value
      auth_string="auth"
      search_string="use_uid"
      audit_system_auth_use_uid $auth_string $search_string
    fi
  fi
}

# audit_pam_deny
#
# Add pam.deny to pam config files
#.

audit_pam_deny () {
  :
}

# audit_pam_wheel
#
# PAM Wheel group membership. Make sure wheel group membership is required to su.
#.

audit_pam_wheel () {
  if [ "$os_name" = "Linux" ]; then
    funct_verbose_message "PAM SU Configuration"
    check_file="/etc/pam.d/su"    
    search_string="use_uid"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Wheel group membership required for su in $check_file"
      total=`expr $total + 1`
      check_value=`cat $check_file |grep '^auth' |grep '$search_string$' |awk '{print $8}'`
      if [ "$check_value" != "$search_string" ]; then
        if [ "$audit_mode" = "1" ]; then
          score=`expr $score - 1`
          echo "Warning:   Wheel group membership not required for su in $check_file [$score]"
          funct_verbose_message "" fix
          funct_verbose_message "cp $check_file $temp_file" fix
          funct_verbose_message "cat $temp_file |awk '( $1==\"#auth\" && $2==\"required\" && $3~\"pam_wheel.so\" ) { print \"auth\t\trequired\t\",$3,\"\tuse_uid\"; next }; { print }' > $check_file" fix
          funct_verbose_message "rm $temp_file" fix
          funct_verbose_message "" fix
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Password minimum length in $check_file"
          cp $check_file $temp_file
          cat $temp_file |awk '( $1=="#auth" && $2=="required" && $3~"pam_wheel.so" ) { print "auth\t\trequired\t",$3,"\tuse_uid"; next }; { print }' > $check_file
          rm $temp_file
        fi
      else
        if [ "$audit_mode" = "1" ]; then  
          score=`expr $score + 1`
          echo "Secure:    Wheel group membership required for su in $check_file [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_password_hashing
#
# Check that password hashing is set to SHA512.
#.

audit_password_hashing () {
  if [ "$os_name" = "Linux" ]; then
    hashing=$1
    if [ "$1" = "" ]; then
      hashing="sha512"
    fi
    if [ "$os_name" = "Linux" ]; then
      if [ -f "/usr/sbin/authconfig" ]; then
        funct_verbose_message "Password Hashing"
        if [ "$audit_mode" != 2 ]; then
          log_file="hashing.log"
          echo "Checking:  Password hashing is set to $hashing"
          total=`expr $total + 1`
          check_value=`authconfig --test |grep hashing |awk '{print $5}'`
          if [ "$check_value" != "$hashing" ]; then
            if [ "$audit_mode" = "1" ]; then
              score=`expr $score - 1`
              echo "Warning:   Password hashing not set to $hashing [$score]"
              funct_verbose_message "" fix
              funct_verbose_message "authconfig --passalgo=$hashing" fix
              funct_verbose_message "" fix
            fi
            if [ "$audit_mode" = 0 ]; then
              echo "Setting:   Password hashing to $hashing"
              log_file="$work_dir/$log_file"
              echo "$check_value" > $log_file
              authconfig --passalgo=$hashing
            fi
          else
            if [ "$audit_mode" = "1" ]; then  
              score=`expr $score + 1`
              echo "Secure:    Password hashing set to $hashing [$score]"
            fi
          fi
        else
          restore_file="$restore_dir/$log_file"
          if [ -f "$restore_file" ]; then
            check_value=`cat $restore_file`
            authconfig --passalgo=$check_value
          fi
        fi
      fi
    fi
  fi
}

# audit_wheel_group
#
# Make sure there is a wheel group so privileged account access is limited.
#.

audit_wheel_group () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    check_file="/etc/group"    
    funct_verbose_message "Wheel Group"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Wheel group exists in $check_file"
      total=`expr $total + 1`
      check_value=`cat $check_file |grep '^$wheel_group:'`
      if [ "$check_value" != "$search_string" ]; then
        if [ "$audit_mode" = "1" ]; then
          score=`expr $score - 1`
          echo "Warning:   Wheel group does not exist in $check_file [$score]"
        fi
        if [ "$audit_mode" = 0 ]; then
          funct_backup_file $check_file
          echo "Setting:   Adding $wheel_group group to $check_file"
          groupadd wheel
          usermod -G $wheel_group root
        fi
      else
        if [ "$audit_mode" = "1" ]; then  
          score=`expr $score + 1`
          echo "Secure:    Wheel group exists in $check_file [$score]"
        fi
      fi
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

#
# audit_wheel_users
# 
# Check users in wheel group have recently logged in, if not lock them
#

audit_wheel_users () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ] || [ "$os_name" = "Darwin" ]; then
    check_file="/etc/group"
    if [ "$audit_mode" != 2 ]; then
      for user_name in `cat $check_file |grep '^$wheel_group:' |cut -f4 -d: |sed 's/,/ /g'`; do
        last_login=`last -1 guest |grep '[a-z]' |awk '{print $1}'`
        if [ "$last_login" = "wtmp" ]; then
          lock_test=`cat /etc/shadow |grep '^$user_name:' |grep -v 'LK' |cut -f1 -d:`
          if [ "$lock_test" = "$user_name" ]; then
            if [ "$audit_mode" = 1 ]; then
              score=`expr $score - 1`
              echo "Warning:   User $user_name has not logged in recently and their account is not locked [$score]"
            fi
            if [ "$audit_mode" = 0 ]; then
              funct_backup_file $check_file
              echo "Setting:   User $user_name to locked"
              passwd -l $user_name
            fi
          fi
        fi
      done
    else
      funct_restore_file $check_file $restore_dir
    fi
  fi  
}


# audit_wheel_su
#
# Make sure su has a wheel group ownership
#.

audit_wheel_su () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ] || [ "$os_name" = "Darwin" ]; then
    check_file=`which su`
    funct_check_perms $check_file 4750 root $wheel_group 
  fi
}

#
# audit_wheel_sudo
#
# Check wheel group settings in sudoers
#.

audit_wheel_sudo () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ] || [ "$os_name" = "Darwin" ]; then
    for check_dir in /etc /usr/local/etc /usr/sfw/etc /opt/csw/etc; do
      check_file="$check_dir/sudoers"
      if [ -f "$check_file" ]; then
        if [ "$audit_mode" != 2 ]; then
          nopasswd_check=`cat $check_file |grep $wheel_group |awk '{print $3}'`
          if [ "$nopasswd_check" = "NOPASSWD" ]; then
            if [ "$audit_mode" = 1 ]; then
              score=`expr $score - 1`
              echo "Warning:   Group $wheel_group does not require password to escalate privileges [$score]"
            fi
            if [ "$audit_mode" = 0 ]; then
              funct_backup_file $check_file
              echo "Setting:   User $user_name to locked"
              passwd -l $user_name
            fi
          fi
        else
          funct_restore_file $check_file $restore_dir
        fi
      fi
    done
  fi
}

# audit_super_users
#
# Make sure no other accounts than root have UID 0.
#.

audit_super_users () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ]; then
    funct_verbose_message "Users with UID 0"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Super users other than root"
      total=`expr $total + 1`
      for user_name in `awk -F: '$3 == "0" { print $1 }' /etc/passwd |grep -v root`; do
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score - 1`
          echo "Warning:   UID 0 for $user_name [$score]"
        fi
        if [ "$audit_mode" = 0 ]; then
          check_file="/etc/shadow"
          funct_backup_file $check_file
          check_file="/etc/passwd"
          funct_backup_file $check_file
          echo "Removing:  Account $user_name as it has UID 0"
          userdel $user_name
        fi
      done
      if [ "$user_name" = "" ]; then
        if [ "$audit_mode" = 1 ]; then
          score=`expr $score + 1`
          echo "Secure:    No accounts other than root have UID 0 [$score]"
        fi
      fi
    else
      check_file="/etc/shadow"
      funct_restore_file $check_file $restore_dir
      check_file="/etc/passwd"
      funct_restore_file $check_file $restore_dir
    fi
  fi
}

# audit_root_keys
#
# Make sure there are not ssh keys for root
#.

audit_root_keys () {
  if [ "$os_name" = "SunOS" ] || [ "$os_name" = "Linux" ] || [ "$os_name" = "Darwin" ]; then
    funct_verbose_message "Root SSH keys"
    if [ "$audit_mode" != 2 ]; then
      echo "Checking:  Root SSH keys"
      root_home=`cat /etc/passwd |grep '^root' |cut -f6 -d:`
      for check_file in $root_home/.ssh/authorized_keys $root_home/.ssh/authorized_keys2; do
        total=`expr $total + 1`
        if [ "$audit_home" != 2 ]; then
          if [ -f "$check_file" ]; then
            if [ "`wc -l $check_file |awk '{print $1}'`" -ge 1 ]; then
              if [ "$audit_mode" = 1 ]; then
                score=`expr $score - 1`
                echo "Warning:   Keys file $check_file exists [$score]"
                funct_verbose_message "mv $check_file $check_file.disabled" fix
              fi
              if [ "$audit_mode" = 0 ]; then
                funct_backup_file $check_file
                echo "Removing:  Keys file $check_file"
              fi
            else
              if [ "$audit_mode" = 1 ]; then
                score=`expr $score + 1`
                echo "Secure:    Keys file $check_file does not contain any keys"
              fi
            fi
          else
            if [ "$audit_mode" = 1 ]; then
              score=`expr $score + 1`
              echo "Secure:    Keys file $check_file does not exist"
            fi
          fi
        else
          funct_restore_file $check_file $restore_dir
        fi
      done
    fi
  fi
}

# audit_logrotate
#
# Make sure logroate is set up appropriately.
#.

audit_logrotate () {
  if [ "$os_name" = "Linux" ]; then
    check_file="/etc/logrotate.d/syslog"
    if [ -f "$check_file" ]; then
      funct_verbose_message "Log Rotate Configuration"
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  Logrotate is set up"
        total=`expr $total + 1`
        search_string="/var/log/messages /var/log/secure /var/log/maillog /var/log/spooler /var/log/boot.log /var/log/cron"
        check_value=`cat $check_file |grep "$search_string" |sed 's/ {//g'`
        if [ "$check_value" != "$search_string" ]; then
          score=`expr $score - 1`
          if [ "$audit_mode" = 1 ]; then
            echo "Warning:   Log rotate is not configured for $search_string [$score]"
            funct_verbose_message "" fix
            funct_verbose_message "cat $check_file |sed 's,.*{,$search_string {,' > $temp_file" fix
            funct_verbose_message "cat $temp_file > $check_file" fix
            funct_verbose_message "rm $temp_file" fix
            funct_verbose_message "" fix
          fi
          if [ "$audit_mode" = 0 ]; then
            funct_backup_file $check_file
            echo "Removing:  Configuring logrotate"
            cat $check_file |sed 's,.*{,$search_string {,' > $temp_file
            cat $temp_file > $check_file
            rm $temp_file
          fi
        else
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    Log rotate is configured [$score]"
          fi
        fi
      else
        funct_restore_file $check_file $restore_dir
      fi
    fi
  fi
}

# audit_rsa_securid_pam
#
# Check that RSA is installed
#.

audit_rsa_securid_pam () {
  if [ "$os_name" = "Linux" ] || [ "$os_name" = "SunOS" ]; then
    check_file="/etc/sd_pam.conf"
    if [ -f "$check_file" ]; then
      search_string="pam_securid.so"
      if [ "$os_name" = "SunOS" ]; then 
        check_file="/etc/pam.conf"
        if [ -f "$check_file" ]; then
          check_value=`cat $check_file |grep "$search_string" |awk '{print  $3}'`
        fi
      fi
      if [ "$os_name" = "Linux" ]; then
        check_file="/etc/pam.d/sudo"
        if [ -f "$check_file" ]; then
          check_value=`cat $check_file |grep "$search_string" |awk '{print  $4}'`
        fi
      fi
      funct_verbose_message "RSA SecurID PAM Agent Configuration"
      if [ "$audit_mode" != 2 ]; then
        echo "Checking:  RSA SecurID PAM Agent is enabled for sudo"
        total=`expr $total + 1`
        if [ "$check_value" != "$search_string" ]; then
          score=`expr $score - 1`
          if [ "$audit_mode" = 1 ]; then
            echo "Warning:   RSA SecurID PAM Agent is not enabled for sudo [$score]"
            funct_verbose_message "" fix
            if [ "$os_name" = "Linux" ]; then
              funct_verbose_message "cat $check_file |sed 's/^auth/#\&/' > $temp_file" fix
              funct_verbose_message "cat $temp_file > $check_file" fix
              funct_verbose_message "echo \"auth\trequired\tpam_securid.so reserve\" >> $check_file" fix
              funct_verbose_message "rm $temp_file" fix
            fi
            if [ "$os_name" = "SunOS" ]; then
              funct_verbose_message "echo \"sudo\tauth\trequired\tpam_securid.so reserve\" >> $check_file" fix
            fi
            funct_verbose_message "" fix
          fi
          if [ "$audit_mode" = 0 ]; then
            funct_backup_file $check_file
            echo "Fixing:    Configuring RSA SecurID PAM Agent for sudo"
            if [ "$os_name" = "Linux" ]; then
              cat $check_file |sed 's/^auth/#\&/' > $temp_file
              cat $temp_file > $check_file
              echo "auth\trequired\tpam_securid.so reserve" >> $check_file
              rm $temp_file
            fi
            if [ "$os_name" = "SunOS" ]; then
              echo "sudo\tauth\trequired\tpam_securid.so reserve" >> $check_file
            fi
            #echo "Removing:  Configuring logrotate"
            #cat $check_file |sed 's,.*{,$search_string {,' > $temp_file
            #cat $temp_file > $check_file
            #rm $temp_file
          fi
        else
          if [ "$audit_mode" = 1 ]; then
            score=`expr $score + 1`
            echo "Secure:    RSA SecurID PAM Agent is configured for sudo [$score]"
          fi
        fi
      else
        funct_restore_file $check_file $restore_dir
      fi
    fi
  fi
}

# audit_x11_services
#
# Audit X11 Services
#.

audit_x11_services () {
  audit_cde_ttdb
  audit_cde_cal
  audit_cde_spc
  audit_cde_print
  audit_xlogin
  audit_gdm_conf
  audit_cde_banner
  audit_gnome_banner
  audit_cde_screen_lock
  audit_gnome_screen_lock
  audit_opengl
  audit_font_server
  audit_vnc
}

# audit_naming_services
#
# Audit Naming Services
#.

audit_naming_services () {
  audit_nis_server
  audit_nis_client
  audit_nisplus
  audit_ldap_cache
  audit_kerberos_tgt
  audit_gss
  audit_keyserv
  audit_dns_client
  audit_dns_server
  audit_krb5
  audit_nis_entries
  audit_avahi_conf
}

# audit_user_services
#
# Audit users and groups
#.

audit_user_services () {
  audit_root_home
  audit_root_group
  audit_root_keys
  audit_mesgn
  audit_groups_exist
  audit_home_perms
  audit_home_ownership
  audit_duplicate_users
  audit_duplicate_groups
  audit_user_dotfiles
  audit_forward_files
  audit_root_path
  audit_root_group
  audit_default_umask
  audit_password_fields
  audit_reserved_ids
  audit_super_users
  audit_daemon_umask
  audit_cron_perms
  audit_wheel_group
  audit_wheel_su
  audit_old_users
  ##  audit_cron_allow
  audit_system_accounts
}

# audit_print_services
#
# Audit print services
#.

audit_print_services () {
  audit_ppd_cache
  audit_print
  audit_cups
}

# audit_web_services
#
# Audit web services

audit_web_services () {
  audit_webconsole
  audit_wbem
  audit_apache
  audit_webmin
}

# audit_disk_services
#
# Audit disk and hardware related services
#.

audit_disk_services () {
  audit_svm
  audit_svm_gui
  audit_iscsi
}

# audit_hardware_services
#
# Audit hardware related services
#.

audit_hardware_services () {
  audit_hotplug
}

# audit_power_services
#.
# Audit power related services
#.

audit_power_services () {
  audit_power_management
  audit_sys_suspend
}

# audit_file_services
#
# Audit file permissions
#.

audit_file_services () {
  audit_syslog_perms
  audit_volfs
  audit_autofs
  audit_dfstab
  audit_mount_setuid
  audit_mount_nodev
  audit_mount_fdi
  audit_nfs
  audit_uucp
}

# audit_mail_services
#
# Audit sendmail

audit_mail_services () {
  audit_sendmail_daemon
  audit_sendmail_greeting
  audit_sendmail_aliases
  audit_email_services
  audit_postfix_daemon
}

# audit_ftp_services
#
# Audit FTP Services

audit_ftp_services () {
  audit_ftp_logging
  audit_ftp_umask
  audit_ftp_conf
  audit_ftp_server
  audit_tftp_server
  audit_ftp_banner
}

# audit_kernel_services
#
# Audit kernel services
#.

audit_kernel_services () {
  audit_sysctl
  audit_kernel_accounting
  audit_kernel_params
  audit_tcpsyn_cookie
  audit_stack_protection
  audit_tcp_strong_iss
  audit_routing_params
  audit_modprobe_conf
  audit_unconfined_daemons
  audit_selinux
}

# audit_routing_services
#
# Audit routing services
#.

audit_routing_services () {
  audit_routing_daemons
  audit_routing_params
}

# audit_windows_services
#
# Audit windows services 
#.

audit_windows_services () {
  audit_smbpasswd_perms
  audit_smbconf_perms
  audit_samba
  audit_wins
  audit_winbind
}

# audit_startup_services
#
# Audit startup services
#.

audit_startup_services () {
  audit_xinetd
  audit_chkconfig
  audit_legacy
  audit_inetd
  audit_inetd_logging
}

# audit_shell_services
#
# Audit remote shell services
#.

audit_shell_services () {
  audit_issue_banner
  audit_ssh_config
  audit_remote_consoles
  audit_ssh_forwarding
  audit_remote_shell
  audit_console_login
  #audit_security_banner
  audit_telnet_banner
  audit_pam_rhosts
  #audit_user_netrc
  #audit_user_rhosts
  audit_rhosts_files
  audit_netrc_files
  audit_serial_login
  audit_sulogin
}

# audit_accounting_services
#
# Audit accounting services
#.

audit_accounting_services () {
  audit_system_accounting
  audit_process_accounting
  audit_audit_class
}

# audit_firewall_services
#
# Audit firewall related services
#.

audit_firewall_services () {
  audit_ipsec
  audit_ipfilter
  audit_tcp_wrappers
}

# audit_password_services
#
# Audit password related services
#.

audit_password_services () {
  audit_rsa_securid_pam
  audit_system_auth
  audit_password_expiry
  audit_strong_password
  audit_passwd_perms
  audit_retry_limit
  audit_login_records
  audit_failed_logins
  audit_login_delay
  audit_pass_req
  audit_pam_wheel
  audit_password_hashing
  audit_pam_deny
  audit_crypt_policy
}

# audit_log_services
#
# Audit log files and log related services
#.

audit_log_services () {
  audit_linux_logfiles
  audit_syslog_conf
  audit_debug_logging
  audit_syslog_auth
  audit_core_dumps
  audit_cron_logging
  audit_logrotate
}

# audit_network_services
#
# Audit Network Service
#.

audit_network_services () {
  audit_snmp
  audit_ntp
  audit_ipmi
  audit_echo
  audit_ocfserv 
  audit_tname
  audit_service_tags
  audit_ticotsord
  audit_boot_server
  audit_slp
  audit_tnd
  audit_nobody_rpc
}

# audit_update_services
#
# Update services
#.

audit_update_services () {
  apply_latest_patches
  audit_yum_conf
}

# audit_other_services
#
# Other remaining services
#.

audit_other_services () {
  audit_postgresql
  audit_encryption_kit
}

# audit_virtualisation_services
#
# Audit vitualisation services
#.

audit_virtualisation_services () {
  audit_zones
  audit_xen
}

# audit_osx_services
#
# Audit All System 
#.

audit_osx_services () {
  audit_bt_sharing
  audit_guest_sharing
  audit_file_sharing
  audit_web_sharing
  audit_login_warning
  audit_firewall_setting
  audit_infrared_remote
  audit_setup_file
  audit_screen_lock
  audit_secure_swap
  audit_login_guest
  audit_login_hints
  audit_login_autologin
  audit_login_details
  audit_core_limit
}

# funct_audit_system_all
#
# Audit All System 
#.

funct_audit_system_all () {
  
  audit_shell_services
  audit_accounting_services
  audit_firewall_services
  audit_password_services
  audit_kernel_services
  audit_mail_services
  audit_user_services
  audit_disk_services
  audit_hardware_services
  audit_power_services
  audit_virtualisation_services
  audit_x11_services
  audit_naming_services
  audit_file_services
  audit_web_services
  audit_print_services
  audit_routing_services
  audit_windows_services
  audit_startup_services
  audit_log_services
  audit_network_services
  audit_other_services
  audit_update_services
  if [ "$os_name" = "Darwin" ]; then
    audit_osx_services
  fi
}

# funct_audit_search_fs
#
# Audit Filesystem
#
# Run various filesystem audits, add support for NetBackup
#.

funct_audit_search_fs () {
  if [ "$os_name" = "SunOS" ]; then
    funct_verbose_message "Filesystem Search"
    nb_check=`pkginfo -l |grep SYMCnbclt |grep PKG |awk '{print $2}'`
    if [ "$nb_check" != "SYMCnbclt" ]; then
      audit_bpcd
      audit_vnetd
      audit_vopied
      audit_bpjava_msvc
    else
      check_file="/etc/hosts.allow"
      funct_file_value $check_file bpcd colon " ALL" hash
      funct_file_value $check_file vnetd colon " ALL" hash
      funct_file_value $check_file bpcd vopied " ALL" hash
      funct_file_value $check_file bpcd bpjava-msvc " ALL" hash
    fi
    audit_extended_attributes
  fi
  audit_writable_files
  audit_suid_files
  audit_file_perms
  audit_sticky_bit
}

# funct_audit_system_x86
#
# Audit x86
#.

funct_audit_system_x86 () {
  if [ "$os_name" = "SunOS" ]; then
    audit_grub_security
    audit_kdm_config
  fi
}

# funct_audit_system_sparc
#
# Audit SPARC
#.

funct_audit_system_sparc () {
  if [ "$os_name" = "SunOS" ]; then
    audit_eeprom_security
  fi
}

# funct_audit_test_subset
#
# Audit Subset for testing
#.

funct_audit_test_subset () {
  audit_legacy
}

# print_results
#
# Print Results
#.

print_results () {
  echo ""
  if [ "$audit_mode" != 1 ]; then
    if [ "$reboot" = 1 ]; then
      reboot="Required"
    else
      reboot="Not Required"
    fi
    echo "Reboot:    $reboot"
  fi
  if [ "$audit_mode" = 1 ]; then
    echo "Tests:     $total"
    if test $score -lt 0; then
      score=`echo $score |sed 's/-//'`
	    score=`echo $total - $score |bc`
    fi
    echo "Score:     $score"
  fi
  if [ "$audit_mode" = 0 ]; then
    echo "Backup:    $work_dir"
    echo "Restore:   $0 -u $date_suffix"
  fi
  echo ""
}

# funct_audit_select
#
# Selective Audit
#.

funct_audit_select () {
  audit_mode=$1
  function=$2
  check_environment
  if [ "`expr $function : audit_`" != "6" ]; then
    function="audit_$function"
  fi
  funct_print_audit_info $function
  $function
  print_results
}

# funct_audit_system () {
#
# Audit System
#.

funct_audit_system () {
  audit_mode=$1
  check_environment
  if [ "$audit_mode" = 0 ]; then
    if [ ! -d "$work_dir" ]; then
      mkdir -p $work_dir
      if [ "$os_name" = "SunOS" ]; then
        echo "Creating:  Alternate Boot Environment $date_suffix"
        if [ "$os_version" = "11" ]; then
          beadm create audit_$date_suffix
        fi
        if [ "$os_version" = "8" ] || [ "$os_version" = "9" ] || [ "$os_version" = "10" ]; then
          if [ "$os_platform" != "i386" ]; then
            lucreate -n audit_$date_suffix
          fi
        fi
      else
        :
        # Add code to do LVM snapshot
      fi
    fi
  fi
  if [ "$audit_mode" = 2 ]; then
    restore_dir="$base_dir/$restore_date"
    if [ ! -d "$restore_dir" ]; then
      echo "Restore directory $restore_dir does not exit"
      exit
    else
      echo "Setting:   Restore directory to $restore_dir"
    fi
  fi
  funct_audit_system_all
  if [ "$do_fs" = 1 ]; then
    funct_audit_search_fs
  fi
  #funct_audit_test_subset
  if [ `expr "$os_platform" : "sparc"` != 1 ]; then
    funct_audit_system_x86
  else
    funct_audit_system_sparc
  fi
  print_results
}

# Handle command line arguments

while getopts abdlps:u:z:hASVL args; do
  case $args in
    a)
      if [ "$2" = "-v" ]; then
        verbose=1
      fi
      echo ""
      echo "Running:   In audit mode (no changes will be made to system)"
      echo "           Filesystem checks will not be done"
      echo ""
      audit_mode=1
      do_fs=0
      funct_audit_system $audit_mode
      exit
      ;;
    s)
      if [ "$3" = "-v" ]; then
        verbose=1
      fi
      echo ""
      echo "Running:   In audit mode (no changes will be made to system)"
      echo "           Filesystem checks will not be done"
      echo ""
      audit_mode=1
      do_fs=0
      function="$OPTARG"
      echo "Auditing:  Selecting $function"
      funct_audit_select $audit_mode $function
      exit
      ;;
    z)
      if [ "$3" = "-v" ]; then
        verbose=1
      fi
      echo ""
      echo "Running:   In lockdown mode (no changes will be made to system)"
      echo "           Filesystem checks will not be done"
      echo ""
      audit_mode=0
      do_fs=0
      function="$OPTARG"
      echo "Auditing:  Selecting $function"
      funct_audit_select $audit_mode $function
      exit
      ;;
    S)
      echo ""
      echo "Functions:"
      echo ""
      cat $0 |grep 'audit_' |grep '()' | awk '{print $1}' |grep -v cat |sed 's/audit_//g' |sort
      ;;
    A)
      if [ "$2" = "-v" ]; then
        verbose=1
      fi
      echo ""
      echo "Running:   In audit mode (no changes will be made to system)"
      echo "           Filesystem checks will be done"
      echo ""
      audit_mode=1
      do_fs=1
      funct_audit_system $audit_mode
      exit
      ;;
    l)
      if [ "$2" = "-v" ]; then
        verbose=1
      fi
      echo ""
      echo "Running:   In lockdown mode (changes will be made to system)"
      echo "           Filesystem checks will not be done"
      echo ""
      audit_mode=0
      do_fs=0
      funct_audit_system $audit_mode
      exit
      ;;
    L)
      if [ "$2" = "-v" ]; then
        verbose=1
      fi
      echo ""
      echo "Running:   In lockdown mode (no changes will be made to system)"
      echo "           Filesystem checks will be done"
      echo ""
      audit_mode=0
      do_fs=1
      funct_audit_system $audit_mode
      exit
      ;;
    u)
      echo ""
      echo "Running:   In Restore mode (changes will be made to system)"
      echo ""
      audit_mode=2
      restore_date="$OPTARG"
      echo "Setting:   Restore date $restore_date"
      echo ""
      funct_audit_system $audit_mode
      exit
      ;;
    h)
      print_usage
      exit
      ;;
    V)
      echo $script_version
      exit
      ;;
    p)
      echo ""
      echo "Printing previous settings:"
      echo ""
      print_previous
      exit
      ;;
    d)
      echo ""
      echo "Printing changes:"
      echo ""
      print_changes
      exit
      ;;
    b)
      echo ""
      echo "Previous backups:"
      echo ""
      ls $base_dir
      exit
      ;;
    *)
      print_usage
      exit
      ;;
  esac
done
