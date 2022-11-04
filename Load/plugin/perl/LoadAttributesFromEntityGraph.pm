package ApiCommonData::Load::Plugin::LoadAttributesFromEntityGraph;
# Load attributes into EDA.attribute and EDA.attributevalue
# Warning! Only one instance of this plugin should run at a time
# because values for attribute_value_id are written as SEQUENCE(MAX,1)
#
@ISA = qw(GUS::PluginMgr::Plugin ApiCommonData::Load::Plugin::ParameterizedSchema);
use strict;
use warnings;
use GUS::PluginMgr::Plugin;
use ApiCommonData::Load::Plugin::ParameterizedSchema;

use ApiCommonData::Load::Fifo;
use ApiCommonData::Load::Sqlldr;

use Scalar::Util qw(looks_like_number);

use List::Util qw(min max);
#use Date::Manip qw(ParseDate Date_Cmp);

use File::Temp qw/ tempfile tempdir tmpnam /;

use Time::HiRes qw(gettimeofday);

use ApiCommonData::Load::StudyUtils qw(queryForOntologyTerms getTermsWithDataShapeOrdinal dropTablesLike);

use JSON;
use Encode qw/encode/;

use Data::Dumper;

my $SCHEMA = '__SCHEMA__'; # must be replaced with real schema name

my $END_OF_RECORD_DELIMITER = "#EOR#\n";
my $END_OF_COLUMN_DELIMITER = "#EOC#\t";

my $RANGE_FIELD_WIDTH = 16; # truncate numbers to fit Attribute table: Range_min, Range_max, Bin_width (varchar2(16))

my $TERMS_WITH_DATASHAPE_ORDINAL = {};

my $ALLOW_VOCABULARY_COUNT = 10; # if the number of distinct values is less, generate vocabulary/ordered_values/ordinal_values

my $GEOHASH_PRECISION = ${ApiCommonData::Load::StudyUtils::GEOHASH_PRECISION};

my $purposeBrief = 'Read Study tables and insert tall table for attribute values and attribute table';
my $purpose = $purposeBrief;

my @UNDO_TABLES = qw(
  Attribute
);
my @REQUIRE_TABLES = qw(
  Attribute
);

my $tablesAffected =
    [ ['__SCHEMA__::Attribute', ''],
      ['__SCHEMA__::AttributeValue', '']
    ];

my $tablesDependedOn =
    [['__SCHEMA__::Study',''],
     ['__SCHEMA__::EntityAttributes',  ''],
     ['__SCHEMA__::ProcessAttributes',  ''],
     ['__SCHEMA__::ProcessType',  ''],
     ['__SCHEMA__::EntityType',  ''],
     ['__SCHEMA__::AttributeUnit',  ''],
     ['SRes::OntologyTerm',  ''],
     ['__SCHEMA__::ProcessType',  ''],
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
   stringArg({name           => 'schema',
            descr          => 'GUS::Model schema for entity tables',
            reqd           => 1,
            constraintFunc => undef,
            isList         => 0, }),

   booleanArg({name => 'runRLocally',
          descr => 'if true, will assume Rscript and plot.data are installed locally.  otherwise will call singularity',
          reqd => 1,
          constraintFunc => undef,
          isList => 0,
         }),



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
  $self->{_require_tables} = \@REQUIRE_TABLES;
  $self->{_undo_tables} = \@UNDO_TABLES;
  return $self;
}


$| = 1;

