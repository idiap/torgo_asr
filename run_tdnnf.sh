#!/bin/bash

# Copyright 2018  Idiap Research Institute (Author: Enno Hermann)

# Apache 2.0

set -euo pipefail

stage=0

# Speakers to evaluate.
speakers="F01 F03 F04 FC01 FC02 FC03 M01 M02 M03 M04 M05 MC01 MC02 MC03 MC04"

# Tests to run.
tests="dev test_single test_single_nolimit test_multi"
#tests="test_single_nolimit"
#tests="dev"

# Different (15ms) frame shift for dysarthric speakers?
different_frame_shift=false

nj=6
gmm=tri3
feat_affix=
nnet3_affix=
data_all=data/all_speakers

# Number of utterances to reserve for validation.
# The speakers in the training and dev sets will overlap, but this is impossible
# to avoid with this small amount of data (we can't just reserve 1-2 speakers
# for development because those sets would be identical to the test sets then
# and bias our results).
num_dev_utts=800

affix=
tree_affix=
train_stage=-10
get_egs_stage=-10
decode_iter=

# training options
# training chunk-options
chunk_width=140,100,160
dropout_schedule='0,0@0.20,0.3@0.50,0'
common_egs_dir=
xent_regularize=0.1

# training options
srand=0
remove_egs=true
reporting_email=

# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. utils/parse_options.sh

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

# Split data into 14 training speakers and 1 test speakers for each specified
# test speaker. We'll get the speed-perturbed data for training and the
# non-perturbed data for testing. We also need the low-resolution perturbed
# training data to get alignments. We further reserve 800 (= 2400 perturbed)
# utterances for validation.
if [ $stage -le 10 ]; then
    tmp=$(mktemp -d /tmp/${USER}_XXXXX)
    # Identify single- and multi-word utterances to evaluate them separately.
    cat $data_all/text | awk 'NF==2' > $tmp/single.utts
    cat $data_all/text | awk 'NF>2' > $tmp/multi.utts
    
    for spk in $speakers; do
        echo -e "$spk" > $tmp/$spk
        # Get high-resolution test set.
        utils/subset_data_dir_tr_cv.sh \
            --cv-spk-list "$tmp/$spk" ${data_all}_hires${feat_affix} \
            data/$spk/train_dev_hires${feat_affix} data/$spk/test_hires${feat_affix}
        utils/subset_data_dir.sh --utt-list $tmp/single.utts \
                                 data/$spk/test_hires${feat_affix} data/$spk/test_single_hires${feat_affix}
        utils/subset_data_dir.sh --utt-list $tmp/single.utts \
                                 data/$spk/test_hires${feat_affix} data/$spk/test_single_nolimit_hires${feat_affix}
        utils/subset_data_dir.sh --utt-list $tmp/multi.utts \
                                 data/$spk/test_hires${feat_affix} data/$spk/test_multi_hires${feat_affix}
        utils/fix_data_dir.sh data/$spk/train_dev_hires${feat_affix}
        utils/fix_data_dir.sh data/$spk/test_hires${feat_affix}
        utils/fix_data_dir.sh data/$spk/test_single_hires${feat_affix}
        utils/fix_data_dir.sh data/$spk/test_single_nolimit_hires${feat_affix}
        utils/fix_data_dir.sh data/$spk/test_multi_hires${feat_affix}

        # Split the rest into train and dev sets.
        utils/subset_data_dir.sh data/$spk/train_dev_hires${feat_affix} $num_dev_utts \
                                 data/$spk/dev_hires${feat_affix}
        utts=$tmp/${spk}_utts
        cp data/$spk/dev_hires${feat_affix}/utt2spk ${utts}_dev.tmp
        utils/filter_scp.pl --exclude ${utts}_dev.tmp \
                            data/$spk/train_dev_hires${feat_affix}/utt2spk > ${utts}_train.tmp
        utils/utt2spk_to_spk2utt.pl ${data_all}_sp/utt2uniq > $tmp/uniq2utt
        for data in train dev; do
            cat ${utts}_${data}.tmp | utils/apply_map.pl -f 1 ${data_all}_sp/utt2uniq | \
                sort | uniq | utils/apply_map.pl -f 1 $tmp/uniq2utt | \
                awk '{for(n=1;n<NF;n++) print $n;}' | sort  > ${utts}_${data}
        done
        
        rm -rdf data/$spk/train_dev_hires${feat_affix}
        
        # Get perturbed train and dev sets.
        for suffix in _sp _sp_hires${feat_affix}; do
            for data in train dev; do
                utils/subset_data_dir.sh \
                    --utt-list ${utts}_$data ${data_all}${suffix} \
                    data/$spk/${data}${suffix}
                utils/fix_data_dir.sh data/$spk/${data}${suffix}
            done
        done
    done
fi

