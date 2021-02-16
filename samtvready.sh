#!/bin/bash
# Author: Petr27

# ---------------------------------------------------------------

config_file="/opt/samtvready/samtvready.conf"

# ---------------------------------------------------------------

# check parameters
if [ -z "$1" ]
then
    echo "Input file must be specified."
    exit -1
fi
input_file_arg=$1

if [ ! -f "$input_file_arg" ]
then
    echo "Not existing file for check / convert: " $input_file_arg
    exit -1
fi

if [ -z "$2" ]
then
    check_only=false
else
    if [ "$2" = "check_only" ]
    then
        check_only=true
    else
        check_only=false
    fi
fi

# ---------------------------------------------------------------

# converted file name suffix
converted_file_name_suffix="-SamTVReady"

# report file location
report_file_location="/opt/samtvready/report"

# working dir
# not empty - location into which source file will be copied or moved, everything will be converted there and as final it will be copied to original dir
#working_dir_location="/opt/samtvready/work"
# empty - work in file directory
working_dir_location=""
# if file size is above this value in bytes, working dir will NOT be ever used
max_file_size_for_using_working_dir=100000000000

# number of ffmpeg threads to use - number - 0 means optimal
ffmpeg_threads=0

# input fileadditional params for ffmpeg
# libx
ffmpeg_input_params="-nostdin -fflags +genpts"
# nvenc
#ffmpeg_input_params="-nostdin -fflags +genpts -hwaccel auto"

# --- VIDEO ---
# video codecs, that we "want support" - can be more (for more details use: ffmpeg -codecs)
supported_video_codecs="hevc,h264,av1" 
# constants - configuration "remove" / "convert" / "copy" (default if nothing or bad value) / "report"
unsupported_video="convert"
# conversion params for ffmpeg
# libx
unsupported_video_480p_params="-preset slow -vcodec libx264 -cq 19 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"
unsupported_video_576p_params="-preset slow -vcodec libx264 -cq 20 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"
unsupported_video_720p_params="-preset slow -vcodec libx264 -cq 21 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"
unsupported_video_1080p_params="-preset slow -vcodec libx265 -cq 22 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"
unsupported_video_2160p_params="-preset slow -vcodec libx265 -cq 24 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"
# nvenc
#unsupported_video_480p_params="-preset slow -vcodec h264_nvenc -cq 19 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"
#unsupported_video_576p_params="-preset slow -vcodec h264_nvenc -cq 20 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"
#unsupported_video_720p_params="-preset slow -vcodec h264_nvenc -cq 21 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"
#unsupported_video_1080p_params="-preset slow -vcodec hevc_nvenc -cq 22 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"
#unsupported_video_2160p_params="-preset slow -vcodec hevc_nvenc -cq 24 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"

# --- AUDIO ---
# audio codecs, that we "want support" - can be more (for more details use: ffmpeg -codecs)
supported_audio_codecs="aac,aac_latm,ac3,eac3"
# constants - configuration "remove" / "convert" / "copy" (default if nothing or bad value) / "report"
unsupported_audio="convert"
# conversion params for ffmpeg
unsupported_audio_lq_acodec="-acodec aac -b:a 192k"
unsupported_audio_hq_acodec="-acodec eac3 -b:a 1536k"

# --- SUBTITLE ---
# subtitle codecs, that we "want support" - can be more (for more details use: ffmpeg -codecs)
supported_subtitles_codecs="subrip,srt,ass,ssa"
# constants - configuration "remove" / "convert" / "copy" (default if nothing or bad value) / "report"
unsupported_subtitles="remove"
# conversion params for ffmpeg
unsupported_subtitles_conversion_params=""

# keep original file?
keep_original_file=true

# save original streams into defined dir?
save_original_streams=true
original_streams_dir="0-original-streams"

# clean temp files (delete help files)
clean_temp_files=true

# loglevel "TRACE", "DEBUG", "INFO", "WARNING", "ERROR", "HIGHEST"
loglevel="TRACE"

# logstyle "BFU" / "DEVEL"
logstyle="DEVEL"

. $config_file

basename=$(basename -- "$input_file_arg")
input_file_extension="${basename##*.}"
input_file_name="${basename%.*}"
input_file="$input_file_name.$input_file_extension"
input_file_size=$(wc -c "$input_file_arg" | awk '{print $1}')

# check if file is not converted yet
if [[ "$input_file_name" = *"$converted_file_name_suffix" ]]
then
    echo "File has been already converted: " $input_file
    exit -1
fi

input_dirname=$(dirname -- "$input_file_arg")
if [ "$input_dirname" = "." ]
then
    input_dirname="$PWD"
fi
start_dirname="$PWD"

# ---------------------------------------------------------------

# function for logging
myLog () {
    local myLogFirst=true
    local myLogMessage=""
    for myLogVar in "$@"
    do
        if [ "$myLogFirst" = true ]
        then
            myLogFirst=false
        else
            myLogMessage+=" $myLogVar"
        fi
    done

    local messageLogLevelStr=$1
    resolveLogLevel $loglevel;definedLogLevel=$?
    resolveLogLevel $messageLogLevelStr;messageLogLevel=$?

    if [ $messageLogLevel -ge $definedLogLevel ]
    then
        if [ "$logstyle" != "DEVEL" ]
        then
            echo $myLogMessage
        else
            dateTime=`date +"%Y-%m-%d %H:%M:%S.%N"`
            echo $dateTime $messageLogLevelStr $myLogMessage
        fi
    fi
}

# function for resolve log level
resolveLogLevel() {
    local locaLogLevel=$1

    if [ "$locaLogLevel" = "HIGHEST" ]
    then
        return 100
    fi
    if [ "$locaLogLevel" = "ERROR" ]
    then
        return 90
    fi
    if [ "$locaLogLevel" = "WARNING" ]
    then
        return 70
    fi
    if [ "$locaLogLevel" = "INFO" ]
    then
        return 50
    fi
    if [ "$locaLogLevel" = "DEBUG" ]
    then
        return 30
    fi
    if [ "$locaLogLevel" = "TRACE" ]
    then
        return 10
    fi

    return 0
}

# helper functions for split string to array
function mfcb() {
    local val="$4"
    "$1"
    eval "$2[$3]=\$val;"
}

function valLeftTrim() {
    if [[ "$val" =~ ^[[:space:]]+ ]]
    then
        val="${val:${#BASH_REMATCH[0]}}"
    fi
}

