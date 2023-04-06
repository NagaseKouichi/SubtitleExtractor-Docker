#!/bin/bash
set -e

USER=dockeruser

echo "---Checking if UID: ${UID} matches user---"
usermod -o -u ${UID} ${USER}
echo "---Checking if GID: ${GID} matches user---"
groupmod -o -g ${GID} ${USER} > /dev/null 2>&1 ||:
usermod -g ${GID} ${USER}
echo "---Setting umask to ${UMASK}---"
umask ${UMASK}

chown -R ${UID}:${GID} /data

extractSubsAndAttachments() {
    file="${1}"
    basename="${1%.*}"
    : ${OUT_EXT:="ass"} #Sets the default value if not specified
    originaldir=$(pwd)

    if [[ ! -z $SUBFOLDER ]]; then
        gosu ${USER} mkdir -p $SUBFOLDER
        cd $SUBFOLDER
    fi

    gosu ${USER} mkdir -p "$basename"
    cd "$basename"

    subsmappings=$(ffprobe -loglevel error -select_streams s -show_entries stream=index,codec_name:stream_tags=language,title -of csv=p=0 "${originaldir}/${file}")
    #Results formatted as : 2,eng,title

    #IFS is the command delimiter - https://bash.cyberciti.biz/guide/$IFS
    #We back it up before changing it to a ',' as used in the mappings
    OLDIFS=$IFS
    IFS=,

    (while read idx codec lang title; do
        if [[ "$codec" == *pgs* ]]; then
            echo "codec $codec, forcing output format."
            EXT="sup"
            forceArgument=("-c:s" "copy" )
        else
            forceArgument=()
            EXT=$OUT_EXT
        fi
        if [ -z "$lang" ]; then
            lang="und"
            #When the subtitle language isn't present in the file, we note it as undefined and extract it regardless of the parameters
        else
            if [[ ! -z "$LANGS" ]] && [[ "$LANGS" != *$lang* ]]; then
                #If subtitles language restrictions were provided, we check that the subtitles lang is one of them before proceeding
                echo "Skipping ${lang} subtitle #${idx}"
                continue
            fi
        fi

        echo "Extracting ${lang} subtitle #${idx} named '$title' to .${EXT}, from ${file}"
        formattedTitle="${title//[^[:alnum:] -]/}" #We format the track title to avoid issues using it in a filename.
        gosu ${USER} ffmpeg -y -nostdin -hide_banner -loglevel error -i \
        "${originaldir}/${file}" -map 0:"$idx" "${forceArgument[@]}" "${formattedTitle}_${idx}_${lang}_${basename}.${EXT}"
        # The -y option replaces existing files.

    done <<<"${subsmappings}")

    echo "Dumping attachments from $file"
    gosu ${USER} ffmpeg -nostdin -hide_banner -loglevel quiet -dump_attachment:t "" -i "${originaldir}/${file}" || true #"One or more attachments could not be extracted."
    # Despite successful extraction, the error "At least one output file must be specified" seems to always appear.
    # The "|| true" part allows us to continue the script regardless.

    #Restore previous values
    IFS=$OLDIFS
    cd $originaldir
}
for f in *.mkv; do
    extractSubsAndAttachments "$f"
done
echo "Finished."
