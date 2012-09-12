require 'rubygems'
require 'net/http'
require 'uri'
require "rexml/document"
require 'yaml'
require 'open-uri'
require 'cgi'
class AirbreakTracker
  PIVOTAL_URL = 'http://www.pivotaltracker.com/services/v3'
  attr_accessor :errors
  
  def initialize(&args)
    config = YAML.load_file("config.yml")
    @airbreak_project_url = config["config"]["AIRBREAK_PROJECT_URL"]
    @requester = config["config"]["REQUESTER"]
    @airbreak_user_name = config["config"]["AIRBREAK_USERNAME"]
    @airbreak_password = config["config"]["AIRBREAK_PASSWORD"]
  	# @css_file = config["config"]["css_file"]
    @airbreak_error_uri = "/errors.xml?auth_token=#{config["config"]["AIRBREAK_AUTH_TOKEN"]}"
    @pivotal_url = "#{PIVOTAL_URL}/projects/#{config["config"]["PIVOTAL_PROJECT_ID"]}/stories"
    @pivotal_headers = {
            "X-TrackerToken" => config["config"]["PIVOTAL_API_TOKEN"],
            "Accept"         => "application/xml",
            "Content-type"   => "application/xml"
          }
  end
  
  
  def errors
    @errors = []
    #914b74a111fa3ddd7e5f02ef0a499e38
    res = open("http://"+@airbreak_project_url+@airbreak_error_uri)

    result = REXML::Document.new(res)
    result.root.elements.each do |x|
      error_id = x.elements['id'].text
      unless check_existing?(error_id)
        error_title = CGI.escapeHTML "[#{x.elements['rails-env'].text}]Airbreak Error id-#{error_id}}"
        error_description = CGI.escapeHTML "In #{x.elements['controller'].text}/ #{x.elements['action'].text}. /n #{x.elements['error-message'].text} /n check the details at #{@airbreak_project_url}/errors/#{error_id}"
        story = "<story><story_type>bug</story_type><name>#{error_title}</name><requested_by>#{@requester}</requested_by><description>#{error_description}</description></story>"
        @errors << {:id => error_id, :story => story}
      end
    end
    return @errors
  end
  
  def post_errors(errors)
    uri = URI.parse(@pivotal_url)
    errors.each do |e|
      res = Net::HTTP.new(uri.host, uri.port).start do |http|
        http.post(uri.path, e[:story], @pivotal_headers )
      end
      p "======="*5
      p "Entering error id #{e[:id]}..."
      p "======="*5
      p "STORY: #{e[:story]}"
      result =  REXML::Document.new(res.body)
      case res
      when Net::HTTPSuccess,Net::HTTPRedirection
        e[:story_id] = result.root.elements['id'].text
        update_existing(e)
        p "OK. Entered Story id:#{e[:story_id]}"
      else
        res.root.elements.text
      end
    end
  end
  
  def self.recent_errors
    h = AirbreakTracker.new
    e = h.errors
    h.post_errors(e)
  end
  
  private
  
  def check_existing?(e_id)
    errors = YAML.load_file("errors.yml") rescue nil
    return unless errors
    errors[e_id]
  end
  
  def update_existing(error)
    errors = YAML.load_file("errors.yml") || {}
    errors["#{error[:id]}"] = "#{error[:story_id]}"
    File.open("errors.yml", 'w') { |f| YAML.dump(errors, f) }
  end

end

# run

AirbreakTracker.recent_errors