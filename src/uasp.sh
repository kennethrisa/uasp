#!/bin/bash

# Maintainer: kennethrisa
# Github: https://github.com/kennethrisa/uasp
# Description: UASP - Umod Autoupdate Script for Plugins

uasp_version="0.1.0"
uasp_github="https://github.com/kennethrisa/uasp"
script_dir="$( cd "$( dirname "$0" )" && pwd )"
config_file="config.sh"

# Colors
red=`tput setaf 1`
green=`tput setaf 2`
yellow=`tput setaf 3`
blue=`tput setaf 4`
reset=`tput sgr0`

# Checking if you have dependencies installed
if ! command -v jq &>/dev/null; then
    echo "jq is not installed - if you are on debian/ubuntu, run: sudo apt install jq -y"
    exit 1
fi

# Checking if config.sh exist
if [ -f !"$config_file" ]; then
    init
    sleep 1
    exit 1
else
    . $config_file
fi

# Init the config file
function fn_config_init() {
    echo "Creating config file"
cat <<EOF | tee ./$config_file
plugins_dir=""
tmp_dir="tmp"
plugins_file="plugins.json"
plugins_file_tmp="tmp_plugins.json"
plugins_file_outdated="outdated_plugins.txt"
autoupdate_plugin=true # Needs to be true or false
discord_webhook_url="https://discordapp.com/api/webhooks/" # Discord webhook url
enable_alerts=false # true or false. Needs to be true to enable notification to discord
EOF
    echo -e "Init done"
}

function fn_alert_info() {
    if [[ $enable_alerts = true ]]; then
        plugin_update_page="https://umod.org/plugins/$pluginname#updates"
        curl -X POST --max-time 3 --data '{ "username": "UASP","avatar_url": "", "content": "", "embeds": [{"title": "'$pluginname'", "url": "'$plugin_update_page'", "color": "3406737", "fields": [{"name": "Autoupdate:","value": "'$autoupdate_plugin'", "inline": true},{"name": "Old Version: ","value": "'$current_version'", "inline": true},{"name": "New Version: ","value": "'$version'","inline": true}],"footer": {"text": "UASP version: '$uasp_version'"},"thumbnail": { "url": "https://pbs.twimg.com/profile_images/791068896124166144/KEdjn2Z-_400x400.jpg" } }]  }' -H "Content-Type: application/json" $discord_webhook_url
    fi 
}

function fn_version() {
    echo "Version: $uasp_version"
}