function valRightTrim() {
    if [[ "$val" =~ [[:space:]]+$ ]]
    then
        val="${val:0:${#val}-${#BASH_REMATCH[0]}}"
    fi
}

function val_trim() {
    valLeftTrim
    valRightTrim
}

function readArrayFromString() {
    readarray -c1 -C 'mfcb val_trim "$1"' -td, <<<"$2,"
    eval `echo "unset '$1[-1]'"`
    declare -a $1
}

# read common information about track

function readCommonTrackInfo() {
    # default flag
    cmd="ffprobe -v quiet -select_streams ${indexes_a[$stream_counter]} -show_entries stream_disposition=default -of csv=s=,:p=0 $input_file"
    myLog "DEBUG" "CMD: $cmd"
    local default=`eval $cmd;result=$?`
    myLog "DEBUG" "CMD RESULT: $result"
    if [ "$default" = "1" ]
    then
        default_flags_a[$stream_counter]=true
    else
        default_flags_a[$stream_counter]=false
    fi
    myLog "DEBUG" "Track default flag: ${default_flags_a[$stream_counter]}"

    # forced flag
    cmd="ffprobe -v quiet -select_streams ${indexes_a[$stream_counter]} -show_entries stream_disposition=forced -of csv=s=,:p=0 $input_file"
    myLog "DEBUG" "CMD: $cmd"
    local forced=`eval $cmd;result=$?`
    myLog "DEBUG" "CMD RESULT: $result"
    if [ "$forced" = "1" ]
    then
        forced_flags_a[$stream_counter]=true
    else
        forced_flags_a[$stream_counter]=false
    fi
    myLog "DEBUG" "Track forced flag: ${forced_flags_a[$stream_counter]}"

    # title
    cmd="ffprobe -v quiet -select_streams ${indexes_a[$stream_counter]} -show_entries stream_tags=title -of csv=s=,:p=0 $input_file"
    myLog "DEBUG" "CMD: $cmd"
    local title=`eval $cmd;result=$?`
    myLog "DEBUG" "CMD RESULT: $result"
      titles_a[$stream_counter]=$title
    myLog "DEBUG" "Track title: ${titles_a[$stream_counter]}"

    # language
    cmd="ffprobe -v quiet -select_streams ${indexes_a[$stream_counter]} -show_entries stream_tags=language -of csv=s=,:p=0 $input_file"
    myLog "DEBUG" "CMD: $cmd"
    language=`eval $cmd;result=$?`
    myLog "DEBUG" "CMD RESULT: $result"
    if [ -z "$language" ]
    then
        languages_a[$stream_counter]="und"
    else
        languages_a[$stream_counter]=$language
    fi
    myLog "DEBUG" "Track language: ${languages_a[$stream_counter]}"

    # codec type
    cmd="ffprobe -v quiet -select_streams ${indexes_a[$stream_counter]} -show_entries stream=codec_name -of csv=s=,:p=0 $input_file"
    myLog "DEBUG" "CMD: $cmd"
    local codec=`eval $cmd;result=$?`
    myLog "DEBUG" "CMD RESULT: $result"
    codecs_a[$stream_counter]=$codec
    myLog "DEBUG" "Track codec: ${codecs_a[$stream_counter]}"
}

# read video information about track

function readVideoTrackInfo() {
    # video height
    cmd="ffprobe -v quiet -select_streams ${indexes_a[$stream_counter]} -show_entries stream=height -of csv=s=,:p=0 $input_file"
    myLog "DEBUG" "CMD: $cmd"
    local height=`eval $cmd;result=$?`
    myLog "DEBUG" "CMD RESULT: $result"
    heights_a[$stream_counter]=$height
    myLog "DEBUG" "Track video height: ${heights_a[$stream_counter]}"

    # video width
    cmd="ffprobe -v quiet -select_streams ${indexes_a[$stream_counter]} -show_entries stream=width -of csv=s=,:p=0 $input_file"
    myLog "DEBUG" "CMD: $cmd"
    local width=`eval $cmd;result=$?`
    myLog "DEBUG" "CMD RESULT: $result"
    widths_a[$stream_counter]=$width
    myLog "DEBUG" "Track video width: ${widths_a[$stream_counter]}"

    # interlaced
    cmd="ffprobe -v quiet -select_streams ${indexes_a[$stream_counter]} -show_entries stream=field_order -of csv=s=,:p=0 $input_file"
    myLog "DEBUG" "CMD: $cmd"
    local field_order=`eval $cmd;result=$?`
    myLog "DEBUG" "CMD RESULT: $result"
    if [ "$field_order" = "tb" ] || [ "$field_order" = "tt" ] || [ "$field_order" = "bt" ] 
    then
        interlaced_flags_a[$stream_counter]=true
    else
        interlaced_flags_a[$stream_counter]=false
    fi
    myLog "DEBUG" "Track interlaced flag: ${interlaced_flags_a[$stream_counter]}"

    # pixel format
    cmd="ffprobe -v quiet -select_streams ${indexes_a[$stream_counter]} -show_entries stream=pix_fmt -of csv=s=,:p=0 $input_file"
    myLog "DEBUG" "CMD: $cmd"
    local pixel_format=`eval $cmd;result=$?`
    myLog "DEBUG" "CMD RESULT: $result"
    pixel_formats_a[$stream_counter]=$pixel_format
    myLog "DEBUG" "Track pixel format: ${pixel_formats_a[$stream_counter]}"
}

# read video information about track

function readAudioTrackInfo() {
    # number of channels format
    cmd="ffprobe -v quiet -select_streams ${indexes_a[$stream_counter]} -show_entries stream=channels -of csv=s=,:p=0 $input_file"
    myLog "DEBUG" "CMD: $cmd"
    local channels=`eval $cmd;result=$?`
    myLog "DEBUG" "CMD RESULT: $result"
    channels_a[$stream_counter]=$channels
    myLog "DEBUG" "Track channels no.: ${channels_a[$stream_counter]}"
}


# is given codec supported
function isVideoCodecSupported() {

    for spc in "${supported_video_codecs_a[@]}"
    do
        if [[ "$spc" = *"$1"* ]]
        then
            return 1
        fi
    done
 
    return 0
}

# is given audio supported
function isAudioCodecSupported() {

    for spc in "${supported_audio_codecs_a[@]}"
    do
        if [[ "$spc" = *"$1"* ]]
        then
            return 1
        fi
    done
 
    return 0
}

