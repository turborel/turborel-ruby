# frozen_string_literal: true

module Turborel
  # The nodes of an XML value's serialization [CLIENT XML values], as
  # turborel's XmlValue#sequence parses the text the protocol carries: XML
  # content, its whitespace kept, read into elements, their attributes and
  # namespaces, text, comments and processing instructions.
  #
  # The text is what the server serializes: XML 1.0 content with no XML
  # declaration, or, where 1.0 cannot hold it, XML 1.1 after one. A
  # document type declaration, which no serialization holds, is refused.
  module XmlNodes
    # An element: its +name+ as written, its +local_name+ less its prefix,
    # its +namespace+, +nil+ if in none, its +attributes+ in their order,
    # the namespaces it +declared+ by prefix ("" the default one), and its
    # +children+.
    Element = Data.define(:name, :local_name, :namespace, :attributes, :declared, :children)
    # An attribute: its +name+ as written, its +local_name+, its
    # +namespace+, +nil+ unless prefixed, and its +value+, its references
    # replaced and its whitespace normalized.
    Attribute = Data.define(:name, :local_name, :namespace, :value)
    # Character data, CDATA sections among it, joined.
    Text = Data.define(:text)
    # A comment.
    Comment = Data.define(:text)
    # A processing instruction: its +target+ and +data+.
    ProcessingInstruction = Data.define(:target, :data)

    # SQLSTATE 2200N, invalid XML content.
    INVALID_XML_CONTENT = "2200N"
    # The namespace the prefix xml is bound to.
    XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace"
    # The namespace the prefix xmlns is bound to.
    XMLNS_NAMESPACE = "http://www.w3.org/2000/xmlns/"
    # A name's first character [XML 1.0 §2.3, production 4].
    START = "A-Z_a-zÀ-ÖØ-öø-˿Ͱ-ͽͿ-῿‌-‍" \
            "⁰-↏Ⰰ-⿯、-퟿豈-﷏ﷰ-�\u{10000}-\u{EFFFF}"
    # A name [XML 1.0 §2.3, productions 4a and 5].
    NAME = /[#{START}:][#{START}:\-.0-9·̀-ͯ‿-⁀]*/
    # Whitespace [XML 1.0 §2.3, production 3].
    SPACE = /[ \t\n]+/
    # A character no document may hold [XML 1.0 §2.2].
    NOT_CHAR = /[^\t\n -퟿-�\u{10000}-\u{10FFFF}]/
    # The five entities every document knows [XML 1.0 §4.6].
    PREDEFINED = { "lt" => "<", "gt" => ">", "amp" => "&", "apos" => "'", "quot" => '"' }.freeze
    # The start of an XML declaration [XML 1.0 §2.8, production 23].
    DECLARATION = /<\?xml[ \t\n]/
    # The namespaces in scope before any element.
    TOP_SCOPE = { "xml" => XML_NAMESPACE, "xmlns" => XMLNS_NAMESPACE }.freeze

    # An element whose end tag is not yet read.
    Open = Data.define(:name, :attributes, :children, :scope, :declared)

    # The nodes of +text+, XML content, in order, its whitespace kept.
    #
    # @param text [String]
    # @return [Array<Element, Text, Comment, ProcessingInstruction>]
    # @raise [Error] SQLSTATE 2200N if it is not well-formed XML content
    def self.parse(text)
      Parser.new(text.gsub(/\r\n?/, "\n")).content
    end

    # Reads XML content.
    #
    # @api private
    class Parser
      # @param text [String] the content, its line ends normalized
      def initialize(text)
        @text = text
        @at = 0
      end

      # @return [Array] its nodes
      def content
        fail!("a character XML does not take") if NOT_CHAR.match?(@text)
        through("?>", "the XML declaration") if match(DECLARATION)
        top = [] #: Array[XmlNodes::node]
        stack = [] #: Array[Open]
        step(top, stack) while @at < @text.length
        unclosed = stack.last
        fail!("the element #{unclosed.name} is not ended") if unclosed
        top
      end

      private

      # Reads the next piece of content: text, a tag or other markup.
      def step(top, stack)
        parent = stack.last
        into = parent ? parent.children : top
        if !took?("<") then add_text(into, chars)
        elsif took?("/") then end_tag(stack, top)
        elsif !other?(into) then begun(into, stack, parent ? parent.scope : TOP_SCOPE)
        end
      end

      # Reads a start tag: an empty element into +into+, or another onto
      # +stack+.
      def begun(into, stack, scope)
        open, empty = start_tag(name, scope)
        empty ? into << element(open) : stack << open
      end

      # Raises the failure +why+.
      def fail!(why)
        raise Error.of(Error::DATA_EXCEPTION_SQLCODE, INVALID_XML_CONTENT,
                       "the string is not well-formed XML content: #{why} (at #{@at})")
      end

      # Whether the text goes on with +text+, read past it if so.
      def took?(text)
        return false unless @text[@at, text.length] == text

        @at += text.length
        true
      end

      # Reads +text+, or fails.
      def expect(text)
        fail!("#{text.inspect} expected") unless took?(text)
      end

      # The text up to +ending+, read past it.
      def through(ending, what)
        found = @text.index(ending, @at)
        fail!("#{what} not ended") unless found
        read = @text[@at...found] || ""
        @at = found + ending.length
        read
      end

      # What +pattern+ matches here, read; +nil+ if nothing.
      def match(pattern)
        found = pattern.match(@text, @at)
        return nil unless found && found.begin(0) == @at

        @at = found.end(0) || @at
        found[0]
      end

      # A name, or a failure.
      def name = match(NAME) || fail!("a name expected")

      # Whether whitespace was read.
      def spaced? = !match(SPACE).nil?

      # The character data up to the next markup.
      def chars
        ending = @text.index("<", @at) || @text.length
        raw = @text[@at...ending] || ""
        fail!('"]]>" in character data') if raw.include?("]]>")
        @at = ending
        references(raw)
      end

      # +raw+ with its references replaced.
      def references(raw)
        raw.gsub(/&([^;]*);?/) do |whole|
          fail!("a reference not ended") unless whole.end_with?(";")
          reference(Regexp.last_match(1) || "")
        end
      end

      # The text the reference +ref+, between & and ;, stands for.
      def reference(ref)
        known = PREDEFINED[ref]
        return known if known

        code = number(ref) || fail!("the entity &#{ref}; is not declared")
        char = code <= 0x10FFFF && !code.between?(0xD800, 0xDFFF) ? [code].pack("U") : "\u0000"
        fail!("&#{ref}; is no character") if code.zero? || NOT_CHAR.match?(char.tr("\r", "\n"))
        char
      end

      # The code point a character reference names, +nil+ if none.
      def number(ref)
        if (hex = /\A#x(\h+)\z/.match(ref)) then Integer(hex[1] || "", 16)
        elsif (dec = /\A#(\d+)\z/.match(ref)) then Integer(dec[1] || "", 10)
        end
      end

      # An attribute's value, its references replaced and its whitespace
      # normalized.
      def quoted
        quote = if took?('"') then '"'
                elsif took?("'") then "'"
                else fail!("a quoted value expected")
                end
        raw = through(quote, "a value")
        fail!('"<" in an attribute value') if raw.include?("<")
        references(raw.tr("\t\n", "  "))
      end

      # Reads a start tag past its name: the element begun, and whether
      # its tag ended it.
      def start_tag(name, scope)
        attributes = [] #: Array[[String, String]]
        declared = {} #: Hash[String, String]
        loop do
          spaced = spaced?
          return [opened(name, attributes, declared, scope), true] if took?("/>")
          return [opened(name, attributes, declared, scope), false] if took?(">")

          fail!("whitespace expected between attributes") unless spaced
          attribute(attributes, declared)
        end
      end

      # Reads an attribute into +attributes+, a namespace declaration into
      # +declared+ too.
      def attribute(attributes, declared)
        attribute = name
        spaced?
        expect("=")
        spaced?
        value = quoted
        fail!("the attribute #{attribute} is repeated") if attributes.any? { |(other, _)| other == attribute }
        if attribute == "xmlns" then declared[""] = value
        elsif attribute.start_with?("xmlns:") then declared[attribute.delete_prefix("xmlns:")] = value
        end
        attributes << [attribute, value]
      end

      # An element begun.
      def opened(name, attributes, declared, scope)
        Open.new(name:, attributes:, children: [], scope: scope.merge(declared), declared:)
      end

      # The element +open+ makes, its names resolved.
      def element(open)
        attributes = resolved(open)
        local_name, namespace = resolve(open.name, open.scope, attribute: false)
        Element.new(name: open.name, local_name:, namespace:, attributes:, declared: open.declared,
                    children: open.children)
      end

      # The attributes of +open+ but its namespace declarations, their names
      # resolved, none repeated.
      def resolved(open)
        seen = {} #: Hash[[String?, String], bool]
        open.attributes.filter_map do |(name, value)|
          next if name == "xmlns" || name.start_with?("xmlns:")

          local_name, namespace = resolve(name, open.scope, attribute: true)
          fail!("the attribute #{name} is repeated") if seen[[namespace, local_name]]
          seen[[namespace, local_name]] = true
          Attribute.new(name:, local_name:, namespace:, value:)
        end
      end

      # The local name and namespace of +name+ in +scope+: an attribute's
      # takes no default namespace.
      def resolve(name, scope, attribute:)
        prefix, colon, local = name.partition(":")
        return [name, attribute ? nil : default_namespace(scope)] if colon.empty?

        namespace = scope[prefix]
        fail!("the prefix of #{name} is not declared") if namespace.nil? || local.empty? || local.include?(":")
        [local, namespace]
      end

      # The default namespace of +scope+, +nil+ if none or undeclared.
      def default_namespace(scope)
        namespace = scope[""]
        namespace unless namespace.nil? || namespace.empty?
      end

      # Appends +text+ to +into+, joined to text before it.
      def add_text(into, text)
        return if text.empty?

        before = into.last
        if before.is_a?(Text) then into[-1] = Text.new(text: before.text + text)
        else into << Text.new(text:)
        end
      end

      # Reads markup past its < that is not a tag: a comment, CDATA or a
      # processing instruction; whether it was one.
      def other?(into)
        if took?("!--") then comment(into)
        elsif took?("![CDATA[") then add_text(into, through("]]>", "a CDATA section"))
        elsif took?("?") then instruction(into)
        elsif took?("!DOCTYPE") then fail!("a document type declaration in content")
        else return false
        end
        true
      end

      # Reads a comment's text.
      def comment(into)
        text = through("-->", "a comment")
        fail!('"--" in a comment') if text.include?("--") || text.end_with?("-")
        into << Comment.new(text:)
      end

      # Reads a processing instruction.
      def instruction(into)
        target = name
        fail!("an XML declaration only at the start") if target.casecmp?("xml")
        data = if spaced? then through("?>", "a processing instruction")
               else
                 expect("?>")
                 ""
               end
        into << ProcessingInstruction.new(target:, data:)
      end

      # Reads an end tag past its </, ending the element open.
      def end_tag(stack, top)
        name = self.name
        spaced?
        expect(">")
        open = stack.pop
        return fail!("the end tag #{name} matches no start tag") unless open && open.name == name

        (stack.last&.children || top) << element(open)
      end
    end
  end
end
