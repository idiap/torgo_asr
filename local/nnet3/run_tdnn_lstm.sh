#!/bin/bash

# Set -e here so that we catch if any executable fails immediately
set -euo pipefail

# Speakers to evaluate.
speakers="F01 F03 F04 FC01 FC02 FC03 M01 M02 M03 M04 M05 MC01 MC02 MC03 MC04"

# Tests to run.
tests="test_single test_single_nolimit test_multi"

# Different (15ms) frame shift for dysarthric speakers?
different_frame_shift=true

# First the options that are passed through to run_ivector_common.sh
# (some of which are also used in this script directly).
stage=0

nj=6
gmm=tri3
feat_affix=
nnet3_affix=
data_all=data/all_speakers

# The rest are configs specific to this script.  Most of the parameters
# are just hardcoded at this level, in the commands below.
affix=   # affix for the TDNN+LSTM directory name
train_stage=-10
get_egs_stage=-10
decode_iter=

# training options
# training chunk-options
chunk_width=40,30,20
chunk_left_context=40
chunk_right_context=0
common_egs_dir=
dropout_schedule='0,0@0.20,0.3@0.50,0'

# training options
srand=0
remove_egs=true
reporting_email=

#decode options
test_online_decoding=false  # if true, it will run the last decoding stage.


# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

# The iVector-extraction and feature-dumping parts are the same as the standard
# nnet3 setup, and you can skip them by setting "--stage 11" if you have already
# run those things.
local/nnet3/run_ivector_common.sh --stage $stage \
                                  --feat-affix "$feat_affix" \
                                  --nnet3-affix "$nnet3_affix" \
                                  --different-frame-shift "$different_frame_shift" \
                                  --speakers $speakers --data-all $data_all || exit 1;

# Problem: We have removed the "train_" prefix of our training set in
# the alignment directory names! Bad!
gmm_dir=exp/$gmm
ali_dir=exp/${gmm}_ali_sp
label_delay=5

dir=exp/nnet3${nnet3_affix}${feat_affix}/tdnn_lstm${affix}_sp
train_ivector_dir=exp/nnet3${nnet3_affix}${feat_affix}/ivectors_all_speakers_sp_hires${feat_affix}

