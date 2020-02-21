#!/bin/bash

# Copyright 2012-2014  Brno University of Technology (Author: Karel Vesely)
# Apache 2.0

# This example shows how to train a simple autoencoder network.
# We use <tanh>, little different training hyperparameters and MSE objective.

. path.sh
. cmd.sh

set -eu

echo "$0 $@"  # Print the command line for logging

cv_spk_percent=8 # one speaker of the 14 in training for CV
# Train,
dir=exp/autoencoder
data_fmllr=data-fmllr-tri3b
dirdata=$data_fmllr/train
if [ ! -e ${dirdata}_tr90 ] || [ ! -e ${dirdata}_cv1 ] ; then
   utils/subset_data_dir_tr_cv.sh --cv-spk-percent ${cv_spk_percent} $dirdata ${dirdata}_tr90 ${dirdataq}_cv10
fi

echo "Training"

labels="ark:feat-to-post scp:$data_fmllr/train/feats.scp ark:- |"
$cuda_cmd $dir/log/train_nnet.log \
  steps/nnet/train.sh --hid-layers 2 --hid-dim 200 --learn-rate 0.00001 \
    --labels "$labels" --num-tgt 40 --train-tool "nnet-train-frmshuff --objective-function=mse" \
    --proto-opts "--no-softmax --activation-type=<Tanh> --hid-bias-mean=0.0 --hid-bias-range=1.0 --param-stddev-factor=0.01" \
    $data_fmllr/train_tr90 $data_fmllr/train_cv10 dummy-dir dummy-dir dummy-dir $dir || exit 1;

echo "Forward the data"
# Forward the data,
output_dir=data-autoencoded/test
steps/nnet/make_bn_feats.sh --nj 1 --cmd "$train_cmd" --remove-last-components 0 \
  $output_dir $data_fmllr/test $dir $output_dir/{log,data} || exit 1
