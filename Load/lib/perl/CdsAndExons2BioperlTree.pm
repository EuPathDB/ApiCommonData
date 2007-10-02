package ApiCommonData::Load::CdsAndExons2BioperlTree;


use strict;
use Bio::SeqFeature::Generic;
use Bio::Location::Simple;
use ApiCommonData::Load::BioperlTreeUtils qw{makeBioperlFeature};


#input: CDS with join location (if multiple exons)
#output: standard api tree: gene->transcript->exons
#                                           ->CDS

sub preprocess {
  my ($bioperlSeq, $plugin) = @_;

  # (1) retype CDS or transcript into Gene
  # (4) create transcript, give it a copy of the gene's location
  # (5) add to gene
  # (6) add exons to transcript
  # (7) remove exons from gene
  foreach my $bioperlFeatureTree ($bioperlSeq->get_SeqFeatures()) {
    my $type = $bioperlFeatureTree->primary_tag();
    if (grep {$type eq $_} ("transcript","CDS", "tRNA", "rRNA", "snRNA")) {
      $type = "coding" if ($type eq "CDS" || $type eq "transcript");
      $bioperlFeatureTree->primary_tag("${type}_gene");
      my $gene = $bioperlFeatureTree;
      my $geneLoc = $gene->location();
      my $transcript = &makeBioperlFeature("transcript", $geneLoc, $bioperlSeq);
      my @exons = $gene->get_SeqFeatures();
      foreach my $exon (@exons) {
	my $t = $exon->primary_tag();
	die "expected bioperl exon but got '$t'" unless $t = "exon";
	$transcript->add_SeqFeature($exon);
      }
      # we have to remove the exons before adding the transcript b/c
      # remove_SeqFeatures() removes all subfeatures of the $gene
      $gene->remove_SeqFeatures();
      $gene->add_SeqFeature($transcript);
    }
  }
}


1;
