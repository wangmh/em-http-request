require 'helper'
require 'em-http/middleware/cookie_jar'

describe EventMachine::HttpRequest do

  class EmptyMiddleware; end

  class GlobalMiddleware
    def response(resp)
      resp.response_header['X-Global'] = 'middleware'
    end
  end

  it "should accept middleware" do
    EventMachine.run {
      lambda {
        conn = EM::HttpRequest.new('http://127.0.0.1:8090')
        conn.use ResponseMiddleware
        conn.use EmptyMiddleware

        EM.stop
      }.should_not raise_error
    }
  end

  context "configuration" do
    class ConfigurableMiddleware
      def initialize(conf, &block)
        @conf = conf
        @block = block
      end

      def response(resp)
        resp.response_header['X-Conf'] = @conf
        resp.response_header['X-Block'] = @block.call
      end
    end

    it "should accept middleware initialization parameters" do
      EventMachine.run {
        conn = EM::HttpRequest.new('http://127.0.0.1:8090')
        conn.use ConfigurableMiddleware, 'conf-value' do
          'block-value'
        end

        req = conn.get
        req.callback {
          req.response_header['X-Conf'].should match('conf-value')
          req.response_header['X-Block'].should match('block-value')
          EM.stop
        }
      }
    end
  end

  context "request" do
    class ResponseMiddleware
      def response(resp)
        resp.response_header['X-Header'] = 'middleware'
        resp.response = 'Hello, Middleware!'
      end
    end

    it "should execute response middleware before user callbacks" do
      EventMachine.run {
        conn = EM::HttpRequest.new('http://127.0.0.1:8090')
        conn.use ResponseMiddleware

        req = conn.get
        req.callback {
          req.response_header['X-Header'].should match('middleware')
          req.response.should match('Hello, Middleware!')
          EM.stop
        }
      }
    end

    it "should execute global response middleware before user callbacks" do
      EventMachine.run {
        EM::HttpRequest.use GlobalMiddleware

        conn = EM::HttpRequest.new('http://127.0.0.1:8090')

        req = conn.get
        req.callback {
          req.response_header['X-Global'].should match('middleware')
          EM.stop
        }
      }
    end
  end

  context "request" do
    class RequestMiddleware
      def request(client, head, body)
        head['X-Middleware'] = 'middleware'   # insert new header
        body += ' modified'                   # modify post body

        [head, body]
      end
    end

    it "should execute request middleware before dispatching request" do
      EventMachine.run {
        conn = EventMachine::HttpRequest.new('http://127.0.0.1:8090/')
        conn.use RequestMiddleware

        req = conn.post :body => "data"
        req.callback {
          req.response_header.status.should == 200
          req.response.should match(/data modified/)
          EventMachine.stop
        }
      }
    end
  end

  context "jsonify" do
    class JSONify
      def request(client, head, body)
        [head, Yajl::Encoder.encode(body)]
      end

      def response(resp)
        resp.response = Yajl::Parser.parse(resp.response)
      end
    end

    it "should use middleware to JSON encode and JSON decode the body" do
      EventMachine.run {
        conn = EventMachine::HttpRequest.new('http://127.0.0.1:8090/')
        conn.use JSONify

        req = conn.post :body => {:ruby => :hash}
        req.callback {
          req.response_header.status.should == 200
          req.response.should == {"ruby" => "hash"}
          EventMachine.stop
        }
      }
    end
  end

  context "CookieJar" do
    it "should use the cookie jar as opposed to any other method when in use" do
      lambda {
        EventMachine.run {
          conn = EventMachine::HttpRequest.new('http://127.0.0.1:8090/')
          middleware = EventMachine::Middleware::CookieJar
          conn.use middleware
          middleware.set_cookie('http://127.0.0.1:8090/', 'id=1')
          req = conn.get :head => {'cookie' => 'id=2;'}
          req.callback { failed(req) }
          req.errback  { failed(req) }
        }
      }.should raise_error(ArgumentError)
    end

    it "should send cookies" do
      EventMachine.run {
        uri = 'http://127.0.0.1:8090/cookie_parrot'
        conn = EventMachine::HttpRequest.new(uri)
        middleware = EventMachine::Middleware::CookieJar
        conn.use middleware
        middleware.set_cookie(uri, 'id=1')
        req = conn.get
        req.callback {
          req.response_header.cookie.should == 'id=1'
          EventMachine.stop
        }
      }
    end

    if Http::Parser.respond_to? :default_header_value_type
      it "should store cookies and send them" do
        EventMachine.run {
          uri = 'http://127.0.0.1:8090/set_cookie'
          conn = EventMachine::HttpRequest.new(uri)
          middleware = EventMachine::Middleware::CookieJar
          conn.use middleware
          req = conn.get
          req.callback {
            req.response_header.cookie[0..3].should == 'id=1'
            cookies = middleware.cookiejar.get_cookies(uri)
            cookies.length.should == 1
            cookies[0].to_s.should == "id=1"
            EventMachine.stop
          }
        }
      end
    end
  end

end
