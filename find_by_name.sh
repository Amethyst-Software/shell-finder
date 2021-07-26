#!/bin/bash

# Find By Name
# A script that recursively searches a directory for files by name. The results can be
# printed to screen, copied, moved, or deleted. Copying and moving can preserve the
# original folder structure if desired. Run with no parameters for usage.
# Recommended width:
# |--------------------------------------------------------------------------------------|

# Set the field separator to a newline to avoid spaces in paths breaking our
# variable-setting
IFS="
"


## CONSTANTS ##
MATCH_BODY=1
MATCH_SUFF=2
MATCH_TYPE=3
MATCH_DOT=4
PRINT=1
COPY_MIRR=2
COPY_FLAT=3
MOVE_MIRR=4
MOVE_FLAT=5
DELETE=6
declare -a SUFFIX_SETS=(-archive 7z rar zip -code c cc cp cpp cs h hpp js m mm pas php py s sh -image gif jpeg jpg png tiff -text doc docx htm html pdf rtf txt xls xlsx -video 3gp avi flv m4v mkv mov mp4 mpeg mpg webm wmv)
STR_FILES="files"
cols=$(tput cols)
bold=$(tput bold)
normal=$(tput sgr0)
THE_TIME=$(date "+%Y-%m-%d--%H-%M-%S")
TRASH_FOLDER="$HOME/.Trash/Deleted files ($THE_TIME)"


## VARIABLES ##
MATCH_MODE=0
NO_DSS=0
OPER_MODE=0
REVERSE_MODE=0 # 0 = operate on positive matches, 1 = use the negative matches
SEARCH_PATH=""
DEST_FOLDER=""
MATCH_ARGS=""
MATCH_NAME=""
declare -a MATCH_ELS=()
declare -a TARGET_SUFFIXES=()
FOUND=0


## FUNCTIONS ##
# Print SUFFIX_SETS in a human-readable manner
function printSetList()
{
   FIRST_EL=1
   a=0
   while [ "x${SUFFIX_SETS[$a]}" != "x" ]; do
      if [[ ${SUFFIX_SETS[$a]} =~ ^- ]]; then
         if [ $a -ne 0 ]; then
            echo
         fi
         echo -n "      ${SUFFIX_SETS[$a]}: " | tr -d '-'
         FIRST_EL=1
      else
         if [ $FIRST_EL -eq 1 ]; then
            echo -n "${SUFFIX_SETS[$a]}"
            FIRST_EL=0
         else
            echo -n ", ${SUFFIX_SETS[$a]}"
         fi
      fi
      let a+=1
   done
   echo
}

# For passing output through the 'fmt' wrapping tool
function mypr()
{
   echo $1 | fmt -w 80
}

# Help user if they are lost
function printHelp()
{
   echo -n ${bold}
   echo "--Find By Name--" | fmt -w $cols -c
   echo -n ${normal}
   mypr "You need to supply the following settings in any order:"
   echo "${bold}Operation mode:${normal}"
   mypr "   '--print': Print matching files to screen and take no other action."
   mypr "   '--copy-mirr': Copy matching files to destination folder, mirroring the original folder structure."
   mypr "   '--copy-flat': Copy matching files into the top level of the destination folder (files will be safely renamed in the case of naming conflicts)."
   mypr "   '--move-mirr': Move matching files to destination folder, mirroring the original folder structure."
   mypr "   '--move-flat': Move matching files into the top level of the destination folder (files will be safely renamed in the case of naming conflicts)."
   mypr "   '--delete': Move the matching files to the Trash."
   echo "${bold}Name pattern of files to copy/delete:${normal}"
   mypr "   '--name:pattern': Find all files matching 'pattern', a regex pattern."
   mypr "   '--not-name:pattern': Find all files that don't match 'pattern'."
   mypr "   '--suff:suffix1,suffix2': Find all files with these specific suffixes."
   mypr "   '--not-suff:suffix1,suffix2': Find all files without these specific suffixes."
   mypr "   '--type:set1,set2': Find all files with these sets of suffixes. The available sets are:"
   printSetList
   mypr "   '--not-type:set1,set2': Find all files that aren't in these sets of suffixes."
   mypr "   '--dotfile': Find all files beginning with a period."
   echo "${bold}Directories:${normal}"
   mypr "   '--from path': (Note the lack of a colon after 'from'.) The directory to search recursively."
   mypr "   '--dest path': (Not needed with '--delete' or '--print' option.) The folder to which the selected files should be copied or moved."
   echo "${bold}Optional:${normal}"
   mypr "   '--no-ds': When using the '--dotfile' option, don't show .DS_Store files."
}

