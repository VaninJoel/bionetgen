
package BipartiteGraph;
# pragmas
use strict;
use warnings;
no warnings 'redefine';

# Perl Modules
use Class::Struct;
use List::Util qw(min max sum);
use List::MoreUtils qw( uniq);
use Data::Dumper;

# BNG modules
use StructureGraph;


struct BipartiteGraph => 
{ 
	'NodeList' => '@', # array of strings
	'EdgeList' => '@', # array of strings
	'Name' => '$', # a name which might come in handy to compare/combine rules
	# of the form <transformationstring>:<atomicpatternstring>:<edgetype>
	# or <wildcardpattern>:<atomicpatternstring>:Wildcard
	'NodeGroups' => '@' # array of arrayrefs, each being a ref to a group of nodes	
};

sub isAtomicPattern { return ($_[0] =~ '->') ? 0 : 1; }
sub isTransformation { return ($_[0] =~ '->') ? 1 : 0; }
sub isWildcard{ return ($_[0] =~ /\!\+/) ? 1 : 0; }
sub listHas
{
	my @list = @{shift @_};
	my $item = shift @_;
	foreach my $check(@list)
		{
		if ($item eq $check) { return 1;}
		}
	return 0;
}
sub reverseTransformation
{
	my $tr = shift @_; #unprettified
	my @splits = reverse split('->',prettify($tr));
	my @splits2 = map ( join(',',sort split(',',$_)), @splits);
	my $tr2 = unprettify(join '->',@splits2 );
	return $tr2;
}

sub makeAtomicPattern { return StructureGraph::makeAtomicPattern(@_); }
sub makeTransformation { return StructureGraph::makeTransformation(@_); }
sub printGraph 
{
	my $bpg = shift @_;
	my @nodelist = @{$bpg->{'NodeList'}};
	my @transf = grep ( $_ =~ /->/, @nodelist);
	my @ap = ();
	foreach my $item(@nodelist)
		{
		if ( $item =~ m/->/) { next;}
		else { push @ap, $item; }
		}
	
	my $string = "";
	$string .= "\n\nAtomicPatterns: ".(scalar @ap)."\n";
	$string .= join("", map prettify($_)."\n", @ap);
	$string .= "\n\nTransformations: ".(scalar @transf)."\n";
	$string .= join("", map prettify($_)."\n", @transf);
	$string .= "\n\nEdges: ".(scalar @{$bpg->{'EdgeList'}})."\n";
	$string .= join("", map $_."\n",@{$bpg->{'EdgeList'}});
	return $string;
	
}

sub prettify
{
	my $string = shift @_;
	my $arrow = '->';
	#print ($string, $string =~ /$arrow/, "\n");
	# check if it is a transformation
	if ($string =~ /$arrow/)
	{
		# see if arrow has spaces already
		if ($string =~ /\b$arrow\b/) { return $string;}
		else  
		{
			my @splits = split $arrow,$string;
			if (scalar @splits == 1) { push @splits,"0"; }
			elsif (length $splits[0] == 0) { $splits[0]="0";}
			return join(" -> ",map prettify($_), @splits);
		}
	}
	my $comma = ',';
	if ($string =~ /$comma/) 
	{
		if ($string =~ /\b$comma\b/) { return $string; }
		else 
		{ 
			my @splits = split $comma,$string;
			return join(" , ", @splits); 
		}
	} 
	if ($string =~ /$0^/) { return $string; } 
	#if ($string =~ /\(/)  { return $string; }
	#else { return $string."\(\)"; }
	return $string;
}

sub unprettify
{
	my $string = shift @_;
	$string =~ s/\s//g;
	$string =~ s/\(\)//g;
	$string =~ s/^0//g;
	$string =~ s/0$//g;
	return $string;
}


sub getReactantsProducts
{
	my $string = unprettify(shift @_);
	my @splits = split '->',$string;
	my @reac = ();
	my @prod = ();
	if (scalar @splits == 1) { @reac = ($splits[0]); }
	elsif (length $splits[0] == 0) { @prod = ($splits[1]); }
	else { @reac = split ',',$splits[0]; @prod = split ',',$splits[1]; }
	return (\@reac,\@prod);
}

