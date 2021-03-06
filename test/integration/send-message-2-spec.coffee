{describe,context,beforeEach,afterEach,expect,it} = global
bcrypt         = require 'bcryptjs'
TestDispatcherWorker = require './test-dispatcher-worker'

describe 'SendMessage: send', ->
  @timeout 5000
  beforeEach 'prepare TestDispatcherWorker', (done) ->
    @testDispatcherWorker = new TestDispatcherWorker
    @testDispatcherWorker.start done

  afterEach (done) ->
    @testDispatcherWorker.stop done

  beforeEach 'clearAndGetCollection devices', (done) ->
    @testDispatcherWorker.clearAndGetCollection 'devices', (error, @devices) =>
      done error

  beforeEach 'clearAndGetCollection subscriptions', (done) ->
    @testDispatcherWorker.clearAndGetCollection 'subscriptions', (error, @subscriptions) =>
      done error

  beforeEach 'getHydrant', (done) ->
    @testDispatcherWorker.getHydrant (error, @hydrant) =>
      done error

  beforeEach 'create sender device', (done) ->
    @auth =
      uuid: 'sender-uuid'
      token: 'leak'

    @senderDevice =
      uuid: 'sender-uuid'
      type: 'device:sender'
      token: bcrypt.hashSync @auth.token, 8
      meshblu:
        version: '2.0.0'
        whitelists:
          message:
            sent: [{uuid: 'spy-uuid'}]

    @devices.insert @senderDevice, done

  beforeEach 'create receiver device', (done) ->
    @receiverDevice =
      uuid: 'receiver-uuid'
      type: 'device:receiver'
      meshblu:
        version: '2.0.0'
        whitelists:
          message:
            from: [{uuid: 'sender-uuid'}]
            received: [{uuid: 'nsa-uuid'}]

    @devices.insert @receiverDevice, done

  beforeEach 'create spy device', (done) ->
    @spyDevice =
      uuid: 'spy-uuid'
      type: 'device:spy'

    @devices.insert @spyDevice, done

  beforeEach 'create nsa device', (done) ->
    @nsaDevice =
      uuid: 'nsa-uuid'
      type: 'device:nsa'

    @devices.insert @nsaDevice, done

  context 'When sending a message to another device', ->
    context "sender-uuid receiving its sent messages", ->
      beforeEach 'create message sent subscription', (done) ->
        subscription =
          type: 'message.sent'
          emitterUuid: 'sender-uuid'
          subscriberUuid: 'sender-uuid'

        @subscriptions.insert subscription, done

      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'sender-uuid'
          subscriberUuid: 'sender-uuid'

        @subscriptions.insert subscription, done

      beforeEach (done) ->
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        @hydrant.connect uuid: @auth.uuid, (error) =>
          return done(error) if error?

          @hydrant.once 'message', (@message) =>
            @hydrant.close()
            done()

          @testDispatcherWorker.jobManagerRequester.do job, (error) =>
            done error if error?
        return # fix redis promise issue

      it 'should deliver the sent message to the sender', ->
        expect(@message).to.exist

    context 'receiving a direct message', ->
      beforeEach 'create message sent subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'receiver-uuid'
          subscriberUuid: 'receiver-uuid'

        @subscriptions.insert subscription, done

      beforeEach (done) ->
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        @hydrant.connect uuid: 'receiver-uuid', (error) =>
          return done(error) if error?

          @hydrant.once 'message', (@message) =>
            @hydrant.close()
            done()

          @testDispatcherWorker.jobManagerRequester.do job, (error) =>
            done error if error?
        return # fix redis promise issue

      it 'should deliver the sent message to the receiver', ->
        expect(@message).to.exist

    context 'subscribed to someone elses sent messages', ->
      beforeEach 'create message sent subscription', (done) ->
        subscription =
          type: 'message.sent'
          emitterUuid: 'sender-uuid'
          subscriberUuid: 'spy-uuid'

        @subscriptions.insert subscription, done

      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'spy-uuid'
          subscriberUuid: 'spy-uuid'

        @subscriptions.insert subscription, done

      beforeEach (done) ->
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        @hydrant.connect uuid: 'spy-uuid', (error) =>
          return done(error) if error?

          @hydrant.once 'message', (@message) =>
            @hydrant.close()
            done()

          @testDispatcherWorker.jobManagerRequester.do job, (error) =>
            done error if error?
        return # fix redis promise issue

      it 'should deliver the sent message to the receiver', ->
        expect(@message).to.exist

    context 'subscribed to someone elses sent messages, but is not authorized', ->
      beforeEach 'create message sent subscription', (done) ->
        subscription =
          type: 'message.sent'
          emitterUuid: 'sender-uuid'
          subscriberUuid: 'nsa-uuid'

        @subscriptions.insert subscription, done

      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'nsa-uuid'
          subscriberUuid: 'nsa-uuid'

        @subscriptions.insert subscription, done

      beforeEach (done) ->
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        @hydrant.connect uuid: 'nsa-uuid', (error) =>
          return done(error) if error?

          @hydrant.once 'message', (@message) => @hydrant.close()

          @testDispatcherWorker.jobManagerRequester.do job, (error) =>
            done error if error?
            setTimeout done, 2000
        return # fix redis promise issue

      it 'should not deliver the sent message to the receiver', ->
        expect(@message).to.not.exist

    context 'subscribed to someone elses received messages', ->
      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'receiver-uuid'
          subscriberUuid: 'nsa-uuid'

        @subscriptions.insert subscription, done

      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'nsa-uuid'
          subscriberUuid: 'nsa-uuid'

        @subscriptions.insert subscription, done

      beforeEach 'wait-for-the-hydrant', (done) ->
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        @hydrant.connect uuid: 'nsa-uuid', (error) =>
          return done(error) if error?

          @hydrant.once 'message', (@message) =>
            @hydrant.close()
            done()

          @testDispatcherWorker.jobManagerRequester.do job, (error) =>
            done error if error?
        return # fix redis promise issue

      it 'should deliver the sent message to the receiver', ->
        expect(@message).to.exist

    context 'subscribed to someone elses received messages, but is not authorized', ->
      beforeEach 'create message sent subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'receiver-uuid'
          subscriberUuid: 'spy-uuid'

        @subscriptions.insert subscription, done

      beforeEach 'create message received subscription', (done) ->
        subscription =
          type: 'message.received'
          emitterUuid: 'spy-uuid'
          subscriberUuid: 'spy-uuid'

        @subscriptions.insert subscription, done

      beforeEach (done) ->
        job =
          metadata:
            auth: @auth
            toUuid: @auth.uuid
            jobType: 'SendMessage'
          data:
            devices: ['receiver-uuid'], payload: 'boo'

        @hydrant.connect uuid: 'spy-uuid', (error) =>
          return done(error) if error?
          @hydrant.once 'message', (@message) => @hydrant.close()

          @testDispatcherWorker.jobManagerRequester.do job, (error) =>
            done error if error?
            setTimeout done, 2000
        return # fix redis promise issue

      it 'should not deliver the sent message to the receiver', ->
        expect(@message).to.not.exist
