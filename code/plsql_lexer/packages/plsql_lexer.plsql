create or replace package plsql_lexer is
--Copyright (C) 2015 Jon Heller.  This program is licensed under the LGPLv3.
C_VERSION constant varchar2(10) := '1.0.2';

--Main functions:
function lex(p_source in clob) return token_table;
function concatenate(p_tokens in token_table) return clob;

--Helper functions useful for some tools:
function print_tokens(p_tokens token_table) return clob;
function is_lexical_whitespace(p_char varchar2) return boolean;
function get_varchar2_table_from_clob(p_clob clob) return varchar2_table;

/*

== Purpose ==

Tokenize a SQL or PL/SQL statement.

Tokens may be one of these types:
    whitespace
        Characters 0,9,10,11,12,13,32,and unistr('\3000') (ideographic space)
    comment
        Single and multiline.  Does not include newline at end of the single line comment
    text
        Includes quotation marks, alternative quote delimiters, "Q", and "N"
    numeric
        Everything but initial + or -: ^([0-9]+\.[0-9]+|\.[0-9]+|[0-9]+)((e|E)(\+|-)?[0-9]+)?(f|F|d|D)?
    word
        May be a keyword, identifier, or (alphabetic) operator.
        The parser must distinguish between them because keywords are frequently not reserved.
    inquiry_directive
        PL/SQL preprocessor (conditional compilation) feature that is like: $$name
    preprocessor_control_token
        PL/SQL preprocessor (conditional compilation) feature that is like: $plsql_identifier
    ,}?
        3-character punctuation operators (Row Pattern Quantifier).
    ~= != ^= <> := => >= <= ** || << >> {- -} *? +? ?? ,} }? {, ..
        2-character punctuation operators.
    ! $ @ % ^ * ( ) - + = [ ] { } | : ; < , > . / ?
        1-character punctuation operators.
    EOF
        End of File.
    unexpected
        Everything else.  For example "&", a SQL*Plus character.


== Output ==

The most important output is a Token type:

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


== Requirements ==

- Only 11gR2 and above are supported.  But this will likely work well in lower versions.
- EBCDIC character set is not supported.


== Example ==

begin
	dbms_output.put_line(plsql_lexer.print_tokens(plsql_lexer.lex(
		'select * from dual;'
	)));
end;

Results:  word whitespace * whitespace word whitespace word ; EOF

*/

--Constants for token types.
C_WHITESPACE                 constant varchar2(10) := 'whitespace';
C_COMMENT                    constant varchar2(7)  := 'comment';
C_TEXT                       constant varchar2(4)  := 'text';
C_NUMERIC                    constant varchar2(7)  := 'numeric';
C_WORD                       constant varchar2(4)  := 'word';
C_INQUIRY_DIRECTIVE          constant varchar2(17) := 'inquiry_directive';
C_PREPROCESSOR_CONTROL_TOKEN constant varchar2(26) := 'preprocessor_control_token';

"C_,}?"                      constant varchar2(3)  := '_,}';

"C_~="                       constant varchar2(2)  := '~=';
"C_!="                       constant varchar2(2)  := '!=';
"C_^="                       constant varchar2(2)  := '^=';
"C_<>"                       constant varchar2(2)  := '<>';
"C_:="                       constant varchar2(2)  := ':=';
"C_=>"                       constant varchar2(2)  := '=>';
"C_>="                       constant varchar2(2)  := '>=';
"C_<="                       constant varchar2(2)  := '<=';
"C_**"                       constant varchar2(2)  := '**';
"C_||"                       constant varchar2(2)  := '||';
"C_<<"                       constant varchar2(2)  := '<<';
"C_>>"                       constant varchar2(2)  := '>>';
"C_{-"                       constant varchar2(2)  := '{-';
"C_-}"                       constant varchar2(2)  := '-}';
"C_*?"                       constant varchar2(2)  := '*?';
"C_+?"                       constant varchar2(2)  := '+?';
"C_??"                       constant varchar2(2)  := '??';
"C_,}"                       constant varchar2(2)  := ',}';
"C_}?"                       constant varchar2(2)  := '}?';
"C_{,"                       constant varchar2(2)  := '{,';
"C_.."                       constant varchar2(2)  := '..';

