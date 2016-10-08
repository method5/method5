create or replace package statement_splitter is
--Copyright (C) 2015 Jon Heller.  This program is licensed under the LGPLv3.

function split_by_semicolon(p_tokens in token_table) return token_table_table;
function split_by_sqlplus_delimiter(p_statements in clob, p_sqlplus_delimiter in varchar2 default '/') return clob_table;
function split_by_sqlplus_del_and_semi(p_statements in clob, p_sqlplus_delimiter in varchar2 default '/') return token_table_table;

/*

== Purpose ==

Split a string of SQL and PL/SQL statements into individual statements.

SPLIT_BY_SEMICOLON - Use semicolons for all terminators, even for PL/SQL
  statements.  This mode is useful for IDEs where a "/" in strings causes problems.

SPLIT_BY_SQLPLUS_DELIMITER - Uses a delimiter the way SQL*Plus does - it must
  be on a line with only whitespace.

SPLIT_BY_SQLPLUS_DEL_AND_SEMI - Combines the above two.

== Example ==

SPLIT_BY_SEMICOLON:

	select rownum, plsql_lexer.concatenate(column_value) statement
	from table(
		statement_splitter.split_by_semicolon(
			plsql_lexer.lex('begin null; end;select * from test2;')
		)
	);

	Results:
	*  ROWNUM   STATEMENT
	*  ------   ---------
	*  1        begin null; end;
	*  2        select * from test2;


SPLIT_BY_SQLPLUS_DELIMITER:

	select rownum, column_value statement
	from table(
		statement_splitter.split_by_sqlplus_delimiter(
			'begin null; end;'||chr(10)||
			'/'||chr(10)||
			'select * from test2'
		)
	);

	Results:
	*  ROWNUM   STATEMENT
	*  ------   ---------
	*  1        begin null; end;
	*           /
	*  2        select * from test2;

*/

end;
/
create or replace package body statement_splitter is

C_TERMINATOR_SEMI              constant number := 1;
C_TERMINATOR_PLSQL_DECLARATION constant number := 2;
C_TERMINATOR_PLSQL             constant number := 3;
C_TERMINATOR_EOF               constant number := 4;





