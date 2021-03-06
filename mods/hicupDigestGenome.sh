#!/bin/bash -e

# Script running hicup including reference genome digestion, read mapping for single 
# and paired DNA reads with bowtie from fastq files
# It expects a fastq file, pairdend, reference genome and digest pattern  as input.
# author: Fabian Buske
# date: Apr 2013

# messages to look out for -- relevant for the QC.sh script:
# QCVARIABLES,Resource temporarily unavailable
# RESULTFILENAME common/<TASK>/Digest_${REFERENCE_NAME}_${HICUP_RENZYME1}_${HICUP_RENZYME2}.txt

echo ">>>>> Digest genome with HiCUP "
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> $(basename $0) $*"

function usage {
echo -e "usage: $(basename $0) -k NGSANE -o OUTDIR [OPTIONS]"
exit
}

if [ ! $# -gt 2 ]; then usage ; fi

#INPUTS
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the NGSANE repository
        -o | --outdir )         shift; OUTDIR=$1 ;; # output dir
        --recover-from )        shift; NGSANE_RECOVERFROM=$1 ;; # attempt to recover from log file
        -h | --help )           usage ;;
        * )                     echo "don't understand "$1
    esac
    shift
done

#PROGRAMS
. $CONFIG
. ${NGSANE_BASE}/conf/header.sh
. $CONFIG

################################################################################
NGSANE_CHECKPOINT_INIT "programs"

# save way to load modules that itself loads other modules
hash module 2>/dev/null && for MODULE in $MODULE_HICUP; do module load $MODULE; done && module list 

export PATH=$PATH_HICUP:$PATH
echo "PATH=$PATH"
#this is to get the full path (modules should work but for path we need the full path and this is the\
# best common denominator)

echo -e "--NGSANE      --\n" $(trigger.sh -v 2>&1)
echo -e "--perl        --\n "$(perl -v | grep "This is perl" )
[ -z "$(which perl)" ] && echo "[ERROR] no perl detected" && exit 1
echo -e "--HiCUP       --\n "$(hicup --version )
[ -z "$(which hicup)" ] && echo "[ERROR] no hicup detected" && exit 1

NGSANE_CHECKPOINT_CHECK
################################################################################
NGSANE_CHECKPOINT_INIT "parameters"

if [ -z "$FASTA" ]; then
    echo "[ERROR] no reference provided (FASTA)"
    exit 1
fi

if [ -z "$HICUP_RENZYME1" ]; then
   echo "[ERROR] No restriction enzyme given!" && exit 1
elif [ -z "$HICUP_RCUTSITE1" ]; then
   echo "[ERROR] Restriction enzyme 1 lacks cutsite pattern!" && exit 1
fi
if [ -n "$HICUP_RENZYME2" ] && [ -z "$HICUP_RCUTSITE2" ]; then
   echo "[ERROR] Restriction enzyme 2 lacks cutsite pattern!" && exit 1
else
    HICUP_RENZYME2="None"
fi

if [ -z "$REFERENCE_NAME" ]; then
    echo "[ERROR] Reference assembly name not detected" && exit 1
fi

DIGESTGENOME="Digest_${REFERENCE_NAME}_${HICUP_RENZYME1}_${HICUP_RENZYME2}.txt"

# delete old bam files unless attempting to recover
if [ -z "$NGSANE_RECOVERFROM" ]; then
    [ -e $OUTDIR/$DIGESTGENOME ] && rm $OUTDIR/$DIGESTGENOME && rm -f $OUTDIR/Digest_${REFERENCE_NAME}_${HICUP_RENZYME1}_${HICUP_RENZYME2}_*.txt
fi

NGSANE_CHECKPOINT_CHECK
################################################################################
NGSANE_CHECKPOINT_INIT "recall files from tape"

if [ -n "$DMGET" ]; then
	dmget -a $(dirname $FASTA)/*
	dmget -a $OUTDIR/*
fi

NGSANE_CHECKPOINT_CHECK
################################################################################
NGSANE_CHECKPOINT_INIT "digest reference"

if [[ $(NGSANE_CHECKPOINT_TASK) == "start" ]]; then


    if [ -z "$HICUP_RCUTSITE2" ]; then
       echo "Restriction Enzyme 1: $HICUP_RENZYME1:$HICUP_RCUTSITE1"
       RUN_COMMAND="$(which perl) $(which hicup_digester)  --outdir $OUTDIR --genome $REFERENCE_NAME --re1 $HICUP_RCUTSITE1,$HICUP_RENZYME1 $FASTA"
       echo $RUN_COMMAND && eval $RUN_COMMAND
    
    else
       echo "Restriction Enzyme 1: $HICUP_RENZYME1:$HICUP_RCUTSITE1 "
       echo "Restriction Enzyme 2: $HICUP_RENZYME2:$HICUP_RCUTSITE2 "
       RUN_COMMAND="$(which perl) $(which hicup_digester)  --outdir $OUTDIR --genome $REFERENCE_NAME --re1 $HICUP_RCUTSITE1,$HICUP_RENZYME1 --re2 $HICUP_RCUTSITE2,$HICUP_RENZYME2 $FASTA"
       echo $RUN_COMMAND && eval $RUN_COMMAND
    fi

    mv $OUTDIR/Digest_${REFERENCE_NAME}_${HICUP_RENZYME1}_${HICUP_RENZYME2}*.txt $OUTDIR/${DIGESTGENOME}
    
    # mark checkpoint
    NGSANE_CHECKPOINT_CHECK $OUTDIR/$DIGESTGENOME

fi
################################################################################
[ -e $OUTDIR/Digest_${REFERENCE_NAME}_${HICUP_RENZYME1}_${HICUP_RENZYME2}.txt.dummy ] && rm $OUTDIR/Digest_${REFERENCE_NAME}_${HICUP_RENZYME1}_${HICUP_RENZYME2}.txt.dummy
echo ">>>>> readmapping with hicup (bowtie) - FINISHED"
echo ">>>>> enddate "`date`

