--------------------------------------------------------------------------------
-- Used by PLSQL_LEXER
--------------------------------------------------------------------------------
create or replace type clob_table is table of clob;
/
create or replace type varchar2_table is table of varchar2(1 char);
/
create or replace type token is object
(
	type                varchar2(4000), --String to represent token type.  See the constants in PLSQL_LEXER.
	value               clob,           --The text of the token.
	line_number         number,         --The line number the token starts at - useful for printing warning and error information.
	column_number       number,         --The column number the token starts at - useful for printing warning and error information.
	first_char_position number,         --First character position of token in the whole string - useful for inserting before a token.
	last_char_position  number,         --Last character position of token in the whole string  - useful for inserting after a token.
	sqlcode             number,         --Error code of serious parsing problem.
	sqlerrm             varchar2(4000)  --Error message of serious parsing problem.
);
/
--Use VARRAY because it is guaranteed to maintain order.
create or replace type token_table is varray(2147483647) of token;
/
--Use TABLE here to avoid an ORA-7445 error.
--TODO: Can I use a varray of a smaller size to avoid the error?
create or replace type token_table_table is table of token_table;
/


--------------------------------------------------------------------------------
-- Used by PLSQL_PARSER (EXPERIMENTAL - DO NOT DEPEND ON THESE YET!)
--------------------------------------------------------------------------------
--create or replace type number_table is table of number
--/
--create or replace type node is object
--(
--	id                  number,         --Unique identifier for the node.
--	type                varchar2(4000), --String to represent the node type.  See the constants in PLSQL_PARSER.
--	parent_id           number,         --Unique identifier of the node's parent.
--	lexer_token         token,          --Token information.
--	child_ids           number_table    --Unique identifiers of node's children.
--);
--/
--create or replace type node_table is table of node
--/


--------------------------------------------------------------------------------
-- Used by MISPLACED_HINTS
--------------------------------------------------------------------------------
create or replace type misplaced_hints_code_type is object
(
	line_number number,
	column_number number,
	line_text varchar2(4000)
);
/
create or replace type misplaced_hints_code_table is table of misplaced_hints_code_type;
/
create or replace type misplaced_hints_schema_type is object
(
	object_name varchar2(30),
	object_type varchar2(23),
	line_number number,
	column_number number,
	line_text varchar2(4000)
);
/
create or replace type misplaced_hints_schema_table is table of misplaced_hints_schema_type;
/
