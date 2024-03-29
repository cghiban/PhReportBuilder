#!/usr/bin/perl

use common::sense;
use strict;	
use File::Spec ();
use File::Copy qw/copy/;
use IO::File ();
use IO::Dir ();
use Getopt::Long;
use Pod::Usage;
#use Term::ANSIColor;
use Cwd qw/getcwd abs_path/;
use File::Basename;
use Capture::Tiny qw/capture/;
use XML::Twig ();
use MIME::Base64;
use Data::Dumper;

=head1 NAME

build-report.pl - (runs and ) builds PhosphateLocalization report

=head1 SYNOPSIS

 # to run PhosphateLocalization and build the report:
 % build-report.pl --dir|-d <data_dir> 
                   --input|-r <inspect output>
                   --inspect_dir|-i <inspect home dir>
                   --triedb|-t <trie database>
                   --filter-ppm|-f <integer> 
                   --output|-o [report_output_dir]
                   --pv|-p [pvalue_file] # with this option PValue is not run

=head1 DESCRIPTION

=head2 1. run PhosphateLocalization

=over 

=item B<- inspect_dir> (location of PhosphateLocalization)

=item B<- PVALUE file>

=item B<- output dir>

=back

python PhosphateLocalization.py 
  -r phos/sites/PVALUE_output_sites.txt  # 1st 3 columns from PVALUE_output.txt
  -m phos/                               # location for mzXML files
  -w phos/sites/phos_out/localized.txt   # output file
  -d phos/sites/phos_out                 # output dir for localization files

=head2 2. build report

=over 

=item - PVALUE file

=item - report output dir

