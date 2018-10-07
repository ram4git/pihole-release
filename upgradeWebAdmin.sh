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
NEW_SNS_CONFIG_FILE=/tmp/sns_config
TEMP_DOWNLOAD_DIR=/tmp/sns
ADMIN_GIT_URL=https://github.com/ram4git/AdminLTE
WEB_INTERFACE_DIR="/var/www/html/admin"
CURRENT_SNS_ID_FILE=/etc/pihole/snsvid
CURRENT_SNS_HISTORY_FILE=/etc/pihole/snshistory

main() {
    DATE=`date '+%Y-%m-%d %H:%M:%S'`

    logger SNS "${DATE} Checking if upgrade is needed!"
    ## GET LATEST CONFIG
    logger SNS "Fetching latest config.."
    rm -rf ${NEW_SNS_CONFIG_FILE}
    wget -O ${NEW_SNS_CONFIG_FILE} https://raw.githubusercontent.com/ram4git/pihole-release/master/config
    if [ ! -f ${NEW_SNS_CONFIG_FILE} ]; then
        echo "Unable to download SNS upgrade configuration"
        logger SNS "Unable to download SNS configuration"
        exit 0;
    fi

    source ${NEW_SNS_CONFIG_FILE}
    CURRENT_SNS_VERSION_ID=`cat ${CURRENT_SNS_ID_FILE}`

    logger SNS "SNS_ID ${SNS_ID}"
    logger SNS "CURRENT_SNS_VERSION_ID ${CURRENT_SNS_VERSION_ID}"


    if [ $(($SNS_ID+0)) -eq $(($CURRENT_SNS_VERSION_ID+0)) ]; then
        echo "SNS is up to date !"
        logger SNS "SNS is up to date"
        exit 0;
    else
        # UPGRADE IS NEEDED
        echo "Needs Upgradation. Begining to upgrade"
        logger SNS "New Version of SNS Admin is available"
    fi

    logger SNS "Begining Upgrade"

    ## UPGRADE WEB ADMIN
    #git clone --branch ${SNS_TAG} https://github.com/ram4git/AdminLTE
    #git clone -q --depth 1  --branch ${SNS_TAG} "https://github.com/ram4git/AdminLTE" "${TEMP_DOWNLOAD_DIR}" &> /dev/null || return $?
    get_files_from_repository ${WEB_INTERFACE_DIR} ${ADMIN_GIT_URL} ${SNS_TAG}

    retVal=$?

    if [  $retVal -ne 0 ]; then
        echo "Unable to clone latest admin console"
        logger SNS "Unable to clone ${ADMIN_GIT_URL}#${SNS_TAG} to ${WEB_INTERFACE_DIR}" $?
        exit 0;
    fi

    ## UPDATE SUCCESS

    echo ${SNS_ID} > ${CURRENT_SNS_ID_FILE}
    echo ${DATE} ${SNS_ID} >> ${CURRENT_SNS_HISTORY_FILE}

    logger SNS "Successfully upgraded SNS"
}




# A function for checking if a folder is a git repository
is_repo() {
    # Use a named, local variable instead of the vague $1, which is the first argument passed to this function
    # These local variables should always be lowercase
    local directory="${1}"
    # A local variable for the current directory
    local curdir
    # A variable to store the return code
    local rc
    # Assign the current directory variable by using pwd
    curdir="${PWD}"
    # If the first argument passed to this function is a directory,
    if [[ -d "${directory}" ]]; then
        # move into the directory
        cd "${directory}"
        # Use git to check if the folder is a repo
        # git -C is not used here to support git versions older than 1.8.4
        git status --short &> /dev/null || rc=$?
    # If the command was not successful,
    else
        # Set a non-zero return code if directory does not exist
        rc=1
    fi
    # Move back into the directory the user started in
    cd "${curdir}"
    # Return the code; if one is not set, return 0
    return "${rc:-0}"
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
    git clone -q --depth 1 --branch "${tag}" "${remoteRepo}" "${directory}" &> /dev/null || return $?
    # Show a colored message showing it's status
    echo -e "${OVER}  ${TICK} ${str}"
    # Always return 0? Not sure this is correct
    return 0
}