# is given subtitle supported
function isSubtitlesCodecSupported() {

    for spc in "${supported_subtitles_codecs_a[@]}"
    do
        if [[ "$spc" = *"$1"* ]]
        then
            return 1
        fi
    done
 
    return 0
}

# ---------------------------------------------------------------

# starting
myLog "HIGHEST" "Samsung TV 2018+ conversion / check started..."

useWorkingDirectory=false
if [ -d "$working_dir_location" ] 
then
    if [ $input_file_size -le $max_file_size_for_using_working_dir ]
    then
        useWorkingDirectory=true
    else
        myLog "WARNING" "File is too big for using working directory. It will be converted in original destination."
        useWorkingDirectory=false
    fi
fi
myLog "TRACE" "Use working direcotry: " $useWorkingDirectory

working_dirname="."
if [ "$check_only" = true ]
then
    myLog "HIGHEST" "Checking $input_file."
    myLog "INFO" "Changing directory to: " $input_dirname
    eval "cd '$input_dirname'"
else
    myLog "HIGHEST" "Converting $input_file."
    if [ "$useWorkingDirectory" = true ]
    then
        working_dirname=$working_dir_location
        cmd="cd '$working_dirname'"
        myLog "DEBUG" "CMD: $cmd"
        eval $cmd;result=$?
        if [ "$keep_original_file" = true ]
        then
            cmd="cp '$input_dirname/$input_file' '$working_dirname/$input_file'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
        else
            cmd="mv '$input_dirname/$input_file' '$working_dirname/$input_file'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
        fi
    else
        working_dirname=$input_dirname
        cmd="cd '$working_dirname'"
        myLog "DEBUG" "CMD: $cmd"
        eval $cmd;result=$?
    fi
fi
myLog "TRACE" "Working dir name:" $working_dirname

# main arrays
declare -a indexes_a
declare -a codecs_a
declare -a languages
declare -a default_flags_a
declare -a forced_flags_a
declare -a titles_a
declare -a heights_a
declare -a widths_a
declare -a interlaced_flags_a
declare -a pixel_formats_a
declare -a channels_a

declare -a fmux_inputs_a
declare -a fmux_tracks_a
declare -a fmux_track_languages_a
declare -a fmux_track_forced_flags_a
declare -a fmux_track_default_flags_a
declare -a fmux_track_titles_a
declare -a fmux_not_copy_videos_a
declare -a fmux_not_copy_audios_a
declare -a fmux_not_copy_subtitles_a

declare -a files_with_original_streams_a
declare -a files_with_temp_data_a

readArrayFromString "supported_video_codecs_a" $supported_video_codecs 
readArrayFromString "supported_audio_codecs_a" $supported_audio_codecs
readArrayFromString "supported_subtitles_codecs_a" $supported_subtitles_codecs

actual_date_str=`date +"%Y-%m-%d"`
report_file_name="$report_file_location/samtvready-$actual_date_str-report.csv"

# input file is first file in inputs
fmux_inputs_a+=("'$input_file'")

# title
cmd="ffprobe -v quiet -show_entries format_tags=title -of csv=s=,:p=0 -i '$input_file'"
myLog "DEBUG" "CMD: $cmd"
main_title=`eval $cmd`
if [ -z "$main_title" ]
then
    main_title=$input_file_name
fi
myLog "TRACE" "Main title: $main_title"

# container type
cmd="ffprobe -v quiet -show_entries format=format_name -of csv=s=,:p=0 -i '$input_file'"
myLog "DEBUG" "CMD: $cmd"
container_type=`eval $cmd`
if [ -z "$container_type" ]
then
    container_type="unknown"
fi
myLog "TRACE" "Container type: $containlanguageser_type"

is_matroska=false
if [[ $container_type = *"matroska"* ]]
then
    is_matroska=true
fi
myLog "TRACE" "Is matroska file: $is_matroska"

if [ ! -f "$report_file_name" ]
then
    touch $report_file_name
fi
myLog "TRACE" "Report file name: " $report_file_name

# help file names
streams_output=streams_output.txt
video_streams_output=video_streams_output.txt
audio_streams_output=audio_streams_output.txt
subtitle_streams_output=subtitle_streams_output.txt
# will be deleted :-)?
files_with_temp_data_a+=($streams_output $video_streams_output $audio_streams_output $subtitle_streams_output)

# converted file
converted_file="$input_file_name$converted_file_name_suffix.mkv"
converted_srtfile="$input_file_name$converted_file_name_suffix.srt"

# prepare help files
cmd="ffprobe -v quiet -show_entries stream=index,codec_type -of csv=s=,:p=0 '$input_file' > '$streams_output'"
myLog "DEBUG" "CMD: $cmd"
eval $cmd;result=$?
myLog "DEBUG" "CMD RESULT: $result"

cmd="grep 'video' '$streams_output' > '$video_streams_output'"
myLog "DEBUG" "CMD: $cmd"
eval $cmd;result=$?
myLog "DEBUG" "CMD RESULT: $result"

cmd="grep 'audio' '$streams_output' > '$audio_streams_output'"
myLog "DEBUG" "CMD: $cmd"
eval $cmd;result=$?
myLog "DEBUG" "CMD RESULT: $result"

cmd="grep 'subtitle' '$streams_output' > '$subtitle_streams_output'"
myLog "DEBUG" "CMD: $cmd"
eval $cmd;result=$?
myLog "DEBUG" "CMD RESULT: $result"

# counters
stream_counter=$((0))
input_counter=$((0))

# booleans for valid video file
at_least_one_video=false
at_least_one_audio=false

# ---------------------------------------------------------------

# read info about track and find default track for video
exists_default_video_track=false
while read line; do
    # streams position in original
    indexes_a[$stream_counter]=`echo $line | awk 'BEGIN { FS="," } { print $1 }'`
    # codec, flags, title, language etc.
    readCommonTrackInfo
    
    if [ "${default_flags_a[$stream_counter]}" = true ]
    then
        exists_default_video_track=true
    fi 

    # append +1 to stream counter
    stream_counter=$(($stream_counter + 1))
    
done < $video_streams_output

# reset counter
stream_counter=$((0))

