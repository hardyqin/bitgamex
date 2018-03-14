%%%--------------------------------------
%%% @Module  : bg_gatesvr_cb
%%% @Description: gatesvr回调模块
%%%--------------------------------------
-module(bg_gatesvr_cb).
-export([init/2]).

-include("common.hrl").
-include("record_usr_game.hrl").
-include("record_usr_user.hrl").

init(Req, Opts) ->
    Method = cowboy_req:method(Req),
    #{a := Action} = cowboy_req:match_qs([a], Req),
    Req2 =
        try
            {ok, ResMap} = action(Method, Action, Req),
            cowboy_req:reply(200, #{}, lib_http:reply_body_succ(ResMap), Req)
        catch
            throw:{ErrNo, ErrMsg} when is_integer(ErrNo), is_binary(ErrMsg) ->
                cowboy_req:reply(500, #{}, lib_http:reply_body_fail(Action, ErrNo, ErrMsg), Req);
            throw:{HttpCode, ErrNo, ErrMsg} when is_integer(HttpCode), is_integer(ErrNo), is_binary(ErrMsg) ->
                cowboy_req:reply(HttpCode, #{}, lib_http:reply_body_fail(Action, ErrNo, ErrMsg), Req);
            _:ExceptionErr ->
                ?ERR("bg_gatesvr_cb exception:~nerr_msg=~p~nstack=~p~n", [ExceptionErr, erlang:get_stacktrace()]),
                cowboy_req:reply(500, #{}, lib_http:reply_body_fail(Action, ?ERRNO_EXCEPTION, ?T2B(ExceptionErr)), Req)
        end,
    {ok, Req2, Opts}.

action(<<"GET">>, undefined, Req) ->
    cowboy_req:reply(400, #{}, lib_http:reply_body_fail(undefined, ?ERRNO_MISSING_PARAM, <<"Missing parameter">>), Req);

% https://api.bitgamex.com/?a=login_game&uid=xx&game_id=xx&device_id=xx&time=xx&sign=xx
action(<<"GET">>, <<"login_game">> = Action, Req) ->
    ParamsMap = cowboy_req:match_qs([uid, game_id, device_id, time, sign,
                                     {device_model, [], undefined},
                                     {os_type, [], undefined},
                                     {os_ver, [], undefined},
                                     {lang, [], undefined},
                                     {org_device_id, [], undefined},
                                     {gc_id, [], undefined},
                                     {gg_id, [], undefined},
                                     {fb_id, [], undefined}], Req),
    #{uid := UidBin0, game_id := GameIdBin0, device_id := DeviceId0, time := TimeBin0, sign := Sign0,
      device_model := DeviceModel0, os_type := OsType0, os_ver := OsVer0, lang := Lang0,
      org_device_id := OrgDeviceId0, gc_id := GCId0, gg_id := GGId0, fb_id := FBId0} = ParamsMap,
    ?DBG("login_game: ~p~n", [ParamsMap]),
    L = [UidBin0, GameIdBin0, DeviceId0, TimeBin0, Sign0, DeviceModel0, OsType0, OsVer0, Lang0, OrgDeviceId0, GCId0, GGId0, FBId0],
    [UidBin, GameIdBin, DeviceId, TimeBin, Sign, DeviceModel, OsType, OsVer, Lang, OrgDeviceId, GCId, GGId, FBId] = [util:trim(One) || One <- L],
    case lists:member(<<>>, [UidBin, GameIdBin, DeviceId, TimeBin, Sign]) of
        true -> throw({400, ?ERRNO_MISSING_PARAM, <<"Missing parameter">>});
        false -> void
    end,
    Uid = binary_to_integer(UidBin),
    GameId = binary_to_integer(GameIdBin),
    Time = binary_to_integer(TimeBin),
    GameKey =
        case usr_game:get_one(GameId) of
            #usr_game{open_status = OpenStatus, game_key = GKey} ->
                case OpenStatus =:= 0 of
                    true -> throw({?ERRNO_GAME_NOT_OPEN, <<"game not open">>});
                    false -> GKey
                end;
            _ -> throw({?ERRNO_WRONG_PARAM, <<"wrong game id">>})
        end,
    MD5Bin = <<UidBin/binary, GameIdBin/binary, DeviceId/binary, TimeBin/binary, GameKey/binary>>,
    MD5Val = util:md5(MD5Bin),
    case Sign =:= list_to_binary(MD5Val) of
        false -> throw({?ERRNO_VERIFY_FAILED, <<"md5 check failed">>});
        true -> void
    end,
    {PeerIp, _} = maps:get(peer, Req),
    c_gatesvr:api_login_game([Uid, GameId, DeviceId, Time, DeviceModel, OsType, OsVer,
                              Lang, OrgDeviceId, GCId, GGId, FBId, PeerIp]);

% https://api.bitgamex.com/?a=bind_user&uid=xx&game_id=xx&token=xx&bind_type=xx&bind_val=xx&time=xx&sign=xx
action(<<"GET">>, <<"bind_user">> = Action, Req) ->
    ParamsMap = cowboy_req:match_qs([uid, game_id, token, bind_type, bind_val, time, sign], Req),
    #{uid := UidBin0, game_id := GameIdBin0, token := Token0, bind_type := BindType0, bind_val := BindVal0, time := TimeBin0, sign := Sign0} = ParamsMap,
    ?DBG("bind_user: ~p~n", [ParamsMap]),
    L = [UidBin0, GameIdBin0, Token0, BindType0, BindVal0, TimeBin0, Sign0],
    [UidBin, GameIdBin, Token, BindType, BindVal, TimeBin, Sign] = [util:trim(One) || One <- L],
    case lists:member(<<>>, [UidBin, GameIdBin, Token, BindType, BindVal, TimeBin, Sign]) of
        true -> throw({400, ?ERRNO_MISSING_PARAM, <<"Missing parameter">>});
        false -> void
    end,
    Uid = binary_to_integer(UidBin),
    GameId = binary_to_integer(GameIdBin),
    %Time = binary_to_integer(TimeBin),
    GameKey =
        case usr_game:get_one(GameId) of
            #usr_game{open_status = OpenStatus, game_key = GKey} ->
                case OpenStatus =:= 0 of
                    true -> throw({?ERRNO_GAME_NOT_OPEN, <<"game not open">>});
                    false -> GKey
                end;
            _ -> throw({?ERRNO_WRONG_PARAM, <<"wrong game id">>})
        end,
    MD5Bin = <<UidBin/binary, GameIdBin/binary, Token/binary, BindType/binary, BindVal/binary, TimeBin/binary, GameKey/binary>>,
    MD5Val = util:md5(MD5Bin),
    case Sign =:= list_to_binary(MD5Val) of
        false -> throw({?ERRNO_VERIFY_FAILED, <<"md5 check failed">>});
        true -> void
    end,
    #usr_user{current_game_id = TheGameId, session_token = TheToken} = User = usr_user:get_one(Uid),
    case TheGameId =:= GameId andalso TheToken =:= Token of
        false -> throw({?ERRNO_VERIFY_FAILED, <<"token check failed">>});
        true -> void
    end,
    c_gatesvr:api_bind_user([User, BindType, BindVal]);

% https://api.bitgamex.com/?a=get_game&uid=xx&game_id=xx&token=xx
action(<<"GET">>, <<"get_game">> = Action, Req) ->
    ParamsMap = cowboy_req:match_qs([uid, game_id, token], Req),
    #{uid := UidBin0, game_id := GameIdBin0, token := Token0} = ParamsMap,
    ?DBG("get_game: ~p~n", [ParamsMap]),
    L = [UidBin0, GameIdBin0, Token0],
    [UidBin, GameIdBin, Token] = [util:trim(One) || One <- L],
    case lists:member(<<>>, [UidBin, GameIdBin, Token]) of
        true -> throw({400, ?ERRNO_MISSING_PARAM, <<"Missing parameter">>});
        false -> void
    end,
    Uid = binary_to_integer(UidBin),
    GameId = binary_to_integer(GameIdBin),
    GameKey =
        case usr_game:get_one(GameId) of
            #usr_game{open_status = OpenStatus, game_key = GKey} ->
                case OpenStatus =:= 0 of
                    true -> throw({?ERRNO_GAME_NOT_OPEN, <<"game not open">>});
                    false -> GKey
                end;
            _ -> throw({?ERRNO_WRONG_PARAM, <<"wrong game id">>})
        end,
    #usr_user{current_game_id = TheGameId, session_token = TheToken} = User = usr_user:get_one(Uid),
    case TheGameId =:= GameId andalso TheToken =:= Token of
        false -> throw({?ERRNO_VERIFY_FAILED, <<"token check failed">>});
        true -> void
    end,
    c_gatesvr:api_get_game([User]);

% https://api.bitgamex.com/?a=save_game
% POST内容：uid=xx&game_id=xx&token=xx&game_data=xx&time=xx&sign=xx
action(<<"POST">>, <<"save_game">> = Action, Req) ->
    {ok, PostVals, Req2} = cowboy_req:body_qs(Req),
    UidBin0 = proplists:get_value(<<"uid">>, PostVals),
    GameIdBin0 = proplists:get_value(<<"game_id">>, PostVals),
    Token0 = proplists:get_value(<<"token">>, PostVals),
    GameData0 = proplists:get_value(<<"game_data">>, PostVals),
    TimeBin0 = proplists:get_value(<<"time">>, PostVals),
    Sign0 = proplists:get_value(<<"sign">>, PostVals),
    ?DBG("save_game: ~p~n", [PostVals]),
    L = [UidBin0, GameIdBin0, Token0, GameData0, TimeBin0, Sign0],
    [UidBin, GameIdBin, Token, GameData, TimeBin, Sign] = [util:trim(One) || One <- L],
    case lists:member(<<>>, [UidBin, GameIdBin, Token, GameData, TimeBin, Sign]) of
        true -> throw({400, ?ERRNO_MISSING_PARAM, <<"Missing parameter">>});
        false -> void
    end,
    Uid = binary_to_integer(UidBin),
    GameId = binary_to_integer(GameIdBin),
    %Time = binary_to_integer(TimeBin),
    GameKey =
        case usr_game:get_one(GameId) of
            #usr_game{open_status = OpenStatus, game_key = GKey} ->
                case OpenStatus =:= 0 of
                    true -> throw({?ERRNO_GAME_NOT_OPEN, <<"game not open">>});
                    false -> GKey
                end;
            _ -> throw({?ERRNO_WRONG_PARAM, <<"wrong game id">>})
        end,
    MD5Bin = <<UidBin/binary, GameIdBin/binary, Token/binary, GameData/binary, TimeBin/binary, GameKey/binary>>,
    MD5Val = util:md5(MD5Bin),
    case Sign =:= list_to_binary(MD5Val) of
        false -> throw({?ERRNO_VERIFY_FAILED, <<"md5 check failed">>});
        true -> void
    end,
    #usr_user{current_game_id = TheGameId, session_token = TheToken} = User = usr_user:get_one(Uid),
    case TheGameId =:= GameId andalso TheToken =:= Token of
        false -> throw({?ERRNO_VERIFY_FAILED, <<"token check failed">>});
        true -> void
    end,
    c_gatesvr:api_save_game([User, GameData]);

% https://api.bitgamex.com/?a=transfer_coin_in_game&uid=xx&game_id=xx&token=xx&dst_uid=xx&amount=xx&time=xx&sign=xx
action(<<"GET">>, <<"transfer_coin_in_game">> = Action, Req) ->
    ParamsMap = cowboy_req:match_qs([uid, game_id, token, dst_uid, amount, time, sign], Req),
    #{uid := UidBin0, game_id := GameIdBin0, token := Token0, dst_uid := DstUidBin0, amount := AmountBin0, time := TimeBin0, sign := Sign0} = ParamsMap,
    ?DBG("transfer_coin_in_game: ~p~n", [ParamsMap]),
    L = [UidBin0, GameIdBin0, Token0, DstUidBin0, AmountBin0, TimeBin0, Sign0],
    [UidBin, GameIdBin, Token, DstUidBin, AmountBin, TimeBin, Sign] = [util:trim(One) || One <- L],
    case lists:member(<<>>, [UidBin, GameIdBin, Token, DstUidBin, AmountBin, TimeBin, Sign]) of
        true -> throw({400, ?ERRNO_MISSING_PARAM, <<"Missing parameter">>});
        false -> void
    end,
    Uid = binary_to_integer(UidBin),
    GameId = binary_to_integer(GameIdBin),
    DstUid = binary_to_integer(DstUidBin),
    Amount = binary_to_float(AmountBin),
    %Time = binary_to_integer(TimeBin),
    GameKey =
        case usr_game:get_one(GameId) of
            #usr_game{open_status = OpenStatus, game_key = GKey} ->
                case OpenStatus =:= 0 of
                    true -> throw({?ERRNO_GAME_NOT_OPEN, <<"game not open">>});
                    false -> GKey
                end;
            _ -> throw({?ERRNO_WRONG_PARAM, <<"wrong game id">>})
        end,
    MD5Bin = <<UidBin/binary, GameIdBin/binary, Token/binary, DstUidBin/binary, AmountBin/binary, TimeBin/binary, GameKey/binary>>,
    MD5Val = util:md5(MD5Bin),
    case Sign =:= list_to_binary(MD5Val) of
        false -> throw({?ERRNO_VERIFY_FAILED, <<"md5 check failed">>});
        true -> void
    end,
    #usr_user{current_game_id = TheGameId, session_token = TheToken} = User = usr_user:get_one(Uid),
    case TheGameId =:= GameId andalso TheToken =:= Token of
        false -> throw({?ERRNO_VERIFY_FAILED, <<"token check failed">>});
        true -> void
    end,
    DstUser = usr_user:get_one(DstUid),
    case is_record(DstUser, usr_user) of
        false -> throw({?ERRNO_WRONG_PARAM, <<"wrong dst uid">>});
        true -> void
    end,
    c_gatesvr:api_transfer_coin_in_game([User, DstUser, Amount, iolist_to_binary(cowboy_req:uri(Req, #{}))]);

action(_, Action, Req) ->
    cowboy_req:reply(405, #{}, lib_http:reply_body_fail(Action, ?ERRNO_ACTION_NOT_SUPPORT, <<"Action not supported">>), Req).

