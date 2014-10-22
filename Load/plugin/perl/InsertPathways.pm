package ApiCommonData::Load::Plugin::InsertPathways;
#vvvvvvvvvvvvvvvvvvvvvvvvv GUS4_STATUS vvvvvvvvvvvvvvvvvvvvvvvvv
  # GUS4_STATUS | SRes.OntologyTerm              | auto   | absent
  # GUS4_STATUS | SRes.SequenceOntology          | auto   | absent
  # GUS4_STATUS | Study.OntologyEntry            | auto   | absent
  # GUS4_STATUS | SRes.GOTerm                    | auto   | absent
  # GUS4_STATUS | Dots.RNAFeatureExon            | auto   | absent
  # GUS4_STATUS | RAD.SageTag                    | auto   | absent
  # GUS4_STATUS | RAD.Analysis                   | auto   | absent
  # GUS4_STATUS | ApiDB.Profile                  | auto   | absent
  # GUS4_STATUS | Study.Study                    | auto   | absent
  # GUS4_STATUS | Dots.Isolate                   | auto   | absent
  # GUS4_STATUS | DeprecatedTables               | auto   | broken
  # GUS4_STATUS | Pathway                        | auto   | broken
  # GUS4_STATUS | DoTS.SequenceVariation         | auto   | absent
  # GUS4_STATUS | RNASeq Junctions               | auto   | absent
  # GUS4_STATUS | Simple Rename                  | auto   | absent
  # GUS4_STATUS | ApiDB Tuning Gene              | auto   | absent
  # GUS4_STATUS | Rethink                        | auto   | absent
  # GUS4_STATUS | dots.gene                      | manual | absent
die 'This file has broken or unreviewed GUS4_STATUS rules.  Please remove this line when all are fixed or absent';
#^^^^^^^^^^^^^^^^^^^^^^^^^ End GUS4_STATUS ^^^^^^^^^^^^^^^^^^^^
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use Data::Dumper;
use GUS::PluginMgr::Plugin;
use GUS::Supported::ParseKeggXml;
use GUS::Supported::ParseMpmp;
use GUS::Supported::MetabolicPathway;
use GUS::Supported::MetabolicPathways;
use GUS::Model::ApiDB::NetworkContext;
use GUS::Model::ApiDB::Network;
use GUS::Model::ApiDB::NetworkNode;
use GUS::Model::ApiDB::NetworkRelationship;
use GUS::Model::ApiDB::NetworkRelationshipType;
use GUS::Model::ApiDB::NetworkRelContextLink;
use GUS::Model::ApiDB::NetworkRelContext;
use GUS::Model::ApiDB::Pathway;
use GUS::Model::ApiDB::PathwayNode;
use GUS::Model::ApiDB::PathwayImage;
use DBD::Oracle qw(:ora_types);

