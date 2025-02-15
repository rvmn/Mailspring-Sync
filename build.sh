#!/bin/bash
#
# This script is run by Travis on Mac and Linux to build and package mailsync.
# Windows uses ./build.cmd.
#
export MAILSYNC_DIR=$( cd $(dirname $0) ; pwd -P );
export APP_ROOT_DIR="$MAILSYNC_DIR/../app"
export APP_DIST_DIR="$APP_ROOT_DIR/dist"
export DEP_BUILDS_DIR=/tmp/mailsync-build-deps-v2 # Note: also referenced in CMakeLists

set -e
mkdir -p "$APP_DIST_DIR"

if [[ "$OSTYPE" == "darwin"* ]]; then
  cd "$MAILSYNC_DIR"
  gem install xcpretty;
  set -o pipefail && xcodebuild -scheme mailsync -configuration Release;

  # the xcodebuild copies the build products to the APP_ROOT_DIR and codesigns
  # them for us. We just need to tar them up and move them to the artifacts folder
  cd "$APP_ROOT_DIR"
  if [ -e "mailsync.dSYM.zip" ]; then
    tar -czf "$APP_DIST_DIR/mailsync.tar.gz" mailsync.dSYM.zip mailsync
  else
    tar -czf "$APP_DIST_DIR/mailsync.tar.gz" mailsync
  fi

elif [[ "$OSTYPE" == "linux-gnu" ]]; then
  # we cache this directory between builds to make CI faster.
  # if it exists, just run make install again, otherwise pull
  # the libraries down and build from source.
  if [ ! -d "$DEP_BUILDS_DIR" ]; then
    mkdir "$DEP_BUILDS_DIR"
  fi
  
  # install all dependencies
  sudo apt install libc-ares-dev libicu-dev libctemplate-dev libtidy-dev uuid-dev libxml2-dev libssl-dev libsasl2-dev liblzma-dev nano curl libcurl4-openssl-dev gcc-5 g++-5 cmake autoconf git libtool -y
  
  # remove test as they require libicule which is not available
  rm -rf Vendor/mailcore2/*test*
  mkdir Vendor/mailcore2/tests
  mkdir Vendor/mailcore2/tests-ios
  mkdir Vendor/mailcore2/unittest
  
  echo "Building and installing libetpan..."
  cd "$MAILSYNC_DIR/Vendor/libetpan"
  ./autogen.sh --with-openssl=/opt/openssl
  make -t >/dev/null
  sudo make install prefix=/usr >/dev/null

  # build mailcore2
  echo "Building mailcore2..."
  cd "$MAILSYNC_DIR/Vendor/mailcore2"
  mkdir -p build
  cd build
  cmake ..
  make -t

  # build mailsync
  echo "Building Mailspring MailSync..."
  cd "$MAILSYNC_DIR"
  cmake .
  make -t

  # copy build product into the client working directory.
  cp "$MAILSYNC_DIR/mailsync" "$APP_ROOT_DIR/mailsync.bin"

  # copy libsasl2 (and potentially others - just add to grep expression)
  # into the target directory since we don't want to depend on installed version
  ldd "$MAILSYNC_DIR/mailsync" | grep "=> /" | awk '{print $3}' | grep "libsasl2" | xargs -I '{}' cp -v '{}' "$APP_ROOT_DIR"

  # copy libsasl2's modules into the target directory because they're all shipped separately
  # (We set SASL_PATH below so it finds these.)
  cp /usr/lib/aarch64-linux-gnu/sasl2/* "$APP_ROOT_DIR"

  printf "#!/bin/bash\nset -e\nset -o pipefail\nSCRIPTPATH=\"\$( cd \"\$(dirname \"\$0\")\" >/dev/null 2>&1 ; pwd -P )\"\nSASL_PATH=\"\$SCRIPTPATH\" LD_LIBRARY_PATH=\"\$SCRIPTPATH;\$LD_LIBRARY_PATH\" \"\$SCRIPTPATH/mailsync.bin\" \"\$@\"" > "$APP_ROOT_DIR/mailsync"
  chmod +x "$APP_ROOT_DIR/mailsync"

  # Zip this stuff up so we can push it to S3 as a single artifacts
  cd "$APP_ROOT_DIR"
  tar -czf "$APP_DIST_DIR/mailsync.tar.gz" *.so* mailsync mailsync.bin --wildcards
else
  echo "Mailsync does not build on $OSTYPE yet.";
fi
