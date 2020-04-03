#!/bin/bash

# Copyright 2019  Idiap Research Institute (author: Enno Hermann)
# Apache 2.0

# Usage:
# ./local/get_phone_alignments.sh exp/sgmm

speakers="F01 F03 F04 FC01 FC02 FC03 M01 M02 M03 M04 M05 MC01 MC02 MC03 MC04"

# Remove trailing slash if present.
exp=${1%/}

# Writes phoneme alignments and lengths to file.
for spk in $speakers; do
    for f in ${exp}/$spk/final.mdl ${exp}_ali/$spk/ali.1.gz; do
        [ ! -f $f ] && echo "expected $f to exist" && exit 1;
    done
    ali-to-phones --write-lengths ${exp}/$spk/final.mdl ark:"gunzip -c ${exp}_ali/$spk/ali.*.gz|" ark,t:-  > ${exp}_ali/$spk/phone_lengths.ali
done