=item - psites output dir (if we don't run PhosphateLocalization)

=back

=cut


my $PROTON_MASS = 1.007825;
my ($DIR, $OUTDIR, $INPUT, $TRIE, $PV_FILE, $QUIET, $HELP, $hk_dir, $filter_ppm);
my ($threshhold, $INSPECT_HOME, $filter_ppm_default) = (0.05, "/usr/local/inspect", 20);

GetOptions(
  'dir|d=s'	=> \$DIR,
  'input|r=s'	=> \$INPUT,
  'inspect|i=s'	=> \$INSPECT_HOME,
  'triedb|t=s'	=> \$TRIE,
  'pv|p:s'	=> \$PV_FILE,
  'output|o:s'	=> \$OUTDIR,
  'hkdir|k:s'	=> \$hk_dir,
  'filter-ppm|f:i' => \$filter_ppm,
  'quiet'	=> \$QUIET,
  'help|h'	=> \$HELP,
);

pod2usage(-verbose => 0, -exitval => 0) if $HELP;

my $err = 0;

my $work_dir = $DIR;
$work_dir =~ s|/*$||;

#print color 'bold red';

unless ( $work_dir ) {
	print "Data dir is missing.\n";
	$err++;
} elsif (!-d $work_dir) {
	print "Argument $work_dir is not a valid directory.\n";
	$err++;
}

unless ( $INPUT ) {
	print "Inspect output file is missing.\n";
	$err++;
} elsif (!-f $INPUT) {
	print "Argument $INPUT is not a valid file.\n";
	$err++;
}

unless ( $INSPECT_HOME ) {
	print "Inspect home dir is missing.\n";
	$err++;
} elsif (!-d $INSPECT_HOME) {
	print "Argument $INSPECT_HOME is not a valid directory.\n";
	$err++;
} elsif (!-f File::Spec->catfile($INSPECT_HOME, 'inspect')) {
	print "Can't find executable [inspect] in $INSPECT_HOME.\n";
	$err++;
}

unless ( $TRIE ) {
	print "Trie db file is missing.\n";
	$err++;
} elsif (!-f $TRIE) {
	print "Argument $TRIE is not a valid file.\n";
	$err++;
}

unless ( $OUTDIR ) {
	$OUTDIR = File::Spec->catfile($DIR, "output") if $DIR;
}

if ( $PV_FILE && !-f $PV_FILE) {
	print "Argument [--pv $PV_FILE] points to a non-existing file.\n";
	$err++;
}

if (defined $filter_ppm && $filter_ppm) {
	if ($filter_ppm < 0) {
		print "Argument [--filter_ppm|f $filter_ppm] should be a positiv integer.\n";
		$err++;
	}
}
$filter_ppm = $filter_ppm_default unless ($filter_ppm);

#print color 'reset';

if ($err) {
	print "\n";
	pod2usage(-verbose => 0, -exitval => 1);
	#exit 1;
}

unless ( -d $OUTDIR) {
	mkdir $OUTDIR or do {
		print "ERROR: Can't create output directory for the report: ", $!, $/;
		exit 1;
	};
}


#------------------------------------------------
main();

exit 0;

# TODO
# get MQScore values din *phos*.html
# allow filering option on command line
# get PPM value from Hrdklor (a) and a 2nd value should be calculated(b)
#	(a) coloana 5 de pe rindurile cu P, pt scanul de la linia S (de deasupra linie P)
#	http://proteome.gs.washington.edu/software/hardklor/tutorial.html

# how do we compute HK values? on what files? since we have all the psites, but no files...

exit 0;

#------------------------------------------------
sub main {

	my $pv_threshhold = $threshhold;
	my $reports = ();
	my %ppms = ();
	unless ($PV_FILE) {
		$PV_FILE = run_pvalue();
	}
	
	my $pvalues = get_pvalues($PV_FILE, $pv_threshhold);
	
	my $phos_dir = run_phos_loc($PV_FILE);
	#my $phos_dir = "data/test_phosphoreport/output/phos_out";

	#print join "\n", keys %$pvalues, $/;
	#print "$OUTDIR\n---------\n";
	#return;
	my @pfnames = get_pfile_names($phos_dir);
	print "phos files # ", scalar @pfnames, $/ unless $QUIET;

	if (@pfnames) {
		
		# get ppms
		my %scans = ();
		my %mzXMLs = (); # holds the scans found by PValue and it's scans
		for my $pf (sort @pfnames) {
			my ($mzXML, $scan) = $pf =~ /(.*?\.mzXML)\.(\d+)\./i;
			$scans{ $scan } = 1;
			$mzXMLs{ $mzXML } = $mzXMLs{ $mzXML } ? [ @{$mzXMLs{ $mzXML }}, $scan ]	 : [ $scan ];
		}

		for my $mz (keys %mzXMLs) {
		#for my $mz ('012010_tes_1.mzXML') {
			my $mzf = File::Spec->catfile($work_dir, $mz);
			# extract the experimental mass for each scan
			$mzXMLs{$mz} = extract_scan_mass($mzf, $mzXMLs{$mz});
		}
		#print STDERR Dumper($mzXMLs{'012010_tes_1.mzXML'}), $/;
		#print STDERR Dumper(\%mzXMLs), $/;
		
		my $rep_dir = File::Spec->catfile($OUTDIR, "report");
		unless (mkdir $rep_dir) {
			print "cwd: ", getcwd(), $/;
			print "Error creating dir $rep_dir: ", $!, $/;
		}
		#print "rep_dir: ", $rep_dir, $/;
		my $report = File::Spec->catfile($rep_dir, "00-report.html");
		my $html = IO::File->new;
		unless ($html->open($report, 'w')) {
			exit 1;
		}

		print "\nReport saved in: ", $report, "\n" x 2;
		
		print "\nFiltering out any annotation with ppm not in this interval: [$filter_ppm, -$filter_ppm].\n\n" unless $QUIET;
		print $html "<html>\n<body>"
			. "<table><tr>\n"
			. "<td>Annotation</td>"
			. "<td>PLS-Annotation</td>"
			. "<td>Theoretical M</td>"
			. "<td>Experimental M</td>"
			. "<td>ppm</td>"
			. "<td>MQScore</td>"
			. "<td>PhLocScore</td>"
			. "<td>File</td>"
			. "<td>Scan</td>"
			. "<td>PValue</td>"
			. "</tr>";

		for my $pf ( sort @pfnames) {
			my ($mzXML, $scan, $formula) = $pf =~ /(.*?\.mzXML)\.(\d+)\.(.*)/i;
			my $pvkey = sprintf("%s.%d", $mzXML, $scan);
			#unless () {
			#	print join " - ", ($mzXML, $scan, sprintf("%s.%d", $mzXML, $scan), "NO"), $/;
			#}
			#print STDERR $pf, "\t", $pvalues->{$pvkey}, $/;
			if (defined $pvalues->{$pvkey}) {
				my $mqscore = 0;
				my $pfl_score = 0;
				my $annotation = my $pls_annotation = $pvalues->{$pvkey}->[0]->[0];
				my $pf_file = File::Spec->catfile($OUTDIR, "phos_out", $pf . ".verbose.txt");
				if (my $mfh = IO::File->new($pf_file)) {
					while (<$mfh>) {
						if (/^MQScore\s+(-?\d+\.?\d*)/) {
							$mqscore = $1;
						}
						elsif (/^Phosphate Localization Score:\s*(\d+\.?\d*)/) {
							$pfl_score = $1;
						}
						elsif (/^WARNING: Better annotation than input.\s+.*?\d,\s+(.*)$/) {
							$pls_annotation = $1;
						}
						#last if $mqscore && $pfl_score;
					}
					$mfh->close;
				}
				#print STDERR "\tMSQ = $mqscore\n";
				next if $mqscore < 1;

				my $phos_num = $formula =~ s/phos|\+80\D//g;
				my ($computed, $computed_verbose) = compute_mass($formula, $phos_num);
				my $extra_data = '<strong>Experimental M</strong>: ' .  $mzXMLs{$mzXML}->{$scan} . "\n" .
						'<strong>Computed M</strong>: '. $computed_verbose . "\n";
				#print "YY: ", $pvkey,"/$formula: ", $mzXMLs{$mzXML}->{$scan}, $/;
				my $lnk = generate_report($pf, $extra_data, $annotation);
				my $ppm = sprintf("%.2f", ($computed - $mzXMLs{$mzXML}->{$scan}) * 1e6 / $computed);

				next if $filter_ppm && ($ppm > $filter_ppm || $ppm < -$filter_ppm);

				$pls_annotation = $annotation if $pfl_score <= 7;

				print $html "<tr>"
						. "<td>" . $annotation . "</td>"
						. "<td>" . $pls_annotation . "</td>"
						. "<td>$computed</td>"
						. "<td>" . $mzXMLs{$mzXML}->{$scan} . "</td>"
						. "<td> $ppm </td>"
						. "<td>" . sprintf("%.3f", $mqscore ) . "</td>"
						. "<td> $pfl_score </td>"
						. "<td>$mzXML</td>"
						. "<td><a href=\"$lnk\">$scan</a></td>"
						. "<td>" . sprintf("%.07g", $pvalues->{$pvkey}->[0]->[1]) . "</td>"
						. "</tr>";
				#last;
			}
		}
		print $html "</table>\n</body>\n</html>";

	}
}

#------------------------------------------------
# return an hashref of arrayrefs [ Annotation, p-value]
# the keys have this format {SpectrumFile}.{Scan#},
sub get_pvalues {
	my ($pv_path, $threshhold) = @_;
	
	print "\n** threshold: ", $threshhold, $/ unless $QUIET;
	
	# 0 SpectrumFile
	# 1 Scan#
	# 2 Annotation
	#13 p-value
	
	my $pv = {};
	my $fh = IO::File->new();
	if ($fh->open($pv_path)) {
		while (<$fh>) {
			my @lvalues = split /\t+/;
			$lvalues[0] =~ s|.*/||;
			my $key = sprintf("%s.%d", @lvalues[0, 1]);
			push @{$pv->{$key}}, [@lvalues[2, 13]];
		}
	}
	
	$pv;
}

