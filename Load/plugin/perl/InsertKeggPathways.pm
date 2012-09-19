package ApiCommonData::Load::Plugin::InsertKeggPathways;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use Data::Dumper;
use GUS::PluginMgr::Plugin;
use GUS::Supported::ParseKeggXml;
use GUS::Supported::MetabolicPathway;
use GUS::Supported::MetabolicPathways;
use GUS::Model::ApiDB::NetworkContext;
use GUS::Model::ApiDB::Network;
use GUS::Model::ApiDB::NetworkNode;
use GUS::Model::ApiDB::NetworkRelationship;
use GUS::Model::ApiDB::NetworkRelationshipType;
use GUS::Model::ApiDB::NetworkRelContext;
use GUS::Model::ApiDB::Pathway;
use GUS::Model::ApiDB::PathwayNode;
use GUS::Model::ApiDB::PathwayImage;
use DBD::Oracle qw(:ora_types);


# ----------------------------------------------------------
# Load Arguments
# ----------------------------------------------------------

sub getArgsDeclaration {
  my $argsDeclaration  =
    [   
     stringArg({ name => 'pathwaysFileDir',
                 descr => 'full path to xml files',
                 constraintFunc=> undef,
                 reqd  => 1,
                 isList => 0,
                 mustExist => 1,
	       }),

     enumArg({ name           => 'format',
               descr          => 'The file format for pathways (Kegg, Biopax, Other)',
               constraintFunc => undef,
               reqd           => 1,
               isList         => 0,
               enum           => 'KEGG, Biopax, Other'
	    }),

     stringArg({ name => 'imageFileDir',
                 descr => 'full path to image files',
                 constraintFunc=> undef,
                 reqd  => 0,
                 isList => 0,
                 mustExist => 0,
	       }),

    ];

  return $argsDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = "Inserts KEGG pathways from a set of KGML files into Network schema.";

  my $purpose =  "Inserts KEGG pathways from a set of KGML files into Network schema.";

  my $tablesAffected = [['ApiDB.NetworkContext','One row for each new context. Added if not already existing'],['ApiDB.Network', 'One Row to identify each pathway'],['ApiDB.NetworkNode', 'one row per for each Coumpound or EC Number in the KGML files'],['ApiDB.NetworkRelationship', 'One row per association bewteen nodes (Compounds/EC Numbers)'], ['ApiDB.NetworkRelationshipType','One row per type of association (if not already existing)'], ['ApiDB.NetworkRelContext','One row per association bewteen nodes (Compounds/EC Numbers) indicating direction of relationship']];

  my $tablesDependedOn = [['Core.TableInfo',  'To store a reference to tables that have Node records (ex. EC Numbers, Coumpound IDs']];

  my $howToRestart = "No restart";

  my $failureCases = "";

  my $notes = "";

  my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief, tablesAffected=>$tablesAffected, tablesDependedOn=>$tablesDependedOn, howToRestart=>$howToRestart, failureCases=>$failureCases,notes=>$notes};

  return $documentation;
}

#--------------------------------------------------------------------------------

sub new {
  my $class = shift;
  my $self = {};
  bless($self, $class);

  my $documentation = &getDocumentation();

  my $args = &getArgsDeclaration();

  my $configuration = { requiredDbVersion => 3.6,
                        cvsRevision => '$Revision$',
                        name => ref($self),
                        argsDeclaration => $args,
                        documentation => $documentation
                      };

  $self->initialize($configuration);

  return $self;
}


#######################################################################
# Main Routine
#######################################################################

