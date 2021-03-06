=begin pod

=head1 ANTLR4::Actions::Perl6

C<ANTLR4::Actions::Perl6> generates a perl6 representation of an ANTLR4 AST.

=head1 Synopsis

    use ANTLR4::Actions::Perl6;
    use ANTLR4::Grammar;
    my $p = ANTLR4::Actions::Perl6.new;

    say $p.parse('grammar Minimal { identifier : [A-Z][A-Za-z]+ ; }', :actions($p)).ast;
    say $p.parsefile('ECMAScript.g4', :actions($p)).ast;

=head1 Documentation

The action in this file will return a string containing a rough Perl 6
translation of the ANTLR4 grammar that the module has been given to parse.

=end pod

use v6;

my role Named { has $.name; }
my role Modified {
	has $.modifier = '';
	has $.greed = False;
}

class Action {
	also does Named;
}

class Terminal {
	also does Named;
	also does Modified;
}

class Wildcard { also does Modified; }

class EOF { also does Modified; }

class Nonterminal {
	also does Named;
	also does Modified;
}

class Range {
	also does Modified;

	has $.from;
	has $.to;
	has $.negated;
}

class CharacterSet {
	also does Modified;

	has @.content;
	has $.negated;
}

class Alternation { has @.content; }

class Concatenation { has @.content; }

class Block {
	also does Named;

	has $.type = '';
	has @.content;
}

class Grouping is Block { also does Modified; }

class Token is Block { }

class Rule is Block { has $.type = 'rule'; }

# This doesn't use the generic Block because it'll eventually be indented,
# and the grammar level is always the top level of the file.
#
class Grammar {
	also does Named;

	has $.type;
	has %.option;
	has %.import;
	has %.action;
	has @.token;
	has @.rule;
}

class ANTLR4::Actions::Perl6 {
	method ID( $/ ) { make ~$/ }
	method STRING_LITERAL( $/ ) { make ~$/[0] }
	method MODIFIER( $/ ) { make ~$/ }
	method GREED( $/ ) { make ?( ~$/ eq '?' ) }

	method tokenName( $/ ) {
		make Token.new( :name( $/<ID>.ast ) )
	}

	method token_list_trailing_comma( $/ ) {
		make $/<tokenName>>>.ast
	}

	method tokensSpec( $/ ) {
		make $/<token_list_trailing_comma>.ast
	}

	#method prequelConstruct - gave up temporarily on using tat.
	# I'll make that work later.

	# XXX The 'if $copy' shouldn't be needed because Terminals with empty
	# XXX names shouldn't ever be created.
	sub ANTLR-to-perl( $str ) {
		if $str {
			my $copy = $str;
			$copy ~~ s:g/\\u(....)/\\x[$0]/;
			$copy ~~ s:g/<!after \\>\'/\\\'/;
			$copy;
		}
		else {
			$str;
		}
	}

	# A lovely quirk of the ANTLR grammar is that nonterminals are actually
	# just a variant of the terminal, because ANTLR internally divides
	# lexer and parser grammars, and lexers can't have parser terms
	# so it's not notated separately.
	#
	method terminal( $/ ) {
		if $/<ID> {
			if $/<scalar>.ast eq 'EOF' {
				make EOF.new
			}
			else {
				make Nonterminal.new( :name( $/<scalar>.ast ) )
			}
		}
		else {
			make Terminal.new(
				:name( ANTLR-to-perl( $/<scalar>.ast ) )
			)
		}
	}

	# Keep in mind that there is no 'from' rule, so even though here we
	# reference 'STRING_LITERAL' by its alias, the actual method that
	# gets called is STRING_LITERAL.
	#
	method range( $/ ) {
		make Range.new(
			:from( ANTLR-to-perl( $/<from>.ast ) ),
			:to( ANTLR-to-perl( $/<to>.ast ) )
		)
	}

	method setElementAltList( $/ ) {
		my @content;
		for $/<setElement> {
			@content.append( $_.<terminal><scalar>.ast )
		}
		make CharacterSet.new(
			:negated( True ),
			:content( @content )
		)
	}

	method blockSet( $/ ) {
		make $/<setElementAltList>.ast
	}

	method setElement( $/ ) {
		my @content;
		for $/<LEXER_CHAR_SET> {
			@content.append( $_ )
		}
		make CharacterSet.new(
			:negated( True ),
			:content( @content )
		)
	}

	method notSet( $/ ) {
		if $/<setElement><LEXER_CHAR_SET> {
			make $/<setElement>.ast
		}
		elsif $/<blockSet> {
			make $/<blockSet>.ast
		}
		else {
			make CharacterSet.new(
				:negated( True ),
				:content(
					$/<setElement><terminal><scalar>.ast
				)
			)
		}
	}

	method DOT( $/ ) {
		make Wildcard.new;
	}

	method atom( $/ ) {
		make $/<notSet>.ast //
			$/<DOT>.ast //
			$/<range>.ast //
			$/<terminal>.ast
	}

	method blockAltList( $/ ) {
		make $/<parserElement>>>.ast
	}

