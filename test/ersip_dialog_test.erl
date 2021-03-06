%%
%% Copyright (c) 2018 Dmitry Poroh
%% All rights reserved.
%% Distributed under the terms of the MIT License. See the LICENSE file.
%%
%% Common dialog support test
%%
%% TODO:
%% - Check record route with strict route
%% - Target refreshing by request
%% - Target refreshing by response
%%


-module(ersip_dialog_test).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Cases
%%%===================================================================

dialog_create_test() ->
    InvReq = invite_request(),
    InvSipMsg = ersip_request:sipmsg(InvReq),
    InvResp180UAS = invite_reply(180, InvSipMsg),
    ?assertMatch({_, _}, ersip_dialog:uas_new(InvSipMsg, InvResp180UAS)),
    {UASDialogEarly, InvResp180UAC} = ersip_dialog:uas_new(InvSipMsg, InvResp180UAS),

    ?assertMatch({ok, _}, ersip_dialog:uac_new(InvReq, InvResp180UAC)),
    {ok, UACDialogEarly} = ersip_dialog:uac_new(InvReq, InvResp180UAC),

    InvResp200UAS = invite_reply(200, InvSipMsg),
    {UASDialogConfirmed, InvResp200UAC} = ersip_dialog:uas_update(InvResp200UAS, UASDialogEarly),

    {ok, UACDialogConfirmed} = ersip_dialog:uac_update(InvResp200UAS, UACDialogEarly),

    %% ====================
    %% Sending BYE through UAC dialog:
    {_UACDialog1, ByeSipMsgA} = ersip_dialog:uac_request(bye_sipmsg(), UACDialogConfirmed),

    %% --------------------
    %% Check that dialog identifier of UAS is equal to calculated by request:
    ?assertMatch({ok, _}, ersip_dialog:uas_dialog_id(ByeSipMsgA)),
    {ok, ByeUASDialogId} = ersip_dialog:uas_dialog_id(ByeSipMsgA),
    ?assertEqual(ersip_dialog:id(UASDialogConfirmed), ByeUASDialogId),

    %% --------------------
    %% Check that message is filled in according to dialog:
    %% 1. The URI in the To field of the request MUST be set to the
    %% remote URI from the dialog state.
    ?assertEqual(ersip_hdr_fromto:uri(ersip_sipmsg:get(to, InvSipMsg)),
                 ersip_hdr_fromto:uri(ersip_sipmsg:get(to, ByeSipMsgA))),

    %% 2. The tag in the To header field of the request MUST be set to
    %% the remote tag of the dialog ID.
    ?assertEqual(ersip_hdr_fromto:tag(ersip_sipmsg:get(to, InvResp180UAC)),
                 ersip_hdr_fromto:tag(ersip_sipmsg:get(to, ByeSipMsgA))),

    %% 3. The From URI of the request MUST be set to the local URI
    %% from the dialog state.
    ?assertEqual(ersip_hdr_fromto:uri(ersip_sipmsg:get(from, InvSipMsg)),
                 ersip_hdr_fromto:uri(ersip_sipmsg:get(from, ByeSipMsgA))),

    %% 4. The tag in the From header field of the request MUST be set to the local tag
    %% of the dialog ID
    ?assertEqual(ersip_hdr_fromto:tag(ersip_sipmsg:get(from, InvSipMsg)),
                 ersip_hdr_fromto:tag(ersip_sipmsg:get(from, ByeSipMsgA))),

    %% 5. The Call-ID of the request MUST be set to the Call-ID of the dialog.
    ?assertEqual(ersip_sipmsg:get(callid, InvSipMsg),
                 ersip_sipmsg:get(callid, ByeSipMsgA)),

    %% 6. Requests within a dialog MUST contain strictly monotonically
    %%    increasing and contiguous CSeq sequence numbers
    %%    (increasing-by-one) in each direction (excepting ACK and CANCEL
    %%    of course, whose numbers equal the requests being acknowledged
    %%    or cancelled).
    ?assert(ersip_hdr_cseq:number(ersip_sipmsg:get(cseq, InvSipMsg))
            < ersip_hdr_cseq:number(ersip_sipmsg:get(cseq, ByeSipMsgA))),

    %% 7. The method field in the CSeq header field value MUST match
    %% the method of the request.
    ?assertEqual(ersip_sipmsg:method(ByeSipMsgA),
                 ersip_hdr_cseq:method(ersip_sipmsg:get(cseq, ByeSipMsgA))),

    %% 8. If the route set is empty, the UAC MUST place the remote target URI
    %% into the Request-URI. The UAC MUST NOT add a Route header field to
    %% the request.
    [RemoteContactA] = ersip_sipmsg:get(contact, InvResp200UAC),
    ?assertEqual(ersip_hdr_contact:uri(RemoteContactA),
                 ersip_sipmsg:ruri(ByeSipMsgA)),

    %% ====================
    %% Sending BYE through UAS dialog:
    {_UASDialog1, ByeSipMsgB} = ersip_dialog:uac_request(bye_sipmsg(), UASDialogConfirmed),

    %% --------------------
    %% Check that dialog identifier of UAC is equal to calculated by request:
    ?assertMatch({ok, _}, ersip_dialog:uas_dialog_id(ByeSipMsgB)),
    {ok, ByeBDialogId} = ersip_dialog:uas_dialog_id(ByeSipMsgB),
    ?assertEqual(ersip_dialog:id(UACDialogConfirmed), ByeBDialogId),

    %% --------------------
    %% Check that message is filled in according to dialog:
    %% 1. The URI in the To field of the request MUST be set to the
    %% remote URI from the dialog state.
    ?assertEqual(ersip_hdr_fromto:uri(ersip_sipmsg:get(from, InvSipMsg)),
                 ersip_hdr_fromto:uri(ersip_sipmsg:get(to,   ByeSipMsgB))),

    %% 2. The tag in the To header field of the request MUST be set to
    %% the remote tag of the dialog ID.
    ?assertEqual(ersip_hdr_fromto:tag(ersip_sipmsg:get(from, InvResp180UAC)),
                 ersip_hdr_fromto:tag(ersip_sipmsg:get(to,   ByeSipMsgB))),

    %% 3. The From URI of the request MUST be set to the local URI
    %% from the dialog state.
    ?assertEqual(ersip_hdr_fromto:uri(ersip_sipmsg:get(to,   InvSipMsg)),
                 ersip_hdr_fromto:uri(ersip_sipmsg:get(from, ByeSipMsgB))),

    %% 4. The tag in the From header field of the request MUST be set to the local tag
    %% of the dialog ID
    ?assertEqual(ersip_hdr_fromto:tag(ersip_sipmsg:get(to,   InvResp180UAS)),
                 ersip_hdr_fromto:tag(ersip_sipmsg:get(from, ByeSipMsgB))),

    %% 5. The Call-ID of the request MUST be set to the Call-ID of the dialog.
    ?assertEqual(ersip_sipmsg:get(callid, InvSipMsg),
                 ersip_sipmsg:get(callid, ByeSipMsgB)),

    %% 6. Requests within a dialog MUST contain strictly monotonically
    %%    increasing and contiguous CSeq sequence numbers
    %%    (increasing-by-one) in each direction (excepting ACK and CANCEL
    %%    of course, whose numbers equal the requests being acknowledged
    %%    or cancelled).
    %% Filled with new value

    %% 7. The method field in the CSeq header field value MUST match
    %% the method of the request.
    ?assertEqual(ersip_sipmsg:method(ByeSipMsgB),
                 ersip_hdr_cseq:method(ersip_sipmsg:get(cseq, ByeSipMsgB))),

    %% 8. If the route set is empty, the UAC MUST place the remote target URI
    %% into the Request-URI. The UAC MUST NOT add a Route header field to
    %% the request.
    [RemoteContactB] = ersip_sipmsg:get(contact, InvSipMsg),
    ?assertEqual(ersip_hdr_contact:uri(RemoteContactB),
                 ersip_sipmsg:ruri(ByeSipMsgB)),

    ok.

