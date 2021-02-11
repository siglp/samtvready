#!/bin/bash
# Author: Petr27

# ---------------------------------------------------------------

config_file="/opt/nas/samtvready.conf"

# ---------------------------------------------------------------

# check parameters
if [ -z "$1" ]
then
    echo "File must be specified."
    exit -1
fi
input_file=$1

if [ ! -f "$input_file" ]
then
    echo "Not existing file for check / convert."
    exit -1
fi

if [ -z "$2" ]
then
    check_only=false
else
    if [ $2 == "check_only" ]
    then
        check_only=true
    else
        check_only=false
    fi
fi

# ---------------------------------------------------------------

# constants - configuration "remove" / "convert" / "copy" (default if nothing or bad value)
unsupported_video="convert"
unsupported_audio="convert"
unsupported_subtitles="remove"

# codec settings for ffmpeg
unsupported_video_vcodec="-preset slow -vcodec libx265 -crf 23 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2'"
unsupported_audio_acodec="-acodec eac3 -b:a 1536k"
unsupported_subtitles_scodec=""

# number of ffmpeg threads to use - number - 0 means optimal
ffmpeg_threads=0

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

# ---------------------------------------------------------------

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
    resolveLogLevel $loglevel
    definedLogLevel=$?
    resolveLogLevel $messageLogLevelStr
    messageLogLevel=$?

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

# ---------------------------------------------------------------

# starting
myLog "HIGHEST", "Samsung TV 2018+ conversion / check started..."

if [ "$check_only" = false ]
then
    myLog "HIGHEST", "Converting $input_file."
else
    myLog "HIGHEST", "Checking $input_file."
fi

basename=$(basename -- "$input_file")
input_file_extension="${basename##*.}"
input_file_name="${basename%.*}"

# main arrays
declare -a final_mux_inputs
declare -a final_mux_tracks
declare -a streams
declare -a codecs
declare -a languages
declare -a files_with_original_streams
declare -a files_with_temp_data
declare -a not_copy_videos
declare -a not_copy_audios
declare -a not_copy_subtitles
declare -a track_languages

# input file is first file in inputs
final_mux_inputs+=("'$input_file'")

# help file names
ffprobe_output=ffprobe_output.txt
streams_output=streams_output.txt
video_streams_output=video_streams_output.txt
audio_streams_output=audio_streams_output.txt
subtitle_streams_output=subtitle_streams_output.txt
# will be deleted :-)?
files_with_temp_data+=($ffprobe_output $streams_output $video_streams_output $audio_streams_output $subtitle_streams_output)

# converted file
converted_file="$input_file_name-SamTVReady.mkv"
converted_srtfile="$input_file_name-SamTVReady.srt"

# prepare help files
ffprobe -i "$input_file" > "$ffprobe_output" 2>&1
cat "$ffprobe_output" | grep "Stream" > "$streams_output"
cat "$streams_output" | grep "Video:" > "$video_streams_output"
cat "$streams_output" | grep "Audio:" > "$audio_streams_output"
cat "$streams_output" | grep "Subtitle:" > "$subtitle_streams_output"

# counters
stream_counter=$((0))
input_counter=$((0))

# ---------------------------------------------------------------

