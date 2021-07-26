#!/bin/bash

# Find By Content
# A program for searching through files' content. Matching files can be printed to screen
# (matching excerpts only), copied to another destination, or moved to the Trash. Usage
# details below.
# Recommended width:
# |---------------------------------------------------------------------------------------|

# Set the field separator to a newline to avoid spaces in paths breaking our
# variable-setting
IFS="
"


## GLOBALS ##
SEARCH_DIR=
SEARCH_FILES="^.*$"
declare -a SEARCH_TERMS_PLUS=()
declare -a SEARCH_TERMS_MINUS=()
WITHIN=0
CASE_INS=""
MODE=0
PRINT=1
COPY=2
DELETE=3
DEST_DIR=
THE_TIME=$(date "+%Y-%m-%d--%H-%M-%S")
TRASH_FOLDER="$HOME/.Trash/Deleted files ($THE_TIME)"
LOOKBACK=0
LOOKAHEAD=0
SHOW_LINE_NUM=0
QUIET=0
CHECKED=0
FOUND=0
declare -a PLUS_ARGS=()
declare -a MINUS_ARGS=()
NUM_ARGS=0
STR_FILES="files"
STR_TERMS="terms"
cols=$(tput cols)
bold=$(tput bold)
normal=$(tput sgr0)


## UTILITY FUNCTIONS ##
# An exit message which will print even if user force-quits
function niceExit()
{
   if [ $NUM_ARGS -eq 1 ]; then
      STR_TERMS="term"
   fi

   if [ $CHECKED -eq 1 ]; then
      STR_FILES="file"
   fi
   echo
   echo -n "Checked $CHECKED $STR_FILES. "

   if [ $FOUND -eq 1 ]; then
      STR_FILES="file"
   else
      STR_FILES="files"
   fi

   if [ $MODE -eq $PRINT ]; then
      echo "Found search $STR_TERMS in $FOUND $STR_FILES."
   elif [ $MODE -eq $COPY ]; then
      echo "Copied $FOUND matching $STR_FILES."
   else
      echo "Deleted $FOUND matching $STR_FILES."
   fi

   exit
}

trap niceExit INT

# Print usage of program; use this margin for help text:
# |----------------------------------------------------------------------------|
function printHelp()
{
   echo -n ${bold}
   echo "--Find By Content--" | fmt -w $cols -c
   echo -n ${normal}
   cat << EOF
You can supply the following parameters, in any order:
${bold}Required:${normal}
  --dir [dir]: The directory which should be recursively searched.
  --find [term]: A search term (regex pattern) to look for in these files. You
    can use --find as many times as you want to add search terms, and any file
    that matches one or more of the terms will be returned.
  ${bold}(pick one:)${normal}
  --print: Print the matches within each file to screen.
  --copy-to [dir]: The directory into which to copy matching files.
  --delete: Delete the matching files (sends files to Trash).
${bold}Optional:${normal}
  --in-files [name]: The names of the files to be searched, as a regex pattern.
    For example, "\.[ch]$" would search files ending in ".c" or ".h"; "\.[c]+$"
    would search ".c" and ".cc" files. Otherwise all files are searched.
  --omit [term]: A search term (regex pattern) to cut out of the results
    obtained by searching for the --find term(s). You can use --omit as many
    times as you want to create multiple cut-outs from the combined search
    results of all the --find operations.
  --within [num]: Any two hits must be within this many lines.
  --insens: Perform content searches with case-insensitivity.
  ${bold}('print' mode only:)${normal}
  --above [num]: Show this many lines before the matching content.
  --below [num]: Show this many lines after the matching content.
  --line-num: Print the line number before each line's content.
  --quiet: Minimal output; no header line with the name and number of matches
    in each file. Instead all content matches are printed back to back.
EOF
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
      exit
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
      echo "Error: Cannot find a place in $(dirname $1) for $(basename $1)."
      exit
   else
      echo "$TEST_PATH"
   fi
}


## ARGUMENT PROCESSING ##
# Show help if called without enough args
if [ "$#" -lt 5 ]; then
   printHelp
   exit
fi

