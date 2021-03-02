#!/bin/bash
# Author: Petr27

# ---------------------------------------------------------------

config_file="/opt/samtvready/samtvready.conf"

# ---------------------------------------------------------------

# check parameters
if [ -z "$1" ]
then
    echo "Output file must be specified."
    exit -1
fi
output_file_arg=$1

find ~+ ! \( -name "*-SamTVReady*" -o -name "*movie-poster*" -o -name "*original-stream-*" -o -name "*.srt" -o -name "*.SRT" -o -name "*.sub" -o -name "*.SUB" -o -name "*.jpg" -o -name "*.JPG" -o -name "*.png" -o -name "*.PNG" -o -name "*.mp3" -o -name "*.MP3" -o -name "*.mka" -o -name "*.MKA" -o -name "*.m3u" -o -name "*.M3U" -o -name "*.pls" -o -name "*.PLS" -o -name "*.gif*" -o -name "*.GIF*" -o -name "*.zip" -o -name "*.ZIP" -o -name "*.rar" -o -name "*.RAR" -o -name "*.txt" -o -name "*.TXT" -o -name "*.nfo" -o -name "*.NFO" -o -name "CFV-*" -o -name ".nomedia" \) -type f > $output_file_arg

exit 0
