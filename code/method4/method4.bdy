create or replace package body method4 as

procedure set_temp_object_id(p_temp_object_id varchar2) is
begin
	dbms_session.set_context('method4_context', 'temp_object_id', p_temp_object_id);
end;

procedure set_owner(p_owner varchar2) is
begin
	dbms_session.set_context('method4_context', 'owner', p_owner);
end;

procedure set_table_name(p_table_name varchar2) is
begin
	dbms_session.set_context('method4_context', 'table_name', p_table_name);
end;

end method4;
/
