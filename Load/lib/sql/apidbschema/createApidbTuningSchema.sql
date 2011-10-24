CREATE USER ApidbTuning
IDENTIFIED BY temppass
QUOTA UNLIMITED ON users 
QUOTA UNLIMITED ON gus
DEFAULT TABLESPACE users
TEMPORARY TABLESPACE temp;

GRANT GUS_R TO ApidbTuning;
GRANT GUS_W TO ApidbTuning;
GRANT CREATE VIEW TO ApidbTuning;
GRANT CREATE MATERIALIZED VIEW TO ApidbTuning;
GRANT CREATE TABLE TO ApidbTuning;
GRANT CREATE SYNONYM TO ApidbTuning;
GRANT CREATE SESSION TO ApidbTuning;
GRANT CREATE ANY INDEX TO ApidbTuning;
GRANT CREATE TRIGGER TO ApidbTuning;
GRANT CREATE ANY TRIGGER TO ApidbTuning;

GRANT REFERENCES ON dots.GeneFeature TO ApidbTuning;
GRANT REFERENCES ON dots.NaFeature TO ApidbTuning;
GRANT REFERENCES ON dots.NaFeatureNaGene TO ApidbTuning;
GRANT REFERENCES ON dots.AaSequenceImp TO ApidbTuning;
GRANT REFERENCES ON sres.Taxon TO ApidbTuning;

--BEGIN grant CTXSYS to GUS/APIDBTUNING schema owners
GRANT EXECUTE ON CTXSYS.CTX_CLS TO GUS_W;
GRANT EXECUTE ON CTXSYS.CTX_DDL TO GUS_W;
GRANT EXECUTE ON CTXSYS.CTX_DOC TO GUS_W;
GRANT EXECUTE ON CTXSYS.CTX_OUTPUT TO GUS_W;
GRANT EXECUTE ON CTXSYS.CTX_QUERY TO GUS_W;
GRANT EXECUTE ON CTXSYS.CTX_REPORT TO GUS_W;
GRANT EXECUTE ON CTXSYS.CTX_THES TO GUS_W;
GRANT EXECUTE ON CTXSYS.CTX_ULEXER TO GUS_W;
GRANT EXECUTE ON CTXSYS.DRUE TO GUS_W;
GRANT EXECUTE ON CTXSYS.CATINDEXMETHODS TO GUS_W;
GRANT CREATE INDEXTYPE to GUS_W;
GRANT CREATE CLUSTER to GUS_W;
GRANT CREATE DATABASE LINK to GUS_W;
GRANT CREATE JOB to GUS_W;
GRANT CREATE PROCEDURE to GUS_W;
GRANT CREATE SEQUENCE to GUS_W;
GRANT CREATE SESSION to GUS_W;
GRANT CREATE SYNONYM to GUS_W;
GRANT CREATE TABLE to GUS_W;
GRANT CREATE TRIGGER to GUS_W;
GRANT CREATE TYPE to GUS_W;
GRANT CREATE VIEW to GUS_W;
GRANT MANAGE SCHEDULER to GUS_W;
GRANT SELECT ANY DICTIONARY to GUS_W;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to ApidbTuning;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to core;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to dots;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to rad;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to study;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to sres;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to tess;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to prot;
--END grant CTXSYS to GUS/APIDBTUNING schema owners


-- tuningManager needs there to be a index named "ApidbTuning.blastp_text_ix"
--  (because OracleText needs it)
CREATE INDEX ApidbTuning.blastp_text_ix
ON core.tableinfo(superclass_table_id, table_id, database_id);

exit
