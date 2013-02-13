#!/bin/bash

# BWA calling script
# author: Denis C. Bauer
# date: Nov.2010

# messages to look out for -- relevant for the QC.sh script:
# QCVARIABLES,We are loosing reads,MAPQ should be 0 for unmapped read,no such file,file not found,bwa.sh: line,Resource temporarily unavailable

#module load bwa
#BWA=bwa

echo ">>>>> readmapping with BWA "
echo ">>>>> startdate "`date`
echo ">>>>> hostname "`hostname`
echo ">>>>> job_name "$JOB_NAME
echo ">>>>> job_id "$JOB_ID
echo ">>>>> bwa.sh $*"


function usage {
echo -e "usage: $(basename $0) -k HISEQINF -f FASTQ -r REFERENCE -o OUTDIR [OPTIONS]

Script running read mapping for single and paired DNA reads from fastq files
It expects a fastq file, pairdend, reference genome  as input and 
It runs BWA, converts the output to .bam files, adds header information and
writes the coverage information for IGV.

required:
  -k | --toolkit <path>     location of the HiSeqInf repository 
  -f | --fastq <file>       fastq file
  -r | --reference <file>   reference genome
  -o | --outdir <path>      output dir

options:
  -t | --threads <nr>       number of CPUs to use (default: 1)
  -m | --memory <nr>        memory available (default: 2)
  -i | --rgid <name>        read group identifier RD ID (default: exp)
  -l | --rglb <name>        read group library RD LB (default: qbi)
  -p | --rgpl <name>        read group platform RD PL (default: illumna)
  -s | --rgsi <name>        read group sample RG SM prefac (default: )
  -u | --rgpu <name>        read group platform unit RG PU (default:flowcell )
  -R | --region <ps>        region of specific interest, e.g. targeted reseq
                             format chr:pos-pos
  -S | --sam                do not convert to bam file (default confert); not the
                             resulting sam file is not duplicate removed
  --forceSingle             run single end eventhough second read is present
  --oldIllumina             old Illumina encoding 1.3+
  --noMapping
  --fastqName               name of fastq file ending (fastq.gz)
"
exit
}


if [ ! $# -gt 3 ]; then usage ; fi



#DEFAULTS
MYTHREADS=1
MYMEMORY=2
EXPID="exp"           # read group identifier RD ID
LIBRARY="qbi"         # read group library RD LB
PLATFORM="illumina"   # read group platform RD PL
UNIT="flowcell"       # read group platform unit RG PU
DOBAM=1               # do the bam file
FORCESINGLE=0
NOMAPPING=0
FASTQNAME=""
QUAL="" # standard Sanger


#INPUTS
while [ "$1" != "" ]; do
    case $1 in
        -k | --toolkit )        shift; CONFIG=$1 ;; # location of the HiSeqInf repository
        -t | --threads )        shift; MYTHREADS=$1 ;; # number of CPUs to use
	-m | --memory )         shift; MYMEMORY=$1 ;; # memory used
        -f | --fastq )          shift; f=$1 ;; # fastq file
        -r | --reference )      shift; FASTA=$1 ;; # reference genome
        -o | --outdir )         shift; MYOUT=$1 ;; # output dir
	-i | --rgid )           shift; EXPID=$1 ;; # read group identifier RD ID
	-l | --rglb )           shift; LIBRARY=$1 ;; # read group library RD LB
	-p | --rgpl )           shift; PLATFORM=$1 ;; # read group platform RD PL
	-s | --rgsi )           shift; SAMPLEID=$1 ;; # read group sample RG SM (pre)
	-u | --rgpu )           shift; UNIT=$1 ;; # read group platform unit RG PU 
	-R | --region )         shift; SEQREG=$1 ;; # (optional) region of specific interest, e.g. targeted reseq
        -S | --sam )            DOBAM=0 ;;
	--fastqName )           shift; FASTQNAME=$1 ;; #(name of fastq or fastq.gz)
	--forceSingle )         FORCESINGLE=1;;
	--noMapping )           NOMAPPING=1;;
	--oldIllumina )         QUAL="-S";;   # old illumina encoding 1.3+
        -h | --help )           usage ;;
        * )                     echo "don't understand "$1
    esac
    shift
done

JAVAPARAMS="-Xmx"$MYMEMORY"g" # -XX:ConcGCThreads=1 -XX:ParallelGCThreads=1 -XX:MaxDirectMemorySize=4G"