# prepare video streams
first=true
default=false
while read line; do

    # prepare default
    if [ "$exists_default_video_track" = true ]
    then
        default="${default_flags_a[$stream_counter]}"
    else
        if [ "$first" = true ]
        then
            default=true
            default_flags_a[$stream_counter]=true
        else
            default=false
        fi
    fi        
    first=false
    myLog "TRACE" "Default video track: " $default

    # is actual codec supported?
    isVideoCodecSupported ${codecs_a[$stream_counter]};videoCodecSupported=$?
    if [ "$videoCodecSupported" -eq 0 ]
    then
        myLog "INFO" "NOT supported VIDEO codec. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]}."
        
        # read additional info about video
        readVideoTrackInfo
        if [ "$unsupported_video" = "report" ]
        then
            echo "VIDEO,$input_dirname,$input_file,${codecs_a[$stream_counter]},${indexes_a[$stream_counter]}" >> $report_file_name
        fi

        if [ "$check_only" = false ] && ([ "$unsupported_video" = "remove" ] || [ "$unsupported_video" = "convert" ])
        then
            # do not copy from original file
            fmux_not_copy_videos_a+=(${indexes_a[$stream_counter]})
            
            # prepare extract original stream
            original_stream_name="$input_file_name-original-${codecs_a[$stream_counter]}-${languages_a[$stream_counter]}-${indexes_a[$stream_counter]}"
            original_stream_file_name="$original_stream_name.mkv"
            original_stream_file_name_converted="$original_stream_name-converted.mkv"

            # extract orginal stream
            can_convert=true
            if [ "$is_matroska" = true ]
            then
                myLog "INFO" "Extracting (mkvextract) original VIDEO. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]} ... ... ..."
                cmd="mkvextract '$input_file' tracks ${indexes_a[$stream_counter]}:'$original_stream_file_name'"
                myLog "DEBUG" "CMD: $cmd"
                eval $cmd;result=$?
                myLog "DEBUG" "CMD RESULT: $result"
            fi

            if [ "$is_matroska" != true ] || [ $result != 0 ]
            then
                myLog "INFO" "Extracting (ffmpeg) original VIDEO. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]} ... ... ..."
                cmd="ffmpeg -y -loglevel error -hide_banner -nostats $ffmpeg_input_params -i '$input_file' -threads $ffmpeg_threads -map 0:${indexes_a[$stream_counter]} -vcodec copy -map_metadata -1 -f matroska '$original_stream_file_name'"
                myLog "DEBUG" "CMD: $cmd"
                eval $cmd;result=$?
                myLog "DEBUG" "CMD RESULT: $result"
                if [ $result = 0 ]
                then
                    files_with_original_streams_a+=($original_stream_file_name)
                else
                    myLog "ERROR" "Extracting not successful. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]}."
                    can_convert=false
                fi
            else
                files_with_original_streams_a+=($original_stream_file_name)
            fi

            # convert only default and only if there is something to convert
            if [ "$default" = true ] && [ "$can_convert" = true ]
            then
                # convert if want to convert
                if [ "$unsupported_video" = "convert" ]
                then
                    # start at highest resolution
                    unsupported_video_vcodec_params="$unsupported_video_2160p_params"
                    
                    myLog "TRACE" "Video height: " ${heights_a[$stream_counter]}  
                    myLog "TRACE" "Video width: " ${widths_a[$stream_counter]}
                    
                    if [ "${widths_a[$stream_counter]}" -le 1920 ] || [ "${heights_a[$stream_counter]}" -le 1080 ]
                    then
                        unsupported_video_vcodec_params="$unsupported_video_1080p_params"
                    fi
                    
                    if [ "${widths_a[$stream_counter]}" -le 1280 ] || [ "${heights_a[$stream_counter]}" -le 720 ]
                    then
                        unsupported_video_vcodec_params="$unsupported_video_720p_params"
                    fi
                    
                    if [ "${widths_a[$stream_counter]}" -le 1024 ] || [ "${heights_a[$stream_counter]}" -le 576 ]
                    then
                        unsupported_video_vcodec_params="$unsupported_video_576p_params"
                    fi
                    
                    if [ "${widths_a[$stream_counter]}" -le 480 ] || [ "${heights_a[$stream_counter]}" -le 854 ]
                    then
                        unsupported_video_vcodec_params="$unsupported_video_480p_params"
                    fi

                    myLog "TRACE" "Video interlaced: " ${interlaced_flags_a[$stream_counter]}
                    if [ "${interlaced_flags_a[$stream_counter]}" = true ]
                    then
                        unsupported_video_vcodec_params="$unsupported_video_480p_params -vf yadif"
                    fi

                    # convert original stream into supported codec
                    myLog "INFO" "Converting NOT supported VIDEO. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]} ... ... ..."
                    cmd="ffmpeg -y -loglevel error -hide_banner -nostats $ffmpeg_input_params -i '$original_stream_file_name' -threads $ffmpeg_threads -map 0 -map_metadata -1 $unsupported_video_vcodec_params '$original_stream_file_name_converted'"
                    myLog "DEBUG" "CMD: $cmd"
                    eval $cmd;result=$?
                    myLog "DEBUG" "CMD RESULT: $result"
                    if [ $result = 0 ]
                    then
                        files_with_temp_data_a+=($original_stream_file_name_converted)
                        # prepare for final output
                        input_counter=$(($input_counter + 1))
                        myLog "TRACE" "Input counter: $input_counter"
                        mux_input="-T -A -S -B -M --no-global-tags --no-chapters -d '0' '$original_stream_file_name_converted'"

                        myLog "TRACE" "Final mux input before: " ${fmux_inputs_a[@]}
                        fmux_inputs_a+=("$mux_input")
                        myLog "TRACE" "Final mux input after: " ${fmux_inputs_a[@]}

                        myLog "TRACE" "Final mux tracks before: " ${fmux_tracks_a[@]}
                        fmux_tracks_a+=("$input_counter:0")
                        myLog "TRACE" "Final mux tracks after: " ${fmux_tracks_a[@]}

                        myLog "TRACE" "Languages before: " ${fmux_track_languages_a[$input_counter]}
                        fmux_track_languages_a[$input_counter]=${fmux_track_languages_a[$input_counter]}"--language '0:${languages_a[$stream_counter]}' "
                        myLog "TRACE" "Languages after: " ${fmux_track_languages_a[$input_counter]}

                        myLog "TRACE" "Forced before: " ${fmux_track_forced_flags_a[$input_counter]}
                        fmux_track_forced_flags_a[$input_counter]=${fmux_track_forced_flags_a[$input_counter]}"--forced-track '0:${forced_flags_a[$stream_counter]}' "
                        myLog "TRACE" "Forced after: " ${fmux_track_forced_flags_a[$input_counter]}

                        myLog "TRACE" "Default before: " ${fmux_track_default_flags_a[$input_counter]}
                        fmux_track_default_flags_a[$input_counter]=${fmux_track_default_flags_a[$input_counter]}"--default-track '0:${default_flags_a[$stream_counter]}' "
                        myLog "TRACE" "Default after: " ${fmux_track_default_flags_a[$input_counter]}

                        myLog "TRACE" "Titles before: " ${fmux_track_titles_a[$input_counter]}
                        fmux_track_titles_a[$input_counter]=${fmux_track_titles_a[$input_counter]}"--track-name '0:${titles_a[$stream_counter]}' "
                        myLog "TRACE" "Titles after: " ${fmux_track_titles_a[$input_counter]}
                        
                        at_least_one_video=true
                    else
                        myLog "ERROR" "Conversion not successful. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]}."
                    fi
                fi
            fi
        fi
    else
        # prepare for final output
        if [ "$check_only" = false ]
        then
            myLog "TRACE" "Final mux tracks before: " ${fmux_tracks_a[@]}
            fmux_tracks_a+=("0:${indexes_a[$stream_counter]}")
            myLog "TRACE" "Final mux tracks after: " ${fmux_tracks_a[@]}
    
            myLog "TRACE" "Languages before: " ${fmux_track_languages_a[0]}
            fmux_track_languages_a[0]=${fmux_track_languages_a[0]}"--language '${indexes_a[$stream_counter]}:${languages_a[$stream_counter]}' "
            myLog "TRACE" "Languages after: " ${fmux_track_languages_a[0]}
    
            myLog "TRACE" "Forced before: " ${fmux_track_forced_flags_a[0]}
            fmux_track_forced_flags_a[0]=${fmux_track_forced_flags_a[0]}"--forced-track '${indexes_a[$stream_counter]}:${forced_flags_a[$stream_counter]}' "
            myLog "TRACE" "Forced after: " ${fmux_track_forced_flags_a[0]}

            myLog "TRACE" "Default before: " ${fmux_track_default_flags_a[0]}
            fmux_track_default_flags_a[$input_counter]=${fmux_track_default_flags_a[0]}"--default-track '${indexes_a[$stream_counter]}:${default_flags_a[$stream_counter]}' "
            myLog "TRACE" "Default after: " ${fmux_track_default_flags_a[0]}

            myLog "TRACE" "Titles before: " ${fmux_track_titles_a[0]}
            fmux_track_titles_a[$input_counter]=${fmux_track_titles_a[0]}"--track-name '${indexes_a[$stream_counter]}:${titles_a[$stream_counter]}' "
            myLog "TRACE" "Titles after: " ${fmux_track_titles_a[0]}
            
            at_least_one_video=true
        fi
    fi

    # append +1 to stream counter
    stream_counter=$(($stream_counter + 1))

