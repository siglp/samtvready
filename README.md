# Samsung TV 2018+ ready
Scripts for converting media files to be Samsung TV 2018+ ready.

## Introduction
Samsung TV from year 2018 doesn't support DivX / XviD video codecs and DTS audio codecs. Don't ask me why. I don't know it and I don't understand that too. Especially DTS "support".
This scripts (**linux shell**) can help you to convert your media (video) files to be compatible with Samsung TV 2018+.
I am not shell programmer, so it is NOT optimalized for speed, but for functionality.
In fact you can configure it to convert "every type" to "some another type" (default configuration is for Samsung TV 2018+).

This scripts should work also in Windows 10, if you have enabled and installed [WSL](https://ubuntu.com/wsl).

## Prerequisites
- **ffmpeg** installed
    - **ffprobe** used for getting detailed info about streams
    - **ffmpeg** used for extracting streams (as backup solution if mkvextract is not working)
    - **ffmpeg** used for audio and video conversion
- **mkvtools** installed
    - **mkvextract** used for extracting streams (easier way to extract streams)
    - **mkvmerge** used for final merging of streams (nicer result of final mkv)

## Install
1. Install prerequisites
2. Copy below files to some location (default **/opt/samtvready**). Or you can clone this repository and then copy :-)
    - **samtvready.sh**
    - **samtvready.conf**
    - **samtvready-batch.sh**
    - **language-codes.csv**
3. If you choose some another location, you must change it also in **samtvready.sh** (for including config file)
    - ``config_file="/opt/samtvready/samtvready.conf"``
4. Make a symbolic link in **/usr/local/sbin** to **samtvready.sh** and **samtvready-batch.sh**
    - ``sudo ln -s /opt/samtvready/samtvready.sh /usr/local/sbin/samtvready``
    - ``sudo ln -s /opt/samtvready/samtvready-batch.sh /usr/local/sbin/samtvready-batch``
5. Edit **samtvready.conf** for your own usage
6. Copy **language-codes.csv** to the same location as **samtvready.conf**

## Configuration
Always change configuration in **samtvready.conf**.

### Basic config parameters
- **converted_file_name_suffix**
    - string suffix for converted file name
    - it is also used for check, if file was already converted
    - ``converted_file_name_suffix**="-SamTVReady"``
- **converted_title_suffix**
    - string suffix in media file title
    - ``converted_title_suffix=" converted for Samsung TV 2018+"``
