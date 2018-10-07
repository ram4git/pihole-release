#!/bin/bash

if [ ! -d "/var/log/pihole/" ]
then
    mkdir -p "/var/log/pihole"
    touch /var/log/pihole/upgrade
fi

exec &> /var/log/pihole/upgrade


# -e option instructs bash to immediately exit if any command [1] has a non-zero exit status
# We do not want users to end up with a partially working install, so we exit the script
# instead of continuing the installation with something broken
set -e

## CONSTANTS
NEW_SNS_CONFIG_FILE=/tmp/sns-config
TEMP_DOWNLOAD_DIR=/tmp/sns
ADMIN_GIT_URL=https://github.com/ram4git/AdminLTE
WEB_INTERFACE_DIR="/var/www/html/admin"
CURRENT_SNS_ID_FILE=/etc/pihole/snsvid
CURRENT_SNS_HISTORY_FILE=/etc/pihole/snshistory

## GET LATEST CONFIG
logger sns "Fetching latest config..""
rm -rf ${NEW_SNS_CONFIG_FILE}
wget -O ${NEW_SNS_CONFIG_FILE} https://raw.githubusercontent.com/ram4git/pihole-release/master/config
if [ ! -f ${NEW_SNS_CONFIG_FILE} ]; then
    echo "Unable to download SNS upgrade configuration"
    logger sns "Unable to download SNS configuration"
    exit 0;
fi

source ${NEW_SNS_CONFIG_FILE}
CURRENT_SNS_VERSION_ID=`cat ${CURRENT_SNS_ID_FILE}`

if [ "${SNS_ID}" > "${CURRENT_SNS_VERSION_ID}" ]; then
    # UPGRADE IS NEEDED
    echo "Needs Upgradation. Begining to upgrade"
    logger sns "New Version of SNS Admin is available"
else 
    echo "SNS is up to date !"
    logger sns "SNS is up to date"
    exit 0;
fi

## UPGRADE WEB ADMIN
mkidr ${TEMP_DOWNLOAD_DIR}
#git clone --branch ${SNS_TAG} https://github.com/ram4git/AdminLTE
#git clone -q --depth 1  --branch ${SNS_TAG} "https://github.com/ram4git/AdminLTE" "${TEMP_DOWNLOAD_DIR}" &> /dev/null || return $?
get_files_from_repository ${WEB_INTERFACE_DIR} ${ADMIN_GIT_URL} ${SNS_TAG}



## UPDATE SUCCESS
DATE=`date '+%Y-%m-%d %H:%M:%S'`

echo ${SNS_ID} > ${CURRENT_SNS_ID_FILE}
echo ${DATE} ${SNS_ID} >> ${CURRENT_SNS_HISTORY_FILE}

logger sns 'Successfully upgraded SNS'



get_files_from_repository() {
    # Set named variables for better readability
    local directory="${1}"
    local remoteRepo="${2}"
    local tag="${2}"
    # The message to display when this function is running
    str="Clone ${remoteRepo} into ${directory}"
    # Display the message and use the color table to preface the message with an "info" indicator
    echo -ne "  ${INFO} ${str}..."
    # If the directory exists,
    if [[ -d "${directory}" ]]; then
        # delete everything in it so git can clone into it
        rm -rf "${directory}"
    fi
    # Clone the repo and return the return code from this command
    git clone -q --depth 1 --branch "${tag}" "${remoteRepo}" "${TEMP_DOWNLOAD_DIR}" &> /dev/null || return $?
    # Show a colored message showing it's status
    echo -e "${OVER}  ${TICK} ${str}"
    # Always return 0? Not sure this is correct
    cp -rf "${TEMP_DOWNLOAD_DIR}/*" "${direcotry}/"
    logger sns "Succesfully copied latest files"
    return 0
}



# A function to clone a repo
make_repo() {
    # Set named variables for better readability
    local directory="${1}"
    local remoteRepo="${2}"
    local tag="${3}"
    # The message to display when this function is running
    str="Clone ${remoteRepo} into ${directory}"
    # Display the message and use the color table to preface the message with an "info" indicator
    echo -ne "  ${INFO} ${str}..."
    # If the directory exists,
    if [[ -d "${directory}" ]]; then
        # delete everything in it so git can clone into it
        rm -rf "${directory}"
    fi
    # Clone the repo and return the return code from this command
    if [ -z "$tag" ] 
    then
         git clone -q --depth 1 --branch "${tag}" "${remoteRepo}" "${directory}" &> /dev/null || return $?

    else
        git clone -q --depth 1 "${remoteRepo}" "${directory}" &> /dev/null || return $?

    fi
    # Show a colored message showing it's status
    echo -e "${OVER}  ${TICK} ${str}"
    # Always return 0? Not sure this is correct
    return 0
}


clone_or_update_repos() {

    getGitFiles ${PI_HOLE_LOCAL_REPO} ${piholeGitUrl} || \
    { echo -e "  ${COL_LIGHT_RED}Unable to clone ${piholeGitUrl} into ${PI_HOLE_LOCAL_REPO}, unable to continue${COL_NC}"; \
    exit 1; \
    }
    # If the Web interface was installed,
    if [[ "${INSTALL_WEB_INTERFACE}" == true ]]; then
        # get the Web git files
        getGitFiles ${webInterfaceDir} ${webInterfaceGitUrl} || \
        { echo -e "  ${COL_LIGHT_RED}Unable to clone ${webInterfaceGitUrl} into ${webInterfaceDir}, exiting installer${COL_NC}"; \
        exit 1; \
        }
    fi
}
