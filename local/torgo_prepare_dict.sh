#!/bin/bash

# Copyright 2012 Vassil Panayotov
#           2016 Cristina Espana-Bonet
#           2018 Idiap Research Institute (Author: Enno Hermann)

# Apache 2.0

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# -lt 0 ] || [ $# -gt 0 ]; then
   echo "Usage: $0 [options]";
   echo "e.g.: $0"
   echo "options: "
   exit 1;
fi

local=data/local
dict=data/local/dict
cmudict=data/cmudict

echo ""
echo "=== Preparing the dictionary ..."
echo ""

mkdir -p $dict $cmudict

if [ ! -f $cmudict/cmudict.0.7a ]; then
  echo "--- Downloading CMU dictionary ..."
  svn co http://svn.code.sf.net/p/cmusphinx/code/trunk/cmudict \
    $cmudict || exit 1;
fi

echo "--- Striping stress and pronunciation variant markers from cmudict ..."
perl $cmudict/scripts/make_baseform.pl \
  $cmudict/cmudict.0.7a /dev/stdout |\
  sed -e 's:^\([^\s(]\+\)([0-9]\+)\(\s\+\)\(.*\):\1\2\3:' > $cmudict-plain.txt

echo "--- Searching for OOV words ..."
awk 'NR==FNR{words[$1]; next;} !($1 in words)' \
  $cmudict-plain.txt $local/vocab-full.txt |\
  egrep -v '<.?s>' > $dict/vocab-oov.txt

awk 'NR==FNR{words[$1]; next;} ($1 in words)' \
  $local/vocab-full.txt $cmudict-plain.txt |\
  egrep -v '<.?s>' > $dict/lexicon-iv.txt

wc -l $dict/vocab-oov.txt
wc -l $dict/lexicon-iv.txt

if [ ! -f conf/g2p_model ]; then
  echo "--- Downloading a pre-trained Sequitur G2P model ..."
  wget http://sourceforge.net/projects/kaldi/files/sequitur-model4 -O conf/g2p_model
  if [ ! -f conf/g2p_model ]; then
    echo "Failed to download the g2p model!"
    exit 1
  fi
fi

if [[ "$(uname)" == "Darwin" ]]; then
  command -v greadlink >/dev/null 2>&1 || \
    { echo "Mac OS X detected and 'greadlink' not found - please install using macports or homebrew"; exit 1; }
  alias readlink=greadlink
fi

sequitur=$KALDI_ROOT/tools/sequitur
export PATH=$PATH:$sequitur/bin
export PYTHONPATH=$PYTHONPATH:`readlink -f $sequitur/lib/python*/site-packages`

if ! g2p=`which g2p.py` ; then
  echo "The Sequitur was not found !"
  echo "Go to $KALDI_ROOT/tools and execute extras/install_sequitur.sh"
  exit 1
fi

echo "--- Preparing pronunciations for OOV words ..."
g2p.py --model=conf/g2p_model --apply $dict/vocab-oov.txt > $dict/lexicon-oov.txt

cat $dict/lexicon-oov.txt $dict/lexicon-iv.txt |\
  sort > $dict/lexicon.txt

echo "--- Prepare phone lists ..."
echo SIL > $dict/silence_phones.txt
echo SIL > $dict/optional_silence.txt
grep -v -w sil $dict/lexicon.txt | \
  awk '{for(n=2;n<=NF;n++) { p[$n]=1; }} END{for(x in p) {print x}}' |\
  sort > $dict/nonsilence_phones.txt

echo "--- Adding SIL to the lexicon ..."
echo -e "!SIL\tSIL" >> $dict/lexicon.txt

# Some downstream scripts expect this file exists, even if empty
touch $dict/extra_questions.txt

