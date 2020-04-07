#!/bin/bash

# Copyright 2012  Vassil Panayotov
#           2016  Cristina Espana-Bonet
#           2018  Idiap Research Institute (Author: Enno Hermann)

# Apache 2.0

. ./cmd.sh
. ./path.sh

stage=0
train=false

DYS_SPEAKERS="F01 F03 F04 M01 M02 M03 M04 M05"
CTL_SPEAKERS="FC01 FC02 FC03 MC01 MC02 MC03 MC04"
ALL_SPEAKERS="$DYS_SPEAKERS $CTL_SPEAKERS"

# Speakers to evaluate.
speakers=$ALL_SPEAKERS

# Tests to run.
tests="test_single test_single_nolimit test_multi"

# Word position dependent phones?
pos_dep_phones=false

# Different (15ms) frame shift for dysarthric speakers?
different_frame_shift=true

# Number of leaves and total gaussians
leaves=1800
gaussians=9000

nj_decode=1

. utils/parse_options.sh

set -euo pipefail

data_all=data/all_speakers

# Data extraction
if [ $stage -le 0 ]; then
    rm -rdff data/*
    # Initial extraction of the data.
    local/torgo_data_prep.sh || exit 1
fi

# Make MFCC features.
if [ $stage -le 1 ]; then
    if [ $different_frame_shift = true ]; then
        mfcc_config_dys=conf/mfcc_dysarthric.conf
    else
        mfcc_config_dys=conf/mfcc.conf
    fi
    local/torgo_make_mfcc.sh \
        --cmd "$train_cmd" --nj 15 --mfcc-config-dys $mfcc_config_dys \
        $data_all || exit 1;
    steps/compute_cmvn_stats.sh $data_all || exit 1;
    utils/fix_data_dir.sh ${data_all}
fi

# Removing too short utterances (and other bad ones if not discarded earlier).
if [ $stage -le 2 ]; then
    bad_utts=conf/bad_utts
    utils/data/get_utt2num_frames.sh $data_all
    # Discard utterances with less than 35 frames.
    awk '$2 < 35 { print $1 " # too short (" $2 " frames)" ;}' \
        $data_all/utt2num_frames >> $bad_utts
    sort -u -o $bad_utts $bad_utts
    utils/filter_scp.pl --exclude $bad_utts $data_all/feats.scp \
                        > $data_all/feats_filtered.scp
    mv $data_all/feats_filtered.scp $data_all/feats.scp
    utils/fix_data_dir.sh $data_all
fi

# Split data into 14 training speakers and 1 test speakers for each specified
# test speaker.
if [ $stage -le 2 ]; then
    tmp=$(mktemp -d /tmp/${USER}_XXXXX)
    # Identify single- and multi-word utterances to evaluate them separately.
    cat $data_all/text | awk 'NF==2' > $tmp/single.utts
    cat $data_all/text | awk 'NF>2' > $tmp/multi.utts
    
    for spk in $speakers; do
        echo $spk > $tmp/$spk
        utils/subset_data_dir_tr_cv.sh --cv-spk-list "$tmp/$spk" $data_all \
                                       data/${spk}/train data/$spk/test
        utils/subset_data_dir.sh --utt-list $tmp/single.utts \
                                 data/$spk/test data/$spk/test_single
        utils/subset_data_dir.sh --utt-list $tmp/single.utts \
                                 data/$spk/test data/$spk/test_single_nolimit
        utils/subset_data_dir.sh --utt-list $tmp/multi.utts \
                                 data/$spk/test data/$spk/test_multi
    done
fi

# Prepare LM and dictionary.
if [ $stage -le 3 ]; then
    # Prepare ARPA LM and vocabulary using SRILM, separately for 1- and
    # multi-word utterances.
    local/torgo_prepare_lm.sh || exit 1

    # Prepare the lexicon and various phone lists
    # Pronunciations for OOV words are obtained using a pre-trained Sequitur model
    local/torgo_prepare_dict.sh || exit 1
    
    for spk in $speakers; do
        for utts in single single_nolimit multi; do
            # Prepare data/lang folder.
            echo ""
            echo "=== Preparing data/lang and data/local/lang directories ..."
            echo ""
            utils/prepare_lang.sh --position-dependent-phones $pos_dep_phones \
                                  data/local/dict '!SIL' data/$spk/local/lang \
                                  data/$spk/lang || exit 1

            # Prepare G.fst
            local/torgo_prepare_grammar.sh $spk $utts || exit 1
        done
    done
fi

# Train monophone models.
if [ $stage -le 4 ] && [ "$train" = true ] ; then
    for spk in $speakers; do
        rm -rdf exp/mono/$spk
        mkdir -p exp/mono/$spk
        nj=$(cat data/$spk/train/spk2utt | wc -l)
        steps/train_mono.sh --nj $nj --cmd "$train_cmd" \
                            data/$spk/train data/$spk/lang exp/mono/$spk \
                            >& exp/mono/$spk/train.log &
    done
    wait;
fi

# Monophone decoding.
if [ $stage -le 5 ]; then
    for spk in $speakers; do
        (
        for x in $tests; do     
            utils/mkgraph.sh data/$spk/lang_$x exp/mono/$spk \
                             exp/mono/$spk/graph_$x >& exp/mono/$spk/mkgraph.log
            steps/decode.sh --nj $nj_decode --cmd "$decode_cmd" \
                            exp/mono/$spk/graph_$x data/$spk/$x \
                            exp/mono/$spk/decode_$x >& exp/mono/$spk/decode.log
        done
        ) &
    done
    wait;
fi

# Train tri1 (first triphone pass).
if [ $stage -le 6 ] && [ "$train" = true ] ; then
    for spk in $speakers; do
        (
        rm -rdf exp/mono_ali/$spk exp/tri1/$spk
        mkdir -p exp/mono_ali/$spk exp/tri1/$spk
        nj=$(cat data/$spk/train/spk2utt | wc -l)
        steps/align_si.sh --nj $nj --cmd "$train_cmd" \
                          data/$spk/train data/$spk/lang exp/mono/$spk \
                          exp/mono_ali/$spk >& exp/mono_ali/$spk/align.log

        steps/train_deltas.sh --cmd "$train_cmd" $leaves $gaussians \
                              data/$spk/train data/$spk/lang exp/mono_ali/$spk \
                              exp/tri1/$spk >& exp/tri1/$spk/train.log
        ) &
    done
    wait;
fi

# Decode tri1.
if [ $stage -le 7 ]; then
    for spk in $speakers; do
        (
        for x in $tests; do
            utils/mkgraph.sh data/$spk/lang_$x exp/tri1/$spk \
                             exp/tri1/$spk/graph_$x >& exp/tri1/$spk/mkgraph.log
            steps/decode.sh --nj $nj_decode --cmd "$decode_cmd" \
                            exp/tri1/$spk/graph_$x data/$spk/$x \
                            exp/tri1/$spk/decode_$x >& exp/tri1/$spk/decode.log
        done
        ) &
    done
    wait;
fi

# Train tri2 (LDA+MLLT).
if [ $stage -le 8 ] && [ "$train" = true ] ; then
    for spk in $speakers; do
        (
        rm -rdf exp/tri1_ali/$spk exp/tri2/$spk
        mkdir -p exp/tri1_ali/$spk exp/tri2/$spk
        nj=$(cat data/$spk/train/spk2utt | wc -l)
        steps/align_si.sh --nj $nj --cmd "$train_cmd" --use-graphs true \
                          data/$spk/train data/$spk/lang exp/tri1/$spk \
                          exp/tri1_ali/$spk >& exp/tri1_ali/$spk/align.log

        steps/train_lda_mllt.sh --cmd "$train_cmd" $leaves $gaussians \
                                data/$spk/train data/$spk/lang \
                                exp/tri1_ali/$spk exp/tri2/$spk >& exp/tri2/$spk/train.log
        ) &
    done
    wait;
fi

# Decode tri2.
if [ $stage -le 9 ]; then
    for spk in $speakers; do
        (
        for x in $tests; do
            utils/mkgraph.sh data/$spk/lang_$x exp/tri2/$spk \
                             exp/tri2/$spk/graph_$x >& exp/tri2/$spk/mkgraph.log
            steps/decode.sh --nj $nj_decode --cmd "$decode_cmd" \
                            exp/tri2/$spk/graph_$x data/$spk/$x \
                            exp/tri2/$spk/decode_$x >& exp/tri2/$spk/decode.log
        done
        ) &
    done
    wait;
fi

# Train tri3 (LDA+MLLT+SAT).
if [ $stage -le 10 ] && [ "$train" = true ] ; then
    for spk in $speakers; do
        (
        rm -rdf exp/tri2_ali/$spk exp/tri3/$spk
        mkdir -p exp/tri2_ali/$spk exp/tri3/$spk
        nj=$(cat data/$spk/train/spk2utt | wc -l)
        steps/align_si.sh --nj $nj --cmd "$train_cmd" --use-graphs true \
                          data/$spk/train data/$spk/lang exp/tri2/$spk \
                          exp/tri2_ali/$spk >& exp/tri2_ali/$spk/align.log
        steps/train_sat.sh --cmd "$train_cmd" $leaves $gaussians data/$spk/train data/$spk/lang \
                           exp/tri2_ali/$spk exp/tri3/$spk >& exp/tri3/$spk/train.log
        ) &
    done
    wait;
fi

# Decode tri3.
if [ $stage -le 11 ]; then
    for spk in $speakers; do
        (
        for x in $tests; do
            utils/mkgraph.sh data/$spk/lang_$x exp/tri3/$spk \
                             exp/tri3/$spk/graph_$x >& exp/tri3/$spk/mkgraph.log
            steps/decode_fmllr.sh --nj $nj_decode --cmd "$decode_cmd" \
                                  exp/tri3/$spk/graph_$x data/$spk/$x \
                                  exp/tri3/$spk/decode_$x >& exp/tri3/$spk/decode.log
        done
        ) &
    done
    wait;
fi

# Train SGMM.
if [ $stage -le 12 ] && [ "$train" = true ] ; then
    for spk in $speakers; do
        (
        rm -rdf exp/tri3_ali/$spk exp/ubm/$spk exp/sgmm/$spk
        mkdir -p exp/tri3_ali/$spk exp/ubm/$spk exp/sgmm/$spk
        nj=$(cat data/$spk/train/spk2utt | wc -l)
        steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" --use-graphs true \
                             data/$spk/train data/$spk/lang exp/tri3/$spk \
                             exp/tri3_ali/$spk >& exp/tri3_ali/$spk/align.log
        steps/train_ubm.sh --silence-weight 0.5 --cmd "$train_cmd" 400 \
                           data/$spk/train data/$spk/lang exp/tri3_ali/$spk \
                           exp/ubm/$spk >& exp/ubm/$spk/train.log
        sgmm_leaves=8000
        sgmm_substates=19000
        steps/train_sgmm2.sh --cmd "$train_cmd" $sgmm_leaves $sgmm_substates \
                             data/$spk/train data/$spk/lang exp/tri3_ali/$spk \
                             exp/ubm/$spk/final.ubm exp/sgmm/$spk \
                             >& exp/sgmm/$spk/train.log
        ) &
    done
    wait;
fi

# Decode SGMM.
if [ $stage -le 13 ]; then
    for spk in $speakers; do
        (
        for x in $tests; do
            utils/mkgraph.sh data/$spk/lang_$x exp/sgmm/$spk \
                             exp/sgmm/$spk/graph_$x >& exp/sgmm/$spk/mkgraph.log
            steps/decode_sgmm2.sh --use-fmllr true --nj $nj_decode \
                                  --cmd "$decode_cmd" \
                                  --transform-dir exp/tri3/$spk/decode_$x \
                                  exp/sgmm/$spk/graph_$x data/$spk/$x \
                                  exp/sgmm/$spk/decode_$x \
                                  >& exp/sgmm/$spk/decode.log
        done
        ) &
    done
    wait;
fi

# Train SGMM+MMI.
if [ $stage -le 14 ] ; then
    for spk in $speakers; do
        (
        rm -rdf exp/sgmm_ali/$spk exp/sgmm_denlats/$spk exp/sgmm_mmi_b0.1/$spk
        mkdir -p exp/sgmm_ali/$spk exp/sgmm_denlats/$spk exp/sgmm_mmi_b0.1/$spk
        nj=$(cat data/$spk/train/spk2utt | wc -l)
        steps/align_sgmm2.sh --nj $nj --cmd "$train_cmd" \
                             --transform-dir exp/tri3_ali/$spk --use-graphs true \
                             --use-gselect true data/$spk/train \
                             data/$spk/lang exp/sgmm/$spk exp/sgmm_ali/$spk \
                             >& exp/sgmm_ali/$spk/align.log
        if [ "$train" = true ]; then
            steps/make_denlats_sgmm2.sh --nj $nj --sub-split 1 --cmd "$train_cmd" \
                                        --transform-dir exp/tri3_ali/$spk \
                                        data/$spk/train data/$spk/lang \
                                        exp/sgmm_ali/$spk exp/sgmm_denlats/$spk \
                                        >& exp/sgmm_denlats/$spk/make.log
            steps/train_mmi_sgmm2.sh --cmd "$train_cmd" \
                                     --transform-dir exp/tri3_ali/$spk --boost 0.1 \
                                     data/$spk/train data/$spk/lang exp/sgmm_ali/$spk \
                                     exp/sgmm_denlats/$spk exp/sgmm_mmi_b0.1/$spk \
                                     >& exp/sgmm_mmi_b0.1/$spk/train.log
        fi
        ) &
    done
    wait;
fi

# Decode SGMM+MMI.
if [ $stage -le 15 ]; then
    for spk in $speakers; do
        (
        for x in $tests; do
            for iter in 1 2 3 4; do
                steps/decode_sgmm2_rescore.sh \
                    --cmd "$decode_cmd" --iter $iter \
                    --transform-dir exp/tri3/$spk/decode_$x \
                    data/$spk/lang_$x data/$spk/$x exp/sgmm/$spk/decode_$x \
                    exp/sgmm_mmi_b0.1/$spk/decode_${x}_it$iter >& exp/sgmm_mmi_b0.1/$spk/decode.log
            done
        done
        ) &
    done
    wait;
fi
