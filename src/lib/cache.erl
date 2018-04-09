%%%--------------------------------------
%%% @Module  : cache
%%% @Description: 数据缓存操作（基于CouchBase）
%%%--------------------------------------
-module(cache).
-export(
    [
        start_link/2,
        mget/1,
        get/1,
        set/2,
        set/3,
        del/1,
        get_and_lock/1,
        unlock/2
    ]
).
-include("common.hrl").


start_link(ConnPoolSize, Host) ->
    cberl:start_link(?CACHE, ConnPoolSize, Host, "", "", "bitgamex").

mget(Keys)->
  case cberl:mget(?CACHE, Keys) of
    {error, _} = E -> E;
    Result -> Result
  end.

get(Key) ->
    case cberl:get(?CACHE, Key) of
        {Key, Cas, Val} -> {true, Cas, Val};
        {Key, {error, key_enoent}} -> false;
        {Key, {error, Err}} ->
            throw({?ERRNO_READ_CACHE, <<"read cache error">>}),
            {false, Err};
        {error, Err} ->
            throw({?ERRNO_READ_CACHE, <<"read cache error">>}),
            {false, Err}
    end.

set(Key, Val) ->
    cberl:set(?CACHE, Key, 0, Val).

set(Key, Val, ExpSeconds) ->
    cberl:set(?CACHE, Key, ExpSeconds, Val).

del(Key) ->
    cberl:remove(?CACHE, Key).

% 最多能锁30秒
get_and_lock(Key) ->
    case cberl:get_and_lock(?CACHE, Key, 0) of
        {Key, Cas, Val} -> {true, Cas, Val};
        {Key, {error, key_enoent}} -> false;
        {Key, {error, etmpfail}} ->
            timer:sleep(100),
            get_and_lock(Key);
        {Key, {error, Err}} ->
            throw({?ERRNO_READ_CACHE, <<"read cache error">>}),
            {false, Err};
        {error, Err} ->
            throw({?ERRNO_READ_CACHE, <<"read cache error">>}),
            {false, Err}
    end.

unlock(Key, Cas) ->
    cberl:unlock(?CACHE, Key, Cas).
    %% 如果是在run_data的事务中，只有在事务提交后才能保证数据写回完毕，这时候才能解锁，否则提前解锁会导致并发进程读出的数据是老数据
    %case run_data:in_trans() of
    %    true -> run_data:trans_set_post_commit_function(fun() -> cberl:unlock(?CACHE, Key, Cas) end);
    %    false -> cberl:unlock(?CACHE, Key, Cas)
    %end.

