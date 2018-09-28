#/bin/sh
#**************************************************************************
#  Copyright International Business Machines Corp, 2018. 
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#**************************************************************************

#
# When this script is called outside an LSF job array, it will process the first image
#
# arg1 = IMAGE_DIR

if [ $# -lt 1 ] ; then
        echo "Expecting at least a log directory argument"
        exit 2
fi

IMAGE_DIR=$1
if [ ! -d $IMAGE_DIR ]; then
   echo "This directory was not found: $IMAGE_DIR"
   exit 2
fi

if [ $# -lt 1 ] ; then
        echo "Expecting at least a log directory argument"
        exit 2
fi


# Get the job index number
indx=${LSB_JOBINDEX:-1}
#echo $indx

max_images=`ls $IMAGE_DIR/*.jpg |wc -l`
if [ $max_images -eq 0 ]; then
   echo "There are no jpg files in: $IMAGE_DIR"
   exit 3
fi

# for case where number of job array elements is greater than max number of images
#echo $indx $max_images
indx=$((indx%(max_images)))
if [ $indx -eq 0 ]; then
   indx=$max_images
fi
#echo $indx $max_images


f1=`ls $IMAGE_DIR/*.jpg | head -${indx} | tail -1`
#echo $f1

echo classify_image.py --image_file  $f1
classify_image.py --image_file  $f1