--------------------------------------------------------------------------------
procedure add_statement_consume_tokens(
	p_split_tokens in out nocopy token_table_table,
	p_parse_tree in token_table,
	p_terminator number,
	p_parse_tree_index in out number,
	p_command_name in varchar2
) is
	/*
	This is a recursive descent parser for PL/SQL.
	This link has a good introduction to recursive descent parsers: https://www.cis.upenn.edu/~matuszek/General/recursive-descent-parsing.html)

	The functions roughly follow the same order as the "Block" chapater in the 12c PL/SQL Langauge Reference:
	http://docs.oracle.com/database/121/LNPLS/block.htm#LNPLS01303

	The splitter only needs to know when the statement ends and does not consume
	every token in a meaningful way, like a real parser would.  For example,
	there are many times when tokens can be skipped until the next semicolon.

	If Oracle ever allows PLSQL_DECLARATIONS inside PL/SQL code this code will need to
	be much more complicated.
	*/

	-------------------------------------------------------------------------------
	--Globals
	-------------------------------------------------------------------------------
	--v_code clob := 'declare procedure p1 is begin null; end; begin null; end;select * from dual;';
	--v_code clob := '<<asdf>>declare a number; procedure p1 is begin null; end; begin null; end;select * from dual;';

	--Cursors can have lots of parentheses, and even an "IS" inside them.
	--v_code clob := 'declare cursor c(a number default case when (((1 is null))) then 1 else 0 end) is select 1 a from dual; begin null; end;select * from dual;';
	--v_code clob := '<<asdf>>begin null; end;';

	--SELECT test.
	--v_code clob := 'declare a number; select 1 into a from dual; end;';


	type string_table is table of varchar2(32767);
	type number_table is table of number;

	g_debug_lines string_table := string_table();
	g_ast_index number := 1;

	v_abstract_syntax_tree token_table := token_table();
	v_map_between_parse_and_ast number_table := number_table();

	--Holds return value of optional functions.
	g_optional boolean;


	-------------------------------------------------------------------------------
	--Forward declarations so that functions can be in the same order as the documentation.
	-------------------------------------------------------------------------------
	function anything_(p_value varchar2) return boolean;
	function anything_before_begin return boolean;
	function anything_in_parentheses return boolean;
	function anything_up_to_may_include_(p_value varchar2) return boolean;
	function anything_up_to_must_include_(p_value varchar2) return boolean;
	function basic_loop_statement return boolean;
	function body return boolean;
	function case_statement return boolean;
	function create_procedure return boolean;
	function create_function return boolean;
	function create_package return boolean;
	function create_type_body return boolean;
	function create_trigger return boolean;
	function cursor_for_loop_statement return boolean;
	function declare_section return boolean;
	function exception_handler return boolean;
	function expression_case_when_then return boolean;
	function initialize_section return boolean;
	function for_loop_statement return boolean;
	function for_each_row return boolean;
	function function_definition return boolean;
	function if_statement return boolean;
	function label return boolean;
	function name return boolean;
	function name_maybe_schema return boolean;
	function nested_table_nt_column_of return boolean;
	function p_end return boolean;
	function plsql_block return boolean;
	function procedure_definition return boolean;
	function referencing_clause return boolean;
	function statement_or_inline_pragma return boolean;
	function trigger_edition_clause return boolean;
	function trigger_ordering_clause return boolean;
	function when_condition return boolean;

	-------------------------------------------------------------------------------
	--Helper functions
	-------------------------------------------------------------------------------
	procedure push(p_line varchar2) is
	begin
		g_debug_lines.extend;
		g_debug_lines(g_debug_lines.count) := p_line;
	end;

	function pop(p_local_ast_before number default null, p_local_lines_before string_table default null) return boolean is
	begin
		if p_local_ast_before is null then
			g_debug_lines.trim;
		else
			g_ast_index := p_local_ast_before;
			g_debug_lines := p_local_lines_before;
		end if;
		return false;
	end;

	procedure pop is
	begin
		g_debug_lines.trim;
	end;

	procedure increment(p_increment number default 1) is begin
		g_ast_index := g_ast_index + p_increment;
	end;

	function get_next_(p_value varchar2) return number is begin
		for i in g_ast_index .. v_abstract_syntax_tree.count loop
			if upper(v_abstract_syntax_tree(i).value) = p_value then
				return i;
			end if;
		end loop;
		return null;
	end;

	function current_value return clob is begin
		return upper(v_abstract_syntax_tree(g_ast_index).value);
	end;

	procedure parse_error(p_syntax_type varchar2) is begin
		raise_application_error(-20002, 'Fatal parse error in '||p_syntax_type||' around line #'||
			v_abstract_syntax_tree(g_ast_index).line_number||', column #'||
			v_abstract_syntax_tree(g_ast_index).column_number||' of the original string.');

	end;

	function next_value(p_increment number default 1) return clob is begin
		begin
			return upper(v_abstract_syntax_tree(g_ast_index+p_increment).value);
		exception when subscript_beyond_count then
			null;
		end;
	end;

	function previous_value(p_decrement number) return clob is begin
		begin
			if g_ast_index - p_decrement <= 0 then
				return null;
			else
				return upper(v_abstract_syntax_tree(g_ast_index - p_decrement).value);
			end if;
		exception when subscript_beyond_count then
			null;
		end;
	end;

	function current_type return varchar2 is begin
		return v_abstract_syntax_tree(g_ast_index).type;
	end;

	function anything_(p_value varchar2) return boolean is begin
		push(p_value);
		if current_value = p_value then
			increment;
			return true;
		else
			return pop;
		end if;
	end;

	function anything_up_to_may_include_(p_value varchar2) return boolean is begin
		push('ANYTHING_UP_TO_MAY_INCLUDE_'||p_value);
		begin
			loop
				if current_value = p_value then
					increment;
					return true;
				end if;
				increment;
			end loop;
		exception when subscript_beyond_count then return true;
		end;
	end;

	function anything_up_to_must_include_(p_value varchar2) return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('ANYTHING_UP_TO_MUST_INCLUDE_'||p_value);
		begin
			loop
				if current_value = p_value then
					increment;
					return true;
				end if;
				increment;
			end loop;
		exception when subscript_beyond_count then null;
		end;

		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function anything_before_begin return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('ANYTHING_BUT_BEGIN');
		begin
			loop
				if current_value = 'BEGIN' then
					return true;
				end if;
				increment;
			end loop;
		exception when subscript_beyond_count then null;
		end;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function anything_in_parentheses return boolean is v_paren_counter number; begin
		push('ANYTHING_IN_PARENTHESES');
		if anything_('(') then
			v_paren_counter := 1;
			while v_paren_counter >= 1 loop
				if current_value = '(' then
					v_paren_counter := v_paren_counter + 1;
				elsif current_value = ')' then
					v_paren_counter := v_paren_counter - 1;
				end if;
				increment;
			end loop;
			return true;
		end if;
		return pop;
	end;

	-------------------------------------------------------------------------------
	--Production rules that consume tokens and return true or false if rule was found.
	-------------------------------------------------------------------------------
	function plsql_block return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('PLSQL_BLOCK');

		g_optional := label;
		if anything_('DECLARE') then
			g_optional := declare_section;
			if body then
				return true;
			else
				return pop(v_local_ast_before, v_local_lines_before);
			end if;
		elsif body then
			return true;
		else
			return pop(v_local_ast_before, v_local_lines_before);
		end if;
	end;

	function label return boolean is begin
		push('LABEL');
		if current_value = '<<' then
			loop
				increment;
				if current_value = '>>' then
					increment;
					return true;
				end if;
			end loop;
		end if;
		return pop;
	end;

	function declare_section return boolean is begin
		push('DECLARE_SECTION');
		if current_value in ('BEGIN', 'END') then
			return pop;
		else
			loop
				if current_value in ('BEGIN', 'END') then
					return true;
				end if;

				--Of the items in ITEM_LIST_1 and ITEM_LIST_2, only
				--these two require any special processing.
				if procedure_definition then null;
				elsif function_definition then null;
				elsif anything_up_to_may_include_(';') then null;
				end if;
			end loop;
		end if;
	end;

	function body return boolean is begin
		push('BODY');
		if anything_('BEGIN') then
			g_optional := statement_or_inline_pragma;
			while statement_or_inline_pragma loop null; end loop;
			if anything_('EXCEPTION') then
				while exception_handler loop null; end loop;
			end if;
			g_optional := p_end;
			return true;
		end if;
		return pop;
	end;

	function initialize_section return boolean is begin
		push('BODY');
		if anything_('BEGIN') then
			g_optional := statement_or_inline_pragma;
			while statement_or_inline_pragma loop null; end loop;
			if anything_('EXCEPTION') then
				while exception_handler loop null; end loop;
			end if;
			return true;
		end if;
		return pop;
	end;

	function procedure_definition return boolean is begin
		push('PROCEDURE_DEFINITION');
		--Exclude CTE queries that create a table expression named "PROCEDURE".
		if current_value = 'PROCEDURE' and next_value not in ('AS', '(') then
			g_optional := anything_before_begin; --Don't need the header information.
			return body;
		end if;
		return pop;
	end;

	function function_definition return boolean is begin
		push('FUNCTION_DEFINITION');
		--Exclude CTE queries that create a table expression named "FUNCTION".
		if current_value = 'FUNCTION' and next_value not in ('AS', '(') then
			g_optional := anything_before_begin; --Don't need the header information.
			return body;
		end if;
		return pop;
	end;

	function name return boolean is begin
		push('NAME');
		if current_type = plsql_lexer.c_word then
			increment;
			return true;
		end if;
		return pop;
	end;

	function name_maybe_schema return boolean is begin
		push('NAME_MAYBE_SCHEMA');
		if name then
			if anything_('.') then
				g_optional := name;
			end if;
			return true;
		end if;
		return pop;
	end;

	function statement_or_inline_pragma return boolean is begin
		push('STATEMENT_OR_INLINE_PRAGMA');
		if label then return true;
		--Types that might have more statements:
		elsif basic_loop_statement then return true;
		elsif case_statement then return true;
		elsif for_loop_statement then return true;
		elsif cursor_for_loop_statement then return true;
		elsif if_statement then return true;
		elsif plsql_block then return true;
		--Anything else
		elsif current_value not in ('EXCEPTION', 'END', 'ELSE', 'ELSIF') then
			return anything_up_to_may_include_(';');
		end if;
		return pop;
	end;

	function p_end return boolean is begin
		push('P_END');
		if current_value = 'END' then
			increment;
			g_optional := name;
			if current_type = ';' then
				increment;
			end if;
			return true;
		end if;
		return pop;
	end;

	function exception_handler return boolean is begin
		push('EXCEPTION_HANDLER');
		if current_value = 'WHEN' then
			g_optional := anything_up_to_must_include_('THEN');
			while statement_or_inline_pragma loop null; end loop;
			return true;
		end if;
		return pop;
	end;

	function basic_loop_statement return boolean is begin
		push('BASIC_LOOP_STATEMENT');
		if current_value = 'LOOP' then
			increment;
			while statement_or_inline_pragma loop null; end loop;
			if current_value = 'END' then
				increment;
				if current_value = 'LOOP' then
					increment;
					g_optional := name;
					if current_value = ';' then
						increment;
						return true;
					end if;
				end if;
			end if;
			parse_error('BASIC_LOOP_STATEMENT');
		end if;
		return pop;
	end;

	function for_loop_statement return boolean is begin
		push('FOR_LOOP_STATEMENT');
		if current_value = 'FOR' and get_next_('..') < get_next_(';') then
			g_optional := anything_up_to_must_include_('LOOP');
			while statement_or_inline_pragma loop null; end loop;
			if current_value = 'END' then
				increment;
				if current_value = 'LOOP' then
					increment;
					g_optional := name;
					if current_value = ';' then
						increment;
						return true;
					end if;
				end if;
			end if;
			parse_error('FOR_LOOP_STATEMENT');
		else
			return pop;
		end if;
	end;

	function cursor_for_loop_statement return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('CURSOR_FOR_LOOP_STATEMENT');
		if current_value = 'FOR' then
			increment;
			if name then
				if current_value = 'IN' then
					increment;
					g_optional := name;
					if current_value = '(' then
						g_optional := anything_in_parentheses;
						if current_value = 'LOOP' then
							increment;
							while statement_or_inline_pragma loop null; end loop;
							if current_value = 'END' then
								increment;
								if current_value = 'LOOP' then
									increment;
									g_optional := name;
									if current_value = ';' then
										increment;
										return true;
									end if;
								end if;
							end if;
						end if;
					end if;
				end if;
			end if;
			parse_error('CURSOR_FOR_LOOP_STATEMENT');
		else
			return pop(v_local_ast_before, v_local_lines_before);
		end if;
	end;

	procedure case_expression is begin
		push('CASE_EXPRESSION');
		loop
			if anything_('CASE') then
				case_expression;
				return;
			elsif anything_('END') then
				return;
			else
				increment;
			end if;
		end loop;
		pop;
	end;

	function expression_case_when_then return boolean is begin
		push('EXPRESSION_CASE_WHEN_THEN');
		loop
			if current_value = 'CASE' then
				case_expression;
			elsif current_value = 'WHEN' or current_value = 'THEN' then
				return true;
			else
				increment;
			end if;
		end loop;
		return pop;
	end;

	function case_statement return boolean is begin
		push('CASE_STATEMENT');
		if anything_('CASE') then
			--Searched case.
			if current_value = 'WHEN' then
				while anything_('WHEN') and expression_case_when_then and anything_('THEN') loop
					while statement_or_inline_pragma loop null; end loop;
				end loop;
				if anything_('ELSE') then
					while statement_or_inline_pragma loop null; end loop;
				end if;
				if anything_('END') and anything_('CASE') and (name or not name) and anything_(';') then
					return true;
				end if;
				parse_error('SEARCHED_CASE_STATEMENT');
			--Simple case.
			else
				if expression_case_when_then then
					while anything_('WHEN') and expression_case_when_then and anything_('THEN') loop
						while statement_or_inline_pragma loop null; end loop;
					end loop;
					if anything_('ELSE') then
						while statement_or_inline_pragma loop null; end loop;
					end if;
					if anything_('END') and anything_('CASE') and (name or not name) and anything_(';') then
						return true;
					end if;
				end if;
				parse_error('SIMPLE_CASE_STATEMENT');
			end if;
		else
			return pop;
		end if;
	end;

	function if_statement return boolean is begin
		push('IF_STATEMENT');
		if anything_('IF') then
			if expression_case_when_then and anything_('THEN') then
				while statement_or_inline_pragma loop null; end loop;
				while anything_('ELSIF') and expression_case_when_then and anything_('THEN') loop
					while statement_or_inline_pragma loop null; end loop;
				end loop;
				if anything_('ELSE') then
					while statement_or_inline_pragma loop null; end loop;
				end if;
				if anything_('END') and anything_('IF') and anything_(';') then
					return true;
				end if;
			end if;
			parse_error('IF_STATEMENT');
		end if;
		return pop;
	end;

	function create_or_replace_edition return boolean is begin
		push('CREATE_OR_REPLACE_EDITION');
		if anything_('CREATE') then
			g_optional := anything_('OR');
			g_optional := anything_('REPLACE');
			g_optional := anything_('EDITIONABLE');
			g_optional := anything_('NONEDITIONABLE');
			return true;
		end if;
		return pop;
	end;

	function create_procedure return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('CREATE_PROCEDURE');
		if create_or_replace_edition and anything_('PROCEDURE') and name_maybe_schema then
			g_optional := anything_in_parentheses;
			if anything_up_to_must_include_('IS') or anything_up_to_must_include_('AS') then
				if anything_('EXTERNAL') or anything_('LANGUAGE') then
					g_optional := anything_up_to_may_include_(';');
					return true;
				elsif plsql_block then
					return true;
				end if;
			end if;
			parse_error('CREATE_PROCEDURE');
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function create_function return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('CREATE_FUNCTION');
		if create_or_replace_edition and anything_('FUNCTION') and name_maybe_schema then
			--Consume everything between the function name and either AGGREGATE|PIPELINED USING
			--or the last IS/AS.
			--This is necessary to exclude some options that may include another IS, such as
			--expressions in the PARALLEL_ENABLE_CLAUSE.
			loop
				if current_value in ('AGGREGATE', 'PIPELINED') and next_value = 'USING' then
					--This one is simple, return true.
					increment(2);
					g_optional := anything_up_to_may_include_(';');
					return true;
				elsif current_value = '(' then
					g_optional := anything_in_parentheses;
				elsif current_value in ('IS', 'AS') then
					increment;
					exit;
				else
					increment;
				end if;
			end loop;
			--There must have been an IS or AS to get here:
			if anything_('EXTERNAL') then
				g_optional := anything_up_to_may_include_(';');
				return true;
			elsif anything_('LANGUAGE') then
				g_optional := anything_up_to_may_include_(';');
				return true;
			else
				return plsql_block;
			end if;
			parse_error('CREATE_FUNCTION');
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function create_package return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('CREATE_PACKAGE');
		if create_or_replace_edition and anything_('PACKAGE') and name_maybe_schema then
			g_optional := anything_in_parentheses;
			if anything_up_to_must_include_('IS') or anything_up_to_must_include_('AS') then
				loop
					if anything_('END') then
						g_optional := name;
						g_optional := anything_(';');
						return true;
					else
						g_optional := anything_up_to_may_include_(';');
					end if;
				end loop;
			end if;
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function create_package_body return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('CREATE_PACKAGE_BODY');
		if create_or_replace_edition and anything_('PACKAGE') and anything_('BODY') and name_maybe_schema then
			if anything_('IS') or anything_('AS') then
				g_optional := declare_section;
				g_optional := initialize_section;
				if anything_('END') then
					g_optional := name;
					g_optional := anything_(';');
					return true;
				end if;
			end if;
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function create_type_body return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('CREATE_TYPE_BODY');
		if create_or_replace_edition and anything_('TYPE') and anything_('BODY') and name_maybe_schema then
			g_optional := anything_in_parentheses;
			if anything_up_to_must_include_('IS') or anything_up_to_must_include_('AS') then
				loop
					if anything_('END') and anything_(';') then
						return true;
					elsif current_value in ('MAP', 'ORDER', 'MEMBER') then
						g_optional := anything_('MAP');
						g_optional := anything_('ORDER');
						g_optional := anything_('MEMBER');
						if procedure_definition or function_definition then
							null;
						end if;
					elsif current_value in ('FINAL', 'INSTANTIABLE', 'CONSTRUCTOR') then
						g_optional := anything_('FINAL');
						g_optional := anything_('INSTANTIABLE');
						g_optional := anything_('CONSTRUCTOR');
						g_optional := function_definition;
					else
						g_optional := anything_up_to_may_include_(';');
					end if;
				end loop;
			end if;
			parse_error('CREATE_TYPE_BODY');
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function dml_event_clause return boolean is
		function update_of_column return boolean is begin
			if anything_('UPDATE') then
				if anything_('OF') and name then
					while anything_(',') and name loop null; end loop;
					return true;
				else
					return true;
				end if;
			end if;
			return false;
		end;
	begin
		push('DML_EVENT_CLAUSE');
		if anything_('DELETE') or anything_('INSERT') or update_of_column then
			while anything_('OR') and (anything_('DELETE') or anything_('INSERT') or update_of_column) loop null; end loop;
			if anything_('ON') and name_maybe_schema then
				return true;
			end if;
			parse_error('DML_EVENT_CLAUSE');
		end if;
		return pop;
	end;

	function referencing_clause return boolean is begin
		push('REFERENCING_CLAUSE');
		if anything_('REFERENCING') then
			if anything_('OLD') or anything_('NEW') or anything_('PARENT') then
				g_optional := anything_('AS');
				g_optional := name;
				while anything_('OLD') or anything_('NEW') or anything_('PARENT') loop
					g_optional := anything_('AS');
					g_optional := name;
				end loop;
				return true;
			end if;
			parse_error('REFERENCING_CLAUSE');
		end if;
		return pop;
	end;

	function for_each_row return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('FOR_EACH_ROW');
		if anything_('FOR') and anything_('EACH') and anything_('ROW') then
			return true;
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function trigger_edition_clause return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('TRIGGER_EDITION_CLAUSE');
		if anything_('FORWARD') or anything_('REVERSE') then
			null;
		end if;
		if anything_('CROSSEDITION') then
			return true;
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function trigger_ordering_clause return boolean is begin
		push('TRIGGER_ORDERING_CLAUSE');
		if anything_('FOLLOWS') or anything_('PRECEDES') then
			if name_maybe_schema then
				while anything_(',') and name_maybe_schema loop null; end loop;
				return true;
			end if;
			parse_error('TRIGGER_ORDERING_CLAUSE');
		end if;
		return pop;
	end;

	function when_condition return boolean is begin
		push('WHEN_CONDITION');
		if anything_('WHEN') then
			if anything_in_parentheses then
				return true;
			end if;
			parse_error('WHEN_CONDITION');
		end if;
		return pop;
	end;

	function trigger_body return boolean is begin
		push('TRIGGER_BODY');
		if anything_('CALL') then
			g_optional := anything_up_to_may_include_(';');
			return true;
		elsif plsql_block then return true;
		end if;
		return pop;
	end;

	function delete_insert_update_or return boolean is begin
		push('DELETE_INSERT_UPDATE_OR');
		if anything_('DELETE') or anything_('INSERT') or anything_('UPDATE') then
			while anything_('OR') and (anything_('DELETE') or anything_('INSERT') or anything_('UPDATE')) loop null; end loop;
			return true;
		end if;
		return pop;
	end;

	function nested_table_nt_column_of return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('NESTED_TABLE_NT_COLUMN_OF');
		if anything_('NESTED') and anything_('TABLE') and name and anything_('OF') then
			return true;
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function timing_point return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('TIMING_POINT');
		if current_value = 'BEFORE' and next_value = 'STATEMENT' then
			increment(2);
			return true;
		elsif current_value = 'BEFORE' and next_value = 'EACH' and next_value(2) = 'ROW' then
			increment(3);
			return true;
		elsif current_value = 'AFTER' and next_value = 'STATEMENT' then
			increment(2);
			return true;
		elsif current_value = 'AFTER' and next_value = 'EACH' and next_value(2) = 'ROW' then
			increment(3);
			return true;
		elsif current_value = 'INSTEAD' and next_value = 'OF' and next_value(2) = 'EACH' and next_value(3) = 'ROW' then
			increment(4);
			return true;
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function tps_body return boolean is begin
		push('TPS_BODY');
		if statement_or_inline_pragma then
			while statement_or_inline_pragma loop null; end loop;
			if anything_('EXCEPTION') then
				while exception_handler loop null; end loop;
			end if;
			return true;
		end if;
		return pop;
	end;

	function timing_point_section return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('TIMING_POINT_SECTION');
		if timing_point and anything_('IS') and anything_('BEGIN') and tps_body and anything_('END') and timing_point and anything_(';') then
			return true;
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function compound_trigger_block return boolean is
		--Similar to the regular DECLARE_SECTION but also stops at timing point keywords.
		function declare_section return boolean is begin
			push('DECLARE_SECTION');
			if current_value in ('BEGIN', 'END', 'BEFORE', 'AFTER', 'INSTEAD') then
				return pop;
			else
				loop
					if current_value in ('BEGIN', 'END', 'BEFORE', 'AFTER', 'INSTEAD') then
						return true;
					end if;

					--Of the items in ITEM_LIST_1 and ITEM_LIST_2, only
					--these two require any special processing.
					if procedure_definition then null;
					elsif function_definition then null;
					elsif anything_up_to_may_include_(';') then null;
					end if;
				end loop;
			end if;
		end;
	begin
		push('COMPOUND_TRIGGER_BLOCK');
		if anything_('COMPOUND') and anything_('TRIGGER') then
			g_optional := declare_section;
			if timing_point_section then
				while timing_point_section loop null; end loop;
				if anything_('END') then
					g_optional := name;
					if anything_(';') then
						return true;
					end if;
				end if;
			end if;
			parse_error('COMPOUND_TRIGGER_BLOCK');
		end if;
		return pop;
	end;

	function ddl_or_database_event return boolean is begin
		push('DDL_OR_DATABASE_EVENT');
		if current_value in
		(
			'ALTER', 'ANALYZE', 'AUDIT', 'COMMENT', 'CREATE', 'DROP', 'GRANT', 'NOAUDIT',
			'RENAME', 'REVOKE', 'TRUNCATE', 'DDL', 'STARTUP', 'SHUTDOWN', 'DB_ROLE_CHANGE',
			'SERVERERROR', 'LOGON', 'LOGOFF', 'SUSPEND', 'CLONE', 'UNPLUG'
		) then
			increment;
			return true;
		elsif current_value||' '|| next_value in
		(
			'ASSOCIATE STATISTICS', 'DISASSOCIATE STATISTICS', 'SET CONTAINER'
		) then
			increment(2);
			return true;
		end if;
		return pop;
	end;

	function simple_dml_trigger return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('SIMPLE_DML_TRIGGER');
		if (anything_('BEFORE') or anything_('AFTER')) and dml_event_clause then
			g_optional := referencing_clause;
			g_optional := for_each_row;
			g_optional := trigger_edition_clause;
			g_optional := trigger_ordering_clause;
			if anything_('ENABLE') or anything_('DISABLE') then
				null;
			end if;
			g_optional := when_condition;
			if trigger_body then
				return true;
			end if;
			parse_error('SIMPLE_DML_TRIGGER');
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function instead_of_dml_trigger return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('INSTEAD_OF_DML_TRIGGER');
		if anything_('INSTEAD') and anything_('OF') and delete_insert_update_or then
			if anything_('ON') then
				g_optional := nested_table_nt_column_of;
				if name_maybe_schema then
					g_optional := referencing_clause;
					g_optional := for_each_row;
					g_optional := trigger_edition_clause;
					g_optional := trigger_ordering_clause;
					if anything_('ENABLE') or anything_('DISABLE') then
						null;
					end if;
					if trigger_body then
						return true;
					end if;
				end if;
				parse_error('INSTEAD_OF_DML_TRIGGER');
			end if;
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function compound_trigger return boolean is begin
		push('COMPOUND_TRIGGER');
		if anything_('FOR') then
			if dml_event_clause then
				g_optional := referencing_clause;
				g_optional := trigger_edition_clause;
				g_optional := trigger_ordering_clause;
				if anything_('ENABLE') or anything_('DISABLE') then
					null;
				end if;
				g_optional := when_condition;
				if compound_trigger_block then
					return true;
				end if;
			end if;
			parse_error('COMPOUND_TRIGGER');
		end if;
		return pop;
	end;

	function system_trigger return boolean is v_local_ast_before number := g_ast_index; v_local_lines_before string_table := g_debug_lines; begin
		push('SYSTEM_TRIGGER');
		if (anything_('BEFORE') or anything_('AFTER') or (anything_('INSTEAD') and anything_('OF'))) and ddl_or_database_event then
			while anything_('OR') and ddl_or_database_event loop null; end loop;
			if anything_('ON') then
				if anything_('DATABASE') or (anything_('PLUGGABLE') and anything_('DATABASE')) or anything_('SCHEMA') or (name and anything_('.') and anything_('SCHEMA')) then
					g_optional := trigger_ordering_clause;
					--The manual is missing the last part of SYSTEM_TRIGGER - ENABLE|DISABLE, WHEN (CONDITION) and TRIGGER_BODY.
					if anything_('ENABLE') or anything_('DISABLE') then
						null;
					end if;
					g_optional := when_condition;
					if trigger_body then
						return true;
					end if;
				end if;
			end if;
			parse_error('SYSTEM_TRIGGER');
		end if;
		return pop(v_local_ast_before, v_local_lines_before);
	end;

	function create_trigger return boolean is begin
		push('CREATE_TRIGGER');
		if create_or_replace_edition and anything_('TRIGGER') and name_maybe_schema then
			if simple_dml_trigger then return true;
			elsif instead_of_dml_trigger then return true;
			elsif compound_trigger then return true;
			elsif system_trigger then return true;
			end if;
			parse_error('CREATE_TRIGGER');
	end if;
		return pop;
	end;


