# This file documented how we can run SPARQL queries using ROBOT tool to query and preform quality checking
# on EuPathDB terminologies in OWL format. Current we are focusing on ClinEpi projects.

=============================================================
# Install ROBOT
=============================================================
Please following the instruction on the page:
	http://robot.obolibrary.org

Current for making queries working for cross ontologies, need to download robot.jar "v1.2.0-alpha-1" from page: https://github.com/ontodev/robot/releases


=============================================================
# Retrieve ontology files and SPARQL queries from Git repository
=============================================================
Git check out the files from https://github.com/VEuPathDB/ApiCommonData/Load/ontology and store under ontology directory
	git colon https://github.com/VEuPathDB/ApiCommonData.git

# VEuPathDB projects that used terminologies in OWL files

ClinEpi Projects
--------------------------------------------
Gates foundation projects:
- gates_avenir.owl
- gates_betterbirth.owl
- gates_elicit.owl
- gates_gamin.owl
- gates_ganc.owl
- gates_gems.owl
- gates_gems_huas.owl
- gates_gems1a.owl
- gates_gems1a_huas.owl
- gates_jilinde_awareness_survey.owl
- gates_jilinde_costing_survey.owl
- gates_jilinde_demand_creation_evaluation_questionnaire.owl
- gates_jilinde_healthcareprovider_cohort.owl
- gates_jilinde_pe_chv_cohort.owl
- gates_jilinde_prospective_cohort.owl
- gates_jilinde_retrospective_survey.owl
- gates_llineup.owl
- gates_maled.owl
- gates_mordor.owl
- gates_namibia.owl
- gates_nectar1.owl
- gates_pcs.owl
- gates_perch.owl
- gates_ppfp_choices_kenya_pp.owl
- gates_provide.owl
- gates_score_burundi.owl
- gates_score_five_country.owl
- gates_score_moz.owl
- gates_score_nig.owl
- gates_score_rwanda.owl
- gates_score_seasonal.owl
- gates_score_sm_cohort.owl
- gates_score_sm_crt.owl
- gates_score_zanzibar.owl
- gates_shine.owl
- gates_sip.owl
- gates_vida.owl
- gates_vida_hucs_gambia_mali.owl
- gates_vida_hucs_kenya.owl
- gates_washb_bangladesh.owl
- gates_washb_kenya.owl

General
- general_guatemala_oi_cohort.owl
- general_kalifabougou.owl
- general_promote.owl
- general_umsp.owl
- general_umsp_aggregate.owl

ICEMR projects:
- icemr_amazonia_brazil.owl
- icemr_amazonia_peru.owl
- icemr_india_behavior.owl
- icemr_india_cohort.owl
- icemr_india_cx.owl (cross-sectional study)
- icemr_india_daman.owl
- icemr_india_fever_surv.owl
- icemr_india_meghalaya.owl
- icemr_india_severe_malaria.owl
- icemr_llineup2.owl
- icemr_malawi.owl
- icemr_myanmar.owl
- icemr_prism.owl
- icemr_prism2.owl
- icemr_prism2_border_cohort.owl
- icemr_south_asia.owl
- icemr_southeast_asia.owl
- icemr_southern_africa.owl
- icemr_sub_saharan_africa_kenya_cohort.owl
- icemr_sw_pacific.owl
- icemr_west_africa.owl

Non-eda projects:
- general_covid19_india.owl
- general_hcq_non_randomized.owl
- general_nhs.owl

--------------------------------------------

Genomics projects:
- eupath_isa.owl
- protein_array.owl (ICEMR protein array)

MicrobiomeDB project:
- microbiome_eda.owl

PopBio project:
- popbio.owl

Study classification:
- general_classifications.owl

=============================================================

# SPARQL queries is under:
	ontology/SPARQL

# harmonization/web_display.owl
	includes all VEuPathDB projects

# harmonization/clinEpi_eda.owl
	includes all ClinEpi EDA projects


=============================================================
# Run SPARQL queries using robot tools
=============================================================

1. Open Terminal window for running command line

2. Change path to checked-out ontology directory

3. Create a directory ‘query_results’ under ontology for saving query results
	mkdir query_results

4. Following SPARQL queries can be ran using ROBOT tool, SPARQL queries are in SPARQL directory and query results will be saved in query_results directory. All output are in CSV format. We can set the output as other formats, like TSV, TTL, JSONLD, etc.

Notes: You need to change the PATH to the files or queries if you want to run the query and save results in the directory other than what specified here.



QUERY EXAMPLEs

=============================================================
# Retrieve terms used in VEuPathDB
=============================================================