# Look for known options as long as there are more arguments to process
while (( "$#" )); do
   case "$1" in
      --dir )      SEARCH_DIR="$2"; shift 2;;
      --in-files ) SEARCH_FILES="$2"; shift 2;;
      --find )     SEARCH_TERMS_PLUS+=("$2"); let NUM_ARGS+=1; shift 2;;
      --omit )     SEARCH_TERMS_MINUS+=("$2"); let NUM_ARGS+=1; shift 2;;
      --within )   WITHIN="$2"; shift 2;;
      --insens )   CASE_INS="-i"; shift;;
      --print )    MODE=$PRINT; shift;;
      --copy-to )  MODE=$COPY; DEST_DIR="$2"; shift 2;;
      --delete )   MODE=$DELETE; shift;;
      --above )    LOOKBACK="$2"; shift 2;;
      --below )    LOOKAHEAD="$2"; shift 2;;
      --line-num ) SHOW_LINE_NUM=1; shift;;
      --quiet )    QUIET=1; shift;;
      * )          echo "Error: Invalid argument '$1' detected."; exit;;
   esac
done

# Safety checks
if [ -z "$SEARCH_DIR" ]; then
   echo "You didn't specify a pattern of file name to search in using --dir! Aborting."
   exit
fi

if [ ! -d "$SEARCH_DIR" ]; then
   echo "Directory $SEARCH_DIR does not exist! Aborting."
   exit
fi

if [ "${#SEARCH_TERMS_PLUS[@]}" -lt 1 ]; then
   echo "You didn't specify anything to search for using --find! Aborting."
   exit
fi

if [ $MODE -eq 0 ]; then
   echo "You didn't specify a mode with --print, --copy-to, or --delete! Aborting."
   exit
fi

if [ $MODE -eq $COPY ] && [ ! -d "$DEST_DIR" ]; then
   echo "When using this program in copy mode, you need to specify a destination directory after --copy-to. Aborting."
   exit
fi

if [ $MODE -eq $DELETE ]; then
   mkdir "$TRASH_FOLDER"
   if [ ! -d "$TRASH_FOLDER" ]; then
      echo "Could not create the folder \"$TRASH_FOLDER\". Aborting."
      exit
   fi
fi

# Build additive grep query from patterns that user supplied via --find
for PLUS in "${SEARCH_TERMS_PLUS[@]}"; do
   PLUS_ARGS+=("-e${PLUS}")
done

# Build subtractive grep query from patterns that user supplied via --omit
MINUS_ARGS+=("echo \$RESULT")
for MINUS in "${SEARCH_TERMS_MINUS[@]}"; do
   MINUS_ARGS+=("| egrep $CASE_INS -v $MINUS")
done