begin
	--Convert parse tree into abstract syntax tree by removing whitespace, comment, and EOF.
	--Also create a map between the two.
	for i in p_parse_tree_index .. p_parse_tree.count loop
		if p_parse_tree(i).type not in (plsql_lexer.c_whitespace, plsql_lexer.c_comment, plsql_lexer.c_eof) then
			v_abstract_syntax_tree.extend;
			v_abstract_syntax_tree(v_abstract_syntax_tree.count) := p_parse_tree(i);

			v_map_between_parse_and_ast.extend;
			v_map_between_parse_and_ast(v_map_between_parse_and_ast.count) := i;
		end if;
	end loop;

	--Find the last AST token index.
	--
	begin
		--Consume everything
		if p_terminator = C_TERMINATOR_EOF then
			g_ast_index := v_abstract_syntax_tree.count + 1;

		--Look for a ';' anywhere.
		elsif p_terminator = C_TERMINATOR_SEMI then
			--Loop through all tokens, exit if a semicolon found.
			for i in 1 .. v_abstract_syntax_tree.count loop
				if v_abstract_syntax_tree(i).type = ';' then
					g_ast_index := i + 1;
					exit;
				end if;
				g_ast_index := i + 1;
			end loop;

		--Match BEGIN and END for a PLSQL_DECLARATION.
		elsif p_terminator = C_TERMINATOR_PLSQL_DECLARATION then
			/*
			PL/SQL Declarations must have this pattern before the first ";":
				(null or not "START") "WITH" ("FUNCTION"|"PROCEDURE") (neither "(" nor "AS")

			This was discovered by analyzing all "with" strings in the Oracle documentation
			text descriptions.  That is, download the library and run a command like this:
				C:\E50529_01\SQLRF\img_text> findstr /s /i "with" *.*

			SQL has mnay ambiguities, simply looking for "with function" would incorrectly catch these:
				1. Hierarchical queries.  Exclude them by looking for "start" before "with".
					select * from (select 1 function from dual)	connect by function = 1	start with function = 1;
				2. Subquery factoring that uses "function" as a name.  Stupid, but possible.
					with function as (select 1 a from dual) select * from function;
					with function(a) as (select 1 a from dual) select * from function;
				Note: "start" cannot be the name of a table, no need to worry about DML
				statements like `insert into start with ...`.
			*/
			for i in 1 .. v_abstract_syntax_tree.count loop
				if
				(
					(previous_value(2) is null or previous_value(2) <> 'START')
					and previous_value(1) = 'WITH'
					and current_value in ('FUNCTION', 'PROCEDURE')
					and (next_value is null or next_value not in ('(', 'AS'))
				) then
					if current_value in ('FUNCTION', 'PROCEDURE') then
						while function_definition or procedure_definition loop null; end loop;
					end if;
				elsif v_abstract_syntax_tree(g_ast_index).type = ';' then
					g_ast_index := g_ast_index + 1;
					exit;
				else
					g_ast_index := g_ast_index + 1;
				end if;
			end loop;
		--Match BEGIN and END for a common PL/SQL block.
		elsif p_terminator = C_TERMINATOR_PLSQL then
			if plsql_block then null;
			elsif create_procedure then null;
			elsif create_function then null;
			elsif create_package_body then null;
			elsif create_package then null;
			elsif create_type_body then null;
			elsif create_trigger then null;
			else
				parse_error(p_command_name);
			end if;
		end if;
	exception when subscript_beyond_count then
		--If a token was expected but not found just return everything up to that point.
		null;
	end;

	--Helpful for debugging:
	--for i in 1 .. g_debug_lines.count loop
	--	dbms_output.put_line(g_debug_lines(i));
	--end loop;

	--Create a new parse tree with the new tokens.
	declare
		v_new_parse_tree token_table := token_table();
		v_has_abstract_token boolean := false;
	begin
		--Special case if there are no abstract syntax tokens - add everything.
		if g_ast_index = 1 then
			--Create new parse tree.
			for i in p_parse_tree_index .. p_parse_tree.count loop
				v_new_parse_tree.extend;
				v_new_parse_tree(v_new_parse_tree.count) := p_parse_tree(i);
			end loop;

			--Add new parse tree.
			p_split_tokens.extend;
			p_split_tokens(p_split_tokens.count) := v_new_parse_tree;

			--Set the parse tree index to the end, plus one to stop loop.
			p_parse_tree_index := p_parse_tree.count + 1;

		--Else iterate up to the last abstract syntax token and maybe some extra whitespace.
		else
			--Iterate selected parse tree tokens, add them to collection.
			for i in p_parse_tree_index .. v_map_between_parse_and_ast(g_ast_index-1) loop
				v_new_parse_tree.extend;
				v_new_parse_tree(v_new_parse_tree.count) := p_parse_tree(i);
			end loop;

			--Are any of the remaining tokens abstract?
			for i in v_map_between_parse_and_ast(g_ast_index-1) + 1 .. p_parse_tree.count loop
				if p_parse_tree(i).type not in (plsql_lexer.c_whitespace, plsql_lexer.c_comment, plsql_lexer.c_eof) then
					v_has_abstract_token := true;
					exit;
				end if;
			end loop;

			--If no remaining tokens are abstract, add them to the new parse tree.
			--Whitespace and comments after the last statement belong to that statement, not a new one.
			if not v_has_abstract_token then
				for i in v_map_between_parse_and_ast(g_ast_index-1) + 1 .. p_parse_tree.count loop
					v_new_parse_tree.extend;
					v_new_parse_tree(v_new_parse_tree.count) := p_parse_tree(i);
				end loop;

				--Set the parse tree index to the end, plus one to stop loop.
				p_parse_tree_index := p_parse_tree.count + 1;
			else
				--Set the parse tree index based on the last AST index.
				p_parse_tree_index := v_map_between_parse_and_ast(g_ast_index-1) + 1;
			end if;

			--Add new tree to collection of trees.
			p_split_tokens.extend;
			p_split_tokens(p_split_tokens.count) := v_new_parse_tree;
		end if;
	end;