sub run {
  my $self  = shift;

  ## ParameterizedSchema
  $self->requireModelObjects();
  $self->resetUndoTables(); # for when logRowsInserted() is called after loading
  $SCHEMA = $self->getArg('schema');
  ## 

  chdir $self->getArg('logDir');


  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));

  $self->dropTables($extDbRlsId);

  #my $studies = $self->sqlAsDictionary( Sql  => "select study_id, max_attr_length from $SCHEMA.study where external_database_release_id = $extDbRlsId");

  my %studies = ();
  $self->sqlAsHashRefs( Sql  => "select study_id, max_attr_length, internal_abbrev from $SCHEMA.study where external_database_release_id = $extDbRlsId",
                       Code => sub {
                          my $row = shift;
                          $studies{$row->{study_id}}->{max_attr_length} = $row->{max_attr_length};
                          $studies{$row->{study_id}}->{internal_abbrev} = $row->{internal_abbrev};
                          return 1;
                       }
                     );

  $self->error("Expected one study row.  Found ". scalar keys %studies) unless(scalar keys %studies == 1);

  $self->getQueryHandle()->do("alter session set nls_date_format = 'yyyy-mm-dd hh24:mi:ss'") or $self->error($self->getQueryHandle()->errstr);

  my $dbh = $self->getQueryHandle();
  my $ontologyExtDbRlsSpec = $self->getExtDbRlsId($self->getArg('ontologyExtDbRlsSpec'));

  my $studiesCount;

  foreach my $studyId (keys %studies) {


    my $maxAttrLength = $studies{$studyId}->{max_attr_length};
    my $internalAbbrev = $studies{$studyId}->{internal_abbrev};

    $studiesCount++;

    my $entityTypeIds = $self->queryForEntityTypeIds($studyId);

    my $ontologyTerms = &queryForOntologyTerms($dbh, $ontologyExtDbRlsSpec);
    $self->addUnitsToOntologyTerms($studyId, $ontologyTerms, $self->getExtDbRlsId($self->getArg('ontologyExtDbRlsSpec')));
    $self->addScaleToOntologyTerms($ontologyTerms, $self->getExtDbRlsId($self->getArg('ontologyExtDbRlsSpec')));

    $TERMS_WITH_DATASHAPE_ORDINAL = &getTermsWithDataShapeOrdinal($dbh, $ontologyExtDbRlsSpec) ;

    my $tempDirectory = tempdir( CLEANUP => 1 );
    my ($dateValsFh, $dateValsFileName) = tempfile( DIR => $tempDirectory);
    my ($numericValsFh, $numericValsFileName) = tempfile( DIR => $tempDirectory);

    my ($annPropsByAttributeStableIdAndEntityTypeId, $typeCountsByAttributeStableIdAndEntityTypeId) = $self->loadAttributeValues($studyId, $ontologyTerms, $maxAttrLength, $dateValsFh, $numericValsFh, $entityTypeIds, $internalAbbrev);
    my $statsForPlotsByAttributeStableIdAndEntityTypeId = $self->statsForPlots($dateValsFileName, $numericValsFileName, $tempDirectory);
    my $attributeCount = $self->loadAttributeTerms($annPropsByAttributeStableIdAndEntityTypeId, $typeCountsByAttributeStableIdAndEntityTypeId, $statsForPlotsByAttributeStableIdAndEntityTypeId, $entityTypeIds);

    $self->log("Loaded $attributeCount attributes for study id $studyId");
  }

  return 0;
}


sub statsForPlots {
  my ($self, $dateValsFileName, $numericValsFileName, $tempDirectory) = @_;

  my $outputStatsFileName = tmpnam();
  while(-e $outputStatsFileName) {
    $outputStatsFileName = tmpnam();
  }

  my ($rCommandsFh, $rCommandsFileName) = tempfile( DIR => $tempDirectory, UNLINK => 0 );

  print $rCommandsFh $self->rCommandsForStats();

  my $singularity =  "singularity exec docker://veupathdb/rserve";
  if($self->getArg("runRLocally")) {
    $singularity = "";
  }

  printf STDERR ("$singularity Rscript $rCommandsFileName $numericValsFileName $outputStatsFileName\n");
  my $numberSysResult = system("$singularity Rscript $rCommandsFileName $numericValsFileName $outputStatsFileName");
  if($numberSysResult) {
    $self->error("Error Running Rscript for numericFile");
  }

  printf STDERR ("$singularity Rscript $rCommandsFileName $dateValsFileName $outputStatsFileName\n");
  my $dateSysResult = system("$singularity Rscript $rCommandsFileName $dateValsFileName $outputStatsFileName");
  if($dateSysResult) {
    $self->error("Error Running Rscript for datesFile");
  }

  unless (-e $outputStatsFileName){
    $self->log("No stats to load");
    return {};
  }

  my $rv = {};
  open(FILE, "<", $outputStatsFileName) or $self->error("Cannot open $outputStatsFileName for reading: $!");
  
  while(<FILE>) {
    chomp;
    my ($attributeSourceId, $entityTypeId, $min, $max, $binWidth, $mean, $median, $lower_quartile, $upper_quartile) = split(/\t/, $_);
    # Handle cases where bin_width = 0 because distinct_values_count = 1
    # For number types only (dates are handled correctly by plot.data)
    if(($min eq $max) && looks_like_number($binWidth) && $binWidth == 0){
      $binWidth = 1;
    }

    $rv->{$attributeSourceId}->{$entityTypeId} =  {range_min => $self->truncateSummaryStat($min),
                                                   range_max => $self->truncateSummaryStat($max),
                                                   bin_width => $self->truncateSummaryStat($binWidth),
                                                   mean => $self->truncateSummaryStat($mean),
                                                   median => $self->truncateSummaryStat($median),
                                                   lower_quartile => $self->truncateSummaryStat($lower_quartile),
                                                   upper_quartile => $self->truncateSummaryStat($upper_quartile),
    };
  }
  close FILE;
  unlink $outputStatsFileName;

  return $rv;
}

sub truncateSummaryStat {
  my ($self,$val) = @_;
  return $val unless(looks_like_number($val) && $val !~ /^(inf|nan)$/);
  my $type = "integer";
  if(length($val) > $RANGE_FIELD_WIDTH){
    # trim scientific notation, which should always be in the format
    if($val =~ /^([-+]?\d*)\.\d+(e[-+]?\d+)$/){ 
      $type = "exponent";
      # sprintf will always handle irregular notation e.g. 101.3e-12 => 1.013e-10
      my $width = $RANGE_FIELD_WIDTH - (length($1 . $2) + 1);
      $val = sprintf("%.${width}e", $val);
    }
    elsif($val =~ /^([-+]?\d+)\.\d+$/){  # floating point, no exponent
      $type = "floating point";
      my $width = $RANGE_FIELD_WIDTH - (length($1) + 1);
      $val = sprintf("%.${width}f", $val);
    }
    else { # really big number should be in notation anyway
      $type = "long int";
      my $width = $RANGE_FIELD_WIDTH - 6; # should be short enough allowing for negative, decimal, and exp up to 2 digits
      $val = sprintf("%.$width", $val);
    }
    if(length($val) > $RANGE_FIELD_WIDTH ){
      $self->error("Your math is off! $val is still too long; fix the calculation where \$type=$type");
    }
  }
  return $val;
}