#------------------------------------------------
#
sub get_pfile_names {
	my ($pv_path) = @_;

	my @names = ();
	my $d = IO::Dir->new($pv_path);
	if (defined $d) {
		while (defined($_ = $d->read)) {
			$_ =~ s|.*/||;
			#next if (!/phos/ || /\.png$/);
			if (/\.verbose\.txt$/) {
				$_ =~ s/\.verbose\.txt//;
				push @names, $_;
			}
		}
		undef $d;
	}
	return @names;
}

#------------------------------------------------
#
sub generate_report {
	my ($pattern, $extra_data, $annotation) = @_;
	
	my $data_file = File::Spec->catfile($OUTDIR, "phos_out", sprintf("%s.verbose.txt", $pattern));
	my $png_file = sprintf("%s.png", $pattern);
	my $rep_details = File::Spec->catfile($OUTDIR, "report", sprintf("%s.html", $pattern));

	my $data = '';
	my $fh = IO::File->new($data_file);
	# parse the data_file
	if ($fh) {
		while (<$fh>) {
			unless(/^$/) {
				$data .= $_;
			}
			else {
				last;
			}
		}
		undef $fh;
	}
	return unless $data;
	$extra_data ||= "\n";

	my $fasta = $TRIE;
	$fasta =~ s/\.trie$/.fasta/;

	if (-f $fasta) {
		$extra_data .= "\n" . run_fasta36($annotation, $fasta);
	}
	else {
		print STDERR "No fasta file found!!", $/;
	}

	# create the html_file
	$fh = IO::File->new($rep_details, 'w');
	if ($fh) {
		print $fh q{<html><body style="margin-left: 30px;">}
			.qq{<img src="$png_file">}
			.qq{<pre>\n}
			. $data
			. $extra_data
			. q{</pre></body></html>};
		undef $fh;
	}
	
	# copy png
	my $target_png_file = File::Spec->catfile($OUTDIR, "report", $png_file);
	my $src_png_file = File::Spec->catfile($OUTDIR, "phos_out", $png_file);
	
	copy($src_png_file, $target_png_file) or 
		print "* ERROR: Can't copy image to [$src_png_file]\n";
	
	return sprintf("%s.html", $pattern);
}