#MAJOR TO DOs :
#1.) Create OntologyTerm records called Reaction, Enzyme, Compound and EntityShapes (circle, rect.) etc for 
#Pathway graphics. The row and table id of these will then need to be referenced here eventually.
#
#2.) Create an extDbXref table for enzymes and compound and reference them here as a row id and table id eventually.

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
               descr          => 'The file format for pathways (Kegg, MPMP, Biopax, Other)',
               constraintFunc => undef,
               reqd           => 1,
               isList         => 0,
               enum           => 'KEGG, MPMP, Biopax, Other'
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
  my $purposeBrief = "Inserts pathways from a set of KGML or XGMML (MPMP) files into Network schema.";

  my $purpose =  "Inserts pathways from a set of KGML or XGMML (MPMP) files into Network schema.";

  my $tablesAffected = [['ApiDB.NetworkContext','One row for each new context. Added if not already existing'],['ApiDB.Network', 'One Row to identify each pathway'],['ApiDB.NetworkNode', 'one row per for each Coumpound or EC Number in the KGML files'],['ApiDB.NetworkRelationship', 'One row per association bewteen nodes (Compounds/EC Numbers)'], ['ApiDB.NetworkRelationshipType','One row per type of association (if not already existing)'], ['ApiDB.NetworkRelContext','One row per association bewteen nodes (Compounds/EC Numbers) indicating direction of relationship'], ['ApiDB.NetworkRelContextLink','One row per association between a relationship and a network'],['ApiDB.Pathway', 'One Row to identify each pathway'], ['ApiDB.PathwayImage', 'One Row to store a binary image of the pathway'], ['ApiDB.PathwayNode', 'One row to store network and graphical inforamtion about a network node']];

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
  die "$inputFileDir directory does not exist\n" if !(-d $inputFileDir); 

  my $pathwayFormat = $self->getArg('format');
  my $extension = ($pathwayFormat eq 'MPMP') ? 'xgmml' : 'xml';

  my @pathwayFiles = <$inputFileDir/*.$extension>;
  die "No $extension files found in the directory $inputFileDir\n" if not @pathwayFiles;

  my $pathwaysObj = new GUS::Supported::MetabolicPathways;
  $self->{"pathwaysCollection"} = $pathwaysObj;

  $self->readKeggFiles(\@pathwayFiles) if $pathwayFormat eq 'KEGG';
  $self->readXgmmlFiles(\@pathwayFiles) if ($pathwayFormat eq 'MPMP');

  $self->loadPathway($pathwayFormat);
}



sub readKeggFiles {
  my ($self, $kgmlFiles) = @_;

  my $kgmlParser = new GUS::Supported::ParseKeggXml;

  my $pathwaysObj = $self->{pathwaysCollection};
  print "Reading KEGG files...\n";
  my $reverseNodeLookup; # to get uniqId if one has the indexId in hand
  foreach my $kgml (@{$kgmlFiles}) {

    my $pathwayElements = $kgmlParser->parseKGML($kgml);
    my $pathwayObj = $pathwaysObj->getNewPathwayObj($pathwayElements->{NAME});
    $pathwayObj->{source_id} = $pathwayElements->{SOURCE_ID};
    $pathwayObj->{url} = $pathwayElements->{URI};    
    # $pathwayObj->{image_file} = $pathwayElements->{IMAGE_FILE};

    foreach my $node  (keys %{$pathwayElements->{NODES}}) {

      my $uniqId = $node;
      my $id = $node;
      $id =~s/\_X:\d+\_Y:\d+//;  # remove coordinates 

      $reverseNodeLookup->{$pathwayElements->{NODES}->{$node}->{ENTRY_ID}} = $pathwayElements->{NODES}->{$node}->{UNIQ_ID};

      $pathwayObj->setPathwayNode($node, { node_name => $uniqId,
					   uniqId => $uniqId,
                                           node_type => $pathwayElements->{NODES}->{$node}->{TYPE}
                                         });
      $pathwayObj->setNodeGraphics($node, { x => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{X},
                                            y => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{Y},
                                            shape => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{TYPE},
                                            height => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{HEIGHT},
                                            width => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{WIDTH}
					    });
    }


    foreach my $reactionKey (keys %{$pathwayElements->{REACTIONS}}) {
      my $reaction = $pathwayElements->{REACTIONS}->{$reactionKey};

      my $reactName = $reaction->{NAME};
      my $reactType = $reaction->{TYPE};
      my $direction = 1;
      $direction = 0 unless ($reactType eq 'irreversible');

      foreach my $substrate (@{$reaction->{SUBSTRATES}}){
        foreach my $enzyme (@{$reaction->{ENZYMES}}){



	  my $uniqId = $reverseNodeLookup->{$substrate->{ENTRY}};
	  my $enzId = $reverseNodeLookup->{$enzyme};

          $pathwayObj->setPathwayNodeAssociation("$reactionKey"."_"."$substrate->{NAME}", { 
											   source_node => $uniqId ,
                                                                                            associated_node => $enzId,
                                                                                            assoc_type => "Reaction ".$reactType,
                                                                                            direction => $direction,
                                                                                            reaction_name => $reactName
                                                                                          });
        }
      } 

      foreach my $enzyme (@{$reaction->{ENZYMES}}){
        foreach my $product (@{$reaction->{PRODUCTS}}){
	  my $uniqId = $reverseNodeLookup->{$product->{ENTRY}};
	  my $enzId = $reverseNodeLookup->{$enzyme};

          $pathwayObj->setPathwayNodeAssociation("$reactionKey"."_"."$product->{NAME}", { 
											 source_node => $enzId,
                                                                                          associated_node => $uniqId,
                                                                                          assoc_type => "Reaction ".$reactType,
                                                                                          reaction_name => $reactName,
                                                                                          direction => $direction
                                                                                        });
        }
      }
    }

    # add a row in NetworkRelationship for the compound (entity) and entry that is of type 'map'
    foreach my $relationKey (keys %{$pathwayElements->{RELATIONS}}) {
      my $relation = $pathwayElements->{RELATIONS}->{$relationKey};
      foreach my $x (keys %{$relation} ) {
    	if ($relation->{$x}->{INTERACTION_TYPE} eq 'Maplink'){
    	  my $entity = $relation->{$x}->{INTERACTION_ENTITY_ENTRY}; # compound
	  my $cpdId = $reverseNodeLookup->{$entity};
	  if ( $cpdId && $pathwayElements->{NODES}->{$cpdId}->{ENTRY_ID} eq $entity) {
    	      $entity = $pathwayElements->{NODES}->{$cpdId}->{SOURCE_ID} ;
    	    }

    	  # if relation is between compound and entry
    	  my $entry = $relation->{$x}->{ENTRY};
	  my $nodeId = $reverseNodeLookup->{$entry};
	  if ( $nodeId && $pathwayElements->{NODES}->{$nodeId}->{ENTRY_ID} eq $entry ) {
	    $entry = $pathwayElements->{NODES}->{$nodeId}->{SOURCE_ID};
	    if ($pathwayElements->{NODES}->{$nodeId}->{TYPE} eq 'map') {
	      $pathwayObj->{map}->{$nodeId} = $cpdId;
	      print STDOUT "    RELATION1 : $entry,\t AND $entity \n";
	    }
	  }

    	  # if relation is between compound and associated_entry instead
    	  $entry = $relation->{$x}->{ASSOCIATED_ENTRY}; 
	  $nodeId = $reverseNodeLookup->{$entry};
	  if ($nodeId &&  $pathwayElements->{NODES}->{$nodeId}->{ENTRY_ID} eq $entry) {
	    $entry = $pathwayElements->{NODES}->{$nodeId}->{SOURCE_ID};
	    if ($pathwayElements->{NODES}->{$nodeId}->{TYPE} eq 'map') {
	      $pathwayObj->{map}->{$nodeId} = $cpdId;
	      print STDOUT "    RELATION2 : $entry,\t AND $entity \n";
	    }
	  }

    	}
      }
    }

    $pathwaysObj->setPathwayObj($pathwayObj);
    #print STDOUT Dumper $pathwaysObj;
  }
  $self->{"pathwaysCollection"} = $pathwaysObj;
}


sub readXgmmlFiles {
  my ($self, $xgmmlFiles) = @_;

  my $xgmmlParser = new GUS::Supported::ParseMpmp;

  my $pathwaysObj = $self->{pathwaysCollection};
  print "Reading XGMML files...\n";
  my $reverseNodeLookup; # to get uniqId if one has the indexId in hand
  foreach my $xgmml (@{$xgmmlFiles}) {

    my $pathwayElements = $xgmmlParser->parseXGMML($xgmml);
    my $pathwayObj = $pathwaysObj->getNewPathwayObj($pathwayElements->{NAME});
    $pathwayObj->{source_id} = $pathwayElements->{SOURCE_ID};
    $pathwayObj->{url} = $pathwayElements->{URI};

    foreach my $node  (keys %{$pathwayElements->{NODES}}) {
      my $uniqId = $node;
      my $id = $node;
      $id =~s/\_X:\d+\_Y:\d+//;  # remove coordinates 

      $reverseNodeLookup->{$pathwayElements->{NODES}->{$node}->{ENTRY_ID}} = $pathwayElements->{NODES}->{$node}->{UNIQ_ID};

      $pathwayObj->setPathwayNode($node, { node_name => $uniqId,
					   uniqId => $uniqId,
                                           node_type => $pathwayElements->{NODES}->{$node}->{TYPE}
                                         });
      $pathwayObj->setNodeGraphics($node, { x => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{X},
                                            y => $pathwayElements->{NODES}->{$node}->{GRAPHICS}->{Y}
					    });
    }


    foreach my $edge_id (keys %{$pathwayElements->{EDGES}}) {
      my $edge = $pathwayElements->{EDGES}->{$edge_id};
      my $source_id = $edge->{SOURCE_ID};
      my $target_id =  $edge->{TARGET_ID};

      my ($source, $target);
      foreach my $node (keys %{$pathwayElements->{NODES}}) {
	if ($pathwayElements->{NODES}->{$node}->{ENTRY_ID} eq $source_id) {
	  $source = $pathwayElements->{NODES}->{$node}->{UNIQ_ID};
	}
	if ($pathwayElements->{NODES}->{$node}->{ENTRY_ID} eq $target_id) {
	  $target = $pathwayElements->{NODES}->{$node}->{UNIQ_ID};
	}
      }

      $pathwayObj->setPathwayNodeAssociation("$edge_id",
					     {  source_node => $source,
						associated_node => $target,
						assoc_type => "mpmp",
						direction => 1,
						reaction_name => $edge_id
					     });


    }


    $pathwaysObj->setPathwayObj($pathwayObj);
    #print STDOUT Dumper $pathwaysObj;
  }
  $self->{"pathwaysCollection"} = $pathwaysObj;
}


sub loadPathway {
  my ($self, $format) = @_;


  my $network = GUS::Model::ApiDB::Network->new({ name => "Metabolic Pathways - $format",
						  description => "Metabolic Pathways and Associations - $format" });
  if (! $network->retrieveFromDB()) {
    $network->submit();
    print  "Loaded Network...\n"
  };
  my $networkId = $network->getNetworkId();


  my $pathwaysObj = $self->{"pathwaysCollection"};
  die "No Pathways were read from the specified directory/files\n" if (!$pathwaysObj);

    foreach my $pathwayName (keys %{$pathwaysObj}) {
      #get individual pathway
      my $pathwayObj = $pathwaysObj->{$pathwayName};


      #create a network context and pathway record for the pathway
      my $networkContext = GUS::Model::ApiDB::NetworkContext->new({ name => $pathwayObj->{source_id},
								    description => $pathwayName });
      if (! $networkContext->retrieveFromDB()) {
        $networkContext->submit();
        print "Loaded Network Context Record for..$pathwayName\n";
      } else {
        print "Network Context Record already exists for: $pathwayName\n";
        next;
      }
      my $networkContextId = $networkContext->getNetworkContextId();

      my $pathway;
      print "CHECk name= $pathwayName, source_id=" . $pathwayObj->{source_id} . " AND url=" . $pathwayObj->{url} ." DONE\n";
      $pathway = GUS::Model::ApiDB::Pathway->new({ name => $pathwayName,
						   external_database_release_id => 0000,
						   source_id => $pathwayObj->{source_id},
						   url => $pathwayObj->{url} });

      if (! $pathway->retrieveFromDB()) {
        $pathway->submit();
        print "Loaded Pathway Record for..$pathwayName\n";
      }
      my $pathwayId = $pathway->getPathwayId();
      # REVISIT EXT DB NAME ABOVE - IS IT NEEDED ? NETWORK SCHEMA HAS NO EXT DB REFS;



      #load images if present
      if ($pathwayObj->{image_file}) {
        my $imageFileDir = $self->getArg('imageFileDir');
        die "$imageFileDir directory does not exist" if !(-d $imageFileDir);

        my $imgFile = "$imageFileDir/".$pathwayObj->{image_file};
	$imgFile =~s/ec/map/;
        if ($self->loadPathwayImage($pathwayObj->{source_id},$networkContextId, \$imgFile)) {
          print "Loaded Image for: $pathwayName\n";
        }
      } 


      # load ALL nodes
      print "Loading ALL pathways Nodes\n";
      foreach my $n (keys %{$pathwayObj->{nodes}}) {
        my $node = $pathwayObj->{nodes}->{$n};
	  my $mapNode = $node->{node_name};
	  my $nodeGraphics = $pathwayObj->{graphics}->{$mapNode};
	  $self->loadNetworkNode($pathwayId, $node, $nodeGraphics);
      }


      #read and load nodes and associations
      print "Loading Nodes and Associations for.. $pathwayName\n";
      foreach my $reactionKey (keys %{$pathwayObj->{associations}}) {
        my $reaction = $pathwayObj->{associations}->{$reactionKey};
        my $rel_type = ($reaction->{assoc_type} =~ /Reaction/) ? 1 : 2;

        #establish relationship only if both nodes are present.
        next if (!$reaction->{source_node} || !$reaction->{associated_node});

        #source node
	my $srcNode = $pathwayObj->{nodes}->{($reaction->{source_node})};
        my $nodeGraphics = $pathwayObj->{graphics}->{($reaction->{source_node})};
        my $srcNodeId = $self->loadNetworkNode($pathwayId, $srcNode, $nodeGraphics);

        #associated node
	my $asscNode = $pathwayObj->{nodes}->{($reaction->{associated_node})};
        $nodeGraphics = $pathwayObj->{graphics}->{($reaction->{associated_node})};
        my $asscNodeId = $self->loadNetworkNode($pathwayId, $asscNode, $nodeGraphics);

        next unless ($srcNodeId  && $asscNodeId ); 
        #node relationship
        my $relationship = GUS::Model::ApiDB::NetworkRelationship->new({ node_id => $srcNodeId,
                                                                         associated_node_id => $asscNodeId });
        $relationship->submit() unless $relationship->retrieveFromDB();
        my $relId = $relationship->getNetworkRelationshipId();
 
        #relationship type (ex reversible reaction etc).
        my $relType = GUS::Model::ApiDB::NetworkRelationshipType->new({ relationship_type_id => $rel_type,
                                                                        display_name => $reaction->{reaction_name} });
        $relType->submit() unless $relType->retrieveFromDB();
        my $relTypeId = $relType->getNetworkRelationshipTypeId();

        #relationship context and direction
        my $direction = $reaction->{direction}; 
        my $relContext = GUS::Model::ApiDB::NetworkRelContext->new({ network_relationship_id => $relId, 
                                                                     network_relationship_type_id => $relTypeId,
                                                                     network_context_id => $networkContextId,
                                                                     source_node => $direction }); 
        $relContext->submit() unless $relContext->retrieveFromDB();
        my $relContextId= $relContext->getNetworkRelContextId();
      
        #Link relationship to the Network 
        my $relContextLink = GUS::Model::ApiDB::NetworkRelContextLink->new({ network_id => $networkId,
                                                                            network_rel_context_id => $relContextId });
        $relContextLink->submit() unless $relContextLink->retrieveFromDB();

        $self->undefPointerCache();
      }# close relationships

      print "Loading initial relationship(s)\n";
      # now load the pathway to first compound relationship	
      foreach my $n (keys %{$pathwayObj->{map}}) {
	my $identifier = $pathwayId ."_" . $n ; # eg: 571_1.14.-.-_X:140_Y:333

	print STDOUT  " RELATIONSHIP :  $pathwayId _" . $pathwayObj->{map}->{$n} . "  and  $identifier \n";
	my $networkNode = GUS::Model::ApiDB::NetworkNode->new({ #display_label => $n,
								node_type_id => 3,
								identifier => $identifier
							      });
	$networkNode->submit() unless $networkNode->retrieveFromDB();
	my $nodeId = $networkNode->getNetworkNodeId();

	$networkNode = GUS::Model::ApiDB::NetworkNode->new({ #display_label => $pathwayObj->{map}->{$n},
							     node_type_id => 2,
							     identifier => $pathwayId . "_" . $pathwayObj->{map}->{$n}
							   });
	$networkNode->submit() unless $networkNode->retrieveFromDB();
	my $entityId = $networkNode->getNetworkNodeId();

	my $relationship = GUS::Model::ApiDB::NetworkRelationship->new({ node_id => $nodeId,
									 associated_node_id => $entityId });
	$relationship->submit() unless $relationship->retrieveFromDB();

        my $relId = $relationship->getNetworkRelationshipId();
        my $relType = GUS::Model::ApiDB::NetworkRelationshipType->new({ relationship_type_id => 2,
                                                                        display_name => 'Maplink'  });
        $relType->submit() unless $relType->retrieveFromDB();
        my $relTypeId = $relType->getNetworkRelationshipTypeId();


        #relationship context
        my $relContext = GUS::Model::ApiDB::NetworkRelContext->new({ network_relationship_id => $relId, 
                                                                     network_relationship_type_id => $relTypeId,
                                                                     network_context_id => $networkContextId });
        $relContext->submit() unless $relContext->retrieveFromDB();
        my $relContextId= $relContext->getNetworkRelContextId();

        #Link relationship to the Network
        my $relContextLink = GUS::Model::ApiDB::NetworkRelContextLink->new({ network_id => $networkId,
									     network_rel_context_id => $relContextId });
        $relContextLink->submit() unless $relContextLink->retrieveFromDB();
      }


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
  }#close pathway

}#subroutine


sub loadNetworkNode {
  my($self,$pathwayId, $node,$nodeGraphics) = @_;

  if ($node->{node_name}) {
    my $identifier = $pathwayId ."_" . $node->{node_name}; # eg: 571_1.14.-.-_X:140_Y:333
    my $node_type = ($node->{node_type} eq 'enzyme') ? 1 : ($node->{node_type} eq 'compound') ? 2 : ($node->{node_type} eq 'map') ? 3 : 4;
    my $display_label = $node->{node_name};
    $display_label =~s/\_X:\d+(\.?\d*)\_Y:\d+(\.?\d*)//;  # remove coordinates

    my $networkNode = GUS::Model::ApiDB::NetworkNode->new({ display_label => $display_label,
                                                            node_type_id => $node_type,
							    identifier => $identifier
							  });

    $networkNode->submit() unless $networkNode->retrieveFromDB();
    my $nodeId = $networkNode->getNetworkNodeId();

    my $nodeShape ='';
    if ($nodeGraphics->{shape}) {
      $nodeShape = ($nodeGraphics->{shape} eq 'round') ? 1 :
	($nodeGraphics->{shape} eq 'rectangle') ? 2 : ($nodeGraphics->{shape} eq 'roundrectangle') ? 3 : 4;
    }

  my ($networkNode_tableId) = $self->sqlAsArray( Sql => "select table_id from core.tableinfo where name = 'NetworkNode'" );

    #if a parent Pathway Id is provided only then insert a new record.
    if ($pathwayId){
      my $pathwayNode = GUS::Model::ApiDB::PathwayNode->new({ parent_id => $pathwayId,
                                                              display_label => $display_label,
                                                              pathway_node_type_id => $node_type,
                                                              glyph_type_id => $nodeShape,
                                                              x => $nodeGraphics->{x},
                                                              y => $nodeGraphics->{y},
                                                              height => $nodeGraphics->{height},
                                                              width => $nodeGraphics->{width},
							      table_id => $networkNode_tableId,
							      row_id => $nodeId
                                                             });
      $pathwayNode->submit()  unless $pathwayNode->retrieveFromDB();
    }
    return $nodeId;
  }
}


sub loadPathwayImage{
  my($self,$pathwaySourceId,$networkContextId,$imgFile) = @_;

  open(IMGFILE, $$imgFile) or die "Cannot open file $$imgFile\n";
  binmode IMGFILE;

  my ($data, $buffer,$bytes);

  #read upto 500KB img files
  while (($bytes = read IMGFILE, $buffer, 500*1024) != 0) {
          $data .= $buffer;
        }
  close IMGFILE;

  my $sqlCheck = "Select pathway_id from ApiDB.PathwayImage where pathway_id = $networkContextId";
  my $dbh        = $self->getQueryHandle();
  my $sth        = $dbh->prepare($sqlCheck);
  $sth->execute();

  #if not eixsts already then insert a new record.
  if (! $sth->fetchrow_array()){ 
    my $userId     = $self->getDb()->getDefaultUserId();
    my $groupId    = $self->getDb()->getDefaultGroupId(); 
    my $projectId  = $self->getDb()->getDefaultProjectId();
    my $algInvId   = $self->getAlgInvocation()->getId();
 
    my $sql = "Insert into ApiDB.PathwayImage
             (pathway_id, pathway_source_id, image, row_user_id, row_group_id, row_project_id, row_alg_invocation_id)
             values (?,?,?,?,?,?,?)"; 

    my $sthInsert = $dbh->prepare($sql);
    $sthInsert->bind_param(3,$data,{ora_type=>SQLT_BIN});#BIND FOR BLOB DATA - IMAGE
    $sthInsert->execute($networkContextId, $pathwaySourceId, $data, $userId, $groupId, $projectId, $algInvId);

    if ($self->getArg('commit')) {
      $dbh->commit();
    } else {
      $dbh->rollback();
    }
    $sthInsert->finish;
    $sth->finish;
    return 1;
  } else {
    return 0;
  }
}

sub undoTables {
  my ($self) = @_;

  return ('ApiDB.NetworkRelContext',
          'ApiDB.Network',
          'ApiDB.NetworkRelationship',
	  'ApiDB.NetworkNode',
	  'ApiDB.NetworkRelationshipType',
          'ApiDB.NetworkContext',
	  'ApiDB.NetworkRelContextLink',
	  'ApiDB.Pathway',
	  'ApiDB.PathwayNode',
	  'ApiDB.PathwayImage',
	 );
}


1;
