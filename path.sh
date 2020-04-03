# Location of your Kaldi installation
export KALDI_ROOT=

# Location of the Torgo corpus (.../torgo/data/)
export CORPUS=

if [ -z $KALDI_ROOT ]; then
  echo "You need to set the KALDI_ROOT variable in path.sh to point to the location of your Kaldi installation."
  exit 1
elif [ -z $CORPUS ]; then
  echo "You need to set the CORPUS variable in path.sh to point to the location of the Torgo corpus."
  exit 1
fi

[ -f $KALDI_ROOT/tools/env.sh ] && . $KALDI_ROOT/tools/env.sh
[ -f $KALDI_ROOT/tools/extras/env.sh ] && . $KALDI_ROOT/tools/extras/env.sh
export PATH=$PWD/utils/:$KALDI_ROOT/tools/openfst/bin:$PWD:$PATH
[ ! -f $KALDI_ROOT/tools/config/common_path.sh ] && echo >&2 "The standard file $KALDI_ROOT/tools/config/common_path.sh is not present -> Exit!" && exit 1
. $KALDI_ROOT/tools/config/common_path.sh
export LC_ALL=C