sub run_pvalue {
	my (%p) = @_;
	
# python /usr/local/inspect/PValue.py 
# -r BSA_unrest.txt 			# Read results from filename (this is the output from inspect)
# -w PVALUED_ouput.txt 			# Write re-scored results to a file.
# -b 					# Blind search (use different score/deltascore weighting)
# -p 0.1				# [PVALUE] Cutoff for saving results; by default, 0.1
# -d /home/ruse/database/db.trie	# Database (.trie file) searched
	my $pv_file = File::Spec->catfile($OUTDIR, "PVALUED_output.txt");
	my @args = (	'python', File::Spec->catfile($INSPECT_HOME, 'PValue.py'),
			'-r', $INPUT,
			'-w', $pv_file,
			'-S', '0.5',
			'-p', '0.1',
			'-d', $TRIE,
		);
	print "PVALUE:\n@args\n" unless $QUIET;

	system (@args) == 0 or do {
			print "ERROR: PValue.py: ", $?, $/;
			exit 1;
		};
	return $pv_file;
}

sub run_phos_loc {
	my ($pv_file) = @_;
	
	#print "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n";
	
# cd /usr/local/inspect
# python PhosphateLocalization.py 
	# -r /home/ruse/data/sf2_0319/phos/sites/PVALUE_output.txt 	# File of formatted annotations
	# -w /home/ruse/data/sf2_0319/phos/sites/phos_out/localized.txt # Output of this program
	# -m /home/ruse/data/sf2_0319/phos/ 				# Directory containing spectra files
	# -d /home/ruse/data/sf2_0319/phos/sites/phos_out		# (opt) Directory for the images and annotated peak
									# lists created during the label process

	#
	my $data_dir = abs_path($DIR);
	my $phos_out = abs_path(File::Spec->catfile($OUTDIR, "phos_out"));
	my $slim_pf_file = abs_path(File::Spec->catfile($OUTDIR, "PValue4PhL.txt"));

	mkdir $phos_out;

	#print '$slim_pf_file: ', $slim_pf_file, $/;
	#print '$phos_out ', $phos_out, $/;
	#return;
	if (my $fh = IO::File->new($pv_file)) {
		if (my $sfh = IO::File->new($slim_pf_file, "w")) {
			while (my $l = <$fh>) {
				my @data = split /\t/, $l;
				unless ($l =~ /^#/) {
					next unless $data[2] =~ /phos|\+80\D/;
				}
				
				splice @data, 3;
				$data[0] = File::Spec->catfile($data_dir, basename($data[0])) unless $data[0] =~ /^#/;
				print $sfh join "\t", @data, "\n"
			}
		}
	}
	
	my $pwd = getcwd();
	chdir $INSPECT_HOME;
	
	# belea mare la 
	# /home/ruse/data/test_phosphoreport/012010_tes_7.mzXML   8694    S.LGRPTphosKDGAIKVAVKK.V

	
	my @args = ('python', 'PhosphateLocalization.py',
			'-r', $slim_pf_file,
			'-d', $phos_out,
			'-w', File::Spec->catfile($phos_out, "localized.txt"),
			'-m', $data_dir,
		);
	my $cmd = join " ", @args;
	print "\n", $cmd, $/ unless $QUIET;
	my ($sout, $serr) = capture {
		system (@args) == 0 or do {
			print "ERROR: PhosphateLocalization.py: ", $?, $/;
			chdir $pwd;
			exit 1;
		};
	};
	print "Error in PhosphateLocalization:\n", $serr if ($serr && !$QUIET);
	chdir $pwd;
	return $phos_out;
}


