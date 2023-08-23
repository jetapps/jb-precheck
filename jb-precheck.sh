#!/bin/bash

# JetBackup Pre-Check Troubleshooting Script 

# Copyright 2023, JetApps, LLC.
# All rights reserved.
# Use of this script and JetBackup Software is governed by the End User License Agreement: 
# https://www.jetapps.com/legal/jetbackup-eula/
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# SCRIPT: JB-PRECHECK
# PURPOSE: Runs various diagnostics to determine common JetBackup related errors. 
# AUTHOR: Clark Poppa
# CURRENT MAINTAINER: JetApps, LLC


LINEBREAK="********************************"

echo "${LINEBREAK}"
echo "Trying CURL to get outgoing public IP address..."
MYIP="$(curl -sS -4 ifconfig.me)"
[[ $? != 0 ]] && echo "Failed CURL to determine outgoing IP address. May be blocked by Firewall or CSF."
[[ -n ${MYIP} ]] && echo "OUTGOING SERVER IP: $MYIP"
echo "${LINEBREAK}"
################################################################
# Check Connectivity to JetLicense 
################################################################

echo "Attempting to connect to JetLicense..."
echo "CMD: curl -m 30 -vsSL https://check.jetlicense.com"
CONJL=$(curl -m 30 -sSL https://check.jetlicense.com -d "product_id=111111111111111111111111" |grep "No valid Product ID was found" 1>/dev/null 2>&1)
STATUS=$?
if [[ ${STATUS} -gt 0 ]] ; then
echo "WARNING: Unable to connect to JetLicense or received unexpected response. Escalate to L2!"
elif [[ ${STATUS} == 0 ]] ; then
echo "SUCCESS: Successfully connected to JetLicense. No connectivity issues were found"
fi
echo "${LINEBREAK}"
echo "Attempting to connect to JetApps Repo..."
echo "CMD: curl -m 30 -vsSL https://repo.jetlicense.com"
CONREPO=$(curl -m 30 -sSL https://repo.jetlicense.com |grep -q "LiteSpeed Web Server at repo.jetlicense.com Port 443" 1>/dev/null 2>&1)
STATUSR=$?
if [[ ${STATUSR} != 0 ]] ; then
echo "WARNING: Unable to connect to JetApps Repo or received unexpected response. Check with L2!"
elif [[ ${STATUSR} == 0 ]] ; then
echo "SUCCESS: Successfully connected to JetApps Repo. No connectivity issues were found"
fi
echo "${LINEBREAK}"

################################################################
# Check cron 
################################################################

echo "Checking Crons for issues..."
JB4_CRON_FILE="/etc/cron.d/jetbackup"
JETAPPS_CRON_FILE="/etc/cron.d/jetapps"

! [[ -f ${JB4_CRON_FILE} ]] && echo "${JB4_CRON_FILE} Cron file missing. This could cause issues running schedules in JetBackup 4.x."

! [[ -f ${JETAPPS_CRON_FILE} ]] && echo "WARN: Auto Update Cron ${JETAPPS_CRON_FILE} not found. You may not receive updates."

JB_CRONS="/etc/cron.d"
for file in "${JB_CRONS}"/*?et?ackup* ; do
IFS=$'\n'
if [[ -f "$file" ]] && [[ "$file" != 'jetbackup' ]] && [[ "$file" != *"rpmsave" ]]; then
echo "Additional JetBackup Crons Found: ${file}".
ADDL_CRON=1
fi
done
[[ -n "$ADDL_CRON" ]] && echo "WARN: Custom crons can effect JB function. Verify there are no conflicts." || echo "Crons OK"
echo "${LINEBREAK}"

################################################################
# Check binaries 
################################################################

echo "${LINEBREAK}"
echo "Checking for missing or unexpected binaries..."
# https://saasbase.dev/tools/regex-generator
JB5_BIN_PATH="/usr/bin"
JB5_BINFILES=(
    "${JB5_BIN_PATH}/jetapps"
    "${JB5_BIN_PATH}/jetbackup5"
    "${JB5_BIN_PATH}/jetbackup5api"
    "${JB5_BIN_PATH}/jetmongo"
)

JB5_regex=( $(find /usr/bin/ -maxdepth 1 | grep -E 'jet(apps|api|backup5api|backup5|cli|mongo)|.*CSPupdate|update_jetbackup|esp\b'))
# diff_array=( $("${JB5_BINFILES[@]}" "${JB5_regex[@]}"| sort | uniq -d))
COUNT_B=$(echo ${JB5_BINFILES[@]} ${JB5_regex[@]} | tr ' ' '\n' | sort | uniq -u | wc -l)

if [[ ${COUNT_B} > 0 ]]; then
echo "Found ${COUNT_B} unexpected or missing binaries:"
echo ${JB5_BINFILES[@]} ${JB5_regex[@]} | tr ' ' '\n' | sort | uniq -u
elif [[ ${COUNT_B} == 0 ]]; then
echo "OK"
fi

echo "${LINEBREAK}"

################################################################
# Check MongoDB paths for common problems.
################################################################

echo "${LINEBREAK}"
echo "Checking MongoDB permissions/ownership for common problems"

MONGO_DIRS=( /usr/local/jetapps/var/lib/mongod /usr/local/jetapps/var/log/mongod /usr/local/jetapps/var/run/mongod /tmp/mongodb-27217.sock )
for dir in "${MONGO_DIRS[@]}"
do
IFS=$'\n'
    for file in $(find $dir ! -user mongod ! -name "*log*")
    do
echo "[WARNING] $file doesn't have expected owner. This may cause issues with MongoDB."
MONGO_PERM_ISSUE=1
echo "DONE."
    done
done

CHECKONLY_DIRS=( /tmp /dev/null )
for dir in "${CHECKONLY_DIRS[@]}"
do
IFS=$'\n'
    for perms in $(find $dir -maxdepth 0 -exec stat -c '%a' '{}' +)
    do
    if  [[ $dir == "/tmp" ]] && [[ $perms != *1777 ]]; then
echo "WARN: $dir doesn't have the expected permissions. (Got $perms Expected 1777) - This may cause issues with MongoDB."
echo "Please see our Knowledgebase for more information: https://billing.jetapps.com/index.php?rp=/knowledgebase/5/Jetmongod-Install-Errors.html "
MONGO_PERM_ISSUE=1
fi
if [[ $dir == "/dev/null" ]] && [[ $perms != *666 ]]; then
echo "WARN: $dir doesn't have the expected permissions. (Got $perms Expected 666) - This may cause issues with MongoDB."
echo "Please see our Knowledgebase for more information: https://billing.jetapps.com/index.php?rp=/knowledgebase/5/Jetmongod-Install-Errors.html "
MONGO_PERM_ISSUE=1
fi
    done
done
unset IFS
[[ -n $MONGO_PERM_ISSUE ]] && echo "jetmongod permissions issue(s) found." || echo "OK"

echo "${LINEBREAK}"

################################################################
# Check journalctl for errors
################################################################

if [[ $(systemctl -q is-active jetbackup5d > /dev/null 2>&1 ; echo $?) != 0 ]]; then 
echo "JetBackup 5 service not running."
echo "Checking journalctl for errors. Displaying last 10 journalctl entries. This could take a while..."
journalctl -q -u jetbackup5d -n 10 --no-pager
else 
echo -e "jetbackup5d service:\nOK\n"
fi

echo "${LINEBREAK}"

if [[ $(systemctl -q is-active jetmongod > /dev/null 2>&1 ; echo $?) != 0 ]]; then 
echo "jetmongod service not running."
echo "Checking logs for errors. Displaying last 5 logged errors. This could take a while..."
grep -E '"s":"E"|Fatal assertion|WiredTiger error' /usr/local/jetapps/var/log/mongod/mongod.log | tail -5
else 
echo -e "jetmongod service:\nOK\n"
fi

echo "${LINEBREAK}"

