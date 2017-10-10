%%%-------------------------------------------------------------------
%%% @author ccredrock@gmail.com
%%% @copyright (C) 2017, <free>
%%% @doc
%%%
%%% @end
%%% Created : 2017年07月07日12:10:04
%%%-------------------------------------------------------------------
-module(node_alive_app).

-export([start/2, stop/1]).

%%------------------------------------------------------------------------------
-behaviour(application).

%%------------------------------------------------------------------------------
start(_StartType, _StartArgs) ->
    application:ensure_started(eredis_cluster),
    node_alive_sup:start_link().

stop(_State) ->
    ok.