# Checks to see if file name passed in is taken; if so, it attempts to add a number to
# the file name, and passes back the first available path that is found; function will
# exit script if no available path is found
function correctForPathConflict()
{
   isFile=

   if ! [ -a "$1" ]; then
      echo "$1"
      return
   elif [ -f "$1" ]; then
      isFile=true
   elif [ -d "$1" ]; then
      isFile=false
   else
      echo "Error: Encountered something that is not a file or directory: $1."
      exit 56
   fi

   ct=0
   TEST_PATH="$1"
   until [ $ct -eq 3000 ]; do
      if [ -a "$TEST_PATH" ]; then
         let ct+=1
         # If this is a file, and it has a suffix, break the name up at the period so
         # we can insert the unique number at the end of the name and not the suffix
         if $isFile && [[ $1 == *.* ]]; then
            preDot=${1%.*}
            postDot=${1##*.}
            TEST_PATH="$preDot $ct.$postDot"
         else
            TEST_PATH="$1 $ct"
         fi
      else
         break
      fi
   done
   if [ $ct -eq 3000 ]; then
      # Just quit, because something is probably wrong
      mypr "Error: Cannot find a place in $(dirname $1) for $(basename $1)."
      exit 57
   else
      echo "$TEST_PATH"
   fi
}


## ARGUMENT PROCESSING ##
# Print help if run with no arguments
if [ "$#" -eq 0 ]; then
   printHelp
   exit
fi

# Process all arguments
while (( "$#" )); do
   case "$1" in
      --name:* )     MATCH_NAME="$1"; MATCH_MODE=$MATCH_BODY; REVERSE_MODE=0; shift;;
      --not-name:* ) MATCH_NAME="$1"; MATCH_MODE=$MATCH_BODY; REVERSE_MODE=1; shift;;
      --suff:* )     MATCH_ARGS="$1"; MATCH_MODE=$MATCH_SUFF; REVERSE_MODE=0; shift;;
      --not-suff:* ) MATCH_ARGS="$1"; MATCH_MODE=$MATCH_SUFF; REVERSE_MODE=1; shift;;
      --type:* )     MATCH_ARGS="$1"; MATCH_MODE=$MATCH_TYPE; REVERSE_MODE=0; shift;;
      --not-type:* ) MATCH_ARGS="$1"; MATCH_MODE=$MATCH_TYPE; REVERSE_MODE=1; shift;;
      --dotfile )    MATCH_MODE=$MATCH_DOT; REVERSE_MODE=0; shift;;
      --no-ds )      NO_DSS=1; shift;;
      --from )       SEARCH_PATH="$2"; shift 2;;
      --dest )       DEST_FOLDER="$2"; shift 2;;
      --print )      OPER_MODE=$PRINT; shift;;
      --copy-mirr )  OPER_MODE=$COPY_MIRR; shift;;
      --copy-flat )  OPER_MODE=$COPY_FLAT; shift;;
      --move-mirr )  OPER_MODE=$MOVE_MIRR; shift;;
      --move-flat )  OPER_MODE=$MOVE_FLAT; shift;;
      --delete )     OPER_MODE=$DELETE; shift;;
      * )            mypr "Unrecognized argument '$1'. Aborting."; exit;;
   esac
done

# Check that settings are in place and valid
if [ $MATCH_MODE -eq 0 ]; then
   mypr "You need to specify a pattern for name-matching. Run this script without arguments to see your options. Aborting."
   exit
fi

if [ $OPER_MODE -eq 0 ]; then
   mypr "You need to pick an operation mode '--print', '--copy-mirr', '--copy-flat', '--move-mirr', '--move-flat', or '--delete'. Aborting."
   exit
fi

if [ -z "$SEARCH_PATH" ]; then
   mypr "You need to specify the folder to search using '--from PATH'. Aborting."
   exit
fi

if [ -z "$DEST_FOLDER" ] && [ $OPER_MODE -ne $PRINT ] && [ $OPER_MODE -ne $DELETE ]; then
   mypr "When using a copy or move mode, you need to specify the destination for the files with '--dest PATH'. Aborting."
   exit
fi

if [ ! -z "$DEST_FOLDER" ] && [ $OPER_MODE -eq $DELETE ]; then
   mypr "You specified a destination folder for copied/moved files, but also requested 'delete' mode. Aborting for your protection."
   exit
