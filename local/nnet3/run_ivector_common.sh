#!/bin/bash

# Cristina Espana-Bonet
# Modified to deal with the Torgo DB and to consider different time shifts when extracting 
# the features according to the nature of the speaker (dysartric vs. control)

# this script is called from scripts like run_ms.sh; it does the common stages
# of the build, such as feature extraction.
# This is actually the same as local/online/run_nnet2_common.sh, except
# for the directory names.

stage=0
nnet3_affix=
feat_affix=""
speakers="F01 F03 F04 FC01 FC02 FC03 M01 M02 M03 M04 M05 MC01 MC02 MC03 MC04"

data_all=data/all_speakers

# Different (15ms) frame shift for dysarthric speakers?
different_frame_shift=false

. cmd.sh
. ./path.sh
. ./utils/parse_options.sh

# speakers="F01 F03 F04 M01 M02 M03 M04 M05"
# nnet3_affix=_dys_only
# data_all=data/dys_only/dys_speakers

if [ $different_frame_shift = true ]; then
    mfcc_config_dys=conf/mfcc_dysarthric.conf
    mfcc_hires_config_dys=conf/mfcc_hires${feat_affix}_dysarthric.conf
else
    mfcc_config_dys=conf/mfcc.conf
    mfcc_hires_config_dys=conf/mfcc_hires${feat_affix}.conf
fi

for f in $data_all/feats.scp ; do
    if [ ! -f $f ]; then
        echo "$0: expected file $f to exist"
        exit 1
    fi
done

if [ $stage -le 1 ]; then
  # Although the nnet will be trained by high resolution data, we still have to
  # perturb the normal data to get the alignment _sp stands for speed-perturbed
  echo "$0: preparing directory for low-resolution speed-perturbed data (for alignment)"
  utils/data/perturb_data_dir_speed_3way.sh $data_all ${data_all}_sp
  echo "$0: making MFCC features for low-resolution speed-perturbed data"
  local/torgo_make_mfcc.sh --cmd "$train_cmd" --nj 8 \
                           --mfcc-config-dys $mfcc_config_dys ${data_all}_sp || exit 1;
  steps/compute_cmvn_stats.sh ${data_all}_sp || exit 1;
  utils/fix_data_dir.sh ${data_all}_sp
fi

if [ $stage -le 2 ]; then
  # Create high-resolution MFCC features (with 40 cepstra instead of 13).
  # this shows how you can split across multiple file-systems.
  echo "$0: creating high-resolution MFCC features"
  utils/copy_data_dir.sh ${data_all}_sp ${data_all}_sp_hires${feat_affix}

  # do volume-perturbation on the training data prior to extracting hires
  # features; this helps make trained nnets more invariant to test data volume.
  utils/data/perturb_data_dir_volume.sh ${data_all}_sp_hires${feat_affix} || exit 1;

  local/torgo_make_mfcc.sh --cmd "$train_cmd" --nj 8 \
                           --mfcc-config conf/mfcc_hires${feat_affix}.conf \
                           --mfcc-config-dys $mfcc_hires_config_dys \
                           ${data_all}_sp_hires${feat_affix} || exit 1;
  steps/compute_cmvn_stats.sh ${data_all}_sp_hires${feat_affix} || exit 1;
  utils/fix_data_dir.sh ${data_all}_sp_hires${feat_affix} || exit 1;

  # Also extract high-resolution MFCCs on the non-perturbed data for testing.
  utils/copy_data_dir.sh ${data_all} ${data_all}_hires${feat_affix}
  local/torgo_make_mfcc.sh --cmd "$train_cmd" --nj 8 \
                           --mfcc-config conf/mfcc_hires${feat_affix}.conf \
                           --mfcc-config-dys $mfcc_hires_config_dys \
                           ${data_all}_hires${feat_affix} || exit 1;
  steps/compute_cmvn_stats.sh ${data_all}_hires${feat_affix} || exit 1;
  utils/fix_data_dir.sh ${data_all}_hires${feat_affix} || exit 1;
fi

