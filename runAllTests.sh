#!/bin/bash

# Author: Cristina Espana-Bonet
# Description: Launches an instance of Kaldi pipeline for each speaker
#  in the Torgo database taken as a test speaker.


#speakers=(F01 F03 F04 FC01 FC02 FC03 M01 M02 M03 M04 M05 MC01 MC02 MC03 MC04)
speakers=(F01)

for speaker in ${speakers[@]} ; do
   mkdir -p $speaker
   cd $speaker
#   cp cmd.sh path.sh run.sh $speaker/.
#   cp -r local  $speaker/.
   ln -s ../cmd.sh ../path.sh ../runMultipleSubtests.sh ../conf ../local .
   ln -s ../../../wsj/s5/utils .
   ln -s ../../../wsj/s5/steps .
   nohup ./runMultipleSubtests.sh $speaker &>> ../nohup.lstmbiNoIvec.$speaker.out &
   cd ..
done