# Terms with EUPATH prefix
robot query --use-graphs true --input ./harmonization/web_display.owl --query ./SPARQL/get_EuPathTermsWithSource.rq ./harmonization/EuPathTermsWithSource.csv

# All Terms
robot query --use-graphs true --input ./harmonization/web_display.owl --query ./SPARQL/get_termsWithSource.rq ./harmonization/termsWithSource.csv



=============================================================
# Individual ontology queries
=============================================================

—————————————————————————————————————————————————————————————————————————————
# RETRIEVAL QUERY

————————————————————————————————————————————————————————————
# Generate the file for adding/updating display order
#	get_displayOrder_lable_parentLabel.rq.rq
————————————————————————————————————————————————————————————
# ICEMR india
robot query --input ./ICEMR/india/icemr_indian.owl --query ./SPARQL/get_displayOrder_lable_parentLabel.rq ./query_results/ICEMR_indian_displayOrder.csv

# ICEMR southAsia
robot query --input ./ICEMR/south_asia/icemr_southAsia.owl --query ./SPARQL/get_displayOrder_lable_parentLabel.rq ./query_results/ICEMR_southAsia_displayOrder.csv

# ICEMR amazonia peru longitudinal study
robot query --input ./ICEMR/amazonia/icemr_amazoniaPeru_long.owl --query ./SPARQL/get_displayOrder_lable_parentLabel.rq ./query_results/ICEMR_amazoniaPeru_long_displayOrder.csv

# Gates GEMS1
robot query --input ./Gates/GEMS/gates_gems.owl --query ./SPARQL/get_displayOrder_lable_parentLabel.rq ./query_results/GEMS_displayOrder.csv

# Gates GEMS1a
robot query --input ./Gates/GEMS1A/gates_gems1a.owl --query ./SPARQL/get_displayOrder_lable_parentLabel.rq ./query_results/GEMS1a_displayOrder.csv

# Gates GEMS1 HUAS
robot query --input ./Gates/GEMS-HUAS/gates_gems_huas.owl --query ./SPARQL/get_displayOrder_lable_parentLabel.rq ./query_results/GEMS1_HUAS_displayOrder.csv



# Gates MALED
robot query --input ./Gates/MALED/gates_maled.owl --query ./SPARQL/get_displayOrder_lable_parentLabel.rq ./query_results/gates_MALED_displayOrder.csv

------------------------------------------------------------------------------------------
# Get variables and mapped ontology terms with labels	
#	get_variable_sourceID_label.rq
------------------------------------------------------------------------------------------
# Gates GEMS
robot query --input ./release/production/gates_gems.owl --query ./SPARQL/get_variable_sourceID_label.rq ./query_results/gates_gems_variableMappings.csv

------------------------------------------------------------------------------------------
# Get variables under specify root category, observation, household, sample, participant	
#	get_variable_sourceID_label.rq
------------------------------------------------------------------------------------------
# Gates GEMS
robot query --input ./release/production/gates_gems.owl --query ./SPARQL/get_variable_sourceID_label.rq ./query_results/gates_gems_variableMappings.csv

------------------------------------------------------------------------------------------
# Microbiome
robot query --input ./Microbiome/microbiome.owl --query ./SPARQL/get_variable_sourceID_label.rq ./query_results/microbiome_variableMappings.csv
------------------------------------------------------------------------------------------
# Rebuild missing project_conversion.csv file from project.owl file
#   owl_to_conversion.rq
------------------------------------------------------------------------------------------
# Gates MALED
robot query --use-graphs true --input ./Gates/MALED/gates_maled.owl --query ./SPARQL/owl_to_conversion.rq ./Gates/MALED/doc/MALED_conversion.csv
—————————————————————————————————————————————————————————————————————————————
# QC QUERY

————————————————————————————————————————————————————————————
# Check any label used for more than one ontology terms
#	QC_sameLabelForMultipleTerms.rq
————————————————————————————————————————————————————————————
# Gates GEMS1
robot query --input ./Gates/GEMS/gates_gems.owl --query ./SPARQL/QC_sameLabelForMultipleTerms.rq ./query_results/GEMS1_terms_sameLabelForMultipleTerms.csv


# Gates GEMS1 HUAS
robot query --input ./Gates/GEMS-HUAS/gates_gems_huas.owl --query ./SPARQL/QC_sameLabelForMultipleTerms.rq ./query_results/GEMS1_HUAS_terms_sameLabelForMultipleTerms.csv


————————————————————————————————————————————————————————————
# Check any leaf terms without corresponding variables in the dataset
#	QC_leaf_notVariable.rq
————————————————————————————————————————————————————————————
# Gates MALED
robot query --input ./Gates/MALED/gates_maled.owl --query ./SPARQL/QC_leaf_notVariable.rq ./query_results/MALED_leaf_terms_no_mapped_variables.csv