# prepare video streams
first=true
while read line; do
    default=false
    # is video default
    if [[ "$line" == *"default"* ]]
    then
        default=true
    else
        if [ "$first" == true ]
        then
            default=true
        fi
    fi
    first=false

    myLog "DEBUG" "Default video track: ${default}"

    # streams position in original
    streams[$stream_counter]=`echo $line | awk '{ print $2 }' | awk 'BEGIN { FS=":" } { print $2 }' | awk 'BEGIN { FS="(" } { print $1 }'`

    # streams language in original
    languages[$stream_counter]=`echo $line | awk '{ print $2 }' | awk 'BEGIN { FS=":" } { print $2 }' | awk 'BEGIN { FS="(" } { print $2 }' | awk 'BEGIN { FS=")" } { print $1 }'`
    if [ -z "${languages[$stream_counter]}" ]
    then
        languages[$stream_counter]="und"
    fi

    # video codes in original
    codecs[$stream_counter]=`echo $line | awk '{ print $4 }'`
    if [ "${codecs[$stream_counter]}" != "h264" ] && [ "${codecs[$stream_counter]}" != "hevc" ]
    then
        myLog "INFO" "NOT supported VIDEO codec. Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]}."
        # convert?
        if [ "$check_only" = false ] && ([ "$unsupported_video" = "remove" ] || [ "$unsupported_video" = "convert" ])
        then
            # do not copy from original file
            not_copy_videos+=(${streams[$stream_counter]})
            # extract original stream
            original_stream_name="$input_file_name-original-${codecs[$stream_counter]}-${languages[$stream_counter]}-${streams[$stream_counter]}"
            original_stream_file_name="$original_stream_name.mkv"
            original_stream_file_name_converted="$original_stream_name-converted.mkv"
            # extract orginal stream
            can_convert=true
            myLog "INFO" "Extracting (mkvextract) original VIDEO Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]} ... ... ..."
            cmd="mkvextract '$input_file' tracks ${streams[$stream_counter]}:'$original_stream_file_name'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            myLog "DEBUG" "CMD RESULT: $result"
            if [ $result != 0 ]
            then
                myLog "INFO" "Extracting original VIDEO for the second time (ffmpeg). Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]} ... ... ..."
                cmd="ffmpeg -y -loglevel error -hide_banner -nostats -i '$input_file' -threads $ffmpeg_threads -map 0:${streams[$stream_counter]} -vcodec copy -map_metadata -1 '$original_stream_file_name'"
                myLog "DEBUG" "CMD: $cmd"
                eval $cmd;result=$?
                myLog "DEBUG" "CMD RESULT: $result"
                if [ $result == 0 ]
                then
                    files_with_original_streams+=($original_stream_file_name)
                else
                    myLog "ERROR" "Extracting not successful. Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]}."
                    can_convert=false
                fi
            else
                files_with_original_streams+=($original_stream_file_name)
            fi

            # convert only default
            if [ "$default" = true ] && [ "$can_convert" = true ]
            then
                # convert if needed
                if [ "$unsupported_video" = "convert" ]
                then
                    # convert original stream into supported codec
                    myLog "INFO" "Converting NOT supported VIDEO. Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]} ... ... ..."
                    cmd="ffmpeg -y -loglevel error -hide_banner -nostats -i '$original_stream_file_name' -threads $ffmpeg_threads -map 0 -map_metadata -1 $unsupported_video_vcodec  '$original_stream_file_name_converted'"
                    myLog "DEBUG" "CMD: $cmd"
                    eval $cmd;result=$?
                    myLog "DEBUG" "CMD RESULT: $result"
                    if [ $result == 0 ]
                    then
                        files_with_temp_data+=($original_stream_file_name_converted)
                        # prepare for final output
                        input_counter=$(($input_counter + 1))
                        myLog "TRACE" "Input counter: $input_counter"
                        mux_input="-T -A -S -B -M --no-global-tags --no-chapters -d '0' '$original_stream_file_name_converted'"

                        myLog "TRACE" "Final mux input before: " ${final_mux_inputs[@]}
                        final_mux_inputs+=("$mux_input")
                        myLog "TRACE" "Final mux input after: " ${final_mux_inputs[@]}

                        myLog "TRACE" "Final mux tracks before: " ${final_mux_tracks[@]}
                        final_mux_tracks+=("$input_counter:0")
                        myLog "TRACE" "Final mux tracks after: " ${final_mux_tracks[@]}

                        myLog "TRACE" "Languages before: " ${track_languages[$input_counter]}
                        track_languages[$input_counter]=${track_languages[$input_counter]}"--language '0:${languages[$stream_counter]}' "
                        myLog "TRACE" "Languages after: " ${track_languages[$input_counter]}
                    else
                        myLog "ERROR" "Conversion not successful. Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]}."
                    fi
                fi
            fi
        fi
    else
        # prepare for final output
        if [ "$check_only" = false ]
        then
            myLog "TRACE" "Final mux tracks before: " ${final_mux_tracks[@]}
            final_mux_tracks+=("0:${streams[$stream_counter]}")
            myLog "TRACE" "Final mux tracks after: " ${final_mux_tracks[@]}

            myLog "TRACE" "Languages before: " ${track_languages[0]}
            track_languages[0]=${track_languages[0]}"--language '${streams[$stream_counter]}:${languages[$stream_counter]}' "
            myLog "TRACE" "Languages after: " ${track_languages[0]}
        fi
    fi

    # append +1 to stream counter
    stream_counter=$(($stream_counter + 1))

