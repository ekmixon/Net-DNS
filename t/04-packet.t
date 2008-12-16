# $Id$	-*-perl-*-

use Test::More tests => 80;
use strict;

use Net::DNS;

my $had_xs=$Net::DNS::HAVE_XS; 


#	new() class constructor method must return object of appropriate class
isa_ok(Net::DNS::Packet->new(),	'Net::DNS::Packet',	'new() object');


#	string method returns character string representation of object
like(Net::DNS::Packet->new(undef)->string,	"/IN\tA/",	'$packet->string' );


#	Create a DNS query packet
my ($domain, $type, $class) = qw(example.test MX IN);
my $question = Net::DNS::Question->new($domain, $type, $class);

my $packet = Net::DNS::Packet->new($domain, $type, $class);
like($packet->string,	"/$class\t$type/",	'create query packet' );

ok($packet->header,	'packet->header() method works');
ok($packet->header->isa('Net::DNS::Header'),	'header() returns header object');

my @question = $packet->question;
ok(@question && @question == 1,		'packet->question() returns single element list');
my ($q) = @question;
ok($q->isa('Net::DNS::Question'),	'list element is a question object');
is_deeply($q,	$question,		'question object correct');


#	Empty packet created when new() arguments omitted
my $empty = Net::DNS::Packet->new();
ok($empty,	'create empty packet' );
foreach my $method ( qw(question answer authority additional) ) {
	my @result = $empty->$method;
	ok(@result == 0,	"$method() returns empty list");
}

#	Default question added to empty packet
my $default = Net::DNS::Question->new qw(. ANY ANY);
ok($empty->data,	'packet->data() method works');
my ($data) = $empty->question;
is_deeply($data,	$default,	'implicit question in empty packet' );


#	parse() class constructor method must return object of appropriate class
my $packet_data = $packet->data;
my $packet2 = Net::DNS::Packet->parse(\$packet_data);
isa_ok($packet2,	'Net::DNS::Packet',	'parse() object');
is_deeply($packet2->question, $packet->question, 'check question section');


#	parse() class constructor raises exception when data truncated
my $truncated = $packet->data;
while ( chop $truncated ) {
	my ($object,$error) = eval { Net::DNS::Packet->parse(\$truncated) };
	my $length = length $truncated;
	like($error,	'/exception/i',	"parse(truncated($length))");
}


#	Use push() to add RRs to each section
my $update = Net::DNS::Packet->new('.');
my $index;
foreach my $section ( qw(answer authority additional) ) {
	my $i = ++$index;
	my $rr1 = Net::DNS::RR->new(	Name	=> "$section$i.example.test",
					Type	=> "A",
					Address	=> "10.0.0.$i"
					);
	my $string1 = $rr1->string;
	my $count1 = $update->push($section, $rr1);
	like($update->string,	"/$string1/",	"push first RR into $section section");
	is($count1,	1,	"push() returns $section RR count");

	my $j = ++$index;
	my $rr2 = Net::DNS::RR->new(	Name	=> "$section$j.example.test",
					Type	=> "A",
					Address	=> "10.0.0.$j"
					);
	my $string2 = $rr2->string;
	my $count2 = $update->push($section, $rr2);
	like($update->string,	"/$string2/",	"push second RR into $section section");
	is($count2,	2,	"push() returns $section RR count");
}

# Add enough distinct labels to render compression unusable at some point
for (0..255) {
    $update->push('answer',
		  Net::DNS::RR->new("X$_ TXT \"" . pack("A255", "x").'"'));
}
$update->push('answer', Net::DNS::RR->new('XY TXT ""'));
$update->push('answer', Net::DNS::RR->new('VW.XY TXT ""'));

#	Parse data and compare with original
my $buffer = $update->data;
my $parsed = eval { Net::DNS::Packet->parse(\$buffer) };
ok($parsed, 'parse() from data buffer works');
foreach my $count ( qw(qdcount ancount nscount arcount) ) {
	is($parsed->header->$count, $update->header->$count, "check header->$count correct");
}


foreach my $section ( qw(question answer authority additional) ) {
	my @original = map{$_->string} $update->$section;
	my @content = map{$_->string} $parsed->$section;
	is_deeply(\@content, \@original, "check content of $section section");
}


#	check that pop() removes RR from section
foreach my $section ( qw(question answer authority additional) ) {
	my $c1 = $update->push($section);
	my $rr = $update->pop($section);
	my $c2 = $update->push($section);
	is($c2,	$c1-1,	"pop() RR from $section section");
}




#	Test using a predefined answer. This is an answer that was generated by a bind server.

my $BIND = pack('H*','22cc85000001000000010001056461636874036e657400001e0001c00c0006000100000e100025026e730472697065c012046f6c6166c02a7754e1ae0000a8c0000038400005460000001c2000002910000000800000050000000030');

my $bind = Net::DNS::Packet->parse(\$BIND);

is($bind->header->qdcount, 1, 'check question count in synthetic packet header');
is($bind->header->ancount, 0, 'check answer count in synthetic packet header');
is($bind->header->nscount, 1, 'check authority count in synthetic packet header'); 
is($bind->header->adcount, 1, 'check additional count in synthetic packet header');

my ($rr) = $bind->additional;

is($rr->type,	'OPT',	'Additional section packet is EDNS0 type');
is($rr->class,	'4096',	'EDNS0 packet size correct');



#	Check dn_expand can detect data corrupted by introducing a pointer loop.
my $circular = pack('H*', '1025000000010000000000007696e76616c6964c00000010001');

SKIP: {
	skip 'No dn_expand_xs available', 1 unless $had_xs;
	my ($pkt, $error) = Net::DNS::Packet->parse(\$circular);
	like($error,	'/exception/i',	'loopdetection in dn_expand_XS');
}


# Force use of the pure-perl parser
$Net::DNS::HAVE_XS=0;
my ($pkt, $error) = Net::DNS::Packet->parse(\$circular);
like($error,	'/exception/i',	'loopdetection in dn_expand_PP');