"C_!"                        constant varchar2(1)  := '!';
"C_@"                        constant varchar2(1)  := '@';
"C_$"                        constant varchar2(1)  := '$';
"C_%"                        constant varchar2(1)  := '%';
"C_^"                        constant varchar2(1)  := '^';
"C_*"                        constant varchar2(1)  := '*';
"C_("                        constant varchar2(1)  := '(';
"C_)"                        constant varchar2(1)  := ')';
"C_-"                        constant varchar2(1)  := '-';
"C_+"                        constant varchar2(1)  := '+';
"C_="                        constant varchar2(1)  := '=';
"C_["                        constant varchar2(1)  := '[';
"C_]"                        constant varchar2(1)  := ']';
"C_{"                        constant varchar2(1)  := '{';
"C_}"                        constant varchar2(1)  := '}';
"C_|"                        constant varchar2(1)  := '|';
"C_:"                        constant varchar2(1)  := ':';
"C_;"                        constant varchar2(1)  := ';';
"C_<"                        constant varchar2(1)  := '<';
"C_,"                        constant varchar2(1)  := ',';
"C_>"                        constant varchar2(1)  := '>';
"C_."                        constant varchar2(1)  := '.';
"C_/"                        constant varchar2(1)  := '/';
"C_?"                        constant varchar2(1)  := '?';

C_EOF                        constant varchar2(26) := 'EOF';
C_unexpected                 constant varchar2(10) := 'unexpected';

/*
Note:
	"#" is not included.
	The XMLSchema_spec clause in the manual implies that "#" is valid syntax but
	testing shows that the "#" must still be enclosed in double quotes.

*/

end;
/
create or replace package body plsql_lexer is

--Globals

g_chars varchar2_table := varchar2_table();
g_last_char varchar2(1 char);
g_line_number number;
g_column_number number;
g_last_char_position number;

--Last non-whitespace, non-comment token.
g_last_concrete_token token;
--Track when we're inside a MATCH_RECOGNIZE and a PATTERN to disambiguate "$".
--"$" is a pattern row when inside, else it could be for conditional compilation
--or an identifier name.
g_match_recognize_paren_count number;
g_pattern_paren_count number;


--------------------------------------------------------------------------------
--Get and consume one character.
function get_char return varchar2 is
begin
	--Increment last character counter.
	g_last_char_position := g_last_char_position + 1;

	--Increment line and column counters.
	if g_last_char = chr(10) then
		g_line_number := g_line_number + 1;
		g_column_number := 1;
	else
		g_column_number := g_column_number + 1;
	end if;

	--Return character.
	if g_last_char_position > g_chars.count then
		return null;
	else
		return g_chars(g_last_char_position);
	end if;
end;


--------------------------------------------------------------------------------
--Get but do not consume next character.
function look_ahead(p_offset number) return varchar2 is
begin
	if g_last_char_position + p_offset > g_chars.count then
		return null;
	else
		return g_chars(g_last_char_position + p_offset);
	end if;
end look_ahead;


--------------------------------------------------------------------------------
--From the current position, return a string that contains all possibly numeric
--characters.  The real parsing will be done by a regular expression, but we
--can at least filter out anything that's not one of 0-9,+,-,.,e,E,f,F,d,D
--'^([0-9]+\.[0-9]+|\.[0-9]+|[0-9]+)((e|E)(\+|-)?[0-9]+)?(f|F|d|D)?');
function get_potential_numeric_string return varchar2 is
	v_string varchar2(32767);
	v_numeric_position number := g_last_char_position;
begin
	loop
		exit when v_numeric_position > g_chars.count;
		exit when g_chars(v_numeric_position) not in
			(
				'0','1','2','3','4','5','6','7','8','9',
				'+','-','.','e','E','f','F','d','D'
			);

		v_string := v_string || g_chars(v_numeric_position);
		v_numeric_position := v_numeric_position + 1;
	end loop;

	return v_string;
end get_potential_numeric_string;


--------------------------------------------------------------------------------
--Is the character alphabetic, in any language.
function is_alpha(p_char varchar2) return boolean is
begin
	return regexp_like(p_char, '[[:alpha:]]');
end is_alpha;


