#!/bin/bash

# Copyright 2012 Vassil Panayotov
#           2016 Cristina Espana-Bonet
#           2018 Idiap Research Institute (Author: Enno Hermann)

# Apache 2.0

. path.sh || exit 1

echo ""
echo "=== Building a language model ..."

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# -lt 0 ] || [ $# -gt 0 ]; then
   echo "Usage: $0";
   echo "e.g.: $0"
   echo "options: "
   exit 1;
fi

loc=`which ngram-count`;
if [ -z $loc ]; then
  if uname -a | grep 64 >/dev/null; then # some kind of 64 bit...
    sdir=$KALDI_ROOT/tools/extras/srilm/bin/i686-m64 
  else
    sdir=$KALDI_ROOT/tools/extras/srilm/bin/i686
  fi
  if [ -f $sdir/ngram-count ]; then
    echo Using SRILM tools from $sdir
    export PATH=$PATH:$sdir
  else
    echo You appear to not have SRILM tools installed, either on your path,
    echo or installed in $sdir.  See tools/install_srilm.sh for installation
    echo instructions.
    exit 1
  fi
fi

local=data/local_$x
mkdir -p data/local_{single,multi}

ngram-count -order 1 -write-vocab data/local_single/vocab-full.txt -wbdiscount \
            -text data/text_uniq_single -lm data/local_single/lm.arpa
ngram-count -order 2 -write-vocab data/local_multi/vocab-full.txt -wbdiscount \
            -text data/text_uniq_multi -lm data/local_multi/lm.arpa
mkdir data/local
cat data/local_{single,multi}/vocab-full.txt | sort | uniq > data/local/vocab-full.txt
cd data
ln -s local_single local_single_nolimit
cd ..