	method block( $/ ) {
		make $/<blockAltList>.ast
	}

	method ebnf( $/ ) {
		make $/<block>.ast
	}

	sub is-ANTLR-terminal( $str ) {
		$str ~~ / ^ \' /;
	}

	method element( $/ ) {
		if $/<ACTION> {
			# XXX aack, ACTIONs are next to the term they refer to
			make Action.new(
				:name( ~$/<ACTION> )
			)
		}
		elsif $/<ebnfSuffix> {
			my $modifier = $/<ebnfSuffix><MODIFIER>.ast;
			my $greed = $/<ebnfSuffix><GREED>.ast // False;
			if $/<atom><terminal><scalar> and
				!is-ANTLR-terminal( ~$/<atom><terminal><scalar> ) {
				if $/<atom><terminal><scalar>.ast eq 'EOF' {
					make EOF.new(
						:modifier( $modifier ),
						:greed( $greed ),
					)
				}
				else {
					make Nonterminal.new(
						:modifier( $modifier ),
						:greed( $greed ),
						:name( $/<atom><terminal><scalar>.ast )
					)
				}
			}
			elsif $/<atom><DOT> {
				make Wildcard.new(
					:modifier( $modifier ),
					:greed( $greed )
				)
			}
			elsif $/<atom><notSet><blockSet> {
				make CharacterSet.new(
					:negated( True ),
					:modifier( $modifier ),
					:greed( $greed ),
					# XXX can improve
					:content(
$/<atom><notSet><blockSet><setElementAltList><setElement>[0]<terminal><STRING_LITERAL>.ast
					)
				)
			}
			elsif $/<atom><notSet><setElement><LEXER_CHAR_SET> {
				make CharacterSet.new(
					:negated( True ),
					:modifier( $modifier ),
					:greed( $greed ),
					# XXX can improve
					:content(
$/<atom><notSet><setElement><LEXER_CHAR_SET>>>.Str
					)
				)
			}
			elsif $/<atom><notSet><setElement><terminal> {
				make CharacterSet.new(
					:negated( True ),
					:modifier( $modifier ),
					:greed( $greed ),
					# XXX can improve
					:content(
$/<atom><notSet><setElement><terminal><STRING_LITERAL>.ast
					)
				)
			}
			elsif $/<atom>.ast {
				make Terminal.new(
					:modifier( $modifier ),
					:greed( $greed ),
					:name(
						ANTLR-to-perl(
							$/<atom><terminal><scalar>.ast
						)
					)
				)
			}
		}
		elsif $/<ebnf> {
			# XXX The // '' should probably go away...
			make Grouping.new(
				:modifier(
					$/<ebnf><ebnfSuffix><MODIFIER>.ast // ''
				),
				:greed(
					$/<ebnf><ebnfSuffix><GREED>.ast // False
				),
				:content(
					Alternation.new(
						:content( $/<ebnf>.ast )
					)
				)
			)
		}
		elsif $/<atom> {
			make $/<atom>.ast
		}
	}

	method parserElement( $/ ) {
		if $/<element>[0]<atom><range> and
			$/<element>[0]<ebnfSuffix> {
			make Range.new(
				:modifier(
					 $/<element>[0]<ebnfSuffix><MODIFIER>.ast
				),
				:greed(
					$/<element>[0]<ebnfSuffix><GREED>.ast // False
				),
				:from(
					ANTLR-to-perl(
						$/<element>[0]<atom><range><from>.ast
					)
				),
				:to(
					ANTLR-to-perl(
						$/<element>[0]<atom><range><to>.ast
					)
				),
			)
		}
		elsif $/<element>[0]<atom><notSet> and
			$/<element>[1]<atom><DOT> and
			$/<element>[2]<atom><DOT> {
			make Range.new(
				:modifier(
					$/<element>[3]<ebnfSuffix><MODIFIER>.ast // ''
				),
				:greed(
					$/<element>[3]<ebnfSuffix><GREED>.ast // False
				),
				:negated( True ),
				:from(
					ANTLR-to-perl(
						$/<element>[0]<atom><notSet><setElement><terminal><scalar>.ast
					)
				),
				:to(
					ANTLR-to-perl(
						$/<element>[3]<atom><terminal><scalar>.ast
					)
				)
			)
		}
		elsif $/<element> {
			make Concatenation.new( :content( $/<element>>>.ast ) )
		}
	}

	method parserAlt( $/ ) {
		make $/<parserElement>.ast
	}

	sub ANTLR-to-char-range( $str ) {
		if $str ~~ / ^ (.) \- (.) $ / {
			return qq{$0 .. $1}
		}
		else {
			return $str
		}
	}

	method lexerAtom( $/ ) {
		if $/<LEXER_CHAR_SET> {
			my @content;
			for $/<LEXER_CHAR_SET>[0] {
				@content.append(
					ANTLR-to-char-range(
						~$_<LEXER_CHAR_SET_RANGE>
					)
				)
			}
			make CharacterSet.new(
				#:content( $/<LEXER_CHAR_SET>>>.Str )
				:content( @content )
			)
		}
		elsif $/<terminal> {
			make Terminal.new(
				:name(
					ANTLR-to-perl(
						$/<terminal><STRING_LITERAL>.ast
					)
				)
			)
		}
	}

