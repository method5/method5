`PLSQL_LEXER` 1.0.2
============

PL/SQL Lexer solves PL/SQL language problems such as tokenizing, splitting, classifying, feedback messages, and removing terminators.

## Packages and Types

**Main Package**

 - *PLSQL_LEXER* - Convert statements into PL/SQL tokens and tokens back into strings.

**Script Execution Packages**

 - *STATEMENT_CLASSIFIER* - Classify a statement as DDL, PL/SQL, SELECT, ALTER, etc.
 - *STATEMENT_FEEDBACK* - Get a message similar to SQL*Plus feedback messages.  For example "0 rows created".
 - *STATEMENT_SPLITTER* - Split multiple statements into individual statements based on a terminator.
 - *STATEMENT_TERMINATOR* - Remove unnecessary terminating semicolon and SQL*Plus delimiters.  This prepares a statement to run as dynamic SQL.

**Code Analysis Packages**

 - *MISPLACED_HINTS* - Find hint in the wrong place.  For example, `insert into /*+ append */ ...` is incorrect because the hint should be placed immediately after the `insert`.

See the top of each file in the packages directory for more thorough documentation.

**Types**

See the file types.sql for all the type definitions.  The most important type that's central to all programs is TOKEN:

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

## How to Install

Click the "Download ZIP" button, extract the files, CD to the directory with those files, connect to SQL*Plus, and run these commands:

1. Create objects and packages on the desired schema:

        alter session set current_schema=&schema_name;
        @install

2. Install unit tests (optional):

        alter session set current_schema=&schema_name;
        @install_unit_tests

## How to uninstall

        alter session set current_schema=&schema_name;
        @uninstall

## Example

PLSQL_LEXER provides functionality for handling groups of statements.  This can
be useful for a patch system, a logging utility, or a private SQL Fiddle.

The example below shows almost all of the steps to build the backend for a
private SQL Fiddle: a website where users enter "a bunch of statements" in a
window and Oracle must run and report on their success.  The basic steps are:

1. split the string into multiple statements and loop through them
2. classify statement, for example to disallow anonymous PL/SQL blocks
3. remove semicolons from some statements to prepare them for dynamic SQL
4. Run each statement
5. Report on the success or failure of each statement

After following the installation steps above this code should be runnable:

	declare
		--A collection of statements separated by semicolons.
		--These may come from a website, text file, etc.
		v_statements clob := q'<
			create table my_table(a number);
			insert into my_table values(1);
			begin null; end;
			udpate my_table set a = 2;
		>';

		v_split_statements token_table_table;
		v_category         varchar2(100);
		v_statement_type   varchar2(100);
		v_command_name     varchar2(64);
		v_command_type     number;
		v_lex_sqlcode      number;
		v_lex_sqlerrm      varchar2(4000);
	begin
		--Tokenize and split the string into multiple statements.
		v_split_statements := statement_splitter.split_by_semicolon(
			plsql_lexer.lex(v_statements));

		--Loop through the statements.
		for i in 1 .. v_split_statements.count loop
			--Classify each statement.
			statement_classifier.classify(
				p_tokens =>         v_split_statements(i),
				p_category =>       v_category,
				p_statement_type => v_statement_type,
				p_command_name =>   v_command_name,
				p_command_type =>   v_command_type,
				p_lex_sqlcode =>    v_lex_sqlcode,
				p_lex_sqlerrm =>    v_lex_sqlerrm
			);

			--For debugging, print the statement and COMMAND_NAME.
			dbms_output.put_line(chr(10)||'Statement '||i||' : '||
				replace(replace(
					plsql_lexer.concatenate(v_split_statements(i))
				,chr(10)), chr(9)));
			dbms_output.put_line('Command Name: '||v_command_name);

			--Handle different command types.
			--
			--Prevent Anonymous Blocks from running.
			if v_command_name = 'PL/SQL EXECUTE' then
				dbms_output.put_line('Error       : Anonymous PL/SQL blocks not allowed.');
			--Warning message if "Invalid" - probably a typo.
			elsif v_command_name = 'Invalid' then
				dbms_output.put_line('Warning     : Could not classify this statement, '||
					'please check for a typo: '||
					replace(replace(substr(
						plsql_lexer.concatenate(v_split_statements(i))
					, 1, 30), chr(10)), chr(9)));
			--Warning message if "Nothing"
			elsif v_command_name = 'Nothing' then
				dbms_output.put_line('No statements found.');
			--Run everything else.
			else
				declare
					v_success_message         varchar2(4000);
					v_compile_warning_message varchar2(4000);
				begin
					--Remove extra semicolons and run.
					execute immediate to_clob(plsql_lexer.concatenate(
						statement_terminator.remove_semicolon(
							p_tokens => v_split_statements(i))));
					--Get the feedback message.
					statement_feedback.get_feedback_message(
						p_tokens => v_split_statements(i), 
						p_rowcount => sql%rowcount,
						p_success_message => v_success_message,
						p_compile_warning_message => v_compile_warning_message
					);
					--Print success message.
					dbms_output.put_line('Status      : '||v_success_message);
					--Print compile warning message, if any.
					--This happens when objects successfully compile but are invalid.
					if v_compile_warning_message is not null then
						dbms_output.put_line('Compile warning: '||v_compile_warning_message);
					end if;
				exception when others then
					dbms_output.put_line('Error       : '||dbms_utility.format_error_stack||
						dbms_utility.format_error_backtrace);
				end;
			end if;
		end loop;
	end;
	/

Results:

	Statement 1 : create table my_table(a number);
	Command Name: CREATE TABLE
	Status      : Table created.

	Statement 2 : insert into my_table values(1);
	Command Name: INSERT
	Status      : 1 row created.

	Statement 3 : begin null; end;
	Command Name: PL/SQL EXECUTE
	Error       : Anonymous PL/SQL blocks are not allowed.

	Statement 4 : udpate my_table set a = 2;
	Command Name: Invalid
	Warning     : Could not classify this statement, please check for a typo: udpate my_table set a = 2;

## License
`plsql_lexer` is licensed under the LGPL.
