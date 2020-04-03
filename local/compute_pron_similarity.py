#!/usr/bin/env python3

# Copyright 2019  Idiap Research Institute (author: Enno Hermann)
# Apache 2.0

import Levenshtein
import numpy as np
from sortedcontainers import SortedList
import string

pron_file = 'data/pronunciations_single'

prons = []
best1_dists = []
best5_dists = []

phoneme_map = {}
reverse_map = {}
map_counter = 0

with open(pron_file) as f:
    for line in f:
        phonemes = line.strip().split()
        chars = []
        for phoneme in phonemes:
            if len(phoneme) > 1:
                if phoneme not in phoneme_map:
                    phoneme_map[phoneme] = string.ascii_lowercase[map_counter]
                    reverse_map[string.ascii_lowercase[map_counter]] = phoneme
                    map_counter += 1
                chars.append(phoneme_map[phoneme])
            else:
                chars.append(phoneme)

        prons.append(''.join(chars))


def pron_str(pron):
    chars = []
    for char in pron:
        if char in reverse_map:
            chars.append(reverse_map[char])
        else:
            chars.append(char)
    return ''.join(chars)


def pron_strs(prons):
    return ' '.join(map(lambda x: pron_str(x), prons))


for pron1 in prons:
    closest_prons = []
    dists = SortedList()
    for pron2 in prons:
        if pron1 != pron2:
            dist = Levenshtein.distance(pron1, pron2)
            if len(dists) > 0 and dist < dists[0]:
                closest_prons = []
            dists.add(dist)
            if dist == dists[0]:
                closest_prons.append(pron2)
    best1_dists.append(dists[0])
    best5_dists.append(np.mean(dists[:5]))
    print("%s - %s (%.2f)" %
          (pron_str(pron1), pron_strs(closest_prons), dists[0]))

best1_dists = np.array(best1_dists)
best5_dists = np.array(best5_dists)
print()
print("For %.1f %% of pronuncations the shortest Levenshtein distance is 1" %
      (100 * (best1_dists == 1).sum() / len(dists)))
print("1-best average Levenshtein distance: %.2f" % best1_dists.mean())
print("5-best average Levenshtein distance: %.2f" % best5_dists.mean())