—————————————————————————————————————————————————————————————————————————————
# COUNT QUERY
————————————————————————————————————————————————————————————
# Count variable number under Household category
#	count_Household_variables.rq
————————————————————————————————————————————————————————————
# Gates MALED

robot query --input ./release/production/gates_maled.owl --query ./SPARQL/count_Household_variables.rq ./query_results/gates_maled_count_Household_variables.csv


————————————————————————————————————————————————————————————
# Count variable number under Participant category
#	count_Participant_variables.rq
————————————————————————————————————————————————————————————
# Gates MALED

robot query --input ./release/production/gates_maled.owl --query ./SPARQL/count_Participant_variables.rq ./query_results/gates_maled_count_Participant_variables.csv


————————————————————————————————————————————————————————————
# Count variable number under Observation category
#	count_Observation_variables.rq
————————————————————————————————————————————————————————————
# Gates MALED

robot query --input ./release/production/gates_maled.owl --query ./SPARQL/count_Observation_variables.rq ./query_results/gates_maled_count_Observation_variables.csv


————————————————————————————————————————————————————————————
# Count variable number under Sample category
#	count_Sample_variables.rq
————————————————————————————————————————————————————————————
# Gates MALED

robot query --input ./release/production/gates_maled.owl --query ./SPARQL/count_Sample_variables.rq ./query_results/gates_maled_count_Sample_variables.csv




=============================================================
# Multiple ontologies queries
=============================================================

—————————————————————————————————————————————————————————————————————————————
# RETRIEVAL QUERY

————————————————————————————————————————————————————————————
# List all terms with their parents and project sources
#	get_termWithParentAndSource.rq
————————————————————————————————————————————————————————————
# ClinEpi
robot query --use-graphs true --input ./harmonization/clinEpi.owl --query ./SPARQL/get_termWithParentAndSource.rq ./query_results/clinEpi_termsWithParentAndSource.csv


robot query --use-graphs true --input ./harmonization/clinEpi.owl --query ./SPARQL/get_termWithParentAndSource.rq ./query_results/clinEpi_termsWithParentAndSource.csv

# All projects
robot query --use-graphs true --input ./harmonization/web_display.owl --query ./SPARQL/get_termWithParentAndSource.rq ./query_results/web_display_termsWithParentAndSource.csv


————————————————————————————————————————————————————————————
# List terms which used as multifilter variables or values with their parents and project sources
#	get_multifilterWithSource.rq
————————————————————————————————————————————————————————————
# ClinEpi
robot query --use-graphs true --input ./harmonization/clinEpi.owl --query ./SPARQL/get_multifilterWithSource.rq ./query_results/clinEpi_multifilterWithSource.csv

————————————————————————————————————————————————————————————
# List terms used in which project(s)
#	get_termWithSourceGroupByID.rq
————————————————————————————————————————————————————————————
# ClinEpi
robot query --use-graphs true --input ./harmonization/clinEpi.owl --query ./SPARQL/get_termWithSourceGroupByID.rq ./query_results/clinEpi_termsWithSourceGroupByID.csv

————————————————————————————————————————————————————————————
# Retrieve terms which are not leaves of the tree (considering the terms as category), used to generate category OWL file  
#	get_nonLeaf_terms.rq
————————————————————————————————————————————————————————————
# ClinEpi projects
robot query --use-graphs true --input ./harmonization/clinEpi.owl --query ./SPARQL/get_nonLeaf_terms.rq ./query_results/clinEpi_categories.csv


—————————————————————————————————————————————————————————————————————————————
# QC QUERY

————————————————————————————————————————————————————————————
# Check any inconsistent labels used for same ontology term in multiple projects 
#	QC_termWithMultipleLabelsWithSource.rq
————————————————————————————————————————————————————————————
# ClinEpi
robot query --use-graphs true --input ./harmonization/clinEpi.owl --query ./SPARQL/QC_termWithMultipleLabelsWithSource.rq ./query_results/clinEpi_termWithMultipleLabelsWithSource.csv

# All projects
robot query --use-graphs true --input ./harmonization/web_display.owl --query ./SPARQL/QC_termWithMultipleLabelsWithSource.rq ./query_results/allProjects_termWithMultipleLabelsWithSource.csv


————————————————————————————————————————————————————————————
# Check any inconsistent labels used for same EuPathDB ontology term in multiple projects 
#	QC_EuPathTermWithMultipleLabelsWithSource.rq
————————————————————————————————————————————————————————————
# All projects
robot query --use-graphs true --input ./harmonization/web_display.owl --query ./SPARQL/QC_EuPathTermWithMultipleLabelsWithSource.rq ./query_results/allProjects_EuPathTermWithMultipleLabelsWithSource.csv


