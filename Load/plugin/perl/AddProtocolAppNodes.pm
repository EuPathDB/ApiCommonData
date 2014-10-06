package ApiCommonData::Load::Plugin::AddProtocolAppNodes;

@ISA = qw(GUS::Community::Plugin::AddToStudy);

use strict;
use GUS::Community::Plugin::AddToStudy;

 sub new {
   my ($class) = @_;
   my $self = {};
   bless($self,$class);

   my $documentation = $self->SUPER::getDocumentation();
   my $argumentDeclaration    = $self->SUPER::getArgumentsDeclaration();

   $self->initialize({requiredDbVersion => 4.0,
 		     cvsRevision => '$Revision$',
 		     name => ref($self),
 		     revisionNotes => '',
 		     argsDeclaration => $argumentDeclaration,
 		     documentation => $documentation
 		    });
   return $self;
 }

sub handleExistingProtocolAppNode {
  my ($self,$protocolAppNode) = @_;
  my $source_id = $protocolAppNode->findvalue('./source_id');
  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode->new({source_id => $source_id});
   $self->userError("Input ProtocolAppNode $source_id is not in the database, please make sure that all input protocoal app nodes have been loaded") unless $protocolAppNode->retrieveFromDB();
  my $id = $protocolAppNode->getId();

  return ($id);

}

sub setExtDbSpec () {
my ($self, $node) = @_;
my $extDbSpec = $node->findvalue('./external_database_release');
$extDbSpec = $node->findvalue('./ext_db_rls') unless $extDbSpec;
$extDbSpec = 'OBI|http://purl.obolibrary.org/obo/obi/2012-07-01/obi.owl' unless $extDbSpec;
 my $extDbRlsId =  $self->getExtDbRlsId($extDbSpec) ;
      if (!$extDbRlsId || !defined($extDbRlsId)) {
	$self->userError("Database is missing an entry for $extDbSpec");
	}
return $extDbRlsId;
}

1;