end add_statement_consume_tokens;


--------------------------------------------------------------------------------
--Fix line_number, column_number, first_char_position and last_char_position.
function adjust_metadata(p_split_tokens in token_table_table) return token_table_table is
	v_new_split_tokens token_table_table := token_table_table();
	v_new_tokens token_table := token_table();
	v_line_number_difference number;
	v_column_number_difference number;
	v_first_char_position_diff number;
	v_last_char_position_diff number;
begin
	--Loop through split tokens.
	for i in 1 .. p_split_tokens.count loop
		v_new_split_tokens.extend;
		--Keep the first token collection the same.
		if i = 1 then
			v_new_split_tokens(i) := p_split_tokens(i);
		--Shift numbers for other token tables.
		else
			--Reset token table.
			v_new_tokens := token_table();

			--Get differences based on the first token.
			v_line_number_difference := p_split_tokens(i)(1).line_number - 1;
			v_column_number_difference := p_split_tokens(i)(1).column_number - 1;
			v_first_char_position_diff := p_split_tokens(i)(1).first_char_position - 1;
			v_last_char_position_diff := p_split_tokens(i)(1).first_char_position - 1;

			--Loop through tokens and create new adjusted values.
			for token_index in 1 .. p_split_tokens(i).count loop
				--Create new token with adjusted values.
				v_new_tokens.extend;
				v_new_tokens(v_new_tokens.count) := token(
					p_split_tokens(i)(token_index).type,
					p_split_tokens(i)(token_index).value,
					p_split_tokens(i)(token_index).line_number - v_line_number_difference,
					p_split_tokens(i)(token_index).column_number - v_column_number_difference,
					p_split_tokens(i)(token_index).first_char_position - v_first_char_position_diff,
					p_split_tokens(i)(token_index).last_char_position - v_last_char_position_diff,
					p_split_tokens(i)(token_index).sqlcode,
					p_split_tokens(i)(token_index).sqlerrm
				);
			end loop;

			--Add new token collection.
			v_new_split_tokens(i) := v_new_tokens;
		end if;
	end loop;

	return v_new_split_tokens;
