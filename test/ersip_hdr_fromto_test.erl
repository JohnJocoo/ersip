%%
%% Copyright (c) 2018 Dmitry Poroh
%% All rights reserved.
%% Distributed under the terms of the MIT License. See the LICENSE file.
%%
%% SIP From/to header tests
%%

-module(ersip_hdr_fromto_test).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Cases
%%%===================================================================

parse_test() ->
    URIBin = <<"sip:alice@atlanta.com">>,
    { ok, URI } = ersip_uri:parse(URIBin),

    To = success_parse_fromto(<<"Alice <", URIBin/binary, ">;tag=1928301774">>),
    ?assertEqual({ display_name,  [ <<"Alice">> ] }, ersip_hdr_fromto:display_name(To)),
    ?assertEqual({ tag, <<"1928301774">> }, ersip_hdr_fromto:tag(To)),
    ?assertEqual(URI, ersip_hdr_fromto:uri(To)),

    To1 = success_parse_fromto(<<"Alice <", URIBin/binary, ">">>),
    ?assertEqual({ display_name,  [ <<"Alice">> ] }, ersip_hdr_fromto:display_name(To1)),
    ?assertEqual(undefined, ersip_hdr_fromto:tag(To1)),
    ?assertEqual(URI, ersip_hdr_fromto:uri(To1)),

    To2 = success_parse_fromto(<<"<", URIBin/binary, ">;Some=y">>),
    ?assertEqual({ display_name, [] }, ersip_hdr_fromto:display_name(To2)),
    ?assertEqual(#{ <<"some">> => <<"y">> }, ersip_hdr_fromto:params(To2)),

    To3 = success_parse_fromto(<<URIBin/binary, ";tag=1928301774">>),
    ?assertEqual({ display_name,  [] }, ersip_hdr_fromto:display_name(To3)),
    ?assertEqual({ tag, <<"1928301774">> }, ersip_hdr_fromto:tag(To3)),
    ?assertEqual(URI, ersip_hdr_fromto:uri(To3)).

parse_fail_test() ->
    ?assertMatch({error, _}, ersip_hdr_fromto:parse(create(<<"a@b">>))),
    ?assertMatch({error, _}, ersip_hdr_fromto:parse(create(<<"sip:a@b;tag=\"123\"">>))),
    ?assertMatch({error, _}, ersip_hdr_fromto:parse(create(<<"sip:a@b;my_param=&">>))),
    NoValue = ersip_hdr:new(<<"To">>),
    ?assertMatch({error, _}, ersip_hdr_fromto:parse(NoValue)),
    NValues = ersip_hdr:new(<<"To">>),
    NValues1 = ersip_hdr:add_values([ <<"Alice <sip:a@b>">>,
                                      <<"Bob <sip:b@a>">> ],
                                    NValues),
    ?assertMatch({error, _}, ersip_hdr_fromto:parse(NValues1)).

make_test() ->
    URIBin = <<"sip:alice@atlanta.com">>,
    { ok, URI } = ersip_uri:parse(URIBin),
    To = ersip_hdr_fromto:make(<<"Alice <", URIBin/binary, ">;tag=1928301774">>),
    ?assertEqual({ display_name,  [ <<"Alice">> ] }, ersip_hdr_fromto:display_name(To)),
    ?assertEqual({ tag, <<"1928301774">> }, ersip_hdr_fromto:tag(To)),
    ?assertEqual(URI, ersip_hdr_fromto:uri(To)),
    ?assertError({ error, _ }, ersip_hdr_fromto:make(<<>>)).

tag_key_test() ->
    ?assertEqual({ tag_key, <<"1928301774">> }, tag_key(<<"sip:a@b;tag=1928301774">>)),
    ?assertEqual({ tag_key, <<"abc">> }, tag_key(<<"sip:a@b;tag=ABC">>)),
    ?assertEqual(undefined, tag_key(<<"sip:a@b">>)).


%%%===================================================================
%%% Helpers
%%%===================================================================
create(Bin) ->
    H = ersip_hdr:new(<<"To">>),
    ersip_hdr:add_value(Bin, H).

success_parse_fromto(Bin) ->
    H = create(Bin),
    { ok, Hdr } = ersip_hdr_fromto:parse(H),
    Hdr.

tag_key(Bin) ->
    ersip_hdr_fromto:tag_key(ersip_hdr_fromto:make(Bin)).