#!/usr/bin/env bash

# Help function
# Token has to be the first argument.
# "d" and "directory" have one required argument.
# "t" and "build-type" have one required argument.
function echo_help {
  echo "
$(basename "$0") <odevio_api_key> [-d|--directory <directory/>] [-t|--build-type ad-hoc|publication|validation]

USAGE:
    Script used in CI/CD integration with Odevio.

OPTIONS:
    -h|--help           Shows this help message.
    -d|--directory      Specifies the directory of the flutter project in the current directory. It has to end with '/'. Default: './'
    -t|--build-type     Selects the build type used on Odevio. Choices are: 'ad-hoc', 'publication', 'validation'.
                        Default: 'publication'
    -k|--app-key           Specifies the app key of the application on Odevio.
    -fv|--flutter-version   Specifies the flutter version used on Odevio.
    -iv|--minimal-ios-version   Specifies the minimal iOS version used on Odevio. If not specified, the minimal iOS version will be read from the .odevio file.
    -m|--mode           Specifies the mode used on Odevio.
                        Choices are: 'debug', 'profile', 'release'.
    -tg|--target        Specifies the target used on Odevio.
    -f|--flavor         Specifies the flavor used on Odevio.
"
}

# Handling arguments of the script

if [[ "$#" -lt 1 ]]; then
    echo_help ; exit 1
fi

# The first argument of the script has to be the Token that is used to
# authenticate the different request for Odevio
TOKEN=$1
shift

# The optional argument -d|--directory provides the FLUTTER_DIRECTORY.
# Make sure that the path ends with "/". Default="./"
FLUTTER_DIRECTORY="./"
# The optional argument -t|--build-type provides the BUILD_TYPE.
# Default="publication"
BUILD_TYPE="publication"

while (( "$#" )); do
  case "$1" in
    -h|--help)
        echo_help
        exit 0
        ;;
    -d|--directory)
        FLUTTER_DIRECTORY=$2
        shift 2
        ;;
    -t|--build-type)
        case "$2" in
            "ad-hoc"|"publication"|"validation")
                BUILD_TYPE=$2
                shift 2
                ;;
            *)
                >&2 echo "Error: Invalid build type. Must be one of: ad-hoc, publication, validation."
                echo_help
                exit 1
                ;;
        esac
        ;;
    -k|--app-key)
        APP_KEY="$2"; shift 2 ;;
    -fv|--flutter-version) FLUTTER_VERSION="$2"; shift 2 ;;
    -iv|--minimal-ios-version) MINIMAL_IOS_VERSION="$2"; shift 2 ;;
    -m|--mode)
        case "$2" in
                "debug"|"profile"|"release")
                    MODE=$2
                    shift 2
                    ;;
                *)
                    >&2 echo "Error: Invalid mode type. Must be one of: debug, profile, release"
                    echo_help
                    exit 1
                    ;;
            esac
            ;;
    -tg|--target) TARGET="$2"; shift 2 ;;
    -f|--flavor) FLAVOR="$2"; shift 2 ;;
    *)
        >&2 echo "Error: Invalid argument $1"
        echo_help
        exit 1
        ;;
  esac
done

WORKING_DIRECTORY="$(pwd)/$FLUTTER_DIRECTORY"
BASE_URL="https://odevio.com"

# FUNCTIONS

function check_flutter_project {
    echo -e "\n*** Check that the project is a flutter project ***"

    # Check if WORKING_DIRECTORY, lib/ folder and pubspec.yaml file exist
    if [[ ! -d "$1" || ! -d "${1}lib" || ! -f "${1}pubspec.yaml" ]]; then
        echo "The FLUTTER_DIRECTORY variable does not lead to a flutter directory. Verify the -d|--directory argument."
        exit 1
    else
        echo "Flutter directory detected."
    fi

    echo "[DONE]"
}

function check_token {
    echo -e "\n*** Check token ***"

    STATUS_CODE_TOKEN=$(curl --silent --output /dev/null --write-out "%{http_code}" --header "Authorization: Token $1" "${BASE_URL}/api/v1/my-account/")
    if [ "$STATUS_CODE_TOKEN" -ne 200 ]; then
        >&2 echo "Error: HTTP status code is not 200"
        echo "The token is not correct"
        exit 1
    else
        echo "The token is correct"
    fi

    echo "[DONE]"
}

