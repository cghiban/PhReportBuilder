package PhReportBuilder;
use Dancer ':syntax';

use File::Basename qw/basename/;
use FindBin qw($Bin);
use File::Spec;
use Capture::Tiny qw/capture/;
use Cwd qw/getcwd/;

our $VERSION = '0.1';

get '/' => sub {
    template 'index';
};

any ['get', 'post'] => '/buildreport' => sub {
    
	my $cf = config->{appconf};
	my $out_base = $cf->{output_base_dir};
	my $data_base_dir = $cf->{data_base_dir};
	
	if ( request->method() eq "POST" ) {
		my $d = params->{d};
		my $t = params->{t};
		my $o = params->{o};
		my $r = params->{r};
		my $f = params->{f};

		if ($o ne "") {
			$o = File::Spec->catfile($out_base, basename($o));
		}
		
		#content_type 'text/plain';
		content_type 'text/html';
		my $inspect_dir = $cf->{inspect_dir};
		my $web_output_base_path = $cf->{web_output_base_path};
		my ($out, $err) = capture {
			my $pwd = getcwd();
			mkdir $o;
			chdir $o;
			system('perl', "$Bin/build-report.pl",
						'-d', $d,
						'-r', $r,
						'-t', $t,
						'-o', $o,
						'-f', $f,
						'-i', $inspect_dir,
						#'-p', "$out_base/demo16/PVALUED_output.txt",
					) or do {
						print "Error building report: ", $?, $/;
					};
			chdir $pwd;
		};
		$o =~ s/$out_base/$web_output_base_path/;
		return "<pre>$out\nDone</pre>"
			. "<hr/><pre>$err</pre>"
			. "<br/><a target=\"_blank\" href=\"$o/report/00-report.html\">view report</a>";
	}
	else {
		my @out_dirs = <$out_base/*>;
		template 'builreport', {
			d => "$data_base_dir/ph-report-data",
			r => "$data_base_dir/ph-report-data/all_output.txt",
			t => "$data_base_dir/ph-report-data/uniprotKB_EcoliK12_bpv.RS.trie",
			o => 'demo' . (1 + scalar @out_dirs),
			f => 10,
			cf => $cf,
		};
	}
};

post '/dobuildreport' => sub {
	`ls /`;
};

get '/xy' => sub {
	return "ucu\n";
};

true;
