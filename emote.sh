#!/bin/bash

set -e

base_url="https://discord.com/api/v8"
dir=$(dirname "$0")
data_file=$dir/emote_data
emote_col=$dir/emotes
thumbnail_path=$emote_col/gif_thumbnails
window_class="Discord"
colon=false
paste_url=false

function show_help () {
    echo "Usage: $(basename "$0") [OPTION...]"
    echo -e "A script to open a discord emote menu\n"
    echo "Options:"
    echo -e "-w, --window-class [class]         Window class to send the emote to. Set to \"Discord\" by default"
    echo -e "-r, --rofi-config  [file]          Specify a custom config file for the rofi menu"
    echo -e "-f, --fetch-emotes [servers]       Download emotes. Optionally specify a server ID list seperated by a space and enclosed in quotes. Example: \"234113424342 092432714749\""
    echo -e "-c, --colon                        Display colon at the beginning and end of emote name."
    echo -e "-h, --help                         Display this help menu\n"
    exit 0
}

function die () {
    echo -e $1
    exit 1
}

function resize () {
    convert -resize "48x48" $1 $1
}


function fetch_data () {
    curl --silent -H "Content-Type: application/json" -H "Authorization: $token" \
        "$base_url$1"
    }

function rm_tr_quotes () {
    echo "$1" | sed -e 's/^"//' -e 's/"$//'
}

function invalid_option () {
    die "Incorrect usage."
}

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -r|--rofi-config)
            [ -z "$2" ] && invalid_option
            rofi_config=$(rm_tr_quotes "$2")
            shift
            shift
            ;;
        -w|--window-class)
            [ -z "$2" ] && invalid_option
            window_class=$(rm_tr_quotes "$2")
            shift
            shift
            ;;
        -f|--fetch-emotes)
            fetch_emotes=true
            if [ ! -z "$2" ]; then
                server_list=$2
                shift
            fi
            shift
            ;;
        -c|--colon)
            colon=true
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *) 
            invalid_option
            ;;
    esac
done

if [ ! -d $emote_col ] && [ -z "$fetch_emotes" ]; then
    die "You do not have any emotes. Run this script with -f to initialize the emote database"
fi

if  [ "$fetch_emotes" = true ]; then
    echo -n "Enter your discord authentication token: "
    read -s token

    if [[ $(fetch_data "/users/@me" | jq '.message') = '"401: Unauthorized"' ]]; then
        die "\nIncorrect token"
    fi

    echo -e "\nStarting to download emotes..."

    mkdir -p $thumbnail_path

    servers=$(fetch_data "/users/@me/guilds" | jq '.[] | .id')

    for id in $servers; do
        id=$(rm_tr_quotes $id)
        if [[ ! -z $server_list && ! " ${server_list[@]} " =~ " ${id} " ]]; then
            continue
        fi
        fetch_data "/guilds/$id/emojis" | jq -c '.[]'|
            while read line; do
                name=$(rm_tr_quotes $(echo $line | jq '.name'))
                emote_id=$(rm_tr_quotes $(echo $line | jq '.id'))
                url="https://cdn.discordapp.com/emojis/$emote_id"

                filetype=$(curl -s -I $url | grep "^content-type: " | awk '{ print $2 }' | sed -e 's/.*\///g' -e 's/\r//g')
                filename=$(echo "emotes/$name.$filetype" | sed 's/\r//g')
                full_fn=$dir/$filename

                if [ ! -f $filename ]; then
                    echo "Downloading $name..."
                    wget -q -O $full_fn "$url?size=48"
                    # create thumbnail to display in rofi
                    # not sure why it wouldn't let me compare filetype
                    [  ${full_fn##*.} = "gif" ] && convert $full_fn -delete 1--1 $thumbnail_path/$name.png
                    [ -s $full_fn ] || rm $full_fn
                    echo "$name $filename 0 $url.$filetype?size=48" >> $data_file
                else
                    echo "Skipping $name..."
                fi
            done
    done

    echo "Done!"
    exit 0
fi

rofi_cmd=(rofi -dmenu -i -p "Emote:" -sort -show-icons)

[ ! -z ${rofi_config+x} ] && rofi_cmd+=(-config "$rofi_config")

selected=$(sort -k 3 -r $data_file | \
    while read entry; do

        origname=$(echo $entry | awk '{print $1}')
        [ "$colon" = true ] && name=":${origname%%.*}:" || name="$origname"

        img=$(echo $entry | awk '{print $2}')
        [ ${img##*.} = "gif" ] && img=emotes/gif_thumbnails/$origname.png

        img=$(realpath $dir/$img)
        url=$(echo $entry | awk '{print $4}')

        if [[ $paste_url = false || $url != "" ]]; then
            echo -e "$name\0icon\x1f$img"
        fi

    done | ${rofi_cmd[@]})

if [ "$selected" ]; then
    [ "$colon" = true ] && selected=$(echo $selected | cut -d ":" -f 2)
    real_fn=$dir/$(grep "^$selected " $data_file | awk '{print $2}')
    url=$(grep "^$selected " $data_file | awk '{print $4}')

    if [ -f "$real_fn" ]; then
        mime_type=$(file -b --mime-type "$real_fn")
        # increments usage counter
        sed -E -i 's/(^'"$selected"') (.*) ([0-9]*) (.*)/echo "\1 \2 $((\3+1)) \4"/ge' $data_file

        echo $url | xclip -se c

        sleep 0.1 # I'm not entirely sure whats happening but sometimes xdotool fails randomly. More at https://github.com/jordansissel/xdotool/issues/60
        WID=$(xdotool search --class --onlyvisible --limit 1 "$window_class")
        if [ "$WID" ]; then
            xdotool windowactivate $WID
            xdotool key ctrl+v
            xdotool key KP_Enter
        else
            die "You do not have discord open"
        fi
    else
        die "Invalid emote name"
    fi
fi
