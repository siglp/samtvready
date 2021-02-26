#!/bin/bash
# Author: Petr27

# ---------------------------------------------------------------

# check parameters
if [ -z "$1" ]
then
    echo "Input file list must be specified."
    exit -1
fi
input_file_arg=$1

if [ ! -f "$input_file_arg" ]
then
    echo "Not existing file list for check / convert: " $input_file_arg
    exit -1
fi
input_file=$input_file_arg


# ---------------------------------------------------------------

# starting
echo "Samsung TV 2018+ BATCH conversion / check started..."

# ---------------------------------------------------------------

# read info about track and find default track for video
declare -a errors
hasErrors=false
while read line; do

    echo "--------------------------- Start: $line ---------------------------" 

    cmd="samtvready '$line' ${*:2}"
    eval $cmd;result=$?
    
    if [ $result != 0 ]
    then
        echo "ERROR: Conversion of file $line ends with some error."
        errors+=("$line") 
        hasErrors=true;
    fi

    echo "--------------------------- End: $line ---------------------------"
    
done < "$input_file"

# ---------------------------------------------------------------

if [ "$hasErrors" = false ]
then
    echo "Samsung TV 2018+ BATCH conversion / check finished."
else
    echo "Samsung TV 2018+ BATCH conversion / check finished with ERRORS for some inputs. See below:"
    printf '%s\n' "${errors[@]}"
fi

exit 0