sub getStructures
{
	my @nodelist = @{shift @_};
	my %structures = ('Mol'=>1,'Comp'=>1,'CompState'=>1,'BondState'=>1,'GraphOp'=>0,'Rule'=>0);
	my @nodes = grep( $structures{$_->{'Type'}}==1, @nodelist);
	return @nodes;
}
sub getContext
{
	my @nodelist = @{shift @_};
	my @nodes_struct = getStructures(\@nodelist);
	my @nodes = hasSide(\@nodes_struct,'both');
	my @context = ();
	
	# comp states
	my @compstates = hasType(\@nodes,'CompState');
	if (@compstates)
	{
		foreach my $node(@compstates)
		{
			my $string = makeAtomicPattern(\@nodes_struct,$node);
			if ($string) { push @context,$string;}
		}
	}
	
	# bond states
	my @bondstates = hasType(\@nodes,'BondState');
	foreach my $node(@bondstates)
	{
		my $string = makeAtomicPattern(\@nodes_struct,$node);
		if ($string) { push @context,$string;}
	}
	
	# unbound states
	my @comps = hasType(\@nodes,'Comp');
	my %unbound;
	foreach my $x(@comps) { $unbound{$x->{'ID'}}=1; }
	my @allbonds = hasType(\@nodelist,'BondState');
	my @allbondparents;
	foreach my $node(@allbonds) { push @allbondparents, @{$node->{'Parents'}}; }
	foreach my $x(@allbondparents) { $unbound{$x}=0; }
	foreach my $x(keys %unbound) 
	{ 
		if ($unbound{$x}) 
		{
			my $node = findNode(\@comps,$x);
			push @context,makeAtomicPattern(\@nodes_struct,$node);
		}
	}
	
	# mol nodes that do not have any components (hence identified by only label)
	my @mols = hasType(\@nodes,'Mol');
	my %havenocomps;
	foreach my $x(@mols) { $havenocomps{$x->{'ID'}}=1; }
	my @allcompparents;
	foreach my $node(@comps) { push @allcompparents, @{$node->{'Parents'}}; }
	foreach my $x(@allcompparents) { $havenocomps{$x}=0; }
	foreach my $x(keys %havenocomps) 
	{ 
		if ($havenocomps{$x}) 
		{
			my $node = findNode(\@mols,$x);
			push @context,makeAtomicPattern(\@nodes_struct,$node);
		}
	}
	
	return @context;
}

sub getSyndelContext
{
	my @nodelist = @{shift @_};
	my $op = shift @_;
	
	my $mol = findNode(\@nodelist,${$op->{'Parents'}}[0]);
	
	# get child components
	my @allcomps = hasType(\@nodelist,'Comp');
	my @comps = grep (${$_->{'Parents'}}[0] eq $mol->{'ID'}, @allcomps);
	my @comps_ids = map $_->{'ID'}, @comps;
	
	# get child component states
	my @allcompstates = hasType(\@nodelist,'CompState');
	my @compstates = ();
	foreach my $x(@allcompstates)
	{
		foreach my $y (@comps_ids)
			{
				if (${$x->{'Parents'}}[0] eq $y) { push @compstates,$x; }
			}
	}
	
	# get child bond states
	my %unbound;
	foreach my $y (@comps_ids) { $unbound{$y} = 1; }
			
	my @allbondstates = hasType(\@nodelist,'BondState');
	my @bondstates = ();
	foreach my $x(@allbondstates)
	{	
		my @parents = @{$x->{'Parents'}};
		foreach my $y (@comps_ids)
		{
			foreach my $z(@parents)
			{
			if ($y eq $z) 
				{
				push @bondstates,$x;
				$unbound{$z} = 0;
				}
			}
		}
	}
	
	my @unboundcomps = ();
	foreach my $x(keys %unbound)
	{
	if ($unbound{$x}) 
		{
		my $node = findNode(\@nodelist,$x);
		push @unboundcomps, $node;
		}
	}
	
	my @syndelnodes = (@compstates,@bondstates,@unboundcomps);
	my @syndel = ();
	foreach my $node(@syndelnodes) { push @syndel, makeAtomicPattern(\@nodelist,$node); }
	
	return @syndel;
}