————————————————————————————————————————————————————————————
# Check any label used for more than one ontology terms
#	QC_sameLabelForMultipleTerms.rq
————————————————————————————————————————————————————————————
# ClinEpi
robot query --use-graphs true --input ./harmonization/clinEpi.owl --query ./SPARQL/QC_sameLabelForMultipleTerms.rq ./query_results/clinEpi_terms_sameLabelForMultipleTerms.csv

# All projects
robot query --use-graphs true --input ./harmonization/web_display.owl --query ./SPARQL/QC_sameLabelForMultipleTerms.rq ./query_results/allProjects_terms_sameLabelForMultipleTerms.csv



————————————————————————————————————————————————————————————
# Check any label used for more than one EuPath ontology terms
#	QC_sameLabelForMultipleEuPathTerms.rq
————————————————————————————————————————————————————————————
# All projects
robot query --use-graphs true --input ./harmonization/web_display.owl --query ./SPARQL/QC_sameLabelForMultipleEuPathTerms.rq ./query_results/allProjects_terms_sameLabelForMultipleEuPathTerms.csv


————————————————————————————————————————————————————————————
# Check any terms asserted under different categories in different projects
#	QC_termWithMultipleParents.rq
————————————————————————————————————————————————————————————
# ClinEpi
robot query --use-graphs true --input ./harmonization/clinEpi.owl --query ./SPARQL/QC_termWithMultipleParents.rq ./query_results/clinEpi_termsWithMultipleParents.csv


—————————————————————————————————————————————————————————————————————————————
# COUNT QUERY

————————————————————————————————————————————————————————————
# Number of distinct ontology classes(terms) 
#	count_uniqueClasses.rq
————————————————————————————————————————————————————————————
# All EuPathDB projects
robot query --use-graphs true --input ./harmonization/web_display.owl --query ./SPARQL/count_uniqueClasses.rq ./query_results/allProjects_termsCount.csv

————————————————————————————————————————————————————————————
# Number of distinct EuPathDB ontology classes(terms) 
#	count_uniqueEuPathClasses.rq
————————————————————————————————————————————————————————————
# All EuPathDB projects
robot query --use-graphs true --input ./harmonization/web_display.owl --query ./SPARQL/count_uniqueEuPathClasses.rq ./query_results/allProjects_EUPATHtermsCount.csv


————————————————————————————————————————————————————————————
# Number of datasets the ontology classes(terms) were used and indicate whether they have same labels 
#	count_datasetsOfTerms.rq
————————————————————————————————————————————————————————————
# ClinEpi
robot query --use-graphs true --input ./harmonization/clinEpi.owl --query ./SPARQL/count_datasetsOfTerms.rq ./query_results/clinEpi_count_datasetsOfTerms.csv

# All EuPathDB projects
robot query --use-graphs true --input ./harmonization/web_display.owl --query ./SPARQL/count_datasetsOfTerms.rq ./query_results/allProjects_count_datasetsOfTerms.csv


————————————————————————————————————————————————————————————
# Number of datasets the ontology classes(terms) were used including term label, parent label, term type, category, category assigned in the ontology and also indicate whether they have same labels 
#	count_datasetsOfTermsByCategory.rq
————————————————————————————————————————————————————————————
# ClinEpi
robot query --use-graphs true --input ./harmonization/clinEpi.owl --query ./SPARQL/count_datasetsOfTermsByCategory.rq ./query_results/clinEpi_count_datasetsOfTerms.csv


—————————————————————————————————————————————————————————————————————————————
# UPDATE QUERY

————————————————————————————————————————————————————————————

————————————————————————————————————————————————————————————
UPDATE category annotation setting values based on category of terms asserted in the
Ontology hierarchy 
————————————————————————————————————————————————————————————
robot query --input ./Gates/VIDA/gates_vida.owl \
	--update ./SPARQL/update_category_participant.rq \
	--update ./SPARQL/update_category_household.rq \
	--update ./SPARQL/update_category_observation.rq \
	--update ./SPARQL/update_category_sample.rq \
	--update ./SPARQL/update_category_insectSample.rq \
	--update ./SPARQL/update_category_entomology.rq \
 	--output ./Gates/VIDA/gates_vida_new.owl







—————————————————————————————————————————————————————————————————————————————
# SOLR QUERY

————————————————————————————————————————————————————————————

————————————————————————————————————————————————————————————
# Get term information for solr collection 	
	get_solr_collection.rq
————————————————————————————————————————————————————————————
# All EuPathDB projects
robot query  --use-graphs true --input ./harmonization/web_display.owl --query ./SPARQL/get_solr_collection.rq ./query_results/solr_collection.csv

