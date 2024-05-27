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

set -o pipefail

getIP() {

echo "${LINEBREAK}"

# Determine the IP address protocol to use from JB5
if [[ -f /usr/local/jetapps/etc/.mongod.auth ]]; 
then
echo "Checking the default IP Protocol set for JB5..."
source /usr/local/jetapps/etc/.mongod.auth
FORCE_IP=$( /usr/local/jetapps/usr/bin/mongosh --quiet --port $PORT -u $USER -p $PASS --authenticationDatabase admin --eval 'print(db.config.find({_id:"license"}).next().force_ip);' jetbackup5 )
fi
# Default to IPv4 if not found or set to auto
[[ ${FORCE_IP} -eq 0 ]] && FORCE_IP=4
[[ -z ${FORCE_IP} ]] && FORCE_IP=4

echo "Attempting to find outgoing public IP address..."
MYIP="$(curl \-${FORCE_IP} -sS ifconfig.me)"
STATUS1="$?"
# If the above fails and force IP was 6, try with 4. But if it fails and Force IP was 4, try with 6. 
if [[ -z ${MYIP} ]] && [[ ${STATUS1} != 0 && ${FORCE_IP} -eq 6 ]]; then
MYIP="$(curl -4 -sS ifconfig.me)"
elif [[ -z ${MYIP} ]] && [[ ${STATUS1} != 0 && ${FORCE_IP} -eq 4 ]]; then
MYIP="$(curl -6 -sS ifconfig.me)"
fi

[[ -z ${MYIP} ]] && echo "ERROR - Could not find a valid IPv4 or IPv6 address. CURL may have been blocked by Firewall or CSF."
[[ -n ${MYIP} ]] && echo "OUTGOING SERVER IP: $MYIP"


}



getOS() {

  echo "${LINEBREAK}"
  echo "Server Details:"
[[ ! -f /etc/os-release ]] && echo "Aborted: Can't find /etc/os-release file" 
if [ -f /etc/os-release ]; then
. /etc/os-release
OS=$NAME
VER=$VERSION_ID
ID=$ID
fi

  echo "OS: $NAME $VERSION_ID"

# Determine the package manager. 
if [[ -x "$(command -v yum)" || -x "$(command -v dnf)" ]]; then
RPM_PKG=1
elif [[ -x "$(command -v apt-get)" ]]; then
APT_PKG=1
else 
	echo -en "[ERROR] Failed fetching package manager." 
fi

}


validateLicense() {

echo "${LINEBREAK}"

# 58ac64be19a4643cdf582727
# [[ -n ${MYIP} ]] && echo -e "JetBackup License Status (Activation Date, Type, Partner, Status): \n$(curl --get \-${FORCE_IP} -m 30 -LSs --data-urlencode "ip=${MYIP}" https://billing.jetapps.com/verify.php | grep -i 'jetlicense_info' -A11 | awk -F ' ' '{print $5}' | awk -F '>' '{print $2}' | sed 's/<\/td//g')" | tr -s "[:space:]" || echo "[WARN] Skipped License Check - Failed to obtain IP address in outgoing IP step."

[[ -n ${MYIP} ]] && echo "JetBackup License Status:"

LICFORMAT="Created:
Type:
Partner:
Status:"
STATUS="$(curl --get -m 30 -LSs --data-urlencode "ip=${MYIP}" https://billing.jetapps.com/verify.php | grep -i 'jetlicense_info' -A11 | awk -F ' ' '{print $5}' | awk -F '>' '{print $2}' | sed 's/<\/td//g' | tr -s "[:space:]" )"

[[ -n ${STATUS} ]] && paste <(echo "$LICFORMAT") <(echo "${STATUS}" | sed '/^[[:space:]]*$/d') --delimiters ' ' || echo "Could not get License Status. (Not licensed?)"
echo "${LINEBREAK}"

}


################################################################
# Check Connectivity to JetLicense 
################################################################

