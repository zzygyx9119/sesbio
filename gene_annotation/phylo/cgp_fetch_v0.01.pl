#!/usr/bin/env perl

#TODO: add POD

#
# Libs
#
use 5.010;
use strict;
use warnings;
use Getopt::Long;
use File::Basename;
use LWP::UserAgent;
use Time::HiRes qw(gettimeofday);
use HTML::TreeBuilder;
use Data::Dump qw(dd);
use IPC::System::Simple qw(system);
use Try::Tiny;
use Pod::Usage;

#
# Vars
#
my $all;
my $genus;
my $species;
my $outfile; ## log
my $help;
my $man;
my $sequences;
my $alignments;
my $assemblies;
my $cgp_response = "CGP_DB_response.html"; # HTML

#
# Opts
#
GetOptions(
           'all'              => \$all,
	   'g|genus=s'        => \$genus,
	   's|species=s'      => \$species,
	   'o|outfile=s'      => \$outfile,
	   'seq|sequences'    => \$sequences,
           'aln|alignments'   => \$alignments,
           'asm|assemblies'   => \$assemblies,
	   'h|help'           => \$help,
	   'm|man'            => \$man,
	  );

#pod2usage( -verbose => 1 ) if $help;
#pod2usage( -verbose => 2 ) if $man;

#
# Check @ARGV
#
if (!$assemblies && !$sequences && !$alignments) {
   say "\nERROR: Command line not parsed correctly. Exiting.";
   usage();
   exit(1);
}


#
# Counters
#
my $t0 = gettimeofday();
my $records = 0;

#
# Set terms for search
#
my ($gen, $sp);
if ($genus) {
    $gen = substr($genus, 0, 4);
}
if ($species) {
    $sp = substr($species, 0, 4);
}

#
# Create the UserAgent
# 
my $ua = LWP::UserAgent->new;
my $tree = HTML::TreeBuilder->new;

#
# Perform the request
#
my $urlbase = 'http://cgpdb.ucdavis.edu/asteraceae_assembly/';
my $response = $ua->get($urlbase);

#
# Check for a response
#
unless ($response->is_success) {
    die "Can't get url $urlbase -- ", $response->status_line;
}

#
# Open and parse the results
#
open my $out, '>', $cgp_response or die "\nERROR: Could not open file: $!\n";
say $out $response->content;
close $out;
$tree->parse_file($cgp_response);

for my $tag ($tree->look_down(_tag => 'a')) {
    if ($tag->attr('href')) {
	if ($assemblies) {
	    my $type = "assemblies";
	    if ($tag->as_text =~ /\.assembly$/) {
		if ($all) {
		    fetch_files($urlbase, $type, $tag->as_text);
		}
		else {
		    filter_search($genus, $species, $gen, $sp, $tag->as_text, $type);
		}
	    }
	}
	elsif ($sequences) {
	    my $type = "sequences";
	    if ($tag->as_text =~ /\.fasta$/) {
		if ($all) {
		    fetch_files($urlbase, $type, $tag->as_text);
		}
		else {
		    filter_search($genus, $species, $gen, $sp, $tag->as_text, $type);
		}
	    }
	}
	elsif ($alignments) {
	    my $type = "alignments";
	    if ($tag->as_text =~ /\.Align.tar.gz$/) {
		if ($all) {
		    fetch_files($urlbase, $type, $tag->as_text);
		}
		else {
		    filter_search($genus, $species, $gen, $sp, $tag->as_text, $type);
		}
	    }
	}
    }
}

unlink $cgp_response;

#
# Subroutines
#
sub filter_search {
    my ($genus, $species, $gen, $sp, $file, $type) = @_;

    if ($genus && !$species && $file =~ /$gen/i) {
	fetch_files($urlbase, $type, $file);
    }
    elsif (!$genus && $species && $file =~ /$sp/i) {
	fetch_files($urlbase, $type, $file);
    }
    elsif ($genus && $species && $file =~ /$gen/i && $file =~ /$sp/i) {
	fetch_files($urlbase, $type, $file);
    }
}

sub fetch_files {
    my ($urlbase, $type, $file) = @_;

    my $data_dir;
    if ($type =~ /assemblies/i) {
	$data_dir = "data_assembly_files/";
    }
    elsif ($type =~ /alignments/i) {
	$data_dir = "data_contig_assembly_files/";
    }
    elsif ($type =~ /sequences/i) {
	$data_dir = "data_sequence_files/";
    }

    my $endpoint = $urlbase.$data_dir.$file;
    my $exit_code;
    try {
	$exit_code = system([0..5], "wget -O $file $endpoint");
    }
    catch {
	say "\nERROR: wget exited abnormally with exit code $exit_code. Here is the exception: $_\n";
    };
}

sub usage {
    my $script = basename( $0, () );
    print STDERR <<END

USAGE: perl $script [-seq] [-aln] [-asm] [-g] [-s] [--all]

Required Arguments:
  o|outfile         :      File to place the results (NOT IMPLEMENTED).
  seq|sequences     :      Specifies that the raw EST sequences should be fetched.
  aln|alignments    :      Specifies that the assemblies aligned to Arabidopsis should be fetched.
  asm|assemblies    :      Specifies that the EST assemblies should be fetched.

Options:
  all               :      Download files of the specified type for all species in the database.
  g|genus           :      The name of a genus query.
  s|species         :      The name of a species to query.
  h|help            :      Print a help statement.
  m|man             :      Print the full manual. 

END
}
