#!/bin/bash

export PATH=/home/px4build/gcc-arm-none-eabi-4_6-2012q2/bin:$PATH
BASE_DIR=/srv/www/px4.oznet.ch
BUILD_DIR=/home/px4build/build

COMMAND=$1

build () {
    BRANCH=$1
    TARGET=$2

    FIRMWARE_DIR="$TARGET/$BRANCH"  
    BUILD_RESULT="FAILED"
    DO_NOT_REPORT=false

    echo ""
    echo "*******************************************************************"
    echo "*** BUILDING: $TARGET $BRANCH (`pwd`)"
    echo "*******************************************************************"
    date
    echo $FIRMWARE_DIR 
    cd $FIRMWARE_DIR

    RETRY_ON_FAIL=false
    if [ -f force_retry ]; then
      # This will be used to prevent us retrying more than once.
      RETRY_ON_FAIL=true
    fi

    # Grab the latest from github to check if there have been any updates, otherwise we can exit.
    git pull origin $BRANCH | grep -q -v "Already up-to-date."
    if [ $? -eq 0 ] || [ "$COMMAND" == "force" ] || [ -f force ] || [ -f force_retry ]; then
      echo "Building..."
    else
      echo "No change - SKIPPING"
      return
    fi

    # Let the build status page know that the build is currently running.
    cp $BUILD_DIR/running.png $BASE_DIR/$TARGET/$BRANCH/build_status.png

    # Create the directories if they don't already exist
    mkdir -p $BASE_DIR/$TARGET/$BRANCH/bin

    # Probably not needed as we pulled above already, but what the hell.
    git pull origin $BRANCH
    if  [ $? -ne 0 ]; then
      echo "FAILED: git pull origin $TARGET:$BRANCH"
      return
    fi

    # The PX4 firmware requires NuttX. Go get the latest changes.
    if [ "$TARGET" == "px4" ]; then
      cd NuttX
      git pull origin
      git clean -d -f -x
      cd ..
    fi

    git clean -d -f -x

    DOMAIN="http://px4.oznet.ch"
    DATE=`date +%Y%m%d%H%M`    
    LOGFILE=$TARGET/$BRANCH/bin/$DATE-px4.log
    REPORT=/tmp/build-report.txt

    git log -n1 > $REPORT
    COMMIT_ID=`git log -n1 | grep commit`

    echo "" >> $REPORT
    echo "*******************************************************" >> $REPORT
    echo "" >> $REPORT

    cp $REPORT $BASE_DIR/$LOGFILE

    echo "Log: $DOMAIN/$LOGFILE" >> $REPORT
    echo "Binaries:" >> $REPORT

    if [ "$TARGET" == "px4" ]; then
      # Build the PX4 firmware
      echo "$DOMAIN/$TARGET/$BRANCH/bin/$DATE-px4fmu-v1_default.px4" >> $REPORT
      echo "$DOMAIN/$TARGET/$BRANCH/bin/$DATE-px4io-v1_default.bin" >> $REPORT
      echo "$DOMAIN/$TARGET/$BRANCH/bin/$DATE-px4fmu-v2_default.px4" >> $REPORT
      echo "$DOMAIN/$TARGET/$BRANCH/bin/$DATE-px4io-v1_default.bin" >> $REPORT
      echo "" >> $REPORT

      make archives && make -j8 >> $BASE_DIR/$LOGFILE 2>&1
    elif [ "$TARGET" == "px4flow" ]; then
      # Build the PX4Flow firmware.
      echo "$DOMAIN/$TARGET/$BRANCH/bin/$DATE-px4flow.px4" >> $REPORT
      make  >> $BASE_DIR/$LOGFILE 2>&1
    fi

    if [ $? -eq 0 ]; then
      cp $BUILD_DIR/pass.png $BASE_DIR/$TARGET/$BRANCH/build_status.png

      if [ "$TARGET" == "px4" ]; then
        # Copy and link to the FMU and IO firmware files.
        # V1
        cp Images/px4fmu-v1_default.px4 $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4fmu-v1_default.px4
        cp Images/px4io-v1_default.bin $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4io-v1_default.bin
        cp Build/px4io-v1_default.build/firmware.elf $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4io-v1_default.elf
        ln -sf $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4fmu-v1_default.px4 $BASE_DIR/$BRANCH/px4fmu-v1_default.px4
        ln -sf $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4io-v1_default.bin $BASE_DIR/$BRANCH/px4io-v1_default.bin

        # V2
        cp Images/px4fmu-v2_default.px4 $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4fmu-v2_default.px4
        cp Images/px4io-v2_default.bin $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4io-v2_default.bin
        cp Build/px4io-v2_default.build/firmware.elf $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4io-v2_default.elf
        ln -sf $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4fmu-v2_default.px4 $BASE_DIR/$TARGET/$BRANCH/px4fmu-v2_default.px4
        ln -sf $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4io-v2_default.bin $BASE_DIR/$TARGET/$BRANCH/px4io-v2_default.bin

      elif [ "$TARGET" == "px4flow" ]; then
        # Copy and link to the PX4Flow firmware file.
        cp ./px4flow.px4 $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4flow.px4
        ln -sf $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4flow.px4 $BASE_DIR/$TARGET/$BRANCH/px4flow.px4
        # and a link to it from the px4 branch directory (Lorenz wants it that way).
        ln -sf $BASE_DIR/$TARGET/$BRANCH/bin/$DATE-px4flow.px4 $BASE_DIR/px4/$BRANCH/px4flow.px4
      fi

      BUILD_RESULT="OK"

      echo "Last build: `date`" > $BASE_DIR/timestamp.html
    else
      cp $BUILD_DIR/fail.png $BASE_DIR/$TARGET/$BRANCH/build_status.png
      if [ $RETRY_ON_FAIL == false ]; then
        # In case of a build failure re-run the build one time only.
        touch force_retry
        # We want to try one more time before reporting a failure.
        DO_NOT_REPORT=true
      fi
    fi

    # Send out an Email with a summary of how things went.
    SUBJECT="[$BUILD_RESULT] PX4 Build - $TARGET:$BRANCH"
    if [ "$COMMAND" == "test" ] || [ $DO_NOT_REPORT == true ]; then
      EMAIL="sjwilks@gmail.com"
    else
      EMAIL="px4-continuous-build@googlegroups.com"
    fi
    EMAILMESSAGE="$REPORT"
    
    /usr/bin/mail -s "$SUBJECT ($COMMIT_ID)" "$EMAIL" < $EMAILMESSAGE
}

cd $BUILD_DIR

if test $(find lock -mmin +90); then
  echo "Stale lock file. Removing." 
  rm lock
fi

if [ -f lock ]; then
  # If a lock is in place then builds are probably still running.
  echo "Already running (remove $CWD/lock if this is not true)"
  exit
fi
touch lock

# First build all the PX4 firmware branches.
for t in 'master' 'beta' 'stable'; do
  build $t px4
  cd $BUILD_DIR
  sleep 5
done

# For the PX4Flow we will only build master
build master px4flow
cd $BUILD_DIR

COMMAND=""

# Clear the lock so the next round of builds can be run.
rm lock