## MAIN PROGRAM ##
for FN in `find "$SEARCH_DIR" | egrep $SEARCH_FILES`; do
   if [ -d "$FN" ]; then
      continue
   fi

   let CHECKED+=1

   # Get result of all plus terms, with accompanying line numbers
   declare -a RESULTS_PLUS=($(cat "$FN" | egrep $CASE_INS -n ${PLUS_ARGS[@]}))

   # Skip file if we got no results
   RESULT_CHARS=0
   RESULT_CHARS=`echo -n "${RESULTS_PLUS[@]}" | wc -c | tr -d '[:space:]'`
   if [ $RESULT_CHARS -lt 2 ]; then
      continue
   fi

   # Get result of running plus results against all --omit terms
   declare -a RESULTS_MINUS=()
   for RESULT in "${RESULTS_PLUS[@]}"; do
      RESULTS_MINUS+=($(eval "${MINUS_ARGS[@]}"))
   done

   # Evaluate if anything's left
   RESULT_CHARS=`echo -n "${RESULTS_MINUS[@]}" | wc -c | tr -d '[:space:]'`
   if [ $RESULT_CHARS -gt 1 ]; then
      # Save line numbers from grep results in FINAL_LINES
      declare -a RES_LINES=()
      for RESULT in "${RESULTS_MINUS[@]}"; do
         RES_LINES+=(${RESULT%%:*}) # get everything before first ':'
      done

      # If two consecutive hits have more than WITHIN lines between them, ignore file
      WITHIN_EXCEEDED=0
      if [ $WITHIN -gt 0 ]; then
         LAST_NUM=${RES_LINES[0]}
         for LINE in "${RES_LINES[@]}"; do
            if [ $((LINE - LAST_NUM)) -gt $WITHIN ]; then
               WITHIN_EXCEEDED=1
               break
            else
               LAST_NUM=$LINE
            fi
         done
      fi
      if [ $WITHIN_EXCEEDED -eq 1 ]; then
         continue
      fi

      # The file meets all our criteria
      let FOUND+=1

      # Print mode
      if [ $MODE -eq $PRINT ]; then
         # Print results header: "[magenta on]'File name'[magenta off] (x matches)"
         if [ $QUIET -eq 0 ]; then
            RESULT_COUNT=`echo "${#RESULTS_MINUS[@]}"`
            STR_MATCHES="matches"
            if [ $RESULT_COUNT -eq 1 ]; then
               STR_MATCHES="match"
            fi

            echo -e "\033[35m$FN\033[0m ($RESULT_COUNT $STR_MATCHES)"
         fi

         # Start off with just the line numbers for the final results
         declare -a FINAL_LINES=("${RES_LINES[@]}")

         # Add lookback line numbers to FINAL_LINES if lookback was requested
         if [ $LOOKBACK -gt 0 ]; then
            for LINE in "${RES_LINES[@]}"; do
               # Find line number for every line from 1 line to LOOKBACK lines back from each
               # result line, adding each number to FINAL_LINES
               for i in $(seq $LOOKBACK); do
                  LB_LINE=$((LINE - i))
                  if [ $LB_LINE -gt 0 ]; then # make sure we didn't back up past line 1
                     FINAL_LINES+=($LB_LINE)
                  fi
               done
            done
            # Sort FINAL_LINES' contents in numerical order, then pass through 'uniq' to
            # eliminate duplicate lines due to overlapping ranges in results
            FINAL_LINES=($(sort -g <<< "${FINAL_LINES[*]}" | uniq))
         fi

         # Add lookahead line numbers to FINAL_LINES if lookahead was requested
         if [ $LOOKAHEAD -gt 0 ]; then
            # Get and isolate number of lines in file
            NUM_LINES=$(wc -l $FN)
            NUM_LINES=$(echo $NUM_LINES | egrep -o --max-count=1 "[[:digit:]]* ")
            NUM_LINES=$(echo $NUM_LINES | tr -d '[:space:]')

            # As above, add the lines coming after each result line to FINAL_LINES
            for LINE in "${RES_LINES[@]}"; do
               for i in $(seq $LOOKAHEAD); do
                  LA_LINE=$((LINE + i))
                  if [ $LA_LINE -le $NUM_LINES ]; then # don't go past end of file
                     FINAL_LINES+=($LA_LINE)
                  fi
               done
            done
            # Sort FINAL_LINES' contents in numerical order, then pass through 'uniq' to
            # eliminate duplicate lines due to overlapping ranges in results
            FINAL_LINES=($(sort -g <<< "${FINAL_LINES[*]}" | uniq))
         fi

         # Print the lines whatse numbers are in FINAL_LINES
         for LINE_NUM in "${FINAL_LINES[@]}"; do
            THE_LINE=$(tail -n+$LINE_NUM "$FN" | head -n1)

            if [ $SHOW_LINE_NUM -eq 1 ]; then
               echo -n "$LINE_NUM: "
            fi

            # If we're also printing lines before or after the matching one, make the
            # surrounding lines gray
            if [ $LOOKBACK -gt 0 ] || [ $LOOKAHEAD -gt 0 ]; then
               WAS_ORIG=0
               for ORIG_LINE in "${RES_LINES[@]}"; do
                  if [ $ORIG_LINE -eq $LINE_NUM ]; then
                     echo "$THE_LINE"
                     WAS_ORIG=1
                     break
                  fi
               done
               if [ $WAS_ORIG -eq 0 ]; then
                  echo -e "\033[2m$THE_LINE\033[0m"
               fi
            else
               echo $THE_LINE
            fi
         done

         if [ $QUIET -eq 0 ]; then
            echo - - - - - - - -
         fi
      elif [ $MODE -eq $COPY ]; then
         DESIRED_PATH="$DEST_DIR/$(basename $FN)"
         CORRECTED_PATH=$(correctForPathConflict "$DESIRED_PATH")
         cp -a "$FN" "$CORRECTED_PATH"
      elif [ $MODE -eq $DELETE ]; then
         DESIRED_PATH="$TRASH_FOLDER/$(basename $FN)"
         CORRECTED_PATH=$(correctForPathConflict "$DESIRED_PATH")
         mv "$FN" "$CORRECTED_PATH"
      fi
   fi
done

niceExit