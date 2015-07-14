#!/bin/python
######################################
# Generate contact maps from bam files
# and fragment lists
#
# Author: Fabian Buske (28/11/2014)
######################################

import os, sys, re
import traceback
from optparse import OptionParser
import fileinput
import datetime
from readData import *
from quicksect import IntervalTree
import gzip
import numpy as np
import scipy.sparse as ss

# manage option and arguments processing
def main():
    global options
    global args
    usage = '''usage: %prog [options] [bamFile]+

    generates (single locus) fragmentCounts and (pairwise) contactCount files
    for a (set of) aligned files.
    NOTE: If multiple libraries are input they are simply pooled, i.e. read-pairs are
          summed across all libraries - this may bias results to a libraries sequenced deeper)
    '''
    parser = OptionParser(usage)
    parser.add_option("-q", "--quiet", action="store_false", dest="verbose", default=True,
                    help="don't print status messages to stdout")
    parser.add_option("-v", "--verbose", action="store_true", dest="verbose", default=False,
                    help="print status messages to stdout")
    parser.add_option("-V", "--veryverbose", action="store_true", dest="vverbose", default=False,
                    help="print lots of status messages to stdout")
    parser.add_option("-P", "--CPU-processes", type="int", dest="cpus", default=-1,
                    help="number of CPU threads to use, -1 for all available [default -1]")
    parser.add_option("-O", "--onlycis", action="store_true", dest="onlycis", default=False,
                    help="only consider intra chromosomal contacts (cis)")
    parser.add_option("-M", "--multicount", action="store_true", dest="multicount", default=True,
                    help="count read that maps onces for each fragment it maps to (potentially several)")
    parser.add_option("-g", "--genomeFragmentFile", type="string", dest="genomeFragmentFile", default="",
                    help="file containing the genome fragments after digestion with the restriction enzyme(s), generated by hicup")
    parser.add_option("-f", "--fragmentAggregation", type="int", dest="fragmentAggregation", default=1,
                    help="number of restriction enzyme fragments to concat")
    parser.add_option("-r", "--resolution", type=int, dest="resolution", default=1000000,
                    help="size of a fragment in bp if no genomeFragmentFile is given")
    parser.add_option("-c", "--chromsizes", type="string", dest="chromSizes", default="",
                    help="tab separated file containing chromosome sizes")
    parser.add_option("-C", "--chrompattern", type="string", dest="chromPattern", default="",
                    help="pattern of chromosomes to filter for [default all]")
    parser.add_option("-m", "--mappability", type="string", dest="mappability", default="",
                    help="bigwig containing mappability score for a given tag size")
    parser.add_option("-o", "--outputDir", type="string", dest="outputDir", default="",
                    help="output directory [default: %default]")
    parser.add_option("-n", "--outputFilename", type="string", dest="outputFilename", default="",
                    help="output filename [default: extracted from first input file")
    parser.add_option("-t", "--tmpDir", type="string", dest="tmpDir", default="/tmp",
                    help="directory for temp files [default: %default]")
    parser.add_option("-s", "--sep", type="string", dest="separator", default=" ",
                    help="delimiter to use when reading the input [default: %default]")
    parser.add_option("--create2DMatrix", action="store_true", dest="create2DMatrix", default=False,
                    help="create a tab separated 2D matrix file")
    parser.add_option("--create2DMatrixPerChr", action="store_true", dest="create2DMatrixPerChr", default=False,
                    help="create a tab separated 2D matrix file one per Chromosome")
    parser.add_option("--inputIsFragmentPairs", action="store_true", dest="inputIsFragmentPairs", default=False,
                    help="input is a gzipped fragment pair file rather than bam files")
    parser.add_option("--inputIsReadPairs", type="string", dest="inputIsReadPairs", default="",
                    help="gzipped files with mapped read pair information, requires 4 column identifier corresponding to chrA,posA,chrB,posB,chrPrefix (separated buy comma), e.g. 2,3,6,7,chr")

    (options, args) = parser.parse_args()
    if (len(args) < 1):
        parser.print_help()
        parser.error("[ERROR] Incorrect number of arguments, need a dataset")

    if (options.fragmentAggregation < 1):
        parser.error("[ERROR] fragmentAggregation must be a positive integer, was :"+str(options.fragmentAggregation))
        sys.exit(1)

    if (options.genomeFragmentFile != ""):
        if (not os.path.isfile(options.genomeFragmentFile)):
            parser.error("[ERROR] genomeFragmentFile does not exist, was :"+str(options.genomeFragmentFile))
            sys.exit(1)

    else:
        if (options.resolution < 1):
            parser.error("[ERROR] resolution must be a positive integer, was :"+str(options.resolution))
            sys.exit(1)
        elif (options.chromSizes == "" or not os.path.isfile(options.chromSizes)):
            parser.error("[ERROR] chromSizes not given or not existing, was :"+str(options.chromSizes))
            sys.exit(1)

    if (options.outputDir != ""):
        options.outputDir += os.sep

    if (options.inputIsReadPairs != ""):
    	if (len(options.inputIsReadPairs.split(",")) < 4 or len(options.inputIsReadPairs.split(",")) > 5):
            parser.error("[ERROR] inputIsReadPairs does not have 4 column indexes :"+str(options.inputIsReadPairs))
            sys.exit(1)
        elif (options.inputIsFragmentPairs):
            parser.error("[ERROR] inputIsFragmentPairs and inputIsReadPairs cannot be set at the same time")
            sys.exit(1)

    if (options.verbose):
        print >> sys.stdout, "genomeFragmentFile:    %s" % (options.genomeFragmentFile)
        print >> sys.stdout, "fragmentAggregation:   %s" % (options.fragmentAggregation)
        print >> sys.stdout, "resolution:            %s" % (options.resolution)
        print >> sys.stdout, "chromSizes:            %s" % (options.chromSizes)
        print >> sys.stdout, "outputDir:             %s" % (options.outputDir)
        print >> sys.stdout, "tmpDir:                %s" % (options.tmpDir)

    process()

