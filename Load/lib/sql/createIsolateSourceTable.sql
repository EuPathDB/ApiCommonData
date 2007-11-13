DROP TABLE ApiDB.IsolateSource;

CREATE TABLE ApiDB.IsolateSource (
  NA_FEATURE_ID                NUMBER(10) not null,
  NA_SEQUENCE_ID               NUMBER(10) not null,
  PARENT_ID                    NUMBER(10) not null,
  COUNTRY                      VARCHAR(50),
  EXTERNAL_DATABASE_RELEASE_ID NUMBER(10),
	MODIFICATION_DATE 	         DATE, 
	USER_READ 	                 NUMBER(1), 
	USER_WRITE 	                 NUMBER(1),
	GROUP_READ 	                 NUMBER(1),	
	GROUP_WRITE                  NUMBER(1), 
	OTHER_READ 	                 NUMBER(1),
	OTHER_WRITE                  NUMBER(1), 	
	ROW_USER_ID                  NUMBER(12), 
	ROW_GROUP_ID 	               NUMBER(4), 	
	ROW_PROJECT_ID 	             NUMBER(4), 	
	ROW_ALG_INVOCATION_ID 	     NUMBER(12),
CONSTRAINT ISOLATE_ID_PK  primary key (NA_FEATURE_ID) ENABLE,
CONSTRAINT isolate_source_fk foreign key (PARENT_ID)
references DOTS.NAFEATUREIMP (NA_FEATURE_ID) ENABLE
);

GRANT INSERT, SELECT, UPDATE, DELETE ON apidb.IsolateSource TO gus_w;
GRANT SELECT ON apidb.IsolateSource TO gus_r;

------------------------------------------------------------------------------

INSERT INTO core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable, 
     modification_date, user_read, user_write, group_read, group_write, 
     other_read, other_write, row_user_id, row_group_id, row_project_id, 
     row_alg_invocation_id)
SELECT core.tableinfo_sq.nextval, 'IsolateSource',
       'Standard', 'db_ref_aa_feature_id',
       d.database_id, 0, 0, '', '', 1,sysdate, 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM dual,
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE lower(name) = 'apidb') d
WHERE 'IsolateSource' NOT IN (SELECT name FROM core.TableInfo
                                    WHERE database_id = d.database_id);

------------------------------------------------------------------------------
exit;
