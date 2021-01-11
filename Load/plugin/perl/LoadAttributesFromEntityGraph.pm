package ApiCommonData::Load::Plugin::LoadAttributesFromEntityGraph;

@ISA = qw(GUS::PluginMgr::Plugin);
use strict;
use GUS::PluginMgr::Plugin;

use GUS::Model::ApiDB::Attribute;

use ApiCommonData::Load::Fifo;
use ApiCommonData::Load::Sqlldr;

use Scalar::Util qw(looks_like_number);

use Time::HiRes qw(gettimeofday);

use ApiCommonData::Load::StudyUtils qw(queryForOntologyTerms);

use JSON;

use Data::Dumper;

my $END_OF_RECORD_DELIMITER = "#EOR#\n";
my $END_OF_COLUMN_DELIMITER = "#EOC#\t";

my $purposeBrief = 'Read Study tables and insert tall table for attribute values and attribute table';
my $purpose = $purposeBrief;

my $tablesAffected =
    [ ['ApiDB::Attribute', ''],
      ['ApiDB::AttributeValue', '']
    ];

my $tablesDependedOn =
    [['ApiDB::Study',''],
     ['ApiDB::EntityAttributes',  ''],
     ['ApiDB::ProcessAttributes',  ''],
     ['ApiDB::ProcessType',  ''],
     ['ApiDB::EntityType',  ''],
     ['ApiDB::AttributeUnit',  ''],
     ['SRes::OntologyTerm',  ''],
     ['ApiDB::ProcessType',  ''],
    ];

my $howToRestart = ""; 
my $failureCases = "";
my $notes = "";

my $documentation = { purpose => $purpose,
                      purposeBrief => $purposeBrief,
                      tablesAffected => $tablesAffected,
                      tablesDependedOn => $tablesDependedOn,
                      howToRestart => $howToRestart,
                      failureCases => $failureCases,
                      notes => $notes
};

my $argsDeclaration =
[
   fileArg({name           => 'logDir',
            descr          => 'directory where to log sqlldr output',
            reqd           => 1,
            mustExist      => 1,
            format         => '',
            constraintFunc => undef,
            isList         => 0, }),

 stringArg({ name            => 'extDbRlsSpec',
	     descr           => 'ExternalDatabaseSpec for the Entity Graph',
	     reqd            => 1,
	     constraintFunc  => undef,
	     isList          => 0 }),

 stringArg({ name            => 'ontologyExtDbRlsSpec',
	     descr           => 'ExternalDatabaseSpec for the Associated Ontology',
	     reqd            => 1,
	     constraintFunc  => undef,
	     isList          => 0 }),

];

sub getActiveForkedProcesses {
  my ($self) = @_;

  return $self->{_active_forked_processes} || [];
}

sub addActiveForkedProcess {
  my ($self, $pid) = @_;

  push @{$self->{_active_forked_processes}}, $pid;
}

sub resetActiveForkedProcesses {
  my ($self) = @_;

  $self->{_active_forked_processes} = [];
}

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class);

  $self->initialize({requiredDbVersion => 4.0,
		     cvsRevision => '$Revision$', # cvs fills this in!
		     name => ref($self),
		     argsDeclaration   => $argsDeclaration,
		     documentation     => $documentation
		    });
  return $self;
}


$| = 1;

sub run {
  my $self  = shift;

  chdir $self->getArg('logDir');

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));
  
  my $studies = $self->sqlAsDictionary( Sql  => "select study_id, max_attr_length from apidb.study where external_database_release_id = $extDbRlsId");

  $self->error("Expected one study row.  Found ". scalar keys %{$studies}) unless(scalar keys %$studies == 1);

  $self->getQueryHandle()->do("alter session set nls_date_format = 'yyyy-mm-dd hh24:mi:ss'") or die $self->getQueryHandle()->errstr;

  my ($attributeCount, $attributeValueCount, $entityTypeGraphCount);
  while(my ($studyId, $maxAttrLength) = each (%$studies)) {
    my $ontologyTerms = &queryForOntologyTerms($self->getQueryHandle(), $self->getExtDbRlsId($self->getArg('ontologyExtDbRlsSpec')));

    my $entityTypeIds = $self->queryForEntityTypeIds($studyId);

    my $ct = $self->loadAttributeValues($studyId, $ontologyTerms, $maxAttrLength);
    $attributeValueCount = $attributeValueCount + $ct;

    $self->addUnitsToOntologyTerms($studyId, $ontologyTerms);

    my $act = $self->loadAttributeTerms($ontologyTerms, $studyId, $entityTypeIds);
    $attributeCount = $attributeCount + $act;
  }

  return "Loaded $attributeValueCount rows into ApiDB.AttributeValue, $attributeCount rows into ApiDB.Attribute and $entityTypeGraphCount rows into ApiDB.EntityTypeGraph";
}


