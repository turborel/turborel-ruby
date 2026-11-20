# frozen_string_literal: true

module Turborel
  module Client
    # What a connection's session tells and how it is controlled [CLIENT
    # What the server tells], [CLIENT Controlling the session]: whether a
    # transaction is active, autocommit, the last statement's completion
    # and what it told, notices, query attributes; ping, reset, change of
    # user and several statements in one request.
    module Session
      # @return [Boolean] whether the session's transaction is active, as
      #   the server said after the last statement
      def in_transaction? = @active

      # @return [Boolean] whether each statement is its own transaction
      attr_accessor :autocommit

      # Whether each statement query, query_into and execute run is its own
      # transaction from now on: the server commits it as it succeeds, or
      # rolls it back as it fails, within the request, so no COMMIT is
      # sent. Off as a connection opens: a transaction begins with the
      # first statement and lasts until COMMIT or ROLLBACK.
      #
      # @param on [Boolean]

      # @return [String, nil] the SQLSTATE of the warning the last statement
      #   completed with, of class 01; of a query once all its rows were
      #   read
      attr_reader :warning

      # @return [Integer, nil] the log position of the last commit the
      #   server told of, once granted commit-position
      attr_reader :commit_position

      # @return [Completion, nil] the last statement's completion
      attr_reader :completion

      # @return [Integer, nil] the rows the last statement inserted,
      #   updated, deleted or merged, or the rows the last query returned
      #   once all were read; once granted row-counts
      def rows_affected = @completion&.rows

      # @return [Timing, nil] the server's time for the last statement, in
      #   microseconds, once granted row-counts
      def server_time = @completion&.time

      # @return [Array<String>] the identity values the last INSERT
      #   generated, in the order of its rows, as SQL writes them, once
      #   granted generated-values
      def last_generated = @completion&.generated || []

      # @return [Array<Failure>] each condition the last statement raised
      #   and completed with, once granted conditions
      def conditions = @completion&.conditions || []

      # The conditions of the last statement, taken, so a program that
      # tells them after each statement tells each once.
      #
      # @return [Array<Failure>]
      def take_conditions
        completion = @completion
        return [] unless completion

        @completion = completion.with(conditions: [])
        completion.conditions
      end

      # What takes each notice the server sends from now on, as it comes,
      # before the reply of the statement that raised it: a Proc of one
      # Notice; +nil+, they are kept, the last KEPT_NOTICES (take_notices).
      #
      # @param handler [Proc, nil]
      attr_writer :notice_handler

      # The notices kept while no handler was set, taken.
      #
      # @return [Array<Notice>]
      def take_notices
        notices = @notices
        @notices = []
        notices
      end

      # @return [Array<Array(String, String)>] the query attributes each
      #   later statement carries
      attr_reader :query_attributes

      # Query attributes carried by each Query and Execute from now on,
      # read in SQL by QUERY_ATTRIBUTE(name); traceparent is the request's
      # trace context. Each is a name and a value; none, for none.
      #
      # @param attributes [Array<Array(String, String)>]
      # @raise [Error] a connection failure if query-attributes was not
      #   granted, for attributes not none
      def query_attributes=(attributes)
        needs(attributes.empty?, Protocol::Capabilities::QUERY_ATTRIBUTES)
        @query_attributes = attributes.dup.freeze
      end

      # @api private
      # @return [Integer] the number the next prepared statement takes: how
      #   many the session may hold
      def prepared_count = @next_statement

      # Forgets the session's prepared statements, gone with it.
      #
      # @api private
      # @return [void]
      def forget_prepared
        @next_statement = 0
      end

      # Whether the server answers, with no worker of its taken.
      #
      # @return [void]
      # @raise [Error] a connection failure: ping not granted, or the
      #   server gone
      def ping
        needs(false, Protocol::Capabilities::PING)
        send_frame(Protocol::Requests.ping)
        expect(Protocol::Replies::Pong)
        nil
      end

      # The session back to its state at login: its transaction rolled
      # back, its prepared statements, cursors, temporary tables and
      # settings gone, its user and cancel key kept. Statements prepared
      # before are of no use after.
      #
      # @return [void]
      # @raise [Error] a connection failure: reset not granted, or the
      #   server gone
      def reset
        needs(false, Protocol::Capabilities::RESET)
        send_frame(Protocol::Requests.reset)
        completion_reply
        nil
      end

      # The connection authenticated again as +user+ by +mechanism+, its
      # session renewed as that user's, as reset renews it, under a new
      # cancel key, no transaction active after it.
      #
      # @param user [String]
      # @param mechanism [Mechanism]
      # @return [void]
      # @raise [Error] the server's refusal, which closes the connection; a
      #   connection failure: change-user not granted, or the server gone
      def change_user(user, mechanism)
        needs(false, Protocol::Capabilities::CHANGE_USER)
        send_frame(Protocol::Requests.change_user(user, mechanism.name, mechanism.initial))
        loop do
          reply = expect(Protocol::Replies::Challenge, Protocol::Replies::Ready)
          return renewed(reply, mechanism) if reply.is_a?(Protocol::Replies::Ready)

          send_frame(Protocol::Requests.answer(mechanism.answer(reply.challenge)))
        end
      end

      # Runs +sql+, several statements, in one request: the server splits
      # it and runs each in order, each the transaction ended with it under
      # autocommit; the first that fails stops the rest.
      #
      # @param sql [String]
      # @return [Ran]
      # @raise [Error] a connection failure: multi-statement not granted,
      #   or the server gone
      def query_many(sql)
        needs(false, Protocol::Capabilities::MULTI_STATEMENT)
        send_frame(Protocol::Requests.query(sql, ends: @autocommit, attributes: carried_attributes, multi: true))
        ran([])
      end

      private

      # What a text of several statements gave, the outcomes so far in
      # +outcomes+: each outcome until the last, or the failure that
      # stopped the rest, unless it lost the connection.
      def ran(outcomes)
        loop do
          result, more = outcome
          outcomes << result
          return Ran.new(outcomes:, failure: nil) unless more
        end
      rescue Error => e
        raise if @lost

        Ran.new(outcomes:, failure: e.failure)
      end

      # Takes the Ready of a change of user: the new authorization, server
      # and cancel key.
      def renewed(ready, mechanism)
        mechanism.ready!
        @authorization = ready.authorization
        @server = ready.server
        @key = ready.key
        nil
      end
    end
  end
end