uas_dialog_rfc2543_compiance_test() ->
    %% A UAS MUST be prepared to receive a
    %% request without a tag in the From field, in which case the tag is
    %% considered to have a value of null.
    %%
    %%    This is to maintain backwards compatibility with RFC 2543, which
    %%    did not mandate From tags.
    InvReq = invite_request(),
    InvSipMsg = clear_tag(from, ersip_request:sipmsg(InvReq)),
    InvResp200 = invite_reply(200, InvSipMsg),
    ?assertMatch({_, _}, ersip_dialog:uas_new(InvSipMsg, InvResp200)),
    {Dialog, _} = ersip_dialog:uas_new(InvSipMsg, InvResp200),
    %% If the value of the remote or local tags is null, the tag
    %% parameter MUST be omitted from the To or From header fields,
    %% respectively.
    {_, ByeSipMsgB} = ersip_dialog:uac_request(bye_sipmsg(), Dialog),
    ?assertEqual(undefined, ersip_hdr_fromto:tag(ersip_sipmsg:get(to, ByeSipMsgB))),

    %% Check that message sent without from tag is mached dialog
    %% created by initial invite.
    {ok, DialogA} = ersip_dialog:uac_new(InvReq, InvResp200),
    {_, ByeSipMsgA0} = ersip_dialog:uac_request(bye_sipmsg(), DialogA),
    ByeSipMsgA = clear_tag(from, ByeSipMsgA0),
    {ok, ByeADialogId} = ersip_dialog:uas_dialog_id(ByeSipMsgA),
    ?assertEqual(ersip_dialog:id(Dialog), ByeADialogId),

    ok.

