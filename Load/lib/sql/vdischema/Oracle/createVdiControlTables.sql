-- This file is parameterized by a LIFECYCLE_CAMPUS suffix (eg qa_n) to append to 'VDI_CONTROL_' in order to form the target VDI control schema
-- In Oracle, that schema must be first created by DBA
--   CREATE USER &1
--   IDENTIFIED BY "<password>"
--   QUOTA UNLIMITED ON users;

CREATE TABLE VDI_CONTROL_&1..dataset (
  dataset_id   VARCHAR2(32)     PRIMARY KEY NOT NULL
, owner        NUMBER                   NOT NULL
, type_name    VARCHAR2(64)             NOT NULL
, type_version VARCHAR2(64)             NOT NULL
, is_deleted   NUMBER       DEFAULT 0   NOT NULL
);

CREATE TABLE VDI_CONTROL_&1..sync_control (
  dataset_id         VARCHAR2(32)                 NOT NULL
, shares_update_time TIMESTAMP WITH TIME ZONE NOT NULL
, data_update_time   TIMESTAMP WITH TIME ZONE NOT NULL
, meta_update_time   TIMESTAMP WITH TIME ZONE NOT NULL
, FOREIGN KEY (dataset_id) REFERENCES VDI_CONTROL_&1..dataset (dataset_id)
);

CREATE TABLE VDI_CONTROL_&1..dataset_install_message (
  dataset_id   VARCHAR2(32)     NOT NULL
, install_type VARCHAR2(64) NOT NULL
, status       VARCHAR2(64) NOT NULL
, message      CLOB
, FOREIGN KEY (dataset_id) REFERENCES VDI_CONTROL_&1..dataset (dataset_id)
);

CREATE TABLE VDI_CONTROL_&1..dataset_visibility (
  dataset_id VARCHAR2(32) NOT NULL
, user_id    NUMBER   NOT NULL
, FOREIGN KEY (dataset_id) REFERENCES VDI_CONTROL_&1..dataset (dataset_id)
);

CREATE TABLE VDI_CONTROL_&1..dataset_project (
  dataset_id VARCHAR2(32)     NOT NULL
, project_id VARCHAR2(64) NOT NULL
, FOREIGN KEY (dataset_id) REFERENCES VDI_CONTROL_&1..dataset (dataset_id)
);

GRANT SELECT ON VDI_CONTROL_&1..dataset                 TO gus_r;
GRANT SELECT ON VDI_CONTROL_&1..sync_control            TO gus_r;
GRANT SELECT ON VDI_CONTROL_&1..dataset_install_message TO gus_r;
GRANT SELECT ON VDI_CONTROL_&1..dataset_visibility      TO gus_r;
GRANT SELECT ON VDI_CONTROL_&1..dataset_project         TO gus_r;

GRANT DELETE, INSERT, SELECT, UPDATE ON VDI_CONTROL_&1..dataset                 TO gus_w;
GRANT DELETE, INSERT, SELECT, UPDATE ON VDI_CONTROL_&1..sync_control            TO gus_w;
GRANT DELETE, INSERT, SELECT, UPDATE ON VDI_CONTROL_&1..dataset_install_message TO gus_w;
GRANT DELETE, INSERT, SELECT, UPDATE ON VDI_CONTROL_&1..dataset_visibility      TO gus_w;
GRANT DELETE, INSERT, SELECT, UPDATE ON VDI_CONTROL_&1..dataset_project         TO gus_w;

GRANT REFERENCES ON VDI_CONTROL_&1..dataset TO VDI_DATASETS_&1;

exit;
