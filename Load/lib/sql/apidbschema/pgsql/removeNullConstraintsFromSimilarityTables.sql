
ALTER TABLE DoTS.Similarity ALTER COLUMN total_match_length DROP NOT NULL;
ALTER TABLE DoTS.Similarity ALTER COLUMN number_identical DROP NOT NULL;
ALTER TABLE DoTS.Similarity ALTER COLUMN number_positive DROP NOT NULL;
ALTER TABLE DoTS.Similarity ALTER COLUMN score DROP NOT NULL;
ALTER TABLE DoTS.Similarity ALTER COLUMN pvalue_mant DROP NOT NULL;
ALTER TABLE DoTS.Similarity ALTER COLUMN pvalue_exp DROP NOT NULL;

ALTER TABLE DoTS.SimilaritySpan ALTER COLUMN match_length DROP NOT NULL;
ALTER TABLE DoTS.SimilaritySpan ALTER COLUMN number_identical DROP NOT NULL;
ALTER TABLE DoTS.SimilaritySpan ALTER COLUMN number_positive DROP NOT NULL;
ALTER TABLE DoTS.SimilaritySpan ALTER COLUMN score DROP NOT NULL;
ALTER TABLE DoTS.SimilaritySpan ALTER COLUMN pvalue_mant DROP NOT NULL;
ALTER TABLE DoTS.SimilaritySpan ALTER COLUMN pvalue_exp DROP NOT NULL;

ALTER TABLE DoTSVer.SimilarityVer ALTER COLUMN total_match_length DROP NOT NULL;
ALTER TABLE DoTSVer.SimilarityVer ALTER COLUMN number_identical DROP NOT NULL;
ALTER TABLE DoTSVer.SimilarityVer ALTER COLUMN number_positive DROP NOT NULL;
ALTER TABLE DoTSVer.SimilarityVer ALTER COLUMN score DROP NOT NULL;
ALTER TABLE DoTSVer.SimilarityVer ALTER COLUMN pvalue_mant DROP NOT NULL;
ALTER TABLE DoTSVer.SimilarityVer ALTER COLUMN pvalue_exp DROP NOT NULL;

ALTER TABLE DoTSVer.SimilaritySpanVer ALTER COLUMN match_length DROP NOT NULL;
ALTER TABLE DoTSVer.SimilaritySpanVer ALTER COLUMN number_identical DROP NOT NULL;
ALTER TABLE DoTSVer.SimilaritySpanVer ALTER COLUMN number_positive DROP NOT NULL;
ALTER TABLE DoTSVer.SimilaritySpanVer ALTER COLUMN score DROP NOT NULL;
ALTER TABLE DoTSVer.SimilaritySpanVer ALTER COLUMN pvalue_mant DROP NOT NULL;
ALTER TABLE DoTSVer.SimilaritySpanVer ALTER COLUMN pvalue_exp DROP NOT NULL;
