package ApiCommonData::Load::GeneAndCds2BioperlTree;

# Remove existing gene features, promote CDS, tRNA, etc to gene

use strict;
use Bio::SeqFeature::Generic;
use Bio::Location::Simple;
use ApiCommonData::Load::BioperlTreeUtils qw{makeBioperlFeature};
use Data::Dumper;
#input:
#
# gene  [folded into CDS]
# mRNA  (optional)  [discarded]
# CDS
#
#output: standard api tree: gene->transcript->exons

# (0) remove all seq features, add back the non-genes
# (1) copy old gene qualifiers to cds/rna feature
# (2) retype CDS into Gene
# (3) remember its join locations
# (4) create transcript, give it a copy of the gene's location
# (5) add to gene
# (6) create exons from sublocations
# (7) add to transcript


sub preprocess {
  my ($bioperlSeq, $plugin) = @_;
  my ($geneFeature, $mRNALocation, $CDSLocation);

  my @seqFeatures = $bioperlSeq->remove_SeqFeatures;
  foreach my $bioperlFeatureTree (@seqFeatures) {
    my $type = $bioperlFeatureTree->primary_tag();

    if ($type eq 'gene') {
      $geneFeature = $bioperlFeatureTree;
      next;
    }

    if ($type eq 'mRNA') {
      $mRNALocation = $bioperlFeatureTree->location();
      next;
    }

    $bioperlSeq->add_SeqFeature($bioperlFeatureTree);

    # This will accept genes of type misc_feature (e.g. cgd4_1050 of GI:46229367)
    # because it will have a geneFeature but not standalone misc_feature 
    # as found in GI:32456060.
    # And will accept transcripts that do not have 'gene' parents (e.g. tRNA
    # in GI:32456060)
    if ($geneFeature 
        or grep {$type eq $_} (
             'CDS',
             'misc_RNA',
             'rRNA',
             'snRNA',
             'snoRNA',
             'tRNA',
             )
        ) {

      copyQualifiers($geneFeature, $bioperlFeatureTree) if ($geneFeature);
      undef $geneFeature;

      my $gene = $bioperlFeatureTree;
      my $geneLoc = $gene->location();
      if ($type eq "CDS") {
	$type = "coding";
	$CDSLocation = $geneLoc;
	$geneLoc = $gene->location($mRNALocation);
      }
      $bioperlFeatureTree->primary_tag("${type}_gene");
      my $transcript = &makeBioperlFeature("transcript", $geneLoc, $bioperlSeq);
      $gene->add_SeqFeature($transcript);
      my @exonLocations = $geneLoc->each_Location();
      foreach my $exonLoc (@exonLocations) {
        my $exon = &makeBioperlFeature("exon", $exonLoc, $bioperlSeq);


	if ($type eq "coding") {
	  my $codingStart = $exonLoc->start();
	  my $codingEnd = $exonLoc->end();
	  $codingStart = $CDSLocation->start() if ($codingStart < $CDSLocation->start());
	  $codingEnd = $CDSLocation->end() if ($codingEnd > $CDSLocation->end());
	  if ($codingStart > $exonLoc->end() || $codingEnd < $exonLoc->start()) {
	    $codingStart = undef; # non-coding exon
	    $codingEnd = undef;
	  }
	  $exon->add_tag_value('coding_start', $codingStart);
	  $exon->add_tag_value('coding_end', $codingEnd);
	}
        $transcript->add_SeqFeature($exon);

      }
#        print STDERR  Dumper $gene;
    }
  }

}

sub copyQualifiers {
  my ($geneFeature, $bioperlFeatureTree) = @_;
  
  for my $qualifier ($geneFeature->get_all_tags()) {

    if ($bioperlFeatureTree->has_tag($qualifier)) {
      # remove tag and recreate with merged non-redundant values
      my %seen;
      my @uniqVals = grep {!$seen{$_}++} 
                       $bioperlFeatureTree->remove_tag($qualifier), 
                       $geneFeature->get_tag_values($qualifier);
                       
      $bioperlFeatureTree->add_tag_value(
                             $qualifier, 
                             @uniqVals
                           );    
    } else {
      $bioperlFeatureTree->add_tag_value(
                             $qualifier,
                             $geneFeature->get_tag_values($qualifier)
                           );
    }
     
  }
}

1;
