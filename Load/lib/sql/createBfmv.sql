set time on timing on

-- createBfmv.sql
--
-- Big F{-at,-reakin',-unctional,-ast} Materialized Views
--
-- This script creates materialized views which denormalize GUS tables for
-- the sake of performance.  Each record type X has at least an mview named
-- apidb.XAttributes, which has one row for each X record (that is, each
-- distinct source_id for an X), and columns for different attributes.
-- Including an attribute in apidb.XAttributes makes the WDK's query-history
-- column-sorting easy and relatively efficient.
--
-- It is sometimes desirable to change the definition of one of these mviews
-- while it is being used by an application.  Simply dropping and re-creating
-- the materialized view creates a time gap in which the application will
-- fail.  To handle this, the script gives the mviews names of the form
-- "apidb.XAttributes1111", then creates a synonym, "apidb.XAttributes", which
-- points to the mview.  To re-run this script while the mviews may be in use,
-- change all occurrences of "1111" to any other four-digit number, for
-- instance "1234".  The application will use the old mview until the "CREATE
-- OR REPLACE SYNONYM" statement runs, and then switch seamlessly to the new.
--
-- A query at the end of this script looks for materialized views that end in
-- a four-digit number but aren't pointed to by a synonym.  For convenience,
-- the query result is in the form of "DROP MATERIALIZED VIEW" statements.  If
-- this script terminates successfully*, these statements can be run, dropping
-- the disused mviews.
--
-- This SQL statement will find which four-digit numbers are in use:
-- SELECT * FROM all_synonyms where owner='APIDB';
--
-- This script should be run as the database user APIDB.  Running it as other
-- users has generated "insufficient privilege" errors (even for a user with
-- the DBA privilege).
--
-- * Before trying to create a materialized view, this script will attempt to
-- drop any existing one of the same name.  If the four-digit number is
-- changed, this will typically result in an "ORA-12003" error ("materialized
-- view does not exist").  If the output contains no errors other than these,
-- the script has run successfully.


---------------------------
-- set permissions
---------------------------
-- These mviews can't be created unless the apidb user has these privileges.
-- But now that we're running this script as the apidb user, they generate
-- errors (you can't grant privileges to yourself).  So they're commented out.
-- GRANT CREATE TABLE TO apidb;
-- GRANT CREATE MATERIALIZED VIEW TO apidb;

-- GRANT REFERENCES ON dots.ExternalNaSequence TO apidb;
-- GRANT SELECT ON dots.ExternalNaSequence TO apidb WITH GRANT OPTION;
-- GRANT REFERENCES ON sres.TaxonName TO apidb;
-- GRANT SELECT ON sres.TaxonName TO apidb WITH GRANT OPTION;
-- GRANT REFERENCES ON dots.SnpFeature TO apidb;
-- GRANT SELECT ON dots.SnpFeature TO apidb WITH GRANT OPTION;
-- GRANT REFERENCES ON dots.Library TO apidb;
-- GRANT SELECT ON dots.Library TO apidb WITH GRANT OPTION;
-- GRANT REFERENCES ON dots.Est TO apidb;
-- GRANT SELECT ON dots.Est TO apidb WITH GRANT OPTION;
-- GRANT REFERENCES ON dots.Source TO apidb;
-- GRANT SELECT ON dots.Source TO apidb WITH GRANT OPTION;
-- GRANT REFERENCES ON dots.VirtualSequence TO apidb;
-- GRANT SELECT ON dots.VirtualSequence TO apidb WITH GRANT OPTION;
-- GRANT REFERENCES ON dots.TranslatedAaFeature TO apidb;
-- GRANT SELECT ON dots.TranslatedAaFeature TO apidb WITH GRANT OPTION;
-- GRANT SELECT ON dots.AaLocation TO apidb;
-- GRANT SELECT ON dots.NaFeatureComment TO apidb;
-- GRANT SELECT ON dots.ExonFeature TO apidb;
-- GRANT SELECT ON dots.TransmembraneAaFeature TO apidb;
-- GRANT SELECT ON dots.GeneFeature TO apidb;
-- GRANT SELECT ON dots.NaLocation TO apidb;
-- GRANT SELECT ON dots.Miscellaneous TO apidb;
-- GRANT SELECT ON sres.SequenceOntology TO apidb;
-- GRANT SELECT ON sres.Taxon TO apidb;

---------------------------
-- genes
---------------------------

prompt ### DROP MATERIALIZED VIEW apidb.GoTermList ###;
DROP MATERIALIZED VIEW apidb.GoTermList;

prompt ### CREATE MATERIALIZED VIEW apidb.GoTermList ###;
CREATE MATERIALIZED VIEW apidb.GoTermList AS
SELECT gf.source_id, o.ontology,
       DECODE(gail.name, 'Interpro', 'predicted', 'annotated') AS source,
       apidb.tab_to_string(CAST(COLLECT(DISTINCT gt.name) AS apidb.varchartab), ', ') AS go_terms
FROM dots.GeneFeature gf, dots.Transcript t,
     dots.TranslatedAaFeature taf, dots.GoAssociation ga,
     sres.GoTerm gt, dots.GoAssociationInstance gai,
     dots.GoAssociationInstanceLoe gail,
     dots.GoAssocInstEvidCode gaiec, sres.GoEvidenceCode gec,
     (SELECT gr.child_term_id AS go_term_id, gp.name AS ontology
      FROM sres.GoRelationship gr, sres.GoTerm gp
      WHERE gr.parent_term_id = gp.go_term_id
        AND gp.go_id in ('GO:0008150','GO:0003674','GO:0005575')) o
WHERE gf.na_feature_id = t.parent_id
  AND t.na_feature_id = taf.na_feature_id
  AND taf.aa_sequence_id = ga.row_id
  AND ga.table_id = (SELECT table_id
                     FROM core.TableInfo
                     WHERE name = 'TranslatedAASequence')
  AND ga.go_term_id = gt.go_term_id
  AND ga.go_association_id = gai.go_association_id
  AND gai.go_assoc_inst_loe_id = gail.go_assoc_inst_loe_id
  AND gai.go_association_instance_id
      = gaiec.go_association_instance_id
  AND gaiec.go_evidence_code_id = gec.go_evidence_code_id
  AND gt.go_term_id = o.go_term_id
GROUP BY gf.source_id, o.ontology, gail.name;

---------------------------

prompt ### DROP MATERIALIZED VIEW apidb.GeneGoAttributes ###;
DROP MATERIALIZED VIEW apidb.GeneGoAttributes;

prompt ### CREATE MATERIALIZED VIEW apidb.GeneGoAttributes ###;
CREATE MATERIALIZED VIEW apidb.GeneGoAttributes AS
SELECT gene.source_id,
       annotated_go_component.go_terms AS annotated_go_component,
       annotated_go_function.go_terms AS annotated_go_function,
       annotated_go_process.go_terms AS annotated_go_process,
       predicted_go_component.go_terms AS predicted_go_component,
       predicted_go_function.go_terms AS predicted_go_function,
       predicted_go_process.go_terms AS predicted_go_process
FROM (SELECT DISTINCT gene AS source_id FROM apidb.GeneId) gene,
     (SELECT * FROM apidb.GoTermList
      WHERE source = 'annotated' AND ontology = 'cellular_component')
       annotated_go_component,
     (SELECT * FROM apidb.GoTermList
      WHERE source = 'annotated' AND ontology = 'molecular_function')
       annotated_go_function,
     (SELECT * FROM apidb.GoTermList
      WHERE source = 'annotated' AND ontology = 'biological_process')
       annotated_go_process,
     (SELECT * FROM apidb.GoTermList
      WHERE source = 'predicted' AND ontology = 'cellular_component')
       predicted_go_component,
     (SELECT * FROM apidb.GoTermList
      WHERE source = 'predicted' AND ontology = 'molecular_function')
       predicted_go_function,
     (SELECT * FROM apidb.GoTermList
      WHERE source = 'predicted' AND ontology = 'biological_process')
       predicted_go_process
WHERE gene.source_id = annotated_go_component.source_id(+)
  AND 'annotated' = annotated_go_component.source(+)
  AND 'cellular_component' = annotated_go_component.ontology(+)
  AND gene.source_id = annotated_go_function.source_id(+)
  AND 'annotated' = annotated_go_function.source(+)
  AND 'molecular_function' = annotated_go_function.ontology(+)
  AND gene.source_id = annotated_go_process.source_id(+)
  AND 'annotated' = annotated_go_process.source(+)
  AND 'biological_process' = annotated_go_process.ontology(+)
  AND gene.source_id = predicted_go_component.source_id(+)
  AND 'predicted' = predicted_go_component.source(+)
  AND 'cellular_component' = predicted_go_component.ontology(+)
  AND gene.source_id = predicted_go_function.source_id(+)
  AND 'predicted' = predicted_go_function.source(+)
  AND 'molecular_function' = predicted_go_function.ontology(+)
  AND gene.source_id = predicted_go_process.source_id(+)
  AND 'predicted' = predicted_go_process.source(+)
  AND 'biological_process' = predicted_go_process.ontology(+);

GRANT SELECT ON apidb.GeneGoAttributes TO gus_r;

CREATE INDEX apidb.GeneGoAttr_sourceId ON apidb.GeneGoAttributes (source_id);

---------------------------

prompt ### DROP MATERIALIZED VIEW apidb.DerisiExpn ###;
DROP MATERIALIZED VIEW apidb.DerisiExpn;

prompt ### CREATE MATERIALIZED VIEW apidb.DerisiExpn ###;
CREATE MATERIALIZED VIEW apidb.DerisiExpn AS
SELECT gene.source_id, expn.derisi_max_level, derisi_max_pct,
       derisi_max_timing, derisi_min_timing, derisi_min_level
FROM (SELECT DISTINCT gene AS source_id from apidb.GeneId) gene,
     (SELECT p.source_id,
             p.max_expression AS derisi_max_level,
             p.max_percentile AS derisi_max_pct,
             p.equiv_max AS derisi_max_timing,
             p.equiv_min AS derisi_min_timing,
             p.min_expression AS derisi_min_level
      FROM apidb.Profile p, apidb.ProfileSet ps, core.TableInfo ti
      WHERE ps.name = 'DeRisi 3D7 Smoothed Averaged'
        AND ti.name = 'GeneFeature'
        AND p.profile_set_id = ps.profile_set_id
        AND ti.table_id = p.subject_table_id) expn
WHERE gene.source_id = expn.source_id(+);

GRANT SELECT ON apidb.DerisiExpn TO gus_r;

CREATE INDEX apidb.Derisi_sourceId ON apidb.DerisiExpn (source_id);

---------------------------

prompt ### DROP MATERIALIZED VIEW apidb.WinzelerExpn ###;
DROP MATERIALIZED VIEW apidb.WinzelerExpn;

prompt ### CREATE MATERIALIZED VIEW apidb.WinzelerExpn ###;
CREATE MATERIALIZED VIEW apidb.WinzelerExpn AS
SELECT gene.source_id, expn.winzeler_max_level, winzeler_max_pct,
       winzeler_max_timing, winzeler_min_timing, winzeler_min_level
FROM (SELECT DISTINCT gene AS source_id from apidb.GeneId) gene,
     (SELECT p.source_id,
             p.max_expression AS winzeler_max_level,
             p.max_percentile AS winzeler_max_pct,
             p.time_of_max_expr AS winzeler_max_timing,
             p.time_of_min_expr AS winzeler_min_timing,
             p.min_expression AS winzeler_min_level
      FROM apidb.Profile p, apidb.ProfileSet ps, core.TableInfo ti
      WHERE ps.name = 'winzeler_cc_sorbExp'
        AND ti.name = 'GeneFeature'
        AND p.profile_set_id = ps.profile_set_id
        AND ti.table_id = p.subject_table_id) expn
WHERE gene.source_id = expn.source_id(+);

GRANT SELECT ON apidb.WinzelerExpn TO gus_r;

CREATE INDEX apidb.Winzeler_sourceId ON apidb.WinzelerExpn (source_id);

---------------------------

prompt ### DROP MATERIALIZED VIEW apidb.ToxoExpn ###;
DROP MATERIALIZED VIEW apidb.ToxoExpn;

prompt ### CREATE MATERIALIZED VIEW apidb.ToxoExpn ###;
CREATE MATERIALIZED VIEW apidb.ToxoExpn AS
SELECT gene.source_id, pru.expression AS pru, veg.expression AS veg,
       rh.expression AS rh, rh_high_glucose.expression AS rh_high_glucose,
       rh_no_glucose.expression AS rh_no_glucose,
       glucose.fold_change AS glucose_fold_change,
       pru_veg.fold_change AS pru_veg_fold_change,
       pru_rh.fold_change AS pru_rh_fold_change,
       veg_rh.fold_change AS veg_rh_fold_change
FROM (SELECT DISTINCT gene AS source_id FROM apidb.GeneAlias) gene,
     (SELECT ga.gene, avg(ep1.mean) AS expression
       FROM rad.LogicalGroup lg, rad.AnalysisInput ai1, rad.Analysis a1,
            rad.ExpressionProfile ep1, rad.Protocol p,
            rad.ShortOligoFamily sof, ApiDB.GeneAlias ga
       WHERE p.name = 'R Expression Statistics'
        AND lg.name = 'Pru - RMA Quantifications'
        AND lg.logical_group_id = ai1.logical_group_id
        AND a1.analysis_id = ai1.analysis_id
        AND a1.protocol_id = p.protocol_id
        AND ep1.analysis_id = a1.analysis_id
        AND sof.composite_element_id = ep1.row_id
          AND sof.source_id is not null
        AND ga.alias = sof.source_id
       GROUP BY ga.gene) pru,
     (SELECT ga.gene, avg(ep1.mean) AS expression
       FROM rad.LogicalGroup lg, rad.AnalysisInput ai1, rad.Analysis a1,
            rad.ExpressionProfile ep1, rad.Protocol p,
            rad.ShortOligoFamily sof, ApiDB.GeneAlias ga
       WHERE p.name = 'R Expression Statistics'
        AND lg.name = 'VEG - RMA Quantifications'
        AND lg.logical_group_id = ai1.logical_group_id
        AND a1.analysis_id = ai1.analysis_id
        AND a1.protocol_id = p.protocol_id
        AND ep1.analysis_id = a1.analysis_id
        AND sof.composite_element_id = ep1.row_id
          AND sof.source_id is not null
        AND ga.alias = sof.source_id
       GROUP BY ga.gene) veg,
     (SELECT ga.gene, avg(ep1.mean) AS expression
       FROM rad.LogicalGroup lg, rad.AnalysisInput ai1, rad.Analysis a1,
            rad.ExpressionProfile ep1, rad.Protocol p,
            rad.ShortOligoFamily sof, ApiDB.GeneAlias ga
       WHERE p.name = 'R Expression Statistics'
        AND lg.name = 'RH - RMA Quantifications'
        AND lg.logical_group_id = ai1.logical_group_id
        AND a1.analysis_id = ai1.analysis_id
        AND a1.protocol_id = p.protocol_id
        AND ep1.analysis_id = a1.analysis_id
        AND sof.composite_element_id = ep1.row_id
          AND sof.source_id is not null
        AND ga.alias = sof.source_id
       GROUP BY ga.gene) rh,
     (SELECT ga.gene, avg(ep1.mean) AS expression
       FROM rad.LogicalGroup lg, rad.AnalysisInput ai1, rad.Analysis a1,
            rad.ExpressionProfile ep1, rad.Protocol p,
            rad.ShortOligoFamily sof, ApiDB.GeneAlias ga
       WHERE p.name = 'R Expression Statistics'
        AND lg.name = 'RH (High Glucose) - RMA Quantifications'
        AND lg.logical_group_id = ai1.logical_group_id
        AND a1.analysis_id = ai1.analysis_id
        AND a1.protocol_id = p.protocol_id
        AND ep1.analysis_id = a1.analysis_id
        AND sof.composite_element_id = ep1.row_id
          AND sof.source_id is not null
        AND ga.alias = sof.source_id
       GROUP BY ga.gene) rh_high_glucose,
     (SELECT ga.gene, avg(ep1.mean) AS expression
       FROM rad.LogicalGroup lg, rad.AnalysisInput ai1, rad.Analysis a1,
            rad.ExpressionProfile ep1, rad.Protocol p,
            rad.ShortOligoFamily sof, ApiDB.GeneAlias ga
       WHERE p.name = 'R Expression Statistics'
        AND lg.name = 'RH (No Glucose) - RMA Quantifications'
        AND lg.logical_group_id = ai1.logical_group_id
        AND a1.analysis_id = ai1.analysis_id
        AND a1.protocol_id = p.protocol_id
        AND ep1.analysis_id = a1.analysis_id
        AND sof.composite_element_id = ep1.row_id
          AND sof.source_id is not null
        AND ga.alias = sof.source_id
       GROUP BY ga.gene) rh_no_glucose,
     (SELECT ga.gene,
              CASE WHEN avg(ep1.mean)/avg(ep2.mean) >= 1
                   THEN avg(ep1.mean)/avg(ep2.mean)
                   ELSE -1/(avg(ep1.mean)/avg(ep2.mean))
                   END AS fold_change
       FROM rad.LogicalGroup lg1, rad.AnalysisInput ai1, rad.Analysis a1,
            rad.ExpressionProfile ep1, rad.LogicalGroup lg2,
            rad.AnalysisInput ai2, rad.Analysis a2,
            rad.ExpressionProfile ep2,
            rad.Protocol p, rad.ShortOligoFamily sof,
            ApiDB.GeneAlias ga
       WHERE p.name = 'R Expression Statistics'
         AND lg1.name = 'RH (No Glucose) - RMA Quantifications'
         AND ai1.logical_group_id = lg1.logical_group_id
         AND a1.analysis_id = ai1.analysis_id
         AND a1.protocol_id = p.protocol_id
         AND ep1.analysis_id = a1.analysis_id
         AND sof.composite_element_id = ep1.row_id
         AND lg2.name = 'RH (High Glucose) - RMA Quantifications'
         AND ai2.logical_group_id = lg2.logical_group_id
         AND a2.analysis_id = ai2.analysis_id
         AND a2.protocol_id = p.protocol_id
         AND ep2.analysis_id = a2.analysis_id
         AND sof.composite_element_id = ep2.row_id
         AND sof.source_id is not null
         AND ga.alias = sof.source_id
        GROUP BY ga.gene) glucose,
     (SELECT ga.gene,
             CASE WHEN avg(ep1.mean)/avg(ep2.mean) >= 1
                            THEN avg(ep1.mean)/avg(ep2.mean)
                            ELSE -1/(avg(ep1.mean)/avg(ep2.mean))
                            END AS fold_change
       FROM rad.LogicalGroup lg1, rad.AnalysisInput ai1, rad.Analysis a1,
            rad.ExpressionProfile ep1, rad.LogicalGroup lg2,
            rad.AnalysisInput ai2, rad.Analysis a2,
            rad.ExpressionProfile ep2,
            rad.Protocol p, rad.ShortOligoFamily sof,
            ApiDB.GeneAlias ga
       WHERE p.name = 'R Expression Statistics'
         AND lg1.name = 'Pru - RMA Quantifications'
         AND ai1.logical_group_id = lg1.logical_group_id
         AND a1.analysis_id = ai1.analysis_id
         AND a1.protocol_id = p.protocol_id
         AND ep1.analysis_id = a1.analysis_id
         AND sof.composite_element_id = ep1.row_id
         AND lg2.name = 'VEG - RMA Quantifications'
         AND ai2.logical_group_id = lg2.logical_group_id
         AND a2.analysis_id = ai2.analysis_id
         AND a2.protocol_id = p.protocol_id
         AND ep2.analysis_id = a2.analysis_id
         AND sof.composite_element_id = ep2.row_id
         AND sof.source_id is not null
         AND ga.alias = sof.source_id
        GROUP BY ga.gene) pru_veg,
     (SELECT ga.gene,
             CASE WHEN avg(ep1.mean)/avg(ep2.mean) >= 1
                            THEN avg(ep1.mean)/avg(ep2.mean)
                            ELSE -1/(avg(ep1.mean)/avg(ep2.mean))
                            END AS fold_change
       FROM rad.LogicalGroup lg1, rad.AnalysisInput ai1, rad.Analysis a1,
            rad.ExpressionProfile ep1, rad.LogicalGroup lg2,
            rad.AnalysisInput ai2, rad.Analysis a2,
            rad.ExpressionProfile ep2,
            rad.Protocol p, rad.ShortOligoFamily sof,
            ApiDB.GeneAlias ga
       WHERE p.name = 'R Expression Statistics'
         AND lg1.name = 'Pru - RMA Quantifications'
         AND ai1.logical_group_id = lg1.logical_group_id
         AND a1.analysis_id = ai1.analysis_id
         AND a1.protocol_id = p.protocol_id
         AND ep1.analysis_id = a1.analysis_id
         AND sof.composite_element_id = ep1.row_id
         AND lg2.name = 'RH - RMA Quantifications'
         AND ai2.logical_group_id = lg2.logical_group_id
         AND a2.analysis_id = ai2.analysis_id
         AND a2.protocol_id = p.protocol_id
         AND ep2.analysis_id = a2.analysis_id
         AND sof.composite_element_id = ep2.row_id
         AND sof.source_id is not null
         AND ga.alias = sof.source_id
        GROUP BY ga.gene) pru_rh,
     (SELECT ga.gene,
             CASE WHEN avg(ep1.mean)/avg(ep2.mean) >= 1
                            THEN avg(ep1.mean)/avg(ep2.mean)
                            ELSE -1/(avg(ep1.mean)/avg(ep2.mean))
                            END AS fold_change
       FROM rad.LogicalGroup lg1, rad.AnalysisInput ai1, rad.Analysis a1,
            rad.ExpressionProfile ep1, rad.LogicalGroup lg2,
            rad.AnalysisInput ai2, rad.Analysis a2,
            rad.ExpressionProfile ep2,
            rad.Protocol p, rad.ShortOligoFamily sof,
            ApiDB.GeneAlias ga
       WHERE p.name = 'R Expression Statistics'
         AND lg1.name = 'VEG - RMA Quantifications'
         AND ai1.logical_group_id = lg1.logical_group_id
         AND a1.analysis_id = ai1.analysis_id
         AND a1.protocol_id = p.protocol_id
         AND ep1.analysis_id = a1.analysis_id
         AND sof.composite_element_id = ep1.row_id
         AND lg2.name = 'RH - RMA Quantifications'
         AND ai2.logical_group_id = lg2.logical_group_id
         AND a2.analysis_id = ai2.analysis_id
         AND a2.protocol_id = p.protocol_id
         AND ep2.analysis_id = a2.analysis_id
         AND sof.composite_element_id = ep2.row_id
         AND sof.source_id is not null
         AND ga.alias = sof.source_id
        GROUP BY ga.gene) veg_rh
WHERE gene.source_id = pru.gene(+)
  AND gene.source_id = veg.gene(+)
  AND gene.source_id = rh.gene(+)
  AND gene.source_id = rh_no_glucose.gene(+)
  AND gene.source_id = rh_high_glucose.gene(+)
  AND gene.source_id = glucose.gene(+)
  AND gene.source_id = pru_veg.gene(+)
  AND gene.source_id = pru_rh.gene(+)
  AND gene.source_id = veg_rh.gene(+);

GRANT SELECT ON apidb.ToxoExpn TO gus_r;

CREATE INDEX apidb.Toxo_sourceId ON apidb.ToxoExpn (source_id);

---------------------------
prompt ### DROP MATERIALIZED VIEW apidb.GeneProteinAttributes ###;
DROP MATERIALIZED VIEW apidb.GeneProteinAttributes;

prompt ### CREATE MATERIALIZED VIEW apidb.GeneProteinAttributes ###;
CREATE MATERIALIZED VIEW apidb.GeneProteinAttributes AS
SELECT gene.source_id,
       protein.tm_count, protein.molecular_weight,
       protein.isoelectric_point, protein.min_molecular_weight,
       protein.max_molecular_weight, protein.hydropathicity_gravy_score,
       protein.aromaticity_score, protein.cds_length, protein.protein_length,
       protein.ec_numbers
FROM (SELECT DISTINCT gene AS source_id from apidb.GeneId) gene,
     (SELECT gf.source_id, taf.na_feature_id, tas.molecular_weight,
             tas.length AS protein_length,
             greatest(taf.translation_start, taf.translation_stop)
             - least(taf.translation_start, taf.translation_stop) + 1 AS cds_length,
             asa.isoelectric_point,
             asa.min_molecular_weight, asa.max_molecular_weight,
             asa.hydropathicity_gravy_score,
             asa.aromaticity_score,
             NVL(transmembrane.tm_domains, 0) AS tm_count,
             ec.ec_numbers
      FROM  dots.GeneFeature gf, dots.Transcript t,
            dots.TranslatedAaFeature taf,
            dots.TranslatedAaSequence tas,
            apidb.AaSequenceAttribute asa,
            (SELECT aa_sequence_id, max(tm_domains) AS tm_domains
             FROM (SELECT tmaf.aa_sequence_id, COUNT(*) AS tm_domains
                   FROM dots.TransmembraneAaFeature tmaf, dots.AaLocation al
                   WHERE tmaf.aa_feature_id = al.aa_feature_id
                   GROUP BY tmaf.aa_sequence_id) tms
             GROUP BY tms.aa_sequence_id) transmembrane,
            (SELECT aa_sequence_id,
                    SUBSTR(apidb.tab_to_string(CAST(COLLECT(ec_number)
                                               AS apidb.varchartab), '; '),
                           1, 300)
                      AS ec_numbers
             FROM (SELECT DISTINCT asec.aa_sequence_id,
                          ec.ec_number || ' (' || ec.description || ')' AS ec_number
                   FROM dots.aaSequenceEnzymeClass asec, sres.enzymeClass ec
                   WHERE ec.enzyme_class_id = asec.enzyme_class_id)
             GROUP BY aa_sequence_id) ec
      WHERE gf.na_feature_id = t.parent_id
        AND t.na_feature_id = taf.na_feature_id
        AND taf.aa_sequence_id = tas.aa_sequence_id
        AND taf.aa_sequence_id = asa.aa_sequence_id
        AND tas.aa_sequence_id = transmembrane.aa_sequence_id(+)
        AND tas.aa_sequence_id = ec.aa_sequence_id(+)) protein
WHERE gene.source_id = protein.source_id(+);

GRANT SELECT ON apidb.GeneProteinAttributes TO gus_r;

CREATE INDEX apidb.GPA_sourceId ON apidb.GeneProteinAttributes (source_id);

---------------------------
prompt ### DROP/CREATE MATERIALIZED VIEW apidb.GenomicSequence1111 ###;
DROP MATERIALIZED VIEW apidb.GenomicSequence1111;

CREATE MATERIALIZED VIEW apidb.GenomicSequence1111 AS
  SELECT na_sequence_id, taxon_id, SUBSTR(source_id, 1, 40) AS source_id,
         LOWER(SUBSTR(source_id, 1, 40)) AS lowercase_source_id,
         a_count, c_count, g_count, t_count, length,
         SUBSTR(description, 1, 400) AS description,
         external_database_release_id, SUBSTR(chromosome, 1, 40) AS chromosome,
         chromosome_order_num, sequence_ontology_id
  FROM dots.ExternalNaSequence
  WHERE -- see both? use the VirtualSequence.
        source_id IN (SELECT source_id FROM dots.ExternalNaSequence
                     MINUS
                      SELECT source_id FROM dots.VirtualSequence)
UNION
  SELECT na_sequence_id, taxon_id, SUBSTR(source_id, 1, 40) AS source_id,
         LOWER(SUBSTR(source_id, 1, 40)) AS lowercase_source_id,
         a_count, c_count, g_count, t_count, length,
         SUBSTR(description, 1, 400) AS description,
         external_database_release_id, SUBSTR(chromosome, 1, 40) AS chromosome,
         chromosome_order_num, sequence_ontology_id
  FROM dots.VirtualSequence;

GRANT SELECT ON apidb.GenomicSequence1111 TO gus_r;

CREATE INDEX apidb.GS_sourceId1111 ON apidb.GenomicSequence1111 (source_id);
CREATE INDEX apidb.GS_lcSourceId1111 ON apidb.GenomicSequence1111 (lowercase_source_id);
CREATE INDEX apidb.GS_naSeqId1111 ON apidb.GenomicSequence1111 (na_sequence_id);

CREATE OR REPLACE SYNONYM apidb.GenomicSequence
                          FOR apidb.GenomicSequence1111;
---------------------------
prompt ### DROP MATERIALIZED VIEW apidb.GeneAttributes1111 ###;
DROP MATERIALIZED VIEW apidb.GeneAttributes1111;

prompt ### CREATE MATERIALIZED VIEW apidb.GeneAttributes1111 ###;
CREATE MATERIALIZED VIEW apidb.GeneAttributes1111 AS
SELECT CASE
         WHEN SUBSTR(tn.name, 1, 6) = 'Crypto'
           THEN 'CryptoDB'
         WHEN SUBSTR(tn.name, 1, 6) = 'Plasmo'
           THEN 'PlasmoDB'
         WHEN SUBSTR(tn.name, 1, 4) = 'Toxo'
           THEN 'ToxoDB'
         WHEN SUBSTR(tn.name, 1, 5) = 'Trich'
           THEN 'TrichDB'
         WHEN SUBSTR(tn.name, 1, 7) = 'Giardia'
           THEN 'GiardiaDB'
         ELSE 'ERROR: setting project in createBfmv.sql'
       END as project_id,
       gf.source_id,
       REPLACE(so.term_name, '_', ' ') AS gene_type,
       SUBSTR(gf.product, 1, 200) AS product,
       LEAST(nl.start_min, nl.end_max) AS start_min,
       GREATEST(nl.start_min, nl.end_max) AS end_max,
       sns.length AS transcript_length,
       GREATEST(0, least(nl.start_min, nl.end_max) - 5000)
           AS context_start,
       LEAST(sequence.length, greatest(nl.start_min, nl.end_max) + 5000)
           AS context_end,
       DECODE(nvl(nl.is_reversed, 0), 0, 'forward', 1, 'reverse',
              nl.is_reversed) AS strand,
       SUBSTR(sequence.source_id, 1, 50) AS sequence_id,
       SUBSTR(tn.name, 1, 40) AS organism,
       taxon.ncbi_tax_id,
       so_id, SUBSTR(so.term_name, 1, 150) AS so_term_name,
       SUBSTR(so.definition, 1, 150) AS so_term_definition,
       so.ontology_name, SUBSTR(so.so_version, 1, 7) AS so_version,
       SUBSTR(NVL(rt1.anticodon, rt2.anticodon), 1, 3) AS anticodon,
       protein.tm_count, protein.molecular_weight,
       protein.isoelectric_point, protein.min_molecular_weight,
       protein.max_molecular_weight, protein.hydropathicity_gravy_score,
       protein.aromaticity_score, protein.cds_length, protein.protein_length,
       protein.ec_numbers,
       ed.name AS external_db_name,
       SUBSTR(edr.version, 1, 10) AS external_db_version,
       exons.exon_count, SUBSTR(cmnt.comment_string, 1, 300) AS comment_string,
       SUBSTR(sequence.chromosome, 1, 20) AS chromosome,
       sequence.chromosome_order_num,
       go.annotated_go_component,
       go.annotated_go_function,
       go.annotated_go_process,
       go.predicted_go_component,
       go.predicted_go_function,
       go.predicted_go_process,
       DerisiExpn.derisi_max_level,
       DerisiExpn.derisi_max_pct,
       DerisiExpn.derisi_max_timing,
       DerisiExpn.derisi_min_timing,
       DerisiExpn.derisi_min_level,
       WinzelerExpn.winzeler_max_level,
       WinzelerExpn.winzeler_max_pct,
       WinzelerExpn.winzeler_max_timing,
       WinzelerExpn.winzeler_min_timing,
       WinzelerExpn.winzeler_min_level,
       ToxoExpn.pru, ToxoExpn.veg, ToxoExpn.rh, ToxoExpn.rh_high_glucose,
       ToxoExpn.rh_no_glucose, ToxoExpn.glucose_fold_change,
       ToxoExpn.pru_veg_fold_change, ToxoExpn.pru_rh_fold_change,
       ToxoExpn.veg_rh_fold_change
FROM dots.GeneFeature gf, dots.NaLocation nl,
     sres.SequenceOntology so, sres.Taxon,
     sres.TaxonName tn, dots.RnaType rt1, dots.RnaType rt2,
     dots.Transcript t,
     sres.ExternalDatabase ed,
     sres.ExternalDatabaseRelease edr,
     dots.SplicedNaSequence sns,
     apidb.GeneProteinAttributes protein,
     apidb.GeneGoAttributes go,
     apidb.DerisiExpn DerisiExpn,
     apidb.WinzelerExpn WinzelerExpn,
     apidb.ToxoExpn ToxoExpn,
     apidb.GenomicSequence sequence,
     (SELECT parent_id, count(*) AS exon_count
      FROM dots.ExonFeature
      GROUP BY parent_id) exons,
     (SELECT nfc.na_feature_id,
             MAX(DBMS_LOB.SUBSTR(nfc.comment_string, 300, 1))
               AS comment_string
      FROM dots.NaFeatureComment nfc
      GROUP BY nfc.na_feature_id) cmnt
WHERE gf.na_feature_id = nl.na_feature_id
  AND gf.na_sequence_id = sequence.na_sequence_id
  AND gf.sequence_ontology_id = so.sequence_ontology_id
  AND sequence.taxon_id = taxon.taxon_id
  AND sequence.taxon_id = tn.taxon_id
  AND tn.name_class = 'scientific name'
  AND gf.source_id = protein.source_id(+)
  AND gf.source_id = go.source_id(+)
  AND gf.source_id = DerisiExpn.source_id(+)
  AND gf.source_id = WinzelerExpn.source_id(+)
  AND gf.source_id = ToxoExpn.source_id(+)
  AND t.na_sequence_id = sns.na_sequence_id(+)
  AND gf.na_feature_id = t.parent_id
  AND t.na_feature_id = rt1.parent_id(+)
  AND gf.na_feature_id = rt2.parent_id(+)
  AND gf.external_database_release_id
       = edr.external_database_release_id
  AND edr.external_database_id = ed.external_database_id
  AND gf.na_feature_id = exons.parent_id(+)
  AND gf.na_feature_id = cmnt.na_feature_id(+)
  -- skip toxo predictions (except tRNAs)
  AND (tn.name != 'Toxoplasma gondii'
       OR ed.name NOT IN ('GLEAN predictions', 'GlimmerHMM predictions',
                          'TigrScan', /*'tRNAscan-SE',*/
                          'TwinScan predictions', 'TwinScanEt predictions'));

GRANT SELECT ON apidb.GeneAttributes1111 TO gus_r;

CREATE INDEX apidb.GeneAttr1111_sourceId
       ON apidb.GeneAttributes1111 (source_id);

CREATE INDEX apidb.GeneAttr1111_exon_ix
       ON apidb.GeneAttributes1111 (exon_count, source_id);

CREATE OR REPLACE SYNONYM apidb.GeneAttributes
                          FOR apidb.GeneAttributes1111;

---------------------------
-- sequences
---------------------------

prompt ### DROP MATERIALIZED VIEW apidb.SequenceAttributes1111 ###;
DROP MATERIALIZED VIEW apidb.SequenceAttributes1111;

prompt ### CREATE MATERIALIZED VIEW apidb.SequenceAttributes1111 ###;
CREATE MATERIALIZED VIEW apidb.SequenceAttributes1111 AS
SELECT CASE
         WHEN SUBSTR(tn.name, 1, 6) = 'Crypto'
           THEN 'CryptoDB'
         WHEN SUBSTR(tn.name, 1, 6) = 'Plasmo'
           THEN 'PlasmoDB'
         WHEN SUBSTR(tn.name, 1, 4) = 'Toxo'
           THEN 'ToxoDB'
         WHEN SUBSTR(tn.name, 1, 5) = 'Trich'
           THEN 'TrichDB'
         WHEN SUBSTR(tn.name, 1, 7) = 'Giardia'
           THEN 'GiardiaDB'
         ELSE 'ERROR: setting project in createBfmv.sql'
       END as project_id,
       SUBSTR(sequence.source_id, 1, 60) AS source_id, sequence.a_count,
       sequence.c_count, sequence.g_count, sequence.t_count,
       (sequence.length
        - (sequence.a_count + sequence.c_count + sequence.g_count + sequence.t_count))
         AS other_count,
       sequence.length,
       to_char((sequence.a_count + sequence.t_count) / sequence.length * 100, '99.99')
         AS at_percent,
       SUBSTR(tn.name, 1, 40) AS organism,
       taxon.ncbi_tax_id,
       SUBSTR(sequence.description, 1, 400) AS sequence_description,
       SUBSTR(genbank.genbank_accession, 1, 20) AS genbank_accession,
       SUBSTR(db.database_version, 1, 30) AS database_version, db.database_name,
       SUBSTR(sequence.chromosome, 1, 20) AS chromosome,
       sequence.chromosome_order_num
FROM sres.TaxonName tn, sres.Taxon, sres.SequenceOntology so,
     apidb.GenomicSequence sequence,
     (SELECT drns.na_sequence_id, max(dr.primary_identifier) AS genbank_accession
      FROM dots.dbrefNaSequence drns, sres.DbRef dr,
           sres.ExternalDatabaseRelease gb_edr, sres.ExternalDatabase gb_ed
      WHERE drns.db_ref_id = dr.db_ref_id
        AND dr.external_database_release_id
            = gb_edr.external_database_release_id
        AND gb_edr.external_database_id = gb_ed.external_database_id
        AND gb_ed.name = 'GenBank'
      GROUP BY drns.na_sequence_id) genbank,
     (SELECT edr.external_database_release_id,
             edr.version AS database_version, ed.name AS database_name
      FROM sres.ExternalDatabase ed, sres.ExternalDatabaseRelease edr
      WHERE edr.external_database_id = ed.external_database_id) db
WHERE sequence.taxon_id = tn.taxon_id(+)
  AND tn.name_class = 'scientific name'
  AND sequence.taxon_id = taxon.taxon_id
  AND sequence.sequence_ontology_id = so.sequence_ontology_id
  AND so.term_name IN ('chromosome', 'contig', 'supercontig')
  AND sequence.na_sequence_id = genbank.na_sequence_id(+)
  AND sequence.external_database_release_id = db.external_database_release_id(+)
;

GRANT SELECT ON apidb.SequenceAttributes1111 TO gus_r;

CREATE INDEX apidb.SeqAttr1111_source_id ON apidb.SequenceAttributes1111 (source_id);

CREATE OR REPLACE SYNONYM apidb.SequenceAttributes
                          FOR apidb.SequenceAttributes1111;
---------------------------
-- SNPs
---------------------------

prompt ### DROP MATERIALIZED VIEW apidb.SnpAttributes1111 ###;
DROP MATERIALIZED VIEW apidb.SnpAttributes1111;

prompt ### CREATE MATERIALIZED VIEW apidb.SnpAttributes1111 ###;
CREATE MATERIALIZED VIEW apidb.SnpAttributes1111 AS
SELECT CASE
         WHEN SUBSTR(tn.name, 1, 6) = 'Crypto'
           THEN 'CryptoDB'
         WHEN SUBSTR(tn.name, 1, 6) = 'Plasmo'
           THEN 'PlasmoDB'
         WHEN SUBSTR(tn.name, 1, 4) = 'Toxo'
           THEN 'ToxoDB'
         WHEN SUBSTR(tn.name, 1, 5) = 'Trich'
           THEN 'TrichDB'
         WHEN SUBSTR(tn.name, 1, 7) = 'Giardia'
           THEN 'GiardiaDB'
         ELSE 'ERROR: setting project in createBfmv.sql'
       END as project_id,
       snp.source_id AS source_id,
       CASE WHEN ed.name = 'Su SNPs' THEN 'NIH SNPs'
       ELSE ed.name END AS dataset,
       CASE WHEN ed.name = 'Su SNPs' THEN 'Su_SNPs'
       WHEN ed.name = 'Broad SNPs' THEN 'Broad_SNPs'
       WHEN ed.name = 'Sanger falciparum SNPs' THEN 'sangerItGhanaSnps'
       WHEN ed.name = 'Sanger reichenowi SNPs' THEN 'sangerReichenowiSnps'
       WHEN ed.name = 'PlasmoDB combined SNPs' THEN 'plasmoDbCombinedSnps'
       END AS dataset_hidden,
       sequence.na_sequence_id,
       sequence.source_id AS seq_source_id,
       snp_loc.start_min,
       SUBSTR(snp.reference_strain, 1, 200) AS reference_strain,
       SUBSTR(snp.reference_na, 1, 200) AS reference_na,
       DECODE(snp.is_coding, 0, 'no', 1, 'yes') AS is_coding,
       snp.position_in_CDS,
       snp.position_in_protein,
       SUBSTR(snp.reference_aa, 1, 200) AS reference_aa,
       DECODE(snp.has_nonsynonymous_allele, 0, 'no', 1, 'yes')
         AS has_nonsynonymous_allele,
       SUBSTR(snp.major_allele, 1, 40) AS major_allele,
       SUBSTR(snp.major_product, 1, 40) AS major_product,
       SUBSTR(snp.minor_allele, 1, 40) AS minor_allele,
       SUBSTR(snp.minor_product, 1, 40) AS minor_product,
       snp.major_allele_count, snp.minor_allele_count,
       SUBSTR(snp.strains, 1, 1000) AS strains,
       SUBSTR(snp.strains_revcomp, 1, 1000) AS strains_revcomp,
       gene_info.source_id AS gene_source_id,
       DECODE(gene_info.is_reversed, 0, 'forward', 1, 'reverse')
         AS gene_strand,
       SUBSTR(DBMS_LOB.SUBSTR(ns.sequence, 60, snp_loc.start_min - 60), 1, 60)
         AS lflank,
       SUBSTR(DBMS_LOB.SUBSTR(ns.sequence, 60, snp_loc.start_min + 1), 1, 60)
         AS rflank,
       SUBSTR(tn.name, 1, 40) AS organism,
       taxon.ncbi_tax_id,
       SUBSTR(sequence.chromosome, 1, 20) AS chromosome,
       sequence.chromosome_order_num
FROM dots.NaSequence ns, dots.SnpFeature snp, dots.NaLocation snp_loc,
     sres.ExternalDatabase ed, sres.ExternalDatabaseRelease edr, sres.Taxon,
     sres.TaxonName tn,
     apidb.GenomicSequence sequence,
     (SELECT gene.source_id, gene_loc.is_reversed, gene.na_feature_id
      FROM dots.GeneFeature gene, dots.NaLocation gene_loc
      WHERE gene.na_feature_id = gene_loc.na_feature_id) gene_info
WHERE edr.external_database_release_id = snp.external_database_release_id
  AND ed.external_database_id = edr.external_database_id
  AND ns.na_sequence_id = snp.na_sequence_id
  AND sequence.na_sequence_id = snp.na_sequence_id
  AND sequence.taxon_id = taxon.taxon_id
  AND sequence.taxon_id = tn.taxon_id
  AND tn.name_class = 'scientific name'
  AND snp_loc.na_feature_id = snp.na_feature_id
  AND gene_info.na_feature_id(+) = snp.parent_id;

GRANT SELECT ON apidb.SnpAttributes1111 TO gus_r;

CREATE INDEX apidb.SnpAttr1111_source_id ON apidb.SnpAttributes1111 (source_id);

CREATE INDEX apidb.Snp1111_Seq_ix
       ON apidb.SnpAttributes1111 (na_sequence_id, dataset, start_min);

CREATE OR REPLACE SYNONYM apidb.SnpAttributes
                          FOR apidb.SnpAttributes1111;
---------------------------
-- ORFs
---------------------------

prompt ### DROP MATERIALIZED VIEW apidb.OrfAttributes1111 ###;
DROP MATERIALIZED VIEW apidb.OrfAttributes1111;

prompt ### CREATE MATERIALIZED VIEW apidb.OrfAttributes1111 ###;
CREATE MATERIALIZED VIEW apidb.OrfAttributes1111 AS
SELECT CASE
         WHEN SUBSTR(tn.name, 1, 6) = 'Crypto'
           THEN 'CryptoDB'
         WHEN SUBSTR(tn.name, 1, 6) = 'Plasmo'
           THEN 'PlasmoDB'
         WHEN SUBSTR(tn.name, 1, 4) = 'Toxo'
           THEN 'ToxoDB'
         WHEN SUBSTR(tn.name, 1, 5) = 'Trich'
           THEN 'TrichDB'
         WHEN SUBSTR(tn.name, 1, 7) = 'Giardia'
           THEN 'GiardiaDB'
         ELSE 'ERROR: setting project in createBfmv.sql'
       END as project_id,
       SUBSTR(m.source_id, 1, 60) AS source_id,
       LOWER(SUBSTR(m.source_id, 1, 60)) AS lowercase_source_id,
       SUBSTR(tn.name, 1, 40) AS organism,
       taxon.ncbi_tax_id,
       SUBSTR(sequence.source_id, 1, 30) AS nas_id,
       tas.length,
       nl.start_min, nl.end_max, nl.is_reversed,
       SUBSTR(sequence.chromosome, 1, 20) AS chromosome,
       sequence.chromosome_order_num
FROM dots.Miscellaneous m, dots.TranslatedAaFeature taaf,
     dots.TranslatedAaSequence tas, sres.Taxon, sres.TaxonName tn,
     sres.SequenceOntology so, dots.NaLocation nl,
     apidb.GenomicSequence sequence
WHERE m.na_feature_id = taaf.na_feature_id
  AND taaf.aa_sequence_id = tas.aa_sequence_id
  AND sequence.na_sequence_id = m.na_sequence_id
  AND sequence.taxon_id = tn.taxon_id
  AND sequence.taxon_id = taxon.taxon_id
  AND m.sequence_ontology_id = so.sequence_ontology_id
  AND m.na_feature_id = nl.na_feature_id
  AND so.term_name = 'ORF'
  AND tn.name_class='scientific name';

GRANT SELECT ON apidb.OrfAttributes1111 TO gus_r;

CREATE INDEX apidb.OrfAttr1111_source_id ON apidb.OrfAttributes1111 (source_id);

CREATE OR REPLACE SYNONYM apidb.OrfAttributes
                        FOR apidb.OrfAttributes1111;
---------------------------
-- ESTs
---------------------------

prompt ### DROP MATERIALIZED VIEW apidb.EstAttributes1111 ###;
DROP MATERIALIZED VIEW apidb.EstAttributes1111;

prompt ### CREATE MATERIALIZED VIEW apidb.EstAttributes1111 ###;
CREATE MATERIALIZED VIEW apidb.EstAttributes1111 AS
SELECT CASE
         WHEN SUBSTR(tn.name, 1, 6) = 'Crypto'
           THEN 'CryptoDB'
         WHEN SUBSTR(tn.name, 1, 6) = 'Plasmo'
           THEN 'PlasmoDB'
         WHEN SUBSTR(tn.name, 1, 4) = 'Toxo'
           THEN 'ToxoDB'
         WHEN SUBSTR(tn.name, 1, 5) = 'Trich'
           THEN 'TrichDB'
         WHEN SUBSTR(tn.name, 1, 7) = 'Giardia'
           THEN 'GiardiaDB'
         ELSE 'ERROR: setting project in createBfmv.sql'
       END as project_id,
       ens.source_id,
       e.seq_primer AS primer,
       ens.a_count,
       ens.c_count,
       ens.g_count,
       ens.t_count,
       (length - (a_count + c_count + g_count + t_count)) AS other_count,
       ens.length,
       l.dbest_name,
       NVL(l.vector, 'unknown') AS vector,
       NVL(l.stage, 'unknown') AS stage,
       SUBSTR(tn.name, 1, 40) AS organism,
       taxon.ncbi_tax_id,
       ed.name AS external_db_name
FROM  dots.Est e, dots.ExternalNaSequence ens, dots.Library l,
      sres.Taxon, sres.TaxonName tn, sres.ExternalDatabase ed,
      sres.ExternalDatabaseRelease edr, sres.SequenceOntology so
WHERE e.na_sequence_id = ens.na_sequence_id
  AND e.library_id = l.library_id
  AND ens.taxon_id = tn.taxon_id
  AND ens.taxon_id = taxon.taxon_id
  AND tn.name_class='scientific name'
  AND ens.external_database_release_id = edr.external_database_release_id
  AND edr.external_database_id = ed.external_database_id
  AND ens.sequence_ontology_id = so.sequence_ontology_id
  AND so.term_name = 'EST';

GRANT SELECT ON apidb.EstAttributes1111 TO gus_r;

CREATE INDEX apidb.EstAttr1111_source_id ON apidb.EstAttributes1111 (source_id);

CREATE OR REPLACE SYNONYM apidb.EstAttributes
                          FOR apidb.EstAttributes1111;
---------------------------
-- array elements
---------------------------

prompt ### DROP MATERIALIZED VIEW apidb.ArrayElementAttributes1111 ###;
DROP MATERIALIZED VIEW apidb.ArrayElementAttributes1111;

prompt ### CREATE MATERIALIZED VIEW apidb.ArrayElementAttributes1111 ###;
CREATE MATERIALIZED VIEW apidb.ArrayElementAttributes1111 AS
SELECT CASE
         WHEN SUBSTR(tn.name, 1, 6) = 'Crypto'
           THEN 'CryptoDB'
         WHEN SUBSTR(tn.name, 1, 6) = 'Plasmo'
           THEN 'PlasmoDB'
         WHEN SUBSTR(tn.name, 1, 4) = 'Toxo'
           THEN 'ToxoDB'
         WHEN SUBSTR(tn.name, 1, 5) = 'Trich'
           THEN 'TrichDB'
         WHEN SUBSTR(tn.name, 1, 7) = 'Giardia'
           THEN 'GiardiaDB'
         ELSE 'ERROR: setting project in createBfmv.sql'
       END as project_id,
       ens.source_id, ed.name AS provider,
       SUBSTR(tn.name, 1, 40) AS organism,
       taxon.ncbi_tax_id
FROM sres.ExternalDatabase ed, sres.ExternalDatabaseRelease edr,
     dots.ExternalNASequence ens, sres.TaxonName tn, sres.Taxon
WHERE ens.external_database_release_id = edr.external_database_release_id
  AND edr.external_database_id = ed.external_database_id
  AND tn.taxon_id = ens.taxon_id
  AND tn.name_class = 'scientific name'
  AND taxon.taxon_id = ens.taxon_id
;

GRANT SELECT ON apidb.ArrayElementAttributes1111 TO gus_r;

CREATE INDEX apidb.AEAttr1111_source_id
ON apidb.ArrayElementAttributes1111 (source_id);

CREATE OR REPLACE SYNONYM apidb.ArrayElementAttributes
                          FOR apidb.ArrayElementAttributes1111;

---------------------------
-- EstAlignmentGeneSummary
---------------------------

prompt DROP/CREATE MATERIALIZED VIEW apidb.EstAlignmentGeneSummary1111;

DROP MATERIALIZED VIEW apidb.EstAlignmentGeneSummary1111;

CREATE MATERIALIZED VIEW apidb.EstAlignmentGeneSummary1111 AS
SELECT ba.blat_alignment_id, ba.query_na_sequence_id, e.accession,
         e.library_id, ba.query_taxon_id, ba.target_na_sequence_id,
         ba.target_taxon_id, ba.percent_identity, ba.is_consistent,
         ba.is_best_alignment, ba.is_reversed, ba.target_start, ba.target_end,
         sequence.source_id AS target_sequence_source_id,
         least(ba.target_end, ga.end_max)
         - greatest(ba.target_start, ga.start_min) + 1
           AS est_gene_overlap_length,
         ba.query_bases_aligned / (aseq.sequence_end - aseq.sequence_start + 1)
         * 100 AS percent_est_bases_aligned,
         ga.source_id AS gene
  FROM dots.blatalignment ba, dots.est e, dots.AssemblySequence aseq,
       apidb.GeneAttributes ga, apidb.GenomicSequence sequence,
       dots.NaSequence query_sequence, sres.SequenceOntology so
  WHERE e.na_sequence_id = ba.query_na_sequence_id
    AND aseq.na_sequence_id = ba.query_na_sequence_id
    AND sequence.na_sequence_id = ba.target_na_sequence_id
    AND ga.sequence_id = sequence.source_id
    AND least(ba.target_end, ga.end_max) - greatest(ba.target_start, ga.start_min) >= 0
    AND query_sequence.na_sequence_id = ba.query_na_sequence_id
    AND query_sequence.sequence_ontology_id = so.sequence_ontology_id
    AND so.term_name = 'EST'
    AND ba.target_na_sequence_id = sequence.na_sequence_id
UNION
  SELECT ba.blat_alignment_id, ba.query_na_sequence_id, e.accession,
         e.library_id, ba.query_taxon_id, ba.target_na_sequence_id,
         ba.target_taxon_id, ba.percent_identity, ba.is_consistent,
         ba.is_best_alignment, ba.is_reversed, ba.target_start, ba.target_end,
         sequence.source_id AS target_sequence_source_id,
         NULL AS est_gene_overlap_length,
         ba.query_bases_aligned / (aseq.sequence_end - aseq.sequence_start + 1)
         * 100 AS percent_est_bases_aligned,
         NULL AS gene
  FROM dots.blatalignment ba, dots.est e, dots.AssemblySequence aseq,
       dots.NaSequence sequence
  WHERE e.na_sequence_id = ba.query_na_sequence_id
    AND aseq.na_sequence_id = ba.query_na_sequence_id
    AND ba.target_na_sequence_id = sequence.na_sequence_id
    AND ba.blat_alignment_id IN
  ( -- set of blat_alignment_ids not in in first leg of UNION
    -- (because they overlap no genes)
    SELECT ba.blat_alignment_id
    FROM dots.BlatAlignment ba, dots.NaSequence query_sequence,
         sres.SequenceOntology so
    WHERE query_sequence.na_sequence_id = ba.query_na_sequence_id
      AND query_sequence.sequence_ontology_id = so.sequence_ontology_id
      AND so.term_name = 'EST'
  MINUS
    SELECT ba.blat_alignment_id
    FROM dots.blatalignment ba, dots.est e, dots.AssemblySequence aseq,
         apidb.GeneAttributes ga
    WHERE e.na_sequence_id = ba.query_na_sequence_id
      AND aseq.na_sequence_id = ba.query_na_sequence_id
      AND sequence.na_sequence_id = ba.target_na_sequence_id
      AND ga.sequence_id = sequence.source_id
      AND least(ba.target_end, ga.end_max)
          - greatest(ba.target_start, ga.start_min) >= 0
  );

GRANT SELECT ON apidb.EstAlignmentGeneSummary1111 TO gus_r;

CREATE INDEX apidb.EstSumm_libOverlap_ix1111
             ON apidb.EstAlignmentGeneSummary1111
                (library_id, percent_identity, is_consistent,
                 est_gene_overlap_length, percent_est_bases_aligned);

CREATE INDEX apidb.EstSumm_estSite_ix1111
             ON apidb.EstAlignmentGeneSummary1111
                (target_sequence_source_id, target_start, target_end,
                 library_id);

CREATE OR REPLACE SYNONYM apidb.EstAlignmentGeneSummary
                          FOR apidb.EstAlignmentGeneSummary1111;

---------------------------
-- cleanup
---------------------------

prompt These mviews appear superfluous (their names end in four digits but no synonym points at them).
prompt Consider carefully dropping them.

SELECT 'drop materialized view ' || owner || '.' || mview_name || ';' AS drops
FROM all_mviews
WHERE mview_name IN (SELECT mview_name
                     FROM all_mviews
                    MINUS
                     SELECT table_name
                     FROM all_synonyms)
  AND REGEXP_REPLACE(mview_name, '[0-9][0-9][0-9][0-9]', 'fournumbers')
      LIKE '%fournumbers';

exit
