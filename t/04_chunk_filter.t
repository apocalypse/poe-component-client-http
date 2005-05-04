BEGIN { $| = 1; print "1..2\n"; }


END {$got_eof ? print "ok 2\n" : print "not ok 2\n";}
#END {$got_input ? print "ok 2\n" : print "not ok 2\n";}
END {print "not ok 1\n" unless $loaded;}

use POE qw(
		Wheel::ReadWrite
		Driver::SysRW
		Filter::Line
		Filter::Stream
		Filter::HTTPHead
		Filter::HTTPChunk
		Filter::XML
	);

if (defined $INC{"POE/Filter/HTTPChunk.pm"}) {
        $loaded = 1;
        print "ok 1\n";
}

use IO::File;

my $session = POE::Session->create(
	inline_states => {
		_start => \&start,
		input => \&input,
		error => \&error,
		flushed => \&flushed,
	},
);

IO::Handle::autoflush (STDOUT, 1);
$poe_kernel->run;


sub start {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

	my $filter = POE::Filter::HTTPHead->new;
	$fh = IO::File->new ("<chunked");
	$fh->autoflush;
	
	my $wheel = POE::Wheel::ReadWrite->new (
		Handle => $fh,
		Driver => POE::Driver::SysRW->new (BlockSize => 100),
		InputFilter => $filter,
		InputEvent => 'input',
		ErrorEvent => 'error',
	);
	$heap->{'wheel'} = $wheel;
}

sub input {
	my ($kernel, $heap, $data) = @_[KERNEL, HEAP, ARG0];
	print STDERR "$data";
	if ($heap->{wheel}->get_input_filter->isa('POE::Filter::HTTPHead')) {
	  if (UNIVERSAL::isa ($data, 'HTTP::Response')) {
	  	my $te = $data->header('Transfer-Encoding');
		my @te = split(/\s*,\s*/, lc($te));
		$te = pop(@te);
		warn "transfer encoding $te";
		if ($te eq 'chunked') {
	  		$heap->{wheel}->set_filter (POE::Filter::HTTPChunk->new (Response => $response));
		} else {
	  		$heap->{wheel}->set_filter (POE::Filter::Line->new);
		}
	  } else {
	    print STDERR "not a response\n";
	  }
	}
}

sub error {
	my $heap = $_[HEAP];
	my ($type, $errno, $errmsg, $id) = @_[ARG0..$#_];
	if ($errno == 0) {
		$got_eof = 1;
	} else {
		print STDERR "$type err $errno ($errmsg) for $id\n";
	}
	delete $heap->{wheel};
}