sub scan_mass {
	my ($twig, $el, $scans) = @_;

	my %scan_mass = ();
	my @sub_scans = $el->children("scan");
	for (@sub_scans) {
		my $scan_num = $_->att("num");
		if ( exists $scans->{$scan_num} ) {
			my $pMz = $_->first_child("precursorMz");
			#print "\t", $_->att("num"), " ", $pMz->field, "\t", $_->att('peaksCount'), $/;
			#print STDERR "\tprecursorCharge: ", $pMz->att('precursorCharge'), $/;
			$scans->{ $scan_num} = $pMz->field * $pMz->att('precursorCharge');
			$scan_mass{$scan_num} = {valms2 => $pMz->field, precursor => $pMz->att('precursorCharge')};
		}
		#print $out "\n";
		$_->delete;
	}
	if (%scan_mass) {
		my $peaksCount = $el->att('peaksCount');
		my $peaks_str = $el->first_child('peaks')->field;

		
		my $base64decoded = decode_base64($peaks_str);
		my @data = unpack("N*", $base64decoded);
		for my $scan_id ( keys %scan_mass) {
			$scan_mass{$scan_id}->{valms1} = find_closest_mass($scan_mass{$scan_id}->{valms2}, \@data);
			#print STDERR $_->att("num"), "\t", $peaksCount, "\t--\t", join (" => ", $scan_mass{$scan_id}->{valms1}, $scan_mass{$scan_id}->{valms2}), $/;

			my $adjustment = ($scan_mass{$scan_id}->{precursor} - 1) * $PROTON_MASS;
			#$scans->{ $scan_id } = sprintf("%.6f(ms2=%.6f)", 
			#		$scan_mass{$scan_id}->{valms1}*$scan_mass{$scan_id}->{precursor} - $adjustment,
			#		($scan_mass{$scan_id}->{valms2} * $scan_mass{$scan_id}->{precursor} - $adjustment)
			$scans->{ $scan_id } = sprintf("%.6f", 
					$scan_mass{$scan_id}->{valms1}*$scan_mass{$scan_id}->{precursor} - $adjustment
				);
		}

	}
	# make a function that looks through all the scans and finds the right mass

	#print STDERR $peaksCount, "\t",  length($peaks_str), $/;

	#if ($el->att('peaksCount')) {
	#	print $_->att("num"), " ", $_->att('peaksCount'), $/;
	#}
	#else {
	#	$el->purge;
	#}
}
sub extract_scan_mass {
	my ($mz, $scans) = @_;
	my %scans = map {$_ => 0} @$scans;


	my $handlers = { 'msRun/scan' => sub {scan_mass(@_, \%scans);} };
	my $twig= new XML::Twig(twig_roots => $handlers);
	$twig->parsefile( $mz );
	#print $mz, "\t", Dumper(\%scans), $/;
	return \%scans;
}

