#!/bin/bash
# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0

[ -f ./path.sh ] && . ./path.sh

# begin configuration section.
cmd=run.pl
min_lmwt=9
#min_lmwt=12
#max_lmwt=28
max_lmwt=15
#end configuration section.

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: local/score.sh [--cmd (run.pl|queue.pl...)] <Command|Kent> <lang-dir|graph-dir> <decode-dir>"
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "    --min_lmwt <int>                # minumum LM-weight for lattice rescoring "
  echo "    --max_lmwt <int>                # maximum LM-weight for lattice rescoring "
  exit 1;
fi

single=$1
lang_or_graph=$2
dir=$3

symtab=$lang_or_graph/words.txt

for f in $symtab; do
  [ ! -f $f ] && echo "torgo_score_subset.sh: no such file $f" && exit 1;
done

mkdir -p $dir/scoring/log

join $dir/scoring/test_filt.txt local/single$single.txt > $dir/scoring/test_filt_$single.txt
for f in $(seq $min_lmwt $max_lmwt); do
    join $dir/scoring/$f.tra local/single$single.txt > $dir/scoring/$f.$single.tra
done


# Note: the double level of quoting for the sed command
$cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/score_$single.LMWT.log \
   cat $dir/scoring/LMWT.$single.tra \| \
    utils/int2sym.pl -f 2- $symtab \| sed 's:\<UNK\>::g' \| \
    compute-wer --text --mode=present \
     ark:$dir/scoring/test_filt_$single.txt  ark,p:- ">&" $dir/wer_$single\_LMWT || exit 1;

# Show results
for f in $dir/wer_$single*; do echo $f; egrep  '(WER)|(SER)' < $f; done

exit 0;