function read_pubspec_file {
    echo -e "\n*** Read pubspec.yaml file ***"

    # Open pubspec.yaml file if it exists and read the application version and the build number
    if [ -f pubspec.yaml ]; then
        echo "Info: pubspec.yaml file found."
        # Find the pattern "version: 1.2.3+4" in the content of the file. The numbers can change and are not always 1-digit.
        # The variable APP_VERSION will be set to the match of "1.2.3" and BUILD_NUMBER to "4"
        while IFS= read -r line || [[ -n "$line" ]]
        do
            if [[ $line =~ ^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+) ]]; then
                APP_VERSION=${BASH_REMATCH[1]}
                BUILD_NUMBER=${BASH_REMATCH[2]}
                break
            fi
        done < pubspec.yaml
    else
        >&2 echo -e "Error: Missing pubspec.yaml file.\nThis file is necessary as it contains the application version and the build number."
        exit 1
    fi

    # Check that the variables APP_VERSION and BUILD_NUMBER are set
    if [[ -z "$APP_VERSION" ]] || [[ -z "$BUILD_NUMBER" ]]; then
        >&2 echo "Error: APP_VERSION and BUILD_NUMBER were not found in the pubspec.yaml file."
        exit 1
    fi

    echo "Info: APP_VERSION and BUILD_NUMBER found in the pubspec.yaml file."

    echo "[DONE]"
}

function read_odevio_file {
    echo -e "\n*** Read .odevio file ***"

    # Open .odevio file if it exists and read the build settings
    if [ -f .odevio ]; then
        echo "Info: Command line arguments override the values present in the .odevio file."
        while IFS= read -r line || [[ -n "$line" ]]
        do
            # Ignore lines starting with # or empty lines
            if [[ $line == \#* ]] || [[ -z "$line" ]]; then
                continue
            fi

            IFS='=' read -r key value <<< "$line"

            # Remove leading and trailing whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)

            case "$key" in
                "app-key") APP_KEY=${APP_KEY:-$value} ;;
                "build-type") ;;  # Ignore "build-type" key -> Given as argument or default value
                "flutter") FLUTTER_VERSION=${FLUTTER_VERSION:-$value} ;;
                "minimal-ios-version") MINIMAL_IOS_VERSION=${MINIMAL_IOS_VERSION:-$value} ;;
                "app-version") ;;  # Ignore "app-version" key -> Read from pubspec.yaml
                "build-number") ;;  # Ignore "build-number" key -> Read from pubspec.yaml
                "mode") MODE=${MODE:-$value} ;;
                "target") TARGET=${TARGET:-$value} ;;
                "flavor") FLAVOR=${FLAVOR:-$value} ;;
                "tunnel-port") ;;  # Ignore "tunnel-port" key
                "tunnel-host") ;;  # Ignore "tunnel-host" key
                "tunnel-remote-port") ;;  # Ignore "tunnel-remote-port" key
                "no-progress") ;;  # Ignore "no-progress" key
                "no-flutter-warning") ;;  # Ignore "no-flutter-warning" key
                *) echo "Warning: unknown option '$key' in .odevio file" ;;
            esac
        done < .odevio
    else
        echo "Info: .odevio file not found"
    fi

    # Check that the variables APP_KEY and FLUTTER_VERSION are set
    if [[ -z "$APP_KEY" ]] || [[ -z "$FLUTTER_VERSION" ]]; then
        >&2 echo -e "\nError: APP_KEY and FLUTTER_VERSION must be set in the .odevio file or given as arguments."
        exit 1
    fi

    echo "[DONE]"
}

function print_configuration {
    echo -e "\n*** Configuration for this build ***\n"

    echo "APP_KEY = $APP_KEY"
    echo "FLUTTER_VERSION = $FLUTTER_VERSION"
    echo "BUILD_TYPE = $BUILD_TYPE"
    echo "FLUTTER_DIRECTORY = $FLUTTER_DIRECTORY"
    echo "APP_VERSION = $APP_VERSION"
    echo "BUILD_NUMBER = $BUILD_NUMBER"
    echo "MINIMAL_IOS_VERSION = $MINIMAL_IOS_VERSION"
    echo "MODE = $MODE"
    echo "TARGET = $TARGET"
    echo "FLAVOR  = $FLAVOR"

    echo -e "\n[DONE]"
}

