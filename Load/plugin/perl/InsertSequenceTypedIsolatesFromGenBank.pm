package ApiCommonData::Load::Plugin::InsertSequenceTypedIsolatesFromGenBank;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;

use lib "$ENV{GUS_HOME}/lib/perl";
use Bio::SeqIO;
use GUS::PluginMgr::Plugin;
use GUS::Model::DoTS::ExternalNASequence;
use GUS::Model::Results::SegmentResult;
use GUS::Model::Study::Study;
use GUS::Model::Study::StudyLink;
use GUS::Model::Study::StudyBibRef;
use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::Study::Characteristic;
use GUS::Model::SRes::Taxon;
use GUS::Model::SRes::OntologyTerm;
use GUS::Model::SRes::BibliographicReference;
use Data::Dumper;

use lib "$ENV{GUS_HOME}/lib/perl/ApiCommonWebsite/Model";
use pcbiPubmed;

my $purposeBrief = <<PURPOSEBRIEF;
Insert GenBank Isolate data from a genbank file (.gbk). 
PURPOSEBRIEF

my $purpose = <<PURPOSE;
Insert GenBank Isolate data from a genbank file (.gbk). 
PURPOSE

my $tablesAffected = [
  ['Results.SegmentResult', 'One row or more per isolate - mRNA, rRNA, gene'],
  ['Study.Study',           'One row per inserted study, one study could have multiple isolates'],
  ['Study.ProtocolAppNode', 'One row per inserted isolate'],
  ['Study.Characteristic',  'One row or more per inserted isolate - metadata, e.g. country, strin, genotype...'],
  ['Study.StudyLink',       'Link Study.Study with Study.ProtocolAppNode - one study could have multiple isolates'],
  ['Study.StudyBibRef',     'Link Study.Study with SRes.BibliographicReference - one study could have multiple references'],
  ['SRes.OntologyTerm',     'Store GenBank source modifiers'],
  ['SRes.BibliographicReference', 'Store GenBank source modifiers'],
  ['DoTS.ExternalNASequence',     'One row inserted per isolate .ProtocolAppNode row'] 
];

my $tablesDependedOn = [
  ['SRes.OntologyTerm', 'Get the ontology_term_id for each metadata']
];

my $howToRestart = "There is currently no restart method.";

my $failureCases = "There are no know failure cases.";

my $notes = <<PLUGIN_NOTES;
Input File is a typical GenBank file, e.g. GenBank accession AF527841
#MetaData  is inside the /source block, e.g. strain, genotype, country, clone, lat-lon...
PLUGIN_NOTES

my $documentation = { purpose          => $purpose,
                      purposeBrief     => $purposeBrief,
                      tablesAffected   => $tablesAffected,
                      tablesDependedOn => $tablesDependedOn,
                      howToRestart     => $howToRestart,
                      failureCases     => $failureCases,
                      notes            => $notes
                    };

my $argsDeclaration = 
  [
    stringArg({name           => 'extDbName',
               descr          => 'the external database name to tag the data with.',
               reqd           => 1,
               constraintFunc => undef,
               isList         => 0,
             }),
    stringArg({name           => 'extDbRlsVer',
               descr          => 'the version of the external database to tag the data with.',
               reqd           => 1,
               constraintFunc => undef,
               isList         => 0,
             }),
    fileArg({  name           => 'inputFile',
               descr          => 'file containing the data',
               constraintFunc => undef,
               reqd           => 1,
               mustExist      => 1,
               isList         => 0,
               format         =>'Tab-delimited.'
             }), 
   ];

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class); 

  $self->initialize({ requiredDbVersion => 4.0,
                      cvsRevision => '$Revision$', # cvs fills this in!
                      name => ref($self),
                      argsDeclaration => $argsDeclaration,
                      documentation => $documentation
                   });
  return $self;
}

sub run {

  my ($self) = @_;
  my $dbiDb = $self->getDb();
  $dbiDb->setMaximumNumberOfObjects(1000000);

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbName'), $self->getArg('extDbRlsVer'));
  my $inputFile = $self->getArg('inputFile');

  my ($studyHash, $nodeHash, $termHash) = $self->readGenBankFile($inputFile, $extDbRlsId);

  $self->makeOntologyTerm($termHash, $extDbRlsId);

  my $count = $self->loadIsolates($studyHash, $nodeHash);

  my $msg = "$count isolate records have been loaded.";
  $self->log("$msg \n");
  return $msg;
}

sub readGenBankFile {

  my ($self, $inputFile, $extDbRlsId) = @_;

  my %studyHash; # study name => { ids => @ids; pmid => pmid }
  my %termHash;  # list of distinct source modifiers
  my %nodeHash;  # isolate => { desc => desc; seq => seq; terms => { key => value } }

  my $seq_io = Bio::SeqIO->new(-file => $inputFile);

  while(my $seq = $seq_io->next_seq) {

    my $source_id = $seq->accession_number;
    my $desc = $seq->desc;

    $nodeHash{$source_id}{desc} = $desc;
    $nodeHash{$source_id}{seq}  = $seq->seq;

    # process source modifiers, store distince terms as a list
    for my $feat ($seq->get_SeqFeatures) {    
      my $primary_tag = $feat->primary_tag;
      if($primary_tag =~ /source/i || $primary_tag =~ /rna/i) {    
        for my $tag ($feat->get_all_tags) {    
          $termHash{$tag} = 1;
          for my $value ($feat->get_tag_values($tag)) {
             $nodeHash{$source_id}{terms}{$tag} = $value;
          }
        }   
      } 
    }

    # process references
    my $ac = $seq->annotation;

    foreach my $key ( $ac->get_all_annotation_keys ) { 
      next unless $key =~ /reference/i;
      my @values = $ac->get_Annotations($key);

      # one isolate record could have multiple references
      my $title_count = 0;

      foreach my $value ( @values ) { 
        # value is an Bio::AnnotationI
        # location => 'Mol. Bi chem. Parasitol. 61 (2), 159-169 (1993) PUBMED   7903426'

        my $title = $value->title;
        # tile cut to 200 characters - study.study name column
        $title = substr $title, 0, 150;
        next if ($title eq "" || $title =~ /Direct Submission/i);

        my $location = $value->location;
        my ($pmid) = $location =~ /PUBMED\s+(\d+)/;
        if($pmid) {
          push @{$studyHash{$title}{pmid}}, $pmid; 
        }

        push @{$studyHash{$title}{ids}}, $source_id unless $title_count > 0; # only associlate id with first title
        $title_count++;

      } # end foreach value   
     } # end foreach key 
  } # end foreach seq

  $seq_io->close;

  $termHash{ncbi_taxon} = 1; # add hardcoded term "ncbi_taxon" as a term

  return (\%studyHash, \%nodeHash, \%termHash);
}

