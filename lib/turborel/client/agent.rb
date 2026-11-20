# frozen_string_literal: true

module Turborel
  module Client
    # An SQL-agent [CLIENT The SQL-agent]: a program's connections, each
    # named, one current, and CONNECT, SET CONNECTION and DISCONNECT run
    # by it, as SQL-92's SQL-agent runs them (ISO/IEC 9075:1992 §15);
    # every other statement goes to the current connection, as
    # turborel-client's Agent. A connector the program gives, anything
    # that answers call(server, user), makes the connections CONNECT asks
    # for, to the address it names, as the user it names; +nil+ for the
    # default server or the connector's user.
    class Agent
      # SQLSTATE of a syntax error or access rule violation.
      SYNTAX_ERROR = "2A000"

      # An agent with no connection, or whose default connection, current,
      # is +connection+.
      #
      # @param connector [#call]
      # @param connection [Connection, nil]
      def initialize(connector, connection = nil)
        @connector = connector
        @held = connection ? [[nil, connection]] : [] #: Array[[String?, Connection]]
        @current = connection ? 0 : nil
      end

      # The current connection.
      #
      # @return [Connection]
      # @raise [Error] SQLSTATE 08003 if there is none
      def current
        index = @current || raise(Agent.exception("08003", "there is no current connection"))
        @held.fetch(index).last
      end

      # @return [Connection, nil] the current connection, if any
      def current_connection
        index = @current
        index && @held.fetch(index).last
      end

      # @return [String, nil] the current connection's name, +nil+ for the
      #   default one or for none
      def current_name
        index = @current
        index && @held.fetch(index).first
      end

      # @return [Canceller, nil] what cancels the current connection's
      #   statement, if any
      def canceller = current_connection&.canceller

      # @return [String, nil] the SQLSTATE of the warning the current
      #   connection's last statement completed with
      def warning = current_connection&.warning

      # @return [Boolean] whether the current connection is lost; none is
      #   not
      def lost? = current_connection&.lost? || false

      # Runs +sql+: a connection statement itself, its Completion; any
      # other in the current connection's session, as Connection#query.
      #
      # @param sql [String]
      # @return [Rows, Completion]
      # @raise [Error] the connection statement's, or the statement's
      def query(sql) = connection_statement(sql) || current.query(sql)

      # Runs +sql+ as query does, a query's rows given to +sink+.
      #
      # @return [Integer, Completion]
      def query_into(sql, sink) = connection_statement(sql) || current.query_into(sql, sink)

      # +sql+, if a connection statement, run: its Completion; +nil+ of
      # another.
      #
      # @param sql [String]
      # @return [Completion, nil]
      # @raise [Error] the statement's, as each rule of §15 says
      def connection_statement(sql)
        statement = ConnectionStatement.parse(sql)
        return nil unless statement

        kind, first, second, third = statement
        case kind
        when :connect then connect(first, second, third)
        when :set then choose(first)
        else disconnect(first)
        end
      end

      # Ends every connection, as the program ends.
      #
      # @return [void]
      # @raise [Error] the first failure ending one; every one ended still
      def terminate
        first = nil #: Error?
        @held.map(&:last).each do |connection|
          connection.terminate
        rescue Error => e
          first ||= e
        end
        @held = []
        @current = nil
        raise first if first
      end

      # The connection exception of +state+, of +message+: of class 28 a
      # privilege's SQLCODE, of 0A a feature's, else a connection's.
      #
      # @api private
      def self.exception(state, message)
        sqlcode = { "28" => -104, "0A" => -900 }.fetch(state[0, 2], Error::CONNECTION_FAILURE_SQLCODE)
        Error.of(sqlcode, state, message)
      end

      # A syntax error of a connection statement (SQLCODE -102).
      #
      # @api private
      def self.syntax(message) = Error.of(-102, SYNTAX_ERROR, message)

      # A syntax rule broken by a connection statement (SQLCODE -103).
      #
      # @api private
      def self.syntax_rule(message) = Error.of(-103, SYNTAX_ERROR, message)

      private

      # [§15.1] CONNECT TO +server+ AS +name+ USER +user+, or for no server
      # TO DEFAULT: the connection made current.
      def connect(server, name, user)
        not_in_transaction
        user = ConnectionStatement.text(user)
        if user && !ConnectionStatement.identifier(user)
          raise Agent.exception("28000", "'#{user}' is not an <authorization identifier>")
        end

        address = ConnectionStatement.text(server)
        identified = connection_name(ConnectionStatement.text(name) || address)
        established(identified)
        @held << [identified, connected(address, user)]
        @current = @held.size - 1
        done
      end

      # The name +named+ is, as an identifier; none of the default
      # connection.
      def connection_name(named)
        return nil unless named

        ConnectionStatement.identifier(named) || raise(Agent.exception("2E000", "'#{named}' is not an <identifier>"))
      end

      # Refuses a name already in use.
      def established(name)
        return unless find(name)

        raise Agent.exception("08002", "#{name ? "the connection #{name}" : "the default connection"} is established")
      end

      # The connection the connector makes, its failure a connection
      # exception: 08001 of one that cannot be made, else 08004.
      def connected(address, user)
        @connector.call(address, user)
      rescue Error => e
        raise Agent.exception(e.sqlstate == Error::CONNECTION_FAILURE_SQLSTATE ? "08001" : "08004", e.message)
      end

      # [§15.2] SET CONNECTION +name+, or DEFAULT for +nil+.
      def choose(name)
        not_in_transaction
        text = ConnectionStatement.text(name)
        named = text ? ConnectionStatement.identifier(text) || text : nil
        what = named ? "no connection #{named}" : "no default connection"
        @current = find(named) || raise(Agent.exception("08003", "there is #{what}"))
        done
      end

      # [§15.3] DISCONNECT +object+: each connection it names ended.
      def disconnect(object)
        ended = ended_by(object)
        raise Error.of(-917, "25000", "a connection's transaction is active") if active_among?(ended)

        index = @current
        name = index && @held.fetch(index).first
        warned = ended_all(ended)
        @current = index && find(name)
        done(warned ? "01002" : "00000")
      end

      # Ends the connections of +places+, keeping the rest: whether ending
      # one failed.
      def ended_all(places)
        warned = !places.all? { |i| ended_quietly?(@held.fetch(i).last) }
        @held = @held.each_with_index.reject { |_, i| places.include?(i) }.map(&:first)
        warned
      end

      # Whether a transaction is active on a connection of +places+.
      def active_among?(places) = places.any? { |i| @held.fetch(i).last.in_transaction? }

      # Whether +connection+ ended without a failure.
      def ended_quietly?(connection)
        connection.terminate
        true
      rescue Error
        false
      end

      # The connections DISCONNECT's +object+ names, by place.
      def ended_by(object)
        case object
        when :all then (0...@held.size).to_a
        when :current then [@current || raise(missing("no current connection"))]
        when :default then [find(nil) || raise(missing("no default connection"))]
        else [named_index(object)]
        end
      end

      # The place of the connection DISCONNECT names by +object+, a value.
      def named_index(object)
        text = ConnectionStatement.text(object).to_s
        name = ConnectionStatement.identifier(text) || text
        find(name) || raise(missing("no connection #{name}"))
      end

      # The failure of DISCONNECT naming +what+, which is not there.
      def missing(what) = Agent.exception("08003", "there is #{what}")

      # Refuses to leave the current connection's active transaction.
      def not_in_transaction
        return unless current_connection&.in_transaction?

        raise Agent.exception("0A001", "the current connection's transaction is active, and none spans servers")
      end

      # The place of the connection named +name+, +nil+ the default one.
      def find(name) = @held.index { |held_name, _| held_name == name }

      # A Completion of SQLCODE 0 and +state+.
      def done(state = "00000")
        Completion.new(sqlcode: 0, sqlstate: state, active: false, position: nil, more: false, rows: nil, generated: [],
                       conditions: [], time: nil)
      end
    end
  end
end