# This function requires the variable APP_KEY, FLUTTER_VERSION, APP_VERSION and BUILD_NUMBER to be set.
function start_build {
    echo -e "\n*** Start the build ***"

    # Initialize arrays
    declare -a ignoreDirectories
    declare -a ignoreFiles

    # Open .odevioignore file if it exists and read the directories and files to ignore
    if [ -f .odevioignore ]; then
        while IFS= read -r line || [[ -n "$line" ]]
        do
            # Ignore lines starting with # or empty lines
            if [[ $line == \#* ]] || [[ -z "$line" ]]; then
                continue
            fi

            # If line ends with /, it's a directory. Else, it's a file.
            if [[ $line == */ ]]; then
                ignoreDirectories+=("$line*")  # Add * add the end of the directories for the future zip command
            else
                ignoreFiles+=("$line")
            fi
        done < .odevioignore
    fi

    # Create .app.zip
    rm -f .app.zip
    zip -qr ./.app.zip . -x \
        build/\* windows/\* linux/\* .dart_tool/\* .pub-cache/\* .pub/\* .git/\* .gradle/\* .fvm/\* \
        source.zip .app.zip odevio.patch \
        "${ignoreDirectories[@]}" \
        "${ignoreFiles[@]}"

    # Check that the required variables are set
    if [[ -z "$1" ]] || [[ -z "$APP_KEY" ]] || [[ -z "$FLUTTER_VERSION" ]] || [[ -z "$APP_VERSION" ]] || [[ -z "$BUILD_NUMBER" ]]; then
        >&2 echo "Error: TOKEN or APP_KEY or FLUTTER_VERSION or APP_VERSION or BUILD_NUMBER is empty."
        exit 1
    fi

    # Start the build
    CMD="curl -s -w '\n%{http_code}' \
                -F 'build_type=$BUILD_TYPE' \
                -F 'application=$APP_KEY' \
                -F 'flutter_version=$FLUTTER_VERSION' \
                -F 'app_version=$APP_VERSION' \
                -F 'build_number=$BUILD_NUMBER' \
                -F source=@.app.zip"

    # Add optional parameters if they are set
    [[ -n "$MINIMAL_IOS_VERSION" ]] && CMD+=" -F 'min_sdk=$MINIMAL_IOS_VERSION'"
    [[ -n "$MODE" ]] && CMD+=" -F 'mode=$MODE'"
    [[ -n "$TARGET" ]] && CMD+=" -F 'target=$TARGET'"
    [[ -n "$FLAVOR" ]] && CMD+=" -F 'flavor=$FLAVOR'"

    # Add the end of the command
    CMD+=" --header 'Authorization: Token $1' \
          --header 'Platform: cicd' \
          '${BASE_URL}/api/v1/builds/'"

    # Execute the command and store the response
    RESPONSE=$(eval "$CMD")

    rm -f .app.zip

    HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
    RESPONSE_BODY=$(echo "$RESPONSE" | sed '$ d')

    if [ "$HTTP_STATUS" -ne 201 ]; then
        >&2 echo -e "Error: HTTP status code is not 201\nThe build is not started"
        echo "$RESPONSE_BODY"
        exit 1
    fi

    BUILD_KEY=$(echo "$RESPONSE_BODY" | grep -o '"key":"[^"]*"' | sed 's/"key":"//;s/"//')
    # BUILD_KEY=$(echo "$RESPONSE_BODY" | jq -r '.key')
    echo "The build key is: $BUILD_KEY"

    echo "[DONE]"
}

# This function requires the variable BUILD_KEY to be set.
function subscribe_to_sse {
    echo -e "\n*** Subscribe to SSE to listen to changes of the Odevio build ***"

    STATUS_CODE="created"
    echo "Looking for available instance."

    # Subscribe to SSE of the build
    while IFS= read -r line
    do
        # Ignore blank lines and the lines that does not start with "event: " or "data: "
        if [[ -z "$line" || "$line" != event:* && "$line" != data:* ]]; then
            continue
        fi

        # Split the line into key and value
        IFS=': ' read -r key value <<< "$line"

        # If the key is event, we store the value in a variable $EVENT,
        # else if the key is data, we do things depending on the previous $EVENT, then we reset $EVENT
        if [[ "$key" == "event" ]]; then
            EVENT="$value"
        elif [[ "$key" == "data" && "$EVENT" ]]; then
            DATA="$value"
            if [[ "$EVENT" == "status" ]]; then
                # Remove leading and trailing spaces and the double quotes around the $DATA
                STATUS_CODE=$(echo "$DATA" | tr -d '"' | xargs)
                case "$STATUS_CODE" in
                    "created") echo "Looking for available instance." ;;
                    "waiting_instance") echo "No instance available at the moment. Waiting for one to be free." ;;
                    "in_progress") echo "Instance found. Build is in progress." ;;
                    "succeeded") echo "Success."; break ;;
                    "failed") echo "Failed."; break ;;
                    "stopped") echo "Stopped."; break ;;
                    *) break ;;
                esac
            elif [[ "$EVENT" == "substatus" ]]; then
                if [[ "$STATUS_CODE" == "created" ]]; then
                    STATUS_CODE="in_progress"
                    echo "Instance found. Build is in progress."
                fi
                
                SUBSTATUS=$(echo "$DATA" | tr -d '"' | xargs)
                case "$SUBSTATUS" in
                    "starting_instance") echo "Starting instance..." ;;
                    "preparing_build") echo "Preparing build..." ;;
                    "building") echo "Building..." ;;
                    "getting_result") echo "Getting result..." ;;
                    "publishing") echo "Publishing..." ;;
                esac
            fi

            # Reset EVENT
            EVENT=""
        fi
    done < <(curl --no-buffer -s -H "Authorization: Token $1" -H "Accept: text/event-stream" -H "cache-control: no-cache" "${BASE_URL}/events/builds/$BUILD_KEY/logs")

    echo "[DONE]"
}

