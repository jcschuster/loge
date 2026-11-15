:- module(loge, [read_program/3, capture/1, solve/2]).

% The Prolog half of Loge.Prolog.Swipl, loaded into a fresh swipl per lint or run.

% Reads every term of a UTF-8 file as consult would, in a temporary module so that
% op/3 directives apply to the terms after them. Collects findings as
% finding(Severity, Kind, From, To, Message) and the goal of each query ?- Goal as
% query(From, To), From and To character offsets.
read_program(File, Findings, Queries) :-
    in_temporary_module(Module, true,
        loge:setup_call_cleanup(open(File, read, Stream, [encoding(utf8)]),
                           loge:terms(Stream, Module, Findings, Queries),
                           close(Stream))).

terms(Stream, Module, Findings, Queries) :-
    stream_property(Stream, position(Before)),
    catch(read_term(Stream, Term,
                    [ module(Module), subterm_positions(Position),
                      singletons(Singletons), variable_names(_)
                    ]),
          error(syntax_error(Message), Context),
          Term = '$syntax_error'(Message, Context)),
    term_findings(Term, Stream, Before, Module, Position, Singletons, Findings, RestFindings),
    term_queries(Term, Position, Queries, RestQueries),
    (   Term == end_of_file
    ->  RestFindings = [], RestQueries = []
    ;   terms(Stream, Module, RestFindings, RestQueries)
    ).

term_findings(end_of_file, _, _, _, _, _, Findings, Findings) :- !.
term_findings('$syntax_error'(Message, Context), Stream, Before, _, _, _,
              [finding(error, syntax_error, From, To, Text)|Findings], Findings) :- !,
    syntax_error_offset(Context, Stream, Before, From),
    To is From + 1,
    message_to_string(error(syntax_error(Message), _), Text).
term_findings(Term, _, _, _, _, _, Findings, Findings) :-
    query(Term), !.
term_findings(Term, _, _, Module, Position, Singletons, Findings, Rest) :-
    directive(Term, Module),
    singleton_findings(Singletons, Term, Position, Findings, Rest).

% A query's variables are what it asks for, so none of them is a singleton.
query(Term) :- subsumes_term((?- _), Term).

term_queries(Term, term_position(_, _, _, _, [Goal]), [query(From, To)|Queries], Queries) :-
    query(Term), !,
    arg(1, Goal, From),
    arg(2, Goal, To).
term_queries(_, _, Queries, Queries).

% Consulting leaves the queries out; the engine asks them one by one after it.
:- multifile user:term_expansion/2.
user:term_expansion((?- _), []).

syntax_error_offset(stream(_, _, _, CharNo), _, _, CharNo) :- !.
syntax_error_offset(file(_, _, _, CharNo), _, _, CharNo) :- !.
syntax_error_offset(string(_, CharNo), _, Before, From) :- !,
    stream_position_data(char_count, Before, Start), From is Start + CharNo.
syntax_error_offset(_, _, Before, From) :-
    stream_position_data(char_count, Before, From).

directive((:- op(Priority, Type, Names)), Module) :- !,
    catch(op(Priority, Type, Module:Names), _, true).
directive(_, _).

% As consult, a variable whose name starts with an underscore is meant to occur once.
singleton_findings([], _, _, Findings, Findings).
singleton_findings([Name=_|Singletons], Term, Position, Findings, Rest) :-
    sub_atom(Name, 0, 1, _, '_'), !,
    singleton_findings(Singletons, Term, Position, Findings, Rest).
singleton_findings([Name=Variable|Singletons], Term, Position,
                   [finding(warning, singleton, From, To, Text)|Findings], Rest) :-
    (   variable_position(Term, Position, Variable, From-To)
    ->  true
    ;   Position =.. [_, From, To|_]
    ),
    format(string(Text), "Singleton variable ~w", [Name]),
    singleton_findings(Singletons, Term, Position, Findings, Rest).

variable_position(Term, From-To, Variable, From-To) :-
    var(Term), !, Term == Variable.
variable_position(Term, term_position(_, _, _, _, Positions), Variable, Found) :-
    compound(Term), !,
    compound_name_arguments(Term, _, Arguments),
    first_position(Arguments, Positions, Variable, Found).
variable_position(Term, list_position(_, _, Positions, Tail), Variable, Found) :- !,
    list_elements(Term, Positions, Elements, Rest),
    (   first_position(Elements, Positions, Variable, Found)
    ->  true
    ;   Tail \== none, variable_position(Rest, Tail, Variable, Found)
    ).
variable_position({Term}, brace_term_position(_, _, Position), Variable, Found) :- !,
    variable_position(Term, Position, Variable, Found).
variable_position(Term, parentheses_term_position(_, _, Position), Variable, Found) :-
    variable_position(Term, Position, Variable, Found).

first_position([Term|Terms], [Position|Positions], Variable, Found) :-
    (   variable_position(Term, Position, Variable, Found)
    ->  true
    ;   first_position(Terms, Positions, Variable, Found)
    ).

list_elements(List, [], [], List) :- !.
list_elements([Element|List], [_|Positions], [Element|Elements], Rest) :-
    list_elements(List, Positions, Elements, Rest).

% Sends the output and messages of the calling thread to File, and those of solve/2,
% which the bridge runs in an engine of its own, so that what consulting and solving
% print is the session's output.
:- dynamic output/1.

capture(File) :-
    open(File, write, Stream, [encoding(utf8), buffer(false)]),
    assertz(output(Stream)),
    redirect.

redirect :-
    output(Stream),
    set_stream(Stream, alias(user_output)),
    set_stream(Stream, alias(user_error)),
    set_output(Stream).

% Solves the goal in Text against user, yielding per answer the bindings of its
% named variables, in order of appearance, as [Name, Text] written as the toplevel
% writes them. Variables starting with an underscore are not shown.
solve(Text, Answer) :-
    redirect,
    term_string(Goal, Text, [variable_names(Bindings), module(user)]),
    call(user:Goal),
    include(shown, Bindings, Shown),
    maplist(binding_text(Bindings), Shown, Answer).

shown(Name=_) :- \+ sub_atom(Name, 0, 1, _, '_').

binding_text(Bindings, Name=Value, [NameText, ValueText]) :-
    atom_string(Name, NameText),
    term_string(Value, ValueText,
                [ quoted(true), variable_names(Bindings), module(user),
                  cycles(true), spacing(next_argument)
                ]).