sub queryForEntityTypeIds {
  my ($self, $studyId) = @_;

  my %rv;

  my $dbh = $self->getQueryHandle();

  my $sql = "select t.entity_type_id, ot.source_id
from apidb.entitytype t, sres.ontologyterm ot
where ot.ontology_term_id = t.type_id
and study_id = $studyId";

  my $sh = $dbh->prepare($sql);
  $sh->execute();

  while(my ($etId, $stableId) = $sh->fetchrow_array()) {
    $rv{$etId} = $stableId;
  }
  $sh->finish();

  return \%rv;
}



sub loadAttributeTerms {
  my ($self, $ontologyTerms, $studyId, $entityTypeIds) = @_;

  my $attributeCount;

  foreach my $sourceId (keys %$ontologyTerms) {
    my $ontologyTerm = $ontologyTerms->{$sourceId};

    my $hasValues = $ontologyTerm->{_COUNT} > 0 ? 1 : 0;

    my ($dataType, $dataShape, $precision);
    if($hasValues) {
      $precision = 1; # THis is the default; probably never changed
      my $isNumber = $ontologyTerm->{_COUNT} == $ontologyTerm->{_IS_NUMBER_COUNT};
      my $isDate = $ontologyTerm->{_COUNT} == $ontologyTerm->{_IS_DATE_COUNT};
      my $valueCount = scalar(keys(%{$ontologyTerm->{_VALUES}}));
      my $isBoolean = $ontologyTerm->{_COUNT} == $ontologyTerm->{_IS_BOOLEAN_COUNT};

      if($ontologyTerm->{_COUNT} == $ontologyTerm->{_IS_ORDINAL_COUNT}) {
        $dataShape = 'ordinal';
      }
      elsif($isDate || ($isNumber && $valueCount > 10)) {
        $dataShape = 'continuous';
      }
      elsif($valueCount == 2)) {
        $dataShape = 'binary';
      }
      else {
        $dataShape = 'categorical'; 
      }

      if($isDate) {
        $dataType = 'date';
      }
      elsif($isNumber) {
        $dataType = 'number';
      }
      elsif($isBoolean) {
        $dataType = 'boolean';
      }
      else {
        $dataType = 'string';
      }



      foreach my $etId (keys %{$ontologyTerm->{TYPE_IDS}}) {
        my $ptId = $ontologyTerm->{TYPE_IDS}->{$etId};

        my $entityTypeStableId = $entityTypeIds->{$etId};

        my $attribute = GUS::Model::ApiDB::Attribute->new({entity_type_id => $etId,
                                                           entity_type_stable_id => $entityTypeStableId,
                                                           process_type_id => $ptId,
                                                           ontology_term_id => $ontologyTerm->{ONTOLOGY_TERM_ID},
                                                           stable_id => $sourceId,
                                                           data_type => $dataType,
                                                           value_count_per_entity => $valuesCount,
                                                           data_shape => $dataShape,
                                                           unit => $ontologyTerm->{UNIT_NAME},
                                                           unit_ontology_term_id => $ontologyTerm->{UNIT_ONTOLOGY_TERM_ID},
                                                           precision => $precision,
                                                          });



        $attribute->submit();
        $attributeCount++;
      }
    }
  }

  return $attributeCount;
}



sub addUnitsToOntologyTerms {
  my ($self, $studyId, $ontologyTerms) = @_;

  my $dbh = $self->getQueryHandle();

  my $sql = "select  att.source_id, unit.ontology_term_id, unit.name
from apidb.study pg
   , apidb.entitytype vt
   , apidb.attributeunit au
   , sres.ontologyterm att
   , sres.ontologyterm unit
where pg.study_id = ?
and pg.study_id = vt.study_id
and vt.entity_type_id = au.entity_type_id
and au.ATTR_ONTOLOGY_TERM_ID = att.ontology_term_id
and au.UNIT_ONTOLOGY_TERM_ID = unit.ontology_term_id";

  my $sh = $dbh->prepare($sql);
  $sh->execute($studyId);

  while(my ($sourceId, $unitOntologyTermId, $unitName) = $sh->fetchrow_array()) {
    $ontologyTerms->{$sourceId}->{UNIT_ONTOLOGY_TERM_ID} = $unitOntologyTermId;
    $ontologyTerms->{$sourceId}->{UNIT_NAME} = $unitName;
  }

  $sh->finish();
}




