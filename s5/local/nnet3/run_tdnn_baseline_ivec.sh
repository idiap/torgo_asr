#!/bin/bash


# This version of the TDNN system is being built to have a similar configuration
# to the one in local/online/run_nnet2.sh, for better comparability.

. cmd.sh


# At this script level we don't support not running on GPU, as it would be painfully slow.
# If you want to run without GPU you'd have to call train_tdnn.sh with --gpu false,
# --num-threads 16 and --minibatch-size 128.

stage=0
train_stage=-10
dir=exp/nnet3/nnet_tdnn_c_ivec
tests=("test" "test_head" "test_head_single" "test_head_sentence")

. cmd.sh
. ./path.sh
. ./utils/parse_options.sh


if ! cuda-compiled; then
  cat <<EOF && exit 1 
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA 
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

local/nnet3/run_ivector_common.sh --stage $stage || exit 1;

if [ $stage -le 8 ]; then

  steps/nnet3/train_tdnn.sh --stage $train_stage \
    --num-epochs 8 --num-jobs-initial 2 --num-jobs-final 14 \
    --splice-indexes "-1,0,1  -2,1  -4,2 0" \
    --feat-type raw \
    --online-ivector-dir exp/nnet3/ivectors_train \
    --cmvn-opts "--norm-means=false --norm-vars=false" \
    --initial-effective-lrate 0.005 --final-effective-lrate 0.0005 \
    --cmd "$decode_cmd" \
    --pnorm-input-dim 2000 \
    --pnorm-output-dim 250 \
    --egs-opts "--nj 1" \
    data/train_hires data/lang exp/tri4b_ali $dir  || exit 1;
fi
   #--cmvn_opts "--nj 4" \
 #    --io-opts "--max-jobs-run 12" \


if [ $stage -le 9 ]; then
  # this does offline decoding that should give the same results as the real
  # online decoding.

  graph_dir=exp/tri4b/graph_
  hires=_hires
  # use already-built graphs.
  for x in "${tests[@]}"; do
    steps/nnet3/decode.sh --nj 1 --cmd "$decode_cmd" \
      --online-ivector-dir exp/nnet3/ivectors_test \
      $graph_dir$x data/$x$hires $dir/decode_$x || exit 1;
  done
fi

