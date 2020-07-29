# Torgo ASR

## Description
This is a Kaldi recipe to build automatic speech recognition systems on the
[Torgo corpus](http://www.cs.toronto.edu/~complingweb/data/TORGO/torgo.html) of
dysarthric speech.

## Setup

Update the `KALDI_ROOT` and `DATA_ORIG` variables in `path.sh` to point to the
correct locations for your Kaldi installation and the Torgo corpus. Then run
the following:

```sh
source path.sh
ln -s $KALDI_ROOT/egs/wsj/s5/{steps,utils} .
```

Some scripts in `local/` also require the following Python packages:

```
invoke numpy pandas python-Levenshtein
```

## Usage

The following instructions allow to train ASR systems on Torgo and to reproduce
results from the paper.

### Train ASR systems

```sh
# HMM/GMM systems:
./run.sh

# LF-MMI (TDNN-F) systems:
./run_tdnnf.sh

# CE (TDNN-LSTM) systems:
./local/nnet3/run_tdnn_lstm.sh

# Show WER:
./local/get_wer.py exp/sgmm
```

### Corpus statistics

Torgo corpus statistics:

```sh
./local/corpus_statistics.sh
```

### Pronunciation similarity

How similar are the isolated words to each other? First retrieve the phonetic
representation for each word, then analyse the similarity of pronunciations:

```sh
./local/get_prons.sh > data/pronunciations_single
./local/compute_pron_similarity.py
```

### Phone duration
We analysed how mean phoneme duration and WER are correlated.

```sh
# Get phone alignments with duration information:
./local/get_phone_alignments.sh exp/sgmm

# Compute mean phoneme durations:
./local/analyze_phone_lengths.py
```

## Citation

Please cite the following paper if you use this code for your research.

```BibTeX
@inproceedings{hermann2020.asr,
    author = "Hermann, Enno and Magimai.-Doss, Mathew",
    title = "Dysarthric Speech Recognition with Lattice-Free {MMI}",
    booktitle = "Proceedings International Conference on Acoustics, Speech, and Signal Processing (ICASSP)",
    pages = "6109--6113",
    year = "2020",
    doi = "10.1109/ICASSP40776.2020.9053549"
}
```

The code is based on [an earlier recipe](https://github.com/cristinae/ASRdys) by
Cristina España-Bonet and José A. R. Fonollosa.