sub loadIsolates {

  my($self, $studyHash, $nodeHash, $extDbRlsId) = @_;

  my $count = 0;

  my $ontologyObj = GUS::Model::SRes::OntologyTerm->new({ name => 'sample from organism' });
  $self->error("cannot find ontology term 'sample from organism'") unless $ontologyObj->retrieveFromDB;

  while(my ($title, $v) = each %$studyHash) {

    my $study = GUS::Model::Study::Study->new();
    $study->setName($title);
    $study->setExternalDatabaseReleaseId($extDbRlsId);

    foreach my $id ( @{$v->{ids}} ) {  # id is each isolate accession

      my $node = GUS::Model::Study::ProtocolAppNode->new();
      $node->setDescription($nodeHash->{$id}->{desc});
      $node->setName($id);
      $node->setSourceId($id);
      $node->setExternalDatabaseReleaseId($extDbRlsId);
      $node->setParent($ontologyObj);  # type_id 

      my $extNASeq = $self->buildSequence($nodeHash->{$id}->{seq}, $id, $extDbRlsId);
      $extNASeq->submit;

      #my $segmentResult = GUS::Model::Results::SegmentResult->new();
      #$segmentResult->setParent($extNASeq);
      #$segmentResult->setParent($study);

      while(my ($term, $value) = each %{$nodeHash->{$id}->{terms}}) {  # loop each source modifiers

        if($term eq 'db_xref' && $value =~ /taxon/i) {
          $term = 'ncbi_taxon';
          $value =~ s/taxon://;

          my $taxonObj = GUS::Model::SRes::Taxon->new({ ncbi_tax_id => $value });
          $taxonObj->retrieveFromDB;

          $node->setParent($taxonObj);
        }

        my $categoryOntologyObj = $self->findOntologyTermByCategory($term);
        my $characteristic = GUS::Model::Study::Characteristic->new();
        $characteristic->setValue($value);

        $characteristic->setParent($categoryOntologyObj);
        $characteristic->setParent($node);
      } # end load terms

      my $link = GUS::Model::Study::StudyLink->new();
      $link->setParent($study);
      $link->setParent($node);

      $count++;
    }

    my %seen = ();
    my @pmids = grep { ! $seen{$_}++ } @{$v->{pmid}};  # unique pmid

    foreach my $pmid (@pmids) { 

      pcbiPubmed::setPubmedID ($pmid);
      my $publication = pcbiPubmed::fetchPublication(); 
      my $authors = pcbiPubmed::fetchAuthorListLong();

      my $ref = GUS::Model::SRes::BibliographicReference->new();
      $ref->setTitle($title);
      $ref->setAuthors($authors);
      $ref->setPublication($publication);

      my $study_ref = GUS::Model::Study::StudyBibRef->new;
      $study_ref->setParent($study);
      $study_ref->setParent($ref);
    }

    $study->submit;
  }

  return $count;
}

sub addOntologyCategory {
  my ($self, $ontologyTermObj) = @_;
  push @{$self->{_ontology_category_terms} }, $ontologyTermObj;
}

sub findOntologyTermByCategory {
  my ($self, $name) = @_;
  foreach my $term ( @{$self->{_ontology_category_terms}}) {
     return $term if ($term->getName eq $name);
  }

  $self->error("cannot find ontology name $name");
}

sub makeOntologyTerm {
  my ($self, $termHash, $extDbRlsId) = @_;

  foreach my $term( keys %$termHash) {
    my $termObj = GUS::Model::SRes::OntologyTerm->new({ name => $term });

    unless  ($termObj->retrieveFromDB ){ 
      $termObj->setExternalDatabaseReleaseId($extDbRlsId);
    }

    $self->addOntologyCategory($termObj);
  }
}

sub buildSequence {
  my ($self, $seq, $source_id, $extDbRlsId) = @_;

  my $extNASeq = GUS::Model::DoTS::ExternalNASequence->new();

  $extNASeq->setExternalDatabaseReleaseId($extDbRlsId);
  $extNASeq->setSequence($seq);
  $extNASeq->setSourceId($source_id);
  $extNASeq->setSequenceVersion(1);

  return $extNASeq;
}

sub undoTables {
  my ($self) = @_;
  return ( 'DoTS.ExternalNASequence',
           'Study.Study',
           'Study.StudyLink',
           'Study.StudyBibRef',
           'Study.ProtocolAppNode',
           'Study.Characteristic',
           'SRes.OntologyTerm',
           'SRes.BibliographicReference', 
         );
}

1;