done < $video_streams_output

myLog "TRACE" "At least one video track: " $at_least_one_video 
 
# ---------------------------------------------------------------

# prepare audio streams
while read line; do
    # streams position in original
    indexes_a[$stream_counter]=`echo $line | awk 'BEGIN { FS="," } { print $1 }'`
    # codec, flags, title, language etc.
    readCommonTrackInfo

    # is actual codec supported?
    isAudioCodecSupported ${codecs_a[$stream_counter]};audioCodecSupported=$?
    if [ "$audioCodecSupported" -eq 0 ]
    then
        myLog "INFO" "NOT supported AUDIO codec. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]}."

        # read additional info about audio
        readAudioTrackInfo
        if [ "$unsupported_audio" = "report" ]
        then
            echo "AUDIO,$input_dirname,$input_file,${codecs_a[$stream_counter]},${indexes_a[$stream_counter]}" >> $report_file_name
        fi

        # convert?
        if [ "$check_only" = false ] && ([ "$unsupported_audio" = "remove" ] || [ "$unsupported_audio" = "convert" ])
        then
            fmux_not_copy_audios_a+=(${indexes_a[$stream_counter]})
            
            # prepare extract original stream
            original_stream_name="$input_file_name-original-${codecs_a[$stream_counter]}-${languages_a[$stream_counter]}-${indexes_a[$stream_counter]}"
            original_stream_file_name="$original_stream_name.mka"
            original_stream_file_name_converted="$original_stream_name-converted.mka"

            # extract orginal stream
            can_convert=true
            if [ "$is_matroska" = true ]
            then
                myLog "INFO" "Extracting (mkvextract) original AUDIO. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]} ... ... ..."
                cmd="mkvextract '$input_file' tracks ${indexes_a[$stream_counter]}:'$original_stream_file_name'"
                myLog "DEBUG" "CMD: $cmd"
                eval $cmd;result=$?
                myLog "DEBUG" "CMD RESULT: $result"
            fi

            if [ "$is_matroska" != true ] || [ $result != 0 ]
            then
                myLog "INFO" "Extracting (ffmpeg) original AUDIO. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]} ... ... ..."
                cmd="ffmpeg -y -loglevel error -hide_banner -nostats $ffmpeg_input_params -i '$input_file' -threads $ffmpeg_threads -map 0:${indexes_a[$stream_counter]} -acodec copy -map_metadata -1 -f matroska '$original_stream_file_name'"
                myLog "DEBUG" "CMD: $cmd"
                eval $cmd;result=$?
                myLog "DEBUG" "CMD RESULT: $result"
                if [ $result = 0 ]
                then
                    files_with_original_streams_a+=($original_stream_file_name)
                else
                    myLog "ERROR" "Extracting not successful. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]}."
                    can_convert=false
                fi
            else
                files_with_original_streams_a+=($original_stream_file_name)
            fi

            # convert only if there is something to convert
            if [ "$can_convert" = true ]
            then
                # convert if want to convert
                if [ "$unsupported_audio" = "convert" ]
                then
                    # start at highest resolution
                    unsupported_audio_acodec_params="$unsupported_audio_hq_acodec"
                    
                    myLog "TRACE" "Audio channels: " ${channels_a[$stream_counter]}  
                    
                    if [ "${channels_a[$stream_counter]}" -gt 6 ]
                    then
                        unsupported_audio_acodec_params="$unsupported_audio_hq_acodec -ac 6"
                    fi

                    if [ "${channels_a[$stream_counter]}" -le 2 ]
                    then
                        unsupported_audio_acodec_params="$unsupported_audio_lq_acodec"
                    fi

                    # convert original stream into supported codec
                    myLog "INFO" "Converting NOT supported AUDIO. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]} ... ... ..."
                    cmd="ffmpeg -y -loglevel error -hide_banner -nostats $ffmpeg_input_params -i '$original_stream_file_name' -threads $ffmpeg_threads -map 0 -map_metadata -1 $unsupported_audio_acodec_params '$original_stream_file_name_converted'"
                    myLog "DEBUG" "CMD: $cmd"
                    eval $cmd;result=$?
                    myLog "DEBUG" "CMD RESULT: $result"
                    if [ $result = 0 ]
                    then
                        files_with_temp_data_a+=($original_stream_file_name_converted)
                        # prepare for final output
                        input_counter=$(($input_counter + 1))
                        myLog "TRACE" "Input counter: $input_counter"
                        mux_input="-T -D -S -B -M --no-global-tags --no-chapters -a '0' '$original_stream_file_name_converted'"

                        myLog "TRACE" "Final mux input before: " ${fmux_inputs_a[@]}
                        fmux_inputs_a+=("$mux_input")
                        myLog "TRACE" "Final mux input after: " ${fmux_inputs_a[@]}

                        myLog "TRACE" "Final mux tracks before: " ${fmux_tracks_a[@]}
                        fmux_tracks_a+=("$input_counter:0")
                        myLog "TRACE" "Final mux tracks after: " ${fmux_tracks_a[@]}

                        myLog "TRACE" "Languages before: " ${fmux_track_languages_a[$input_counter]}
                        fmux_track_languages_a[$input_counter]=${fmux_track_languages_a[$input_counter]}"--language '0:${languages_a[$stream_counter]}' "
                        myLog "TRACE" "Languages after: " ${fmux_track_languages_a[$input_counter]}

                        myLog "TRACE" "Forced before: " ${fmux_track_forced_flags_a[$input_counter]}
                        fmux_track_forced_flags_a[$input_counter]=${fmux_track_forced_flags_a[$input_counter]}"--forced-track '0:${forced_flags_a[$stream_counter]}' "
                        myLog "TRACE" "Forced after: " ${fmux_track_forced_flags_a[$input_counter]}

                        myLog "TRACE" "Default before: " ${fmux_track_default_flags_a[$input_counter]}
                        fmux_track_default_flags_a[$input_counter]=${fmux_track_default_flags_a[$input_counter]}"--default-track '0:${default_flags_a[$stream_counter]}' "
                        myLog "TRACE" "Default after: " ${fmux_track_default_flags_a[$input_counter]}

                        myLog "TRACE" "Titles before: " ${fmux_track_titles_a[$input_counter]}
                        fmux_track_titles_a[$input_counter]=${fmux_track_titles_a[$input_counter]}"--track-name '0:${titles_a[$stream_counter]}' "
                        myLog "TRACE" "Titles after: " ${fmux_track_titles_a[$input_counter]}
                        
                        at_least_one_audio=true
                    else
                        myLog "ERROR" "Conversion not successful. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]}."
                    fi
                fi
            fi
        fi
    else
        # prepare for final output
        if [ "$check_only" = false ]
        then
            myLog "TRACE" "Final mux tracks before: " ${fmux_tracks_a[@]}
            fmux_tracks_a+=("0:${indexes_a[$stream_counter]}")
            myLog "TRACE" "Final mux tracks after: " ${fmux_tracks_a[@]}

            myLog "TRACE" "Languages before: " ${fmux_track_languages_a[0]}
            fmux_track_languages_a[0]=${fmux_track_languages_a[0]}"--language '${indexes_a[$stream_counter]}:${languages_a[$stream_counter]}' "
            myLog "TRACE" "Languages after: " ${fmux_track_languages_a[0]}

            myLog "TRACE" "Forced before: " ${fmux_track_forced_flags_a[0]}
            fmux_track_forced_flags_a[0]=${fmux_track_forced_flags_a[0]}"--forced-track '${indexes_a[$stream_counter]}:${forced_flags_a[$stream_counter]}' "
            myLog "TRACE" "Forced after: " ${fmux_track_forced_flags_a[0]}

            myLog "TRACE" "Default before: " ${fmux_track_default_flags_a[0]}
            fmux_track_default_flags_a[$input_counter]=${fmux_track_default_flags_a[0]}"--default-track '${indexes_a[$stream_counter]}:${default_flags_a[$stream_counter]}' "
            myLog "TRACE" "Default after: " ${fmux_track_default_flags_a[0]}

            myLog "TRACE" "Titles before: " ${fmux_track_titles_a[0]}
            fmux_track_titles_a[$input_counter]=${fmux_track_titles_a[0]}"--track-name '${indexes_a[$stream_counter]}:${titles_a[$stream_counter]}' "
            myLog "TRACE" "Titles after: " ${fmux_track_titles_a[0]}
            
            at_least_one_audio=true
        fi
    fi

    # append +1 to stream counter
    stream_counter=$(($stream_counter + 1))

