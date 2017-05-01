create or replace package statement_feedback is
--Copyright (C) 2015 Jon Heller.  This program is licensed under the LGPLv3.

procedure get_feedback_message(
	p_tokens                   in token_table,
	p_rowcount                 in number,
	p_success_message         out varchar2,
	p_compile_warning_message out varchar2
);

procedure get_feedback_message(
	p_command_name             in varchar2,
	p_rowcount                 in number,
	p_success_message         out varchar2,
	p_compile_warning_message out varchar2
);

/*

== Purpose ==

Generate a feedback message for a successful SQL or PL/SQL statement, similar to SQL*Plus.

This can help when processing dynamic SQL and PL/SQL statements.  Here are some examples:
- Table created
- Table altered.
- Table dropped.
- PL/SQL procedure successfully completed.
- 5 rows inserted.
- Warning: Package Body altered with compilation errors.
- no rows selected


== Example ==

--Test Statement_Feedback.
declare
	v_statement varchar2(32767);
	v_success_message varchar2(100);
	v_compile_warning_message varchar2(100);
	v_has_compile_warning boolean := false;

	v_success_with_compilation_err exception;
	pragma exception_init(v_success_with_compilation_err, -24344);

begin
	--Test statement.
	v_statement := 'create table some_test_table1(a number)';

	--Execute the statement and catch compile warning errors.
	begin
		execute immediate v_statement;
	exception when v_success_with_compilation_err then
		v_has_compile_warning := true;
	end;

	--Get the feedback message.
	statement_feedback.get_feedback_message(
		p_statement => v_statement,
		p_rowcount => sql%rowcount,
		p_success_message => v_success_message,
		p_compile_warning_message => v_compile_warning_message
	);

	--Display the success message or warning message
	if v_has_compile_warning then
		dbms_output.put_line(v_compile_warning_message);
	else
		dbms_output.put_line(v_success_message);
	end if;
end;


== Parameters ==

p_statement - The SQL or PL/SQL statement that was executed successfully.
              Most of the messages are obvious.  Only the SELECT message is
              unusual - this package will not display the results, only a
              message like "no rows selected".
  OR
p_command_name - The V$SQLCOMMAND.COMMAND_NAME of the statement.  This value
                 can be retrieved from statement_classifier.classify.

p_rowcount - The number of rows modified by the statement.
             If it does not apply, pass in NULL.
p_success_message - The message SQL*Plus would display if the statement was successful.
p_compile_warning_message - The message SQL*Plus would display if a PL/SQL object compiled with errors.
                            Catch "ORA-24344: success with compilation error" to detect this situation.


*/

end;
/
create or replace package body statement_feedback is

