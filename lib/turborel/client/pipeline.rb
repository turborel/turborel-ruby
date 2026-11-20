# frozen_string_literal: true

module Turborel
  module Client
    # The outcome of one request of a pipeline [CLIENT Pipelines]: what it
    # gave, Rows or a Completion (+done+), how it failed (+failed+, a
    # Failure), or +skipped+, not run, or run and undone, after an earlier
    # request failed under on_error :skip.
    Piped = Data.define(:done, :failed, :skipped)

    # Outcomes made.
    class Piped
      # @return [Piped] of what a request gave
      def self.of(outcome) = new(done: outcome, failed: nil, skipped: false)

      # @return [Piped] of how a request failed
      def self.failure(failure) = new(done: nil, failed: failure, skipped: false)

      # @return [Piped] of a request skipped
      def self.skip = new(done: nil, failed: nil, skipped: true)
    end

    # Requests queued on a connection, written at once by run, one outcome
    # read for each, in order, as the server answers each request alone
    # and in turn [CLIENT Pipelines], as turborel-client's Pipeline: a
    # window of PIPELINE_WINDOW bytes written at a time, its replies read
    # before the next. Under on_error :skip a savepoint is set before each
    # request but the first, and the requests after a failure are undone,
    # or never sent, each skipped.
    class Pipeline
      # The most bytes of requests written before their replies are read.
      PIPELINE_WINDOW = 64 * 1024
      # What the savepoints of :skip are named by, then each its place.
      SAVEPOINT = "TURBOREL_PIPELINE"
      # What a pipeline does after a request fails.
      ON_ERRORS = %i[continue skip].freeze

      # A pipeline of +connection+'s, empty.
      #
      # @api private
      def initialize(connection)
        @connection = connection
        @queued = [] #: Array[Array[untyped]]
        @on_error = :continue
      end

      # Queues +sql+, run as Connection#query runs it.
      #
      # @param sql [String]
      # @return [Pipeline] itself
      def query(sql)
        @queued << [:query, sql]
        self
      end

      # Queues an execution of +statement+ with +values+, as
      # Connection#execute runs it.
      #
      # @param statement [Statement]
      # @param values [Array]
      # @return [Pipeline] itself
      def execute(statement, values = [])
        @queued << [:execute, statement, values]
        self
      end

      # Queues the closing of statement +number+'s cursor, then its
      # destruction: a pool's reset of what a borrower left.
      #
      # @api private
      # @return [Pipeline] itself
      def release(number)
        @queued << [:close, number] << [:deallocate, number]
        self
      end

      # What the batch does after a request fails: +:continue+, every
      # request run, or +:skip+, the batch stopped at its first failure.
      #
      # @param choice [Symbol]
      # @return [Pipeline] itself
      # @raise [Error] TB910 of another
      def on_error(choice)
        raise Error.misused("#{choice.inspect} is no choice of a pipeline") unless ON_ERRORS.include?(choice)

        @on_error = choice
        self
      end

      # @return [Integer] how many requests are queued
      def size = @queued.size

      # @return [Boolean] whether none is queued
      def empty? = @queued.empty?

      # Writes the requests, a window at a time, and reads one outcome for
      # each, in the order queued.
      #
      # @return [Array<Piped>]
      # @raise [Error] a connection failure, once the connection is lost;
      #   under :skip, the failure of undoing the requests after a failed one
      def run
        skip = @on_error == :skip
        began = @connection.in_transaction?
        sent = skip ? guarded(@queued) : @queued
        outcomes = run_windows(sent, skip)
        settle(sent, outcomes, began) if skip
        sent.zip(outcomes).filter_map { |queued, outcome| outcome unless queued.first == :savepoint }
      end

      private

      # The outcomes of +sent+, a window at a time; under +skip+, a window
      # after a failure skipped, never sent.
      def run_windows(sent, skip)
        ends = @connection.autocommit && !skip
        attributes = @connection.__send__(:carried_attributes)
        outcomes = [] #: Array[Piped]
        windows(sent, ends, attributes).each do |window|
          if skip && outcomes.any?(&:failed)
            outcomes.concat(window.map { Piped.skip })
          else
            outcomes.concat(@connection.__send__(:piped_window, window))
          end
        end
        outcomes
      end

      # +queued+, a savepoint of its own before each request but the first.
      def guarded(queued)
        queued.each_with_index.flat_map { |q, n| n.positive? ? [[:savepoint, n], q] : [q] }
      end

      # The requests of +queued+, each its queued entry and its frame,
      # grouped into windows of at most PIPELINE_WINDOW bytes, a longer
      # request alone in its own.
      def windows(queued, ends, attributes)
        windows = [] #: Array[Array[[Array[untyped], String]]]
        filled = PIPELINE_WINDOW
        queued.each do |q|
          frame = request(q, ends, attributes)
          filled += frame.bytesize
          if filled > PIPELINE_WINDOW
            windows << []
            filled = frame.bytesize
          end
          windows.last << [q, frame]
        end
        windows
      end

      # The frame of the request +queued+ sends.
      def request(queued, ends, attributes)
        kind, subject, values = queued
        case kind
        when :query then Protocol::Requests.query(subject, ends:, attributes:)
        when :execute
          Protocol::Requests.execute(subject.number, values, rows: 0, ends:, tail: { attributes: })
        when :close then Protocol::Requests.close(subject)
        when :deallocate then Protocol::Requests.deallocate(subject)
        else Protocol::Requests.query("SAVEPOINT #{SAVEPOINT}_#{subject}", ends: false)
        end
      end

      # Ends a batch run under :skip: the requests after the first that
      # failed undone, to the savepoint set after it, each skipped; the
      # savepoints released; under autocommit of a batch that began no
      # transaction, its work committed.
      def settle(sent, outcomes, began)
        statements = undone(sent, outcomes)
        set = savepoint_set(sent, outcomes, 1)
        statements << "RELEASE SAVEPOINT #{set}" if set
        statements << "COMMIT" if !began && @connection.autocommit
        statements.each { |sql| @connection.__send__(:within_batch, sql) }
      end

      # The name of the savepoint sent at +at+, if one was, and set.
      def savepoint_set(sent, outcomes, at)
        queued = sent[at]
        "#{SAVEPOINT}_#{queued[1]}" if queued&.first == :savepoint && outcomes[at]&.done
      end

      # The rollback of the requests after the first that failed, each
      # marked skipped.
      def undone(sent, outcomes)
        at = outcomes.index(&:failed)
        none = [] #: Array[String]
        return none unless at

        set = savepoint_set(sent, outcomes, at + 1)
        statements = set ? ["ROLLBACK TO SAVEPOINT #{set}"] : none
        ((at + 1)...outcomes.size).each { |i| outcomes[i] = Piped.skip }
        statements
      end
    end

    # A connection's pipelines [CLIENT Pipelines].
    module Pipelines
      # A pipeline of requests on this connection, empty, on_error
      # :continue.
      #
      # @return [Pipeline]
      def pipeline = Pipeline.new(_ = self)

      private

      # Writes +window+, each a queued request and its frame, at once, and
      # reads its outcomes.
      def piped_window(window)
        send_frame(window.map(&:last).join)
        window.map do |queued, _|
          Piped.of(piped_reply(queued))
        rescue Error => e
          raise if @lost

          Piped.failure(e.failure)
        end
      end

      # The reply of +queued+, a request written.
      def piped_reply(queued)
        kind, subject = queued
        case kind
        when :query, :savepoint then outcome.first
        when :execute
          subject.columns.empty? ? completion_reply : Rows.new(columns: subject.columns, rows: rows_until_end.first)
        else completion_reply
        end
      end

      # Runs +sql+ within the transaction, whatever autocommit says: a
      # statement of a batch's own, which must not end it.
      def within_batch(sql)
        send_frame(Protocol::Requests.query(sql, ends: false))
        outcome
        nil
      end
    end
  end
end