sub run {
  my ($self) = shift;

  my $inputFileDir = $self->getArg('pathwaysFileDir');
  die "$inputFileDir directory does not exist" if !(-d $inputFileDir); 

  my @pathwayFiles = <$inputFileDir/*.xml>;
  die "No files found in the directory $inputFileDir" if not @pathwayFiles;

  my $pathwaysObj = new GUS::Supported::MetabolicPathways;
  $self->{"pathwaysCollection"} = $pathwaysObj;

  my $pathwayFormat = $self->getArg('format');
  $self->readKeggFiles(\@pathwayFiles) if $pathwayFormat eq 'KEGG';
  $self->loadPathway();
}



sub readKeggFiles {
  my ($self, $kgmlFiles) = @_;

  my $kgmlParser = new GUS::Supported::ParseKeggXml;

  my $pathwaysObj = $self->{pathwaysCollection};

  foreach my $kgml (@{$kgmlFiles}) {

    my $pathwayElements = $kgmlParser->parseKGML($kgml);
    my $pathwayObj = $pathwaysObj->getNewPathwayObj($pathwayElements->{NAME});
    $pathwayObj->{source_id} = $pathwayElements->{SOURCE_ID};
    $pathwayObj->{url} = $pathwayElements->{URI};    
    $pathwayObj->{image_file} = $pathwayElements->{IMAGE_FILE};    

    foreach my $node  (keys %{$pathwayElements->{NODES}}) {
      $pathwayObj->setPathwayNode($node, { node_name => $node,
                                           node_type => $pathwayElements->{NODES}->{$node}->{TYPE}
                                         });

      $pathwayObj->setNodeGraphics($node, { x => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{X},
                                            y => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{Y},
                                            shape => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{TYPE},
                                            height => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{HEIGHT},
                                            width => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{WIDTH}
                                           }); 
    }

    foreach my $reaction (keys %{$pathwayElements->{REACTIONS}}) {
    my $reactType = $pathwayElements->{REACTIONS}->{$reaction}->{TYPE};
    my $direction = 1;
    $direction = 0 unless ($reactType eq 'irreversible');
 
    $pathwayObj->setPathwayNodeAssociation($reaction, { source_node => $pathwayElements->{REACTIONS}->{$reaction}->{SUBSTRATE}->{NAME}, 
                                                        associated_node => $pathwayElements->{REACTIONS}->{$reaction}->{PRODUCT}->{NAME},
                                                        assoc_type => "Reaction ".$reactType,
                                                        direction => $direction
                                                       });
 

    }

    $pathwaysObj->setPathwayObj($pathwayObj);
    print STDOUT Dumper $pathwaysObj;
  }
  $self->{"pathwaysCollection"} = $pathwaysObj;
}



sub loadPathway {
  my ($self, $format, $debug) = @_;
                    

  print "Loading Network Context..." if $debug;
  my $networkContext = GUS::Model::ApiDB::NetworkContext->new({ name => 'Metabolic Pathways - $format',
                                                                description => 'Metabolic Pathways and Associations - $format'
                                                                });
  $networkContext->submit() unless $networkContext->retrieveFromDB();
  my $networkContextId = $networkContext->getNetworkContextId();


  my $pathwaysObj = $self->{"pathwaysCollection"};
  die "No Pathways were read from the specified directory/files" if (!$pathwaysObj);

    foreach my $pathwayName (keys %{$pathwaysObj}) {
      #get individual pathway
      my $pathwayObj = $pathwaysObj->{$pathwayName};

      #create a network and pathway record for the pathway
      print "Loading Network Record...$pathwayName" if $debug; 
      my $network = GUS::Model::ApiDB::Network->new({ name => $pathwayObj->{source_id},
                                                      description => $pathwayName });
      $network->submit() unless $network->retrieveFromDB();
      my $networkId = $network->getNetworkId();

      print "Loading Pathway Record...$pathwayName" if $debug; 
      my $pathway = GUS::Model::ApiDB::Pathway->new({ name => $pathwayName,
                                                      external_database_release_id => 0000,
                                                      source_id => $pathwayObj->{source_id},
                                                      url => $pathwayObj->{url} });
      $pathway->submit() unless $pathway->retrieveFromDB();
      # REVISIT EXT DB NAME ABOVE - IS IT NEEDED ? NETWORK SCHEMA HAS NO EXT DB REFS;



      #load images if present
      if ($pathwayObj->{image_file}) {
        my $imageFileDir = $self->getArg('imageFileDir');
        die "$imageFileDir directory does not exist" if !(-d $imageFileDir);
        my $imgFile = "$imageFileDir/".$pathwayObj->{image_file};
        $self->loadPathwayImage($pathwayObj->{source_id},$networkId, \$imgFile);
      } 


      #read and load nodes and associations
      print "Loading Network Nodes and Associatons for... $pathwayName" if $debug;

      foreach my $reactionName (keys %{$pathwayObj->{associations}}) {
        my $reaction = $pathwayObj->{associations}->{$reactionName};
        my $rel_type = ($reaction->{assoc_type} =~ /Reaction/) ? 1 : 2;

        #source node
        my $srcNode = $pathwayObj->{nodes}->{($reaction->{source_node})};
        print "$srcNode->{node_name}\n";
        my $nodeGraphics = $pathwayObj->{graphics}->{($reaction->{source_node})};
        my $srcNodeId = $self->loadNetworkNode($srcNode, $nodeGraphics);

        #associated node
        my $asscNode = $pathwayObj->{nodes}->{($reaction->{associated_node})}; 
        $nodeGraphics = $pathwayObj->{graphics}->{($reaction->{source_node})};
        my $asscNodeId = $self->loadNetworkNode($asscNode, $nodeGraphics);

          
        #node relationship
        my $relationship = GUS::Model::ApiDB::NetworkRelationship->new({ node_id => $srcNodeId,
                                                                         associated_node_id => $asscNodeId });
        $relationship->submit() unless $relationship->retrieveFromDB();
        my $relId = $relationship->getNetworkRelationshipId();
 
        #relationship type (ex reversible reaction etc).
        my $relType = GUS::Model::ApiDB::NetworkRelationshipType->new({ relationship_type_id => $rel_type,
                                                                       display_name => $reactionName });
        $relType->submit() unless $relType->retrieveFromDB();
        my $relTypeId = $relType->getNetworkRelationshipTypeId();

        #relationship context and direction
        my $direction = $reaction->{direction}; 
        my $relContext = GUS::Model::ApiDB::NetworkRelContext->new({ network_relationship_id => $relId, 
                                                                    network_relationship_type_id => $relTypeId,
                                                                    network_context_id => $networkContextId,
                                                                    source_node => $direction }); 
        $relContext->submit() unless $relContext->retrieveFromDB();
      }# close relationships

        #---------------
        #For Future TO DO
        #Cross Ref Enzymes and compounds. A new DBXref for pathway Enzymes and Compounds weill have to be created.
        #the foriegn key constraint in the schema will the be enforced for table_id and row_id
        #my ($table_id, $row_id);
        #if ($node->{NODE_TYPE} eq 'enzyme') {
          #my ($tableId) = $self->sqlAsArray( Sql => "select table_id from core.tableinfo where name = 'EnzymeClass'" );
         # my ($row_id)  = $self->sqlAsArray( Sql => "select row_id from sres.enzymeclass where ec_number = $node->{NODE_NAME}" );
        #} elsif ($node->{NODE_TYPE} eq 'compound') {
         # my ($tableId) = $self->sqlAsArray( Sql => "select table_id from core.tableinfo where name = ''" );
         # my ($row_id)  = $self->sqlAsArray( Sql => "select row_id from sres.enzymeclass where ec_number = $node->{NODE_NAME}" );
       # }
        #---------------
      print "Loaded all Network relationships for... $pathwayName\n" if $debug;     
  }#close pathway

}#subroutine


sub loadNetworkNode {
  my($self,$node,$nodeGraphics) = @_;

  my $node_type = ($node->{node_type} eq 'enzyme') ? 1 : ($node->{node_type} eq 'compound') ? 2 : 3;
  my $networkNode = GUS::Model::ApiDB::NetworkNode->new({ display_label => $node->{node_name},
                                                          node_type_id => $node_type });

  $networkNode->submit() unless $networkNode->retrieveFromDB();
  my $nodeId = $networkNode->getNetworkNodeId();

  my $nodeShape = ($nodeGraphics->{shape} eq 'round') ? 1 :
                  ($nodeGraphics->{shape} eq 'rectangle') ? 2 : 3;

  my $pathwayNode = GUS::Model::ApiDB::PathwayNode->new({ display_label => $node->{node_name},
                                                          pathway_node_type_id => $node_type,
                                                          glyph_type_id => $nodeShape,
                                                          x => $nodeGraphics->{x},
                                                          y => $nodeGraphics->{y},
                                                          height => $nodeGraphics->{height},
                                                          width  => $nodeGraphics->{width} });
  $pathwayNode->submit() unless $pathwayNode->retrieveFromDB();
  return $nodeId 
}


sub loadPathwayImage{
  my($self,$pathwaySourceId,$networkId,$imgFile) = @_;

  open(IMGFILE, $$imgFile)  or die "Cannot open file";
  binmode IMGFILE;

  my ($data, $buffer,$bytes);
  #read upto 500KB img files
  while (($bytes = read IMGFILE, $buffer, 500*1024) != 0) {
          $data .= $buffer;
        }
  close IMGFILE;

  my $sql = "Insert into ApiDB.PathwayImage  (pathway_id, pathway_source_id, image, row_user_id, row_group_id, row_project_id, row_alg_invocation_id) values (?,?,?,?,?,?,?)"; 
  my $dbh        = $self->getQueryHandle();
  my $userId     = $self->getDb()->getDefaultUserId();
  my $groupId    = $self->getDb()->getDefaultGroupId(); 
  my $projectId  = $self->getDb()->getDefaultProjectId();
  my $algInvId   = $self->getAlgInvocation()->getId();

  my $sth = $dbh->prepare($sql);
  $sth->bind_param(3,$data,{ora_type=>SQLT_BIN});#BIND FOR BLOB DATA - IMAGE
  $sth->execute($networkId, $pathwaySourceId, $data, $userId, $groupId, $projectId, $algInvId);

  if ($self->getArg('commit')) {
    $self->log("Committing");
    $dbh->commit();
  } else {
    $dbh->rollback();
    $self->log("Rolling back");
  }
  $sth->finish;
}

sub undoTables {
  my ($self) = @_;

  return ('ApiDB.NetworkContext',
	  'ApiDB.Network',
	  'ApiDB.NetworkNode',
	  'ApiDB.NetworkRelationship',
	  'ApiDB.NetworkRelationshipType',
	  'ApiDB.NetworkRelContext',
	  'ApiDB.Pathway',
	  'ApiDB.PathwayNode',
	  'ApiDB.PathwayImage',
	 );
}


1;