# We need to make sure the repos are up-to-date so we can effectively install Clean out the directory if it exists for git to clone into
update_repo() {
    # Use named, local variables
    # As you can see, these are the same variable names used in the last function,
    # but since they are local, their scope does not go beyond this function
    # This helps prevent the wrong value from being assigned if you were to set the variable as a GLOBAL one
    local directory="${1}"
    local tag="${2}"
    local curdir

    # A variable to store the message we want to display;
    # Again, it's useful to store these in variables in case we need to reuse or change the message;
    # we only need to make one change here
    local str="Update repo in ${1}"

    # Make sure we know what directory we are in so we can move back into it
    curdir="${PWD}"
    # Move into the directory that was passed as an argument
    cd "${directory}" &> /dev/null || return 1
    # Let the user know what's happening
    echo -ne "  ${INFO} ${str}..."
    # Stash any local commits as they conflict with our working code
    git stash --all --quiet &> /dev/null || true # Okay for stash failure
    git clean --quiet --force -d || true # Okay for already clean directory
    # Pull the latest commits
    git checkout tags/"${tag}" --quiet &> /dev/null || return $?
    # Show a completion message
    echo -e "${OVER}  ${TICK} ${str}"
    # Move back into the original directory
    cd "${curdir}" &> /dev/null || return 1
    return 0
}


get_files_from_repository() {
    # Set named variables for better readability
    local directory="${1}"
    local remoteRepo="${2}"
    local tag="${3}"
    local str="Check for existing repository in ${1}"

    # The message to display when this function is running
    str="Clone ${remoteRepo} into ${directory}"
    # Display the message and use the color table to preface the message with an "info" indicator
    echo -ne "  ${INFO} ${str}..."
    # If the directory exists,
    if [[ -d "${directory}" ]]; then
        # delete everything in it so git can clone into it
        rm -rf ${directory}
    fi
    
    mkdir ${directory}

    if [[ -d "${TEMP_DOWNLOAD_DIR}" ]]; then
        rm -rf "${TEMP_DOWNLOAD_DIR}"
        mkdir ${TEMP_DOWNLOAD_DIR}
    fi


    # Show the message
    echo -ne "  ${INFO} ${str}..."
    # Check if the directory is a repository
    if is_repo "${directory}"; then
        # Show that we're checking it
        echo -e "${OVER}  ${TICK} ${str}"
        # Update the repo, returning an error message on failure
        update_repo "${directory}" "${tag}" || { echo -e "\\n  ${COL_LIGHT_RED}Error: Could not update local repository. Contact support.${COL_NC}"; exit 1; }
    # If it's not a .git repo,
    else
        # Show an error
        echo -e "${OVER}  ${CROSS} ${str}"
        # Attempt to make the repository, showing an error on failure
        make_repo "${directory}" "${remoteRepo}"  "${tag}"|| { echo -e "\\n  ${COL_LIGHT_RED}Error: Could not update local repository. Contact support.${COL_NC}"; exit 1; }
    fi
    # echo a blank line
    echo ""

    # Clone the repo and return the return code from this command
    #logger SNS "git clone -q --depth 1 --branch ${tag} ${remoteRepo} ${TEMP_DOWNLOAD_DIR}"
    #git clone -q --depth 1 --branch "${tag}" "${remoteRepo}" "${TEMP_DOWNLOAD_DIR}" || return $?
    # Show a colored message showing it's status
    echo -e "${OVER}  ${TICK} ${str}"
    # Always return 0? Not sure this is correct
    #cp -rf ${TEMP_DOWNLOAD_DIR}/* ${direcotry}/
    chown -R pi:pi ${directory}
    logger SNS "Succesfully copied latest files"
    return 0
}

# A function that combines the functions previously made
# getGitFiles() {
#     # Setup named variables for the git repos
#     # We need the directory
#     local directory="${1}"
#     # as well as the repo URL
#     local remoteRepo="${2}"
#     # A local variable containing the message to be displayed
#     local str="Check for existing repository in ${1}"
#     # Show the message
#     echo -ne "  ${INFO} ${str}..."
#     # Check if the directory is a repository
#     if is_repo "${directory}"; then
#         # Show that we're checking it
#         echo -e "${OVER}  ${TICK} ${str}"
#         # Update the repo, returning an error message on failure
#         update_repo "${directory}" || { echo -e "\\n  ${COL_LIGHT_RED}Error: Could not update local repository. Contact support.${COL_NC}"; exit 1; }
#     # If it's not a .git repo,
#     else
#         # Show an error
#         echo -e "${OVER}  ${CROSS} ${str}"
#         # Attempt to make the repository, showing an error on failure
#         make_repo "${directory}" "${remoteRepo}" || { echo -e "\\n  ${COL_LIGHT_RED}Error: Could not update local repository. Contact support.${COL_NC}"; exit 1; }
#     fi
#     # echo a blank line
#     echo ""
#     # and return success?
#     return 0
# }


main "$@"
logger SNS 'UPGRADE CHECK DONE !' 