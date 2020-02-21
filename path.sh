#export KALDI_ROOT=`pwd`/../../..
export KALDI_ROOT=/veu4/usuaris30/cristinae/soft/kaldi-trunk
export PATH=$PWD/utils/:$KALDI_ROOT/src/bin:$KALDI_ROOT/tools/openfst/bin:$KALDI_ROOT/src/fstbin/:$KALDI_ROOT/src/gmmbin/:$KALDI_ROOT/src/featbin/:$KALDI_ROOT/src/lm/:$KALDI_ROOT/src/sgmmbin/:$KALDI_ROOT/src/sgmm2bin/:$KALDI_ROOT/src/fgmmbin/:$KALDI_ROOT/src/latbin/:$KALDI_ROOT/src/onlinebin/:$KALDI_ROOT/src/nnetbin/:$KALDI_ROOT/src/nnet2bin/:$KALDI_ROOT/src/nnet3bin/:$KALDI_ROOT/src/online2bin/:$KALDI_ROOT/src/ivectorbin/:$KALDI_ROOT/src/kwsbin/:$PWD:$PATH

#  IRSTLM
export IRSTLM=/veu4/usuaris30/cristinae/soft/kaldi-trunk/tools/extras/irstlm
export PATH=${PATH}:${IRSTLM}/bin

#  ISRLM                                           
export SRILM=/veu4/usuaris30/cristinae/soft/kaldi-trunk/tools/extras/srilm
export PATH=${PATH}:${SRILM}/bin/i686-m64

# SEQUITUR
export SEQUITUR=/veu4/usuaris30/cristinae/soft/kaldi-trunk/tools/sequitur-g2p
export PATH=$PATH:${SEQUITUR}/bin
_site_packages=`find ${SEQUITUR}/lib64 -type d -regex '.*python.*/site-packages'`
export PYTHONPATH=$PYTHONPATH:$_site_packages

# Torgo data
export DATA_ORIG="/veu4/usuaris30/xtrans/data/LDC/LDC2012S02/data"    
export DATA_ROOT="/veu4/usuaris30/cristinae/soft/kaldi-trunk/egs/torgo/s5"    

if [ -z $DATA_ROOT ]; then
  echo "You need to set \"DATA_ROOT\" variable in path.sh to point to the directory where Torgo data will be"
  exit 1
fi

# Make sure that MITLM shared libs are found by the dynamic linker/loader
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$(pwd)/tools/mitlm-svn/lib

# Needed for "correct" sorting
export LC_ALL=C
