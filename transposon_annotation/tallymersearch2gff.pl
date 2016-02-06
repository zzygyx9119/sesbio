#!/usr/bin/env perl

=head1 NAME 
                                                                       
tallymersearch2gff.pl - Compute k-mer frequencies in a genome

=head1 SYNOPSIS    
 
 perl tallymersearch2gff.pl -i contig.fas -t target.fas -k 20 -o contig_target.gff --gff

=head1 DESCRIPTION

This script will generate a GFF3 file for a query sequence (typically a contig or chromosome)
that can be used with GBrowse or other genome browsers (it's also possible to generate quick
plots with the results with, e.g. R).

=head1 DEPENDENCIES

Non-core Perl modules used are IPC::System::Simple and Try::Tiny.

Tested with:

=over 2

=item *

Perl 5.16.0 (on Mac OS X 10.6.8 (Snow Leopard))

=item *

Perl 5.18.0 (on Red Hat Enterprise Linux Server release 5.9 (Tikanga)) 

=back

=head1 LICENSE

Copyright (C) 2013-2016 S. Evan Staton

This program is distributed under the MIT (X11) License: http://www.opensource.org/licenses/mit-license.php

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and 
associated documentation files (the "Software"), to deal in the Software without restriction, 
including without limitation the rights to use, copy, modify, merge, publish, distribute, 
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software 
is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies 
or substantial portions of the Software.

=head1 AUTHOR 

S. Evan Staton                                                

=head1 CONTACT
 
statonse at gmail dot com

=head1 REQUIRED ARGUMENTS

=over 2

=item -i, --infile

A Fasta file (contig or chromosome) to search.

=item -o, --outfile

The name a GFF3 file that will be created with the search results.

=back

=head1 OPTIONS

=over 2

=item -t, --target

A file of WGS reads to index and search against the input Fasta.

=item -k, --kmerlen

The k-mer length to use for building the index. Integer (Default: 20).

=item -s, --search

Search the input Fasta file against an existing index. The index must be
specified with this option.

=item -idx, --index

The name of the index to search against the input Fasta. Leave this option off if you want
to build an index to search.

=item -e, --esa

Build the suffix array from the WGS reads (--target) and exit. The name of the index can then
be used to search a query sequence. This makes it possible to avoid repeatedly building
the index files. 

=item --log

Report the log number of counts instead of raw counts. This is often a good option with WGS
data because many regions have very, very high coverage.

=item --quiet

Do not print progress of the program to the screen.

=item --clean

Remove all the files generated by this script. This does not currently touch any of
the Tallymer suffix or index files.

=item -h, --help

Print a usage statement. 

=item -m, --man

Print the full documentation.

=cut

use 5.010;
use strict;
use warnings;
use IPC::System::Simple qw(capture system);
use Try::Tiny;
use Bio::SeqIO;
use Getopt::Long;
use Data::Dumper;
use File::Basename;
#File::Temp;

#TODO: 
#       (Makes more sense to use separate script because 
#        there is no way to know the range of counts,
#        though it may be a useful option to just do the 
#        search and print the statistical properties
#        of the k-mers.) 
#
#       Print information about the outfile names.
#       Print time or message that program is completed.

#       Use File::Temp for temp fasta file creation, which 
#       would be much safer because in the event that a 
#       multifasta and one of the sequences has the same 
#       name, the original would also be deleted with the 
#       --clean option.

my ($infile, $outfile, $k, $db, $help, $man, $clean, $debug);
my ($esa, $index, $search, $log, $gff, $quiet, $filter, $matches, $ratio);