sub rCommandsForStats {
  my $R_script = <<'RSCRIPT';
args = commandArgs(trailingOnly = TRUE);
fileName = args[1];
if( file.info(fileName)$size == 0 ){
  write("No data for stats", stderr())
  quit('no')
}
outputFileName = args[2];
t = read.table(fileName, header=FALSE, sep="\t");
isDate = 0;
if(!is.character(t$V2)) {
  t$V2 = as.character(t$V2);
}
if(is.character(t$V3)) {
  t$V3 = as.Date(t$V3);
  isDate = 1;
}
u = unique(t[,1:2]);
subsetFxn = function(x, output){
   v = subset(t, V1==x[1] & V2==x[2])$V3
   data.min = min(v);
   data.max = max(v);
   data.mean = mean(v);
   data.median = median(v);
   data.binWidth = plot.data::findBinWidth(v);
  
   if(data.min != data.max) {
     if(isDate) {
       stats = as.Date(stats::fivenum(as.numeric(v)), origin = "1970-01-01");
       data.lower_quartile = stats[2];
       data.upper_quartile = stats[4];
     }
     else {
       stats = stats::fivenum(v); # min, lower hinge, median, upper hinge, max
       data.lower_quartile = stats[2];
       data.upper_quartile = stats[4];
     }
   }
   else {
     data.lower_quartile = "";
     data.upper_quartile = "";
   }
   if(is.null(data.binWidth)) { data.binWidth = "" }
   data.output = c(x, as.character(data.min), as.character(data.max), as.character(data.binWidth), as.character(data.mean), as.character(data.median), as.character(data.lower_quartile), as.character(data.upper_quartile));
   write(data.output, file=outputFileName, append=T, ncolumns=16, sep="\t")
};
apply(u, 1, subsetFxn);
quit('no')
RSCRIPT
return $R_script;
}


sub queryForEntityTypeIds {
  my ($self, $studyId) = @_;

  my %rv;

  my $dbh = $self->getQueryHandle();

  my $sql = "select t.name, t.entity_type_id, ot.source_id, t.internal_abbrev
from $SCHEMA.entitytype t, sres.ontologyterm ot
where t.type_id = ot.ontology_term_id (+)
and study_id = $studyId";

  my $sh = $dbh->prepare($sql);
  $sh->execute();

  while(my ($etName, $etId, $stableId, $internalAbbrev) = $sh->fetchrow_array()) {
    warn "No ontology term for entity type $etName" unless $stableId;
    $rv{$etId}->{STABLE_ID} = $stableId;
    $rv{$etId}->{NAME} = $etName;
    $rv{$etId}->{INTERNAL_ABBREV} = $internalAbbrev
  }
  $sh->finish();

  return \%rv;
}
sub annPropsFromParentOntologyTerm {
  my ($displayName, $parentOntologyTerm, $processTypeId, $isMultiValued) = @_;
  return {
    ontology_term_id => undef,
    parent_ontology_term_id => $parentOntologyTerm->{ONTOLOGY_TERM_ID},
    unit => $parentOntologyTerm->{UNIT_NAME},
    unit_ontology_term_id => $parentOntologyTerm->{UNIT_ONTOLOGY_TERM_ID},
    scale => $parentOntologyTerm->{SCALE},
    display_name => $displayName,
    process_type_id => $processTypeId,
    is_multi_valued => $isMultiValued,
  };
}
sub annPropsFromOntologyTerm {
  my ($ontologyTerm, $processTypeId, $isMultiValued) = @_;
  return {
    ontology_term_id => $ontologyTerm->{ONTOLOGY_TERM_ID},
    parent_ontology_term_id => $ontologyTerm->{PARENT_ONTOLOGY_TERM_ID},
    unit => $ontologyTerm->{UNIT_NAME},
    unit_ontology_term_id => $ontologyTerm->{UNIT_ONTOLOGY_TERM_ID},
    scale => $ontologyTerm->{SCALE},
    display_name => $ontologyTerm->{DISPLAY_NAME},
    process_type_id => $processTypeId,
    is_multi_valued => $isMultiValued,
  };
}