JetLicense_Test() {


echo "Attempting to connect to JetLicense..."
echo "CMD: curl -m 30 -vsSL https://check.jetlicense.com"
CONJL=$(curl -m 30 -sSL https://check.jetlicense.com -d "product_id=111111111111111111111111" |grep "No valid Product ID was found" 1>/dev/null 2>&1)
STATUS=$?
if [[ ${STATUS} -gt 0 ]] ; then
echo "WARNING: Unable to connect to JetLicense or received unexpected response. Escalate to L2!"
elif [[ ${STATUS} == 0 ]] ; then
echo "OK"
fi
echo "${LINEBREAK}"
echo "Attempting to connect to JetApps Repo..."
echo "CMD: curl -m 30 -vsSL https://repo.jetlicense.com"
CONREPO=$(curl -m 30 -sSL https://repo.jetlicense.com |grep -q "LiteSpeed Web Server at repo.jetlicense.com Port 443" 1>/dev/null 2>&1)
STATUSR=$?
if [[ ${STATUSR} != 0 ]] ; then
echo "WARNING: Unable to connect to JetApps Repo or received unexpected response. Check with L2!"
elif [[ ${STATUSR} == 0 ]] ; then
echo "OK"
fi
echo "${LINEBREAK}"

}

################################################################
# Compare installed version to latest version from repository
################################################################

MinVersionCheck() {



echo "Determining whether JB5 is out of date..."


# current_version=$(jetbackup5 --version 2>/dev/null | awk -F "|" '{print $1}' | awk -F " " '{print $NF}' | sed -n 1p)
# updates_tier=$(jetbackup5 --version 2>/dev/null | awk -F "|" '{print $2}' | grep -oP "(?<=Current Tier )[A-Z]+" | tr '[:upper:]' '[:lower:]')

[[ -n $JBVersion ]] && current_version=$(echo "${JBVersion}" | awk -F "|" '{print $1}' | awk -F " " '{print $NF}' | sed -n 1p)
[[ -n $JBVersion ]] && updates_tier=$(echo "${JBVersion}" | awk -F "|" '{print $2}' | grep -oP "(?<=Current Tier )[A-Z]+" | tr '[:upper:]' '[:lower:]')

# Only checking the first 3 digits of the version. 
if [[ -n ${RPM_PKG} ]]; then
  LATEST_STABLE=$(curl -m 30 -LSs http://repo.jetlicense.com/centOS/8/x86_64/${updates_tier}/RPMS/ | grep "jetbackup5-${panel}" | awk -F ' ' '{print $5}' | sed -n 's#href=".*">\(.*\)</a>.*#\1#p' | awk -F '-' '{print $3}' | sort | tail -1)
elif [[ -n ${APT_PKG} ]]; then
  LATEST_STABLE=$(curl -m 30 -LSs http://repo.jetlicense.com/debian/dists/bullseye/${updates_tier}/main/binary-amd64/ | grep "jetbackup5-${panel}" | awk -F ' ' '{print $5}' | sed -n 's#href=".*">\(.*\)</a>.*#\1#p' | awk -F '-' '{print $3}' | sort | tail -1)
fi

# If either variable is empty, skip the rest of the function.
[[ -z "${current_version}" || -z ${LATEST_STABLE} ]] && echo "Failed to determine versions for compare." && return 1

# Convert the version number to remove periods. Required for the proceeding if statement.
function version_parse { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }
if [[ $(version_parse $current_version) -ge $(version_parse $LATEST_STABLE) ]]; then
    echo -e "Version ${current_version} is up to date.\nOK"
    else
    WARNING_OLD_VERSION=1
    echo "[WARN] JetBackup 5 version is outdated! Got ${current_version} Expected ${LATEST_STABLE} - Updates Tier: ${updates_tier}"
fi

[[ $WARNING_OLD_VERSION == 1 ]] && echo -e "[WARN] The installed JetBackup 5 version is older than the latest ${updates_tier} release!\nUpdate with the command:\n jetapps -u jetbackup5-${panel}"

echo "${LINEBREAK}"

}



getPanelDetails() {

JBVersion="$(jetbackup5 --version 2>/dev/null| sed "2 d")" 
JB4Version="$(jetbackup --version 2>/dev/null| sed "2 d")"

# Checking the installed control panel
PANEL=""
[[ -x "$(command -v uapi)" || -x "$(command -v whmapi1)" ]] && PANEL="cPanel/WHM" && panel="cpanel"
[[ -x "$(command -v /usr/local/directadmin/directadmin)" ]] && PANEL="DirectAdmin" && panel="directadmin"
[[ -x "$(command -v plesk)" ]] && PANEL="Plesk" && panel="plesk"
[[ -x "$(command -v /usr/bin/nodeworx)" ]] && PANEL="InterWorx" && panel="interworx"

# Per-Panel Checks

case ${PANEL} in 
cPanel/WHM) echo "Panel: ${PANEL}"
echo "Panel Version: $(cat /usr/local/cpanel/version 2>/dev/null)"
LICENSESTATUS="$(curl -LSs https://verify.cpanel.net/index.cgi?ip=${MYIP} | grep 'cPanel/WHM</td' -A1 | sed -n 2p  | perl -pe 's/<[^>]*>//g')"
echo "cPanel License Status: ${LICENSESTATUS}"
[[ -n $JBVersion ]] && echo "JB5 Version: ${JBVersion}"
[[ -n $JB4Version ]] && echo "JB4 Version: ${JB4Version}" 
validateLicense
;;
DirectAdmin) echo "Panel: ${PANEL}"
echo "Panel Version: $(/usr/local/directadmin/directadmin v | awk '{print $2, $3}')"
[[ -n $JBVersion ]] && echo "Version: ${JBVersion}" || echo "No JetBackup 5 version information available."

validateLicense
;;
Plesk) echo "Panel: ${PANEL}"
echo "Panel Version:$(plesk -v | awk 'NR==1' |cut -d ":" -f 2)"
[[ -n $JBVersion ]] && echo "Version: ${JBVersion}" || echo "No JetBackup 5 version information available."
validateLicense
;;
InterWorx) echo "Panel: ${PANEL}"
echo "Panel Version: $(grep 'rpm.release="' /usr/local/interworx/iworx.ini | cut -d "\"" -f 2)"
[[ -n $JBVersion ]] && echo "Version: ${JBVersion}" || echo "No JetBackup 5 version information available."
validateLicense
;;
*) echo "Panel: N/A"
[[ -n $JBVersion ]] && echo "Version: ${JBVersion}" || echo "No JetBackup 5 version information available."
[[ -n $JB4Version ]] && echo "JB4 Version: ${JB4Version}" 
panel="linux"
validateLicense
;;
esac

}