#HISEQINF=$1   # location of the HiSeqInf repository
#MYTHREADS=$2    # number of CPUs to use
#f=$3          # fastq file
#FASTA=$4      # reference genome
#MYOUT=$5        # output dir
#EXPID=$6      # read group identifier RD ID
#LIBRARY=$7    # read group library RD LB
#PLATFORM=$8   # read group platform RD PL
#SAMPLEID=$9   # read group sample RG SM (pre)
#SEQREG=$10    # (optional) region of specific interest, e.g. targeted reseq

#PROGRAMS
. $CONFIG
. $HISEQINF/pbsTemp/header.sh
. $CONFIG
export PATH=$PATH:$(basename $SAMTOOLS)

#if [ -n "$FASTQNAME" ]; then FASTQ=$FASTQNAME ; fi

module load R
module load jdk

n=`basename $f`

# delete old bam file
if [ -e $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam} ]; then rm $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam}; fi
if [ -e $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam}.stats ]; then rm $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam}.stats; fi
if [ -e $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam}.dupl ]; then rm $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam}.dupl; fi

dmget -a $(dirname $FASTA)/*
dmget -a $(dirname $SAMTOOLS)/*
dmget -a $(dirname $BWA)/*
dmget -a $PICARD/*


#is paired ?
if [ -e ${f/$READONE/$READTWO} ] && [ "$FORCESINGLE" = 0 ]; then
    PAIRED="1"
    dmget -a $f
    dmget -a ${f/$READONE/$READTWO}
else
    PAIRED="0"
    dmget -a $f
fi

#is ziped ?
ZCAT="zcat"
if [[ $f != *.fastq.gz ]]; then ZCAT="cat"; fi

FULLSAMPLEID=$SAMPLEID"${n/'_'$READONE.$FASTQ/}"
echo ">>>>> full sample ID "$FULLSAMPLEID

# generating the index files
if [ ! -e $FASTA.bwt ]; then echo ">>>>> make .bwt"; $BWA index -a bwtsw $FASTA; fi
if [ ! -e $FASTA.fai ]; then echo ">>>>> make .fai"; $SAMTOOLS faidx $FASTA; fi

echo "********* mapping"
# Paired read
if [ "$PAIRED" = 1 ]
then
    if [ "$NOMAPPING" = 0 ]; then
    echo "********* PAIRED READS"
    $BWA aln $QUAL -t $MYTHREADS $FASTA $f > $MYOUT/${n/$FASTQ/sai}
    $BWA aln $QUAL -t $MYTHREADS $FASTA ${f/$READONE/$READTWO} > $MYOUT/${n/$READONE.$FASTQ/$READTWO.sai}
    $BWA sampe $FASTA $MYOUT/${n/$FASTQ/sai} $MYOUT/${n/$READONE.$FASTQ/$READTWO.sai} \
	-r "@RG\tID:$EXPID\tSM:$FULLSAMPLEID\tPL:$PLATFORM\tLB:$LIBRARY" \
	$f ${f/$READONE/$READTWO} >$MYOUT/${n/'_'$READONE.$FASTQ/.$ALN.sam}

    rm $MYOUT/${n/$FASTQ/sai}
    rm $MYOUT/${n/$READONE.$FASTQ/$READTWO.sai}
    fi
    READ1=`$ZCAT $f | wc -l | gawk '{print int($1/4)}' `
    READ2=`$ZCAT ${f/$READONE/$READTWO} | wc -l | gawk '{print int($1/4)}' `
    let FASTQREADS=$READ1+$READ2
# Single read
else
    echo "********* SINGLE READS"
    $BWA aln $QUAL -t $MYTHREADS $FASTA $f > $MYOUT/${n/$FASTQ/sai}

    $BWA samse $FASTA $MYOUT/${n/$FASTQ/sai} \
	-r "@RG\tID:$EXPID\tSM:$FULLSAMPLEID\tPL:$PLATFORM\tLB:$LIBRARY" \
	$f >$MYOUT/${n/'_'$READONE.$FASTQ/.$ALN.sam}

#    $BWA samse $FASTA $MYOUT/${n/$FASTQ/sai} \
#	-i $EXPID \
#	-m $FULLSAMPLEID \
#	-p $PLATFORM \
#	-l $LIBRARY \
#	$f >$MYOUT/${n/'_'$READONE.$FASTQ/.$ALN.sam}

    rm $MYOUT/${n/$FASTQ/sai}
    let FASTQREADS=`$ZCAT $f | wc -l | gawk '{print int($1/4)}' `
fi

# exit if only the sam file is required
if [ "$DOBAM" = 0 ]; then
    SAMREADS=`grep -v @ $MYOUT/${n/'_'$READONE.$FASTQ/.$ALN.sam} | wc -l`
    if [ "$SAMREADS" = "" ]; then let SAMREADS="0"; fi			
    if [ $SAMREADS -eq $FASTQREADS ]; then
	echo "-----------------> PASS check mapping: $SAMREADS == $FASTQREADS"
	echo ">>>>> readmapping with BWA - FINISHED"
	echo ">>>>> enddate "`date`
	exit
    else
	echo -e "***ERROR**** We are loosing reads from .fastq -> .sam in $f: 
                 Fastq had $FASTQREADS Bam has $SAMREADS"
	exit 1
    fi
fi

# continue for normal bam file conversion
echo "********* sorting and bam-conversion"
$SAMTOOLS view -bt $FASTA.fai $MYOUT/${n/'_'$READONE.$FASTQ/.$ALN.sam} | $SAMTOOLS sort - $MYOUT/${n/'_'$READONE.$FASTQ/.ash}

#TODO look at samtools for rmdup
#val string had to be set to LENIENT to avoid crash due to a definition dis-
#agreement between bwa and picard
#http://seqanswers.com/forums/showthread.php?t=4246
echo "********* mark duplicates"
if [ ! -e $MYOUT/metrices ]; then mkdir $MYOUT/metrices ; fi
THISTMP=$TMP/$n$RANDOM #mk tmp dir because picard writes none-unique files
echo $THISTMP
mkdir $THISTMP
java $JAVAPARAMS -jar $PICARD/MarkDuplicates.jar \
    INPUT=$MYOUT/${n/'_'$READONE.$FASTQ/.ash.bam} \
    OUTPUT=$MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam} \
    METRICS_FILE=$MYOUT/metrices/${n/'_'$READONE.$FASTQ/.$ASD.bam}.dupl AS=true \
    VALIDATION_STRINGENCY=LENIENT \
    TMP_DIR=$THISTMP
rm -r $THISTMP
$SAMTOOLS index $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam}



# statistics
echo "********* statistics"
STATSMYOUT=$MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam}.stats
$SAMTOOLS flagstat $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam} > $STATSMYOUT
if [ -n $SEQREG ]; then
    echo "#custom region" >> $STATSMYOUT
    echo `$SAMTOOLS view $MYOUT/${n/'_'$READONE.$FASTQ/.ash.bam} $SEQREG | wc -l`" total reads in region " >> $STATSMYOUT
    echo `$SAMTOOLS view -f 2 $MYOUT/${n/'_'$READONE.$FASTQ/.ash.bam} $SEQREG | wc -l`" properly paired reads in region " >> $STATSMYOUT
fi


echo "********* calculate inner distance"
export PATH=$PATH:/usr/bin/
THISTMP=$TMP/$n$RANDOM #mk tmp dir because picard writes none-unique files
mkdir $THISTMP
java $JAVAPARAMS -jar $PICARD/CollectMultipleMetrics.jar \
    INPUT=$MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam} \
    REFERENCE_SEQUENCE=$FASTA \
    OUTPUT=$MYOUT/metrices/${n/'_'$READONE.$FASTQ/.$ASD.bam} \
    VALIDATION_STRINGENCY=LENIENT \
    PROGRAM=CollectAlignmentSummaryMetrics \
    PROGRAM=CollectInsertSizeMetrics \
    PROGRAM=QualityScoreDistribution \
    TMP_DIR=$THISTMP
for im in $( ls $MYOUT/metrices/*.pdf ); do
    $IMGMAGCONVERT $im ${im/pdf/jpg}
done
rm -r $THISTMP

echo "********* verify"
BAMREADS=`head -n1 $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam}.stats | cut -d " " -f 1`
if [ "$BAMREADS" = "" ]; then let BAMREADS="0"; fi			
if [ $BAMREADS -eq $FASTQREADS ]; then
    echo "-----------------> PASS check mapping: $BAMREADS == $FASTQREADS"
    rm $MYOUT/${n/'_'$READONE.$FASTQ/.$ALN.sam}
    rm $MYOUT/${n/'_'$READONE.$FASTQ/.ash.bam}
else
    echo -e "***ERROR**** We are loosing reads from .fastq -> .bam in $f: \nFastq had $FASTQREADS Bam has $BAMREADS"
    exit 1
      
fi

echo "********* coverage track"
GENOME=$(echo $FASTA| sed 's/.fasta/.genome/' | sed 's/.fa/.genome/' )
java $JAVAPARAMS -jar $IGVTOOLS count $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam} \
    $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam.cov.tdf} $GENOME


echo "********* samstat"
$SAMSTAT $MYOUT/${n/'_'$READONE.$FASTQ/.$ASD.bam}

echo ">>>>> readmapping with BWA - FINISHED"
echo ">>>>> enddate "`date`
