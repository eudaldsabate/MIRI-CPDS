-module(proposer).
-export([start/5]).

-define(timeout, 2000).
-define(backoff, 10).

start(Name, Proposal, Acceptors, Sleep, PanelId) ->
    spawn(fun() -> init(Name, Proposal, Acceptors, Sleep, PanelId) end).

init(Name, Proposal, Acceptors, Sleep, PanelId) ->
    {A1,A2,A3} = now(),
    random:seed(A1, A2, A3),
    timer:sleep(Sleep),
    Round = order:first(Name),
    round(Name, ?backoff, Round, Proposal, Acceptors, PanelId).

round(Name, Backoff, Round, Proposal, Acceptors, PanelId) ->
    % Update gui
    io:format("[Proposer ~w] Phase 1: round ~w proposal ~w~n",
    [Name, Round, Proposal]),
    PanelId ! {updateProp, "Round: " 
	++ io_lib:format("~p", [Round]), "Proposal: "
	++ io_lib:format("~p", [Proposal]), Proposal},
    case ballot(Name, Round, Proposal, Acceptors, PanelId) of
        {ok, Decision} ->
            io:format("[Proposer ~w] ~w DECIDED ~w in round ~w~n", 
            [Name, Acceptors, Decision, Round]),
            PanelId ! stop,
            {ok, Decision};
        abort ->
            timer:sleep(random:uniform(Backoff)),
            Next = order:inc(Round),
            round(Name, (2*Backoff), Next, Proposal, Acceptors, PanelId)
    end.

ballot(Name, Round, Proposal, Acceptors, PanelId) ->
    prepare(Round, Acceptors),
    Quorum = (length(Acceptors) div 2) + 1,
    SorryQuorum = (length(Acceptors) div 2) + 1,
    MaxVoted = order:null(),
    case collect(Quorum, SorryQuorum, Round, MaxVoted, Proposal) of
        {accepted, Value} ->
            % update gui
            io:format("[Proposer ~w] Phase 2: round ~w proposal ~w (was ~w)~n", 
            [Name, Round, Value, Proposal]),
            PanelId ! {updateProp, "Round: " 
		++ io_lib:format("~p", [Round]), "Proposal: "
		++ io_lib:format("~p", [Value]), Value},
            accept(Round, Value, Acceptors),
            case vote(Quorum, SorryQuorum, Round) of
                ok ->
                    {ok, Value};
                abort ->
                    abort
            end;
        abort ->
            abort
    end.

collect(0, _, _, _, Proposal) ->
    {accepted, Proposal};
collect(_, 0, _, _, _) ->
    abort;
collect(N, S, Round, MaxVoted, Proposal) ->
    receive 
        {promise, Round, _, na} ->
            collect(N-1, S, Round, MaxVoted, Proposal);
        {promise, Round, Voted, Value} ->
            case order:gr(Voted, MaxVoted) of
                true ->
                    collect(N-1, S, Round, Voted, Value);
                false ->
                    collect(N-1, S, Round, MaxVoted, Proposal)
            end;
        {promise, _, _,  _} ->
            collect(N, S, Round, MaxVoted, Proposal);
        {sorry, {prepare, Round}} ->
            collect(N, S-1, Round, MaxVoted, Proposal);
        {sorry, _} ->
            collect(N, S, Round, MaxVoted, Proposal)
    after ?timeout ->
            abort
    end.

vote(0, _, _) ->
    ok;
vote(_, 0, _) ->
    abort;
vote(N, S, Round) ->
    receive
        {vote, Round} ->
            vote(N-1, S, Round);
        {vote, _} ->
            vote(N, S, Round);
        {sorry, {accept, Round}} ->
            vote(N, S-1, Round);
        {sorry, _} ->
            vote(N, S, Round)
    after ?timeout ->
            abort
    end.

prepare(Round, Acceptors) ->
    Fun = fun(Acceptor) -> 
        send(Acceptor, {prepare, self(), Round}) 
    end,
    lists:foreach(Fun, Acceptors).

accept(Round, Proposal, Acceptors) ->
    Fun = fun(Acceptor) -> 
        send(Acceptor, {accept, self(), Round, Proposal}) 
    end,
    lists:foreach(Fun, Acceptors).

send(Name, Message) ->
    Name ! Message.
