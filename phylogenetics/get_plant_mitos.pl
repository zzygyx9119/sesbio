#!/usr/bin/env perl

use 5.020;
use strict;
use warnings;
use autodie;
use File::Basename;
use File::Find;
use File::Copy;
use Try::Tiny;
use Capture::Tiny       qw(capture);
use Time::HiRes         qw(gettimeofday);
use HTTP::Tiny;
use HTML::TableExtract;
use XML::LibXML;
use Getopt::Long;
use Pod::Usage;
use Data::Dump;
use experimental 'signatures';

my $infile;
my $outfile;
my $help;
my $man;

GetOptions('i|infile=s'   => \$infile,
	   'o|outfile=s'  => \$outfile,
	   'h|help'       => \$help,
	   'm|man'        => \$man,
	   );

pod2usage( -verbose => 2 ) if $man;

usage() and exit(0) if $help;

#if (!$infile || !$outfile) {
#    say "\nERROR: No input was given.\n";
#    usage();
#    exit(1);
#}

#open my $in, '<', $infile or die "ERROR: Could not open file: $infile\n";
#open my $out, '>', $outfile or die "\nERROR: Could not open file: $outfile\n";

# counters
my $t0 = gettimeofday();
my $fasnum = 0;
my $headchar = 0;
my $non_atgcn = 0;

my @aux = undef;
my ($name, $comm, $seq, $qual);
my ($n, $slen, $qlen) = (0, 0, 0);

#my $url = 'http://www.ncbi.nlm.nih.gov/genomes/GenomesGroup.cgi?taxid=33090&opt=organelle';
#my $response = HTTP::Tiny->new->get($url);

#unless ($response->{success}) {
#    die "Can't get url $url -- Status: ", $response->{status}, " -- Reason: ", $response->{reason};
#}
# open and parse the results
#open my $out, '>', $outfile or die "\nERROR: Could not open file: $!\n";
#say $out $response->{content};
#close $out;

my %mt;

my $te = HTML::TableExtract->new( attribs => { border => 0 } );
$te->parse_file($outfile);

for my $ts ($te->tables) {
    for my $row ($ts->rows) {
	my @elem = grep { defined } @$row;
	for (@elem) { chomp; tr/\n//d; tr/\xA0//d; }
	if (defined $elem[0] && $elem[0] =~ /Viridiplantae mitochondrial genomes - (\d+) records/i) {
	    my $genomes = $1;
	    #unlink $cpbase_response;
	    say "$genomes mitochondrial plant genomes available at NCBI.";
	}
	#elsif (/Genome Accession/) {
	    #my ($species, $accession, $length, $protein, $rna, $created, $updated) = split /\s+/, $elem[0]; 
	#say join q{ }, @elem;
	
	#}
	if (defined $elem[0] && defined $elem[1] && $elem[1] =~ /NC_/) {
	    my ($species, $accession, $length, $protein, $rna, $created, $updated) = @elem;
	    $length =~ s/nt//;
	    say join "\t", $species, $accession, $length, $protein, $rna, $created, $updated;
	}
    }
}

#while (($name, $comm, $seq, $qual) = readfq(\*$in, \@aux)) {
#    $fasnum++;

#}
#close $in;
#close $out;

my $t1 = gettimeofday();
my $elapsed = $t1 - $t0;
my $time = sprintf("%.2f",$elapsed);

exit;

sub search_by_name ($genus, $species) {
    my $id = _fetch_id_for_name($genus, $species);
    say join "\t", $genus, $species, $id;
    _get_lineage_for_id($id);
}
sub _get_lineage_for_id ($id) {
    my $esumm = "esumm_$id.xml";
    my $urlbase = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=taxonomy&id=$id";
    my $response = _fetch_file($urlbase, $esumm);
    my $parser = XML::LibXML->new;
    my $doc = $parser->parse_file($esumm);
    for my $node ( $doc->findnodes('//TaxaSet/Taxon') ) {
	my ($lineage) = $node->findvalue('Lineage/text()');
	my ($family) = map { s/\;$//; $_; }
	               grep { /(\w+aceae)/ }
          	       map { split /\s+/ } $lineage;
	say "Family: $family";
	say "Full taxonomic lineage: $lineage";
    }
    unlink $esumm;
}
sub _fetch_id_for_name ($genus, $species) {
    my $esearch = "esearch_$genus"."_"."$species.xml";
    my $urlbase = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi";
    $urlbase .= "?db=taxonomy&term=$genus%20$species";
    my $reponse = _fetch_file($urlbase, $esearch);
    my $id;
    my $parser = XML::LibXML->new;
    my $doc = $parser->parse_file($esearch);
    for my $node ( $doc->findnodes('//eSearchResult/IdList') ) {
	($id) = $node->findvalue('Id/text()');
    }
    unlink $esearch;
    return $id;
}

sub _fetch_file ($url, $file) {
    my $response = HTTP::Tiny->new->get($url);
    unless ($response->{success}) {
	die "Can't get url $url -- Status: ", $response->{status}, " -- Reason: ", $response->{reason};
    }
    open my $out, '>', $file or die "\nERROR: Could not open file: $!\n";
    say $out $response->{content};
    close $out;
    return $response;
}

sub readfq ($fh, $aux) {
    @$aux = [undef, 0] if (!@$aux);
    return if ($aux->[1]);
    if (!defined($aux->[0])) {
	while (<$fh>) {
	    chomp;
	    if (substr($_, 0, 1) eq '>' || substr($_, 0, 1) eq '@') {
		$aux->[0] = $_;
		last;
	    }
	}
	if (!defined($aux->[0])) {
	    $aux->[1] = 1;
	    return;
	}
    }
    my ($name, $comm) = /^.(\S+)(?:\s+)(\S+.*)/ ? ($1, $2) : 
	                /^.(\S+)/ ? ($1, '') : ('', '');
    my $seq = '';
    my $c;
    $aux->[0] = undef;
    while (<$fh>) {
	chomp;
	$c = substr($_, 0, 1);
	last if ($c eq '>' || $c eq '@' || $c eq '+');
	$seq .= $_;
    }
    $aux->[0] = $_;
    $aux->[1] = 1 if (!defined($aux->[0]));
    return ($name, $comm, $seq) if ($c ne '+');
    my $qual = '';
    while (<$fh>) {
	chomp;
	$qual .= $_;
	if (length($qual) >= length($seq)) {
	    $aux->[0] = undef;
	    return ($name, $comm, $seq, $qual);
	}
    }
    $aux->[1] = 1;
    return ($name, $seq);
}

sub usage {
  my $script = basename($0);
  print STDERR <<END
USAGE: $script -i file -o file

Required:
    -i|infile    :    input
    -o|outfile   :    output
    
Options:
    -h|help      :    Print usage statement.
    -m|man       :    Print full documentation.
END
}