function fn_uasp_update() {
    get_github_uasp_version=$(curl -s -m 5 https://raw.githubusercontent.com/kennethrisa/uasp/master/uasp_version.json -H 'Content-Type: application/json')
    github_uasp_download_url="https://raw.githubusercontent.com/kennethrisa/uasp/master/src/uasp.sh"
    github_uasp_version=$(echo $get_github_uasp_version | jq -r '.[0].version')
    uasp_filename="uasp.sh"
    if [[ $github_uasp_version > $uasp_version ]]; then
        echo "Downloading new version: $github_uasp_version"
        curl -sSL $github_uasp_download_url --output $tmp_dir/$uasp_filename.tmp
        mv -f $tmp_dir/$uasp_filename.tmp $uasp_filename
        echo "Update done, do ./uasp -v to verify version"
    else
        echo "You are on latest version"
    fi
}

function fn_help() {
    echo "------------------
    Version: $uasp_version
    github: $uasp_github
    Usages:
    --init        | -i - Create config file (config.sh) in current dir.
    --update      | -u - updates plugins.
    --check       | -c - Checks only if a plugins needs update and also notify if enabled.
    --version     | -v - Outputs current version.
    --help        | -h - Help command.
    --uasp-update | -uu - Download latest UASP from github, if version is newer.
------------------"
}

function fn_test_config() {
    # Checks if variable exist and not null in config_file
    if [ -z "$plugins_file" ] || [ -z "$plugins_dir" ] || [ -z "$autoupdate_plugin" ] || [ -z "$plugins_file_tmp" ] || [ -z "$plugins_file_outdated" ]; then
        echo "Missing variable(s) in $config_file, please check file or do ./uasp.sh --init" >&2
        exit 1
    fi

    # Checks if file exist
    if [ -f "$plugins_file" ]; then
        json=$(cat $plugins_file)
        
        # If file is empty
        if [[ -z $(grep '[^[:space:]]' $plugins_file) ]] ; then
            echo "[]" > $plugins_file
        fi
    else 
        echo "[]" > $plugins_file
    fi
}

function fn_download() {
    download_plugin=$(curl -sSL $download_url --output $tmp_dir/$name)
    downloaded_checksum=$(sha1sum $tmp_dir/$name | awk '{print $1}')

    mkdir -p $tmp_dir

    if [ $downloaded_checksum = $checksum ]; then
        json=$(jq --arg downloaded_checksum $downloaded_checksum -e '.['$counterid'].current_checksum = $downloaded_checksum' <<< $json)
        json=$(jq -e '.['$counterid'].is_latest = true' <<< $json)
        echo $json | jq . > $plugins_file_tmp

        # Move plugin from temp
        cp -f $tmp_dir/$name $plugins_dir/$name
        sleep 1
        # Cleanup
        rm -f $tmp_dir/$name

        # Write config file
        if check=$(jq -er '.['$counterid'].current_checksum' $plugins_file_tmp /dev/null); then
            mv $plugins_file_tmp $plugins_file
        else
            echo -e "${red}ERROR Saving config file${reset}"
            echo
        fi 
    fi
}

function fn_plugins() {
    counter=0

    # Run config test
    fn_test_config

    for plugin in $plugins_dir/*.cs; do
        [ -e "$plugin" ] || continue
        name="$(basename -- $plugin)"
        pluginname=${name%.*}
        umod_api="https://umod.org/plugins/$pluginname/latest.json"
        download_url="https://umod.org/plugins/$name"

        json=$(cat $plugins_file)
        jsondata=$(echo $json | jq -r '.[].plugin')

        match=false
        counterid=0

        echo "${yellow}Checking $pluginname... ${reset}"
        # deletes to end of line
        printf "\033[K"
        sleep 5
        # takes cursor one line up
        printf "\033[1A"

        for keys in $jsondata; do
            if [[ $keys == $name ]]; then
                match=true
                is_umod=$(echo $json | jq -r '.['$counterid'].is_umod')

                if [[ $is_umod = true ]]; then

                    getdata=$(curl -s -m 5 $umod_api -H 'Content-Type: application/json')
                    checksum=$(echo $getdata | jq -r '.checksum')
                    current_checksum=$(sha1sum $plugins_dir/$name | awk '{print $1}')
                    autoupdate_plugin=$(echo $json | jq -r '.['$counterid'].autoupdate_plugin')
                    current_version=$(echo $json | jq -r '.['$counterid'].version')
                    updated_at_atom=$(echo $getdata | jq -r .updated_at_atom)
                    version=$(echo $getdata | jq -r .version)

                    if [ $current_checksum != $checksum ]; then
                        echo "${red}$pluginname needs update${reset}"
                        json=$(jq -e '.['$counterid'].is_latest = false' <<< $json)
                        echo $json | jq . > $plugins_file_tmp && mv $plugins_file_tmp $plugins_file
                        echo "---------------------" >> $plugins_file_outdated
                        echo "Plugin:      $pluginname" >> $plugins_file_outdated
                        echo "Old Version: $current_version" >> $plugins_file_outdated
                        echo "New Version: $version" >> $plugins_file_outdated
                        echo "---------------------" >> $plugins_file_outdated

                        fn_alert_info
                        sleep 5
                        is_latest=false

                        if [[ $autoupdate_plugin = true ]] && [[ $update_plugin = true ]]; then
                            fn_download
                        fi
                    else
                        echo "${green}$pluginname is up to date${reset}"
                        sleep 5

                        is_latest=$(echo $getdata | jq -r .is_latest)
                    fi
                    printf "\033[1A"
                    printf "\033[K"

                else
                    echo "${red}Skipping $pluginname - does not exist on Umod${reset}"
                    sleep 5
                    printf "\033[1A"
                    printf "\033[K"
                fi
                break
            fi
            ((counterid++))
        done
        if [[ $match = true ]]; then
            ((counter++))
        else
            json=$(cat $plugins_file)

            response=response.txt
            status=$(curl --head -s -m 5 -o $response -w '%{http_code}' $umod_api)

            if test $status -eq 200; then
                is_umod=true
                # echo "Getting data from API"
                getdata=$(curl -s -m 5 $umod_api -H 'Content-Type: application/json')
                version=$(echo $getdata | jq -r .version)
                checksum=$(echo $getdata | jq -r .checksum)
                updated_at_atom=$(echo $getdata | jq -r .updated_at_atom)

                current_checksum=$(sha1sum $plugins_dir/$name | awk '{print $1}')

                if [ $current_checksum != $checksum ]; then
                    echo "${red}$pluginname needs update${reset}"
                    printf "\033[1A"
                    printf "\033[K"
                    echo "---------------------" >> $plugins_file_outdated
                    echo "Plugin:      $pluginname" >> $plugins_file_outdated
                    echo "New Version: $version" >> $plugins_file_outdated
                    echo "---------------------" >> $plugins_file_outdated
                    is_latest=false
                else
                    is_latest=$(echo $getdata | jq -r .is_latest)
                fi

                json=$(jq --arg name $name --arg is_umod $is_umod --arg autoupdate_plugin $autoupdate_plugin --arg version $version --arg checksum $checksum --arg current_checksum $current_checksum --arg is_latest $is_latest --arg updated_at_atom $updated_at_atom -c '.+ [{"plugin": $name,"autoupdate_plugin": '$autoupdate_plugin',"is_umod": '$is_umod',"version": $version,"checksum": $checksum,"current_checksum": $current_checksum,"is_latest": '$is_latest',"updated_at_atom": $updated_at_atom }]' <<< $json)
                echo $json | jq . > $plugins_file
            else
                is_umod=false
                json=$(jq --arg name $name --arg is_umod $is_umod -c '.+ [{"plugin": $name,"is_umod": '$is_umod' }]' <<< $json)
                echo $json | jq . > $plugins_file
            fi
            # cleanup
            rm -f $response
            ((counter++))
        fi
    done
    # deletes end of line
    printf "\033[K"
    if test -f "$plugins_file_outdated"; then
        cat $plugins_file_outdated
        rm -f $plugins_file_outdated
    fi
    echo "All done"
}

case $1 in
    --init|-i)
        fn_config_init
        ;;
    --uasp-update|-uu)
        fn_uasp_update
        ;;
    --update|-u)
        update_plugin=true
        fn_plugins
        ;;
    --check|-c)
        update_plugin=false
        fn_plugins
        ;;
    --version|-v)
        fn_version
        ;;
    *|--help|-h)
        fn_help
        ;;
esac