--------------------------------------------------------------------------------
procedure get_feedback_message(
		p_command_name in varchar2,
		p_rowcount in number,
		p_success_message out varchar2,
		p_compile_warning_message out varchar2
) is
begin
	--If classification failed then return NULLs.
	if p_command_name is null then
		null;
	--If classification succeeded, set the outputs.
	else
		--These are one-offs and exceptions.
		--Note that some of these seem to have extra spaces because the command names
		--do not always perfectly line up with the real syntax.

		if p_command_name = 'ADMINISTER KEY MANAGEMENT' then
			p_success_message := 'keystore altered.';
		elsif p_command_name = 'ALTER DISK GROUP' then
			p_success_message := 'Diskgroup altered.';
		elsif p_command_name = 'ALTER INMEMORY JOIN GROUP' then
			p_success_message := 'Join group altered.';
		elsif p_command_name = 'ALTER LOCKDOWN PROFILE' then
			p_success_message := 'Lockdown Profile altered.';
		elsif p_command_name = 'ALTER MATERIALIZED VIEW ' then
			p_success_message := 'Materialized view altered.';
		elsif p_command_name = 'ALTER TABLESPACE SET' then
			--TODO: I'm not 100% sure about this.
			p_success_message := 'Tablespace altered.';
		elsif p_command_name = 'ANALYZE CLUSTER' then
			p_success_message := 'Cluster analyzed.';
		elsif p_command_name = 'ANALYZE INDEX' then
			p_success_message := 'Index analyzed.';
		elsif p_command_name = 'ANALYZE TABLE' then
			p_success_message := 'Table analyzed.';
		elsif p_command_name = 'ASSOCIATE STATISTICS' then
			p_success_message := 'Statistics associated.';
		elsif p_command_name = 'AUDIT OBJECT' then
			p_success_message := 'Audit succeeded.';
		elsif p_command_name = 'CALL METHOD' then
			p_success_message := 'Call completed.';
		elsif p_command_name = 'COMMENT' then
			p_success_message := 'Comment created.';
		elsif p_command_name = 'COMMIT' then
			p_success_message := 'Commit complete.';
		elsif p_command_name = 'CREATE DISK GROUP' then
			p_success_message := 'Diskgroup created.';
		elsif p_command_name = 'CREATE INMEMORY JOIN GROUP' then
			p_success_message := 'Join group created.';
		elsif p_command_name = 'CREATE LOCKDOWN PROFILE' then
			p_success_message := 'Lockdown Profile created.';
		elsif p_command_name = 'CREATE MATERIALIZED VIEW ' then
			p_success_message := 'Materialized view created.';
		elsif p_command_name = 'CREATE PFILE' then
			p_success_message := 'File created.';
		elsif p_command_name = 'CREATE SPFILE' then
			p_success_message := 'File created.';
		elsif p_command_name = 'CREATE TABLESPACE SET' then
			p_success_message := 'Tablespace created.';
		elsif p_command_name = 'DELETE' then
			if p_rowcount is null then
				p_success_message := 'ERROR: Unknown number of rows deleted.';
			elsif p_rowcount = 1 then
				p_success_message := '1 row deleted.';
			else
				p_success_message := p_rowcount||' rows deleted.';
			end if;
		elsif p_command_name = 'DISASSOCIATE STATISTICS' then
			p_success_message := 'Statistics disassociated.';
		elsif p_command_name = 'DROP AUDIT POLICY' then
			p_success_message := 'Audit Policy dropped.';
		elsif p_command_name = 'DROP DISK GROUP' then
			p_success_message := 'Diskgroup dropped.';
		elsif p_command_name = 'DROP INMEMORY JOIN GROUP' then
			p_success_message := 'Join group deleted.';
		elsif p_command_name = 'DROP LOCKDOWN PROFILE' then
			p_success_message := 'Lockdown Profile dropped.';
		elsif p_command_name = 'DROP MATERIALIZED VIEW  LOG' then
			p_success_message := 'Materialized view log dropped.';
		elsif p_command_name = 'DROP MATERIALIZED VIEW ' then
			p_success_message := 'Materialized view dropped.';
		elsif p_command_name = 'DROP TABLESPACE SET' then
			--TODO: I'm not 100% sure about this.
			p_success_message := 'Tablespace dropped.';
		elsif p_command_name = 'EXPLAIN' then
			p_success_message := 'Explained.';
		elsif p_command_name = 'FLASHBACK DATABASE' then
			p_success_message := 'Flashback complete.';
		elsif p_command_name = 'FLASHBACK TABLE' then
			p_success_message := 'Flashback complete.';
		elsif p_command_name = 'GRANT OBJECT' then
			p_success_message := 'Grant succeeded.';
		elsif p_command_name = 'INSERT' then
			if p_rowcount is null then
				p_success_message := 'ERROR: Unknown number of rows created.';
			elsif p_rowcount = 1 then
				p_success_message := '1 row created.';
			else
				p_success_message := p_rowcount||' rows created.';
			end if;
		elsif p_command_name = 'LOCK TABLE' then
			p_success_message := 'Table(s) Locked.';
		elsif p_command_name = 'NOAUDIT OBJECT' then
			p_success_message := 'Noaudit succeeded.';
		elsif p_command_name = 'PL/SQL EXECUTE' then
			p_success_message := 'PL/SQL procedure successfully completed.';
		elsif p_command_name = 'PURGE DBA RECYCLEBIN' then
			p_success_message := 'DBA Recyclebin purged.';
		elsif p_command_name = 'PURGE INDEX' then
			p_success_message := 'Index purged.';
		elsif p_command_name = 'PURGE TABLE' then
			p_success_message := 'Table purged.';
		elsif p_command_name = 'PURGE TABLESPACE' then
			p_success_message := 'Tablespace purged.';
		elsif p_command_name = 'PURGE TABLESPACE SET' then
			--TODO: I'm not 100% sure about this.
			p_success_message := 'Tablespace purged.';
		elsif p_command_name = 'PURGE USER RECYCLEBIN' then
			p_success_message := 'Recyclebin purged.';
		elsif p_command_name = 'RENAME' then
			p_success_message := 'Table renamed.';
		elsif p_command_name = 'REVOKE OBJECT' then
			p_success_message := 'Revoke succeeded.';
		elsif p_command_name = 'ROLLBACK' then
			p_success_message := 'Rollback complete.';
		elsif p_command_name = 'SAVEPOINT' then
			p_success_message := 'Savepoint created.';
		elsif p_command_name = 'SELECT' then
			if p_rowcount is null then
				p_success_message := 'ERROR: Unknown number of rows selected.';
			elsif p_rowcount = 0 then
				p_success_message := 'no rows selected';
			elsif p_rowcount = 1 then
				p_success_message := '1 row selected.';
			else
				p_success_message := p_rowcount||' rows selected.';
			end if;
		elsif p_command_name = 'SET CONSTRAINTS' then
			p_success_message := 'Constraint set.';
		elsif p_command_name = 'SET ROLE' then
			p_success_message := 'Role set.';
		elsif p_command_name = 'SET TRANSACTION' then
			p_success_message := 'Transaction set.';
		elsif p_command_name = 'TRUNCATE CLUSTER' then
			p_success_message := 'Cluster truncated.';
		elsif p_command_name = 'TRUNCATE TABLE' then
			p_success_message := 'Table truncated.';
		elsif p_command_name = 'UPDATE' then
			if p_rowcount is null then
				p_success_message := 'ERROR: Unknown number of rows updated.';
			elsif p_rowcount = 1 then
				p_success_message := '1 row updated.';
			else
				p_success_message := p_rowcount||' rows updated.';
			end if;
		elsif p_command_name = 'UPSERT' then
			if p_rowcount is null then
				p_success_message := 'ERROR: Unknown number of rows merged.';
			elsif p_rowcount = 1 then
				p_success_message := '1 row merged.';
			else
				p_success_message := p_rowcount||' rows merged.';
			end if;

		--Standard "ALTER", "CREATE", and "DROP".
		--Remove first word, change to lower case, initialize first letter, add verb.
		elsif p_command_name like 'ALTER %' then
			p_success_message := lower(replace(p_command_name, 'ALTER '))||' altered.';
			p_success_message := upper(substr(p_success_message, 1, 1))||substr(p_success_message, 2);
		elsif p_command_name like 'CREATE %' then
			p_success_message := lower(replace(p_command_name, 'CREATE '))||' created.';
			p_success_message := upper(substr(p_success_message, 1, 1))||substr(p_success_message, 2);
		elsif p_command_name like 'DROP %' then
			p_success_message := lower(replace(p_command_name, 'DROP '))||' dropped.';
			p_success_message := upper(substr(p_success_message, 1, 1))||substr(p_success_message, 2);


		--Print error message if statement type could not be determined.
		else
			p_success_message := 'ERROR: Cannot determine statement type.';
		end if;


		--Get compile warning message for PL/SQL objects
		if p_command_name = 'ALTER ANALYTIC VIEW' then
			p_compile_warning_message := 'Warning: Analytic view altered with compilation errors.';
		elsif p_command_name = 'ALTER ATTRIBUTE DIMENSION' then
			p_compile_warning_message := 'Warning: Attribute dimension altered with compilation errors.';
		elsif p_command_name like 'ALTER%'
			and
			(
				p_command_name like '%ASSEMBLY' or
				p_command_name like '%DIMENSION' or
				p_command_name like '%FUNCTION' or
				p_command_name like '%HIERARCHY' or
				p_command_name like '%JAVA' or
				p_command_name like '%LIBRARY' or
				p_command_name like '%PACKAGE' or
				p_command_name like '%PACKAGE BODY' or
				p_command_name like '%PROCEDURE' or
				p_command_name like '%TRIGGER' or
				(p_command_name like '%TYPE' and p_command_name not like '%INDEXTYPE') or
				p_command_name like '%TYPE BODY' or
				p_command_name like '%VIEW'
			) then
				p_compile_warning_message := 'Warning: '||initcap(replace(p_command_name, 'ALTER '))
					||' altered with compilation errors.';
		elsif p_command_name = 'CREATE ANALYTIC VIEW' then
			p_compile_warning_message := 'Warning: Analytic view created with compilation errors.';
		elsif p_command_name = 'CREATE ATTRIBUTE DIMENSION' then
			p_compile_warning_message := 'Warning: Attribute dimension created with compilation errors.';
		elsif p_command_name like 'CREATE%'
			and
			(
				p_command_name like '%ASSEMBLY' or
				--I don't think a dimension can be created with a compilation error.
				--But it is possible to ALTER them with a warning.
				--For example if a column was changed since it was created.
				--p_command_name like '%DIMENSION' or
				p_command_name like '%FUNCTION' or
				p_command_name like '%HIERARCHY' or
				p_command_name like '%JAVA' or
				p_command_name like '%LIBRARY' or
				p_command_name like '%PACKAGE' or
				p_command_name like '%PACKAGE BODY' or
				p_command_name like '%PROCEDURE' or
				p_command_name like '%TRIGGER' or
				(p_command_name like '%TYPE' and p_command_name not like '%INDEXTYPE') or
				p_command_name like '%TYPE BODY' or
				p_command_name like '%VIEW'
			) then
				p_compile_warning_message := 'Warning: '||initcap(replace(p_command_name, 'CREATE '))
					||' created with compilation errors.';
		end if;
	end if;

end get_feedback_message;


--------------------------------------------------------------------------------
procedure get_feedback_message(
	p_tokens                   in token_table,
	p_rowcount                 in number,
	p_success_message         out varchar2,
	p_compile_warning_message out varchar2
) is
	v_category       varchar2(100);
	v_statement_type varchar2(100);
	v_command_name   varchar2(64);
	v_command_type   number;
	v_lex_sqlcode    number;
	v_lex_sqlerrm    varchar2(4000);
begin
	--Classify the statement.
	statement_classifier.classify(p_tokens,
		v_category,v_statement_type,v_command_name,v_command_type,v_lex_sqlcode,v_lex_sqlerrm
	);

	get_feedback_message(v_command_name, p_rowcount, p_success_message, p_compile_warning_message);

end get_feedback_message;

end;
/