getIP
getOS
getPanelDetails
JetLicense_Test
MinVersionCheck

################################################################
# Check cron 
################################################################


fraud_check() {


echo "${LINEBREAK}"
echo "Checking for fraud..."
# Known binaries or crons that cause problems with JetBackup. 
# IMPORTANT: *** Any Binary or Cron listed below is **NOT** developed or distributed by JetApps, nor has any relation to our software. ***
#FRAUD_BIN=( $(find /usr/bin/ -maxdepth 1 | grep -Ei 'regex') )
#FRAUD_CRON=( $(find /etc/cron.d/ -maxdepth 3 | grep -Ei 'regex') )

if [[ "$(type -t mapfile)" == "builtin" ]]; 
then
mapfile -t FRAUD_BIN < <(find /usr/bin/ -maxdepth 1 | grep -Ei 'CSPupdate|update_jetbackup|\besp\b|esp_jetbackup|gblicensecp\b|gblicensecpcheck\b|GbCpanel|gbcpcronbackup|gblicensecp|gblicensecpcheck|licsys')
mapfile -t FRAUD_CRONS < <(find /etc/cron.d/ -maxdepth 3 | grep -Ei 'licensecp|licensejp|gblicensecp|Rcjetbackup|RcLicenseJetBackup|RCcpanelv3|esp_jetbackup|\besp\b|gbcp\b|licsys')
fi


for BIN in "${FRAUD_BIN[@]}" ; do
IFS=$'\n'
if [[ -n "${BIN}" ]]; then
FILE_MODIFY_DATE="$(date +%F -r ${BIN})"
echo "[WARN] FOUND FRAUDULENT BINARY: ${BIN} - Last Modified Date: ${FILE_MODIFY_DATE}"
FRAUD_DETECTED=1
fi
done

for CRON in "${FRAUD_CRONS[@]}" ; do
IFS=$'\n'
if [[ -n "${CRON}" ]]; then
FILE_MODIFY_DATE="$(date +%F -r ${CRON})"
echo "[WARN] FOUND FRAUDULENT CRON: ${CRON} - Last Modified Date: ${FILE_MODIFY_DATE}"
FRAUD_DETECTED=1
fi
done

[[ -n $FRAUD_DETECTED ]] && echo "ABORTED: EVIDENCE OF LICENSE CIRCUMVENTION. INELIGIBLE FOR SUPPORT" && exit 1 || echo "OK"
#TODO: Check for License.inc 

}

