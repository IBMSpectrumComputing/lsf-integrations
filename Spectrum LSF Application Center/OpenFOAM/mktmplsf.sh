#!/bin/sh
if [ -z $LSF_LIBDIR ] ; then
   echo "Source your LSF profile (profile.lsf or cshrc.lsf) and run this script again"
   exit 1
fi

TMPDIR=lsf
LIB_LIST="libbat.a libbat.so liblsf.a liblsf.so"

# Build directory structure
mkdir $TMPDIR
mkdir $TMPDIR/10.1
mkdir $TMPDIR/10.1/include
mkdir $TMPDIR/10.1/include/lsf
mkdir $TMPDIR/10.1/lib
mkdir $TMPDIR/conf

# Copy files
for LIB in $LIB_LIST
do
   cp -p $LSF_LIBDIR/$LIB $TMPDIR/10.1/lib
done

cp -p $LSF_LIBDIR/../../include/lsf/ls[bf]*.h $TMPDIR/10.1/include/lsf

echo "LSF_INCLUDEDIR=/tmp/lsf/10.1/include" > $TMPDIR/conf/lsf.conf