sub loadAttributeTerms {
  my ($self, $annPropsByAttributeStableIdAndEntityTypeId, $typeCountsByAttributeStableIdAndEntityTypeId, $statsForPlotsByAttributeStableIdAndEntityTypeId, $entityTypeIds) = @_;

  my $attributeCount;
  $self->getDb->setMaximumNumberOfObjects((scalar keys %$annPropsByAttributeStableIdAndEntityTypeId ) * (scalar keys %$entityTypeIds));
  SOURCE_ID:
  foreach my $attributeStableId (keys %$annPropsByAttributeStableIdAndEntityTypeId) {

    foreach my $etId (keys %{$annPropsByAttributeStableIdAndEntityTypeId->{$attributeStableId}}) {
      my $annProps = $annPropsByAttributeStableIdAndEntityTypeId->{$attributeStableId}{$etId};

      my $valProps = valProps($typeCountsByAttributeStableIdAndEntityTypeId->{$attributeStableId}{$etId}, $attributeStableId);

      my $statProps = $statsForPlotsByAttributeStableIdAndEntityTypeId->{$attributeStableId}->{$etId};
      $statProps = {} unless($statProps);

      next SOURCE_ID unless $valProps;


      # Danielle: A syntactically valid name
      #   consists of letters, numbers and the dot or underline characters
      #   and starts with a letter or the dot not followed by a number
      $self->error("Bad attribute stable ID: $attributeStableId")
        unless $attributeStableId =~ m{^(.[A-za-z][A-za-z_.0-9]*|[A-za-z][A-za-z_.0-9]*)$};

      my $attribute = $self->getGusModelClass('Attribute')->new({entity_type_id => $etId,
                                                         entity_type_stable_id => $entityTypeIds->{$etId}->{STABLE_ID},
                                                         stable_id => $attributeStableId,
                                                         %$annProps,
                                                         %$valProps,
                                                         range_min => $statProps->{range_min},
                                                         range_max => $statProps->{range_max},
                                                         bin_width => $statProps->{bin_width},
                                                         mean      => $statProps->{mean},
                                                         median    => $statProps->{median},
                                                         lower_quartile => $statProps->{lower_quartile},
                                                         upper_quartile => $statProps->{upper_quartile},
                                                       });




      $attribute->submit();
      $attributeCount++;
    }
  }
  $self->undefPointerCache;

  return $attributeCount;
}

sub valProps {
  my ($typeCounts, $attributeStableId) = @_;
  return unless $typeCounts;
  my %cs = %{$typeCounts};
  return unless $cs{_COUNT};

  my ($dataType, $dataShape);
  my $precision = $cs{_PRECISION};
  my $isNumber = $cs{_IS_NUMBER_COUNT} && $cs{_COUNT} == $cs{_IS_NUMBER_COUNT};
  my $isDate = $cs{_IS_DATE_COUNT} && $cs{_COUNT} == $cs{_IS_DATE_COUNT};
  my $valueCount = scalar(keys(%{$cs{_VALUES}}));
#  my $isBoolean = $cs{_COUNT} == $cs{_IS_BOOLEAN_COUNT};

#  my $isMultiValued = $cs{_IS_MULTI_VALUED};

  if($TERMS_WITH_DATASHAPE_ORDINAL->{$attributeStableId}){
    $dataShape = 'ordinal';
  }
# DEPRECATED - never infer shape = ordinal
# elsif($cs{_IS_ORDINAL_COUNT} && $cs{_COUNT} == $cs{_IS_ORDINAL_COUNT}) {
#   $dataShape = 'ordinal';
# }
  elsif($isDate || $isNumber ){
    $dataShape = 'continuous';
  }
  elsif($valueCount == 2) {
    $dataShape = 'binary';
  }
  else {
    ## TODO do not set if min or max is set
    $dataShape = 'categorical'; 
  }

  my $orderedValues;
  if($dataShape ne 'continuous' || $valueCount <= $ALLOW_VOCABULARY_COUNT) {
    my @values = sort { if(looks_like_number($a) && looks_like_number($b)){ $a <=> $b } else { lc($a) cmp lc($b)} } keys(%{$cs{_VALUES}});
    $orderedValues = encode_json(\@values);
  }

  # OBI term here is for longitude
  if($attributeStableId eq 'OBI_0001621') {
    $dataType = 'longitude';
  }
  elsif($isDate) {
    $dataType = 'date';
  }
  elsif($isNumber && ($precision > 0)) {
    $dataType = 'number';
  }
  elsif($isNumber && ($precision == 0)) {
    $dataType = 'integer';
  }
#  elsif($isBoolean) {
#    $dataType = 'boolean';
#  }
  else {
    $dataType = 'string';
  }
  if(defined ( $GEOHASH_PRECISION->{$attributeStableId} )){
    $precision = $GEOHASH_PRECISION->{$attributeStableId};
  }
  return {
    data_type => $dataType,
    distinct_values_count => $valueCount,
#    is_multi_valued => $isMultiValued ? 1 : 0,
    data_shape => $dataShape,
    precision => $precision,
    ordered_values => $orderedValues,
  };
}


