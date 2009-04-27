CREATE USER ApiDB
IDENTIFIED BY temppass
QUOTA UNLIMITED ON users 
QUOTA UNLIMITED ON gus
DEFAULT TABLESPACE gus
TEMPORARY TABLESPACE temp;

GRANT SCHEMA_OWNER TO ApiDB;
GRANT GUS_R TO ApiDB;
GRANT GUS_W TO ApiDB;
GRANT CREATE VIEW TO ApiDB;
GRANT CREATE MATERIALIZED VIEW TO ApiDB;
GRANT CREATE TABLE TO ApiDB;
GRANT CREATE SYNONYM TO ApiDB;
GRANT CREATE SESSION TO ApiDB;
GRANT CREATE ANY INDEX TO ApiDB;
GRANT CREATE TRIGGER TO ApiDB;
GRANT CREATE ANY TRIGGER TO ApiDB;

GRANT REFERENCES ON dots.GeneFeature TO ApiDB;
GRANT REFERENCES ON dots.NaFeature TO ApiDB;
GRANT REFERENCES ON dots.NaFeatureNaGene TO ApiDB;
GRANT REFERENCES ON dots.AaSequenceImp TO ApiDB;
GRANT REFERENCES ON sres.Taxon TO ApiDB;

INSERT INTO core.DatabaseInfo
   (database_id, name, description, modification_date, user_read, user_write,
    group_read, group_write, other_read, other_write, row_user_id,
    row_group_id, row_project_id, row_alg_invocation_id)
SELECT core.databaseinfo_sq.nextval, 'ApiDB',
       'Application-specific data for the ApiDB websites', sysdate,
       1, 1, 1, 1, 1, 1, 1, 1, p.project_id, 0
FROM dual, (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p
WHERE lower('ApiDB') NOT IN (SELECT lower(name) FROM core.DatabaseInfo);

--BEGIN grant CTXSYS to GUS/APIDB schema owners
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
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to apidb;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to core;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to dots;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to rad;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to study;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to sres;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to tess;
GRANT CONNECT, RESOURCE, CTXAPP, GUS_W to prot;
--END grant CTXSYS to GUS/APIDB schema owners


-- tuningManager needs there to be a index named "apidb.blastp_text_ix"
--  (because OracleText needs it)
CREATE INDEX apidb.blastp_text_ix
ON core.tableinfo(superclass_table_id, table_id, database_id);

exit