GetOptions(# Required
	   'i|infile=s'           => \$infile,
	   'o|outfile=s'          => \$outfile,
	   'e|esa'                => \$esa,
	   # Options
	   't|target=s'           => \$db,
	   'k|kmerlen=i'          => \$k,
	   'idx|index=s'          => \$index,
	   's|search'             => \$search,
	   'r|repeat-ratio=f'     => \$ratio,
	   'filter'               => \$filter,
	   'log'                  => \$log,
	   'gff'                  => \$gff,
	   'quiet'                => \$quiet,
	   'clean'                => \$clean,
	   'debug'                => \$debug,
	   'h|help'               => \$help,
	   'm|man'                => \$man,
	   );

if ($esa && !$db) {
    say "\nERROR: A target sequence set must be specified for building the index. Exiting.";
    usage();
    exit(1);
}

if ($esa && $db) {
    say "\n========> Building Tallymer index for: $db" unless $quiet;
    build_suffixarry($db);
    say "\n========> Done." unless $quiet;
    exit(0);
}

if (!$infile || !$outfile || !$index) {
    say"\nERROR: No input was given.";
    usage();
    exit(1);
}

my $gt = findprog('gt');

if ($search && $filter && !$ratio) {
    warn "\nWARNING: Using a simple repeat ratio of 0.80 for filtering since one was not specified.\n";
}

# return reference of seq hash here and do tallymer search for each fasta in file
my ($seqhash, $seqreg, $seqct) = split_mfasta($infile);

if ($search) {
    for my $key (sort keys %$seqhash) {
	say "\n========> Running Tallymer Search on sequence: $key" unless $quiet;
	my $oneseq = getFh($key);
	$matches = tallymer_search($oneseq, $index);
	if ($gff) {
	    for my $seqregion (sort keys %$seqreg) {
		if ($key eq $seqregion) {
		    tallymersearch2gff($seqct,$matches,$outfile,$seqregion,$seqreg->{$seqregion});
		    delete $seqreg->{$seqregion};
		}
	    }
	}
	unlink $oneseq if $clean && $seqct > 1; # what we really want is: && $infile ne $oneseq
	delete $seqhash->{$key};
    }
} else {
    build_suffixarray($db);
    my ($idxname) = build_index($db, $index);
    for my $key (sort keys %$seqhash) {
        say "\n========> Running Tallymer Search on sequence: $key" unless $quiet;
	my $oneseq = getFh($key);
	$matches = tallymer_search($oneseq, $idxname);
	if ($gff) {
	    for my $seqregion (sort keys %$seqreg) {
		if ($key eq $seqregion) {
		    tallymersearch2gff($seqct,$matches,$outfile,$seqregion,$seqreg->{$seqregion});
		    delete $seqreg->{$seqregion};
		    # clean all the files from the suffix array creation here
		    # my $clean_cmd = "rm *.al1 *.des *.esq *.lcp *.llv *.prj *.sds *.ssp *.suf";
		}
	    }
	}
	unlink $oneseq if $clean && $seqct > 1; # what we really want is: && $infile ne $oneseq
	delete $seqhash->{$key};
    }
}

exit;
#
# Subs
#
sub findprog {
    my $prog = shift;
    my $path = capture("which $prog 2> /dev/null");
    chomp $path;
    if ( (! -e $path) && (! -x $path) ) {
        die "\nERROR: Cannot find $prog binary. Exiting.\n\n";
    } else {
        return $path;
    }
}

sub split_mfasta {
    my $seq = shift;
    my $seq_in  = Bio::SeqIO->new( -format => 'fasta', -file => $seq);

    my %seqregion;
    my %seq;
    my $seqct = 0;

    while (my $fas = $seq_in->next_seq()) {
	$seqct++;
	$seq{$fas->id} = $fas->seq;
	$seqregion{$fas->id} = $fas->length;
    }

    if ($seqct > 1) {
	say "\n========> Running Tallymer Search on $seqct sequences." unless $quiet;
    } 
   
    return(\%seq,\%seqregion,$seqct);
	
}