end adjust_metadata;


--------------------------------------------------------------------------------
--Split a token stream into statements by ";".
function split_by_semicolon(p_tokens in token_table)
return token_table_table is
	v_split_tokens token_table_table := token_table_table();
	v_command_name varchar2(4000);
	v_parse_tree_index number := 1;
begin
	--Split into statements.
	loop
		--Classify.
		declare
			v_throwaway_number number;
			v_throwaway_string varchar2(32767);
		begin
			statement_classifier.classify(
				p_tokens => p_tokens,
				p_category => v_throwaway_string,
				p_statement_type => v_throwaway_string,
				p_command_name => v_command_name,
				p_command_type => v_throwaway_number,
				p_lex_sqlcode => v_throwaway_number,
				p_lex_sqlerrm => v_throwaway_string,
				p_start_index => v_parse_tree_index
			);
		end;

		--Find a terminating token based on the classification.
		--
		--TODO: CREATE OUTLINE, CREATE SCHEMA, and some others may also differ depending on presence of PLSQL_DECLARATION.
		--
		--#1: Return everything with no splitting if the statement is Invalid or Nothing.
		--    These are probably errors but the application must decide how to handle them.
		if v_command_name in ('Invalid', 'Nothing') then
			add_statement_consume_tokens(v_split_tokens, p_tokens, C_TERMINATOR_EOF, v_parse_tree_index, v_command_name);

		--#2: Match "}" for Java code.
		/*
			'CREATE JAVA', if "{" is found before first ";"
			Note: Single-line comments are different, "//".  Exclude any "", "", or "" after a
				Create java_partial_tokenizer to lex Java statements (Based on: https://docs.oracle.com/javase/specs/jls/se7/html/jls-3.html), just need:
					- multi-line comment
					- single-line comment - Note Lines are terminated by the ASCII characters CR, or LF, or CR LF.
					- character literal - don't count \'
					- string literal - don't count \"
					- {
					- }
					- other
					- Must all files end with }?  What about packages only, or annotation only file?

				CREATE JAVA CLASS USING BFILE (java_dir, 'Agent.class')
				CREATE JAVA SOURCE NAMED "Welcome" AS public class Welcome { public static String welcome() { return "Welcome World";   } }
				CREATE JAVA RESOURCE NAMED "appText" USING BFILE (java_dir, 'textBundle.dat')

				TODO: More examples using lexical structures.
		*/
		elsif v_command_name in ('CREATE JAVA') then
			--TODO
			raise_application_error(-29999, 'CREATE JAVA is not yet supported.');

		--#3: Match PLSQL_DECLARATION BEGIN and END.
		elsif v_command_name in
		(
			'CREATE MATERIALIZED VIEW ', 'CREATE SCHEMA', 'CREATE TABLE', 'CREATE VIEW',
			'DELETE', 'EXPLAIN', 'INSERT', 'SELECT', 'UPDATE', 'UPSERT'
		) then
			add_statement_consume_tokens(v_split_tokens, p_tokens, C_TERMINATOR_PLSQL_DECLARATION, v_parse_tree_index, v_command_name);

		--#4: Match PL/SQL BEGIN and END.
		elsif v_command_name in
		(
			'PL/SQL EXECUTE', 'CREATE FUNCTION','CREATE PROCEDURE', 'CREATE PACKAGE',
			'CREATE PACKAGE BODY', 'CREATE TYPE BODY', 'CREATE TRIGGER'
		) then
			add_statement_consume_tokens(v_split_tokens, p_tokens, C_TERMINATOR_PLSQL, v_parse_tree_index, v_command_name);

		--#5: Stop at first ";" for everything else.
		else
			add_statement_consume_tokens(v_split_tokens, p_tokens, C_TERMINATOR_SEMI, v_parse_tree_index, v_command_name);
		end if;

		--Quit when there are no more tokens.
		exit when v_parse_tree_index > p_tokens.count;
	end loop;

	--Fix line_number, column_number, first_char_position and last_char_position.
	v_split_tokens := adjust_metadata(v_split_tokens);

	return v_split_tokens;
