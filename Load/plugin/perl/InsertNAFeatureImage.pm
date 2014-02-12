package ApiCommonData::Load::Plugin::InsertNAFeatureImage;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;

use GUS::PluginMgr::Plugin;
use Bio::Tools::GFF;

use GUS::Model::DoTS::NAFeature;
use GUS::Model::SRes::ExternalDatabase;
use GUS::Model::SRes::ExternalDatabaseRelease;
use GUS::Model::ApiDB::NAFeatureImage;
use GUS::Supported::Util;

# ----------------------------------------------------------
# Load Arguments
# ----------------------------------------------------------

sub getArgsDeclaration {
  my $argsDeclaration  =
    [
     fileArg({ name => 'file',
         descr => 'tab delimited file',
         constraintFunc=> undef,
         reqd  => 1,
         isList => 0,
         mustExist => 1,
         format => 'Six column tab delimited file in the order geneid, tag, product, goterm, imsage1, image2',
       }),
     stringArg({ name => 'extDbName',
         descr => 'externaldatabase name that this dataset references',
         constraintFunc=> undef,
         reqd  => 1,
         isList => 0
       }),
     stringArg({ name => 'extDbVer',
         descr => 'externaldatabaserelease version of the extDb that this dataset references',
         constraintFunc=> undef,
         reqd  => 1,
         isList => 0
       }),

    ];

  return $argsDeclaration;
}

# ----------------------------------------------------------
# Documentation
# ----------------------------------------------------------

sub getDocumentation {

  my $description = <<DESCR;
Plugin to DBP image file into apidb.nafeatureimage table
DESCR

  my $purpose = <<PURPOSE;
Plugin to load DBP image file into apidb.nafeatureimage table 
PURPOSE

  my $purposeBrief = <<PURPOSEBRIEF;
Plugin to load DBP image file into apidb.nafeatureimage table 
PURPOSEBRIEF

  my $notes = <<NOTES;
NOTES

  my $tablesAffected = <<AFFECT;
ApiDB.NAFeatureImage
AFFECT

  my $tablesDependedOn = <<TABD;
DoTS.NAFeature, SRes.ExternalDatabaseRelease
TABD

  my $howToRestart = <<RESTART;
No restart provided. Must undo and reload.
RESTART

  my $failureCases = <<FAIL;
FAIL

  my $documentation = { purpose          => $purpose,
                        purposeBrief     => $purposeBrief,
                        tablesAffected   => $tablesAffected,
                        tablesDependedOn => $tablesDependedOn,
                        howToRestart     => $howToRestart,
                        failureCases     => $failureCases,
                        notes            => $notes
                      };

  return ($documentation);
}

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

sub run {
  my $self = shift;

  my $extDbReleaseId = $self->getExtDbRlsId($self->getArg('extDbName'), $self->getArg('extDbVer')) || $self->error("Can't find external_database_release_id for this data");

  my $processed = 1;

  open(inputFile, $self->getArg('file'));

  while(<inputFile>) {
    chomp;
    my($gene, $tag, $product, $goterm, @img_uris) = split /\|/, $_;
    my $naFeatureId =  GUS::Supported::Util::getGeneFeatureId($self, $gene, 0, 0) ;
    my $note = "GO term: $goterm; Gene annotation: $product";

    my $image_type = 'GFP';
    foreach(@img_uris) {

      my $img_uri = $_;
      $image_type = 'DIC' if $img_uri =~/DIC/;
      my $naFeatImage = GUS::Model::ApiDB::NAFeatureImage->new({'na_feature_id' => $naFeatureId, 
                                                                'image_uri'     => $img_uri,
                                                                'image_type'    => $image_type,
                                                                'note'          => $note,
                                                                'external_database_release_id' => $extDbReleaseId
                                                              });

      $naFeatImage->submit();
      $processed++;
    }
  }

  return "$processed data lines parsed and loaded";
}

sub undoTables {
  qw(
    ApiDB.NAFeatureImage
  );
}

1;
