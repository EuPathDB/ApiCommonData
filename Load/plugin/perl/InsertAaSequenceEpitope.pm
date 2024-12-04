package ApiCommonData::Load::Plugin::InsertAaSequenceEpitope;
use lib "$ENV{GUS_HOME}/lib/perl";
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;
use JSON;
use Bio::Tools::GFF;
use GUS::PluginMgr::Plugin;
use GUS::Supported::Util;
use GUS::Model::ApiDB::AASequenceEpitope;
use Data::Dumper;
use ApiCommonData::Load::AnalysisConfigRepeatFinder qw(displayAndBaseName);
use GUS::Model::DoTS::AASequenceImp;

sub getArgsDeclaration {
    my $argsDeclaration  =

        [

         fileArg({ name => 'peptideResultFile',
                   descr => 'peptide analysis results file in text format containing the blast and exact matches',
                   constraintFunc=> undef,
                   reqd  => 1,
                   isList => 0,
                   mustExist => 1,
                   format=>'Text',
                 }),

         stringArg({name => 'genomeExtDbRlsSpec',
                    descr => 'ExternalDatabase release spec for the primary genome',
                    constraintFunc=> undef,
                    reqd  => 1,
                    isList => 0
                   }),

        ];
    
    return $argsDeclaration;
}


sub getDocumentation {
    
    my $description = <<NOTES;
Load the epitopes amino acids and the given accession by the IEDB database and the NCBI accession number of the gene the petpide is found.
NOTES
	
	my $purpose = <<PURPOSE;
Load epitopes analyis results to the database.
PURPOSE
	
	my $purposeBrief = <<PURPOSEBRIEF;
Load epitopes analysis results to the database. Results contains both the exact match search and blast analysis.
PURPOSEBRIEF
	
	my $syntax = <<SYNTAX;
SYNTAX
	
	my $notes = <<NOTES;
NOTES
	
	my $tablesAffected = <<AFFECT;
ApiDB.AASequenceEpitope
AFFECT
	
	my $tablesDependedOn = <<TABD;
TABD
	
	my $howToRestart = <<RESTART;
There are no restart facilities for this plugin
RESTART
	
	my $failureCases = <<FAIL;
FAIL
	
	my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief,tablesAffected=>$tablesAffected,tablesDependedOn=>$tablesDependedOn,howToRestart=>$howToRestart,failureCases=>$failureCases,notes=>$notes};
    
    return ($documentation);
}



sub new {
    my $class = shift;
    my $self = {};
    bless($self, $class);
    
    my $documentation = &getDocumentation();
    
    my $args = &getArgsDeclaration();
    
    $self->initialize({requiredDbVersion => 4.0,
		       cvsRevision => '$Revision$',
		       name => ref($self),
		       argsDeclaration   => $args,
		       documentation     => $documentation
		      });
    return $self;
}

sub run {
	my ($self) = @_;
	my $peptideResultFile = $self->getArg('peptideResultFile');
	my $resultString = $self->loadEpitopes($peptideResultFile);

    return ($resultString);
}


sub fetchAASequenceIdFromSourceID {
    my ($self, $origSourceId) = @_;

    if($self->{aa_sequence_id}->{$origSourceId}) {
        return $self->{aa_sequence_id}->{$origSourceId};
    }

    my $extDbRlsSpec = $self->getArg("genomeExtDbRlsSpec");
    my $extDbRlsId = $self->getExtDbRlsId($extDbRlsSpec);

    my $sql = "select aa_sequence_id, source_id from dots.translatedaasequence where external_database_release_id = ?";
    my $dbh = $self->getQueryHandle();
    my $sh = $dbh->prepare($sql);
    $sh->execute($extDbRlsId);


    while(my ($aaSequenceId, $sourceId) = $sh->fetchrow_array()) {
        $self->{aa_sequence_id}->{$sourceId} = $aaSequenceId;
    }
    $sh->finish();

    return $self->{aa_sequence_id}->{$origSourceId};

}



sub loadEpitopes {

    my ($self, $peptideResultFile) = @_;

    open(my $peptides, $peptideResultFile) or die "Could not open file '$peptideResultFile' $!";

    my $count;
    while (my $row = <$peptides>) {
        chomp $row;
        my @counts_list = split("\t", $row);
        my $aa_sequence_source_id = $counts_list[0];
        #my $aa_sequence => $self->fetchAASourceID($aa_sequence_source_id) || $self->error ("Can't retrieve aa_sequence_id for row with source id $aa_sequence_source_id");
        my $iedb_id = $counts_list[1];
        my $peptide_match = $counts_list[2];
        my $protein_match = $counts_list[3];
        my $species_match = $counts_list[4];
        my $number_of_matches = $counts_list[10];
        my $blast_hit_align_len = $counts_list[11];
        my $alignment = $counts_list[14];


        my $aa_sequence_id = $self->fetchAASequenceIdFromSourceID($aa_sequence_source_id);

        my $row_peptide = GUS::Model::ApiDB::AASequenceEpitope->new({
            aa_sequence_id => $aa_sequence_id,
            iedb_id => $iedb_id,
            peptide_match => $peptide_match,
            protein_match => $protein_match,
            species_match => $species_match,
            blast_hit_identity => $number_of_matches,
            blast_hit_align_len => $blast_hit_align_len,
            alignment => $alignment});

        $row_peptide->submit();
        $self->undefPointerCache();

        $count++;
    }

    return "Loaded $count rows into AASequenceEpitope";
}


sub undoTables {
  my ($self) = @_;

  return ('ApiDB.AASequenceEpitope');
}

1;