sub addUnitsToOntologyTerms {
  my ($self, $studyId, $ontologyTerms, $ontologyExtDbRlsId) = @_;

  my $dbh = $self->getQueryHandle();

  my $sql = "select * from (
select  att.source_id, unit.ontology_term_id, unit.name, 2 as priority
from $SCHEMA.study pg
   , $SCHEMA.entitytype vt
   , $SCHEMA.attributeunit au
   , sres.ontologyterm att
   , sres.ontologyterm unit
where pg.study_id = ?
and pg.study_id = vt.study_id
and vt.entity_type_id = au.entity_type_id
and au.ATTR_ONTOLOGY_TERM_ID = att.ontology_term_id
and au.UNIT_ONTOLOGY_TERM_ID = unit.ontology_term_id
UNION
select ot.source_id
     , uot.ontology_term_id
     , json_value(annotation_properties, '\$.unitLabel[0]') label
     , 1 as priority
from sres.ontologysynonym os
   , sres.ontologyterm ot
   , sres.ontologyterm uot
where os.ontology_term_id = ot.ontology_term_id
and json_value(annotation_properties, '\$.unitIRI[0]') = uot.uri
and json_value(annotation_properties, '\$.unitLabel[0]') is not null
and os.external_database_release_id = ?
) order by priority
";

  my $sh = $dbh->prepare($sql);
  $sh->execute($studyId, $ontologyExtDbRlsId);

  while(my ($sourceId, $unitOntologyTermId, $unitName) = $sh->fetchrow_array()) {
    if($ontologyTerms->{$sourceId}->{UNIT_ONTOLOGY_TERM_ID}) {
      # TODO:  Shouldn't we allow one unit per attribute/entityType?
      $self->userError("The Attribute $sourceId can only have one unit specification per study.  Units can be specified either in the ISA files OR in annotation properties");
    }

    $ontologyTerms->{$sourceId}->{UNIT_ONTOLOGY_TERM_ID} = $unitOntologyTermId;
    $ontologyTerms->{$sourceId}->{UNIT_NAME} = $unitName;
  }

  $sh->finish();
}


sub addScaleToOntologyTerms {
  my ($self, $ontologyTerms, $ontologyExtDbRlsId) = @_;

  my $dbh = $self->getQueryHandle();

  my $sql = "
select ot.source_id
     , json_value(annotation_properties, '\$.scale[0]') scale
from sres.ontologysynonym os
   , sres.ontologyterm ot
where os.ontology_term_id = ot.ontology_term_id
and json_value(annotation_properties, '\$.scale[0]') is not null
and os.external_database_release_id = ?
";

  my $sh = $dbh->prepare($sql);
  $sh->execute($ontologyExtDbRlsId);

  while(my ($sourceId, $scale) = $sh->fetchrow_array()) {
    if($ontologyTerms->{$sourceId}->{SCALE}) {
      $self->userError("The Attribute $sourceId can only have one SCALE specification per study.  Units can be specified either in the ISA files OR in annotation properties");
    }

    $ontologyTerms->{$sourceId}->{SCALE} = $scale;
  }

  $sh->finish();
}



sub makeFifosForSqlloader {
  my ($self, $entityTypeIds, $maxAttrLength, $studyInternalAbbrev) = @_;

  my $entityTypeIdFifos;

  foreach my $entityTypeId (keys %$entityTypeIds) {
    my $internalAbbrev = $entityTypeIds->{$entityTypeId}->{INTERNAL_ABBREV};

    my $timestamp = int (gettimeofday * 1000);
    my $fifoName = "${SCHEMA}_attributevalue_${internalAbbrev}_${timestamp}.dat";

    my $fields = $self->fieldsAndCreateTable($maxAttrLength, $internalAbbrev, $studyInternalAbbrev, $entityTypeId);
    my $fifo = $self->makeFifo($fields, $fifoName, $internalAbbrev, $studyInternalAbbrev);

    $entityTypeIdFifos->{$entityTypeId} = $fifo;
  }

  return $entityTypeIdFifos;
}


sub loadAttributeValues {
  my ($self, $studyId, $ontologyTerms, $maxAttrLength, $dateValsFh, $numericValsFh, $entityTypeIds, $studyInternalAbbrev) = @_;

  my $fifos = $self->makeFifosForSqlloader($entityTypeIds, $maxAttrLength, $studyInternalAbbrev);

  my $annPropsByAttributeStableIdAndEntityTypeId = {};
  my $typeCountsByAttributeStableIdAndEntityTypeId = {};
  $self->loadAttributesFromEntity($studyId, $fifos, $ontologyTerms, $annPropsByAttributeStableIdAndEntityTypeId, $typeCountsByAttributeStableIdAndEntityTypeId, $dateValsFh, $numericValsFh);
  $self->loadAttributesFromIncomingProcess($studyId, $fifos, $ontologyTerms, $annPropsByAttributeStableIdAndEntityTypeId, $typeCountsByAttributeStableIdAndEntityTypeId, $dateValsFh, $numericValsFh);

  foreach my $etId (keys %$fifos) {
    my $fifo = $fifos->{$etId};
    $fifo->cleanup();
  }

  return $annPropsByAttributeStableIdAndEntityTypeId, $typeCountsByAttributeStableIdAndEntityTypeId;
}

