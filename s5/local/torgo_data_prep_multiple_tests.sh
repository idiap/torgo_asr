#!/bin/bash

# Copyright 2012  Vassil Panayotov
#           2014  Johns Hopkins University (author: Daniel Povey)
#           2016  Cristina Espana-Bonet
# Apache 2.0

# Converts the data into Kaldi's format and makes train/test splits

source path.sh

echo ""
echo "=== Starting initial Torgo data preparation ..."
echo ""

. utils/parse_options.sh

if [ $# != 1 ]; then
  echo "Usage: $0 <test speaker>";
  exit 1;
fi

test_spk=$1

# Look for the necessary information in the original data
echo "--- Looking into the original data ..."
num_users=0
num_sessions=0
num_Tsessions=0
spk_test_seen=false
for speaker in $DATA_ORIG/* ; do
    spk=$(basename $speaker)
    if [ "$spk" == "$test_spk" ] ; then   #your test speaker must exist
       spk_test_seen=true
    fi
    global=false  #all the information in any session of a user
    for waves in $speaker/S*/wav_* ; do
       info=false  #all the information within a session
       if  [ -d "$waves" ] ; then
            acoustics=true
            transcript="${waves/wav_*Mic/prompts}"
            if  [ -d "$transcript" ] ; then
                 transcriptions=true
                 info=true
	         global=true
            fi

       fi
       if [ "$info" = true ] && [ "$spk" != "$test_spk" ] ; then
        train_sessions[$num_sessions]="$waves"
        ((num_sessions++))
       fi
       if [ "$info" = true ] && [ "$spk" == "$test_spk" ] ; then
        test_sessions[$num_Tsessions]="$waves"
        ((num_Tsessions++))
       fi
    done

    if [ "$global" = true ] ; then
        if [ "$spk" != "$test_spk" ] ; then
	train_spks[$num_users]="$spk"
	((num_users++))
        fi  
    else
        if [ "$spk" == "$test_spk" ]  || [ "$spk_test_seen" = false ]; then
            echo " -- ERROR"
	    echo " --  Your test speaker $test_spk does not have all necessary data"
	    exit 1
        fi
    fi
done
echo "  $num_users users besides your test speaker have all necessary data"
echo "     ${train_spks[@]}"

echo ""
echo "--- Extracting training ..."

# Create the main folders to store the data                                                                   
mkdir -p data/train
mkdir -p data/test
mkdir -p data/test_head
mkdir -p data/test_head_single
mkdir -p data/test_head_sentence

# Create the data for training
rm -f data/train/text.unsorted
rm -f data/train/wav.scp.unsorted
rm -f data/train/utt2spk.unsorted
rm -f data/train/spk2gender.unsorted
for waves in ${train_sessions[@]} ; do
#  get the nomenclature
   session=$(dirname $waves)        
   ssn=$(basename $session)
   tmp=${session#*02/data/}
   spk=${tmp%/Sess*}
   mic=${waves#*wav_}
   echo "  $spk $ssn $mic"
   gender=${spk:0:1}
   gender=${gender,,}
   for doc in $session/prompts/* ; do
       line=$(cat $doc)
       #line=$(<$doc)
       #The DB has incomplete transcriptions. Till solved we
       #  remove transcriptions with comments
       if [[ $line == *'['*']'* ]] ; then
          continue
       fi
       #  remove transcriptions that are paths to files where descriptions should be included
       if [[ $line == *'input/images'* ]] ; then
	  continue
       fi
       utt="${doc%.txt}"
       utt=$(basename $utt)
       id="$spk-$ssn-$mic-$utt"
       line="$id ${line^^}"
       if [ -f $waves/$utt.wav ] ; then  #only files with all the associated info are written
          wav="$id $waves/$utt.wav"
          echo "$wav" >> data/train/wav.scp.unsorted
          #buscar que fer amb les cometes simples
          echo "$line" | tr -d '[.,?!:;"]'  >> data/train/text.unsorted
          echo "$id $spk" >> data/train/utt2spk.unsorted
	  echo "$spk $gender" >> data/train/spk2gender.unsorted
       fi
   done
done

echo "--- Extracting test ..."
# Create the data for test    
for waves in ${test_sessions[@]} ; do
#  get the nomenclature         
   session=$(dirname $waves)
   ssn=$(basename $session)
   tmp=${session#*02/data/}
   spk=${tmp%/Sess*}
   mic=${waves#*wav_}
   echo "  $spk $ssn $mic"
   gender=${spk:0:1}  #inside the for just in case there were more than one test speaker  
   gender=${gender,,}
   for doc in $session/prompts/* ; do
       line=$(cat $doc)
       if [[ $line == *'['*']'* ]] ; then
          continue
       fi
       #  remove transcriptions that are paths to files where descriptions should be included
       if [[ $line == *'input/images'* ]] ; then
          continue
       fi
       utt="${doc%.txt}"
       utt=$(basename $utt)
       id="$spk-$ssn-$mic-$utt"
       line="$id ${line^^}"
       if [ -f $waves/$utt.wav ] ; then   #only files with all the associated info are written
          wav="$id $waves/$utt.wav"
          echo "$wav" >> data/test/wav.scp.unsorted
          #buscar que fer amb les cometes simples
          echo "$line" | tr -d '[.,?!:;"]'  >> data/test/text.unsorted
          echo "$id $spk" >> data/test/utt2spk.unsorted
	  echo "$spk $gender" >> data/test/spk2gender.unsorted
          if [[ $mic == 'headMic' ]] ; then
             echo "$wav" >> data/test_head/wav.scp.unsorted
             echo "$line" | tr -d '[.,?!:;"]'  >> data/test_head/text.unsorted
             echo "$id $spk" >> data/test_head/utt2spk.unsorted
             echo "$spk $gender" >> data/test_head/spk2gender.unsorted
             words=( $line )
             num_words=${#words[@]}
             if [[ $num_words < 3 ]] ; then  #id plus a word
                echo "$wav" >> data/test_head_single/wav.scp.unsorted
                echo "$line" | tr -d '[.,?!:;"]'  >> data/test_head_single/text.unsorted
                echo "$id $spk" >> data/test_head_single/utt2spk.unsorted
                echo "$spk $gender" >> data/test_head_single/spk2gender.unsorted
             else 
                echo "$wav" >> data/test_head_sentence/wav.scp.unsorted
                echo "$line" | tr -d '[.,?!:;"]'  >> data/test_head_sentence/text.unsorted
                echo "$id $spk" >> data/test_head_sentence/utt2spk.unsorted
                echo "$spk $gender" >> data/test_head_sentence/spk2gender.unsorted
             fi
          fi
       fi
   done
done

# Sorting and cleaning everything
for x in train test test_head test_head_single test_head_sentence; do
    sort -u data/$x/wav.scp.unsorted > data/$x/wav.scp
    sort -u data/$x/text.unsorted > data/$x/text
    sort -u data/$x/utt2spk.unsorted > data/$x/utt2spk
    sort -u data/$x/spk2gender.unsorted > data/$x/spk2gender
    rm data/$x/*.unsorted
    utils/utt2spk_to_spk2utt.pl data/$x/utt2spk > data/$x/spk2utt
done






