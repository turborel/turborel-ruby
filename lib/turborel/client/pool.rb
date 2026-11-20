# frozen_string_literal: true

module Turborel
  module Client
    # How a pool keeps its connections [CLIENT Pools]: +max+ made at once,
    # +max_idle+ kept idle, +idle_timeout+ and +max_lifetime+ in seconds,
    # +nil+ for no limit, +wait+ the seconds get waits, +check+ whether an
    # idle connection is checked to answer before it is handed out, and
    # +reset+ the statements run as each comes back, after the pool's own.
    PoolConfig = Data.define(:max, :max_idle, :idle_timeout, :max_lifetime, :wait, :check, :reset)

    # The defaults of a pool.
    class PoolConfig
      # @return [PoolConfig] max and max_idle 10, idle_timeout 10 minutes,
      #   max_lifetime an hour, wait 30 seconds, check yes, reset none
      def self.default
        new(max: 10, max_idle: 10, idle_timeout: 600, max_lifetime: 3600, wait: CONNECT_WITHIN, check: true, reset: [])
      end
    end

    # A pool of connections, a bounded set a program's threads share
    # [CLIENT Pools], as turborel-client's Pool: get hands out an idle
    # connection that answers, or makes one while fewer than max are made,
    # or waits for one to come back, at most wait seconds. A connection
    # comes back as its Pooled is released, reset to the session it logged
    # in with; one lost, whose reset fails, or that has lived its time is
    # closed. The pool starts no thread; each wait is the waiting thread's.
    class Pool
      # A pool of connections +source+ makes, Settings or anything that
      # answers call with a new connection, kept as +config+ says.
      #
      # @param source [Settings, #call]
      # @param config [PoolConfig]
      def initialize(source, config = PoolConfig.default)
        @source = source
        @config = config
        @lock = Mutex.new
        @returned = ConditionVariable.new
        @idle = [] #: Array[[Connection, Float, Float]]
        @made = 0
      end

      # @return [PoolConfig] how it keeps its connections
      attr_reader :config

      # A connection: an idle one that answers, else a new one while the
      # pool has room, else the first to come back within wait. With a
      # block, gives it the connection and releases it after, giving the
      # block's value.
      #
      # @yieldparam connection [Connection]
      # @return [Pooled, Object]
      # @raise [Error] SQLSTATE 08001 if none comes back in time; the
      #   source's failure to make one
      def get
        pooled = taken
        return pooled unless block_given?

        begin
          yield pooled.connection
        ensure
          pooled.release
        end
      end

      # @return [Array(Integer, Integer)] how many connections are made,
      #   handed out and idle, and how many of them are idle
      def counts = @lock.synchronize { [@made, @idle.size] }

      # Takes +connection+ back from a Pooled made at +made+: reset and
      # kept idle, or closed.
      #
      # @api private
      # @return [void]
      def give_back(connection, made)
        kept = !lived?(made) && Resets.reset(connection, config.reset)
        @lock.synchronize do
          if kept && @idle.size < config.max_idle
            @idle << [connection, made, now]
          else
            @made -= 1
            connection.abandon unless connection.lost?
          end
          @returned.signal
        end
      end

      # Whether a connection made at +made+ has lived its time.
      #
      # @api private
      def lived?(made)
        lifetime = config.max_lifetime
        !lifetime.nil? && now - made >= lifetime
      end

      private

      # The connection get gives.
      def taken
        deadline = now + config.wait
        loop do
          _, idle = next_one(deadline)
          return made_one unless idle

          pooled = checked(idle)
          return pooled if pooled
        end
      end

      # What get takes next: an idle connection, or a place to make one,
      # waiting for one to come back until +deadline+; stale ones closed on
      # the way.
      def next_one(deadline)
        @lock.synchronize do
          loop do
            idle = fresh_idle
            return [:idle, idle] if idle
            return [:make, nil] if (@made += 1) <= config.max

            @made -= 1
            left = deadline - now
            raise none_back unless left.positive?

            @returned.wait(@lock, left)
          end
        end
      end

      # The freshest idle connection that may still be handed out; those
      # that may not, closed.
      def fresh_idle
        while (idle = @idle.pop)
          return idle if fresh?(idle)

          @made -= 1
          idle.first.abandon unless idle.first.lost?
        end
        nil
      end

      # Whether +idle+ may still be handed out.
      def fresh?(idle)
        connection, made, since = idle
        lifetime = config.max_lifetime
        rest = config.idle_timeout
        (lifetime.nil? || now - made < lifetime) && (rest.nil? || now - since < rest) && !connection.lost?
      end

      # +idle+, handed out if it answers or need not be checked; else
      # closed, its place given up.
      def checked(idle)
        connection, made, = idle
        return Pooled.new(self, connection, made) unless config.check && !Resets.answers?(connection)

        unmade(connection)
        nil
      end

      # A new connection, in the place next_one took for it.
      def made_one
        connection = @source.is_a?(Settings) ? @source.connect : @source.call
        Pooled.new(self, connection, now)
      rescue StandardError
        unmade(nil)
        raise
      end

      # One fewer connection made, so a waiter may make one.
      def unmade(connection)
        connection&.abandon unless connection.nil? || connection.lost?
        @lock.synchronize do
          @made -= 1
          @returned.signal
        end
      end

      # The failure of no connection in time (SQLSTATE 08001).
      def none_back
        Settings.invalid("no connection of the pool's #{config.max} came back within #{config.wait} seconds")
      end

      # The monotonic clock, in seconds.
      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # A connection handed out by a pool, given back as it is released
    # [CLIENT Pools].
    class Pooled
      # @api private
      def initialize(pool, connection, made)
        @pool = pool
        @connection = connection
        @made = made
      end

      # @return [Connection] the connection, until it is released
      # @raise [Error] TB910 once released
      def connection = @connection || raise(Error.misused("the connection went back to its pool"))

      # Gives the connection back, reset; or closes it, if it is lost, its
      # reset fails, it has lived its time, or enough are idle.
      #
      # @return [void]
      def release
        connection = @connection
        return unless connection

        @connection = nil
        @pool.give_back(connection, @made)
      end
    end

    # A pooled connection's check and reset [CLIENT Pools], as
    # turborel-client's pool reset: by Ping and Reset where the server
    # grants them, else by statements; autocommit off after.
    #
    # @api private
    module Resets
      # How long a check and a reset wait on the server, at most.
      RESET_WITHIN = CONNECT_WITHIN
      # The most statements a borrower may leave prepared for the
      # connection to be reset rather than closed.
      RESET_MOST_STATEMENTS = 256

      # Whether +connection+ answers: Ping, or ROLLBACK of a server that
      # takes no Ping.
      #
      # @return [Boolean]
      def self.answers?(connection)
        bounded(connection) do
          connection.granted?(Protocol::Capabilities::PING) ? connection.ping : connection.query("ROLLBACK")
        end
        true
      rescue Error
        false
      end

      # Gives +connection+'s session back as it logged in, then runs
      # +more+: whether it was.
      #
      # @return [Boolean]
      def self.reset(connection, more)
        return false if connection.lost?

        bounded(connection) { reset_now(connection, more) }
        true
      rescue Error
        false
      end

      # Resets +connection+, unbounded.
      def self.reset_now(connection, more)
        connection.autocommit = false
        return renewed(connection, more) if connection.granted?(Protocol::Capabilities::RESET)

        by_statements(connection, more)
      end

      # Resets +connection+ by the protocol's Reset, then runs +more+.
      def self.renewed(connection, more)
        connection.reset
        connection.forget_prepared
        more.each { |sql| connection.query(sql) }
      end

      # Resets +connection+ by statements, in one pipeline: its transaction
      # rolled back, the statements it prepared closed and destroyed, its
      # user, schema and zone those of its login, then +more+.
      def self.by_statements(connection, more)
        prepared = connection.prepared_count
        if prepared > RESET_MOST_STATEMENTS
          raise Error.connection_failure("too many statements were left prepared to destroy")
        end

        outcomes = reset_pipeline(connection, prepared, more).run
        failed = ([outcomes.first] + outcomes.drop(1 + (2 * prepared))).find { _1&.failed }
        raise Error, failed.failed if failed

        connection.forget_prepared
      end

      # The pipeline that resets +connection+ by statements.
      def self.reset_pipeline(connection, prepared, more)
        pipeline = connection.pipeline.query("ROLLBACK")
        prepared.times { |number| pipeline.release(number) }
        login = "'\"#{connection.authorization.gsub('"', '""').gsub("'", "''")}\"'"
        ["SET SESSION AUTHORIZATION #{login}", "SET SCHEMA #{login}", "SET TIME ZONE LOCAL", *more]
          .each { |sql| pipeline.query(sql) }
        pipeline
      end

      # The block run, each wait at most RESET_WITHIN, or the connection's
      # own limit if shorter; the limit put back after.
      def self.bounded(connection)
        before = connection.read_timeout
        limited = limit(connection, [before, RESET_WITHIN].compact.min)
        begin
          yield
        ensure
          connection.read_timeout = before if limited
        end
      end

      # Whether +connection+'s reads could be bounded by +within+.
      def self.limit(connection, within)
        connection.read_timeout = within
        true
      rescue Error
        false
      end
    end
  end
end
