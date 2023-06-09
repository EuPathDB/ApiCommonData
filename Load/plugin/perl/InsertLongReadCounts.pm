package ApiCommonData::Load::Plugin::InsertLongReadCounts;
use lib "$ENV{GUS_HOME}/lib/perl";
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use warnings;
use JSON;
use Bio::Tools::GFF;
use GUS::PluginMgr::Plugin;
use GUS::Supported::Util;
use GUS::Model::ApiDB::LongReadTranscript;
use Data::Dumper;
use ApiCommonData::Load::AnalysisConfigRepeatFinder qw(displayAndBaseName);

sub getArgsDeclaration {
    my $argsDeclaration  =
	
       [

	fileArg({ name => 'gffFile',
		     descr => 'gff file generated by talon',
		     constraintFunc=> undef,
		     reqd  => 1,
		     isList => 0,
		     mustExist => 1,
		     format=>'Text',
		   }),
	fileArg({ name => 'countFile',
		     descr => 'csv transcripts count file obtained from talon',
		     constraintFunc=> undef,
		     reqd  => 1,
		     isList => 0,
		     mustExist => 1,
		     format=>'Text',
		   }),
	fileArg({ name => 'analysisConfig',
                     descr => 'analysisConfig used for the analysis of the dataset',
                     constraintFunc=> undef,
                     reqd  => 1,
                     isList => 0,
                     mustExist => 1,
                     format=>'Text',
                   }),
	stringArg({name => 'extDbSpec',
              	     descr => 'External database from whence this data came|version',
              	     constraintFunc=> undef,
                     reqd  => 1,
                     isList => 0
             })
	];
    
    return $argsDeclaration;
}


sub getDocumentation {
    
    my $description = <<NOTES;
Load long read RNA seq transcript read counts obtained from talon.
NOTES
	
	my $purpose = <<PURPOSE;
Load long transcripts gene isoforms and read count determine by talon.
PURPOSE
	
	my $purposeBrief = <<PURPOSEBRIEF;
Load long read RNA seq transcripts counts.
PURPOSEBRIEF
	
	my $syntax = <<SYNTAX;
SYNTAX
	
	my $notes = <<NOTES;
NOTES
	
	my $tablesAffected = <<AFFECT;
ApiDB.longreadtranscript
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
	my $gffFile = $self->getArg('gffFile');
	my $countFile = $self->getArg('countFile');
	my $samplesConfig = $self->getArg('analysisConfig');
	$self->loadLongReadCount($gffFile, $countFile, $samplesConfig)	

}


sub loadLongReadCount {

	my ($self, $gffFile, $countFile, $samplesConfig) = @_;
	my $extDbSpec = $self->getArg('extDbSpec');
  	my $extDbRlsId = $self->getExtDbRlsId($extDbSpec) or die "Couldn't find source db: $extDbSpec";		
	my $samplesHash = displayAndBaseName($samplesConfig);	
    	my $gffhh;
	open($gffhh, "gunzip -c $gffFile |") || die "can't open pipe to $gffFile";
	my $gffio = Bio::Tools::GFF->new(-fh => $gffhh, -gff_version => 3);

    	my %transcript_coordinates = ();
    	while(my $feature = $gffio->next_feature()) {
        	$feature->gff_format(Bio::Tools::GFF->new(-gff_version => 3));
        	my $primary = $feature->primary_tag();
        	if ($primary eq "transcript") {
            		my @coordinates = ($feature->start(), $feature->end(), $feature->seq_id());
            		my ($id) = $feature->get_tag_values("ID");
            		$transcript_coordinates{$id} = \@{coordinates};
        		}     
	    }

    	#my $count_file = $countFile;
    	open(my $count, $countFile) or die "Could not open file '$countFile' $!";
    	my $line = <$count>;
    	my @header = split /\s+/,$line;
    	my $len = scalar @header;
    	my @sampleIDs = @header[11 .. $len];
    	while (my $row = <$count>) {
        	chomp $row;
        	my @counts_list = split /\s+/,$row;
        	next if $. == 1;
       		my @counts = @counts_list[11 .. $len];
        	my $gene_source_id = $counts_list[2];
        	my $transcript_source_id = $counts_list[3];
        	my $talon_gene_name = $counts_list[4];
        	my $talon_transcript_name = $counts_list[5];
        	my $number_of_exon = $counts_list[6];
        	my $transcript_length = $counts_list[7];
        	my $gene_novelty = $counts_list[8];
        	my $transcript_novelty = $counts_list[9];
        	my $splice_match = $counts_list[10];
        	my $minStart = $transcript_coordinates{$transcript_source_id}[0];
        	my $maxEnd = $transcript_coordinates{$transcript_source_id}[1];
        	my $chr = $transcript_coordinates{$transcript_source_id}[2];
        	my %read_counts;
        	for my $index(0 .. $#counts -1) {       
            		#$read_counts{$sampleIDs[$index]} = int($counts[$index]);
			$read_counts{$samplesHash->{$sampleIDs[$index]}} = int($counts[$index]);  
        	}

        	my $json = encode_json \%read_counts;
		my $row_counts = GUS::Model::ApiDB::LongReadTranscript->new({
								gene_source_id => $gene_source_id,
								transcript_source_id => $transcript_source_id,
								talon_gene_name => $talon_gene_name,
								talon_transcript_name => $talon_transcript_name,
								number_of_exon => $number_of_exon,
								transcript_length => $transcript_length,
								gene_novelty => $gene_novelty,
								transcript_novelty => $transcript_novelty,
								incomplete_splice_match_type => $splice_match,
								min_Start => $minStart,
								max_End => $maxEnd,
								na_seq_source_id => $chr,
								count_data => $json,
								external_database_release_id => $extDbRlsId});
	 	$row_counts->submit();
		$self->undefPointerCache();
		}
	
}	
sub undoTables {
  my ($self) = @_;

  return ('ApiDB.LongReadTranscript');
}

1;