sub makeEdge
{
	my %shortname = ( 'r'=>"Reactant", 'p'=>"Product", 'c'=>"Context", 's'=>"Syndel", 'w'=>"Wildcard", 'pp'=>"ProcessPair" );
	
	my $node1 = shift @_;
	my $node2 = shift @_;
	my $rel = $shortname{shift @_};
	
	my $string = $node1.":".$node2.":".$rel;
	return $string;
	
}

sub findNode { return StructureGraph::findNode(@_); }
sub hasType { return StructureGraph::hasType(@_); }
sub hasSide { return StructureGraph::hasSide(@_); }
sub printHash {return StructureGraph::printHash(@_); }

sub findParents
{
	my $nodelist = shift @_;
	my $node = shift @_;
	return map findNode($nodelist,$_),@{$node->{'Parents'}};
}

sub combine
{
	my @bpgs = @{shift @_};
	my $bpgout = BipartiteGraph->new();
	
	foreach my $bpg(@bpgs)
		{
		push @{$bpgout->{'NodeList'}}, @{$bpg->{'NodeList'}};
		push @{$bpgout->{'EdgeList'}}, @{$bpg->{'EdgeList'}};
		}
	
	@{$bpgout->{'NodeList'}} = uniq @{$bpgout->{'NodeList'}};
	@{$bpgout->{'EdgeList'}} = uniq @{$bpgout->{'EdgeList'}};

	
	
	return $bpgout;

}
sub addWildcards
{
	my $bpg = shift @_;
	my @nodelist = @{$bpg->{'NodeList'}};
	my @ap = grep (isAtomicPattern($_),@nodelist);
	my @tr = grep (isTransformation($_),@nodelist);
	my @wildcards = grep (isWildcard($_), @ap);
	my @notwildcards = grep (!isWildcard($_), @ap);

	foreach my $wc(@wildcards)
		{
		my @splits = split '\+', $wc;
		my $string = $splits[0];
		
		my @matches = grep(index($_, $string) != -1, @notwildcards);
		foreach my $match(@matches)
			{
			my $edge = makeEdge($wc,$match,'w');
			push @{$bpg->{'EdgeList'}},$edge;
			}
		}
	return;
}
sub addProcessPairs
{
	my $bpg = shift @_;
	my @nodelist = @{$bpg->{'NodeList'}};
	my @trs = grep (isTransformation($_),@nodelist);
	my %checked;
	foreach my $tr(@trs) {$checked{$tr} = 0;}
	foreach my $tr(@trs)
		{
		if ($checked{$tr}) {next;}
		$checked{$tr} = 1;
		my $rev = reverseTransformation($tr);
		if(listHas(\@trs,$rev))
			{
			$checked{$rev} = 1;
			my $edge = makeEdge($tr,$rev,'pp');
			push @{$bpg->{'EdgeList'}},$edge;
			}
		}
}

