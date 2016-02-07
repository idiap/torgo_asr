#!/bin/bash

# Copyright 2012  Vassil Panayotov
#           2014  Johns Hopkins University (author: Daniel Povey)
#           2016  Cristina Espana-Bonet
# Apache 2.0

# Converts the data into Kaldi's format and makes train/test splits
# This version discards those speakers without all the information (txt+phn+wav)
#  That represents 4 speakers (10 vs 14) for training

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
       #path=$(dirname $waves)
       info=false  #all the information within a session
       if  [ -d "$waves" ] ; then
            acoustics=true
            phones="${waves/wav_/phn_}"
            if  [ -d "$phones" ] ; then
                phonetics=true
                transcript="${waves/wav_*Mic/prompts}"
                if  [ -d "$transcript" ] ; then
                    transcriptions=true
                    info=true
		    global=true
                fi
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
   phones="${waves/wav_/phn_}"
   echo "  $spk $ssn"
   gender=${spk:0:1}
   gender=${gender,,}
   for doc in $session/prompts/* ; do
       utt="${doc%.txt}"
       utt=$(basename $utt)
       id="$spk-$ssn-$utt"
       line=$(cat $doc)
       line="$id ${line^^}"
       if [ -f $waves/$utt.wav ] && { [ -f $phones/$utt.PHN ] || [ -f $phones/$utt.phn ]; } ; then  #only files with all the associated info are written
          wav="$id $waves/$utt.wav"
          echo "$wav" >> data/train/wav.scp.unsorted
          #buscar que fer amb les cometes simples i els fitxers amb path com a transcripcio
          echo "$line" | tr -d '[.,?!:;"]'  >> data/train/text.unsorted
          echo "$id $spk" >> data/train/utt2spk.unsorted
	  echo "$spk $gender" >> data/train/spk2gender.unsorted
       fi
   done
done
sort -u data/train/wav.scp.unsorted > data/train/wav.scp
sort -u data/train/text.unsorted > data/train/text
sort -u data/train/utt2spk.unsorted > data/train/utt2spk
sort -u data/train/spk2gender.unsorted > data/train/spk2gender
rm data/train/*.unsorted
utils/utt2spk_to_spk2utt.pl data/train/utt2spk > data/train/spk2utt

echo "--- Extracting test ..."
# Create the data for test                             
rm -f data/test/text.unsorted
rm -f data/test/wav.scp.unsorted
rm -f data/test/utt2spk.unsorted
rm -f data/test/spk2gender.unsorted
for waves in ${test_sessions[@]} ; do
#  get the nomenclature         
   session=$(dirname $waves)
   ssn=$(basename $session)
   tmp=${session#*02/data/}
   spk=${tmp%/Sess*}
   phones="${waves/wav_/phn_}"
   echo "  $spk $ssn"
   gender=${spk:0:1}  #inside the just in case there were more than one test speaker  
   gender=${gender,,}
   for doc in $session/prompts/* ; do
       utt="${doc%.txt}"
       utt=$(basename $utt)
       id="$spk-$ssn-$utt"
       line=$(cat $doc)
       line="$id ${line^^}"
       if [ -f $waves/$utt.wav ] && { [ -f $phones/$utt.PHN ] || [ -f $phones/$utt.phn ]; } ; then   #only files with all the associated info are written
          wav="$id $waves/$utt.wav"
          echo "$wav" >> data/test/wav.scp.unsorted
          #buscar que fer amb les cometes simples i els fitxers amb path com a transcripcio (segurament ja eliminats)
          echo "$line" | tr -d '[.,?!:;"]'  >> data/test/text.unsorted
          echo "$id $spk" >> data/test/utt2spk.unsorted
	  echo "$spk $gender" >> data/test/spk2gender.unsorted
       fi
   done
done
sort -u data/test/wav.scp.unsorted > data/test/wav.scp
sort -u data/test/text.unsorted > data/test/text
sort -u data/test/utt2spk.unsorted > data/test/utt2spk
sort -u data/test/spk2gender.unsorted > data/test/spk2gender
rm data/test/*.unsorted
utils/utt2spk_to_spk2utt.pl data/test/utt2spk > data/test/spk2utt
