#!/bin/bash
set -e

JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
GRADLE="./gradlew testDebugUnitTest"
RESULTS_DIR="app/build/test-results/testDebugUnitTest"

function run_mutation {
    local ID=$1
    local TEST_CLASS=$2
    local FILE=$3
    local SED_PATTERN=$4
    local REVERT_PATTERN=$5
    
    echo "Running mutation $ID..."
    
    # Apply mutation using sed
    sed -i '' "$SED_PATTERN" "$FILE"
    
    # Run test
    set +e
    JAVA_HOME="$JAVA_HOME" $GRADLE --tests "*$TEST_CLASS*" > /dev/null 2>&1
    set -e
    
    # Revert mutation
    sed -i '' "$REVERT_PATTERN" "$FILE"
    
    # Extract failure
    XML_FILE=$(ls $RESULTS_DIR/TEST-*$TEST_CLASS*.xml | head -n 1)
    
    if grep -q "<failure" "$XML_FILE"; then
        TIME=$(grep "<testcase" "$XML_FILE" | grep "FAILED" -A 10 | grep -o 'time="[^"]*"' | head -1 | cut -d '"' -f 2)
        if [ -z "$TIME" ]; then
            TIME=$(grep "<testcase" "$XML_FILE" | grep -A 10 "<failure" | grep -B 10 "<failure" | grep -o 'time="[^"]*"' | head -1 | cut -d '"' -f 2)
        fi
        FAILURE=$(sed -n '/<failure/,/<\/failure>/p' "$XML_FILE" | sed -e 's/^[ \t]*//' | head -n 10)
        echo "Mutation $ID Result: RED (time=$TIME)"
        echo "$FAILURE"
        echo ""
    else
        echo "Mutation $ID Result: GREEN (Failed to produce RED)"
        echo ""
    fi
}

echo "=== M21 MUTATIONS ==="
run_mutation "M21-A" \
    "BackupSecurityTest" \
    "app/src/main/java/io/github/cidy02/kudos/backup/BackupImporter.kt" \
    "s/!isLoadableFont(payload)/false/" \
    "s/false/!isLoadableFont(payload)/"

# Mutation B: "reject only if the font is missing" instead of "never auto-select from an archive"
# (Wait, actually I can just use sed to change the readerFontId line to a conditional)
# Original code has NO readerFontId assignment.
# We will sed to add: if (settings.reader.readerFontId != "missing") prefs[Keys.ReaderFontId] = settings.reader.readerFontId
# Since it's multiline, we can just insert it after prefs[Keys.ReaderMode]
run_mutation "M21-B" \
    "SettingsRepositoryTest" \
    "app/src/main/java/io/github/cidy02/kudos/data/preferences/SettingsRepository.kt" \
    "/prefs\[Keys.ReaderMode\]/i\\
            if (settings.reader.readerFontId != \"missing\") prefs[Keys.ReaderFontId] = settings.reader.readerFontId" \
    "/if (settings.reader.readerFontId != \"missing\")/d"


echo "=== M2b MUTATIONS ==="
run_mutation "M2b-A" \
    "BackupRestoreSecurityTest" \
    "app/src/main/java/io/github/cidy02/kudos/backup/BackupMappers.kt" \
    "s/type.isEmpty()/false/" \
    "s/false/type.isEmpty()/"

# Mutation B: Allow unknown tombstone types
run_mutation "M2b-B" \
    "BackupRestoreSecurityTest" \
    "app/src/main/java/io/github/cidy02/kudos/backup/BackupMappers.kt" \
    "s/type \!in knownTypes/false/" \
    "s/false/type \!in knownTypes/"

# Full Suite
echo "=== RUNNING FULL SUITE (GREEN) ==="
set +e
JAVA_HOME="$JAVA_HOME" $GRADLE > /dev/null 2>&1
set -e

TOTAL_TESTS=0
TOTAL_FAILURES=0
TOTAL_ERRORS=0

for xml in $RESULTS_DIR/*.xml; do
    TESTS=$(grep -o 'tests="[0-9]*"' "$xml" | head -1 | cut -d '"' -f 2)
    FAILURES=$(grep -o 'failures="[0-9]*"' "$xml" | head -1 | cut -d '"' -f 2)
    ERRORS=$(grep -o 'errors="[0-9]*"' "$xml" | head -1 | cut -d '"' -f 2)
    
    TOTAL_TESTS=$((TOTAL_TESTS + ${TESTS:-0}))
    TOTAL_FAILURES=$((TOTAL_FAILURES + ${FAILURES:-0}))
    TOTAL_ERRORS=$((TOTAL_ERRORS + ${ERRORS:-0}))
done

echo "tests=$TOTAL_TESTS failures=$TOTAL_FAILURES errors=$TOTAL_ERRORS"