sub makeRuleBipartiteGraph
{
	# from a rule structure graph
	my $rsg = shift @_;
	my $name = $rsg->{'Name'};
	my @nodelist = @{$rsg->{'NodeList'}};
	
	my $bpg = BipartiteGraph->new();
	$bpg->{'Name'} = $name;
	
	my @graphop = hasType(\@nodelist,'GraphOp');
	my @transf;
	# isolate the common context
	my @contexts = getContext(\@nodelist);
	
	#add edges for reactant, product, common context
	foreach my $op(@graphop)
	{
		my $tr = makeTransformation(\@nodelist,$op);
		# this is because we are currently not treating wildcard bond deletions
		if(length $tr == 0) { next; }
		
		push @{$bpg->{'NodeList'}}, $tr;
		push @transf, $tr;
		
		my ($reac,$prod) = getReactantsProducts($tr);
		push @{$bpg->{'NodeList'}}, @$reac, @$prod;
		foreach my $reactant (@$reac)
		{
			if (length $reactant == 0) {next;}
			my $edge = makeEdge($tr,$reactant,'r');
			push @{$bpg->{'NodeList'}}, $reactant;
			push @{$bpg->{'EdgeList'}}, $edge;
		}
		foreach my $product (@$prod)
		{
			if (length $product == 0) {next;}
			my $edge = makeEdge($tr,$product,'p');
			push @{$bpg->{'NodeList'}}, $product;
			push @{$bpg->{'EdgeList'}}, $edge;
		}
		foreach my $context(@contexts)
		{
			if (length $context == 0) {next;}
			my $edge = makeEdge($tr,$context,'c');
			push @{$bpg->{'NodeList'}}, $context;
			push @{$bpg->{'EdgeList'}}, $edge;
		}
		
		# add syndel edges
		if ($op->{'Name'} =~ /Mol/)
		{
			my @syndels = getSyndelContext(\@nodelist,$op);
			foreach my $syndel(@syndels)
			{
				if (length $syndel == 0) {next;}
				my $edge = makeEdge($tr,$syndel,'s');
				push @{$bpg->{'NodeList'}}, $syndel;
				push @{$bpg->{'EdgeList'}}, $edge;
			}
		}
	}
	
	@{$bpg->{'NodeList'}} = uniq @{$bpg->{'NodeList'}};
	@{$bpg->{'EdgeList'}} = uniq @{$bpg->{'EdgeList'}};
	
	return $bpg;
}

sub makeGroups
{
	my $bpg = shift @_;
	my @nodelist = @{$bpg->{'NodeList'}};
	my @edgelist = @{$bpg->{'EdgeList'}};
	my @groups;
	# isolate the process pairs 
	
	# create isgrouped to keep track of group assignments
	my %isgrouped;
	foreach my $node(@nodelist) {$isgrouped{$node} = 0;}
	
	# isolate and assign process pairs
	my @processpairs = grep(/ProcessPair/,@edgelist);
	foreach my $edge(@processpairs)
	{
		my @splits = split(':',$edge);
		my @trs = splice @splits,0,2;
		foreach my $tr(@trs) { $isgrouped{$tr} = 1; }
		push @groups,\@trs;
	}
	
	# identify unpaired transformations and add them to groups
	my @trs = grep(/->/,@nodelist);
	my @irr = grep( $isgrouped{$_} == 0, @trs);
	foreach my $irr(@irr) 
		{ 
		my @grp = ($irr); 
		$isgrouped{$irr} = 1;
		push @groups,\@grp; 
		}
	
	# isolate and assign reactant/product patterns
	# note: these will be assigned to multiple groups
	# this will be a problem during gml export
	# check at that point when you're assigning group ids
	my @reactprods = grep( /Reactant|Product/,@edgelist);
	foreach my $edge(@reactprods)
	{
		my @splits = split(':',$edge);
		my $tr = shift @splits;
		my $ap =shift @splits;
		foreach my $grp(@groups)
			{
			if (listHas($grp,$tr)) 
				{ 
				$isgrouped{$ap} = 1;
				push @$grp, $ap; 
				}
			}
	}
	
	# isolate and assign wildcard bonds
	# note: these will be assigned to multiple groups
	# this will be a problem during gml export
	# check at that point when you're assigning group ids
	my @wildcards = grep( /Wildcard/,@edgelist);
	foreach my $edge(@wildcards)
	{
		my @splits = split(':',$edge);
		my $wc = shift @splits;
		my $ap = shift @splits;
		foreach my $grp(@groups)
		{
		if (listHas($grp,$ap)) 
			{ 
			$isgrouped{$wc} = 1;
			push @$grp, $wc; 
			}
		}
	}
	$bpg->{'NodeGroups'} = \@groups;
}