fraud_check

echo "${LINEBREAK}"
echo "Checking Crons for issues..."
JB4_CRON_FILE="/etc/cron.d/jetbackup"
JETAPPS_CRON_FILE="/etc/cron.d/jetapps"

[[ ! -f ${JB4_CRON_FILE} && -n ${JB4Version} ]] && echo "${JB4_CRON_FILE} Cron file missing. This could cause issues running schedules in JetBackup 4.x."

! [[ -f ${JETAPPS_CRON_FILE} ]] && echo "WARN: Auto Update Cron ${JETAPPS_CRON_FILE} not found. You may not receive updates."

JB_CRONS="/etc/cron.d"
for file in "${JB_CRONS}"/*?et?ackup* ; do
IFS=$'\n'
if [[ -f "$file" ]] && [[ "$file" != "/etc/cron.d/jetbackup" ]] && [[ "$file" != *"rpmsave" ]]; then
echo "Additional JetBackup Crons Found: ${file}".
ADDL_CRON=1
fi
done


[[ -n "$ADDL_CRON" ]] && echo "WARN: Custom crons can effect JB function. Verify there are no conflicts." || echo "Crons OK"

################################################################
# Check binaries 
################################################################

echo "${LINEBREAK}"
echo "Checking for missing binaries..."
# https://saasbase.dev/tools/regex-generator
JB5_BIN_PATH="/usr/bin"
JB5_BINFILES=(
    "${JB5_BIN_PATH}/jetapps"
    "${JB5_BIN_PATH}/jetbackup5"
    "${JB5_BIN_PATH}/jetbackup5api"
    "${JB5_BIN_PATH}/jetmongo"
)

JB5_regex=( $(find /usr/bin/ -maxdepth 1 | grep -E 'jet(apps|api|backup5api|backup5|cli|mongo)'))
# diff_array=( $("${JB5_BINFILES[@]}" "${JB5_regex[@]}"| sort | uniq -d))
COUNT_B=$(echo ${JB5_BINFILES[@]} ${JB5_regex[@]} | tr ' ' '\n' | sort | uniq -u | wc -l)

if [[ ${COUNT_B} > 0 ]]; then
echo "Found ${COUNT_B} unexpected or missing binaries:"
echo ${JB5_BINFILES[@]} ${JB5_regex[@]} | tr ' ' '\n' | sort | uniq -u
elif [[ ${COUNT_B} == 0 ]]; then
echo "OK"
fi

################################################################
# Check MongoDB paths for common problems.
################################################################

echo "${LINEBREAK}"
echo "Checking MongoDB permissions/ownership for common problems"
#TODO: Check /etc
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

if [[ -x "$(command -v needs-restarting)" ]]; then
echo "Checking if services need restarting..."
NEEDRESTART=$(needs-restarting -s 2>/dev/null |grep -Ei 'jetbackup5d|jetmongod' | awk -F. '{print $1}')
if [[ -n ${NEEDRESTART} ]]; then
echo "[WARN] needs-restarting recommends restart of JB services. Verify no backups, restores, or downloads are running then try restarting the services listed below:"
printf '%s\n' "${NEEDRESTART[@]}"
else
echo "OK"
fi
fi

echo "${LINEBREAK}"

if [[ $(systemctl -q is-active jetbackup5d > /dev/null 2>&1 ; echo $?) != 0 ]]; then 
echo "JetBackup 5 service not running."
echo "Checking journalctl for errors. Displaying last 10 journalctl entries."
journalctl -q -u jetbackup5d -n 10 --no-pager
else 
echo -e "jetbackup5d service:\nactive"
fi

echo "${LINEBREAK}"

if [[ $(systemctl -q is-active jetmongod > /dev/null 2>&1 ; echo $?) != 0 ]]; then 
echo "jetmongod service not running."
echo "Checking logs for errors. Displaying last 10 logged errors."
grep -E '"s":"E"|Fatal assertion|WiredTiger error' /usr/local/jetapps/var/log/mongod/mongod.log | tail -10
else 
echo -e "jetmongod service:\nactive"
fi

echo "${LINEBREAK}"