# This function requires the variable BUILD_KEY to be set.
# DEPRECATED
function subscribe_to_build {
    echo -e "\n*** Retrieve build every 20s to listen to changes of the Odevio build ***"

    PREV_STATUS_CODE="created"
    echo "Looking for available instance."

    LOOP_CONDITION=true
    while $LOOP_CONDITION;
    do
        # Sleeps for 20 seconds
        sleep 20s;

        # Fetch current build status
        RESPONSE=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Token $1" \
            "${BASE_URL}/api/v1/builds/$BUILD_KEY/")

        HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
        RESPONSE_BODY=$(echo "$RESPONSE" | sed '$ d')

        if [ "$HTTP_STATUS" -ne 200 ]; then
            >&2 echo -e "Error: HTTP status code is not 200\nImpossible to retrieve the details of the current build"
            exit 1
        fi

        STATUS_CODE=$(echo "$RESPONSE_BODY" | grep -o '"status_code":"[^"]*"' | sed 's/"status_code":"//;s/"//')
        # echo "Status code is: $STATUS_CODE"

        if [ "$PREV_STATUS_CODE" != "$STATUS_CODE" ]; then
            case "$STATUS_CODE" in
                "created") echo "Looking for available instance." ;;
                "waiting_instance") echo "No instance available at the moment. Waiting for one to be free." ;;
                "in_progress") echo "Instance found. Build is in progress." ;;
                "succeeded") echo "Success."; LOOP_CONDITION=false ;;
                "failed") echo "Failed."; LOOP_CONDITION=false ;;
                "stopped") echo "Stopped."; LOOP_CONDITION=false ;;
                *) LOOP_CONDITION=false ;;
            esac
        fi

        PREV_STATUS_CODE=$STATUS_CODE
    done

    echo "[DONE]"
}

# This function requires the variable BUILD_KEY and STATUS_CODE to be set.
function handling_finished_build {
    echo -e "\n*** Handling finished build ***"

    if [[ "$STATUS_CODE" != "succeeded" ]]; then
        echo "Odevio build with key $BUILD_KEY has failed."
        exit 1
    fi

    echo "Odevio build with key $BUILD_KEY has succeeded."

    # If the BUILD_TYPE is "ad-hoc", we fetch the IPA file
    if [[ "$BUILD_TYPE" == "ad-hoc" ]]; then
        RESPONSE=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: Token $1" \
            "${BASE_URL}/api/v1/builds/$BUILD_KEY/ipa/")

        HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
        RESPONSE_BODY=$(echo "$RESPONSE" | sed '$ d')

        if [[ "$HTTP_STATUS" -ne 200 ]]; then
            >&2 echo -e "Error: HTTP status code is not 200\nImpossible to retrieve the IPA url of the current build"
            exit 1
        fi

        IPA_URL=$(echo "$RESPONSE_BODY" | grep -o '"url":"[^"]*"' | sed 's/"url":"//;s/"//')
        echo "The url of the IPA from Odevio is: $IPA_URL"

        # Write the IPA_URL variable in the text file odevio_ipa_url.txt
        echo "$IPA_URL" > odevio_ipa_url.txt
        echo "This IPA url has been written into the file 'odevio_ipa_url.txt'"
    fi

    echo "[DONE]"
}

# Execution of the main functions

check_flutter_project $WORKING_DIRECTORY
cd $WORKING_DIRECTORY
check_token $TOKEN
read_pubspec_file
read_odevio_file
print_configuration
start_build $TOKEN
subscribe_to_sse $TOKEN
handling_finished_build $TOKEN

exit 0
