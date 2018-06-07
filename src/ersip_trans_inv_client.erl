%%
%% Copyright (c) 2018 Dmitry Poroh
%% All rights reserved.
%% Distributed under the terms of the MIT License. See the LICENSE file.
%%
%% Client INVITE transaction
%%
%% Pure FSM implementation - transformation events to side effects.
%%


-module(ersip_trans_inv_client).

-export([new/3,
         event/2
        ]).


%%%===================================================================
%%% Types
%%%===================================================================

-record(trans_inv_client, {state     = fun 'Calling'/2 :: state(),
                           transport                  :: transport_type(),
                           options                    :: ersip:sip_options(),
                           request                    :: ersip_request:request(),
                           clear_reason = normal      :: ersip_trans_se:clear_reason(),
                           timer_a_timeout = 500      :: pos_integer()
                          }).
-type trans_inv_client() :: #trans_inv_client{}.
-type result() :: {trans_inv_client(), [ersip_trans_se:side_effect()]}.
-type transport_type() :: reliable | unreliable.
-type state()   :: fun((event(), trans_inv_client()) -> result()).
-type event()   :: term().
-type timer_type() :: term().

%%%===================================================================
%%% API
%%%===================================================================

-spec new(Reliable, Request, Options) -> result() when
      Reliable :: reliable | unreliable,
      Request  :: ersip_request:request(),
      Options  :: ersip:sip_options().
new(ReliableTranport, Request, Options) ->
    SipMsg = ersip_request:sipmsg(Request),
    case ersip_sipmsg:type(SipMsg) of
        request ->
            new_impl(ReliableTranport, Request, Options);
        response ->
            error({api_error, <<"client transaction must be initialyzed with INVITE request">>})
    end.

-spec event(Event, trans_inv_client()) -> result() when
      Event :: {timer, timer_type()}
             | {send, ersip_sipmsg:sipmsg()}.
event(_Event, #trans_inv_client{} = Trans) ->
    {Trans, []}.

%%%===================================================================
%%% Internal implementation
%%%===================================================================

-define(default_options,
        #{sip_t1 => 500,
          sip_t2 => 4000,
          sip_t4 => 5000
         }).
