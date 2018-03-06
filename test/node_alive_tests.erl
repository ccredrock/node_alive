-module(node_alive_tests).

-include_lib("eunit/include/eunit.hrl").

basic_test_() ->
    {inorder,
     {setup,
      fun() ->
              node_alive:start()
      end,
      fun(_) ->
              {ok, _} = eredis_cluster:q([<<"DEL">>, <<"${node_alive}_heartbeat_test">>]),
              {ok, _} = eredis_cluster:q([<<"DEL">>, <<"${node_alive}_ref_test">>])
      end,
      [{"redis",
        fun() ->
                ?assertEqual(ok, element(1, hd(eredis_cluster:qa([<<"INFO">>])))),
                ?assertEqual(true, erlang:is_process_alive(whereis(node_alive)))
        end},
       {"node_dead",
        fun() ->
                timer:sleep(500),
                ?assertEqual(1, element(2, node_alive:get_ref())),
                ?assertEqual(1, length(element(2, node_alive:get_nodes()))),
                LiveTime = integer_to_binary(erlang:system_time(seconds)),
                {ok, _} = eredis_cluster:q([<<"ZADD">>, <<"${node_alive}_heartbeat_test">>, LiveTime, <<"101">>]),
                timer:sleep(500),
                ?assertEqual(2, element(2, node_alive:get_ref())),
                ?assertEqual(2, length(element(2, node_alive:get_nodes()))),
                DeadTime = integer_to_binary(erlang:system_time(seconds) - 21),
                {ok, _} = eredis_cluster:q([<<"ZADD">>, <<"${node_alive}_heartbeat_test">>, DeadTime, <<"101">>]),
                timer:sleep(500),
                ?assertEqual(3, element(2, node_alive:get_ref())),
                ?assertEqual(1, length(element(2, node_alive:get_nodes())))
        end}
      ]}
    }.

