%%%-------------------------------------------------------------------
%%% @author ccredrock@gmail.com
%%% @copyright 2018 redrock
%%% @doc redis node alive
%%% @end
%%%-------------------------------------------------------------------
-module(node_alive).

-export([start/0]).

-export([get_ref/0,
         get_nodes/0]).

-export([node_type/0,
         node_id/0,
         loop_time/0,
         over_time/0]).

%% callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%------------------------------------------------------------------------------
-behaviour(gen_server).

-define(LOOP_TIME, 500). %% 500毫秒
-define(OVER_TIME, 5).   %% 5秒

-define(REDIS_HEARTBEAT(T), iolist_to_binary([<<"${node_alive}_heartbeat_">>, T])).

-record(state, {ref = 0, nodes = []}).

%%------------------------------------------------------------------------------
start() ->
    application:ensure_all_started(?MODULE).

%%------------------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec get_ref() -> pos_integer().
get_ref() ->
    case catch element(#state.ref, sys:get_state(?MODULE)) of
        {'EXIT', Reason} -> {error, Reason};
        Result -> {ok, Result}
    end.

-spec get_nodes() -> [binary()].
get_nodes() ->
    case catch element(#state.nodes, sys:get_state(?MODULE)) of
        {'EXIT', Reason} -> {error, Reason};
        Result -> {ok, Result}
    end.

-spec node_type() -> binary().
node_type() ->
    {ok, NodeType} = application:get_env(?MODULE, node_type), to_binary(NodeType).

-spec node_id() -> binary().
node_id() ->
    {ok, HostName} = inet:gethostname(),
    to_binary(application:get_env(?MODULE, node_id, HostName)).

-spec over_time() -> pos_integer().
over_time() ->
    application:get_env(?MODULE, over_time, ?OVER_TIME).

-spec loop_time() -> pos_integer().
loop_time() ->
    application:get_env(?MODULE, loop_time, ?LOOP_TIME).

%% @private
to_binary(X) when is_list(X)    -> list_to_binary(X);
to_binary(X) when is_atom(X)    -> list_to_binary(atom_to_list(X));
to_binary(X) when is_integer(X) -> integer_to_binary(X);
to_binary(X) when is_binary(X)  -> X.

%%------------------------------------------------------------------------------
init([]) ->
    {ok, handle_timeout(#state{}), 0}.

%% @hidden
handle_call(get_ref, _From, State) ->
    {reply, {ok, State#state.ref}, State};
handle_call(get_nodes, _From, State) ->
    {reply, {ok, State#state.nodes}, State};
handle_call(_Call, _From, State) ->
    {reply, ok, State}.

%% @hidden
handle_cast(_Request, State) ->
    {noreply, State}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% @hidden
handle_info(timeout, State) ->
    State1 = handle_timeout(State),
    erlang:send_after(loop_time(), self(), timeout),
    {noreply, State1};
handle_info(_Info, State) ->
    {noreply, State}.

%% @hidden
terminate(_Reason, _State) ->
    ok.

%%------------------------------------------------------------------------------
%% @private
handle_timeout(#state{ref = Ref, nodes = OldNodes} = State) ->
    Now = erlang:system_time(seconds),
    Table = ?REDIS_HEARTBEAT(node_type()),
    case catch eredis_cluster:transaction([[<<"ZADD">>, Table, Now, node_id()],
                                           [<<"ZRANGEBYSCORE">>, Table, Now - over_time(), <<"INF">>]]) of
        {ok, [_, Nodes]} ->
            case lists:sort(Nodes) of
                OldNodes -> State;
                NewNodes -> State#state{ref = Ref + 1, nodes = NewNodes}
            end;
        {_, Reason} ->
            error_logger:error_msg("node_alive error ~p~n", [Reason]), State
    end.

