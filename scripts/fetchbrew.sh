#!/bin/sh -e
ZIPFILE="Sources/App/Resources/appfair-homebrew.zip"
echo "Fetching latest brew from https://github.com/App-Fair/appfair-homebrew (be sure to first merge from upstream)"
printf "Hit return to continue…"
read READY

curl -fSL -o ${ZIPFILE} https://github.com/App-Fair/appfair-homebrew/zipball/HEAD 
# need to also delete the test fixtures because they contain un-signed binaries that will cause the notary service to fail
ls -lah ${ZIPFILE}
echo "Removing unneeded test support files"
zip -q -d ${ZIPFILE} '*/Library/Homebrew/test/support/**'
#zip -q -d ${ZIPFILE} '*/docs/**'
ls -lah ${ZIPFILE}
