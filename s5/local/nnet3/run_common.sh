#!/bin/bash

# Cristina Espana-Bonet
# Modified to deal with the Torgo DB and to consider different time shifts when extracting 
# the features according to the nature of the speaker (dysartric vs. control)

# this script is called from scripts like run_ms.sh; it does the common stages
# of the build, such as feature extraction.
# This is actually the same as local/online/run_nnet2_common.sh, except
# for the directory names.

. cmd.sh
mfccdir=mfcc

# Subtests to be decoded
tests=("test" "test_head" "test_head_single" "test_head_sentence")

stage=1

. cmd.sh
. ./path.sh
. ./utils/parse_options.sh


if [ $stage -le 1 ]; then
  for datadir in "${tests[@]}"; do
    utils/copy_data_dir.sh data/$datadir data/${datadir}_hires
    local/torgo_make_mfcc.sh --nj 1 --mfcc-config conf/mfcc_hires.conf \
      --cmd "$train_cmd" data/${datadir}_hires exp/make_hires/$datadir $mfccdir || exit 1;
    steps/compute_cmvn_stats.sh data/${datadir}_hires exp/make_hires/$datadir $mfccdir || exit 1;
  done

  datadir=train
  utils/copy_data_dir.sh data/$datadir data/${datadir}_hires
  local/torgo_make_mfcc.sh --nj 14 --mfcc-config conf/mfcc_hires.conf \
    --cmd "$train_cmd" data/${datadir}_hires exp/make_hires/$datadir $mfccdir || exit 1;
  steps/compute_cmvn_stats.sh data/${datadir}_hires exp/make_hires/$datadir $mfccdir || exit 1;

fi

if [ $stage -le 2 ]; then
  # We need to build a small system just because we need the LDA+MLLT transform
  # to train the diag-UBM on top of.  We align the small data for this purpose.

  # too small to split ($nj=1)
  steps/align_fmllr.sh --nj 1 --cmd "$train_cmd" \
    data/train data/lang exp/tri4b exp/nnet3/tri4b_ali
    #data/train_small data/lang exp/tri4b exp/nnet3/tri4b_ali_small
fi

exit 0;