-define(T1(InvServerTrans), maps:get(sip_t1, InvServerTrans#trans_inv_client.options)).

-spec new_impl(Reliable, Request, Options) -> result() when
      Reliable :: reliable | unreliable,
      Request  :: ersip_request:request(),
      Options  :: ersip:sip_options().
new_impl(TransportType, Request, Options) ->
    %% The initial state, "calling", MUST be entered when the TU
    %% initiates a new client transaction with an INVITE request.  The
    %% client transaction MUST pass the request to the transport layer for
    %% transmission (see Section 18).
    Trans = #trans_inv_client{
               transport = TransportType,
               options   = maps:merge(?default_options, Options),
               request   = Request
              },
    Result0 = {Trans, [ersip_trans_se:send_request(Request)]},
    %% If an unreliable transport is being
    %% used, the client transaction MUST start timer A with a value of T1.
    Result1 =
        case TransportType of
            reliable ->
                Result0;
            unreliable ->
                Timeout = ?T1(Trans),
                {Trans1, SE1} = Result0,
                Trans2 = Trans1#trans_inv_client{timer_a_timeout = Timeout},
                set_timer_a(Timeout, {Trans2, SE1})
        end,
    %% For any transport, the client transaction MUST start timer B with a value
    %% of 64*T1 seconds (Timer B controls transaction timeouts).
    set_timer_b(64 * ?T1(Trans), Result1).

-spec 'Calling'(event(), trans_inv_client()) -> result().
'Calling'({timer, timer_a}, #trans_inv_client{request = Req, timer_a_timeout = TimerATimeout} = Trans) ->
    %% When timer A fires 2*T1 seconds later, the request MUST be
    %% retransmitted again (assuming the client transaction is still in this
    %% state).  This process MUST continue so that the request is
    %% retransmitted with intervals that double after each transmission.
    NewTimerATimeout = 2*TimerATimeout,
    Trans2 = Trans#trans_inv_client{timer_a_timeout = NewTimerATimeout},
    Result = {Trans2, [ersip_trans_se:send_request(Req)]},
    set_timer_a(NewTimerATimeout, Result);
'Calling'({timer, timer_b}, #trans_inv_client{} = Trans) ->
    %% If the client transaction is still in the "Calling" state when timer
    %% B fires, the client transaction SHOULD inform the TU that a timeout
    %% has occurred.
    terminate(timeout, Trans);
'Calling'({resp, provisional, SipMsg}, #trans_inv_client{} = Trans) ->
    %% If the client transaction receives a provisional response while
    %% in the "Calling" state, it transitions to the "Proceeding"
    %% state. In the "Proceeding" state, the client transaction SHOULD
    %% NOT retransmit the request any longer. Furthermore, the
    %% provisional response MUST be passed to the TU.
    Trans1 = set_state(fun 'Proceeding'/2, Trans),
    {Trans1, [ersip_trans_se:tu_result(SipMsg)]};
'Calling'({resp, final, SipMsg}, #trans_inv_client{request = Req} = Trans) ->
    %% When in either the "Calling" or "Proceeding" states, reception
    %% of a response with status code from 300-699 MUST cause the
    %% client transaction to transition to "Completed". The client
    %% transaction MUST pass the received response up to the TU, and
    %% the client transaction MUST generate an ACK request, even if
    %% the transport is reliable
    Trans1 = set_state(fun 'Completed'/2, Trans),
    ACKReq = generate_ack_request(SipMsg, Req),
    {Trans1, [ersip_trans_se:tu_result(SipMsg),
              ersip_trans_se:send_request(ACKReq)
             ]};
'Calling'(_Event, #trans_inv_client{} = Trans) ->
    {Trans, []}.

-spec 'Proceeding'(event(), trans_inv_client()) -> result().
'Proceeding'(_Event, #trans_inv_client{} = Trans) ->
    {Trans, []}.

-spec 'Completed'(event(), trans_inv_client()) -> result().
'Completed'(_Event, #trans_inv_client{} = Trans) ->
    {Trans, []}.

%% RFC6026 state:
-spec 'Accepted'(event(), trans_inv_client()) -> result().
'Accepted'(_Event, #trans_inv_client{} = Trans) ->
    {Trans, []}.

-spec 'Terminated'(event(), trans_inv_client()) -> result().
'Terminated'(_Event, #trans_inv_client{} = Trans) ->
    {Trans, []}.

-spec process_event(Event :: term(), result()) -> result().
process_event(Event, {#trans_inv_client{state = StateF} = Trans, SE}) ->
    {Trans1, EventSE} = StateF(Event, Trans),
    {Trans1, SE ++ EventSE}.

-spec set_state(state(), trans_inv_client()) -> trans_inv_client().
set_state(State, Trans) ->
    Trans#trans_inv_client{state = State}.

-spec set_timer_a(pos_integer(), result()) -> result().
set_timer_a(Timeout, Result) ->
    set_timer(Timeout, timer_a, Result).

-spec set_timer_b(pos_integer(), result()) -> result().
set_timer_b(Timeout, Result) ->
    set_timer(Timeout, timer_b, Result).

-spec set_timer(pos_integer(), TimerType, result()) -> result() when
      TimerType :: timer_type().
set_timer(Timeout, TimerType, {#trans_inv_client{} = Trans, SE}) ->
    {Trans, SE ++ [ersip_trans_se:set_timer(Timeout, {timer, TimerType})]}.

-spec terminate(Reason,  trans_inv_client()) -> result() when
      Reason :: ersip_trans_se:clear_reason().
terminate(Reason, Trans) ->
    Trans1 = set_state(fun 'Terminated'/2, Trans),
    Trans2 = Trans1#trans_inv_client{clear_reason = Reason},
    process_event('enter', {Trans2, []}).

%% 17.1.1.3 Construction of the ACK Request
%%
%% Note that this generation is INVITE transaction specific and cannot
%% be reused to generate ACK on 2xx.
-spec generate_ack_request(Response , InitialReq) -> ersip_request:request() when
      Response :: ersip:sipmsg(),
      InitialReq :: ersip_request:request().
generate_ack_request(Response, InitialRequest) ->
    InitialSipMsg = ersip_request:sipmsg(InitialRequest),
    %% The ACK request constructed by the client transaction MUST
    %% contain values for the Call-ID, From, and Request-URI that are
    %% equal to the values of those header fields in the request
    %% passed to the transport by the client transaction (call this
    %% the "original request").
    RURI = ersip_sipmsg:ruri(InitialSipMsg),
    ACK0 = ersip_sipmsg:new_request(ersip_method:ack(), RURI),
    ACK1 = ersip_sipmsg:copy(from, InitialSipMsg, ACK0),
    %% The To header field in the ACK MUST equal the To header field
    %% in the response being acknowledged, and therefore will usually
    %% differ from the To header field in the original request by the
    %% addition of the tag parameter.
    ACK2 = ersip_sipmsg:copy(to, Response, ACK1),

    %% The CSeq header field in the ACK MUST contain the same
    %% value for the sequence number as was present in the original request,
    %% but the method parameter MUST be equal to "ACK".
    InviteCSeq = ersip_sipmsg:get(cseq, InitialSipMsg),
    ACKCSeq = ersip_hdr_cseq:set_method(ersip_method:ack(), InviteCSeq),
    ACK3 = ersip_sipmsg:set(cseq, ACKCSeq, ACK2),

    %% If the INVITE request whose response is being acknowledged had Route
    %% header fields, those header fields MUST appear in the ACK.
    ACK4 = ersip_sipmsg:copy(route, InitialSipMsg, ACK3),

    %% RFC 3261 says nothing about max-forwards in ACK for this case
    %% but following logic of route copy it should be the same as in
    %% INVITE:
    ACK5 = ersip_sipmsg:copy(maxforwards, InitialSipMsg, ACK4),

    %% Normative:
    %% The ACK MUST contain a single Via header field, and this MUST
    %% be equal to the top Via header field of the original request.

    %% Implementation: we really do not add Via here because it is
    %% automatically added when message is passed via connection. So
    %% what we really do here - we generate ersip_request with the
    %% same paramters as InitialRequest
    ersip_request:set_sipmsg(ACK5, InitialRequest).