sub loadAttributes {
  my ($self, $studyId, $fifos, $ontologyTerms, $annPropsByAttributeStableIdAndEntityTypeId, $typeCountsByAttributeStableIdAndEntityTypeId, $dateValsFh, $numericValsFh, $sql) = @_;
  # Try to force printing only 8-bit characters
  binmode( $dateValsFh, ":utf8" );
  binmode( $numericValsFh, ":utf8" );

  my $dbh = $self->getQueryHandle();



  #$self->log("Loading attribute values for study $studyId from sql:".$sql);
  my $sh = $dbh->prepare($sql, { ora_auto_lob => 0 } );
  $sh->execute($studyId);

  my $clobCount = 0;

  while(my ($entityAttributesId, $entityStableId, $entityTypeId, $entityTypeIdOrig, $entityTypeOntologyTermId, $processTypeId, $processTypeOntologyTermId, $lobLocator) = $sh->fetchrow_array()) {
    my $json = encode('UTF-8', $self->readClob($lobLocator));

    my $attsHash = decode_json($json);

    while(my ($ontologySourceId, $valueArray) = each (%$attsHash)) {

      my $unitOntologyTermId = $ontologyTerms->{$ontologySourceId}->{UNIT_ONTOLOGY_TERM_ID};

      for my $p ($self->annPropsAndValues($ontologyTerms, $ontologySourceId, $processTypeId, $valueArray)){
        $processTypeId //= "";
        my ($attributeStableId, $annProps, $value) = @{$p};
        $annPropsByAttributeStableIdAndEntityTypeId->{$attributeStableId}{$entityTypeId} //= $annProps;
#######
        if($annProps->{is_multi_valued} && !($annPropsByAttributeStableIdAndEntityTypeId->{$attributeStableId}{$entityTypeId}{is_multi_valued})){
          $annPropsByAttributeStableIdAndEntityTypeId->{$attributeStableId}{$entityTypeId}{is_multi_valued} = 1;
#          printf STDERR ("DEBUG: IS_MULTI_VALUED UPDATED!!! %s\n", $attributeStableId);
        }
######

        # get original unit;  options are skipPrint,die if units are different, printRow
        my $unitOntologytermIdOrig;
        # if this row has units, lookup orig unit;  Handle mismatch or die
        if($unitOntologyTermId) {
          $unitOntologytermIdOrig = $self->lookupUnit($entityTypeIdOrig, $attributeStableId);

          if(!$unitOntologytermIdOrig || $unitOntologytermIdOrig != $unitOntologyTermId) {
            my ($convertedValue) = $self->convertValue($value, $unitOntologytermIdOrig, $unitOntologyTermId);
            $value = $convertedValue;
          }
        }


        my $cs = $typeCountsByAttributeStableIdAndEntityTypeId->{$attributeStableId}{$entityTypeId} // {};
        my ($updatedCs, $stringValue, $numberValue, $dateValue) = $self->typedValueForAttribute($attributeStableId, $cs, $value);
        $typeCountsByAttributeStableIdAndEntityTypeId->{$attributeStableId}{$entityTypeId} = $updatedCs;

        if($dateValue) {
          print $dateValsFh join("\t", $attributeStableId, $entityTypeId, $dateValue) . "\n";
        }
        elsif(defined($numberValue)) { # avoid if( 0 ) evaluating to false
          print $numericValsFh join("\t", $attributeStableId, $entityTypeId, $numberValue) . "\n";
        }
        else {}

        my @a = ($entityStableId,
                 $attributeStableId,
                 $stringValue,
                 $numberValue,
                 $dateValue
            );


        my $fh = $fifos->{$entityTypeId}->getFileHandle();
        binmode( $fh, ":utf8" );
        $self->printToFifo(\@a, $fh);

      }
      $self->undefPointerCache();
    }
    if(++$clobCount % 500 == 0){
      $self->log("Loading attribute values for study $studyId: processed $clobCount clobs");
    }
  }
  $self->log("Loaded attribute values for study $studyId: processed $clobCount clobs");
}


sub convertValue {
  my ($self, $value, $unitIdOrig, $unitIdDesired) = @_;

  $self->error("Unit Mismatch Not yet supported.  VALUE $value found in units [$unitIdOrig] but desired [$unitIdDesired]");

  my $newValue; #TODO
  return $newValue;
}


sub lookupUnit {
  my ($self, $entityTypeId, $attributeStableId) = @_;

  if($self->{_unit_map}->{$attributeStableId}->{$entityTypeId}) {
    return $self->{_unit_map}->{$attributeStableId}->{$entityTypeId};
  }

  my $sql = "select ot.source_id, au.unit_ontology_term_id
from SRES.ONTOLOGYTERM ot, ${SCHEMA}.attributeunit au
where au.ATTR_ONTOLOGY_TERM_ID = ot.ONTOLOGY_TERM_ID
and au.entity_type_id = ?";

  my $dbh = $self->getQueryHandle();
  my $sh = $dbh->prepare($sql);
  $sh->execute($entityTypeId);

  while(my ($sourceId, $unitId) = $sh->fetchrow_array()) {
    $self->{_unit_map}->{$sourceId}->{$entityTypeId} = $unitId;
  }

  return $self->{_unit_map}->{$attributeStableId}->{$entityTypeId};
}


