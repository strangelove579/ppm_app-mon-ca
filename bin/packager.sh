#!/bin/bash
# Build script for ppm_app
# !! Run this to wrap this code into the ppm_app.tar 
# Tar will be created here: /tmp/ppm_app.tar


SCRIPT=$(readlink -f $0)
BIN=$(dirname $SCRIPT)
PACKAGEHOME=$(dirname $BIN)


TS=$(date +"%m%d%Y%H%M%S")
TMPDIR=${PACKAGEHOME}_$TS
PKGTAR=/tmp/ppm_app.tar
mkdir $TMPDIR

echo "Moving package to temporary directory" 
/bin/cp -R $PACKAGEHOME/* $TMPDIR/

echo "Removing post-deploy flag file: ./bin/.is_deployed..."
cd $TMPDIR/bin
/bin/rm -f .is_deployed

echo "Removing post-deploy configs: ./config/tz.cfg ./config/.live_bo_processes.cfg..."
cd $TMPDIR/config
/bin/rm -f tz.cfg .live_bo_processes.cfg .boss_unverified

echo "Removing logs: ./log/*.log..."
cd $TMPDIR/log
/bin/rm -f *

echo "Done cleaning package"


echo "Creating package tarball..."
cd $TMPDIR
/bin/tar cf $PKGTAR ./
/bin/chmod 0777 $PKGTAR

/bin/rm -rf $TMPDIR
echo "Done. Package file created: /tmp/ppm_app.tar"

exit