	method lexerElement( $/ ) {
		if $/<lexerAtom><terminal> and $/<ebnfSuffix> {
			make Terminal.new(
				:modifier( $/<ebnfSuffix><MODIFIER>.ast ),
				:greed( $/<ebnfSuffix><GREED> // False ),
				:name( $/<lexerAtom><terminal><STRING_LITERAL>.ast )
			)
		}
		elsif $/<lexerAtom><terminal> {
			if $/<lexerAtom><terminal><scalar>.ast eq 'EOF' {
				make EOF.new
			}
			else {
				make Terminal.new(
					:name( $/<lexerAtom><terminal><scalar>.ast )
				)
			}
		}
		elsif $/<lexerAtom>[0] and $/<ebnfSuffix> {
			make Wildcard.new(
				:modifier( $/<ebnfSuffix><MODIFIER>.ast ),
				:greed( $/<ebnfSuffix><GREED> // False ),
			)
		}
		elsif $/<lexerBlock> {
			make Grouping.new(
				:content(
					$/<lexerBlock><lexerAltList>.ast
				)
			)
		}
		elsif $/<ebnfSuffix> {
			if $/<lexerAtom><LEXER_CHAR_SET> {
				make CharacterSet.new(
					:modifier( $/<ebnfSuffix><MODIFIER>.ast ),
					:greed( $/<ebnfSuffix><GREED> // False ),
					:content( $/<lexerAtom><LEXER_CHAR_SET>>>.Str )
				)
			}
			elsif $/<lexerAtom><notSet><setElement> and $/<ebnfSuffix> {
				my @content;
				for $/<lexerAtom><notSet><setElement><LEXER_CHAR_SET>[0] {
					@content.append( ~$_.<LEXER_CHAR_SET_RANGE> );
				}
				make CharacterSet.new(
					:negated( True ),
					:modifier( $/<ebnfSuffix><MODIFIER>.ast ),
					:greed( $/<ebnfSuffix><GREED> // False ),
					:content( @content )
				)
			}
			elsif $/<lexerAtom><notSet> {
				my @content;
				for $/<lexerAtom><notSet><blockSet><setElementAltList><setElement> {
					@content.append( $_.<terminal><STRING_LITERAL>.ast )
				}
				make CharacterSet.new(
					:negated( True ),
					:modifier( $/<ebnfSuffix><MODIFIER>.ast ),
					:greed( $/<ebnfSuffix><GREED> // False ),
					:content( @content )
				)
			}
			else {
				make CharacterSet.new(
					:modifier( $/<ebnfSuffix><MODIFIER>.ast ),
					:greed( $/<ebnfSuffix><GREED> // False ),
					:content( $/<lexerAtom><terminal>>>.Str )
				)
			}
		}
		else {
			make $/<lexerAtom>.ast
		}
	}

	method lexerAlt( $/ ) {
		make Concatenation.new( :content( $/<lexerElement>>>.ast ) )
	}

	method parserAltList( $/ ) {
		make Alternation.new( :content( $/<parserAlt>>>.ast ) )
	}

	method lexerAltList( $/ ) {
		make Alternation.new( :content( $/<lexerAlt>>>.ast ) )
	}

	method parserRuleSpec( $/ ) {
		make Rule.new(
			:name( $/<ID>.ast ),
			:content( $/<parserAltList>.ast )
		)
	}

	method lexerRuleSpec( $/ ) {
		make Rule.new(
			:name( $/<ID>.ast ),
			:content( $/<lexerAltList>.ast )
		)
	}

	method ruleSpec( $/ ) {
		make $/<parserRuleSpec>.ast //
			$/<lexerRuleSpec>.ast
	}

	method TOP( $/ ) {
		my @token;
		my %option;
		my %action;
		my %import;
		for $/<prequelConstruct> {
			when $_.<optionsSpec> {
				for $_.<optionsSpec><option> {
					%option{ $_.<ID>.ast } =
						~$_.<optionValue>;
				}
			}
			when $_.<delegateGrammars> {
				for $_.<delegateGrammars><delegateGrammar> {
					%import{ ~$_.<key> } = 
						( $_.<value> ?? ~$_.<value> !! Any );
				}
			}
			when $_.<tokensSpec> {
				@token.append( $_.<tokensSpec>.ast );
			}
			when $_.<action> {
				%action{ ~$_.<action><action_name> } =
					~$_.<action><ACTION>;
			}
		}
		my @rule;
		for $/<ruleSpec> {
			@rule.append( $_.ast )
		}
		my $type;
		if $/<grammarType>[0] {
			$type = ~$/<grammarType>[0];
		}
		my $grammar = Grammar.new(
			:type( $type ),
			:name( $/<ID>.ast ),
			:option( %option ),
			:import( %import ),
			:action( %action ),
			:token( @token ),
			:rule( @rule )
		);
		make $grammar
	}
}

# vim: ft=perl6
