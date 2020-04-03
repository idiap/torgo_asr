#!/usr/bin/env python3

# Copyright 2019  Idiap Research Institute (author: Enno Hermann)
# Apache 2.0

import fnmatch
import numpy as np
import os
import sys

from invoke import run

speakers = "F01 F03 F04 FC01 FC02 FC03 M01 M02 M03 M04 M05 MC01 MC02 MC03 MC04".split()
control_speakers = "FC01 FC02 FC03 MC01 MC02 MC03 MC04".split()
subsets = "single single_nolimit multi".split()

hide_detail = True

if len(sys.argv) > 1:
    exp_dir = sys.argv[1]
else:
    raise ValueError("Need to specify the experiment folder")


def get_wer(spk, subset, lmwt='*'):
    spk_exp_dir = os.path.join(exp_dir, spk)
    decode_dir = fnmatch.filter(os.listdir(spk_exp_dir),
                                'decode*' + subset)
    assert(len(decode_dir) == 1)
    decode_dir = os.path.join(spk_exp_dir, decode_dir[0])

    result = run(f'grep -sH WER {decode_dir}/wer_{lmwt} | utils/best_wer.sh',
                 hide=hide_detail)
    if result.ok:
        return result.stdout
    else:
        raise ValueError("Error in getting WER")


for subset in subsets:
    print(f"### {subset} ###")
    lmwts = []
    for spk in control_speakers:
        wer = get_wer(spk, subset)
        lmwt = int(wer.split('_')[-1])
        lmwts.append(lmwt)

    print(f"Average LMWT on the control speakers: {np.mean(lmwts):.1f}\n")
    average_lmwt = int(round(np.mean(lmwts)))

    print("Now using this to get the WER of all speakers.")
    wer_ctl = []
    wer_dys = []
    for spk in speakers:
        wer = get_wer(spk, subset, average_lmwt)
        wer = float(wer.split()[1])
        if spk in control_speakers:
            wer_ctl.append(wer)
        else:
            wer_dys.append(wer)
    print(f"Average (dys): {np.mean(wer_dys):.1f}")
    print(f"Average (ctl): {np.mean(wer_ctl):.1f}")
    print(f"Average (overall): {np.mean(wer_dys + wer_ctl):.1f}\n")
