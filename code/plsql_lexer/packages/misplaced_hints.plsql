create or replace package misplaced_hints authid current_user is
--Copyright (C) 2016 Jon Heller.  This program is licensed under the LGPLv3.

function get_misplaced_hints_in_code(p_text in clob) return misplaced_hints_code_table;
function get_misplaced_hints_in_schema(p_schema in varchar2) return misplaced_hints_schema_table;

/*

== Purpose ==

Find misplaced hints.  Hints in the wrong place do not generate errors or
warnings, they are simply "ignored".

Hints should be placed directly after the first keyword.  For example:
    select --+ parallel(8)  ...
    insert --+ append ...

These are invalid hints:
    select * --+ parallel(8) ...
    insert into --+ append ...

== Example ==

select * from table(misplaced_hints.get_misplaced_hints_in_schema('TEST_USER'));

== Parameters ==

P_TEXT - The source code check for bad hints.  Can be either SQL or PL/SQL.
P_SCHEMA - The name of the schema to check for bad hints.
*/

end;
/
create or replace package body misplaced_hints is

--------------------------------------------------------------------------------
--Purpose: Get the line with the hint on it.
function get_line(p_tokens token_table, p_hint_index number) return varchar2 is
	v_newline_position number;
	v_line clob;

	--DBMS_INSTR does not allow negative positions so we must loop through to find the last.
	function find_last_newline_position(p_clob in clob) return number is
		v_nth number := 1;
		v_new_newline_position number;
		v_previous_newline_position number;
	begin
		v_previous_newline_position := dbms_lob.instr(lob_loc => p_clob, pattern => chr(10), nth => v_nth);

		loop
			v_nth := v_nth + 1;
			v_new_newline_position := dbms_lob.instr(lob_loc => p_clob, pattern => chr(10), nth => v_nth);

			if v_new_newline_position = 0 then
				return v_previous_newline_position;
			else
				v_previous_newline_position := v_new_newline_position;
			end if;
		end loop;
	end find_last_newline_position;
begin
	--Get text before index token and after previous newline.
	for i in reverse 1 .. p_hint_index - 1 loop
		--Look for the last newline.
		v_newline_position := find_last_newline_position(p_tokens(i).value);

		--Get everything after newline if there is one, and exit.
		if v_newline_position > 0 then
			--(If the last character is a newline, the +1 will return null, which is what we want anyway.)
			v_line := dbms_lob.substr(lob_loc => p_tokens(i).value, offset => v_newline_position + 1) || v_line;
			exit;
		--Add entire string to the line if there was no newline.
		else
			v_line := p_tokens(i).value || v_line;
		end if;
	end loop;

	--Get text from hint token until the next newline.
	for i in p_hint_index .. p_tokens.count loop
		v_newline_position := dbms_lob.instr(lob_loc => p_tokens(i).value, pattern => chr(10));
		if v_newline_position = 0 then
			v_line := v_line || p_tokens(i).value;
		else
			v_line := v_line || dbms_lob.substr(lob_loc => p_tokens(i).value, offset => 1, amount => v_newline_position - 1);
			exit;
		end if;
	end loop;

	--Only return the first 4K bytes of data, to fit in SQL varchar2(4000). 
	return substrb(cast(substr(v_line, 1, 4000) as varchar2), 1, 4000);
end get_line;


--------------------------------------------------------------------------------
--Purpose: Get misplaced hints in a single block of code.
function get_misplaced_hints_in_code(p_text in clob) return misplaced_hints_code_table is
	v_tokens token_table;
	v_bad_hints misplaced_hints_code_table := misplaced_hints_code_table();