uac_dialog_rfc2543_compiance_test() ->
    %% A UAC MUST be prepared to receive a response without a tag in
    %% the To field, in which case the tag is considered to have a
    %% value of null.
    %%
    %%    This is to maintain backwards compatibility with RFC 2543,
    %%    which did not mandate To tags.
    InvReq = invite_request(),
    InvSipMsg = ersip_request:sipmsg(InvReq),
    InvResp200 = clear_tag(to, invite_reply(200, InvSipMsg)),
    ?assertEqual(undefined, ersip_hdr_fromto:tag(ersip_sipmsg:get(to, InvResp200))),
    ?assertMatch({ok, _}, ersip_dialog:uac_new(InvReq, InvResp200)),
    {ok, Dialog} = ersip_dialog:uac_new(InvReq, InvResp200),
    %% If the value of the remote or local tags is null, the tag
    %% parameter MUST be omitted from the To or From header fields,
    %% respectively.
    {_, ByeSipMsg} = ersip_dialog:uac_request(bye_sipmsg(), Dialog),
    ?assertEqual(undefined, ersip_hdr_fromto:tag(ersip_sipmsg:get(to, ByeSipMsg))),

    %% Check that message sent without from tag is mached dialog
    %% created by initial invite.
    {DialogB, _} = ersip_dialog:uas_new(InvSipMsg, InvResp200),
    {_, ByeSipMsgB0} = ersip_dialog:uac_request(bye_sipmsg(), DialogB),
    ByeSipMsgB = clear_tag(from, ByeSipMsgB0),
    {ok, ByeBDialogId} = ersip_dialog:uas_dialog_id(ByeSipMsgB),
    ?assertEqual(ersip_dialog:id(Dialog), ByeBDialogId),

    ok.


