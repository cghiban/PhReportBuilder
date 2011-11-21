package PhReportBuilder;
use Dancer ':syntax';

use FindBin qw($Bin);
#use lib "$Bin/../lib";


our $VERSION = '0.1';

get '/' => sub {
    template 'index';
};

any ['get', 'post'] => '/buildreport' => sub {
    
	
	if ( request->method() eq "POST" ) {
		my $d = params->{d};
		my $t = params->{t};
		my $o = params->{o};
		my $r = params->{r};
		my $f = params->{f};
		
		header('Content-Type' => 'text/plain');
		#content_type 'text/plain';
		return `perl $Bin/build-report.pl -d $d -r $r -t $t -o $o -f $f -i /home/cornel/tmp/inspect/ --quiet` . "\nDone";
	}
	else {
		template 'builreport', {
			d => '/home/cornel/tmp/ph-report-data',
			r => '/home/cornel/tmp/ph-report-data/all_output.txt',
			t => '/home/cornel/tmp/ph-report-data/uniprotKB_EcoliK12_bpv.trie',
			o => '/tmp/xyz',
			f => 10,
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