--------------------------------------------------------------------------------
--Is the character alphabetic (in any language), numeric, or one of "_", "#", or "$".
function is_alpha_numeric_or__#$(p_char varchar2) return boolean is
begin
	return regexp_like(p_char, '[[:alpha:]]|[0-9]|\_|#|\$');
end is_alpha_numeric_or__#$;


--------------------------------------------------------------------------------
--Is the character alphabetic (in any language), numeric, or one of "_", or "#".
function is_alpha_numeric_or__#(p_char varchar2) return boolean is
begin
	return regexp_like(p_char, '[[:alpha:]]|[0-9]|\_|#');
end is_alpha_numeric_or__#;


--------------------------------------------------------------------------------
--Track tokens to detect if inside a row pattern matching.
--Row pattern matching introduces some ambiguity because the regular-expression
--syntax conflicts with "$", "**", and "||".
procedure track_row_pattern_matching(p_token token) is
begin
	--Start counters.
	if p_token.type = '('
	and g_last_concrete_token.type = c_word
	and lower(g_last_concrete_token.value) = 'pattern'
	and g_match_recognize_paren_count > 0
	and g_pattern_paren_count = 0 then
		g_pattern_paren_count := 1;
	elsif p_token.type = '('
	and g_last_concrete_token.type = c_word
	and lower(g_last_concrete_token.value) = 'match_recognize'
	and g_match_recognize_paren_count = 0 then
		g_match_recognize_paren_count := 1;
	--Increment or decrement parentheses counters.
	elsif g_pattern_paren_count > 0 and p_token.type = '(' then
		g_pattern_paren_count := g_pattern_paren_count + 1;
	elsif g_pattern_paren_count > 0 and p_token.type = ')' then
		g_pattern_paren_count := g_pattern_paren_count - 1;
	elsif g_match_recognize_paren_count > 0 and p_token.type = '(' then
		g_match_recognize_paren_count := g_match_recognize_paren_count + 1;
	elsif g_match_recognize_paren_count > 0 and p_token.type = ')' then
		g_match_recognize_paren_count := g_match_recognize_paren_count - 1;
	end if;
end track_row_pattern_matching;


--------------------------------------------------------------------------------
--Return the next token from a string.
--Type is one of: EOF, whitespace, comment, text, numeric, word, or special characters.
--See the package specification for some information on the lexer.
function get_token return token is
	v_quote_delimiter varchar2(1 char);

	--Ideally this would be a CLOB but VARCHAR2 performs much better.
	--It's extemely unlikely, but possible, for whitespace or text to be more than 32K.
	v_token_text varchar2(32767);
	--Some types, like multi-line comments, can realisitically be larger than 32k.
	v_token_clob clob;


	v_line_number number;
	v_column_number number;
	v_first_char_position number;
