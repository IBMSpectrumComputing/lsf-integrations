#!/bin/bash
#
# Licensed Materials - Property of IBM
# 5725-G82
# @ Copyright IBM Corp. 2009, 2017 All Rights Reserved
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
# 

#this script control available NCPU values based on MEMARC selection

if [ $MEMARC = "Sequential" ];then
        echo "<field-control visible=\"true\" type=\"default\">"
        echo "<option value=\"1\" /> "
        echo "</field-control>"
elif [ $MEMARC = "SMP" ]; then

        echo "<field-control visible=\"true\" type=\"default\">"
        echo "<option value=\"2\" />"
        echo "</field-control>"

else
        echo "<field-control visible=\"true\" type=\"default\">"
        echo "<option value=\"4\" />"
        echo "</field-control>"
fi
