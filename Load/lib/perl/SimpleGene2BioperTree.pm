package ApiCommonData::Load::SimpleGene2BioperTree;

# Remove existing gene features, promote CDS, tRNA, etc to gene

use strict;
use Bio::SeqFeature::Generic;
use Bio::Location::Simple;
use ApiCommonData::Load::BioperlTreeUtils qw{makeBioperlFeature};
use Data::Dumper;

#input:
#
# gene  [folded into CDS]
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


sub preprocess 
{
  my ($bioperlSeq, $plugin) = @_;

  my @seqFeatures = $bioperlSeq->get_SeqFeatures;
  $bioperlSeq->remove_SeqFeatures;

  foreach my $bioperlFeatureTree (@seqFeatures) {
    my $type = $bioperlFeatureTree->primary_tag();

    if ($type eq 'gene') {
      $type = "coding";
      $bioperlFeatureTree->primary_tag("${type}_gene");

      my $gene = $bioperlFeatureTree;
      my $geneLoc = $gene->location();


      my $transcript = &makeBioperlFeature("transcript", $geneLoc, $bioperlSeq);

      my $codonStart = 0;
      $codonStart = $bioperlFeatureTree->get_tag_values("codon_start") - 1
		if ( $bioperlFeatureTree->has_tag("codon_start") );
      $codonStart = $bioperlFeatureTree->frame() if ($bioperlFeatureTree->frame());

      my @exonLocs = $geneLoc->each_Location();
      my $CDSLength = 0;

      my (@exons, @sortedExons);
      foreach my $exonLoc (@exonLocs) {
        my $exon = &makeBioperlFeature("exon", $exonLoc, $bioperlSeq);
        my ($codingStart, $codingEnd);
        if ($exon->location->strand == -1) {
          $codingStart = $exon->location->end;
          $codingEnd = $exon->location->start;
          $codingStart -= $codonStart if ($codonStart > 0);
        } else {
          $codingStart = $exon->location->start;
          $codingEnd = $exon->location->end;
          $codingStart += $codonStart if ($codonStart > 0);
        }
        $exon->add_tag_value('CodingStart', $codingStart);
        $exon->add_tag_value('CodingEnd', $codingEnd);

        $CDSLength += (abs($codingStart - $codingEnd) + 1);
        push (@exons, $exon);
      }
      $transcript->add_tag_value('CDSLength', $CDSLength);

      foreach my $exon (sort {$a->location->start() <=> $b->location->start()} @exons) {
        $transcript->add_SeqFeature($exon);
      }

      $gene->add_SeqFeature($transcript);
      $bioperlSeq->add_SeqFeature($gene);

    }
    else {
      $bioperlSeq->add_SeqFeature($bioperlFeatureTree);
    }
  }
}


1;
