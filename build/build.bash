#!/bin/bash
#-----------------------------------------------------------------------------#
# eFa 4.0.0 build script version 20190312
#-----------------------------------------------------------------------------#
# Copyright (C) 2013~2017 https://efa-project.org
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#-----------------------------------------------------------------------------#
action=$1
action="${action:=testing}" # default to testing if no arg supplied

#-----------------------------------------------------------------------------#
# Install eFa
#-----------------------------------------------------------------------------#
mirror="https://mirrors.efa-project.org"

LOGFILE="/var/log/eFa/build.log"


#==============================================================================================
#
# Set up logging
#

LOGGER='/usr/bin/logger'
HEADER='=============  EFA4 BUILD SCRIPT STARTING  ============'

# CREATE LOG FOLDER IF NOT EXISTS
mkdir -p $(dirname "${LOGFILE}")

# TRY TO CREATE LOG FILE IF NOT EXISTS
( [ -e "$LOGFILE" ] || touch "$LOGFILE" ) && [ ! -w "$LOGFILE" ] && echo "Unable to create or write to $LOGFILE"

function logthis() {
    TAG='EFA4'
    MSG="$1"
    $LOGGER -t "$TAG" "$MSG"
    echo "`date +%Y.%m.%d-%H:%M:%S` - $MSG"
    echo "`date +%Y.%m.%d-%H:%M:%S` - $MSG" >> $LOGFILE
}

logthis "$HEADER"

# check if user is root
if [ `whoami` == root ]; then
  logthis "Good you are root."
else
  logthis "ERROR: Please become root first."
  logthis "^^^^^^^^^^ SCRIPT ABORTED ^^^^^^^^^^"
  exit 1
fi

# check if we run CentOS 7
OSVERSION=`cat /etc/centos-release`
if [[ $OSVERSION =~ .*'release 7.'.* ]]; then
  logthis "Good you are running CentOS 7"
else
  logthis "ERROR: You are not running CentOS 7"
  logthis "ERROR: Unsupported system, stopping now"
  logthis "^^^^^^^^^^ SCRIPT ABORTED ^^^^^^^^^^"
  exit 1
fi

# Check that SELinux is not disabled (unless it is lxc)
if [[ -z $(grep -i 'lxc\|docker' /proc/1/cgroup) ]]; then
    if [[ -f /etc/selinux/config && -n $(grep -i ^SELINUX=disabled$ /etc/selinux/config)  ]]; then
        logthis "ERROR: SELinux is disabled and this is not an lxc container"
        logthis "ERROR: Please enable SELinux and try again."
        logthis "^^^^^^^^^^ SCRIPT ABORTED ^^^^^^^^^^"
        exit 1
    fi
fi

# Check network connectivity
logthis "Checking network connectivity"
# use curl to test in case wget not installed yet.
curl -s --connect-timeout 3 --max-time 5 --retry 3 --retry-delay 0 --retry-max-time 30 "${mirror}" > /dev/null
if [[ $? -eq 0 ]]; then
  logthis "OK - $mirror is reachable"
else
  logthis "ERROR: No network connectivity"
  logthis "ERROR: unable to reach $mirror"
  logthis "^^^^^^^^^^ SCRIPT ABORTED ^^^^^^^^^^"
  exit 1
fi

# have network, install wget if missing
rpm -q wget >/dev/null 2>&1
if [ $? -ne 0 ]; then
    logthis "Installing wget"
    yum -y install wget
    if [ $? -eq 0 ]; then
        logthis "wget installed"
    else
        logthis "ERROR: wget installation failed"
        # non-fatal for this script but will cause issues after system configuration
    fi
fi

# Add eFa Repo
aCTN=(testing kstesting testingnoefa)

case "${aCTN[@]}" in
    ("$action "*|*" $action "*|*" $action")
       if [ ! -f /etc/yum.repos.d/eFa4-testing.repo ]; then
           logthis "Adding eFa Testing Repo"
           rpm --import $mirror/rpm/eFa4/RPM-GPG-KEY-eFa-Project
           curl -L $mirror/rpm/eFa4/eFa4-testing.repo -o /etc/yum.repos.d/eFa4-testing.repo
       fi
       ;;

    *) if [ ! -f /etc/yum.repos.d/eFa4.repo ]; then
           logthis "Adding eFa Repo"
           rpm --import $mirror/rpm/eFa4/RPM-GPG-KEY-eFa-Project
           curl -L $mirror/rpm/eFa4/eFa4.repo -o /etc/yum.repos.d/eFa4.repo
       fi
       ;;
esac


# echo "- Adding mariadb Repo"
# cat > /etc/yum.repos.d/mariadb.repo << 'EOF'
# # MariaDB 10.1 CentOS repository list - created 2017-03-19 11:09 UTC
# # http://downloads.mariadb.org/mariadb/repositories/
# [mariadb]
# name = MariaDB
# baseurl = http://yum.mariadb.org/10.1/centos7-amd64
# gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
# gpgcheck=1
# enabled=1
# EOF

rpm -q epel-release >/dev/null 2>&1
if [ $? -ne 0 ]; then
    logthis "Installing EPEL Repo"
    yum -y install epel-release
    if [ $? -eq 0 ]; then
        logthis "EPEL repo installed"
    else
        logthis "ERROR: EPEL installation failed"
        logthis "^^^^^^^^^^ SCRIPT ABORTED ^^^^^^^^^^"
        exit 1
    fi
fi

rpm -q ius-release >/dev/null 2>&1
if [ $? -ne 0 ]; then
    logthis "Installing IUS Repo"
    yum -y install https://centos7.iuscommunity.org/ius-release.rpm
    if [ $? -eq 0 ]; then
        logthis "IUS repo installed"
        rpm --import /etc/pki/rpm-gpg/IUS-COMMUNITY-GPG-KEY
    else
        logthis "ERROR: IUS installation failed"
        logthis "^^^^^^^^^^ SCRIPT ABORTED ^^^^^^^^^^"
        exit 1
    fi
fi

logthis "Updating the OS"
yum -y update
if [ $? -eq 0 ]; then
    logthis "System Updated"
fi

logthis "Removing conflicting packages"
yum -y remove postfix mariadb-libs >/dev/null 2>&1
# Ignore return here

# install eFa
rpm -q eFa >/dev/null 2>&1
if [ $? -ne 0 ]; then
    if [[ "$action" != "testingnoefa" ]]; then
        yum -y install eFa
        if [ $? -eq 0 ]; then
            logthis "eFa4 Installed"
        else
            logthis "ERROR: eFa4 failed to install"
            logthis "^^^^^^^^^^ SCRIPT ABORTED ^^^^^^^^^^"
            exit 1
        fi
    fi
fi

if [[ "$action" == "kstesting" || "$action" == "ksproduction" ]]; then
  # Set root default pass for kickstart builds
  echo 'echo "First time login: root/eFaPr0j3ct" >> /etc/issue' >> /etc/rc.d/rc.local
  echo "root:eFaPr0j3ct" | chpasswd --md5 root

  # Disable ssh for kickstart builds
  systemctl disable sshd
fi

logthis "============  EFA4 BUILD SCRIPT FINISHED  ============"

while true; do
    read -p "Do you wish to reboot the system now?" yn
    case $yn in
        [Yy]* ) shutdown -r +1 "Installation requires reboot. Restarting in 1 minute"; break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done
exit 0