begin
	--Load first character.
	if g_last_char_position = 0 then
		g_last_char := get_char;
	end if;

	--Record variables at the beginning of the token.
	v_line_number := g_line_number;
	v_column_number := g_column_number;
	v_first_char_position := g_last_char_position;

	--Out of characters.
	if g_last_char_position > g_chars.count or g_chars.count = 0 then
		return token(c_eof, null, v_line_number, v_column_number, v_first_char_position, g_last_char_position, null, null);
	end if;

	--Whitespace - don't throw it out, it may contain a hint or help with pretty printing.
	if is_lexical_whitespace(g_last_char) then
		v_token_text := g_last_char;
		loop
			g_last_char := get_char;
			exit when not is_lexical_whitespace(g_last_char);
			v_token_text := v_token_text || g_last_char;
		end loop;
		return token(c_whitespace, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Single line comment.
	if g_last_char = '-' and look_ahead(1) = '-' then
		v_token_text := g_last_char || get_char;
		loop
			g_last_char := get_char;
			--chr(13) by itself does not count.
			exit when g_last_char = chr(10) or g_last_char is null;
			v_token_text := v_token_text || g_last_char;
		end loop;
		return token(c_comment, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Multi-line comment.  Use CLOB instead of VARCHAR2 to hold data.
	if g_last_char = '/' and look_ahead(1) = '*' then
		v_token_clob := g_last_char || get_char;
		loop
			g_last_char := get_char;
			if g_last_char = '*' and look_ahead(1) = '/' then
				v_token_clob := v_token_clob || g_last_char;
				g_last_char := get_char;
				v_token_clob := v_token_clob || g_last_char;
				g_last_char := get_char;
				exit;
			end if;
			if look_ahead(1) is null then
				v_token_clob := v_token_clob || g_last_char;
				g_last_char := get_char;
				return token(c_comment, v_token_clob, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, -01742, 'comment not terminated properly');
			end if;
			v_token_clob := v_token_clob || g_last_char;
		end loop;
		return token(c_comment, v_token_clob, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Text.
	if g_last_char = '''' then
		v_token_text := g_last_char;
		loop
			g_last_char := get_char;
			--Ignore escaped strings.
			if g_last_char = '''' and look_ahead(1) = '''' then
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
			elsif g_last_char = '''' and (look_ahead(1) is null or look_ahead(1) <> '''') then
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				exit;
			elsif look_ahead(1) is null then
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				return token(c_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, -01756, 'quoted string not properly terminated');
			end if;
			v_token_text := v_token_text || g_last_char;
		end loop;
		return token(c_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Nvarchar text.
	if lower(g_last_char) = 'n' and look_ahead(1) = '''' then
		--Consume 2 characters: n and the quote.
		v_token_text := g_last_char;
		g_last_char := get_char;
		v_token_text := v_token_text||g_last_char;
		loop
			g_last_char := get_char;
			--Ignore escaped strings.
			if g_last_char = '''' and look_ahead(1) = '''' then
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
			elsif g_last_char = '''' and (look_ahead(1) is null or look_ahead(1) <> '''') then
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				exit;
			elsif look_ahead(1) is null then
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				return token(c_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, -01756, 'quoted string not properly terminated');
			end if;
			v_token_text := v_token_text || g_last_char;
		end loop;
		return token(c_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Alternative quoting mechanism.
	if lower(g_last_char) = 'q' and look_ahead(1) = '''' then
		--Consume 3 characters: q, quote, and the quote delimiter.
		v_token_text := g_last_char;
		g_last_char := get_char;
		v_token_text := v_token_text||g_last_char;
		g_last_char := get_char;
		v_token_text := v_token_text||g_last_char;
		--The ending delimiter is different in a few cases.
		v_quote_delimiter := case g_last_char
			when '[' then ']'
			when '{' then '}'
			when '<' then '>'
			when '(' then ')'
			else g_last_char
		end;

		loop
			g_last_char := get_char;
			if g_last_char = v_quote_delimiter and look_ahead(1) = '''' then
				--"Alternative quotes (q'#...#') cannot use spaces, tabs, or carriage returns as delimiters".
				--(The error says carriage return, but testing indicates they really mean newlines)
				if g_last_char in (chr(9), chr(10), chr(32)) then
					v_token_text := v_token_text || g_last_char;
					g_last_char := get_char;
					v_token_text := v_token_text || g_last_char;
					g_last_char := get_char;
					return token(c_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, -00911, 'invalid character');
				end if;

				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				exit;
			end if;
			if look_ahead(1) is null then
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				return token(c_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, -01756, 'quoted string not properly terminated');
			end if;
			v_token_text := v_token_text || g_last_char;
		end loop;
		return token(c_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Nvarchar alternative quoting mechanism.
	if lower(g_last_char) = 'n' and lower(look_ahead(1)) = 'q' and look_ahead(2) = '''' then
		--Consume 4 characters: n, q, quote, and the quote delimiter.
		v_token_text := g_last_char;
		g_last_char := get_char;
		v_token_text := v_token_text||g_last_char;
		g_last_char := get_char;
		v_token_text := v_token_text||g_last_char;
		g_last_char := get_char;
		v_token_text := v_token_text||g_last_char;
		--The ending delimiter is different in a few cases.
		v_quote_delimiter := case g_last_char
			when '[' then ']'
			when '{' then '}'
			when '<' then '>'
			when '(' then ')'
			else g_last_char
		end;

		loop
			g_last_char := get_char;
			if g_last_char = v_quote_delimiter and look_ahead(1) = '''' then
				--"Alternative quotes (q'#...#') cannot use spaces, tabs, or carriage returns as delimiters".
				--(The error says carriage return, but also includes newlines)
				if g_last_char in (chr(9), chr(10), chr(32)) then
					v_token_text := v_token_text || g_last_char;
					g_last_char := get_char;
					v_token_text := v_token_text || g_last_char;
					g_last_char := get_char;
					return token(c_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, -00911, 'invalid character');
				end if;

				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				exit;
			end if;
			if look_ahead(1) is null then
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				return token(c_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, -01756, 'quoted string not properly terminated');
			end if;
			v_token_text := v_token_text || g_last_char;
		end loop;
		return token(c_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Numeric.
	--This follows the BNF diagram, except it doesn't include leading + or -.
	--And note that the diagram incorrectly implies '3+3' is a number,
	--the (E|e)?(+|-)? is incorrect.
	--http://docs.oracle.com/database/121/SQLRF/img/number.gif
	if g_last_char between '0' and '9' or (g_last_char = '.' and look_ahead(1) between '0' and '9') then
		declare
			v_substring varchar2(32767) := get_potential_numeric_string();
		begin
			--Note: Combining classes, anchors, and regexp_substr positions other than 1 do not always work.
			--Note: This won't work with numbers larger than 1K characters,
			--a ridiculous number that would cause a runtime error, but is theoretically valid.
			v_token_text := regexp_substr(
				v_substring,
				'^([0-9]+\.[0-9]+|\.[0-9]+|[0-9]+)((e|E)(\+|-)?[0-9]+)?(f|F|d|D)?');
		end;

		--Advance the characters.
		--Regular "length" is fine here since numerics cannot be more than one code point.
		g_last_char_position := g_last_char_position + length(v_token_text) - 1;
		g_column_number := g_column_number + length(v_token_text) - 1;

		g_last_char := get_char;
		return token(c_numeric, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Word - quoted identifier.  Note that quoted identifiers are not escaped.
	--Do *not* check for these errors in words:
	--"ORA-00972: identifier is too long" or "ORA-01741: illegal zero-length identifier".
	--Database links have different rules, like 128 bytes instead of 30, and we
	--won't know if it's a database link name until parse time.
	if g_last_char = '"' then
		v_token_text := g_last_char;
		loop
			g_last_char := get_char;
			if g_last_char = '"'then
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				exit;
			end if;
			if look_ahead(1) is null then
				v_token_text := v_token_text || g_last_char;
				g_last_char := get_char;
				return token(c_word, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, -01740, 'missing double quote in identifier');
			end if;
			v_token_text := v_token_text || g_last_char;
		end loop;
		return token(c_word, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Word.
	--Starts with alpha (in any language!), may contain number, "_", "$", and "#".
	if is_alpha(g_last_char) then
		v_token_text := g_last_char;
		loop
			g_last_char := get_char;

			--"$" does not count as part of the word when inside a row pattern match.
			if g_pattern_paren_count > 0 then
				if g_last_char is null or not is_alpha_numeric_or__#(g_last_char) then
					exit;
				end if;
			else
				if g_last_char is null or not is_alpha_numeric_or__#$(g_last_char) then
					exit;
				end if;
			end if;

			v_token_text := v_token_text || g_last_char;
		end loop;
		return token(c_word, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Inquiry Directive.
	--Starts with $$ alpha (in any language!), may contain number, "_", "$", and "#".
	if g_last_char = '$' and look_ahead(1) = '$' and is_alpha(look_ahead(2)) then
		v_token_text := g_last_char || get_char;
		v_token_text := v_token_text || get_char;
		loop
			g_last_char := get_char;
			if g_last_char is null or not is_alpha_numeric_or__#$(g_last_char) then
				exit;
			end if;
			v_token_text := v_token_text || g_last_char;
		end loop;
		return token(c_inquiry_directive, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Preprocessor Control Token.
	--Starts with $ alpha (in any language!), may contain number, "_", "$", and "#".
	if g_last_char = '$' and is_alpha(look_ahead(1)) then
		v_token_text := g_last_char || get_char;
		loop
			g_last_char := get_char;
			if g_last_char is null or not is_alpha_numeric_or__#$(g_last_char) then
				exit;
			end if;
			v_token_text := v_token_text || g_last_char;
		end loop;
		return token(c_preprocessor_control_token, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--3-character punctuation operators.
	--12c Row Pattern Quantifiers introduced a lot of regular-expression operators.
	if g_last_char||look_ahead(1)||look_ahead(2) in (',}?') then
		v_token_text := g_last_char || get_char || get_char;
		g_last_char := get_char;
		return token(v_token_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--2-character punctuation operators.
	--Ignore the IBM "not" character - it's in the manual but is only supported
	--on obsolete platforms: http://stackoverflow.com/q/9305925/409172
	if g_last_char||look_ahead(1) in ('~=','^=','<>',':=','=>','>=','<=','<<','>>','{-','-}','*?','+?','??',',}','}?','{,','..') then
		v_token_text := g_last_char || get_char;
		g_last_char := get_char;
		return token(v_token_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Ambiguity - "!=" usually means "not equals to", but the "!" can mean "the database calling the link".  For example:
	--  select * from dual where sysdate@!=sysdate;   Those characters should be separated - "@", "!", and "=".
	if g_last_char||look_ahead(1) in ('!=') then
		if g_last_concrete_token.type = '@' then
			null;
		else
			v_token_text := g_last_char || get_char;
			g_last_char := get_char;
			return token(v_token_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
		end if;
	end if;

	--Ambiguity - "**" and "||" are only 2-character operators outside of row pattern matching.
	if g_last_char||look_ahead(1) in ('**','||') and g_pattern_paren_count = 0 then
		v_token_text := g_last_char || get_char;
		g_last_char := get_char;
		return token(v_token_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--1-character punctuation operators.
	if g_last_char in ('!', '@','%','^','*','(',')','-','+','=','[',']','{','}','|',':',';','<',',','>','.','/','?') then
		v_token_text := g_last_char;
		g_last_char := get_char;
		return token(v_token_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--"$" only counts as "$" inside row pattern matching.
	if g_last_char = '$' and g_pattern_paren_count > 0 then
		v_token_text := g_last_char;
		g_last_char := get_char;
		return token(v_token_text, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
	end if;

	--Unexpected - everything else.
	v_token_text := g_last_char;
	g_last_char := get_char;
	return token(c_unexpected, v_token_text, v_line_number, v_column_number, v_first_char_position, g_last_char_position-1, null, null);
end get_token;


--------------------------------------------------------------------------------
--Convert a string into a VARRAY of tokens.
function lex(p_source clob) return token_table is
	v_token token;
	v_tokens token_table := token_table();
begin
	--Initialize globals.
	g_chars := get_varchar2_table_from_clob(p_source);
	--set_g_chars(p_source);
	g_last_char_position := 0;
	g_line_number := 1;
	g_column_number := 0;
	g_last_concrete_token := token(null, null, null, null, null, null, null, null);
	g_match_recognize_paren_count := 0;
	g_pattern_paren_count := 0;

	--Get all the tokens.
	loop
		v_token := get_token;
		v_tokens.extend;
		v_tokens(v_tokens.count) := v_token;
		track_row_pattern_matching(v_token);
		if v_token.type not in (c_whitespace, c_comment, c_eof) then
			g_last_concrete_token := v_token;
		end if;
		exit when v_token.type = c_eof;
	end loop;

	--Return them.
	return v_tokens;
end lex;


--------------------------------------------------------------------------------
--Convert the tokens into an CLOB.
function concatenate(p_tokens in token_table) return clob
is
	v_clob clob;
begin
	for i in 1 .. p_tokens.count loop
		v_clob := v_clob || p_tokens(i).value;
	end loop;

	return v_clob;
end concatenate;


--------------------------------------------------------------------------------
--Print tokens for debugging.
function print_tokens(p_tokens token_table) return clob is
	v_output clob;
begin
	for i in 1 .. p_tokens.count loop
		v_output := v_output||' '||p_tokens(i).type;
	end loop;

	return substr(v_output, 2);
end print_tokens;


--------------------------------------------------------------------------------
--Is the character white space.
function is_lexical_whitespace(p_char varchar2) return boolean is
begin
	/*
	--Find single-byte whitespaces.
	--ASSUMPTION: There are no 3 or 4 byte white space characters.
	declare
		c1 varchar2(1); c2 varchar2(1); c3 varchar2(1); c4 varchar2(1);
		v_string varchar2(10);
		v_throwaway number;
	begin
		for n1 in 0..15 loop c1 := trim(to_char(n1, 'XX'));
		for n2 in 0..15 loop c2 := trim(to_char(n2, 'XX'));
		for n3 in 0..15 loop c3 := trim(to_char(n3, 'XX'));
		for n4 in 0..15 loop c4 := trim(to_char(n4, 'XX'));
			v_string := unistr('\'||c1||c2||c3||c4);
			begin
				execute immediate 'select 1 a '||v_string||' from dual' into v_throwaway;
				dbms_output.put_line('Whitespace character: \'||c1||c2||c3||c4);
			exception when others then null;
			end;
		end loop; end loop; end loop; end loop;
	end;
	*/

	--These results are not the same as the regular expression "\s".
	--There are dozens of Unicode white space characters, but only these
	--are considered whitespace in PL/SQL or SQL.
	--For performance, list characters in order of popularity, and only use
	--UNISTR when necessary.
	if p_char in
	(
		chr(32),chr(10),chr(9),chr(13),chr(0),chr(11),chr(12),unistr('\3000')
	) then
		return true;
	else
		return false;
	end if;
end is_lexical_whitespace;


--------------------------------------------------------------------------------
--Create a nested table of characters.
--This extra step takes care of non-trivial Unicode processing up front.
--This cannot be simplified with SUBSTRC, that will not work for large CLOBs.
--TODO: Is there an easier way to do this?
function get_varchar2_table_from_clob(p_clob clob) return varchar2_table
is
	v_varchar2 varchar2(32767 byte);

	v_chars varchar2_table := varchar2_table();

	v_offset_not_on_char_boundary exception;
	pragma exception_init(v_offset_not_on_char_boundary, -22831);

	v_next_char_boundary number := 1;
	v_amount_to_read constant number := 8000;
begin
	--Return empty collection is there's nothing.
	if p_clob is null then
		return v_chars;
	--Convert CLOB to VARCHAR2 the easy way if it's small enough.
	elsif dbms_lob.getLength(p_clob) <= 8191 then
		v_varchar2 := p_clob;
		for i in 1 .. lengthc(v_varchar2) loop
			v_chars.extend();
			v_chars(v_chars.count) := substrc(v_varchar2, i, 1);
		end loop;
	--Convert CLOB to VARCHAR2 the hard way if it's too large.
	else
		--Convert multiple characters from CLOB to VARCHAR2 at once.
		--This is tricky because CLOBs use UCS and VARCHARs use UTF8.
		--Some single-characters in VARCHAR2 use 2 UCS code points.
		--They can be treated as 2 separate characters but must be selected together.
		--Oracle will not throw an error if SUBSTR reads half a character at the end.
		--But it does error if it starts at a bad character.
		--The code below finds the valid character boundary first, and then reads up to it.
		for i in 1 .. ceil(dbms_lob.getLength(p_clob)/v_amount_to_read) loop
			begin
				--Check if the next boundary is OK by trying to read a small amount.
				--TODO: Checking 2 bytes is as expensive as retrieving all data.  Pre-fetch and use later if valid?
				v_varchar2 := dbms_lob.substr(lob_loc => p_clob, offset => v_next_char_boundary + v_amount_to_read, amount => 2);

				--If it's ok, grab the data and increment the character boundary.
				v_varchar2 := dbms_lob.substr(lob_loc => p_clob, offset => v_next_char_boundary, amount => v_amount_to_read);
				v_next_char_boundary := v_next_char_boundary + v_amount_to_read;

			--If it wasn't successful, grab one less character and set character boundary to one less.
			exception when v_offset_not_on_char_boundary then
				v_varchar2 := dbms_lob.substr(lob_loc => p_clob, offset => v_next_char_boundary, amount => v_amount_to_read - 1);
				v_next_char_boundary := v_next_char_boundary + v_amount_to_read - 1;
			end;

			--Loop through VARCHAR2 and convert it to array.
			for i in 1 .. lengthc(v_varchar2) loop
				v_chars.extend();
				v_chars(v_chars.count) := substrc(v_varchar2, i, 1);
			end loop;
		end loop;
	end if;

	return v_chars;

end get_varchar2_table_from_clob;

end;
/
