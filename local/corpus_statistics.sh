#!/bin/bash

# Copyright 2018  Idiap Research Institute (author: Enno Hermann)
# Apache 2.0

text=data/all_speakers/text
speakers="F01 F03 F04 FC01 FC02 FC03 M01 M02 M03 M04 M05 MC01 MC02 MC03 MC04"

echo "TORGO corpus statistics"
echo ""
echo -n "Total utterances: "
cat $text | wc -l
echo -n "Total unique utterances: "
cat $text | cut -d' ' -f2- | sort | uniq > data/text_uniq
wc -l data/text_uniq
echo -n "Total multi-word utterances: "
cat $text | cut -d' ' -f3- | sed '/^\s*$/d' | wc -l
echo -n "Total unique multi-word utterances: "
awk 'NF>1' data/text_uniq > data/text_uniq_multi
wc -l data/text_uniq_multi
echo -n "Total unique single-word utterances: "
awk 'NF==1' data/text_uniq > data/text_uniq_single
wc -l data/text_uniq_single

count=0
total=0
for spk in $speakers; do
    if [ ! -d data/$spk ]; then exit 0; fi
    utts=$(cat data/$spk/test/text | cut -d' ' -f3- | sort | uniq | sed '/^\s*$/d' | wc -l)
    total=$(echo $total+$utts | bc)
    ((count++))
done
echo -n "Average unique multi-word utterances per speaker: "
echo "scale=2; $total / $count" | bc
