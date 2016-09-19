#!/usr/bin/env ruby

require 'wappalyzer/version'
require 'capybara/dsl'
require 'capybara/poltergeist'

require 'net/http'
require 'v8'
require 'json'

Encoding.default_external = Encoding::UTF_8

module Wappalyzer
  class Detector
    include Capybara::DSL

    def initialize
      @realdir = File.dirname(File.realpath(__FILE__))
      file = File.join(@realdir, 'apps.json')
      @json = JSON.parse(IO.read(file))
      @categories = @json['categories']
      @apps = @json['apps']
      configure_capybara
      configure_driver
    end

    def analyze(url)
      uri = URI(url)
      Capybara.reset_sessions!
      visit url

      data = { 'host' => uri.hostname, 'url' => url,
               'html' => page.html, 'headers' => response_headers }
      output = evaluate_output(data)
      JSON.load(output)
    end

    private

    def context
      @cxt ||= begin
        cxt = V8::Context.new
        cxt.load File.join(@realdir, 'js', 'wappalyzer.js')
        cxt.load File.join(@realdir, 'js', 'driver.js')
        cxt
      end
    end

    def response_headers
      headers = {}
      page.response_headers.each { |k, v| headers[k.downcase] = v }
      headers
    end

    def evaluate_output(data)
      context.eval("w.apps = #{@apps.to_json}; "\
                   "w.categories = #{@categories.to_json};"\
                   "w.driver.data = #{data.to_json};"\
                   'w.driver.init();')
    end

    def user_agent
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.31 (KHTML, like Gecko) '\
      'Chrome/26.0.1410.43 Safari/537.31'
    end

    def configure_capybara
      Capybara.run_server = false
      Capybara.register_driver :poltergeist do |app|
        Capybara::Poltergeist::Driver.new(
          app,
          # Raise JavaScript errors to Ruby
          js_errors: false,
          # Additional command line options for PhantomJS
          phantomjs_options: ['--ignore-ssl-errors=yes', '--ssl-protocol=any']
        )
      end
      Capybara.current_driver = :poltergeist
    end

    def configure_driver
      page.driver.resize(1024, 768)
      page.driver.headers = {
        'User-Agent' => user_agent
      }
    end
  end
end

if $0 == __FILE__
  url = ARGV[0]
  if url
    puts JSON.pretty_generate(Wappalyzer::Detector.new.analyze(ARGV[0]))
  else
    puts "Usage: #{__FILE__} http://example.com"
  end
end
