#!/bin/bash

# Copyright 2019  Idiap Research Institute (author: Enno Hermann)
# Apache 2.0

utts=data/text_uniq_single
lex=data/cmudict-plain.txt

while IFS='' read -r word || [[ -n "$word" ]]; do
    grep "^${word}[[:space:]]" $lex | cut -f 2 
done < $utts