indialog_ack_and_cancel_cseq_test() ->
    %% Requests within a dialog MUST contain strictly monotonically
    %% increasing and contiguous CSeq sequence numbers (increasing-by-one)
    %% in each direction (excepting ACK and CANCEL of course, whose numbers
    %% equal the requests being acknowledged or cancelled).
    {UASDialog0, UACDialog0} = create_uas_uac_dialogs(invite_request()),
    {UASDialog1, ReInviteSipMsg} = ersip_dialog:uac_request(reinvite_sipmsg(), UASDialog0),
    {_, AckSipMsg}    = ersip_dialog:uac_request(ack_sipmsg(), UASDialog1),
    {_, CancelSipMsg} = ersip_dialog:uac_request(cancel_sipmsg(), UASDialog1),
    ?assertEqual(cseq_number(ReInviteSipMsg), cseq_number(AckSipMsg)),
    ?assertEqual(cseq_number(ReInviteSipMsg), cseq_number(CancelSipMsg)),

    {UACDialog1, UACReInviteSipMsg} = ersip_dialog:uac_request(reinvite_sipmsg(), UACDialog0),
    {_, UACAckSipMsg}    = ersip_dialog:uac_request(ack_sipmsg(), UACDialog1),
    {_, UACCancelSipMsg} = ersip_dialog:uac_request(cancel_sipmsg(), UACDialog1),
    ?assertEqual(cseq_number(UACReInviteSipMsg), cseq_number(UACAckSipMsg)),
    ?assertEqual(cseq_number(UACReInviteSipMsg), cseq_number(UACCancelSipMsg)),
    ok.