sub find_closest_mass {
	my ($mass_to_find, $data) = @_;
	my $delta = 9999990; # a big number
	my $found_mass = 0;
	my $data_num = @$data;
	#print "fcm: ", $mass_to_find, ' in ', $data_num, ' things', $/;
	for (my $i = 0; $i < $data_num; $i += 2) {
		#my $mz = $data->[$i];
		my $mz = unpack("f", pack("I", $data->[$i]));
		#$delta = abs($mass_to_find - $mz) < abs($delta) ? $mass_to_find - $mz : $delta;
		if (abs($mass_to_find - $mz) < abs($delta)) {
			$delta = $mass_to_find - $mz;
			$found_mass = $mz;
		
		}
		#print "\t*\t$mz\t$delta\n";
	}
	$found_mass;
}

sub compute_mass {
	my ($aa, $phos_num) = @_;
	my @args = (
			'/usr/local/bin/ipc',
			'-a', $aa,
			'-c', 'H',
			'-f', 10
		);
	my ($sout, $serr) = capture {
		system (@args) == 0 or do {
			print "ERROR: icp: ", $?, $/;
			exit 1;
		};
	};
	my ($data) = $sout =~ m/M=(.*?%)/;
	my @data = split /,/, $data;
	$data[0] += $phos_num * 79.96633;
	#print "ZZ: ", $aa, " ", $data, $/;
	#print STDERR "\tAdded: ", $phos_num * 79.96633, " to ", $aa, $/;

	return ($data[0], join(',', @data));
}

sub run_hardklore {
	my (@files) = @_;
	
	return unless @files;

	my $hk_dir = File::Spec->catfile($OUTDIR, "hardklor");
	my $hk_config = File::Spec->catfile($OUTDIR, "hk_config.txt");
	if (my $fh = IO::File->new($hk_config, "w")) {
		print $fh q{
# Set paths to DAT files
-mdat /usr/local/hardklor/ISOTOPE.DAT
-hdat /usr/local/hardklor/Hardklor.dat

# Set global parameters
-d 2
-sn 2.5
-corr 0.9
-chMax 5
-res 60000 OrbiTrap
-a FastFewestPeptides
-cdm Q

#Files
};

		mkdir $hk_dir;
		for (sort @files) {
			print $fh File::Spec->catfile($DIR, $_), " ", File::Spec->catfile($hk_dir, $_ . ".hk"), "\n";
		}
	}
	#print $hk_config, $/;
	
	my @args = ('/usr/local/hardklor/hardklor',
			'-conf', $hk_config);
			
	print "\n", "@args", $/;
	system (@args) == 0 or do {
			print "ERROR: hardklor: ", $?, $/;
			exit 1;
		};
	return $hk_dir;
}