sub loadAttributeValues {
  my ($self, $studyId, $ontologyTerms, $maxAttrLength) = @_;

  my $timestamp = int (gettimeofday * 1000);
  my $fifoName = "apidb_attributevalue_${timestamp}.dat";

  my $fields = $self->fields($maxAttrLength);

  my $fifo = $self->makeFifo($fields, $fifoName, $maxAttrLength);
  $self->loadAttributesFromEntity($studyId, $fifo, $ontologyTerms);
  $self->loadAttributesFromIncomingProcess($studyId, $fifo, $ontologyTerms);

  $fifo->cleanup();
  unlink $fifoName;
}

sub loadAttributes {
  my ($self, $studyId, $fifo, $ontologyTerms, $sql) = @_;

  my $dbh = $self->getQueryHandle();

  my $fh = $fifo->getFileHandle();

  my $sh = $dbh->prepare($sql, { ora_auto_lob => 0 } );
  $sh->execute($studyId);

  while(my ($vaId, $vtId, $etId, $lobLocator) = $sh->fetchrow_array()) {
    my $json = $self->readClob($lobLocator);

    my $attsHash = decode_json($json);

    while(my ($ontologySourceId, $valueArray) = each (%$attsHash)) {

      foreach my $value (@$valueArray) {
        my $ontologyTerm = $ontologyTerms->{$ontologySourceId};
        my $ontologyTermId = $ontologyTerm->{ONTOLOGY_TERM_ID};

        $ontologyTerm->{TYPE_IDS}->{$vtId} = $etId;

        unless($ontologyTermId) {
          $self->error("No ontology_term_id found for:  $ontologySourceId");
        }

        my ($dateValue, $numberValue) = $self->ontologyTermValues($ontologyTerm, $value);

        my @a = ($vaId,
                 $vtId,
                 undef,
                 $ontologyTermId,
                 $value,
                 $numberValue,
                 $dateValue
            );

        print $fh join($END_OF_COLUMN_DELIMITER, @a) . $END_OF_RECORD_DELIMITER;
      }
    }
  }
}


sub ontologyTermValues {
  my ($self, $ontologyTerm, $value) = @_;

  my ($dateValue, $numberValue);

  $ontologyTerm->{_VALUES}->{$value}++;

  $ontologyTerm->{_COUNT}++;

  my $valueNoCommas = $value;
  $valueNoCommas =~ tr/,//d;

  if(looks_like_number($valueNoCommas)) {
    $numberValue = $valueNoCommas;
    $ontologyTerm->{_IS_NUMBER_COUNT}++;
  }
  elsif($value =~ /^\d\d\d\d-\d\d-\d\d$/) {
    $dateValue = $value;
    $ontologyTerm->{_IS_DATE_COUNT}++;
  }
  elsif($value =~ /^\d/) {
    $ontologyTerm->{_IS_ORDINAL_COUNT}++;
  }
  else {
    my $lcValue = lc $value;
    if($lcValue eq 'yes' || $lcValue eq 'no' || $lcValue eq 'true' || $lcValue eq 'false') {
      $ontologyTerm->{_IS_BOOLEAN_COUNT}++;
    }
  }


  return $dateValue, $numberValue
}


sub readClob {
  my ($self, $lobLocator) = @_;

  my $dbh = $self->getQueryHandle();

  my $chunkSize = $self->{_lob_locator_size};

  unless($chunkSize) {
    $self->{_lob_locator_size} = $dbh->ora_lob_chunk_size($lobLocator);
    $chunkSize = $self->{_lob_locator_size};
  }

  my $offset = 1;   # Offsets start at 1, not 0

  my $output;

  while(1) {
    my $data = $dbh->ora_lob_read($lobLocator, $offset, $chunkSize );
    last unless length $data;
    $output .= $data;
    $offset += $chunkSize;
  }

  return $output;
}


sub loadAttributesFromEntity {
  my ($self, $studyId, $fifo, $ontologyTerms) = @_;

  my $sql = "select va.entity_attributes_id, va.entity_type_id, null as process_type_id, va.atts from apidb.entityattributes va, apidb.entitytype vt where to_char(va.atts) != '{}' and vt.entity_type_id = va.entity_type_id and vt.study_id = ?";

  $self->loadAttributes($studyId, $fifo, $ontologyTerms, $sql);
}


sub loadAttributesFromIncomingProcess {
  my ($self, $studyId, $fifo, $ontologyTerms) = @_;

  my $sql = "select va.entity_attributes_id, va.entity_type_id, ea.process_type_id, ea.atts
from apidb.processattributes ea
   , apidb.entityattributes va
   , apidb.entitytype vt
where to_char(ea.atts) != '{}'
and vt.entity_type_id = va.entity_type_id
and va.entity_attributes_id = ea.out_entity_id
and vt.study_id = ?
";

  $self->loadAttributes($studyId, $fifo, $ontologyTerms, $sql);
}