sub getFh {
    my ($key) = shift;
    my $singleseq = $key.".fasta";           # fixed bug adding extra underscore 2/10/12
    #$seqhash->{$key} =~ s/(.{60})/$1\n/gs;   # may speed things up marginally to not format the sequence
    $seqhash->{$key} =~ s/.{60}\K/\n/g;      # v5.10 is required to use \K
    open my $tmpseq, '>', $singleseq or die "\nERROR: Could not open file: $singleseq\n";
    say $tmpseq join "\n", ">".$key, $seqhash->{$key};
    close $tmpseq;
    return $singleseq;
    
}

sub build_suffixarray {
    my $db = shift;
    my $suffix = "$gt suffixerator ".
	         "-dna ".
                 "-pl ".
                 "-tis ".
                 "-suf ".
                 "-lcp ".
                 "-v ".
                 "-parts 4 ".
                 "-db $db ".
                 "-indexname $db";
    $suffix .= $suffix." 2>&1 > /dev/null" if $quiet;
    my $exit_code;
    try {
	$exit_code = system([0..5], $suffix);
    }
    catch {
	say "ERROR: gt suffixerator failed with exit code: $exit_code. Here is the exception: $_.\n";
    };
}

sub build_index {
    my $db = shift;
    my $indexname = shift;
    my $index = "$gt tallymer ".
	        "mkindex ".
                "-mersize $k ".
		"-minocc 10 ".
		"-indexname $indexname ".
		"-counts ".
		"-pl ".
		"-esa $db";
    $index .= $index." 2>&1 > /dev/null" if $quiet;

    say "\n========> Creating Tallymer index for mersize $k for sequence: $db";
    my $exit_code;
    try {
	$exit_code = system([0..5], $index);
    }
    catch {
	say "ERROR: gt tallymer failed with exit code: $exit_code. Here is the exception: $_.\n";
    };
}

sub tallymer_search {
    my ($infile, $indexname) = @_;
    my ($seqfile,$seqdir,$seqext) = fileparse($infile, qr/\.[^.]*/);
    my ($indfile,$inddir,$indext) = fileparse($indexname, qr/\.[^.]*/);
    #say "========> $seqfile";
    #say "========> $indfile";

    my $searchout = $seqfile."_".$indfile.".tallymer-search.out";

    my $search = "$gt tallymer ".
	         "search ".
		 "-output qseqnum qpos counts sequence ".
                 "-tyr $indexname ".
                 "-q $infile ".
                 "> $searchout";
    say "\n========> Searching $infile with $indexname" unless $quiet;
    #say "\n========> Outfile is $searchout" unless $quiet;    # The Tallymer search output. 
    my $exit_code;
    try{
        $exit_code = system([0..5], $index);
    }
    catch {
	say "ERROR: gt tallymer failed with exit code: $exit_code. Here is the exception: $_.\n";
    };
    return $searchout;

}

sub tallymersearch2gff {
    my ($seqct, $matches, $outfile, $seqid, $end) = @_;
    my ($file,$dir,$ext) = fileparse($outfile, qr/\.[^.]*/);
    my $out;
    $out = $file."_".$seqid.".gff3" if $seqct > 1;
    $out = $outfile if $seqct == 1;

    open my $mers,'<',$matches or die "\nERROR: Could not open file: $matches\n";
    open my $gff,'>',$out or die "\nERROR: Could not open file: $out\n";
    
    say $gff "##gff-version 3";
    say $gff "##sequence-region ",$seqid," 1 ",$end;
    
    while (my $match = <$mers>) {
	chomp $match;
	my ($seqnum, $offset, $count, $seq) = split /\t/, $match;
	$offset =~ s/^\+//;
	$seq =~ s/\s//;
	my $merlen = length($seq);

	if ($filter) {
	    my $repeatseq = filter_simple($seq, $merlen);
	    unless (exists $repeatseq->{$seq} ) {
		printgff($count, $seqid, $offset, $merlen, $seq, $gff);
	    }
	} else {
	    printgff($count, $seqid, $offset, $merlen, $seq, $gff);
	}
    }
    close $gff;
    close $mers;
    unlink $matches if $clean;
}

