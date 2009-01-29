create or replace function apidb.searchable_comment_text (p_comment_id number)
return clob
is
    smooshed clob;
begin
    select c.headline || '|' || c.content || '|' || 
           u.first_name || ' ' || u.last_name || '(' || u.organization || ')' into smooshed
    from comments2.comments c, userlogins3.users u
    where c.email = u.email(+)
      and c.comment_id = p_comment_id;
    return smooshed;
end;
/

grant execute on apidb.searchable_comment_text to public;

drop table apidb.TextSearchableComment;
create table apidb.TextSearchableComment as
select comment_id, stable_id as source_id, project_name as project_id, organism,
       apidb.searchable_comment_text(comment_id) as content
from comments2.comments;

grant select,insert,update,delete on apidb.TextSearchableComment to public;

create index apidb.comments_text_ix
on apidb.TextSearchableComment(content)
indextype is ctxsys.context
parameters('DATASTORE CTXSYS.DEFAULT_DATASTORE SYNC (ON COMMIT)');

create or replace trigger comments2.comments_insert
after insert on comments2.comments
begin
  insert into apidb.TextSearchableComment (comment_id, source_id, project_id, organism, content)
  select comment_id, stable_id, project_name, organism,
          apidb.searchable_comment_text(comment_id)
  from comments2.comments
  where comment_id not in (select comment_id from apidb.TextSearchableComment);
end;
/

-- this update trigger won't do the right thing if the comment_id itself is updated
create or replace trigger comments2.comments_update
after update on comments2.comments
for each row
begin
  update apidb.TextSearchableComment
  set content = apidb.searchable_comment_text(:new.comment_id)
  where comment_id = :new.comment_id;
end;
/

create or replace trigger comments2.comments_delete
after delete on comments2.comments
begin
  delete from apidb.TextSearchableComment
  where comment_id not in (select comment_id from comments2.comments);
end;
/