sub fields {
  my ($self, $maxAttrLength) = @_;
  my $database = $self->getDb();
  my $projectId = $database->getDefaultProjectId();
  my $userId = $database->getDefaultUserId();
  my $groupId = $database->getDefaultGroupId();
  my $algInvocationId = $database->getDefaultAlgoInvoId();
  my $userRead = $database->getDefaultUserRead();
  my $userWrite = $database->getDefaultUserWrite();
  my $groupRead = $database->getDefaultGroupRead();
  my $groupWrite = $database->getDefaultGroupWrite();
  my $otherRead = $database->getDefaultOtherRead();
  my $otherWrite = $database->getDefaultOtherWrite();

  my ($sec,$min,$hour,$mday,$mon,$year) = localtime();
  my @abbr = qw(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC);
  my $modDate = sprintf('%2d-%s-%02d', $mday, $abbr[$mon], ($year+1900) % 100);

  my $datatypeMap = {'user_read' => " constant $userRead", 
                     'user_write' => " constant $userWrite", 
                     'group_read' => " constant $groupRead", 
                     'group_write' => " constant $groupWrite", 
                     'other_read' => " constant $otherRead", 
                     'other_write' => " constant $otherWrite", 
                     'row_user_id' => " constant $userId", 
                     'row_group_id' => " constant $groupId", 
                     'row_alg_invocation_id' => " constant $algInvocationId",
                     'row_project_id' => " constant $projectId",
                     'modification_date' => " constant \"$modDate\"",
  };


  my $attributeList = ["entity_attributes_id",
                       "entity_type_id",
                       "incoming_process_type_id",
                       "attribute_ontology_term_id",
                       "string_value",
                       "number_value",
                       "date_value",
                       "attribute_value_id",
      ];

  push @$attributeList, keys %$datatypeMap;

  $datatypeMap->{'attribute_value_id'} = " SEQUENCE(MAX,1)";
  $datatypeMap->{'entity_attributes_id'} = " CHAR(12)";
  $datatypeMap->{'entity_type_id'} = "  CHAR(12)";
  $datatypeMap->{'incoming_process_type_id'} = "  CHAR(12)";
  $datatypeMap->{'attribute_ontology_term_id'} = "  CHAR(10)";
  $datatypeMap->{'string_value'} = "  CHAR($maxAttrLength)";
  $datatypeMap->{'number_value'} = "  CHAR($maxAttrLength)";
  $datatypeMap->{'date_value'} = " DATE 'yyyy-mm-dd hh24:mi:ss'";
  
  my @fields = map { lc($_) . $datatypeMap->{lc($_)}  } @$attributeList;

  return \@fields;
}


sub makeFifo {
  my ($self, $fields, $fifoName) = @_;

  my $eorLiteral = $END_OF_RECORD_DELIMITER;
  $eorLiteral =~ s/\n/\\n/;

  my $eocLiteral = $END_OF_COLUMN_DELIMITER;
  $eocLiteral =~ s/\t/\\t/;

  my $database = $self->getDb();
  my $login       = $database->getLogin();
  my $password    = $database->getPassword();
  my $dbiDsn      = $database->getDSN();
  my ($dbi, $type, $db) = split(':', $dbiDsn);

  my $sqlldr = ApiCommonData::Load::Sqlldr->new({_login => $login,
                                                 _password => $password,
                                                 _database => $db,
                                                 _direct => 0,
                                                 _controlFilePrefix => 'sqlldr_AttributeValue',
                                                 _quiet => 1,
                                                 _infile_name => $fifoName,
                                                 _reenable_disabled_constraints => 1,
                                                 _table_name => "ApiDB.AttributeValue",
                                                 _fields => $fields,
                                                 _rows => 100000
                                                });

  $sqlldr->setLineDelimiter($eorLiteral);
  $sqlldr->setFieldDelimiter($eocLiteral);

  $sqlldr->writeConfigFile();

  my $fifo = ApiCommonData::Load::Fifo->new($fifoName);

  my $sqlldrProcessString = $sqlldr->getCommandLine();

  my $pid = $fifo->attachReader($sqlldrProcessString);
  $self->addActiveForkedProcess($pid);

  my $sqlldrInfileFh = $fifo->attachWriter();

  return $fifo;
}

sub error {
  my ($self, $msg) = @_;
  print STDERR "\nERROR: $msg\n";

  foreach my $pid (@{$self->getActiveForkedProcesses()}) {
    kill(9, $pid); 
  }

  $self->SUPER::error($msg);
}


sub undoTables {
  my ($self) = @_;
  return (
    'ApiDB.Attribute',
    'ApiDB.AttributeValue',
      );
}

1;


