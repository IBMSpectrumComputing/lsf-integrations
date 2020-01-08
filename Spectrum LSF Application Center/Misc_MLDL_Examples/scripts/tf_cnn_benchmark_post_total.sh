#!/bin/bash

if [ -z "$LS_EXECCWD" ]; then
        exit 0
fi

tot="total images/sec:"
stdfile=$LS_EXECCWD/stdout*.txt
postfile=$LS_EXECCWD/total.txt

echo -n "Grand $tot " >> $postfile
grep "$tot" $stdfile | awk '{ sum += $3 } END { print sum }' >> $postfile