end split_by_semicolon;


--------------------------------------------------------------------------------
--Split a string into separate strings by an optional delmiter, usually "/".
--This follows the SQL*Plus rules - the delimiter must be on a line by itself,
--although the line may contain whitespace before and after the delimiter.
--The delimiter and whitespace on the same line are included with the first statement.
function split_by_sqlplus_delimiter(p_statements in clob, p_sqlplus_delimiter in varchar2 default '/') return clob_table is
	v_chars varchar2_table := plsql_lexer.get_varchar2_table_from_clob(p_statements);
	v_delimiter_size number := nvl(lengthc(p_sqlplus_delimiter), 0);
	v_char_index number := 0;
	v_string clob;
	v_is_empty_line boolean := true;

	v_strings clob_table := clob_table();

	--Get N chars for comparing with multi-character delimiter.
	function get_next_n_chars(p_n number) return varchar2 is
		v_next_n_chars varchar2(32767);
	begin
		for i in v_char_index .. least(v_char_index + p_n - 1, v_chars.count) loop
			v_next_n_chars := v_next_n_chars || v_chars(i);
		end loop;

		return v_next_n_chars;
	end get_next_n_chars;

	--Check if there are only whitespace characters before the next newline
	function only_ws_before_next_newline return boolean is
	begin
		--Loop through the characters.
		for i in v_char_index + v_delimiter_size .. v_chars.count loop
			--TRUE if a newline is found.
			if v_chars(i) = chr(10) then
				return true;
			--False if non-whitespace is found.
			elsif not plsql_lexer.is_lexical_whitespace(v_chars(i)) then
				return false;
			end if;
		end loop;

		--True if neither a newline or a non-whitespace was found.
		return true;
	end only_ws_before_next_newline;