begin
	--Convert to tokens.
	v_tokens := plsql_lexer.lex(p_text);

	--Loop through all tokens and build a table of bad hints.
	for v_hint_index in 1 .. v_tokens.count loop

		--Examine token stream if this token is a comment and a hint.
		if
		(
			v_tokens(v_hint_index).type = plsql_lexer.c_comment
			and
			(
				v_tokens(v_hint_index).value like '/*+%'
				or v_tokens(v_hint_index).value like '--+%'
			)
		) then
			--Get the previous non-whitespace token.
			for v_non_whitespace_index in reverse 1 .. v_hint_index-1 loop
				--Stop if subscript is 0 or lower.
				if v_non_whitespace_index <= 0 then
					exit;
				--Stop at first non-whitespace.
				elsif v_tokens(v_non_whitespace_index).type <> plsql_lexer.c_whitespace then
					--Add to bad tokens if it's not the right SQL keyword.
					if upper(v_tokens(v_non_whitespace_index).value) not in ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'MERGE') then
						v_bad_hints.extend;
						v_bad_hints(v_bad_hints.count) := misplaced_hints_code_type(
							v_tokens(v_hint_index).line_number,
							v_tokens(v_hint_index).column_number,
							get_line(v_tokens, v_hint_index)
						);
					end if;
					exit;
				end if;
			end loop;
		end if;
	end loop;

	--Return bad hints, if any.
	return v_bad_hints;
end get_misplaced_hints_in_code;


--------------------------------------------------------------------------------
--Purpose: Get misplaced hints in all objects in a schema.
function get_misplaced_hints_in_schema(p_schema in varchar2) return misplaced_hints_schema_table is
	v_bad_hints_per_schema misplaced_hints_schema_table := misplaced_hints_schema_table();

	v_bad_hints_per_object misplaced_hints_code_table;
	v_code clob;
begin
	--Loop through all objects owned by that schema.
	for objects in
	(
		--Convert ALL_OBJECTS.OBJECT_TYPE to DBMS_METADATA object type.
		--Based on http://stackoverflow.com/a/10886633/409172
		select
			owner,
			object_name,
			decode(object_type,
				'DATABASE LINK',     'DB_LINK',
				'JAVA CLASS',        'JAVA_CLASS',
				'JAVA RESOURCE',     'JAVA_RESOURCE',
				'JOB',               'PROCOBJ',
				'PACKAGE',           'PACKAGE_SPEC',
				'PACKAGE BODY',      'PACKAGE_BODY',
				'TYPE',              'TYPE_SPEC',
				'TYPE BODY',         'TYPE_BODY',
				'MATERIALIZED VIEW', 'MATERIALIZED_VIEW',
				object_type
			) object_type
		from all_objects
		where owner = upper(trim(p_schema))
			--These objects are included with other object types.
			and object_type not in ('INDEX PARTITION','INDEX SUBPARTITION', 'LOB','LOB PARTITION','TABLE PARTITION','TABLE SUBPARTITION')
			--These objects cannot have SQL in them:
			and object_type not in ('ASSEMBLY', 'INDEX', 'JAVA CLASS', 'JAVA RESOURCE', 'JAVA SOURCE', 'TABLE')
			--Ignore system-generated types that support collection processing.
			and not (object_type like 'TYPE' and object_name like 'SYS_PLSQL_%')
		order by owner, object_name, object_type
	) loop
		--Get source code for the object.
		v_code := dbms_metadata.get_ddl(objects.object_type, objects.object_name, objects.owner);

		--Get bad hints for that objects.
		v_bad_hints_per_object := get_misplaced_hints_in_code(v_code);

		--Add bad hints to the list.
		for i in 1 .. v_bad_hints_per_object.count loop
			v_bad_hints_per_schema.extend;
			v_bad_hints_per_schema(v_bad_hints_per_schema.count) := 
				misplaced_hints_schema_type(
					objects.object_name,
					objects.object_type,
					--DBMS_METADATA.GET_DDL adds a newline to the beginning.
					v_bad_hints_per_object(i).line_number - 1,
					v_bad_hints_per_object(i).column_number,
					v_bad_hints_per_object(i).line_text
				);
		end loop;
	end loop;

	--Return bad hints, if any.
	return v_bad_hints_per_schema;
end get_misplaced_hints_in_schema;

end;
/
