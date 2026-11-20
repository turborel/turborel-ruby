# frozen_string_literal: true

require "test_helper"

module Turborel
  # The nodes of an XML value's serialization.
  class XmlNodesTest < Minitest::Test
    include TestSupport

    INVALID = [-301, "2200N"].freeze

    def parse(text) = XmlNodes.parse(text)

    # Verifies: [CLIENT XML values] an XML value's nodes parsed from its
    # text: elements, their attributes and namespaces, text with its
    # references replaced and CDATA joined to it, comments and processing
    # instructions, its whitespace kept.
    def test_nodes_of_content
      order, tail = parse(%(<order no="18" xmlns="urn:o" xmlns:a="urn:a" a:b='1'>) +
                          %(<item>jam &amp; &#x41;&#66;</item><!--c--><?pi d?><?e?><![CDATA[<x>]]></order>\r\n))

      assert_equal ["order", "urn:o", { "" => "urn:o", "a" => "urn:a" }],
                   [order.local_name, order.namespace, order.declared]
      assert_equal([["no", nil, "18"], ["b", "urn:a", "1"]],
                   order.attributes.map { [_1.local_name, _1.namespace, _1.value] })
      item, comment, instruction, empty, text = order.children

      assert_equal [XmlNodes::Text.new(text: "jam & AB")], item.children
      assert_equal "urn:o", item.namespace
      assert_equal [XmlNodes::Comment.new(text: "c"), XmlNodes::ProcessingInstruction.new(target: "pi", data: "d")],
                   [comment, instruction]
      assert_equal ["", "<x>", "\n"], [empty.data, text.text, tail.text]
    end

    # Verifies: [CLIENT XML values] a serialization in XML 1.1 begins with
    # its declaration, which is read past; an attribute's whitespace is
    # normalized; the prefix xml is bound; an unprefixed attribute takes
    # no namespace; a default namespace undeclared by "" puts none.
    def test_declaration_attributes_and_namespaces
      a, = parse(%(<?xml version="1.1"?><a xml:lang="en" t="x\ty" xmlns="urn:d"><b xmlns=""/></a>))

      assert_equal([[XmlNodes::XML_NAMESPACE, "en"], [nil, "x y"]], a.attributes.map { [_1.namespace, _1.value] })
      assert_nil a.children.first.namespace
      assert_empty parse("")
    end

    # Verifies: [CLIENT XML values] text that is not well-formed XML
    # content fails with SQLSTATE 2200N.
    def test_ill_formed_content
      ["<a>", "</a>", "<a></b>", "<a b='1' b='2'/>", "<a x:b='1'/>", "<x:a/>", "<a b=1/>", "<a b='<'/>",
       "<a b='1'c='2'/>", "a]]>b", "&nope;", "&#0;", "&#xD800;", "&amp", "<!-- a -- b -->", "<!--a--->",
       "<?xml version='1.0'?><?xml x?>", "<!DOCTYPE a><a/>", "<!--", "<![CDATA[", "<?pi", "\u0001",
       "<a xmlns:p='u' p:b='1' xmlns:q='u' q:b='2'/>", "<", "<a", "<a b>", "<a b='1'"].each do |text|
        assert_fails(INVALID) { parse(text) }
      end
    end

    # Verifies: [CLIENT XML values] Xml#nodes parses its own text.
    def test_an_xml_values_nodes
      assert_equal [XmlNodes::Text.new(text: "t")], Xml.new(text: "t").nodes
    end
  end
end