sub printGroups
{
	my $bpg = shift @_;
	my @groups = @{$bpg->{'NodeGroups'}};
	return map(("Group ".groupName($_)."\n".join("\n",@{$_})."\n\n",@groups));
}

sub groupName
{
	my @group = @{shift @_};
	my @trs = grep( /->/,@group);
	# assuming groups only have one process or a process pair
	my $tr = $trs[0];
	my $string;
	if ( (index($tr, '~') != -1) )
		{
		# its a statechange
		my @sides = sort split('->',$tr);
		my @s1 = split(/\(|\)/,$sides[0]);
		my @s2 = split(/\(|\)/,$sides[1]);
		my $molname = $s1[0];
		my @s3 = split(/~/,$s1[1]);
		my @s4 = split(/~/,$s2[1]);
		my $compname = $s3[0];
		my @states = sort ($s3[1], $s4[1]);
		$string = $molname."(".$compname."~".$states[0]."~".$states[1].")";
		}
	elsif ( (index($tr, '!') != -1) )
		{
		# its a bond operation
		my @sides = split('->',$tr);
		my $side = (index($sides[0], ',') != -1) ? $sides[0]: $sides[1];
		my @mols = sort split(',',$side);
		$string = join(":",@mols);
		}
	else 
		{
		# its a molecule add or delete opn
		# is it add
		my $type = index($tr, '>')==(length($tr)-1) ? 'delete' : 'add';
		my $len = (length $tr) - 2;
		my $offset = ($type eq 'add') ? 2 : 0;
		$string = "+/-:".substr($tr,$offset,$len);
		}
	return $string;
}
sub analyzeGroups
{
	my $bpg = shift @_;
	my @nodelist = @{$bpg->{'NodeList'}};
	my @edgelist = @{$bpg->{'EdgeList'}};
	my @groups = @{$bpg->{'NodeGroups'}};
	#print printGroups($bpg);
	
	# extract context
	my @context = grep( /Context/, @edgelist);
	my @syndel = grep( /Syndel/, @edgelist);
	my @syn = grep( (index($_, '->') == 0), @syndel);
	my @del = grep( (index($_, '->') != 0), @syndel);
	my @uni = ();
	my @bi = ();
	
	foreach my $i(0..@groups-1)
	{
		foreach my $j($i..@groups-1)
		{
			my @group1 = @{$groups[$i]};
			my @group2 = @{$groups[$j]};
			my $f = 0;
			my $r = 0;
			foreach my $p (@group1)
			{
				foreach my $q(@group2)
				{
					if ($p eq $q) { next; }
					# see if $p is a transformation and $q is a pattern
					if ((index($p, '->') != -1) and (index($q, '->') == -1) )
					{
						my $check = $p.":".$q.":";
						my @reverse = grep ( index($_, $check) != -1, (@context,@syn,@del) );
						my @forward = grep( index($_, $check) != -1, @del);
						if (@forward > 0) {$f++;}
						if (@reverse > 0) {$r++;}
					}
					# see if $q is a transformation and $p is a pattern
					if ((index($p, '->') == -1) and (index($q, '->') != -1) )
					{
						my $check = $q.":".$p.":";
						my @forward = grep ( index($_, $check) != -1, (@context,@syn,@del) );
						my @reverse = grep( index($_, $check) != -1, @del);
						if (@forward > 0) {$f++;}
						if (@reverse > 0) {$r++;}
					}
				}				
			}
			my $groupname1 = groupName(\@group1);
			my $groupname2 = groupName(\@group2);
			my $string1 = $groupname1." ".$groupname2;
			my $string2 = $groupname2." ".$groupname1;
			if ($f > 0 and $r > 0) { push @bi, $string1." ".$f." ".$r; }
			elsif ($f > 0 ) { push @uni, $string1." ".$f; }
			elsif ($r > 0 ) { push @uni, $string2." ".$r; }
		}
	}
	
	return (\@bi,\@uni);
}
1;