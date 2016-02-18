#!/bin/bash

# Author: Cristina Espana-Bonet
# Description: Launches an instance of Kaldi pipeline for each speaker
#  in the Torgo database taken as a test speaker.

#speakers=(F01 F03 F04 FC01 FC02 FC03 M01 M02 M03 M04 M05 MC01 MC02 MC03 MC04)
speakers=(M02)
folder=M02
for speaker in ${speakers[@]} ; do
   mkdir -p $folder
   cd $folder
#   cp cmd.sh path.sh run.sh $speaker/.
#   cp -r local  $speaker/.
   ln -s ../cmd.sh ../path.sh ../run.sh ../conf ../local .
   ln -s ../../../wsj/s5/utils .
   ln -s ../../../wsj/s5/steps .
   nohup ./run.sh $speaker &>> ../nohupNew.$speaker.out &
   cd ..
done