fi

if [ ! -d "$SEARCH_PATH" ]; then
   mypr "Can't search folder '$SEARCH_PATH' because it doesn't exist. Aborting."
   exit
fi

if [ $OPER_MODE -ne $PRINT ] && [ $OPER_MODE -ne $DELETE ] && [ ! -d "$DEST_FOLDER" ]; then
   mypr "Can't copy/move files to '$DEST_FOLDER' because it doesn't exist. Aborting."
   exit
fi

if [ $MATCH_MODE -eq $MATCH_SUFF ] || [ $MATCH_MODE -eq $MATCH_TYPE ]; then
   # Place comma-separated values following "--[not-]suff/type:" into an array
   IFS=","
   MATCH_ELS=(${MATCH_ARGS##*:})
   IFS="
"
else
   # Strip "--[not-]name:" from search string
   MATCH_NAME=(${MATCH_NAME##*:})
fi

# Add user's suffixes or sets of suffixes into our target suffixes array
if [ $MATCH_MODE -eq $MATCH_TYPE ]; then
   # If we're matching sets, then loop through elements user passed in, trying to match
   # each one to a set name
   a=0
   while [ "x${MATCH_ELS[$a]}" != "x" ]; do
      MATCHED=0
      b=0
      # Look for set names in SUFFIX_SETS
      while [ "x${SUFFIX_SETS[$b]}" != "x" ] && [ $MATCHED -eq 0 ]; do
         # If set name, match against one of the elements user passed in
         if [[ ${SUFFIX_SETS[$b]} =~ ^- ]]; then
            SET_NAME=$(echo ${SUFFIX_SETS[$b]} | tr -d '-')
            # If a match, iterate through following suffixes in set, adding each one
            if [ ${MATCH_ELS[$a]} == $SET_NAME ]; then
               let b+=1
               while [ "x${SUFFIX_SETS[$b]}" != "x" ] && [[ ! ${SUFFIX_SETS[$b]} =~ ^- ]]; do
                  TARGET_SUFFIXES+=(${SUFFIX_SETS[$b]})
                  let b+=1
               done
               MATCHED=1
            fi
         fi
         let b+=1
      done
      if [ $MATCHED -eq 0 ]; then
         mypr "Unknown set encountered: ${MATCH_ELS[$a]}. Your choices are:"
         printSetList
         exit
      fi
      let a+=1
   done
elif [ $MATCH_MODE -eq $MATCH_SUFF ]; then
   # We're matching user-specified suffixes, so just set our array to suffixes passed in
   TARGET_SUFFIXES=(${MATCH_ELS[@]})
fi

# Create dest. folder in Trash if we're in delete mode
if [ $OPER_MODE -eq $DELETE ]; then
   mkdir "$TRASH_FOLDER"
   if [ ! -d "$TRASH_FOLDER" ]; then
      echo "Could not create the folder \"$TRASH_FOLDER\". Aborting."
      exit
   fi
fi

# Print chosen settings
if [ $OPER_MODE -eq $PRINT ]; then
   echo -n "Printing names of files "
elif [ $OPER_MODE -eq $COPY_MIRR ]; then
   echo -n "Copying files in mirror mode "
elif [ $OPER_MODE -eq $COPY_FLAT ]; then
   echo -n "Copying files in flat mode "
elif [ $OPER_MODE -eq $MOVE_MIRR ]; then
   echo -n "Moving files in mirror mode "
elif [ $OPER_MODE -eq $MOVE_FLAT ]; then
   echo -n "Moving files in flat mode "
else
   echo -n "Moving files to Trash "
fi

if [ $OPER_MODE -ne $PRINT ] && [ $OPER_MODE -ne $DELETE ]; then
   echo -n "from $SEARCH_PATH to $DEST_FOLDER "
else
   echo -n "in $SEARCH_PATH "
fi

if [ $MATCH_MODE == $MATCH_DOT ]; then
   if [ $NO_DSS -eq 0 ]; then
      echo "if they are dot-files..."
   else
      echo "if they are dot-files (besides .DS_Store files)..."
   fi
elif [ $REVERSE_MODE -eq 0 ]; then
   echo -n "if they match the "
else
   echo -n "if they don't match the "
fi

if [ $MATCH_MODE -eq $MATCH_BODY ]; then
   echo "name pattern '$MATCH_NAME'..."
elif [ $MATCH_MODE -eq $MATCH_SUFF ] || [ $MATCH_MODE -eq $MATCH_TYPE ]; then
   echo "suffix list {${TARGET_SUFFIXES[@]}}..."
fi


## MAIN SCRIPT ##
for FILE in `find "$SEARCH_PATH" -type f`; do
   FILE_NAME=$(echo "$FILE" | sed 's/.*\///') # clip file name from whole path
   MATCHED=0

   if [ $MATCH_MODE -eq $MATCH_DOT ]; then
      # If name begins with a period...
      if [[ "$FILE_NAME" =~ ^\. ]]; then
         if [ $NO_DSS -eq 0 ]; then
            MATCHED=1
         elif [[ "$FILE_NAME" != ".DS_Store" ]]; then
            MATCHED=1
         fi
      fi
   elif [ $MATCH_MODE -eq $MATCH_BODY ]; then
      # If this is not a file with a name body (anything before the period), skip it
      if [[ "$FILE_NAME" =~ ^\. ]]; then
         continue
      fi

      FILE_BODY=${FILE_NAME%.*} # clip body from file name
      
      if [[ "$FILE_BODY" =~ $MATCH_NAME ]]; then
         MATCHED=1
      fi
   else
      # If this is not a file with a name and suffix, skip it
      if [[ ! "$FILE_NAME" =~ [[:print:]]+\.[[:print:]]+$ ]]; then
         continue
      fi

      FILE_SUFFIX=${FILE_NAME##*.} # clip suffix from file name

      # Search for suffix in list of desirable suffixes
      shopt -s nocasematch
      for SUFFIX in "${TARGET_SUFFIXES[@]}"; do
         if [ "$SUFFIX" == $FILE_SUFFIX ]; then
            MATCHED=1
            break
         fi
      done
      shopt -u nocasematch
   fi

   DESIRED=$((MATCHED ^= REVERSE_MODE))
   if [ $DESIRED -eq 1 ]; then
      if [ $OPER_MODE -eq $COPY_MIRR ]; then
         REL_PATH="${FILE#$SEARCH_PATH/}" # get path to file relative to starting dir.
         REL_PATH="${REL_PATH%$(basename $FILE)}" # cut file name from end
         mkdir -p "$DEST_FOLDER/$REL_PATH" && cp -a "$FILE" "$DEST_FOLDER/$REL_PATH"
      elif [ $OPER_MODE -eq $COPY_FLAT ]; then
         DESIRED_PATH="$DEST_FOLDER/$(basename $FILE)"
         CORRECTED_PATH=$(correctForPathConflict "$DESIRED_PATH")
         cp -a "$FILE" "$CORRECTED_PATH"
      elif [ $OPER_MODE -eq $MOVE_MIRR ]; then
         REL_PATH="${FILE#$SEARCH_PATH/}"
         REL_PATH="${REL_PATH%$(basename $FILE)}"
         mkdir -p "$DEST_FOLDER/$REL_PATH" && mv "$FILE" "$DEST_FOLDER/$REL_PATH"
      elif [ $OPER_MODE -eq $MOVE_FLAT ]; then
         DESIRED_PATH="$DEST_FOLDER/$(basename $FILE)"
         CORRECTED_PATH=$(correctForPathConflict "$DESIRED_PATH")
         mv "$FILE" "$CORRECTED_PATH"
      elif [ $OPER_MODE -eq $DELETE ]; then
         DESIRED_PATH="$TRASH_FOLDER/$(basename $FILE)"
         CORRECTED_PATH=$(correctForPathConflict "$DESIRED_PATH")
         mv "$FILE" "$CORRECTED_PATH"
      else # print mode or unknown mode
         echo $FILE
      fi
      let FOUND+=1
   fi
done

if [ $FOUND -eq 1 ]; then
   STR_FILES="file"
fi

if ([ $OPER_MODE -eq $COPY_MIRR ] || [ $OPER_MODE -eq $COPY_FLAT ]); then
   mypr "Copied $FOUND $STR_FILES to destination."
elif ([ $OPER_MODE -eq $MOVE_MIRR ] || [ $OPER_MODE -eq $MOVE_FLAT ]); then
   mypr "Moved $FOUND $STR_FILES to destination."
elif [ $OPER_MODE -eq $PRINT ]; then
   mypr "Found $FOUND $STR_FILES."
else
   mypr "Moved $FOUND $STR_FILES to Trash."
fi