- **report_file_location**
    - location for report file (it is used for reporting VOB files and not supported codecs in files - mode "report"
    - must **NOT** end with **"/"**
    - ``report_file_location="/opt/samtvready/report"``
- **working_dir_location**
    - location where script should work (and to that location it will copy original file)
    - for example if you have files on some RAID / NAS, but conversion you want to do on local SSD disk
    - if this setting is empty, then script will work in original file destination
    - must **NOT** end with **"/"**
    - ``working_dir_location=""``
- **max_file_size_for_using_working_dir**
    - maximal file size in bytes which should be copy to working location
    - if file size is above this value, then script will work in original file destination
    - ``max_file_size_for_using_working_dir=100000000000``
- **ffmpeg_threads**
    - parameter for ffmpeg
    - it define how many threads can ffmpeg use
    - **0** means optimal (decision is on ffmpeg)
    - ``ffmpeg_threads=0``
- **ffmpeg_input_params**
    - additional params for ffmpeg used as global params (before -i option)
    - **libx** ex:``ffmpeg_input_params="-nostdin -fflags +genpts"``
    - **nvenc** ex:``ffmpeg_input_params="-nostdin -fflags +genpts -hwaccel auto"``

### Video config parameters
- **supported_video_codecs**
    - comma separated list of video codecs, which are supported => will not be converted
    - ``supported_video_codecs="hevc,h264,av1"``
- **unsupported_video**
    - mode/action for unsupported video
    - **remove** - remove stream from final file
    - **convert** - convert stream to some supported codec
    - **copy** - copy stream as it is
        - default if there is nothing or bad value
    - **report** - report unsupported stream into report file and do any conversion
    - ``unsupported_video="convert"``
- **unsupported_video_480p_params**
    - params for ffmpeg conversion used for video streams with resolution 480p and less
    - **libx** ex:``unsupported_video_480p_params="-preset slow -vcodec libx264 -cq 19 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"``
    - **nvenc** ex:``unsupported_video_480p_params="-preset slow -vcodec h264_nvenc -cq 19 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"``
- **unsupported_video_576p_params**
    - params for ffmpeg conversion used for video streams with resolution 576p
    - **libx** ex:``unsupported_video_576p_params="-preset slow -vcodec libx264 -cq 20 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"``
    - ``unsupported_video_576p_params="-preset slow -vcodec h264_nvenc -cq 20 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"``
- **unsupported_video_720p_params**
    - params for ffmpeg conversion used for video streams with resolution 720p - HD
    - **libx** ex:``unsupported_video_720p_params="-preset slow -vcodec libx264 -cq 21 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"``
    - **nvenc** ex:``unsupported_video_720p_params="-preset slow -vcodec h264_nvenc -cq 21 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"``
- **unsupported_video_1080p_params**
    - params for ffmpeg conversion used for video streams with resolution 1080p - Full HD
    - **libx** ex:``unsupported_video_1080p_params="-preset slow -vcodec libx265 -cq 22 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"``
    - **nvenc** ex:``unsupported_video_1080p_params="-preset slow -vcodec hevc_nvenc -cq 22 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"``
- **unsupported_video_2160p_params**
    - params for ffmpeg conversion used for video streams with resolution 2160p - UHD / 4K
    - **libx** ex:``unsupported_video_2160p_params="-preset slow -vcodec libx265 -cq 24 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"``
    - **nvenc** ex:``unsupported_video_2160p_params="-preset slow -vcodec hevc_nvenc -cq 24 -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p"``
- **report_vob_files**
    - boolean value which indicates if you want to report *.VOB files (DVD)
    - it can be useful, when you want concat result in one file: [ffmpeg concatenate](https://trac.ffmpeg.org/wiki/Concatenate)
    - ``report_vob_files=true``
- **mux_without_video**
    - boolean value which indicates, that you want mux final media file even if there is no valid (converted or original) video
    - ``mux_without_video=false``

### Audio config parameters
- **supported_audio_codecs**
    - comma separated list of audio codecs, which are supported => will not be converted
    - ``supported_audio_codecs="aac,aac_latm,ac3,eac3"``
- **unsupported_audio**
    - mode/action for unsupported audio
    - **remove** - remove stream from final file
    - **convert** - convert stream to some supported codec
    - **copy** - copy stream as it is
        - default if there is nothing or bad value
    - **report** - report unsupported stream into report file and do any conversion
    - ``unsupported_audio="convert"``
- **unsupported_audio_lq_acodec**
    - params for ffmpeg conversion used for audio streams with lq (low quality) sound (no. of channels less then 5.1, bitrate below **lq_sq_bitrate_border**)
    - ``unsupported_audio_lq_acodec="-acodec aac -b:a 192k"``
- **unsupported_audio_sq_acodec**
    - params for ffmpeg conversion used for audio streams with sq (standard quality) sound (no. of channels less then 5.1, bitrate above **lq_sq_bitrate_border**)
    - ``unsupported_audio_sq_acodec="-acodec aac -b:a 448k"``
- **unsupported_audio_hq_acodec**
    - params for ffmpeg conversion used for audio streams with hq (high quality) sound (no. of channels more or equal 5.1)
    - ``unsupported_audio_hq_acodec="-acodec eac3 -b:a 1536k -ac 6"``
- **lq_sq_bitrate_border**
    - border for lq (low quality) and sq (standard quality)
    - sound with 2 (or less) channels and bitrate below this border will be lq, above this border will be sq
    - ``lq_sq_bitrate_border=192000``
- **mux_without_audio**
    - boolean value which indicates, that you want mux final media file even if there is no valid (converted or original) audio
    - ``mux_without_audio=false``

### Subtitles config parameters
- **supported_subtitles_codecs=**
    - comma separated list of subtitle formats, which are supported => will not be converted
    - ``supported_subtitles_codecs="subrip,srt,ass,ssa,dvd_subtitle"``
- **unsupported_subtitles**
    - mode/action for unsupported subtitles
    - **remove** - remove stream from final file
    - **convert** - convert stream to some supported codec (*NOT IMPLEMENTED*)
    - **copy** - copy stream as it is
        - default if there is nothing or bad value
    - **report** - report unsupported stream into report file and do any conversion
    - ``unsupported_subtitles="remove"``
- **unsupported_subtitles_conversion_params**
    - params for ffmpeg conversion used for subtitles (*NOT IMPLEMENTED*)
    - ``unsupported_subtitles_conversion_params=""``

### Keep original streams and videos. temp files
- **keep_original_file**
    - boolean value which indicates if you want to keep original file (recommendation **true**)
    - ``keep_original_file=true``
- **save_original_streams**
    - boolean value which indicates if you want to save original streams, which are converted (recommendation **true**)
    - ``save_original_streams=true``
- **original_streams_dir**
    - location for original streams (it can be absolute or relative path)
    - if it is relative than "base" is original file direcotry
    - must **NOT** end with **"/"**
    - ``original_streams_dir="0-original-streams"``
- **clean_temp_files**
    - boolean value which indicates if you want to delete work / temp files
    - ``clean_temp_files=true``

### Logging
- **loglevel**
    - string value which defines logging level
    - **TRACE** - very detailed information
    - **DEBUG** - information for debugging, finding errors
    - **INFO** - common information and all errors, warnings
    - **WARNING** - show only warning, errors and the highest priority messages
    - **ERROR** - show only errors and the highest priority messages
    - **HIGHEST** - only the highest priority information
    - ``loglevel="INFO"``
- **logstyle**
    - string value which defines logging style
    - **DEVEL** with timestamps, for developers
    - **BFU** without timestamps, for normal users ;-)
    - ``logstyle="BFU"``

## Usage
**!!! ALERT !!!** Usage is on your own risk. I really recommend to have config option **keep_original_file=true**!!!
- Single file check:
    -   ``samtvready /data/movies/MyMovie.avi check_only``
- Single file conversion:
    -   ``samtvready /data/movies/MyMovie.avi``
- Batch file check:
    -   ``samtvready-batch /data/movies/file_list.txt check_only``
- Batch file conversion:
    -   ``samtvready-batch /data/movies/file_list.txt``
    
Batch conversion needs list of full path filenames to convert / check. See file_list_sample.txt.
You can generate this file with find or create it manually or what ever you want.

Example: ``find ~+ ! \( -name "*-SamTVReady*" -o -name "*movie-poster*" -o -name "*original-stream-*" -o -name "*.srt" \) -type f > movies.txt``

You can also create cron for periodically check and so on...

It's up to you :-).