begin
	--Special cases.
	--
	--Throw an error if the delimiter is null.
	if p_sqlplus_delimiter is null then
		raise_application_error(-20000, 'The SQL*Plus delimiter cannot be NULL.');
	end if;
	--Throw an error if the delimiter contains whitespace.
	for i in 1 .. lengthc(p_sqlplus_delimiter) loop
		if plsql_lexer.is_lexical_whitespace(substrc(p_sqlplus_delimiter, i, 1)) then
			raise_application_error(-20001, 'The SQL*Plus delimiter cannot contain whitespace.');
		end if;
	end loop;
	--Return an empty string if the string is NULL.
	if p_statements is null then
		v_strings.extend;
		v_strings(v_strings.count) := p_statements;
		return v_strings;
	end if;

	--Loop through characters and build strings.
	loop
		v_char_index := v_char_index + 1;

		--Look for delimiter if it's on an empty line.
		if v_is_empty_line then
			--Add char, push, and exit if it's the last character.
			if v_char_index = v_chars.count then
				v_string := v_string || v_chars(v_char_index);
				v_strings.extend;
				v_strings(v_strings.count) := v_string;
				exit;
			--Continue if it's still whitespace.
			elsif plsql_lexer.is_lexical_whitespace(v_chars(v_char_index)) then
				v_string := v_string || v_chars(v_char_index);
			--Split string if delimiter is found.
			elsif get_next_n_chars(v_delimiter_size) = p_sqlplus_delimiter and only_ws_before_next_newline then
				--Consume delimiter.
				for i in 1 .. v_delimiter_size loop
					v_string := v_string || v_chars(v_char_index);
					v_char_index := v_char_index + 1;
				end loop;

				--Consume all tokens until either end of string or next character is non-whitespace.
				loop
					v_string := v_string || v_chars(v_char_index);
					v_char_index := v_char_index + 1;
					exit when v_char_index = v_chars.count or not plsql_lexer.is_lexical_whitespace(v_chars(v_char_index));
				end loop;

				--Remove extra increment.
				v_char_index := v_char_index - 1;

				--Add string and start over.
				v_strings.extend;
				v_strings(v_strings.count) := v_string;
				v_string := null;
				v_is_empty_line := false;
			--It's no longer an empty line otherwise.
			else
				v_string := v_string || v_chars(v_char_index);
				v_is_empty_line := false;
			end if;
		--Add the string after the last character.
		elsif v_char_index >= v_chars.count then
			v_string := v_string || v_chars(v_char_index);
			v_strings.extend;
			v_strings(v_strings.count) := v_string;
			exit;
		--Look for newlines.
		elsif v_chars(v_char_index) = chr(10) then
			v_string := v_string || v_chars(v_char_index);
			v_is_empty_line := true;
		--Else just add the character.
		else
			v_string := v_string || v_chars(v_char_index);
		end if;
	end loop;

	return v_strings;
end split_by_sqlplus_delimiter;


--------------------------------------------------------------------------------
--Split a string of separate SQL and PL/SQL statements terminated by ";" and
--some secondary terminator, usually "/".
function split_by_sqlplus_del_and_semi(p_statements in clob, p_sqlplus_delimiter in varchar2 default '/')
return token_table_table is
	v_split_statements clob_table := clob_table();
	v_split_token_tables token_table_table := token_table_table();
begin
	--First split by SQL*Plus delimiter.
	v_split_statements := split_by_sqlplus_delimiter(p_statements, p_sqlplus_delimiter);

	--Split each string further by the primary terminator, ";".
	for i in 1 .. v_split_statements.count loop
		v_split_token_tables :=
			v_split_token_tables
			multiset union
			split_by_semicolon(plsql_lexer.lex(v_split_statements(i)));
	end loop;

	--Return the statements.
	return v_split_token_tables;
end split_by_sqlplus_del_and_semi;


end;
/
