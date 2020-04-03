#!/bin/bash

# Copyright 2012  Vassil Panayotov
#           2014  Johns Hopkins University (author: Daniel Povey)
#           2016  Cristina Espana-Bonet
#           2018  Idiap Research Institute (author: Enno Hermann)
# Apache 2.0

# Converts the data into Kaldi's format and makes train/test splits

source path.sh

echo ""
echo "=== Starting initial Torgo data preparation ..."
echo ""

. utils/parse_options.sh

# Utterances to discard
bad_utts=conf/bad_utts

# Look for the necessary information in the original data
echo "--- Looking into the original data ..."
num_users=0
num_sessions=0
for speaker in $CORPUS/* ; do
    spk=$(basename $speaker)
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
        if [ "$info" = true ] ; then
            train_sessions[$num_sessions]="$waves"
            ((num_sessions++))
        fi
    done

    if [ "$global" = true ] ; then
	train_spks[$num_users]="$spk"
	((num_users++))
    fi
done
echo "  $num_users users have all necessary data"
echo "     ${train_spks[@]}"

echo ""
echo "--- Extracting data ..."

# Create the main folders to store the data
data=data/all_speakers
mkdir -p $data

# Create the data
rm -f $data/text.unsorted
rm -f $data/wav.scp.unsorted
rm -f $data/utt2spk.unsorted
rm -f $data/spk2gender.unsorted
for waves in ${train_sessions[@]} ; do
    # get the nomenclature
    session=$(dirname $waves)        
    ssn=$(basename $session)
    tmp=${session#*/data/}
    spk=${tmp%/Sess*}
    mic=${waves#*wav_}
    echo "  $spk $ssn $mic"
    gender=${spk:0:1}
    gender=${gender,,}
    for doc in $session/prompts/* ; do
        line=$(cat $doc)
        utt="${doc%.txt}"
        utt=$(basename $utt)
        id="$spk-$ssn-$mic-$utt"
        # The corpus has incomplete transcriptions. Till solved we remove
        # transcriptions with comments.
        if [[ $line == *'['*']'* ]] ; then
            echo "$id # includes comments" >> $bad_utts
            continue
        fi
        # Ignore utterances transcribed 'xxx' (discarded recordings).
        if [[ $line == *'xxx'* ]] ; then
            echo "$id # bad utterances ('xxx')" >> $bad_utts
            continue
        fi
        #  Remove transcriptions that are paths to files where descriptions
        #  should be included.
        if [[ $line == *'input/images'* ]] ; then
            echo "$id # untranscribed image description" >> $bad_utts
	    continue
        fi
        line="$id ${line^^}"
        if [ -f $waves/$utt.wav ] ; then  # Only files with all the associated info are written
            wav="$id $waves/$utt.wav"
            echo "$wav" >> $data/wav.scp.unsorted
            # Remove punctuation, escape characters, and trailing spaces.
            echo "$line" | tr -d '[.,?!:;"\r]' \
                | sed 's/.//g' \
                | sed 's/XRAY/X-RAY/g' \
                | awk '{$1=$1;print}' >> $data/text.unsorted
            echo "$id $spk" >> $data/utt2spk.unsorted
	    echo "$spk $gender" >> $data/spk2gender.unsorted
        fi
    done
done
sort -u $data/wav.scp.unsorted > $data/wav.scp
sort -u $data/text.unsorted > $data/text
sort -u $data/utt2spk.unsorted > $data/utt2spk
sort -u $data/spk2gender.unsorted > $data/spk2gender
sort -u -o $bad_utts $bad_utts
rm $data/*.unsorted
utils/utt2spk_to_spk2utt.pl $data/utt2spk > $data/spk2utt

local/corpus_statistics.sh