sub printToFifo {
  my ($self, $a, $fh) = @_;

  print $fh join($END_OF_COLUMN_DELIMITER, map {$_ // ""} @$a) . $END_OF_RECORD_DELIMITER;
}

sub annPropsAndValues {
  my ($self, $ontologyTerms, $ontologySourceId, $processTypeId, $valueArray) = @_;
  my $ontologyTerm = $ontologyTerms->{$ontologySourceId};
  unless($ontologyTerm) {
    $self->error("No ontology term found for:  $ontologySourceId");
  }
  my $isMultiValued = (scalar(@{$valueArray//[]}) > 1);
  my @result;

  VALUE:
  for my $value (@{$valueArray//[]}){
    if (ref $value eq 'HASH'){
      # MBio results
      for my $k (keys %{$value}){
        my ($displayName, $subvalue);
        my $o = $value->{$k};
        if (ref $o eq 'ARRAY'){
          $displayName = $o->[0];
          $subvalue = $o->[1];
        } else {
           $displayName = $ontologyTerm->{DISPLAY_NAME}. ": $k";
           $subvalue = $o;
        }
        push @result, ["${ontologySourceId}_$k", annPropsFromParentOntologyTerm($displayName, $ontologyTerm, $processTypeId, $isMultiValued), $subvalue];
      }
    } else {
      push @result, [$ontologySourceId, annPropsFromOntologyTerm($ontologyTerm, $processTypeId, $isMultiValued), $value];
    }
  }
  return @result;
}

sub typedValueForAttribute {
  my ($self, $attributeStableId, $counts, $value) = @_;

  my ($stringValue, $numberValue, $dateValue); 

  $counts->{_COUNT}++;

  my $valueNoCommas = $value;
  $valueNoCommas =~ tr/,//d;

  $counts->{_VALUES}->{$value}++;

  #####################################################
  ## Abort if annotation property forceStringType = yes
  ## which is loaded into SRes.OntologySynonym.Annotation_Properties
  ## by the step _updateOntologySynonym_owlAttributes
  if($TERMS_WITH_DATASHAPE_ORDINAL->{$attributeStableId}){
    $stringValue = $value; # unless(defined($dateValue) || defined($numberValue));
    return $counts, $stringValue, $numberValue, $dateValue;
  }
  #####################################################

  if(looks_like_number($valueNoCommas) && lc($valueNoCommas) ne "nan" && lc($valueNoCommas) ne "inf") {
    # looks_like_number() considers these numbers: nan=not a number, inf=infinity 
    $numberValue = $valueNoCommas;
    $counts->{_IS_NUMBER_COUNT}++;
    
    my $precision = length(($value =~ /\.(\d+)/)[0]) || 0;
    $counts->{_PRECISION} ||= 0;
    $counts->{_PRECISION} = max($counts->{_PRECISION}, $precision);#if $counts->{_PRECISION};
  }
  elsif($value =~ /^\d\d\d\d-\d\d-\d\d$/) {
    $dateValue = $value;
    $counts->{_IS_DATE_COUNT}++;

    # my $parsedDate = ParseDate($dateValue);
    # $counts->{_MIN_DATE} = (sort { Date_Cmp($b, $a) } ($counts->{_MIN_DATE} || $parsedDate, $parsedDate))[-1];
    # $counts->{_MAX_DATE} = (sort { Date_Cmp($a, $b) } ($counts->{_MAX_DATE} || $parsedDate, $parsedDate))[-1];
  }
  elsif($value =~ /^\d/) {
    $counts->{_IS_ORDINAL_COUNT}++;
  }
  else {
#    my $lcValue = lc $value;
#    if($lcValue eq 'yes' || $lcValue eq 'no' || $lcValue eq 'true' || $lcValue eq 'false') {
#      $counts->{_IS_BOOLEAN_COUNT}++;
#    }
  }

	# Always load string_value (see https://github.com/VEuPathDB/EdaLoadingIssues/issues/1)
  $stringValue = $value; # unless(defined($dateValue) || defined($numberValue));

  return $counts, $stringValue, $numberValue, $dateValue;
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
  loadAttributes(@_, "
select ea.entity_attributes_id
     , ea.stable_id
     , et.entity_type_id
     , ea.entity_type_id as orig_entity_type_id
     , et.type_id as entity_type_ontology_term_id
     , null as process_type_id
     , null as process_type_ontology_term_id
     , ea.atts
from $SCHEMA.entityattributes ea
   , $SCHEMA.entityclassification ec
   , $SCHEMA.entitytype et
where ea.atts is not null
and et.entity_type_id = ec.entity_type_id
and ec.entity_attributes_id = ea.entity_attributes_id
and et.study_id = ?
");
}


sub loadAttributesFromIncomingProcess {
  loadAttributes(@_, "
select ea.entity_attributes_id
     , ea.stable_id
     , et.entity_type_id
     , ea.entity_type_id as orig_entity_type_id
     , et.type_id as entity_type_ontology_term_id
     , pt.process_type_id
     , pt.type_id as process_type_ontology_term_id
     , pa.atts
from $SCHEMA.processattributes pa
   , $SCHEMA.entitytype et
   , $SCHEMA.entityclassification ec
   , $SCHEMA.entityattributes ea
   , $SCHEMA.processtype pt
where pa.atts is not null
and et.entity_type_id = ec.entity_type_id
and ec.entity_attributes_id = pa.out_entity_id
and ec.entity_attributes_id = ea.entity_attributes_id
and pa.process_type_id = pt.process_type_id
and et.study_id = ?
");
}

sub fieldsAndCreateTable {
  my ($self, $maxAttrLength, $internalAbbrev, $studyInternalAbbrev, $entityTypeId) = @_;
  $maxAttrLength += $maxAttrLength; # Workaround to prevent Sqlldr from choking on wide characters
  my $datatypeMap = {};

  my $idField = lc($internalAbbrev) . "_stable_id";

  my $attributeList = [$idField,
                       "attribute_stable_id",
                       "string_value",
                       "number_value",
                       "date_value"
      ];

  $datatypeMap->{$idField} = " CHAR(200)";
  $datatypeMap->{'attribute_stable_id'} = "  CHAR(255)";
  $datatypeMap->{'string_value'} = "  CHAR($maxAttrLength)";
  $datatypeMap->{'number_value'} = "  CHAR($maxAttrLength)";
  $datatypeMap->{'date_value'} = " DATE 'yyyy-mm-dd hh24:mi:ss'";

  my @fields = map { lc($_) . $datatypeMap->{lc($_)}  } @$attributeList;

  my $tableName = "${SCHEMA}.AttributeValue_${studyInternalAbbrev}_${internalAbbrev}";

  my $createTableSql = "create table $tableName (
$idField VARCHAR2(200) NOT NULL,
attribute_stable_id  VARCHAR2(255) NOT NULL,
string_value VARCHAR2(1000) NOT NULL,
number_value NUMBER,
date_value DATE
)
";

  my $dbh = $self->getDbHandle();

  $dbh->do($createTableSql) or die $dbh->errstr;

  $dbh->do("CREATE INDEX attrval_${entityTypeId}_1_ix ON $tableName (attribute_stable_id, ${internalAbbrev}_stable_id) TABLESPACE indx") or die $dbh->errstr;

  $dbh->do("CREATE INDEX attrval_${entityTypeId}_2_ix ON $tableName (attribute_stable_id, string_value, ${internalAbbrev}_stable_id) TABLESPACE indx") or die $dbh->errstr;
  $dbh->do("CREATE INDEX attrval_${entityTypeId}_3_ix ON $tableName (attribute_stable_id, date_value, ${internalAbbrev}_stable_id) TABLESPACE indx") or die $dbh->errstr;
  $dbh->do("CREATE INDEX attrval_${entityTypeId}_4_ix ON $tableName (attribute_stable_id, number_value, ${internalAbbrev}_stable_id) TABLESPACE indx") or die $dbh->errstr;

  $dbh->do("GRANT SELECT ON $tableName TO gus_r");

  return \@fields;
}


sub makeFifo {
  my ($self, $fields, $fifoName, $entityTypeAbbrev, $studyInternalAbbrev) = @_;

  my $eorLiteral = $END_OF_RECORD_DELIMITER;
  $eorLiteral =~ s/\n/\\n/;

  my $eocLiteral = $END_OF_COLUMN_DELIMITER;
  $eocLiteral =~ s/\t/\\t/;

  my $database = $self->getDb();
  my $login       = $database->getLogin();
  my $password    = $database->getPassword();
  my $dbiDsn      = $database->getDSN();
  my ($dbi, $type, $db) = split(':', $dbiDsn, 3);

  my $sqlldr = ApiCommonData::Load::Sqlldr->new({_login => $login,
                                                 _password => $password,
                                                 _database => $db,
                                                 _direct => 1,
                                                 _controlFilePrefix => 'sqlldr_AttributeValue',
                                                 _quiet => 0,
                                                 _append => 0,
                                                 _infile_name => $fifoName,
                                                 _reenable_disabled_constraints => 1,
                                                 _table_name => "$SCHEMA.AttributeValue_${studyInternalAbbrev}_${entityTypeAbbrev}",
                                                 _fields => $fields
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

sub dropTables {
  my ($self, $extDbRlsId) = @_;

  my $dbh = $self->getDbHandle();
#  my ($dbName, $dbVersion) = $extDbRlsSpec =~ /(.+)\|(.+)/;

  my $sql = "select distinct s.internal_abbrev from ${SCHEMA}.study s where s.external_database_release_id = $extDbRlsId";
  $self->log("Looking for tables belonging to this study :\n$sql");
  my $sh = $dbh->prepare($sql);
  $sh->execute();

  while(my ($s) = $sh->fetchrow_array()) {
    &dropTablesLike(${SCHEMA}, "ATTRIBUTEVALUE_${s}", $dbh);
  }
  $sh->finish();
}

1;
