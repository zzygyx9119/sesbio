#!/bin/bash

perl ~/ePerl/qseq2fq.pl -i HA0001_61U0AAAXX_1_1_concat_qseq.txt -o HA0001_61U0AAAXX_1_1_concat_qseq.fastq -c
perl ~/ePerl/qseq2fq.pl -i HA0001_61U0AAAXX_1_2_concat_qseq.txt -o HA0001_61U0AAAXX_1_2_concat_qseq.fastq -c
perl ~/ePerl/qseq2fq.pl -i HA0001_61U0AAAXX_2_1_concat_qseq.txt -o HA0001_61U0AAAXX_2_1_concat_qseq.fastq -c
perl ~/ePerl/qseq2fq.pl -i HA0001_61U0AAAXX_2_2_concat_qseq.txt -o HA0001_61U0AAAXX_2_2_concat_qseq.fastq -c