sub run_fasta36 {
	my ($annotation, $fasta_file) = @_;

	my $query = File::Spec->catfile($OUTDIR, "seq.fa");
	my $out_search = File::Spec->catfile($OUTDIR, "outsrc.txt");

	my $fh = IO::File->new;
	if ($fh->open($query, 'w')) {
		my $aa = $annotation;
		$aa =~ s/phos//g;
		print $fh ">seq1\n";
		print $fh $aa, "\n";
	}
	my @args = ('/usr/local/fasta36/bin/fasts36',
			'-d', 3,
			$query,
			$fasta_file
		);
	my ($sout, $serr) = capture {
		system (join(' ', @args) . " > $out_search") == 0 or do {
			print STDERR "ERROR: fasts36: ", $?, $/;
			return;
		};
	};
	print STDERR  "run_fasta36: ", $serr, $/ if $serr;

	return parse_fasta36_output($out_search, $annotation);
}

# extracts the alignment and it indicates where the phosphorilation occured
#
sub parse_fasta36_output {
	my ($file, $pep) = @_;
	my ($out, $grab_all, $extra_char, $seq, $re) = ('', 0, 0);

	# extract the 1st alignment (with the best score?!)
	#
	my $in = IO::File->new($file);
	if ($in) {
		while (my $l = <$in>) {
			$l =~ s/\|//; # replace the 1st encounter of |
			if ($l =~ /^The best scores are:\s+/) {
				$out .= $l;
				my $line = <$in>;
				($seq) = $line =~ m/^(.*?)\s+/;
				if ($seq) {
					$extra_char = $seq =~ s/\|//; # replace the 1st encounter of |
					$seq = substr $seq, 0, 5;
					$re = qr/^>>$seq/;
				}
				$out .= $line;
			}
			elsif (defined $re && $l =~ /^>>/) {
				if ($l =~ /$re/) {
					$grab_all = 1;
					$out .= "\n" . $l;
				}
				else {
					$grab_all = 0;
				}
			}
			elsif ($grab_all) {
				if ($extra_char) {
					$l =~ s/^$seq\s+/$seq  /;
				}
				$out .= $l;
			}
		}
	}

	#----------
	# compute the "phos" position so we mark it in the alignment
	#
	$pep =~ s/\.//g;
	my @phos_positions = ();
	my @xxphos_positions = ();
	my $index = 0;
	while((my $p = index($pep, 'phos', $index)) > 0) {
		push @phos_positions, $p;
		push @xxphos_positions, $p - $#phos_positions * 4; #4 == length("phos")
		$index = $p + 1;
	}
	#----------

	my ($area, $x) = $out =~ m/Smith-.*?overlap \(.*\)\n\n(.*)\n+/sm;
	my $area_copy = $area;

	my @phos_indexes = ();

	my @seq1 = ($area =~ /seq1(\s+[A-Z]+)/g);
	my $prev_pep_len = 0;
	my $added = 0;
	for my $pep (@seq1) {
		my $spaces = $pep =~ s/\s//g;
		my $pep_copy = $pep;
		for my $poz (@xxphos_positions) {
			my $ndx = $poz + $added - $prev_pep_len;
			next if length($pep) < $ndx;
			substr $pep, $ndx, 0, "+";
			push @phos_indexes, $ndx;
			$added++;
		}
		my $xx = 0;
		while ($xx++ < $added) {
			shift @xxphos_positions;
		}
		$prev_pep_len += length $pep;
		$area_copy =~ s/$pep_copy/$pep/;
		while (my $ndx = shift @phos_indexes) {
			$area_copy =~ s/(    \s{$spaces})([+:]{$ndx})(.+)/$1$2+$3/;
			#$area_copy =~ s/(    \s{$spaces})([+:]{$ndx})/$1$2+/;
			my $sec_pos = $spaces + $ndx - 3;
			if ($area_copy =~ /^$seq/m) {
				$area_copy =~ s/^($seq\s+)([A-Z+]{$sec_pos})/$1$2+/m;
			}
		}
	}

	$out =~ s/(Smith-.*?overlap \(.*\)\n\n).*\n\n/$1$area_copy/sm;
	return $out;
}


