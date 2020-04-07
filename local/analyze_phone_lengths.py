#!/usr/bin/env python3

# Copyright 2019  Idiap Research Institute (author: Enno Hermann)
# Apache 2.0

import os
import numpy as np
import pandas as pd
from collections import defaultdict

# Different (15ms) frame shift for dysarthric speakers?
different_frame_shift = False

speakers = ['F01', 'F03', 'F04', 'FC01', 'FC02', 'FC03', 'M01', 'M02', 'M03',
            'M04', 'M05', 'MC01', 'MC02', 'MC03', 'MC04']
ctl_speakers = ['FC01', 'FC02', 'FC03', 'MC01', 'MC02', 'MC03', 'MC04']
dys_speakers = ['F01', 'F03', 'F04', 'M01', 'M02', 'M03', 'M04', 'M05']

# The methodology and these phone classes (adapted to Torgo) follow:
# "Phonetic Analysis of Dysarthric Speech Tempo and Applications to Robust
# Personalised Dysarthric Speech Recognition" (Xiong et al. , ICASSP 2019).
phone_classes = {
    'vowels_short': ['AH', 'AO', 'EH', 'IH', 'UH'],
    'vowels_medium': ['AE'],
    'vowels_long': ['AA', 'ER', 'IY', 'UW'],
    'diphthongs': ['AW', 'AY', 'EY', 'OW', 'OY'],
    'glides': ['L', 'R', 'W', 'Y'],
    'stops_unvoiced': ['K', 'P', 'T'],
    'stops_voiced': ['B', 'D', 'G'],
    'nasals': ['M', 'N', 'NG'],
    'fricatives_unvoiced': ['F', 'S', 'SH', 'TH'],
    'fricatives_voiced': ['DH', 'V', 'Z', 'ZH'],
    'affricates_unvoiced': ['CH'],
    'affricates_voiced': ['JH'],
    'aspirates': ['HH']
}

vowels = ['vowels_short', 'vowels_medium', 'vowels_long', 'diphthongs']
consonants = ['glides', 'stops_unvoiced', 'stops_voiced', 'nasals', 'fricatives_unvoiced',
              'fricatives_voiced', 'affricates_unvoiced', 'affricates_voiced', 'aspirates']

phones_txt = 'data/F01/lang/phones.txt'

ali = 'exp/sgmm_ali'

phone_map = {}
with open(phones_txt) as f:
    for line in f:
        phone, phone_id = line.strip().split()
        phone_map[phone_id] = phone

avg_frames = {}

for spk in speakers:
    phone_counts = defaultdict(lambda: defaultdict(int))
    phone_frames = defaultdict(lambda: defaultdict(int))
    # Read training alignments (i.e. from everyone except the test speaker).
    with open(os.path.join(ali, spk, 'phone_lengths.ali')) as f:
        for line in f:
            line = line.strip()
            utt_id, segments = line.split(' ', 1)
            spk_id = utt_id.split('-', 1)[0]
            segments = segments.split(' ; ')
            # Get phone counts and length, indexed by speaker.
            for segment in segments:
                phone_id, frames = segment.split()
                frames = int(frames)
                # Account for the different frame shift.
                if different_frame_shift and spk_id in dys_speakers:
                    frames = frames * 1.5
                phone = phone_map[phone_id]
                phone_counts[spk_id][phone] += 1
                phone_frames[spk_id][phone] += frames

    # for spk_id in speakers:
    #     # print(spk_id)
    #     for phone, frames in sorted(phone_frames[spk_id].items()):
    #         avg_frames = frames / phone_counts[spk_id][phone]
    #         # print("%d: %.2f" % (phone, avg_frames))

    df_frames = pd.DataFrame(phone_frames).sort_index()
    df_counts = pd.DataFrame(phone_counts).sort_index()
    # Store average length of each phone.
    avg_frames['tst_' + spk] = df_frames / df_counts

avg_frames_df = pd.concat({k: pd.DataFrame(v)
                           for k, v in avg_frames.items()}, sort=True)

# Average over the data (i.e. all 14 times it is used in training) across test
# speakers.
avg_frames_mean_df = avg_frames_df.mean(level=1)
avg_frames_std_df = avg_frames_df.std(level=1)
# print(avg_frames_mean_df)
# print(avg_frames_std_df)

# Get average phone lengths for dysarthric and control speakers.
ctl_mean = avg_frames_mean_df[ctl_speakers].mean(axis=1)
dys_mean = avg_frames_mean_df[dys_speakers].mean(axis=1)
ctl_std = avg_frames_mean_df[ctl_speakers].std(axis=1)
dys_std = avg_frames_mean_df[dys_speakers].std(axis=1)
# print(ctl_mean - dys_mean)
# print(ctl_std, dys_std)

# Group phones by class.
grouped_avg_frames_mean_df = pd.DataFrame(columns=avg_frames_mean_df.columns)
for phone_class, phones in phone_classes.items():
    grouped_avg_frames_mean_df.loc[phone_class] = avg_frames_mean_df.loc[phones].mean()

grouped_avg_frames_mean_df.loc['MEAN'] = grouped_avg_frames_mean_df.mean()
grouped_avg_frames_mean_df.loc['Vowels'] = grouped_avg_frames_mean_df.loc[vowels].mean()
grouped_avg_frames_mean_df.loc['Consonants'] = grouped_avg_frames_mean_df.loc[consonants].mean()

grouped_ctl_mean = grouped_avg_frames_mean_df[ctl_speakers].mean(axis=1)

print("Deviation factor from control mean per category:")
for dys_speaker in dys_speakers:
    print(dys_speaker)
    #print(ctl_mean - avg_frames_mean_df[dys_speaker])
    print(grouped_avg_frames_mean_df[dys_speaker] / grouped_ctl_mean)

print()
print(f"Control speakers' mean phoneme duration: {grouped_ctl_mean.loc['MEAN'] * 10:.1f}")
print()
print("Mean phoneme duration (and deviation factor from control mean):")
for speaker in speakers:
    mean_duration = grouped_avg_frames_mean_df[speaker].loc['MEAN'] * 10
    deviation = (grouped_avg_frames_mean_df[speaker] / grouped_ctl_mean).loc['MEAN']
    print(f"{speaker} {mean_duration:.1f} ({deviation:.2f}x)")
