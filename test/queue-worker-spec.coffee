QueueWorker = require '../src/queue-worker'
JobManager  = require 'meshblu-core-job-manager'
redisMock   = require 'fakeredis'
_           = require 'lodash'
uuid        = require 'uuid'

describe 'QueueWorker', ->
  beforeEach ->
    @clientId = uuid.v1()
    @client = _.bindAll redisMock.createClient @clientId

    @jobManager = new JobManager
      client: redisMock.createClient @clientId
      namespace: 'test:internal'
      timeoutSeconds: 1
      responseQueue: 'authenticate'
      requestQueue: 'authenticate'

    @tasks =
      'meshblu-core-task-authenticate': sinon.stub().yields null, {}
      'meshblu-core-task-get-subscriptions': sinon.stub().yields null, {}

  describe '->run', ->
    describe 'when using client', ->
      beforeEach ->
        @sut = new QueueWorker
          client: redisMock.createClient @clientId
          jobs: ['authenticate']
          tasks: @tasks
          namespace: 'test:internal'
          timeout: 1

      describe 'when called and job is pushed into queue', ->
        beforeEach (done) ->
          @sut.run()
          responseKey = 'test:internal:sometin'
          @client.lpush 'test:internal:authenticate:sometin', responseKey, done

        it 'should place the job in the queue', (done) ->
          @client.brpop 'test:internal:authenticate:sometin', 1, (error, result) =>
            return done error if error?
            [channel, responseKey] = result
            expect(responseKey).to.equal 'test:internal:sometin'
            done()

    describe 'when using client', ->
      beforeEach ->
        @sut = new QueueWorker
          client: redisMock.createClient @clientId
          localHandlers: ['authenticate']
          remoteHandlers: []
          tasks: @tasks
          namespace: 'test:internal'
          timeout: 1

      describe 'when called and job is pushed into queue', ->
        beforeEach (done) ->
          @sut.run()
          responseKey = 'test:internal:sometin'
          @client.lpush 'test:internal:authenticate:sometin', responseKey, done

        it 'should place the job in the queue', (done) ->
          @client.brpop 'test:internal:authenticate:sometin', 1, (error, result) =>
            return done error if error?
            [channel, responseKey] = result
            expect(responseKey).to.equal 'test:internal:sometin'
            done()

      describe 'when called and different job is pushed into queue', ->
        beforeEach (done) ->
          @sut.run()
          responseKey = 'test:internal:sometin-cool'
          @client.lpush 'test:internal:authenticate:sometin-cool', responseKey, done

        it 'should place the job in the queue', (done) ->
          @client.brpop 'test:internal:authenticate:sometin-cool', 1, (error, result) =>
            return done error if error?
            [channel, responseKey] = result
            expect(responseKey).to.equal 'test:internal:sometin-cool'
            done()

        it 'should not place the job in the remote queue', (done) ->
          @timeout 3000
          @client.brpop 'test:internal:authenticate:queue', 1, (error, result) =>
            return done(error) if error?
            expect(result).not.to.exist
            done()

  describe '->runJob', ->
    beforeEach ->
      @sut = new QueueWorker
        client: redisMock.createClient @clientId
        jobs: ['authenticate']
        tasks: @tasks
        namespace: 'test:internal'
        timeout: 1

    describe 'when called with an authenticate job', ->
      beforeEach (done) ->
        @timeout 3000

        job =
          metadata:
            auth:
              uuid: 'uuid'
              token: 'token'
            jobType: 'authenticate'
            responseId: 'cool-beans'
          rawData: 'null'

        response =
          metadata:
            auth:
              uuid: 'uuid'
              token: 'token'
            jobType: 'authenticate'
            responseId: 'cool-beans'
          rawData: 'bacon is good'

        @tasks['meshblu-core-task-authenticate'] = sinon.stub().yields null, response

        @sut.runJob job, (error) =>
          return done error if error?
          @jobManager.getResponse 'cool-beans', (error, @job) => done error

      it 'should have the original metadata', ->
        expect(@job.metadata).to.deep.equal
          auth:
            uuid: 'uuid'
            token: 'token'
          jobType: 'authenticate'
          responseId: 'cool-beans'

      it 'should have the new rawData', ->
        expect(@job.rawData).to.equal 'bacon is good'

    describe 'when called with an SubscriptionList job', ->
      beforeEach (done) ->
        @timeout 3000

        job =
          metadata:
            auth:
              uuid: 'uuid'
              token: 'token'
            jobType: 'SubscriptionList'
            responseId: 'cool-beans'
          rawData: 'null'

        authenticateResponse =
          metadata:
            responseId: 'cool-beans'
            code: 200

        getSubscriptionsResponse =
          metadata:
            responseId: 'cool-beans'
            code: 200
          rawData: '[]'

        @tasks['meshblu-core-task-authenticate'] = sinon.stub().yields null, authenticateResponse
        @tasks['meshblu-core-task-get-subscriptions'] = sinon.stub().yields null, getSubscriptionsResponse

        @sut.runJob job, (error) =>
          return done error if error?
          @jobManager.getResponse 'cool-beans', (error, @job) =>
            done error

      it 'should have the original metadata', ->
        expect(@job.metadata).to.deep.equal
          responseId: 'cool-beans'
          code: 200

      it 'should have the new rawData', ->
        expect(@job.rawData).to.equal '[]'