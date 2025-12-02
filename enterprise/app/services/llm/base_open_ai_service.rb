require 'net/http'
require 'json'

class Llm::BaseOpenAiService
  # DEFAULT_MODEL = 'gpt-4o-mini'.freeze  # Commented out - Using Gemini instead
  DEFAULT_GEMINI_MODEL = 'gemini-2.0-flash'.freeze
  # OPENAI_PROVIDER = 'openai'.freeze  # Commented out - Using Gemini instead
  GEMINI_PROVIDER = 'gemini'.freeze
  
  attr_reader :client, :model, :provider, :api_key

  def initialize
    @provider = ENV['CAPTAIN_LLM_PROVIDER'].presence || InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value.presence || GEMINI_PROVIDER  # Default to Gemini
    
    case @provider
    # when OPENAI_PROVIDER  # Commented out - Using Gemini instead
    #   initialize_openai
    when GEMINI_PROVIDER
      initialize_gemini
    else
      raise "Unsupported LLM provider: #{@provider}"
    end
  rescue StandardError => e
    raise "Failed to initialize LLM client: #{e.message}"
  end

  private

  # Commented out - Using Gemini instead
  # def initialize_openai
  #   access_token = ENV['CAPTAIN_OPEN_AI_API_KEY'].presence || ENV['OPENAI_API_KEY'].presence || InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value
  #   @client = OpenAI::Client.new(
  #     access_token: access_token,
  #     uri_base: openai_uri_base,
  #     log_errors: Rails.env.development?
  #   )
  #   setup_openai_model
  # end

  def initialize_gemini
    @api_key = ENV['CAPTAIN_GEMINI_API_KEY'].presence || InstallationConfig.find_by!(name: 'CAPTAIN_GEMINI_API_KEY').value
    setup_gemini_model
    @client = GeminiChatClient.new(@api_key, @model)
  end

  # Commented out - Using Gemini instead
  # def openai_uri_base
  #   endpoint = ENV['CAPTAIN_OPEN_AI_ENDPOINT'].presence || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
  #   endpoint.presence || 'https://api.openai.com/'
  # end

  # def setup_openai_model
  #   config_value = ENV['CAPTAIN_OPEN_AI_MODEL'].presence || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
  #   @model = (config_value.presence || DEFAULT_MODEL)
  # end

  def setup_gemini_model
    config_value = ENV['CAPTAIN_GEMINI_MODEL'].presence || InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_MODEL')&.value
    @model = (config_value.presence || DEFAULT_GEMINI_MODEL)  # Updated default
  end
end

# Wrapper class to make Gemini API compatible with OpenAI client interface
class GeminiChatClient
  def initialize(api_key, model)
    @api_key = api_key
    @model = model
  end

  def chat(parameters:)
    messages = parameters[:messages]
    tools = parameters[:tools] || []
    temperature = parameters[:temperature] || 0.7
    
    gemini_messages = convert_messages_to_gemini(messages)
    
    request_body = {
      contents: gemini_messages,
      generationConfig: {
        temperature: temperature,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 8192,
        responseMimeType: 'application/json'
      }
    }

    if tools.any?
      request_body[:tools] = [{
        functionDeclarations: convert_tools_to_gemini(tools)
      }]
    end

    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{@model}:generateContent")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['x-goog-api-key'] = @api_key
    request.body = request_body.to_json

    Rails.logger.info("Gemini API request: #{request_body.to_json}")
    response = http.request(request)
    Rails.logger.info("Gemini API response (#{response.code}): #{response.body}")

    convert_gemini_to_openai_response(JSON.parse(response.body))
  rescue StandardError => e
    Rails.logger.error("Gemini API error: #{e.message}")
    raise e
  end

  private

  def convert_messages_to_gemini(messages)
    gemini_contents = []
    system_content = nil
    
    messages.each do |msg|
      if msg[:role] == 'system'
        system_content = msg[:content]
        next
      end
      
      role = msg[:role] == 'assistant' ? 'model' : 'user'
      content = msg[:content]
      
      # Prepend system message to first user message
      if system_content && role == 'user' && gemini_contents.empty?
        content = "#{system_content}\n\n#{content}"
        system_content = nil
      end

      gemini_contents << {
        role: role,
        parts: [{ text: content.to_s }]
      }
    end

    gemini_contents
  end

  def convert_tools_to_gemini(tools)
    tools.map do |tool|
      {
        name: tool[:function][:name],
        description: tool[:function][:description],
        parameters: tool[:function][:parameters]
      }
    end
  end

  def convert_gemini_to_openai_response(gemini_response)
    if gemini_response['error']
      raise StandardError, "Gemini API error: #{gemini_response['error']['message']}"
    end

    candidate = gemini_response.dig('candidates', 0)
    content = candidate&.dig('content', 'parts', 0)

    if content.nil?
      raise StandardError, 'No content in Gemini response'
    end

    message = if content['functionCall']
                {
                  'tool_calls' => [{
                    'id' => SecureRandom.hex(12),
                    'type' => 'function',
                    'function' => {
                      'name' => content['functionCall']['name'],
                      'arguments' => content['functionCall']['args'].to_json
                    }
                  }]
                }
              else
                { 'content' => content['text'] }
              end

    {
      'choices' => [{
        'message' => message,
        'finish_reason' => 'stop'
      }]
    }
  end
end