if [ $stage -le 3 ]; then
  echo "$0: computing a subset of data to train the diagonal UBM."
  # We don't do this 15 times separately for each test speaker because the
  # UBM and subsequent i-vector extractor training is done in an unsupervised
  # manner. Improvements from i-vectors would be minor anyway, so that
  # leaving out the test speaker here will have a negligible effect.
  
  # We'll use about a quarter of the data.
  mkdir -p exp/nnet3${nnet3_affix}${feat_affix}/diag_ubm
  temp_data_root=exp/nnet3${nnet3_affix}${feat_affix}/diag_ubm

  num_utts_total=$(wc -l <${data_all}_sp_hires${feat_affix}/utt2spk)
  num_utts=$[$num_utts_total/4]
  utils/data/subset_data_dir.sh ${data_all}_sp_hires${feat_affix} \
     $num_utts ${temp_data_root}/all_speakers_sp_hires${feat_affix}_subset

  echo "$0: computing a PCA transform from the hires data."
  steps/online/nnet2/get_pca_transform.sh --cmd "$train_cmd" \
      --splice-opts "--left-context=3 --right-context=3" \
      --max-utts 10000 --subsample 2 \
       ${temp_data_root}/all_speakers_sp_hires${feat_affix}_subset \
       exp/nnet3${nnet3_affix}${feat_affix}/pca_transform

  echo "$0: training the diagonal UBM."
  # Use 512 Gaussians in the UBM.
  steps/online/nnet2/train_diag_ubm.sh --cmd "$train_cmd" --nj 24 \
    --num-frames 700000 \
    --num-threads 4 \
    ${temp_data_root}/all_speakers_sp_hires${feat_affix}_subset 512 \
    exp/nnet3${nnet3_affix}${feat_affix}/pca_transform exp/nnet3${nnet3_affix}${feat_affix}/diag_ubm
fi

if [ $stage -le 4 ]; then
  # Train the iVector extractor.  Use all of the speed-perturbed data since iVector extractors
  # can be sensitive to the amount of data.  The script defaults to an iVector dimension of
  # 100.
  echo "$0: training the iVector extractor"
  steps/online/nnet2/train_ivector_extractor.sh \
      --cmd "$train_big_cmd" --nj 10 --num-processes 1 \
      ${data_all}_sp_hires${feat_affix} exp/nnet3${nnet3_affix}${feat_affix}/diag_ubm \
      exp/nnet3${nnet3_affix}${feat_affix}/extractor || exit 1;
fi

if [ $stage -le 5 ]; then
  # We extract iVectors on the speed-perturbed training data after combining
  # short segments, which will be what we train the system on.  With
  # --utts-per-spk-max 2, the script pairs the utterances into twos, and treats
  # each of these pairs as one speaker; this gives more diversity in iVectors..
  # Note that these are extracted 'online'.

  # note, we don't encode the 'max2' in the name of the ivectordir even though
  # that's the data we extract the ivectors from, as it's still going to be
  # valid for the non-'max2' data, the utterance list is the same.

  ivectordir=exp/nnet3${nnet3_affix}${feat_affix}/ivectors_all_speakers_sp_hires${feat_affix}

  # having a larger number of speakers is helpful for generalization, and to
  # handle per-utterance decoding well (iVector starts at zero).
  temp_data_root=${ivectordir}
  utils/data/modify_speaker_info.sh --utts-per-spk-max 2 \
    ${data_all}_sp_hires${feat_affix} ${temp_data_root}/all_speakers_sp_hires${feat_affix}_max2

  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_big_cmd" --nj 8 \
    ${temp_data_root}/all_speakers_sp_hires${feat_affix}_max2 \
    exp/nnet3${nnet3_affix}${feat_affix}/extractor $ivectordir

  # Also extract iVectors for the non-perturbed data for testing.
  steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_big_cmd" --nj 8 \
    ${data_all}_hires${feat_affix} exp/nnet3${nnet3_affix}${feat_affix}/extractor \
    exp/nnet3${nnet3_affix}${feat_affix}/ivectors_all_speakers_hires${feat_affix}
fi

exit 0