sub filter_simple {
    my ($seq, $len) = @_;
    my %di = ('AA' => 0, 'AC' => 0, 
	      'AG' => 0, 'AT' => 0, 
	      'CA' => 0, 'CC' => 0, 
	      'CG' => 0, 'CT' => 0, 
	      'GA' => 0, 'GC' => 0, 
	      'GG' => 0, 'GT' => 0, 
	      'TA' => 0, 'TC' => 0, 
	      'TG' => 0,'TT' => 0);
    my %mono = ('A' => 0, 'C' => 0, 'G' => 0, 'T' => 0);
    my $dict = 0;
    my $monoct = 0;
    my $diratio;
    my $monoratio;

    my %simpleseqs;
    my $repeat_ratio = defined($ratio) ? $ratio : "0.80";

    for my $mononuc (keys %mono) {
        #my $monoct = (uc($seq) =~ tr/$mononuc//);
	while ($seq =~ /$mononuc/ig) { $monoct++ };
        $monoratio = sprintf("%.2f",$monoct/$len);
        #say "Mer: $mononuc\tMer: $seq\nMononuc count: $monoct";    # for debug, if these simple repeats are of interest they
	#say "Mer: $mononuc\tMer: $seq\nMononuc ratio: $monoratio"; # are stored, along with their repeat ratio, in the hash below
	if ($monoratio >= $repeat_ratio) {
	    $simpleseqs{$seq} = $monoratio;
	}
	$monoct = 0;
    }

    for my $dinuc (keys %di) {
	while ($seq =~ /$dinuc/ig) { $dict++ };
	$diratio = sprintf("%.2f",$dict*2/$len);
	#say "Mer: $dinuc\tMer: $seq\nDinuc count: $dict";    # for debug, if these simple repeats are of interest they
	#say "Mer: $dinuc\tMer: $seq\nDinuc ratio: $diratio"; # are stored, along with their repeat ratio, in the hash below
	if ($diratio >= $repeat_ratio) {
	    $simpleseqs{$seq} = $diratio;
	}
	$dict = 0;
    }

    return \%simpleseqs;
	    
}

sub printgff {
    my ($count, $seqid, $offset, $merlen, $seq, $gff) = @_;

    if ($log) {
	# may want to consider a higher level of resolution than 2 sig digs
	eval { $count = sprintf("%.2f",log($count)) }; warn $@ if $@; 
    }
    
    say $gff join "\t", $seqid, "Tallymer", "MDR", $offset, $offset, $count, ".", "+",
                        join ";", "Name=Tallymer_".$merlen."_mer","ID=$seq","dbxref=SO:0000657";
}

sub usage {
    my $script = basename($0);
  print STDERR <<END

USAGE: $script -i contig.fas -t target.fas -k 20 -o contig_target.gff [--gff] [--log] [--filter] [--clean] [-r] [-s] [-e] [-idx]

Required:
    -i|infile       :    Fasta file to search (contig or chromosome).
    -o|outfile      :    File name to write the gff to.

Options:
    -t|target       :    Fasta file of WGS reads to index.
    -k|kmerlen      :    Kmer length to use for building the index.
    -e|esa          :    Build the suffix array from the WGS reads (--target) and exit.
    -s|search       :    Just search the (--infile). Must specify an existing index.
    -r|ratio        :    Repeat ratio to use for filtering simple repeats (must be used with --filter).
    -idx|index      :    Name of the index (if used with --search option, otherwise leave ignore this option).
    --filter        :    Filter out simple repeats including di- and mononucleotides. (In testing phase)
    --log           :    Return the log number of matches instead of the raw count.
    --gff           :    Create a GBrowse-compatible GFF3 file. 
    --clean         :    Remove all the files generated by this script. This does not currently touch any of
                         the Tallymer suffix or index files. 			 
    --quiet         :    Do not print progress or program output.
	
END
}