done < "$video_streams_output"

# ---------------------------------------------------------------

# prepare audio streams
while read line; do

    # streams position in original
    streams[$stream_counter]=`echo $line | awk '{ print $2 }' | awk 'BEGIN { FS=":" } { print $2 }' | awk 'BEGIN { FS="(" } { print $1 }'`

    # streams language in original
    languages[$stream_counter]=`echo $line | awk '{ print $2 }' | awk 'BEGIN { FS=":" } { print $2 }' | awk 'BEGIN { FS="(" } { print $2 }' | awk 'BEGIN { FS=")" } { print $1 }'`
    if [ -z "${languages[$stream_counter]}" ]
    then
        languages[$stream_counter]="und"
    fi

    # audio codes in original
    codecs[$stream_counter]=`echo $line | awk '{ print $4 }'`
    if [[ "${codecs[$stream_counter]}" == *"dts"* ]] || [[ "${codecs[$stream_counter]}" == *"truehd"* ]] || [[ "${codecs[$stream_counter]}" == *"atmos"* ]] || [[ "${codecs[$stream_counter]}" == *"flac"* ]]
    then
        myLog "INFO" "NOT supported AUDIO codec. Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]}."
        # convert?
        if [ "$check_only" = false ] && ([ "$unsupported_audio" = "remove" ] || [ "$unsupported_audio" = "convert" ])
        then
            # extract original stream
            original_stream_name="$input_file_name-original-${codecs[$stream_counter]}-${languages[$stream_counter]}-${streams[$stream_counter]}"
            original_stream_file_name="$original_stream_name.mka"
            original_stream_file_name_converted="$original_stream_name-converted.mka"
            # extract orginal stream
            not_copy_audios+=(${streams[$stream_counter]})
            myLog "INFO" "Extracting (mkvextract) original AUDIO Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]} ... ... ..."
            cmd="mkvextract '$input_file' tracks ${streams[$stream_counter]}:'$original_stream_file_name'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            myLog "DEBUG" "CMD RESULT: $result"
            if [ $result != 0 ]
            then
                myLog "INFO" "Extracting original AUDIO for the second time (ffmpeg). Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]} ... ... ..."
                cmd="ffmpeg -y -loglevel error -hide_banner -nostats -i '$input_file' -threads $ffmpeg_threads -map 0:${streams[$stream_counter]} -acodec copy -map_metadata -1 '$original_stream_file_name'"
                myLog "DEBUG" "CMD: $cmd"
                eval $cmd;result=$?
                myLog "DEBUG" "CMD RESULT: $result"
                if [ $result == 0 ]
                then
                    files_with_original_streams+=($original_stream_file_name)
                else
                    myLog "ERROR" "Extracting not successful. Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]}."
                    can_convert=false
                fi
            fi

            if [ "$can_convert" = true ]
            then
                files_with_original_streams+=($original_stream_file_name)
                # convert if needed
                if [ "$unsupported_audio" = "convert" ]
                then
                    # convert original stream into supported codec
                    myLog "INFO" "Converting NOT supported AUDIO. Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]} ... ... ..."
                    cmd="ffmpeg -y -loglevel error -hide_banner -nostats  -i '$original_stream_file_name' -threads $ffmpeg_threads -map 0 -map_metadata -1 $unsupported_audio_acodec '$original_stream_file_name_converted'"
                    myLog "DEBUG" "cmd: $cmd"
                    eval $cmd;result=$?
                    myLog "DEBUG" "CMD RESULT: $result"
                    if [ $result == 0 ]
                    then
                        files_with_temp_data+=($original_stream_file_name_converted)
                        # prepare for final output
                        input_counter=$(($input_counter + 1))
                        myLog "TRACE" "Input counter: $input_counter"
                        mux_input="-T -D -S -B -M --no-global-tags --no-chapters -a '0' '$original_stream_file_name_converted'"

                        myLog "TRACE" "Final mux input before: " ${final_mux_inputs[@]}
                        final_mux_inputs+=("$mux_input")
                        myLog "TRACE" "Final mux input after: " ${final_mux_inputs[@]}

                        myLog "TRACE" "Final mux tracks before: " ${final_mux_tracks[@]}
                        final_mux_tracks+=("$input_counter:0")
                        myLog "TRACE" "Final mux tracks after: " ${final_mux_tracks[@]}

                        myLog "TRACE" "Languages before: " ${track_languages[$input_counter]}
                        track_languages[$input_counter]=${track_languages[$input_counter]}"--language '0:${languages[$stream_counter]}' "
                        myLog "TRACE" "Languages after: " ${track_languages[$input_counter]}
                    else
                        myLog "ERROR" "Conversion not successful. Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]}."
                    fi
                fi
            fi
        fi
    else
        # prepare for final output
        if [ "$check_only" = false ]
        then
            myLog "TRACE" "Final mux tracks before: " ${final_mux_tracks[@]}
            final_mux_tracks+=("0:${streams[$stream_counter]}")
            myLog "TRACE" "Final mux tracks after: " ${final_mux_tracks[@]}

            myLog "TRACE" "Languages before: " ${track_languages[0]}
            track_languages[0]=${track_languages[0]}"--language '${streams[$stream_counter]}:${languages[$stream_counter]}' "
            myLog "TRACE" "Languages after: " ${track_languages[0]}
        fi
    fi

    # append +1 to stream counter
    stream_counter=$(($stream_counter + 1))

