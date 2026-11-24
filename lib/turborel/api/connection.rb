# frozen_string_literal: true

# The driver: its plain API, of connections, results and prepared
# statements (RULES.md D2).
module Turborel
  # Connects as +uri+, a turborel:// URI, and +options+, each a connection
  # setting by its name in Client::Options, say, laid over the URI's, then
  # over the service file's, the environment's and the defaults, as
  # Client::Settings.resolve lays them; or as +uri+, a Client::Settings
  # (RULES.md D2).
  #
  # @param uri [String, Client::Settings, nil]
  # @param options [Hash{Symbol => Object}]
  # @yieldparam name [String] an environment variable's name
  # @yieldreturn [String, nil] its value; ENV's without a block
  # @return [Connection]
  # @raise [Error] SQLSTATE 08001 of settings that cannot be read, or no
  #   server kept; 28000 of a user refused; a connection failure
  def self.connect(uri = nil, **options, &)
    settings = if uri.is_a?(Client::Settings)
                 uri
               else
                 given = Client::Options.new(options.to_h { |key, value| [key.to_s, value.to_s] })
                 Client::Settings.resolve(uri ? given.over(Client::Sources.uri(uri)) : given, &)
               end
    Connection.new(settings.connect)
  end

  # A connection of the plain API, over a Client::Connection (RULES.md D2).
  # As Turborel's, its autocommit is off: a statement begins a transaction
  # that lasts until COMMIT or ROLLBACK.
  class Connection
    # @return [Client::Connection] the low-level connection, for what the
    #   plain API has no place for
    attr_reader :client

    # A connection over +client+.
    #
    # @param client [Client::Connection]
    def initialize(client)
      @client = client
      @prepared = {} #: Hash[String, Client::Statement]
    end

    # Runs +sql+, a statement's text.
    #
    # @param sql [String]
    # @return [Result]
    # @raise [Error] the statement's, as the server reports it
    def exec(sql) = Result.new(client.query(sql))

    # Runs +sql+ with +params+, a value for each of its ? marks, each as
    # Appendix A writes it: prepared, executed and destroyed.
    #
    # @param sql [String]
    # @param params [Array]
    # @return [Result]
    # @raise [Error] the statement's; SQLSTATE 07001 of values short of its
    #   parameters
    def exec_params(sql, params)
      values = params_of(params)
      statement = client.prepare(sql)
      begin
        Result.new(client.execute(statement, values))
      ensure
        client.deallocate(statement) unless client.lost?
      end
    end

    # Prepares +sql+ under +name+, as PREPARE does: a statement prepared
    # under the name before destroyed.
    #
    # @param name [String]
    # @param sql [String]
    # @return [Result] of no rows, its columns those +sql+ will give
    # @raise [Error] the server's: SQLSTATE 42000 of a statement that
    #   cannot be prepared
    def prepare(name, sql)
      statement = client.prepare(sql)
      deallocate(name) if @prepared.key?(name)
      @prepared[name] = statement
      Result.new(Client::Rows.new(columns: statement.columns, rows: []))
    end

    # Executes the statement prepared under +name+ with +params+.
    #
    # @param name [String]
    # @param params [Array]
    # @return [Result]
    # @raise [Error] SQLSTATE 26000 of a name no statement is prepared
    #   under, as EXECUTE gives it; the statement's
    def exec_prepared(name, params = [])
      values = params_of(params)
      Result.new(client.execute(prepared(name), values))
    end

    # Each ? mark of the statement prepared under +name+, in written order:
    # its mode, +:in+, +:inout+ or +:out+, and the ordinal position of the
    # parameter whose argument holds it, a CALL's as the server tells them,
    # another statement's each IN at its place. An OUT one is given no
    # value; its value comes back as a column of the CALL's result.
    #
    # @param name [String]
    # @return [Array<Array(Symbol, Integer)>]
    # @raise [Error] SQLSTATE 26000 of a name no statement is prepared under
    def modes(name) = prepared(name).modes

    # Destroys the statement prepared under +name+, as DEALLOCATE PREPARE
    # does.
    #
    # @param name [String]
    # @return [void]
    # @raise [Error] SQLSTATE 26000 of a name no statement is prepared under
    def deallocate(name)
      client.deallocate(prepared(name))
      @prepared.delete(name)
    end

    # Runs the block in a transaction of its own, committed as it ends and
    # rolled back as it raises, the exception raised again; autocommit off
    # within it, and put back after.
    #
    # @yieldparam connection [Connection]
    # @return [Object] the block's value
    # @raise [Error] SQLSTATE TB910 if a transaction is active already
    def transaction
      raise Error.misused("a transaction is active already") if in_transaction?

      before = autocommit
      client.autocommit = false
      committed = false
      begin
        value = yield self
        client.query("COMMIT")
        committed = true
        value
      ensure
        # Whatever the block raised, it rolls the transaction back and goes
        # on.
        client.query("ROLLBACK") unless committed || client.lost?
        client.autocommit = before
      end
    end

    # @return [Boolean] whether each statement ends its transaction
    def autocommit = client.autocommit

    # @param on [Boolean]
    def autocommit=(on)
      client.autocommit = on
    end

    # @return [Boolean] whether a transaction is active
    def in_transaction? = client.in_transaction?

    # @return [Boolean] whether the connection is closed or lost
    def finished? = client.lost?

    # Ends the session and closes the connection.
    #
    # @return [void]
    def close
      client.terminate unless client.lost?
    end

    # (see #close)
    alias finish close

    # @return [String]
    def inspect = "#<#{self.class.name} #{client.inspect}>"

    private

    # The statement prepared under +name+.
    def prepared(name)
      @prepared.fetch(name) do
        raise Error.of(-921, "26000", "no statement #{name} is prepared")
      end
    end

    # +params+, if an Array.
    def params_of(params)
      raise Error.misused("the parameters' values are not an Array") unless params.is_a?(Array)

      params
    end
  end
end