for spk in $speakers; do
    for f in $gmm_dir/$spk/final.mdl data/$spk/train_sp_hires${feat_affix}/feats.scp \
                                     $train_ivector_dir/ivector_online.scp; do
        [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1
    done
    
    # for data in $tests; do
    #     for f in $gmm_dir/$spk/graph_$data/HCLG.fst; do
    #         [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1
    #     done
    # done
done

if [ $stage -le 11 ]; then
    echo "$0: aligning with the perturbed low-resolution data"
    for spk in $speakers; do
        (
        steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
                             data/$spk/train_sp data/$spk/lang \
                             $gmm_dir/$spk $ali_dir/$spk || exit 1
        ) &
    done
    wait;
fi

if [ $stage -le 12 ]; then
  echo "$0: creating neural net configs using the xconfig parser";
  for spk in $speakers; do
      mkdir -p $dir/$spk

      num_targets=$(tree-info $ali_dir/$spk/tree |grep num-pdfs|awk '{print $2}')
      tdnn_opts="l2-regularize=0.05"
      lstm_opts="l2-regularize=0.01 decay-time=20 delay=-3 dropout-proportion=0.0"
      output_opts="l2-regularize=0.01"

      mkdir -p $dir/$spk/configs
      cat <<EOF > $dir/$spk/configs/network.xconfig
      input dim=100 name=ivector
      input dim=40 name=input

      # please note that it is important to have input layer with the name=input
      # as the layer immediately preceding the fixed-affine-layer to enable
      # the use of short notation for the descriptor
      fixed-affine-layer name=lda delay=$label_delay input=Append(-2,-1,0,1,2,ReplaceIndex(ivector, t, 0)) affine-transform-file=$dir/$spk/configs/lda.mat

      relu-batchnorm-layer name=tdnn1 dim=520 $tdnn_opts
      relu-batchnorm-layer name=tdnn2 dim=520 $tdnn_opts input=Append(-1,0,1)
      fast-lstmp-layer name=lstm1 cell-dim=520 recurrent-projection-dim=130 non-recurrent-projection-dim=130 $lstm_opts
      relu-batchnorm-layer name=tdnn3 dim=520 $tdnn_opts input=Append(-3,0,3)
      relu-batchnorm-layer name=tdnn4 dim=520 $tdnn_opts input=Append(-3,0,3)
      fast-lstmp-layer name=lstm2 cell-dim=520 recurrent-projection-dim=130 non-recurrent-projection-dim=130 $lstm_opts
      relu-batchnorm-layer name=tdnn5 dim=520 $tdnn_opts input=Append(-3,0,3)
      relu-batchnorm-layer name=tdnn6 dim=520 $tdnn_opts input=Append(-3,0,3)
      fast-lstmp-layer name=lstm3 cell-dim=520 recurrent-projection-dim=130 non-recurrent-projection-dim=130 $lstm_opts

      output-layer name=output input=lstm3 $output_opts output-delay=$label_delay dim=$num_targets max-change=1.5
EOF
      steps/nnet3/xconfig_to_configs.py \
          --xconfig-file $dir/$spk/configs/network.xconfig \
          --config-dir $dir/$spk/configs/
  done
fi


if [ $stage -le 13 ]; then
  for spk in $speakers; do
      (
      steps/nnet3/train_rnn.py \
          --stage=$train_stage \
          --cmd="$cuda_cmd" \
          --feat.online-ivector-dir=$train_ivector_dir \
          --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
          --trainer.srand=$srand \
          --trainer.max-param-change=2.0 \
          --trainer.num-epochs=6 \
          --trainer.deriv-truncate-margin=10 \
          --trainer.samples-per-iter=20000 \
          --trainer.optimization.num-jobs-initial=1 \
          --trainer.optimization.num-jobs-final=2 \
          --trainer.optimization.initial-effective-lrate=0.0003 \
          --trainer.optimization.final-effective-lrate=0.00003 \
          --trainer.dropout-schedule="$dropout_schedule" \
          --trainer.rnn.num-chunk-per-minibatch=128,64 \
          --trainer.optimization.momentum=0.5 \
          --egs.chunk-width=$chunk_width \
          --egs.chunk-left-context=$chunk_left_context \
          --egs.chunk-right-context=$chunk_right_context \
          --egs.chunk-left-context-initial=0 \
          --egs.chunk-right-context-final=0 \
          --egs.dir="$common_egs_dir" \
          --cleanup.remove-egs=$remove_egs \
          --use-gpu=true \
          --reporting.email="$reporting_email" \
          --feat-dir=data/$spk/train_sp_hires${feat_affix} \
          --ali-dir=$ali_dir/$spk \
          --lang=data/$spk/lang \
          --dir=$dir/$spk  || exit 1;
      ) &
  done
  wait;
fi

if [ $stage -le 14 ]; then
  frames_per_chunk=$(echo $chunk_width | cut -d, -f1)
  rm $dir/.error 2>/dev/null || true

  for spk in $speakers; do
      (
      for data in $tests; do
          nspk=$(wc -l <data/$spk/${data}_hires${feat_affix}/spk2utt)  # always 1 for Torgo
          steps/nnet3/decode.sh \
              --extra-left-context $chunk_left_context \
              --extra-right-context $chunk_right_context \
              --extra-left-context-initial 0 \
              --extra-right-context-final 0 \
              --frames-per-chunk $frames_per_chunk \
              --nj $nspk --cmd "$train_big_cmd"  --num-threads 4 \
              --online-ivector-dir exp/nnet3${nnet3_affix}${feat_affix}/ivectors_all_speakers_hires${feat_affix} \
              $gmm_dir/$spk/graph_${data} data/$spk/${data}_hires${feat_affix} \
              ${dir}/$spk/decode_${data} || exit 1
      done
      ) || touch $dir/$spk/.error &
      [ -f $dir/$spk/.error ] && echo "$0: there was a problem while decoding" && exit 1
  done
  wait;
fi

exit 0;
