module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class BraspagGateway < Gateway
      TEST_URL = 'https://homologacao.pagador.com.br/webservice/pagador.asmx'
      LIVE_URL = 'https://www.pagador.com.br/webservice/pagador.asmx'

      self.supported_countries = ['BR']
      self.supported_cardtypes = [:visa, :master, :american_express]
      self.default_currency = 'BRL'
      self.homepage_url = 'http://www.braspag.com.br'
      self.display_name = 'Braspag'

      # map credit card to the Braspag expected representation
      CREDIT_CARD_CODES = {
        :visa  => 22,
        :master => 23,
        :american_express => 18
      }

      # Creates a new BraspagGateway
      #
      # The gateway requires that a valid login
      # in the +options+ hash.
      #
      # ==== Options
      #
      # * <tt>:login</tt> -- The Braspag Merchant ID (REQUIRED)
      # * <tt>:test</tt> -- +true+ or +false+. If true, perform transactions against the test server.
      # Otherwise, perform transactions against the production server.
      def initialize(options = {})
        requires!(options, :login)
        @options = options
        super
      end

      # Performs an authorization, which reserves the funds on the customer's credit card, but does not
      # charge the card.
      #
      # ==== Parameters
      #
      # * <tt>money</tt> -- The amount to be authorized as an Integer value in cents.
      # * <tt>creditcard</tt> -- The CreditCard details for the transaction.
      #
      # ==== Options
      #
      #   * <tt>:order_id</tt> - A unique reference for this order (REQUIRED).
      def authorize(money, creditcard, options = {})
        post = PostData.new
        add_invoice(post, options)
        add_amount(post, money)
        add_creditcard(post, money, creditcard)
        add_customer_data(post, creditcard)
        add_extra_data(post)

        commit(:authorize, post)
      end

      # Captures the funds from an authorized transaction.
      #
      # ==== Parameters
      # * <tt>money</tt> -- The amount to be captured as an Integer value in cents.
      # * <tt>authorization</tt> - The authorization string returned from the initial authorization
      #
      # ==== Options
      #
      #   * <tt>:order_id</tt> - A unique reference for this order (REQUIRED).
      def capture(money, authorization, options = {})
        if authorization.success?
          post = PostData.new
          add_invoice(post, options)
          commit(:capture, post)
        else
          authorization
        end
      end

      # Perform a purchase, which is essentially an authorization and capture in a single operation.
      #
      # ==== Parameters
      #
      # * <tt>money</tt> -- The amount to be purchased as an Integer value in cents.
      # * <tt>creditcard</tt> -- The CreditCard details for the transaction.
      # * <tt>options</tt> -- A hash of optional parameters.
      def purchase(money, creditcard, options = {})
        capture(money, authorize(money, creditcard, options), options)
      end

      # Void a transaction.
      #
      # ==== Parameters
      # * <tt>authorization</tt> - The authorization string returned from the initial authorization or purchase.
      #
      # ==== Options
      #
      #   * <tt>:order_id</tt> - A unique reference for this order (REQUIRED).
      def void(authorization, options = {})
        if authorization.success?
          requires!(options, :order_id)
          post = PostData.new
          post[:order] = options[:order_id]
          commit(:void_transaction, post)
        else
          authorization
        end
      end

      private

      def add_invoice(post, options)
        requires!(options, :order_id)
        post[:orderId] = options[:order_id]
      end

      def add_amount(post, money)
        post[:amount] = format_amount(money)
      end

      def add_creditcard(post, money, creditcard)
        post[:paymentMethod] = CREDIT_CARD_CODES[card_brand(creditcard).to_sym]
        post[:holder] = creditcard.name
        post[:cardNumber] = creditcard.number
        post[:expiration] = "#{format(creditcard.month, :two_digits)}/#{format(creditcard.year, :two_digits)}"
        post[:securityCode] = creditcard.verification_value
      end

      def add_customer_data(post, creditcard)
        post[:customerName] = creditcard.name
      end

      def add_extra_data(post)
        post[:numberPayments] = 1
        post[:typePayment] = 0
      end

      def test?
        @options[:test] || super
      end

      def commit(action, parameters)
        parameters[:merchantId] = @options[:login]

        response = parse(ssl_post(service_url(action), parameters.to_post_data), action)

        Response.new(success?(response), response[:message], response,
          :authorization => response[:authorisationNumber],
          :order_id => parameters[:orderId]
        )
      end

      def success?(response)
        %w(0 1).include? response[:status]
      end

      # Parse Braspag response xml into a convinient hash
      def parse(xml, action)
        # <?xml version="1.0" encoding="utf-8"?>
        # <PagadorReturn xmlns="https://www.pagador.com.br/webservice/pagador">
        #  <amount>decimal</amount>
        #  <authorisationNumber>string</authorisationNumber>
        #   <message>string</message>
        #   <returnCode>string</returnCode>
        #   <status>unsignedByte</status>
        #   <transactionId>string</transactionId>
        # </PagadorReturn>

        root_element = action == :void_transaction ? "PagadorVoidReturn" : "PagadorReturn"

        response = {}
        xml = REXML::Document.new(xml)
        xml.elements.each("//#{root_element}/*") do |node|
          response[node.name.to_sym] = node.text
        end unless xml.root.nil?

        response
      end

      def service_url(action)
        "#{test? ? TEST_URL : LIVE_URL}/#{action.to_s.classify}"
      end

      def format_amount(amount)
        (amount / 100).to_s.sub ".", ","
      end

    end
  end
end