done < "$audio_streams_output"

myLog "TRACE" "At least one audio track: " $at_least_one_audio

# ---------------------------------------------------------------

# prepare subtitle streams
while read line; do
    # streams position in original
    indexes_a[$stream_counter]=`echo $line | awk 'BEGIN { FS="," } { print $1 }'`
    # codec, flags, title, language etc.
    readCommonTrackInfo

    # is actual codec supported?
    isSubtitlesCodecSupported ${codecs_a[$stream_counter]};subtitlesCodecSupported=$?
    if [ "$subtitlesCodecSupported" -eq 0 ]
    then
        myLog "INFO" "NOT supported SUBTITLE codec. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]}."
        
        # read additional info about audio
        if [ "$unsupported_subtitles" = "report" ]
        then
            echo "SUBTITLES,$input_dirname,$input_file,${codecs_a[$stream_counter]},${indexes_a[$stream_counter]}" >> $report_file_name
        fi

        # convert?
        if [ "$check_only" = false ] && ([ "$unsupported_subtitles" = "remove" ] || [ "$unsupported_subtitles" = "convert" ])
        then
            fmux_not_copy_subtitles_a+=(${indexes_a[$stream_counter]})
            
            # prepare extract original stream
            original_stream_name="$input_file_name-original-${codecs_a[$stream_counter]}-${languages_a[$stream_counter]}-${indexes_a[$stream_counter]}"
            original_stream_file_name="$original_stream_name.sup"
            original_stream_file_name_converted="$original_stream_name-converted.sup"

            # extract orginal stream
            can_convert=true
            if [ "$is_matroska" = true ]
            then
                myLog "INFO" "Extracting (mkvextract) original SUBTITLES. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]} ... ... ..."
                cmd="mkvextract '$input_file' tracks ${indexes_a[$stream_counter]}:'$original_stream_file_name'"
                myLog "DEBUG" "CMD: $cmd"
                eval $cmd;result=$?
                myLog "DEBUG" "CMD RESULT: $result"
            fi

            if [ "$is_matroska" != true ] || [ $result != 0 ]
            then
                myLog "INFO" "Extracting (ffmpeg) original SUBTITLES. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]} ... ... ..."
                cmd="ffmpeg -y -loglevel error -hide_banner -nostats $ffmpeg_input_params -i '$input_file' -threads $ffmpeg_threads -map 0:${indexes_a[$stream_counter]} -scodec copy -map_metadata -1 '$original_stream_file_name'"
                myLog "DEBUG" "CMD: $cmd"
                eval $cmd;result=$?
                myLog "DEBUG" "CMD RESULT: $result"
                if [ $result = 0 ]
                then
                    files_with_original_streams_a+=($original_stream_file_name)
                else
                    myLog "ERROR" "Extracting not successful. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]}."
                    can_convert=false
                fi
            else
                files_with_original_streams_a+=($original_stream_file_name)
            fi

            if [ "$can_convert" = true ]
            then
                if [ "$unsupported_subtitles" = "convert" ]
                then
                    # convert original stream into supported codec
                    # TODO: convert
                    myLog "INFO" "Converting NOT supported SUBTITLES. Stream: ${indexes_a[$stream_counter]}, Codec: ${codecs_a[$stream_counter]} ... ... ..."
                    myLog "ERROR" "Subtitles conversion is NOT implemented. Subtitles wil be removed!!!!"
                fi
            fi
        fi
    else
        # prepare for final output
        if [ "$check_only" = false ]
        then
            myLog "TRACE" "Final mux tracks before: " ${fmux_tracks_a[@]}
            fmux_tracks_a+=("0:${indexes_a[$stream_counter]}")
            myLog "TRACE" "Final mux tracks after: " ${fmux_tracks_a[@]}

            myLog "TRACE" "Languages before: " ${fmux_track_languages_a[0]}
            fmux_track_languages_a[0]=${fmux_track_languages_a[0]}"--language '${indexes_a[$stream_counter]}:${languages_a[$stream_counter]}' "
            myLog "TRACE" "Languages after: " ${fmux_track_languages_a[0]}
            
            myLog "TRACE" "Forced before: " ${fmux_track_forced_flags_a[0]}
            fmux_track_forced_flags_a[0]=${fmux_track_forced_flags_a[0]}"--forced-track '${indexes_a[$stream_counter]}:${forced_flags_a[$stream_counter]}' "
            myLog "TRACE" "Forced after: " ${fmux_track_forced_flags_a[0]}

            myLog "TRACE" "Default before: " ${fmux_track_default_flags_a[0]}
            fmux_track_default_flags_a[$input_counter]=${fmux_track_default_flags_a[0]}"--default-track '${indexes_a[$stream_counter]}:${default_flags_a[$stream_counter]}' "
            myLog "TRACE" "Default after: " ${fmux_track_default_flags_a[0]}

            myLog "TRACE" "Titles before: " ${fmux_track_titles_a[0]}
            fmux_track_titles_a[$input_counter]=${fmux_track_titles_a[0]}"--track-name '${indexes_a[$stream_counter]}:${titles_a[$stream_counter]}' "
            myLog "TRACE" "Titles after: " ${fmux_track_titles_a[0]}
        fi
    fi

    # append +1 to stream counter
    stream_counter=$(($stream_counter + 1))

