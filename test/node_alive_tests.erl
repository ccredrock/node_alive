-module(node_alive_tests).

-include_lib("eunit/include/eunit.hrl").

-define(Setup, fun() -> application:start(node_alive) end).
-define(Clearnup, fun(_) -> application:stop(node_alive) end).

basic_test_() ->
    {inorder,
     {setup, ?Setup, ?Clearnup,
      [{"redis",
        fun() ->
                ?assertEqual(ok, element(1, eredis_pool:q([<<"INFO">>]))),
                ?assertEqual(true, erlang:is_process_alive(whereis(node_alive)))
        end},
       {"node_dead",
        fun() ->
                timer:sleep(1000),
                ?assertEqual(<<"1">>, element(2, eredis_pool:q([<<"ZCARD">>, <<"$node_alive_heartbeat_test">>]))),
                Now = erlang:system_time(seconds),
                LiveTime = integer_to_binary(Now),
                DeadTime = integer_to_binary(Now - 21),
                {ok, _} = eredis_pool:q([<<"ZADD">>, <<"$node_alive_heartbeat_test">>, LiveTime, <<"101">>]),
                {ok, _} = eredis_pool:q([<<"ZADD">>, <<"$node_alive_heartbeat_test">>, DeadTime, <<"102">>]),
                ?assertEqual(<<"3">>, element(2, eredis_pool:q([<<"ZCARD">>, <<"$node_alive_heartbeat_test">>]))),
                timer:sleep(2000),
                ?assertEqual(<<"2">>, element(2, eredis_pool:q([<<"ZCARD">>, <<"$node_alive_heartbeat_test">>]))),
                ?assertEqual(<<"1">>, element(2, eredis_pool:q([<<"LLEN">>, <<"$node_alive_over_test_101">>])))
        end},
       {"clean",
        fun() ->
                {ok, _} = eredis_pool:q([<<"DEL">>, <<"$node_alive_heartbeat_test">>]),
                {ok, _} = eredis_pool:q([<<"DEL">>, <<"$node_alive_master_test">>]),
                {ok, _} = eredis_pool:q([<<"DEL">>, <<"$node_alive_over_test_101">>]),
                {ok, _} = eredis_pool:q([<<"DEL">>, <<"$node_alive_over_test_102">>]),
                {ok, _} = eredis_pool:q([<<"DEL">>, <<"$node_alive_over_test_102">>])
        end}
      ]}
    }.

