package PhReportBuilder;
use Dancer ':syntax';

use strict;

use File::Basename qw/basename/;
use FindBin qw($Bin);
use File::Spec ();
use Cwd qw/getcwd/;
use File::Slurp qw/read_file/;
use Data::Dumper;

our $VERSION = '0.1';

get '/' => sub {
    template 'index';
};

any ['get', 'post'] => '/buildreport' => sub {
    
	my $cf = config->{appconf};
	my $out_base = $cf->{output_base_dir};
	my $data_base_dir = $cf->{data_base_dir};
	
	if ( request->method() eq "POST" ) {
		my ($params, $errs) = validate_params(params);

		my $d = $params->{d};
		my $t = $params->{t};
		my $o = $params->{o};
		my $r = $params->{r};
		my $f = $params->{f};

		if ($o ne "") {
			$o = File::Spec->catfile($out_base, basename($o));
		}
		else {
			push @$errs, "Output dir not specified!";
		}
		
		#content_type 'text/plain';
		content_type 'text/html';
		my $inspect_dir = $cf->{inspect_dir};
		my $web_output_base_path = $cf->{web_output_base_path};

		if (@$errs) {
			return join (" ", map {"<div>$_</div>"} @$errs) 
				. q{<script type="text/javascript">parent.document.getElementById('build_btn').style.display='inline'</script>};
		}
		
		my $pwd = getcwd();
		mkdir $o;
		chdir $o;

		# handle the stdin/out
		my ($stdout, $stderr) = ('stdout.txt', 'stderr.txt');

		open OLDOUT,'>&', \*STDOUT or die "Can't dup STDOUT: $!";
		open OLDERR, '>&', \*STDERR or die "Can't dup STDERR: $!";
		open STDOUT, '>', $stdout
					or die "Can't dup STDOUT: $o: $!";
		open STDERR, '>', $stderr
					or die "Can't dup STDERR to $o: $!";

		system ("$Bin/build-report.pl",
					'-d', $d,
					'-r', $r,
					'-t', $t,
					'-o', $o,
					'-f', $f,
					'-i', $inspect_dir,
				);
		my $exit_code = $?;

		close STDOUT;
		close STDERR;
		open STDOUT, '>&', \*OLDOUT;
		open STDERR, '>&', \*OLDERR;

		my $out = read_file( $stdout ) ;
		my $err = read_file( $stderr ) ;

		chdir $pwd;

		$o =~ s/$out_base/$web_output_base_path/;
		return "Done. "
			. ($exit_code != -1 && $exit_code >> 8 == 0 ? "<br/><a target=\"_blank\" href=\"$o/report/00-report.html\">view report</a>" : "with errors ($exit_code)...")
			. "<hr/><pre>$out\n$err</pre>"
			. ($exit_code >> 8 != 0 ? q{<script type="text/javascript">parent.document.getElementById('build_btn').style.display='inline'</script>} : '');
	}
	else {
		my $triedb_dir = $cf->{triedb_dir};
		my @dbs =  map { s|$triedb_dir/?||; $_ } <$triedb_dir/*trie>;
		my @out_dirs = <$out_base/*>;
		template 'builreport', {
			#d => "$data_base_dir/ph-report-data",
			d => "ph-report-data",
			r => "ph-report-data/all_output.txt",
			#t => "ph-report-data/uniprotKB_EcoliK12_bpv.RS.trie",
			trie_dbs => \@dbs,
			o => 'demo' . (1 + scalar @out_dirs),
			f => 20,
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


get qr{/browse/(.*)} => sub {

	my $type = params->{t} || '';
	unless ($type =~ /[fd]/) {
		$type = '';
	}

	my ($arg) = splat;
	$arg =~ s/([.\\])+/$1/g;
	$arg =~ s|/+|/|g;

	my $web_dir  = '';

	my $cf = config->{appconf};
	my $data_base_dir = $cf->{data_base_dir};

	my $topdir = '/';
	if ( $arg ) {
		$arg =~ s/\/$//;
		if ($arg =~ m{(.*)/}) {
			$topdir = '/' . ($1 || '');
		}
	}

	my $regex = 0;

	my $out = "<html><head>" .
			"<script type=\"text/javascript\" src=\"/js/browse.js\"></script>".
			"</head><body>";

	#$out .= "<div>$type</div>";
	$out .= "Location: <b>/DATA/" . ($arg || '') . "</b>\n<br>";

	$out .= "<img src=\"/images/back.gif\" />" .
			"<a href=\"javascript:void(0)\" onclick=\"goPath('/browse$topdir?t=$type')\">Parent directory</a><br/>";

	$arg =~ s/\/$// if defined $arg;

	#print STDERR $data_base_dir, ' --'. $arg, $/;
	my ($d, $f) = _get_file_tree($data_base_dir, $arg);

	$out .= '<ul>';
	foreach (sort @$d) {
		$_ =~ s|^/||;
		my $js_dir = $_;
		$js_dir =~ s/'/\\'/g;
		$out .= "<li style=\"list-style: none\">"
			 .  "<img src=\"/images/folder.gif\" />"
			 .	"<a href=\"javascript:;\" onclick=\"goPath('/browse/$_/?t=$type')\">/$_</a>"
			 . ($type eq "d" ? qq{ &nbsp; <input type="button" onclick="javascript:selectDir('$js_dir')" value="select" />}: '')
			 . "</li>";
	}

	if ($type ne "d"){
	 if (@$f) {
		foreach (@$f) {
			my $error = '';
			my $web_media_dir = '';
			my $show = 1;
 			if($regex) {
				if($_->{name} =~ m/($regex)/i) { $show = 1; } else { $show = 0; }
			}
			(my $th = $_->{name}) =~ s{(.*)\.(\w){3}$}{$1_thumb.jpg};
			unless (-f "$data_base_dir/$th") {
				$th = 'images/nothumb.jpg';
				$web_media_dir = '';
			} else {
				$web_media_dir = $web_dir;
			}

			if ($_->{name} !~ /^[0-9A-Za-z._\/\-]*$/){
				$error = 'Invalid characters used for the name of this file!\n' .
						 'Use only [letters, digits, -, _ and .]\n\n'.
						 'Please rename the file and reload the page!';
			}

			if ($show) {
				$out .= "<li style=\"margin-left:10px\"><a href=\"javascript:void(1)\" " .
						"onclick=\"javascript:";
				$out .= $error  ? "alert('$error');\" />"
						: "selectFile('$_->{name}')\" />";
				$out .= "$_->{name}</a> ($_->{size})</li>";
			}
		}
	 } else {
		$out .= '<li>No files found in this directory.</li>';
	 }
	}
	$out .= "</ul>";

	$out .= '</body></html>';

	#$r->content_type('text/html');
	#$r->send_http_header;
	return $out;
};

sub commify {
	local $_  = shift;
	1 while s/^(-?\d+)(\d{3})/$1,$2/;
	return $_;
}

sub _get_file_tree {

	my ($base, $subdir) = @_;

	my @dirs  = ();
	my @files = ();

	unless ($subdir) {

		my $x = getChildren($base, '');
		@dirs = map {$subdir . '/' . $_} @{$x->{d}};
	} else {

		my $re = qr/(=?jpg|gif|png|swf|flv|pdf|doc|txt|mp4|avi|wmv|ogg|mp3|exe|zip)$/i;
		my $x = getChildren($base, $subdir, $re);
		@dirs = map {$subdir . '/' . $_} @{$x->{d}};
		@files = map { {name => $subdir . '/' . $_->{name}, size => $_->{size}, realsize => $_->{realsize}}} @{$x->{f}};
	}

	return (\@dirs, \@files);
}

sub getChildren {
	my ($base_path, $dir, $re) = @_;
	
	my @dirs  = ();
	my @files = ();
		
	my $path = $base_path . '/' . $dir;

	if(opendir(DIR, $path)) {
		foreach (readdir(DIR)) {
			next if $_ =~ /^\./ || $_ =~ /_thumb\./;
			if(-d "$path/$_") {
				push(@dirs,$_);
			} else {
				#(my $ext = $_) =~ $re;
				#print STDERR "EXT: ", $ext , ' - ', $1, $/;
				#if ( $_ =~ $re) {
				if ( defined $re && $_ =~ $re) {
					#print STDERR  "$_ - EXT: $1", $/;
					my $size = -s "$path/$_";
					my $realsize = $size;
					my $unit = 'B';
					if ($size > 1024) {
						$size = int($size / 1024);
						$unit = 'KB';
					}
					$size = commify($size);
					push(@files,{name => $_, size => "$size $unit", realsize => $realsize });
				}
			}
		}
		closedir(DIR);
	}

	return {d => \@dirs, f => \@files};
}



sub validate_params {
	my (%p) = @_;
	my @errs = ();

	my $cf = config->{appconf};
	my $data_base_dir = $cf->{data_base_dir};
	my $triedb_dir = $cf->{triedb_dir};
	my %errs = (
			d => 'Data dir',
			r => 'Input file (output from inspect)',
			t => 'Trie DB',
		);

	for (qw/d r/) {
		my $full_path = File::Spec->catfile($data_base_dir, $p{$_});
		unless ($p{$_} ne "" && -e $full_path) {
			push @errs, "$errs{$_} not found!";
		}
		$p{$_} = $full_path;
	}
	my $full_path = File::Spec->catfile($triedb_dir, $p{t});
	unless ($p{t} ne "" && -e $full_path) {
		push @errs, "$errs{t} not found!";
	}
	$p{t} = $full_path;

	return (\%p, \@errs);
}

true;