uas_message_checking_cseq_test() ->
    %% 1. If the remote sequence number is empty, it MUST be set to
    %% the value of the sequence number in the CSeq header field value
    %% in the request.
    {UASDialog0, UACDialog0} = create_uas_uac_dialogs(invite_request()),
    %% Note that UAC dialog has empty remote sequence number, so we
    %% use initially UAC side as UAS for CSeq checking:
    CSeq = <<"3251">>,
    {_, ReInviteSipMsg} =
        ersip_dialog:uac_request(reinvite_sipmsg(#{cseq => CSeq}), UASDialog0),
    ?assertEqual(empty, ersip_dialog:remote_seq(UACDialog0)),
    {ok, UpdatedDialog} = ersip_dialog:uas_process(ReInviteSipMsg, target_referesh, UACDialog0),
    ?assertEqual(binary_to_integer(CSeq), ersip_dialog:remote_seq(UpdatedDialog)),

    %% If the remote sequence number was not empty, but the sequence
    %% number of the request is lower than the remote sequence number,
    %% the request is out of order and MUST be rejected with a 500
    %% (Server Internal Error) response.
    {_, ReInviteSipMsg1} = ersip_dialog:uac_request(reinvite_sipmsg(), UASDialog0),
    ReInviteSipMsg2 = set_cseq_number(3250, ReInviteSipMsg1),
    ?assertMatch({reply, _}, ersip_dialog:uas_process(ReInviteSipMsg2, target_referesh, UpdatedDialog)),
    {reply, Resp500} = ersip_dialog:uas_process(ReInviteSipMsg2, target_referesh, UpdatedDialog),
    ?assertEqual(500, ersip_sipmsg:status(Resp500)),

    %% Check that in-order message updates cseq:
    CSeqNew = 3252,
    ReInviteSipMsg3 = set_cseq_number(CSeqNew, ReInviteSipMsg1),
    ?assertMatch({ok, _}, ersip_dialog:uas_process(ReInviteSipMsg3, target_referesh, UpdatedDialog)),
    {ok, UpdatedDialog1} = ersip_dialog:uas_process(ReInviteSipMsg3, target_referesh, UpdatedDialog),
    ?assertEqual(CSeqNew, ersip_dialog:remote_seq(UpdatedDialog1)),
    ok.

loose_routing_dialog_test() ->
    %% Create dialogs with defined route set:
    {BobDialog, AliceDialog} = create_uas_uac_dialogs(invite_request(), fun loose_route/2),

    {_, ReInviteFromBob} = ersip_dialog:uac_request(reinvite_sipmsg(), BobDialog),
    RouteBob = ersip_sipmsg:get(route, ReInviteFromBob),
    ?assertEqual(ersip_uri:make(<<"sip:alice@pc33.atlanta.com">>), ersip_sipmsg:ruri(ReInviteFromBob)),
    %% Check requirements:
    %%
    %% Creating route set:
    %% 1. The route set MUST be set to the list of URIs in the
    %%    Record-Route header field from the request, taken in order
    %%    and preserving all URI parameters.
    %%
    %% Filling loose-route request:
    %% 2. If the route set is not empty, and the first URI in the
    %%    route set contains the lr parameter (see Section 19.1.1),
    %%    the UAC MUST place the remote target URI into the
    %%    Request-URI and MUST include a Route header field containing
    %%    the route set values in order, including all parameters.
    ?assertEqual(ersip_uri:make(<<"sip:biloxi.com;lr">>), ersip_hdr_route:uri(ersip_route_set:first(RouteBob))),
    ?assertEqual(ersip_uri:make(<<"sip:atlanta.com;lr">>), ersip_hdr_route:uri(ersip_route_set:last(RouteBob))),

    {_, ReInviteFromAlice} = ersip_dialog:uac_request(reinvite_sipmsg(), AliceDialog),
    RouteAlice = ersip_sipmsg:get(route, ReInviteFromAlice),
    ?assertEqual(ersip_uri:make(<<"sip:bob@192.0.2.4">>), ersip_sipmsg:ruri(ReInviteFromAlice)),
    %% Check requirements:
    %%
    %% Creating route set:
    %% 1. The route set MUST be set to the list of URIs in the
    %%    Record-Route header field from the response, taken in
    %%    reverse order and preserving all URI parameters.
    %%
    %% Filling loose-route request:
    %% 2. If the route set is not empty, and the first URI in the
    %%    route set contains the lr parameter (see Section 19.1.1),
    %%    the UAC MUST place the remote target URI into the
    %%    Request-URI and MUST include a Route header field containing
    %%    the route set values in order, including all parameters.
    ?assertEqual(ersip_uri:make(<<"sip:atlanta.com;lr">>), ersip_hdr_route:uri(ersip_route_set:first(RouteAlice))),
    ?assertEqual(ersip_uri:make(<<"sip:biloxi.com;lr">>), ersip_hdr_route:uri(ersip_route_set:last(RouteAlice))),
    ok.

strict_routing_dialog_test() ->
    %% Create dialogs with defined route set:
    {BobDialog, AliceDialog} = create_uas_uac_dialogs(invite_request(), fun strict_route/2),

    %% Check requirements:
    %%
    %% If the route set is not empty, and its first URI does not
    %% contain the lr parameter, the UAC MUST place the first URI from
    %% the route set into the Request-URI, stripping any parameters
    %% that are not allowed in a Request-URI.  The UAC MUST add a
    %% Route header field containing the remainder of the route set
    %% values in order, including all parameters.  The UAC MUST then
    %% place the remote target URI into the Route header field as the
    %% last value.
    {_, ReInviteFromBob} = ersip_dialog:uac_request(reinvite_sipmsg(), BobDialog),
    RouteBob = ersip_sipmsg:get(route, ReInviteFromBob),
    ?assertEqual(ersip_uri:make(<<"sip:biloxi.com">>), ersip_sipmsg:ruri(ReInviteFromBob)),
    ?assertEqual(ersip_uri:make(<<"sip:atlanta.com">>), ersip_hdr_route:uri(ersip_route_set:first(RouteBob))),
    ?assertEqual(ersip_uri:make(<<"sip:alice@pc33.atlanta.com">>), ersip_hdr_route:uri(ersip_route_set:last(RouteBob))),

    {_, ReInviteFromAlice} = ersip_dialog:uac_request(reinvite_sipmsg(), AliceDialog),
    RouteAlice = ersip_sipmsg:get(route, ReInviteFromAlice),
    ?assertEqual(ersip_uri:make(<<"sip:atlanta.com">>), ersip_sipmsg:ruri(ReInviteFromAlice)),
    ?assertEqual(ersip_uri:make(<<"sip:biloxi.com">>), ersip_hdr_route:uri(ersip_route_set:first(RouteAlice))),
    ?assertEqual(ersip_uri:make(<<"sip:bob@192.0.2.4">>), ersip_hdr_route:uri(ersip_route_set:last(RouteAlice))),
    ok.


%%%===================================================================
%%% Helpers
%%%===================================================================

-define(crlf, "\r\n").

invite_request() ->
    InvSipMsg = create_sipmsg(invite_request_bin(), make_default_source()),
    Target = ersip_uri:make(<<"sip:127.0.0.1">>),
    ersip_request:new(InvSipMsg, ersip_branch:make_random(7), Target).

invite_request_bin() ->
    <<"INVITE sip:bob@biloxi.com SIP/2.0" ?crlf
      "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bKnashds8" ?crlf
      "Max-Forwards: 70" ?crlf
      "To: Bob <sip:bob@biloxi.com>" ?crlf
      "From: Alice <sip:alice@atlanta.com>;tag=1928301774" ?crlf
      "Call-ID: a84b4c76e66710" ?crlf
      "CSeq: 314159 INVITE" ?crlf
      "Contact: <sip:alice@pc33.atlanta.com>" ?crlf
      "Content-Type: application/sdp" ?crlf
      "Content-Length: 4" ?crlf
      ?crlf
      "Test">>.


invite_reply(Code, InvSipMsg) ->
    InvResp = ersip_sipmsg:reply(Code, InvSipMsg),
    ersip_sipmsg:set(contact, make_contact(<<"sip:bob@192.0.2.4">>), InvResp).


create_uas_uac_dialogs(Req) ->
    create_uas_uac_dialogs(Req, fun(_, ReqResp) -> ReqResp end).

create_uas_uac_dialogs(Req, ProxyFun) ->
    InvSipMsg0 = ersip_request:sipmsg(Req),
    InvSipMsg = ProxyFun(request, InvSipMsg0),
    InvResp180UAS = invite_reply(180, InvSipMsg),
    ?assertMatch({_, _}, ersip_dialog:uas_new(InvSipMsg, InvResp180UAS)),
    {UASDialogEarly, InvResp180UAC0} = ersip_dialog:uas_new(InvSipMsg, InvResp180UAS),
    InvResp180UAC = ProxyFun(response, InvResp180UAC0),

    ?assertMatch({ok, _}, ersip_dialog:uac_new(Req, InvResp180UAC)),
    {ok, UACDialogEarly} = ersip_dialog:uac_new(Req, InvResp180UAC),

    InvResp200UAS = invite_reply(200, InvSipMsg),
    {UASDialogConfirmed, _} = ersip_dialog:uas_update(InvResp200UAS, UASDialogEarly),
    InvResp200UAC = ProxyFun(response, InvResp200UAS),

    {ok, UACDialogConfirmed} = ersip_dialog:uac_update(InvResp200UAC, UACDialogEarly),
    {UASDialogConfirmed, UACDialogConfirmed}.

bye_sipmsg() ->
    create_sipmsg(bye_bin(), make_default_source(), []).

bye_bin() ->
    <<"BYE sip:bob@biloxi.com SIP/2.0" ?crlf
      "Max-Forwards: 70" ?crlf
      ?crlf>>.

reinvite_sipmsg() ->
    reinvite_sipmsg(#{}).

reinvite_sipmsg(UserOpts) ->
    FullOpts = maps:merge(#{cseq => <<"314160">>},
                          UserOpts),
    #{cseq := CSeq} = FullOpts,
    Bin =
        <<"INVITE sip:bob@biloxi.com SIP/2.0" ?crlf
          "Max-Forwards: 70" ?crlf
          "Content-Type: application/sdp" ?crlf
          "Content-Length: 4" ?crlf
          "CSeq: ", CSeq/binary, " INVITE" ?crlf
          ?crlf
          "Test">>,
    create_sipmsg(Bin, make_default_source(), []).

ack_sipmsg() ->
    Bin =
        <<"ACK sip:bob@biloxi.com SIP/2.0" ?crlf
          "Max-Forwards: 70" ?crlf
          "Content-Type: application/sdp" ?crlf
          "Content-Length: 4" ?crlf
          "CSeq: 314160 ACK" ?crlf
          ?crlf
          "Test">>,
    create_sipmsg(Bin, make_default_source(), []).

cancel_sipmsg() ->
    Bin =
        <<"CANCEL sip:bob@biloxi.com SIP/2.0" ?crlf
          "Max-Forwards: 70" ?crlf
          "Content-Type: application/sdp" ?crlf
          "Content-Length: 4" ?crlf
          "CSeq: 314160 CANCEL" ?crlf
          ?crlf
          "Test">>,
    create_sipmsg(Bin, make_default_source(), []).

make_default_source() ->
    tcp_source(default_peer()).

default_peer() ->
    {{127, 0, 0, 1}, 5060}.

tcp_source(Peer) ->
    ersip_source:new(Peer, ersip_transport:tcp(), undefined).

create_sipmsg(Msg, Source) when is_binary(Msg) ->
    create_sipmsg(Msg, Source, all).

create_sipmsg(Msg, Source, HeadersToParse) when is_binary(Msg) ->
    P  = ersip_parser:new_dgram(Msg),
    {{ok, PMsg}, _P2} = ersip_parser:parse(P),
    PMsg1 = ersip_msg:set_source(Source, PMsg),
    {ok, SipMsg} = ersip_sipmsg:parse(PMsg1, HeadersToParse),
    SipMsg.

make_contact(ContactBin) when is_binary(ContactBin) ->
    Contact = ersip_hdr_contact:make(ContactBin),
    [Contact].

clear_tag(H, SipMsg) when H == from; H == to ->
    FromOrTo0 = ersip_sipmsg:get(H, SipMsg),
    FromOrTo = ersip_hdr_fromto:set_tag(undefined, FromOrTo0),
    ersip_sipmsg:set(H, FromOrTo, SipMsg).

cseq_number(SipMsg) ->
    ersip_hdr_cseq:number(ersip_sipmsg:get(cseq, SipMsg)).

set_cseq_number(Seq, Req) ->
    CSeq0 = ersip_sipmsg:get(cseq, Req),
    CSeq  = ersip_hdr_cseq:set_number(Seq, CSeq0),
    ersip_sipmsg:set(cseq, CSeq, Req).

loose_route(request, ReqSipMsg) ->
    %% Add proxy record route:
    RRRoutes = [<<"sip:atlanta.com;lr">>, <<"sip:biloxi.com;lr">>],
    RRSet0 = ersip_route_set:new(),
    RRSet = add_routes(RRRoutes, RRSet0),
    ersip_sipmsg:set(record_route, RRSet, ReqSipMsg);
loose_route(response, RespSipMsg) ->
    RespSipMsg.

strict_route(request, ReqSipMsg) ->
    %% Add proxy record route:
    RRRoutes = [<<"sip:atlanta.com">>, <<"sip:biloxi.com">>],
    RRSet0 = ersip_route_set:new(),
    RRSet = add_routes(RRRoutes, RRSet0),
    ersip_sipmsg:set(record_route, RRSet, ReqSipMsg);
strict_route(response, RespSipMsg) ->
    RespSipMsg.

add_routes([], RouteSet) ->
    RouteSet;
add_routes([URI|Rest], RouteSet0) ->
    Route = ersip_hdr_route:make_route(ersip_uri:make(URI)),
    RouteSet = ersip_route_set:add_first(Route, RouteSet0),
    add_routes(Rest, RouteSet).