done < "$audio_streams_output"

# ---------------------------------------------------------------

# prepare subtitle streams
while read line; do

    # streams position in original
    streams[$stream_counter]=`echo $line | awk '{ print $2 }' | awk 'BEGIN { FS=":" } { print $2 }' | awk 'BEGIN { FS="(" } { print $1 }'`

    # streams language in original
    languages[$stream_counter]=`echo $line | awk '{ print $2 }' | awk 'BEGIN { FS=":" } { print $2 }' | awk 'BEGIN { FS="(" } { print $2 }' | awk 'BEGIN { FS=")" } { print $1 }'`
    if [ -z "${languages[$stream_counter]}" ]
    then
        languages[$stream_counter]="und"
    fi

    # subtitle codes in original
    codecs[$stream_counter]=`echo $line | awk '{ print $4 }'`
    if [[ "${codecs[$stream_counter]}" == *"pgs"* ]]
    then
        myLog "INFO" "NOT supported SUBTITLE codec. Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]}."
        # convert?
        if [ "$check_only" = false ] && ([ "$unsupported_subtitles" = "remove" ] || [ "$unsupported_subtitles" = "convert" ])
        then
            # extract original stream
            original_stream_name="$input_file_name-original-${codecs[$stream_counter]}-${languages[$stream_counter]}-${streams[$stream_counter]}"
            original_stream_file_name="$original_stream_name.sup"
            original_stream_file_name_converted="$original_stream_name-converted.sup"
            # extract orginal stream
            not_copy_subtitles+=(${streams[$stream_counter]})
            myLog "INFO" "Extracting (mkvextract) original SUBTITLE Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]} ... ... ..."
            cmd="mkvextract '$input_file' tracks ${streams[$stream_counter]}:'$original_stream_file_name'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            myLog "DEBUG" "CMD RESULT: $result"
            if [ $result != 0 ]
            then
                myLog "INFO" "Extracting original SUBTITLE for the second time (ffmpeg). Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]} ... ... ..."
                cmd="ffmpeg -y -loglevel error -hide_banner -nostats -i '$input_file' -threads $ffmpeg_threads -map 0:${streams[$stream_counter]} -scodec copy -map_metadata -1 '$original_stream_file_name'"
                myLog "DEBUG" "CMD: $cmd"
                eval $cmd;result=$?
                myLog "DEBUG" "CMD RESULT: $result"
                if [ $result == 0 ]
                then
                    files_with_original_streams+=($original_stream_file_name)
                else
                    myLog "ERROR" "Extracting not successful. Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]}."
                    can_convert=false
                fi
            fi

            if [ "$can_convert" = true ]
            then
                files_with_original_streams+=($original_stream_file_name)
                if [ "$unsupported_subtitles" = "convert" ]
                then
                    # convert original stream into supported codec
                    # TODO: convert
                    myLog "INFO" "Converting NOT supported SUBTITLE. Stream: ${streams[$stream_counter]}, Codec: ${codecs[$stream_counter]} ... ... ..."
                    myLog "ERROR" "Subtitles conversion is NOT implemented. Subtitles wil be removed!!!!"
                fi
            fi
        fi
    else
        # prepare for final output
        if [ "$check_only" = false ]
        then
            myLog "TRACE" "Final mux tracks before: " ${final_mux_tracks[@]}
            final_mux_tracks+=("0:${streams[$stream_counter]}")
            myLog "TRACE" "Final mux tracks after: " ${final_mux_tracks[@]}

            myLog "TRACE" "Languages before: " ${track_languages[0]}
            track_languages[0]=${track_languages[0]}"--language '${streams[$stream_counter]}:${languages[$stream_counter]}' "
            myLog "TRACE" "Languages after: " ${track_languages[0]}
        fi
    fi

    # append +1 to stream counter
    stream_counter=$(($stream_counter + 1))