gmm_dir=exp/$gmm
ali_dir=exp/${gmm}_ali_sp
tree_dir=exp/chain${nnet3_affix}${feat_affix}/tree_sp${tree_affix:+_$tree_affix}
lat_dir=exp/chain${nnet3_affix}${feat_affix}/${gmm}_train_sp_lats
dir=exp/chain${nnet3_affix}${feat_affix}/tdnn${affix}_sp
train_ivector_dir=exp/nnet3${nnet3_affix}${feat_affix}/ivectors_all_speakers_sp_hires${feat_affix}

for spk in $speakers; do
    for f in $gmm_dir/$spk/final.mdl data/$spk/train_sp_hires${feat_affix}/feats.scp \
                                     $train_ivector_dir/ivector_online.scp \
                                     data/$spk/train_sp/feats.scp; do
        [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1
    done
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
  echo "$0: creating lang directory with chain-type topology"
  # Create a version of the lang/ directory that has one state per phone in the
  # topo file. [note, it really has two states.. the first one is only repeated
  # once, the second one has zero or more repeats.]
  for spk in $speakers; do
      lang=data/$spk/lang_chain
      if [ -d $lang ]; then
          if [ $lang/L.fst -nt data/$spk/lang/L.fst ]; then
              echo "$0: $lang already exists, not overwriting it; continuing"
          else
              echo "$0: $lang already exists and seems to be older than data/$spk/lang..."
              echo " ... not sure what to do.  Exiting."
              exit 1;
          fi
      else
          cp -r data/$spk/lang $lang
          silphonelist=$(cat $lang/phones/silence.csl) || exit 1;
          nonsilphonelist=$(cat $lang/phones/nonsilence.csl) || exit 1;
          # Use our special topology... note that later on may have to tune this
          # topology.
          steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >$lang/topo
      fi
  done
fi

if [ $stage -le 13 ]; then
    # Get the alignments as lattices (gives the chain training more freedom).
    # use the same num-jobs as the alignments
    for spk in $speakers; do
        (
        steps/align_fmllr_lats.sh --nj $nj --cmd "$train_cmd" data/$spk/train_sp \
                                  data/$spk/lang $gmm_dir/$spk $lat_dir/$spk
        rm $lat_dir/$spk/fsts.*.gz # save space
        ) &
    done
    wait;
fi

if [ $stage -le 14 ]; then
    # Build a tree using our new topology. We know we have alignments for the
    # speed-perturbed data, so use those. The num-leaves is always somewhat less
    # than the num-leaves from the GMM baseline.
    for spk in $speakers; do
        (
        if [ -f $tree_dir/$spk/final.mdl ]; then
            echo "$0: $tree_dir/$spk/final.mdl already exists, refusing to overwrite it."
            exit 1;
        fi
        steps/nnet3/chain/build_tree.sh \
            --frame-subsampling-factor 3 \
            --context-opts "--context-width=2 --central-position=1" \
            --cmd "$train_cmd" 3500 data/$spk/train_sp \
            data/$spk/lang_chain $ali_dir/$spk $tree_dir/$spk
        ) &
    done
    wait;
fi

if [ $stage -le 15 ]; then
    echo "$0: creating neural net configs using the xconfig parser";
    for spk in $speakers; do
        mkdir -p $dir/$spk

        num_targets=$(tree-info $tree_dir/$spk/tree |grep num-pdfs|awk '{print $2}')
        learning_rate_factor=$(echo "print (0.5/$xent_regularize)" | python)

        tdnn_opts="l2-regularize=0.03 dropout-proportion=0.0 dropout-per-dim-continuous=true"
        tdnnf_opts="l2-regularize=0.03 dropout-proportion=0.0 bypass-scale=0.66"
        linear_opts="l2-regularize=0.03 orthonormal-constraint=-1.0"
        prefinal_opts="l2-regularize=0.03"
        output_opts="l2-regularize=0.015"

        mkdir -p $dir/$spk/configs
        cat <<EOF > $dir/$spk/configs/network.xconfig
        input dim=100 name=ivector
        input dim=40 name=input

        # please note that it is important to have input layer with the name=input
        # as the layer immediately preceding the fixed-affine-layer to enable
        # the use of short notation for the descriptor
        fixed-affine-layer name=lda input=Append(-1,0,1,ReplaceIndex(ivector, t, 0)) affine-transform-file=$dir/$spk/configs/lda.mat
        #fixed-affine-layer name=lda input=Append(-1,0,1) affine-transform-file=$dir/$spk/configs/lda.mat

        # the first splicing is moved before the lda layer, so no splicing here
        relu-batchnorm-dropout-layer name=tdnn1 $tdnn_opts dim=768
        tdnnf-layer name=tdnnf2 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=1
        tdnnf-layer name=tdnnf3 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=1
        tdnnf-layer name=tdnnf4 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=1
        tdnnf-layer name=tdnnf5 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=0
        tdnnf-layer name=tdnnf6 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=3
        tdnnf-layer name=tdnnf7 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=3
        tdnnf-layer name=tdnnf8 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=3
        tdnnf-layer name=tdnnf9 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=3
        tdnnf-layer name=tdnnf10 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=3
        tdnnf-layer name=tdnnf11 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=3
        tdnnf-layer name=tdnnf12 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=3
        tdnnf-layer name=tdnnf13 $tdnnf_opts dim=768 bottleneck-dim=96 time-stride=3
        linear-component name=prefinal-l dim=192 $linear_opts

        ## adding the layers for chain branch
        prefinal-layer name=prefinal-chain input=prefinal-l $prefinal_opts small-dim=192 big-dim=768
        output-layer name=output include-log-softmax=false dim=$num_targets $output_opts

        # adding the layers for xent branch
        prefinal-layer name=prefinal-xent input=prefinal-l $prefinal_opts small-dim=192 big-dim=768
        output-layer name=output-xent dim=$num_targets learning-rate-factor=$learning_rate_factor $output_opts
EOF
        steps/nnet3/xconfig_to_configs.py \
            --xconfig-file $dir/$spk/configs/network.xconfig \
            --config-dir $dir/$spk/configs/
    done
fi

if [ $stage -le 16 ]; then
    for spk in $speakers; do
        (
        python2 steps/nnet3/chain/train.py \
            --feat.online-ivector-dir=$train_ivector_dir \
            --stage=$train_stage \
            --cmd="$cuda_cmd" \
            --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
            --chain.xent-regularize $xent_regularize \
            --chain.leaky-hmm-coefficient=0.1 \
            --chain.l2-regularize=0.0 \
            --chain.apply-deriv-weights=false \
            --chain.lm-opts="--num-extra-lm-states=2000" \
            --trainer.dropout-schedule $dropout_schedule \
            --trainer.add-option="--optimization.memory-compression-level=2" \
            --trainer.srand=$srand \
            --trainer.max-param-change=2.0 \
            --trainer.num-epochs=10 \
            --trainer.frames-per-iter=3000000 \
            --trainer.optimization.num-jobs-initial=2 \
            --trainer.optimization.num-jobs-final=5 \
            --trainer.optimization.initial-effective-lrate=0.001 \
            --trainer.optimization.final-effective-lrate=0.0001 \
            --trainer.num-chunk-per-minibatch=128,64 \
            --egs.chunk-width=$chunk_width \
            --egs.dir="$common_egs_dir" \
            --egs.opts="--frames-overlap-per-eg 0" \
            --cleanup.remove-egs=$remove_egs \
            --use-gpu=true \
            --reporting.email="$reporting_email" \
            --feat-dir=data/$spk/train_sp_hires${feat_affix} \
            --tree-dir=$tree_dir/$spk \
            --lat-dir=$lat_dir/$spk \
            --dir=$dir/$spk  || exit 1;
        ) &
    done
    wait;
fi

if [ $stage -le 17 ]; then
    # Note: it's not important to give mkgraph.sh the lang directory with the
    # matched topology (since it gets the topology file from the model).
    for spk in $speakers; do
        (
            for data in $tests; do
                if [ "$data" = "dev" ]; then
                    # Use the lang folder of multi-word utterances for the
                    # (mixed) dev set. Not ideal, but simpler to handle.
                    utils/mkgraph.sh \
                        --self-loop-scale 1.0 data/$spk/lang_test_multi \
                        $tree_dir/$spk $tree_dir/$spk/graph_tgsmall_$data || exit 1;
                else
                    utils/mkgraph.sh \
                        --self-loop-scale 1.0 data/$spk/lang_$data \
                        $tree_dir/$spk $tree_dir/$spk/graph_tgsmall_$data || exit 1;
                fi
            done
        ) &
    done
    wait;
fi

if [ $stage -le 18 ]; then
    frames_per_chunk=$(echo $chunk_width | cut -d, -f1)
    for spk in $speakers; do
        (
        rm $dir/$spk/.error 2>/dev/null || true

        for data in $tests; do
            nspk=$(wc -l <data/$spk/${data}_hires${feat_affix}/spk2utt)  # always 1 for Torgo
            steps/nnet3/decode.sh \
                --online-ivector-dir exp/nnet3${nnet3_affix}${feat_affix}/ivectors_all_speakers_hires${feat_affix} \
                --acwt 1.0 --post-decode-acwt 10.0 \
                --frames-per-chunk $frames_per_chunk \
                --nj $nspk --cmd "$train_big_cmd"  --num-threads 4 \
                $tree_dir/$spk/graph_tgsmall_$data data/$spk/${data}_hires${feat_affix} \
                ${dir}/$spk/decode_tgsmall_${data} || touch $dir/$spk/.error
        done
        [ -f $dir/$spk/.error ] && echo "$0: there was a problem while decoding" && exit 1
        ) &
    done
    wait;
fi
