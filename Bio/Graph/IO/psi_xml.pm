#!/bin/perl -w
package Bio::Graph::IO::psi_xml;
use strict;
use XML::Twig;
use Bio::Seq::SeqFactory;
use Bio::Graph::ProteinGraph;
use Bio::Graph::Edge;
use Bio::Graph::IO;
use Bio::Annotation::DBLink;
use Bio::Annotation::Collection;
use Bio::Species;
use vars qw(@ISA  %species $g $c $fac);
@ISA = qw(Bio::Graph::IO);

BEGIN{
		 $fac  = Bio::Seq::SeqFactory->new(
							-type => 'Bio::Seq::RichSeq'
						);
         $g = Bio::Graph::ProteinGraph->new();
}
#parsing done by XML::Twig, not by RootIO, therefore override usual new
sub new {

my ($class,@args) = @_;
my $self = bless {}, $class;
$self->_initialize(@args);
return $self;

}

sub _initialize  {

  my($self,@args) = @_;
  return unless $self->SUPER::_initialize_io(@args);

}

=head2     next_network

 name       : next_network
 purpose    : to construct a protein interaction graph from xml data
 usage      : my $gr = $netowkio->next_network();
 arguments  : void
 returns    : A Bio::Graph::ProteinGraph object

=cut

sub next_network {

 my $self = shift;
 my $t    = XML::Twig->new
				(  TwigHandlers => {
									 proteinInteractor   => \&_proteinInteractor,
								 	 interaction         => \&_addEdge
									});
 $t->parsefile($self->file);
 return $g;	 


}

=head2   _proteinInteractor

 name      : _proteinInteractor
 purpose   : parses protein information into Bio::Seq::RichSeq objects
 returns   : void
 usage     : internally called by next_network(), 
 arguments : none.

=cut

sub _proteinInteractor {
	my ($twig, $pi) = @_;

	my ($acc, $sp, $desc, $taxid,  $prim_id);

	my $org =  $pi->first_child('organism');
	$taxid  = $org->att('ncbiTaxId');
	
	## just make new species object if doesn't already exist ##
	if (!exists($species{$taxid})) {
		my $full       =  $org->first_child('names')->first_child('fullName')->text;
		my ($gen, $sp) = $full =~ /(\S+)\s+(.+)/;
		my $sp_obj     = Bio::Species->new(-ncbi_taxid     => $taxid,
									       -classification => [$sp, $gen],
									      );
		$species{$taxid} = $sp_obj;
		} 
	
	## next extract sequence id info ##
	my @ids          = $pi->first_child('xref')->children();
	my %ids          = map{$_->att('db'), $_->att('id')} @ids;
	 $ids{'psixml'}  = $pi->att('id');
	
	
	$prim_id = defined ($ids{'GI'})?  $ids{'GI'}:'';
	$acc        = $ids{'RefSeq'} || $ids{'SWP'} || $ids{'PIR'} || $ids{'GI'};
	
	## get description line
	$desc    = $pi->first_child('names')->first_child('fullName')->text;

	## use ids that aren't accession_no or primary_tag to build dbxref Annotations
	my $ac = Bio::Annotation::Collection->new();	
	for my $db (keys %ids) {
		next if $ids{$db} eq $acc or $ids{$db} eq $prim_id;
		my $an = Bio::Annotation::DBLink->new( -database   => $db,
											   -primary_id => $ids{$db},
											);
		$ac->add_Annotation('dblink',$an);
	}

	## now we can make sequence object ##
	my $node = $fac->create(
						-accession_number => $acc,
						-desc             => $desc,
						-display_id       => $acc,
						-primary_id       => $prim_id,
						-species          => $species{$taxid},
						-annotation       => $ac);
	
	## now fill hash with keys = ids and vals = node refs to have lookip
	## hash for nodes by any id.	
	$g->{'_id_map'}{$ids{'psixml'}}          = $node;
	if (defined($node->primary_id)) {
		$g->{'_id_map'}{$node->primary_id} = $node;
		}
	if (defined($node->accession_number)) {
		$g->{'_id_map'}{$node->accession_number} = $node;
		}
	## cycle thru annotations
	 $ac = $node->annotation();
	for my $an ($ac->get_Annotations('dblink')) {
		$g->{'_id_map'}{$an->primary_id} = $node;
		}
	$twig->purge();
}

=head2      add_edge

 name     : add_edge
 purpose  : adds a new edge to a graph
 usage    : do not call, called by next_network
 returns  : void
 
=cut

sub _addEdge {

	my ($twig, $i) = @_;
	my @ints = $i->first_child('participantList')->children;
	my @node = map{$_->first_child('proteinInteractorRef')->att('ref')} @ints;
    my $edge_id = $i->first_child('xref')->first_child('primaryRef')->att('id');
	$g->add_edge(Bio::Graph::Edge->new(
					-nodes =>[($g->{'_id_map'}{$node[0]}, 
                               $g->{'_id_map'}{$node[1]})],
					-id    => $edge_id));
	$twig->purge();
}
1;