done < "$subtitle_streams_output"

# ---------------------------------------------------------------

if [ "$check_only" = false ]
then
    # not copied video tracks from original
    myLog "TRACE" "Not copy videos: " ${not_copy_videos[@]}
    if [ ${#not_copy_videos[@]} -gt 0 ]
    then
        final_mux_not_copy_videos_mkvmerge_param="-d '!"
        first=true
        for ncv in "${not_copy_videos[@]}"
        do
            if [ "$first" = true ]
            then
                final_mux_not_copy_videos_mkvmerge_param+="$ncv"
                first=false
            else
                final_mux_not_copy_videos_mkvmerge_param+=",$ncv"
            fi
        done
        final_mux_not_copy_videos_mkvmerge_param+="'"
    else
        final_mux_not_copy_videos_mkvmerge_param=""
    fi
    myLog "TRACE" "Not copy videos param: ${final_mux_not_copy_videos_mkvmerge_param}"

    # not copied audio tracks from original
    myLog "TRACE" "Not copy audios: " ${not_copy_audios[@]}
    if [ ${#not_copy_audios[@]} -gt 0 ]
    then
        final_mux_not_copy_audios_mkvmerge_param="-a '!"
        first=true
        for ncv in "${not_copy_audios[@]}"
        do
            if [ "$first" = true ]
            then
                final_mux_not_copy_audios_mkvmerge_param+="$ncv"
                first=false
            else
                final_mux_not_copy_audios_mkvmerge_param+=",$ncv"
            fi
        done
        final_mux_not_copy_audios_mkvmerge_param+="'"
    else
        final_mux_not_copy_audios_mkvmerge_param=""
    fi
    myLog "TRACE" "Not copy audios param: ${final_mux_not_copy_audios_mkvmerge_param}"

    # not copied subtitle tracks from original
    myLog "TRACE" "Not copy subtitles: " ${not_copy_subtitles[@]}
    if [ ${#not_copy_subtitles[@]} -gt 0 ]
    then
        final_mux_not_copy_subtitles_mkvmerge_param="-s '!"
        first=true
        for ncv in "${not_copy_subtitles[@]}"
        do
            if [ "$first" = true ]
            then
                final_mux_not_copy_subtitles_mkvmerge_param+="$ncv"
                first=false
            else
                final_mux_not_copy_subtitles_mkvmerge_param+=",$ncv"
            fi
        done
        final_mux_not_copy_subtitles_mkvmerge_param+="'"
    else
        final_mux_not_copy_subtitles_mkvmerge_param=""
    fi
    myLog "TRACE" "Not copy subtitles param: ${final_mux_not_copy_subtitles_mkvmerge_param}"

    # final mux
    final_mux_inputs_mkvmerge_param=""
    first=true
    input_counter=$((0))
    myLog "TRACE" "Final mux inputs: " ${final_mux_inputs[@]}
    for fin in "${final_mux_inputs[@]}"
    do
        myLog "TRACE" "Final mux input: $fin"
        if [ "$first" = true ]
        then
            myLog "TRACE" "Track language: ${track_languages[$input_counter]}"
            final_mux_inputs_mkvmerge_param+=" $final_mux_not_copy_videos_mkvmerge_param $final_mux_not_copy_audios_mkvmerge_param $final_mux_not_copy_subtitles_mkvmerge_param ${track_languages[$input_counter]} $fin"
            first=false
        else
            final_mux_inputs_mkvmerge_param+=" ${track_languages[$input_counter]} $fin"
        fi
        input_counter=$(($input_counter + 1))
    done
    myLog "TRACE" "${final_mux_inputs_mkvmerge_param}"

    myLog "TRACE" "Final mux tracks: " ${final_mux_tracks[@]}
    final_mux_tracks_mkvmerge_param=""
    first=true
    for fin in "${final_mux_tracks[@]}"
    do
        myLog "TRACE" "Final mux track: $fin"
        if [ "$first" = true ]
        then
            final_mux_tracks_mkvmerge_param+="$fin"
            first=false
        else
            final_mux_tracks_mkvmerge_param+=",$fin"
        fi
    done
    myLog "TRACE" "${final_mux_tracks_mkvmerge_param}"

    myLog "INFO" "Final muxing streams to $converted_file ... ... ..."
    # eval not working here, don't know why
    final_mux_cmd="mkvmerge -o '$converted_file' $final_mux_inputs_mkvmerge_param --track-order '$final_mux_tracks_mkvmerge_param' --title '$input_file_name converted for Samsung TV 2018+'"
    myLog "DEBUG" "FINAL MUX CMD: " $final_mux_cmd
    # eval not working here, don't know why
    eval $final_mux_cmd;final_mux_result=$?
    myLog "DEBUG" "CMD RESULT: " $final_mux_result
    if [ "$final_mux_result" != 1 ]
    then
        myLog "ERROR" "Samsung TV 2018+ conversion wasn't successful... (all temp files etc. are not deleted)"
        exit -1
    fi

    # copy or move original srt
    original_srt_file="$input_file_name.srt"
    if [ "$keep_original_file" = false ]
    then
        cmd="rm -rf '$input_file'"
        myLog "DEBUG" "CMD: $cmd"
        eval $cmd;result=$?
        myLog "DEBUG" "CMD RESULT: $result"
        if [ $result != 0 ]
        then
           myLog "WARNING" "Couldn't delete original file."
        fi

        if [ -f "$original_srt_file" ]
        then
            cmd="mv '$original_srt_file' '$converted_srtfile'"
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
            cmd="cp '$original_srt_file' '$converted_srtfile'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            myLog "DEBUG" "CMD RESULT: $result"
            if [ $result != 0 ]
            then
                myLog "WARNING" "Couldn't copy original srt file."
            fi
        fi
    fi

    myLog "TRACE" "Files with original streams: " ${files_with_original_streams[@]}
    # save original streams
    if [ "$save_original_streams" = true ]
    then
        cmd="mkdir -p '$original_streams_dir'"
        myLog "DEBUG" "CMD: $cmd"
        eval $cmd;result=$?
        myLog "DEBUG" "CMD RESULT: $result"
        if [ $result != 0 ]
        then
            myLog "WARNING" "Couldn't create directory for original streams."
        fi

        for osfn in "${files_with_original_streams[@]}"
        do
            cmd="mv '$osfn' '$original_streams_dir'"
            myLog "DEBUG" "CMD: $cmd"
            eval $cmd;result=$?
            myLog "DEBUG" "CMD RESULT: $result"
            if [ $result != 0 ]
            then
                myLog "WARNING" "Couldn't move original stream. '$osfn'"
            fi

        done
    else
        for osfn in "${files_with_original_streams[@]}"
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

    myLog "TRACE" "Files with temp data: " ${files_with_temp_data[@]}
    # clean tmp files
    if [ "$clean_temp_files" = true ]
    then
        for osfn in "${files_with_temp_data[@]}"
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

myLog "HIGHEST" "Samsung TV 2018+ conversion / check finished."
exit 0