done < "$subtitle_streams_output"

# ---------------------------------------------------------------

if [ "$check_only" = false ]
then
    if [ "$at_least_one_video" = true ] && [ "$at_least_one_audio" = true ]
    then
        # not copied video tracks from original
        myLog "TRACE" "Not copy videos: " ${fmux_not_copy_videos_a[@]}
        if [ ${#fmux_not_copy_videos_a[@]} -gt 0 ]
        then
            fmux_not_copy_videos_mkvmerge_param="-d '!"
            first=true
            for ncv in "${fmux_not_copy_videos_a[@]}"
            do
                if [ "$first" = true ]
                then
                    fmux_not_copy_videos_mkvmerge_param+="$ncv"
                    first=false
                else
                    fmux_not_copy_videos_mkvmerge_param+=",$ncv"
                fi
            done
            fmux_not_copy_videos_mkvmerge_param+="'"
        else
            fmux_not_copy_videos_mkvmerge_param=""
        fi
        myLog "TRACE" "Not copy videos param: ${fmux_not_copy_videos_mkvmerge_param}"
        
        # not copied audio tracks from original
        myLog "TRACE" "Not copy audios: " ${fmux_not_copy_audios_a[@]}
        if [ ${#fmux_not_copy_audios_a[@]} -gt 0 ]
        then
            fmux_not_copy_audios_mkvmerge_param="-a '!"
            first=true
            for ncv in "${fmux_not_copy_audios_a[@]}"
            do
                if [ "$first" = true ]
                then
                    fmux_not_copy_audios_mkvmerge_param+="$ncv"
                    first=false
                else
                    fmux_not_copy_audios_mkvmerge_param+=",$ncv"
                fi
            done
            fmux_not_copy_audios_mkvmerge_param+="'"
        else
            fmux_not_copy_audios_mkvmerge_param=""
        fi
        myLog "TRACE" "Not copy audios param: ${fmux_not_copy_audios_mkvmerge_param}"
        
        # not copied subtitle tracks from original
        myLog "TRACE" "Not copy subtitles: " ${fmux_not_copy_subtitles_a[@]}
        if [ ${#fmux_not_copy_subtitles_a[@]} -gt 0 ]
        then
            fmux_not_copy_subtitles_mkvmerge_param="-s '!"
            first=true
            for ncv in "${fmux_not_copy_subtitles_a[@]}"
            do
                if [ "$first" = true ]
                then
                    fmux_not_copy_subtitles_mkvmerge_param+="$ncv"
                    first=false
                else
                    fmux_not_copy_subtitles_mkvmerge_param+=",$ncv"
                fi
            done
            fmux_not_copy_subtitles_mkvmerge_param+="'"
        else
            fmux_not_copy_subtitles_mkvmerge_param=""
        fi
        myLog "TRACE" "Not copy subtitles param: ${fmux_not_copy_subtitles_mkvmerge_param}"
        
        # final mux
        fmux_inputs_mkvmerge_param=""
        first=true
        input_counter=$((0))
        myLog "TRACE" "Final mux inputs: " ${fmux_inputs_a[@]}
        for fin in "${fmux_inputs_a[@]}"
        do
            myLog "TRACE" "Final mux input: $fin"
            if [ "$first" = true ]
            then
                myLog "TRACE" "Track languages: ${fmux_track_languages_a[$input_counter]}"
                myLog "TRACE" "Track forced flags: ${fmux_track_forced_flags_a[$input_counter]}"
                myLog "TRACE" "Track default flags: ${fmux_track_default_flags_a[$input_counter]}"
                myLog "TRACE" "Track titles: ${fmux_track_titles_a[$input_counter]}"
                fmux_inputs_mkvmerge_param+=" $fmux_not_copy_videos_mkvmerge_param $fmux_not_copy_audios_mkvmerge_param $fmux_not_copy_subtitles_mkvmerge_param ${fmux_track_languages_a[$input_counter]} ${fmux_track_forced_flags_a[$input_counter]} ${fmux_track_default_flags_a[$input_counter]} ${fmux_track_titles_a[$input_counter]} $fin"
                first=false
            else
                fmux_inputs_mkvmerge_param+=" ${fmux_track_languages_a[$input_counter]} $fin"
            fi
            input_counter=$(($input_counter + 1))
        done
        myLog "TRACE" "${fmux_inputs_mkvmerge_param}"
        
        myLog "TRACE" "Final mux tracks: " ${fmux_tracks_a[@]}
        fmux_tracks_mkvmerge_param=""
        first=true
        for fin in "${fmux_tracks_a[@]}"
        do
            myLog "TRACE" "Final mux track: $fin"
            if [ "$first" = true ]
            then
                fmux_tracks_mkvmerge_param+="$fin"
                first=false
            else
                fmux_tracks_mkvmerge_param+=",$fin"
            fi
        done
        myLog "TRACE" "${fmux_tracks_mkvmerge_param}"
        
        myLog "INFO" "Final muxing streams to $converted_file ... ... ..."
        # eval not working here, don't know why
        fmux_cmd="mkvmerge -o '$converted_file' $fmux_inputs_mkvmerge_param --track-order '$fmux_tracks_mkvmerge_param' --title '$input_file_name converted for Samsung TV 2018+'"
        myLog "DEBUG" "FINAL MUX CMD: " $fmux_cmd
        # eval not working here, don't know why
        eval $fmux_cmd;fmux_result=$?
        myLog "DEBUG" "CMD RESULT: " $fmux_result
        if [ "$fmux_result" -ne 1 ]
        then
            myLog "ERROR" "Samsung TV 2018+ conversion wasn't successful... (all temp files etc. are not deleted - you can check them)"
            cmd="cd '$start_dirname'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            exit -1
        fi
        
        if [ "$useWorkingDirectory" = true ]
        then
            cmd="mv '$converted_file' '$input_dirname'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            myLog "DEBUG" "CMD RESULT: $result"
            if [ $result != 0 ]
            then
               myLog "WARNING" "Couldn't move converted file into original folder."
            fi
          
            cmd="rm -rf '$input_file'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            myLog "DEBUG" "CMD RESULT: $result"
            if [ $result != 0 ]
            then
               myLog "WARNING" "Couldn't delete original file in working folder."
            fi
        fi
        
        # copy or move original srt
        original_srt_file="$input_file_name.srt"
        if [ "$keep_original_file" = false ]
        then
            cmd="rm -rf '$input_dirname/$input_file'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            myLog "DEBUG" "CMD RESULT: $result"
            if [ $result != 0 ]
            then
               myLog "WARNING" "Couldn't delete original file."
            fi
        
            if [ -f "$original_srt_file" ]
            then
                cmd="mv '$input_dirname/$original_srt_file' '$input_dirname/$converted_srtfile'"
                myLog "DEBUG" "CMD: $cmd"
                eval $cmd;result=$?
                myLog "DEBUG" "CMD RESULT: $result"
                if [ $result != 0 ]
                then
                    myLog "WARNING" "Couldn't rename original srt file."
                fi
            fi
        else
            if [ -f "$original_srt_file" ]
            then
                cmd="cp '$input_dirname/$original_srt_file' '$input_dirname/$converted_srtfile'"
                myLog "DEBUG" "CMD: $cmd"
                eval $cmd;result=$?
                myLog "DEBUG" "CMD RESULT: $result"
                if [ $result != 0 ]
                then
                    myLog "WARNING" "Couldn't copy original srt file."
                fi
            fi
        fi
    else
        myLog "ERROR" "Samsung TV 2018+ conversion wasn't successful. There is NOT at least one audio and one video track."
    fi

    myLog "TRACE" "Files with original streams: " ${files_with_original_streams_a[@]}
    # save original streams
    if [ "$save_original_streams" = true ]
    then
        cmd="mkdir -p '$input_dirname/$original_streams_dir'"
        myLog "DEBUG" "CMD: $cmd"
        eval $cmd;result=$?
        myLog "DEBUG" "CMD RESULT: $result"
        if [ $result != 0 ]
        then
            myLog "WARNING" "Couldn't create directory for original streams."
        fi

        for osfn in "${files_with_original_streams_a[@]}"
        do
            cmd="mv '$osfn' '$input_dirname/$original_streams_dir'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            myLog "DEBUG" "CMD RESULT: $result"
            if [ $result != 0 ]
            then
                myLog "WARNING" "Couldn't move original stream. '$osfn'"
            fi

        done
    else
        for osfn in "${files_with_original_streams_a[@]}"
        do
            cmd="rm -rf '$osfn'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            myLog "DEBUG" "CMD RESULT: $result"
            if [ $result != 0 ]
            then
                myLog "WARNING" "Couldn't delete original stream file."
            fi

        done
    fi

    myLog "TRACE" "Files with temp data: " ${files_with_temp_data_a[@]}
    # clean tmp files
    if [ "$clean_temp_files" = true ]
    then
        for osfn in "${files_with_temp_data_a[@]}"
        do
            cmd="rm -rf '$osfn'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            myLog "DEBUG" "CMD RESULT: $result"
            if [ $result != 0 ]
            then
                myLog "WARNING" "Couldn't delete temp file."
            fi
        done
    fi
fi

cmd="cd '$start_dirname'"
myLog "DEBUG" "CMD: $cmd"
eval $cmd;result=$?

myLog "HIGHEST" "Samsung TV 2018+ conversion / check finished."

exit 0
