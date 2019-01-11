create or replace trigger method5.m5_database_trg
before insert or update
on method5.m5_database
for each row
--Purpose: Automatically set M5_DEFAULT_CONNECT_STRING, CHANGED_BY, and CHANGED_DATE if they were not set.
--  You may want to customize the M5_DEFAULT_CONNECT_STRING to match your environment's connection policies.
declare
	pragma autonomous_transaction;
begin
	--If the default connect string is changed, drop any relevant host and database links.
	--Dropping the link will force it to refresh with the new connect string.
	if updating('M5_DEFAULT_CONNECT_STRING') then
		method5.method5_admin.drop_m5_db_link_for_m5('M5_'||:new.database_name);
		method5.method5_admin.drop_m5_db_link_for_m5('M5_'||:new.host_name);
	end if;

	if inserting then
		if :new.m5_default_connect_string is null then
			--
			-- BEGIN CUSTOMIZE HERE
			--
			--You may want to use an existing TNSNAMES.ORA file as a guide for how to populate this column
			--(for each entry, use the text after the first equal sign).
			--You may want to remove spaces and newlines, it is easier to compare the strings without them.
			--It is OK if not all CONNECT_STRING values are 100% perfect, problems can be manually adjusted later if necessary.
			:new.m5_default_connect_string :=
				lower(replace(replace(
						'(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host_name)(PORT=&1))(CONNECT_DATA=(SERVICE_NAME=$instance_name))) '
						--SID may work better for some organizations:
						--'(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host_name)(PORT=&1))(CONNECT_DATA=(SID=$instance_name))) ',
					,'$instance_name', :new.instance_name)
					,'$host_name', :new.host_name)
				);
			--
			-- END CUSTOMIZE HERE
			--
		end if;

		if :new.changed_by is null then
			--Get the user from APEX if it was used.
			:new.changed_by := 	coalesce(
				sys_context('APEX$SESSION','app_user')
				,regexp_substr(sys_context('userenv','client_identifier'),'^[^:]*')
				,sys_context('userenv','session_user'));
		end if;

		if :new.changed_date is null then
			:new.changed_date := sysdate;
		end if;
	end if;

	if not updating('CHANGED_BY') then
		:new.changed_by := 	coalesce(
			--Get the user from APEX if it was used.
			sys_context('APEX$SESSION','app_user')
			,regexp_substr(sys_context('userenv','client_identifier'),'^[^:]*')
			,sys_context('userenv','session_user'));
	end if;
	if not updating('CHANGED_DATE') then
		:new.changed_date := sysdate;
	end if;
end m5_database_trg;
/