def output(fragmentsMap , fragmentList, fragmentPairs, fragmentCount, fragmentsChrom, mappableList):
    '''
    outputs 2 files, the first containing
    "chr    extraField      fragmentMid     marginalizedContactCount        mappable? (0/1)"

    and the second containing:
    "chr1   fragmentMid1    chr2    fragmentMid2    contactCount"

    optionally output the 2D contact matrix
    '''

    if (options.verbose):
        print >> sys.stdout, "- %s START   : output data " % (timeStamp())

    if ( options.outputFilename != "" ):
        outfile1 = gzip.open(options.outputDir+options.outputFilename+".fragmentLists.gz","wb")
    else:
        outfile1 = gzip.open(options.outputDir+os.path.basename(args[0])+".fragmentLists.gz","wb")

    fragmentIds = fragmentsMap.keys()
    fragmentIds.sort()

    chromlen={}
    for line in fileinput.input([options.chromSizes]):
        (chrom, chromsize) =line.split("\t")[0:2]
        # check if chromosome needs to be filtered out or not
        if (options.chromPattern != "" and not re.match("^"+options.chromPattern+"$", chrom)):
            continue
        chromlen[chrom]=int(chromsize)

    for fragmentId in fragmentIds:

        (chrom, start, end) = fragmentsMap[fragmentId]

        if (options.vverbose):
            print >> sys.stdout, "- process %s %d-%d " % (chrom, start, end)

        contactCounts = fragmentList[fragmentId]

        if (options.mappability == "" and contactCounts>0):
            mappableList[fragmentId]=1

        midpoint = min(int(0.5*(start+end)),chromlen[chrom])
        outfile1.write("%s\t%d\t%s\t%f\n" % (chrom, midpoint, "NA", mappableList[fragmentId]))

    outfile1.close()

    if ( options.outputFilename != "" ):
        outfile2 = gzip.open(options.outputDir+options.outputFilename+".contactCounts.gz","wb")
    else:
        outfile2 = gzip.open(options.outputDir+os.path.basename(args[0])+".contactCounts.gz","wb")

    if (options.verbose):
        print "    Size of combined matrix: {}".format(fragmentPairs.data.nbytes + fragmentPairs.indptr.nbytes + fragmentPairs.indices.nbytes)

    (I,J,V) = ss.find(fragmentPairs)
    for row,col,contactCounts in np.nditer([I,J,V]):
        (chrom1, start1, end1) = fragmentsMap[int(row)]
        (chrom2, start2, end2) = fragmentsMap[int(col)]

        midpoint1 = min(int(0.5*(start1+end1)),chromlen[chrom1])
        midpoint2 = min(int(0.5*(start2+end2)),chromlen[chrom2])

        outfile2.write("%s\t%d\t%s\t%d\t%d\n" % (chrom1, midpoint1, chrom2, midpoint2, int(contactCounts)))

    outfile2.close()


    if (options.verbose):
        print >> sys.stdout, "- %s FINISHED: output data" % (timeStamp())


def process():
    global options
    global args

    if (options.genomeFragmentFile != ""):
        [ fragmentsMap, lookup_structure, fragmentCount, fragmentsChrom ] = createIntervalTreesFragmentFile(options)
    else:
        [ fragmentsMap, lookup_structure, fragmentCount, fragmentsChrom ] = createIntervalTreesFragmentResolution(options)

    [ fragmentList, fragmentPairs ] = countReadsPerFragment(fragmentCount, lookup_structure, options,args)

    if (options.mappability != ""):
        mappableList = createMappabilityList(fragmentsMap, options.mappability, fragmentCount, options)
    else:
        mappableList = np.zeroes((fragmentCount,), dtype=np.float)

    output(fragmentsMap, fragmentList, fragmentPairs, fragmentCount, fragmentsChrom, mappableList)

######################################
# main
######################################
if __name__ == "__main__":
    main()
